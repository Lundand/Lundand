--[[
	FX — every visual effect, built from temporary client-side parts:
	damage numbers, per-weapon slashes and hit sparks, arrows, ability effects, boss slam telegraphs,
	mob death bursts, Core drop beams, reward popups and camera shake.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent.UI)
local Anim = require(script.Parent.Anim)

local FX = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local folder: Folder
local rng = Random.new()
local numbers = 0
local shakeUntil, shakeAmp = 0, 0
local UP = CFrame.Angles(0, 0, math.pi / 2)

local function tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function part(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function near(pos: Vector3, dist: number): boolean
	return (camera.CFrame.Position - pos).Magnitude < dist
end

function FX.Shake(amp: number, duration: number)
	shakeAmp = math.max(amp, os.clock() < shakeUntil and shakeAmp or 0)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

-- Expanding, fading ball
function FX.Burst(pos: Vector3, color: Color3, diameter: number, time: number)
	local p = part(Vector3.one * diameter * 0.25, CFrame.new(pos), color, Enum.PartType.Ball)
	p.Transparency = 0.15
	tween(p, time, { Size = Vector3.one * diameter, Transparency = 1 })
	task.delay(time, function()
		p:Destroy()
	end)
end

-- Expanding flat ring on the ground
function FX.Ring(pos: Vector3, color: Color3, radius: number, time: number)
	local p = part(Vector3.new(0.3, radius * 0.4, radius * 0.4), CFrame.new(pos + Vector3.new(0, 0.2, 0)) * UP, color, Enum.PartType.Cylinder)
	p.Transparency = 0.3
	tween(p, time, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 })
	task.delay(time, function()
		p:Destroy()
	end)
end

function FX.Popup(pos: Vector3, text: string, color: Color3, big: boolean)
	if numbers > 45 or not near(pos, 140) then
		return
	end
	numbers += 1
	local att = Instance.new("Attachment")
	att.Parent = workspace.Terrain
	att.Position = pos + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(0, 1), rng:NextNumber(-1.2, 1.2))
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(big and 150 or 110, big and 52 or 38)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 150
	bb.Adornee = att
	bb.Parent = att
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = big and 1.6 or 1.2
	scale.Parent = label
	tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(bb, 0.9, { StudsOffset = Vector3.new(0, 3.5, 0) })
	task.delay(0.45, function()
		tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	task.delay(0.95, function()
		att:Destroy()
		numbers -= 1
	end)
end

--------------------------------------------------------------------------------
-- Attacks
--------------------------------------------------------------------------------
local function handPos(character: Model): Vector3
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position or Vector3.zero
end

-- Where a shot leaves the weapon: the staff's orb, the bow's grip, else the hand
local function muzzlePos(character: Model, style: string): Vector3
	local weapon = character:FindFirstChild("EquippedWeapon")
	if weapon then
		local tip = style == "staff" and weapon:FindFirstChild("Orb", true) or weapon:FindFirstChild("Handle")
		if tip and tip:IsA("BasePart") and tip.Transparency < 1 then
			return tip.Position
		end
	end
	return handPos(character)
end

-- Ground height under a character (where its feet are)
local function groundBelow(character: Model, root: BasePart): Vector3
	local hum = character:FindFirstChildOfClass("Humanoid")
	local legs = hum and (hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight) or 2
	return root.Position - Vector3.new(0, root.Size.Y / 2 + legs, 0)
end

--[[
	A crescent of neon segments on the circle (radius r) in the X/-Z plane of `frame` (angle 0 = frame's right,
	90° = its look direction), from angle a0 to a1 (degrees). Segments light up one after another over `sweep`
	seconds (following the blade), then each fades over `life` while drifting outward.
]]
local function arc(frame: CFrame, r: number, a0: number, a1: number, n: number, thick: number, width: number, color: Color3, sweep: number, life: number)
	local segs: { Part } = {}
	local bases: { CFrame } = {}
	for i = 0, n - 1 do
		local u, v = math.rad(a0 + (a1 - a0) * i / n), math.rad(a0 + (a1 - a0) * (i + 1) / n)
		local p0 = frame * Vector3.new(math.cos(u) * r, 0, -math.sin(u) * r)
		local p1 = frame * Vector3.new(math.cos(v) * r, 0, -math.sin(v) * r)
		local shape = math.sin(math.pi * (i + 0.5) / n) -- thin at both ends
		local seg = part(Vector3.new(thick * (0.35 + 0.65 * shape), width * (0.3 + 0.7 * shape), (p1 - p0).Magnitude + 0.08), CFrame.lookAt((p0 + p1) / 2, p1, frame.UpVector), color)
		seg.Transparency = 1
		segs[i + 1] = seg
		bases[i + 1] = seg.CFrame
	end
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - started
		local alive = false
		for i, seg in segs do
			local t = age - sweep * (i - 1) / n
			if t < 0 then
				alive = true
			elseif t < life then
				alive = true
				local k = t / life
				seg.Transparency = 0.15 + 0.85 * k * k
				local out = (bases[i].Position - frame.Position)
				seg.CFrame = bases[i] + (out.Magnitude > 0.01 and out.Unit * k * r * 0.18 or Vector3.zero)
			elseif seg.Parent then
				seg:Destroy()
			end
		end
		if not alive then
			conn:Disconnect()
			for _, seg in segs do
				seg:Destroy()
			end
		end
	end)
