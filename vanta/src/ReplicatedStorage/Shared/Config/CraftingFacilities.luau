--!strict
-- Crafting facilities (L-31). One crafting system; facilities differ only by configuration. NPC
-- facilities need a short introduction quest, charge a fee and are the least efficient. Player
-- workshops (kind PlayerWorkshop) and guild facilities (kind GuildFacility) arrive later.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	CityBlacksmith = {
		id = "CityBlacksmith",
		displayName = "City Forge",
		kind = "Npc",
		locationId = "CityForge",
		processes = { Forging = true },
		recipes = { TrainingSword = true, CopperPickaxe = true, IronPickaxe = true, LeatherJerkin = true, RustyDagger = true, IronHelm = true, FangDagger = true, SignetBlade = true, MountainGuardLongsword = true,
			CutpursesShortsword = true, WatchmansSword = true, BanditsSaber = true, IronwroughtBastardSword = true, GoblinHookblade = true,
			SilverwroughtRapier = true, ApprenticeStaff = true, TrainingMace = true, WornKnuckles = true, HuntingBow = true, CopperHatchet = true,
			IronSpear = true, IronGreataxe = true, OakShield = true, ApprenticeRobe = true },
		fee = 10,
		qualityBonus = 0,
		unlockQuest = "CraftsmenIntroForge",
	},
	CityAlchemist = {
		id = "CityAlchemist",
		displayName = "City Apothecary",
		kind = "Npc",
		locationId = "CityApothecary",
		processes = { Brewing = true },
		recipes = { MinorHealthPotion = true },
		fee = 5,
		qualityBonus = 0,
		unlockQuest = "CraftsmenIntroBrewing",
	},
})
