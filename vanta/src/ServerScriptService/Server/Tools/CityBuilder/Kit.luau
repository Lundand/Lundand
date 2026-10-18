--!strict
-- Building kit for the city: part helpers that work in a local frame, district palettes, walls with openings,
-- floor slabs with stairwell holes, and stair flights. Everything is anchored; decoration never collides.
local Kit = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Kit.rgb = rgb

local M = Enum.Material
Kit.materials = M

-- District palettes (docs/ART_DIRECTION.md): grounded medieval materials, one family per district.
Kit.palettes = {
	Market = {
		base = { rgb(176, 168, 150), rgb(160, 152, 136), rgb(186, 176, 156) },
		baseMaterial = M.Cobblestone,
		plaster = { rgb(232, 222, 196), rgb(238, 230, 210), rgb(226, 208, 160), rgb(214, 200, 170) },
		timber = { rgb(74, 52, 36), rgb(62, 44, 30), rgb(86, 60, 40) },
		roof = { rgb(150, 70, 52), rgb(128, 64, 48), rgb(110, 76, 60), rgb(140, 90, 70) },
		roofMaterial = M.ClayRoofTiles,
		trim = rgb(150, 144, 130),
		jetty = 0.8,
	},
	Residential = {
		base = { rgb(168, 160, 145), rgb(150, 144, 132), rgb(178, 170, 154) },
		baseMaterial = M.Cobblestone,
		plaster = { rgb(230, 222, 200), rgb(220, 206, 172), rgb(236, 230, 214), rgb(204, 190, 160) },
		timber = { rgb(70, 50, 34), rgb(84, 60, 42) },
		roof = { rgb(140, 72, 54), rgb(116, 84, 66), rgb(104, 100, 98), rgb(150, 86, 62) },
		roofMaterial = M.ClayRoofTiles,
		trim = rgb(150, 144, 130),
		jetty = 0.8,
	},
	Noble = {
		base = { rgb(206, 198, 180), rgb(196, 190, 176) },
		baseMaterial = M.Limestone,
		plaster = { rgb(214, 206, 188), rgb(222, 216, 200) },
		timber = { rgb(60, 54, 50) },
		roof = { rgb(78, 84, 96), rgb(70, 76, 88), rgb(92, 96, 104) },
		roofMaterial = M.Slate,
		trim = rgb(236, 232, 220),
		jetty = 0,
		upperMaterial = M.Limestone,
	},
	Slum = {
		base = { rgb(120, 110, 96), rgb(110, 100, 88), rgb(132, 120, 102) },
		baseMaterial = M.Cobblestone,
		plaster = { rgb(170, 158, 132), rgb(150, 136, 112), rgb(160, 150, 130) },
		timber = { rgb(76, 62, 48), rgb(90, 74, 56), rgb(66, 56, 46) },
		roof = { rgb(98, 82, 66), rgb(88, 84, 80), rgb(110, 90, 70) },
		roofMaterial = M.WoodPlanks,
		trim = rgb(110, 100, 88),
		jetty = 0.6,
		upperMaterial = M.WoodPlanks,
	},
	Harbor = {
		base = { rgb(140, 138, 132), rgb(126, 124, 120) },
		baseMaterial = M.Slate,
		plaster = { rgb(200, 192, 176), rgb(180, 170, 150) },
		timber = { rgb(82, 66, 50), rgb(70, 58, 46) },
		roof = { rgb(96, 96, 98), rgb(110, 84, 66), rgb(84, 88, 92) },
		roofMaterial = M.RoofShingles,
		trim = rgb(120, 118, 112),
		jetty = 0,
		upperMaterial = M.WoodPlanks,
	},
	Craft = {
		base = { rgb(150, 92, 72), rgb(136, 84, 66), rgb(160, 104, 80) },
		baseMaterial = M.Brick,
		plaster = { rgb(220, 210, 186), rgb(206, 194, 166) },
		timber = { rgb(70, 50, 36) },
		roof = { rgb(120, 70, 54), rgb(100, 90, 84) },
		roofMaterial = M.ClayRoofTiles,
		trim = rgb(140, 130, 116),
		jetty = 0,
	},
	Royal = {
		base = { rgb(178, 174, 166), rgb(168, 164, 156) },
		baseMaterial = M.Limestone,
		plaster = { rgb(190, 186, 178) },
		timber = { rgb(58, 52, 48) },
		roof = { rgb(66, 74, 92), rgb(72, 80, 100) },
		roofMaterial = M.Slate,
		trim = rgb(220, 214, 200),
		jetty = 0,
		upperMaterial = M.Limestone,
	},
	Church = {
		base = { rgb(196, 194, 188) },
		baseMaterial = M.Limestone,
		plaster = { rgb(196, 194, 188) },
		timber = { rgb(70, 54, 40) },
		roof = { rgb(84, 90, 100) },
		roofMaterial = M.Slate,
		trim = rgb(220, 218, 210),
		jetty = 0,
		upperMaterial = M.Limestone,
	},
}

