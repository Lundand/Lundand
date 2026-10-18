--!strict
-- Combat rules (L-03, M3), decided on the server for players and enemies alike. Attacks have a windup (the
-- telegraph), a moment when the hit lands, and a recovery. A parry is a short window that turns a hit into an
-- opening for a riposte; a dodge is a short invulnerable roll. Clients only ask to act and play animations;
-- timing, learned techniques, reach, damage and kill credit are checked here.
local CombatRules = {}

function CombatRules.newState()
	return {
		busyUntil = 0,
		cooldowns = {},
		comboNext = nil,
		comboUntil = 0,
		parryFrom = -1,
		parryTo = -1,
		invulnerableUntil = 0,
		riposteUntil = 0,
		staggeredUntil = 0,
	}
end

local function ready(state: any, now: number): (boolean, string?)
	if now < state.staggeredUntil then
		return false, "staggered"
	end
	if now < state.busyUntil then
		return false, "busy"
	end
	return true, nil
end

-- What a request becomes: a basic attack continues the combo, or becomes a riposte right after a perfect parry.
function CombatRules.resolveAttack(state: any, discipline: any, action: any, unlocked: any, now: number): string?
	if action == "Attack" then
		local riposte = discipline.attacks.Riposte
		if riposte ~= nil and now <= state.riposteUntil and unlocked[riposte.technique] then
			return "Riposte"
		end
		if state.comboNext ~= nil and now <= state.comboUntil then
			return state.comboNext
		end
		return "Combo1"
	elseif action == "Heavy" then
		return "Heavy"
	elseif action == "Sweep" then
		return "Sweep"
	end
	return nil
end

function CombatRules.startAttack(state: any, discipline: any, attackId: string, unlocked: any, now: number, rules: any): (boolean, any)
	local attack = discipline.attacks[attackId]
	if attack == nil then
		return false, "unknown attack"
	end
	if not unlocked[attack.technique] then
		return false, "technique not learned"
	end
	local ok, reason = ready(state, now)
	if not ok then
		return false, reason
	end
	if now < (state.cooldowns[attackId] or 0) then
		return false, "cooling down"
	end
	if attack.step ~= nil and attack.step > 1 and not (state.comboNext == attackId and now <= state.comboUntil) then
		return false, "combo broken"
	end
	if attack.requiresParry and now > state.riposteUntil then
		return false, "no opening"
	end
	local hitAt = now + attack.windup
	state.busyUntil = hitAt + attack.active + attack.recovery
	if attack.cooldown ~= nil then
		state.cooldowns[attackId] = now + attack.cooldown
	end
	if attack.next ~= nil then
		state.comboNext = attack.next
		state.comboUntil = state.busyUntil + rules.comboResetSeconds
	else
		state.comboNext = nil
	end
	if attack.requiresParry then
		state.riposteUntil = 0
	end
	return true, { id = attackId, attack = attack, hitAt = hitAt, endsAt = state.busyUntil }
end

function CombatRules.startParry(state: any, discipline: any, unlocked: any, now: number): (boolean, string?)
	local parry = discipline.parry
	if parry == nil or not unlocked[parry.technique] then
		return false, "technique not learned"
	end
	local ok, reason = ready(state, now)
	if not ok then
		return false, reason
	end
	if now < (state.cooldowns.Parry or 0) then
		return false, "cooling down"
	end
	state.parryFrom = now
	state.parryTo = now + parry.window
	state.busyUntil = now + parry.window + parry.recovery
	state.cooldowns.Parry = now + parry.cooldown
	state.comboNext = nil
	return true, nil
end

function CombatRules.startDodge(state: any, rules: any, now: number): (boolean, string?)
	local ok, reason = ready(state, now)
	if not ok then
		return false, reason
	end
	if now < (state.cooldowns.Dodge or 0) then
		return false, "cooling down"
	end
	state.invulnerableUntil = now + rules.dodge.invulnerable
	state.busyUntil = state.invulnerableUntil
	state.cooldowns.Dodge = now + rules.dodge.cooldown
	state.comboNext = nil
	return true, nil
end

-- How an incoming hit lands: "Dodged", "Parried" (opening a riposte) or "Hit".
function CombatRules.receiveHit(state: any, discipline: any, now: number): string
	if now < state.invulnerableUntil then
		return "Dodged"
	end
	if now >= state.parryFrom and now <= state.parryTo then
		local window = (discipline and discipline.parry and discipline.parry.riposteWindow) or 0
		state.riposteUntil = now + window
		state.parryTo = -1
		return "Parried"
	end
	return "Hit"
end

function CombatRules.stagger(state: any, now: number, seconds: number)
	state.staggeredUntil = math.max(state.staggeredUntil, now + seconds)
	state.comboNext = nil
end

-- Reach on the ground plane: within range (plus leniency) and inside the arc around the facing direction.
-- Points are { x, z } tables.
function CombatRules.inArc(origin: any, facing: any, target: any, range: number, arcDegrees: number, leniency: number): boolean
	local dx, dz = target.x - origin.x, target.z - origin.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > range + leniency then
		return false
	end
	if distance < 1.5 then
		return true
	end
	local facingLength = math.sqrt(facing.x * facing.x + facing.z * facing.z)
	if facingLength == 0 then
		return false
	end
	local cosine = math.max(-1, math.min(1, (dx * facing.x + dz * facing.z) / (distance * facingLength)))
	return math.deg(math.acos(cosine)) <= arcDegrees / 2
end

-- Weapon attack power x attack multiplier x the physicalDamage stat (Strength), never below 1.
function CombatRules.damage(attackPower: number, multiplier: number, physicalDamage: number): number
	return math.max(1, math.floor(attackPower * multiplier * physicalDamage + 0.5))
end

function CombatRules.recordDamage(ledger: any, attackerKey: string, amount: number)
	ledger[attackerKey] = (ledger[attackerKey] or 0) + amount
end

-- Everyone who dealt at least `share` of the enemy's health gets kill credit.
function CombatRules.credited(ledger: any, maxHealth: number, share: number): {string}
	local list = {}
	for attackerKey, amount in pairs(ledger) do
		if amount >= maxHealth * share then
			table.insert(list, attackerKey)
		end
	end
	table.sort(list)
	return list
end

return CombatRules
