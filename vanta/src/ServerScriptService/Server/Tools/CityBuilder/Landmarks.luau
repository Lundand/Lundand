--!strict
-- Hand-shaped landmarks: the square's fountain with the Heart of Realms, the church (spawn and awakening), the
-- castle (keep with throne hall, Royal Library, curtain walls, towers, gatehouse) and the harbour fish market.
-- Each works in its block's frame, front (door side) towards +z, like Shell.
local Kit = require(script.Parent.Kit)
local Furniture = require(script.Parent.Furniture)
local Layout = require(game:GetService("ServerStorage"):WaitForChild("ServerData").CityLayout)
local LayoutRules = require(script.Parent.Parent.Parent.Domain.LayoutRules)

local Landmarks = {}
local C = Kit.colors
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }
local DOOR_YAW = { South = 0, North = 180, East = 90, West = -90 }

local function frameFor(entry: any, model: Model): (Frame, number, number)
	local door = entry.door or "South"
	local W, D = entry.size[1], entry.size[2]
	if door == "East" or door == "West" then
		W, D = entry.size[2], entry.size[1]
	end
	local yaw = (entry.yaw or 0) + DOOR_YAW[door]
	return Kit.frame(model, CFrame.new(entry.center[1], 0, entry.center[2]) * CFrame.Angles(0, math.rad(yaw), 0)), W, D
end

local function put(f: Frame, x: number, y: number, z: number, rot: number?, fn: (Frame) -> ())
	local g = Furniture.at(f, x, y, z, rot)
	if g ~= nil then
		fn(g)
	end
end

-- Pyramid cap from four wedges (tower spires, roofs of square towers)
local function spire(f: Frame, x: number, y: number, z: number, size: number, height: number, color: Color3, material: Enum.Material)
	for index = 0, 3 do
		local a = index * math.pi / 2
		local cf = CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, size / 4)
		f:wedgeAt("Spire", Vector3.new(size, height, size / 2), cf * CFrame.Angles(0, math.pi, 0), color, material, NO)
	end
end

-- Battlements along a run: merlons every 4 studs
-- (hidden, when given, says which merlons stand inside a tower: those are left out)
local function merlons(f: Frame, alongX: boolean, fixed: number, from: number, to: number, y: number, color: Color3, material: Enum.Material, hidden: ((Vector3) -> boolean)?)
	local count = math.floor((to - from) / 4)
	for index = 0, count - 1 do
		local a = from + 2 + index * 4 + 0.05
		local x, z = if alongX then a else fixed, if alongX then fixed else a
		if hidden == nil or not hidden(f.cframe:PointToWorldSpace(Vector3.new(x, y + 1.2, z))) then
			f:box("Merlon", if alongX then Vector3.new(1.86, 2.4, 1.3) else Vector3.new(1.3, 2.4, 1.86), x, y + 1.2, z, color, material)
		end
	end
end
Landmarks.merlons = merlons
Landmarks.spire = spire

-- A banner with House Lundand's crest hanging on a wall face (wall behind at -z of the placed frame)
local function lundandBanner(f: Frame, x: number, y: number, z: number, rot: number, scale: number?)
	put(f, x, y, z, rot, function(g)
		local s = scale or 1
		g:box("BannerCloth", Vector3.new(4 * s, 8 * s, 0.15), 0, 0, 0, C.lundandBlue, M.Fabric, NO)
		g:box("BannerTrim", Vector3.new(4.2 * s, 0.4 * s, 0.2), 0, 4 * s, 0, C.lundandGold, M.Metal, NO)
		local crest = Kit.frame(g.parent, g.cframe * CFrame.new(0, 0.5 * s, 0.15))
		Furniture.crest(crest, s)
	end)
end
Landmarks.banner = lundandBanner