Kit.colors = {
	wood = rgb(120, 86, 56),
	darkWood = rgb(78, 56, 38),
	lightWood = rgb(168, 130, 90),
	floor = rgb(132, 98, 66),
	stoneFloor = rgb(150, 146, 138),
	iron = rgb(58, 58, 62),
	glass = rgb(170, 196, 210),
	cloth = { rgb(150, 40, 40), rgb(40, 70, 130), rgb(60, 110, 60), rgb(170, 130, 50), rgb(110, 60, 120) },
	straw = rgb(196, 170, 100),
	linen = rgb(226, 220, 200),
	lundandBlue = rgb(28, 46, 98),
	lundandSilver = rgb(214, 218, 224),
	lundandGold = rgb(212, 170, 72),
	fire = rgb(255, 150, 60),
}

--------------------------------------------------------------------------------------------------------------------
-- Counting and yielding: the builder makes tens of thousands of parts, so it can pause now and then.
--------------------------------------------------------------------------------------------------------------------
Kit.stats = { parts = 0, lights = 0 }
local yieldEvery = 0
local yieldFn: (() -> ())? = nil
function Kit.setYield(every: number, fn: (() -> ())?)
	yieldEvery = every
	yieldFn = fn
end
local function counted()
	Kit.stats.parts += 1
	if yieldFn ~= nil and yieldEvery > 0 and Kit.stats.parts % yieldEvery == 0 then
		yieldFn()
	end
end

export type Options = { collide: boolean?, transparency: number?, shape: Enum.PartType?, shadow: boolean?, query: boolean? }

local function setup(item: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, options: Options?)
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cf
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	local collide = true
	if options ~= nil then
		if options.collide ~= nil then
			collide = options.collide
		end
		if options.transparency ~= nil then
			item.Transparency = options.transparency
		end
		if options.shadow == false then
			item.CastShadow = false
		end
	end
	item.CanCollide = collide
	item.CanTouch = false
	item.CanQuery = if options ~= nil and options.query ~= nil then options.query else collide
	counted()
end

function Kit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?): Part
	local item = Instance.new("Part")
	if options ~= nil and options.shape ~= nil then
		item.Shape = options.shape
	end
	setup(item, name, size, cf, color, material or M.SmoothPlastic, options)
	item.Parent = parent
	return item
end

function Kit.wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?): WedgePart
	local item = Instance.new("WedgePart")
	setup(item, name, size, cf, color, material or M.SmoothPlastic, options)
	item.Parent = parent
	return item
end

-- Real light sources are capped per building (Kit.lightBudget); past the cap a lamp still glows (Neon) but casts
-- no light. Every PointLight costs every nearby client a little, and a server may hold 200 players.
Kit.lightBudget = math.huge
function Kit.light(part: BasePart, color: Color3, range: number, brightness: number)
	if Kit.lightBudget <= 0 then
		return
	end
	Kit.lightBudget -= 1
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	Kit.stats.lights += 1
end

function Kit.model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Kit.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- A text face on a part (shop signs, the contract board, street names).
function Kit.sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.Fantasy
	label.TextColor3 = color or rgb(240, 226, 190)
	label.Parent = gui
	gui.Parent = part
end

