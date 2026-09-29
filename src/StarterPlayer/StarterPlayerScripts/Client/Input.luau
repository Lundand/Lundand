--[[
	Input — attacking, abilities and dropping Cores on PC, touch and gamepad.
	Hold click / the ⚔ button to keep attacking at your weapon's speed.
	Attacks auto-aim at the nearest monster in front of the camera.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)
local FX = require(script.Parent.FX)
local HUD = require(script.Parent.HUD)
local Panels = require(script.Parent.Panels)

local Input = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local held = false
local nextAttack = 0
local abilityReady = 0
local AttackEvent: RemoteEvent
local AbilityEvent: RemoteEvent

local function body(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return nil, nil, nil
	end
	return character, hum, root
end

local function carrying(): boolean
	return player:GetAttribute("CarryTitle") ~= nil
end

local function equipped(slot: string): string
	local data = State.Data
	return data and data.eq and data.eq[slot] or Items.Key(0, slot, 1, 1)
end

-- Nearest living mob within range, preferring the direction the camera faces
local function findTarget(root: BasePart, range: number): BasePart?
	local look = Util.FlatUnit(camera.CFrame.LookVector)
	local best, bestScore = nil, math.huge
	for _, model in CollectionService:GetTagged("Mob") do
		if model:IsA("Model") and not model:GetAttribute("Dead") then
			local mobRoot = model.PrimaryPart
			if mobRoot then
				local to = mobRoot.Position - root.Position
				local dist = Vector3.new(to.X, 0, to.Z).Magnitude
				if dist <= range + mobRoot.Size.Z * 0.5 then
					local facing = Util.FlatUnit(to):Dot(look)
					if facing > -0.2 or dist < 7 then
						local score = dist - facing * 6
						if score < bestScore then
							best, bestScore = mobRoot, score
						end
					end
				end
			end
		end
	end
	return best
end

local function mouseAimPoint(root: BasePart, character: Model): Vector3
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
		if result then
			return result.Position
		end
		return ray.Origin + ray.Direction * 60
	end
	return root.Position + Util.FlatUnit(camera.CFrame.LookVector) * 40
end

local function face(root: BasePart, pos: Vector3)
	local flat = Vector3.new(pos.X, root.Position.Y, pos.Z)
	if (flat - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

local function attack()
	local character, _, root = body()
	if not character or not root or carrying() or character:GetAttribute("Stunned") then
		return
	end
	local now = os.clock()
	if now < nextAttack then
		return
	end
	local style, styleName = Items.Style(equipped("w"))
	nextAttack = now + 1 / style.rate
	local target = findTarget(root, style.range + (style.kind == "melee" and 4 or 0))
	local aimPoint = target and target.Position or mouseAimPoint(root, character)
	face(root, aimPoint)
	local dir = aimPoint - root.Position
	if style.kind == "melee" then
		dir = Util.FlatUnit(dir)
	elseif dir.Magnitude > 0.01 then
		dir = dir.Unit
	else
		dir = Util.FlatUnit(camera.CFrame.LookVector)
	end
	FX.Swing(character, styleName, dir, style.kind == "ranged" and aimPoint or nil)
	UI.Sound(Config.Sounds.Swing, 0.2)
	AttackEvent:FireServer(dir)
end

local function safeGoal(character: Model, root: BasePart, dir: Vector3, dist: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local origin = root.Position + Vector3.new(0, 1, 0)
	local result = workspace:Raycast(origin, dir * dist, params)
	local d = result and math.max(0, (result.Position - origin).Magnitude - 3) or dist
	return root.Position + dir * d
end

local function moveDirection(hum: Humanoid): Vector3
	if hum.MoveDirection.Magnitude > 0.1 then
		return Util.FlatUnit(hum.MoveDirection)
	end
	return Util.FlatUnit(camera.CFrame.LookVector)
end

local function dash(character: Model, hum: Humanoid, root: BasePart, dist: number)
	local dir = moveDirection(hum)
	local start = root.Position
	local goal = safeGoal(character, root, dir, dist)
	local started = os.clock()
	local duration = 0.18
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - started) / duration, 1)
		if not root.Parent then
			conn:Disconnect()
			return
		end
		local pos = start:Lerp(goal, alpha)
		root.CFrame = CFrame.lookAt(Vector3.new(pos.X, root.Position.Y, pos.Z), Vector3.new(pos.X, root.Position.Y, pos.Z) + dir)
		root.AssemblyLinearVelocity = Vector3.new(dir.X * 30, root.AssemblyLinearVelocity.Y, dir.Z * 30)
		if alpha >= 1 then
			conn:Disconnect()
		end
	end)
end

-- Height a character's root should have when standing at `pos`
local function standHeight(character: Model, pos: Vector3, fallback: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character }
	for _, name in { "Mobs", "GroundCores", "ClientFX" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	return result and result.Position.Y + 3.2 or fallback
end

-- Shadow Step: appear behind the target, facing it
local function shadowStep(character: Model, root: BasePart, target: BasePart)
	local behind = target.Position - Util.FlatUnit(target.CFrame.LookVector) * (target.Size.Z * 0.5 + 3.5)
	local y = standHeight(character, behind, root.Position.Y)
	local pos = Vector3.new(behind.X, y, behind.Z)
	root.CFrame = CFrame.lookAt(pos, Vector3.new(target.Position.X, y, target.Position.Z))
	root.AssemblyLinearVelocity = Vector3.zero
end

-- Teleport (warp): jump to the aim point, stopping short of walls
local function warp(character: Model, hum: Humanoid, root: BasePart, aimPoint: Vector3, range: number): Vector3
	local offset = Vector3.new(aimPoint.X - root.Position.X, 0, aimPoint.Z - root.Position.Z)
	if offset.Magnitude < 4 then
		offset = moveDirection(hum) * math.min(range, 30)
	elseif offset.Magnitude > range then
		offset = offset.Unit * range
	end
	local goal = safeGoal(character, root, offset.Unit, offset.Magnitude)
	local y = standHeight(character, goal, root.Position.Y)
	local pos = Vector3.new(goal.X, y, goal.Z)
	root.CFrame = CFrame.lookAt(pos, pos + offset.Unit)
	root.AssemblyLinearVelocity = Vector3.zero
	return pos
end

local function ability()
	local character, hum, root = body()
	if not character or not hum or not root or character:GetAttribute("Stunned") then
		return
	end
	local key = equipped("a")
	local def = Items.Ability(key)
	local now = os.clock()
	if now < abilityReady then
		return
	end
	if Items.MovementAbility[def.kind] and carrying() then
		Notify.Toast("Movement abilities are disabled while carrying a Core!", "error")
		return
	end
	local target = findTarget(root, def.range or 40)
	if def.kind == "shadowstep" and not target then
		Notify.Toast("No enemy close enough to Shadow Step to.", "error")
		return
	end
	local cooldown = Items.AbilityCooldown(key)
	abilityReady = now + cooldown
	HUD.SetCooldown(abilityReady, cooldown)
	local start = root.Position
	local aimPoint = target and target.Position or mouseAimPoint(root, character)
	if def.kind == "dash" then
		dash(character, hum, root, def.dist or 40)
	elseif def.kind == "shadowstep" and target then
		shadowStep(character, root, target)
	elseif def.kind == "warp" then
		aimPoint = warp(character, hum, root, aimPoint, def.range or 60)
	elseif target then
		face(root, target.Position)
	end
	AbilityEvent:FireServer(aimPoint, start)
end

local function drop()
	if carrying() then
		State.Action("drop")
	end
end

local function bindHold(button: TextButton)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = true
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = false
		end
	end)
end

function Input.Init()
	AttackEvent = Net.Event("Attack")
	AbilityEvent = Net.Event("Ability")

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			held = true
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			held = true
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonX then
			ability()
		elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonB then
			drop()
		elseif input.KeyCode == Enum.KeyCode.B then
			Panels.Toggle("base")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			held = false
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
	end)

	local attackButton = HUD.AttackButton
	if attackButton then
		bindHold(attackButton)
	end
	local abilityButton = HUD.AbilityButton
	if abilityButton then
		abilityButton.Activated:Connect(ability)
	end
	local dropButton = HUD.DropButton
	if dropButton then
		dropButton.Activated:Connect(drop)
	end

	State.OnChange(function(data)
		local key = data.eq and data.eq.a
		if key then
			HUD.SetAbilityName(Items.Name(key))
		end
	end)

	RunService.RenderStepped:Connect(function()
		if held and not Panels.IsOpen() then
			attack()
		end
	end)
end

return Input
