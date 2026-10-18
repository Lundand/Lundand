--!strict
-- Furniture and fittings, each built from a handful of parts around (0, floor, 0) in a placed frame.
-- Decoration doesn't collide unless it is something you would walk around (tables, counters, beds, crates).
local Kit = require(script.Parent.Kit)

local Furniture = {}
local C = Kit.colors
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }

-- Points that must stay clear (NPC standing spots, markers), in world X/Z.
local keepClear: {Vector3} = {}
function Furniture.setKeepClear(points: {Vector3})
	keepClear = points
end

-- A frame for one piece: at (x, y, z) in the building frame, turned by rot degrees.
function Furniture.at(f: Frame, x: number, y: number, z: number, rot: number?): Frame?
	local cf = f.cframe * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rot or 0), 0)
	local p = cf.Position
	for _, point in ipairs(keepClear) do
		if math.abs(p.Y - point.Y) < 8 and Vector3.new(p.X - point.X, 0, p.Z - point.Z).Magnitude < 4 then
			return nil
		end
	end
	return Kit.frame(f.parent, cf)
end

function Furniture.table(g: Frame, w: number, d: number, color: Color3?)
	g:box("TableTop", Vector3.new(w, 0.3, d), 0, 2.85, 0, color or C.wood, M.WoodPlanks)
	g:box("TableLeg", Vector3.new(math.min(w, d) * 0.3, 2.7, math.min(w, d) * 0.3), 0, 1.35, 0, C.darkWood, M.Wood)
end

function Furniture.chair(g: Frame)
	g:box("Seat", Vector3.new(1.6, 1.8, 1.6), 0, 0.9, 0, C.wood, M.Wood)
end

function Furniture.stool(g: Frame)
	g:cyl("Stool", 1.7, 1.3, 0, 0, 0, C.wood, M.Wood)
end

function Furniture.bench(g: Frame, length: number)
	g:box("Bench", Vector3.new(length, 1.7, 1.3), 0, 0.85, 0, C.wood, M.WoodPlanks)
end

function Furniture.bed(g: Frame, double: boolean?, blanket: Color3?)
	local w = if double then 5 else 3.4
	g:box("BedFrame", Vector3.new(w, 1.4, 7), 0, 0.7, 0, C.darkWood, M.Wood)
	g:box("Blanket", Vector3.new(w - 0.2, 0.6, 5.2), 0, 1.7, 0.8, blanket or C.cloth[1], M.Fabric, NO)
end

function Furniture.fourPoster(g: Frame, blanket: Color3)
	Furniture.bed(g, true, blanket)
	for _, side in ipairs({ -1, 1 }) do
		g:box("BedPost", Vector3.new(0.4, 7, 0.4), side * 2.4, 3.5, -3.2, C.darkWood, M.Wood, NO)
	end
	g:box("Canopy", Vector3.new(5.2, 0.3, 4), 0, 7, -1.4, blanket, M.Fabric, NO)
end

function Furniture.strawBed(g: Frame)
	g:box("StrawMat", Vector3.new(3.2, 0.5, 6), 0, 0.25, 0, C.straw, M.Fabric, NO)
	g:box("Rag", Vector3.new(2.8, 0.2, 3), 0, 0.6, 0.8, rgb(120, 104, 86), M.Fabric, NO)
end

function Furniture.chest(g: Frame, color: Color3?)
	g:box("Chest", Vector3.new(3, 1.8, 1.8), 0, 0.9, 0, color or C.wood, M.Wood)
end

function Furniture.wardrobe(g: Frame)
	g:box("Wardrobe", Vector3.new(4, 7, 2), 0, 3.5, 0, C.darkWood, M.Wood)
end

function Furniture.shelf(g: Frame, width: number, goods: {Color3}?, material: Enum.Material?)
	g:box("Shelf", Vector3.new(width, 7, 1.4), 0, 3.5, 0, C.darkWood, M.Wood)
	local colors: {Color3} = goods or { rgb(120, 40, 40), rgb(40, 60, 110), rgb(150, 120, 60) }
	g:box("Goods", Vector3.new(width - 0.6, 3.4, 0.5), 0, 4.4, 0.75, colors[1], material or M.Fabric, NO)
end

function Furniture.bookshelf(g: Frame, width: number)
	Furniture.shelf(g, width, { rgb(110, 40, 30), rgb(40, 50, 90), rgb(60, 80, 50), rgb(130, 100, 50) }, M.Leather)
