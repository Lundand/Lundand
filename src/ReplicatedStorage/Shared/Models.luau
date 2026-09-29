--[[
	Models — builds every procedural model in the game out of plain Parts (no meshes, no animation assets).

	MOBS   Models.Mob(def, tier, scale) -> model, root, humanoid, height
	       Five archetypes (biped / quad / blob / floater / bug); body styles and features come from the
	       visual fields in Config.Mobs. Motor6D joints the client animates (MobAnim.luau), by name:
	         biped    Waist Neck LeftHip RightHip LeftShoulder RightShoulder   (+ Jaw Tail LeftWing RightWing Cape)
	         quad     Body Neck LegFL LegFR LegBL LegBR TailJoint              (+ Jaw Tail2)
	         blob     Body
	         floater  Body Spin                                                (+ Tail Tent1..Tent6 LeftArm RightArm)
	         bug      Body Leg1..Leg6 TailJoint                                (+ Tail2 Tail3 ClawL ClawR)
	       Elites get armour trim and a faint aura; bosses a crown/crest, heavy armour, glow and a light.
	WEAPONS Models.Weapon(key) — Handle origin = grip point, blade along +Y (see the WEAPONS section).
	TROPHIES Models.ClassEmblem(key), Models.AbilityTome(key) (pedestal displays), Models.Orb(color, size)
	CORES  Models.Core(z, r, scale)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local Models = {}

local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rgb = Color3.fromRGB
local PI = math.pi
local SIDES = { -1, 1 }
local MAT = Enum.Material

local GOLD = rgb(255, 205, 60)
local BONE = rgb(236, 228, 206)
local INK = rgb(24, 20, 28)
local WHITE = rgb(250, 250, 248)
local IRON = rgb(92, 95, 106)
local LEATHER = rgb(92, 62, 42)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local UPRIGHT = ANG(0, 0, PI / 2) -- turns a Cylinder's axis (local X) upright
local FACING = ANG(0, PI / 2, 0) -- turns a Cylinder's axis along Z (a disc facing forward)

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	return p
end
Models.NewPart = newPart

local function newWedge(name: string, size: Vector3, color: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	return p
end
Models.NewWedge = newWedge

-- A block part rendered as a smooth ellipsoid that fills its size
local function ellipsoid(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = newPart(name, size, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Rigidly attach child to parent at an offset
local function attach(parent: BasePart, child: BasePart, offset: CFrame, model: Instance): Weld
	child.CFrame = parent.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = parent
	w.Part1 = child
	w.C0 = offset
	w.Parent = child
	child.Parent = model
	return w
end
Models.Attach = attach

-- Animatable joint (the client drives Motor6D.C0)
local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame, model: Instance): Motor6D
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
	part1.Parent = model
	return m
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end
Models.Light = light

local function sparkles(parent: BasePart, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end
Models.Sparkles = sparkles

local function darker(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), a)
end

local function lighter(c: Color3, a: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), a)
end

local function lum(c: Color3): number
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end

--------------------------------------------------------------------------------
-- MOB RIG HELPERS
-- Parts are placed in "rig units": x/y/z relative to the ground point under the root, before
-- scaling (y = 0 is the ground, the mob faces -Z). put/rbox/... scale positions and sizes by rig.s.
--------------------------------------------------------------------------------
type Rig = {
	model: Model,
	root: BasePart,
	def: any,
	s: number,
	elite: boolean,
	boss: boolean,
	G: CFrame,
	c1: Color3,
	c2: Color3,
	eye: Color3,
}

type Body = {
	torso: BasePart,
	head: BasePart,
	arms: { [number]: BasePart },
	legs: { [number]: BasePart },
	headC: Vector3, -- head block centre / size (rig units)
	headS: Vector3,
	hand: { [number]: Vector3 }, -- hand centres
	handS: number,
	shoulderY: number,
	armX: number,
	armW: number,
	chestZ: number, -- front of the chest
	backZ: number, -- back of the torso
	neckY: number, -- top of the torso
	torsoW: number, -- half width of the upper torso
	waistY: number,
}

local function rigCF(rig: Rig, cf: CFrame): CFrame
	return rig.G * ((cf - cf.Position) + cf.Position * rig.s)
end

local function put(rig: Rig, parent: BasePart, part: BasePart, cf: CFrame): BasePart
	attach(parent, part, parent.CFrame:ToObjectSpace(rigCF(rig, cf)), rig.model)
	return part
end

local function rbox(rig: Rig, parent: BasePart, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame): BasePart
	return put(rig, parent, newPart(name, size * rig.s, color, mat), cf)
end

local function rball(rig: Rig, parent: BasePart, name: string, d: number, color: Color3, mat: Enum.Material?, cf: CFrame): BasePart
	return put(rig, parent, newPart(name, V(d, d, d) * rig.s, color, mat, Enum.PartType.Ball), cf)
end

local function rell(rig: Rig, parent: BasePart, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame): BasePart
	return put(rig, parent, ellipsoid(name, size * rig.s, color, mat), cf)
end

-- Cylinder: size.X is the length along its axis (the part's local X), size.Y/Z the diameter
local function rcyl(rig: Rig, parent: BasePart, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame): BasePart
	return put(rig, parent, newPart(name, size * rig.s, color, mat, Enum.PartType.Cylinder), cf)
end

local function rwedge(rig: Rig, parent: BasePart, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame): BasePart
	return put(rig, parent, newWedge(name, size * rig.s, color, mat), cf)
end

-- Motor6D between part0 and part1; pivot and part1's placement are given in rig units
local function rjoint(rig: Rig, name: string, part0: BasePart, part1: BasePart, pivot: CFrame, cf: CFrame): Motor6D
	local pw, cw = rigCF(rig, pivot), rigCF(rig, cf)
	return joint(name, part0, part1, part0.CFrame:ToObjectSpace(pw), cw:ToObjectSpace(pw), rig.model)
end

-- Curved chain of tapering blocks (horns, antlers, hooks): each step turns by (rx, 0, rz) and grows along +Y
local function rchain(rig: Rig, parent: BasePart, name: string, start: CFrame, steps: { { number } }, color: Color3, mat: Enum.Material?): CFrame
	local cf = start
	for _, st in steps do
		local len, w = st[1], st[2]
		cf = cf * ANG(st[3] or 0, 0, st[4] or 0)
		rbox(rig, parent, name, V(w, len, w), color, mat, cf * CF(0, len / 2, 0))
		cf = cf * CF(0, len * 0.86, 0)
	end
	return cf
end

-- A forward-facing triangle pointing down (fangs, claws, tatters); flip = true points it up
local function tri(rig: Rig, parent: BasePart, name: string, pos: Vector3, side: number, w: number, h: number, d: number, color: Color3, mat: Enum.Material?, flip: boolean?)
	local rot = flip and ANG(0, side * PI / 2, 0) or ANG(PI, side * PI / 2, 0)
	return rwedge(rig, parent, name, V(d, h, w), color, mat, CF(pos) * rot)
end

--------------------------------------------------------------------------------
-- FACES
--------------------------------------------------------------------------------
-- fz = front surface z of the face; glowing eye colours become Neon, dark ones get whites + pupils
local function eyes(rig: Rig, head: BasePart, fz: number, x: number, y: number, w: number, h: number)
	local glow = lum(rig.eye) > 0.3
	for _, side in SIDES do
		if glow then
			rbox(rig, head, "Eye", V(w, h, 0.2), rig.eye, MAT.Neon, CF(side * x, y, fz - 0.02))
		else
			rbox(rig, head, "EyeWhite", V(w, h, 0.2), WHITE, nil, CF(side * x, y, fz - 0.02))
			rbox(rig, head, "Eye", V(w * 0.5, h * 0.66, 0.1), rig.eye, nil, CF(side * (x - w * 0.12), y - h * 0.1, fz - 0.17))
		end
	end
end

-- angle > 0 = angry (inner ends low)
local function brows(rig: Rig, head: BasePart, fz: number, x: number, y: number, w: number, color: Color3, angle: number)
	for _, side in SIDES do
		rbox(rig, head, "Brow", V(w, 0.15, 0.26), color, nil, CF(side * x, y, fz - 0.05) * ANG(0, 0, side * angle))
	end
end

local function mouth(rig: Rig, head: BasePart, fz: number, y: number, w: number, h: number, teeth: string?)
	rbox(rig, head, "Mouth", V(w, h, 0.2), INK, nil, CF(0, y, fz - 0.02))
	if teeth == "fangs" then
		for _, side in SIDES do
			tri(rig, head, "Fang", V(side * w * 0.3, y - 0.03, fz - 0.17), side, math.min(0.22, w * 0.26), h + 0.16, 0.1, BONE)
		end
	elseif teeth == "grin" then
		rbox(rig, head, "Teeth", V(w * 0.84, h * 0.45, 0.2), BONE, nil, CF(0, y + h * 0.275 + 0.06, fz - 0.12))
	elseif teeth == "tusks" then
		for _, side in SIDES do
			tri(rig, head, "Tusk", V(side * w * 0.36, y + 0.05, fz - 0.17), -side, 0.2, h + 0.26, 0.12, BONE, nil, true)
		end
	end
end

--------------------------------------------------------------------------------
-- HEADGEAR (hats, helmets, crowns, horns, ears)
--------------------------------------------------------------------------------
local function crown(rig: Rig, parent: BasePart, style: string, c: Vector3, top: number, radius: number)
	local c2 = rig.c2
	if style == "ice" then
		rcyl(rig, parent, "Crown", V(0.3, radius * 2, radius * 2), lighter(c2, 0.2), MAT.Glass, CF(c.X, top + 0.1, c.Z) * UPRIGHT)
		for k = 0, 6 do
			local a = k * PI * 2 / 7
			local h = k % 2 == 0 and 1.0 or 0.65
			rwedge(rig, parent, "Crown", V(0.18, h, 0.34), lighter(c2, 0.35), MAT.Ice, CF(c.X + math.cos(a) * radius * 0.86, top + 0.2 + h / 2, c.Z + math.sin(a) * radius * 0.86) * ANG(0, -a - PI / 2, 0))
		end
	elseif style == "star" then
		-- a floating halo of star shards
		for k = 0, 5 do
			local a = k * PI / 3
			rbox(rig, parent, "Crown", V(0.3, 0.3, 0.3), k % 2 == 0 and c2 or rig.eye, MAT.Neon, CF(c.X + math.cos(a) * radius, top + 0.7, c.Z + math.sin(a) * radius) * ANG(PI / 4, a, PI / 4))
		end
		rball(rig, parent, "CrownGem", 0.45, rig.eye, MAT.Neon, CF(c.X, top + 1.1, c.Z))
	elseif style == "flame" then
		for k = 0, 5 do
			local a = k * PI / 3 + PI / 6
			local h = k % 2 == 0 and 1.1 or 0.75
			rwedge(rig, parent, "Crown", V(0.2, h, 0.42), k % 2 == 0 and c2 or rgb(255, 220, 90), MAT.Neon, CF(c.X + math.cos(a) * radius * 0.8, top + h / 2 - 0.05, c.Z + math.sin(a) * radius * 0.8) * ANG(0, -a - PI / 2, 0))
		end
	elseif style == "void" then
		rcyl(rig, parent, "Crown", V(0.32, radius * 2, radius * 2), rgb(30, 22, 44), MAT.Metal, CF(c.X, top + 0.12, c.Z) * UPRIGHT)
		for k = 0, 4 do
			local a = -PI / 2 + (k - 2) * 0.62
			local h = k == 2 and 1.2 or (k % 2 == 1 and 0.85 or 0.6)
			rwedge(rig, parent, "Crown", V(0.16, h, 0.36), c2, MAT.Neon, CF(c.X + math.cos(a) * radius * 0.9, top + 0.24 + h / 2, c.Z + math.sin(a) * radius * 0.9) * ANG(0, -a - PI / 2, 0))
		end
	elseif style ~= "branch" then
		-- gold: band + points + gems
		rcyl(rig, parent, "Crown", V(0.42, radius * 2, radius * 2), GOLD, MAT.Foil, CF(c.X, top + 0.14, c.Z) * UPRIGHT)
		for k = 0, 4 do
			local a = -PI / 2 + k * PI * 2 / 5
			rbox(rig, parent, "CrownPoint", V(0.36, 0.36, 0.12), GOLD, MAT.Foil, CF(c.X + math.cos(a) * (radius - 0.02), top + 0.4, c.Z + math.sin(a) * (radius - 0.02)) * ANG(0, -a - PI / 2, 0) * ANG(0, 0, PI / 4))
		end
		rball(rig, parent, "CrownGem", 0.3, rgb(255, 60, 90), MAT.Neon, CF(c.X, top + 0.14, c.Z - radius - 0.04))
	end
end

local function horns(rig: Rig, head: BasePart, c: Vector3, sz: Vector3, style: string)
	local top = c.Y + sz.Y / 2
	for _, side in SIDES do
		if style == "ram" then
			local start = CF(c.X + side * sz.X * 0.4, top - 0.12, c.Z + 0.05) * ANG(0, 0, -side * 1.2)
			rchain(rig, head, "Horn", start, { { 0.5, 0.42 }, { 0.5, 0.38, -0.9 }, { 0.45, 0.32, -0.9 }, { 0.4, 0.26, -0.9 }, { 0.32, 0.2, -0.8 } }, rgb(225, 205, 165), MAT.SmoothPlastic)
		elseif style == "ice" then
			rwedge(rig, head, "Horn", V(0.22, 0.95, 0.3), lighter(rig.c2, 0.45), MAT.Ice, CF(c.X + side * sz.X * 0.3, top + 0.35, c.Z + 0.05) * ANG(0, 0, -side * 0.35) * ANG(0, side * PI / 2, 0))
			rwedge(rig, head, "Horn", V(0.14, 0.5, 0.18), lighter(rig.c2, 0.6), MAT.Ice, CF(c.X + side * sz.X * 0.46, top + 0.12, c.Z + 0.25) * ANG(0, 0, -side * 0.7) * ANG(0, side * PI / 2, 0))
		elseif style == "small" then
			rwedge(rig, head, "Horn", V(0.2, 0.5, 0.3), darker(rig.c2, 0.3), nil, CF(c.X + side * sz.X * 0.3, top + 0.2, c.Z) * ANG(0, 0, -side * 0.3) * ANG(0, side * PI / 2, 0))
		else -- curved
			local start = CF(c.X + side * sz.X * 0.3, top - 0.18, c.Z + 0.05) * ANG(0, 0, -side * 0.75)
			local hornColor = lum(rig.c1) < 0.1 and rgb(205, 190, 225) or rgb(40, 30, 32)
			rchain(rig, head, "Horn", start, { { 0.5, 0.34 }, { 0.45, 0.27, -0.25, side * 0.55 }, { 0.42, 0.2, -0.25, side * 0.55 }, { 0.3, 0.13, -0.1, side * 0.5 } }, hornColor, MAT.SmoothPlastic)
		end
	end
end

local function ears(rig: Rig, head: BasePart, c: Vector3, sz: Vector3, style: string, color: Color3)
	for _, side in SIDES do
		if style == "long" then -- goblin: long and pointing sideways
			rwedge(rig, head, "Ear", V(0.16, 0.6, 1.1), color, nil, CF(c.X + side * (sz.X / 2 + 0.42), c.Y + 0.1, c.Z + 0.05) * ANG(0, 0, side * 0.38) * ANG(0, -side * PI / 2, 0))
			rwedge(rig, head, "EarInner", V(0.1, 0.36, 0.7), darker(color, 0.25), nil, CF(c.X + side * (sz.X / 2 + 0.32), c.Y + 0.06, c.Z - 0.02) * ANG(0, 0, side * 0.38) * ANG(0, -side * PI / 2, 0))
		else -- pointy, standing up at the top corners
			rwedge(rig, head, "Ear", V(0.16, 0.7, 0.46), color, nil, CF(c.X + side * (sz.X / 2 - 0.12), c.Y + sz.Y / 2 + 0.18, c.Z + 0.05) * ANG(0, 0, -side * 0.35) * ANG(0, side * PI / 2, 0))
		end
	end
end

-- Open hood: the face shows, a peak overhangs the brow
local function hood(rig: Rig, b: Body, color: Color3)
	local c, sz, head = b.headC, b.headS, b.head
	rbox(rig, head, "Hood", V(sz.X + 0.3, sz.Y + 0.3, sz.Z + 0.1), color, MAT.Fabric, CF(c.X, c.Y + 0.05, c.Z + 0.16))
	rwedge(rig, head, "HoodPeak", V(sz.X + 0.12, 0.4, 0.55), color, MAT.Fabric, CF(c.X, c.Y + sz.Y / 2 - 0.08, c.Z - sz.Z / 2 - 0.02) * ANG(PI, 0, 0))
	rwedge(rig, head, "HoodTail", V(sz.X * 0.7, 1.0, 0.55), darker(color, 0.1), MAT.Fabric, CF(c.X, c.Y - sz.Y / 2 - 0.3, c.Z + sz.Z / 2 + 0.25) * ANG(0, PI, 0))
end

local function witchHat(rig: Rig, b: Body, color: Color3, band: Color3)
	local c, sz, head = b.headC, b.headS, b.head
	local y = c.Y + sz.Y / 2
	rcyl(rig, head, "HatBrim", V(0.14, 3.0, 3.0), color, MAT.Fabric, CF(c.X, y - 0.02, c.Z) * UPRIGHT * ANG(0.12, 0, 0))
	rcyl(rig, head, "HatBand", V(0.34, 1.5, 1.5), band, MAT.Fabric, CF(c.X, y + 0.2, c.Z) * UPRIGHT)
	rbox(rig, head, "Hat", V(1.3, 0.78, 1.3), color, MAT.Fabric, CF(c.X, y + 0.56, c.Z + 0.02))
	rbox(rig, head, "Hat", V(0.94, 0.75, 0.94), color, MAT.Fabric, CF(c.X, y + 1.16, c.Z + 0.14) * ANG(-0.22, 0.3, 0))
	rbox(rig, head, "Hat", V(0.6, 0.7, 0.6), color, MAT.Fabric, CF(c.X, y + 1.68, c.Z + 0.4) * ANG(-0.5, 0.6, 0))
	rwedge(rig, head, "HatTip", V(0.34, 0.6, 0.46), color, MAT.Fabric, CF(c.X, y + 2.0, c.Z + 0.78) * ANG(-1.05, 0, 0))
	rbox(rig, head, "Buckle", V(0.42, 0.3, 0.12), GOLD, MAT.Metal, CF(c.X, y + 0.2, c.Z - 0.8))
end

-- Pharaoh's striped headdress with the cobra on the brow
local function nemes(rig: Rig, b: Body)
	local c, sz, head = b.headC, b.headS, b.head
	local blue = rig.c2
	rbox(rig, head, "Nemes", V(sz.X + 0.3, 0.5, sz.Z + 0.44), GOLD, MAT.Foil, CF(c.X, c.Y + sz.Y / 2 - 0.02, c.Z + 0.1))
	rbox(rig, head, "NemesStripe", V(sz.X + 0.5, 0.16, sz.Z + 0.64), blue, MAT.SmoothPlastic, CF(c.X, c.Y + sz.Y / 2 - 0.1, c.Z + 0.1))
	rbox(rig, head, "Nemes", V(sz.X + 0.2, 1.3, 0.36), GOLD, MAT.Foil, CF(c.X, c.Y - 0.2, c.Z + sz.Z / 2 + 0.12))
	for _, side in SIDES do
		local x = c.X + side * (sz.X / 2 + 0.18)
		local tilt = ANG(0, 0, side * 0.1)
		rbox(rig, head, "Lappet", V(0.4, 1.9, 0.9), GOLD, MAT.Foil, CF(x, c.Y - 0.45, c.Z + 0.05) * tilt)
		for k = 0, 2 do
			rbox(rig, head, "LappetStripe", V(0.52, 0.18, 1.02), blue, MAT.SmoothPlastic, CF(x - side * k * 0.03, c.Y - 0.05 - k * 0.5, c.Z + 0.05) * tilt)
		end
	end
	rbox(rig, head, "Uraeus", V(0.22, 0.6, 0.18), GOLD, MAT.Metal, CF(c.X, c.Y + sz.Y / 2 + 0.05, c.Z - sz.Z / 2 - 0.3))
	rball(rig, head, "UraeusHead", 0.3, GOLD, MAT.Metal, CF(c.X, c.Y + sz.Y / 2 + 0.36, c.Z - sz.Z / 2 - 0.36))
	rbox(rig, head, "UraeusGem", V(0.14, 0.14, 0.12), rig.eye, MAT.Neon, CF(c.X, c.Y + sz.Y / 2 + 0.36, c.Z - sz.Z / 2 - 0.52))
end

local function helmet(rig: Rig, b: Body, style: string)
	local c, sz, head = b.headC, b.headS, b.head
	local hs = sz + V(0.2, 0.44, 0.2) -- reaches below the jaw so no face lines up with the head's
	local top = c.Y + 0.04 + hs.Y / 2
	if style == "crest" then -- open bronze helmet with a horsehair crest; the face shows
		local bronze = rgb(200, 145, 72)
		rbox(rig, head, "Helmet", hs, bronze, MAT.Metal, CF(c.X, c.Y + 0.04, c.Z + 0.36))
		for _, side in SIDES do
			rbox(rig, head, "CheekGuard", V(0.3, 0.8, 0.5), bronze, MAT.Metal, CF(c.X + side * (hs.X / 2 - 0.05), c.Y - 0.25, c.Z - sz.Z / 2 + 0.2))
		end
		rbox(rig, head, "NoseGuard", V(0.16, 0.55, 0.14), bronze, MAT.Metal, CF(c.X, c.Y + 0.12, c.Z - sz.Z / 2 - 0.16))
		rbox(rig, head, "Crest", V(0.26, 0.6, hs.Z + 0.45), rig.c2, MAT.Fabric, CF(c.X, top + 0.22, c.Z + 0.3))
		return
	end
	if style == "skull" then -- iron helm behind a bone skull mask, big horns
		rbox(rig, head, "Helmet", hs, rgb(58, 54, 52), MAT.Metal, CF(c.X, c.Y + 0.04, c.Z))
		rbox(rig, head, "SkullMask", V(hs.X - 0.2, hs.Y * 0.62, 0.3), BONE, nil, CF(c.X, c.Y + 0.18, c.Z - hs.Z / 2 - 0.05))
		local fz = c.Z - hs.Z / 2 - 0.2
		for _, side in SIDES do
			rbox(rig, head, "Socket", V(0.38, 0.32, 0.2), INK, nil, CF(c.X + side * 0.3, c.Y + 0.3, fz - 0.02))
			rbox(rig, head, "Eye", V(0.2, 0.14, 0.2), rig.eye, MAT.Neon, CF(c.X + side * 0.3, c.Y + 0.28, fz - 0.1))
		end
		rbox(rig, head, "SkullTeeth", V(0.7, 0.24, 0.3), BONE, nil, CF(c.X, c.Y - 0.3, c.Z - hs.Z / 2 - 0.1))
		rbox(rig, head, "SkullNose", V(0.16, 0.2, 0.2), INK, nil, CF(c.X, c.Y + 0.02, fz - 0.02) * ANG(0, 0, PI / 4))
		for _, side in SIDES do
			local start = CF(c.X + side * (hs.X / 2 - 0.1), top - 0.3, c.Z) * ANG(0, 0, -side * 1.25)
			rchain(rig, head, "Horn", start, { { 0.55, 0.36 }, { 0.5, 0.28, 0, side * 0.6 }, { 0.45, 0.2, 0, side * 0.6 }, { 0.3, 0.13, 0, side * 0.5 } }, BONE, nil)
		end
		return
	end
	local metal = lighter(rig.c1, 0.12)
	rbox(rig, head, "Helmet", hs, metal, MAT.Metal, CF(c.X, c.Y + 0.04, c.Z))
	local fz = c.Z - hs.Z / 2
	rbox(rig, head, "Visor", V(hs.X * 0.7, 0.16, 0.2), rig.eye, MAT.Neon, CF(c.X, c.Y + 0.12, fz - 0.02))
	rbox(rig, head, "VisorRidge", V(hs.X * 0.8, 0.2, 0.26), darker(metal, 0.35), MAT.Metal, CF(c.X, c.Y + 0.36, fz - 0.04))
	if style == "great" then -- demonic horns
		for _, side in SIDES do
			local start = CF(c.X + side * (hs.X / 2 - 0.12), top - 0.4, c.Z) * ANG(0, 0, -side * 1.1)
			rchain(rig, head, "Horn", start, { { 0.5, 0.32 }, { 0.45, 0.25, 0, side * 0.8 }, { 0.35, 0.16, 0, side * 0.6 } }, rgb(30, 24, 24), MAT.Metal)
		end
	elseif style == "spiked" then
		for k = -1, 1 do
			rwedge(rig, head, "Spike", V(0.18, k == 0 and 0.9 or 0.6, 0.4), darker(metal, 0.2), MAT.Metal, CF(c.X + k * 0.42, top + (k == 0 and 0.42 or 0.27), c.Z + 0.05) * ANG(0, 0, -k * 0.25) * ANG(0, PI / 2, 0))
		end
	elseif style == "fin" then
		rwedge(rig, head, "Fin", V(0.2, 0.95, hs.Z + 0.35), rig.c2, MAT.Neon, CF(c.X, top + 0.4, c.Z + 0.12))
	end
end

--------------------------------------------------------------------------------
-- HELD ITEMS (right hand weapon, left hand shield)
--------------------------------------------------------------------------------
local function mobWeapon(rig: Rig, b: Body, kind: string)
	local arm = b.arms[1]
	local h = b.hand[1]
	local k = b.handS / 0.9
	local steel = rgb(200, 205, 215)
	local wood = rgb(118, 80, 48)
	if kind == "sword" or kind == "dagger" or kind == "icicle" then
		local len = (kind == "sword" and 2.5 or 1.2) * k
		local w = (kind == "sword" and 0.44 or 0.34) * k
		local W = CF(h) * ANG(-1.05, 0, 0)
		local bladeColor = kind == "icicle" and lighter(rig.c1, 0.4) or (rig.def.body == "skeleton" and rgb(150, 132, 112) or steel)
		local bladeMat = kind == "icicle" and MAT.Ice or MAT.Metal
		if kind ~= "icicle" then
			rbox(rig, arm, "Grip", V(0.2, 0.95, 0.2) * k, LEATHER, MAT.Leather, W)
			rbox(rig, arm, "Guard", V(0.86, 0.16, 0.3) * k, rig.def.body == "knight" and rig.c2 or IRON, rig.def.body == "knight" and MAT.Neon or MAT.Metal, W * CF(0, 0.52 * k, 0))
		end
		local base = kind == "icicle" and 0.2 * k or 0.58 * k
		local bodyLen = len - w * 0.9
		rbox(rig, arm, "WeaponBlade", V(0.12 * k, bodyLen, w), bladeColor, bladeMat, W * CF(0, base + bodyLen / 2, 0))
		for _, side in SIDES do
			rwedge(rig, arm, "WeaponTip", V(0.12 * k, w * 0.9, w / 2), bladeColor, bladeMat, W * CF(0, base + bodyLen + w * 0.45, side * w / 4) * ANG(0, side > 0 and PI or 0, 0))
		end
		if rig.def.body == "knight" then
			rbox(rig, arm, "WeaponRune", V(0.2 * k, bodyLen * 0.7, w * 0.26), rig.c2, MAT.Neon, W * CF(0, base + bodyLen * 0.45, 0))
		end
	elseif kind == "club" then
		local W = CF(h) * ANG(-0.95, 0, 0)
		local icy = rig.def.crownStyle == "ice"
		local headColor = icy and lighter(rig.c2, 0.1) or rgb(128, 90, 56)
		rbox(rig, arm, "Grip", V(0.24, 1.3, 0.24) * k, wood, MAT.Wood, W * CF(0, 0.15 * k, 0))
		rell(rig, arm, "ClubHead", V(0.7, 1.5, 0.7) * k, headColor, icy and MAT.Ice or MAT.Wood, W * CF(0, 1.35 * k, 0))
		for i, a in { 0.4, 2.5, 4.4 } do
			rwedge(rig, arm, "ClubSpike", V(0.12, 0.34, 0.24) * k, icy and lighter(rig.c2, 0.5) or BONE, icy and MAT.Ice or nil, W * CF(0, (1.0 + i * 0.22) * k, 0) * ANG(0, a, 0) * CF(0, 0, -0.38 * k) * ANG(-PI / 2, 0, 0))
		end
	elseif kind == "spear" then
		local W = CF(h) * ANG(-0.22, 0, 0)
		local tip = rig.def.body == "knight" and rig.c2 or rgb(214, 170, 90)
		local tipMat = rig.def.body == "knight" and MAT.Neon or MAT.Metal
		rbox(rig, arm, "Shaft", V(0.17, 5.6, 0.17) * k, rig.def.body == "knight" and lighter(rig.c1, 0.2) or wood, MAT.Wood, W * CF(0, 1.1 * k, 0))
		for _, side in SIDES do
			rwedge(rig, arm, "SpearTip", V(0.12, 0.9, 0.24) * k, tip, tipMat, W * CF(0, 4.35 * k, side * 0.12 * k) * ANG(0, side > 0 and PI or 0, 0))
			rwedge(rig, arm, "SpearTip", V(0.12, 0.35, 0.24) * k, tip, tipMat, W * CF(0, 3.73 * k, side * 0.12 * k) * ANG(PI, side > 0 and 0 or PI, 0))
		end
		rbox(rig, arm, "Tassel", V(0.24, 0.5, 0.24) * k, rig.c2, MAT.Fabric, W * CF(0, 3.45 * k, 0))
	elseif kind == "staff" then
		local W = CF(h) * ANG(-0.12, 0, 0)
		rbox(rig, arm, "Shaft", V(0.2, 5.2, 0.2) * k, rgb(62, 44, 36), MAT.Wood, W * CF(0, 1.0 * k, 0))
		rball(rig, arm, "StaffOrb", 0.62 * k, rig.eye, MAT.Neon, W * CF(0, 3.95 * k, 0))
		for i = 0, 2 do
			local a = i * PI * 2 / 3
			rwedge(rig, arm, "StaffClaw", V(0.1, 0.62, 0.22) * k, rgb(62, 44, 36), MAT.Wood, W * CF(0, 3.72 * k, 0) * ANG(0, a, 0) * CF(0, 0, -0.26 * k) * ANG(-0.35, 0, 0))
		end
	elseif kind == "axe" then
		local W = CF(h) * ANG(-0.75, 0, 0)
		rbox(rig, arm, "Grip", V(0.24, 3.4, 0.24) * k, rgb(70, 50, 40), MAT.Wood, W * CF(0, 0.85 * k, 0))
		rell(rig, arm, "AxeHead", V(0.16, 1.5, 2.3) * k, rgb(120, 118, 124), MAT.Metal, W * CF(0, 2.2 * k, 0))
		rell(rig, arm, "AxeEdge", V(0.1, 1.25, 2.55) * k, rig.c2, MAT.Metal, W * CF(0, 2.2 * k, 0))
		rwedge(rig, arm, "AxeSpike", V(0.14, 0.5, 0.2) * k, rgb(120, 118, 124), MAT.Metal, W * CF(0, 2.95 * k, 0))
	elseif kind == "crook" then
		local W = CF(h) * ANG(-0.18, 0, 0)
		rbox(rig, arm, "Shaft", V(0.18, 4.0, 0.18) * k, GOLD, MAT.Foil, W * CF(0, 0.7 * k, 0))
		for i = 0, 3 do
			rbox(rig, arm, "ShaftBand", V(0.24, 0.2, 0.24) * k, rig.c2, nil, W * CF(0, (-0.6 + i * 0.8) * k, 0))
		end
		rchain(rig, arm, "Crook", W * CF(0, 2.6 * k, 0), { { 0.45 * k, 0.18 * k }, { 0.4 * k, 0.18 * k, 1.0 }, { 0.4 * k, 0.18 * k, 1.1 }, { 0.3 * k, 0.16 * k, 1.0 } }, GOLD, MAT.Foil)
	elseif kind == "saw" then
		-- right: pincer claw; left: buzz saw
		local W = CF(h) * ANG(-0.8, 0, 0)
		for _, side in SIDES do
			rwedge(rig, arm, "Claw", V(0.16, 0.8, 0.3) * k, rgb(150, 150, 158), MAT.Metal, W * CF(side * 0.2 * k, 0.55 * k, 0) * ANG(0, 0, side * 0.3) * ANG(0, -side * PI / 2, 0))
		end
		local armL = b.arms[-1]
		local hl = b.hand[-1]
		rcyl(rig, armL, "SawBlade", V(0.12, 1.6, 1.6) * k, rgb(200, 200, 205), MAT.Metal, CF(hl + V(-0.12, -0.35, -0.3) * k))
		rcyl(rig, armL, "SawHub", V(0.3, 0.5, 0.5) * k, rig.eye, MAT.Neon, CF(hl + V(-0.12, -0.35, -0.3) * k))
	elseif kind == "orb" then
		rball(rig, arm, "VoidOrb", 0.75 * k, rig.c2, MAT.Neon, CF(h + V(0, 0.45, -0.7) * k))
		rcyl(rig, arm, "OrbRing", V(0.1, 1.2, 1.2) * k, darker(rig.c2, 0.4), MAT.Neon, CF(h + V(0, 0.45, -0.7) * k) * ANG(0, 0, 0.5))
	end
end

local function mobShield(rig: Rig, b: Body, kind: string)
	local arm = b.arms[-1]
	local h = b.hand[-1]
	local k = b.handS / 0.9
	local center = h + V(-0.2, 0.55, -0.62) * k
	local facing = CF(center) * ANG(0, -1.95, 0) -- disc axis toward forward-left
	local field = rig.def.body == "knight" and rig.c1 or rgb(178, 128, 64)
	local rim = rig.def.body == "knight" and rig.c2 or rgb(204, 150, 72)
	if kind == "kite" then
		local up = CF(center) * ANG(0, 0.45, 0)
		rbox(rig, arm, "Shield", V(1.3, 1.4, 0.2) * k, field, MAT.Metal, up * CF(0, 0.3 * k, 0))
		rbox(rig, arm, "Shield", V(0.92, 0.92, 0.2) * k, field, MAT.Metal, up * CF(0, -0.4 * k, 0) * ANG(0, 0, PI / 4))
		rbox(rig, arm, "ShieldCrest", V(0.26, 1.2, 0.32) * k, rim, rig.def.body == "knight" and MAT.Neon or MAT.Metal, up * CF(0, 0.05 * k, 0))
		rbox(rig, arm, "ShieldCrest", V(0.86, 0.22, 0.32) * k, rim, rig.def.body == "knight" and MAT.Neon or MAT.Metal, up * CF(0, 0.35 * k, 0))
	else
		rcyl(rig, arm, "Shield", V(0.22, 1.9, 1.9) * k, field, rig.def.body == "knight" and MAT.Metal or MAT.Wood, facing)
		rcyl(rig, arm, "ShieldRim", V(0.12, 2.12, 2.12) * k, rim, MAT.Metal, facing)
		rball(rig, arm, "ShieldBoss", 0.5 * k, rim, rig.def.body == "knight" and MAT.Neon or MAT.Metal, facing * CF(-0.12 * k, 0, 0))
	end
end

--------------------------------------------------------------------------------
-- BIPED BODIES. Each returns the Body anchors used by headgear / extras / dressing.
--------------------------------------------------------------------------------
local function makeLegs(rig: Rig, x: number, y: number, size: Vector3, color: Color3, mat: Enum.Material?): { [number]: BasePart }
	local legs: { [number]: BasePart } = {}
	for _, side in SIDES do
		local leg = newPart(side < 0 and "LeftLeg" or "RightLeg", size * rig.s, color, mat)
		rjoint(rig, side < 0 and "LeftHip" or "RightHip", rig.root, leg, CF(side * x, y, 0), CF(side * x, y + 0.06 - size.Y / 2, 0))
		legs[side] = leg
	end
	return legs
end

-- arm pivot at (±x, y); the arm's top sits `top` above the pivot
local function makeArms(rig: Rig, torso: BasePart, x: number, y: number, size: Vector3, color: Color3, mat: Enum.Material?, top: number): { [number]: BasePart }
	local arms: { [number]: BasePart } = {}
	for _, side in SIDES do
		local arm = newPart(side < 0 and "LeftArm" or "RightArm", size * rig.s, color, mat)
		rjoint(rig, side < 0 and "LeftShoulder" or "RightShoulder", torso, arm, CF(side * x, y, 0), CF(side * x, y + top - size.Y / 2, 0))
		arms[side] = arm
	end
	return arms
end

local function makeTorso(rig: Rig, size: Vector3, color: Color3, mat: Enum.Material?, waistY: number, center: Vector3): BasePart
	local torso = newPart("Torso", size * rig.s, color, mat)
	rjoint(rig, "Waist", rig.root, torso, CF(0, waistY, 0), CF(center))
	return torso
end

local function makeHead(rig: Rig, torso: BasePart, size: Vector3, color: Color3, mat: Enum.Material?, neck: Vector3, center: Vector3, round: boolean?): BasePart
	local head = round and ellipsoid("Head", size * rig.s, color, mat) or newPart("Head", size * rig.s, color, mat)
	rjoint(rig, "Neck", torso, head, CF(neck), CF(center))
	return head
end

local function humanFace(rig: Rig, b: Body)
	local def = rig.def
	local head, c, sz = b.head, b.headC, b.headS
	local fz = c.Z - sz.Z / 2
	local browColor = def.hat == "nemes" and INK or darker(rig.c1, 0.6)
	eyes(rig, head, fz, 0.34, c.Y + 0.1, 0.3, 0.3)
	brows(rig, head, fz, 0.35, c.Y + 0.36, 0.44, browColor, def.hat == "nemes" and 0.12 or 0.28)
	if def.mask == "bandana" then
		rbox(rig, head, "Mask", V(sz.X + 0.14, sz.Y / 2 + 0.17, sz.Z + 0.2), rig.c2, MAT.Fabric, CF(c.X, c.Y - sz.Y / 4 - 0.135, c.Z))
		for _, side in SIDES do
			rwedge(rig, head, "MaskKnot", V(0.14, 0.5, 0.4), darker(rig.c2, 0.15), MAT.Fabric, CF(c.X + side * 0.18, c.Y - 0.5, c.Z + sz.Z / 2 + 0.25) * ANG(0.5, side * 0.4, 0))
		end
	elseif not def.beard then
		mouth(rig, head, fz, c.Y - 0.32, 0.56, 0.14, def.teeth)
	end
end

local function bodyHuman(rig: Rig): Body
	local def, c1, c2 = rig.def, rig.c1, rig.c2
	local knight = def.body == "knight"
	local outfit = def.outfit or "shirt"
	local skin = c1
	local legs = makeLegs(rig, 0.48, 2.0, V(0.78, 1.62, 0.82), knight and c1 or darker(c2, 0.25), knight and MAT.Metal or MAT.Fabric)
	for _, side in SIDES do
		local boot = knight and darker(c1, 0.3) or (outfit == "bare" and darker(c2, 0.4) or rgb(64, 48, 38))
		rbox(rig, legs[side], "Boot", V(0.92, 0.55, 1.18), boot, knight and MAT.Metal or MAT.Leather, CF(side * 0.48, 0.275, -0.12))
	end
	local shirt = knight and c1 or (outfit == "shirt" and c2 or (outfit == "linen" and lighter(c1, 0.65) or skin))
	local torso = makeTorso(rig, V(1.86, 1.9, 1.0), shirt, knight and MAT.Metal or (outfit == "bare" and MAT.SmoothPlastic or MAT.Fabric), 2.0, V(0, 2.95, 0))
	rbox(rig, torso, "Belt", V(2.0, 0.36, 1.14), knight and darker(c1, 0.4) or rgb(74, 52, 38), MAT.Leather, CF(0, 2.08, 0))
	rbox(rig, torso, "Buckle", V(0.4, 0.3, 0.22), knight and c2 or GOLD, knight and MAT.Neon or MAT.Metal, CF(0, 2.08, -0.64))
	if def.kilt then
		rbox(rig, torso, "Kilt", V(2.2, 0.72, 1.34), outfit == "linen" and WHITE or c2, MAT.Fabric, CF(0, 1.72, 0))
		if outfit == "linen" then
			rbox(rig, torso, "KiltFront", V(0.6, 0.8, 0.14), c2, MAT.Fabric, CF(0, 1.66, -0.72))
		end
	end
	if outfit == "bare" and not knight then
		rbox(rig, torso, "Chest", V(1.5, 0.12, 0.2), darker(skin, 0.18), nil, CF(0, 3.2, -0.52))
	end
	local sleeve = knight and c1 or (outfit == "shirt" and c2 or skin)
	local arms = makeArms(rig, torso, 1.3, 3.62, V(0.7, 1.7, 0.7), sleeve, knight and MAT.Metal or (outfit == "shirt" and MAT.Fabric or nil), 0.25)
	for _, side in SIDES do
		rbox(rig, arms[side], "Hand", V(0.9, 0.66, 0.9), knight and darker(c1, 0.3) or skin, knight and MAT.Metal or nil, CF(side * 1.3, 2.1, 0))
	end
	local faceColor = def.hat == "nemes" and GOLD:Lerp(c1, 0.35) or (knight and darker(c1, 0.3) or skin)
	local head = makeHead(rig, torso, V(1.45, 1.4, 1.35), faceColor, def.hat == "nemes" and MAT.Foil or nil, V(0, 3.9, 0), V(0, 4.62, 0))
	local b: Body = {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = V(0, 4.62, 0),
		headS = V(1.45, 1.4, 1.35),
		hand = { [-1] = V(-1.3, 2.1, 0), [1] = V(1.3, 2.1, 0) },
		handS = 0.9,
		shoulderY = 3.62,
		armX = 1.3,
		armW = 0.7,
		chestZ = -0.5,
		backZ = 0.5,
		neckY = 3.9,
		torsoW = 0.93,
		waistY = 2.0,
	}
	if knight then
		-- plate armour: breastplate, faulds, pauldrons with a glowing trim
		rbox(rig, torso, "Breastplate", V(2.02, 1.26, 1.18), lighter(c1, 0.12), MAT.Metal, CF(0, 3.4, 0))
		rbox(rig, torso, "ChestGlow", V(0.2, 0.9, 0.2), c2, MAT.Neon, CF(0, 3.35, -0.62))
		rbox(rig, torso, "Faulds", V(2.12, 0.56, 1.24), darker(c1, 0.15), MAT.Metal, CF(0, 1.86, 0))
		for _, side in SIDES do
			rell(rig, arms[side], "Pauldron", V(1.15, 0.8, 1.1), lighter(c1, 0.12), MAT.Metal, CF(side * 1.38, 3.82, 0))
			rbox(rig, arms[side], "PauldronTrim", V(0.14, 0.14, 0.9), c2, MAT.Neon, CF(side * 1.9, 3.72, 0) * ANG(0, 0, side * 0.6))
		end
	end
	if not def.helmet or def.helm == "crest" then
		humanFace(rig, b)
	end
	return b
end

local function bodySmall(rig: Rig): Body
	local def, c1, c2 = rig.def, rig.c1, rig.c2
	local skin = c1
	local legs = makeLegs(rig, 0.42, 1.35, V(0.6, 1.1, 0.62), skin, nil)
	for _, side in SIDES do
		rbox(rig, legs[side], "Foot", V(0.8, 0.42, 1.04), darker(skin, 0.25), nil, CF(side * 0.42, 0.21, -0.14))
	end
	local torso = makeTorso(rig, V(1.5, 1.35, 1.0), skin, nil, 1.35, V(0, 1.98, 0))
	rell(rig, torso, "Belly", V(1.36, 1.1, 1.0), lighter(skin, 0.18), nil, CF(0, 1.86, -0.2))
	local cloth = def.hornStyle == "ice" and darker(c2, 0.2) or c2
	rbox(rig, torso, "Belt", V(1.66, 0.42, 1.16), cloth, MAT.Fabric, CF(0, 1.42, 0))
	rbox(rig, torso, "Flap", V(0.72, 0.62, 0.16), cloth, MAT.Fabric, CF(0, 1.1, -0.62))
	local arms = makeArms(rig, torso, 0.98, 2.42, V(0.5, 1.22, 0.5), skin, nil, 0.2)
	for _, side in SIDES do
		rbox(rig, arms[side], "Hand", V(0.68, 0.52, 0.68), darker(skin, 0.15), nil, CF(side * 0.98, 1.3, 0))
	end
	local hc, hs = V(0, 3.42, -0.05), V(1.95, 1.72, 1.72)
	local head = makeHead(rig, torso, hs, skin, nil, V(0, 2.62, 0), hc)
	local fz = hc.Z - hs.Z / 2
	eyes(rig, head, fz, 0.46, hc.Y + 0.14, 0.44, 0.4)
	brows(rig, head, fz, 0.48, hc.Y + 0.5, 0.58, darker(skin, 0.55), 0.38)
	mouth(rig, head, fz, hc.Y - 0.45, 0.9, 0.18, def.teeth)
	if def.nose == "big" then
		rell(rig, head, "Nose", V(0.5, 0.55, 0.75), darker(skin, 0.08), nil, CF(0, hc.Y - 0.12, fz - 0.24))
	else
		rbox(rig, head, "Nose", V(0.26, 0.2, 0.2), darker(skin, 0.15), nil, CF(0, hc.Y - 0.14, fz - 0.06))
	end
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-0.98, 1.3, 0), [1] = V(0.98, 1.3, 0) },
		handS = 0.68,
		shoulderY = 2.42,
		armX = 0.98,
		armW = 0.5,
		chestZ = -0.5,
		backZ = 0.5,
		neckY = 2.65,
		torsoW = 0.75,
		waistY = 1.35,
	}
end

local function bodyBrute(rig: Rig): Body
	local def, c1, c2 = rig.def, rig.c1, rig.c2
	local fur = def.fur
	local skin = fur and c2 or c1
	local furColor = c1
	local legColor = fur and furColor or (def.helm == "skull" and rgb(66, 56, 50) or darker(c1, 0.3))
	local legs = makeLegs(rig, 0.6, 2.0, V(0.96, 1.65, 1.0), legColor, MAT.Fabric)
	for _, side in SIDES do
		rbox(rig, legs[side], "Foot", V(1.24, 0.55, 1.44), fur and skin or rgb(58, 46, 40), if fur then nil else MAT.Leather, CF(side * 0.6, 0.275, -0.14))
	end
	local torso = makeTorso(rig, V(2.3, 1.55, 1.4), fur and furColor or skin, fur and MAT.Fabric or nil, 2.0, V(0, 2.78, 0.05))
	rbox(rig, torso, "Chest", V(2.9, 1.6, 1.7), fur and furColor or skin, fur and MAT.Fabric or nil, CF(0, 3.85, 0))
	if fur then
		rell(rig, torso, "ChestSkin", V(1.6, 1.1, 0.5), skin, nil, CF(0, 3.55, -0.72))
	else
		local beltColor = def.crownStyle == "ice" and lighter(c2, 0.1) or rgb(72, 52, 40)
		rbox(rig, torso, "Belt", V(2.46, 0.42, 1.56), beltColor, def.crownStyle == "ice" and MAT.Fabric or MAT.Leather, CF(0, 2.1, 0.05))
		rbox(rig, torso, "Buckle", V(0.5, 0.36, 0.16), def.mask == "gas" and c2 or IRON, def.mask == "gas" and MAT.Neon or MAT.Metal, CF(0, 2.1, -0.76))
		rbox(rig, torso, "Pecs", V(2.0, 0.14, 0.2), darker(skin, 0.2), nil, CF(0, 3.7, -0.86))
	end
	local arms = makeArms(rig, torso, 2.0, 4.2, V(1.0, 2.55, 1.0), fur and furColor or skin, fur and MAT.Fabric or nil, 0.3)
	for _, side in SIDES do
		rbox(rig, arms[side], "Fist", V(1.3, 1.1, 1.3), skin, nil, CF(side * 2.0, 1.9, 0))
		if fur then
			rwedge(rig, arms[side], "FurTuft", V(0.9, 0.6, 0.7), furColor, MAT.Fabric, CF(side * 2.05, 2.6, 0.1) * ANG(PI, 0, 0))
		end
	end
	local hc, hs = V(0, 4.85, -0.55), V(1.35, 1.3, 1.3)
	local head = makeHead(rig, torso, hs, fur and furColor or skin, fur and MAT.Fabric or nil, V(0, 4.45, -0.35), hc)
	local fz = hc.Z - hs.Z / 2
	local b: Body = {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-2.0, 1.9, 0), [1] = V(2.0, 1.9, 0) },
		handS = 1.3,
		shoulderY = 4.2,
		armX = 2.0,
		armW = 1.0,
		chestZ = -0.85,
		backZ = 0.85,
		neckY = 4.65,
		torsoW = 1.45,
		waistY = 2.0,
	}
	if fur then
		-- yeti: blue face plate on the fur, tuft on top
		rell(rig, head, "Face", V(1.05, 0.95, 0.4), skin, nil, CF(0, hc.Y - 0.08, fz - 0.02))
		local ffz = fz - 0.12
		eyes(rig, head, ffz, 0.24, hc.Y + 0.08, 0.22, 0.22)
		brows(rig, head, ffz, 0.26, hc.Y + 0.28, 0.36, furColor, 0.3)
		mouth(rig, head, ffz, hc.Y - 0.3, 0.56, 0.16, def.teeth)
		for k = -1, 1 do
			rwedge(rig, head, "FurTuft", V(0.2, 0.55, 0.5), furColor, MAT.Fabric, CF(k * 0.36, hc.Y + hs.Y / 2 + 0.15, hc.Z + 0.1) * ANG(0, 0, -k * 0.3) * ANG(0, PI / 2, 0))
		end
	elseif def.mask == "gas" then
		-- gas mask: dark plate, two glowing lenses, a filter canister
		rbox(rig, head, "GasMask", V(hs.X + 0.2, hs.Y * 0.72, 0.3), rgb(48, 50, 46), MAT.Rubber, CF(0, hc.Y - 0.1, fz - 0.05))
		for _, side in SIDES do
			rcyl(rig, head, "Lens", V(0.18, 0.44, 0.44), rig.eye, MAT.Neon, CF(side * 0.32, hc.Y + 0.08, fz - 0.24) * FACING)
		end
		rcyl(rig, head, "Filter", V(0.4, 0.5, 0.5), rgb(90, 96, 80), MAT.Metal, CF(0, hc.Y - 0.36, fz - 0.4) * FACING)
		rcyl(rig, head, "FilterGlow", V(0.1, 0.34, 0.34), c2, MAT.Neon, CF(0, hc.Y - 0.36, fz - 0.62) * FACING)
	elseif not def.helmet then
		eyes(rig, head, fz, 0.3, hc.Y + 0.12, 0.26, 0.22)
		brows(rig, head, fz, 0.31, hc.Y + 0.33, 0.44, def.beard and lighter(c2, 0.2) or darker(skin, 0.55), 0.3)
		if not def.beard then
			mouth(rig, head, fz, hc.Y - 0.32, 0.7, 0.16, def.teeth or "tusks")
		end
	end
	return b
