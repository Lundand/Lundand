--!strict
-- Quest definitions (L-30, L-44). Quests are found by talking to NPCs; nothing marks who offers one (L-42).
-- Fields: id, displayName, description (for the journal), giver (NPC ID), chain (questline), main (main
-- story), requires { characterLevel, quests, flags }, objectives, rewards { gold, characterXp,
-- professionXp }, repeatCooldownSeconds (repeatable), guidance (a brief hint toward a place on accepting).
-- Objective kinds: Talk (NPC ID), Gather (item ID), Kill (enemy ID), Craft (recipe ID) progress from server
-- events; Deliver (item ID) is checked at turn-in and the items are taken then. Values are placeholders.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- The opening (L-43)
	TheStolenBelongings = {
		id = "TheStolenBelongings",
		displayName = "The Stolen Belongings",
		description = "Thieves took the little a weary stranger had left. They were last seen in the alley behind the church.",
		giver = "WearyStranger",
		chain = "Opening",
		requires = { characterLevel = 1, quests = {}, flags = { "Awakened" } },
		objectives = {
			{ id = "Thieves", kind = "Kill", target = "AlleyThief", count = 3 },
		},
		rewards = { gold = 20, characterXp = 80 },
		guidance = { locationId = "ChurchAlley", seconds = 15 },
	},

	-- Main story
	TheCrystalsUnease = {
		id = "TheCrystalsUnease",
		displayName = "The Crystal's Unease",
		description = "The King wants to hear what the Old Scholar believes about the flickering runes on the Heart of Realms.",
		giver = "TheKing",
		chain = "MainChapter1",
		main = true,
		requires = { characterLevel = 1, quests = { "AdventurerRegistration" } },
		objectives = {
			{ id = "HearTheLegend", kind = "Talk", target = "OldScholar", count = 1 },
		},
		rewards = { gold = 30, characterXp = 150 },
	},

	-- Adventurers' Guild
	AdventurerRegistration = {
		id = "AdventurerRegistration",
		displayName = "Register at the Adventurers' Guild",
		description = "Put my name in the Adventurers' Guild ledger.",
		giver = "GuildRegistrar",
		chain = "AdventurersGuild",
		requires = { characterLevel = 1, quests = {} },
		objectives = {
			{ id = "Register", kind = "Talk", target = "GuildRegistrar", count = 1 },
		},
		rewards = { gold = 25, characterXp = 50 },
	},
	BountyForestPests = {
		id = "BountyForestPests",
		displayName = "Bounty: Forest Pests",
		description = "The Guild pays for wolves culled along the southern road.",
		giver = "GuildRegistrar",
		requires = { characterLevel = 1, quests = { "AdventurerRegistration" } },
		objectives = {
			{ id = "Wolves", kind = "Kill", target = "ForestWolf", count = 5 },
		},
		rewards = { gold = 40, characterXp = 120 },
		repeatCooldownSeconds = 3600,
	},
	BountyHerbBundle = {
		id = "BountyHerbBundle",
		displayName = "Bounty: Herbs for the Infirmary",
		description = "The Guild infirmary buys bundles of healing herbs.",
		giver = "GuildRegistrar",
		requires = { characterLevel = 1, quests = { "AdventurerRegistration" } },
		objectives = {
			{ id = "Herbs", kind = "Deliver", target = "HealingHerb", count = 6 },
		},
		rewards = { gold = 30, characterXp = 60 },
		repeatCooldownSeconds = 3600,
	},
	BountyCopperRun = {
		id = "BountyCopperRun",
		displayName = "Bounty: Copper for the Armoury",
		description = "The Guild armoury needs copper ore.",
		giver = "GuildRegistrar",
		requires = { characterLevel = 1, quests = { "AdventurerRegistration" } },
		objectives = {
			{ id = "Copper", kind = "Deliver", target = "CopperOre", count = 8 },
		},
		rewards = { gold = 35, characterXp = 60 },
		repeatCooldownSeconds = 3600,
	},

	-- Guild contracts (L-48): for members of a player guild; they earn guild XP, the only way guilds level.
	ContractWolfCulling = {
		id = "ContractWolfCulling",
		displayName = "Guild Contract: Wolf Culling",
		description = "The Adventurers' Guild hires player guilds to keep the forest road safe. Your guild earns standing for every pack thinned.",
		giver = "GuildRegistrar",
		requires = { characterLevel = 2, quests = {}, inGuild = true },
		objectives = {
			{ id = "Wolves", kind = "Kill", target = "ForestWolf", count = 6 },
		},
		rewards = { gold = 20, characterXp = 80, guildXp = 150 },
		repeatCooldownSeconds = 86400,
	},
	ContractOreForTheHalls = {
		id = "ContractOreForTheHalls",
		displayName = "Guild Contract: Ore for the Halls",
		description = "The city's masons need copper for repairs. Guilds that supply it earn the Crown's gratitude.",
		giver = "GuildRegistrar",
		requires = { characterLevel = 1, quests = {}, inGuild = true },
		objectives = {
			{ id = "Ore", kind = "Deliver", target = "CopperOre", count = 15 },
		},
		rewards = { gold = 15, characterXp = 50, guildXp = 120 },
		repeatCooldownSeconds = 86400,
	},

	-- Craftsmen's Guild
	CraftsmenIntroForge = {
		id = "CraftsmenIntroForge",
		displayName = "The Forge's Apprentice",
		description = "Gather copper and logs and meet the Forge Master to earn a place at the city forge.",
		giver = "GuildSteward",
		chain = "Craftsmen",
		requires = { characterLevel = 1, quests = {} },
		objectives = {
			{ id = "MineCopper", kind = "Gather", target = "CopperOre", count = 4 },
			{ id = "BringLogs", kind = "Deliver", target = "OakLog", count = 2 },
			{ id = "MeetSmith", kind = "Talk", target = "ForgeMaster", count = 1 },
		},
		rewards = { gold = 15, professionXp = { Blacksmithing = 30 } },
	},
	CraftsmenIntroBrewing = {
		id = "CraftsmenIntroBrewing",
		displayName = "Herbs and Tinctures",
		description = "Pick healing herbs and meet the Apothecary to earn a place at her workbench.",
		giver = "GuildSteward",
		chain = "Craftsmen",
		requires = { characterLevel = 1, quests = {} },
		objectives = {
			{ id = "PickHerbs", kind = "Gather", target = "HealingHerb", count = 4 },
			{ id = "MeetAlchemist", kind = "Talk", target = "Apothecary", count = 1 },
		},
		rewards = { gold = 15, professionXp = { Alchemy = 30 } },
	},

	-- Side stories: other ways to earn experience
	HerbsForTheHealer = {
		id = "HerbsForTheHealer",
		displayName = "Herbs for the Healer",
		description = "The priest tends the sick of the slums and is short of healing herbs.",
		giver = "ChurchPriest",
		requires = { characterLevel = 1, quests = {}, flags = { "Awakened" } },
		objectives = {
			{ id = "Herbs", kind = "Deliver", target = "HealingHerb", count = 5 },
		},
		rewards = { gold = 15, characterXp = 60, professionXp = { Harvesting = 20 } },
	},
	HuntersRequest = {
		id = "HuntersRequest",
		displayName = "The Hunter's Request",
		description = "A hunter at the south gate wants help thinning the wolves that stalk the forest road.",
		giver = "Hunter",
		requires = { characterLevel = 2, quests = {}, flags = { "Awakened" } },
		objectives = {
			{ id = "Wolves", kind = "Kill", target = "ForestWolf", count = 4 },
		},
		rewards = { gold = 25, characterXp = 120 },
	},
	-- The Southern Woods (the Hunter at the South Gate)
	PeltsForTheHunter = {
		id = "PeltsForTheHunter",
		displayName = "Pelts for the Hunter",
		description = "The Hunter needs wolf pelts to mend his gear before winter.",
		giver = "Hunter",
		requires = { characterLevel = 2, quests = { "HuntersRequest" } },
		objectives = {
			{ id = "Pelts", kind = "Deliver", target = "WolfPelt", count = 4 },
		},
		rewards = { gold = 30, characterXp = 80 },
	},
	TheBoarProblem = {
		id = "TheBoarProblem",
		displayName = "The Boar Problem",
		description = "Wild boars are tearing up the forest road. Drive three of them off for good.",
		giver = "Hunter",
		requires = { characterLevel = 3, quests = { "HuntersRequest" } },
		objectives = {
			{ id = "Boars", kind = "Kill", target = "WildBoar", count = 3 },
		},
		rewards = { gold = 25, characterXp = 90 },
	},
	AlphaOfTheWoods = {
		id = "AlphaOfTheWoods",
		displayName = "Alpha of the Woods",
		description = "A great wolf leads the packs from a den deep in the woods. End its reign.",
		giver = "Hunter",
		requires = { characterLevel = 6, quests = { "TheBoarProblem" } },
		objectives = {
			{ id = "Alpha", kind = "Kill", target = "WolfAlpha", count = 1 },
		},
		rewards = { gold = 80, characterXp = 300 },
	},
	-- The criminal hideout under the slums (rumours at the inn)
	TroubleInTheSlums = {
		id = "TroubleInTheSlums",
		displayName = "Trouble in the Slums",
		description = "Thugs have been shaking down the slum folk. Teach three of them a lesson.",
		giver = "Innkeeper",
		requires = { characterLevel = 4, quests = {  } },
		objectives = {
			{ id = "Thugs", kind = "Kill", target = "StreetThug", count = 3 },
		},
		rewards = { gold = 30, characterXp = 110 },
	},
	TheCellarGang = {
		id = "TheCellarGang",
		displayName = "The Cellar Gang",
		description = "The thugs answer to an enforcer who keeps to the cellars beneath the slums. Find him.",
		giver = "Innkeeper",
		requires = { characterLevel = 9, quests = { "TroubleInTheSlums" } },
		objectives = {
			{ id = "Enforcer", kind = "Kill", target = "CriminalEnforcer", count = 1 },
		},
		rewards = { gold = 60, characterXp = 260 },
	},
	TheHideoutLeader = {
		id = "TheHideoutLeader",
		displayName = "The Hideout Leader",
		description = "Whoever runs the hideout has the slums by the throat. Break their hold.",
		giver = "Innkeeper",
		requires = { characterLevel = 12, quests = { "TheCellarGang" } },
		objectives = {
			{ id = "Leader", kind = "Kill", target = "HideoutLeader", count = 1 },
		},
		rewards = { gold = 150, characterXp = 900 },
	},
})
