--!strict
-- Combat tuning (L-03, M3): aimed attacks, telegraphed enemy attacks, dodging and parrying. Seconds, studs and
-- degrees. Placeholder values for the combat sandbox. Each attack names the Sword Arts technique that must be
-- learned and its animation in Config/Animations.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	dodge = { cooldown = 1.2, invulnerable = 0.35, animation = "Dodge", cost = { stamina = 20 } },
	comboResetSeconds = 0.8, -- after a combo step ends, how long the next step stays available
	hitLeniencyStuds = 3, -- allowance for movement and latency in the server's reach check
	unarmedAttackPower = 2,
	parryStaggerSeconds = 1.0, -- how long an enemy reels after a perfect parry
	staggerSeconds = 0.8, -- how long a staggering attack stops an enemy
	maxDamageReduction = 0.75,
	-- Crowd control: repeats within the window last half as long; immune after three; never longer than maxSeconds.
	crowdControl = { window = 15, falloff = 0.5, maxStacks = 3, maxSeconds = 4 }, -- defences together never reduce damage by more than this
	killCreditShare = 0.1, -- share of an enemy's health a player must deal to get kill credit
	-- Feel (client presentation only): lunge on basic attacks, slower walking while attacking, hitstop and shake.
	feel = { lungeSpeed = 24, lungeSeconds = 0.12, dodgeSpeed = 50, dodgeSeconds = 0.2, attackWalkSpeed = 6, hitstopSeconds = 0.07, shakeDealt = 0.12, shakeTaken = 0.3, shakeSeconds = 0.15 },
	-- Sound asset IDs; 0 = silent until sounds with clear usage rights are chosen.
	sounds = { swing = 0, heavySwing = 0, hit = 0, parry = 0, dodge = 0 },
	disciplines = {
		SwordArts = {
			weaponType = "Sword",
			attacks = {
				Combo1 = { technique = "SwordCombo", step = 1, windup = 0.12, active = 0.12, recovery = 0.22, range = 7, arc = 100, multiplier = 1.0, next = "Combo2", animation = "SwordCombo1" },
				Combo2 = { technique = "SwordCombo", step = 2, windup = 0.12, active = 0.12, recovery = 0.22, range = 7, arc = 100, multiplier = 1.1, next = "Combo3", animation = "SwordCombo2" },
				Combo3 = { technique = "SwordCombo", step = 3, windup = 0.18, active = 0.15, recovery = 0.4, range = 8, arc = 120, multiplier = 1.5, finisher = true, animation = "SwordCombo3" },
				Heavy = { technique = "HeavyStrike", windup = 0.45, active = 0.15, recovery = 0.5, range = 8, arc = 70, multiplier = 2.4, staggers = true, cooldown = 4, animation = "SwordHeavy", cost = { stamina = 25 } },
				Riposte = { technique = "Riposte", windup = 0.08, active = 0.12, recovery = 0.3, range = 7, arc = 90, multiplier = 3.0, requiresParry = true, staggers = true, animation = "SwordRiposte" },
				Sweep = { technique = "CrescentSweep", windup = 0.3, active = 0.2, recovery = 0.45, range = 9, arc = 300, multiplier = 1.6, cooldown = 6, animation = "SwordSweep", cost = { stamina = 30 } },
			},
			parry = { technique = "SwordParry", window = 0.25, recovery = 0.35, cooldown = 0.8, riposteWindow = 1.2, animation = "SwordParry" },
		},
	},
	-- Enemy attacks. The windup is the telegraph players read to dodge or parry.
	-- Shared attacks by enemy archetype (world specification). Passive enemies only fight back once attacked.
	archetypeAttacks = {
		Melee = { windup = 0.6, active = 0.15, recovery = 0.7, range = 6, arc = 90, cooldown = 1.6, aggroRange = 35, leashRange = 70, animation = "KnifeSlash" },
		Fast = { windup = 0.4, active = 0.12, recovery = 0.6, range = 6, arc = 80, cooldown = 1.3, aggroRange = 40, leashRange = 80, animation = "WolfBite" },
		Heavy = { windup = 1.0, active = 0.2, recovery = 1.0, range = 7, arc = 110, cooldown = 2.4, aggroRange = 30, leashRange = 60, animation = "KnifeSlash" },
		Ranged = { windup = 0.9, active = 0.1, recovery = 0.8, range = 24, arc = 25, cooldown = 2.2, aggroRange = 40, leashRange = 70, keepDistance = 12, animation = "KnifeSlash" },
		Passive = { windup = 0.6, active = 0.15, recovery = 0.8, range = 6, arc = 80, cooldown = 1.8, aggroRange = 0, leashRange = 50, passive = true, fleeBelow = 0.4, animation = "WolfBite" },
	},
	enemyAttacks = {
		AlleyThief = { windup = 0.6, active = 0.15, recovery = 0.7, range = 6, arc = 90, cooldown = 1.6, aggroRange = 30, leashRange = 60, animation = "KnifeSlash" },
		ForestWolf = { windup = 0.5, active = 0.15, recovery = 0.8, range = 6, arc = 80, cooldown = 1.8, aggroRange = 40, leashRange = 80, animation = "WolfBite" },
	},
})