--------------------------------------------------------------------------------------------------------------------
-- The central fountain: an octagonal basin, a carved pillar, and the Heart of Realms crystal above the water
--------------------------------------------------------------------------------------------------------------------
function Landmarks.fountain(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	local f = Kit.frame(model, CFrame.new(entry.center[1], 0, entry.center[2]))
	local stone = rgb(214, 208, 194)
	local r = entry.size[1] / 2
	for index = 0, 7 do
		local a = index * math.pi / 4
		local cf = CFrame.Angles(0, a, 0) * CFrame.new(0, 1.3, r - 0.9)
		local side = 2 * r * math.tan(math.pi / 8) + 0.2
		-- neighbouring segments differ a little in height, so the corners where they overlap never flicker
		local lift = (index % 2) * 0.12
		f:boxAt("Basin", Vector3.new(side, 2.6 + lift, 1.8), cf * CFrame.new(0, lift / 2, 0), stone, M.Marble)
		f:boxAt("BasinLip", Vector3.new(side + 0.4, 0.4, 2.4), cf * CFrame.new(0, 1.5 + lift, 0), rgb(226, 222, 210), M.Marble)
	end
	f:cyl("BasinFloor", 0.6, entry.size[1] - 2, 0, 0, 0, rgb(150, 160, 160), M.Slate)
	local water = f:cyl("Water", 0.2, entry.size[1] - 3, 0, 2, 0, rgb(80, 140, 170), M.Glass, { collide = false, query = false, transparency = 0.35, shadow = false })
	water.Name = "FountainWater"
	f:cyl("Pillar", 9, 3.6, 0, 0.6, 0, stone, M.Marble)
	f:cyl("PillarBand", 0.6, 4.4, 0, 3, 0, rgb(180, 170, 150), M.Marble, NO)
	f:cyl("UpperBowl", 1, 9, 0, 8.6, 0, stone, M.Marble)
	f:cyl("UpperWater", 0.2, 8, 0, 9.5, 0, rgb(80, 140, 170), M.Glass, { collide = false, query = false, transparency = 0.35 })
	-- four carved spouts
	for index = 0, 3 do
		local a = index * math.pi / 2
		f:boxAt("Spout", Vector3.new(0.8, 0.8, 2), CFrame.Angles(0, a, 0) * CFrame.new(0, 8.2, 2.4), rgb(170, 160, 140), M.Marble, NO)
	end
	f:cyl("CrystalSeat", 1.4, 3, 0, 9.6, 0, rgb(180, 170, 150), M.Marble)
	-- the Heart of Realms (L-27 lore): RiftService finds it by LocationId and lights it up during rift events
	local heart = f:boxAt("HeartOfRealms", Vector3.new(3.2, 7, 3.2), CFrame.new(0, 14.5, 0) * CFrame.Angles(0, math.rad(45), 0), rgb(150, 170, 230), M.Glass, { transparency = 0.15 })
	heart:SetAttribute("LocationId", "HeartOfRealms")
	Kit.light(heart, rgb(150, 170, 255), 18, 0.8)
	model:SetAttribute("LocationId", "HeartOfRealms")
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- The church: nave and aisles under a tall roof, a bell tower, the awakening circle set into the floor,
-- a sacristy and a side chapel with their own doors.
--------------------------------------------------------------------------------------------------------------------
function Landmarks.church(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	model:SetAttribute("LocationId", entry.locationId)
	model:SetAttribute("Access", "Public")
	local f, W, D = frameFor(entry, model)
	local stone = rgb(196, 194, 188)
	local darkStone = rgb(160, 158, 152)
	local roof = rgb(84, 90, 100)
	local T = 2
	local nave, aisleTop, naveTop = 12, 16, 30
	local hw, hd = W / 2, D / 2
	local glassColors = { rgb(180, 40, 50), rgb(40, 80, 170), rgb(200, 160, 40), rgb(60, 140, 80), rgb(120, 60, 150) }

	-- the plinth sits just inside the walls' outer faces, so no face is shared
	f:box("Plinth", Vector3.new(W - 0.4, 0.6, D - 0.4), 0, 0.3, 0, darkStone, M.Limestone)
	f:box("Floor", Vector3.new(W - 2 * T, 0.1, D - 2 * T), 0, 0.65, 0, rgb(176, 170, 160), M.Slate, NO)
	-- outer walls of the aisles, with tall stained windows
	for _, s in ipairs({ -1, 1 }) do
		local openings = {}
		for index = 0, 5 do
			local z = -hd + 10 + index * 10
			table.insert(openings, { from = z - 1.6, to = z + 1.6, bottom = 4, top = 13.5 })
		end
		if s == 1 then
			-- the sacristy's side door (clear of the first window)
			table.insert(openings, { from = -hd + 3, to = -hd + 7.5, bottom = 0, top = 9 })
		end
		Kit.wall(f, "AisleWall", false, s * (hw - T / 2), -hd + T, hd - T, 0, aisleTop, T, openings, stone, M.Limestone)
		for index = 0, 5 do
			local z = -hd + 10 + index * 10
			f:box("StainedGlass", Vector3.new(0.3, 9.5, 3.2), s * (hw - T / 2), 8.75, z, glassColors[index % #glassColors + 1], M.Glass, { transparency = 0.25, shadow = false })
		end
	end
	-- front and back walls (front: the great door; back: behind the altar)
	Kit.wall(f, "FrontWall", true, hd - T / 2, -hw, hw, 0, aisleTop, T, { { from = -5, to = 5, bottom = 0, top = 14 } }, stone, M.Limestone)
	Kit.wall(f, "BackWall", true, -hd + T / 2, -hw, hw, 0, aisleTop, T, {}, stone, M.Limestone)
	-- clerestory: nave walls above the aisle roofs, carried by pillars
	for _, s in ipairs({ -1, 1 }) do
		local openings = {}
		for index = 0, 5 do
			local z = -hd + 10 + index * 10
			table.insert(openings, { from = z - 1.4, to = z + 1.4, bottom = aisleTop + 3, top = naveTop - 3 })
		end
		Kit.wall(f, "Clerestory", false, s * (nave + 0.5), -hd + T, hd - T, aisleTop, naveTop, 1, openings, stone, M.Limestone)
		for index = 0, 5 do
			local z = -hd + 10 + index * 10
			f:box("ClerestoryGlass", Vector3.new(0.3, naveTop - aisleTop - 6, 2.8), s * (nave + 0.5), (aisleTop + naveTop) / 2, z, glassColors[(index + 2) % #glassColors + 1], M.Glass, { transparency = 0.25, shadow = false })
		end
		for index = 0, 6 do
			local z = -hd + 5 + index * 10
			f:cyl("Pillar", aisleTop, 2.2, s * (nave + 0.5), 0.6, z, rgb(210, 206, 198), M.Limestone)
		end
		-- aisle roof (lean-to) and its ceiling
		-- the aisle roof leans against the clerestory's outer face (nave + 1) and overhangs the aisle wall
		f:wedgeAt("AisleRoof", Vector3.new(D + 1, 4, hw - nave - 0.5), CFrame.new(s * ((nave + 1 + hw + 0.5) / 2), aisleTop + 2, 0) * CFrame.Angles(0, if s == 1 then -math.pi / 2 else math.pi / 2, 0), roof, M.Slate)
	end
	-- nave front and back gables (rose window at the front)
	for _, z in ipairs({ hd - T / 2, -hd + T / 2 }) do
		Kit.wall(f, "NaveGableWall", true, z, -nave - 1, nave + 1, aisleTop, naveTop, T, {}, stone, M.Limestone)
	end
	local rose = f:boxAt("RoseWindow", Vector3.new(0.4, 8, 8), CFrame.new(0, aisleTop + 7, hd + 0.1) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), rgb(150, 60, 120), M.Glass, { collide = false, query = false, transparency = 0.2 })
	rose.Shape = Enum.PartType.Cylinder
	local rise = 10
	f:wedgeAt("NaveRoof", Vector3.new(D + 2, rise, nave + 1.5), CFrame.new(-(nave + 1.5) / 2, naveTop + rise / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), roof, M.Slate)
	f:wedgeAt("NaveRoof", Vector3.new(D + 2, rise, nave + 1.5), CFrame.new((nave + 1.5) / 2, naveTop + rise / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0), roof, M.Slate)
	-- ceilings sit just under the wall tops
	f:box("NaveCeiling", Vector3.new(nave * 2 + 1, 0.6, D - 2 * T), 0, naveTop - 0.4, 0, rgb(120, 96, 70), M.WoodPlanks, NO)
	f:box("AisleCeiling", Vector3.new(hw - nave - 2, 0.6, D - 2 * T), -(nave + hw) / 2 - 0.5, aisleTop - 0.4, 0, rgb(120, 96, 70), M.WoodPlanks, NO)
	f:box("AisleCeiling", Vector3.new(hw - nave - 2, 0.6, D - 2 * T), (nave + hw) / 2 + 0.5, aisleTop - 0.4, 0, rgb(120, 96, 70), M.WoodPlanks, NO)
	-- bell tower at the front-left corner, rising well above the roofs
	local tx, tz, ts = -hw + 6, hd - 6, 12
	-- a little wider than its corner of the church, so its faces stand clear of the church walls
	f:box("Tower", Vector3.new(ts + 0.4, 52, ts + 0.4), tx - 0.2, 26, tz + 0.2, stone, M.Limestone)
	for _, s in ipairs({ -1, 1 }) do
		f:box("BelfryOpening", Vector3.new(0.3, 6, 4), tx - 0.2 + s * (ts / 2 + 0.3), 44, tz + 0.2, rgb(30, 30, 34), M.SmoothPlastic, NO)
	end
	f:box("BelfryOpening", Vector3.new(4, 6, 0.3), tx - 0.2, 44, tz + 0.2 + ts / 2 + 0.3, rgb(30, 30, 34), M.SmoothPlastic, NO)
	spire(f, tx - 0.2, 52, tz + 0.2, ts + 1, 18, roof, M.Slate)
	f:box("SpireCross", Vector3.new(0.6, 4, 0.6), tx - 0.2, 72, tz + 0.2, C.lundandGold, M.Metal, NO)
	f:box("SpireCross", Vector3.new(2.4, 0.5, 0.5), tx - 0.2, 72.6, tz + 0.2, C.lundandGold, M.Metal, NO)
	-- great doors standing open
	for _, s in ipairs({ -1, 1 }) do
		f:box("GreatDoor", Vector3.new(0.4, 13.6, 4.8), s * 5.2, 7.4, hd - T - 2.4, rgb(80, 54, 34), M.WoodPlanks, NO)
	end
	-- interior: altar dais, altar, pews, candles, the awakening circle
	f:box("AltarDais", Vector3.new(nave * 2 - 2, 1.2, 9), 0, 1.2, -hd + T + 4.5, rgb(200, 196, 186), M.Marble)
	f:box("Altar", Vector3.new(7, 3.4, 3), 0, 3.5, -hd + T + 3, rgb(232, 228, 218), M.Marble)
	f:box("AltarCloth", Vector3.new(7.2, 0.2, 3.2), 0, 5.3, -hd + T + 3, rgb(240, 236, 220), M.Fabric, NO)
	for _, s in ipairs({ -1, 1 }) do
		local candle = f:box("Candle", Vector3.new(0.5, 1.6, 0.5), s * 2.6, 6.2, -hd + T + 3, rgb(255, 220, 160), M.Neon, NO)
		candle.CastShadow = false
		Kit.light(candle, rgb(255, 210, 150), 18, 1)
	end
	for row = 0, 5 do
		local z = 14 + row * 3
		for _, s in ipairs({ -1, 1 }) do
			put(f, s * 6.5, 0.6, z, 0, function(g)
				Furniture.pew(g, 8)
			end)
		end
	end
	-- the awakening circle (L-43): summoned Adventurers appear here
	local cz = entry.circleZ or 4
	f:cyl("CircleStone", 0.12, 18, 0, 0.62, cz, rgb(120, 116, 130), M.Slate, NO)
	f:cyl("CircleInner", 0.14, 14, 0, 0.64, cz, rgb(150, 146, 160), M.Marble, NO)
	for index = 0, 11 do
		local a = index * math.pi / 6
		local rune = f:boxAt("Rune", Vector3.new(1.4, 0.1, 0.5), CFrame.new(math.cos(a) * 8, 0.8, cz + math.sin(a) * 8) * CFrame.Angles(0, -a, 0), rgb(160, 140, 255), M.Neon, NO)
		rune.CastShadow = false
		rune.Transparency = 0.3
	end
	-- auxiliary rooms behind the aisles: the sacristy (right, with its own door) and a side chapel (left)
	for _, s in ipairs({ -1, 1 }) do
		Kit.wall(f, "ChapelWall", true, -hd + 13, s * (nave + 1.6), s * (hw - T), 0, aisleTop - 0.6, 0.8, { { from = s * (nave + 1.6) + (if s == 1 then 1 else -5), to = s * (nave + 1.6) + (if s == 1 then 5 else -1), bottom = 0, top = 8.4 } }, stone, M.Limestone)
	end
	for index = 0, 3 do
		local z = -hd + 12 + index * 16
		local lamp = f:box("HangingLamp", Vector3.new(1.4, 1.4, 1.4), 0, naveTop - 8, z, rgb(255, 214, 150), M.Neon, NO)
		lamp.CastShadow = false
		f:box("LampChain", Vector3.new(0.15, 7.4, 0.15), 0, naveTop - 4, z, C.iron, M.Metal, NO)
		Kit.light(lamp, rgb(255, 210, 150), 34, 1.2)
	end
	lundandBanner(f, -nave + 1, 9, -hd + T + 0.2, 0)
	lundandBanner(f, nave - 1, 9, -hd + T + 0.2, 0)
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- The keep of House Lundand: entrance hall, double-height throne hall, guard room and administrative chamber,
-- grand stairs to the upper floor (council chamber, royal apartments) wrapping round the hall.
--------------------------------------------------------------------------------------------------------------------
local function stoneHall(f: Frame, W: number, D: number, height: number, stone: Color3, frontOpenings: {Kit.Opening}, windowsY: {number}, battlements: boolean)
	local T = 2
	local hw, hd = W / 2, D / 2
	local function windows(run: number): {Kit.Opening}
		local list = {}
		local count = math.max(1, math.floor(run / 10))
		for _, y in ipairs(windowsY) do
			for index = 1, count do
				local a = -run / 2 + run * (index - 0.5) / count
				table.insert(list, { from = a - 1.4, to = a + 1.4, bottom = y, top = y + 6 })
			end
		end
		return list
	end
	local front = windows(W)
	local kept = {}
	for _, w in ipairs(front) do
		local blocked = false
		for _, o in ipairs(frontOpenings) do
			if w.to > o.from - 1 and w.from < o.to + 1 then
				blocked = true
			end
		end
		if not blocked then
			table.insert(kept, w)
		end
	end
	for _, o in ipairs(frontOpenings) do
		table.insert(kept, o)
	end
	-- windows stack in columns (one above the other), so the walls are cut as facades
	Kit.facade(f, "FrontWall", true, hd - T / 2, -hw, hw, 0, height, T, kept, stone, M.Limestone)
	Kit.facade(f, "BackWall", true, -hd + T / 2, -hw, hw, 0, height, T, windows(W), stone, M.Limestone)
	for _, s in ipairs({ -1, 1 }) do
		Kit.facade(f, "SideWall", false, s * (hw - T / 2), -hd + T, hd - T, 0, height, T, windows(D - 2 * T), stone, M.Limestone)
	end
	for _, y in ipairs(windowsY) do
		-- glass in every window at this height (one pane per wall run keeps the part count low)
		f:box("WindowGlass", Vector3.new(W - 0.2, 6, 0.2), 0, y + 3, hd - T / 2, C.glass, M.Glass, { collide = false, query = false, transparency = 0.6, shadow = false })
		f:box("WindowGlass", Vector3.new(W - 0.2, 6, 0.2), 0, y + 3, -hd + T / 2, C.glass, M.Glass, { collide = false, query = false, transparency = 0.6, shadow = false })
	end
	if battlements then
		merlons(f, true, hd - 0.7, -hw, hw, height, stone, M.Limestone)
		merlons(f, true, -hd + 0.7, -hw, hw, height, stone, M.Limestone)
		merlons(f, false, -hw + 0.7, -hd + 1.4, hd - 1.4, height, stone, M.Limestone)
		merlons(f, false, hw - 0.7, -hd + 1.4, hd - 1.4, height, stone, M.Limestone)
	end
	f:box("Plinth", Vector3.new(W - 0.4, 0.6, D - 0.4), 0, 0.3, 0, rgb(150, 146, 138), M.Limestone)
end

function Landmarks.keep(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	model:SetAttribute("LocationId", entry.locationId)
	model:SetAttribute("Access", "Royal")
	local f, W, D = frameFor(entry, model)
	local stone = rgb(178, 174, 166)
	local hw, hd = W / 2, D / 2
	local T = 2
	local UP = 24 -- the upper floor (the throne hall is double height)
	local wallTop = 44
	stoneHall(f, W, D, wallTop, stone, { { from = -4, to = 4, bottom = 0, top = 12 } }, { 4, UP + 4 }, true)
	f:box("Floor", Vector3.new(W - 2 * T, 0.1, D - 2 * T), 0, 0.65, 0, rgb(150, 146, 138), M.Slate, NO)
	-- inner walls: the throne hall between x = -18 and 18, behind the entrance hall (z < 12)
	local hallX, hallFront = 18, 12
	for _, s in ipairs({ -1, 1 }) do
		Kit.wall(f, "HallWall", false, s * hallX, -hd + T, hallFront - 0.6, 0.6, UP - 1, 1.2, { { from = hallFront - 10, to = hallFront - 5, bottom = 0.6, top = 9 }, { from = -10, to = -5, bottom = 0.6, top = 9 } }, stone, M.Limestone)
	end
	Kit.wall(f, "HallFront", true, hallFront, -hallX, hallX, 0.6, UP - 1, 1.2, { { from = -5, to = 5, bottom = 0.6, top = 14 } }, stone, M.Limestone)
	-- the grand stairs run the length of the left wing against its outer wall
	local stairX0, stairX1 = -hw + T, -hw + T + 5
	-- side rooms: guard room (left front), administrative chamber (right front), stores (both back); the left
	-- wing's dividing wall stops at the stairs
	for _, s in ipairs({ -1, 1 }) do
		local outer = if s == 1 then hw - T else stairX1
		local inner = s * (hallX + 0.6)
		Kit.wall(f, "RoomWall", true, -6, math.min(inner, outer), math.max(inner, outer), 0.6, UP - 1, 1, { { from = s * (hallX + 0.6) + (if s == 1 then 3 else -7), to = s * (hallX + 0.6) + (if s == 1 then 7 else -3), bottom = 0.6, top = 9 } }, stone, M.Limestone)
	end
	-- upper floor slab over the side wings and the entrance hall, with the stairwell hole on the left
	local zLow, zHigh = hd - T - 3, -hd + T + 3
	local run = zHigh - zLow
	local cut = zLow + run * 0.25
	Kit.slab(f, "UpperFloor", { x0 = -hw + T, x1 = -hallX, z0 = -hd + T, z1 = hd - T }, UP, 1, { x0 = stairX0, x1 = stairX1, z0 = zHigh, z1 = cut }, rgb(120, 92, 64), M.WoodPlanks)
	Kit.slab(f, "UpperFloor", { x0 = hallX, x1 = hw - T, z0 = -hd + T, z1 = hd - T }, UP, 1, nil, rgb(120, 92, 64), M.WoodPlanks)
	Kit.slab(f, "UpperFloor", { x0 = -hallX, x1 = hallX, z0 = hallFront, z1 = hd - T }, UP, 1, nil, rgb(120, 92, 64), M.WoodPlanks)
	Kit.flight(f, "GrandStairs", stairX0 + 0.1, stairX1 - 0.1, zLow, zHigh, 0.6, UP, rgb(170, 150, 120), C.darkWood)
	f:box("StairRail", Vector3.new(0.3, 3.2, cut - zHigh), stairX1, UP + 1.6, (cut + zHigh) / 2, C.darkWood, M.Wood)
	-- gallery rail over the throne hall
	for _, s in ipairs({ -1, 1 }) do
		f:box("GalleryRail", Vector3.new(0.4, 3.4, hallFront + hd - T - 0.4), s * hallX, UP + 1.7, (hallFront - 0.4 - hd + T) / 2, C.darkWood, M.Wood)
	end
	f:box("GalleryRail", Vector3.new(hallX * 2, 3.4, 0.4), 0, UP + 1.7, hallFront, C.darkWood, M.Wood)
	-- the upper floor's rooms: council chamber (left), royal apartments (right), divided along z = -4
	for _, s in ipairs({ -1, 1 }) do
		Kit.wall(f, "UpperRoomWall", true, -4, math.min(s * (hallX + 0.4), s * (hw - T)), math.max(s * (hallX + 0.4), s * (hw - T)), UP, wallTop - 10.6, 1, { { from = s * (hallX + 0.4) + (if s == 1 then 3 else -7), to = s * (hallX + 0.4) + (if s == 1 then 7 else -3), bottom = UP, top = UP + 8.4 } }, stone, M.Limestone)
	end
	-- roof over the walls (flat leads behind the battlements) and the hall ceiling
	-- the flat roof sits a little below the wall tops, inside them
	f:box("Roof", Vector3.new(W - 2, 1, D - 2), 0, wallTop - 0.6, 0, rgb(90, 96, 110), M.Slate)
	f:box("Ceiling", Vector3.new(W - 2 * T, 0.6, D - 2 * T), 0, wallTop - 10.3, 0, rgb(100, 76, 54), M.WoodPlanks, NO)
	-- corner turrets with pointed roofs
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			f:box("Turret", Vector3.new(9, wallTop + 10, 9), sx * (hw - 2), (wallTop + 10) / 2, sz * (hd - 2), stone, M.Limestone)
			spire(f, sx * (hw - 2), wallTop + 10, sz * (hd - 2), 10, 12, rgb(66, 74, 92), M.Slate)
		end
	end
	-- throne hall: dais and throne at the back, carpet, pillars, banners, chandeliers
	put(f, 0, 0.6, -hd + T + 6, 0, function(g)
		Furniture.throne(g)
	end)
	f:box("Carpet", Vector3.new(6, 0.1, hallFront + hd - T - 12), 0, 0.72, (hallFront - hd + T + 12) / 2, rgb(140, 30, 36), M.Fabric, NO)
	for index = 0, 3 do
		local z = -hd + T + 12 + index * 9
		for _, s in ipairs({ -1, 1 }) do
			f:cyl("HallPillar", UP + 8, 2.4, s * (hallX - 4), 0.6, z, rgb(200, 196, 188), M.Limestone)
			if index % 2 == 0 then
				lundandBanner(f, s * (hallX - 0.8), 14, z + 4.5, s * -90)
			end
		end
		local chandelier = f:box("Chandelier", Vector3.new(4, 0.8, 4), 0, UP + 6, z, C.lundandGold, M.Metal, NO)
		Kit.light(chandelier, rgb(255, 210, 150), 30, 1)
	end
	lundandBanner(f, 0, 14, -hd + T + 0.2, 0, 1.4)
	-- the royal apartments are closed to visitors until the story opens them
	model:SetAttribute("RestrictedUpperFloor", true)
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- The Royal Library: a two-storey reading hall with tall bookcases, reading tables, a gallery on three sides
-- with more shelves, a scholar's desk and lecterns. Stairs on both sides lead up to the gallery.
--------------------------------------------------------------------------------------------------------------------
function Landmarks.library(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	model:SetAttribute("LocationId", entry.locationId)
	model:SetAttribute("Access", entry.access or "Royal")
	local f, W, D = frameFor(entry, model)
	local stone = rgb(180, 176, 168)
	local hw, hd = W / 2, D / 2
	local T = 2
	local GALLERY = 13
	local wallTop = 28
	stoneHall(f, W, D, wallTop, stone, { { from = -3.5, to = 3.5, bottom = 0, top = 11 } }, { 4, GALLERY + 4 }, false)
	f:box("Floor", Vector3.new(W - 2 * T, 0.1, D - 2 * T), 0, 0.65, 0, rgb(120, 92, 64), M.WoodPlanks, NO)
	-- pitched roof over the hall
	local rise = 9
	f:wedgeAt("Roof", Vector3.new(W + 1, rise, hd + 0.5), CFrame.new(0, wallTop + rise / 2, (hd + 0.5) / 2) * CFrame.Angles(0, math.pi, 0), rgb(66, 74, 92), M.Slate)
	f:wedgeAt("Roof", Vector3.new(W + 1, rise, hd + 0.5), CFrame.new(0, wallTop + rise / 2, -(hd + 0.5) / 2), rgb(66, 74, 92), M.Slate)
	f:box("Ceiling", Vector3.new(W - 2 * T, 0.6, D - 2 * T), 0, wallTop - 0.3, 0, rgb(100, 76, 54), M.WoodPlanks, NO)
	-- gallery: a walkway 6 studs deep along the back and both sides
	local g0 = 6
	f:box("Gallery", Vector3.new(W - 2 * T, 1, g0), 0, GALLERY - 0.5, -hd + T + g0 / 2, rgb(110, 84, 58), M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		-- side galleries, leaving room at the front for the stair arrivals
		local zFrom, zTo = -hd + T + g0, hd - T - 18
		f:box("Gallery", Vector3.new(g0, 1, zTo - zFrom), s * (hw - T - g0 / 2), GALLERY - 0.5, (zFrom + zTo) / 2, rgb(110, 84, 58), M.WoodPlanks)
		f:box("GalleryRail", Vector3.new(0.3, 3.2, zTo - (-hd + T + g0) - 0.3), s * (hw - T - g0), GALLERY + 1.6, (zTo + (-hd + T + g0) + 0.3) / 2, C.darkWood, M.Wood)
		-- a stair up each side, rising from the front towards the gallery
		local x0, x1 = s * (hw - T) - (if s == 1 then 4.5 else 0), s * (hw - T) + (if s == 1 then 0 else 4.5)
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		f:box("StairLanding", Vector3.new(hi - lo, 1, 3), (lo + hi) / 2, GALLERY - 0.5, zTo + 1.5, rgb(110, 84, 58), M.WoodPlanks)
		Kit.flight(f, "GalleryStairs", lo + 0.1, hi - 0.1, hd - T - 1, zTo + 3, 0.6, GALLERY, rgb(150, 120, 90), C.darkWood)
	end
	f:box("GalleryRail", Vector3.new(W - 2 * T - 2 * g0, 3.2, 0.3), 0, GALLERY + 1.6, -hd + T + g0, C.darkWood, M.Wood)
	-- bookcases: tall ones on the ground floor walls and in rows across the hall, more along the gallery
	for _, s in ipairs({ -1, 1 }) do
		for index = 0, 2 do
			if -hd + T + 8 + index * 6.5 < hd - T - 21 then
				put(f, s * (hw - T - 0.8), 0.6, -hd + T + 8 + index * 6.5, s * -90, function(g)
					Furniture.bookshelf(g, 5.6)
				end)
			end
			if -hd + T + 8 + index * 6.5 < hd - T - 21 then
				put(f, s * (hw - T - 0.8), GALLERY, -hd + T + 8 + index * 6.5, s * -90, function(g)
					Furniture.bookshelf(g, 5.6)
				end)
			end
		end
	end
	for index = 0, 4 do
		local x = -hw + T + 4 + index * ((W - 2 * T - 8) / 4)
		put(f, x, 0.6, -hd + T + 0.8, 0, function(g)
			Furniture.bookshelf(g, 5)
		end)
		put(f, x, GALLERY, -hd + T + 0.8, 0, function(g)
			Furniture.bookshelf(g, 5)
		end)
	end
	-- free-standing stacks in two rows, with reading tables between them and the door
	for _, s in ipairs({ -1, 1 }) do
		for row = 0, 1 do
			put(f, s * 7, 0.6, -hd + T + 11 + row * 5, 0, function(g)
				Furniture.bookshelf(g, 7)
			end)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		put(f, s * 5, 0.6, hd - T - 8, 0, function(g)
			Furniture.longTable(g, 7)
		end)
		local lamp = f:box("ReadingLamp", Vector3.new(0.6, 0.8, 0.6), s * 5, 3.5, hd - T - 8, rgb(255, 214, 150), M.Neon, NO)
		Kit.light(lamp, rgb(255, 210, 150), 16, 0.9)
	end
	put(f, 0, 0.6, -hd + T + 6, 180, function(g)
		Furniture.desk(g)
	end)
	put(f, 0, GALLERY, -hd + T + 3.5, 0, function(g)
		Furniture.desk(g)
	end)
	put(f, 0, 0.7, 0, 0, function(g)
		Furniture.rug(g, 10, 14, rgb(90, 30, 40))
	end)
	for index = 0, 1 do
		local chandelier = f:box("Chandelier", Vector3.new(3.4, 0.8, 3.4), 0, wallTop - 6, -4 + index * 10, C.lundandGold, M.Metal, NO)
		Kit.light(chandelier, rgb(255, 214, 160), 30, 1.1)
	end
	lundandBanner(f, 0, GALLERY + 7, -hd + T + 0.2, 0, 1.2)
	return model
end

--------------------------------------------------------------------------------------------------------------------
-- Castle fortifications and other solid landmarks
--------------------------------------------------------------------------------------------------------------------
function Landmarks.castleWall(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	local x, z = entry.center[1], entry.center[2]
	local w, d, h = entry.size[1], entry.size[2], entry.height
	local f = Kit.frame(model, CFrame.new(x, 0, z))
	local stone = rgb(160, 156, 148)
	f:box("CurtainWall", Vector3.new(w, h, d), 0, h / 2, 0, stone, M.Limestone)
	-- the castle's towers stand over the wall's ends; no merlons inside them
	local function inTower(point: Vector3): boolean
		for _, other in ipairs(Layout.blocks) do
			if other.kind == "Tower" and LayoutRules.contains(other, { point.X, point.Z }) then
				return true
			end
		end
		return false
	end
	if w > d then
		merlons(f, true, -d / 2 + 0.7, -w / 2, w / 2, h, stone, M.Limestone, inTower)
		merlons(f, true, d / 2 - 0.7, -w / 2, w / 2, h, stone, M.Limestone, inTower)
	else
		merlons(f, false, -w / 2 + 0.7, -d / 2, d / 2, h, stone, M.Limestone, inTower)
		merlons(f, false, w / 2 - 0.7, -d / 2, d / 2, h, stone, M.Limestone, inTower)
	end
	return model
end

function Landmarks.tower(entry: any, parent: Instance, roofed: boolean?): Model
	local model = Kit.model(parent, entry.id)
	local x, z = entry.center[1], entry.center[2]
	local s, h = entry.size[1], entry.height
	local f = Kit.frame(model, CFrame.new(x, 0, z))
	local stone = rgb(150, 146, 138)
	f:box("Tower", Vector3.new(s, h, s), 0, h / 2, 0, stone, M.Limestone)
	if roofed then
		spire(f, 0, h, 0, s + 1.4, s * 0.9, rgb(66, 74, 92), M.Slate)
	else
		merlons(f, true, -s / 2 + 0.7, -s / 2, s / 2, h, stone, M.Limestone)
		merlons(f, true, s / 2 - 0.7, -s / 2, s / 2, h, stone, M.Limestone)
		merlons(f, false, -s / 2 + 0.7, -s / 2 + 1.4, s / 2 - 1.4, h, stone, M.Limestone)
		merlons(f, false, s / 2 - 0.7, -s / 2 + 1.4, s / 2 - 1.4, h, stone, M.Limestone)
	end
	return model
end

-- Gatehouse: two piers with an arch over a passage along z, a raised portcullis and open gate leaves.
function Landmarks.gatehouse(parent: Instance, name: string, cf: CFrame, passage: number, depth: number, height: number, stone: Color3, crest: boolean): Model
	local model = Kit.model(parent, name)
	local f = Kit.frame(model, cf)
	local pier = 8
	for _, s in ipairs({ -1, 1 }) do
		f:box("GatePier", Vector3.new(pier, height, depth), s * (passage / 2 + pier / 2), height / 2, 0, stone, M.Limestone)
		merlons(f, true, -depth / 2 + 0.7, s * passage / 2, s * (passage / 2 + pier), height, stone, M.Limestone)
		-- open gate leaves against the passage walls
		f:box("GateLeaf", Vector3.new(0.6, 15, passage / 2 - 0.5), s * (passage / 2 - 0.4), 7.5, depth / 2 - passage / 4, rgb(76, 52, 32), M.WoodPlanks, NO)
	end
	local archBottom = 16
	f:box("GateArch", Vector3.new(passage, height - archBottom, depth), 0, (height + archBottom) / 2, 0, stone, M.Limestone)
	merlons(f, true, -depth / 2 + 0.7, -passage / 2, passage / 2, height, stone, M.Limestone)
	merlons(f, true, depth / 2 - 0.7, -passage / 2, passage / 2, height, stone, M.Limestone)
	-- the portcullis, raised into the arch: its lower bars still show
	for index = 0, math.floor(passage / 2.5) do
		f:box("PortcullisBar", Vector3.new(0.3, 4, 0.3), -passage / 2 + 0.8 + index * 2.5, archBottom + 1, 0, C.iron, M.Metal, NO)
	end
	f:box("PortcullisRail", Vector3.new(passage, 0.4, 0.4), 0, archBottom - 0.6, 0, C.iron, M.Metal, NO)
	if crest then
		for _, side in ipairs({ -1, 1 }) do
			local g = Kit.frame(model, cf * CFrame.new(0, archBottom + 6, side * (depth / 2 + 0.2)) * CFrame.Angles(0, if side == 1 then 0 else math.pi, 0))
			Furniture.crest(g, 1.6)
		end
	end
	return model
end

function Landmarks.castleGatehouse(entry: any, parent: Instance): Model
	local model = Landmarks.gatehouse(parent, entry.id, CFrame.new(entry.center[1], 0, entry.center[2]), 12, entry.size[2], entry.height, rgb(160, 156, 148), true)
	return model
end

-- The fish market: an open hall of posts under a broad roof, with stalls and baskets of the day's catch.
function Landmarks.fishMarket(entry: any, parent: Instance): Model
	local model = Kit.model(parent, entry.id)
	model:SetAttribute("LocationId", entry.locationId)
	model:SetAttribute("Access", "Public")
	local f, W, D = frameFor(entry, model)
	local timber = rgb(82, 66, 50)
	f:box("Floor", Vector3.new(W, 0.6, D), 0, 0.3, 0, rgb(130, 128, 122), M.Slate)
	for ix = 0, 3 do
		for iz = 0, 3 do
			if ix == 0 or ix == 3 or iz == 0 or iz == 3 then
				f:box("Post", Vector3.new(1.2, 11, 1.2), -W / 2 + 1 + ix * (W - 2) / 3, 6, -D / 2 + 1 + iz * (D - 2) / 3, timber, M.Wood)
			end
		end
	end
	local rise = 7
	f:wedgeAt("Roof", Vector3.new(W + 2, rise, D / 2 + 1.5), CFrame.new(0, 11.5 + rise / 2, (D / 2 + 1.5) / 2) * CFrame.Angles(0, math.pi, 0), rgb(96, 96, 98), M.RoofShingles)
	f:wedgeAt("Roof", Vector3.new(W + 2, rise, D / 2 + 1.5), CFrame.new(0, 11.5 + rise / 2, -(D / 2 + 1.5) / 2), rgb(96, 96, 98), M.RoofShingles)
	for row = -1, 1, 2 do
		for index = -1, 1 do
			put(f, index * 10, 0.6, row * 7, if row == 1 then 180 else 0, function(g)
				Furniture.counter(g, 7, rgb(120, 100, 76))
				for k = -1, 1 do
					g:box("Fish", Vector3.new(1.6, 0.4, 0.6), k * 2, 3.8, 0, rgb(160, 172, 180), M.SmoothPlastic, NO)
				end
			end)
		end
	end
	put(f, W / 2 - 3, 0.6, 0, -90, function(g)
		Furniture.barrel(g)
	end)
	local sign = f:box("Sign", Vector3.new(10, 2, 0.3), 0, 13.6, D / 2 + 1.6, rgb(90, 64, 40), M.WoodPlanks, NO)
	Kit.sign(sign, Enum.NormalId.Front, entry.name or "Fish Market")
	return model
end

return Landmarks