end

function Furniture.counter(g: Frame, length: number, color: Color3?)
	g:box("Counter", Vector3.new(length, 3.6, 2), 0, 1.8, 0, color or C.wood, M.WoodPlanks)
end

function Furniture.barrel(g: Frame, height: number?)
	g:cyl("Barrel", height or 3.2, 2.4, 0, 0, 0, rgb(116, 82, 52), M.Wood)
end

function Furniture.crate(g: Frame, size: number?)
	local s = size or 2.6
	g:box("Crate", Vector3.new(s, s, s), 0, s / 2, 0, rgb(150, 112, 70), M.WoodPlanks)
end

function Furniture.crates(g: Frame, count: number)
	for index = 0, math.min(count, 2) - 1 do
		local s = 2.4 + (index % 2) * 0.6
		g:box("Crate", Vector3.new(s, s, s), (index % 3) * 3 - 3, s / 2 + math.floor(index / 3) * 3, 0, rgb(150 - index * 6, 112, 70), M.WoodPlanks)
	end
end

function Furniture.sacks(g: Frame)
	g:box("Sacks", Vector3.new(5.4, 2, 1.6), 0, 1, 0, rgb(186, 164, 118), M.Fabric, NO)
end

function Furniture.rug(g: Frame, w: number, d: number, color: Color3)
	g:box("Rug", Vector3.new(w, 0.1, d), 0, 0.05, 0, color, M.Fabric, NO)
end

-- A hearth against a wall (the wall is behind, at -z).
function Furniture.hearth(g: Frame, lit: boolean?, stone: Color3?)
	local color = stone or rgb(120, 116, 110)
	g:box("HearthBack", Vector3.new(6, 6, 2.4), 0, 3, 0, color, M.Cobblestone)
	g:box("Mantel", Vector3.new(6.6, 0.6, 3), 0, 4.3, 0.4, C.darkWood, M.Wood, NO)
	local embers = g:box("Embers", Vector3.new(3, 0.8, 0.4), 0, 0.6, 1.25, C.fire, M.Neon, NO)
	embers.CastShadow = false
	if lit ~= false then
		Kit.light(embers, rgb(255, 170, 90), 22, 1.4)
	end
end

function Furniture.lamp(g: Frame, height: number)
	local lamp = g:box("Lamp", Vector3.new(0.8, 1, 0.8), 0, height, 0, rgb(255, 214, 150), M.Neon, NO)
	lamp.CastShadow = false
	Kit.light(lamp, rgb(255, 210, 150), 20, 1)
end

function Furniture.painting(g: Frame, w: number, h: number, color: Color3)
	g:box("Painting", Vector3.new(w, h, 0.2), 0, 6, 0, color, M.SmoothPlastic, NO)
	g:box("PaintingFrame", Vector3.new(w + 0.4, h + 0.4, 0.1), 0, 6, -0.1, C.lundandGold, M.Metal, NO)
end

function Furniture.banner(g: Frame, color: Color3, height: number?)
	g:box("Banner", Vector3.new(3, 6, 0.15), 0, height or 6, 0, color, M.Fabric, NO)
end

-- House Lundand's crest: a silver tower on deep blue, a gold star of the rifts above it.
function Furniture.crest(g: Frame, scale: number)
	local s = scale
	g:box("CrestField", Vector3.new(3 * s, 3.6 * s, 0.2), 0, 0, 0, C.lundandBlue, M.Fabric, NO)
	g:box("CrestTower", Vector3.new(1 * s, 1.8 * s, 0.1), 0, -0.5 * s, 0.15, C.lundandSilver, M.SmoothPlastic, NO)
	g:box("CrestTowerTop", Vector3.new(1.5 * s, 0.4 * s, 0.1), 0, 0.5 * s, 0.15, C.lundandSilver, M.SmoothPlastic, NO)
	g:boxAt("CrestStar", Vector3.new(0.8 * s, 0.8 * s, 0.1), CFrame.new(0, 1.2 * s, 0.15) * CFrame.Angles(0, 0, math.rad(45)), C.lundandGold, M.SmoothPlastic, NO)
end

function Furniture.anvil(g: Frame)
	g:box("AnvilBase", Vector3.new(1.4, 2, 1.4), 0, 1, 0, rgb(80, 64, 50), M.Wood)
	g:box("Anvil", Vector3.new(3, 1, 1.3), 0, 2.5, 0, C.iron, M.Metal)
