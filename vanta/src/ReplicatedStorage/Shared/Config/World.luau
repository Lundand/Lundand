--!strict
-- Stable IDs for the capital and its connections (L-27 to L-30). World geometry in Studio carries these
-- IDs as attributes (LocationId, PropertyId); gameplay never depends on model names or hierarchy.
-- Property counts are placeholders until O-10.
local Table = require(script.Parent.Parent.Util.Table)

local properties = {}
local function addProperties(prefix: string, kind: string, district: string, tier: string, count: number)
	for index = 1, count do
		local id = string.format("%s%02d", prefix, index)
		properties[id] = { id = id, kind = kind, district = district, tier = tier }
	end
end
addProperties("NobleHouse", "House", "NobleQuarter", "Noble", 4)
addProperties("SlumHouse", "House", "Slums", "Modest", 8)
addProperties("Storefront", "Shop", "MerchantSquare", "Market", 6) -- player shops (L-53, L-54)
addProperties("GuildHall", "GuildHall", "CraftsmanQuarter", "Hall", 3) -- one per guild, from guild level 5 (L-54)

return Table.deepFreeze({
	districts = {
		MerchantSquare = { id = "MerchantSquare", displayName = "Merchant Square" },
		Castle = { id = "Castle", displayName = "Royal Castle" },
		NobleQuarter = { id = "NobleQuarter", displayName = "Noble Quarter" },
		Slums = { id = "Slums", displayName = "The Slums" },
		CraftsmanQuarter = { id = "CraftsmanQuarter", displayName = "Craftsman Quarter" },
		CityWalls = { id = "CityWalls", displayName = "City Walls" },
	},
	locations = {
		HeartOfRealms = { id = "HeartOfRealms", district = "MerchantSquare", kind = "Landmark" }, -- the crystal (docs/LORE.md)
		Church = { id = "Church", district = "MerchantSquare", kind = "Church" },
		ChurchSteps = { id = "ChurchSteps", displayName = "Church Steps", district = "MerchantSquare", kind = "Landmark" },
		FineryStall = { id = "FineryStall", displayName = "Silk and Silver", district = "MerchantSquare", kind = "Shop" },
		ChurchAlley = { id = "ChurchAlley", displayName = "Alley behind the Church", district = "MerchantSquare", kind = "Alley" },
		SquareInn = { id = "SquareInn", district = "MerchantSquare", kind = "Inn" },
		MarketStalls = { id = "MarketStalls", district = "MerchantSquare", kind = "Market" },
		AdventurersGuild = { id = "AdventurersGuild", district = "MerchantSquare", kind = "NpcGuild", guildId = "Adventurers" },
		ThievesGuildEntrance = {
			id = "ThievesGuildEntrance",
			district = "MerchantSquare",
			kind = "NpcGuild",
			guildId = "Thieves",
			hidden = true,
		},
		CraftsmensGuild = { id = "CraftsmensGuild", district = "CraftsmanQuarter", kind = "NpcGuild", guildId = "Craftsmen" },
		CityForge = { id = "CityForge", district = "CraftsmanQuarter", kind = "CraftingFacility", facilityId = "CityBlacksmith" },
		CityApothecary = { id = "CityApothecary", district = "CraftsmanQuarter", kind = "CraftingFacility", facilityId = "CityAlchemist" },
		CastleCourtyard = { id = "CastleCourtyard", district = "Castle", kind = "Royal" },
		ThroneRoom = { id = "ThroneRoom", district = "Castle", kind = "Royal" },
		SouthGate = { id = "SouthGate", district = "CityWalls", kind = "CityGate", leadsTo = "SouthernForest" },
		NorthGate = { id = "NorthGate", district = "CityWalls", kind = "CityGate", leadsTo = "NorthernMountains" },
	},
	npcGuilds = {
		Adventurers = { id = "Adventurers", displayName = "Adventurers' Guild", locationId = "AdventurersGuild" },
		Craftsmen = { id = "Craftsmen", displayName = "Craftsmen's Guild", locationId = "CraftsmensGuild" },
		Thieves = { id = "Thieves", displayName = "(hidden)", locationId = "ThievesGuildEntrance", hidden = true },
	},
	inns = {
		SquareInn = { id = "SquareInn", locationId = "SquareInn" },
	},
	regions = {
		SouthernForest = { id = "SouthernForest", displayName = "Southern Forest", place = "Main", available = true },
		NorthernMountains = {
			id = "NorthernMountains",
			displayName = "Northern Mountains",
			place = "NorthernMountains",
			available = false,
		},
	},
	properties = properties,
})
