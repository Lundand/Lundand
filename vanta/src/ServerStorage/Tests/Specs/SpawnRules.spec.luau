--!strict
local SpawnRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Domain.SpawnRules)

return function(t)
	t.test("a spawner fills up when a player comes near, then replaces each death once after the delay", function()
		local spawner = { maxAlive = 3, respawnSeconds = 20 }
		local state = SpawnRules.newState()
		t.equal(SpawnRules.due(spawner, state, 0), 0, "inactive spawners make nothing")
		SpawnRules.activate(spawner, state, 0)
		local due = SpawnRules.due(spawner, state, 0)
		t.equal(due, 3)
		for _ = 1, due do SpawnRules.spawned(state) end
		SpawnRules.died(spawner, state, 5)
		t.equal(SpawnRules.due(spawner, state, 10), 0, "not before the delay")
		t.equal(SpawnRules.due(spawner, state, 25), 1, "one replacement for one death")
	end)

	t.test("population never exceeds the maximum, whatever happens", function()
		local spawner = { maxAlive = 2, respawnSeconds = 10 }
		local state = SpawnRules.newState()
		SpawnRules.activate(spawner, state, 0)
		SpawnRules.activate(spawner, state, 0)
		local due = SpawnRules.due(spawner, state, 0)
		t.equal(due, 2, "activating twice doesn't double the population")
		for _ = 1, due do SpawnRules.spawned(state) end
		SpawnRules.died(spawner, state, 1)
		SpawnRules.died(spawner, state, 1)
		SpawnRules.died(spawner, state, 1)
		t.truthy(state.alive + #state.pending <= spawner.maxAlive)
		t.equal(SpawnRules.due(spawner, state, 100), 2)
	end)
end
