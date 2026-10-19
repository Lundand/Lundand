--!strict
-- Enemy behaviour (M8): idle; chase a player inside the aggro range; wind up (the telegraph); strike; recover;
-- return home when pulled past the leash. Positions are { x, z } tables; EnemyService moves the models.
local EnemyBrain = {}

function EnemyBrain.new(home: any)
	return { mode = "Idle", home = home, target = nil, windupUntil = 0, recoverUntil = 0, cooldownUntil = 0 }
end

local function distance(a: any, b: any): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- targets: { { key, x, z } } players this enemy may attack. Returns this tick's decision:
-- { moveTo = { x, z }?, telegraph = true?, face = { x, z }?, strike = true?, reset = true? }
function EnemyBrain.update(brain: any, me: any, targets: {any}, attack: any, now: number, staggeredUntil: number): any
	local decision: any = {}
	if now < staggeredUntil then
		if brain.mode == "WindUp" then
			brain.mode = "Recover"
			brain.recoverUntil = staggeredUntil
		end
		return decision
	end
	local target = nil
	for _, candidate in ipairs(targets) do
		if candidate.key == brain.target then
			target = candidate
		end
	end
	if brain.mode == "Idle" then
		local best = attack.aggroRange
		for _, candidate in ipairs(targets) do
			local d = distance(me, candidate)
			if d <= best then
				target, best = candidate, d
			end
		end
		if target == nil then
			return decision
		end
		brain.mode = "Chase"
		brain.target = target.key
	end
	if brain.mode == "Return" then
		if distance(me, brain.home) <= 3 then
			brain.mode = "Idle"
			decision.reset = true
		else
			decision.moveTo = brain.home
		end
		return decision
	end
	if distance(me, brain.home) > attack.leashRange or (target == nil and brain.mode ~= "Recover") then
		brain.mode = "Return"
		brain.target = nil
		decision.moveTo = brain.home
		return decision
	end
	if brain.mode == "WindUp" then
		if now >= brain.windupUntil then
			brain.mode = "Recover"
			brain.recoverUntil = now + attack.active + attack.recovery
			brain.cooldownUntil = now + attack.cooldown
			decision.strike = true
		end
		return decision
	end
	if brain.mode == "Recover" then
		if now >= brain.recoverUntil then
			brain.mode = "Chase"
		end
		return decision
	end
	local d = distance(me, target)
	if d <= attack.range * 0.8 then
		if now >= brain.cooldownUntil then
			brain.mode = "WindUp"
			brain.windupUntil = now + attack.windup
			decision.telegraph = true
			decision.face = { x = target.x, z = target.z }
		end
	else
		decision.moveTo = { x = target.x, z = target.z }
	end
	return decision
end

return EnemyBrain
