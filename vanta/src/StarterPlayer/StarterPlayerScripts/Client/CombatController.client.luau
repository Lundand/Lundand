--!strict
-- Combat controls (L-03, L-06, L-50). Shoulder camera (Client.ShoulderCamera): the character faces where the camera looks, and the centre of the screen is the aim. PC: left click attacks (chains the
-- combo; right after a perfect parry the server turns it into a riposte), F parries, Q dodges, R heavy strike,
-- T crescent sweep. Basic attacks, parries and dodges are predicted: your client plays them at once, with a short
-- lunge and slower walking during the swing, while the server checks and decides every outcome. Heavier
-- techniques are shown when the server confirms them. Gamepad and touch get buttons only while a weapon is in hand.
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local Animator = require(Shared.Presentation.Animator)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local combat = Content.combat
local feel = combat.feel

local ACTIONS = {
	{ name = "Attack", inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }, title = "Attack" },
	{ name = "Parry", inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonL2 }, title = "Parry" },
	{ name = "Dodge", inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonB }, title = "Dodge" },
	{ name = "Heavy", inputs = { Enum.KeyCode.R, Enum.KeyCode.ButtonR1 }, title = "Heavy" },
	{ name = "Sweep", inputs = { Enum.KeyCode.T, Enum.KeyCode.ButtonY }, title = "Sweep" },
}

local state: any = { busyUntil = 0, comboNext = nil, comboUntil = 0, parryReady = 0, dodgeReady = 0, slowToken = nil }
local ABILITY_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
local bound = false
local normalWalkSpeed = 16

local function disciplineFor(character: Model): any
	local weaponType = character:GetAttribute("WeaponType")
	for _, discipline in pairs(combat.disciplines) do
		if discipline.weaponType == weaponType then
			return discipline
		end
	end
	return nil
end

local function slowFor(humanoid: Humanoid, seconds: number)
	local token = {}
	state.slowToken = token
	humanoid.WalkSpeed = feel.attackWalkSpeed
	task.delay(seconds, function()
		if state.slowToken == token and humanoid.Parent ~= nil then
			humanoid.WalkSpeed = normalWalkSpeed
		end
	end)
end

-- Moves the character along the ground for a moment. The character controller cancels plain speed changes almost
-- at once, so a short-lived LinearVelocity carries the movement instead.
local function push(root: BasePart, direction: Vector3, speed: number, seconds: number)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local attachment = root:FindFirstChild("RootAttachment")
	if flat.Magnitude < 0.01 or attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	flat = flat.Unit * speed
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(flat.X, flat.Z)
	mover.MaxForce = 60000
	mover.Parent = root
	Debris:AddItem(mover, seconds)
end

local function dodgeMove(humanoid: Humanoid, root: BasePart)
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector
	end
	push(root, direction, feel.dodgeSpeed, feel.dodgeSeconds)
end

-- Which dodge body animation fits the direction the player is moving (relative to where the character faces). No input
-- backsteps. The name is sent with the dodge request, and the server passes it on to the other clients.
local function dodgeAnimation(humanoid: Humanoid, root: BasePart): string
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then
		return combat.dodge.animation
	end
	local relative = root.CFrame:VectorToObjectSpace(move)
	if math.abs(relative.X) > math.abs(relative.Z) then
		return if relative.X > 0 then "DodgeRight" else "DodgeLeft"
	end
	return if relative.Z < 0 then "DodgeForward" else combat.dodge.animation
end

