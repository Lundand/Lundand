--!strict
-- Combat feedback (L-42): readable but unobtrusive. Plays everyone's attack animations, a red glow on enemies
-- winding up (the telegraph to dodge or parry), a brief flash and number on hits, "Parried" and "Dodged" cues,
-- and health bars that appear only when someone is hurt: yours bottom left, enemies' above their heads.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Animator = require(ReplicatedStorage:WaitForChild("Shared").Presentation.Animator)
local SpellEffects = require(ReplicatedStorage:WaitForChild("Shared").Presentation.SpellEffects)
local WeaponEffects = require(ReplicatedStorage:WaitForChild("Shared").Presentation.WeaponEffects)
local Content = require(ReplicatedStorage:WaitForChild("Shared").Content)
local feel = Content.combat.feel
local sounds = Content.combat.sounds
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local RED = Color3.fromRGB(170, 40, 50)
local GOLD = Color3.fromRGB(230, 190, 90)
local PARCHMENT = Color3.fromRGB(240, 232, 210)

local function glow(model: Model, color: Color3, seconds: number)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	task.delay(seconds, function()
		highlight:Destroy()
	end)
end

local function floatingText(model: Model, text: string, color: Color3)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if head == nil then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	billboard.AlwaysOnTop = true
	local adornee: any = head
	billboard.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Text = text
	label.Parent = billboard
	billboard.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(billboard, TweenInfo.new(0.8), { StudsOffset = billboard.StudsOffset + Vector3.new(0, 1.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.8, function()
		billboard:Destroy()
	end)
end

-- Spell effects (placeholders until the effects pass): bolts fly along the aim; bursts and sigils mark the ground
-- during the windup, then erupt.
local VIOLET = Color3.fromRGB(150, 120, 255)

local function effectPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, transparency: number): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Material = Enum.Material.Neon
	part.Color = VIOLET
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = workspace
	return part
end

-- Projectile models from the asset library (ReplicatedStorage.Assets.Projectiles): PrimaryPart "Root" (invisible) at the
-- centre, flying along -Z. Bows and crossbows shoot the Arrow; every other bolt is the ArcaneBolt for now.
local ARROW_WEAPONS = { Bow = true, Crossbow = true }

local function projectileTemplate(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild("Projectiles")
	local template = library and library:FindFirstChild(name)
	return if template ~= nil and template:IsA("Model") and template.PrimaryPart ~= nil then template else nil
end

local function impact(position: Vector3, isArrow: boolean)
	local holder = Instance.new("Part")
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Position = position
	local burst = Instance.new("ParticleEmitter")
	burst.Enabled = false
	burst.Color = ColorSequence.new(if isArrow then Color3.fromRGB(150, 130, 105) else VIOLET)
	burst.LightEmission = if isArrow then 0 else 0.5
	burst.Size = NumberSequence.new(if isArrow then 0.25 else 0.18, 0)
	burst.Transparency = NumberSequence.new(0.2, 1)
	burst.Lifetime = NumberRange.new(0.2, 0.4)
	burst.Speed = NumberRange.new(if isArrow then 3 else 6, if isArrow then 6 else 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Parent = holder
	holder.Parent = workspace
	burst:Emit(if isArrow then 6 else 14)
	Debris:AddItem(holder, 0.6)
end

local function showEffect(extra: any, actor: Model?)
	local windup = extra.windup or 0
	if extra.effect == "Bolt" and typeof(extra.origin) == "Vector3" and typeof(extra.direction) == "Vector3" then
		local isArrow = actor ~= nil and ARROW_WEAPONS[actor:GetAttribute("WeaponType") or ""] == true
		task.delay(windup, function()
			local start = extra.origin + Vector3.new(0, 1.5, 0)
			local range = extra.range or 30
			local seconds = range / (extra.speed or 80)
			local finish = start + extra.direction * range
			-- magic bolts: each family's own projectile and impact (Shared.Presentation.SpellEffects); arrows and unknown bolts below
			if not isArrow and SpellEffects.bolt(extra, actor, start, extra.direction, range, seconds) then
				return
			end
			local template = projectileTemplate(if isArrow then "Arrow" else "ArcaneBolt")
			if template == nil then
				local bolt = effectPart(Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9), CFrame.new(start), 0)
				TweenService:Create(bolt, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Position = finish }):Play()
				Debris:AddItem(bolt, seconds)
				return
			end
			local projectile = (template :: Model):Clone()
			for _, part in ipairs(projectile:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
				end
			end
			local from = CFrame.lookAt(start, finish)
			projectile:PivotTo(from)
			projectile.Parent = workspace
			local began = os.clock()
			local step: RBXScriptConnection
			step = RunService.RenderStepped:Connect(function()
				local alpha = math.min((os.clock() - began) / seconds, 1)
				projectile:PivotTo(from + extra.direction * range * alpha)
				if alpha >= 1 then
					step:Disconnect()
					impact(finish, isArrow)
					projectile:Destroy()
				end
			end)
		end)
	elseif extra.effect == "Burst" or extra.effect == "Sigil" then
		-- area spells: the marked circle, its charge and each ability family's eruption (Shared.Presentation.SpellEffects)
		SpellEffects.play(extra)
	end
end

remotes.CombatEvent.OnClientEvent:Connect(function(actor: Model, animation: string, extra: any)
	if type(extra) == "table" and extra.effect ~= nil then
		showEffect(extra, actor)
	end
	if actor == nil or actor.Parent == nil then
		return
	end
	Animator.play(actor, animation, if type(extra) == "table" then tonumber(extra.windup) else nil)
	if type(extra) == "table" and extra.telegraph then
		glow(actor, RED, tonumber(extra.windup) or 0.5)
	end
end)

-- Sword stance (animation pass): a relaxed idle while a sword is in hand, a guarded combat idle for a few seconds after
-- fighting, and a draw animation when the weapon appears. Driven by the replicated WeaponType attribute and by the
-- clips Animator plays, so every client shows every player's stance.
task.spawn(Animator.preloadAll)
local COMBAT_STANCE_SECONDS = 5
local HEAVY_HIT_FRACTION = 0.2 -- a hit this large (share of max health) staggers instead of flinching
local combatUntil: {[Model]: number} = setmetatable({}, { __mode = "k" }) :: any
local ACTION_CLIPS = {
	SwordCombo1 = true, SwordCombo2 = true, SwordCombo3 = true, SwordHeavy = true, SwordSweep = true,
	SwordParry = true, SwordRiposte = true, Dodge = true, DodgeForward = true, DodgeLeft = true, DodgeRight = true,
	CastBolt = true, CastBoltRaise = true, CastBoltChannel = true, CastLance = true, CastBurst = true, CastSigil = true, CastBuff = true, CastSummon = true, CastBlink = true,
	StaffDodge = true, StaffDodgeForward = true, StaffDodgeLeft = true, StaffDodgeRight = true,
	DaggerSlash = true, DaggerSlashB = true, DaggerCross = true, DaggerFlurry = true, DaggerPlunge = true, DaggerBlink = true, DaggerVeil = true,
	DaggerDance = true, DaggerShadowStrike = true, DaggerCuts = true,
	DaggerDodge = true, DaggerDodgeForward = true, DaggerDodgeLeft = true, DaggerDodgeRight = true,
	BowShot = true, BowShotB = true, BowQuick = true, BowCharge = true, BowBackflip = true, BowRain = true,
	BowDodge = true, BowDodgeForward = true, BowDodgeLeft = true, BowDodgeRight = true,
	MaceSmash = true, MaceSwing = true, MaceBash = true, MaceJudgment = true, MaceBrace = true, MaceCharge = true, MaceFortress = true, MaceRadiant = true,
	MaceConsecrate = true, MaceAscend = true, MaceDodge = true, MaceDodgeForward = true, MaceDodgeLeft = true, MaceDodgeRight = true,
	SpearThrust = true, SpearSweep = true, SpearLeap = true, SpearLunge = true, SpearVault = true, SpearConduct = true, SpearDive = true,
	SpearDodge = true, SpearDodgeForward = true, SpearDodgeLeft = true, SpearDodgeRight = true,
	AxeCleave = true, AxeCleaveSweep = true, AxeCleaveRise = true, AxeRush = true, AxeBreaker = true, AxeRoar = true, AxeSplit = true,
	AxeDodge = true, AxeDodgeForward = true, AxeDodgeLeft = true, AxeDodgeRight = true,
	GreatswordCombo1 = true, GreatswordCombo2 = true, GreatswordCombo3 = true, GreatswordHeavy = true, GreatswordSweep = true, GreatswordParry = true,
	GreatswordRiposte = true, GreatswordDodge = true, GreatswordDodgeForward = true, GreatswordDodgeLeft = true, GreatswordDodgeRight = true,
	FistJab = true, FistCross = true, FistHook = true, FistUpper = true, FistHaymaker = true, FistKick = true, FistCounter = true, FistPound = true,
	FistDodge = true, FistDodgeForward = true, FistDodgeLeft = true, FistDodgeRight = true,
}
-- Per weapon type: the calm and combat stances, and the draw and sheathe clips.
local STANCES = {
	Sword = { calm = "SwordIdle", combat = "SwordCombatIdle", equip = "SwordEquip", unequip = "SwordUnequip" },
	Staff = { calm = "StaffIdle", combat = "StaffCombatIdle", equip = "StaffEquip", unequip = "StaffUnequip" },
	Dagger = { calm = "DaggerIdle", combat = "DaggerCombatIdle", equip = "DaggerEquip", unequip = "DaggerUnequip" },
	Bow = { calm = "BowIdle", combat = "BowCombatIdle", equip = "BowEquip", unequip = "BowUnequip" },
	Fist = { calm = "FistIdle", combat = "FistCombatIdle", equip = "FistEquip", unequip = "FistUnequip" },
	Mace = { calm = "MaceIdle", combat = "MaceCombatIdle", equip = "MaceEquip", unequip = "MaceUnequip" },
	Greatsword = { calm = "GreatswordIdle", combat = "GreatswordCombatIdle", equip = "GreatswordEquip", unequip = "GreatswordUnequip" },
	Greataxe = { calm = "AxeIdle", combat = "AxeCombatIdle", equip = "AxeEquip", unequip = "AxeUnequip" },
	Spear = { calm = "SpearIdle", combat = "SpearCombatIdle", equip = "SpearEquip", unequip = "SpearUnequip" },
}

local function refreshStance(character: Model)
	if character.Parent == nil then
		return
	end
	local stances = STANCES[character:GetAttribute("WeaponType")]
	if stances == nil then
		Animator.setStance(character, nil)
		return
	end
	local remaining = (combatUntil[character] or 0) - os.clock()
	if remaining > 0 then
		Animator.setStance(character, stances.combat)
		task.delay(remaining + 0.05, refreshStance, character)
	else
		Animator.setStance(character, stances.calm)
	end
end

local function markCombat(character: Model?)
	if character == nil or character:GetAttribute("WeaponType") == nil then
		return
	end
	local wasIdle = os.clock() >= (combatUntil[character] or 0)
	combatUntil[character] = os.clock() + COMBAT_STANCE_SECONDS
	if wasIdle then
		refreshStance(character)
	end
end

Animator.played:Connect(function(model: Model, animationId: string)
	if ACTION_CLIPS[animationId] then
		markCombat(model)
	end
	-- effects pass: a swing trail on the held weapon during attack clips, dizzy motes over anyone who staggers
	WeaponEffects.swing(model, animationId)
	if animationId == "Stagger" then
		WeaponEffects.stagger(model, 1)
	end
end)

local function watchCharacter(character: Model)
	local last = character:GetAttribute("WeaponType")
	refreshStance(character)
	character:GetAttributeChangedSignal("WeaponType"):Connect(function()
		local now = character:GetAttribute("WeaponType")
		if now ~= last then
			if STANCES[now] ~= nil then
				Animator.play(character, STANCES[now].equip)
			elseif now == nil and STANCES[last] ~= nil then
				Animator.play(character, STANCES[last].unequip)
			end
		end
		last = now
		refreshStance(character)
	end)
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character ~= nil then
		task.spawn(watchCharacter, other.Character)
	end
end
for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(watchPlayer)

-- Bow arrows: during a bow clip an arrow sits nocked on the string, in the drawing hand, and vanishes at each release marker
-- (the bolt effect takes over); Rain of Arrows brings it back between volleys. Follows the bow, so it points where the bow does.
local BOW_CLIPS = { BowShot = true, BowShotB = true, BowQuick = true, BowCharge = true, BowBackflip = true, BowRain = true }

local function buildArrow(): Model
	-- the library arrow (same model the shot flies as), without its trail; the part-built arrow below is the fallback
	local template = projectileTemplate("Arrow")
	if template ~= nil then
		local copy = (template :: Model):Clone()
		copy.Name = "NockedArrow"
		for _, item in ipairs(copy:GetDescendants()) do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanQuery = false
				item.CanTouch = false
				item.CastShadow = false
				item:SetAttribute("ShownTransparency", item.Transparency)
			elseif item:IsA("Trail") or item:IsA("ParticleEmitter") or item:IsA("Light") then
				item.Enabled = false
			end
		end
		return copy
	end
	local model = Instance.new("Model")
	model.Name = "NockedArrow"
	local function part(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		return p
	end
	local shaft = part("Shaft", Vector3.new(0.1, 0.1, 2.6), Color3.fromRGB(170, 135, 90), Enum.Material.Wood)
	part("Tip", Vector3.new(0.2, 0.2, 0.45), Color3.fromRGB(190, 195, 205), Enum.Material.Metal)
	part("Fletching", Vector3.new(0.3, 0.02, 0.5), Color3.fromRGB(230, 225, 210), Enum.Material.SmoothPlastic)
	model.PrimaryPart = shaft
	return model
end

local function placeArrow(arrow: Model, origin: Vector3, direction: Vector3)
	local center = origin + direction * 1.0
	local frame = CFrame.lookAt(center, center + direction) -- forward (the way the arrow flies) is -Z of this frame
	if arrow:FindFirstChild("Shaft") == nil then
		arrow:PivotTo(frame) -- library arrow: Root at its centre, flying along -Z
		return
	end
	local shaft = arrow:FindFirstChild("Shaft") :: BasePart
	local tip = arrow:FindFirstChild("Tip") :: BasePart
	local fletching = arrow:FindFirstChild("Fletching") :: BasePart
	shaft.CFrame = frame
	tip.CFrame = frame * CFrame.new(0, 0, -1.3)
	fletching.CFrame = frame * CFrame.new(0, 0, 1.15)
end

local function nockArrow(character: Model, clipId: string)
	local hand = character:FindFirstChild("RightHand")
	local bow = character:FindFirstChild("Weapon")
	if hand == nil or bow == nil or not hand:IsA("BasePart") or not bow:IsA("Model") or bow.PrimaryPart == nil then
		return
	end
	local arrow = buildArrow()
	placeArrow(arrow, (hand :: BasePart).Position, (bow.PrimaryPart :: BasePart).CFrame.ZVector) -- in place before its first frame
	arrow.Parent = workspace
	local hiddenUntil = 0
	local marker = Animator.onMarker(character, clipId, "Hit", function()
		hiddenUntil = os.clock() + 0.18
	end)
	local step: RBXScriptConnection
	step = RunService.RenderStepped:Connect(function()
		if not Animator.isPlaying(character, clipId) or hand.Parent == nil or bow.Parent == nil or arrow.Parent == nil then
			step:Disconnect()
			if marker ~= nil then
				marker:Disconnect()
			end
			arrow:Destroy()
			return
		end
		local visible = os.clock() >= hiddenUntil
		for _, part in ipairs(arrow:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = if visible then (part:GetAttribute("ShownTransparency") or 0) else 1
			end
		end
		local primary = bow.PrimaryPart :: BasePart
		placeArrow(arrow, (hand :: BasePart).Position, primary.CFrame.ZVector)
	end)
end

Animator.played:Connect(function(model: Model, animationId: string)
	if BOW_CLIPS[animationId] and model:GetAttribute("WeaponType") == "Bow" then
		nockArrow(model, animationId)
	end
end)

-- Flinch, stagger and (enemy) parry stagger: only for R15 bodies, which the clips are authored for.
local function isR15(model: Model?): boolean
	return model ~= nil and model.Parent ~= nil and model:FindFirstChild("LowerTorso") ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function react(target: Model, amount: number, delaySeconds: number)
	task.delay(delaySeconds, function()
		if not isR15(target) then
			return
		end
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local heavy = humanoid ~= nil and humanoid.Health > 0 and amount >= humanoid.MaxHealth * HEAVY_HIT_FRACTION
		if heavy then
			Animator.play(target, "HitReactHeavy")
		elseif not Animator.busy(target) then
			Animator.play(target, "HitReactLight")
		end
	end)
end

-- Impact: a short camera shake (tiny when you land a hit, stronger when you take one), hit sparks and sounds.
local shakeUntil, shakeStrength = 0, 0
RunService:BindToRenderStep("CombatShake", Enum.RenderPriority.Camera.Value + 1, function()
	local now = os.clock()
	if now < shakeUntil then
		local amount = shakeStrength * (shakeUntil - now) / feel.shakeSeconds
		local camera = workspace.CurrentCamera
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
	end
end)

local function shake(strength: number)
	shakeUntil = os.clock() + feel.shakeSeconds
	shakeStrength = strength
end

local function spark(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 0.5, 0)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 190))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(14, 22)
	emitter.Lifetime = NumberRange.new(0.12, 0.25)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(14)
	Debris:AddItem(attachment, 0.5)
end

local function playSound(id: number?, parent: Instance?)
	if (id or 0) <= 0 or parent == nil then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.PlaybackSpeed = 0.92 + math.random() * 0.16
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

remotes.CombatHit.OnClientEvent:Connect(function(target: Model, amount: number, result: string, attacker: Model?)
	if target == nil or target.Parent == nil then
		return
	end
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if result == "Parried" then
		if attacker ~= nil and isR15(attacker) then
			Animator.play(attacker, "Stagger") -- the enemy whose strike was parried reels
		end
		glow(target, GOLD, 0.25)
		floatingText(target, "Parried", GOLD)
		playSound(sounds.parry, targetRoot)
	elseif result == "Dodged" then
		floatingText(target, "Dodged", PARCHMENT)
		playSound(sounds.dodge, targetRoot)
	elseif result == "Healed" then
		floatingText(target, "+" .. tostring(amount), Color3.fromRGB(120, 220, 140))
	else
		glow(target, PARCHMENT, 0.12)
		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		WeaponEffects.impact(target, attacker, amount, targetHumanoid ~= nil and amount >= targetHumanoid.MaxHealth * HEAVY_HIT_FRACTION)
		markCombat(target)
		markCombat(attacker)
		react(target, amount, if attacker ~= nil and attacker == player.Character then feel.hitstopSeconds else 0)
		floatingText(target, tostring(amount), target == player.Character and RED or PARCHMENT)
		playSound(sounds.hit, targetRoot)
		if attacker ~= nil and attacker == player.Character then
			Animator.freeze(attacker, feel.hitstopSeconds)
			Animator.freeze(target, feel.hitstopSeconds)
			spark(target)
			shake(feel.shakeDealt)
		elseif target == player.Character then
			shake(feel.shakeTaken)
		end
	end
end)

-- Your own health is on the HUD. Enemies get a nameplate in the HUD's steel style: name and level over a small
-- steel-framed crimson bar, shown while you are near or the enemy is hurt (elites and bosses marked in gold).
local NameplateContent = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
local NameplateUi = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Presentation.Ui)
local NEAR = 30
local plates: {[Model]: any} = {}
local STEEL = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(213, 220, 230)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(140, 150, 167)), ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 48, 59)) })
local CRIMSON = ColorSequence.new(Color3.fromRGB(226, 98, 120), Color3.fromRGB(120, 16, 40))

