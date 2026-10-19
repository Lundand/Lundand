--!strict
-- Class definitions (L-17 to L-22). Only the Swordmaster example exists until the progression slice
-- passes its tests (L-21). PlaceholderLegendary exists to test class books and is development-only.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	Swordmaster = {
		id = "Swordmaster",
		startingWeapon = "TrainingSword", -- from the church chest after the awakening (L-43)
		weaponTypes = { "Sword", "Greatsword" }, -- weapons this class may wield (class specification)
		abilities = { "CrossSlash", "LungingStrike", "SteelGuard", "BladeTempest" }, -- slots 1 to 4; slot 4 is the End Ability
		displayName = "Swordmaster",
		rarity = "Common", -- placeholder until the roster and rarities are decided (O-02, O-09)
		awakeningWeight = 100,
		disciplines = {
			SwordArts = { maxRank = 5 },
		},
		classUnlocks = {
			BattleFocus = { displayName = "Battle Focus", kind = "Mechanic", requires = { characterLevel = 5 } },
		},
	},
	PlaceholderLegendary = {
		id = "PlaceholderLegendary",
		displayName = "Legendary Class (placeholder)",
		rarity = "Legendary",
		developmentOnly = true,
		disciplines = {
			PlaceholderLegendaryArts = { maxRank = 10 },
		},
		classUnlocks = {
			PlaceholderLegendaryMechanic = {
				displayName = "Legendary Mechanic (placeholder)",
				kind = "Mechanic",
				requires = { characterLevel = 10 },
			},
		},
	},
	-- Mage (Common): ranged magic on mana; fragile up close (class specification 4.2).
	Mage = {
		id = "Mage",
		displayName = "Mage",
		rarity = "Common",
		awakeningWeight = 100,
		startingWeapon = "ApprenticeStaff",
		weaponTypes = { "Staff", "Wand" },
		abilities = { "MagicBolt", "ArcaneBurst", "Blink", "ArcaneCataclysm" },
		traits = { healthMultiplier = 0.85 },
		-- Without a discipline, the class's basic attack comes from here: a weak bolt, no mana.
		basicAttack = {
			windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt",
			hit = { shape = "line", range = 30, radius = 2, multiplier = 0.8, damageType = "Magic", speed = 70 },
		},
		disciplines = {},
		classUnlocks = {},
	},
	-- Heavy Knight (Rare): very high health and defense, very low damage, slow; protects groups (specification 5.1).
	HeavyKnight = {
		id = "HeavyKnight",
		displayName = "Heavy Knight",
		rarity = "Rare",
		awakeningWeight = 25,
		startingWeapon = "TrainingMace",
		weaponTypes = { "Sword", "Mace", "Shield" },
		abilities = { "ShieldWall", "ProvokingStrike", "BulwarkAdvance", "FortressOfTheLastStand" },
		traits = { healthMultiplier = 1.6, damageMultiplier = 0.6, walkSpeed = 13 },
		basicAttack = {
			windup = 0.25, active = 0.15, recovery = 0.5, animation = "MaceSmash",
			hit = { range = 7, arc = 110, multiplier = 1.0 },
		},
		disciplines = {},
		classUnlocks = {},
	},
	-- Archer (Common): aimed physical shots; vulnerable up close (class specification 4.3).
	Archer = {
		id = "Archer", displayName = "Archer", rarity = "Common", awakeningWeight = 100, startingWeapon = "HuntingBow",
		weaponTypes = { "Bow", "Crossbow" },
		abilities = { "QuickShot", "PiercingArrow", "BackstepShot", "RainOfArrows" },
		traits = { healthMultiplier = 0.9 },
		basicAttack = { windup = 0.12, active = 0.08, recovery = 0.3, animation = "BowShot", effect = "Bolt",
			hit = { shape = "line", range = 45, radius = 2, multiplier = 0.9, speed = 110 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Rogue (Common): fast, mobile, exploits openings; fragile (4.4).
	Rogue = {
		id = "Rogue", displayName = "Rogue", rarity = "Common", awakeningWeight = 100, startingWeapon = "RustyDagger",
		weaponTypes = { "Dagger" },
		abilities = { "TwinFang", "Shadowstep", "ExposeWeakness", "ExecutionDance" },
		traits = { healthMultiplier = 0.85 },
		basicAttack = { windup = 0.08, active = 0.08, recovery = 0.18, animation = "DaggerSlash", hit = { range = 6, arc = 90, multiplier = 0.6 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Acolyte (Common): support, minor healing, holy damage (4.5).
	Acolyte = {
		id = "Acolyte", displayName = "Acolyte", rarity = "Common", awakeningWeight = 100, startingWeapon = "ApprenticeStaff",
		weaponTypes = { "Staff", "Mace" },
		abilities = { "HolyBolt", "MinorHeal", "ProtectiveWard", "DivineSanctuary" },
		traits = {},
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt",
			hit = { shape = "line", range = 30, radius = 2, multiplier = 0.6, damageType = "Magic", speed = 70 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Brawler (Common): close-range strikes, counters, disruption; very short reach (4.6).
	Brawler = {
		id = "Brawler", displayName = "Brawler", rarity = "Common", awakeningWeight = 100, startingWeapon = "WornKnuckles",
		weaponTypes = { "Fist" },
		abilities = { "HeavyPunch", "SweepingKick", "CounterStance", "IronFistCataclysm" },
		traits = { healthMultiplier = 1.1 },
		basicAttack = { windup = 0.08, active = 0.08, recovery = 0.2, animation = "FistJab", hit = { range = 5, arc = 90, multiplier = 0.7 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Spellblade (Rare): sword and magic together; resource management (5.2).
	Spellblade = {
		id = "Spellblade", displayName = "Spellblade", rarity = "Rare", awakeningWeight = 25, startingWeapon = "TrainingSword",
		weaponTypes = { "Sword", "Catalyst" },
		abilities = { "ArcaneEdge", "RunicDash", "SpellParry", "ArcaneOverdrive" },
		traits = {},
		basicAttack = { windup = 0.15, active = 0.12, recovery = 0.3, animation = "SwordCombo1", hit = { range = 7, arc = 110, multiplier = 0.9 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Shadowblade (Rare): assassin burst; vulnerable if the burst fails (5.3).
	Shadowblade = {
		id = "Shadowblade", displayName = "Shadowblade", rarity = "Rare", awakeningWeight = 25, startingWeapon = "RustyDagger",
		weaponTypes = { "Dagger" },
		abilities = { "UmbralDash", "MarkedPrey", "Veil", "ShadowExecution" },
		traits = { healthMultiplier = 0.8 },
		basicAttack = { windup = 0.08, active = 0.08, recovery = 0.18, animation = "DaggerSlash", hit = { range = 6, arc = 90, multiplier = 0.65 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Summoner (Unique): summoned allies and sustained pressure; summon limits (class specification 6.1).
	Summoner = {
		id = "Summoner", displayName = "Summoner", rarity = "Unique", awakeningWeight = 6, startingWeapon = "ApprenticeStaff",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "SummonWisp", "CommandMinion", "SoulLink", "EternalLegion" },
		traits = { healthMultiplier = 0.9 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt",
			hit = { shape = "line", range = 28, radius = 2, multiplier = 0.6, damageType = "Magic", speed = 70 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Paladin (Unique): holy frontline hybrid; less damage than dedicated fighters, less defence than the Heavy Knight (6.2).
	Paladin = {
		id = "Paladin", displayName = "Paladin", rarity = "Unique", awakeningWeight = 6, startingWeapon = "TrainingMace",
		weaponTypes = { "Sword", "Mace", "Shield" },
		abilities = { "JudgmentStrike", "RadiantGuard", "Consecration", "LightOfTheCovenant" },
		traits = { healthMultiplier = 1.25, damageMultiplier = 0.85 },
		basicAttack = { windup = 0.2, active = 0.12, recovery = 0.4, animation = "MaceSmash", hit = { range = 7, arc = 110, multiplier = 1.0 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Stormcaller (Epic): elemental ranged damage and area control; long casts (7.1).
	Stormcaller = {
		id = "Stormcaller", displayName = "Stormcaller", rarity = "Epic", awakeningWeight = 2, startingWeapon = "ApprenticeStaff",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "LightningLance", "ChainLightning", "StormField", "TempestSovereign" },
		traits = { healthMultiplier = 0.85 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt",
			hit = { shape = "line", range = 32, radius = 2, multiplier = 0.85, damageType = "Magic", speed = 90 } },
		disciplines = {}, classUnlocks = {},
	},
	-- Grand Swordmaster (Epic): advanced sword mastery; sword combos and parry plus its own techniques (7.2).
	GrandSwordmaster = {
		id = "GrandSwordmaster", displayName = "Grand Swordmaster", rarity = "Epic", awakeningWeight = 2, startingWeapon = "TrainingSword",
		weaponTypes = { "Sword", "Greatsword" },
		abilities = { "PerfectParry", "RisingSever", "FlowingEdge", "EmperorsBlade" },
		disciplines = { SwordArts = { maxRank = 5 } },
		classUnlocks = {},
	},
	-- Legendary classes (class specification 8): only from class books; never in the awakening pool.
	VoidSwordmaster = {
		id = "VoidSwordmaster", displayName = "Void Swordmaster", rarity = "Legendary",
		weaponTypes = { "Sword" },
		abilities = { "VoidCut", "RiftStep", "FractureMark", "RiftsEnd" },
		traits = { damageMultiplier = 1.1 },
		basicAttack = { windup = 0.15, active = 0.12, recovery = 0.3, animation = "SwordCombo1", hit = { range = 7.5, arc = 110, multiplier = 1 } },
		disciplines = {}, classUnlocks = {},
	},
	LichLord = {
		id = "LichLord", displayName = "Lich Lord", rarity = "Legendary",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "SoulBolt", "RaiseRevenant", "SoulDrain", "LichLegion" },
		traits = { healthMultiplier = 0.9 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt", hit = { shape = "line", range = 32, radius = 2, multiplier = 0.7, damageType = "Magic", speed = 80 } },
		disciplines = {}, classUnlocks = {},
	},
	WorldbreakerBerserker = {
		id = "WorldbreakerBerserker", displayName = "Worldbreaker Berserker", rarity = "Legendary",
		weaponTypes = { "Greataxe" },
		abilities = { "Bloodrush", "FuryBreaker", "UnyieldingRage", "Worldsplitter" },
		traits = { healthMultiplier = 1.2, damageMultiplier = 1.15 },
		basicAttack = { windup = 0.3, active = 0.15, recovery = 0.5, animation = "AxeCleave", hit = { range = 8, arc = 120, multiplier = 1.3, furyGain = 10 } },
		disciplines = {}, classUnlocks = {},
	},
	AstralArchmage = {
		id = "AstralArchmage", displayName = "Astral Archmage", rarity = "Legendary",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "GravityWell", "AstralLance", "StarShards", "StarfallCataclysm" },
		traits = { healthMultiplier = 0.85 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt", hit = { shape = "line", range = 32, radius = 2, multiplier = 0.9, damageType = "Magic", speed = 80 } },
		disciplines = {}, classUnlocks = {},
	},
	SeraphicGuardian = {
		id = "SeraphicGuardian", displayName = "Seraphic Guardian", rarity = "Legendary",
		weaponTypes = { "Sword", "Shield" },
		abilities = { "WingsOfAegis", "Judgment", "GuardiansIntercession", "HeavensLastBastion" },
		traits = { healthMultiplier = 1.4, damageMultiplier = 0.7 },
		basicAttack = { windup = 0.15, active = 0.12, recovery = 0.3, animation = "SwordCombo1", hit = { range = 7, arc = 110, multiplier = 1 } },
		disciplines = {}, classUnlocks = {},
	},
	NightSovereign = {
		id = "NightSovereign", displayName = "Night Sovereign", rarity = "Legendary",
		weaponTypes = { "Dagger" },
		abilities = { "UmbralRend", "NightPassage", "DeathMark", "ThousandCuts" },
		traits = { healthMultiplier = 0.8, damageMultiplier = 1.1 },
		basicAttack = { windup = 0.08, active = 0.08, recovery = 0.16, animation = "DaggerSlash", hit = { range = 6, arc = 90, multiplier = 0.75 } },
		disciplines = {}, classUnlocks = {},
	},
	DragonbloodKnight = {
		id = "DragonbloodKnight", displayName = "Dragonblood Knight", rarity = "Legendary",
		weaponTypes = { "Sword", "Greatsword" },
		abilities = { "DragonfireSlash", "ScaleGuard", "DraconicRush", "DragonGodsDescent" },
		traits = { healthMultiplier = 1.2 },
		basicAttack = { windup = 0.15, active = 0.12, recovery = 0.3, animation = "SwordCombo1", hit = { range = 7.5, arc = 110, multiplier = 1.1 } },
		disciplines = {}, classUnlocks = {},
	},
	Chronomancer = {
		id = "Chronomancer", displayName = "Chronomancer", rarity = "Legendary",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "TemporalSnare", "RewindStep", "Accelerate", "ZeroHour" },
		traits = { healthMultiplier = 0.9 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt", hit = { shape = "line", range = 32, radius = 2, multiplier = 0.75, damageType = "Magic", speed = 80 } },
		disciplines = {}, classUnlocks = {},
	},
	ThunderSovereign = {
		id = "ThunderSovereign", displayName = "Thunder Sovereign", rarity = "Legendary",
		weaponTypes = { "Spear" },
		abilities = { "ThunderThrust", "Stormstep", "ChainSpark", "HeavensSpear" },
		traits = {},
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.3, animation = "SpearThrust", hit = { shape = "line", range = 9, radius = 2, multiplier = 1.0, speed = 300 } },
		disciplines = {}, classUnlocks = {},
	},
	WorldrootSage = {
		id = "WorldrootSage", displayName = "Worldroot Sage", rarity = "Legendary",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "RootSnare", "VerdantRenewal", "ThornSurge", "WorldrootPrison" },
		traits = {},
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt", hit = { shape = "line", range = 32, radius = 2, multiplier = 0.7, damageType = "Magic", speed = 80 } },
		disciplines = {}, classUnlocks = {},
	},
	AbyssalWarlock = {
		id = "AbyssalWarlock", displayName = "Abyssal Warlock", rarity = "Legendary",
		weaponTypes = { "Staff", "Catalyst" },
		abilities = { "AbyssBolt", "CurseOfRuin", "AbyssChains", "AbyssUnbound" },
		traits = { healthMultiplier = 0.9 },
		basicAttack = { windup = 0.15, active = 0.1, recovery = 0.35, animation = "CastBolt", effect = "Bolt", hit = { shape = "line", range = 32, radius = 2, multiplier = 0.8, damageType = "Magic", speed = 80 } },
		disciplines = {}, classUnlocks = {},
	},
	BladeEmperor = {
		id = "BladeEmperor", displayName = "Blade Emperor", rarity = "Legendary",
		weaponTypes = { "Sword" },
		abilities = { "PhantomBlade", "BladeOrbit", "ImperialPursuit", "ThousandBladesImperialExecution" },
		traits = {},
		basicAttack = { windup = 0.15, active = 0.12, recovery = 0.3, animation = "SwordCombo1", hit = { range = 7.5, arc = 110, multiplier = 1 } },
		disciplines = {}, classUnlocks = {},
	},
})