end

function Furniture.forge(g: Frame)
	g:box("ForgeBase", Vector3.new(6, 3, 5), 0, 1.5, 0, rgb(110, 100, 96), M.Brick)
	g:box("ForgeHood", Vector3.new(6, 6, 4), 0, 8, -0.5, rgb(90, 84, 80), M.Brick, NO)
	local coals = g:box("Coals", Vector3.new(4, 0.4, 3), 0, 3.2, 0, rgb(255, 110, 40), M.Neon, NO)
	coals.CastShadow = false
	Kit.light(coals, rgb(255, 140, 60), 26, 2)
end

function Furniture.weaponRack(g: Frame)
	g:box("Rack", Vector3.new(5, 5, 0.6), 0, 2.5, 0, C.darkWood, M.Wood)
	for index = -1, 1 do
		g:box("Blade", Vector3.new(0.3, 4, 0.15), index * 1.4, 3, 0.4, rgb(190, 194, 200), M.Metal, NO)
	end
end

function Furniture.armorStand(g: Frame)
	g:box("StandPost", Vector3.new(0.4, 5, 0.4), 0, 2.5, 0, C.darkWood, M.Wood, NO)
	g:box("Cuirass", Vector3.new(2, 2.4, 1.2), 0, 4.2, 0, rgb(160, 164, 170), M.Metal)
end