local function trackEnemy(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local humanoid = model:WaitForChild("Humanoid", 10)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or not humanoid:IsA("Humanoid") or head == nil then
		return
	end
	-- effects pass: enemies dissolve as they die
	humanoid.Died:Connect(function()
		WeaponEffects.death(model)
	end)
	local def = NameplateContent.enemies[model:GetAttribute("EnemyId") or ""]
	local special = def ~= nil and (def.boss or def.elite or def.archetypeRank == "Elite")
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(170, 36)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	local adornee: any = head
	billboard.Adornee = adornee
	billboard.Enabled = false
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.FontFace = NameplateUi.fonts.labelBold
	name.TextSize = 13
	name.TextColor3 = if special then Color3.fromRGB(240, 205, 120) else Color3.fromRGB(236, 240, 246)
	name.TextStrokeTransparency = 0.45
	name.Size = UDim2.new(1, 0, 0, 16)
	local level = model:GetAttribute("Level") or (def and def.level)
	name.Text = (if special then "◆ " else "") .. (if def then def.displayName else model.Name) .. (if level then "  ·  Lv " .. tostring(level) else "")
	name.Parent = billboard
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 20)
	frame.Size = UDim2.fromOffset(124, 10)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	local steel = Instance.new("UIGradient")
	steel.Color = STEEL
	steel.Rotation = 90
	steel.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(17, 20, 26)
	edge.Thickness = 1.5
	edge.Parent = frame
	local recess = Instance.new("Frame")
	recess.BorderSizePixel = 0
	recess.Position = UDim2.fromOffset(2, 2)
	recess.Size = UDim2.new(1, -4, 1, -4)
	recess.BackgroundColor3 = Color3.fromRGB(11, 14, 20)
	recess.ClipsDescendants = true
	recess.Parent = frame
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.new(1, 0, 1, 0)
	local crimson = Instance.new("UIGradient")
	crimson.Color = CRIMSON
	crimson.Rotation = 90
	crimson.Parent = fill
	fill.Parent = recess
	frame.Parent = billboard
	billboard.Parent = model
	plates[model] = { billboard = billboard, humanoid = humanoid, root = head, fill = fill, name = name, def = def, special = special }
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			plates[model] = nil
		end
	end)
