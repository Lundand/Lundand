--!strict
-- Equipment progression and catalogue (owner's equipment specification). Item level and rarity: an item's base stats
-- grow with its item level and are scaled by its rarity, so rarity improves an item relative to others of its level
-- without erasing item level (a Common level 40 sword beats a Rare level 20 one). Weapon families and subtypes carry
-- handling profiles (attack speed, reach, damage); armour comes in three weights. Values are placeholders to balance.
local Table = require(script.Parent.Parent.Util.Table)

-- speed, reach and damage relative to the family's standard weapon
local function h(speed: number, reach: number, damage: number): any
	return { speed = speed, reach = reach, damage = damage }
end

return Table.deepFreeze({
	levelCap = 60,
	bands = {
		{ name = "Starter", from = 1, to = 10 }, { name = "Adventurer", from = 11, to = 20 },
		{ name = "Veteran", from = 21, to = 30 }, { name = "Elite", from = 31, to = 40 },
		{ name = "Master", from = 41, to = 50 }, { name = "Endgame", from = 51, to = 60 },
	},
	levelGrowth = 0.08, -- each item level above 1 adds 8% of the base stats
	rarityMultiplier = { Common = 1.0, Uncommon = 1.1, Rare = 1.22, Epic = 1.36, Legendary = 1.5 },
	-- Crafted items only (L-60, smithing makes the best gear): quality adds to the stats on top of rarity.
	qualityBonus = { Crude = -0.05, Standard = 0, Fine = 0.04, Superior = 0.08, Masterwork = 0.12 },
	rarityColors = {
		Common = { 200, 200, 200 }, Uncommon = { 110, 200, 120 }, Rare = { 90, 150, 240 },
		Epic = { 170, 100, 230 }, Legendary = { 240, 170, 60 },
	},

	-- Damage reduction from worn armour's defence: defence / (defence + constant), at most cap. Shields don't count
	-- (they protect only while blocking).
	armor = { constant = 60, cap = 0.6 },
	-- Equipment drops (L-60): extremely rare, so most gear is bought from smiths or crafted. Separate rolls: any
	-- equipment at all, then its rarity (ordinary drops are never Legendary), then which item. Placeholders.
	drops = {
		equipmentChance = { Normal = 0.002, Elite = 0.01, Boss = 0.04 },
		rarityWeights = {
			Normal = { Common = 75, Uncommon = 20, Rare = 5 },
			Elite = { Common = 50, Uncommon = 32, Rare = 15, Epic = 3 },
			Boss = { Uncommon = 45, Rare = 40, Epic = 15 },
		},
	},
	-- Weapon families (weaponType on items) and their subtypes. hands = 2 for two-handed weapons.
	weaponFamilies = {
		Sword = { hands = 1, subtypes = {
			ShortSword = h(1.1, 0.9, 0.9), ArmingSword = h(1, 1, 1), Longsword = h(0.95, 1.1, 1.05), KnightsSword = h(0.95, 1, 1.1),
			Saber = h(1.1, 1, 0.95), Scimitar = h(1.05, 0.95, 1), Rapier = h(1.2, 1.1, 0.85), Katana = h(1.05, 1.05, 1.05),
			BastardSword = h(0.9, 1.1, 1.1),
		} },
		Greatsword = { hands = 2, subtypes = {
			Greatsword = h(0.8, 1.25, 1.35), Zweihander = h(0.75, 1.35, 1.4), Claymore = h(0.8, 1.25, 1.35),
			ExecutionersSword = h(0.7, 1.15, 1.5), HeavyBlade = h(0.75, 1.2, 1.45),
		} },
		Dagger = { hands = 1, subtypes = {
			Dagger = h(1.3, 0.8, 0.75), DualDaggers = h(1.4, 0.8, 0.7), Stiletto = h(1.35, 0.8, 0.7), Kris = h(1.3, 0.8, 0.8),
			AssassinsBlade = h(1.25, 0.85, 0.85), ThrowingKnives = h(1.2, 2.5, 0.6),
		} },
		Axe = { hands = 1, subtypes = { HandAxe = h(1, 0.9, 1.05), Hatchet = h(1.1, 0.85, 0.95), BattleAxe = h(0.9, 1, 1.15) } },
		Greataxe = { hands = 2, subtypes = { GreatAxe = h(0.75, 1.2, 1.45), ExecutionersAxe = h(0.65, 1.15, 1.6), DoubleHeadedAxe = h(0.7, 1.2, 1.5) } },
		Mace = { hands = 1, subtypes = { Mace = h(0.95, 0.95, 1.1), Warhammer = h(0.85, 0.95, 1.2), Club = h(1, 0.9, 1) } },
		Maul = { hands = 2, subtypes = { Maul = h(0.7, 1.1, 1.5), GreatHammer = h(0.65, 1.15, 1.6), HeavyWarhammer = h(0.6, 1.15, 1.65) } },
		Spear = { hands = 2, subtypes = {
			Spear = h(1, 1.4, 1), Pike = h(0.85, 1.7, 1.05), Lance = h(0.8, 1.6, 1.15), Halberd = h(0.8, 1.45, 1.25),
			Glaive = h(0.9, 1.45, 1.15), Poleaxe = h(0.75, 1.35, 1.35), Trident = h(0.95, 1.4, 1.05),
		} },
		Bow = { hands = 2, subtypes = { Shortbow = h(1.15, 0.8, 0.85), Longbow = h(0.85, 1.3, 1.15), RecurveBow = h(1, 1, 1), HuntingBow = h(1.05, 0.95, 0.95), WarBow = h(0.8, 1.15, 1.3) } },
		Crossbow = { hands = 2, subtypes = { LightCrossbow = h(0.9, 1, 1.1), HeavyCrossbow = h(0.6, 1.15, 1.5), RepeatingCrossbow = h(1.3, 0.9, 0.7), Arbalest = h(0.5, 1.3, 1.7) } },
		Staff = { hands = 2, subtypes = { ApprenticeStaff = h(1, 1, 1), WizardStaff = h(1, 1.05, 1.1), BattleStaff = h(0.95, 1, 1.05), ElementalStaff = h(1, 1, 1.1), ArcaneStaff = h(1, 1.1, 1.1), RitualStaff = h(0.9, 1, 1.2) } },
		Wand = { hands = 1, subtypes = { ApprenticeWand = h(1.2, 0.9, 0.85), ArcaneWand = h(1.25, 0.9, 0.9), ElementalWand = h(1.2, 0.9, 0.95), BattleWand = h(1.15, 0.9, 1), RitualWand = h(1.1, 0.9, 1.05) } },
		Catalyst = { hands = 1, subtypes = { ArcaneOrb = h(1, 1, 1), ElementalOrb = h(1, 1, 1.05), SoulOrb = h(0.95, 1, 1.1), CrystalCatalyst = h(1.05, 1, 1), RuneCatalyst = h(1, 1, 1.05), SpellFocus = h(1.1, 1, 0.95) } },
		Fist = { hands = 2, subtypes = { Knuckles = h(1.3, 0.85, 0.8), Claws = h(1.35, 0.9, 0.8), Gauntlets = h(1.1, 0.85, 0.95), Tonfa = h(1.2, 0.95, 0.85), MartialBracers = h(1.25, 0.85, 0.85) } },
	},
	-- Off-hand shields: block strength and stamina per block. Shields only protect while blocking (Shield Wall and
	-- similar abilities); there is no passive shield damage reduction.
	shields = {
		Buckler = { block = 0.3, blockStamina = 6, stability = 0.3 }, RoundShield = { block = 0.4, blockStamina = 8, stability = 0.4 },
		KiteShield = { block = 0.5, blockStamina = 10, stability = 0.5 }, HeaterShield = { block = 0.5, blockStamina = 9, stability = 0.55 },
		TowerShield = { block = 0.65, blockStamina = 14, stability = 0.7 }, Greatshield = { block = 0.75, blockStamina = 18, stability = 0.8 },
	},
	-- Armour weights: defence relative to heavy armour, and their trade-offs.
	armorWeights = {
		Heavy = { defense = 1.0, staminaRegen = 0.85 },
		Medium = { defense = 0.65, staminaRegen = 1.0 },
		Light = { defense = 0.4, staminaRegen = 1.0, magicPower = 0.02 },
	},
	-- Which classes may wear each weight (classes not listed wear light and medium).
	heavyArmorClasses = { "HeavyKnight", "Paladin", "SeraphicGuardian", "DragonbloodKnight", "WorldbreakerBerserker", "Swordmaster", "GrandSwordmaster", "VoidSwordmaster", "BladeEmperor", "Spellblade" },
	lightOnlyClasses = { "Mage", "Acolyte", "Summoner", "Stormcaller", "LichLord", "AstralArchmage", "Chronomancer", "WorldrootSage", "AbyssalWarlock" },
})