--------------------------------------------------------------------------------------------------------------------
-- Local frames: build in a building's own coordinates (x across the facade, y up, z towards the street).
--------------------------------------------------------------------------------------------------------------------
export type Frame = {
	parent: Instance,
	cframe: CFrame,
	box: (self: Frame, name: string, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material?, options: Options?) -> Part,
	boxAt: (self: Frame, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?) -> Part,
	wedgeAt: (self: Frame, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?) -> WedgePart,
	cyl: (self: Frame, name: string, height: number, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?, options: Options?) -> Part,
	child: (self: Frame, parent: Instance) -> Frame,
	world: (self: Frame, x: number, y: number, z: number) -> Vector3,
}

local FrameClass = {}
FrameClass.__index = FrameClass

function Kit.frame(parent: Instance, cframe: CFrame): Frame
	return (setmetatable({ parent = parent, cframe = cframe }, FrameClass) :: any) :: Frame
end

function FrameClass.box(self: Frame, name: string, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material?, options: Options?): Part
	return Kit.part(self.parent, name, size, self.cframe * CFrame.new(x, y, z), color, material, options)
end

function FrameClass.boxAt(self: Frame, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?): Part
	return Kit.part(self.parent, name, size, self.cframe * cf, color, material, options)
end

function FrameClass.wedgeAt(self: Frame, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, options: Options?): WedgePart
	return Kit.wedge(self.parent, name, size, self.cframe * cf, color, material, options)
end

-- Upright cylinder standing on (x, y, z)
function FrameClass.cyl(self: Frame, name: string, height: number, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?, options: Options?): Part
	local opts: Options = { shape = Enum.PartType.Cylinder }
	if options ~= nil then
		opts.collide, opts.transparency, opts.shadow, opts.query = options.collide, options.transparency, options.shadow, options.query
	end
	return Kit.part(self.parent, name, Vector3.new(height, diameter, diameter), self.cframe * CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, material, opts)
end

function FrameClass.child(self: Frame, parent: Instance): Frame
	return Kit.frame(parent, self.cframe)
end

function FrameClass.world(self: Frame, x: number, y: number, z: number): Vector3
	return self.cframe:PointToWorldSpace(Vector3.new(x, y, z))
end

--------------------------------------------------------------------------------------------------------------------
-- Walls with openings. A wall runs along local X (at depth z) or along local Z (at x). Openings are
-- { from, to, bottom, top } in the wall's own run and height; the solid wall is split around them.
--------------------------------------------------------------------------------------------------------------------
export type Opening = { from: number, to: number, bottom: number, top: number }

function Kit.wall(f: Frame, name: string, alongX: boolean, fixed: number, from: number, to: number, y0: number, y1: number, thickness: number, openings: {Opening}, color: Color3, material: Enum.Material, options: Options?)
	if from > to then
		from, to = to, from
	end
	table.sort(openings, function(a, b)
		return a.from < b.from
	end)
	local function piece(a: number, b: number, bottom: number, top: number)
		if b - a < 0.05 or top - bottom < 0.05 then
			return
		end
		local mid, length, height = (a + b) / 2, b - a, top - bottom
		if alongX then
			f:box(name, Vector3.new(length, height, thickness), mid, (bottom + top) / 2, fixed, color, material, options)
		else
			f:box(name, Vector3.new(thickness, height, length), fixed, (bottom + top) / 2, mid, color, material, options)
		end
	end
	local cursor = from
	for _, opening in ipairs(openings) do
		local a, b = math.max(opening.from, from), math.min(opening.to, to)
		if b > a then
			piece(cursor, a, y0, y1)
			piece(a, b, y0, math.max(y0, opening.bottom))
			piece(a, b, math.min(y1, opening.top), y1)
			cursor = b
		end
	end
	piece(cursor, to, y0, y1)
end

