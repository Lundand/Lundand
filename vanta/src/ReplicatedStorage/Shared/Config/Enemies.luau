--!strict
-- Enemy roster (owner's world specification). Base stats are for each enemy's own `level`; a spawned enemy rolls a
-- level within `levelRange` and its health, damage and experience scale with it (Config/EnemyProgression).
-- archetype picks shared attack behaviour (Config/Combat archetypeAttacks) unless the enemy has its own attack.
-- region: Forest and Hideout are in the city's overworld; Mountains is its own place (L-61).
-- AlleyThief stays for the opening quest. Kills are reported only by the server.
local Table = require(script.Parent.Parent.Util.Table)

local function enemy(id: string, name: string, level: number, maxLevel: number, stats: any): any
	stats.id = id
	stats.displayName = name
	stats.level = level
	stats.levelRange = { min = level, max = maxLevel }
	return stats
end

return Table.deepFreeze({
	-- Opening quest (personal encounter in the church alley)
	AlleyThief = enemy("AlleyThief", "Alley Thief", 1, 1, { maxHealth = 40, damage = 4, xp = 15, walkSpeed = 13, archetype = "Melee", region = "City", model = "Humanoid", weapon = "Knife", lootTable = "Thieves" }),
	-- Forest outside the walls (levels 1 to 8)
	YoungWolf = enemy("YoungWolf", "Young Wolf", 1, 3, { maxHealth = 30, damage = 3, xp = 10, walkSpeed = 15, archetype = "Fast", region = "Forest", model = "Beast", lootTable = "Wolves" }),
	ForestWolf = enemy("ForestWolf", "Forest Wolf", 4, 6, { maxHealth = 67, damage = 6, xp = 24, walkSpeed = 18, archetype = "Fast", region = "Forest", model = "Beast", lootTable = "Wolves" }),
	WildBoar = enemy("WildBoar", "Wild Boar", 11, 14, { maxHealth = 223, damage = 15, xp = 60, walkSpeed = 12, archetype = "Heavy", region = "Forest", model = "Beast", lootTable = "Boars" }),
	WolfAlpha = enemy("WolfAlpha", "Wolf Alpha", 7, 9, { maxHealth = 291, damage = 13, xp = 132, walkSpeed = 18, archetype = "Fast", elite = true, region = "Forest", model = "Beast", lootTable = "WolfAlpha",
		mechanics = { callForHelp = { atHealth = 0.4, enemyId = "YoungWolf", count = 2, message = "The Wolf Alpha howls for its pack!" } } }),
	-- Criminal hideout under the slums (levels 3 to 15)
	Pickpocket = enemy("Pickpocket", "Pickpocket", 3, 5, { maxHealth = 50, damage = 5, xp = 20, walkSpeed = 16, archetype = "Fast", region = "Hideout", model = "Humanoid", weapon = "Knife", lootTable = "Thieves" }),
	StreetThug = enemy("StreetThug", "Street Thug", 5, 8, { maxHealth = 90, damage = 9, xp = 33, walkSpeed = 13, archetype = "Melee", region = "Hideout", model = "Humanoid", lootTable = "Thieves" }),
	BanditFighter = enemy("BanditFighter", "Bandit Fighter", 12, 15, { maxHealth = 237, damage = 17, xp = 80, walkSpeed = 13, archetype = "Melee", region = "Hideout", model = "Humanoid", weapon = "Sword", lootTable = "Bandits" }),
	BanditArcher = enemy("BanditArcher", "Bandit Archer", 13, 16, { maxHealth = 168, damage = 16, xp = 85, walkSpeed = 12, archetype = "Ranged", region = "Hideout", model = "Humanoid", weapon = "Bow", lootTable = "Bandits" }),
	CriminalEnforcer = enemy("CriminalEnforcer", "Criminal Enforcer", 10, 13, { maxHealth = 426, damage = 17, xp = 220, walkSpeed = 13, archetype = "Heavy", elite = true, region = "Hideout", model = "Humanoid", weapon = "Mace", lootTable = "Enforcer" }),
	HideoutLeader = enemy("HideoutLeader", "Hideout Leader", 12, 15, { maxHealth = 1400, damage = 22, xp = 900, walkSpeed = 14, archetype = "Melee", boss = true, region = "Hideout", model = "Humanoid", weapon = "Sword", lootTable = "HideoutLeader",
		-- Learnable pattern: a telegraphed slam around him, and help at half health.
		mechanics = { slam = { every = 9, windup = 1.3, radius = 11, damageMultiplier = 1.6 }, callForHelp = { atHealth = 0.5, enemyId = "StreetThug", count = 2, message = "The Hideout Leader calls for help!" } } }),
	-- Mountains: its own place (levels 8 to 25)
	MountainGoat = enemy("MountainGoat", "Mountain Goat", 14, 18, { maxHealth = 237, damage = 10, xp = 44, walkSpeed = 14, archetype = "Passive", region = "Mountains", model = "Beast", lootTable = "MountainBeasts" }),
	MountainWolf = enemy("MountainWolf", "Mountain Wolf", 16, 20, { maxHealth = 316, damage = 24, xp = 124, walkSpeed = 19, archetype = "Fast", region = "Mountains", model = "Beast", lootTable = "MountainBeasts" }),
	GoblinScout = enemy("GoblinScout", "Goblin Scout", 18, 22, { maxHealth = 336, damage = 25, xp = 151, walkSpeed = 16, archetype = "Fast", region = "Mountains", model = "Humanoid", weapon = "Knife", lootTable = "Goblins" }),
	GoblinWarrior = enemy("GoblinWarrior", "Goblin Warrior", 21, 25, { maxHealth = 513, damage = 35, xp = 213, walkSpeed = 13, archetype = "Melee", region = "Mountains", model = "Humanoid", weapon = "Sword", lootTable = "Goblins" }),
	MountainTroll = enemy("MountainTroll", "Mountain Troll", 25, 29, { maxHealth = 1990, damage = 58, xp = 877, walkSpeed = 11, archetype = "Heavy", elite = true, region = "Mountains", model = "Humanoid", weapon = "Mace", lootTable = "Troll" }),
	MountainWarlord = enemy("MountainWarlord", "Mountain Warlord", 30, 30, { maxHealth = 7923, damage = 74, xp = 5359, walkSpeed = 14, archetype = "Melee", boss = true, region = "Mountains", model = "Humanoid", weapon = "Greataxe", lootTable = "Warlord",
		mechanics = { slam = { every = 7, windup = 1.2, radius = 13, damageMultiplier = 1.8 }, callForHelp = { atHealth = 0.5, enemyId = "GoblinWarrior", count = 3, message = "The Mountain Warlord calls his warband!" } } }),
})
