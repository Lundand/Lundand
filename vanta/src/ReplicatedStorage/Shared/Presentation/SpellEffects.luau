--!strict
-- Spell effects for area abilities (effects pass): replaces the neon disc-and-ball placeholders for every "Burst" and
-- "Sigil" ability. Presentation only, played on each client from the CombatEvent broadcast; damage, timing and areas are the
-- server's, and the marked circle is exactly the area that is hit (its radius).
--   SpellEffects.play({ effect, ability, target, origin, radius, windup, pulses })
-- Each ability belongs to a family (its look). Every family shares the readable parts: a ground ring at the true radius, a
-- faint field, and an inner ring that closes on the edge as the windup ends (when it lands). Sigils add a slowly turning
-- rune ring. Then each family erupts its own way, once per pulse (multi-hit fields pulse with their hits):
--   blast (arcane, abyss, astral, time), lightning (storm), pillar (holy), roots (nature), quake (earth),
--   rain (arrows, blades: real library models falling), dome (protective fields), wisps (spectral legions).
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SpellEffects = {}

type Family = { color: Color3, accent: Color3, glow: number, eruption: string, field: boolean }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local FAMILIES: { [string]: Family } = {
	Arcane = { color = rgb(150, 120, 255), accent = rgb(215, 205, 255), glow = 0.55, eruption = "blast", field = true },
	Abyss = { color = rgb(105, 55, 150), accent = rgb(190, 120, 255), glow = 0.25, eruption = "blast", field = true },
	Astral = { color = rgb(80, 110, 210), accent = rgb(225, 235, 255), glow = 0.6, eruption = "blast", field = true },
	Time = { color = rgb(70, 175, 170), accent = rgb(200, 245, 235), glow = 0.45, eruption = "blast", field = true },
	Storm = { color = rgb(120, 170, 235), accent = rgb(235, 245, 255), glow = 0.7, eruption = "lightning", field = true },
	Holy = { color = rgb(235, 195, 110), accent = rgb(255, 245, 215), glow = 0.6, eruption = "pillar", field = true },
	Nature = { color = rgb(105, 160, 80), accent = rgb(200, 230, 150), glow = 0.2, eruption = "roots", field = true },
	Earth = { color = rgb(150, 120, 90), accent = rgb(210, 190, 160), glow = 0, eruption = "quake", field = false },
	Arrows = { color = rgb(200, 180, 140), accent = rgb(240, 230, 205), glow = 0.1, eruption = "rain", field = false },
	Blades = { color = rgb(120, 150, 200), accent = rgb(215, 228, 250), glow = 0.4, eruption = "rain", field = true },
	Bulwark = { color = rgb(200, 175, 110), accent = rgb(245, 235, 205), glow = 0.35, eruption = "dome", field = true },
	Spectral = { color = rgb(130, 200, 170), accent = rgb(215, 245, 230), glow = 0.45, eruption = "wisps", field = true },
}
local ABILITY_FAMILY: { [string]: string } = {
	ArcaneBurst = "Arcane", ArcaneCataclysm = "Arcane",
	AbyssChains = "Abyss", AbyssUnbound = "Abyss",
	GravityWell = "Astral", StarfallCataclysm = "Astral",
	TemporalSnare = "Time", ZeroHour = "Time",
	StormField = "Storm", Stormstep = "Storm", TempestSovereign = "Storm", HeavensSpear = "Storm",
	Consecration = "Holy", LightOfTheCovenant = "Holy",
	DivineSanctuary = "Bulwark", HeavensLastBastion = "Bulwark", FortressOfTheLastStand = "Bulwark",
	RootSnare = "Nature", WorldrootPrison = "Nature",
	IronFistCataclysm = "Earth", Worldsplitter = "Earth",
	RainOfArrows = "Arrows", ThousandBladesImperialExecution = "Blades",
	LichLegion = "Spectral", EternalLegion = "Spectral",
}
-- abilities whose eruption is a single falling model before the blast
local FALLING: { [string]: string } = { HeavensSpear = "IronSpear", StarfallCataclysm = "ArcaneBolt" }

