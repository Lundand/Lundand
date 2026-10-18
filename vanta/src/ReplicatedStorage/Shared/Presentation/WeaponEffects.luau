--!strict
-- Weapon and hit effects (effects pass): presentation only, played on every client. Nothing here changes damage, timing,
-- positions or hit detection.
--   WeaponEffects.swing(model, clipId)                       -- a swing trail on the held weapon(s) during an attack clip
--   WeaponEffects.impact(target, attacker, amount, heavy)    -- a hit effect chosen by the attacker's weapon, and the target's recoil
--   WeaponEffects.stagger(target, seconds)                   -- dizzy motes over a staggered target
--   WeaponEffects.death(model)                               -- a dissolve as an enemy dies
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local WeaponEffects = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- per weapon type: trail tint and how a hit lands ("slash", "blunt", "pierce")
type Style = { tint: Color3, hit: string, trail: boolean }
local STYLES: { [string]: Style } = {
	Sword = { tint = rgb(225, 232, 245), hit = "slash", trail = true },
	Greatsword = { tint = rgb(225, 232, 245), hit = "slash", trail = true },
	Dagger = { tint = rgb(210, 220, 240), hit = "slash", trail = true },
	Greataxe = { tint = rgb(235, 220, 200), hit = "blunt", trail = true },
	Mace = { tint = rgb(235, 215, 175), hit = "blunt", trail = true },
	Spear = { tint = rgb(215, 232, 255), hit = "pierce", trail = true },
	Fist = { tint = rgb(255, 228, 195), hit = "blunt", trail = true },
	-- ranged and casting weapons: their projectiles already have impacts, so the hit adds only the flash and recoil
	Staff = { tint = rgb(190, 175, 255), hit = "none", trail = false },
	Wand = { tint = rgb(190, 175, 255), hit = "none", trail = false },
	Catalyst = { tint = rgb(190, 175, 255), hit = "none", trail = false },
	Bow = { tint = rgb(230, 220, 200), hit = "none", trail = false },
	Crossbow = { tint = rgb(230, 220, 200), hit = "none", trail = false },
}
-- clips that are not swings (no trail)
local NOT_SWINGS = { "Dodge", "Equip", "Idle", "Cast", "Bow", "HitReact", "Stagger", "Parry", "Brace", "Fortress", "Roar", "Death" }