end

local function bodySkeleton(rig: Rig): Body
	local bone, dark = rig.c1, rig.c2
	local legs = makeLegs(rig, 0.45, 2.0, V(0.3, 1.9, 0.3), bone, nil)
	for _, side in SIDES do
		rball(rig, legs[side], "Knee", 0.44, bone, nil, CF(side * 0.45, 1.05, 0))
		rbox(rig, legs[side], "Foot", V(0.44, 0.26, 0.86), bone, nil, CF(side * 0.45, 0.13, -0.15))
	end
	local torso = makeTorso(rig, V(0.34, 1.75, 0.34), dark, nil, 2.05, V(0, 2.95, 0.22))
	rbox(rig, torso, "Pelvis", V(1.26, 0.42, 0.62), bone, nil, CF(0, 2.12, 0.0))
	for k, w in { 1.62, 1.5, 1.3 } do
		rbox(rig, torso, "Rib", V(w, 0.17, 0.95), bone, nil, CF(0, 3.55 - (k - 1) * 0.34, 0))
	end
	rbox(rig, torso, "Sternum", V(0.2, 0.98, 0.14), bone, nil, CF(0, 3.22, -0.53))
	rbox(rig, torso, "Collarbone", V(1.96, 0.2, 0.32), bone, nil, CF(0, 3.84, 0.05))
	local arms = makeArms(rig, torso, 1.02, 3.72, V(0.26, 1.75, 0.26), bone, nil, 0.12)
	for _, side in SIDES do
		rball(rig, arms[side], "Elbow", 0.36, bone, nil, CF(side * 1.02, 2.95, 0))
		rbox(rig, arms[side], "Hand", V(0.4, 0.46, 0.34), bone, nil, CF(side * 1.02, 1.98, 0))
	end
	local hc, hs = V(0, 4.55, 0), V(1.28, 1.22, 1.35)
	local head = makeHead(rig, torso, hs, bone, nil, V(0, 3.9, 0.1), hc, true)
	rbox(rig, head, "Face", V(1.06, 0.8, 0.52), bone, nil, CF(0, 4.3, -0.42))
	for _, side in SIDES do
		rell(rig, head, "Socket", V(0.4, 0.44, 0.22), INK, nil, CF(side * 0.27, 4.6, -0.62))
		rball(rig, head, "Eye", 0.17, rig.eye, MAT.Neon, CF(side * 0.27, 4.58, -0.73))
	end
	rbox(rig, head, "NoseHole", V(0.16, 0.16, 0.12), INK, nil, CF(0, 4.37, -0.7) * ANG(0, 0, PI / 4))
	rbox(rig, head, "Teeth", V(0.8, 0.17, 0.14), WHITE, nil, CF(0, 4.07, -0.7))
	local jaw = newPart("Jaw", V(0.9, 0.3, 0.8) * rig.s, bone)
	rjoint(rig, "Jaw", head, jaw, CF(0, 3.98, 0.05), CF(0, 3.83, -0.3))
	rbox(rig, jaw, "Teeth", V(0.74, 0.14, 0.14), WHITE, nil, CF(0, 3.95, -0.77))
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-1.02, 1.98, 0), [1] = V(1.02, 1.98, 0) },
		handS = 0.6,
		shoulderY = 3.72,
		armX = 1.02,
		armW = 0.3,
		chestZ = -0.48,
		backZ = 0.48,
		neckY = 3.9,
		torsoW = 0.8,
		waistY = 2.05,
	}