end

-- Straight streak that shoots out from `from` along `dir` and fades (thrusts, stabs)
local function streak(from: Vector3, dir: Vector3, length: number, thick: number, color: Color3, time: number)
	local p = part(Vector3.new(thick, thick, 0.2), CFrame.lookAt(from, from + dir), color)
	p.Transparency = 0.1
	tween(p, time * 0.45, { Size = Vector3.new(thick, thick, length), CFrame = CFrame.lookAt(from + dir * length / 2, from + dir * length) })
	task.delay(time * 0.35, function()
		tween(p, time * 0.65, { Transparency = 1, Size = Vector3.new(thick * 0.3, thick * 0.3, length) })
	end)
	task.delay(time, function()
		p:Destroy()
	end)
end

-- Small hit spark: a flash and a few shards flying off the surface facing the attacker
local function spark(pos: Vector3, normal: Vector3, color: Color3)
	FX.Burst(pos, Color3.new(1, 1, 1), 2.4, 0.16)
	for _ = 1, 5 do
		local dir = (normal + Vector3.new(rng:NextNumber(-0.9, 0.9), rng:NextNumber(-0.4, 1), rng:NextNumber(-0.9, 0.9))).Unit
		local shard = part(Vector3.new(0.14, 0.14, 0.7), CFrame.lookAt(pos, pos + dir), color)
		tween(shard, 0.22, { CFrame = CFrame.lookAt(pos + dir * 2.2, pos + dir * 3), Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.3) })
		task.delay(0.22, function()
			shard:Destroy()
		end)
	end
end

-- Sparks on the monsters a melee swing reaches (a client-side guess of what the server hits)
local function sparkTargets(root: BasePart, dir: Vector3, style: string, color: Color3)
	local cfg = Config.WeaponStyles[style] or Config.WeaponStyles.sword
	local cosHalf = math.cos(math.rad((cfg.arc or 120) / 2))
	local found = 0
	for _, model in CollectionService:GetTagged("Mob") do
		local mobRoot = model:IsA("Model") and model.PrimaryPart
		if mobRoot and not model:GetAttribute("Dead") then
			local to = mobRoot.Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude <= (cfg.range or 10) + mobRoot.Size.Z * 0.5 and ((cfg.arc or 120) >= 360 or flat.Magnitude < 3 or Util.FlatUnit(to):Dot(dir) >= cosHalf) then
				local normal = Util.FlatUnit(-to)
				spark(mobRoot.Position + normal * math.min(mobRoot.Size.X, mobRoot.Size.Z) * 0.45 + Vector3.new(0, mobRoot.Size.Y * 0.15, 0), normal, color)
				found += 1
				if found >= 3 then
					return
				end
			end
		end
	end
end

