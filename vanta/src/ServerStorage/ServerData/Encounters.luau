--!strict
-- Enemy encounters (M8). Personal encounters appear for a player (and can only be fought by them and their
-- party) while they hold the quest and its kills aren't done, so nobody can steal or block a quest fight.
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

return Table.deepFreeze({
	ChurchAlleyThieves = {
		id = "ChurchAlleyThieves",
		locationId = "ChurchAlley",
		enemyId = "AlleyThief",
		count = 3,
		personal = true,
		questId = "TheStolenBelongings",
		despawnDistance = 150,
	},
})