end

local function bodyTree(rig: Rig): Body
	local def = rig.def
	local bark, leaf = rig.c1, rig.c2
	local barkDark = darker(bark, 0.25)
	local legs = makeLegs(rig, 0.5, 2.0, V(0.95, 1.7, 0.95), barkDark, MAT.Wood)
	for _, side in SIDES do
		rbox(rig, legs[side], "Root", V(1.25, 0.45, 1.55), darker(bark, 0.35), MAT.Wood, CF(side * 0.58, 0.225, -0.12))
		rwedge(rig, legs[side], "RootToe", V(0.5, 0.4, 0.6), darker(bark, 0.35), MAT.Wood, CF(side * 0.62, 0.2, -1.1))
	end
	local torso = makeTorso(rig, V(2.2, 2.55, 1.6), bark, MAT.Wood, 2.0, V(0, 3.25, 0))
	-- face in the trunk: dark sockets, glowing eyes, heavy brow, hollow mouth
	local fz = -0.8
	for _, side in SIDES do
		rbox(rig, torso, "Socket", V(0.56, 0.4, 0.2), INK, nil, CF(side * 0.46, 3.95, fz - 0.02))
		rbox(rig, torso, "Eye", V(0.34, 0.22, 0.2), rig.eye, MAT.Neon, CF(side * 0.46, 3.93, fz - 0.1))
	end
	rwedge(rig, torso, "Brow", V(1.7, 0.36, 0.42), barkDark, MAT.Wood, CF(0, 4.3, fz - 0.12) * ANG(PI, 0, 0))
	rbox(rig, torso, "Mouth", V(0.95, 0.5, 0.2), INK, nil, CF(0, 3.2, fz - 0.02))
	for _, side in SIDES do
		tri(rig, torso, "Fang", V(side * 0.24, 3.36, fz - 0.14), side, 0.24, 0.3, 0.1, barkDark, MAT.Wood)
	end
	rell(rig, torso, "Moss", V(1.1, 0.5, 1.0), leaf, MAT.LeafyGrass, CF(0.72, 4.45, 0.25))
	rbox(rig, torso, "BarkRidge", V(0.28, 2.2, 0.22), barkDark, MAT.Wood, CF(-0.72, 2.9, fz + 0.02))
	local arms = makeArms(rig, torso, 1.42, 4.1, V(0.68, 2.3, 0.68), bark, MAT.Wood, 0.2)
	for _, side in SIDES do
		for i, a in { -0.5, 0, 0.5 } do
			rwedge(rig, arms[side], "Twig", V(0.2, 0.7, 0.26), barkDark, MAT.Wood, CF(side * 1.42 + a * 0.4, 1.8, (i - 2) * 0.2) * ANG(PI, 0, a * 0.8))
		end
		rball(rig, arms[side], "LeafTuft", 0.95, leaf, MAT.LeafyGrass, CF(side * 1.62, 3.7, 0.2))
	end
	local hc, hs = V(0, 4.95, 0.05), V(1.7, 0.9, 1.3)
	local head = makeHead(rig, torso, hs, bark, MAT.Wood, V(0, 4.5, 0), hc)
	local big = def.beard and 1.12 or 1
	rball(rig, head, "Leaves", 3.5 * big, leaf, MAT.LeafyGrass, CF(0, 6.45, 0.1))
	for _, side in SIDES do
		rball(rig, head, "Leaves", 2.2 * big, darker(leaf, 0.1), MAT.LeafyGrass, CF(side * 1.45, 5.75, 0.25))
	end
	rball(rig, head, "Leaves", 2.1 * big, lighter(leaf, 0.08), MAT.LeafyGrass, CF(0, 5.95, 1.05))
	if def.beard then
		-- elder: mossy beard, glowing fruits in the canopy
		for _, side in SIDES do
			tri(rig, torso, "Beard", V(side * 0.32, 2.45, fz - 0.16), -side, 0.64, 1.4, 0.3, leaf, MAT.LeafyGrass)
		end
		for k, p in { V(-1.1, 6.9, -1.3), V(0.9, 7.4, -1.25), V(1.9, 5.4, -0.7) } do
			rball(rig, head, "Fruit", 0.5, k == 2 and rgb(255, 120, 200) or rig.eye, MAT.Neon, CF(p))
		end
	end
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = V(0, 6.45, 0.1),
		headS = V(3.5 * big, 3.2 * big, 3.2 * big),
		hand = { [-1] = V(-1.42, 1.95, 0), [1] = V(1.42, 1.95, 0) },
		handS = 0.8,
		shoulderY = 4.1,
		armX = 1.42,
		armW = 0.68,
		chestZ = -0.8,
		backZ = 0.8,
		neckY = 4.5,
		torsoW = 1.1,
		waistY = 2.0,
	}
end

local function bodyRobot(rig: Rig): Body
	local rust, steel = rig.c1, rig.c2
	local legs = makeLegs(rig, 0.55, 2.0, V(0.5, 1.75, 0.5), steel, MAT.Metal)
	for _, side in SIDES do
		rball(rig, legs[side], "Knee", 0.7, darker(steel, 0.2), MAT.Metal, CF(side * 0.55, 1.2, 0))
		rbox(rig, legs[side], "Foot", V(0.96, 0.42, 1.32), darker(rust, 0.2), MAT.CorrodedMetal, CF(side * 0.55, 0.21, -0.12))
	end
	local torso = makeTorso(rig, V(2.1, 1.8, 1.4), rust, MAT.CorrodedMetal, 2.1, V(0, 3.0, 0))
	rbox(rig, torso, "Pelvis", V(1.4, 0.45, 0.95), darker(steel, 0.2), MAT.Metal, CF(0, 2.06, 0))
	rbox(rig, torso, "Grille", V(1.2, 0.5, 0.14), darker(steel, 0.1), MAT.DiamondPlate, CF(0, 3.42, -0.74))
	rcyl(rig, torso, "Core", V(0.16, 0.6, 0.6), rig.eye, MAT.Neon, CF(0, 2.72, -0.72) * FACING)
	rbox(rig, torso, "HazardStripe", V(2.2, 0.2, 1.5), rgb(250, 190, 40), MAT.SmoothPlastic, CF(0, 2.3, 0))
	for _, side in SIDES do
		rcyl(rig, torso, "Exhaust", V(1.3, 0.34, 0.34), darker(steel, 0.25), MAT.Metal, CF(side * 0.52, 4.1, 0.55) * UPRIGHT)
		rcyl(rig, torso, "ExhaustTip", V(0.2, 0.26, 0.26), INK, nil, CF(side * 0.52, 4.72, 0.55) * UPRIGHT)
		rball(rig, torso, "Bolt", 0.5, darker(steel, 0.1), MAT.Metal, CF(side * 1.08, 3.72, 0))
	end
	local arms = makeArms(rig, torso, 1.42, 3.62, V(0.5, 1.62, 0.5), steel, MAT.Metal, 0.2)
	for _, side in SIDES do
		rbox(rig, arms[side], "Wrist", V(0.64, 0.36, 0.64), darker(rust, 0.1), MAT.CorrodedMetal, CF(side * 1.42, 2.2, 0))
	end
	local hc, hs = V(0, 4.46, 0), V(1.36, 1.0, 1.16)
	local head = makeHead(rig, torso, hs, steel, MAT.Metal, V(0, 3.9, 0), hc)
	local fz = hc.Z - hs.Z / 2
	rcyl(rig, head, "LensRim", V(0.2, 0.84, 0.84), INK, nil, CF(0, hc.Y + 0.05, fz - 0.04) * FACING)
	rcyl(rig, head, "Eye", V(0.2, 0.6, 0.6), rig.eye, MAT.Neon, CF(0, hc.Y + 0.05, fz - 0.14) * FACING)
	rbox(rig, head, "Jaw", V(0.9, 0.22, 0.2), INK, nil, CF(0, hc.Y - 0.3, fz - 0.02))
	for _, side in SIDES do
		rcyl(rig, head, "EarBolt", V(0.24, 0.42, 0.42), darker(rust, 0.1), MAT.CorrodedMetal, CF(side * (hs.X / 2 + 0.06), hc.Y, hc.Z))
	end
	rcyl(rig, head, "Antenna", V(0.8, 0.08, 0.08), INK, nil, CF(0.35, hc.Y + hs.Y / 2 + 0.4, hc.Z + 0.2) * UPRIGHT)
	rball(rig, head, "AntennaTip", 0.24, rig.eye, MAT.Neon, CF(0.35, hc.Y + hs.Y / 2 + 0.84, hc.Z + 0.2))
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-1.42, 2.05, 0), [1] = V(1.42, 2.05, 0) },
		handS = 0.8,
		shoulderY = 3.62,
		armX = 1.42,
		armW = 0.5,
		chestZ = -0.7,
		backZ = 0.7,
		neckY = 3.9,
		torsoW = 1.05,
		waistY = 2.1,
	}
end

local function bodyRobe(rig: Rig): Body
	local def, skin, robe = rig.def, rig.c1, rig.c2
	local void = def.crownStyle == "void"
	if void then
		robe = darker(skin, 0.1)
	end
	local legs = makeLegs(rig, 0.42, 2.0, V(0.55, 1.75, 0.55), darker(robe, 0.3), MAT.Fabric)
	for _, side in SIDES do
		rwedge(rig, legs[side], "Shoe", V(0.6, 0.36, 1.0), INK, nil, CF(side * 0.42, 0.18, -0.24))
	end
	local torso = makeTorso(rig, V(1.5, 1.7, 0.95), robe, MAT.Fabric, 2.05, V(0, 2.95, 0))
	rcyl(rig, torso, "Skirt", V(1.0, 2.0, 2.0), robe, MAT.Fabric, CF(0, 1.45, 0) * UPRIGHT)
	rcyl(rig, torso, "Hem", V(0.95, 2.6, 2.6), darker(robe, 0.12), MAT.Fabric, CF(0, 0.62, 0) * UPRIGHT)
	local trim = void and rig.c2 or rgb(120, 220, 90)
	rcyl(rig, torso, "HemTrim", V(0.14, 2.72, 2.72), trim, void and MAT.Neon or MAT.Fabric, CF(0, 0.3, 0) * UPRIGHT)
	rbox(rig, torso, "Sash", V(1.64, 0.3, 1.08), void and rig.c2 or darker(robe, 0.35), void and MAT.Neon or MAT.Fabric, CF(0, 2.16, 0))
	rbox(rig, torso, "Shawl", V(1.72, 0.42, 1.14), void and darker(robe, 0.2) or lighter(robe, 0.28), MAT.Fabric, CF(0, 3.69, 0))
	rbox(rig, torso, "RobeFront", V(0.34, 1.0, 0.2), void and rig.c2 or lighter(robe, 0.2), void and MAT.Neon or MAT.Fabric, CF(0, 1.55, -1.02))
	rbox(rig, torso, "RobeFront", V(0.34, 0.86, 0.2), void and rig.c2 or lighter(robe, 0.2), void and MAT.Neon or MAT.Fabric, CF(0, 0.62, -1.32))
	if void then
		for _, side in SIDES do
			rwedge(rig, torso, "Collar", V(0.2, 1.3, 0.8), darker(robe, 0.2), MAT.Fabric, CF(side * 0.62, 4.25, 0.35) * ANG(0, 0, -side * 0.3) * ANG(0, side * PI / 2, 0))
		end
	end
	local arms = makeArms(rig, torso, 1.02, 3.55, V(0.58, 1.45, 0.58), robe, MAT.Fabric, 0.18)
	for _, side in SIDES do
		rbox(rig, arms[side], "Cuff", V(0.86, 0.5, 0.86), void and rig.c2 or lighter(robe, 0.2), void and MAT.Neon or MAT.Fabric, CF(side * 1.02, 2.35, 0))
		rball(rig, arms[side], "Hand", 0.5, skin, nil, CF(side * 1.02, 1.95, 0))
	end
	local hc, hs = V(0, 4.5, 0), V(1.3, 1.35, 1.25)
	local head = makeHead(rig, torso, hs, skin, nil, V(0, 3.8, 0), hc)
	local fz = hc.Z - hs.Z / 2
	eyes(rig, head, fz, 0.3, hc.Y + 0.1, 0.28, void and 0.2 or 0.26)
	if not void then
		brows(rig, head, fz, 0.31, hc.Y + 0.34, 0.4, darker(robe, 0.3), 0.32)
		mouth(rig, head, fz, hc.Y - 0.36, 0.5, 0.12, "grin")
		-- long green-grey hair falling behind the shoulders
		rbox(rig, head, "Hair", V(1.5, 1.0, 0.5), darker(robe, 0.25), MAT.Fabric, CF(0, hc.Y - 0.05, hc.Z + 0.5))
	end
	if def.nose == "witch" then
		rwedge(rig, head, "Nose", V(0.24, 0.55, 0.6), darker(skin, 0.1), nil, CF(0, hc.Y - 0.1, fz - 0.3))
		rball(rig, head, "Wart", 0.14, darker(skin, 0.3), nil, CF(0.08, hc.Y - 0.16, fz - 0.4))
	end
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-1.02, 1.95, 0), [1] = V(1.02, 1.95, 0) },
		handS = 0.6,
		shoulderY = 3.55,
		armX = 1.02,
		armW = 0.58,
		chestZ = -0.48,
		backZ = 0.48,
		neckY = 3.8,
		torsoW = 0.75,
		waistY = 2.05,
	}
end

local function bodyGolem(rig: Rig): Body
	local rock, glow = rig.c1, rig.c2
	local star = rig.def.crownStyle == "star"
	local rockMat = star and MAT.Slate or MAT.Basalt
	local legs = makeLegs(rig, 0.75, 2.1, V(1.15, 1.75, 1.15), darker(rock, 0.1), rockMat)
	for _, side in SIDES do
		rbox(rig, legs[side], "Foot", V(1.45, 0.55, 1.62), darker(rock, 0.2), rockMat, CF(side * 0.75, 0.275, -0.12))
	end
	local torso = makeTorso(rig, V(2.7, 2.2, 1.9), rock, rockMat, 2.1, V(0, 3.15, 0))
	rell(rig, torso, "Core", V(1.1, 1.1, 0.6), glow, MAT.Neon, CF(0, 3.35, -0.9))
	-- glowing cracks running over the chest
	rbox(rig, torso, "Crack", V(0.14, 1.3, 0.2), glow, MAT.Neon, CF(-0.72, 3.2, -0.97) * ANG(0, 0, 0.5))
	rbox(rig, torso, "Crack", V(0.14, 1.1, 0.2), glow, MAT.Neon, CF(0.75, 2.8, -0.97) * ANG(0, 0, -0.6))
	rbox(rig, torso, "Crack", V(0.14, 0.9, 0.2), glow, MAT.Neon, CF(0.35, 4.0, -0.97) * ANG(0, 0, 0.9))
	rbox(rig, torso, "Belly", V(2.3, 0.6, 1.7), darker(rock, 0.2), rockMat, CF(0, 2.12, 0))
	local arms = makeArms(rig, torso, 1.78, 3.95, V(1.05, 2.2, 1.05), rock, rockMat, 0.15)
	for _, side in SIDES do
		rbox(rig, arms[side], "Fist", V(1.55, 1.35, 1.55), darker(rock, 0.15), rockMat, CF(side * 1.9, 1.75, 0))
		rball(rig, arms[side], "Shoulder", 1.75, rock, rockMat, CF(side * 1.95, 4.1, 0))
		rbox(rig, arms[side], "Crack", V(0.14, 0.9, 0.2), glow, MAT.Neon, CF(side * 1.9, 2.9, -0.55) * ANG(0, 0, side * 0.4))
	end
	local hc, hs = V(0, 4.62, -0.45), V(1.15, 1.0, 1.1)
	local head = makeHead(rig, torso, hs, darker(rock, 0.1), rockMat, V(0, 4.25, -0.2), hc)
	local fz = hc.Z - hs.Z / 2
	rbox(rig, head, "Eye", V(0.8, 0.16, 0.2), rig.eye, MAT.Neon, CF(0, hc.Y + 0.08, fz - 0.02))
	rwedge(rig, head, "Brow", V(1.2, 0.3, 0.36), darker(rock, 0.3), rockMat, CF(0, hc.Y + 0.3, fz - 0.1) * ANG(PI, 0, 0))
	rbox(rig, head, "Mouth", V(0.6, 0.14, 0.2), glow, MAT.Neon, CF(0, hc.Y - 0.26, fz - 0.02))
	if star then
		for i, p in { V(-0.9, 3.6, -0.97), V(1.0, 3.9, -0.97), V(-0.5, 2.5, -0.97) } do
			rbox(rig, torso, "Star", V(0.2, 0.2, 0.2), i == 2 and rig.eye or glow, MAT.Neon, CF(p) * ANG(0, 0, PI / 4))
		end
	end
	return {
		torso = torso,
		head = head,
		arms = arms,
		legs = legs,
		headC = hc,
		headS = hs,
		hand = { [-1] = V(-1.9, 1.75, 0), [1] = V(1.9, 1.75, 0) },
		handS = 1.55,
		shoulderY = 3.95,
		armX = 1.9,
		armW = 1.05,
		chestZ = -0.95,
		backZ = 0.95,
		neckY = 4.25,
		torsoW = 1.35,
		waistY = 2.1,
	}
end

local BIPED_BODIES: { [string]: (Rig) -> Body } = {
	human = bodyHuman,
	knight = bodyHuman,
	small = bodySmall,
	brute = bodyBrute,
	skeleton = bodySkeleton,
	tree = bodyTree,
	robot = bodyRobot,
	robe = bodyRobe,
	golem = bodyGolem,
}

--------------------------------------------------------------------------------
-- BIPED EXTRAS
--------------------------------------------------------------------------------
local function bipedTail(rig: Rig, b: Body, style: string)
	local color = style == "icicle" and rig.c1 or darker(rig.c1, 0.15)
	local y = b.waistY + 0.35
	local z = b.backZ
	local tail = newPart("Tail", V(0.2, 0.2, 1.1) * rig.s, color)
	rjoint(rig, "Tail", b.torso, tail, CF(0, y, z), CF(0, y - 0.2, z + 0.5) * ANG(0.35, 0, 0))
	local tip = CF(0, y - 0.1, z + 1.05) * ANG(-0.9, 0, 0)
	rbox(rig, tail, "Tail", V(0.16, 0.16, 0.9), color, nil, tip * CF(0, 0, 0.35))
	local endCF = tip * CF(0, 0, 0.85)
	if style == "icicle" then
		rwedge(rig, tail, "TailTip", V(0.18, 0.55, 0.3), lighter(rig.c2, 0.5), MAT.Ice, endCF * ANG(-PI / 2, 0, 0))
	else
		rbox(rig, tail, "TailTip", V(0.1, 0.42, 0.42), INK, nil, endCF * ANG(PI / 4, 0, 0))
	end
end

-- Bat wings: a bone from the shoulder blade, a finger bone and two membrane triangles
local function bipedWings(rig: Rig, b: Body)
	local boneColor = darker(rig.c1, 0.3)
	local membrane = darker(rig.c2, 0.1)
	for _, side in SIDES do
		local pivot = V(side * 0.4, b.neckY - 0.35, b.backZ + 0.1)
		local frame = CF(pivot) * ANG(0, -side * 0.35, 0)
		local len = math.sqrt(1.8 * 1.8 + 1.2 * 1.2)
		local bone = newPart("Wing", V(0.16, len, 0.16) * rig.s, boneColor)
		rjoint(rig, side < 0 and "LeftWing" or "RightWing", b.torso, bone, CF(pivot), frame * CF(side * 0.9, 0.6, 0) * ANG(0, 0, -side * math.atan2(1.8, 1.2)))
		rbox(rig, bone, "WingFinger", V(0.12, 2.1, 0.12), boneColor, nil, frame * CF(side * 1.8, 0.15, 0))
		rwedge(rig, bone, "WingMembrane", V(0.06, 1.2, 1.8), membrane, MAT.Fabric, frame * CF(side * 0.9, 0.6, 0) * ANG(0, side * PI / 2, 0))
		rwedge(rig, bone, "WingMembrane", V(0.06, 0.9, 1.8), membrane, MAT.Fabric, frame * CF(side * 0.9, -0.45, 0) * ANG(0, -side * PI / 2, 0) * ANG(PI, 0, 0))
	end
end

local function bipedCape(rig: Rig, b: Body, color: Color3)
	local top = b.neckY - 0.05
	local len = top - 0.5
	local w = b.torsoW * 2 - 0.1
	local cape = newPart("Cape", V(w, len, 0.1) * rig.s, color, MAT.Fabric)
	rjoint(rig, "Cape", b.torso, cape, CF(0, top, b.backZ + 0.12), CF(0, top - len / 2, b.backZ + 0.14) * ANG(0.06, 0, 0))
	for _, side in SIDES do
		rball(rig, b.torso, "CapeClasp", 0.34, GOLD, MAT.Metal, CF(side * (b.torsoW - 0.2), top - 0.1, b.chestZ - 0.05))
	end
end

local function bipedExtras(rig: Rig, b: Body)
	local def = rig.def
	local kind = def.body or "human"
	if def.wings then
		bipedWings(rig, b)
	end
	if def.tail then
		bipedTail(rig, b, def.tail)
	end
	if def.cape or (rig.boss and (kind == "human" or kind == "knight")) then
		bipedCape(rig, b, def.cape and darker(rig.c2, 0.2) or rgb(150, 30, 40))
	end
	if def.sack then -- loot sack on the belt
		rell(rig, b.torso, "Sack", V(0.8, 0.9, 0.7), rgb(150, 120, 80), MAT.Fabric, CF(-0.9, 1.95, 0.3))
		rbox(rig, b.torso, "Coin", V(0.3, 0.3, 0.1), GOLD, MAT.Metal, CF(-0.95, 2.25, -0.12))
	end
	if def.tanks then -- toxic tanks on the back
		for _, side in SIDES do
			local p = V(side * 0.55, 3.9, b.backZ + 0.4)
			rcyl(rig, b.torso, "Tank", V(1.6, 0.7, 0.7), rgb(70, 80, 70), MAT.Metal, CF(p) * UPRIGHT)
			rcyl(rig, b.torso, "TankGlow", V(1.1, 0.78, 0.78), rig.c2, MAT.Neon, CF(p + V(0, 0.1, 0)) * UPRIGHT)
		end
		rchain(rig, b.torso, "Hose", CF(0.55, 4.8, b.backZ + 0.4) * ANG(-0.4, 0, 0.6), { { 0.6, 0.16 }, { 0.6, 0.16, -0.8 }, { 0.5, 0.16, -0.6 } }, INK, MAT.Rubber)
		for i, p in { V(-1.0, 3.4, -0.86), V(0.8, 4.3, -0.83), V(0.5, 2.9, -0.86) } do
			rball(rig, b.torso, "Pustule", i == 1 and 0.4 or 0.3, rig.c2, MAT.Neon, CF(p))
		end
	end
	if def.beard then
		local c, sz = b.headC, b.headS
		local fz = c.Z - sz.Z / 2
		if def.hat == "nemes" then -- pharaoh's false beard
			rbox(rig, b.head, "Beard", V(0.3, 0.6, 0.3), GOLD, MAT.Foil, CF(0, c.Y - sz.Y / 2 - 0.2, fz + 0.1))
			rbox(rig, b.head, "BeardStripe", V(0.36, 0.12, 0.36), rig.c2, nil, CF(0, c.Y - sz.Y / 2 - 0.16, fz + 0.1))
		elseif kind == "brute" then -- long white beard
			rwedge(rig, b.head, "Beard", V(1.2, 1.5, 0.5), lighter(rig.c2, 0.2), MAT.Fabric, CF(0, c.Y - 0.95, fz - 0.1) * ANG(PI, 0, 0))
			rbox(rig, b.head, "Moustache", V(0.9, 0.2, 0.24), lighter(rig.c2, 0.2), MAT.Fabric, CF(0, c.Y - 0.25, fz - 0.08))
		end
	end
	if def.spikes then
		local color = def.crownStyle == "ice" and lighter(rig.c2, 0.3) or (kind == "golem" and darker(rig.c1, 0.35) or IRON)
		local mat = def.crownStyle == "ice" and MAT.Ice or (kind == "golem" and MAT.Basalt or MAT.Metal)
		for _, side in SIDES do
			for i = 0, 1 do
				rwedge(rig, b.arms[side], "Spike", V(0.24, 0.8 - i * 0.2, 0.46), color, mat, CF(side * (b.armX + 0.1 + i * 0.35), b.shoulderY + 0.55 - i * 0.12, 0.1 - i * 0.2) * ANG(0, 0, -side * (0.5 + i * 0.4)) * ANG(0, PI / 2, 0))
			end
		end
		for i = 0, 2 do
			rwedge(rig, b.torso, "Spike", V(0.28, 0.8, 0.5), color, mat, CF(0, b.neckY - 0.35 - i * 0.6, b.backZ + 0.12) * ANG(-1.1, 0, 0))
		end
	end
	if def.glow then
		light(b.torso, rig.c2, 10 * rig.s, 1.2)
	end
