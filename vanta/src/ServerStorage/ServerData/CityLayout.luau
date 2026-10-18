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
-- gates on the wall, every door reachable from the gates, stairs fit, every location and property placed once).
-- Entries keep the greybox fields (id, center, size, height, door, locationId, propertyId) and add:
--   yaw      rotation in degrees (the footprint is size = local width x depth, turned about its centre)
--   use      what the building is (Townhouse, Shop, Inn, Apartments, Mansion, Warehouse, ...), drives its interior
--   stories  floors above ground (each FLOOR_HEIGHT studs)
--   style    exterior palette (Market, Residential, Noble, Slum, Harbor, Craft, Royal)
--   access   Public, Npc (an NPC's home or business), Sale (a player property), Guild, Royal, Quest
--   open     sides that face a street or yard (get windows; other sides are shared walls)
--   units    apartments: one property per floor { { propertyId, floor } }
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

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
local function between(min: number, max: number): number
	return min + (max - min) * nextUnit()
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
-- Guild halls (L-54): bought by player guilds, each with a planning table inside
for index, spot in ipairs({ { x = 268, z = -300, door = "East" }, { x = 268, z = -360, door = "East" }, { x = 332, z = -360, door = "West" } }) do
	local id = string.format("GuildHall%02d", index)
	block(id, spot.x, spot.z, 36, 34, 2, { propertyId = id, door = spot.door, use = "GuildHall", style = "Craft", access = "Guild", district = "CraftsmanQuarter", open = { [spot.door] = true } })
end

-- Player storefronts on the market street just south of the square (L-53, L-54)
for index = 1, 6 do
	local side = if index % 2 == 1 then -1 else 1
	local z = ({ 105, 131, 172 })[math.floor((index - 1) / 2) + 1]
	local id = string.format("Storefront%02d", index)
	block(id, side * 22, z, 30, 26, 3, { propertyId = id, door = if side < 0 then "East" else "West", use = "Storefront", style = "Market", access = "Sale", district = "MerchantSquare", open = { [if side < 0 then "East" else "West"] = true } })
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
-- stairs up to the wall walk beside each land gate (built by CityBuilder.Outdoors)
zone("NorthWallStairs", 322, 364, -516, -509, { surface = "None" })
zone("SouthWallStairs", 24, 66, 309, 316, { surface = "None" })
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
				local width, depth = integer(36, 44), integer(30, 36)
				if door == "East" or door == "West" then
					width, depth = depth, width
				end
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
				fields.style = "Noble"
				fields.district = "NobleQuarter"
				fields.open = { North = true, South = true, East = true, West = true }
				fields.estate = { center = { cx, cz }, size = { plotW - 8, plotD - 8 } }
				block(id, cx, cz, width, depth, integer(2, 3), fields)
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
	Market = { style = "Market", stories = { 3, 3, 3, 2 }, width = { 17, 25 }, depth = { 22, 26 }, sale = 0.35, shops = 0.75, district = "MerchantSquare" },
	Residential = { style = "Residential", stories = { 2, 3, 3, 3 }, width = { 18, 25 }, depth = { 20, 25 }, sale = 0.8, shops = 0.15, district = "Residential" },
	Royal = { style = "Residential", stories = { 3, 3, 2 }, width = { 20, 28 }, depth = { 22, 26 }, sale = 0.8, shops = 0.1, district = "Residential" },
	Craft = { style = "Craft", stories = { 2, 2, 3 }, width = { 18, 26 }, depth = { 22, 26 }, sale = 0.6, shops = 0.6, district = "CraftsmanQuarter" },
	Harbor = { style = "Harbor", stories = { 2, 2, 3 }, width = { 17, 24 }, depth = { 20, 24 }, sale = 0.7, shops = 0.3, district = "Harbor" },
	Slum = { style = "Slum", stories = { 1, 2, 2, 2 }, width = { 13, 17 }, depth = { 18, 20 }, sale = 0.5, shops = 0.12, district = "Slums" },
}

local SHOPS = {
	Market = { "GeneralGoods", "Weapons", "Armor", "Tailor", "Bakery", "Butcher", "Potions", "MagicSupplies", "Jeweler", "Cobbler", "Blacksmith", "Tavern", "Grocer", "Bookbinder", "Chandler" },
	Residential = { "Bakery", "Grocer", "Cobbler", "Tavern", "GeneralGoods", "Tailor" },
	Royal = { "Jeweler", "Tailor", "MagicSupplies", "Bookbinder" },
	Craft = { "Blacksmith", "Carpenter", "Tanner", "Weaver", "Workshop", "Workshop", "Armor", "Weapons" },
	Harbor = { "Chandlery", "FishShop", "GeneralGoods", "Tavern", "Rope", "Storage" },
	Slum = { "Pawnshop", "FoodStall", "Workshop", "Tavern" },
}

