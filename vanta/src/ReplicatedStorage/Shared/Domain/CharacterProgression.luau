--!strict
-- Character level layer (L-17): XP, manually allocated stat points, and XP bonuses such as the
-- legendary catch-up bonus (L-23). Stored XP is the source of truth; level is derived (T-09).
local Check = require(script.Parent.Parent.Util.Check)
local Curve = require(script.Parent.Curve)

local CharacterProgression = {}

export type XpBonus = { kind: string, startMultiplier: number, endMultiplier: number, untilLevel: number }
export type State = { xp: number, allocated: {[string]: number}, bonusPoints: number, xpBonus: XpBonus? }
export type GrantResult = { gained: number, levelBefore: number, levelAfter: number, pointsGained: number, bonusEnded: boolean }

function CharacterProgression.newState(): State
	return { xp = 0, allocated = {}, bonusPoints = 0 }
end

function CharacterProgression.level(state: State, progressionConfig: any): number
	return Curve.levelForXp(progressionConfig.characterCurve, state.xp)
end

function CharacterProgression.earnedPoints(state: State, statsConfig: any, level: number): number
	return statsConfig.startingPoints + statsConfig.pointsPerLevel * (level - 1) + (state.bonusPoints or 0)
end

function CharacterProgression.allocatedTotal(state: State): number
	local total = 0
	for _, amount in pairs(state.allocated) do
		total += amount
	end
	return total
end

function CharacterProgression.availablePoints(state: State, statsConfig: any, progressionConfig: any): number
	local level = CharacterProgression.level(state, progressionConfig)
	return CharacterProgression.earnedPoints(state, statsConfig, level) - CharacterProgression.allocatedTotal(state)
end

-- True when a config change left more points allocated than earned; the service then refunds them.
function CharacterProgression.isOverAllocated(state: State, statsConfig: any, progressionConfig: any): boolean
	return CharacterProgression.availablePoints(state, statsConfig, progressionConfig) < 0
end

-- Catch-up multiplier: falls linearly from startMultiplier at level 1 towards endMultiplier at untilLevel.
function CharacterProgression.bonusMultiplier(state: State, level: number): number
	local bonus = state.xpBonus
	if bonus == nil or level >= bonus.untilLevel then
		return 1
	end
	local span = bonus.untilLevel - 1
	local progress = 0
	if span > 0 then
		progress = (level - 1) / span
	end
	return bonus.startMultiplier + (bonus.endMultiplier - bonus.startMultiplier) * progress
end

-- The multiplier is taken at the starting level for the whole grant.
function CharacterProgression.grantXp(state: State, amount: number, statsConfig: any, progressionConfig: any, extraMultiplier: number?): (boolean, any)
	if not Check.isFiniteNumber(amount) or amount <= 0 or amount > progressionConfig.maxXpGrant then
		return false, "invalid XP amount"
	end
	local extra = extraMultiplier or 1
	if not Check.isFiniteNumber(extra) or extra <= 0 then
		return false, "invalid XP multiplier"
	end
	local curve = progressionConfig.characterCurve
	local levelBefore = Curve.levelForXp(curve, state.xp)
	local cap = Curve.xpToReach(curve, Curve.maxLevel(curve))
	local multiplier = CharacterProgression.bonusMultiplier(state, levelBefore) * extra
	local newXp = math.min(state.xp + math.floor(amount * multiplier), cap)
	local gained = math.max(0, newXp - state.xp)
	state.xp = math.max(state.xp, newXp)
	local levelAfter = Curve.levelForXp(curve, state.xp)
	local bonusEnded = false
	if state.xpBonus ~= nil and levelAfter >= state.xpBonus.untilLevel then
		state.xpBonus = nil
		bonusEnded = true
	end
	return true, {
		gained = gained,
		levelBefore = levelBefore,
		levelAfter = levelAfter,
		pointsGained = statsConfig.pointsPerLevel * (levelAfter - levelBefore),
		bonusEnded = bonusEnded,
	}
end

