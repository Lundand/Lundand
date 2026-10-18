--!strict
-- Character level curve and the legendary catch-up bonus (L-17, L-23). Every value is tunable.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- First game version: level cap 30 (the full design goes to 60). Levels 21-30 cost 1.5x as much, so the cap is a climb.
	characterCurve = { kind = "Power", base = 100, exponent = 1.5, maxLevel = 30, slowFrom = 21, slowMultiplier = 1.5 },
	legendaryCatchUp = {
		enabled = true,
		startMultiplier = 2.0, -- XP multiplier right after activating a legendary class book
		endMultiplier = 1.0, -- multiplier it falls to as the character approaches untilLevel
		untilLevel = 20, -- the bonus ends at this level
	},
	maxXpGrant = 1000000, -- sanity limit for a single XP grant
})