-- Slash visuals for each weapon style, shaped like the motion (Anim / Poses): called when the weapon connects
function FX.Slash(character: Model, dir: Vector3, style: string, color: Color3, alt: boolean?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not near(root.Position, 160) then
		return
	end
	local cfg = Config.WeaponStyles[style] or Config.WeaponStyles.sword
	local range = cfg.range or 10
	local flat = Util.FlatUnit(dir)
	local chest = root.Position + Vector3.new(0, 0.5, 0)
	local facing = CFrame.lookAt(chest, chest + flat) -- look = attack direction
	local white = color:Lerp(Color3.new(1, 1, 1), 0.6)
	if style == "katana" then
		-- two crisp, wide horizontal cuts
		local f = facing * CFrame.Angles(0, 0, math.rad(-8))
		arc(f, range * 0.55, -15, 195, 12, 0.14, 0.9, color, 0.07, 0.2)
		arc(f * CFrame.new(0, 0.25, 0), range * 0.48, -5, 185, 12, 0.08, 0.35, white, 0.06, 0.16)
	elseif style == "greatsword" or style == "hammer" then
		-- overhead arc down to the ground in front, then an impact on the ground
		local heavy = style == "hammer"
		arc(facing * CFrame.Angles(0, 0, math.pi / 2), heavy and range * 0.4 or range * 0.5, 15, 160, 10, heavy and 0.7 or 0.5, heavy and 1.6 or 1.3, color, 0.08, 0.26)
		local ground = groundBelow(character, root)
		local impact = ground + flat * (heavy and 4 or 5)
		FX.Burst(impact + Vector3.new(0, 0.6, 0), white, heavy and 5 or 3.5, 0.25)
		FX.Ring(impact, color, heavy and 6 or 4.5, 0.35)
		if heavy then
			-- shockwave around the whole body (the hammer hits all around)
			FX.Ring(ground, white, range, 0.45)
			FX.Ring(ground, color, range * 0.7, 0.3)
			for _ = 1, 6 do
				local d = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
				local rock = part(Vector3.one * rng:NextNumber(0.35, 0.7), CFrame.new(impact) * CFrame.Angles(rng:NextNumber() * 6, rng:NextNumber() * 6, 0), Color3.fromRGB(120, 105, 90), nil, Enum.Material.Slate)
				tween(rock, 0.5, { CFrame = rock.CFrame + d * rng:NextNumber(2, 4) + Vector3.new(0, rng:NextNumber(1.5, 3), 0), Transparency = 1 })
				task.delay(0.5, function()
					rock:Destroy()
				end)
			end
		end
		local dist = (camera.CFrame.Position - impact).Magnitude
		local reach = heavy and 55 or 40
		if dist < reach then
			FX.Shake((heavy and 0.6 or 0.3) * (1 - dist / reach), heavy and 0.3 or 0.2)
		end
	elseif style == "scythe" then
		-- a full circle around the body, sweeping along with the spin (FX.Swing starts it when the spin starts)
		arc(facing * CFrame.new(0, -0.3, 0), range * 0.6, -40, 320, 18, 0.35, 1.2, color, 0.4, 0.22)
	elseif style == "daggers" then
		-- quick stab on the side of the striking hand, with a small cross cut at the tip
		local side = facing.RightVector * (alt and -0.7 or 0.7)
		local from = chest + side + flat * 1.2
		streak(from, (flat * range - side).Unit, range * 0.75, 0.22, white, 0.18)
		local tip = from + flat * range * 0.7
		local x = CFrame.lookAt(tip, tip + flat)
		for _, a in { 40, -40 } do
			local cut = part(Vector3.new(0.1, 1.6, 0.1), x * CFrame.Angles(0, 0, math.rad(a)), color)
			tween(cut, 0.16, { Transparency = 1, Size = Vector3.new(0.05, 2.2, 0.05) })
			task.delay(0.16, function()
				cut:Destroy()
			end)
		end
	elseif style == "spear" then
		-- long narrow thrust with a ring at the point
		streak(chest + flat * 1.5, flat, range - 1, 0.3, white, 0.24)
		streak(chest + flat * 1.5 + Vector3.new(0, 0.05, 0), flat, range - 2, 0.12, color, 0.2)
		local tip = chest + flat * range
		local ring = part(Vector3.new(0.15, 1, 1), CFrame.lookAt(tip, tip + flat) * CFrame.Angles(0, math.pi / 2, 0), color, Enum.PartType.Cylinder)
		ring.Transparency = 0.3
		tween(ring, 0.22, { Size = Vector3.new(0.1, 3.2, 3.2), Transparency = 1 })
		task.delay(0.22, function()
			ring:Destroy()
		end)
	else
		-- sword: diagonal cut from over the right shoulder down to the left hip
		local f = facing * CFrame.Angles(0, 0, math.rad(50))
		arc(f, range * 0.5, 10, 175, 11, 0.3, 1.1, color, 0.07, 0.22)
		arc(f * CFrame.new(0, 0.2, 0), range * 0.44, 20, 165, 11, 0.12, 0.4, white, 0.06, 0.18)
	end
end

function FX.Projectile(from: Vector3, to: Vector3, style: string, color: Color3)
	if not near(from, 220) and not near(to, 220) then
		return
	end
	local dist = (to - from).Magnitude
	local time = math.clamp(dist / 180, 0.05, 0.5)
	local staff = style == "staff"
	local p: Part
	if staff then
		p = part(Vector3.one * 1.2, CFrame.new(from), color, Enum.PartType.Ball)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = 8
		l.Parent = p
	else
		p = part(Vector3.new(0.16, 0.16, 2.6), CFrame.lookAt(from, to), color)
	end
	-- streak behind the shot
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, staff and 0.45 or 0.12, 0)
	a1.Position = Vector3.new(0, staff and -0.45 or -0.12, 0)
	a0.Parent, a1.Parent = p, p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4), color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = staff and 0.2 or 0.12
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = p
	FX.Burst(from, color:Lerp(Color3.new(1, 1, 1), 0.5), staff and 2.4 or 1.4, 0.12) -- muzzle flash
	tween(p, time, { CFrame = CFrame.lookAt(to, to + (to - from).Unit) }, Enum.EasingStyle.Linear)
	task.delay(time, function()
		p:Destroy()
		FX.Burst(to, color, staff and 7 or 2.5, 0.25)
		if staff then
			local splash = (Config.WeaponStyles.staff and Config.WeaponStyles.staff.splash) or 8
			FX.Ring(to - Vector3.new(0, 1.5, 0), color, splash, 0.35)
		else
			spark(to, (from - to).Unit, color)
		end
	end)