end

-- one light loop for every plate: near or hurt, and alive
task.spawn(function()
	while true do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- only the single nearest living enemy gets a plate for being near; hurt enemies always show theirs
		local nearestModel, nearestDistance = nil, NEAR
		if root ~= nil then
			for model, plate in pairs(plates) do
				if plate.humanoid.Health > 0 and plate.root.Parent ~= nil then
					local distance = (plate.root.Position - root.Position).Magnitude
					if distance <= nearestDistance then
						nearestModel, nearestDistance = model, distance
					end
				end
			end
		end
		for model, plate in pairs(plates) do
			local humanoid = plate.humanoid
			local fraction = math.max(0, math.min(1, humanoid.Health / math.max(1, humanoid.MaxHealth)))
			plate.fill.Size = UDim2.new(fraction, 0, 1, 0)
			plate.billboard.Enabled = humanoid.Health > 0 and (model == nearestModel or fraction < 1)
			local level = model:GetAttribute("Level")
			if level ~= nil and plate.def ~= nil then
				plate.name.Text = (if plate.special then "◆ " else "") .. plate.def.displayName .. "  ·  Lv " .. tostring(level)
			end
		end
		task.wait(0.15)
	end
end)

local enemies = workspace:WaitForChild("Enemies", 30)
if enemies ~= nil then
	enemies.ChildAdded:Connect(trackEnemy)
	for _, model in ipairs(enemies:GetChildren()) do
		task.spawn(trackEnemy, model)
	end
end
