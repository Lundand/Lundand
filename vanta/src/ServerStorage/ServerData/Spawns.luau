--!strict
-- Open-world enemy spawners in this place (owner's world specification). Each keeps at most maxAlive enemies of one
-- kind in its zone (a part with that LocationId), replacing each death after respawnSeconds, and only while a player is
-- near. Mountain spawners belong to the mountain place (L-61). Placeholders to tune.
local Table = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Table)

local function spawner(enemyId: string, locationId: string, maxAlive: number, respawnSeconds: number): any
	return { enemyId = enemyId, locationId = locationId, maxAlive = maxAlive, respawnSeconds = respawnSeconds }
end

return Table.deepFreeze({
	-- Southern Woods (levels 1 to 8)
	ForestYoungWolves = spawner("YoungWolf", "ForestEdge", 4, 20),
	ForestWolves = spawner("ForestWolf", "ForestDeep", 4, 25),
	ForestAlpha = spawner("WolfAlpha", "ForestDen", 1, 300),
	-- Criminal hideout under the slums (levels 3 to 15)
	HideoutPickpockets = spawner("Pickpocket", "HideoutEntrance", 3, 25),
	HideoutThugs = spawner("StreetThug", "HideoutHall", 3, 30),
	HideoutEnforcer = spawner("CriminalEnforcer", "HideoutInner", 1, 180),
	-- the first map is thieves and wolves only: the hideout's bandits moved to the mountain place
	HideoutAlleyThieves = spawner("AlleyThief", "HideoutEntrance", 3, 20),
	HideoutInnerThugs = spawner("StreetThug", "HideoutInner", 3, 30),
	HideoutLeader = spawner("HideoutLeader", "HideoutThrone", 1, 900),
})
