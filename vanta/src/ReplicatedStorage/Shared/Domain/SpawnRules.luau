--!strict
-- Spawner population (owner's world specification). A spawner fills up to its population when activated; each death
-- schedules exactly one replacement after the respawn delay. Alive plus waiting never exceeds maxAlive, so killing an
-- enemy can never create several more.
local SpawnRules = {}

function SpawnRules.newState(): any
	return { active = false, alive = 0, pending = {} }
end

function SpawnRules.activate(spawner: any, state: any, now: number)
	state.active = true
	local missing = spawner.maxAlive - state.alive - #state.pending
	for _ = 1, math.max(0, missing) do
		table.insert(state.pending, now)
	end
end

function SpawnRules.deactivate(state: any)
	state.active = false
	state.alive = 0
	state.pending = {}
end

-- How many to spawn now; the caller spawns them and reports each with SpawnRules.spawned.
function SpawnRules.due(spawner: any, state: any, now: number): number
	if not state.active then
		return 0
	end
	local due = 0
	for index = #state.pending, 1, -1 do
		if state.pending[index] <= now then
			table.remove(state.pending, index)
			due += 1
		end
	end
	return math.min(due, spawner.maxAlive - state.alive)
end

function SpawnRules.spawned(state: any)
	state.alive += 1
end

function SpawnRules.died(spawner: any, state: any, now: number)
	if not state.active then
		return
	end
	state.alive = math.max(0, state.alive - 1)
	if state.alive + #state.pending < spawner.maxAlive then
		table.insert(state.pending, now + spawner.respawnSeconds)
	end
end

return SpawnRules
