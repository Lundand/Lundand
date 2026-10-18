--!strict
-- Layout of the capital, its forest and the hideout beneath the slums (L-27). Studs on the X/Z plane; north is -Z,
-- the forest lies beyond the south gate (+Z), the harbour opens to the sea in the east (+X).
--
-- Landmarks (church, guild, castle, harbour, gates...) are placed by hand below. The dense streets are generated
-- from district street grids: every street block gets a ring of attached buildings around a shared courtyard,
-- and any lot that would touch a road, a landmark or a reserved yard is dropped. Generation is deterministic
-- (its own seeded generator, not Random), so Studio, the server and the offline checks see the same city.
--
-- Built by Server.Tools.CityBuilder; checked offline by Server.Domain.LayoutRules (no overlaps, inside the walls,
-- gates on the wall, every door reachable from the gates, houses that match their house model, every location and
-- property placed once).
-- Entries keep the greybox fields (id, center, size, height, door, locationId, propertyId) and add:
--   yaw      rotation in degrees (the footprint is size = local width x depth, turned about its centre)
--   use      what the building is (Townhouse, Shop, Inn, Mansion, Warehouse, ...)
--   stories  floors above ground (each FLOOR_HEIGHT studs)
--   style    exterior palette (Market, Residential, Noble, Slum, Harbor, Craft, Royal)
--   access   Public, Npc (an NPC's home or business), Sale (a player property), Guild, Royal, Quest
--   open     sides that face a street or yard
--   template the house model an ordinary house is built from (TEMPLATES); its interior is instanced. Entries
--            without one are built in place: public buildings with a ground-floor room you walk into, the rest
--            (storefronts, warehouses, offices) as closed shells whose door leads to a room sized to the building
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)
local LayoutRules = require(game:GetService("ServerScriptService"):WaitForChild("Server").Domain.LayoutRules)

local FLOOR_HEIGHT = 12
local ROOF_ALLOWANCE = 9

--------------------------------------------------------------------------------------------------------------------
-- Deterministic generator (Park-Miller): the same numbers in Studio, on servers and offline.
--------------------------------------------------------------------------------------------------------------------
local seedState = 20261018
local function nextUnit(): number
	seedState = (seedState * 48271) % 2147483647
	return seedState / 2147483647
end
local function integer(min: number, max: number): number
	return math.min(max, min + math.floor(nextUnit() * (max - min + 1)))
end
local function chance(p: number): boolean
	return nextUnit() < p