end

--------------------------------------------------------------------------------
-- TIER DRESSING (elite: armour trim + faint aura, boss: heavy armour, glow, light)
--------------------------------------------------------------------------------
local function pauldrons(rig: Rig, b: Body, big: boolean)
	local def = rig.def
	local kind = def.body or "human"
	local k = (big and 1.2 or 1) * math.max(b.armW / 0.7, 0.75)
	for _, side in SIDES do
		local arm = b.arms[side]
		local p = V(side * (b.armX + 0.08 * k), b.shoulderY + 0.2, 0)
		if kind == "tree" then
			rball(rig, arm, "Pauldron", 1.3 * k, darker(rig.c2, 0.15), MAT.LeafyGrass, CF(p + V(0, 0.25, 0)))
			rwedge(rig, arm, "Thorn", V(0.2, 0.7, 0.4), darker(rig.c1, 0.3), MAT.Wood, CF(p + V(side * 0.3, 0.8, 0)) * ANG(0, 0, -side * 0.4) * ANG(0, PI / 2, 0))
		elseif kind == "golem" then
			local rockMat = rig.def.crownStyle == "star" and MAT.Slate or MAT.Basalt
			rball(rig, arm, "Pauldron", 1.35 * k, darker(rig.c1, 0.2), rockMat, CF(p + V(side * 0.2, 0.75, 0.1)))
			rwedge(rig, arm, "Spike", V(0.34, 0.9, 0.6) * k, darker(rig.c1, 0.3), rockMat, CF(p + V(side * 0.35, 1.45, 0.1)) * ANG(0, 0, -side * 0.35) * ANG(0, PI / 2, 0))
			rbox(rig, arm, "Crack", V(0.14, 0.7, 0.2) * k, rig.c2, MAT.Neon, CF(p + V(side * 0.25, 0.7, -0.66 * k)) * ANG(0, 0, side * 0.5))
		elseif kind == "knight" then
			for i = 0, (big and 1 or 0) do
				rwedge(rig, arm, "Spike", V(0.2, 0.7, 0.42), darker(rig.c1, 0.2), MAT.Metal, CF(p + V(side * (0.25 + i * 0.3), 0.55 - i * 0.12, -0.15 + i * 0.3)) * ANG(0, 0, -side * 0.35) * ANG(0, PI / 2, 0))
			end
		elseif kind == "robe" then
			-- sorcerers get a layered fabric mantle and a glowing clasp instead of metal
			local void = rig.def.crownStyle == "void"
			local cloth = void and darker(rig.c1, 0.2) or lighter(rig.c2, 0.2)
			rell(rig, arm, "Mantle", V(b.armW + 0.6, 0.6, b.armW + 0.6) * (big and 1.15 or 1), cloth, MAT.Fabric, CF(p + V(0, -0.02, 0)))
			rball(rig, arm, "MantleGem", big and 0.36 or 0.28, void and rig.c2 or rig.eye, MAT.Neon, CF(p + V(side * (b.armW / 2 + 0.28), 0.02, -0.1)))
		else
			local metal = kind == "robot" and darker(rig.c2, 0.1) or (big and rgb(118, 112, 126) or rgb(158, 162, 174))
			local w = (b.armW + 0.55) * (big and 1.12 or 1)
			rell(rig, arm, "Pauldron", V(w, 0.64 * (big and 1.12 or 1), w - 0.05), metal, kind == "robot" and MAT.DiamondPlate or MAT.Metal, CF(p + V(0, -0.02, 0)))
			rell(rig, arm, "PauldronTrim", V(w + 0.12, 0.2, w + 0.07), big and GOLD or darker(metal, 0.35), MAT.Metal, CF(p + V(0, -0.2, 0)))
			if big then
				rwedge(rig, arm, "Spike", V(0.22, 0.75, 0.44), rgb(225, 225, 235), MAT.Metal, CF(p + V(side * 0.15, 0.55, 0)) * ANG(0, 0, -side * 0.3) * ANG(0, PI / 2, 0))
			end
		end
	end
end

local function dressBiped(rig: Rig, b: Body)
	if not (rig.elite or rig.boss) then
		return
	end
	pauldrons(rig, b, rig.boss)
	local kind = rig.def.body or "human"
	if kind ~= "tree" and kind ~= "golem" and kind ~= "robe" then
		rbox(rig, b.torso, "EliteBuckle", V(0.46, 0.36, 0.2), rig.boss and GOLD or rgb(210, 150, 60), MAT.Metal, CF(0, b.waistY + 0.2, b.chestZ - 0.28))
	end
	sparkles(b.torso, rig.c2, rig.boss and 8 or 3, (rig.boss and 0.55 or 0.4) * rig.s)
	if rig.boss then
		light(b.torso, rig.c2, 18 * rig.s, 2)
	end
end

local function buildBiped(rig: Rig)
	local def = rig.def
	local b = (BIPED_BODIES[def.body or "human"] or bodyHuman)(rig)
	local c, sz, head = b.headC, b.headS, b.head
	local top = c.Y + sz.Y / 2
	if def.hat == "hood" then
		hood(rig, b, darker(rig.c2, 0.1))
	elseif def.hat == "witch" then
		witchHat(rig, b, darker(rig.c2, 0.15), rgb(120, 220, 90))
	elseif def.hat == "nemes" then
		nemes(rig, b)
	end
	if def.helmet and def.body ~= "robot" then
		helmet(rig, b, def.helm or "great")
		top += 0.3
	end
	if def.ears then
		ears(rig, head, c, sz, def.earStyle or "pointy", def.body == "small" and rig.c1 or darker(rig.c1, 0.1))
	end
	if def.horns then
		horns(rig, head, c, sz, def.hornStyle or "curved")
	end
	local style = def.crownStyle
	if not style and (def.crown or (rig.boss and not def.hat and not def.helmet)) then
		style = "gold"
	end
	if style == "branch" then
		for _, side in SIDES do
			local start = CF(side * 0.7, top - 0.6, c.Z + 0.1) * ANG(0, 0, -side * 0.35)
			rchain(rig, head, "Antler", start, { { 0.9, 0.3 }, { 0.8, 0.24, 0, -side * 0.5 }, { 0.6, 0.18, 0, side * 0.9 } }, darker(rig.c1, 0.2), MAT.Wood)
			rchain(rig, head, "Antler", CF(side * 1.05, top + 0.1, c.Z + 0.1) * ANG(0, 0, -side * 1.1), { { 0.55, 0.18 }, { 0.4, 0.14, 0, side * 0.8 } }, darker(rig.c1, 0.2), MAT.Wood)
		end
	elseif style then
		local r = math.min(sz.X, sz.Z) * 0.48
		crown(rig, head, style, c, top, r)
	end
	bipedExtras(rig, b)
	if def.weapon then
		mobWeapon(rig, b, def.weapon)
	end
	if def.shield then
		mobShield(rig, b, def.shield)
	end
	dressBiped(rig, b)
end

--------------------------------------------------------------------------------
-- QUADRUPEDS
--------------------------------------------------------------------------------
type QuadSpec = {
	body: Vector3,
	bodyC: Vector3,
	chest: Vector3?,
	chestC: Vector3?,
	head: Vector3,
	headC: Vector3,
	neck: Vector3,
	legX: number,
	legY: number,
	legFZ: number,
	legBZ: number,
	leg: Vector3,
	paw: Vector3,
	tail: Vector3,
	snout: number,
}

local QUADS: { [string]: QuadSpec } = {
	wolf = { body = V(1.55, 1.45, 3.1), bodyC = V(0, 2.35, 0.1), chest = V(1.8, 1.8, 1.6), chestC = V(0, 2.45, -0.95), head = V(1.15, 1.0, 1.1), headC = V(0, 3.15, -2.05), neck = V(0, 2.8, -1.55), legX = 0.5, legY = 1.9, legFZ = -1.05, legBZ = 1.15, leg = V(0.42, 1.84, 0.48), paw = V(0.55, 0.3, 0.72), tail = V(0, 2.75, 1.55), snout = 0.95 },
	hound = { body = V(1.4, 1.3, 3.1), bodyC = V(0, 2.4, 0.1), chest = V(1.6, 1.65, 1.5), chestC = V(0, 2.5, -0.95), head = V(1.05, 0.95, 1.05), headC = V(0, 3.15, -2.05), neck = V(0, 2.85, -1.55), legX = 0.48, legY = 1.95, legFZ = -1.05, legBZ = 1.15, leg = V(0.38, 1.9, 0.44), paw = V(0.5, 0.3, 0.66), tail = V(0, 2.8, 1.55), snout = 1.05 },
	beast = { body = V(1.75, 1.6, 3.0), bodyC = V(0, 2.4, 0.25), chest = V(2.2, 2.1, 1.9), chestC = V(0, 2.85, -0.85), head = V(1.3, 1.1, 1.2), headC = V(0, 3.05, -2.2), neck = V(0, 2.95, -1.7), legX = 0.58, legY = 1.95, legFZ = -1.05, legBZ = 1.2, leg = V(0.52, 1.9, 0.58), paw = V(0.68, 0.32, 0.86), tail = V(0, 2.7, 1.65), snout = 1.05 },
	ram = { body = V(2.0, 1.8, 3.3), bodyC = V(0, 2.3, 0.1), chest = V(2.1, 1.95, 1.4), chestC = V(0, 2.5, -1.05), head = V(1.2, 1.05, 1.2), headC = V(0, 2.95, -2.0), neck = V(0, 2.7, -1.5), legX = 0.6, legY = 1.85, legFZ = -1.15, legBZ = 1.2, leg = V(0.5, 1.8, 0.56), paw = V(0.62, 0.34, 0.78), tail = V(0, 2.7, 1.65), snout = 0.7 },
	boar = { body = V(2.2, 1.9, 3.5), bodyC = V(0, 2.2, 0.1), head = V(1.35, 1.2, 1.15), headC = V(0, 2.35, -2.0), neck = V(0, 2.4, -1.5), legX = 0.62, legY = 1.6, legFZ = -1.2, legBZ = 1.2, leg = V(0.5, 1.56, 0.56), paw = V(0.62, 0.3, 0.78), tail = V(0, 2.55, 1.8), snout = 0.5 },
	rat = { body = V(1.9, 1.75, 3.0), bodyC = V(0, 2.35, 0.3), head = V(1.2, 1.05, 1.5), headC = V(0, 2.5, -1.8), neck = V(0, 2.55, -1.2), legX = 0.55, legY = 1.8, legFZ = -0.95, legBZ = 1.2, leg = V(0.34, 1.76, 0.36), paw = V(0.46, 0.22, 0.6), tail = V(0, 2.4, 1.7), snout = 0.9 },
	cat = { body = V(1.5, 1.25, 3.4), bodyC = V(0, 2.3, 0.1), chest = V(1.62, 1.5, 1.4), chestC = V(0, 2.35, -1.05), head = V(1.05, 0.9, 1.0), headC = V(0, 2.95, -2.05), neck = V(0, 2.7, -1.6), legX = 0.45, legY = 1.85, legFZ = -1.1, legBZ = 1.2, leg = V(0.36, 1.8, 0.42), paw = V(0.5, 0.26, 0.64), tail = V(0, 2.55, 1.75), snout = 0.45 },
}

-- Long muzzle with a black nose, glowing eyes, a hinged jaw with fangs
local function muzzle(rig: Rig, head: BasePart, hc: Vector3, hs: Vector3, len: number, color: Color3)
	local fz = hc.Z - hs.Z / 2
	local sy = hc.Y - hs.Y * 0.2
	rbox(rig, head, "Snout", V(hs.X * 0.62, hs.Y * 0.46, len), color, nil, CF(0, sy, fz - len / 2 + 0.12))
	rbox(rig, head, "Nose", V(0.34, 0.22, 0.2), INK, nil, CF(0, sy + hs.Y * 0.2, fz - len + 0.12))
	local jaw = newPart("Jaw", V(hs.X * 0.54, 0.2, len * 0.86) * rig.s, darker(color, 0.1))
	rjoint(rig, "Jaw", head, jaw, CF(0, sy - hs.Y * 0.28, fz + 0.1), CF(0, sy - hs.Y * 0.35, fz - len * 0.43 + 0.1))
	for _, side in SIDES do
		tri(rig, head, "Fang", V(side * hs.X * 0.22, sy - hs.Y * 0.3, fz - len + 0.3), side, 0.12, 0.26, 0.1, BONE)
	end
end

local function quadTail(rig: Rig, body: BasePart, spec: QuadSpec, style: string, color: Color3)
	local p = spec.tail
	local s = rig.s
	if style == "bushy" then
		local tail = ellipsoid("Tail", V(0.55, 0.55, 1.6) * s, color)
		rjoint(rig, "TailJoint", body, tail, CF(p), CF(p) * ANG(-0.55, 0, 0) * CF(0, 0, 0.7))
		rell(rig, tail, "TailTip", V(0.44, 0.44, 0.8), lighter(color, 0.3), nil, CF(p) * ANG(-0.55, 0, 0) * CF(0, 0, 1.45))
	elseif style == "flame" then
		local tail = newPart("Tail", V(0.3, 0.3, 1.2) * s, color, MAT.Basalt)
		rjoint(rig, "TailJoint", body, tail, CF(p), CF(p) * ANG(-0.7, 0, 0) * CF(0, 0, 0.55))
		for i = 0, 2 do
			rwedge(rig, tail, "Flame", V(0.16, 0.7 - i * 0.15, 0.5 - i * 0.1), i == 1 and rgb(255, 220, 90) or rig.c2, MAT.Neon, CF(p) * ANG(-0.7, 0, 0) * CF(0, 0.1, 1.15 + i * 0.12) * ANG(0, (i - 1) * 1.1, 0))
		end
	elseif style == "rat" or style == "long" then
		local tailColor = style == "rat" and rgb(215, 150, 150) or color
		local t1 = newPart("Tail", V(0.24, 0.24, 1.5) * s, tailColor)
		local a1 = style == "rat" and 0.15 or -0.5
		rjoint(rig, "TailJoint", body, t1, CF(p), CF(p) * ANG(a1, 0, 0) * CF(0, 0, 0.68))
		local p2 = CF(p) * ANG(a1, 0, 0) * CF(0, 0, 1.36)
		local t2 = newPart("Tail2", V(0.18, 0.18, 1.4) * s, tailColor)
		local a2 = style == "rat" and -0.25 or -0.45
		rjoint(rig, "Tail2", t1, t2, p2, p2 * ANG(a2, 0, 0) * CF(0, 0, 0.64))
		if style == "long" then
			rball(rig, t2, "TailTip", 0.36, rig.c2, MAT.Neon, p2 * ANG(a2, 0, 0) * CF(0, 0, 1.36))
		end
	else -- thin with a tuft (boar / ram)
		local tail = newPart("Tail", V(0.14, 0.14, 0.9) * s, color)
		rjoint(rig, "TailJoint", body, tail, CF(p), CF(p) * ANG(0.5, 0, 0) * CF(0, 0, 0.4))
		rell(rig, tail, "Tuft", V(0.34, 0.5, 0.34), darker(color, 0.3), MAT.Fabric, CF(p) * ANG(0.5, 0, 0) * CF(0, 0, 0.9))
	end
end

local function buildQuad(rig: Rig)
	local def, s = rig.def, rig.s
	local kind = def.body or "wolf"
	local spec = QUADS[kind] or QUADS.wolf
	local c1, c2 = rig.c1, rig.c2
	local belly = lighter(c1, 0.3)
	local mat: Enum.Material? = nil
	if kind == "hound" then
		mat = MAT.Basalt
		belly = darker(c1, 0.2)
	elseif kind == "cat" then
		belly = lighter(c1, 0.1)
	end
	-- body
	local body = ellipsoid("Body", spec.body * s, c1, mat)
	local tilt = kind == "beast" and ANG(0.12, 0, 0) or CF()
	rjoint(rig, "Body", rig.root, body, CF(0, 2.2, 0), CF(spec.bodyC) * tilt)
	if spec.chest and spec.chestC then
		rell(rig, body, "Chest", spec.chest, c1, mat, CF(spec.chestC))
	end
	rell(rig, body, "Belly", V(spec.body.X * 0.75, spec.body.Y * 0.45, spec.body.Z * 0.7), belly, mat, CF(spec.bodyC + V(0, -spec.body.Y * 0.27, -0.1)))
	-- head
	local head = newPart("Head", spec.head * s, c1, mat)
	rjoint(rig, "Neck", body, head, CF(spec.neck), CF(spec.headC))
	local hc, hs = spec.headC, spec.head
	local fz = hc.Z - hs.Z / 2
	-- legs with paws (hooves for boar / ram)
	local names = { "LegFL", "LegFR", "LegBL", "LegBR" }
	local legColor = kind == "boar" and darker(c1, 0.2) or c1
	for i, name in names do
		local side = (i == 1 or i == 3) and -1 or 1
		local back = i >= 3
		local z = back and spec.legBZ or spec.legFZ
		local x = side * spec.legX
		local leg = newPart(name, spec.leg * s, legColor, mat)
		rjoint(rig, name, rig.root, leg, CF(x, spec.legY, z), CF(x, spec.legY + 0.06 - spec.leg.Y / 2, z))
		local hoof = kind == "boar" or kind == "ram"
		rbox(rig, leg, hoof and "Hoof" or "Paw", spec.paw, hoof and rgb(50, 40, 36) or (kind == "rat" and rgb(215, 150, 150) or darker(c1, 0.25)), mat, CF(x, spec.paw.Y / 2, z + spec.leg.Z / 2 + 0.1 - spec.paw.Z / 2))
		if back and kind ~= "boar" and kind ~= "rat" then
			rell(rig, leg, "Haunch", V(spec.leg.X + 0.28, 1.1, 1.0), c1, mat, CF(x, spec.legY - 0.2, z + 0.05))
		end
		if kind == "beast" and not back then
			for k = -1, 1, 2 do
				tri(rig, leg, "Claw", V(x + k * 0.15, 0.2, z - 0.1 - spec.paw.Z / 2 - 0.06), k, 0.14, 0.3, 0.12, BONE)
			end
		end
	end

	if kind == "boar" then
		rcyl(rig, head, "Snout", V(0.42, 0.72, 0.72), rgb(205, 140, 130), nil, CF(0, hc.Y - 0.25, fz - 0.16) * FACING)
		for _, side in SIDES do
			rball(rig, head, "Nostril", 0.16, INK, nil, CF(side * 0.14, hc.Y - 0.24, fz - 0.37))
		end
		eyes(rig, head, fz, 0.36, hc.Y + 0.22, 0.2, 0.2)
		brows(rig, head, fz, 0.37, hc.Y + 0.4, 0.34, darker(c2, 0.4), 0.35)
		for _, side in SIDES do
			rchain(rig, head, "Tusk", CF(side * 0.44, hc.Y - 0.45, fz - 0.08) * ANG(-0.25, 0, -side * 0.25), { { 0.45, 0.2 }, { 0.42, 0.15, -0.65, side * 0.35 } }, BONE, nil)
			rwedge(rig, head, "Ear", V(0.14, 0.42, 0.42), darker(c1, 0.15), nil, CF(side * 0.5, hc.Y + hs.Y / 2 + 0.12, hc.Z + 0.2) * ANG(-0.5, 0, -side * 0.3))
		end
		for i = 0, 2 do
			rwedge(rig, body, "Bristle", V(0.3, 0.55, 0.9), darker(c2, 0.25), MAT.Fabric, CF(0, 3.05 - i * 0.08, -1.0 + i * 0.75))
		end
	elseif kind == "rat" then
		rell(rig, head, "Snout", V(0.62, 0.52, 0.95), c1, nil, CF(0, hc.Y - 0.2, fz - 0.2))
		rball(rig, head, "Nose", 0.26, rgb(230, 140, 150), nil, CF(0, hc.Y - 0.12, fz - 0.64))
		for _, side in SIDES do
			rbox(rig, head, "Tooth", V(0.12, 0.26, 0.1), rgb(250, 240, 200), nil, CF(side * 0.07, hc.Y - 0.5, fz - 0.4))
			rcyl(rig, head, "Ear", V(0.12, 0.8, 0.8), c1, nil, CF(side * 0.52, hc.Y + 0.55, hc.Z + 0.1) * FACING)
			rcyl(rig, head, "EarInner", V(0.12, 0.52, 0.52), rgb(230, 150, 160), nil, CF(side * 0.52, hc.Y + 0.52, hc.Z - 0.02) * FACING)
			rball(rig, head, "Eye", 0.24, rig.eye, MAT.Neon, CF(side * 0.33, hc.Y + 0.2, fz + 0.12))
		end
		for i, p in { V(-0.35, 3.15, 0.2), V(0.4, 3.05, 0.9), V(0.1, 3.2, -0.45) } do
			rball(rig, body, "Pustule", i == 1 and 0.5 or 0.36, c2, MAT.Neon, CF(p))
		end
	elseif kind == "ram" then
		rbox(rig, head, "Muzzle", V(0.85, 0.5, 0.7), lighter(c1, 0.2), nil, CF(0, hc.Y - 0.2, fz - 0.25))
		for _, side in SIDES do
			rball(rig, head, "Nostril", 0.14, INK, nil, CF(side * 0.18, hc.Y - 0.14, fz - 0.6))
		end
		eyes(rig, head, fz, 0.36, hc.Y + 0.18, 0.24, 0.16)
		brows(rig, head, fz, 0.37, hc.Y + 0.34, 0.36, darker(c2, 0.4), 0.35)
		for i = 0, 3 do
			rwedge(rig, body, "Spike", V(0.24, 0.62, 0.55), darker(c2, 0.35), nil, CF(0, 3.1 - i * 0.02, -0.6 + i * 0.62))
		end
	else
		-- wolves, hounds, beasts, cats
		local len = spec.snout
		muzzle(rig, head, hc, hs, len, kind == "hound" and c1 or (kind == "cat" and c1 or lighter(c1, 0.2)))
		eyes(rig, head, fz, hs.X * 0.27, hc.Y + hs.Y * 0.16, 0.24, kind == "cat" and 0.14 or 0.18)
		brows(rig, head, fz, hs.X * 0.28, hc.Y + hs.Y * 0.32, 0.32, darker(c1, 0.55), 0.3)
		if kind == "hound" then
			rbox(rig, head, "Maw", V(hs.X * 0.44, 0.1, len * 0.7), c2, MAT.Neon, CF(0, hc.Y - hs.Y * 0.44, fz - len * 0.3))
		end
	end
	if def.ears and kind ~= "rat" then
		for _, side in SIDES do
			local tall = (kind == "beast" or kind == "cat") and 0.8 or 0.62
			rwedge(rig, head, "Ear", V(0.16, tall, 0.44), darker(c1, 0.12), mat, CF(side * hs.X * 0.33, hc.Y + hs.Y / 2 + tall * 0.38, hc.Z + 0.1) * ANG(0, 0, -side * 0.28) * ANG(0, side * PI / 2, 0))
			if kind == "cat" then
				rwedge(rig, head, "EarGlow", V(0.1, 0.46, 0.24), c2, MAT.Neon, CF(side * hs.X * 0.33, hc.Y + hs.Y / 2 + 0.24, hc.Z - 0.02) * ANG(0, 0, -side * 0.28) * ANG(0, side * PI / 2, 0))
			end
		end
	end
	if def.horns and kind ~= "ram" then
		horns(rig, head, hc, hs, def.hornStyle or "curved")
	elseif def.horns then
		horns(rig, head, hc, hs, "ram")
	end
	-- manes, ruffs, shards, cracks, stripes
	if def.mane then
		local maneColor = kind == "ram" and darker(c2, 0.1) or c2
		rell(rig, body, "Mane", V(spec.body.X + 0.55, spec.body.Y + 0.55, 1.7), maneColor, MAT.Fabric, CF(0, (spec.chestC or spec.bodyC).Y + 0.25, -1.0))
		if kind == "beast" then
			for i = -1, 1 do
				rwedge(rig, body, "FurSpike", V(0.3, 0.75, 0.6), maneColor, MAT.Fabric, CF(i * 0.55, 4.0 - math.abs(i) * 0.2, -0.75) * ANG(-0.4, 0, -i * 0.35))
			end
			rell(rig, body, "Shorts", V(spec.body.X + 0.12, 0.9, 1.25), rgb(70, 80, 140), MAT.Fabric, CF(0, 2.25, 1.2))
		end
	end
	if def.ruff then
		rell(rig, body, "Ruff", V(1.95, 1.5, 1.2), WHITE, MAT.Fabric, CF(0, 2.65, -1.35))
	end
	if def.shards then
		for i = 0, 2 do
			rwedge(rig, body, "IceShard", V(0.2, 0.75 - i * 0.12, 0.5), rgb(170, 220, 255), MAT.Ice, CF(0, 3.05, -0.4 + i * 0.6) * ANG(-0.2, 0, (i - 1) * 0.3))
		end
	end
	if kind == "hound" then
		for _, side in SIDES do
			rbox(rig, body, "Crack", V(0.18, 0.14, 1.9), c2, MAT.Neon, CF(side * 0.63, 2.45, 0.3) * ANG(0, 0, side * 0.3) * ANG(0.2, 0, 0))
		end
		for i = 0, 3 do
			rwedge(rig, body, "Flame", V(0.18, 0.7 - i * 0.1, 0.5), i % 2 == 0 and c2 or rgb(255, 220, 90), MAT.Neon, CF(0, 3.2 - i * 0.12, -1.3 + i * 0.45))
		end
	elseif kind == "cat" then
		for i = 0, 2 do
			rell(rig, body, "Stripe", V(spec.body.X + 0.06, spec.body.Y * 0.95 + 0.04, 0.24), c2, MAT.Neon, CF(spec.bodyC + V(0, 0.02, -0.3 + i * 0.7)))
		end
		for i, p in { V(0.4, 2.9, 0.6), V(-0.45, 2.75, -0.2), V(0.15, 2.95, 1.2) } do
			rball(rig, body, "Star", i == 2 and 0.2 or 0.14, WHITE, MAT.Neon, CF(p))
		end
	end
	local tailStyle = kind == "hound" and "flame" or (kind == "rat" and "rat" or (kind == "cat" and "long" or ((kind == "boar" or kind == "ram") and "thin" or "bushy")))
	quadTail(rig, body, spec, tailStyle, kind == "beast" and c2 or c1)

	-- tiers
	if rig.elite or rig.boss then
		local neckC = (spec.neck + spec.headC) / 2
		rell(rig, head, "Collar", V(hs.X + 0.45, hs.Y + 0.35, 0.55), rgb(52, 40, 34), MAT.Leather, CF(neckC + V(0, -0.1, 0.35)))
		for k = -1, 1 do
			rwedge(rig, head, "CollarSpike", V(0.18, 0.5, 0.36), rgb(200, 200, 210), MAT.Metal, CF(neckC + V(k * 0.45, 0.45 - math.abs(k) * 0.12, 0.35)) * ANG(0, 0, -k * 0.5) * ANG(0, PI / 2, 0))
		end
		rell(rig, body, "Armor", V(spec.body.X * 0.8, 0.5, spec.body.Z * 0.5), rig.boss and GOLD or IRON, MAT.Metal, CF(spec.bodyC + V(0, spec.body.Y / 2 - 0.05, 0.2)))
		sparkles(body, c2, rig.boss and 8 or 3, (rig.boss and 0.55 or 0.4) * s)
	end
	if rig.boss then
		crown(rig, head, def.crownStyle or "gold", hc, hc.Y + hs.Y / 2, math.min(hs.X, hs.Z) * 0.42)
		light(body, c2, 18 * s, 2)
	end
	if def.glow then
		light(body, c2, 10 * s, 1.2)
	end
