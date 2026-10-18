--!strict
-- Where gathering spots grow (owner, 2026-10-16): each area keeps `count` spots of one kind at random places inside
-- its zone (a part with that LocationId). A gathered spot disappears for everyone and regrows after a random delay
-- (respawnSeconds) at another random place in the area. Placeholders to tune.
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

return Table.deepFreeze({
	ForestDeepOaks = { nodeType = "OakTree", locationId = "ForestDeep", count = 8, respawnSeconds = { 60, 150 } },
	ForestEdgeOaks = { nodeType = "OakTree", locationId = "ForestEdge", count = 4, respawnSeconds = { 60, 150 } },
	ForestHerbs = { nodeType = "HealingHerbPatch", locationId = "ForestEdge", count = 6, respawnSeconds = { 45, 120 } },
	ForestCopper = { nodeType = "CopperVein", locationId = "ForestEdge", count = 3, respawnSeconds = { 120, 240 } },
})
