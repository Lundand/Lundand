--[[
	WorldBuilder — generates the whole map when the server starts:
	terrain for every zone, canyon walls, gates with Power requirements, decorations,
	lava/toxic hazards, the spawn plaza, leaderboards and the Endless Rift portal.

	Want to hand-edit the map? Press Play in Studio, copy Workspace.World, stop, paste it
	back into Workspace and save. If a "World" folder already exists the parts are reused
	(terrain is still generated if the ground is empty).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))

local WorldBuilder = {}

type Hazard = { pos: Vector3, radius: number, kind: string }

WorldBuilder.Hazards = {} :: { Hazard }
WorldBuilder.Gates = {} :: { [number]: BasePart }
WorldBuilder.Boards = {} :: { [string]: BasePart }
WorldBuilder.RiftPortal = nil :: BasePart?
WorldBuilder.Folder = nil :: Folder?

local W = Config.World
local rgb = Color3.fromRGB
local rng = Random.new(W.Seed)
local UP = CFrame.Angles(0, 0, math.pi / 2) -- stands a Cylinder part upright

--------------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------------
local function P(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Vertical cylinder standing on `pos`
local function vcyl(parent: Instance, name: string, pos: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return P(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos + Vector3.new(0, height / 2, 0)) * UP, color, material, collide, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return P(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material, collide, Enum.PartType.Ball)
end

local function pick(list: { any }): any
	return list[rng:NextInteger(1, #list)]
end

local function addLight(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.5
	t.Parent = parent
	return t
end
WorldBuilder.Label = label

local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pixelsPerStud
	sg.LightInfluence = 0
	sg.Adornee = part
	sg.Parent = part
	return sg
end
WorldBuilder.Surface = surface

-- Parts larger than 2048 studs are not allowed, so long walls are split up
local function invisibleWall(parent: Instance, from: Vector3, to: Vector3, thickness: number, height: number)
	local delta = to - from
	local length = delta.Magnitude
	local pieces = math.ceil(length / 1000)
	for k = 0, pieces - 1 do
		local a = from + delta * (k / pieces)
		local b = from + delta * ((k + 1) / pieces)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local p = P(parent, "Wall", Vector3.new(thickness, height, len + thickness), CFrame.lookAt(mid, b), rgb(255, 255, 255), Enum.Material.SmoothPlastic, true)
		p.Transparency = 1
		p.CanQuery = false
	end
end

-- Is there terrain (a cliff) within `radius` studs of p, up to 12 studs above the ground?
-- The ground itself ends at y = 0, so anything solid above it is a cliff or a rock.
-- Keeps trees and props from being placed inside the canyon walls.
local function nearCliff(p: Vector3, radius: number): boolean
	local region = Region3.new(Vector3.new(p.X - radius, 1, p.Z - radius), Vector3.new(p.X + radius, 12, p.Z + radius)):ExpandToGrid(4)
	local ok, materials: any, occupancies: any = pcall(function()
		return workspace.Terrain:ReadVoxels(region, 4)
	end)
	if not ok or not materials or not occupancies then
		return false
	end
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				local material = materials[x][y][z]
				if occupancies[x][y][z] > 0.1 and material ~= Enum.Material.Air and material ~= Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Decorations
--------------------------------------------------------------------------------
local function tree(m: Instance, p: Vector3, s: number, trunk: Color3, leaves: { Color3 })
	local h = 7 * s
	vcyl(m, "Trunk", p, h, 1.4 * s, trunk, Enum.Material.Wood, true)
	ball(m, "Leaves", p + Vector3.new(0, h + 1.5 * s, 0), 7 * s, pick(leaves), Enum.Material.Grass)
	ball(m, "Leaves", p + Vector3.new(1.8 * s, h, 1 * s), 5 * s, pick(leaves), Enum.Material.Grass)
	ball(m, "Leaves", p + Vector3.new(-1.6 * s, h + 0.6 * s, -1.2 * s), 5 * s, pick(leaves), Enum.Material.Grass)
end

local function pine(m: Instance, p: Vector3, s: number, trunk: Color3, leaf: Color3, snowy: boolean)
	vcyl(m, "Trunk", p, 4 * s, 1.2 * s, trunk, Enum.Material.Wood, true)
	local y = 3.4 * s
	local w = 8 * s
	for k = 1, 4 do
		local cf = CFrame.new(p + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(45 * k), 0)
		P(m, "Needles", Vector3.new(w, 2.6 * s, w), cf, leaf, Enum.Material.Grass)
		if snowy then
			P(m, "Snow", Vector3.new(w * 0.82, 0.5 * s, w * 0.82), cf * CFrame.new(0, 1.45 * s, 0), rgb(245, 250, 255), Enum.Material.Snow)
		end
		y += 2.4 * s
		w *= 0.7
	end
end

local function deadTree(m: Instance, p: Vector3, s: number, color: Color3, glow: Color3?)
	local h = 10 * s
	vcyl(m, "Trunk", p, h, 1.3 * s, color, Enum.Material.Wood, true)
	for k = 1, 3 do
		local a = rng:NextNumber() * math.pi * 2
		local cf = CFrame.new(p + Vector3.new(0, h * (0.45 + k * 0.15), 0)) * CFrame.Angles(0, a, math.rad(50)) * CFrame.new(0, 2 * s, 0)
		P(m, "Branch", Vector3.new(0.6 * s, 4 * s, 0.6 * s), cf, color, Enum.Material.Wood)
	end
	if glow then
		local g = ball(m, "Glow", p + Vector3.new(0.7 * s, h * 0.35, 0.3 * s), 0.9 * s, glow, Enum.Material.Neon)
		g.CastShadow = false
	end
end

local function rock(m: Instance, p: Vector3, size: number, color: Color3, material: Enum.Material?, collide: boolean)
	local cf = CFrame.new(p + Vector3.new(0, size * 0.22, 0)) * CFrame.Angles(rng:NextNumber() * 0.5, rng:NextNumber() * 6.28, rng:NextNumber() * 0.5)
	P(m, "Rock", Vector3.new(size, size * 0.7, size * 0.9), cf, color, material or Enum.Material.Slate, collide)
end

local function bush(m: Instance, p: Vector3, s: number, colors: { Color3 })
	for k = 1, 3 do
		local offset = Vector3.new(rng:NextNumber() * 2 - 1, 0, rng:NextNumber() * 2 - 1) * 1.6 * s
		ball(m, "Bush", p + offset + Vector3.new(0, 1.2 * s, 0), (2.4 + rng:NextNumber()) * s, pick(colors), Enum.Material.Grass)
	end
end

local function flower(m: Instance, p: Vector3, colors: { Color3 })
	P(m, "Stem", Vector3.new(0.2, 1.2, 0.2), CFrame.new(p + Vector3.new(0, 0.6, 0)), rgb(70, 150, 60), Enum.Material.Grass)
	local head = ball(m, "Petals", p + Vector3.new(0, 1.3, 0), 0.8, pick(colors), Enum.Material.SmoothPlastic)
	head.CastShadow = false
end

local function mushroom(m: Instance, p: Vector3, s: number, cap: Color3, glow: boolean)
	vcyl(m, "Stem", p, 1.6 * s, 0.7 * s, rgb(235, 230, 215), Enum.Material.SmoothPlastic, false)
	local capPart = P(m, "Cap", Vector3.new(2.4 * s, 1 * s, 2.4 * s), CFrame.new(p + Vector3.new(0, 1.8 * s, 0)), cap, glow and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = capPart
	if glow then
		addLight(capPart, cap, 12, 1.2)
	end
end

local function cactus(m: Instance, p: Vector3, s: number)
	local green = rgb(80, 150, 70)
	local h = 7 * s
	vcyl(m, "Cactus", p, h, 1.6 * s, green, Enum.Material.Grass, true)
	for _, side in { -1, 1 } do
		local y = h * (0.35 + rng:NextNumber() * 0.25)
		P(m, "Arm", Vector3.new(2 * s, 0.9 * s, 0.9 * s), CFrame.new(p + Vector3.new(side * 1.2 * s, y, 0)), green, Enum.Material.Grass)
		vcyl(m, "Arm", p + Vector3.new(side * 2 * s, y, 0), 2.6 * s, 0.9 * s, green, Enum.Material.Grass, false)
	end
end

local function crystal(m: Instance, p: Vector3, s: number, color: Color3, material: Enum.Material, collide: boolean, floatY: number?)
	local base = p + Vector3.new(0, (floatY or 0) + 3 * s, 0)
	local c = P(m, "Crystal", Vector3.new(1.6 * s, 6 * s, 1.6 * s), CFrame.new(base) * CFrame.Angles(rng:NextNumber() * 0.4, rng:NextNumber() * 6.28, rng:NextNumber() * 0.4), color, material, collide)
	c.CastShadow = false
	return c
end

local function pool(m: Instance, p: Vector3, radius: number, color: Color3, kind: string)
	local disc = P(m, "Pool", Vector3.new(0.3, radius * 2, radius * 2), CFrame.new(p + Vector3.new(0, 0.12, 0)) * UP, color, Enum.Material.Neon, false, Enum.PartType.Cylinder)
	disc.CastShadow = false
	disc:SetAttribute("Hazard", kind)
	disc:SetAttribute("Radius", radius)
	local rim = P(m, "Rim", Vector3.new(0.5, radius * 2 + 1.6, radius * 2 + 1.6), CFrame.new(p + Vector3.new(0, -0.1, 0)) * UP, kind == "lava" and rgb(40, 32, 30) or rgb(70, 70, 50), Enum.Material.Slate, false, Enum.PartType.Cylinder)
	rim.CastShadow = false
	addLight(disc, color, radius * 2.5, 1.5)
	if kind == "lava" then
		local fire = Instance.new("Fire")
		fire.Size = math.min(radius, 10)
		fire.Heat = 6
		fire.Color = rgb(255, 120, 40)
		fire.SecondaryColor = rgb(255, 60, 20)
		fire.Parent = disc
	else
		local smoke = Instance.new("Smoke")
		smoke.Color = color
		smoke.Opacity = 0.08
		smoke.RiseVelocity = 2
		smoke.Size = radius
		smoke.Parent = disc
	end
end

local function barrel(m: Instance, p: Vector3, color: Color3, top: Color3)
	vcyl(m, "Barrel", p, 3, 2, color, Enum.Material.Metal, true)
	local lid = vcyl(m, "Goo", p + Vector3.new(0, 3, 0), 0.2, 1.7, top, Enum.Material.Neon, false)
	lid.CastShadow = false
end

local function scrapPile(m: Instance, p: Vector3, s: number, colors: { Color3 })
	for k = 1, 5 do
		local size = Vector3.new(1 + rng:NextNumber() * 3, 0.5 + rng:NextNumber() * 2, 1 + rng:NextNumber() * 3) * s
		local offset = Vector3.new(rng:NextNumber() * 4 - 2, size.Y * 0.4 + k * 0.3 * s, rng:NextNumber() * 4 - 2)
		P(m, "Scrap", size, CFrame.new(p + offset) * CFrame.Angles(rng:NextNumber(), rng:NextNumber() * 6, rng:NextNumber()), pick(colors), Enum.Material.CorrodedMetal, k <= 2)
	end
end

local function obelisk(m: Instance, p: Vector3, s: number, color: Color3, glow: Color3)
	local h = 14 * s
	P(m, "Obelisk", Vector3.new(3 * s, h, 3 * s), CFrame.new(p + Vector3.new(0, h / 2, 0)), color, Enum.Material.Slate, true)
	local stripe = P(m, "Rune", Vector3.new(3.1 * s, 0.4 * s, 3.1 * s), CFrame.new(p + Vector3.new(0, h * 0.7, 0)), glow, Enum.Material.Neon)
	addLight(stripe, glow, 14, 1)
	local tip = P(m, "Tip", Vector3.new(2 * s, 2 * s, 2 * s), CFrame.new(p + Vector3.new(0, h + 0.6 * s, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color, Enum.Material.Slate)
	tip.CastShadow = true
end

local function gravestone(m: Instance, p: Vector3)
	P(m, "Grave", Vector3.new(2, 2.6, 0.6), CFrame.new(p + Vector3.new(0, 1.1, 0)) * CFrame.Angles(rng:NextNumber() * 0.2 - 0.1, rng:NextNumber() * 6, rng:NextNumber() * 0.2 - 0.1), rgb(110, 110, 120), Enum.Material.Slate, false)
end

local function bones(m: Instance, p: Vector3)
	for _ = 1, 3 do
		P(m, "Bone", Vector3.new(0.4, 0.4, 1.8), CFrame.new(p + Vector3.new(rng:NextNumber() * 2 - 1, 0.2, rng:NextNumber() * 2 - 1)) * CFrame.Angles(0, rng:NextNumber() * 6, 0), rgb(240, 235, 220), Enum.Material.SmoothPlastic, false)
	end
end

local function stepPyramid(m: Instance, p: Vector3, size: number, color: Color3)
	local y = 0
	local w = size
	while w > 4 do
		P(m, "Pyramid", Vector3.new(w, 4, w), CFrame.new(p + Vector3.new(0, y + 2, 0)), color, Enum.Material.Sandstone, true)
		y += 4
		w -= 7
	end
end

local function snowman(m: Instance, p: Vector3)
	local white = rgb(248, 250, 255)
	ball(m, "Snow", p + Vector3.new(0, 1.6, 0), 3.4, white, Enum.Material.Snow)
	ball(m, "Snow", p + Vector3.new(0, 4, 0), 2.5, white, Enum.Material.Snow)
	ball(m, "Snow", p + Vector3.new(0, 5.8, 0), 1.8, white, Enum.Material.Snow)
	P(m, "Nose", Vector3.new(0.3, 0.3, 1), CFrame.new(p + Vector3.new(0, 5.8, -1.2)), rgb(255, 140, 40))
end

--------------------------------------------------------------------------------
-- Zone decoration
--------------------------------------------------------------------------------
local function edgeSpots(i: number, count: number): { Vector3 }
	local list = {}
	local x0, x1 = Util.ZoneStartX(i) + 12, Util.ZoneEndX(i) - 12
	for k = 1, count do
		local side = k % 2 == 0 and 1 or -1
		local x = x0 + rng:NextNumber() * (x1 - x0)
		local z = 80 + rng:NextNumber() * 42
		-- step toward the middle of the zone until the spot is clear of the cliffs (never into the mob lane)
		while z >= 80 and nearCliff(Vector3.new(x, 0, side * z), 8) do
			z -= 6
		end
		if z >= 80 then
			table.insert(list, Vector3.new(x, 0, side * z))
		end
	end
	return list
end

local function centerSpots(i: number, count: number): { Vector3 }
	local list = {}
	local x0, x1 = Util.ZoneStartX(i) + 14, Util.ZoneEndX(i) - 14
	for _ = 1, count do
		table.insert(list, Vector3.new(x0 + rng:NextNumber() * (x1 - x0), 0, (rng:NextNumber() * 2 - 1) * (W.MobLaneHalfWidth + 6)))
	end
	return list
end

local DECO = {}

DECO.grasslands = function(m: Instance, i: number)
	local leaves = { rgb(96, 180, 72), rgb(120, 200, 80), rgb(80, 160, 60) }
	for _, p in edgeSpots(i, 34) do
		local roll = rng:NextNumber()
		if roll < 0.55 then
			tree(m, p, 0.9 + rng:NextNumber() * 0.6, rgb(115, 80, 50), leaves)
		elseif roll < 0.8 then
			bush(m, p, 1 + rng:NextNumber() * 0.5, leaves)
		else
			rock(m, p, 3 + rng:NextNumber() * 4, rgb(140, 140, 135), Enum.Material.Slate, true)
		end
	end
	local petals = { rgb(255, 120, 160), rgb(255, 230, 90), rgb(255, 255, 255), rgb(180, 120, 255) }
	for _, p in centerSpots(i, 55) do
		if rng:NextNumber() < 0.8 then
			flower(m, p, petals)
		else
			rock(m, p, 1 + rng:NextNumber(), rgb(150, 150, 145), Enum.Material.Slate, false)
		end
	end
end

DECO.forest = function(m: Instance, i: number)
	local leaves = { rgb(50, 120, 50), rgb(60, 140, 55), rgb(40, 100, 45) }
	for _, p in edgeSpots(i, 40) do
		local roll = rng:NextNumber()
		if roll < 0.5 then
			tree(m, p, 1.4 + rng:NextNumber() * 0.8, rgb(95, 65, 40), leaves)
		elseif roll < 0.8 then
			pine(m, p, 1.2 + rng:NextNumber() * 0.5, rgb(90, 60, 40), rgb(45, 105, 50), false)
		else
			rock(m, p, 4 + rng:NextNumber() * 4, rgb(110, 125, 105), Enum.Material.Slate, true)
		end
	end
	for _, p in centerSpots(i, 30) do
		if rng:NextNumber() < 0.6 then
			mushroom(m, p, 0.6 + rng:NextNumber() * 0.5, rgb(220, 50, 50), false)
		else
			bush(m, p, 0.6, leaves)
		end
	end
end

DECO.darkforest = function(m: Instance, i: number)
	local glows = { rgb(170, 90, 255), rgb(90, 220, 255) }
	local lights = 0
	for _, p in edgeSpots(i, 38) do
		local roll = rng:NextNumber()
		if roll < 0.6 then
			deadTree(m, p, 1.1 + rng:NextNumber() * 0.7, rgb(55, 45, 55), rng:NextNumber() < 0.3 and pick(glows) or nil)
		elseif roll < 0.8 then
			rock(m, p, 3 + rng:NextNumber() * 3, rgb(90, 90, 100), Enum.Material.Slate, true)
		else
			gravestone(m, p)
		end
	end
	for _, p in centerSpots(i, 26) do
		if rng:NextNumber() < 0.5 then
			local glow = lights < 12
			if glow then
				lights += 1
			end
			mushroom(m, p, 0.7 + rng:NextNumber() * 0.4, pick(glows), glow)
		else
			gravestone(m, p)
		end
	end
end

DECO.desert = function(m: Instance, i: number)
	for _, p in edgeSpots(i, 30) do
		local roll = rng:NextNumber()
		if roll < 0.5 then
			cactus(m, p, 0.9 + rng:NextNumber() * 0.5)
		else
			rock(m, p, 5 + rng:NextNumber() * 6, rgb(214, 165, 105), Enum.Material.Sandstone, true)
		end
	end
	for _, side in { -1, 1 } do
		local x = Util.ZoneStartX(i) + 60 + rng:NextNumber() * 180
		stepPyramid(m, Vector3.new(x, 0, side * 112), 36, rgb(222, 186, 120))
	end
	for _, p in centerSpots(i, 22) do
		if rng:NextNumber() < 0.6 then
			bones(m, p)
		else
			rock(m, p, 1.2 + rng:NextNumber(), rgb(214, 165, 105), Enum.Material.Sandstone, false)
		end
	end
end

DECO.frozen = function(m: Instance, i: number)
	for _, p in edgeSpots(i, 38) do
		local roll = rng:NextNumber()
		if roll < 0.6 then
			pine(m, p, 1.1 + rng:NextNumber() * 0.6, rgb(80, 60, 45), rgb(40, 90, 70), true)
		elseif roll < 0.85 then
			crystal(m, p, 1 + rng:NextNumber() * 0.8, rgb(170, 220, 255), Enum.Material.Ice, true)
		else
			rock(m, p, 4 + rng:NextNumber() * 3, rgb(200, 220, 235), Enum.Material.Glacier, true)
		end
	end
	for k, p in centerSpots(i, 20) do
		if k <= 2 then
			snowman(m, p)
		else
			ball(m, "Drift", p + Vector3.new(0, 0.3, 0), 2 + rng:NextNumber() * 2, rgb(245, 250, 255), Enum.Material.Snow)
		end
	end
end

DECO.volcano = function(m: Instance, i: number)
	for _, p in edgeSpots(i, 32) do
		local roll = rng:NextNumber()
		if roll < 0.5 then
			local h = 6 + rng:NextNumber() * 14
			vcyl(m, "Basalt", p, h, 3 + rng:NextNumber() * 3, rgb(45, 40, 40), Enum.Material.Basalt, true)
		else
			local spike = Instance.new("WedgePart")
			spike.Name = "Obsidian"
			spike.Anchored = true
			spike.Size = Vector3.new(2, 6 + rng:NextNumber() * 6, 3)
			spike.CFrame = CFrame.new(p + Vector3.new(0, spike.Size.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * 6, 0)
			spike.Color = rgb(25, 20, 30)
			spike.Material = Enum.Material.Glass
			spike.Parent = m
		end
	end
	-- a volcano on the horizon
	local cx = (Util.ZoneStartX(i) + Util.ZoneEndX(i)) / 2
	local base = Vector3.new(cx, 0, 230)
	local d = 150
	local y = 0
	for _ = 1, 6 do
		vcyl(m, "Mountain", base + Vector3.new(0, y, 0), 16, d, rgb(55, 45, 42), Enum.Material.Basalt, false)
		y += 16
		d *= 0.78
	end
	local crater = vcyl(m, "Crater", base + Vector3.new(0, y, 0), 1, d * 0.8, rgb(255, 110, 30), Enum.Material.Neon, false)
	addLight(crater, rgb(255, 110, 30), 60, 3)
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(60, 50, 50)
	smoke.Size = 40
	smoke.RiseVelocity = 12
	smoke.Opacity = 0.3
	smoke.Parent = crater
	-- lava pools (hazards)
	for _, p in centerSpots(i, 7) do
		pool(m, p, 6 + rng:NextNumber() * 5, rgb(255, 110, 30), "lava")
	end
end

DECO.wasteland = function(m: Instance, i: number)
	local metal = { rgb(140, 80, 50), rgb(110, 110, 115), rgb(160, 110, 60) }
	for _, p in edgeSpots(i, 32) do
		local roll = rng:NextNumber()
		if roll < 0.4 then
			scrapPile(m, p, 1 + rng:NextNumber() * 0.6, metal)
		elseif roll < 0.65 then
			barrel(m, p, pick({ rgb(200, 170, 40), rgb(90, 120, 60) }), rgb(170, 255, 60))
		elseif roll < 0.85 then
			deadTree(m, p, 1 + rng:NextNumber() * 0.5, rgb(90, 85, 80), nil)
		else
			P(m, "Ruin", Vector3.new(4, 6 + rng:NextNumber() * 10, 12), CFrame.new(p + Vector3.new(0, 4, 0)) * CFrame.Angles(0, rng:NextNumber() * 6, rng:NextNumber() * 0.2), rgb(150, 145, 135), Enum.Material.Concrete, true)
		end
	end
	for _, p in centerSpots(i, 7) do
		pool(m, p, 5 + rng:NextNumber() * 5, rgb(150, 255, 60), "toxic")
	end
	for _, p in centerSpots(i, 12) do
		scrapPile(m, p, 0.4, metal)
	end
end

DECO.void = function(m: Instance, i: number)
	local lights = 0
	for _, p in edgeSpots(i, 30) do
		local roll = rng:NextNumber()
		if roll < 0.45 then
			obelisk(m, p, 0.9 + rng:NextNumber() * 0.6, rgb(20, 15, 30), rgb(180, 90, 255))
		elseif roll < 0.8 then
			local c = crystal(m, p, 1 + rng:NextNumber(), rgb(170, 80, 255), Enum.Material.Neon, false, 4 + rng:NextNumber() * 8)
			if lights < 10 then
				lights += 1
				addLight(c, rgb(170, 80, 255), 16, 1.2)
			end
		else
			rock(m, p + Vector3.new(0, 6 + rng:NextNumber() * 10, 0), 4 + rng:NextNumber() * 4, rgb(40, 30, 60), Enum.Material.Slate, false)
		end
	end
	for _, p in centerSpots(i, 14) do
		local rift = P(m, "RiftMark", Vector3.new(0.2, 4 + rng:NextNumber() * 4, 4 + rng:NextNumber() * 4), CFrame.new(p + Vector3.new(0, 0.1, 0)) * UP, rgb(10, 5, 20), Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
		rift.CastShadow = false
	end
end

--------------------------------------------------------------------------------
-- Gates
--------------------------------------------------------------------------------
local function buildGate(parent: Instance, i: number)
	local zone = Config.Zones[i]
	local x = Util.ZoneStartX(i)
	local gate = Instance.new("Model")
	gate.Name = "Gate" .. i
	local stone = zone.cliffColor:Lerp(rgb(90, 90, 95), 0.4)
	for _, side in { -1, 1 } do
		P(gate, "Pillar", Vector3.new(7, 38, 7), CFrame.new(x, 19, side * 74), stone, Enum.Material.Cobblestone, true)
		local torch = ball(gate, "Torch", Vector3.new(x, 40, side * 74), 3, zone.coreColor, Enum.Material.Neon)
		addLight(torch, zone.coreColor, 28, 2)
	end
	local beam = P(gate, "Sign", Vector3.new(6, 9, 156), CFrame.new(x, 40, 0), rgb(35, 35, 45), Enum.Material.SmoothPlastic, true)

	local front = surface(beam, Enum.NormalId.Left, 12)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = front
	label(frame, "▲ " .. string.upper(zone.name) .. " ▲", UDim2.new(1, 0, 0.55, 0), UDim2.new(0, 0, 0.02, 0), zone.coreColor)
	local req = Items.Required(i)
	local info = i == 1 and ("Recommended Power: " .. Util.Abbrev(zone.rec))
		or ("⚡ Required Power: " .. Util.Abbrev(req) .. "   •   Recommended: " .. Util.Abbrev(zone.rec))
	if zone.pvp and Config.PvP.Mode ~= "Off" then
		info ..= "   •   ⚠ CONTESTED: Cores can be stolen here"
	end
	label(frame, info, UDim2.new(1, 0, 0.35, 0), UDim2.new(0, 0, 0.6, 0), rgb(255, 255, 255))

	local back = surface(beam, Enum.NormalId.Right, 12)
	label(back, "▲ " .. string.upper(i == 1 and "Spawn & Bases" or Config.Zones[i - 1].name) .. " ▲", UDim2.fromScale(1, 1), UDim2.new(), rgb(220, 220, 230))

	if i >= 2 then
		local barrier = P(gate, "Barrier", Vector3.new(1.5, 90, W.ZoneHalfWidth * 2 + 12), CFrame.new(x, 45, 0), zone.coreColor, Enum.Material.ForceField, false)
		barrier.Transparency = 0.2
		barrier.CanQuery = false
		barrier.CastShadow = false
		barrier:SetAttribute("Zone", i)
		barrier:SetAttribute("Required", req)
	end
	gate.Parent = parent
end

--------------------------------------------------------------------------------
-- Spawn plaza, boards, avenue
-- Floor layers use clearly different heights so no two surfaces ever flicker.
--------------------------------------------------------------------------------
local STONE = rgb(226, 220, 205)
local DARK_STONE = rgb(92, 96, 110)
local WOOD = rgb(196, 160, 110)
local GOLD = rgb(214, 172, 80)

-- Leaderboard kiosk: stone plinth, marble pillars, framed board, tiled roof
local function buildBoard(parent: Instance, name: string, pos: Vector3, facing: Vector3, title: string, color: Color3): BasePart
	local cf = CFrame.lookAt(pos, pos + facing)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	P(parent, "Plinth", Vector3.new(24, 1.2, 3.4), at(0, 0.6, 0), DARK_STONE, Enum.Material.Slate, true)
	for _, side in { -1, 1 } do
		P(parent, "Pillar", Vector3.new(1.6, 13.6, 1.6), at(side * 11.4, 8, 0), rgb(236, 232, 224), Enum.Material.Marble, true)
		P(parent, "PillarCap", Vector3.new(2.2, 0.6, 2.2), at(side * 11.4, 15.1, 0), GOLD, Enum.Material.SmoothPlastic, true)
	end
	local board = P(parent, name, Vector3.new(21.2, 11.6, 0.6), at(0, 8, 0), rgb(26, 30, 46), Enum.Material.SmoothPlastic, true)
	P(parent, "Frame", Vector3.new(21.8, 0.5, 0.9), at(0, 14.05, 0), GOLD, Enum.Material.SmoothPlastic, false)
	P(parent, "Frame", Vector3.new(21.8, 0.5, 0.9), at(0, 1.95, 0), GOLD, Enum.Material.SmoothPlastic, false)
	local glow = P(parent, "Glow", Vector3.new(21, 0.22, 0.25), at(0, 14.42, -0.3), color, Enum.Material.Neon, false)
	glow.CastShadow = false
	P(parent, "Roof", Vector3.new(26, 0.9, 4.4), at(0, 15.85, 0), rgb(170, 84, 60), Enum.Material.ClayRoofTiles, true)
	local sg = surface(board, Enum.NormalId.Front, 25)
	sg.Name = "Display"
	local titleLabel = label(sg, title, UDim2.new(1, 0, 0.15, 0), UDim2.new(0, 0, 0.02, 0), color)
	titleLabel.Name = "Title"
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(0.92, 0, 0.8, 0)
	list.Position = UDim2.new(0.04, 0, 0.19, 0)
	list.Parent = sg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = list
	return board
end

local function lantern(parent: Instance, p: Vector3)
	vcyl(parent, "LanternPost", p, 9, 0.6, rgb(45, 45, 55), Enum.Material.Metal, true)
	local glass = P(parent, "Lantern", Vector3.new(1.6, 2.1, 1.6), CFrame.new(p + Vector3.new(0, 10, 0)), rgb(255, 225, 160), Enum.Material.Glass, false)
	glass.Transparency = 0.25
	local flame = P(parent, "Flame", Vector3.new(0.7, 1.1, 0.7), CFrame.new(p + Vector3.new(0, 10, 0)), rgb(255, 205, 120), Enum.Material.Neon, false)
	flame.CastShadow = false
	P(parent, "LanternCap", Vector3.new(2.1, 0.4, 2.1), CFrame.new(p + Vector3.new(0, 11.25, 0)), rgb(45, 45, 55), Enum.Material.Metal, false)
	addLight(flame, rgb(255, 215, 150), 22, 1.1)
end

local function planter(parent: Instance, p: Vector3, lookAt: Vector3)
	local cf = CFrame.lookAt(p, Vector3.new(lookAt.X, p.Y, lookAt.Z))
	P(parent, "Planter", Vector3.new(9, 1.4, 3.6), cf * CFrame.new(0, 0.7, 0), rgb(165, 95, 72), Enum.Material.Brick, true)
	P(parent, "Soil", Vector3.new(8.4, 0.3, 3), cf * CFrame.new(0, 1.45, 0), rgb(96, 170, 70), Enum.Material.Grass, false)
	local petals = { rgb(255, 120, 160), rgb(255, 230, 90), rgb(255, 255, 255), rgb(180, 120, 255), rgb(255, 150, 70) }
	for k = -2, 2 do
		local bloom = ball(parent, "Bloom", (cf * CFrame.new(k * 1.6, 2.05, (k % 2 == 0) and 0.5 or -0.5)).Position, 1.1, petals[k + 3], Enum.Material.SmoothPlastic)
		bloom.CastShadow = false
	end
end

local function bench(parent: Instance, p: Vector3, lookAt: Vector3)
	local cf = CFrame.lookAt(p, Vector3.new(lookAt.X, p.Y, lookAt.Z))
	P(parent, "Seat", Vector3.new(5, 0.35, 1.6), cf * CFrame.new(0, 1.55, 0), WOOD, Enum.Material.WoodPlanks, true)
	P(parent, "Back", Vector3.new(5, 1.3, 0.3), cf * CFrame.new(0, 2.35, 0.75), WOOD, Enum.Material.WoodPlanks, true)
	for _, side in { -1, 1 } do
		P(parent, "Leg", Vector3.new(0.4, 1.0, 1.4), cf * CFrame.new(side * 2, 0.95, 0), rgb(45, 45, 55), Enum.Material.Metal, true)
	end
end

-- Overhead gate across the avenue: "YOUR BASE" readable from the plaza, "SPAWN & ZONES" from the bases
local function basesGate(parent: Instance, x: number)
	local stone = rgb(236, 232, 224)
	for _, side in { -1, 1 } do
		P(parent, "GatePlinth", Vector3.new(3.6, 1.2, 3.6), CFrame.new(x, 0.6, side * 15.5), DARK_STONE, Enum.Material.Slate, true)
		P(parent, "GatePillar", Vector3.new(2.6, 14.7, 2.6), CFrame.new(x, 7.55, side * 15.5), stone, Enum.Material.Marble, true)
		ball(parent, "GateOrb", Vector3.new(x, 20.1, side * 15.5), 1.6, rgb(120, 200, 255), Enum.Material.Neon).CastShadow = false
	end
	local board = P(parent, "GateBoard", Vector3.new(1.4, 4.4, 34), CFrame.new(x, 16.6, 0), rgb(30, 34, 50), Enum.Material.SmoothPlastic, true)
	P(parent, "GateTrim", Vector3.new(1.8, 0.5, 34.6), CFrame.new(x, 19.05, 0), GOLD, Enum.Material.SmoothPlastic, true)
	P(parent, "GateTrim", Vector3.new(1.8, 0.5, 34.6), CFrame.new(x, 14.15, 0), GOLD, Enum.Material.SmoothPlastic, true)
	-- Right face (+X) looks at the plaza, Left face (-X) looks down the avenue
	local toBases = surface(board, Enum.NormalId.Right, 24)
	label(toBases, "🏠 BASES ▲", UDim2.new(1, 0, 0.62, 0), UDim2.new(0, 0, 0.04, 0), rgb(120, 200, 255))
	label(toBases, "Bring your Cores home here", UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.66, 0), rgb(235, 235, 240), Enum.Font.GothamBold)
	local toZones = surface(board, Enum.NormalId.Left, 24)
	label(toZones, "▲ SPAWN & ZONES ▲", UDim2.new(1, 0, 0.62, 0), UDim2.new(0, 0, 0.04, 0), rgb(140, 225, 100))
	label(toZones, "Fight monsters to find Cores", UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.66, 0), rgb(235, 235, 240), Enum.Font.GothamBold)
	for _, side in { -1, 1 } do
		local glow = P(parent, "GateLamp", Vector3.new(0.8, 1.2, 0.8), CFrame.new(x + 1.7, 10.5, side * 15.5), rgb(255, 214, 150), Enum.Material.Neon, false)
		glow.CastShadow = false
		addLight(glow, rgb(255, 214, 150), 18, 1)
	end
end

local function buildSpawn(parent: Instance)
	local f = Instance.new("Folder")
	f.Name = "Spawn"
	f.Parent = parent
	local C = W.SpawnPos

	-- floor layers: rim 0.30, avenue/path 0.45, plaza 0.55, inner circle 0.70, mosaic 0.72, spawn pad 0.90
	local rim = P(f, "PlazaRim", Vector3.new(1, 100, 100), CFrame.new(C.X, -0.2, C.Z) * UP, DARK_STONE, Enum.Material.Slate, true, Enum.PartType.Cylinder)
	rim.CastShadow = false
	local plaza = P(f, "Plaza", Vector3.new(1, 92, 92), CFrame.new(C.X, 0.05, C.Z) * UP, STONE, Enum.Material.CeramicTiles, true, Enum.PartType.Cylinder)
	plaza.CastShadow = false
	local inner = P(f, "InnerCircle", Vector3.new(0.3, 30, 30), CFrame.new(C.X, 0.55, C.Z) * UP, rgb(240, 238, 232), Enum.Material.Marble, true, Enum.PartType.Cylinder)
	inner.CastShadow = false
	for k = 0, 15 do
		local a = (k + 0.5) / 16 * math.pi * 2
		local pos = Vector3.new(C.X + math.cos(a) * 24, 0.63, C.Z + math.sin(a) * 24)
		local rarity = Config.Rarities[k % 8 + 1]
		local tile = P(f, "Mosaic", Vector3.new(8.8, 0.18, 2.4), CFrame.lookAt(pos, Vector3.new(C.X, 0.63, C.Z)), rarity.secret and rgb(200, 120, 255) or rarity.color, Enum.Material.Neon, false)
		tile.Transparency = 0.35
		tile.CastShadow = false
	end

	-- paths: east to the Grasslands gate, west down the avenue of bases
	local function path(name: string, fromX: number, toX: number, width: number)
		local len = toX - fromX
		local mid = (fromX + toX) / 2
		local floor = P(f, name, Vector3.new(len, 0.6, width), CFrame.new(mid, 0.15, 0), rgb(172, 166, 158), Enum.Material.Cobblestone, true)
		floor.CastShadow = false
		for _, side in { -1, 1 } do
			P(f, name .. "Border", Vector3.new(len, 0.8, 1.2), CFrame.new(mid, 0.5, side * (width / 2 + 0.6)), DARK_STONE, Enum.Material.Slate, true)
		end
	end
	path("Path", C.X + 40, W.GateX + 22, 22)
	path("Avenue", -350, C.X - 40, 24)

	-- fountain with the Great Core floating above it
	local basinFloor = P(f, "BasinFloor", Vector3.new(0.6, 21, 21), CFrame.new(C.X, 0.7, C.Z) * UP, rgb(205, 200, 190), Enum.Material.Marble, true, Enum.PartType.Cylinder)
	basinFloor.CastShadow = false
	for k = 0, 19 do
		local a = k / 20 * math.pi * 2
		local pos = Vector3.new(C.X + math.cos(a) * 10.5, 1.8, C.Z + math.sin(a) * 10.5)
		local look = CFrame.lookAt(pos, Vector3.new(C.X, 1.8, C.Z))
		P(f, "BasinWall", Vector3.new(3.4, 2.2, 1.1), look, rgb(232, 228, 220), Enum.Material.Marble, true)
		P(f, "BasinLedge", Vector3.new(3.6, 0.3, 1.6), look * CFrame.new(0, 1.25, 0), rgb(244, 241, 235), Enum.Material.Marble, true)
	end
	local water = P(f, "Water", Vector3.new(0.25, 20, 20), CFrame.new(C.X, 2.325, C.Z) * UP, rgb(80, 170, 255), Enum.Material.Glass, false, Enum.PartType.Cylinder)
	water.Transparency = 0.3
	water.CastShadow = false
	vcyl(f, "Column", Vector3.new(C.X, 1, C.Z), 8.2, 2.8, rgb(236, 232, 224), Enum.Material.Marble, true)
	P(f, "UpperBowl", Vector3.new(0.9, 8, 8), CFrame.new(C.X, 9.15, C.Z) * UP, rgb(236, 232, 224), Enum.Material.Marble, true, Enum.PartType.Cylinder)
	local upperWater = P(f, "UpperWater", Vector3.new(0.2, 7, 7), CFrame.new(C.X, 9.7, C.Z) * UP, rgb(80, 170, 255), Enum.Material.Glass, false, Enum.PartType.Cylinder)
	upperWater.Transparency = 0.3

	local great = Instance.new("Model")
	great.Name = "GreatCore"
	local coreCenter = Vector3.new(C.X, 15, C.Z)
	local heart = P(great, "Heart", Vector3.new(4.2, 4.2, 4.2), CFrame.new(coreCenter), rgb(110, 220, 255), Enum.Material.Neon, false, Enum.PartType.Ball)
	heart.CastShadow = false
	local shell = P(great, "Shell", Vector3.new(5.8, 5.8, 5.8), CFrame.new(coreCenter), rgb(170, 235, 255), Enum.Material.Glass, false, Enum.PartType.Ball)
	shell.Transparency = 0.55
	shell.CastShadow = false
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		local bit = P(great, "Orbit", Vector3.new(0.6, 0.6, 0.6), CFrame.new(coreCenter + Vector3.new(math.cos(a) * 4.6, math.sin(a * 2) * 0.4, math.sin(a) * 4.6)), rgb(255, 205, 80), Enum.Material.Neon, false)
		bit.CastShadow = false
	end
	great.PrimaryPart = heart
	addLight(heart, rgb(120, 220, 255), 40, 2)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(rgb(170, 235, 255))
	sparkle.LightEmission = 1
	sparkle.Rate = 12
	sparkle.Lifetime = NumberRange.new(1, 2)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = heart
	local title = Instance.new("BillboardGui")
	title.Name = "Title"
	title.Size = UDim2.new(46, 0, 9, 0)
	title.StudsOffset = Vector3.new(0, 7.5, 0)
	title.MaxDistance = 450
	title.LightInfluence = 0
	title.Adornee = heart
	local titleLabel = label(title, Config.GameName, UDim2.fromScale(1, 1), UDim2.new(), rgb(255, 214, 90))
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = rgb(70, 40, 10)
	title.Parent = great
	great:SetAttribute("SpinSpeed", 0.5)
	great.Parent = f
	CollectionService:AddTag(great, "Spin")

	-- spawn point: an invisible SpawnLocation under a glowing pad, facing the zones
	local spawnPos = Vector3.new(C.X + 16, 0, C.Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(9, 0.4, 9)
	spawn.CFrame = CFrame.lookAt(Vector3.new(spawnPos.X, 0.45, spawnPos.Z), Vector3.new(spawnPos.X + 10, 0.45, spawnPos.Z))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.Parent = f
	local pad = P(f, "SpawnPad", Vector3.new(0.2, 8.5, 8.5), CFrame.new(spawnPos.X, 0.8, spawnPos.Z) * UP, rgb(130, 205, 255), Enum.Material.Neon, false, Enum.PartType.Cylinder)
	pad.Transparency = 0.5
	pad.CastShadow = false

	-- lanterns, planters, benches
	for k = 0, 7 do
		if k ~= 3 and k ~= 4 then -- 157.5° and 202.5° flank the avenue, where the BASES gate stands
			local a = (k + 0.5) / 8 * math.pi * 2
			lantern(f, Vector3.new(C.X + math.cos(a) * 48.5, 0.3, C.Z + math.sin(a) * 48.5))
		end
	end
	for _, deg in { 45, 135, 225, 315 } do
		local a = math.rad(deg)
		planter(f, Vector3.new(C.X + math.cos(a) * 38, 0.55, C.Z + math.sin(a) * 38), C)
		bench(f, Vector3.new(C.X + math.cos(a) * 32, 0.55, C.Z + math.sin(a) * 32), C)
	end
	for x = -348, -60, 72 do -- the gaps between bases (bases are 64 wide, every 72 studs)
		for _, side in { -1, 1 } do
			lantern(f, Vector3.new(x, 0, side * 16.5))
		end
	end
	for _, side in { -1, 1 } do
		lantern(f, Vector3.new(C.X + 54, 0, side * 15.5))
	end

	-- leaderboards on the north side, how-to-play on the south side (both face the plaza)
	WorldBuilder.Boards.zone = buildBoard(f, "Board_Zone", Vector3.new(C.X - 26, 0, C.Z - 58), Vector3.new(0, 0, 1), "🏔 HIGHEST ZONE", rgb(120, 220, 255))
	WorldBuilder.Boards.power = buildBoard(f, "Board_Power", Vector3.new(C.X, 0, C.Z - 58), Vector3.new(0, 0, 1), "⚡ MOST POWER", rgb(255, 210, 70))
	WorldBuilder.Boards.rarest = buildBoard(f, "Board_Rarest", Vector3.new(C.X + 26, 0, C.Z - 58), Vector3.new(0, 0, 1), "💎 RAREST CORE FOUND", rgb(200, 120, 255))
	local how = buildBoard(f, "HowToPlay", Vector3.new(C.X, 0, C.Z + 58), Vector3.new(0, 0, -1), "HOW TO PLAY", rgb(120, 255, 160))
	local display = how:FindFirstChild("Display")
	local list = display and display:FindFirstChild("List")
	if list then
		for idx, line in Config.HowToPlay do
			local t = label(list, line, UDim2.new(1, 0, 1 / #Config.HowToPlay - 0.006, 0), UDim2.new(), rgb(235, 235, 240), Enum.Font.GothamBold)
			t.LayoutOrder = idx
			t.TextXAlignment = Enum.TextXAlignment.Left
		end
	end

	basesGate(f, 12)

	-- trees framing the plaza: by the path to the zones, behind the leaderboards and the how-to board
	local leaves = { rgb(96, 180, 72), rgb(120, 200, 80), rgb(80, 160, 60) }
	local plazaTrees = {
		Vector3.new(C.X + 52, 0, 40),
		Vector3.new(C.X + 52, 0, -44),
		Vector3.new(20, 0, 60),
		Vector3.new(20, 0, -72),
		Vector3.new(46, 0, -75),
		Vector3.new(71, 0, -72),
		Vector3.new(96, 0, -75),
		Vector3.new(44, 0, 74),
		Vector3.new(72, 0, 74),
	}
	for _, pos in plazaTrees do
		tree(f, pos, 1.3, rgb(115, 80, 50), leaves)
	end
	-- trees behind the bases, moved in front of the rocks (never closer than 112: the bases end at 104)
	for x = -330, 100, 26 do
		for _, side in { -1, 1 } do
			local px = x + rng:NextNumber() * 8
			local z = 116 + rng:NextNumber() * 8
			local scale = 1 + rng:NextNumber() * 0.5
			while z >= 112 and nearCliff(Vector3.new(px, 0, side * z), 7) do
				z -= 2
			end
			if z >= 112 then
				tree(f, Vector3.new(px, 0, side * z), scale, rgb(115, 80, 50), leaves)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Endless Rift portal at the end of the Void
--------------------------------------------------------------------------------
local function buildRiftPortal(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Rift"
	folder.Parent = parent
	local pos = Util.RiftPortalPos()
	local color = Config.Rift.CoreColor
	local center = pos + Vector3.new(0, 12, 0)
	for k = 0, 17 do
		local a = k * math.pi * 2 / 18
		local seg = P(folder, "Ring", Vector3.new(2, 2, 3.4), CFrame.new(center + Vector3.new(0, math.cos(a) * 10, math.sin(a) * 10)) * CFrame.Angles(a, 0, 0), color, Enum.Material.Neon, false)
		seg.CastShadow = false
	end
	local disc = P(folder, "Disc", Vector3.new(0.6, 19, 19), CFrame.new(center), color, Enum.Material.ForceField, false, Enum.PartType.Cylinder)
	disc.CastShadow = false
	addLight(disc, color, 40, 3)
	local base = vcyl(folder, "PortalBase", pos + Vector3.new(0, -0.5, 0), 1.5, 26, rgb(30, 30, 50), Enum.Material.Slate, true)
	base.CastShadow = false

	local anchor = P(folder, "RiftPortal", Vector3.new(2, 2, 2), CFrame.new(pos + Vector3.new(-4, 4, 0)), color, Enum.Material.SmoothPlastic, false)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Enter the Endless Rift"
	prompt.ObjectText = "∞ ENDLESS RIFT"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	WorldBuilder.RiftPortal = anchor

	local sign = P(folder, "RiftSign", Vector3.new(1, 5, 30), CFrame.new(center + Vector3.new(0, 15, 0)), rgb(20, 20, 35), Enum.Material.SmoothPlastic, false)
	label(surface(sign, Enum.NormalId.Left, 20), "∞ ENDLESS RIFT  •  Zone " .. Config.Rift.StartZone .. "+", UDim2.fromScale(1, 1), UDim2.new(), color)

	local pad = vcyl(folder, "ReturnPad", Util.RiftReturnPos() - Vector3.new(0, 4.3, 0), 0.6, 12, color, Enum.Material.Neon, true)
	pad.CastShadow = false
end

--------------------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------------------
local function terrainIsEmpty(): boolean
	local region = Region3.new(Vector3.new(W.SpawnPos.X - 4, -8, -4), Vector3.new(W.SpawnPos.X + 4, 0, 4)):ExpandToGrid(4)
	local materials = workspace.Terrain:ReadVoxels(region, 4)
	local size = materials.Size
	for x = 1, size.X do
		for y = 1, size.Y do
			for z = 1, size.Z do
				if materials[x][y][z] ~= Enum.Material.Air then
					return false
				end
			end
		end
	end
	return true
end

local function buildTerrain()
	local T = workspace.Terrain
	local trng = Random.new(W.Seed + 99)
	for _, zone in Config.Zones do
		T:SetMaterialColor(zone.ground, zone.groundColor)
		T:SetMaterialColor(zone.cliff, zone.cliffColor)
	end
	-- base / spawn area
	T:FillBlock(CFrame.new((-380 + W.GateX) / 2, -8, 0), Vector3.new(W.GateX + 384, 16, 300), Enum.Material.Grass)
	for x = -380, W.GateX, 22 do
		for _, side in { -1, 1 } do
			T:FillBall(Vector3.new(x + trng:NextNumber() * 10, -6 + trng:NextNumber() * 8, side * (W.ZoneHalfWidth + 8 + trng:NextNumber() * 10)), 16 + trng:NextNumber() * 12, Enum.Material.Rock)
		end
	end
	for z = -150, 150, 20 do
		T:FillBall(Vector3.new(-384 - trng:NextNumber() * 6, -4 + trng:NextNumber() * 6, z), 22 + trng:NextNumber() * 8, Enum.Material.Rock)
	end
	-- zones
	for i, zone in Config.Zones do
		local x0, x1 = Util.ZoneStartX(i), Util.ZoneEndX(i)
		T:FillBlock(CFrame.new((x0 + x1) / 2, -8, 0), Vector3.new(W.ZoneLength + 4, 16, 300), zone.ground)
		for x = x0, x1, 22 do
			for _, side in { -1, 1 } do
				T:FillBall(Vector3.new(x + trng:NextNumber() * 10, -6 + trng:NextNumber() * 8, side * (W.ZoneHalfWidth + 6 + trng:NextNumber() * 10)), 16 + trng:NextNumber() * 14, zone.cliff)
			end
		end
	end
	-- the end of the world
	local last = Config.Zones[#Config.Zones]
	for z = -150, 150, 18 do
		T:FillBall(Vector3.new(Util.WorldEndX() + 14 + trng:NextNumber() * 6, 0, z), 24 + trng:NextNumber() * 8, last.cliff)
	end
end

--------------------------------------------------------------------------------
-- Lighting defaults (the client blends per zone)
--------------------------------------------------------------------------------
local function setupLighting()
	local l = Config.SpawnLight
	Lighting.ClockTime = l.clock
	Lighting.Ambient = l.ambient
	Lighting.OutdoorAmbient = l.outdoor
	Lighting.FogColor = l.fog
	Lighting.FogEnd = l.fogEnd
	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
		return inst
	end
	local atmo = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmo.Density = l.density
	atmo.Color = l.atmo
	atmo.Decay = l.atmo:Lerp(Color3.new(0, 0, 0), 0.4)
	atmo.Haze = 1.2
	atmo.Glare = 0.2
	local cc = ensure("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.TintColor = l.tint
	cc.Saturation = l.sat
	cc.Contrast = 0.08
	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.7
	bloom.Size = 26
	bloom.Threshold = 1.5
	local rays = ensure("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.8
end

--------------------------------------------------------------------------------
-- Collect references (works for generated and hand-edited worlds)
--------------------------------------------------------------------------------
local function collect(folder: Instance)
	table.clear(WorldBuilder.Hazards)
	table.clear(WorldBuilder.Gates)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local hazard = d:GetAttribute("Hazard")
			if type(hazard) == "string" then
				table.insert(WorldBuilder.Hazards, { pos = d.Position, radius = tonumber(d:GetAttribute("Radius")) or 6, kind = hazard })
			end
			local zone = d:GetAttribute("Zone")
			if d.Name == "Barrier" and type(zone) == "number" then
				WorldBuilder.Gates[zone] = d
			end
			if d.Name == "Board_Zone" then
				WorldBuilder.Boards.zone = d
			elseif d.Name == "Board_Power" then
				WorldBuilder.Boards.power = d
			elseif d.Name == "Board_Rarest" then
				WorldBuilder.Boards.rarest = d
			elseif d.Name == "RiftPortal" then
				WorldBuilder.RiftPortal = d
			end
		end
	end
end

local function registerGroup(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

function WorldBuilder.Init(_services: any)
	registerGroup("Players")
	registerGroup("Mobs")
	PhysicsService:CollisionGroupSetCollidable("Mobs", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Mobs", "Mobs", false)
end

function WorldBuilder.Start()
	local started = os.clock()
	setupLighting()
	if terrainIsEmpty() then
		buildTerrain()
	end

	local existing = workspace:FindFirstChild("World")
	if existing and existing:IsA("Folder") then
		WorldBuilder.Folder = existing
		collect(existing)
		print(string.format("[World] Using existing World folder (%.2fs)", os.clock() - started))
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "World"
	WorldBuilder.Folder = folder

	buildSpawn(folder)
	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = folder
	for i, zone in Config.Zones do
		local m = Instance.new("Folder")
		m.Name = "Zone" .. i
		m.Parent = zonesFolder
		local deco = DECO[zone.deco]
		if deco then
			deco(m, i)
		end
		buildGate(m, i)
	end
	buildRiftPortal(folder)

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = folder
	local minX, maxX = -360, Util.WorldEndX() + 6
	local hz = W.ZoneHalfWidth + 6
	invisibleWall(walls, Vector3.new(minX, 150, hz), Vector3.new(maxX, 150, hz), 4, 300)
	invisibleWall(walls, Vector3.new(minX, 150, -hz), Vector3.new(maxX, 150, -hz), 4, 300)
	invisibleWall(walls, Vector3.new(minX, 150, -hz), Vector3.new(minX, 150, hz), 4, 300)
	invisibleWall(walls, Vector3.new(maxX, 150, -hz), Vector3.new(maxX, 150, hz), 4, 300)

	folder.Parent = workspace
	collect(folder)
	print(string.format("[World] Generated in %.2fs", os.clock() - started))
end

-- Height of the ground at (x, z)
function WorldBuilder.GroundY(x: number, z: number, ignore: { Instance }?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	local result = workspace:Raycast(Vector3.new(x, 250, z), Vector3.new(0, -500, 0), params)
	return result and result.Position.Y or 0
end

return WorldBuilder
