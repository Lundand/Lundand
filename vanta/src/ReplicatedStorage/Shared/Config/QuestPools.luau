--!strict
-- Rotating optional tasks (L-44). Each pool offers `count` of its repeatable quests per day, the same on
-- every server. Story quests never rotate.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	GuildBounties = {
		id = "GuildBounties",
		giver = "GuildRegistrar",
		count = 2,
		quests = { "BountyForestPests", "BountyHerbBundle", "BountyCopperRun" },
	},
})