local function container(): Folder
	local folder = workspace:FindFirstChild("SpellEffects")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "SpellEffects"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function anchor(cframe: CFrame, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Name = "Anchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Parent = container()
	return part
end

-- the ground under a point (characters and effects ignored); the old placeholder's fixed offset as a fallback
local function groundUnder(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { container() }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(point + Vector3.new(0, 4, 0), Vector3.new(0, -24, 0), params)
	return if hit then hit.Position + Vector3.new(0, 0.08, 0) else point - Vector3.new(0, 2.9, 0)
end

-- A ring of camera-facing beam segments around an anchor (flat on the ground, any radius, cheap to resize each frame).
type Ring = { setRadius: (number) -> (), setTransparency: (number) -> (), radius: number }
local SEGMENTS = 32
local function ring(host: BasePart, radius: number, color: Color3, width: number, glow: number, transparency: number): Ring
	local points = {}
	for i = 1, SEGMENTS do
		local attachment = Instance.new("Attachment")
		attachment.Parent = host
		points[i] = attachment
	end
	local beams = {}
	for i = 1, SEGMENTS do
		local beam = Instance.new("Beam")
		beam.Attachment0 = points[i]
		beam.Attachment1 = points[i % SEGMENTS + 1]
		beam.Color = ColorSequence.new(color)
		beam.LightEmission = glow
		beam.LightInfluence = 1 - glow
		beam.Width0 = width
		beam.Width1 = width
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Transparency = NumberSequence.new(transparency)
		beam.Parent = host
		beams[i] = beam
	end
	local self: Ring = { radius = radius, setRadius = nil :: any, setTransparency = nil :: any }
	function self.setRadius(r: number)
		self.radius = r
		for i, attachment in ipairs(points) do
			local angle = (i - 1) / SEGMENTS * math.pi * 2
			attachment.Position = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		end
	end
	function self.setTransparency(t: number)
		for _, beam in ipairs(beams) do
			beam.Transparency = NumberSequence.new(math.clamp(t, 0, 1))
		end
	end
	self.setRadius(radius)
	return self
end

-- runs `step(alpha)` every frame for `seconds`, then `done()`
local function animate(seconds: number, step: (number) -> (), done: (() -> ())?)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = if seconds <= 0 then 1 else math.min((os.clock() - started) / seconds, 1)
		step(alpha)
		if alpha >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
end

local function emitter(host: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LockedToPart = false
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = host
	return e
end

local function flash(position: Vector3, color: Color3, range: number, brightness: number)
	local host = anchor(CFrame.new(position + Vector3.new(0, 2, 0)))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(range, 60)
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = host
	TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(host, 0.5)
end

-- an expanding ring that fades: the shockwave every eruption shares
local function shockwave(ground: Vector3, radius: number, family: Family, seconds: number, width: number?)
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.15, 0)))
	local wave = ring(host, radius * 0.15, family.accent, width or math.clamp(radius * 0.06, 0.3, 1.2), family.glow, 0.1)
	animate(seconds, function(alpha)
		local eased = 1 - (1 - alpha) ^ 3
		wave.setRadius(radius * (0.15 + eased))
		wave.setTransparency(0.1 + alpha * 0.9)
	end, function()
		host:Destroy()
	end)
end

local function randomPoint(ground: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius
	return ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- a library model (Assets.<folder>.<name>) as an anchored, untouchable effect prop; `spectral` tints it translucent
local function libraryProp(folderName: string, name: string, spectral: Color3?): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild(folderName)
	local template = library and library:FindFirstChild(name)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.CastShadow = false
			if spectral and item.Transparency < 1 then
				-- tinted translucent glass: ForceField washes out on thin blades and shafts, Neon blows out to white
				item.Material = Enum.Material.Glass
				item.Transparency = 0.25
				item.Color = spectral
				if item:IsA("MeshPart") then
					item.TextureID = ""
				end
			end
		elseif item:IsA("SurfaceAppearance") and spectral then
			item:Destroy()
		end
	end
	return model
end

-- Eruptions -------------------------------------------------------------------------------------------------------------
local ERUPTIONS: { [string]: (Vector3, number, Family, string?) -> () } = {}

function ERUPTIONS.blast(ground, radius, family)
	shockwave(ground, radius, family, 0.4)
	flash(ground, family.accent, radius * 1.6, 2.5)
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.5, 0)), Vector3.new(radius * 1.2, 0.2, radius * 1.2))
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(family.accent, family.color), LightEmission = family.glow,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(35, 35), Drag = 3, Acceleration = Vector3.new(0, -6, 0),
	}):Emit(math.clamp(math.floor(radius * 3), 12, 45))
	-- a dark smoke column for the abyss, so it reads as heavy rather than bright
	if family == FAMILIES.Abyss then
		emitter(host, {
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Color = ColorSequence.new(rgb(35, 20, 50), rgb(70, 40, 95)), LightEmission = 0, LightInfluence = 1,
			Size = NumberSequence.new(1.6, 3.2), Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(15, 15), Rotation = NumberRange.new(0, 360),
		}):Emit(math.clamp(math.floor(radius * 1.5), 8, 24))
	end
	Debris:AddItem(host, 1.6)
end

local function bolt(from: Vector3, to: Vector3, family: Family, width: number)
	local host = anchor(CFrame.new(from))
	local points = {}
	local steps = 7
	for i = 0, steps do
		local attachment = Instance.new("Attachment")
		local p = from:Lerp(to, i / steps)
		if i > 0 and i < steps then
			p += Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2.4
		end
		attachment.WorldPosition = p
		attachment.Parent = host
		table.insert(points, attachment)
	end
	for i = 1, #points - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = points[i]
		beam.Attachment1 = points[i + 1]
		beam.Color = ColorSequence.new(family.accent)
		beam.LightEmission = 1
		beam.Width0 = width
		beam.Width1 = width * 0.8
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = host
	end
	Debris:AddItem(host, 0.14)
end

function ERUPTIONS.lightning(ground, radius, family)
	local strikes = math.clamp(math.floor(radius / 3), 2, 5)
	for _ = 1, strikes do
		local point = randomPoint(ground, radius * 0.85)
		bolt(point + Vector3.new(math.random(-3, 3), 22, math.random(-3, 3)), point, family, 0.35)
		local host = anchor(CFrame.new(point + Vector3.new(0, 0.3, 0)))
		emitter(host, {
			Color = ColorSequence.new(family.accent), LightEmission = 1, Size = NumberSequence.new(0.18, 0),
			Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(80, 80),
			Acceleration = Vector3.new(0, -30, 0),
		}):Emit(10)
		Debris:AddItem(host, 0.6)
	end
	shockwave(ground, radius, family, 0.3, 0.4)
	flash(ground, family.accent, radius * 1.8, 2.5)
