--!strict
-- Item definitions (T-11). Placeholder content for the first forest; names and values are tunable.
-- Tool, Equipment and ClassBook items are unique instances; everything else stacks.
local Table = require(script.Parent.Parent.Util.Table)

local function material(id: string, displayName: string, tier: number, rarity: string, tags: {string})
	return {
		id = id,
		displayName = displayName,
		kind = "Material",
		maxStack = 99,
		tier = tier,
		rarity = rarity,
		binding = "None",
		tradable = true,
		vendorValue = tier * 2,
		tags = tags,
	}
end

return Table.deepFreeze({
	HealingHerb = material("HealingHerb", "Healing Herb", 1, "Common", { "Herb", "Region.SouthernForest" }),
	CaveMushroom = material("CaveMushroom", "Cave Mushroom", 1, "Common", { "Herb", "Cave" }),
	OakLog = material("OakLog", "Oak Log", 1, "Common", { "Wood", "Region.SouthernForest" }),
	CopperOre = material("CopperOre", "Copper Ore", 1, "Common", { "Ore" }),
	IronOre = material("IronOre", "Iron Ore", 2, "Common", { "Ore" }),
	SilverOre = material("SilverOre", "Silver Ore", 3, "Uncommon", { "Ore" }),
	-- Monster materials (world specification), each used by a forge recipe
	WolfPelt = material("WolfPelt", "Wolf Pelt", 1, "Common", { "Hide" }),
	WolfFang = material("WolfFang", "Wolf Fang", 1, "Common", { "Fang" }),
	BoarHide = material("BoarHide", "Boar Hide", 1, "Common", { "Hide" }),
	LeatherScraps = material("LeatherScraps", "Leather Scraps", 1, "Common", { "Hide" }),
	ScrapMetal = material("ScrapMetal", "Scrap Metal", 1, "Common", { "Metal" }),
	AlphaFang = material("AlphaFang", "Alpha Fang", 2, "Uncommon", { "Fang", "Trophy" }),
	LeaderSignet = material("LeaderSignet", "Leader's Signet", 3, "Rare", { "Trophy" }),
	MinorHealthPotion = {
		id = "MinorHealthPotion",
		displayName = "Minor Health Potion",
		kind = "Consumable",
		maxStack = 20,
		tier = 1,
		rarity = "Common",
		binding = "None",
		tradable = true,
		vendorValue = 10,
		tags = { "Potion" },
	},
	CopperPickaxe = {
		id = "CopperPickaxe",
		displayName = "Copper Pickaxe",
		kind = "Tool",
		maxStack = 1,
		tier = 1,
		rarity = "Common",
		binding = "None",
		tradable = true,
		vendorValue = 20,
		tool = { toolType = "Pickaxe", toolTier = 1 },
	},
	IronPickaxe = {
		id = "IronPickaxe",
		displayName = "Iron Pickaxe",
		kind = "Tool",
		maxStack = 1,
		tier = 2,
		rarity = "Common",
		binding = "None",
		tradable = true,
		vendorValue = 60,
		tool = { toolType = "Pickaxe", toolTier = 2 },
	},
	CopperHatchet = {
		id = "CopperHatchet",
		displayName = "Copper Hatchet",
		kind = "Tool",
		maxStack = 1,
		tier = 1,
		rarity = "Common",
		binding = "None",
		tradable = true,
		vendorValue = 20,
		tool = { toolType = "Axe", toolTier = 1 },
	},
	TrainingSword = {
		id = "TrainingSword",
		stats = { attackPower = 5 }, -- placeholder until the combat model (M3); the weakest sword (L-43)
		displayName = "Training Sword",
		kind = "Equipment",
		maxStack = 1,
		tier = 1,
		rarity = "Common",
		binding = "None",
		tradable = true,
		vendorValue = 15,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "ArmingSword" },
		noDrop = true, -- starter and smith's work; never a random drop
		description = "A plain practice blade. Every swordsman starts somewhere.",
	},

	-- Sword progression, levels 1-22 (WEAPON_PROGRESSION_PLAN.md). Each sword has its own subtype handling (speed, reach,
	-- damage from Config.Gear), a secondary bonus, and a source; named swords carry a trait. drop.sources: the loot tables or
	-- enemy ids that can drop it; named drops roll their own chance and keep a fixed rarity.
	CutpursesShortsword = {
		id = "CutpursesShortsword", displayName = "Cutpurse's Shortsword", kind = "Equipment", tier = 1, rarity = "Common", itemLevel = 4,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 20,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "ShortSword" }, stats = { attackPower = 5 }, bonuses = { attackSpeed = 0.03 },
		drop = { sources = { "Thieves" } },
		description = "Short, light and quick: the alley thieves' favourite. Fast strikes, a little less bite.",
	},
	WatchmansSword = {
		id = "WatchmansSword", displayName = "Watchman's Sword", kind = "Equipment", tier = 1, rarity = "Common", itemLevel = 8,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 30,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "ArmingSword" }, stats = { attackPower = 6 }, bonuses = { maxHealth = 0.04 },
		noDrop = true, -- sold by the Forge Master
		description = "Issued to the city watch. Dependable, balanced, and sold at the forge.",
	},
	BanditsSaber = {
		id = "BanditsSaber", displayName = "Bandit's Saber", kind = "Equipment", tier = 1, rarity = "Common", itemLevel = 12,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 35,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "Saber" }, stats = { attackPower = 6 }, bonuses = { staminaRegen = 0.03 },
		drop = { sources = { "Bandits" } },
		description = "A curved raider's blade made for fighting on the move. Quick, and easy on the wind.",
	},
	EnforcersLongsword = {
		id = "EnforcersLongsword", displayName = "Enforcer's Longsword", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 10,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 80,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "Longsword" }, stats = { attackPower = 6.5 }, bonuses = { physicalDamage = 0.05 },
		trait = { on = "Combo3", staggers = true, text = "Your combo finisher staggers the target." },
		drop = { sources = { "CriminalEnforcer" }, named = true, chance = 0.03 },
		description = "The criminal enforcer's own long blade, built to end a fight on the third cut.",
	},
	GoblinHookblade = {
		id = "GoblinHookblade", displayName = "Goblin Hookblade", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 19,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 60,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "Scimitar" }, stats = { attackPower = 7.5 }, bonuses = { attackSpeed = 0.04 },
		drop = { sources = { "Goblins" } },
		description = "A wicked, back-curved goblin blade. Ugly, fast, and meaner than it looks.",
	},
	IronwroughtBastardSword = {
		id = "IronwroughtBastardSword", displayName = "Ironwrought Bastard Sword", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 14,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 70,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "BastardSword" }, stats = { attackPower = 7 }, bonuses = { physicalDamage = 0.04 },
		noDrop = true, -- crafted: the first heavy sword a smith can make from mountain iron
		description = "A smith's first heavy blade of mountain iron. Slow, long, and it lands hard.",
	},
	MountainGuardLongsword = {
		id = "MountainGuardLongsword", displayName = "Mountain Guard Longsword", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 22,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 110,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "Longsword" }, stats = { attackPower = 8 }, bonuses = { maxHealth = 0.06 },
		noDrop = true, -- forged by blacksmiths from mountain iron
		description = "Forged for the guards of the mountain passes from good mountain iron. Long reach, steady hand.",
	},
	TrollSplitter = {
		id = "TrollSplitter", displayName = "Troll-Splitter", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 25,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 160,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "BastardSword" }, stats = { attackPower = 8.5 }, bonuses = { physicalDamage = 0.06 },
		trait = { on = "Hit", chance = 0.2, staggers = true, text = "Each hit has a 20% chance to stagger." },
		drop = { sources = { "MountainTroll" }, named = true, chance = 0.03 },
		description = "Pried from the mountain troll's hoard. Heavy enough to rock a troll back on its heels.",
	},
	SilverwroughtRapier = {
		id = "SilverwroughtRapier", displayName = "Silverwrought Rapier", kind = "Equipment", tier = 3, rarity = "Common", itemLevel = 27,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 220,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "Rapier" }, stats = { attackPower = 8.5 }, bonuses = { attackSpeed = 0.06 },
		noDrop = true, -- crafted from goblin-cave silver
		description = "A slender blade of silver-hardened steel. Lightning-quick thrusts that find every gap.",
	},
	WarlordsEdge = {
		id = "WarlordsEdge", displayName = "Warlord's Edge", kind = "Equipment", tier = 3, rarity = "Common", itemLevel = 30,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 300,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "KnightsSword" }, stats = { attackPower = 9 }, bonuses = { physicalDamage = 0.08, maxHealth = 0.05 },
		trait = { on = "Heavy", mark = { bonus = 0.15, seconds = 6, hits = 2 }, text = "Heavy Strike marks the target: your next 2 hits on it deal 15% more." },
		drop = { sources = { "MountainWarlord" }, named = true, chance = 0.05 },
		description = "The mountain warlord's sword of command. Its first blow marks who falls next.",
	},
	LegendaryBookPlaceholder = {
		id = "LegendaryBookPlaceholder",
		displayName = "Legendary Class Book (placeholder)",
		kind = "ClassBook",
		maxStack = 1,
		tier = 5,
		rarity = "Legendary",
		binding = "None",
		tradable = true,
		vendorValue = 0,
		developmentOnly = true,
		classBook = { classId = "PlaceholderLegendary" },
	},
	ApprenticeStaff = {
		id = "ApprenticeStaff", displayName = "Apprentice Staff", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 15,
		equipment = { slot = "MainHand", weaponType = "Staff" }, stats = { attackPower = 4 },
	},
	TrainingMace = {
		id = "TrainingMace", displayName = "Training Mace", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 15,
		equipment = { slot = "MainHand", weaponType = "Mace" }, stats = { attackPower = 6 },
	},
	OakShield = {
		id = "OakShield", displayName = "Oak Shield", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 12,
		equipment = { slot = "OffHand", weaponType = "Shield" }, stats = { defense = 3 },
	},
	HuntingBow = {
		id = "HuntingBow", displayName = "Hunting Bow", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 15,
		equipment = { slot = "MainHand", weaponType = "Bow" }, stats = { attackPower = 5 },
	},
	RustyDagger = {
		id = "RustyDagger", displayName = "Rusty Dagger", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 12,
		equipment = { slot = "MainHand", weaponType = "Dagger" }, stats = { attackPower = 4 },
	},
	WornKnuckles = {
		id = "WornKnuckles", displayName = "Worn Knuckles", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 12,
		equipment = { slot = "MainHand", weaponType = "Fist" }, stats = { attackPower = 4 },
	},
	IronGreataxe = {
		id = "IronGreataxe", displayName = "Iron Greataxe", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 20,
		equipment = { slot = "MainHand", weaponType = "Greataxe" }, stats = { attackPower = 9 },
	},
	IronSpear = {
		id = "IronSpear", displayName = "Iron Spear", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 18,
		equipment = { slot = "MainHand", weaponType = "Spear" }, stats = { attackPower = 7 },
	},
	VoidSwordmasterBook = {
		id = "VoidSwordmasterBook", displayName = "Codex of the Severed Void", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "VoidSwordmaster" },
	},
	LichLordBook = {
		id = "LichLordBook", displayName = "Grimoire of the Pale Throne", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "LichLord" },
	},
	WorldbreakerBerserkerBook = {
		id = "WorldbreakerBerserkerBook", displayName = "Saga of the Worldbreaker", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "WorldbreakerBerserker" },
	},
	AstralArchmageBook = {
		id = "AstralArchmageBook", displayName = "Atlas of Fallen Stars", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "AstralArchmage" },
	},
	SeraphicGuardianBook = {
		id = "SeraphicGuardianBook", displayName = "Oath of the Seraphim", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "SeraphicGuardian" },
	},
	NightSovereignBook = {
		id = "NightSovereignBook", displayName = "Ledger of the Night Court", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "NightSovereign" },
	},
	DragonbloodKnightBook = {
		id = "DragonbloodKnightBook", displayName = "Chronicle of Dragon Blood", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "DragonbloodKnight" },
	},
	ChronomancerBook = {
		id = "ChronomancerBook", displayName = "Hourglass Codex", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "Chronomancer" },
	},
	ThunderSovereignBook = {
		id = "ThunderSovereignBook", displayName = "Spear-Writ of the Thunder King", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "ThunderSovereign" },
	},
	WorldrootSageBook = {
		id = "WorldrootSageBook", displayName = "Bark-Scroll of the Worldroot", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "WorldrootSage" },
	},
	AbyssalWarlockBook = {
		id = "AbyssalWarlockBook", displayName = "Pact of the Abyss", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "AbyssalWarlock" },
	},
	BladeEmperorBook = {
		id = "BladeEmperorBook", displayName = "Edicts of the Blade Emperor", kind = "ClassBook", tier = 5, rarity = "Legendary",
		maxStack = 1, binding = "None", tradable = false, vendorValue = 0,
		classBook = { classId = "BladeEmperor" },
	},
	-- Representative starter armour, one piece per weight (owner's equipment specification; full sets later).
	IronHelm = {
		id = "IronHelm", displayName = "Iron Helm", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 14,
		equipment = { slot = "Head", armorWeight = "Heavy" }, stats = { defense = 6 },
	},
	LeatherJerkin = {
		id = "LeatherJerkin", displayName = "Leather Jerkin", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 12,
		equipment = { slot = "Chest", armorWeight = "Medium" }, stats = { defense = 5 },
	},
	ApprenticeRobe = {
		id = "ApprenticeRobe", displayName = "Apprentice Robe", kind = "Equipment", tier = 1, rarity = "Common",
		maxStack = 1, binding = "None", tradable = true, vendorValue = 12,
		equipment = { slot = "Chest", armorWeight = "Light" }, stats = { defense = 3 },
	},
	FangDagger = {
		id = "FangDagger", displayName = "Fang Dagger", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 8,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 40,
		equipment = { slot = "MainHand", weaponType = "Dagger" }, stats = { attackPower = 6 },
	},
	SignetBlade = {
		id = "SignetBlade", displayName = "Signet Blade", kind = "Equipment", tier = 2, rarity = "Common", itemLevel = 16,
		maxStack = 1, binding = "None", tradable = true, vendorValue = 90,
		equipment = { slot = "MainHand", weaponType = "Sword", subtype = "KnightsSword" }, stats = { attackPower = 8 }, bonuses = { physicalDamage = 0.05 },
		noDrop = true, -- forged from the Hideout Leader's signet
		description = "Forged around the Hideout Leader's signet: a knight's blade that hits harder than its size.",
	},
})