end

-- Shared by the local (predicted) swing and other players' swings
function FX.Swing(character: Model, style: string, dir: Vector3, target: Vector3?)
	local hitDelay, releaseDelay, duration = Anim.Swing(character, style)
	local color = Color3.fromRGB(235, 240, 255)
	local weapon = character:FindFirstChild("EquippedWeapon")
	local blade = weapon and (weapon:FindFirstChild("Blade") or weapon:FindFirstChild("Orb") or weapon:FindFirstChild("Blade", true) or weapon:FindFirstChild("Orb", true))
	if blade and blade:IsA("BasePart") then
		color = blade.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cfg = Config.WeaponStyles[style]
	if cfg and cfg.kind == "ranged" then
		-- the shot leaves when the string is let go / the staff is thrust forward
		local goal = target or (root and root.Position + Util.FlatUnit(dir) * (cfg.range or 60))
		task.delay(releaseDelay or hitDelay, function()
			if character.Parent then
				local from = muzzlePos(character, style)
				FX.Projectile(from, goal or from, style, color)
			end
		end)
		return
	end
	-- the scythe's circle follows the spin from its start; everything else lands on the hit frame
	local alt = style == "daggers" and Anim.IsAlt(character)
	task.delay(style == "scythe" and duration * 0.16 or hitDelay, function()
		if character.Parent then
			FX.Slash(character, dir, style, color, alt)
		end
	end)
	task.delay(hitDelay, function()
		local r = character:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and near(r.Position, 120) then
			sparkTargets(r, Util.FlatUnit(dir), style, color)
		end
	end)