end

function ERUPTIONS.pillar(ground, radius, family)
	-- a column of warm light rising from the ground, wide at the base, thinning as it climbs
	local base = anchor(CFrame.new(ground))
	local low, high = Instance.new("Attachment"), Instance.new("Attachment")
	low.Parent = base
	high.Position = Vector3.new(0, 16, 0)
	high.Parent = base
	local beam = Instance.new("Beam")
	beam.Attachment0 = low
	beam.Attachment1 = high
	beam.FaceCamera = true
	beam.Width0 = radius * 0.9
	beam.Width1 = radius * 0.25
	beam.LightEmission = family.glow
	beam.Color = ColorSequence.new(family.accent, family.color)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = base
	animate(0.6, function(alpha)
		local t = 0.35 + alpha * 0.65
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t), NumberSequenceKeypoint.new(1, 1) })
	end, function()
		base:Destroy()
	end)
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.4, 0)), Vector3.new(radius * 1.4, 0.2, radius * 1.4))
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(family.accent), LightEmission = family.glow, Size = NumberSequence.new(0.22, 0),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(10, 10), Drag = 1,
	}):Emit(math.clamp(math.floor(radius * 2.5), 10, 36))
	Debris:AddItem(host, 1.6)
	shockwave(ground, radius, family, 0.45)
	flash(ground, family.accent, radius * 1.6, 2)
end

function ERUPTIONS.roots(ground, radius, family)
	-- gnarled roots burst up around the area and sink back
	local count = math.clamp(math.floor(radius * 0.9), 5, 12)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.4
		local distance = radius * (0.35 + math.random() * 0.6)
		local at = ground + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		-- the library root mesh (Assets.Effects.Root, pivot at its base) rises out of the ground, leaning in, and sinks back
		local mesh = libraryProp("Effects", "Root", nil)
		if mesh ~= nil then
			mesh:ScaleTo(0.8 + math.random() * 0.6)
			local height = mesh:GetExtentsSize().Y
			local inward = (ground - at).Unit
			local tilt = CFrame.fromAxisAngle(Vector3.yAxis:Cross(inward).Unit, math.rad(12 + math.random() * 18))
			local up = CFrame.new(at) * tilt * CFrame.Angles(0, math.random() * math.pi * 2, 0)
			local down = up * CFrame.new(0, -height - 0.2, 0)
			mesh:PivotTo(down)
			mesh.Parent = container()
			animate(0.18, function(alpha)
				mesh:PivotTo(down:Lerp(up, 1 - (1 - alpha) ^ 2))
			end, function()
				task.delay(0.9, function()
					animate(0.4, function(alpha)
						mesh:PivotTo(up:Lerp(down, alpha * alpha))
					end, function()
						mesh:Destroy()
					end)
				end)
			end)
			continue
		end
		local root = Instance.new("Part")
		root.Shape = Enum.PartType.Cylinder
		root.Material = Enum.Material.Wood
		root.Color = rgb(88, 64, 42)
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		local thickness = 0.45 + math.random() * 0.35
		local length = 2.6 + math.random() * 2.2
		-- cylinder axis is X (after the turn, X points from the root's foot towards a point high over the centre)
		local lean = CFrame.lookAt(at, ground + Vector3.new(0, length * 2.2, 0)) * CFrame.Angles(0, math.rad(90), 0)
		root.Size = Vector3.new(0.1, thickness, thickness)
		root.CFrame = lean
		root.Parent = container()
		animate(0.18, function(alpha)
			local l = length * (1 - (1 - alpha) ^ 2)
			root.Size = Vector3.new(math.max(l, 0.1), thickness, thickness)
			root.CFrame = lean * CFrame.new(l / 2, 0, 0)
		end, function()
			task.delay(0.9, function()
				animate(0.35, function(alpha)
					local l = length * (1 - alpha)
					root.Size = Vector3.new(math.max(l, 0.1), thickness, thickness)
					root.CFrame = lean * CFrame.new(l / 2, 0, 0)
				end, function()
					root:Destroy()
				end)
			end)
		end)
	end
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.5, 0)), Vector3.new(radius * 1.4, 0.2, radius * 1.4))
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(family.accent, family.color), Size = NumberSequence.new(0.3, 0.1), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120), Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, -8, 0), Drag = 1.5,
	}):Emit(math.clamp(math.floor(radius * 2), 10, 28))
	Debris:AddItem(host, 1.5)
	shockwave(ground, radius, family, 0.4)
end

function ERUPTIONS.quake(ground, radius, family)
	shockwave(ground, radius, family, 0.35, 0.9)
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.4, 0)), Vector3.new(radius * 1.6, 0.2, radius * 1.6))
	-- dust rolling outwards, and rock chips thrown up
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(family.accent, family.color), LightInfluence = 1, Size = NumberSequence.new(1.4, 3.4),
		Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(80, 80), Rotation = NumberRange.new(0, 360), Drag = 2,
	}):Emit(math.clamp(math.floor(radius * 2), 12, 32))
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(rgb(95, 88, 80)), LightInfluence = 1, Size = NumberSequence.new(0.3, 0.2),
		Lifetime = NumberRange.new(0.6, 1.0), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -45, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	}):Emit(math.clamp(math.floor(radius * 1.5), 8, 24))
	Debris:AddItem(host, 1.6)