local function container(): Folder
	local folder = workspace:FindFirstChild("WeaponEffects")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "WeaponEffects"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function anchor(cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Parent = container()
	return part
end

local function emit(host: Instance, count: number, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = host
	e:Emit(count)
end

local function animate(seconds: number, step: (number) -> (), done: (() -> ())?)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min((os.clock() - started) / seconds, 1)
		step(alpha)
		if alpha >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
end

-- Swing trails -------------------------------------------------------------------------------------------------------
-- The held weapon's blade, from its base to its tip: the library's TrailBase/TrailTip attachments when it has them,
-- otherwise measured along the grip's +Y (the convention every weapon model follows).
local function trailFor(weapon: Model, style: Style): Trail?
	local existing = weapon:FindFirstChild("SwingTrail", true)
	if existing ~= nil and existing:IsA("Trail") then
		return existing
	end
	local grip = weapon.PrimaryPart
	if grip == nil then
		return nil
	end
	local base = grip:FindFirstChild("TrailBase")
	local tip = grip:FindFirstChild("TrailTip")
	if base == nil or tip == nil or not base:IsA("Attachment") or not tip:IsA("Attachment") then
		local top = 0
		for _, part in ipairs(weapon:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local localCentre = grip.CFrame:PointToObjectSpace(part.Position)
				top = math.max(top, localCentre.Y + part.Size.Magnitude / 2)
			end
		end
		top = math.max(top, 0.6)
		local b = Instance.new("Attachment")
		b.Name = "SwingBase"
		b.Position = Vector3.new(0, top * 0.4, 0)
		b.Parent = grip
		local t = Instance.new("Attachment")
		t.Name = "SwingTip"
		t.Position = Vector3.new(0, top * 0.95, 0)
		t.Parent = grip
		base, tip = b, t
	end
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base :: Attachment
	trail.Attachment1 = tip :: Attachment
	-- Rare and better weapons (the Rarity attribute Models.applyRarity sets) trail in their rarity colour, a little brighter
	local rarity = weapon:GetAttribute("Rarity")
	local rarityTint = nil
	if rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" then
		local Gear = require(script.Parent.Parent.Config.Gear)
		local c = Gear.rarityColors[rarity]
		rarityTint = Color3.fromRGB(c[1], c[2], c[3])
	end
	trail.Color = ColorSequence.new(rgb(255, 255, 255), rarityTint or style.tint)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if rarityTint then 0.4 else 0.5), NumberSequenceKeypoint.new(0.5, 0.85), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = if rarityTint then 0.4 else 0.15
	trail.LightInfluence = 0.7
	trail.Lifetime = 0.12
	trail.MinLength = 0.05
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = grip
	return trail
end

function WeaponEffects.swing(model: Model, clipId: string)
	for _, word in ipairs(NOT_SWINGS) do
		if string.find(clipId, word, 1, true) then
			return
		end
	end
	local style = STYLES[model:GetAttribute("WeaponType") or ""]
	if style == nil or not style.trail then
		return
	end
	for _, name in ipairs({ "Weapon", "OffhandWeapon" }) do
		local weapon = model:FindFirstChild(name)
		if weapon ~= nil and weapon:IsA("Model") then
			local trail = trailFor(weapon, style)
			if trail ~= nil then
				trail.Enabled = true
				local token = (trail:GetAttribute("Token") or 0) + 1
				trail:SetAttribute("Token", token)
				task.delay(0.55, function()
					if trail.Parent ~= nil and trail:GetAttribute("Token") == token then
						trail.Enabled = false
					end
				end)
			end
		end
	end
end

-- Hit impacts -------------------------------------------------------------------------------------------------------
local function streak(centre: CFrame, length: number, width: number, color: Color3, seconds: number)
	local host = anchor(centre)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(-length / 2, 0, 0)
	a1.Position = Vector3.new(length / 2, 0, 0)
	a0.Parent = host
	a1.Parent = host
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 0.6
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.02
	beam.Width1 = 0.02
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = host
	animate(seconds, function(alpha)
		local w = width * math.sin(alpha * math.pi)
		beam.Width0 = w
		beam.Width1 = w
	end, function()
		host:Destroy()
	end)
end

local function ringOut(position: Vector3, axis: Vector3, radius: number, color: Color3, seconds: number)
	-- a flat ring of camera-facing segments expanding around `axis`
	local host = anchor(CFrame.lookAt(position, position + axis))
	local points = {}
	local count = 20
	for i = 1, count do
		local a = Instance.new("Attachment")
		a.Parent = host
		points[i] = a
	end
	local beams = {}
	for i = 1, count do
		local beam = Instance.new("Beam")
		beam.Attachment0 = points[i]
		beam.Attachment1 = points[i % count + 1]
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = 0.3
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 0.25
		beam.Width1 = 0.25
		beam.Parent = host
		beams[i] = beam
	end
	animate(seconds, function(alpha)
		local r = radius * (0.2 + 0.8 * (1 - (1 - alpha) ^ 3))
		for i, a in ipairs(points) do
			local angle = (i - 1) / count * math.pi * 2
			a.Position = Vector3.new(math.cos(angle) * r, math.sin(angle) * r, 0)
		end
		for _, beam in ipairs(beams) do
			beam.Transparency = NumberSequence.new(alpha)
		end
	end, function()
		host:Destroy()
	end)
end

local function bodyCentre(model: Model): (Vector3, Vector3)
	local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root ~= nil and root:IsA("BasePart") then
		return root.Position, root.Size
	end
	return model:GetPivot().Position, Vector3.new(2, 2, 1)
end

-- a sharp white flash on the struck body (replaces nothing: the existing glow still plays)
local function hitFlash(target: Model, strong: boolean)
	local flash = Instance.new("Highlight")
	flash.FillColor = rgb(255, 255, 255)
	flash.OutlineTransparency = 1
	flash.FillTransparency = if strong then 0.15 else 0.35
	flash.DepthMode = Enum.HighlightDepthMode.Occluded
	flash.Parent = target
	TweenService:Create(flash, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 }):Play()
	Debris:AddItem(flash, 0.16)
end

function WeaponEffects.impact(target: Model, attacker: Model?, amount: number, heavy: boolean)
	local centre, size = bodyCentre(target)
	local from = if attacker ~= nil then bodyCentre(attacker) else centre - Vector3.new(0, 0, 3)
	local toward = Vector3.new(centre.X - from.X, 0, centre.Z - from.Z)
	local push = if toward.Magnitude > 0.05 then toward.Unit else Vector3.zAxis
	local contact = centre - push * math.max(size.Z, 0.8) * 0.5
	local weaponType = attacker and attacker:GetAttribute("WeaponType")
	local style = weaponType and STYLES[weaponType]
	local kind = if style then style.hit elseif attacker ~= nil and attacker:FindFirstChild("LowerTorso") == nil then "claw" else "slash"
	local tint = if style then style.tint else rgb(230, 225, 215)
	hitFlash(target, heavy)
	local host = anchor(CFrame.lookAt(contact, contact - push))
	if kind == "slash" then
		-- a bright cut across the body at a random angle, and metal sparks thrown back towards the attacker
		streak(CFrame.lookAt(contact, contact - push) * CFrame.Angles(0, 0, math.rad(math.random(-60, 60))), if heavy then 4.2 else 3, if heavy then 0.5 else 0.32, tint, 0.16)
		emit(host, if heavy then 14 else 8, {
			Color = ColorSequence.new(rgb(255, 240, 200), rgb(255, 170, 80)), LightEmission = 1, Size = NumberSequence.new(0.12, 0),
			Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(0, -40, 0), Drag = 2, EmissionDirection = Enum.NormalId.Front,
		})
	elseif kind == "blunt" then
		-- a ring punched out of the body along the blow, and a puff of dust
		ringOut(contact, push, if heavy then 3.2 else 2.2, tint, 0.22)
		emit(host, if heavy then 10 else 6, {
			Color = ColorSequence.new(rgb(200, 190, 175)), LightInfluence = 1, Size = NumberSequence.new(0.6, 1.4),
			Transparency = NumberSequence.new(0.45, 1), Lifetime = NumberRange.new(0.3, 0.55), Speed = NumberRange.new(3, 7),
			SpreadAngle = Vector2.new(60, 60), Drag = 4, Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Back,
		})
	elseif kind == "pierce" then
		-- a tight spray straight through the target, along the thrust
		streak(CFrame.lookAt(contact, contact - push) * CFrame.Angles(0, math.rad(90), 0), if heavy then 3.5 else 2.4, 0.2, tint, 0.12)
		emit(host, if heavy then 12 else 8, {
			Color = ColorSequence.new(rgb(255, 245, 220), tint), LightEmission = 0.8, Size = NumberSequence.new(0.14, 0),
			Lifetime = NumberRange.new(0.12, 0.3), Speed = NumberRange.new(14, 24), SpreadAngle = Vector2.new(12, 12),
			Drag = 3, EmissionDirection = Enum.NormalId.Back,
		})
	elseif kind == "claw" then
		-- beasts: three parallel claw marks
		local across = CFrame.lookAt(contact, contact - push) * CFrame.Angles(0, 0, math.rad(55))
		for i = -1, 1 do
			streak(across * CFrame.new(0, i * 0.35, 0), 2.2, 0.16, rgb(235, 225, 215), 0.18)
		end
	end
	-- recoil: a short burst of motes pushed away from the attacker
	emit(host, if heavy then 8 else 4, {
		Color = ColorSequence.new(rgb(255, 255, 255)), LightEmission = 0.6, Size = NumberSequence.new(0.25, 0),
		Transparency = NumberSequence.new(0.3, 1), Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Back,
	})
	Debris:AddItem(host, 0.8)
end

-- Stagger and death ------------------------------------------------------------------------------------------------
function WeaponEffects.stagger(target: Model, seconds: number)
	local head = target:FindFirstChild("Head") or target:FindFirstChild("HumanoidRootPart")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local host = anchor(head.CFrame)
	local points = {}
	for i = 1, 3 do
		local a = Instance.new("Attachment")
		a.Parent = host
		points[i] = a
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(rgb(255, 235, 170))
		e.LightEmission = 0.7
		e.Size = NumberSequence.new(0.22, 0)
		e.Lifetime = NumberRange.new(0.25, 0.35)
		e.Speed = NumberRange.new(0, 0)
		e.Rate = 30
		e.LockedToPart = false
		e.Parent = a
	end
	local started = os.clock()
	animate(math.clamp(seconds, 0.4, 3), function()
		if head.Parent == nil then
			return
		end
		local t = os.clock() - started
		host.CFrame = CFrame.new(head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.6, 0))
		for i, a in ipairs(points) do
			local angle = t * 6 + (i - 1) * math.pi * 2 / 3
			a.Position = Vector3.new(math.cos(angle) * 0.8, math.sin(t * 4 + i) * 0.1, math.sin(angle) * 0.8)
		end
	end, function()
		host:Destroy()
	end)