end

--------------------------------------------------------------------------------
-- BLOBS (slimes)
--------------------------------------------------------------------------------
local function buildBlob(rig: Rig)
	local def, s, c1, c2 = rig.def, rig.s, rig.c1, rig.c2
	local body = ellipsoid("Body", V(3.6, 2.8, 3.6) * s, c1, MAT.SmoothPlastic)
	body.Transparency = 0.18
	rjoint(rig, "Body", rig.root, body, CF(0, 0.1, 0), CF(0, 1.45, 0))
	rell(rig, body, "Puddle", V(4.1, 0.55, 4.1), c2, nil, CF(0, 0.26, 0)).Transparency = 0.2
	local core = rell(rig, body, "Core", V(1.5, 1.3, 1.5), def.crown and GOLD or darker(c2, 0.1), def.crown and MAT.Foil or nil, CF(0, 1.15, 0.35))
	core.Transparency = def.crown and 0 or 0.25
	rell(rig, body, "Shine", V(1.0, 0.55, 0.7), WHITE, nil, CF(-0.85, 2.35, -0.85) * ANG(0.3, -0.6, 0.35)).Transparency = 0.25
	rball(rig, body, "Shine", 0.3, WHITE, MAT.Neon, CF(-0.35, 2.62, -1.05))
	-- face
	for _, side in SIDES do
		rell(rig, body, "EyeWhite", V(0.74, 0.95, 0.4), WHITE, nil, CF(side * 0.62, 1.72, -1.62))
		rell(rig, body, "Eye", V(0.42, 0.6, 0.3), rig.eye, nil, CF(side * 0.58, 1.66, -1.8))
		rball(rig, body, "EyeShine", 0.16, WHITE, MAT.Neon, CF(side * 0.5, 1.84, -1.93))
		rell(rig, body, "Cheek", V(0.46, 0.24, 0.2), rgb(255, 140, 170), nil, CF(side * 1.08, 1.3, -1.42))
	end
	rell(rig, body, "Mouth", V(0.72, 0.32, 0.3), INK, nil, CF(0, 1.12, -1.72))
	rell(rig, body, "Tongue", V(0.34, 0.14, 0.22), rgb(255, 110, 140), nil, CF(0, 1.02, -1.8))
	if def.crown or rig.boss then
		for _, side in SIDES do
			rbox(rig, body, "Brow", V(0.6, 0.16, 0.26), darker(c2, 0.4), nil, CF(side * 0.62, 2.28, -1.4) * ANG(0, 0, side * 0.25))
		end
		crown(rig, body, "gold", V(0, 2.8, 0.1), 2.7, 0.85)
	end
	if def.cape then
		rwedge(rig, body, "Cape", V(2.6, 1.6, 0.8), rgb(170, 30, 50), MAT.Fabric, CF(0, 1.1, 1.55) * ANG(0, PI, 0))
		rcyl(rig, body, "CapeTrim", V(0.3, 2.9, 2.9), WHITE, MAT.Fabric, CF(0, 2.35, 0.55) * UPRIGHT)
	end
	if rig.elite or rig.boss then
		sparkles(body, c2, rig.boss and 8 or 3, (rig.boss and 0.55 or 0.4) * s)
	end
	if rig.boss then
		light(body, c1, 18 * s, 2)
	end
end

--------------------------------------------------------------------------------
-- FLOATERS
--------------------------------------------------------------------------------
local function spinRing(rig: Rig, count: number, radius: number, y: number, size: number, color: Color3, shard: boolean)
	local ring = newPart("Ring", V(0.2, 0.2, 0.2) * rig.s, color)
	ring.Transparency = 1
	rjoint(rig, "Spin", rig.root, ring, CF(0, y, 0), CF(0, y, 0))
	for k = 1, count do
		local a = k * PI * 2 / count
		local p = CF(math.cos(a) * radius, y + (k % 2 == 0 and 0.25 or -0.25), math.sin(a) * radius)
		if shard then
			rbox(rig, ring, "Shard", V(size * 0.5, size, size * 0.5), color, MAT.Neon, p * ANG(0, a, 0.4))
		else
			rball(rig, ring, "Mote", size, color, MAT.Neon, p)
		end
	end
end

local function tentacles(rig: Rig, body: BasePart, count: number, radius: number, y: number, len: number, w: number, color: Color3, tipColor: Color3)
	for k = 1, count do
		local a = (k - 0.5) * PI * 2 / count
		local x, z = math.cos(a) * radius, math.sin(a) * radius
		local t1 = newPart("Tentacle", V(w, len, w) * rig.s, color)
		rjoint(rig, "Tent" .. k, body, t1, CF(x, y, z), CF(x, y - len / 2 + 0.1, z))
		local bend = CF(x, y - len + 0.15, z) * ANG(-math.sin(a) * 0.8, 0, math.cos(a) * 0.8)
		rbox(rig, t1, "Tentacle", V(w * 0.75, len * 0.8, w * 0.75), color, nil, bend * CF(0, -len * 0.38, 0))
		rball(rig, t1, "TentacleTip", w * 1.05, tipColor, MAT.Neon, bend * CF(0, -len * 0.8, 0))
	end
end

local function buildFloater(rig: Rig)
	local def, s, c1, c2 = rig.def, rig.s, rig.c1, rig.c2
	local kind = def.body or "wisp"
	if kind == "eye" then
		-- a huge eyeball with heavy lids, a crown, tentacles and orbiting shards
		local body = newPart("Head", V(2.7, 2.7, 2.7) * s, c1, nil, Enum.PartType.Ball)
		rjoint(rig, "Body", rig.root, body, CF(0, 3.4, 0), CF(0, 3.6, 0))
		rell(rig, body, "Sclera", V(2.15, 2.15, 1.0), rgb(245, 228, 240), nil, CF(0, 3.6, -0.98))
		rcyl(rig, body, "Iris", V(0.2, 1.2, 1.2), rig.eye, MAT.Neon, CF(0, 3.6, -1.46) * FACING)
		rbox(rig, body, "Pupil", V(0.24, 0.88, 0.16), INK, nil, CF(0, 3.6, -1.58))
		rell(rig, body, "Lid", V(2.55, 1.15, 1.7), darker(c1, 0.1), nil, CF(0, 4.45, -0.55) * ANG(-0.35, 0, 0))
		rell(rig, body, "Lid", V(2.45, 0.85, 1.6), darker(c1, 0.1), nil, CF(0, 2.8, -0.6) * ANG(0.3, 0, 0))
		for _, side in SIDES do
			rbox(rig, body, "Vein", V(0.08, 0.6, 0.12), rgb(230, 60, 110), MAT.Neon, CF(side * 0.72, 3.2, -1.22) * ANG(0, side * 0.5, side * 0.6))
		end
		crown(rig, body, "gold", V(0, 3.6, 0.05), 4.75, 0.85)
		tentacles(rig, body, 6, 0.85, 2.65, 1.05, 0.36, darker(c2, 0.55), c2)
		spinRing(rig, 6, 2.4, 3.6, 0.6, c2, true)
		light(body, c2, 12 * s, 1.5)
		return body
	elseif kind == "jelly" then
		local body = ellipsoid("Head", V(3.0, 2.0, 3.0) * s, c1)
		rjoint(rig, "Body", rig.root, body, CF(0, 3.4, 0), CF(0, 4.0, 0))
		rcyl(rig, body, "Rim", V(0.24, 3.15, 3.15), c2, MAT.Neon, CF(0, 3.28, 0) * UPRIGHT)
		rell(rig, body, "Underside", V(2.7, 0.8, 2.7), darker(c1, 0.3), nil, CF(0, 3.15, 0))
		rball(rig, body, "EyeWhite", 0.8, WHITE, MAT.Neon, CF(0, 4.05, -1.3))
		rball(rig, body, "Pupil", 0.42, INK, nil, CF(0, 4.05, -1.62))
		for _, side in SIDES do
			rball(rig, body, "EyeWhite", 0.46, WHITE, MAT.Neon, CF(side * 0.78, 4.35, -1.12))
			rball(rig, body, "Pupil", 0.22, INK, nil, CF(side * 0.8, 4.35, -1.32))
		end
		for i = -1, 1 do
			rwedge(rig, body, "Spine", V(0.18, 0.6, 0.4), c2, MAT.Neon, CF(i * 0.55, 4.95 - math.abs(i) * 0.15, 0.2) * ANG(0, 0, -i * 0.4) * ANG(0, PI / 2, 0))
		end
		tentacles(rig, body, 4, 0.75, 3.1, 1.15, 0.34, darker(c2, 0.5), c2)
		spinRing(rig, 4, 2.4, 4.0, 0.5, c2, true)
		light(body, c2, 12 * s, 1.5)
		return body
	elseif kind == "wraith" then
		local body = ellipsoid("Head", V(1.8, 2.0, 1.8) * s, c1, MAT.Fabric)
		rjoint(rig, "Body", rig.root, body, CF(0, 3.4, 0), CF(0, 4.3, 0))
		rell(rig, body, "Face", V(1.2, 1.3, 0.6), INK, nil, CF(0, 4.2, -0.68))
		for _, side in SIDES do
			rball(rig, body, "Eye", 0.3, c2, MAT.Neon, CF(side * 0.26, 4.36, -0.96))
			rbox(rig, body, "EyeRay", V(0.06, 0.5, 0.06), rig.eye, MAT.Neon, CF(side * 0.26, 4.36, -1.05))
			rbox(rig, body, "EyeRay", V(0.5, 0.06, 0.06), rig.eye, MAT.Neon, CF(side * 0.26, 4.36, -1.05))
		end
		rell(rig, body, "Cloak", V(2.4, 2.9, 2.0), c1, MAT.Fabric, CF(0, 2.85, 0.1))
		rcyl(rig, body, "Trim", V(0.16, 1.95, 1.95), c2, MAT.Neon, CF(0, 3.55, 0.05) * UPRIGHT)
		for k = 0, 4 do
			local a = k * PI * 2 / 5
			rwedge(rig, body, "Tatter", V(0.14, 1.0, 0.7), darker(c1, 0.2), MAT.Fabric, CF(math.cos(a) * 0.75, 1.3, math.sin(a) * 0.75) * ANG(0, -a + PI / 2, 0) * ANG(PI, 0, 0))
		end
		for _, side in SIDES do
			local arm = newPart(side < 0 and "LeftArm" or "RightArm", V(0.5, 1.4, 0.5) * s, c1, MAT.Fabric)
			rjoint(rig, side < 0 and "LeftArm" or "RightArm", body, arm, CF(side * 1.0, 3.7, 0), CF(side * 1.2, 3.2, -0.2) * ANG(-0.3, 0, side * 0.2))
			for i = -1, 1 do
				rwedge(rig, arm, "Claw", V(0.08, 0.45, 0.16), c2, MAT.Neon, CF(side * 1.28 + i * 0.12, 2.4, -0.38) * ANG(PI, 0, 0))
			end
		end
		spinRing(rig, 4, 2.2, 3.4, 0.36, c2, true)
		light(body, c2, 12 * s, 1.5)
		return body
	end
	-- wisp: glowing core inside a dark shroud, flame crest, curling tail
	local body = ellipsoid("Head", V(2.2, 2.4, 2.2) * s, c1)
	body.Transparency = 0.3
	rjoint(rig, "Body", rig.root, body, CF(0, 3.4, 0), CF(0, 3.55, 0))
	rball(rig, body, "Core", 1.3, c2, MAT.Neon, CF(0, 3.5, 0.1))
	for i = -1, 1 do
		rwedge(rig, body, "Flame", V(0.2, i == 0 and 1.1 or 0.75, 0.6), i == 0 and lighter(c2, 0.3) or c2, MAT.Neon, CF(i * 0.45, 4.8 - math.abs(i) * 0.2, 0.1) * ANG(0, 0, -i * 0.4) * ANG(0, PI / 2, 0))
	end
	for _, side in SIDES do
		rell(rig, body, "Eye", V(0.46, 0.66, 0.3), rig.eye, MAT.Neon, CF(side * 0.44, 3.68, -0.98))
		rbox(rig, body, "Brow", V(0.5, 0.14, 0.2), INK, nil, CF(side * 0.44, 4.1, -1.02) * ANG(0, 0, side * 0.35))
	end
	rell(rig, body, "Mouth", V(0.5, 0.24, 0.2), INK, nil, CF(0, 3.08, -0.98))
	local tail = ellipsoid("Tail", V(1.5, 1.3, 1.5) * s, c1)
	tail.Transparency = 0.3
	rjoint(rig, "Tail", body, tail, CF(0, 2.6, 0.15), CF(0, 2.25, 0.35))
	rell(rig, tail, "Tail", V(1.0, 1.0, 1.0), c1, nil, CF(0, 1.5, 0.8)).Transparency = 0.3
	rell(rig, tail, "Tail", V(0.55, 0.8, 0.55), c1, nil, CF(0, 0.95, 1.25)).Transparency = 0.3
	rball(rig, tail, "TailTip", 0.34, c2, MAT.Neon, CF(0, 0.6, 1.5))
	spinRing(rig, 3, 1.9, 3.5, 0.36, c2, false)
	light(body, c2, 12 * s, 1.5)
	return body
end

--------------------------------------------------------------------------------
-- BUGS (scorpion)
--------------------------------------------------------------------------------
local function buildBug(rig: Rig)
	local s, c1, c2 = rig.s, rig.c1, rig.c2
	-- root centre is at y = 1.4
	local body = newPart("Body", V(1.9, 0.75, 1.5) * s, c1)
	rjoint(rig, "Body", rig.root, body, CF(0, 1.4, 0), CF(0, 1.45, -0.6))
	rbox(rig, body, "Plate", V(2.04, 0.62, 0.9), c1, nil, CF(0, 1.42, 0.45))
	rbox(rig, body, "Plate", V(1.8, 0.58, 0.85), c1, nil, CF(0, 1.4, 1.2))
	rbox(rig, body, "Plate", V(1.5, 0.54, 0.75), c1, nil, CF(0, 1.38, 1.85))
	rbox(rig, body, "Underside", V(1.6, 0.3, 3.2), c2, nil, CF(0, 1.05, 0.5))
	for i, p in { V(0, 1.85, 0.075), V(0, 1.76, 0.84), V(0, 1.72, 1.55) } do
		rbox(rig, body, "Band", V(1.5 - i * 0.2, 0.1, 0.3), c2, nil, CF(p))
	end
	rbox(rig, body, "Head", V(1.3, 0.6, 0.7), darker(c1, 0.12), nil, CF(0, 1.4, -1.55))
	for _, side in SIDES do
		rball(rig, body, "Eye", 0.24, rig.eye, MAT.Glass, CF(side * 0.26, 1.72, -1.72))
		tri(rig, body, "Mandible", V(side * 0.22, 1.18, -1.95), side, 0.2, 0.3, 0.14, darker(c2, 0.2))
	end
	-- pincers
	for _, side in SIDES do
		local pivot = V(side * 0.72, 1.4, -1.55)
		local arm = newPart(side < 0 and "ClawArmL" or "ClawArmR", V(0.4, 0.4, 1.2) * s, c1)
		rjoint(rig, side < 0 and "ClawL" or "ClawR", body, arm, CF(pivot), CF(pivot) * ANG(0, side * 0.55, 0) * CF(0, 0, -0.55))
		local hand = CF(pivot) * ANG(0, side * 0.55, 0) * CF(0, 0, -1.25) * ANG(0, -side * 0.9, 0)
		rbox(rig, arm, "Pincer", V(0.8, 0.55, 0.9), c1, nil, hand)
		rwedge(rig, arm, "PincerFinger", V(0.3, 0.4, 0.8), darker(c1, 0.1), nil, hand * CF(-side * 0.2, 0, -0.75) * ANG(0, 0, side * PI / 2))
		rwedge(rig, arm, "PincerFinger", V(0.3, 0.4, 0.8), darker(c1, 0.1), nil, hand * CF(side * 0.22, 0, -0.75) * ANG(0, 0, -side * PI / 2))
	end
	-- legs: out, then down to the ground
	local n = 0
	for i = 1, 3 do
		for _, side in SIDES do
			n += 1
			local z = -0.75 + (i - 1) * 0.8
			local pivot = V(side * 0.85, 1.3, z)
			local leg = newPart("Leg" .. n, V(1.1, 0.22, 0.22) * s, c1)
			rjoint(rig, "Leg" .. n, rig.root, leg, CF(pivot), CF(pivot) * ANG(0, 0, side * 0.45) * CF(side * 0.5, 0, 0))
			local knee = CF(pivot) * ANG(0, 0, side * 0.45) * CF(side * 1.0, 0, 0)
			rbox(rig, leg, "Shin", V(0.2, 1.9, 0.2), c2, nil, knee * ANG(0, 0, -side * 0.75) * CF(side * 0.15, -0.82, 0))
		end
	end
	-- tail: three jointed segments arching over the back, glowing stinger
	local p1 = V(0, 1.55, 2.25)
	local t1 = newPart("Tail", V(0.55, 1.0, 0.55) * s, c1)
	local f1 = CF(p1) * ANG(-0.55, 0, 0)
	rjoint(rig, "TailJoint", body, t1, CF(p1), f1 * CF(0, 0.45, 0))
	local p2 = f1 * CF(0, 0.9, 0)
	local f2 = p2 * ANG(-0.75, 0, 0)
	local t2 = newPart("Tail2", V(0.5, 0.95, 0.5) * s, c1)
	rjoint(rig, "Tail2", t1, t2, p2, f2 * CF(0, 0.42, 0))
	local p3 = f2 * CF(0, 0.85, 0)
	local f3 = p3 * ANG(-0.8, 0, 0)
	local t3 = newPart("Tail3", V(0.44, 0.85, 0.44) * s, c1)
	rjoint(rig, "Tail3", t2, t3, p3, f3 * CF(0, 0.38, 0))
	rball(rig, t3, "StingerBulb", 0.6, c2, nil, f3 * CF(0, 0.85, 0))
	rwedge(rig, t3, "Stinger", V(0.2, 0.6, 0.4), rgb(255, 200, 80), MAT.Neon, f3 * CF(0, 1.1, -0.2) * ANG(-2.3, 0, 0))
	if rig.elite or rig.boss then
		rell(rig, body, "Armor", V(1.6, 0.5, 1.2), rig.boss and GOLD or IRON, MAT.Metal, CF(0, 1.78, -0.6))
		sparkles(body, c2, rig.boss and 8 or 3, (rig.boss and 0.55 or 0.4) * s)
	end
	if rig.boss then
		crown(rig, body, "gold", V(0, 1.4, -1.55), 1.7, 0.5)
		light(body, c2, 18 * s, 2)
	end
end

local ARCH: { [string]: { root: Vector3, hip: number, build: (Rig) -> any } } = {
	biped = { root = V(2, 2, 1), hip = 2, build = buildBiped },
	quad = { root = V(2, 1.6, 3.6), hip = 1.4, build = buildQuad },
	blob = { root = V(3, 2.4, 3), hip = 0.3, build = buildBlob },
	floater = { root = V(2, 2, 2), hip = 2.4, build = buildFloater },
	bug = { root = V(2.4, 1, 3.2), hip = 0.9, build = buildBug },
}

-- Returns model, root, humanoid, height (studs from ground to top)
function Models.Mob(def: any, tierName: string, scale: number): (Model, BasePart, Humanoid, number)
	local model = Instance.new("Model")
	model.Name = def.name

	local arch = ARCH[def.arch] or ARCH.biped
	local root = newPart("HumanoidRootPart", arch.root * scale, def.color)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	root.CFrame = CFrame.new(0, 200, 0)
	root.Parent = model
	model.PrimaryPart = root

	local hip = arch.hip * scale
	local rig: Rig = {
		model = model,
		root = root,
		def = def,
		s = scale,
		elite = tierName == "elite",
		boss = tierName == "boss",
		G = root.CFrame * CFrame.new(0, -(hip + root.Size.Y / 2), 0),
		c1 = def.color,
		c2 = def.color2 or darker(def.color, 0.3),
		eye = def.eye or INK,
	}
	arch.build(rig)
	model:SetAttribute("Scale", scale)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = hip
	hum.WalkSpeed = def.speed or 12
	hum.AutoRotate = true
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.NameDisplayDistance = 0
	hum.UseJumpPower = true
	hum.JumpPower = 0
	for _, state in
		{
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Flying,
			Enum.HumanoidStateType.PlatformStanding,
			Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.GettingUp,
			Enum.HumanoidStateType.Jumping,
		}
	do
		hum:SetStateEnabled(state, false)
	end
	hum.Parent = model

	-- highest point above the ground (for the health bar)
	local ground = rig.G.Position.Y
	local top = ground + root.Size.Y + hip
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Mobs"
			if d ~= root and d.Transparency < 1 then
				local cf, size = d.CFrame, d.Size
				local halfY = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
				top = math.max(top, cf.Position.Y + halfY)
			end
		end
	end
	return model, root, hum, top - ground
end

-- Name + health bar floating above a mob. Returns the fill frame.
function Models.HealthBar(model: Model, adornee: BasePart, height: number, title: string, titleColor: Color3, big: boolean): Frame
	local bb = Instance.new("BillboardGui")
	bb.Name = "Bar"
	bb.Size = UDim2.fromOffset(big and 240 or 156, big and 50 or 36)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bb.MaxDistance = big and 260 or 110
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0.54, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = title
	label.TextColor3 = titleColor
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(10, 8, 16)
	label.Parent = bb

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BorderSizePixel = 0
	back.BackgroundColor3 = Color3.fromRGB(28, 24, 36)
	back.Size = UDim2.new(1, 0, 0.36, 0)
	back.Position = UDim2.new(0, 0, 0.6, 0)
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = big and 2.5 or 2
	stroke.Color = big and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(8, 6, 12)
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = big and Color3.fromRGB(255, 70, 90) or Color3.fromRGB(240, 72, 62)
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(175, 160, 170))
	shade.Parent = fill

	bb.Parent = model
	return fill
end

--------------------------------------------------------------------------------
-- WEAPONS. Models.Weapon(key) -> Model
--   PrimaryPart "Handle": its origin is the grip point, the blade/shaft points along the Handle's +Y
--   (bow: limbs in the Y-Z plane, belly toward -Z, string toward +Z; scythe blade reaches toward -Z).
--   One direct child is named "Blade" (staff: "Orb"; bow: the string) — FX tints swings with its Color.
--   Melee styles carry Attachments "TrailBase"/"TrailTip" on the blade and a disabled Trail "SwingTrail"
--   (the staff has a small one on its Orb, the bow none).
--   Daggers are a pair: the off-hand dagger's grip part is "OffHandle" (grip at its origin, blade +Y),
--   welded to Handle by the Weld "OffHandWeld" (parented to OffHandle); every off-hand part is welded to
--   OffHandle, its blade is "OffBlade" and it has its own "SwingTrail".
--   Looks: shapes from the style, theme from the zone (wood, rustic, leaf, bone, gold, ice, flame, scrap,
--   void, star), and rarity tiers: Uncommon gem + wraps, Rare fuller + coloured guard, Epic glowing runes +
--   sparkles, Legendary gold trim + light, Mythic neon edges + aura, Divine/??? floating shards + halo.
--------------------------------------------------------------------------------
type Wpn = {
	model: Model,
	handle: BasePart,
	z: number,
	r: number,
	theme: string,
	color: Color3, -- blade / main colour
	color2: Color3, -- hilt / accent colour
	rc: Color3, -- rarity colour
	metal: Color3, -- guard and fittings (rarity-tinted from Rare)
	metalMat: Enum.Material,
	bladeMat: Enum.Material,
	secret: boolean,
}