end

function ERUPTIONS.rain(ground, radius, family, abilityId)
	-- real library models fall into the marked area: arrows for the volley, spectral blades for the blade storm
	local arrows = family == FAMILIES.Arrows
	local count = if arrows then math.clamp(math.floor(radius * 1.2), 6, 14) else math.clamp(math.floor(radius * 0.6), 4, 8)
	for i = 1, count do
		task.delay((i - 1) * 0.03, function()
			local point = randomPoint(ground, radius * 0.9)
			local prop = if arrows then libraryProp("Projectiles", "Arrow", nil) else libraryProp("Weapons", "TrainingSword", family.color)
			if prop == nil then
				return
			end
			if not arrows then
				prop:ScaleTo(1.6) -- spectral blades are larger than a real sword, so they read at a distance
			end
			for _, item in ipairs(prop:GetDescendants()) do
				if item:IsA("Trail") or item:IsA("ParticleEmitter") or item:IsA("Light") then
					item:Destroy()
				end
			end
			-- point down: arrows fly along -Z, blades point along +Y from the grip
			local down = if arrows then CFrame.lookAt(Vector3.zero, Vector3.new(0.15, -1, 0.1), Vector3.xAxis) else CFrame.Angles(math.rad(180 + math.random(-12, 12)), math.random() * 6.28, 0)
			local depth = if arrows then 0.9 else 1.6
			local finish = CFrame.new(point + Vector3.new(0, depth, 0)) * down
			local start = finish + Vector3.new(0, 20, 0)
			prop:PivotTo(start)
			prop.Parent = container()
			animate(0.22, function(alpha)
				prop:PivotTo(start:Lerp(finish, alpha * alpha))
			end, function()
				local host = anchor(CFrame.new(point + Vector3.new(0, 0.2, 0)))
				emitter(host, {
					Color = ColorSequence.new(if arrows then rgb(150, 130, 105) else family.accent), LightEmission = if arrows then 0 else 0.6,
					Size = NumberSequence.new(if arrows then 0.5 else 0.25, 0), Transparency = NumberSequence.new(0.3, 1),
					Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(70, 70),
				}):Emit(6)
				Debris:AddItem(host, 0.6)
				task.delay(if arrows then 0.6 else 0.35, function()
					local parts = {}
					for _, item in ipairs(prop:GetDescendants()) do
						if item:IsA("BasePart") and item.Transparency < 1 then
							table.insert(parts, { part = item, from = item.Transparency })
						end
					end
					animate(0.3, function(alpha)
						for _, entry in ipairs(parts) do
							entry.part.Transparency = entry.from + (1 - entry.from) * alpha
						end
					end, function()
						prop:Destroy()
					end)
				end)
			end)
		end)
	end
	if not arrows then
		shockwave(ground, radius, family, 0.4)
	end
end

function ERUPTIONS.dome(ground, radius, family, abilityId)
	-- a protective dome over the party's ground, held for the protection's duration when the ability has one
	local Content = require(ReplicatedStorage:WaitForChild("Shared").Content)
	local def = abilityId and Content.abilities[abilityId]
	local hold = 1.5
	if def ~= nil then
		local protection = def.allyDefense or def.defense
		hold = math.clamp((protection and protection.seconds) or hold, 1, 10)
	end
	local dome = Instance.new("Part")
	dome.Shape = Enum.PartType.Ball
	dome.Material = Enum.Material.ForceField
	dome.Color = family.color
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Size = Vector3.one * 0.5
	dome.CFrame = CFrame.new(ground)
	dome.Parent = container()
	TweenService:Create(dome, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2 }):Play()
	task.delay(hold, function()
		local fade = TweenService:Create(dome, TweenInfo.new(0.5), { Transparency = 1 })
		fade.Completed:Connect(function()
			dome:Destroy()
		end)
		fade:Play()
	end)
	shockwave(ground, radius, family, 0.45)
	flash(ground, family.accent, radius * 1.4, 1.5)
end

function ERUPTIONS.wisps(ground, radius, family)
	local host = anchor(CFrame.new(ground + Vector3.new(0, 0.4, 0)), Vector3.new(radius * 1.4, 0.2, radius * 1.4))
	emitter(host, {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(family.accent, family.color), LightEmission = family.glow,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.3, 1), Lifetime = NumberRange.new(1.0, 1.8), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(15, 15), Rotation = NumberRange.new(0, 360), Drag = 0.5,
	}):Emit(math.clamp(math.floor(radius * 2.5), 12, 30))
	Debris:AddItem(host, 2)
	shockwave(ground, radius, family, 0.5)
end

