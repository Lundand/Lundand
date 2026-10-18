--!strict
-- Community Rift events (L-36, L-47). Values are placeholders (O-16 to O-18). Donations add to the active
-- event's shared total; at the target the Rift opens for every eligible player for openHours. Donating
-- never grants anything in play, and nobody needs to donate to take part.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	activeEventId = "RIFT_0001",
	shardCount = 8, -- shared total split across this many DataStore keys so many servers can add at once
	maxDonationRobux = 10000,
	events = {
		RIFT_0001 = {
			id = "RIFT_0001",
			displayName = "The First Tear",
			description = "Pour strength into the Heart of Realms to force open a Rift beyond the southern forest.",
			target = 100000,
			openHours = 10,
			runsPerPlayer = 3,
		},
	},
})
