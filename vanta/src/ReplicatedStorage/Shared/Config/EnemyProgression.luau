--!strict
-- Enemy level scaling and the level-difference rule for rewards (owner's world specification). Placeholders.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- Per level above an enemy's base level, its stats are multiplied by these.
	growthPerLevel = { health = 1.12, damage = 1.08, xp = 1.1 },
	-- Experience and gold from a kill by level difference (enemy level minus player level): far weaker enemies give
	-- nothing, so high levels can't farm low regions; stronger enemies give a little more. Materials still drop.
	levelDifference = {
		{ atMost = -10, multiplier = 0 },
		{ atMost = -6, multiplier = 0.2 },
		{ atMost = -3, multiplier = 0.6 },
		{ atMost = 2, multiplier = 1 },
		{ atMost = 5, multiplier = 1.15 },
	},
	aboveMultiplier = 1.25,
})