-- a single model drops onto the centre just before the eruption (Heaven's Spear, Starfall Cataclysm)
local function fall(ground: Vector3, family: Family, modelName: string, seconds: number)
	local isSpear = modelName == "IronSpear"
	local prop = if isSpear then libraryProp("Weapons", modelName, family.accent) else libraryProp("Projectiles", modelName, nil)
	if prop == nil then
		return
	end
	if not isSpear then
		prop:ScaleTo(3)
	end
	-- the spear points down (+Y is its tip); the bolt flies along -Z, so it is aimed at the ground
	local offset = Vector3.new(10, 34, 6)
	local finish = if isSpear then CFrame.new(ground + Vector3.new(0, 3, 0)) * CFrame.Angles(math.rad(180), 0, 0) else CFrame.lookAt(ground + Vector3.new(0, 1, 0), ground - offset.Unit)
	local start = finish + offset
	prop:PivotTo(start)
	prop.Parent = container()
	animate(seconds, function(alpha)
		prop:PivotTo(start:Lerp(finish, alpha * alpha))
	end, function()
		task.delay(if isSpear then 0.5 else 0, function()
			prop:Destroy()
		end)
	end)
end

-- Bolts (magic projectiles) ---------------------------------------------------------------------------------------------
-- Every non-bow "Bolt" gets its family's projectile: a library model (Assets.Projectiles) flown along the aim with family
-- particles, or a drawn shape (lightning for storm, a curved crescent for sword waves). Abilities name their family; basic
-- attacks are known by the caster's class. Bows and crossbows keep the arrow (CombatFeedback).
type BoltStyle = { family: string, model: string?, kind: string?, stopsAtTargets: boolean }
local BOLT_ABILITY: { [string]: string } = {
	MagicBolt = "Arcane", HolyBolt = "Holy", SoulBolt = "Soul", SoulDrain = "Soul", AbyssBolt = "Abyss", CurseOfRuin = "Abyss",
	AstralLance = "Astral", StarShards = "Astral", LightningLance = "Storm", ChainLightning = "Storm", ChainSpark = "Storm",
	ThornSurge = "Nature", PhantomBlade = "Blade", EmperorsBlade = "Blade", ArcaneOverdrive = "ArcaneBlade",
	VoidCut = "VoidBlade", RiftsEnd = "VoidBlade", DragonfireSlash = "FireBlade", DragonGodsDescent = "FireBlade",
}
local BOLT_CASTER: { [string]: string } = {
	Mage = "Arcane", Acolyte = "Holy", LichLord = "Soul", Summoner = "Soul", AbyssalWarlock = "Abyss", AstralArchmage = "Astral",
	Stormcaller = "Storm", WorldrootSage = "Nature", Chronomancer = "Time",
}
local BOLT_STYLES: { [string]: BoltStyle } = {
	Arcane = { family = "Arcane", model = "ArcaneBolt", stopsAtTargets = true },
	Holy = { family = "Holy", model = "BoltHoly", stopsAtTargets = true },
	Soul = { family = "Spectral", model = "BoltSoul", stopsAtTargets = true },
	Abyss = { family = "Abyss", model = "BoltAbyss", stopsAtTargets = true },
	Astral = { family = "Astral", model = "BoltAstral", stopsAtTargets = false },
	Time = { family = "Time", model = "BoltTime", stopsAtTargets = true },
	Nature = { family = "Nature", model = "BoltThorn", stopsAtTargets = true },
	Storm = { family = "Storm", kind = "lightning", stopsAtTargets = false },
	Blade = { family = "Blades", kind = "wave", stopsAtTargets = false },
	ArcaneBlade = { family = "Arcane", kind = "wave", stopsAtTargets = false },
	VoidBlade = { family = "Abyss", kind = "wave", stopsAtTargets = false },
	FireBlade = { family = "Fire", kind = "wave", stopsAtTargets = false },
}
FAMILIES.Fire = { color = rgb(225, 95, 40), accent = rgb(255, 205, 120), glow = 0.6, eruption = "blast", field = true }

-- where the bolt's flight ends: the first wall (and, for single-target bolts, the first body) along the aim
local function flightEnd(start: Vector3, direction: Vector3, range: number, actor: Model?, stopsAtTargets: boolean): (Vector3, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { container() }
	if actor then
		table.insert(ignore, actor)
	end
	if not stopsAtTargets then
		for _, other in ipairs(Players:GetPlayers()) do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		local enemies = workspace:FindFirstChild("Enemies")
		if enemies then
			table.insert(ignore, enemies)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(start, direction * range, params)
	if hit then
		return hit.Position, true
	end
	return start + direction * range, false
end

-- a family-coloured burst where a bolt lands
local function boltImpact(position: Vector3, family: Family, size: number)
	local host = anchor(CFrame.new(position))
	emitter(host, {
		Color = ColorSequence.new(family.accent, family.color), LightEmission = family.glow,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * size), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(5, 11),
		SpreadAngle = Vector2.new(180, 180), Drag = 4,
	}):Emit(math.floor(14 * size))
	if family == FAMILIES.Abyss or family == FAMILIES.Fire then
		emitter(host, {
			Color = ColorSequence.new(if family == FAMILIES.Fire then rgb(70, 50, 40) else rgb(35, 20, 50)), LightInfluence = 1,
			Size = NumberSequence.new(0.8 * size, 1.8 * size), Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		}):Emit(6)
	end
	Debris:AddItem(host, 1)
	if family.glow > 0 then
		flash(position, family.accent, 10 * size, 1.5)
	end
	local ground = groundUnder(position)
	if (position - ground).Magnitude < 3 then
		shockwave(ground, 2.2 * size, family, 0.3, 0.2)
	end
end

-- particles that stream off a flying bolt, per family
local function flightParticles(host: BasePart, family: Family)
	local props: { [string]: any } = {
		Color = ColorSequence.new(family.accent, family.color), LightEmission = family.glow,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Rate = 45,
	}
	if family == FAMILIES.Abyss then
		-- dark smoke curling off the void orb
		props.Color = ColorSequence.new(rgb(60, 30, 90), rgb(20, 10, 30))
		props.LightEmission = 0
		props.LightInfluence = 1
		props.Size = NumberSequence.new(0.5, 1.1)
		props.Rotation = NumberRange.new(0, 360)
		props.RotSpeed = NumberRange.new(-90, 90)
		props.Lifetime = NumberRange.new(0.35, 0.6)
	elseif family == FAMILIES.Nature then
		props.Size = NumberSequence.new(0.18, 0.08)
		props.Rotation = NumberRange.new(0, 360)
		props.RotSpeed = NumberRange.new(-200, 200)
		props.Acceleration = Vector3.new(0, -6, 0)
		props.Rate = 18
	end
	local e = emitter(host, props)
	e.Enabled = true
	if family.glow > 0.3 then
		local light = Instance.new("PointLight")
		light.Color = family.accent
		light.Brightness = 1
		light.Range = 7
		light.Shadows = false
		light.Parent = host
	end
end

local function flyModel(style: BoltStyle, family: Family, start: Vector3, finish: Vector3, seconds: number, onDone: () -> ())
	local model = libraryProp("Projectiles", style.model :: string, nil)
	if model == nil then
		onDone()
		return
	end
	local root = model.PrimaryPart :: BasePart
	flightParticles(root, family)
	local from = CFrame.lookAt(start, finish)
	local spin = style.model == "BoltTime" or style.model == "BoltThorn"
	model:PivotTo(from)
	model.Parent = container()
	local started = os.clock()
	animate(seconds, function(alpha)
		local at = from.Rotation + start:Lerp(finish, alpha)
		if spin then
			at *= CFrame.Angles(0, 0, (os.clock() - started) * 9)
		end
		model:PivotTo(at)
	end, function()
		model:Destroy()
		onDone()
	end)
end

-- storm: a crackling bolt that races along the aim, its jagged shape redrawn every frame
local function flyLightning(family: Family, start: Vector3, finish: Vector3, seconds: number, onDone: () -> ())
	local host = anchor(CFrame.new(start))
	local points = {}
	for i = 1, 9 do
		local a = Instance.new("Attachment")
		a.Parent = host
		points[i] = a
	end
	local beams = {}
	for i = 1, #points - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = points[i]
		beam.Attachment1 = points[i + 1]
		beam.Color = ColorSequence.new(family.accent)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 0.35
		beam.Width1 = 0.35
		beam.Parent = host
		beams[i] = beam
	end
	local head = anchor(CFrame.new(start))
	flightParticles(head, family)
	local direction = (finish - start).Unit
	local side = direction:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = side:Cross(direction).Unit
	animate(seconds, function(alpha)
		local tip = start:Lerp(finish, alpha)
		local tail = start:Lerp(finish, math.max(alpha - 0.35, 0))
		for i, a in ipairs(points) do
			local t = (i - 1) / (#points - 1)
			local jitter = if i == 1 or i == #points then Vector3.zero else side * (math.random() - 0.5) * 0.9 + up * (math.random() - 0.5) * 0.9
			a.WorldPosition = tail:Lerp(tip, t) + jitter
		end
		head.Position = tip
	end, function()
		host:Destroy()
		head:Destroy()
		onDone()
	end)
end

-- sword waves: a flat crescent as wide as the hit (two curved ribbons from the centre out to sharp tips) sweeping forward
local function flyWave(family: Family, start: Vector3, finish: Vector3, seconds: number, width: number, onDone: () -> ())
	local host = anchor(CFrame.lookAt(start, finish))
	local centre = Instance.new("Attachment")
	centre.Parent = host
	for _, sign in ipairs({ -1, 1 }) do
		local tip = Instance.new("Attachment")
		-- tips trail behind the centre, so the crescent bows forward
		tip.Position = Vector3.new(sign * width / 2, 0, width * 0.3)
		tip.Parent = host
		local beam = Instance.new("Beam")
		beam.Attachment0 = centre
		beam.Attachment1 = tip
		beam.Color = ColorSequence.new(family.accent, family.color)
		beam.LightEmission = family.glow
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.6) })
		beam.Width0 = math.clamp(width * 0.18, 0.4, 1.6)
		beam.Width1 = 0.05
		beam.CurveSize0 = -width * 0.12
		beam.CurveSize1 = 0
		beam.FaceCamera = false
		beam.Segments = 12
		beam.Parent = host
		-- the ribbon lies flat: attachments' axes point up so the beam faces the sky
		centre.Axis = Vector3.yAxis
		tip.Axis = Vector3.yAxis
	end
	flightParticles(host, family)
	if family == FAMILIES.Fire then
		emitter(host, {
			Color = ColorSequence.new(rgb(255, 200, 110), rgb(200, 70, 30)), LightEmission = 0.8, Size = NumberSequence.new(0.6, 0),
			Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rate = 60,
		}).Enabled = true
	end
	local from = CFrame.lookAt(start, finish)
	animate(seconds, function(alpha)
		host.CFrame = from.Rotation + start:Lerp(finish, alpha)
	end, function()
		host:Destroy()
		onDone()
	end)
