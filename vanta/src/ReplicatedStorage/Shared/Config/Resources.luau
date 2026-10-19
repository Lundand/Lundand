--!strict
-- Combat resources (the owner's resource requirements). Every class has HP (the Humanoid) and stamina; mana is
-- there for everyone, but the HUD shows it only when a class's abilities use it. The stamina maximum comes from the
-- maxStamina stat. Placeholder values, to balance in play.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	stamina = { regenPerSecond = 25, regenDelay = 0.8 }, -- regeneration pauses this long after spending
	mana = { max = 100, regenPerSecond = 8, regenDelay = 1.0 },
	ultimate = { max = 100, perHitDealt = 5, perHitTaken = 4 }, -- the End Ability meter, filled in combat
	syncInterval = 0.1, -- how often the server shows current values to clients
})