-- request: { [statId] = points }. Applies all of it or none of it.
function CharacterProgression.allocate(state: State, request: any, statsConfig: any, progressionConfig: any): (boolean, string?)
	if type(request) ~= "table" then
		return false, "allocation must be a table"
	end
	local total = 0
	local entries = 0
	for statId, amount in pairs(request) do
		entries += 1
		if entries > #statsConfig.order then
			return false, "too many entries"
		end
		if type(statId) ~= "string" or statsConfig.definitions[statId] == nil then
			return false, "unknown stat"
		end
		if not Check.isPositiveInteger(amount) then
			return false, "points must be positive whole numbers"
		end
		total += amount
	end
	if entries == 0 then
		return false, "nothing to allocate"
	end
	if total > CharacterProgression.availablePoints(state, statsConfig, progressionConfig) then
		return false, "not enough stat points"
	end
	for statId, amount in pairs(request) do
		state.allocated[statId] = (state.allocated[statId] or 0) + amount
	end
	return true, nil
end

-- For the character profile: what an allocation would change, without changing anything (L-42).
function CharacterProgression.previewAllocation(state: State, request: any, statsConfig: any, progressionConfig: any): (boolean, any)
	local copy = { xp = state.xp, allocated = table.clone(state.allocated), bonusPoints = state.bonusPoints }
	local ok, err = CharacterProgression.allocate(copy, request, statsConfig, progressionConfig)
	if not ok then
		return false, err
	end
	return true, {
		before = CharacterProgression.derivedStats(state, statsConfig),
		after = CharacterProgression.derivedStats(copy, statsConfig),
		pointsBefore = CharacterProgression.availablePoints(state, statsConfig, progressionConfig),
		pointsAfter = CharacterProgression.availablePoints(copy, statsConfig, progressionConfig),
	}
end

-- Clears every allocated point and returns how many were refunded. Who may do this, and when, is
-- decided by the caller (P-12).
function CharacterProgression.resetAllocation(state: State): number
	local refunded = CharacterProgression.allocatedTotal(state)
	state.allocated = {}
	return refunded
end

-- Removes points allocated to stats that no longer exist (after a config change), making them available
-- again. Returns how many points were refunded.
function CharacterProgression.dropUnknownStats(state: State, statsConfig: any): number
	local refunded = 0
	for statId, points in pairs(state.allocated) do
		if statsConfig.definitions[statId] == nil then
			refunded += points
			state.allocated[statId] = nil
		end
	end
	return refunded
end

function CharacterProgression.effectivePoints(points: number, softCap: any): number
	if softCap == nil or points <= softCap.threshold then
		return points
	end
	return softCap.threshold + (points - softCap.threshold) * softCap.efficiencyAbove
end

-- `bonuses` (optional): percentage bonuses from equipment (ItemStats.equipmentBonuses), applied after attributes.
function CharacterProgression.derivedStats(state: State, statsConfig: any, bonuses: {[string]: number}?): {[string]: number}
	local result = table.clone(statsConfig.baseValues)
	for statId, points in pairs(state.allocated) do
		local effects = statsConfig.effectsPerPoint[statId]
		if effects then
			local effective = CharacterProgression.effectivePoints(points, statsConfig.softCap)
			for effect, perPoint in pairs(effects) do
				result[effect] = (result[effect] or 0) + perPoint * effective
			end
		end
	end
	for stat, bonus in pairs(bonuses or {}) do
		if result[stat] ~= nil then
			result[stat] *= 1 + bonus
		end
	end
	return result
end

function CharacterProgression.validateState(state: any, statsConfig: any): (boolean, string?)
	if type(state) ~= "table" then
		return false, "level layer missing"
	end
	if not Check.isNonNegativeInteger(state.xp) then
		return false, "xp must be a non-negative whole number"
	end
	if type(state.allocated) ~= "table" then
		return false, "allocated must be a table"
	end
	for _, points in pairs(state.allocated) do
		if not Check.isNonNegativeInteger(points) then
			return false, "invalid allocation"
		end
	end
	if not Check.isNonNegativeInteger(state.bonusPoints) then
		return false, "bonusPoints must be a non-negative whole number"
	end
	return true, nil
end

return CharacterProgression
