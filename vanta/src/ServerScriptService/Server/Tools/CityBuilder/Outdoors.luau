--!strict
-- Everything between the buildings: the ground (city paving, meadows, the sea), roads and yards, city walls with
-- towers, gatehouses and wall-walk stairs, the harbour (quay, piers, ships, cranes, cargo), estate gardens, and the
-- street furniture that makes the city feel lived in (lanterns, stalls, wells, carts, troughs, laundry lines).
local Kit = require(script.Parent.Kit)
local Furniture = require(script.Parent.Furniture)
local Landmarks = require(script.Parent.Landmarks)
local Shell = require(script.Parent.Shell)
local LayoutRules = require(script.Parent.Parent.Parent.Domain.LayoutRules)

local Outdoors = {}
local C = Kit.colors
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }
local WORLD = Kit.frame(workspace, CFrame.new())

-- Rectangle minus holes, as a list of rectangles (holes must lie inside or overlap the rectangle).
local function subtract(r: {number}, holes: {{number}}): {{number}}
	local pieces = { r }
	for _, h in ipairs(holes) do
		local nextPieces = {}
		for _, p in ipairs(pieces) do
			local x0, x1, z0, z1 = p[1], p[2], p[3], p[4]
			if h[2] <= x0 or h[1] >= x1 or h[4] <= z0 or h[3] >= z1 then
				table.insert(nextPieces, p)
			else
				local hx0, hx1, hz0, hz1 = math.max(h[1], x0), math.min(h[2], x1), math.max(h[3], z0), math.min(h[4], z1)
				if hz0 > z0 then
					table.insert(nextPieces, { x0, x1, z0, hz0 })
				end
				if hz1 < z1 then
					table.insert(nextPieces, { x0, x1, hz1, z1 })
				end
				if hx0 > x0 then
					table.insert(nextPieces, { x0, hx0, hz0, hz1 })
				end
				if hx1 < x1 then
					table.insert(nextPieces, { hx1, x1, hz0, hz1 })
				end
			end
		end
		pieces = nextPieces
	end
	return pieces
end
Outdoors.subtract = subtract

local function slabs(parent: Instance, name: string, rects: {{number}}, top: number, thickness: number, color: Color3, material: Enum.Material)
	for _, r in ipairs(rects) do
		-- parts can't be larger than 2048 studs: long strips are split
		local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
		local nx, nz = math.ceil((x1 - x0) / 2000), math.ceil((z1 - z0) / 2000)
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local a0, a1 = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
				local b0, b1 = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
				local slab = Kit.part(parent, name, Vector3.new(a1 - a0, thickness, b1 - b0), CFrame.new((a0 + a1) / 2, top - thickness / 2, (b0 + b1) / 2), color, material)
				slab.CastShadow = false
			end
		end
	end
end

local function corners(entry: any): CFrame
	return CFrame.new(entry.center[1], 0, entry.center[2]) * CFrame.Angles(0, math.rad(entry.yaw or 0), 0)
end

