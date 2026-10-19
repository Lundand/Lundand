--!strict
-- Ability rules (the owner's class specification). The server checks every use: the class owns the ability, the
-- character's level unlocks it, the weapon suits the class, the character is free to act, the cooldown is over, and
-- the costs (stamina, mana, End Ability meter) can be paid. Shared so the HUD can explain why an ability is unusable.
local AbilityRules = {}

function AbilityRules.loadout(classDef: any): {string}
	return (classDef and classDef.abilities) or {}
end

function AbilityRules.weaponAllowed(classDef: any, weaponType: any): boolean
	return classDef ~= nil and classDef.weaponTypes ~= nil and weaponType ~= nil and table.find(classDef.weaponTypes, weaponType) ~= nil
end

-- context: { classDef, weaponType, level, now, busyUntil, staggeredUntil, cooldowns, meter, canAfford(cost) }
function AbilityRules.check(ability: any, abilityId: any, context: any): (boolean, string?)
	if ability == nil or table.find(AbilityRules.loadout(context.classDef), abilityId) == nil then
		return false, "not your ability"
	end
	if context.level < (ability.requiredLevel or 1) then
		return false, string.format("unlocks at level %d", ability.requiredLevel)
	end
	if not AbilityRules.weaponAllowed(context.classDef, context.weaponType) then
		return false, "needs a weapon your class can use"
	end
	if context.now < context.staggeredUntil or context.now < context.busyUntil then
		return false, "busy"
	end
	if context.now < (context.cooldowns[abilityId] or 0) then
		return false, "cooling down"
	end
	if ability.meterCost ~= nil and context.meter < ability.meterCost then
		return false, "End Ability not ready"
	end
	if not context.canAfford(ability.cost) then
		return false, "not enough resources"
	end
	return true, nil
end

-- Marks the ability used (cooldown, busy time) and returns when each hit lands, in seconds from now.
function AbilityRules.start(state: any, ability: any, abilityId: string, now: number): {any}
	state.busyUntil = now + ability.windup + ability.active + ability.recovery
	state.cooldowns[abilityId] = now + ability.cooldown
	state.comboNext = nil
	local schedule = {}
	for _, hit in ipairs(ability.hits or {}) do
		table.insert(schedule, { delay = ability.windup + (hit.at or 0), hit = hit })
	end
	return schedule
end

function AbilityRules.gainMeter(current: number, amount: number, max: number): number
	return math.max(0, math.min(max, current + amount))
end

-- Marks (Expose Weakness, Marked Prey): the marked target takes extra damage from the marking attacker for a limited
-- number of hits and time. Empowerment (Arcane Edge): the attacker's next hits deal extra damage. Both are spent
-- per hit that lands; neither lasts beyond its time.
function AbilityRules.applyMark(targetState: any, attackerKey: any, mark: any, now: number)
	targetState.marks = targetState.marks or {}
	targetState.marks[attackerKey] = { bonus = mark.bonus, remaining = mark.hits, untilTime = now + mark.seconds }
end

function AbilityRules.empower(attackerState: any, empower: any, now: number)
	attackerState.empower = { bonus = empower.bonus, remaining = empower.hits, untilTime = now + empower.seconds }
end

-- The damage multiplier for one landed hit, spending one charge of each bonus that applies.
function AbilityRules.consumeBonuses(targetState: any, attackerState: any, attackerKey: any, now: number): number
	local multiplier = 1
	local mark = targetState.marks and targetState.marks[attackerKey]
	if mark ~= nil and now < mark.untilTime and mark.remaining > 0 then
		multiplier += mark.bonus
		mark.remaining -= 1
	end
	local empower = attackerState.empower
	if empower ~= nil and now < empower.untilTime and empower.remaining > 0 then
		multiplier += empower.bonus
		empower.remaining -= 1
	end
	return multiplier
end

return AbilityRules