end

-- basic attacks: a small, fast spark of the class colour (the full models are kept for the class's slot abilities)
local function flySpark(family: Family, start: Vector3, finish: Vector3, seconds: number, onDone: () -> ())
	local host = anchor(CFrame.lookAt(start, finish))
	local front, back = Instance.new("Attachment"), Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -0.2)
	back.Position = Vector3.new(0, 0, 0.2)
	front.Parent = host
	back.Parent = host
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Lifetime = 0.12
	trail.Color = ColorSequence.new(family.accent, family.color)
	trail.LightEmission = family.glow
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.FaceCamera = true
	trail.Parent = host
	local core = emitter(host, {
		Color = ColorSequence.new(family.accent), LightEmission = math.max(family.glow, 0.3),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.08, 0.14), Speed = NumberRange.new(0, 0.3),
		Rate = 120, LockedToPart = true,
	})
	core.Enabled = true
	local from = CFrame.lookAt(start, finish)
	animate(seconds, function(alpha)
		host.CFrame = from.Rotation + start:Lerp(finish, alpha)
	end, function()
		host:Destroy()
		onDone()
	end)
end

-- what a slot ability's impact adds, so its effect reads: Magic Bolt's splash, Abyss Bolt's mark, Soul Bolt's drain
local function abilityImpact(abilityId: string?, position: Vector3, family: Family, actor: Model?)
	if abilityId == "MagicBolt" then
		-- the splash: a ring the size of the area it hits
		local host = anchor(CFrame.new(position))
		local wave = ring(host, 0.5, family.accent, 0.35, family.glow, 0.1)
		animate(0.3, function(alpha)
			wave.setRadius(0.5 + 5.5 * (1 - (1 - alpha) ^ 2))
			wave.setTransparency(0.1 + 0.9 * alpha)
		end, function()
			host:Destroy()
		end)
	elseif abilityId == "AbyssBolt" then
		-- the mark: a small dark sigil hanging over the struck spot for a moment
		local host = anchor(CFrame.new(position + Vector3.new(0, 2.6, 0)))
		local sigil = ring(host, 0.7, family.accent, 0.12, family.glow, 0.2)
		animate(1.2, function(alpha)
			host.CFrame = CFrame.new(position + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, alpha * 6, 0)
			sigil.setTransparency(0.2 + 0.8 * alpha * alpha)
		end, function()
			host:Destroy()
		end)
	elseif abilityId == "SoulBolt" and actor ~= nil then
		-- the drain: a wisp flows back from the target to the caster
		local casterRoot = actor:FindFirstChild("HumanoidRootPart")
		if casterRoot ~= nil and casterRoot:IsA("BasePart") then
			local wisp = anchor(CFrame.new(position))
			flightParticles(wisp, family)
			local from = position
			animate(0.45, function(alpha)
				local to = casterRoot.Position
				wisp.Position = from:Lerp(to, alpha * alpha) + Vector3.new(0, math.sin(alpha * math.pi) * 2, 0)
			end, function()
				wisp:Destroy()
			end)
		end
	end