local THEMES = { [0] = "wood", "rustic", "leaf", "bone", "gold", "ice", "flame", "scrap", "void", "star" }
local RAINBOW = { rgb(255, 70, 70), rgb(255, 200, 60), rgb(80, 255, 120), rgb(70, 170, 255), rgb(210, 90, 255) }

-- Part at a model-space CFrame (the Handle sits at the origin while building), welded to `parent`
local function wp(w: Wpn, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame, shape: Enum.PartType?, parent: BasePart?): BasePart
	local p = newPart(name, size, color, mat, shape)
	local base = parent or w.handle
	attach(base, p, base.CFrame:ToObjectSpace(cf), w.model)
	return p
end

local function wwedge(w: Wpn, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame, parent: BasePart?): BasePart
	local p = newWedge(name, size, color, mat)
	local base = parent or w.handle
	attach(base, p, base.CFrame:ToObjectSpace(cf), w.model)
	return p
end

local function swingTrail(w: Wpn, part: BasePart, base: Vector3, tip: Vector3, width: number?)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = part.CFrame:PointToObjectSpace(base)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = part.CFrame:PointToObjectSpace(tip)
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Name = "SwingTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(lighter(w.color, 0.25), w.rc)
	t.LightEmission = 0.7
	t.Lifetime = 0.18
	t.MinLength = 0.05
	t.FaceCamera = false
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, width or 0.3) })
	t.Enabled = false
	t.Parent = part
end

local function gemColor(w: Wpn, k: number): Color3
	return w.secret and RAINBOW[(k - 1) % #RAINBOW + 1] or w.rc
end

-- Rarity gem (a ball, visible from both faces)
local function wgem(w: Wpn, cf: CFrame, d: number, parent: BasePart?, k: number?)
	wp(w, "Gem", V(d, d, d), gemColor(w, k or 1), MAT.Neon, cf, Enum.PartType.Ball, parent)
end

-- Grip wraps: two bands (Uncommon+), coloured by the theme / rarity
local function wraps(w: Wpn, frame: CFrame, len: number, thick: number, parent: BasePart?)
	if w.r < 2 then
		return
	end
	local c = w.theme == "leaf" and rgb(90, 170, 70) or (w.theme == "gold" and w.color2 or darker(w.rc, 0.25))
	for _, k in { -0.25, 0.25 } do
		wp(w, "Wrap", V(thick + 0.12, 0.12, thick + 0.12), c, MAT.Fabric, frame * CF(0, k * len, 0), nil, parent)
	end
end

-- Crossguard at `frame` (centre), width gw; themed
local function guard(w: Wpn, frame: CFrame, gw: number, gh: number, gd: number, parent: BasePart?): BasePart
	local th = w.theme
	local metal, mat = w.metal, w.metalMat
	frame = frame * ANG(0, PI / 2, 0) -- the crossbar runs along the blade's width (Z)
	local g = wp(w, "Guard", V(gw, gh, gd), metal, mat, frame, nil, parent)
	local ends = w.r >= 5 and GOLD or metal
	if th == "leaf" then
		for _, side in SIDES do
			wwedge(w, "Leaf", V(0.1, gw * 0.3, gd + 0.14), rgb(90, 190, 80), MAT.Grass, frame * CF(side * gw * 0.46, gh * 0.9, 0) * ANG(0, 0, -side * 0.6), parent)
		end
	elseif th == "bone" then
		for _, side in SIDES do
			wwedge(w, "Fang", V(gd * 0.7, gw * 0.3, 0.2), BONE, nil, frame * CF(side * gw * 0.42, -gh * 1.1, 0) * ANG(PI, side * PI / 2, 0), parent)
		end
	elseif th == "gold" then
		for _, side in SIDES do
			wwedge(w, "Wing", V(0.14, gw * 0.3, gw * 0.42), GOLD, MAT.Foil, frame * CF(side * gw * 0.36, gh * 1.05, 0) * ANG(0, 0, -side * 0.9) * ANG(0, side * PI / 2, 0), parent)
		end
		wp(w, "Lapis", V(gd * 0.5, gd * 0.5, gd + 0.16), rgb(40, 90, 200), MAT.Glass, frame * ANG(0, 0, PI / 4), nil, parent)
	elseif th == "ice" then
		for _, side in SIDES do
			wwedge(w, "Icicle", V(0.16, gw * 0.34, gd * 0.9), rgb(200, 235, 255), MAT.Ice, frame * CF(side * gw * 0.5, gh * 0.2, 0) * ANG(0, 0, -side * 1.9) * ANG(0, side * PI / 2, 0), parent)
		end
	elseif th == "flame" then
		for _, side in SIDES do
			wwedge(w, "Flame", V(0.12, gw * 0.32, gd), w.r >= 3 and w.color or rgb(255, 130, 40), w.r >= 3 and MAT.Neon or nil, frame * CF(side * gw * 0.4, gh * 1.0, 0) * ANG(0, 0, -side * 0.45) * ANG(0, side * PI / 2, 0), parent)
		end
	elseif th == "scrap" then
		for _, side in SIDES do
			wp(w, "Bolt", V(gd + 0.14, gh * 0.8, gh * 0.8), rgb(170, 170, 176), MAT.Metal, frame * CF(side * gw * 0.34, 0, 0) * ANG(0, PI / 2, 0), Enum.PartType.Cylinder, parent)
		end
	elseif th == "void" then
		for _, side in SIDES do
			wp(w, "Crystal", V(gh * 1.2, gh * 1.2, gd + 0.1), w.color2, MAT.Neon, frame * CF(side * (gw / 2 + 0.12), 0, 0) * ANG(0, 0, PI / 4), nil, parent)
		end
	elseif th == "star" then
		for _, side in SIDES do
			wp(w, "StarPoint", V(gh * 1.3, gh * 1.3, gd + 0.1), w.color2, MAT.Neon, frame * CF(side * (gw / 2 + 0.1), 0, 0) * ANG(0, 0, PI / 4), nil, parent)
		end
		wp(w, "StarPoint", V(gh * 1.6, gh * 1.6, gd + 0.16), GOLD, MAT.Foil, frame * ANG(0, 0, PI / 4), nil, parent)
	elseif w.r >= 2 then
		for _, side in SIDES do
			wp(w, "Quillon", V(gh * 1.3, gh * 1.3, gh * 1.3), ends, mat, frame * CF(side * gw / 2, 0, 0), Enum.PartType.Ball, parent)
		end
	end
	if w.r >= 5 and th ~= "gold" and th ~= "star" then
		wp(w, "GoldTrim", V(gw * 0.5, gh + 0.12, gd + 0.12), GOLD, MAT.Foil, frame, nil, parent)
	end
	return g
end

local function pommel(w: Wpn, frame: CFrame, d: number, parent: BasePart?)
	local th = w.theme
	if th == "ice" or th == "void" or th == "star" then
		wp(w, "Pommel", V(d * 0.8, d * 0.8, d * 0.8), th == "ice" and rgb(200, 235, 255) or w.color2, th == "ice" and MAT.Ice or MAT.Neon, frame * ANG(PI / 4, 0, PI / 4), nil, parent)
	elseif th == "scrap" then
		wp(w, "Pommel", V(d * 0.6, d, d), rgb(150, 150, 156), MAT.Metal, frame * UPRIGHT, Enum.PartType.Cylinder, parent)
	else
		local c = th == "gold" and GOLD or (th == "leaf" and rgb(120, 85, 50) or (th == "bone" and BONE or w.metal))
		wp(w, "Pommel", V(d, d, d), w.r >= 5 and GOLD or c, th == "wood" and MAT.Wood or w.metalMat, frame, Enum.PartType.Ball, parent)
	end
	if w.r >= 3 and d > 0.4 then
		wgem(w, frame * CF(0, -d * 0.45, 0), d * 0.45, parent, 2)
	end
end

-- Floating shards (Divine/???): welded with gaps around a point
local function fragments(w: Wpn, center: CFrame, radius: number, count: number, size: number)
	for k = 1, count do
		local a = k * PI * 2 / count
		local c = w.secret and RAINBOW[k % #RAINBOW + 1] or lighter(w.rc, 0.2)
		wp(w, "Fragment", V(size * 0.5, size, size * 0.5), c, MAT.Neon, center * CF(math.cos(a) * radius, (k % 2 == 0 and 1 or -1) * size * 0.8, math.sin(a) * radius) * ANG(0.5, a, 0.3))
	end
end

-- Halo ring of small bits around the frame's Y axis (Divine/???)
local function halo(w: Wpn, center: CFrame, radius: number, count: number, size: number)
	for k = 1, count do
		local a = k * PI * 2 / count
		local c = w.secret and RAINBOW[k % #RAINBOW + 1] or w.rc
		wp(w, "Halo", V(size, size, size), c, MAT.Neon, center * CF(math.cos(a) * radius, 0, math.sin(a) * radius) * ANG(0, -a, PI / 4))
	end
end

local function aura(w: Wpn, part: BasePart)
	if w.r >= 4 then
		local e = sparkles(part, w.rc, 2 + w.r * 2, 0.35)
		if w.secret then
			e.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, RAINBOW[1]),
				ColorSequenceKeypoint.new(0.25, RAINBOW[2]),
				ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
				ColorSequenceKeypoint.new(0.75, RAINBOW[4]),
				ColorSequenceKeypoint.new(1, RAINBOW[5]),
			})
		end
	end
	if w.r >= 5 then
		light(part, w.rc, 6 + w.r, 1)
	end
end

-- Straight double-edged blade from y0 along the frame's +Y; returns the Blade part and its body length
local function straightBlade(w: Wpn, frame: CFrame, name: string, y0: number, len: number, width: number, thick: number, parent: BasePart?): (BasePart, number)
	local tipLen = width * 0.9
	local bodyLen = len - tipLen
	local blade = wp(w, name, V(thick, bodyLen, width), w.color, w.bladeMat, frame * CF(0, y0 + bodyLen / 2, 0), nil, parent)
	for _, side in SIDES do
		wwedge(w, "Tip", V(thick, tipLen, width / 2), w.color, w.bladeMat, frame * CF(0, y0 + bodyLen + tipLen / 2, side * width / 4) * ANG(0, side > 0 and PI or 0, 0), parent)
	end
	return blade, bodyLen
end

-- Rarity + theme decoration of a straight blade
local function dressBlade(w: Wpn, frame: CFrame, y0: number, bodyLen: number, width: number, thick: number, parent: BasePart?)
	local th = w.theme
	-- theme silhouettes along the edges
	if th == "leaf" or th == "flame" or th == "scrap" then
		local n = (bodyLen > 3 and bodyLen < 4) and 3 or 2
		for i = 1, n do
			local y = y0 + bodyLen * (i / (n + 1))
			for _, side in SIDES do
				if th == "leaf" then -- thorns
					wwedge(w, "Thorn", V(thick * 0.6, 0.3, 0.26), rgb(60, 110, 50), nil, frame * CF(0, y, side * (width / 2 + 0.1)) * ANG(0, side > 0 and PI or 0, 0), parent)
				elseif th == "flame" then -- jagged flame edge
					wwedge(w, "FlameEdge", V(thick * 0.7, 0.55, 0.3), w.r >= 6 and w.rc or lighter(w.color, 0.25), w.r >= 6 and MAT.Neon or w.bladeMat, frame * CF(0, y, side * (width / 2 + 0.1)) * ANG(0, side > 0 and PI or 0, 0), parent)
				elseif side > 0 then -- serrated back
					wwedge(w, "Serration", V(thick * 0.7, 0.3, 0.24), darker(w.color, 0.2), MAT.CorrodedMetal, frame * CF(0, y, width / 2 + 0.08) * ANG(0, PI, 0), parent)
				end
			end
		end
	end
	if th == "flame" then -- obsidian spine
		wp(w, "Spine", V(thick + 0.12, bodyLen * 0.85, width * 0.3), rgb(30, 24, 26), MAT.Basalt, frame * CF(0, y0 + bodyLen * 0.46, 0), nil, parent)
	elseif th == "void" or th == "star" then -- glowing core
		wp(w, "Core", V(thick + 0.12, bodyLen * 0.8, width * 0.22), w.color2, MAT.Neon, frame * CF(0, y0 + bodyLen * 0.45, 0), nil, parent)
	elseif th == "scrap" then
		for _, k in { 0.3, 0.65 } do
			wp(w, "Rivet", V(thick + 0.16, 0.18, 0.18), rgb(170, 170, 176), MAT.Metal, frame * CF(0, y0 + bodyLen * k, -width * 0.25), Enum.PartType.Cylinder, parent)
		end
	elseif w.r >= 3 then -- fuller
		wp(w, "Fuller", V(thick + 0.12, bodyLen * 0.72, width * 0.24), darker(w.color, 0.28), w.bladeMat, frame * CF(0, y0 + bodyLen * 0.42, 0), nil, parent)
	end
	if w.r >= 4 then -- glowing rune inlays
		for i = 1, 3 do
			wp(w, "Rune", V(thick + 0.26, 0.16, width * 0.16), gemColor(w, i), MAT.Neon, frame * CF(0, y0 + bodyLen * (0.18 + i * 0.16), 0) * ANG(i % 2 == 0 and 0.35 or -0.35, 0, 0), nil, parent)
		end
	end
	if w.r >= 6 then -- neon edges
		for _, side in SIDES do
			wp(w, "Edge", V(thick * 0.6, bodyLen * 0.94, 0.12), lighter(w.rc, 0.15), MAT.Neon, frame * CF(0, y0 + bodyLen * 0.5, side * (width / 2 + 0.03)), nil, parent)
		end
	end
end

local function weaponCtx(key: string): (Wpn, any, string)
	local def, z, _, _, r = Items.Def(key)
	def = def or Config.Items[0].w[1]
	r = math.max(r, 1)
	local style: string = def.style or "sword"
	local zi = math.clamp(z, 0, 9)
	local theme = THEMES[zi] or "rustic"
	local secret = Config.Rarities[r] ~= nil and Config.Rarities[r].secret == true
	local rc = Items.RarityColor(r)
	local color: Color3 = def.color or rgb(180, 180, 180)
	if secret then
		color = rgb(28, 26, 34)
	end
	local base = theme == "wood" and rgb(130, 90, 55) or (theme == "gold" and GOLD or (theme == "bone" and rgb(200, 195, 185) or IRON))
	if theme == "flame" then
		base = rgb(40, 32, 32)
	elseif theme == "scrap" then
		base = rgb(110, 104, 98)
	elseif theme == "void" or theme == "star" then
		base = darker(def.color2 or rc, 0.5)
	elseif theme == "ice" then
		base = rgb(170, 210, 240)
	end
	local metal = r >= 3 and base:Lerp(rc, 0.55) or base
	local bladeMat = MAT.Metal
	if theme == "wood" then
		bladeMat = MAT.Wood
	elseif theme == "rustic" and style == "sword" then
		bladeMat = MAT.Slate
	elseif theme == "ice" then
		bladeMat = MAT.Ice
	elseif theme == "gold" or theme == "star" then
		bladeMat = MAT.Foil
	elseif theme == "scrap" then
		bladeMat = MAT.CorrodedMetal
	elseif theme == "void" then
		bladeMat = MAT.Glass
	end
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local w: Wpn = {
		model = model,
		handle = model :: any,
		z = zi,
		r = r,
		theme = theme,
		color = color,
		color2 = def.color2 or rgb(90, 60, 40),
		rc = secret and WHITE or rc,
		metal = metal,
		metalMat = theme == "wood" and MAT.Wood or (theme == "ice" and MAT.Ice or (theme == "gold" and MAT.Foil or MAT.Metal)),
		bladeMat = bladeMat,
		secret = secret,
	}
	return w, def, style
end

local function gripPart(w: Wpn, size: Vector3, cf: CFrame, name: string?): BasePart
	local th = w.theme
	local c = th == "wood" and rgb(120, 82, 50) or (th == "gold" and rgb(40, 90, 200) or (th == "scrap" and rgb(40, 40, 44) or w.color2))
	if th ~= "wood" and th ~= "gold" and th ~= "scrap" and lum(w.color2) > 0.6 then
		c = LEATHER
	end
	local mat = th == "wood" and MAT.Wood or (th == "scrap" and MAT.Rubber or MAT.Leather)
	return newPart(name or "Handle", size, c, mat)
end

--------------------------------------------------------------------------------
local function buildSword(w: Wpn, style: string)
	local big = style == "greatsword"
	local gripLen = big and 1.5 or 1.1
	local len = big and 5.2 or 3.45
	local width = big and 1.15 or 0.62
	local thick = big and 0.3 or 0.2
	local gy = gripLen / 2 + 0.12
	local gw = big and 2.1 or 1.35
	guard(w, CF(0, gy, 0), gw, big and 0.34 or 0.24, big and 0.56 or 0.44)
	local y0 = gy + (big and 0.1 or 0.06)
	local blade: BasePart
	if big and w.theme == "scrap" then
		-- Rust Cleaver: squared-off cleaver with a slanted end and a bolt hole
		local bodyLen = len - 0.7
		blade = wp(w, "Blade", V(thick, bodyLen, width + 0.2), w.color, w.bladeMat, CF(0, y0 + bodyLen / 2, 0.1))
		wwedge(w, "Tip", V(thick, 0.7, width + 0.2), w.color, w.bladeMat, CF(0, y0 + bodyLen + 0.35, 0.1) * ANG(0, PI, 0))
		wp(w, "Hole", V(thick + 0.12, 0.34, 0.34), INK, nil, CF(0, y0 + bodyLen - 0.45, 0.35), Enum.PartType.Cylinder)
		dressBlade(w, CF(0, 0, 0.1), y0, bodyLen, width + 0.2, thick)
		swingTrail(w, blade, V(0, y0 + 0.4, 0.1), V(0, y0 + len - 0.2, 0.1))
	elseif big and w.theme == "void" then
		-- Reality Cutter: a blade in three floating pieces around a glowing core
		local seg = (len - 1.0) / 3
		for i = 0, 2 do
			local p = wp(w, i == 0 and "Blade" or "BladeShard", V(thick, seg - 0.2, width), w.color, w.bladeMat, CF(0, y0 + seg * i + seg / 2, 0))
			if i == 0 then
				blade = p
			end
		end
		wp(w, "Core", V(thick * 0.6, len - 0.9, width * 0.26), w.color2, MAT.Neon, CF(0, y0 + (len - 0.9) / 2, 0))
		for _, side in SIDES do
			wwedge(w, "Tip", V(thick, 0.9, width / 2), w.color, w.bladeMat, CF(0, y0 + seg * 3 + 0.5, side * width / 4) * ANG(0, side > 0 and PI or 0, 0))
		end
		if w.r >= 4 then
			for i = 1, 3 do
				wp(w, "Rune", V(thick + 0.26, 0.16, width * 0.16), gemColor(w, i), MAT.Neon, CF(0, y0 + seg * (i - 0.5), 0) * ANG(0.35, 0, 0))
			end
		end
		if w.r >= 6 then
			for _, side in SIDES do
				wp(w, "Edge", V(thick * 0.6, len - 1.1, 0.12), lighter(w.rc, 0.15), MAT.Neon, CF(0, y0 + (len - 1.1) / 2, side * (width / 2 + 0.03)))
			end
		end
		swingTrail(w, blade, V(0, y0 + 0.4, 0), V(0, y0 + len - 0.2, 0))
	else
		local b, bodyLen = straightBlade(w, CF(), "Blade", y0, len, width, thick)
		blade = b
		dressBlade(w, CF(), y0, bodyLen, width, thick)
		swingTrail(w, blade, V(0, y0 + 0.3, 0), V(0, y0 + len - 0.15, 0))
	end
	if big then
		wp(w, "Ricasso", V(thick + 0.3, 0.4, width * 0.7), w.metal, w.metalMat, CF(0, y0 + 0.2, 0))
	end
	pommel(w, CF(0, -gripLen / 2 - 0.12, 0), big and 0.55 or 0.44)
	wraps(w, CF(), gripLen, big and 0.36 or 0.3)
	if w.r >= 7 then
		fragments(w, CF(0, y0 + len * 0.62, 0), width * 0.9 + 0.35, 3, big and 0.5 or 0.36)
		halo(w, CF(0, y0 + len + 0.35, 0), big and 0.55 or 0.4, 4, 0.16)
	end
	aura(w, blade)
end

local function buildKatana(w: Wpn)
	wp(w, "Tsuba", V(0.12, 0.84, 0.84), w.metal, w.metalMat, CF(0, 0.77, 0) * UPRIGHT, Enum.PartType.Cylinder)
	wp(w, "Habaki", V(0.2, 0.2, 0.48), w.r >= 5 and GOLD or rgb(200, 170, 90), MAT.Metal, CF(0, 0.92, 0))
	local f = CF(0, 0.84, 0)
	local blade: BasePart? = nil
	local lens = { 1.45, 1.3, 1.1 }
	local startY = 0.84
	for i, L in lens do
		f = f * ANG(-0.055, 0, 0)
		local seg = wp(w, i == 1 and "Blade" or "Blade" .. i, V(0.12, L, 0.42), w.color, w.bladeMat, f * CF(0, L / 2, 0))
		if i == 1 then
			blade = seg
		end
		-- hamon / edge line on the convex (+Z) side
		if w.r >= 3 then
			wp(w, "Edge", V(0.08, L * 0.96, 0.1), w.r >= 6 and lighter(w.rc, 0.15) or lighter(w.color, 0.55), w.r >= 6 and MAT.Neon or w.bladeMat, f * CF(0, L / 2, 0.24))
		end
		if w.r >= 4 then
			wp(w, "Rune", V(0.34, 0.14, 0.1), gemColor(w, i), MAT.Neon, f * CF(0, L * 0.5, -0.08) * ANG(0, 0, 0.3))
		end
		f = f * CF(0, L * 0.98, 0)
	end
	wwedge(w, "Tip", V(0.12, 0.5, 0.42), w.color, w.bladeMat, f * ANG(-0.06, 0, 0) * CF(0, 0.24, 0) * ANG(0, PI, 0))
	local tip = (f * CF(0, 0.4, 0)).Position
	local b = blade :: BasePart
	if w.theme == "void" or w.theme == "bone" then
		wp(w, "Core", V(0.18, 1.2, 0.1), w.color2, MAT.Neon, CF(0, startY + 0.75, -0.12))
	end
	-- diamond grip wrap
	for i = -1, 1 do
		wp(w, "Ito", V(0.3, 0.16, 0.34), w.r >= 2 and darker(w.rc, 0.2) or w.color2, MAT.Fabric, CF(0, i * 0.42, 0) * ANG(0, 0, PI / 4))
	end
	wp(w, "Kashira", V(0.34, 0.16, 0.36), w.metal, w.metalMat, CF(0, -0.78, 0))
	if w.r >= 2 then
		wgem(w, CF(0, 0.77, 0.3), 0.18)
		wgem(w, CF(0, 0.77, -0.3), 0.18, nil, 2)
	end
	if w.r >= 5 then
		wp(w, "GoldTrim", V(0.3, 0.1, 0.62), GOLD, MAT.Foil, CF(0, 0.64, 0))
	end
	if w.r >= 7 then
		fragments(w, CF(0, 2.8, -0.1), 0.6, 3, 0.34)
		halo(w, CF(tip + V(0, 0.3, 0)), 0.36, 4, 0.14)
	end
	swingTrail(w, b, V(0, 1.1, 0), tip)
	aura(w, b)
end

-- One dagger (main or off-hand) built around `frame`, welded to `parent`
local function oneDagger(w: Wpn, frame: CFrame, parent: BasePart, bladeName: string)
	local th = w.theme
	guard(w, frame * CF(0, 0.46, 0), 0.72, 0.16, 0.34, parent)
	local blade: BasePart
	local tip: Vector3
	if th == "bone" or th == "void" then
		-- curved fang
		local f = frame * CF(0, 0.5, 0)
		blade = wp(w, bladeName, V(0.14, 0.95, 0.44), w.color, w.bladeMat, f * CF(0, 0.47, 0), nil, parent)
		local f2 = f * CF(0, 0.92, 0) * ANG(-0.28, 0, 0)
		wp(w, bladeName .. "2", V(0.14, 0.55, 0.38), w.color, w.bladeMat, f2 * CF(0, 0.27, 0), nil, parent)
		wwedge(w, "Tip", V(0.14, 0.45, 0.38), w.color, w.bladeMat, f2 * CF(0, 0.52, 0) * ANG(-0.2, 0, 0) * CF(0, 0.2, 0) * ANG(0, PI, 0), parent)
		tip = (f2 * CF(0, 0.9, 0)).Position
		wp(w, "Edge", V(0.08, 0.9, 0.1), w.r >= 6 and lighter(w.rc, 0.15) or w.color2, MAT.Neon, f * CF(0, 0.5, 0.25), nil, parent)
	else
		local b, _ = straightBlade(w, frame, bladeName, 0.5, 1.6, 0.42, 0.16, parent)
		blade = b
		tip = (frame * CF(0, 2.0, 0)).Position
	end
	if w.r >= 4 then
		wp(w, "Rune", V(0.4, 0.12, 0.1), gemColor(w, 1), MAT.Neon, frame * CF(0, 0.85, 0) * ANG(0, PI / 2, 0.4), nil, parent)
	end
	pommel(w, frame * CF(0, -0.5, 0), 0.34, parent)
	swingTrail(w, blade, (frame * CF(0, 0.7, 0)).Position, tip, 0.25)
	aura(w, blade)