end

function WeaponEffects.death(model: Model)
	-- the body fades out locally while dark motes rise from it (the server removes the model on its own schedule)
	local parts = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			table.insert(parts, { part = part, from = part.Transparency })
		end
	end
	local centre = bodyCentre(model)
	local host = anchor(CFrame.new(centre))
	local motes = Instance.new("ParticleEmitter")
	motes.Color = ColorSequence.new(rgb(90, 80, 75), rgb(30, 25, 25))
	motes.LightInfluence = 1
	motes.Size = NumberSequence.new(0.5, 0)
	motes.Transparency = NumberSequence.new(0.3, 1)
	motes.Lifetime = NumberRange.new(0.8, 1.3)
	motes.Speed = NumberRange.new(1, 3)
	motes.SpreadAngle = Vector2.new(25, 25)
	motes.Acceleration = Vector3.new(0, 2, 0)
	motes.Rate = 40
	motes.Parent = host
	task.delay(0.6, function()
		animate(1.0, function(alpha)
			for _, entry in ipairs(parts) do
				if entry.part.Parent ~= nil then
					entry.part.LocalTransparencyModifier = alpha
				end
			end
			local now = bodyCentre(model)
			host.Position = now
		end, function()
			motes.Enabled = false
			Debris:AddItem(host, 1.5)
		end)
	end)
end

return WeaponEffects