end

--------------------------------------------------------------------------------
-- Abilities
--------------------------------------------------------------------------------
local function explosion(pos: Vector3, color: Color3, radius: number)
	FX.Burst(pos, color, radius * 2, 0.4)
	FX.Ring(pos, color, radius * 1.1, 0.5)
	if near(pos, 90) then
		UI.Sound(Config.Sounds.Explode, 0.35)
		FX.Shake(0.25, 0.25)
	end
end

local function lightning(to: Vector3, color: Color3)
	local top = to + Vector3.new(rng:NextNumber(-6, 6), 70, rng:NextNumber(-6, 6))
	local prev = top
	for i = 1, 7 do
		local alpha = i / 7
		local point = top:Lerp(to, alpha) + (i < 7 and Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)) or Vector3.zero)
		local mid = (prev + point) / 2
		local seg = part(Vector3.new(0.6, 0.6, (point - prev).Magnitude), CFrame.lookAt(mid, point), color)
		tween(seg, 0.35, { Transparency = 1 })
		task.delay(0.35, function()
			seg:Destroy()
		end)
		prev = point
	end
	FX.Burst(to, Color3.new(1, 1, 1), 8, 0.3)
end

local function follow(target: Model, p: BasePart, duration: number, offset: Vector3, spin: boolean)
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local age = os.clock() - started
		if not root or age > duration or not p.Parent then
			conn:Disconnect()
			p:Destroy()
			return
		end
		local cf = CFrame.new(root.Position + offset)
		if spin then
			cf *= CFrame.Angles(0, age * 4, 0)
		end
		p.CFrame = cf * (p:GetAttribute("Upright") and UP or CFrame.new())
	end)
end