end

local function buildDaggers(w: Wpn)
	oneDagger(w, CF(), w.handle, "Blade")
	wraps(w, CF(), 0.8, 0.26)
	-- off-hand dagger beside the main one (slightly splayed) for display; the animation re-welds OffHandle to the left hand
	local offCF = CF(0, 0.12, -0.95) * ANG(-0.2, 0, 0)
	local off = gripPart(w, V(0.26, 0.8, 0.26), offCF, "OffHandle")
	off.CFrame = offCF
	off.Parent = w.model
	local weld = Instance.new("Weld")
	weld.Name = "OffHandWeld"
	weld.Part0 = w.handle
	weld.Part1 = off
	weld.C0 = offCF
	weld.Parent = off
	oneDagger(w, offCF, off, "OffBlade")
	wraps(w, offCF, 0.8, 0.26, off)
	if w.r >= 7 then
		halo(w, CF(0, 2.45, -0.5), 0.45, 4, 0.14)
	end
end

local function buildSpear(w: Wpn)
	wp(w, "Shaft", V(0.24, 7.0, 0.24), w.theme == "gold" and rgb(120, 80, 40) or w.color2, MAT.Wood, CF(0, 1.5, 0))
	wp(w, "ButtCap", V(0.36, 0.3, 0.36), w.metal, w.metalMat, CF(0, -2.05, 0) * UPRIGHT, Enum.PartType.Cylinder)
	wp(w, "Socket", V(0.55, 0.36, 0.36), w.metal, w.metalMat, CF(0, 5.05, 0) * UPRIGHT, Enum.PartType.Cylinder)
	local c = w.color
	local blade = wp(w, "Blade", V(0.16, 0.4, 0.64), c, w.bladeMat, CF(0, 5.6, 0))
	for _, side in SIDES do
		wwedge(w, "Tip", V(0.16, 1.05, 0.32), c, w.bladeMat, CF(0, 6.32, side * 0.16) * ANG(0, side > 0 and PI or 0, 0))
		wwedge(w, "Tip", V(0.16, 0.36, 0.32), c, w.bladeMat, CF(0, 5.22, side * 0.16) * ANG(PI, side > 0 and 0 or PI, 0))
	end
	wp(w, "Wings", V(0.14, 0.14, 1.0), w.metal, w.metalMat, CF(0, 5.3, 0))
	wwedge(w, "Tassel", V(0.2, 0.7, 0.34), w.r >= 2 and w.rc or rgb(190, 50, 40), MAT.Fabric, CF(0, 4.6, 0.1) * ANG(PI, 0, 0))
	if w.theme == "gold" then
		wp(w, "Lapis", V(0.24, 0.3, 0.3), rgb(40, 90, 200), MAT.Glass, CF(0, 5.6, 0) * ANG(PI / 4, 0, 0))
	end
	if w.r >= 3 then
		wp(w, "Fuller", V(0.28, 0.9, 0.12), darker(c, 0.3), w.bladeMat, CF(0, 5.95, 0))
	end
	if w.r >= 4 then
		for i = 1, 3 do
			wp(w, "Rune", V(0.3, 0.12, 0.3), gemColor(w, i), MAT.Neon, CF(0, 1.2 + i * 0.9, 0))
		end
	end
	if w.r >= 5 then
		wp(w, "GoldTrim", V(0.3, 0.14, 0.3), GOLD, MAT.Foil, CF(0, 4.8, 0))
	end
	if w.r >= 6 then
		for _, side in SIDES do
			wp(w, "Edge", V(0.1, 0.9, 0.1), lighter(w.rc, 0.15), MAT.Neon, CF(0, 6.1, side * 0.3) * ANG(side * 0.3, 0, 0))
		end
	end
	if w.r >= 7 then
		fragments(w, CF(0, 6.0, 0), 0.7, 3, 0.36)
		halo(w, CF(0, 5.05, 0), 0.5, 4, 0.14)
	end
	wraps(w, CF(), 1.2, 0.42)
	swingTrail(w, blade, V(0, 5.3, 0), V(0, 6.8, 0))
	aura(w, blade)
end

local function buildHammer(w: Wpn)
	wp(w, "Shaft", V(0.3, 3.4, 0.3), w.theme == "scrap" and rgb(80, 80, 86) or rgb(110, 78, 50), w.theme == "scrap" and MAT.Metal or MAT.Wood, CF(0, 0.95, 0))
	local hy = 3.05
	local blade: BasePart
	if w.theme == "scrap" then
		-- engine-block hammer with exhaust pipes and hazard stripes
		blade = wp(w, "Blade", V(1.9, 1.2, 1.2), w.color, MAT.CorrodedMetal, CF(0, hy, 0) * ANG(0, 0, 0), Enum.PartType.Cylinder)
		for _, side in SIDES do
			wp(w, "Stripe", V(0.2, 1.3, 1.3), w.color2, MAT.SmoothPlastic, CF(side * 0.55, hy, 0), Enum.PartType.Cylinder)
			wp(w, "Face", V(0.2, 0.9, 0.9), rgb(60, 60, 64), MAT.DiamondPlate, CF(side * 1.02, hy, 0), Enum.PartType.Cylinder)
		end
		for _, side in SIDES do
			wp(w, "Pipe", V(0.9, 0.2, 0.2), rgb(70, 70, 74), MAT.Metal, CF(side * 0.3, hy + 0.9, 0.2) * UPRIGHT, Enum.PartType.Cylinder)
			wp(w, "PipeGlow", V(0.12, 0.24, 0.24), w.color2, MAT.Neon, CF(side * 0.3, hy + 1.38, 0.2) * UPRIGHT, Enum.PartType.Cylinder)
		end
	else
		local ice = w.theme == "ice"
		blade = wp(w, "Blade", V(1.8, 1.25, 1.25), w.color, ice and MAT.Ice or w.bladeMat, CF(0, hy, 0))
		for _, side in SIDES do
			wp(w, "Face", V(0.26, 1.15, 1.15), ice and lighter(w.color, 0.3) or w.metal, ice and MAT.Glass or w.metalMat, CF(side * 1.0, hy, 0), Enum.PartType.Cylinder)
			wp(w, "Band", V(0.18, 1.45, 1.45), w.r >= 5 and GOLD or w.metal, w.r >= 5 and MAT.Foil or w.metalMat, CF(side * 0.5, hy, 0))
		end
		if ice then
			for i = -1, 1 do
				wwedge(w, "Icicle", V(0.16, 0.6 - math.abs(i) * 0.15, 0.3), rgb(210, 240, 255), MAT.Ice, CF(i * 0.55, hy - 0.9 + math.abs(i) * 0.07, 0) * ANG(PI, PI / 2, 0))
				wwedge(w, "Crystal", V(0.2, 0.8 - math.abs(i) * 0.25, 0.4), rgb(200, 235, 255), MAT.Ice, CF(i * 0.5, hy + 0.95 - math.abs(i) * 0.12, 0) * ANG(0, PI / 2, -i * 0.3))
			end
		end
	end
	wp(w, "Collar", V(0.46, 0.3, 0.46), w.metal, w.metalMat, CF(0, 2.35, 0))
	if w.r >= 3 then
		wwedge(w, "Spike", V(0.2, 0.6, 0.45), w.metal, w.metalMat, CF(0, hy + 0.88, 0))
	end
	if w.r >= 4 then
		for _, side in SIDES do
			wp(w, "Rune", V(0.5, 0.5, 0.1), gemColor(w, 1), MAT.Neon, CF(0, hy, side * 0.64) * ANG(0, 0, PI / 4))
		end
	end
	if w.r >= 6 then
		for _, side in SIDES do
			wp(w, "Edge", V(0.1, 0.62, 0.62), lighter(w.rc, 0.15), MAT.Neon, CF(side * 1.18, hy, 0), Enum.PartType.Cylinder)
		end
	end
	if w.r >= 2 then
		wgem(w, CF(0, 2.35, 0), 0.52)
	end
	wp(w, "Pommel", V(0.5, 0.3, 0.5), w.metal, w.metalMat, CF(0, -0.8, 0) * UPRIGHT, Enum.PartType.Cylinder)
	if w.r >= 7 then
		fragments(w, CF(0, hy, 0), 1.45, 3, 0.4)
		halo(w, CF(0, hy + 1.3, 0), 0.6, 4, 0.16)
	end
	wraps(w, CF(), 1.2, 0.42)
	swingTrail(w, blade, V(0, hy - 0.6, 0), V(0, hy + 0.6, 0), 0.6)
	aura(w, blade)
end

local function buildScythe(w: Wpn)
	local th = w.theme
	wp(w, "Shaft", V(0.26, 6.0, 0.26), th == "star" and rgb(30, 30, 44) or w.color2, MAT.Wood, CF(0, 1.3, 0))
	wp(w, "Nib", V(0.18, 0.18, 0.7), w.color2, MAT.Wood, CF(0, 1.9, 0.3))
	wp(w, "Collar", V(0.4, 0.46, 0.4), w.metal, w.metalMat, CF(0, 4.1, 0))
	-- curved blade toward -Z: segments bending down, spine on top, edge below
	local f = CF(0, 4.2, -0.12)
	local blade: BasePart? = nil
	local segs = { { 0.9, 0.66 }, { 0.8, 0.56 }, { 0.72, 0.44 }, { 0.6, 0.32 } }
	for i, sg in segs do
		local L, h = sg[1], sg[2]
		local p = wp(w, i == 1 and "Blade" or "Blade" .. i, V(0.14, h, L), w.color, w.bladeMat, f * CF(0, -h * 0.3, -L / 2))
		if i == 1 then
			blade = p
		end
		if i < 4 then
			wp(w, "Spine", V(0.22, 0.12, L), th == "flame" and rgb(30, 24, 26) or darker(w.color, 0.35), w.bladeMat, f * CF(0, h * 0.2 + 0.02, -L / 2))
		end
		if w.r >= 6 and i < 4 then
			wp(w, "Edge", V(0.08, 0.1, L * 0.98), lighter(w.rc, 0.15), MAT.Neon, f * CF(0, -h * 0.8 - 0.03, -L / 2))
		end
		f = f * CF(0, 0, -L * 0.96) * ANG(-0.2 - i * 0.05, 0, 0)
	end
	wwedge(w, "Tip", V(0.14, 0.28, 0.6), w.color, w.bladeMat, f * CF(0, -0.12, -0.28))
	local tip = (f * CF(0, 0, -0.6)).Position
	local b = blade :: BasePart
	if th == "bone" then -- skull at the collar
		wp(w, "Skull", V(0.62, 0.62, 0.62), BONE, nil, CF(0, 4.45, 0.05), Enum.PartType.Ball)
		wp(w, "SkullEyes", V(0.4, 0.12, 0.14), w.r >= 3 and w.rc or INK, w.r >= 3 and MAT.Neon or nil, CF(0, 4.5, -0.27))
	elseif th == "flame" then
		for _, side in SIDES do
			wwedge(w, "Horn", V(0.14, 0.6, 0.3), rgb(40, 30, 30), nil, CF(side * 0.2, 4.55, 0) * ANG(0, 0, -side * 0.4) * ANG(0, side * PI / 2, 0))
		end
		for i = 1, 2 do
			wwedge(w, "Flame", V(0.12, 0.45, 0.35), w.r >= 3 and lighter(w.color, 0.3) or rgb(255, 120, 40), MAT.Neon, CF(0, 4.35, -0.35 - i * 0.55) * ANG(0, 0, 0))
		end
	elseif th == "void" or th == "star" then
		wp(w, "Core", V(0.3, 0.3, 0.3), w.color2, MAT.Neon, CF(0, 4.45, 0) * ANG(PI / 4, 0, PI / 4))
		for i = 1, 2 do
			wp(w, th == "star" and "Star" or "Shard", V(0.16, 0.16, 0.16), w.color2, MAT.Neon, CF(0, 3.95 - i * 0.04, -0.6 - i * 0.7) * ANG(PI / 4, 0, PI / 4))
		end
	end
	if w.r >= 2 then
		wgem(w, CF(0, 4.1, 0), 0.5)
	end
	if w.r >= 3 then
		wp(w, "ShaftBand", V(0.36, 0.16, 0.36), w.metal, w.metalMat, CF(0, 2.6, 0))
	end
	if w.r >= 4 then
		wp(w, "Rune", V(0.2, 0.18, 0.26), gemColor(w, 1), MAT.Neon, CF(0, 4.12, -0.95))
	end
	if w.r >= 5 then
		wp(w, "GoldTrim", V(0.46, 0.12, 0.46), GOLD, MAT.Foil, CF(0, 3.8, 0))
	end
	if w.r >= 7 then
		fragments(w, CF(0, 4.3, -1.3), 0.7, 3, 0.36)
		halo(w, CF(0, 4.9, 0), 0.4, 4, 0.14)
	end
	wraps(w, CF(), 1.2, 0.42)
	swingTrail(w, b, V(0, 3.9, -0.3), tip, 0.4)
	aura(w, b)
end

local function buildBow(w: Wpn)
	local th = w.theme
	local R = 2.4
	local limbColor = w.color
	local limbMat = th == "scrap" and MAT.Metal or (th == "star" and MAT.Metal or (th == "ice" and MAT.Ice or MAT.Wood))
	local angles = { 10, 25, 40, 55 }
	local tips: { [number]: CFrame } = {}
	for _, side in SIDES do
		for i, deg in angles do
			local a = math.rad(deg) * side
			local k = (i - 1) / 3
			local cf = CF(0, math.sin(a) * R, -math.cos(a) * R + R - 0.1) * ANG(a, 0, 0)
			wp(w, "Limb", V(0.26 - k * 0.1, 0.72, 0.34 - k * 0.12), limbColor, limbMat, cf)
			if w.r >= 6 and (i == 2 or i == 3) then
				wp(w, "Edge", V(0.1, 0.66, 0.08), lighter(w.rc, 0.15), MAT.Neon, cf * CF(0, 0, -0.17 + k * 0.06))
			elseif w.r >= 4 and i == 2 then
				wp(w, "Rune", V(0.3 - k * 0.1, 0.16, 0.1), gemColor(w, 1), MAT.Neon, cf * CF(0, 0, -0.17 + k * 0.06))
			end
		end
		local a = math.rad(64) * side
		tips[side] = CF(0, math.sin(a) * R, -math.cos(a) * R + R - 0.1) * ANG(a, 0, 0)
		-- recurve tip bending outward (toward the target side)
		wp(w, "LimbTip", V(0.14, 0.42, 0.18), limbColor, limbMat, tips[side] * ANG(-side * 0.7, 0, 0) * CF(0, side * 0.16, 0))
	end
	local topY, botY = tips[1].Position.Y, tips[-1].Position.Y
	local sz = tips[1].Position.Z + 0.02
	wp(w, "Blade", V(0.05, topY - botY, 0.05), w.color2, MAT.Neon, CF(0, (topY + botY) / 2, sz))
	wp(w, "Rest", V(0.36, 0.14, 0.3), w.metal, w.metalMat, CF(0, 0.56, -0.12))
	for _, side in SIDES do
		local tcf = tips[side]
		if th == "leaf" then
			wwedge(w, "Leaf", V(0.08, 0.5, 0.36), rgb(100, 200, 80), MAT.Grass, tcf * CF(0, -side * 0.2, -0.22) * ANG(0, 0, side * 0.6))
		elseif th == "gold" or w.r >= 5 then
			wp(w, "TipCap", V(0.3, 0.2, 0.3), GOLD, MAT.Foil, tcf, Enum.PartType.Ball)
		elseif th == "scrap" then
			wp(w, "Cam", V(0.16, 0.56, 0.56), rgb(150, 150, 156), MAT.Metal, tcf * CF(0, 0, 0.08), Enum.PartType.Cylinder)
		elseif th == "star" then
			wp(w, "Star", V(0.28, 0.28, 0.28), w.color2, MAT.Neon, tcf * ANG(PI / 4, 0, PI / 4))
		end
	end
	if th == "scrap" then
		wp(w, "Sight", V(0.12, 0.12, 0.6), w.color2, MAT.Neon, CF(0.24, 0.4, -0.2))
	end
	if w.r >= 2 then
		wgem(w, CF(0, 0, -0.26), 0.3)
	end
	if w.r >= 3 then
		wp(w, "Riser", V(0.36, 0.5, 0.2), w.metal, w.metalMat, CF(0, -0.45, -0.22))
	end
	if w.r >= 7 then
		fragments(w, CF(0, 0, 0.3), 1.1, 3, 0.36)
		halo(w, CF(0, 0, 0.5), 0.5, 4, 0.14)
	end
	aura(w, w.handle)
end

local function buildStaff(w: Wpn)
	local th = w.theme
	local wood = w.color
	wp(w, "Shaft", V(0.3, 5.5, 0.3), wood, th == "ice" and MAT.Glass or MAT.Wood, CF(0, 1.0, 0))
	local oy = 4.35
	local orb = wp(w, "Orb", V(1.05, 1.05, 1.05), w.color2, MAT.Neon, CF(0, oy, 0), Enum.PartType.Ball)
	light(orb, w.color2, 8, 1.5)
	wp(w, "HeadCollar", V(0.5, 0.3, 0.5), w.metal, w.metalMat, CF(0, 3.72, 0))
	for k = 0, 2 do
		local a = k * PI * 2 / 3
		if th == "ice" then
			wwedge(w, "Crystal", V(0.2, 1.0, 0.36), rgb(200, 235, 255), MAT.Ice, CF(0, 3.95, 0) * ANG(0, a, 0) * CF(0, 0.3, -0.5) * ANG(0.35, 0, 0))
		else
			wwedge(w, "Prong", V(0.12, 0.9, 0.24), th == "leaf" and rgb(90, 150, 60) or (w.r >= 5 and GOLD or wood), th == "leaf" and MAT.Grass or MAT.Wood, CF(0, 3.95, 0) * ANG(0, a, 0) * CF(0, 0.32, -0.46) * ANG(-0.3, 0, 0))
		end
	end
	if th == "leaf" then -- vines and leaves
		for i = 0, 2 do
			wp(w, "Vine", V(0.4, 0.12, 0.4), rgb(80, 150, 60), MAT.Grass, CF(0, 0.8 + i * 1.0, 0) * ANG(0.35, i * 1.2, 0))
		end
		for _, side in SIDES do
			wwedge(w, "Leaf", V(0.08, 0.5, 0.4), rgb(100, 200, 80), MAT.Grass, CF(side * 0.3, 3.55, 0) * ANG(0, 0, -side * 0.8) * ANG(0, side * PI / 2, 0))
		end
	end
	wp(w, "Foot", V(0.4, 0.3, 0.4), w.metal, w.metalMat, CF(0, -1.75, 0) * UPRIGHT, Enum.PartType.Cylinder)
	if w.r >= 2 then
		wgem(w, CF(0, 3.45, 0), 0.42)
	end
	if w.r >= 4 then
		for i = 1, 2 do
			wp(w, "Rune", V(0.4, 0.12, 0.4), gemColor(w, i), MAT.Neon, CF(0, 2.2 + i * 0.5, 0))
		end
	end
	if w.r >= 6 then
		for k = 0, 3 do
			local a = k * PI / 2
			wp(w, "Edge", V(0.14, 0.14, 0.14), lighter(w.rc, 0.15), MAT.Neon, CF(math.cos(a) * 0.8, oy, math.sin(a) * 0.8) * ANG(PI / 4, a, PI / 4))
		end
	end
	if w.r >= 7 then
		fragments(w, CF(0, oy + 0.1, 0), 1.2, 3, 0.36)
		halo(w, CF(0, oy + 0.95, 0), 0.45, 4, 0.14)
	end
	wraps(w, CF(), 1.2, 0.42)
	swingTrail(w, orb, V(0, oy - 0.4, 0), V(0, oy + 0.4, 0), 0.2)
	aura(w, orb)
end

function Models.Weapon(key: string): Model
	local w, _, style = weaponCtx(key)
	local gripLen = (style == "katana" and 1.4) or (style == "daggers" and 0.8) or (style == "greatsword" and 1.5) or 1.1
	local pole = style == "spear" or style == "hammer" or style == "scythe" or style == "staff"
	local size = pole and V(0.42, 1.2, 0.42) or (style == "katana" and V(0.26, gripLen, 0.3) or (style == "greatsword" and V(0.36, gripLen, 0.36) or (style == "daggers" and V(0.26, gripLen, 0.26) or V(0.3, gripLen, 0.3))))
	local handle = gripPart(w, size, CF())
	if pole then
		handle.Material = MAT.Fabric
	end
	if style == "bow" then
		handle.Size = V(0.3, 1.0, 0.36)
		handle.Color = darker(w.color, 0.25)
		handle.Material = MAT.Leather
	end
	handle.CFrame = CF()
	handle.Parent = w.model
	w.model.PrimaryPart = handle
	w.handle = handle
	if style == "katana" then
		buildKatana(w)
	elseif style == "daggers" then
		buildDaggers(w)
	elseif style == "spear" then
		buildSpear(w)
	elseif style == "hammer" then
		buildHammer(w)
	elseif style == "scythe" then
		buildScythe(w)
	elseif style == "bow" then
		buildBow(w)
	elseif style == "staff" then
		buildStaff(w)
	else
		buildSword(w, style)
	end
	return w.model
end

--------------------------------------------------------------------------------
-- CORES
--------------------------------------------------------------------------------
function Models.Core(z: number, r: number, scale: number?): Model
	local s = scale or 1
	local rarityColor = Items.RarityColor(r)
	local coreColor = Items.CoreColor(z)
	local secret = Config.Rarities[r] and Config.Rarities[r].secret

	local model = Instance.new("Model")
	model.Name = "Core"
	local core = newPart("Core", Vector3.new(1.8, 1.8, 1.8) * s, secret and Color3.fromRGB(12, 12, 16) or coreColor, secret and Enum.Material.SmoothPlastic or Enum.Material.Neon, Enum.PartType.Ball)
	core.Parent = model
	model.PrimaryPart = core

	local shell = newPart("Shell", Vector3.new(2.5, 2.5, 2.5) * s, rarityColor, Enum.Material.Glass, Enum.PartType.Ball)
	shell.Transparency = 0.55
	attach(core, shell, CFrame.new(), model)

	if r >= 3 then
		for k = 0, 7 do
			local a = k * math.pi / 4
			local bit = newPart("Ring", Vector3.new(0.3, 0.3, 0.3) * s, rarityColor, Enum.Material.Neon)
			attach(core, bit, CFrame.Angles(0, a, 0) * CFrame.new(1.75 * s, 0, 0), model)
		end
	end
	if r >= 5 then
		for k = 0, 7 do
			local a = k * math.pi / 4
			local bit = newPart("Ring", Vector3.new(0.26, 0.26, 0.26) * s, rarityColor, Enum.Material.Neon)
			attach(core, bit, CFrame.Angles(math.rad(70), a, 0) * CFrame.new(2.05 * s, 0, 0), model)
		end
	end

	light(core, rarityColor, (6 + r * 1.6) * s, 1.4 + r * 0.2)
	if r >= 4 then
		local e = sparkles(core, rarityColor, 3 + r * 3, 0.4 * s)
		if secret then
			e.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 120)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 160, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 60, 255)),
			})
		end
	end
	return model
end

-- Simple glowing orb used to display classes/abilities on trophy pedestals
function Models.Orb(color: Color3, size: number): Model
	local model = Instance.new("Model")
	model.Name = "Orb"
	local orb = newPart("Handle", Vector3.new(size, size, size), color, Enum.Material.Neon, Enum.PartType.Ball)
	orb.Parent = model
	model.PrimaryPart = orb
	local shell = newPart("Shell", Vector3.new(size, size, size) * 1.35, color, Enum.Material.ForceField, Enum.PartType.Ball)
	attach(orb, shell, CFrame.new(), model)
	light(orb, color, size * 5, 1.5)
	return model
end

--------------------------------------------------------------------------------
-- TROPHIES: class emblems (heraldic crests) and ability tomes (floating spell books) for the
-- base pedestals. Both are centred on their PrimaryPart ("Pivot", invisible) so they spin in place.
--------------------------------------------------------------------------------
type Tro = { model: Model, root: BasePart }

local function newTrophy(name: string): Tro
	local model = Instance.new("Model")
	model.Name = name
	local root = newPart("Pivot", V(0.2, 0.2, 0.2), WHITE)
	root.Transparency = 1
	root.CFrame = CF()
	root.Parent = model
	model.PrimaryPart = root
	return { model = model, root = root }
end

local function tp(t: Tro, name: string, size: Vector3, color: Color3, mat: Enum.Material?, cf: CFrame, shape: Enum.PartType?): BasePart
	local p = newPart(name, size, color, mat, shape)
	attach(t.root, p, cf, t.model)
	return p
end

-- Right triangle facing ±Z (w wide, h tall, d deep); `corner` = where the right angle is: bl / br / tl / tr
local function ttri(t: Tro, name: string, w: number, h: number, d: number, color: Color3, mat: Enum.Material?, cf: CFrame, corner: string): BasePart
	local rot = if corner == "br" then ANG(0, PI / 2, 0) elseif corner == "bl" then ANG(0, -PI / 2, 0) elseif corner == "tr" then ANG(PI, PI / 2, 0) else ANG(PI, -PI / 2, 0)
	local p = newWedge(name, V(d, h, w), color, mat)
	attach(t.root, p, cf * rot, t.model)
	return p
end

-- Flat symbols in the frame's X-Y plane (depth d, visible from both faces); k = size (1 -> ~1.7 studs)
local SYMBOL_COLORS: { [string]: Color3 } = {
	heart = rgb(235, 60, 80),
	drop = rgb(200, 30, 50),
	leaf = rgb(110, 210, 80),
	clover = rgb(90, 200, 80),
	coins = GOLD,
	pack = rgb(200, 150, 90),
}

