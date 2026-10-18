--!strict
-- Greybox layout of the capital (L-27). Footprints in studs on the X/Z plane; north is -Z, the southern
-- forest lies beyond the south gate (+Z). Placeholder geometry for scale and navigation only.
-- Built by Server.Tools.GreyboxBuilder; checked offline by Server.Domain.LayoutRules (no overlaps,
-- inside the walls, gates on the wall, every location and property placed exactly once).
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

local blocks = {}
local function block(id: string, x: number, z: number, width: number, depth: number, height: number, fields: any)
	local entry = { id = id, center = { x, z }, size = { width, depth }, height = height }
	for key, value in pairs(fields) do
		entry[key] = value
	end
	table.insert(blocks, entry)
end

-- Merchant square and its edges
block("HeartOfRealms", 0, 0, 16, 16, 28, { locationId = "HeartOfRealms", shape = "Crystal" })
block("MarketStalls", 0, 45, 120, 10, 4, { locationId = "MarketStalls" })
block("SquareInn", 115, 0, 40, 40, 22, { locationId = "SquareInn", door = "West" })
block("AdventurersGuild", -115, 0, 40, 40, 24, { locationId = "AdventurersGuild", door = "East" })
block("ThievesGuildEntrance", 115, 40, 6, 6, 1, { locationId = "ThievesGuildEntrance", hidden = true })
block("Church", -60, -110, 50, 60, 40, { locationId = "Church", door = "East" })

-- Royal castle (walls leave a 20-stud gate in the south wall, facing the castle road)
block("CastleKeep", 0, -250, 80, 60, 50, { locationId = "ThroneRoom", door = "South" })
block("CastleWallNorth", 0, -298, 172, 4, 20, { kind = "Wall" })
block("CastleWallWest", -88, -235, 4, 130, 20, { kind = "Wall" })
block("CastleWallEast", 88, -235, 4, 130, 20, { kind = "Wall" })
block("CastleWallSouthWest", -48, -172, 76, 4, 20, { kind = "Wall" })
block("CastleWallSouthEast", 48, -172, 76, 4, 20, { kind = "Wall" })

-- Craftsman quarter, on the way to the north gate
block("CityForge", 160, -200, 40, 30, 18, { locationId = "CityForge", door = "East" })
block("CityApothecary", 240, -200, 30, 30, 16, { locationId = "CityApothecary", door = "West" })
block("CraftsmensGuild", 255, -140, 40, 30, 20, { locationId = "CraftsmensGuild", door = "West" })

-- Noble quarter: large houses, outside the castle walls
for index, spot in ipairs({ { -250, -140 }, { -180, -140 }, { -250, -210 }, { -180, -210 } }) do
	local id = string.format("NobleHouse%02d", index)
	block(id, spot[1], spot[2], 40, 40, 24, { propertyId = id, door = "South" })
end

-- Player storefronts on both sides of the south road
local storefronts = { { -40, 100, "East" }, { 40, 100, "West" }, { -40, 140, "East" }, { 40, 140, "West" }, { -40, 180, "East" }, { 40, 180, "West" } }
for index, spot in ipairs(storefronts) do
	local id = string.format("Storefront%02d", index)
	block(id, spot[1], spot[2], 28, 28, 18, { propertyId = id, door = spot[3] })
end
-- Guild halls (L-54), each with a planning table inside.
for index, spot in ipairs({ { 160, 110 }, { 240, 110 }, { 200, 200 } }) do
	local id = string.format("GuildHall%02d", index)
	block(id, spot[1], spot[2], 40, 34, 22, { propertyId = id, door = "South" })
end

-- Slums: small houses with narrow alleys
local slumIndex = 0
for _, z in ipairs({ 160, 190 }) do
	for _, x in ipairs({ -280, -255, -230, -205 }) do
		slumIndex += 1
		local id = string.format("SlumHouse%02d", slumIndex)
		block(id, x, z, 16, 16, 12, { propertyId = id, door = "South" })
	end
end

return Table.deepFreeze({
	walls = { halfSize = 320, thickness = 8, height = 30 },
	door = { width = 6, height = 9 },
	gates = {
		{ id = "SouthGate", locationId = "SouthGate", center = { 0, 320 }, width = 24 },
		{ id = "NorthGate", locationId = "NorthGate", center = { 200, -320 }, width = 20 },
	},
	ground = {
		{ id = "FineryStall", center = { 36, 30 }, size = { 16, 12 }, locationId = "FineryStall" },
		{ id = "ChurchSteps", center = { -27, -110 }, size = { 14, 24 }, locationId = "ChurchSteps" },
		{ id = "ChurchAlley", center = { -120, -115 }, size = { 40, 50 }, locationId = "ChurchAlley" },
		{ id = "MerchantSquarePlaza", center = { 0, 0 }, size = { 160, 120 } },
		{ id = "CastleCourtyardGround", center = { 0, -195 }, size = { 172, 46 }, locationId = "CastleCourtyard" },
	},
	roads = {
		{ id = "SouthRoad", center = { 0, 186 }, size = { 24, 252 } },
		{ id = "CastleRoad", center = { 0, -115 }, size = { 20, 110 } },
		{ id = "EastRoad", center = { 145, -70 }, size = { 130, 20 } },
		{ id = "CraftsmanRoad", center = { 200, -155 }, size = { 20, 150 } },
		{ id = "NorthRoad", center = { 200, -271 }, size = { 20, 82 } },
		{ id = "NobleRoad", center = { -180, -70 }, size = { 200, 20 } },
		{ id = "SlumRoad", center = { -146, 225 }, size = { 268, 16 } },
	},
	blocks = blocks,
	spawn = { center = { 0, -35 } },
	-- Placeholder NPCs, tagged "Npc" by the builder; DialogueService gives each a Talk prompt.
	npcs = {
		{ npcId = "TheKing", at = { 0, -262 } },
		{ npcId = "OldScholar", at = { 0, 14 } },
		{ npcId = "GuildRegistrar", at = { -120, 0 } },
		{ npcId = "PartyClerk", at = { -110, 10 } },
		{ npcId = "GuildSteward", at = { 260, -140 } },
		{ npcId = "ForgeMaster", at = { 155, -205 } },
		{ npcId = "Apothecary", at = { 240, -205 } },
		{ npcId = "ChurchPriest", at = { -70, -120 } },
		{ npcId = "Innkeeper", at = { 120, 5 } },
		{ npcId = "WearyStranger", at = { -26, -104 } },
		{ npcId = "Hunter", at = { 16, 296 } },
		{ npcId = "Clothier", at = { 36, 32 } },
		{ npcId = "HeartCrystal", at = { 0, -11 } },
	},
	-- Opening markers (L-43): where new characters appear, the ritual circle, and the starting chest.
	markers = {
		{ id = "ChurchSpawn", kind = "SpawnPoint", spawnId = "Church", at = { -72, -132 }, inside = "Church" },
		{ id = "AwakeningCircle", kind = "RitualCircle", at = { -60, -110 }, inside = "Church" },
		{ id = "StarterChest", kind = "StarterChest", at = { -42, -96 }, inside = "Church" },
		{ id = "GuildHall01Table", kind = "PlanningTable", at = { 160, 106 }, inside = "GuildHall01", propertyId = "GuildHall01" },
		{ id = "GuildHall02Table", kind = "PlanningTable", at = { 240, 106 }, inside = "GuildHall02", propertyId = "GuildHall02" },
		{ id = "GuildHall03Table", kind = "PlanningTable", at = { 200, 196 }, inside = "GuildHall03", propertyId = "GuildHall03" },
	},
})