end
local function pick(list: {any}): any
	return list[integer(1, #list)]
end

--------------------------------------------------------------------------------------------------------------------
-- Footprint geometry (oriented rectangles, separating axis test)
--------------------------------------------------------------------------------------------------------------------
local function corners(entry: any): {{number}}
	local x, z = entry.center[1], entry.center[2]
	local hw, hd = entry.size[1] / 2, entry.size[2] / 2
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	local out = {}
	for _, offset in ipairs({ { -hw, -hd }, { hw, -hd }, { hw, hd }, { -hw, hd } }) do
		-- CFrame.Angles(0, yaw, 0): local (x, z) -> world (x cos + z sin, -x sin + z cos)
		table.insert(out, { x + offset[1] * c + offset[2] * s, z - offset[1] * s + offset[2] * c })
	end
	return out
end

local function overlaps(a: any, b: any, margin: number?): boolean
	local ca, cb = corners(a), corners(b)
	local pad = margin or 0
	for _, poly in ipairs({ ca, cb }) do
		for index = 1, 4 do
			local p1, p2 = poly[index], poly[index % 4 + 1]
			local ax, az = p2[2] - p1[2], p1[1] - p2[1]
			local length = math.sqrt(ax * ax + az * az)
			ax, az = ax / length, az / length
			local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(ca) do
				local d = p[1] * ax + p[2] * az
				minA, maxA = math.min(minA, d), math.max(maxA, d)
			end
			for _, p in ipairs(cb) do
				local d = p[1] * ax + p[2] * az
				minB, maxB = math.min(minB, d), math.max(maxB, d)
			end
			if maxA + pad <= minB or maxB + pad <= minA then
				return false
			end
		end
	end
	return true
end

local function rect(x0: number, x1: number, z0: number, z1: number): any
	return { center = { (x0 + x1) / 2, (z0 + z1) / 2 }, size = { x1 - x0, z1 - z0 } }
end

--------------------------------------------------------------------------------------------------------------------
-- The plan
--------------------------------------------------------------------------------------------------------------------
local BOUNDS = { minX = -480, maxX = 480, minZ = -520, maxZ = 320 }
local WALL_THICKNESS = 8

-- House models (templates): a few per district, reused for every lot. CityBuilder keeps one copy of each in
-- ServerStorage.CityAssets.Houses (outside) and ServerStorage.CityAssets.Interiors (the room you enter), so they can
-- be remodelled in Studio and every house built from them follows. w is the facade, d the depth (studs); style is
-- the district look it is built in (window sizes, roof pitch, timber framing, chimney).
local TEMPLATES: {[string]: any} = {
	MarketA = { id = "MarketA", w = 22, d = 24, stories = 3, roof = "Eaves", style = "Market" },
	MarketB = { id = "MarketB", w = 26, d = 24, stories = 3, roof = "Gable", style = "Market" },
	MarketC = { id = "MarketC", w = 30, d = 26, stories = 3, roof = "Eaves", style = "Market" },
	RingHouse = { id = "RingHouse", w = 20, d = 22, stories = 3, roof = "Gable", style = "Market" },
	TownA = { id = "TownA", w = 22, d = 22, stories = 2, roof = "Eaves", style = "Residential" },
	TownB = { id = "TownB", w = 24, d = 22, stories = 3, roof = "Gable", style = "Residential" },
	TownC = { id = "TownC", w = 28, d = 24, stories = 2, roof = "Eaves", style = "Residential" },
	CraftA = { id = "CraftA", w = 24, d = 24, stories = 2, roof = "Eaves", style = "Craft" },
	CraftB = { id = "CraftB", w = 30, d = 26, stories = 2, roof = "Gable", style = "Craft" },
	HarborA = { id = "HarborA", w = 22, d = 22, stories = 2, roof = "Gable", style = "Harbor" },
	HarborB = { id = "HarborB", w = 28, d = 24, stories = 3, roof = "Eaves", style = "Harbor" },
	SlumA = { id = "SlumA", w = 16, d = 18, stories = 1, roof = "Eaves", style = "Slum" },
	SlumB = { id = "SlumB", w = 18, d = 18, stories = 2, roof = "Gable", style = "Slum" },
	Mansion = { id = "Mansion", w = 40, d = 30, stories = 3, roof = "Eaves", style = "Noble" },
	Manor = { id = "Manor", w = 34, d = 28, stories = 2, roof = "Eaves", style = "Noble" },
}

local blocks = {}
local roads = {}
local ground = {}
local reserved = {} -- footprints new lots must keep clear of (roads, yards, water, landmarks)
local props = {}

local function reserve(entry: any)
	table.insert(reserved, entry)
end

local function clear(entry: any, margin: number?): boolean
	for _, other in ipairs(reserved) do
		if overlaps(entry, other, margin) then
			return false
		end
	end
	return true
end

local function block(id: string, x: number, z: number, width: number, depth: number, stories: number, fields: any): any
	local entry: any = { id = id, center = { x, z }, size = { width, depth }, stories = stories, height = stories * FLOOR_HEIGHT + ROOF_ALLOWANCE, seed = integer(1, 999999) }
	for key, value in pairs(fields) do
		entry[key] = value
	end
	table.insert(blocks, entry)
	reserve(entry)
	return entry
end

local function road(id: string, x0: number, x1: number, z0: number, z1: number, fields: any?): any
	local entry: any = rect(x0, x1, z0, z1)
	entry.id = id
	for key, value in pairs(fields or {}) do
		entry[key] = value
	end
	table.insert(roads, entry)
	reserve(entry)
	return entry
end

local function zone(id: string, x0: number, x1: number, z0: number, z1: number, fields: any?): any
	local entry: any = rect(x0, x1, z0, z1)
	entry.id = id
	for key, value in pairs(fields or {}) do
		entry[key] = value
	end
	table.insert(ground, entry)
	if entry.keepClear ~= false then
		reserve(entry)
	end
	return entry
end

-- Gates in the city walls
local GATES: {any} = {
	{ id = "SouthGate", locationId = "SouthGate", center = { 0, BOUNDS.maxZ }, width = 24, kind = "Land" },
	{ id = "NorthGate", locationId = "NorthGate", center = { 300, BOUNDS.minZ }, width = 20, kind = "Land" },
	{ id = "SeaGate", center = { BOUNDS.maxX, 100 }, width = 80, kind = "Sea" },
}

-- Main roads: these stay clear of buildings and carry the city's traffic.
road("SouthRoad", -7, 7, 50, 316, { width = "Main" })
road("CastleRoad", -8, 8, -326, -50, { width = "Main" })
road("HarborRoad", 50, 392, -7, 7, { width = "Main" })
road("WestRoad", -472, -50, -6, 6, { width = "Main" })
road("NorthGateRoad", 294, 306, -516, -170, { width = "Main" })
road("NobleAvenue", -308, -292, -470, -6, { width = "Noble" })
road("NobleRoad", -472, -8, -180, -170, { width = "Noble" })
road("CraftsRoad", 8, 472, -180, -170, { width = "Main" })
road("RingNorth", -92, 92, -92, -84, { width = "Secondary" })
road("RingSouth", -92, 92, 84, 92, { width = "Secondary" })
road("RingWest", -92, -84, -92, 92, { width = "Secondary" })
road("RingEast", 84, 92, -92, 92, { width = "Secondary" })
road("MarketStreet", -472, 316, 144, 152, { width = "Secondary" })
road("CastleStreet", -114, 114, -326, -318, { width = "Secondary" })
road("CastleEastStreet", 124, 134, -324, -180, { width = "Secondary" })
road("CastleWestStreet", -134, -124, -324, -180, { width = "Secondary" })
road("SlumEdge", -152, -146, 152, 300, { width = "Secondary" })
road("HarborStreet", 318, 330, -170, 300, { width = "Main" })
road("QuayApron", 370, 392, -140, 300, { width = "Main", surface = "Quay" })
road("WallStreetSouth", -472, 392, 300, 312, { width = "Secondary" })
road("WallStreetWest", -472, -460, -170, 300, { width = "Secondary" })
road("NorthLane", -472, -134, -512, -506, { width = "Secondary" })
road("ChurchWalk", -6, 6, -22, 22, { width = "Secondary", yaw = 45 })
-- re-centre the rotated walk on the square's north-west mouth
roads[#roads].center = { -70, -70 }

-- The central square: a paved disc (radius 50) inside a ring of tall buildings.
zone("MerchantSquarePlaza", -56, 56, -56, 56, { surface = "Plaza", shape = "Disc", keepClear = false })
zone("MarketStalls", -38, 38, 26, 40, { locationId = "MarketStalls", keepClear = false, surface = "None" })
zone("FineryStall", 28, 44, -36, -24, { locationId = "FineryStall", keepClear = false, surface = "None" })
block("HeartOfRealms", 0, 0, 22, 22, 1, { locationId = "HeartOfRealms", use = "Fountain", height = 18, access = "Public", district = "MerchantSquare" })

-- Church on the square's north-west, with its yard and the alley behind it
block("Church", -120, -128, 46, 72, 3, {
	locationId = "Church",
	door = "South",
	use = "Church",
	style = "Church",
	access = "Public",
	district = "MerchantSquare",
	height = 60,
})
zone("ChurchSteps", -146, -94, -92, -60, { locationId = "ChurchSteps", surface = "Yard" })
zone("ChurchAlley", -176, -146, -160, -96, { locationId = "ChurchAlley", surface = "Alley" })
zone("ChurchGarden", -94, -88, -160, -96, { surface = "Garden" })

-- The Adventurers' Guild and the Square Inn face the square from the west and east
local ringRadius = 58
local function ringPlace(angle: number, width: number, depth: number): (number, number, number)
	local a = math.rad(angle)
	local r = ringRadius + depth / 2
	local x, z = math.cos(a) * r, math.sin(a) * r
	return x, z, math.deg(math.atan2(-math.cos(a), -math.sin(a)))
end
do
	local x, z, yaw = ringPlace(154, 34, 24)
	block("AdventurersGuild", x, z, 34, 24, 3, { locationId = "AdventurersGuild", door = "South", yaw = yaw, use = "Guild", style = "Market", access = "Public", district = "MerchantSquare", open = { South = true }, name = "Adventurers' Guild" })
	x, z, yaw = ringPlace(26, 32, 24)
	block("SquareInn", x, z, 32, 24, 3, { locationId = "SquareInn", door = "South", yaw = yaw, use = "Inn", style = "Market", access = "Public", district = "MerchantSquare", open = { South = true }, name = "The Square Inn" })
end

-- Royal castle on the north side: curtain walls, towers, gatehouse, keep, wings, gardens
local CASTLE = { minX = -124, maxX = 124, minZ = -506, maxZ = -334 }
local castleWalls = {
	{ id = "CastleWallNorth", x0 = CASTLE.minX, x1 = CASTLE.maxX, z0 = CASTLE.minZ, z1 = CASTLE.minZ + 6 },
	{ id = "CastleWallWest", x0 = CASTLE.minX, x1 = CASTLE.minX + 6, z0 = CASTLE.minZ, z1 = CASTLE.maxZ },
	{ id = "CastleWallEast", x0 = CASTLE.maxX - 6, x1 = CASTLE.maxX, z0 = CASTLE.minZ, z1 = CASTLE.maxZ },
	{ id = "CastleWallSouthWest", x0 = CASTLE.minX, x1 = -14, z0 = CASTLE.maxZ - 6, z1 = CASTLE.maxZ },
	{ id = "CastleWallSouthEast", x0 = 14, x1 = CASTLE.maxX, z0 = CASTLE.maxZ - 6, z1 = CASTLE.maxZ },
}
for _, wall in ipairs(castleWalls) do
	block(wall.id, (wall.x0 + wall.x1) / 2, (wall.z0 + wall.z1) / 2, wall.x1 - wall.x0, wall.z1 - wall.z0, 2, { kind = "Wall", use = "CastleWall", height = 26, access = "Royal", district = "Castle" })
end
for index, spot in ipairs({ { CASTLE.minX, CASTLE.minZ }, { CASTLE.maxX, CASTLE.minZ }, { CASTLE.minX, CASTLE.maxZ }, { CASTLE.maxX, CASTLE.maxZ }, { -24, CASTLE.maxZ }, { 24, CASTLE.maxZ }, { CASTLE.minX, -420 }, { CASTLE.maxX, -420 } }) do
	local size = if index >= 5 and index <= 6 then 14 else 18
	-- gatehouse towers sit just outside the curtain line; they are part of the wall
	local entry = { id = "CastleTower" .. index, center = { spot[1], spot[2] }, size = { size, size }, stories = 3, height = 44, kind = "Tower", use = "Tower", access = "Royal", district = "Castle" }
	table.insert(blocks, entry)
	reserve(entry)
end

-- stairs up to the wall walk beside each land gate (built by CityBuilder.Outdoors)
zone("NorthWallStairs", 322, 364, -516, -509, { surface = "None" })
zone("SouthWallStairs", 24, 66, 309, 316, { surface = "None" })

-- Towers along the city walls (square, centred on the wall line), none beside a gate, on the wall stairs or where the
-- castle's own towers stand. A tower stands 4 studs proud of the wall's inner face; houses keep a further 4 clear so
-- the lane by the wall goes on round it.
local TOWER_SPACING, TOWER_SIZE = 120, 16
local WALL_TOWERS = {}
do
	local seen = {}
	for _, side in ipairs({
		{ alongX = true, fixed = BOUNDS.minZ, from = BOUNDS.minX, to = BOUNDS.maxX },
		{ alongX = true, fixed = BOUNDS.maxZ, from = BOUNDS.minX, to = BOUNDS.maxX },
		{ alongX = false, fixed = BOUNDS.minX, from = BOUNDS.minZ, to = BOUNDS.maxZ },
		{ alongX = false, fixed = BOUNDS.maxX, from = BOUNDS.minZ, to = BOUNDS.maxZ },
	}) do
		local count = math.floor((side.to - side.from) / TOWER_SPACING)
		for index = 0, count do
			local along = side.from + (side.to - side.from) * index / count
			local skip = false
			for _, gate in ipairs(GATES) do
				local gateAlong, gateAcross = gate.center[1], gate.center[2]
				if not side.alongX then
					gateAlong, gateAcross = gate.center[2], gate.center[1]
				end
				if gateAcross == side.fixed and math.abs(along - gateAlong) < gate.width / 2 + 14.5 then
					skip = true
				end
			end
			local x, z = along, side.fixed
			if not side.alongX then
				x, z = side.fixed, along
			end
			local key = string.format("%d,%d", math.floor(x), math.floor(z))
			local half = TOWER_SIZE / 2
			local tower: any = rect(x - half, x + half, z - half, z + half)
			for _, list in ipairs({ blocks, ground }) do
				for _, other in ipairs(list) do
					if overlaps(tower, other) then
						skip = true
					end
				end
			end
			if not skip and not seen[key] then
				seen[key] = true
				tower.id = "WallTower" .. (#WALL_TOWERS + 1)
				table.insert(WALL_TOWERS, tower)
				reserve(rect(x - half - 4, x + half + 4, z - half - 4, z + half + 4))
			end
		end
	end
end

zone("CastleCourtyardGround", -112, 112, -392, -340, { locationId = "CastleCourtyard", surface = "Courtyard" })
zone("RoyalGardens", -112, -40, -458, -400, { surface = "Garden" })
zone("RoyalGardensEast", 40, 112, -494, -470, { surface = "Garden" })
block("CastleKeep", 0, -440, 72, 56, 3, { locationId = "ThroneRoom", door = "South", use = "Keep", style = "Royal", access = "Royal", district = "Castle", height = 64, name = "Keep of House Lundand" })
block("CastleWestWing", -94, -431, 26, 60, 2, { door = "East", use = "Barracks", style = "Royal", access = "Royal", district = "Castle", name = "Royal Guard Barracks" })
block("CastleEastWing", 94, -431, 26, 60, 2, { door = "West", use = "Chancery", style = "Royal", access = "Royal", district = "Castle", name = "Royal Chancery" })
-- the Royal Library: a double-height reading hall with a gallery, between the keep and the barracks
block("RoyalLibrary", -58, -478, 40, 40, 2, { locationId = "RoyalLibrary", door = "South", use = "Library", style = "Royal", access = "Royal", district = "Castle", height = 40, name = "Royal Library" })
block("CastleServants", 76, -485, 40, 22, 2, { door = "South", use = "Servants", style = "Royal", access = "Royal", district = "Castle", name = "Servants' Hall" })
block("CastleGatehouse", 0, -334, 28, 16, 2, { kind = "Gatehouse", use = "Gatehouse", height = 34, access = "Royal", district = "Castle" })

-- Craftsman quarter around the north gate road
block("CityForge", 270, -228, 34, 30, 2, { locationId = "CityForge", door = "East", use = "Forge", style = "Craft", access = "Public", district = "CraftsmanQuarter", open = { East = true, North = true }, name = "City Forge" })
block("CityApothecary", 326, -228, 26, 28, 2, { locationId = "CityApothecary", door = "West", use = "Apothecary", style = "Craft", access = "Public", district = "CraftsmanQuarter", open = { West = true }, name = "City Apothecary" })
block("CraftsmensGuild", 330, -296, 36, 34, 3, { locationId = "CraftsmensGuild", door = "West", use = "CraftGuild", style = "Craft", access = "Public", district = "CraftsmanQuarter", open = { West = true, South = true }, name = "Craftsmen's Guild" })
-- Guild halls (L-54): bought by player guilds, each with a planning table inside. Three in the craftsman quarter and
-- one or two in every other part of town, on a street; Config/World lists the same districts in the same order.
local GUILD_HALLS = {
	{ x = 268, z = -300, door = "East", style = "Craft", district = "CraftsmanQuarter" },
	{ x = 268, z = -360, door = "East", style = "Craft", district = "CraftsmanQuarter" },
	{ x = 332, z = -360, door = "West", style = "Craft", district = "CraftsmanQuarter" },
	{ x = 173, z = -67, door = "North", style = "Market", district = "MerchantSquare" },
	{ x = -252, z = -67, door = "North", style = "Residential", district = "Residential" },
	{ x = 129, z = 169, door = "North", style = "Residential", district = "Residential" },
	{ x = 300, z = -100, door = "East", style = "Harbor", district = "Harbor" },
	{ x = -278, z = 169, door = "North", style = "Slum", district = "Slums" },
	{ x = -26, z = -250, door = "East", style = "Residential", district = "Residential" },
	{ x = 65, z = 127, door = "South", style = "Market", district = "MerchantSquare" },
}
for index, spot in ipairs(GUILD_HALLS) do
	local id = string.format("GuildHall%02d", index)
	block(id, spot.x, spot.z, 36, 34, 2, { propertyId = id, door = spot.door, use = "GuildHall", style = spot.style, access = "Guild", district = spot.district, open = { [spot.door] = true } })
end

-- Player storefronts on the market street just south of the square (L-53, L-54)
for index = 1, 6 do
	local side = if index % 2 == 1 then -1 else 1
	local z = ({ 105, 131, 172 })[math.floor((index - 1) / 2) + 1]
	local id = string.format("Storefront%02d", index)
	block(id, side * 22, z, 30, 26, 3, { propertyId = id, door = if side < 0 then "East" else "West", use = "Storefront", style = "Market", access = "Sale", district = "MerchantSquare", open = { [if side < 0 then "East" else "West"] = true }, shopfront = true })
end

-- Harbour: quay, warehouses, customs, fish market, sailors' tavern; water east of the quay
local WATER = { minX = 392, maxX = 900, minZ = -136, maxZ = 300 }
local harbourWater = rect(WATER.minX, 480, WATER.minZ, WATER.maxZ)
harbourWater.id = "HarbourBasin"
reserve(harbourWater)
block("CustomsHouse", 350, 26, 38, 30, 3, { locationId = "CustomsHouse", door = "East", use = "Customs", style = "Harbor", access = "Public", district = "Harbor", open = { East = true, North = true, West = true }, name = "Customs House" })
block("FishMarket", 350, -36, 38, 36, 1, { locationId = "FishMarket", use = "FishMarket", style = "Harbor", access = "Public", district = "Harbor", height = 16, open = { East = true, West = true, North = true, South = true }, door = "East", name = "Fish Market" })
block("SailorsTavern", 300, 40, 30, 28, 3, { locationId = "SailorsTavern", door = "East", use = "Tavern", style = "Harbor", access = "Public", district = "Harbor", open = { East = true }, name = "The Salt and Anchor" })
block("CargoOffice", 300, -30, 28, 26, 2, { locationId = "CargoOffice", door = "East", use = "Office", style = "Harbor", access = "Public", district = "Harbor", open = { East = true }, name = "Harbour Cargo Office" })
local warehouseIndex = 0
for _, z in ipairs({ -110, -76, 80, 116, 152, 188, 224, 260 }) do
	warehouseIndex += 1
	block(string.format("Warehouse%02d", warehouseIndex), 350, z, 38, 32, 2, { door = "East", use = "Warehouse", style = "Harbor", access = "Npc", district = "Harbor", open = { East = true, West = true } })
end
zone("HarbourQuay", 370, 392, -136, 300, { locationId = "HarbourQuay", surface = "None", keepClear = false })

-- Slums: the Crooked Lantern tavern stands over the hideout's cellar stairs
-- (the trapdoor is in the building's own frame: the cellar stairs go down in its back room)
block("CrookedLantern", -262, 214, 28, 24, 2, { locationId = "CrookedLantern", door = "South", use = "SlumTavern", style = "Slum", access = "Public", district = "Slums", open = { South = true, East = true }, name = "The Crooked Lantern", trapdoor = { x0 = 7.5, x1 = 11.5, z0 = -10, z1 = -1 } })
zone("LanternYard", -248, -232, 200, 228, { surface = "Alley" })
zone("ThievesGuildEntrance", -246, -234, 216, 226, { locationId = "ThievesGuildEntrance", surface = "None", keepClear = false })
zone("SlumWell", -340, -316, 250, 270, { surface = "Alley" })

-- Gate yards: open space inside each gate
zone("SouthGateYard", -40, 40, 286, 300, { surface = "Plaza" })
zone("NorthGateYard", 280, 320, -512, -490, { surface = "Plaza" })
zone("TempleYardEast", -94, -88, -96, -60, { surface = "None" })

--------------------------------------------------------------------------------------------------------------------
-- Noble quarter: estates behind garden walls along the noble avenue
--------------------------------------------------------------------------------------------------------------------
local nobleSale, estateIndex = 0, 0
for _, column in ipairs({ { -460, -308 }, { -292, -138 } }) do
	for _, rowRange in ipairs({ { -506, -340 }, { -334, -180 } }) do
		local plotW = (column[2] - column[1]) / 2
		local plotD = (rowRange[2] - rowRange[1]) / 2
		for ix = 0, 1 do
			for iz = 0, 1 do
				local x0 = column[1] + ix * plotW
				local z0 = rowRange[1] + iz * plotD
				local cx, cz = x0 + plotW / 2, z0 + plotD / 2
				-- the house faces the street along the north or south edge of its plot
				local door = if iz == 1 then "South" else "North"
				estateIndex += 1
				local template = if estateIndex % 3 == 0 then TEMPLATES.Manor else TEMPLATES.Mansion
				local width, depth = template.w, template.d
				local saleable = estateIndex % 2 == 1 or estateIndex == 8
				local id: string, fields: any
				if saleable then
					nobleSale += 1
					id = string.format("NobleHouse%02d", nobleSale)
					fields = { propertyId = id, access = "Sale" }
				else
					id = string.format("NobleEstate%02d", estateIndex)
					fields = { access = "Npc" }
				end
				fields.door = door
				fields.use = "Mansion"
				fields.template = template.id
				fields.style = "Noble"
				fields.district = "NobleQuarter"
				fields.open = { North = true, South = true, East = true, West = true }
				fields.estate = { center = { cx, cz }, size = { plotW - 8, plotD - 8 } }
				block(id, cx, cz, width, depth, template.stories, fields)
				zone(id .. "Garden", cx - (plotW - 8) / 2, cx + (plotW - 8) / 2, cz - (plotD - 8) / 2, cz + (plotD - 8) / 2, { surface = "Garden", keepClear = false })
			end
		end
	end
end
road("NobleCross", -460, -138, -340, -334, { width = "Noble" })

--------------------------------------------------------------------------------------------------------------------
-- Dense streets: district grids, a ring of attached buildings around each block's courtyard
--------------------------------------------------------------------------------------------------------------------
local DISTRICTS: {[string]: any} = {
	Market = { style = "Market", templates = { "MarketA", "MarketB", "MarketC" }, sale = 0.5, district = "MerchantSquare" },
	Residential = { style = "Residential", templates = { "TownA", "TownB", "TownC" }, sale = 0.8, district = "Residential" },
	Royal = { style = "Residential", templates = { "TownB", "TownC" }, sale = 0.8, district = "Residential" },
	Craft = { style = "Craft", templates = { "CraftA", "CraftB" }, sale = 0.6, district = "CraftsmanQuarter" },
	Harbor = { style = "Harbor", templates = { "HarborA", "HarborB" }, sale = 0.7, district = "Harbor" },
	Slum = { style = "Slum", templates = { "SlumA", "SlumB" }, sale = 0.5, district = "Slums" },
}
for _, district in pairs(DISTRICTS) do
	local deepest, narrowest = 0, math.huge
	for _, id in ipairs(district.templates) do
		deepest = math.max(deepest, TEMPLATES[id].d)
		narrowest = math.min(narrowest, TEMPLATES[id].w)
	end
	district.depth, district.minWidth = deepest, narrowest
end

local propertyCounters: {[string]: number} = {}
local PROPERTY_PREFIX = { Market = "MarketHouse", Residential = "TownHouse", Royal = "TownHouse", Craft = "CraftHouse", Harbor = "HarborHouse", Slum = "SlumHouse" }
local function nextPropertyId(prefix: string): string
	propertyCounters[prefix] = (propertyCounters[prefix] or 0) + 1
	return string.format("%s%02d", prefix, propertyCounters[prefix])
end

local generated = 0
-- One house on a lot: the template's footprint, front on the street side of the row.
local function makeLot(kind: string, district: any, template: any, x0: number, x1: number, z0: number, z1: number, door: string, open: any)
	local entry: any = rect(x0, x1, z0, z1)
	if not clear(entry) then
		return
	end
	-- the street in front of the door must not be another building or a tower
	local stepX = if door == "East" then x1 + 2.5 elseif door == "West" then x0 - 2.5 else (x0 + x1) / 2
	local stepZ = if door == "South" then z1 + 2.5 elseif door == "North" then z0 - 2.5 else (z0 + z1) / 2
	local step = rect(stepX - 1.5, stepX + 1.5, stepZ - 1.5, stepZ + 1.5)
	for _, other in ipairs(blocks) do
		if overlaps(step, other) then
			return
		end
	end
	generated += 1
	local id = string.format("%s%03d", kind, generated)
	local fields: any = { door = door, style = district.style, district = district.district, open = open, template = template.id }
	fields.use = if kind == "Slum" then "Shack" else "Townhouse"
	-- shop, home for sale or an NPC's house: decided once every building stands (see "Foot traffic, shops and deeds")
	fields.lot = { kind = kind, sale = district.sale }
	block(id, entry.center[1], entry.center[2], entry.size[1], entry.size[2], template.stories, fields)
end

-- Fills a run [a, b] with templates; what is left at the end (narrower than any template) stays an alley.
local function fill(a: number, b: number, district: any): {any}
	local out = {}
	local cursor = a
	while true do
		local fits = {}
		for _, id in ipairs(district.templates) do
			if TEMPLATES[id].w <= b - cursor then
				table.insert(fits, TEMPLATES[id])
			end
		end
		if #fits == 0 then
			break
		end
		local template = pick(fits)
		table.insert(out, { from = cursor, to = cursor + template.w, template = template })
		cursor += template.w
	end
	return out
end

local courtyards = 0
-- A street block: rows on all four sides around a courtyard, one alley gap into the courtyard.
local function streetBlock(kind: string, x0: number, x1: number, z0: number, z1: number)
	local district = DISTRICTS[kind]
	local width, height = x1 - x0, z1 - z0
	local depth = district.depth
	if width < district.minWidth or height < depth then
		return
	end
	local twoRowsZ = height >= depth * 2 + 6
	local twoRowsX = width >= depth * 2 + district.minWidth
	-- north and south rows (they own the corners); each house sits against its street, a yard behind it
	local rows = { { door = "North", street = z0 } }
	if twoRowsZ then
		table.insert(rows, { door = "South", street = z1 })
	end
	for _, row in ipairs(rows) do
		local lots = fill(x0, x1, district)
		for index, lot in ipairs(lots) do
			local d = lot.template.d
			local a, b = if row.door == "North" then row.street else row.street - d, if row.door == "North" then row.street + d else row.street
			local open = { [row.door] = true, [if row.door == "North" then "South" else "North"] = true }
			if index == 1 then
				open.West = true
			end
			if index == #lots then
				open.East = true
			end
			makeLot(kind, district, lot.template, lot.from, lot.to, a, b, row.door, open)
		end
	end
	-- west and east rows between them
	if twoRowsZ and twoRowsX then
		local zA, zB = z0 + depth, z1 - depth
		for _, row in ipairs({ { door = "West", street = x0 }, { door = "East", street = x1 } }) do
			for _, lot in ipairs(fill(zA, zB, district)) do
				local d = lot.template.d
				local a, b = if row.door == "West" then row.street else row.street - d, if row.door == "West" then row.street + d else row.street
				makeLot(kind, district, lot.template, a, b, lot.from, lot.to, row.door, { [row.door] = true, [if row.door == "West" then "East" else "West"] = true })
			end
		end
		local cx0, cx1, cz0, cz1 = x0 + depth, x1 - depth, z0 + depth, z1 - depth
		if cx1 - cx0 >= 8 and cz1 - cz0 >= 6 then
			courtyards += 1
			zone(string.format("Courtyard%03d", courtyards), cx0, cx1, cz0, cz1, { surface = if kind == "Slum" then "Alley" else "Yard", keepClear = false, district = kind })
		end
	end
end

-- grid(kind, x0, x1, z0, z1, xCuts, zCuts): cuts are street centre lines { position, width }
local function grid(kind: string, x0: number, x1: number, z0: number, z1: number, xCuts: {{number}}, zCuts: {{number}})
	local xs = { { x0, x0 } }
	for _, cut in ipairs(xCuts) do
		table.insert(xs, { cut[1] - cut[2] / 2, cut[1] + cut[2] / 2 })
	end
	table.insert(xs, { x1, x1 })
	local zs = { { z0, z0 } }
	for _, cut in ipairs(zCuts) do
		table.insert(zs, { cut[1] - cut[2] / 2, cut[1] + cut[2] / 2 })
	end
	table.insert(zs, { z1, z1 })
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			streetBlock(kind, xs[i][2], xs[i + 1][1], zs[j][2], zs[j + 1][1])
		end
	end
end

-- Square ring: tall buildings facing the plaza, gaps for the main roads and the diagonal lanes
local MOUTHS = { { 0, 18 }, { 90, 18 }, { 180, 18 }, { 270, 20 }, { 135, 8 }, { 225, 12 } }
local function inMouth(angle: number, halfSpan: number): boolean
	for _, mouth in ipairs(MOUTHS) do
		local delta = (angle - mouth[1] + 540) % 360 - 180
		local halfGap = math.deg(math.asin(math.min(1, (mouth[2] / 2) / ringRadius)))
		if math.abs(delta) < halfGap + halfSpan then
			return true
		end
	end
	return false
end
do
	local angle = 0
	local ringIndex = 0
	while angle < 360 do
		local width = TEMPLATES.RingHouse.w
		local depth = TEMPLATES.RingHouse.d
		local halfSpan = math.deg(math.asin((width / 2) / ringRadius))
		local center = angle + halfSpan
		if inMouth(center, halfSpan) then
			angle += 0.5
		else
			local x, z, yaw = ringPlace(center, width, depth)
			local entry: any = { center = { x, z }, size = { width, depth }, yaw = yaw }
			if clear(entry) then
				ringIndex += 1
				generated += 1
				-- tall town houses face the square, the busiest spot in the city: many become shops
				local fields: any = { yaw = yaw, door = "South", style = "Market", district = "MerchantSquare", open = { South = true, North = true }, template = "RingHouse", use = "Townhouse" }
				fields.lot = { kind = "Market", sale = 0.5 }
				block(string.format("SquareRing%02d", ringIndex), x, z, width, depth, 3, fields)
				angle += halfSpan * 2 + 0.4
			else
				angle += 0.5
			end
		end
	end
end

-- West residential (between the ring street and the west wall, north and south of the west road)
grid("Residential", -460, -92, -170, -6, { { -150, 7 }, { -214, 5 }, { -280, 7 }, { -350, 5 }, { -410, 6 } }, { { -126, 6 }, { -88, 8 }, { -44, 5 } })
grid("Residential", -460, -92, 6, 144, { { -134, 6 }, { -196, 5 }, { -262, 7 }, { -330, 5 }, { -398, 6 } }, { { 46, 6 }, { 88, 8 } })
-- North of the square, either side of the castle road (the old royal quarter)
grid("Royal", -124, -8, -318, -92, { { -66, 6 } }, { { -270, 6 }, { -210, 7 }, { -126, 6 } })
grid("Royal", 8, 124, -318, -92, { { 66, 6 } }, { { -270, 6 }, { -210, 7 }, { -126, 6 } })
grid("Market", 92, 300, -170, -7, { { 150, 7 }, { 222, 6 } }, { { -88, 8 } })
grid("Market", 92, 300, 7, 144, { { 152, 6 }, { 226, 7 } }, { { 88, 8 } })
grid("Market", -92, 92, 92, 144, { { -44, 6 }, { 44, 6 } }, {})
-- Craftsman quarter
grid("Craft", 134, 472, -512, -180, { { 200, 7 }, { 384, 7 } }, { { -440, 6 }, { -392, 7 }, { -264, 6 } })
-- South-central and south-east residential
grid("Residential", -146, 316, 152, 300, { { -88, 6 }, { -44, 5 }, { 52, 5 }, { 108, 6 }, { 172, 7 }, { 238, 5 } }, { { 222, 6 } })
-- Harbour back streets
grid("Harbor", 250, 318, -140, 300, {}, { { -70, 6 }, { 70, 6 }, { 140, 5 }, { 214, 6 } })
-- Slums: narrow alleys, small lots
grid("Slum", -460, -152, 152, 300, { { -404, 4 }, { -352, 5 }, { -300, 4 }, { -220, 4 }, { -186, 4 } }, { { 194, 4 }, { 246, 5 } })

--------------------------------------------------------------------------------------------------------------------
-- Foot traffic, shops and deeds
--------------------------------------------------------------------------------------------------------------------
-- How busy a spot on the street is, from 0 (a back lane far from the square) to 1 (a main road by the square). It sets
-- what a property there costs (Domain.PropertyPricing) and how likely a house there is to be a shop.
local function trafficAt(x: number, z: number): number
	local nearSquare = math.clamp((420 - math.sqrt(x * x + z * z)) / 350, 0, 1)
	local onRoad = 0
	-- (a door counts as on a road when the road is within 8 studs: across the pavement in front of it)
	local here = rect(x - 8, x + 8, z - 8, z + 8)
	for _, road in ipairs(roads) do
		if overlaps(here, road) then
			onRoad = math.max(onRoad, if road.width == "Main" then 1 else 0.6)
		end
	end
	return math.floor((0.65 * nearSquare + 0.35 * onRoad) * 100 + 0.5) / 100
end

-- Is there street enough in front of a building for a shop's counter (clear of every other building and the walls)?
local function roomForCounter(entry: any): boolean
	local strip = LayoutRules.frontStrip(entry, LayoutRules.SHOP_FRONTAGE)
	local inner = BOUNDS
	local x0, x1, z0, z1 = LayoutRules.bounds(strip)
	local wall = WALL_THICKNESS / 2
	if x0 < inner.minX + wall or x1 > inner.maxX - wall or z0 < inner.minZ + wall or z1 > inner.maxZ - wall then
		return false
	end
	for _, list in ipairs({ blocks, WALL_TOWERS }) do
		for _, other in ipairs(list) do
			if other ~= entry and LayoutRules.overlaps(strip, other) then
				return false
			end
		end
	end
	return true
end

-- Every lot is now a shop, a home for sale or an NPC's house. The busier its street, the likelier a shop: shops line
-- the square and the main roads, and a few sit in quieter streets too.
local SHOP_PREFIX = { Market = "MarketShop", Residential = "TownShop", Royal = "TownShop", Craft = "CraftShop", Harbor = "HarborShop", Slum = "SlumShop" }
for _, entry in ipairs(blocks) do
	local step = if entry.door ~= nil then LayoutRules.doorStep(entry) else nil
	if step ~= nil and (entry.lot ~= nil or entry.propertyId ~= nil) then
		entry.traffic = trafficAt(step[1], step[2])
	end
	local lot = entry.lot
	if lot ~= nil then
		entry.lot = nil
		if roomForCounter(entry) and chance(0.06 + 0.6 * entry.traffic) then
			entry.use = "Storefront"
			entry.shopfront = true
			entry.access = "Sale"
			entry.propertyId = nextPropertyId(SHOP_PREFIX[lot.kind])
		elseif chance(lot.sale) then
			entry.access = "Sale"
			entry.propertyId = nextPropertyId(PROPERTY_PREFIX[lot.kind])
		else
			entry.access = "Npc"
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- People, markers, passages
--------------------------------------------------------------------------------------------------------------------
local function insideOf(entry: any, lx: number, lz: number): {number}
	-- a point in an entry's local frame (x across, z towards its south side), turned into world coordinates
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	return { entry.center[1] + lx * c + lz * s, entry.center[2] - lx * s + lz * c }
end
local function find(id: string): any
	for _, entry in ipairs(blocks) do
		if entry.id == id then
			return entry
		end
	end
	error("no block " .. id)
end
local guild, inn = find("AdventurersGuild"), find("SquareInn")

local SPAWN = { -120, -78 }

local layout: any = {
	floorHeight = FLOOR_HEIGHT,
	templates = TEMPLATES,
	-- instanced interiors are built far above the map, one slot per house that someone is inside
	interiors = { origin = { 3000, 800, -1500 }, spacing = 80, perRow = 16 },
	bounds = BOUNDS,
	walls = { thickness = WALL_THICKNESS, height = 30, towerSpacing = TOWER_SPACING, towerSize = TOWER_SIZE },
	wallTowers = WALL_TOWERS,
	door = { width = 6, height = 9 },
	gates = GATES,
	water = { { id = "Harbour", center = { (WATER.minX + WATER.maxX) / 2, (WATER.minZ + WATER.maxZ) / 2 }, size = { WATER.maxX - WATER.minX, WATER.maxZ - WATER.minZ }, level = -2, depth = 16 } },
	piers = { { z = -96, length = 70 }, { z = -20, length = 74 }, { z = 60, length = 60 }, { z = 136, length = 74 }, { z = 206, length = 66 }, { z = 270, length = 56 } },
	ships = {
		{ name = "Saint Aldric", center = { 446, -58 }, length = 64, beam = 16, masts = 3 },
		{ name = "Grey Heron", center = { 438, 20 }, length = 48, beam = 13, masts = 2 },
		{ name = "Lundand's Promise", center = { 448, 100 }, length = 58, beam = 15, masts = 3 },
		{ name = "Little Wren", center = { 428, 172 }, length = 30, beam = 9, masts = 1 },
		{ name = "Tern", center = { 432, 238 }, length = 36, beam = 10, masts = 1 },
	},
	ground = ground,
	roads = roads,
	blocks = blocks,
	props = props,
	spawn = { center = SPAWN },
	npcs = {
		{ npcId = "TheKing", at = { 0, -452 } },
		{ npcId = "OldScholar", at = { 0, 16 } },
		{ npcId = "GuildRegistrar", at = insideOf(guild, -6, -2) },
		{ npcId = "PartyClerk", at = insideOf(guild, 6, -2) },
		{ npcId = "GuildSteward", at = { 336, -296 } },
		{ npcId = "ForgeMaster", at = { 266, -234 } },
		{ npcId = "Apothecary", at = { 330, -232 } },
		{ npcId = "ChurchPriest", at = { -120, -140 } },
		{ npcId = "Innkeeper", at = insideOf(inn, -4, -4) },
		{ npcId = "WearyStranger", at = { -136, -70 } },
		{ npcId = "Hunter", at = { 18, 292 } },
		{ npcId = "Clothier", at = { 36, -30 } },
		{ npcId = "HeartCrystal", at = { 0, -12 } },
	},
	-- Opening markers (L-43): where new characters appear, the ritual circle, and the starting chest.
	markers = ({
		{ id = "ChurchSpawn", kind = "SpawnPoint", spawnId = "Church", at = { -136, -112 }, inside = "Church" },
		{ id = "AwakeningCircle", kind = "RitualCircle", at = { -120, -124 }, inside = "Church" },
		{ id = "StarterChest", kind = "StarterChest", at = { -106, -104 }, inside = "Church" },
	} :: {any}),
	-- Physical stairs replace the old teleport passages; WorldService still builds anything listed here.
	passages = {},
	-- The hideout beneath the slums (built by CityBuilder.Hideout): floor level and the rooms' footprints.
	hideout = {
		floorY = -30,
		entranceBlock = "CrookedLantern",
		rooms = ({
			{ id = "HideoutCellar", center = { -258, 206 }, size = { 22, 18 }, floorY = -14, height = 11, kind = "Cellar" },
			{ id = "HideoutEntrance", center = { -262, 238 }, size = { 30, 40 }, kind = "Entrance", locationId = "HideoutEntrance" },
			{ id = "HideoutStore", center = { -296, 250 }, size = { 30, 28 }, kind = "Store" },
			{ id = "HideoutHall", center = { -214, 244 }, size = { 54, 44 }, kind = "Hall", locationId = "HideoutHall" },
			{ id = "HideoutBunks", center = { -214, 284 }, size = { 40, 22 }, kind = "Bunks" },
			{ id = "HideoutInner", center = { -166, 226 }, size = { 32, 28 }, kind = "Inner", locationId = "HideoutInner" },
			{ id = "HideoutThrone", center = { -166, 266 }, size = { 32, 30 }, kind = "Throne", locationId = "HideoutThrone" },
		} :: {any}),
		tunnels = {
			{ from = "HideoutEntrance", to = "HideoutStore" },
			{ from = "HideoutEntrance", to = "HideoutHall" },
			{ from = "HideoutHall", to = "HideoutBunks" },
			{ from = "HideoutHall", to = "HideoutInner" },
			{ from = "HideoutInner", to = "HideoutThrone" },
		},
	},
	-- The forest beyond the south gate (CityBuilder.Forest). Zones keep the spawner and gathering IDs.
	forest = {
		bounds = { minX = -420, maxX = 420, minZ = 332, maxZ = 960 },
		seed = 7,
		zones = {
			{ id = "ForestEdge", center = { 0, 420 }, size = { 240, 70 } },
			{ id = "ForestDeep", center = { -40, 600 }, size = { 360, 180 } },
			{ id = "ForestDen", center = { 210, 830 }, size = { 100, 80 } },
		},
		path = { { 0, 324 }, { 6, 380 }, { -24, 440 }, { -10, 500 }, { 40, 560 }, { 30, 640 }, { 90, 720 }, { 170, 780 }, { 210, 830 } },
		branches = {
			{ { -24, 440 }, { -120, 470 }, { -230, 520 }, { -300, 600 } },
			{ { 30, 640 }, { -60, 700 }, { -140, 800 } },
		},
		clearings = { { center = { -150, 480 }, radius = 30 }, { center = { 120, 600 }, radius = 34 }, { center = { -170, 790 }, radius = 28 } },
		ruins = {
			{ kind = "Cabin", center = { -232, 528 } },
			{ kind = "Watchtower", center = { 140, 470 } },
			{ kind = "Shrine", center = { -144, 806 } },
		},
	},
	-- The road beyond the north gate towards the mountains (future region)
	outerRoad = { from = { 300, BOUNDS.minZ - 4 }, to = { 340, -1000 } },
}

return Table.deepFreeze(layout)
