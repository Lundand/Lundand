--!strict
-- Parties (L-42): one to four players, formed at the Adventurers' Guild party board. Preset goals instead
-- of free text, so nothing a player writes has to be filtered.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	maxSize = 4,
	inviteSeconds = 60,
	boardSessionSeconds = 300, -- how long the board stays usable after opening it at the Guild
	goals = { "Questing", "Dungeon", "Gathering", "Exploring" },
})