local function symbol(t: Tro, kind: string, c: CFrame, k: number, color: Color3, mat: Enum.Material, d: number)
	local function box(sx: number, sy: number, x: number, y: number, rot: number?, extra: number?, col: Color3?)
		return tp(t, "Symbol", V(sx * k, sy * k, d + (extra or 0)), col or color, mat, c * CF(x * k, y * k, 0) * ANG(0, 0, rot or 0))
	end
	local function disc(dia: number, x: number, y: number, extra: number?, col: Color3?)
		return tp(t, "Symbol", V(d + (extra or 0), dia * k, dia * k), col or color, mat, c * CF(x * k, y * k, 0) * FACING, Enum.PartType.Cylinder)
	end
	local function tri(w: number, h: number, x: number, y: number, corner: string, extra: number?, col: Color3?, frame: CFrame?)
		return ttri(t, "Symbol", w * k, h * k, d + (extra or 0), col or color, mat, (frame or c) * CF(x * k, y * k, 0), corner)
	end
	local white = if mat == MAT.Neon then lighter(color, 0.6) else WHITE
	if kind == "heart" then
		disc(0.92, -0.32, 0.22)
		disc(0.92, 0.32, 0.22, 0.08)
		box(0.94, 0.94, 0, -0.14, PI / 4, 0.16)
	elseif kind == "swords" then
		for i, side in SIDES do
			local r = side * PI / 4
			local ux, uy = -math.sin(r), math.cos(r)
			local e = (i - 1) * 0.1
			box(0.22, 1.5, ux * 0.25, uy * 0.25, r, e)
			box(0.66, 0.15, -ux * 0.58, -uy * 0.58, r, e + 0.04)
			box(0.14, 0.42, -ux * 0.86, -uy * 0.86, r, e)
		end
	elseif kind == "bow" then
		for i = -2, 2 do
			local a = i * 0.36
			box(0.2, 0.5, -0.3 - math.cos(a) * 0.62 + 0.62, math.sin(a) * 0.95, -a, (i % 2) * 0.06)
		end
		box(0.06, 1.8, -0.08, 0, 0, 0.14)
		box(1.5, 0.1, 0.2, 0, 0, 0.12)
		tri(0.3, 0.3, 1.04, 0.15, "bl", 0.12)
		tri(0.3, 0.3, 1.04, -0.15, "tl", 0.12)
	elseif kind == "wing" then
		local rx, ry = -0.5, 0.45
		box(1.2, 0.3, rx + 0.45, ry + 0.2, 0.38, 0.1)
		for i = 0, 3 do
			local a = -0.1 - i * 0.36
			local L = 1.45 - i * 0.22
			box(L, 0.28, rx + math.cos(a) * L / 2, ry + math.sin(a) * L / 2, a, i * 0.05)
		end
	elseif kind == "star" then
		box(1.15, 1.15, 0, 0, 0)
		box(1.15, 1.15, 0, 0, PI / 4, 0.14)
		disc(0.46, 0, 0, 0.3, white)
	elseif kind == "leaf" then
		local f = c * ANG(0, 0, -0.45)
		tri(0.5, 0.85, 0.25, 0.425, "bl", 0, nil, f)
		tri(0.5, 0.85, -0.25, 0.425, "br", 0, nil, f)
		tri(0.5, 0.85, 0.25, -0.425, "tl", 0, nil, f)
		tri(0.5, 0.85, -0.25, -0.425, "tr", 0, nil, f)
		tp(t, "Symbol", V(0.08 * k, 1.5 * k, d + 0.12), darker(color, 0.35), mat, f)
		tp(t, "Symbol", V(0.1 * k, 0.5 * k, d), darker(color, 0.35), mat, f * CF(0, -1.05 * k, 0))
	elseif kind == "drop" then
		disc(1.0, 0, -0.25)
		tri(0.43, 0.9, -0.215, 0.5, "br", 0.06)
		tri(0.43, 0.9, 0.215, 0.5, "bl", 0.06)
		disc(0.22, -0.2, -0.1, 0.16, white)
	elseif kind == "dagger" or kind == "sword" then
		local long = kind == "sword"
		local f = c * ANG(0, 0, long and 0 or 0.6)
		local bl = long and 1.25 or 0.95
		tp(t, "Symbol", V(0.26 * k, bl * k, d), color, mat, f * CF(0, (0.02 - bl / 2 + 0.3) * k, 0))
		local ty = (0.32 - bl) * k - 0.2 * k
		ttri(t, "Symbol", 0.13 * k, 0.4 * k, d, color, mat, f * CF(-0.065 * k, ty, 0), "tr")
		ttri(t, "Symbol", 0.13 * k, 0.4 * k, d, color, mat, f * CF(0.065 * k, ty, 0), "tl")
		tp(t, "Symbol", V(0.72 * k, 0.15 * k, d + 0.08), color, mat, f * CF(0, 0.42 * k, 0))
		tp(t, "Symbol", V(0.16 * k, 0.45 * k, d), color, mat, f * CF(0, 0.72 * k, 0))
		tp(t, "Symbol", V(d + 0.08, 0.26 * k, 0.26 * k), color, mat, f * CF(0, 0.98 * k, 0) * FACING, Enum.PartType.Cylinder)
	elseif kind == "target" then
		disc(1.7, 0, 0, 0, WHITE)
		disc(1.2, 0, 0, 0.1, rgb(220, 50, 50))
		disc(0.62, 0, 0, 0.2, WHITE)
		box(0.1, 1.1, 0.34, 0.34, -PI / 4, 0.3, rgb(120, 80, 50))
	elseif kind == "tower" then
		box(1.12, 1.3, 0, 0)
		box(0.2, 1.14, 0, 0, 0, 0.1, darker(color, 0.35))
		box(0.96, 0.2, 0, 0.18, 0, 0.18, darker(color, 0.35))
		disc(0.34, 0, 0.18, 0.28, white)
	elseif kind == "pack" then
		box(1.1, 1.2, 0, -0.1)
		box(1.18, 0.46, 0, 0.36, 0, 0.1, darker(color, 0.25))
		box(0.62, 0.36, 0, -0.36, 0, 0.1, darker(color, 0.15))
		box(0.5, 0.16, 0, 0.66, 0, 0.04, darker(color, 0.4))
	elseif kind == "coins" then
		disc(0.95, -0.3, -0.25, 0)
		disc(0.95, 0.32, -0.08, 0.1)
		disc(0.95, -0.02, 0.36, 0.2)
		box(0.12, 0.5, -0.02, 0.36, 0, 0.3, darker(color, 0.35))
	elseif kind == "clover" then
		for i, p in { { 0, 0.36 }, { 0.36, 0 }, { 0, -0.36 }, { -0.36, 0 } } do
			disc(0.66, p[1], p[2] + 0.1, (i % 2) * 0.08)
		end
		box(0.12, 0.6, 0.18, -0.62, 0.3, 0.12, darker(color, 0.3))
	elseif kind == "flame" then
		disc(0.9, 0, -0.5)
		tri(0.45, 1.3, -0.225, 0.2, "br", 0.06)
		tri(0.45, 1.3, 0.225, 0.2, "bl", 0.06)
		tri(0.32, 0.7, -0.55, -0.25, "br", 0.12, lighter(color, 0.3))
		tri(0.32, 0.7, 0.55, -0.25, "bl", 0.12, lighter(color, 0.3))
		disc(0.4, 0, -0.45, 0.16, lighter(color, 0.6))
	elseif kind == "bolt" then
		box(0.34, 0.95, 0.14, 0.4, -0.45)
		box(0.72, 0.24, 0, 0, 0, 0.08)
		box(0.34, 0.95, -0.14, -0.4, -0.45, 0.14)
		tri(0.22, 0.4, -0.42, -0.95, "tr", 0.14)
	elseif kind == "arrow" then
		box(0.95, 0.24, -0.15, 0)
		tri(0.5, 0.4, 0.55, 0.2, "bl", 0.08)
		tri(0.5, 0.4, 0.55, -0.2, "tl", 0.08)
		box(0.5, 0.1, -0.5, 0.36, 0, 0.04)
		box(0.4, 0.1, -0.55, -0.36, 0, 0.04)
	elseif kind == "crescent" then
		for i = 0, 5 do
			local a = PI * 0.3 + i * PI * 1.4 / 5
			box(0.38, 0.36 - math.abs(i - 2.5) * 0.06, math.cos(a) * 0.6, math.sin(a) * 0.6, a + PI / 2, (i % 2) * 0.06)
		end
	elseif kind == "portal" then
		disc(1.0, 0, 0, 0, rgb(30, 18, 48))
		for i = 0, 7 do
			local a = i * PI / 4
			box(0.34, 0.2, math.cos(a) * 0.66, math.sin(a) * 0.66, a + PI / 2, 0.1)
		end
		disc(0.3, 0, 0, 0.2, white)
	elseif kind == "orb" then
		tp(t, "Symbol", V(0.9, 0.9, 0.9) * k, color, mat, c, Enum.PartType.Ball)
		box(1.7, 0.1, 0, 0, 0.35, 0.3)
	elseif kind == "burst" then
		disc(0.6, 0, 0, 0.1, white)
		for i = 0, 7 do
			local a = i * PI / 4
			local L = i % 2 == 0 and 0.62 or 0.42
			box(0.2, L, math.cos(a) * (0.3 + L / 2), math.sin(a) * (0.3 + L / 2), a - PI / 2, 0)
		end
	elseif kind == "meteor" then
		tp(t, "Symbol", V(0.8, 0.8, 0.8) * k, rgb(70, 50, 44), MAT.Basalt, c * CF(-0.25 * k, -0.25 * k, 0), Enum.PartType.Ball)
		for i = 0, 2 do
			box(0.2 + i * 0.05, 0.75 - i * 0.12, 0.08 + i * 0.22, 0.28 + i * 0.12, -0.75, i * 0.06)
		end
	elseif kind == "snowflake" then
		for i = 0, 2 do
			box(0.16, 1.5, 0, 0, i * PI / 3, i * 0.06)
		end
		disc(0.36, 0, 0, 0.2, white)
	elseif kind == "cloud" then
		disc(0.7, -0.35, 0, 0)
		disc(0.85, 0.05, 0.18, 0.08)
		disc(0.65, 0.42, -0.02, 0.16)
		box(1.3, 0.34, 0.03, -0.2, 0, 0.28)
		box(0.12, 0.3, -0.25, -0.58, 0, 0)
		box(0.12, 0.3, 0.25, -0.62, 0, 0)
	elseif kind == "cross" then
		box(0.42, 1.4, 0, 0)
		box(1.4, 0.42, 0, 0, 0, 0.1)
	elseif kind == "shield" then
		box(1.1, 0.8, 0, 0.25)
		tri(0.55, 0.75, -0.275, -0.52, "tr")
		tri(0.55, 0.75, 0.275, -0.52, "tl")
		disc(0.34, 0, 0.1, 0.16, white)
	else -- plain star gem
		box(0.8, 0.8, 0, 0, PI / 4)
	end
end

-- Class emblems ---------------------------------------------------------------
local MOD_SYMBOL: { [string]: string } = {
	hp = "heart",
	melee = "swords",
	ranged = "bow",
	speed = "wing",
	ability = "star",
	regen = "leaf",
	lifesteal = "drop",
	backstab = "dagger",
	crit = "target",
	resist = "tower",
	carry = "pack",
	coins = "coins",
	luck = "clover",
	hazard = "flame",
	dmg = "bolt",
}
-- a mod's "typical" value, so the most defining mod wins (a regen of 0.03 is as big a deal as +40% hp)
local MOD_TYPICAL: { [string]: number } = {
	hp = 0.47,
	dmg = 0.35,
	melee = 0.3,
	ranged = 0.3,
	ability = 0.4,
	speed = 0.28,
	regen = 0.03,
	lifesteal = 0.045,
	backstab = 0.4,
	crit = 0.08,
	resist = 0.09,
	carry = 0.5,
	coins = 0.45,
	luck = 0.25,
	hazard = 0.5,
}

local function classSymbol(mods: { [string]: number }): string
	local best, score = "sword", 0
	for mod, value in mods do
		local s = value / (MOD_TYPICAL[mod] or 1)
		if MOD_SYMBOL[mod] and (s > score or (s == score and mod < best)) then
			best, score = mod, s
		end
	end
	return MOD_SYMBOL[best] or "sword"
end
Models.ClassSymbol = classSymbol

local EMBLEM_SHAPES = { [0] = "heater", "heater", "round", "gothic", "sun", "frost", "flame", "cog", "diamond", "star" }

-- The zone silhouette grown by m studs (m > 0 = rim / glow layers); returns the vertical centre of the field
local function emblemShape(t: Tro, shape: string, m: number, d: number, color: Color3, mat: Enum.Material, name: string)
	if shape == "round" or shape == "frost" or shape == "cog" or shape == "star" or shape == "sun" then
		local dia = (shape == "sun" and 2.3 or (shape == "cog" and 2.9 or 3.1)) + 2 * m
		tp(t, name, V(d, dia, dia), color, mat, FACING, Enum.PartType.Cylinder)
	elseif shape == "diamond" then
		tp(t, name, V(2.5 + 2 * m, 2.5 + 2 * m, d), color, mat, ANG(0, 0, PI / 4))
	else -- heater (also gothic / flame): box on top, a point below
		local hw = 1.35 + m
		local top = 1.25 + m
		local tip = -2.0 - m * 1.4
		local split = -0.3 - m * 0.6 -- each layer splits box / point at its own height
		tp(t, name, V(hw * 2, top - split, d), color, mat, CF(0, (top + split) / 2, 0))
		ttri(t, name, hw, split - tip, d, color, mat, CF(-hw / 2, (split + tip) / 2, 0), "tr")
		ttri(t, name, hw, split - tip, d, color, mat, CF(hw / 2, (split + tip) / 2, 0), "tl")
	end
end

function Models.ClassEmblem(key: string): Model
	local def, z, _, _, r = Items.Def(key)
	r = math.max(r, 1)
	local mods = (def and def.mods) or {}
	local zi = math.clamp(z, 0, 9)
	local zoneColor = Items.CoreColor(math.max(zi, 1))
	local rc = Items.RarityColor(r)
	local secret = Config.Rarities[r] ~= nil and Config.Rarities[r].secret == true
	local t = newTrophy("ClassEmblem")
	local shape = EMBLEM_SHAPES[zi] or "heater"
	local heater = shape == "heater" or shape == "gothic" or shape == "flame"
	local field = secret and INK or darker(zoneColor, 0.45)
	local rimBase = if zi == 4 or zi == 9 then GOLD elseif zi == 8 then rgb(60, 40, 90) else rgb(150, 154, 166)
	local rim = if r >= 5 then GOLD elseif r >= 3 then rimBase:Lerp(rc, 0.55) else rimBase
	local rimMat = if r >= 5 then MAT.Foil else MAT.Metal
	-- field in front, rim (grown outline) behind it, glowing outline from Mythic
	emblemShape(t, shape, 0, 0.5, field, MAT.SmoothPlastic, "Field")
	emblemShape(t, shape, 0.2, 0.36, rim, rimMat, "Rim")
	if r >= 6 then
		emblemShape(t, shape, 0.42, 0.22, secret and WHITE or rc, MAT.Neon, "Glow")
	end
	local top = heater and 1.45 or (shape == "diamond" and 1.95 or 1.75)
	local halfW = heater and 1.55 or (shape == "diamond" and 1.95 or 1.75)
	-- zone decorations around the silhouette
	if shape == "gothic" then
		for _, side in SIDES do
			ttri(t, "Spire", 0.5, 0.8, 0.36, rim, rimMat, CF(side * 1.3, top + 0.35, 0), side < 0 and "br" or "bl")
		end
	elseif shape == "flame" then
		for i = -1, 1 do
			ttri(t, "Flame", 0.36, i == 0 and 1.0 or 0.7, 0.3, rgb(255, 120, 30), MAT.Neon, CF(i * 0.6 - 0.18, top + (i == 0 and 0.45 or 0.3), 0), "br")
			ttri(t, "Flame", 0.36, i == 0 and 1.0 or 0.7, 0.3, rgb(255, 170, 60), MAT.Neon, CF(i * 0.6 + 0.18, top + (i == 0 and 0.45 or 0.3), 0), "bl")
		end
	elseif shape == "sun" then
		for _, side in SIDES do
			for i = 0, 2 do
				local L = 1.35 - i * 0.25
				tp(t, "Wing", V(L, 0.32, 0.3), i == 1 and rgb(40, 90, 200) or GOLD, MAT.Foil, CF(side * (1.2 + L / 2), 0.4 - i * 0.36, 0))
			end
		end
	elseif shape == "frost" then
		for i = 0, 5 do
			local a = i * PI / 3 + PI / 2
			tp(t, "Icicle", V(0.26, 0.6, 0.3), rgb(210, 240, 255), MAT.Ice, CF(math.cos(a) * 2.1, math.sin(a) * 2.1, 0) * ANG(0, 0, a - PI / 2) * ANG(0, 0, PI / 4))
		end
	elseif shape == "cog" then
		for i = 0, 7 do
			local a = i * PI / 4
			tp(t, "Tooth", V(0.62, 0.62, 0.3), rim, rimMat, CF(math.cos(a) * 1.72, math.sin(a) * 1.72, 0) * ANG(0, 0, a))
		end
	elseif shape == "star" then
		for i = 0, 7 do
			local a = i * PI / 4
			local L = i % 2 == 0 and 1.0 or 0.65
			tp(t, "Ray", V(0.24, L, 0.28), i % 2 == 0 and GOLD or rgb(80, 220, 255), MAT.Neon, CF(math.cos(a) * (1.72 + L / 2), math.sin(a) * (1.72 + L / 2), 0) * ANG(0, 0, a - PI / 2))
		end
	elseif shape == "round" then
		for _, side in SIDES do
			ttri(t, "Leaf", 0.5, 0.8, 0.3, rgb(90, 190, 80), MAT.Grass, CF(side * 0.45, top + 0.2, 0) * ANG(0, 0, side * 0.5), side < 0 and "br" or "bl")
		end
	end
	-- the class symbol, through the field so both faces show it
	local kind = next(mods) and classSymbol(mods) or "sword"
	local glow = r >= 4
	local sc = SYMBOL_COLORS[kind] or (if kind == "flame" then lighter(zoneColor, 0.1) else rgb(245, 240, 228))
	if secret then
		sc = WHITE
	end
	symbol(t, kind, CF(0, heater and 0.475 or 0, 0), heater and 1.05 or 1.0, sc, glow and MAT.Neon or MAT.SmoothPlastic, 0.74)
	-- rarity extras
	if r >= 2 then
		tp(t, "Gem", V(0.44, 0.44, 0.44), secret and RAINBOW[1] or rc, MAT.Neon, CF(0, top + 0.12, 0), Enum.PartType.Ball)
	end
	if r >= 3 then
		for i, side in SIDES do
			tp(t, "Stud", V(0.34, 0.34, 0.34), secret and RAINBOW[i + 2] or rim, secret and MAT.Neon or rimMat, CF(side * halfW, heater and 0.9 or 0, 0), Enum.PartType.Ball)
		end
	end
	if r >= 4 then
		local e = sparkles(t.root, rc, 4 + r, 0.4)
		if secret then
			e.Color = ColorSequence.new(RAINBOW[1], RAINBOW[4])
		end
	end
	if r >= 5 then
		-- golden crest: little crown and wings above the shield
		for _, side in SIDES do
			tp(t, "CrestWing", V(0.9, 0.24, 0.24), GOLD, MAT.Foil, CF(side * 0.75, top + 0.5, 0) * ANG(0, 0, side * 0.45))
			tp(t, "CrestWing", V(0.65, 0.2, 0.2), GOLD, MAT.Foil, CF(side * 0.72, top + 0.26, 0) * ANG(0, 0, side * 0.2))
		end
		tp(t, "Crown", V(0.5, 0.5, 0.26), GOLD, MAT.Foil, CF(0, top + 0.55, 0) * ANG(0, 0, PI / 4))
		light(t.root, rc, 12, 1.4)
	end
	if r >= 7 then
		for i = 0, 5 do
			local a = i * PI / 3
			tp(t, "Halo", V(0.2, 0.2, 0.2), secret and RAINBOW[i % 5 + 1] or rc, MAT.Neon, CF(math.cos(a) * 0.8, top + 1.15, math.sin(a) * 0.8) * ANG(0, -a, PI / 4))
		end
		for _, side in SIDES do
			tp(t, "Fragment", V(0.24, 0.5, 0.24), secret and RAINBOW[3] or lighter(rc, 0.2), MAT.Neon, CF(side * (halfW + 0.55), 0.3, 0) * ANG(0.4, 0, side * 0.5))
		end
	end
	return t.model
end

-- Ability tomes ---------------------------------------------------------------
local ABILITY_SIGIL: { [string]: string } = {
	dash = "arrow",
	shadowstep = "crescent",
	warp = "portal",
	bolt = "orb",
	strike = "bolt",
	nova = "burst",
	meteor = "meteor",
	stun = "snowflake",
	dot = "cloud",
	heal = "cross",
	buff = "flame",
	shield = "shield",
	drain = "drop",
}
Models.AbilitySigils = ABILITY_SIGIL

function Models.AbilityTome(key: string): Model
	local def, _, _, _, r = Items.Def(key)
	r = math.max(r, 1)
	local ability = def and Config.Abilities[def.ability]
	local kind: string = ability and ability.kind or "dash"
	local ac: Color3 = ability and ability.color or rgb(200, 200, 255)
	local rc = Items.RarityColor(r)
	local secret = Config.Rarities[r] ~= nil and Config.Rarities[r].secret == true
	local t = newTrophy("AbilityTome")
	-- an open book standing on its spine, the covers form a V opening toward -Z
	local spine = V(0, 0, 0.42)
	local phi = math.rad(58)
	local L, H = 1.5, 2.2
	local coverColor = secret and INK or darker(ac, 0.35)
	local metal = if r >= 5 then GOLD elseif r >= 3 then rgb(170, 170, 180):Lerp(rc, 0.5) else rgb(150, 150, 160)
	tp(t, "Spine", V(H + 0.12, 0.36, 0.36), darker(coverColor, 0.2), MAT.Leather, CF(spine) * UPRIGHT, Enum.PartType.Cylinder)
	for _, side in SIDES do
		local dir = V(side * math.sin(phi), 0, -math.cos(phi))
		local inner = V(-side * math.cos(phi), 0, -math.sin(phi))
		local theta = side > 0 and (PI / 2 - phi) or (PI / 2 + phi)
		local rot = ANG(0, theta, 0)
		local cc = spine + dir * (L / 2 + 0.05)
		tp(t, "Cover", V(L, H, 0.12), coverColor, MAT.Leather, CF(cc) * rot)
		local pc = spine + dir * (L / 2 - 0.04) + inner * 0.16
		tp(t, "Pages", V(L - 0.3, H - 0.36, 0.22), rgb(245, 236, 210):Lerp(ac, 0.22), MAT.SmoothPlastic, CF(pc) * rot)
		tp(t, "PageRune", V(0.5, 0.5, 0.08), ac, MAT.Neon, CF(pc + inner * 0.13 + V(0, 0.12, 0)) * rot * ANG(0, 0, PI / 4))
		tp(t, "PageLine", V(L - 0.6, 0.08, 0.08), darker(ac, 0.3), MAT.SmoothPlastic, CF(pc + inner * 0.13 + V(0, -0.5, 0)) * rot)
		if r >= 3 then
			for _, y in { -1, 1 } do
				tp(t, "Corner", V(0.3, 0.3, 0.26), metal, r >= 5 and MAT.Foil or MAT.Metal, CF(spine + dir * (L + 0.02) + V(0, y * (H / 2 - 0.08), 0)) * rot)
			end
		end
		if r >= 6 then
			tp(t, "Edge", V(0.12, H + 0.06, 0.16), secret and WHITE or rc, MAT.Neon, CF(spine + dir * (L + 0.1)) * rot)
		end
	end
	tp(t, "Ribbon", V(0.14, 1.0, 0.24), rgb(210, 40, 60), MAT.Fabric, CF(spine + V(0, -H / 2 - 0.35, -0.05)))
	if r >= 2 then
		tp(t, "Gem", V(0.36, 0.36, 0.36), secret and RAINBOW[2] or rc, MAT.Neon, CF(spine + V(0, 0, 0.2)), Enum.PartType.Ball)
	end
	if r >= 5 then
		for _, y in { -1, 1 } do
			tp(t, "SpineCap", V(0.14, 0.46, 0.46), GOLD, MAT.Foil, CF(spine + V(0, y * (H / 2 + 0.1), 0)) * UPRIGHT, Enum.PartType.Cylinder)
		end
		local circle = tp(t, "MagicCircle", V(0.06, 2.8, 2.8), secret and WHITE or rc, MAT.Neon, CF(0, -H / 2 - 0.35, 0) * UPRIGHT, Enum.PartType.Cylinder)
		circle.Transparency = 0.45
	end
	-- the glowing sigil hovering above
	local sy = H / 2 + 0.95
	symbol(t, ABILITY_SIGIL[kind] or "star", CF(0, sy, 0), 0.82, secret and WHITE or ac, MAT.Neon, 0.26)
	light(t.root, ac, r >= 5 and 14 or 9, r >= 5 and 1.6 or 1)
	if r >= 4 then
		local e = sparkles(t.root, r >= 6 and rc or ac, 3 + r, 0.35)
		if secret then
			e.Color = ColorSequence.new(RAINBOW[1], RAINBOW[4])
		end
	end
	if r >= 7 then
		for i = 0, 5 do
			local a = i * PI / 3
			tp(t, "Halo", V(0.18, 0.18, 0.18), secret and RAINBOW[i % 5 + 1] or rc, MAT.Neon, CF(math.cos(a) * 1.0, sy, math.sin(a) * 1.0) * ANG(0, -a, PI / 4))
		end
		for _, side in SIDES do
			tp(t, "LoosePage", V(0.55, 0.7, 0.05), rgb(250, 244, 225), MAT.SmoothPlastic, CF(side * 1.6, 0.5, -0.3) * ANG(0.3, side * 0.6, side * 0.25))
		end
	end
	return t.model
end

function Models.SetAnchored(model: Instance, anchored: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
	if model:IsA("BasePart") then
		model.Anchored = anchored
	end
end

return Models
