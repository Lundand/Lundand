--!strict
-- Combat disciplines (L-18, T-13 to T-15). Sword Arts follows docs/specs/PROGRESSION_SLICE.md.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	SwordArts = {
		id = "SwordArts",
		displayName = "Sword Arts",
		weaponTypes = { Sword = true },
		curve = { kind = "Table", thresholds = { 0, 300, 900, 2000, 4000 } },
		techniques = {
			SwordCombo = { displayName = "Three-Hit Combo", rank = 1 },
			SwordParry = { displayName = "Parry", rank = 1 },
			HeavyStrike = { displayName = "Heavy Strike", rank = 2 },
			Riposte = { displayName = "Riposte", rank = 3, milestones = { "IronWall" } },
			CrescentSweep = { displayName = "Crescent Sweep", rank = 4 },
			FlowingBlade = { displayName = "Flowing Blade", rank = 5, milestones = { "EliteDuel" }, passive = true },
		},
		milestones = {
			IronWall = { displayName = "Iron Wall", event = "PerfectParry", count = 10, rewardXp = 150 },
			SteadyHand = {
				displayName = "Steady Hand",
				event = "ComboFinished",
				count = 10,
				requireMovingTarget = true,
				rewardXp = 150,
			},
			EliteDuel = { displayName = "Elite Duel", event = "Kill", count = 1, requireElite = true, rewardXp = 300 },
			TrainersDrill = {
				displayName = "Trainer's Drill",
				event = "DrillCompleted",
				count = 1,
				drillId = "SwordDrill1",
				rewardXp = 0,
			},
		},
		xpSources = { Hit = 4, PerfectParry = 10, ComboFinished = 12, Kill = 20 },
		drills = {
			SwordDrill1 = { firstXp = 200, repeatXp = 40, repeatsPerDay = 3 },
		},
	},
	PlaceholderLegendaryArts = {
		id = "PlaceholderLegendaryArts",
		displayName = "Legendary Arts (placeholder)",
		developmentOnly = true,
		weaponTypes = { Sword = true },
		curve = { kind = "Power", base = 400, exponent = 1.4, maxLevel = 10 },
		techniques = {
			LegendaryStrike = { displayName = "Legendary Strike (placeholder)", rank = 1 },
		},
		milestones = {},
		xpSources = { Hit = 4, PerfectParry = 10, ComboFinished = 12, Kill = 20 },
		drills = {},
	},
})