function Furniture.display(g: Frame, colors: {Color3}, material: Enum.Material?)
	Furniture.table(g, 4, 2.6)
	for index = -1, 1 do
		g:box("Ware", Vector3.new(0.9, 0.8, 0.9), index * 1.3, 3.4, 0, colors[(index + 1) % #colors + 1], material or M.SmoothPlastic, NO)
	end
end

function Furniture.bottles(g: Frame, width: number)
	g:box("Shelf", Vector3.new(width, 7, 1.4), 0, 3.5, 0, C.darkWood, M.Wood)
	local tints = { rgb(200, 60, 60), rgb(60, 160, 90), rgb(80, 110, 210), rgb(200, 170, 60) }
	for row = 1, 2 do
		for index = 0, 2 do
			g:box("Bottle", Vector3.new(0.5, 0.9, 0.5), -width / 2 + 1 + index * (width - 2) / 2, 1.6 + row * 2, 0.6, tints[(row + index) % #tints + 1], M.Glass, NO)
		end
	end
end

function Furniture.desk(g: Frame)
	g:box("Desk", Vector3.new(5, 2.9, 2.6), 0, 1.45, 0, C.darkWood, M.Wood)
	g:box("Papers", Vector3.new(1.6, 0.1, 1.1), -0.8, 2.95, 0.2, C.linen, M.SmoothPlastic, NO)
	g:box("Inkwell", Vector3.new(0.3, 0.4, 0.3), 1.2, 3.1, 0.3, rgb(20, 20, 30), M.Glass, NO)
end

function Furniture.bunk(g: Frame)
	g:box("BunkLow", Vector3.new(3.4, 1.4, 7), 0, 0.7, 0, C.wood, M.Wood)
	g:box("BunkHigh", Vector3.new(3.4, 0.6, 7), 0, 4.5, 0, C.wood, M.Wood, NO)
	g:box("BunkPost", Vector3.new(0.4, 5.2, 0.4), 1.5, 2.6, 3.3, C.darkWood, M.Wood, NO)
end

function Furniture.longTable(g: Frame, length: number)
	g:box("LongTable", Vector3.new(4, 0.3, length), 0, 2.85, 0, C.wood, M.WoodPlanks)
	g:box("TableLeg", Vector3.new(1, 2.7, length - 2), 0, 1.35, 0, C.darkWood, M.Wood)
	for _, side in ipairs({ -1, 1 }) do
		g:box("Bench", Vector3.new(1.3, 1.7, length - 1), side * 3, 0.85, 0, C.wood, M.WoodPlanks)
	end
end

function Furniture.board(g: Frame, title: string, width: number)
	local board = g:box("ContractBoard", Vector3.new(width, 5, 0.4), 0, 5.5, 0, rgb(108, 78, 50), M.WoodPlanks)
	Kit.sign(board, Enum.NormalId.Front, title, rgb(250, 240, 210))
	for index = 0, 3 do
		g:box("Notice", Vector3.new(1.2, 1.6, 0.1), -width / 2 + 1.2 + index * (width - 2.4) / 3, 4.4, -0.25, C.linen, M.SmoothPlastic, NO)
	end
	return board
end

function Furniture.cauldron(g: Frame)
	g:cyl("Cauldron", 2.4, 3, 0, 0, 0, rgb(50, 50, 54), M.Metal)
	local brew = g:cyl("Brew", 0.2, 2.4, 0, 2.3, 0, rgb(110, 200, 120), M.Neon, NO)
	brew.CastShadow = false
end

function Furniture.workbench(g: Frame)
	g:box("Workbench", Vector3.new(6, 3, 2.6), 0, 1.5, 0, C.lightWood, M.WoodPlanks)
	g:box("Tools", Vector3.new(1.4, 0.3, 0.6), -1.6, 3.15, 0.3, C.iron, M.Metal, NO)
	g:box("Plank", Vector3.new(3, 0.3, 0.8), 1, 3.15, -0.2, rgb(190, 150, 100), M.Wood, NO)
end

function Furniture.loom(g: Frame)
	g:box("LoomFrame", Vector3.new(5, 5, 0.5), 0, 2.5, 0, C.wood, M.Wood)
	g:box("Weave", Vector3.new(4, 3, 0.1), 0, 3, 0.3, C.cloth[2], M.Fabric, NO)
end

function Furniture.throne(g: Frame)
	g:box("ThroneDais", Vector3.new(14, 1.2, 10), 0, 0.6, 0, rgb(150, 40, 40), M.Fabric)
	g:box("ThroneSeat", Vector3.new(4, 2.4, 3.4), 0, 2.4, -1, C.lundandGold, M.Metal)
	g:box("ThroneBack", Vector3.new(4, 7, 0.8), 0, 5.6, -2.6, C.lundandGold, M.Metal, NO)
end

function Furniture.pew(g: Frame, length: number)
	g:box("Pew", Vector3.new(length, 1.8, 1.6), 0, 0.9, 0, C.darkWood, M.Wood)
	g:box("PewBack", Vector3.new(length, 2, 0.3), 0, 2.6, 0.7, C.darkWood, M.Wood, NO)
end

-- Goods for a shop kind: what sits on the shelves and display tables.
Furniture.goods = {
	GeneralGoods = { rgb(150, 120, 70), rgb(120, 90, 60), rgb(170, 160, 140) },
	Weapons = { rgb(190, 194, 200), rgb(110, 90, 70) },
	Armor = { rgb(160, 164, 170), rgb(120, 90, 60) },
	Tailor = { rgb(150, 40, 40), rgb(40, 70, 130), rgb(200, 180, 120) },
	Bakery = { rgb(200, 150, 80), rgb(170, 120, 60), rgb(220, 190, 130) },
	Butcher = { rgb(170, 70, 60), rgb(200, 150, 140) },
	Potions = { rgb(200, 60, 60), rgb(60, 160, 90), rgb(80, 110, 210) },
	MagicSupplies = { rgb(110, 70, 160), rgb(70, 140, 170), rgb(200, 190, 140) },
	Jeweler = { rgb(212, 170, 72), rgb(200, 205, 215), rgb(120, 40, 120) },
	Cobbler = { rgb(90, 60, 40), rgb(120, 80, 50) },
	Grocer = { rgb(120, 170, 60), rgb(200, 90, 50), rgb(220, 190, 80) },
	Bookbinder = { rgb(110, 40, 30), rgb(40, 50, 90), rgb(130, 100, 50) },
	Chandler = { rgb(240, 230, 200), rgb(220, 200, 150) },
	Chandlery = { rgb(150, 120, 80), rgb(200, 190, 160) },
	FishShop = { rgb(160, 170, 180), rgb(120, 140, 150) },
	Rope = { rgb(180, 150, 100) },
	Pawnshop = { rgb(160, 150, 120), rgb(110, 100, 90), rgb(190, 170, 90) },
	FoodStall = { rgb(170, 110, 60), rgb(200, 160, 90) },
	Carpenter = { rgb(190, 150, 100) },
	Tanner = { rgb(120, 80, 50), rgb(150, 110, 70) },
	Weaver = { rgb(150, 40, 40), rgb(40, 70, 130) },
	Storage = { rgb(150, 112, 70) },
	Workshop = { rgb(150, 112, 70), rgb(120, 120, 120) },
}

return Furniture