--------------------------------------------------------------------------------------------------------------------
-- Ground, roads, yards
--------------------------------------------------------------------------------------------------------------------
function Outdoors.ground(layout: any, root: Instance, holes: {{number}})
	local folder = Kit.folder(root, "Ground")
	local b = layout.bounds
	local water = layout.water[1]
	local wx0 = water.center[1] - water.size[1] / 2
	local wz0, wz1 = water.center[2] - water.size[2] / 2, water.center[2] + water.size[2] / 2
	-- meadows outside the walls (the forest brings its own ground)
	slabs(folder, "Meadow", { { -760, wx0, -1120, b.maxZ + 14 }, { wx0, 760, -1120, wz0 } }, -0.25, 2, rgb(104, 140, 76), M.Grass)
	-- the city's paving, open over the cellar stairs, stopping at the quay
	local city = subtract({ b.minX - 6, wx0, b.minZ - 6, b.maxZ + 6 }, holes)
	table.insert(city, { wx0, b.maxX + 6, b.minZ - 6, wz0 })
	table.insert(city, { wx0, b.maxX + 6, wz1, b.maxZ + 6 })
	slabs(folder, "Paving", city, 0, 2, rgb(150, 142, 128), M.Cobblestone)
	-- the sea: terrain water where it can be made, a glassy surface otherwise
	local sea = { wx0, wx0 + water.size[1], wz0, wz1 + 40 }
	slabs(folder, "Seabed", { sea }, -water.depth, 2, rgb(150, 138, 110), M.Sand)
	local filled = pcall(function()
		local terrain = workspace.Terrain
		terrain:FillBlock(CFrame.new((sea[1] + sea[2]) / 2, (water.level - water.depth) / 2, (sea[3] + sea[4]) / 2), Vector3.new(sea[2] - sea[1], water.level + water.depth, sea[4] - sea[3]), Enum.Material.Water)
	end)
	if not filled then
		local surface = Kit.part(folder, "WaterSurface", Vector3.new(sea[2] - sea[1], 0.4, sea[4] - sea[3]), CFrame.new((sea[1] + sea[2]) / 2, water.level - 0.2, (sea[3] + sea[4]) / 2), rgb(60, 110, 150), M.Glass, { collide = false, query = false, transparency = 0.3, shadow = false })
		surface:SetAttribute("Water", true)
	end
	-- the quay wall along the water
	-- the quay walls stand a fifth of a stud proud of the land into the water, and stop just under the paving,
	-- so their faces never share a plane with the paving or the meadow
	local quayH = water.depth - 0.1
	Kit.part(folder, "QuayWall", Vector3.new(2.2, quayH, wz1 - wz0 - 0.4), CFrame.new(wx0 - 0.9, -0.1 - quayH / 2, (wz0 + wz1) / 2), rgb(130, 128, 120), M.Slate)
	Kit.part(folder, "QuayWall", Vector3.new(b.maxX - wx0 + 6.4, quayH, 2.2), CFrame.new((wx0 + b.maxX + 6.4) / 2, -0.1 - quayH / 2, wz0 - 0.9), rgb(130, 128, 120), M.Slate)
	Kit.part(folder, "QuayWall", Vector3.new(b.maxX - wx0 + 6.4, quayH, 2.2), CFrame.new((wx0 + b.maxX + 6.4) / 2, -0.1 - quayH / 2, wz1 + 0.9), rgb(130, 128, 120), M.Slate)
	-- the kerb along the quay, on the land side of the edge (the piers start at the edge)
	Kit.part(folder, "QuayEdge", Vector3.new(1.4, 0.4, wz1 - wz0 - 0.4), CFrame.new(wx0 - 0.7, 0.2, (wz0 + wz1) / 2), rgb(180, 176, 166), M.Limestone)
end