end

-- Plays a bolt's flight and impact. Returns false when it isn't a magic bolt this module draws (the caller then falls back).
function SpellEffects.bolt(extra: any, actor: Model?, start: Vector3, direction: Vector3, range: number, seconds: number): boolean
	local abilityId = if type(extra.ability) == "string" then extra.ability else nil
	local caster = if type(extra.caster) == "string" then extra.caster else nil
	local styleName = (abilityId and BOLT_ABILITY[abilityId]) or (caster and BOLT_CASTER[caster])
	local style = styleName and BOLT_STYLES[styleName]
	if style == nil then
		return false
	end
	local family = FAMILIES[style.family]
	local finish, hitSomething = flightEnd(start, direction, range, actor, style.stopsAtTargets)
	local flight = seconds * ((finish - start).Magnitude / math.max(range, 0.01))
	-- a basic attack (no ability, known by the caster's class) is a spark; slot abilities fly their full projectile
	local basic = abilityId == nil
	local size = if basic then 0.6 elseif style.kind == "wave" then 1.4 elseif abilityId == "MagicBolt" then 1.5 else 1
	local function landed()
		if hitSomething or style.kind ~= "wave" then
			boltImpact(finish, family, size)
		end
		if hitSomething then
			abilityImpact(abilityId, finish, family, actor)
		end
	end
	if basic then
		flySpark(family, start, finish, flight, landed)
	elseif style.kind == "lightning" then
		flyLightning(family, start, finish, flight, landed)
	elseif style.kind == "wave" then
		flyWave(family, start, finish, flight, math.clamp((tonumber(extra.radius) or 2) * 2, 2.5, 10), landed)
	else
		flyModel(style, family, start, finish, flight, landed)
	end
	return true
end

-- The marked area --------------------------------------------------------------------------------------------------------
function SpellEffects.play(extra: any)
	local effect = extra.effect
	if effect ~= "Burst" and effect ~= "Sigil" then
		return
	end
	local point = if typeof(extra.target) == "Vector3" then extra.target elseif typeof(extra.origin) == "Vector3" then extra.origin else nil
	if point == nil then
		return
	end
	local abilityId = if type(extra.ability) == "string" then extra.ability else nil
	local family = FAMILIES[(abilityId and ABILITY_FAMILY[abilityId]) or "Arcane"]
	local radius = math.clamp(tonumber(extra.radius) or 8, 2, 30)
	local windup = math.clamp(tonumber(extra.windup) or 0, 0, 5)
	local pulses: { number } = {}
	if type(extra.pulses) == "table" then
		for _, at in ipairs(extra.pulses) do
			if type(at) == "number" then
				table.insert(pulses, math.clamp(at, 0, 12))
			end
		end
	end
	if #pulses == 0 then
		pulses = { 0 }
	end
	local lastPulse = 0
	for _, at in ipairs(pulses) do
		lastPulse = math.max(lastPulse, at)
	end
	local ground = groundUnder(point)
	local sigil = effect == "Sigil"

	-- the mark: field, edge ring, closing ring (and, for sigils, the turning rune ring)
	local host = anchor(CFrame.new(ground), Vector3.new(radius * 2, 0.2, radius * 2))
	local field: Part? = nil
	if family.field then
		local disc = Instance.new("Part")
		disc.Shape = Enum.PartType.Cylinder
		disc.Material = Enum.Material.ForceField
		disc.Color = family.color
		disc.Transparency = 0.1
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Size = Vector3.new(0.1, radius * 2, radius * 2)
		disc.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = container()
		field = disc
	end
	local edge = ring(host, radius, family.color, math.clamp(radius * 0.05, 0.25, 0.7), family.glow, 0.15)
	local closing = ring(host, radius * 0.1, family.accent, math.clamp(radius * 0.03, 0.15, 0.4), family.glow, 0.35)
	local runeHost: Part? = nil
	if sigil then
		local runes = anchor(CFrame.new(ground + Vector3.new(0, 0.05, 0)))
		ring(runes, radius * 0.72, family.accent, math.clamp(radius * 0.025, 0.12, 0.35), family.glow, 0.3)
		-- eight glyph strokes between the rings
		for i = 1, 8 do
			local angle = (i - 1) / 8 * math.pi * 2
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position = Vector3.new(math.cos(angle) * radius * 0.74, 0, math.sin(angle) * radius * 0.74)
			a1.Position = Vector3.new(math.cos(angle + 0.12) * radius * 0.94, 0, math.sin(angle + 0.12) * radius * 0.94)
			a0.Parent = runes
			a1.Parent = runes
			local stroke = Instance.new("Beam")
			stroke.Attachment0 = a0
			stroke.Attachment1 = a1
			stroke.Color = ColorSequence.new(family.accent)
			stroke.LightEmission = family.glow
			stroke.Width0 = math.clamp(radius * 0.035, 0.15, 0.45)
			stroke.Width1 = 0.05
			stroke.FaceCamera = true
			stroke.Transparency = NumberSequence.new(0.25)
			stroke.Parent = runes
		end
		-- motes rising from the sigil while it charges
		local motes = emitter(host, {
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Color = ColorSequence.new(family.accent), LightEmission = family.glow, Size = NumberSequence.new(0.16, 0),
			Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(1.5, 3.5), SpreadAngle = Vector2.new(8, 8),
			Rate = math.clamp(radius * 3, 12, 50),
		})
		motes.Enabled = true
		runes.Parent = container()
		runeHost = runes
	end

	-- charge: the closing ring reaches the edge as the windup ends; sigil runes turn
	local started = os.clock()
	local total = windup + lastPulse + 0.45
	animate(total, function(alpha)
		local elapsed = os.clock() - started
		local charge = if windup > 0 then math.min(elapsed / windup, 1) else 1
		closing.setRadius(radius * (0.1 + 0.9 * charge))
		closing.setTransparency(if charge >= 1 then 1 else 0.35 - 0.2 * charge)
		if runeHost ~= nil then
			runeHost.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, elapsed * 0.8, 0)
		end
		-- fade everything over the last 0.45 s
		local remaining = total - elapsed
		if remaining < 0.45 then
			local fade = 1 - remaining / 0.45
			edge.setTransparency(0.15 + 0.85 * fade)
			if field ~= nil then
				field.Transparency = 0.1 + 0.9 * fade
			end
		end
	end, function()
		host:Destroy()
		if field ~= nil then
			field:Destroy()
		end
		if runeHost ~= nil then
			runeHost:Destroy()
		end
	end)

	-- eruptions: one per pulse (a falling model first, where the ability has one)
	local falling = abilityId and FALLING[abilityId]
	if falling ~= nil then
		local drop = math.min(0.35, math.max(windup, 0.15))
		task.delay(math.max(windup - drop, 0), fall, ground, family, falling, drop)
	end
	local erupt = ERUPTIONS[family.eruption] or ERUPTIONS.blast
	for index, at in ipairs(pulses) do
		task.delay(windup + at, function()
			-- protective domes rise once; the other families erupt on every pulse
			if family.eruption == "dome" and index > 1 then
				return
			end
			erupt(ground, radius, family, abilityId)
		end)
	end
end

return SpellEffects
