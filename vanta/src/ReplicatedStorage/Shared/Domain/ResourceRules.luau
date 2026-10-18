--!strict
-- Stamina and mana: pools with maximums and regeneration that pauses briefly after spending. A cost can use stamina,
-- mana, both or neither, and is paid in full or not at all. The server owns the real pools; clients only read them
-- (and may use these rules to predict whether an action is affordable).
local ResourceRules = {}

function ResourceRules.newPool(maxStamina: number, maxMana: number, now: number): any
	return {
		stamina = maxStamina,
		mana = maxMana,
		maxStamina = maxStamina,
		maxMana = maxMana,
		updatedAt = now,
		staminaPausedUntil = 0,
		manaPausedUntil = 0,
	}
end

local function regen(current: number, max: number, from: number, now: number, rate: number): number
	if now <= from then
		return current
	end
	return math.min(max, current + (now - from) * rate)
end

-- Brings the pool up to `now`, regenerating whatever isn't paused.
function ResourceRules.regenerate(pool: any, now: number, rules: any)
	pool.stamina = regen(pool.stamina, pool.maxStamina, math.max(pool.updatedAt, pool.staminaPausedUntil), now, rules.stamina.regenPerSecond)
	pool.mana = regen(pool.mana, pool.maxMana, math.max(pool.updatedAt, pool.manaPausedUntil), now, rules.mana.regenPerSecond)
	pool.updatedAt = math.max(pool.updatedAt, now)
end

local function amounts(cost: any): (number, number)
	if cost == nil then
		return 0, 0
	end
	return cost.stamina or 0, cost.mana or 0
end

function ResourceRules.canAfford(pool: any, cost: any, now: number, rules: any): boolean
	ResourceRules.regenerate(pool, now, rules)
	local stamina, mana = amounts(cost)
	return pool.stamina >= stamina and pool.mana >= mana
end

-- Pays a cost in full or not at all.
function ResourceRules.spend(pool: any, cost: any, now: number, rules: any): (boolean, string?)
	local stamina, mana = amounts(cost)
	if stamina ~= stamina or mana ~= mana or stamina < 0 or mana < 0 or stamina == math.huge or mana == math.huge then
		return false, "invalid cost"
	end
	if not ResourceRules.canAfford(pool, cost, now, rules) then
		if pool.stamina < stamina then
			return false, "not enough stamina"
		end
		return false, "not enough mana"
	end
	if stamina > 0 then
		pool.stamina -= stamina
		pool.staminaPausedUntil = now + rules.stamina.regenDelay
	end
	if mana > 0 then
		pool.mana -= mana
		pool.manaPausedUntil = now + rules.mana.regenDelay
	end
	return true, nil
end

-- New maximums (for example after spending stat points); current values are kept, within the new maximums.
function ResourceRules.resize(pool: any, maxStamina: number, maxMana: number)
	pool.maxStamina = maxStamina
	pool.maxMana = maxMana
	pool.stamina = math.min(pool.stamina, maxStamina)
	pool.mana = math.min(pool.mana, maxMana)
end

return ResourceRules