-- The paving is the street; only the square and the gardens are drawn on top of it, each a clear step higher and
-- never overlapping another surface, so nothing flickers.
function Outdoors.roads(layout: any, root: Instance)
	local folder = Kit.folder(root, "Surfaces")
	for _, zone in ipairs(layout.ground) do
		if zone.surface == "Plaza" and zone.shape == "Disc" then
			local disc = Kit.part(folder, zone.id, Vector3.new(0.3, zone.size[1], zone.size[1]), CFrame.new(zone.center[1], 0.15, zone.center[2]) * CFrame.Angles(0, 0, math.pi / 2), rgb(206, 196, 176), M.Pavement, { shape = Enum.PartType.Cylinder })
			disc.CastShadow = false
		elseif zone.surface == "Garden" then
			local bed = Kit.part(folder, zone.id, Vector3.new(zone.size[1], 0.4, zone.size[2]), corners(zone) * CFrame.new(0, 0.2, 0), rgb(96, 140, 70), M.Grass)
			bed.CastShadow = false
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- City walls, towers, gates, wall-walk stairs
--------------------------------------------------------------------------------------------------------------------
function Outdoors.walls(layout: any, root: Instance)
	local folder = Kit.folder(root, "CityWalls")
	local b, T, H = layout.bounds, layout.walls.thickness, layout.walls.height
	local stone = rgb(150, 146, 136)
	local water = layout.water[1]
	local wz0, wz1 = water.center[2] - water.size[2] / 2, water.center[2] + water.size[2] / 2
	-- no merlons inside the wall's towers or the castle's
	local function inTower(point: Vector3): boolean
		for _, tower in ipairs(layout.wallTowers) do
			if LayoutRules.contains(tower, { point.X, point.Z }) then
				return true
			end
		end
		for _, entry in ipairs(layout.blocks) do
			if entry.kind == "Tower" and LayoutRules.contains(entry, { point.X, point.Z }) then
				return true
			end
		end
		return false
	end
	local sides = {
		{ name = "North", alongX = true, fixed = b.minZ, from = b.minX, to = b.maxX, outward = -1 },
		{ name = "South", alongX = true, fixed = b.maxZ, from = b.minX, to = b.maxX, outward = 1 },
		{ name = "West", alongX = false, fixed = b.minX, from = b.minZ, to = b.maxZ, outward = -1 },
		{ name = "East", alongX = false, fixed = b.maxX, from = b.minZ, to = b.maxZ, outward = 1 },
	}
	for _, side in ipairs(sides) do
		local openings = {}
		for _, gate in ipairs(layout.gates) do
			local along, across = gate.center[1], gate.center[2]
			if not side.alongX then
				along, across = gate.center[2], gate.center[1]
			end
			if across == side.fixed then
				-- the wall stops half a stud inside the gate's piers, so its end never shows in the passage
				table.insert(openings, { along - gate.width / 2 - 0.5, along + gate.width / 2 + 0.5, gate })
			end
		end
		table.sort(openings, function(a, c)
			return a[1] < c[1]
		end)
		local segments = {}
		-- north and south walls run past the corners; east and west walls stop against them
		local start = if side.alongX then side.from - T / 2 else side.from + T / 2
		for _, opening in ipairs(openings) do
			table.insert(segments, { start, opening[1] })
			start = opening[2]
		end
		table.insert(segments, { start, if side.alongX then side.to + T / 2 else side.to - T / 2 })
		for index, seg in ipairs(segments) do
			local length = seg[2] - seg[1]
			if length > 0.5 then
				local mid = (seg[1] + seg[2]) / 2
				-- the stretch standing in the harbour goes down to the seabed
				local inWater = not side.alongX and side.name == "East" and mid > wz0 and mid < wz1
				local bottom = if inWater then -water.depth else -2
				local cf = if side.alongX then CFrame.new(mid, 0, side.fixed) else CFrame.new(side.fixed, 0, mid) * CFrame.Angles(0, math.pi / 2, 0)
				local f = Kit.frame(folder, cf)
				f:box(string.format("%sWall%d", side.name, index), Vector3.new(length, H - bottom, T), 0, (H + bottom) / 2, 0, stone, M.Limestone)
				Landmarks.merlons(f, true, side.outward * (T / 2 - 0.7) * (if side.alongX then 1 else -1), -length / 2, length / 2, H, stone, M.Limestone, inTower)
				f:box("WallWalk", Vector3.new(length, 0.3, T - 1.6), 0, H + 0.15, 0, rgb(130, 126, 118), M.Slate, NO)
			end
		end
	end
	-- towers along the walls (placed by the layout, so houses keep clear of them)
	for _, tower in ipairs(layout.wallTowers) do
		local x, z = tower.center[1], tower.center[2]
		local inWater = x == b.maxX and z > wz0 and z < wz1
		local f = Kit.frame(folder, CFrame.new(x, 0, z))
		local bottom = if inWater then -water.depth else -2
		f:box("WallTower", Vector3.new(tower.size[1], 42 - bottom, tower.size[2]), 0, (42 + bottom) / 2, 0, stone, M.Limestone)
		Landmarks.spire(f, 0, 42, 0, tower.size[1] + 1.4, 12, rgb(84, 90, 100), M.Slate)
	end
	-- gatehouses for the land gates, chain towers for the sea gate
	for _, gate in ipairs(layout.gates) do
		local x, z = gate.center[1], gate.center[2]
		local onEastWest = x == b.minX or x == b.maxX
		if gate.kind == "Sea" then
			for _, s in ipairs({ -1, 1 }) do
				local f = Kit.frame(folder, CFrame.new(x, 0, z + s * (gate.width / 2 + 8)))
				f:cyl("ChainTower", 46 + water.depth, 18, 0, -water.depth, 0, stone, M.Limestone)
				Landmarks.spire(f, 0, 46, 0, 18, 12, rgb(84, 90, 100), M.Slate)
			end
			local chain = Kit.part(folder, "HarbourChain", Vector3.new(0.6, 0.6, gate.width), CFrame.new(x, water.level - 0.6, z), C.iron, M.Metal, NO)
			chain.CastShadow = false
		else
			local cf = if onEastWest then CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi / 2, 0) else CFrame.new(x, 0, z)
			Landmarks.gatehouse(folder, gate.id .. "House", cf, gate.width, T + 10, H + 8, stone, true)
			-- the gate's marker carries its location ID
			local marker = Kit.part(folder, gate.id, Vector3.new(gate.width, 10, T), cf * CFrame.new(0, 5, 0), stone, M.SmoothPlastic, { collide = false, query = false, transparency = 1 })
			marker:SetAttribute("LocationId", gate.locationId)
			-- wall-walk stairs on the inner face beside the gate
			local inward = if z == b.maxZ then -1 elseif z == b.minZ then 1 else 0
			if inward ~= 0 then
				local laneZ0 = z + inward * (T / 2) + (if inward < 0 then -5 else 0)
				local stairs = Kit.frame(folder, CFrame.new(0, 0, laneZ0 + 2.5) * CFrame.Angles(0, math.pi / 2, 0))
				-- in this frame the lane runs along local z = world x
				local startX = x + gate.width / 2 + 14
				Kit.flight(stairs, "WallStairs", -2.5, 2.5, startX, startX + H * 1.25, 0, H, rgb(150, 146, 136), rgb(120, 116, 108))
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Harbour: piers, ships, boats, cranes, cargo
--------------------------------------------------------------------------------------------------------------------
local function ship(folder: Instance, spec: any, flag: boolean)
	local model = Kit.model(folder, spec.name)
	model:SetAttribute("ShipName", spec.name)
	local L, B = spec.length, spec.beam
	-- the ship lies along x, bow towards the sea (+x)
	local f = Kit.frame(model, CFrame.new(spec.center[1], 0, spec.center[2]))
	local hull = rgb(92, 64, 42)
	local deckY = 2.4
	f:box("Hull", Vector3.new(L * 0.78, 7, B), -L * 0.11, deckY - 3.5, 0, hull, M.WoodPlanks)
	f:box("Keel", Vector3.new(L * 0.7, 2, B * 0.5), -L * 0.08, deckY - 7.5, 0, hull:Lerp(Color3.new(0, 0, 0), 0.2), M.Wood)
	for _, s in ipairs({ -1, 1 }) do
		f:wedgeAt("Bow", Vector3.new(B / 2, 7, L * 0.22), CFrame.new(L * 0.39, deckY - 3.5, s * B / 4) * CFrame.Angles(0, -math.pi / 2, 0) * (if s == 1 then CFrame.new() else CFrame.new()), hull, M.WoodPlanks)
	end
	f:box("Deck", Vector3.new(L * 0.78, 0.4, B - 1), -L * 0.11, deckY + 0.2, 0, rgb(150, 116, 80), M.WoodPlanks)
	f:box("Sterncastle", Vector3.new(L * 0.17, 5, B), -L * 0.425 - 0.01 * L, deckY + 2.5, 0, hull, M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		f:box("Bulwark", Vector3.new(L * 0.62, 1.6, 0.5), 0, deckY + 1.2, s * (B / 2 - 0.25), hull, M.WoodPlanks)
	end
	f:box("Bowsprit", Vector3.new(L * 0.25, 0.7, 0.7), L * 0.55, deckY + 3, 0, rgb(80, 60, 40), M.Wood, NO)
	local masts = spec.masts
	for index = 1, masts do
		local mx = L * 0.3 - (index - 1) * (L * 0.6 / math.max(1, masts - 1 + 0.001))
		if masts == 1 then
			mx = 0
		end
		local height = L * 0.6 - (index - 1) * 4
		f:cyl("Mast", height, 1.1, mx, deckY, 0, rgb(96, 72, 48), M.Wood, NO)
		local sailW = B * 1.4
		f:box("Yard", Vector3.new(0.6, 0.6, sailW + 2), mx, deckY + height * 0.82, 0, rgb(96, 72, 48), M.Wood, NO)
		f:box("Sail", Vector3.new(0.3, height * 0.42, sailW), mx + 0.6, deckY + height * 0.6, 0, rgb(232, 224, 200), M.Fabric, NO)
	end
	if flag then
		f:box("Flag", Vector3.new(0.15, 2.6, 4), 0, deckY + L * 0.6 + 1, 2.2, C.lundandBlue, M.Fabric, NO)
	end
	f:box("Barrels", Vector3.new(3, 2.4, 3), -L * 0.2, deckY + 1.6, 0, rgb(116, 82, 52), M.Wood, NO)
end

function Outdoors.harbour(layout: any, root: Instance)
	local folder = Kit.folder(root, "Harbour")
	local water = layout.water[1]
	local wx0 = water.center[1] - water.size[1] / 2
	local wood = rgb(110, 84, 58)
	for index, pier in ipairs(layout.piers) do
		local f = Kit.frame(folder, CFrame.new(wx0 + pier.length / 2, 0, pier.z))
		f:box("PierDeck", Vector3.new(pier.length, 0.6, 8), 0, -0.3 + 0.3, 0, wood, M.WoodPlanks)
		for k = 0, math.floor(pier.length / 10) do
			for _, s in ipairs({ -1, 1 }) do
				f:cyl("Pile", water.depth, 1.2, -pier.length / 2 + 2 + k * 10, -water.depth, s * 3.6, rgb(80, 64, 50), M.Wood)
			end
		end
		for k = 1, 3 do
			f:cyl("Bollard", 1.6, 1, -pier.length / 2 + k * pier.length / 4, 0.3, 3.4, C.iron, M.Metal)
		end
		-- rowing boats tied up at every other pier
		if index % 2 == 0 then
			local bf = Kit.frame(folder, CFrame.new(wx0 + pier.length * 0.7, water.level, pier.z - 7))
			bf:box("Boat", Vector3.new(10, 1.6, 4), 0, -0.2, 0, rgb(120, 90, 60), M.WoodPlanks)
			bf:box("BoatSeat", Vector3.new(0.6, 0.4, 3.6), 0, 0.8, 0, rgb(150, 116, 80), M.WoodPlanks, NO)
			bf:wedgeAt("BoatBow", Vector3.new(4, 1.6, 2.4), CFrame.new(6.2, -0.2, 0) * CFrame.Angles(0, -math.pi / 2, 0), rgb(120, 90, 60), M.WoodPlanks)
		end
	end
	for index, spec in ipairs(layout.ships) do
		ship(folder, spec, index == 3)
		-- a gangplank from the deck to the nearest pier
		local nearest = layout.piers[1]
		for _, pier in ipairs(layout.piers) do
			if math.abs(pier.z - spec.center[2]) < math.abs(nearest.z - spec.center[2]) then
				nearest = pier
			end
		end
		local side = if nearest.z > spec.center[2] then 1 else -1
		local fromZ = spec.center[2] + side * spec.beam / 2
		local toZ = nearest.z - side * 4
		local length = math.abs(toZ - fromZ)
		if length > 0.5 and length < 30 then
			local slope = math.atan2(2.4, length)
			Kit.part(folder, "Gangplank", Vector3.new(3, 0.4, math.sqrt(length * length + 5.76)), CFrame.new(spec.center[1] - spec.length * 0.1, 1.4, (fromZ + toZ) / 2) * CFrame.Angles(side * slope, 0, 0), wood, M.WoodPlanks)
		end
	end
	-- cranes on the quay, swinging out over the water
	for _, z in ipairs({ -60, 50, 160, 240 }) do
		local f = Kit.frame(folder, CFrame.new(wx0 - 5, 0, z))
		f:box("CraneBase", Vector3.new(5, 2, 5), 0, 1, 0, wood, M.WoodPlanks)
		f:box("CranePost", Vector3.new(1.6, 22, 1.6), 0, 13, 0, wood, M.Wood)
		f:boxAt("CraneJib", Vector3.new(18, 1.2, 1.2), CFrame.new(7, 21, 0) * CFrame.Angles(0, 0, math.rad(12)), wood, M.Wood, NO)
		f:box("CraneRope", Vector3.new(0.2, 12, 0.2), 15, 17, 0, rgb(180, 160, 120), M.Fabric, NO)
		f:box("CraneLoad", Vector3.new(3, 3, 3), 15, 9.5, 0, rgb(150, 112, 70), M.WoodPlanks, NO)
	end
	-- cargo stacked along the quay apron, clear of the warehouse doors
	local cargoZ = { -120, -98, -6, 18, 96, 128, 176, 214, 262, 288 }
	for index, z in ipairs(cargoZ) do
		local g = Furniture.at(WORLD:child(folder), wx0 - 10, 0, z, 0)
		if g ~= nil then
			if index % 3 == 0 then
				Furniture.sacks(g)
			elseif index % 3 == 1 then
				Furniture.crates(g, 5)
			else
				for k = 0, 2 do
					local bg = Furniture.at(WORLD:child(folder), wx0 - 12 + k * 2.6, 0, z, 0)
					if bg ~= nil then
						Furniture.barrel(bg)
					end
				end
			end
		end
	end
	for _, z in ipairs({ -30, 110, 200 }) do
		local f = Kit.frame(folder, CFrame.new(wx0 - 8, 0, z))
		f:box("Nets", Vector3.new(5, 1, 4), 0, 0.5, 0, rgb(120, 110, 80), M.Fabric, NO)
		f:cyl("RopeCoil", 0.8, 3, 4, 0, 0, rgb(180, 160, 120), M.Fabric, NO)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Gardens, yards and street furniture
--------------------------------------------------------------------------------------------------------------------
local function lantern(folder: Instance, x: number, z: number)
	local f = Kit.frame(folder, CFrame.new(x, 0, z))
	f:cyl("LanternPost", 9, 0.5, 0, 0, 0, C.iron, M.Metal)
	local lamp = f:box("Lantern", Vector3.new(1.2, 1.6, 1.2), 0, 9.6, 0, rgb(255, 214, 150), M.Neon, NO)
	lamp.CastShadow = false
	f:box("LanternCap", Vector3.new(1.6, 0.4, 1.6), 0, 10.6, 0, C.iron, M.Metal, NO)
	Kit.light(lamp, rgb(255, 205, 140), 26, 1)
end

local function well(f: Frame, x: number, z: number)
	f:cyl("Well", 2.6, 5, x, 0, z, rgb(140, 136, 128), M.Cobblestone)
	f:cyl("WellWater", 0.1, 4, x, 2.4, z, rgb(50, 80, 100), M.Glass, NO)
	for _, s in ipairs({ -1, 1 }) do
		f:box("WellPost", Vector3.new(0.5, 5, 0.5), x + s * 2.2, 2.5, z, C.darkWood, M.Wood, NO)
	end
	f:box("WellRoof", Vector3.new(5.6, 0.5, 3), x, 5.2, z, rgb(110, 76, 56), M.WoodPlanks, NO)
end

local function cart(f: Frame, x: number, z: number, rot: number)
	local placed = Furniture.at(f, x, 0, z, rot)
	if placed == nil then
		return
	end
	local g = placed :: Frame
	g:box("CartBed", Vector3.new(4, 0.6, 7), 0, 2.4, 0, rgb(130, 96, 62), M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		g:boxAt("Wheel", Vector3.new(0.4, 3.6, 3.6), CFrame.new(s * 2.3, 1.8, 0.5) * CFrame.Angles(0, 0, 0), rgb(80, 60, 40), M.Wood, { collide = false, query = false, shape = Enum.PartType.Cylinder })
	end
	g:box("CartLoad", Vector3.new(3.4, 1.6, 4), 0, 3.5, 0, rgb(186, 164, 118), M.Fabric, NO)
	g:box("Shaft", Vector3.new(0.4, 0.4, 5), -1.2, 2.2, -5.5, rgb(100, 76, 50), M.Wood, NO)
end

local function stall(f: Frame, x: number, z: number, rot: number, cloth: Color3, goods: {Color3})
	local placed = Furniture.at(f, x, 0.12, z, rot)
	if placed == nil then
		return
	end
	local g = placed :: Frame
	Furniture.counter(g, 6, rgb(130, 96, 62))
	for _, s in ipairs({ -1, 1 }) do
		g:box("StallPost", Vector3.new(0.4, 8, 0.4), s * 3, 4, -1, C.darkWood, M.Wood, NO)
	end
	g:boxAt("StallCloth", Vector3.new(7.4, 0.25, 5), CFrame.new(0, 8.2, 0.4) * CFrame.Angles(math.rad(-12), 0, 0), cloth, M.Fabric, NO)
	for k = -1, 1 do
		g:box("StallGoods", Vector3.new(1.2, 0.8, 1), k * 1.8, 3.9, 0, goods[(k + 1) % #goods + 1], M.SmoothPlastic, NO)
	end
end

function Outdoors.dressing(layout: any, root: Instance)
	local folder = Kit.folder(root, "StreetDressing")
	local f = WORLD:child(folder)
	-- lanterns along the main roads, alternating sides
	for _, road in ipairs(layout.roads) do
		if (road.width == "Main" or road.width == "Noble") and (road.yaw or 0) == 0 and road.surface == nil then
			local alongX = road.size[1] > road.size[2]
			local length = if alongX then road.size[1] else road.size[2]
			local count = math.floor(length / 64)
			for index = 0, count - 1 do
				local t = -length / 2 + 32 + index * 64
				local side = if index % 2 == 0 then 1 else -1
				local half = (if alongX then road.size[2] else road.size[1]) / 2 - 0.8
				if alongX then
					lantern(folder, road.center[1] + t, road.center[2] + side * half)
				else
					lantern(folder, road.center[1] + side * half, road.center[2] + t)
				end
			end
		end
	end
	-- the square: market stalls, benches round the plaza, the clothier's stall, carts
	for _, zone in ipairs(layout.ground) do
		if zone.id == "MarketStalls" then
			local count = 6
			for index = 0, count - 1 do
				local x = zone.center[1] - zone.size[1] / 2 + 6 + index * (zone.size[1] - 12) / (count - 1)
				stall(f, x, zone.center[2], 180, C.cloth[index % #C.cloth + 1], Furniture.goods[({ "Grocer", "Bakery", "Butcher", "GeneralGoods", "Tailor", "Potions" })[index + 1]])
			end
		elseif zone.id == "FineryStall" then
			stall(f, zone.center[1], zone.center[2], 0, rgb(110, 60, 120), Furniture.goods.Tailor)
		elseif zone.surface == "Yard" and zone.district ~= nil and zone.size[1] * zone.size[2] > 160 then
			-- courtyards: a well or a woodpile and a cart
			local cx, cz = zone.center[1], zone.center[2]
			local seed = math.floor(math.abs(cx * 7 + cz * 13)) % 3
			if seed == 0 and zone.size[1] > 8 and zone.size[2] > 8 then
				well(f, cx, cz)
			elseif seed == 1 then
				local g = Furniture.at(f, cx, 0, cz, 0)
				if g ~= nil then
					g:box("Woodpile", Vector3.new(5, 2.4, 2.4), 0, 1.2, 0, rgb(130, 92, 58), M.Wood)
				end
			else
				cart(f, cx, cz, 90)
			end
		elseif zone.surface == "Alley" and zone.size[1] * zone.size[2] > 120 then
			-- slum yards: laundry strung between poles
			local cx, cz = zone.center[1], zone.center[2]
			local len = math.min(zone.size[1], 12)
			for _, s in ipairs({ -1, 1 }) do
				f:box("LaundryPole", Vector3.new(0.4, 9, 0.4), cx + s * len / 2, 4.5, cz, C.darkWood, M.Wood, NO)
			end
			f:box("Line", Vector3.new(len, 0.1, 0.1), cx, 8.6, cz, rgb(200, 190, 160), M.Fabric, NO)
			for k = -1, 1 do
				f:box("Laundry", Vector3.new(1.8, 2.4, 0.1), cx + k * 3, 7.3, cz, C.cloth[k + 2], M.Fabric, NO)
			end
		end
	end
	for index = 0, 11 do
		if index % 3 ~= 0 then
			local a = (index + 0.5) * math.pi / 6
			local g = Furniture.at(f, math.cos(a) * 44, 0.12, math.sin(a) * 44, math.deg(math.atan2(-math.cos(a), -math.sin(a))) + 180)
			if g ~= nil then
				Furniture.bench(g, 5)
			end
		end
	end
	cart(f, 30, 22, 30)
	cart(f, -36, -18, -60)
	-- gate yards: troughs and a cart
	for _, gate in ipairs(layout.gates) do
		if gate.kind == "Land" then
			local inward = if gate.center[2] > 0 then -1 else 1
			local tf = Furniture.at(f, gate.center[1] + 18, 0, gate.center[2] + inward * 22, 0)
			if tf ~= nil then
				tf:box("Trough", Vector3.new(6, 2, 2.4), 0, 1, 0, rgb(120, 90, 60), M.WoodPlanks)
				tf:box("TroughWater", Vector3.new(5.4, 0.1, 1.8), 0, 1.9, 0, rgb(60, 100, 120), M.Glass, NO)
			end
			cart(f, gate.center[1] - 20, gate.center[2] + inward * 24, 0)
		end
	end
	-- street name posts at the main junctions
	local posts = {
		{ x = 12, z = 60, name = "South Road" },
		{ x = 60, z = 12, name = "Harbour Road" },
		{ x = -60, z = -12, name = "West Road" },
		{ x = -12, z = -60, name = "Castle Road" },
		{ x = 300, z = -14, name = "North Gate Road" },
		{ x = -300, z = -14, name = "Noble Avenue" },
	}
	for _, post in ipairs(posts) do
		local pf = Kit.frame(folder, CFrame.new(post.x, 0, post.z))
		pf:box("Signpost", Vector3.new(0.5, 8, 0.5), 0, 4, 0, C.darkWood, M.Wood, NO)
		local board = pf:box("StreetSign", Vector3.new(5, 1.2, 0.3), 0, 7, 0, rgb(90, 64, 40), M.WoodPlanks, NO)
		Kit.sign(board, Enum.NormalId.Front, post.name)
		Kit.sign(board, Enum.NormalId.Back, post.name)
	end
end

-- Noble estates: a low wall round the garden with a gateway on the street side, hedges, trees and flower beds.
function Outdoors.estates(layout: any, root: Instance)
	local folder = Kit.folder(root, "Estates")
	for _, entry in ipairs(layout.blocks) do
		if entry.estate ~= nil then
			local cx, cz = entry.estate.center[1], entry.estate.center[2]
			local w, d = entry.estate.size[1], entry.estate.size[2]
			local f = Kit.frame(folder, CFrame.new(cx, 0, cz))
			local stone = rgb(200, 194, 180)
			local door = entry.door or "South"
			local houseX, houseZ = entry.center[1] - cx, entry.center[2] - cz
			-- the gate lines up with the house's door, which is off the facade's middle on a wide house
			local cf, W, D = Shell.frameOf(entry)
			local doorAt = cf:PointToWorldSpace(Vector3.new(Shell.doorX(W), 0, D / 2))
			local doorX, doorZ = doorAt.X - cx, doorAt.Z - cz
			for _, side in ipairs({ "North", "South", "West", "East" }) do
				local alongX = side == "North" or side == "South"
				local fixed = if side == "North" then -d / 2 elseif side == "South" then d / 2 elseif side == "West" then -w / 2 else w / 2
				local run = if alongX then w else d
				local openings = {}
				if side == door then
					local at = if alongX then doorX else doorZ
					table.insert(openings, { from = at - 4, to = at + 4, bottom = 0, top = 4 })
				end
				-- north and south walls run over the corners to the side walls' outer faces; the side walls stop
				-- against their inner faces
				local inset = if alongX then -0.6 else 0.6
				Kit.wall(f, "GardenWall", alongX, fixed, -run / 2 + inset, run / 2 - inset, 0, 3, 1.2, openings, stone, M.Limestone)
				if side == door then
					local at = if alongX then doorX else doorZ
					for _, s in ipairs({ -1, 1 }) do
						local gx, gz = if alongX then at + s * 4.6 else fixed, if alongX then fixed else at + s * 4.6
						f:box("GatePillar", Vector3.new(1.8, 5, 1.8), gx, 2.5, gz, stone, M.Limestone)
						f:box("GateFinial", Vector3.new(1, 1, 1), gx, 5.5, gz, C.lundandGold, M.Metal, NO)
					end
					-- the iron gate stands open
					local gx, gz = if alongX then at - 3.6 else fixed, if alongX then fixed else at - 3.6
					f:box("IronGate", if alongX then Vector3.new(0.2, 4, 3.5) else Vector3.new(3.5, 4, 0.2), gx, 2, gz + (if alongX then (if side == "South" then -1.85 else 1.85) else 0), C.iron, M.Metal, NO)
				end
			end
			-- hedges along the inside of the side walls, trees in the corners, a flower bed by the path
			for _, s in ipairs({ -1, 1 }) do
				f:box("Hedge", Vector3.new(2, 3, d - 10), s * (w / 2 - 2.4), 1.5, 0, rgb(60, 100, 50), M.Grass)
				for _, t in ipairs({ -1, 1 }) do
					local tx, tz = s * (w / 2 - 7), t * (d / 2 - 7)
					if math.abs(tx - houseX) > entry.size[1] / 2 + 4 or math.abs(tz - houseZ) > entry.size[2] / 2 + 4 then
						f:cyl("TreeTrunk", 8, 1.4, tx, 0, tz, rgb(100, 72, 48), M.Wood)
						f:box("TreeCrown", Vector3.new(7, 6, 7), tx, 10, tz, rgb(70, 120, 60), M.Grass, NO).Shape = Enum.PartType.Ball
					end
				end
			end
		end
	end
end

-- Lanterns, barrels and benches are enough outside; this keeps the public spaces in front of landmarks dressed.
function Outdoors.landmarkYards(layout: any, root: Instance)
	local folder = Kit.folder(root, "Yards")
	local f = WORLD:child(folder)
	for _, zone in ipairs(layout.ground) do
		if zone.id == "ChurchSteps" then
			for _, s in ipairs({ -1, 1 }) do
				local g = Furniture.at(f, zone.center[1] + s * 16, 0.06, zone.center[2] + 6, 0)
				if g ~= nil then
					Furniture.bench(g, 5)
				end
				f:cyl("YardTreeTrunk", 7, 1.2, zone.center[1] + s * 22, 0, zone.center[2] - 8, rgb(100, 72, 48), M.Wood)
				f:box("YardTreeCrown", Vector3.new(7, 7, 7), zone.center[1] + s * 22, 9.5, zone.center[2] - 8, rgb(70, 120, 60), M.Grass, NO).Shape = Enum.PartType.Ball
			end
		elseif zone.id == "CastleCourtyardGround" then
			for _, s in ipairs({ -1, 1 }) do
				local g = Furniture.at(f, zone.center[1] + s * 60, 0.1, zone.center[2], 0)
				if g ~= nil then
					Furniture.weaponRack(g)
				end
				lantern(folder, zone.center[1] + s * 20, zone.center[2] + 18)
			end
		end
	end
end

return Outdoors
