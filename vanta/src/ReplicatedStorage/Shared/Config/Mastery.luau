--!strict
-- Rules that keep discipline mastery from being farmed by repetition (T-15). Tunable.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- Uses of the same technique step beyond freeUses within the window earn progressively less.
	repetition = { windowSeconds = 10, freeUses = 12, decayPerUse = 0.05, minimumMultiplier = 0.25 },
	repetitionSources = { Hit = true },
	xpPerMinuteCap = 600,
	-- Targets more than 5 levels below the character give no mastery XP.
	minTargetLevelOffset = -5,
})