-- A facade over several storeys: openings that share a run (windows stacked floor above floor) form a column,
-- so the wall is cut into full-height strips between columns plus the pieces between openings in each column.
-- Openings with different runs must not overlap.
function Kit.facade(f: Frame, name: string, alongX: boolean, fixed: number, from: number, to: number, y0: number, y1: number, thickness: number, openings: {Opening}, color: Color3, material: Enum.Material)
	if from > to then
		from, to = to, from
	end
	local columns: {[string]: any} = {}
	local sorted = {}
	for _, o in ipairs(openings) do
		local key = string.format("%.2f:%.2f", o.from, o.to)
		local column = columns[key]
		if column == nil then
			column = { from = o.from, to = o.to, list = {} }
			columns[key] = column
			table.insert(sorted, column)
		end
		table.insert(column.list, o)
	end
	table.sort(sorted, function(a, b)
		return a.from < b.from
	end)
	local function piece(a: number, b: number, bottom: number, top: number)
		if b - a < 0.05 or top - bottom < 0.05 then
			return
		end
		local mid, length, height = (a + b) / 2, b - a, top - bottom
		if alongX then
			f:box(name, Vector3.new(length, height, thickness), mid, (bottom + top) / 2, fixed, color, material)
		else
			f:box(name, Vector3.new(thickness, height, length), fixed, (bottom + top) / 2, mid, color, material)
		end
	end
	local cursor = from
	for _, column in ipairs(sorted) do
		local a, b = math.max(column.from, from), math.min(column.to, to)
		if b > a then
			piece(cursor, a, y0, y1)
			table.sort(column.list, function(p1, p2)
				return p1.bottom < p2.bottom
			end)
			local y = y0
			for _, o in ipairs(column.list) do
				piece(a, b, y, math.max(y, o.bottom))
				y = math.max(y, o.top)
			end
			piece(a, b, y, y1)
			cursor = b
		end
	end
	piece(cursor, to, y0, y1)
end

-- A floor slab over a rectangle, leaving an optional hole (a stairwell).
export type Rect = { x0: number, x1: number, z0: number, z1: number }
function Kit.slab(f: Frame, name: string, r: Rect, top: number, thickness: number, hole: Rect?, color: Color3, material: Enum.Material)
	local y = top - thickness / 2
	local function piece(x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 > 0.05 and z1 - z0 > 0.05 then
			f:box(name, Vector3.new(x1 - x0, thickness, z1 - z0), (x0 + x1) / 2, y, (z0 + z1) / 2, color, material)
		end
	end
	if hole == nil then
		piece(r.x0, r.x1, r.z0, r.z1)
		return
	end
	local h = hole :: Rect
	piece(r.x0, r.x1, r.z0, h.z0) -- back
	piece(r.x0, r.x1, h.z1, r.z1) -- front
	piece(r.x0, h.x0, h.z0, h.z1) -- left of the hole
	piece(h.x1, r.x1, h.z0, h.z1) -- right of the hole
end

-- A straight flight of stairs in a lane, rising from (zLow, yLow) to (zHigh, yHigh) along local Z.
-- The walking surface is one inclined plank (smooth for characters and the camera); the visible steps
-- on top don't collide. Under the plank stays open, so flights can stack above each other.
function Kit.flight(f: Frame, name: string, x0: number, x1: number, zLow: number, zHigh: number, yLow: number, yHigh: number, color: Color3, stringer: Color3)
	local run = zHigh - zLow
	local rise = yHigh - yLow
	local length = math.sqrt(run * run + rise * rise)
	local width = x1 - x0
	local midX, midZ, midY = (x0 + x1) / 2, (zLow + zHigh) / 2, (yLow + yHigh) / 2
	local direction = if run >= 0 then 1 else -1
	-- the plank: its long axis follows the line from the low end to the high end
	local plankCF = CFrame.new(midX, midY - 0.4, midZ) * CFrame.Angles(math.atan2(-rise, run), 0, 0)
	f:boxAt(name .. "Ramp", Vector3.new(width, 0.7, length), plankCF, stringer, Enum.Material.Wood)
	-- visible treads (one per two studs of rise keeps the part count low; the ramp does the walking)
	local steps = math.max(3, math.floor(rise / 3 + 0.5))
	local tread = math.abs(run) / steps
	for index = 1, steps do
		local z = zLow + direction * (index - 0.5) * tread
		local top = yLow + rise * (index - 0.25) / steps
		f:box(name .. "Step", Vector3.new(width - 0.4, rise / steps, tread * 0.55), midX, top - rise / steps / 2 + 0.2, z + direction * tread * 0.2, color, Enum.Material.WoodPlanks, { collide = false, query = false })
	end
	return plankCF
end

return Kit