function FX.Ability(data: any)
	local kind = tostring(data.kind)
	local color: Color3 = typeof(data.color) == "Color3" and data.color or Color3.new(1, 1, 1)
	local from: Vector3 = typeof(data.from) == "Vector3" and data.from or Vector3.zero
	local to: Vector3 = typeof(data.to) == "Vector3" and data.to or from
	local radius = tonumber(data.radius) or 12
	local caster: Player? = typeof(data.player) == "Instance" and data.player:IsA("Player") and data.player or nil
	local character = caster and caster.Character
	if not near(from, 260) and not near(to, 260) then
		return
	end
	if caster == player then
		UI.Sound(Config.Sounds.Ability, 0.35)
	end

	if kind == "dash" then
		FX.Ring(from - Vector3.new(0, 2.5, 0), color, 6, 0.35)
	elseif kind == "shadowstep" then
		FX.Burst(from, Color3.fromRGB(20, 10, 30), 7, 0.4)
		FX.Burst(to, color, 9, 0.35)
		FX.Ring(to - Vector3.new(0, 2.5, 0), color, 7, 0.45)
		if character then
			FX.Slash(character, Util.FlatUnit(to - from), "katana", color)
		end
	elseif kind == "warp" then
		explosion(from, color, radius)
		task.delay(0.1, function()
			explosion(to, color, radius)
			FX.Burst(to, Color3.new(1, 1, 1), 5, 0.25)
		end)
	elseif kind == "bolt" then
		local start = from + Vector3.new(0, 2, 0)
		local travel = math.clamp((to - from).Magnitude / 120, 0.08, 0.6)
		local ball = part(Vector3.one * 1.8, CFrame.new(start), color, Enum.PartType.Ball)
		tween(ball, travel, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Linear)
		task.delay(travel, function()
			ball:Destroy()
			explosion(to, color, radius)
		end)
	elseif kind == "nova" then
		explosion(from, color, radius)
	elseif kind == "meteor" then
		local delay = tonumber(data.delay) or 0.8
		local size = math.clamp(radius * 0.35, 3, 9)
		local rock = part(Vector3.one * size, CFrame.new(to + Vector3.new(-25, 80, 0)), color, Enum.PartType.Ball)
		local fire = Instance.new("Fire")
		fire.Size = size * 1.5
		fire.Color = color
		fire.Parent = rock
		local marker = part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(to + Vector3.new(0, 0.3, 0)) * UP, color, Enum.PartType.Cylinder)
		marker.Transparency = 0.7
		tween(rock, delay, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Quad)
		task.delay(delay, function()
			rock:Destroy()
			marker:Destroy()
			explosion(to, color, radius)
			if near(to, 80) then
				FX.Shake(0.6, 0.4)
			end
		end)
	elseif kind == "strike" then
		lightning(to, color)
	elseif kind == "drain" then
		lightning(to, color)
		for i = 1, 6 do
			task.delay(i * 0.05, function()
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root then
					return
				end
				local orb = part(Vector3.one * 0.8, CFrame.new(to), color, Enum.PartType.Ball)
				tween(orb, 0.35, { CFrame = CFrame.new(root.Position), Size = Vector3.one * 0.3 })
				task.delay(0.35, function()
					orb:Destroy()
				end)
			end)
		end
	elseif kind == "stun" then
		local dur = tonumber(data.dur) or 2
		local disc = part(Vector3.new(0.3, radius * 2, radius * 2), CFrame.new(from - Vector3.new(0, 2.6, 0)) * UP, color, Enum.PartType.Cylinder, Enum.Material.ForceField)
		tween(disc, dur, { Transparency = 1 })
		task.delay(dur, function()
			disc:Destroy()
		end)
		explosion(from, color, radius * 0.6)
	elseif kind == "dot" and character then
		local dur = tonumber(data.dur) or 5
		local storm = part(Vector3.new(7, radius * 2, radius * 2), CFrame.new(from), color, Enum.PartType.Cylinder, Enum.Material.ForceField)
		storm:SetAttribute("Upright", true)
		follow(character, storm, dur, Vector3.new(0, 1, 0), true)
	elseif kind == "heal" then
		FX.Burst(from, Color3.fromRGB(120, 255, 140), 9, 0.5)
		for _ = 1, 8 do
			local p = part(Vector3.one * 0.5, CFrame.new(from + Vector3.new(rng:NextNumber(-2, 2), -2, rng:NextNumber(-2, 2))), Color3.fromRGB(140, 255, 150), Enum.PartType.Ball)
			tween(p, 0.9, { CFrame = p.CFrame + Vector3.new(0, 6, 0), Transparency = 1 })
			task.delay(0.9, function()
				p:Destroy()
			end)
		end
	elseif kind == "buff" and character then
		local aura = part(Vector3.one * 7, CFrame.new(from), color, Enum.PartType.Ball, Enum.Material.ForceField)
		follow(character, aura, tonumber(data.dur) or 8, Vector3.zero, false)
	elseif kind == "shield" and character then
		local bubble = part(Vector3.one * 8, CFrame.new(from), color, Enum.PartType.Ball, Enum.Material.ForceField)
		follow(character, bubble, tonumber(data.dur) or 8, Vector3.zero, false)
	end
end

--------------------------------------------------------------------------------
-- World events
--------------------------------------------------------------------------------
function FX.MobDie(data: any)
	local pos: Vector3 = data.pos
	if not near(pos, 180) then
		return
	end
	local c1: Color3 = data.color
	local c2: Color3 = data.color2 or c1
	local size = tonumber(data.size) or 4
	FX.Burst(pos, Color3.new(1, 1, 1), size * 1.3, 0.3)
	for i = 1, 8 do
		local cube = part(Vector3.one * math.clamp(size * 0.18, 0.4, 2.2), CFrame.new(pos) * CFrame.Angles(rng:NextNumber() * 6, rng:NextNumber() * 6, 0), i % 2 == 0 and c1 or c2, nil, Enum.Material.SmoothPlastic)
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1.2), rng:NextNumber(-1, 1)).Unit
		tween(cube, 0.6, { CFrame = cube.CFrame + dir * size * 1.2, Transparency = 1, Size = cube.Size * 0.4 })
		task.delay(0.6, function()
			cube:Destroy()
		end)
	end
end