-- Plays what the server will almost certainly accept, straight away. Returns whether to send the request.
local function predict(actionName: string, character: Model, humanoid: Humanoid, root: BasePart): boolean
	local now = os.clock()
	if now < state.busyUntil then
		return false
	end
	if actionName == "Dodge" then
		local cost = combat.dodge.cost
		if now < state.dodgeReady or (cost ~= nil and (character:GetAttribute("Stamina") or 0) < (cost.stamina or 0)) then
			return false
		end
		state.dodgeReady = now + combat.dodge.cooldown
		state.busyUntil = now + combat.dodge.invulnerable
		state.comboNext = nil
		state.dodgeAnimation = dodgeAnimation(humanoid, root)
		Animator.play(character, state.dodgeAnimation)
		dodgeMove(humanoid, root)
		return true
	end
	local discipline = disciplineFor(character)
	if discipline == nil then
		-- Classes without a weapon discipline (Mage, Heavy Knight): the server shows their basic attack to everyone.
		return actionName == "Attack"
	end
	if actionName == "Parry" then
		if now < state.parryReady then
			return false
		end
		state.parryReady = now + discipline.parry.cooldown
		state.busyUntil = now + discipline.parry.window + discipline.parry.recovery
		state.comboNext = nil
		Animator.play(character, discipline.parry.animation)
		return true
	end
	if actionName == "Attack" then
		local attackId = "Combo1"
		if state.comboNext ~= nil and now <= state.comboUntil then
			attackId = state.comboNext
		end
		local attack = discipline.attacks[attackId]
		state.busyUntil = now + attack.windup + attack.active + attack.recovery
		state.comboNext = attack.next
		state.comboUntil = state.busyUntil + combat.comboResetSeconds
		Animator.play(character, attack.animation)
		push(root, root.CFrame.LookVector, feel.lungeSpeed, feel.lungeSeconds)
		slowFor(humanoid, state.busyUntil - now)
		return true
	end
	-- Heavy Strike and Crescent Sweep: the server checks they're learned and ready, then shows them to everyone.
	state.comboNext = nil
	return true
end

local function handle(actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root: any = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or humanoid == nil or root == nil or humanoid.Health <= 0 then
		return Enum.ContextActionResult.Pass
	end
	if predict(actionName, character, humanoid, root) then
		-- A dodge names its body animation in the slot argument, so everyone else sees the same direction.
		remotes.CombatAction:FireServer(actionName, if actionName == "Dodge" then state.dodgeAnimation else nil, player:GetMouse().Hit.Position)
	end
	return Enum.ContextActionResult.Sink
end

local function bind()
	if bound then
		return
	end
	bound = true
	for _, action in ipairs(ACTIONS) do
		ContextActionService:BindAction(action.name, handle, true, table.unpack(action.inputs))
		ContextActionService:SetTitle(action.name, action.title)
	end
	for slot, key in ipairs(ABILITY_KEYS) do
		ContextActionService:BindAction("Ability" .. slot, function(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
			local dialogue = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Dialogue")
			if inputState ~= Enum.UserInputState.Begin or (dialogue ~= nil and dialogue.Enabled) then
				return Enum.ContextActionResult.Pass
			end
			remotes.CombatAction:FireServer("Ability", slot, player:GetMouse().Hit.Position)
			return Enum.ContextActionResult.Sink
		end, false, key)
	end
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	for _, action in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(action.name)
	end
	for slot in ipairs(ABILITY_KEYS) do
		ContextActionService:UnbindAction("Ability" .. slot)
	end
end

local function watch(character: Model)
	state.busyUntil, state.comboNext, state.slowToken = 0, nil, nil
	local function refresh()
		if character:GetAttribute("WeaponType") ~= nil then
			bind()
		else
			unbind()
		end
	end
	character:GetAttributeChangedSignal("WeaponType"):Connect(refresh)
	refresh()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid ~= nil and humanoid:IsA("Humanoid") then
		normalWalkSpeed = humanoid.WalkSpeed
	end
end

player.CharacterAdded:Connect(watch)

-- When the server confirms an ability with a dash (Lunging Strike), the dash happens here, on the client that moves
-- the character.
remotes.AbilityResult.OnClientEvent:Connect(function(_slot: number, ok: boolean, _detail: any, dash: any, blinkTo: any)
	local character = player.Character
	local root: any = character and character:FindFirstChild("HumanoidRootPart")
	if ok and dash ~= nil and root ~= nil then
		push(root, if dash.backward then -root.CFrame.LookVector else root.CFrame.LookVector, dash.speed, dash.seconds)
	end
	-- Blink: the server chose the spot (kept clear of walls); the client that moves the character goes there.
	if ok and typeof(blinkTo) == "Vector3" and character ~= nil and root ~= nil then
		character:PivotTo(CFrame.new(blinkTo) * root.CFrame.Rotation)
	end
end)
if player.Character ~= nil then
	task.spawn(watch, player.Character)
end