local SHOP_NAMES: {[string]: {string}} = {
	GeneralGoods = { "Odds and Ends", "The Full Basket", "Merrow's Sundries" },
	Weapons = { "Steel and Edge", "The Honest Blade", "Brannoc's Arms" },
	Armor = { "The Iron Coat", "Plate and Mail", "Shieldwright" },
	Tailor = { "Needle and Thread", "The Golden Spool", "Fine Cloth" },
	Bakery = { "The Warm Loaf", "Oven and Hearth", "Sweetcrust" },
	Butcher = { "Cleaver and Hook", "The Smoked Ham" },
	Potions = { "Vials and Tinctures", "The Green Flask" },
	MagicSupplies = { "Arcane Sundries", "The Wandering Star", "Runes and Reagents" },
	Jeweler = { "Silver Setting", "The Gilded Ring" },
	Cobbler = { "Sole and Heel", "The Cobbler's Last" },
	Blacksmith = { "Hammerfall Smithy", "The Red Anvil", "Coalbrook Forge" },
	Tavern = { "The Grey Goose", "The Three Crowns", "The Drunken Bard", "The Black Boar", "The Rusty Nail", "The Sleeping Hound" },
	Grocer = { "Market Greens", "The Root Cellar" },
	Bookbinder = { "Ink and Vellum", "The Bound Page" },
	Chandler = { "Wick and Wax" },
	Carpenter = { "The Joiner's Bench", "Oak and Adze" },
	Tanner = { "Hide and Leather" },
	Weaver = { "The Loom House" },
	Workshop = { "Workshop" },
	Chandlery = { "Ship's Chandlery" },
	FishShop = { "Fresh Catch" },
	Rope = { "Ropewalk" },
	Storage = { "Storehouse" },
	Pawnshop = { "Second Chances", "Old Moll's Pawn" },
	FoodStall = { "Stew Pot", "Hot Pies" },
}
local nameCounters: {[string]: number} = {}
local function shopName(kind: string): string
	local names: {string} = SHOP_NAMES[kind] or { kind }
	nameCounters[kind] = (nameCounters[kind] or 0) + 1
	return names[(nameCounters[kind] - 1) % #names + 1]
end

local propertyCounters: {[string]: number} = {}
local PROPERTY_PREFIX = { Market = "MarketHouse", Residential = "TownHouse", Royal = "TownHouse", Craft = "CraftHouse", Harbor = "HarborHouse", Slum = "SlumHouse" }
local function nextPropertyId(prefix: string): string
	propertyCounters[prefix] = (propertyCounters[prefix] or 0) + 1
	return string.format("%s%02d", prefix, propertyCounters[prefix])
end

local generated = 0
local FLAT_PREFIX = { Market = "MarketFlat", Residential = "TownFlat", Royal = "TownFlat", Craft = "CraftFlat", Harbor = "HarborFlat" }
local function makeLot(kind: string, district: any, x0: number, x1: number, z0: number, z1: number, door: string, open: any)
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
	local facade = if door == "North" or door == "South" then x1 - x0 else z1 - z0
	local depth = if door == "North" or door == "South" then z1 - z0 else x1 - x0
	local stories = pick(district.stories)
	if depth < 20 then
		stories = math.min(stories, 2)
	end
	if facade < 14 then
		stories = math.min(stories, 2)
	end
	generated += 1
	local id = string.format("%s%03d", kind, generated)
	local fields: any = { door = door, style = district.style, district = district.district, open = open }
	local roll = nextUnit()
	if roll < district.shops then
		local shop = pick(SHOPS[kind])
		fields.use = if shop == "Tavern" then "Tavern" elseif shop == "Blacksmith" then "Smithy" else "Shop"
		fields.shop = shop
		fields.name = shopName(shop)
		fields.access = "Npc"
	elseif stories == 3 and facade >= 20 and depth >= 22 and kind ~= "Slum" and chance(0.35) then
		fields.use = "Apartments"
		fields.access = "Sale"
		fields.units = {}
		for floor = 0, 2 do
			table.insert(fields.units, { propertyId = nextPropertyId(FLAT_PREFIX[kind]), floor = floor })
		end
	elseif chance(district.sale) then
		fields.use = if kind == "Slum" then "Shack" else "Townhouse"
		fields.access = "Sale"
		fields.propertyId = nextPropertyId(PROPERTY_PREFIX[kind])
	else
		fields.use = if kind == "Slum" then "Shack" else "Townhouse"
		fields.access = "Npc"
	end
	block(id, entry.center[1], entry.center[2], entry.size[1], entry.size[2], stories, fields)
end

-- Splits a run [a, b] into lot widths between min and max, the last one absorbing the remainder.
local function split(a: number, b: number, minWidth: number, maxWidth: number): {{number}}
	local out = {}
	local cursor = a
	while b - cursor >= minWidth do
		local width = math.floor(between(minWidth, maxWidth) + 0.5)
		if b - cursor - width < minWidth then
			width = b - cursor
		end
		table.insert(out, { cursor, cursor + width })
		cursor += width
	end
	return out
end

local courtyards = 0
-- A street block: rows on all four sides around a courtyard, one alley gap into the courtyard.
local function streetBlock(kind: string, x0: number, x1: number, z0: number, z1: number)
	local district = DISTRICTS[kind]
	local width, height = x1 - x0, z1 - z0
	if width < 14 or height < 16 then
		return
	end
	local depth = integer(district.depth[1], district.depth[2])
	local twoRowsZ = height >= depth * 2 + 6
	local twoRowsX = width >= depth * 2 + 6
	local nDepth = if twoRowsZ then depth else height
	local sDepth = if twoRowsZ then depth else 0
	-- north and south rows (they own the corners)
	local alleyGap = if twoRowsZ and width > 60 then integer(1, 2) else 0
	for _, row in ipairs({ { a = z0, b = z0 + nDepth, door = "North" }, { a = z1 - sDepth, b = z1, door = "South" } }) do
		if row.b - row.a >= 14 then
			local lots = split(x0, x1, district.width[1], district.width[2])
			for index, lot in ipairs(lots) do
				local isGap = alleyGap > 0 and row.door == "South" and index == math.max(2, math.floor(#lots / 2)) and #lots >= 4
				if isGap then
					-- an alley into the courtyard: a narrow passage, then the rest of the lot as a smaller house
					local passage = 5
					if lot[2] - lot[1] - passage >= 12 then
						makeLot(kind, district, lot[1] + passage, lot[2], row.a, row.b, row.door, { [row.door] = true, West = true })
					end
				else
					local open = { [row.door] = true }
					if index == 1 then
						open.West = true
					end
					if index == #lots then
						open.East = true
					end
					if twoRowsZ then
						open[if row.door == "North" then "South" else "North"] = true
					end
					makeLot(kind, district, lot[1], lot[2], row.a, row.b, row.door, open)
				end
			end
		end
	end
	-- west and east rows between them
	if twoRowsZ and twoRowsX then
		local zA, zB = z0 + nDepth, z1 - sDepth
		for _, row in ipairs({ { a = x0, b = x0 + depth, door = "West" }, { a = x1 - depth, b = x1, door = "East" } }) do
			for _, lot in ipairs(split(zA, zB, district.width[1], district.width[2])) do
				makeLot(kind, district, row.a, row.b, lot[1], lot[2], row.door, { [row.door] = true, [if row.door == "West" then "East" else "West"] = true })
			end
		end
		local cx0, cx1, cz0, cz1 = x0 + depth, x1 - depth, z0 + nDepth, z1 - sDepth
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
		local width = integer(13, 17)
		local depth = 22
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
				local shop = SHOPS.Market[(ringIndex - 1) % #SHOPS.Market + 1]
				block(string.format("SquareRing%02d", ringIndex), x, z, width, depth, 3, {
					yaw = yaw,
					door = "South",
					use = if shop == "Tavern" then "Tavern" elseif shop == "Blacksmith" then "Smithy" else "Shop",
					shop = shop,
					name = shopName(shop),
					style = "Market",
					access = "Npc",
					district = "MerchantSquare",
					open = { South = true, North = true },
				})
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
	bounds = BOUNDS,
	walls = { thickness = WALL_THICKNESS, height = 30, towerSpacing = 120 },
	door = { width = 6, height = 9 },
	gates = ({
		{ id = "SouthGate", locationId = "SouthGate", center = { 0, BOUNDS.maxZ }, width = 24, kind = "Land" },
		{ id = "NorthGate", locationId = "NorthGate", center = { 300, BOUNDS.minZ }, width = 20, kind = "Land" },
		{ id = "SeaGate", center = { BOUNDS.maxX, 100 }, width = 80, kind = "Sea" },
	} :: {any}),
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