function FX.Slam(data: any)
	local pos: Vector3 = data.pos
	local radius = tonumber(data.radius) or 16
	local delay = tonumber(data.delay) or 1
	if not near(pos, 220) then
		return
	end
	local color = Color3.fromRGB(255, 60, 60)
	local disc = part(Vector3.new(0.25, 1, 1), CFrame.new(pos + Vector3.new(0, 0.25, 0)) * UP, color, Enum.PartType.Cylinder)
	disc.Transparency = 0.55
	local edge = part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(pos + Vector3.new(0, 0.2, 0)) * UP, color, Enum.PartType.Cylinder, Enum.Material.ForceField)
	tween(disc, delay, { Size = Vector3.new(0.25, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	task.delay(delay, function()
		disc:Destroy()
		edge:Destroy()
		explosion(pos, data.color or color, radius)
		if near(pos, 70) then
			FX.Shake(0.8, 0.45)
		end
	end)
end

function FX.CoreBeam(pos: Vector3, rarity: number, own: boolean)
	local r = Config.Rarities[rarity]
	local color = r and r.color or Color3.new(1, 1, 1)
	if not near(pos, 600) then
		return
	end
	local beam = part(Vector3.new(160, 3 + rarity, 3 + rarity), CFrame.new(pos + Vector3.new(0, 80, 0)) * UP, color, Enum.PartType.Cylinder)
	beam.Transparency = 0.1
	tween(beam, 1.6, { Transparency = 1, Size = Vector3.new(160, 0.5, 0.5) })
	task.delay(1.6, function()
		beam:Destroy()
	end)
	FX.Ring(pos, color, 8 + rarity * 2, 0.8)
	if own and rarity >= 4 then
		FX.Shake(0.4 + rarity * 0.08, 0.5)
	end
end

function FX.Handle(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "hits" then
		for _, hit in data.list or {} do
			FX.Popup(hit.pos, Util.Abbrev(hit.amount) .. (hit.crit and "!" or ""), hit.crit and Color3.fromRGB(255, 210, 60) or Color3.new(1, 1, 1), hit.crit)
		end
	elseif kind == "swing" then
		local caster = data.player
		if caster ~= player and typeof(caster) == "Instance" and caster:IsA("Player") and caster.Character then
			FX.Swing(caster.Character, tostring(data.style), data.dir or Vector3.new(0, 0, -1), data.target)
		end
	elseif kind == "ability" then
		FX.Ability(data)
	elseif kind == "mobAttack" then
		if data.model then
			Anim.Lunge(data.model)
		end
	elseif kind == "slam" then
		FX.Slam(data)
	elseif kind == "mobDie" then
		FX.MobDie(data)
	elseif kind == "reward" then
		FX.Popup(data.pos + Vector3.new(0, 1.5, 0), "+" .. Util.Abbrev(data.coins) .. " 💰", Color3.fromRGB(255, 215, 70), false)
	elseif kind == "coreDrop" then
		FX.CoreBeam(data.pos, tonumber(data.rarity) or 1, data.player == player)
	elseif kind == "pickup" or kind == "deliver" or kind == "steal" then
		local r = Config.Rarities[tonumber(data.rarity) or 1]
		local color = r and r.color or Color3.new(1, 1, 1)
		FX.Ring(data.pos - Vector3.new(0, 2.5, 0), color, kind == "deliver" and 16 or 9, 0.7)
		FX.Burst(data.pos, color, kind == "deliver" and 14 or 7, 0.45)
		if data.player == player and kind == "pickup" then
			UI.Sound(Config.Sounds.Pickup, 0.5)
		end
	end
end

function FX.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientFX"
	folder.Parent = workspace
	Net.Event("FX").OnClientEvent:Connect(function(kind, data)
		local ok, err = pcall(FX.Handle, kind, data)
		if not ok then
			warn("[FX] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end)
	RunService:BindToRenderStep("CoreHuntersShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shakeUntil then
			local fade = (shakeUntil - now)
			local a = shakeAmp * math.min(fade * 3, 1) * 0.02
			camera.CFrame *= CFrame.Angles(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
		end
	end)
end

return FX
