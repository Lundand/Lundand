--!strict
-- Profession layer (L-10): XP per profession and the unlocks earned by level. Separate from combat.
local Check = require(script.Parent.Parent.Util.Check)
local Curve = require(script.Parent.Curve)

local ProfessionProgression = {}

export type State = { xp: number, unlocks: {[string]: boolean} }

function ProfessionProgression.newState(): State
	return { xp = 0, unlocks = {} }
end

function ProfessionProgression.level(state: State, def: any): number
	return Curve.levelForXp(def.curve, state.xp)
end

function ProfessionProgression.refreshUnlocks(state: State, def: any): {string}
	local level = ProfessionProgression.level(state, def)
	local granted = {}
	for _, unlock in ipairs(def.unlocks) do
		if level >= unlock.level and not state.unlocks[unlock.id] then
			state.unlocks[unlock.id] = true
			table.insert(granted, unlock.id)
		end
	end
	return granted
end

-- Returns XP actually gained (capped at max level), the level before and after, and new unlocks.
function ProfessionProgression.grantXp(state: State, def: any, amount: any): (number, number, number, {string})
	local before = ProfessionProgression.level(state, def)
	if not Check.isFiniteNumber(amount) or amount <= 0 then
		return 0, before, before, {}
	end
	local cap = Curve.xpToReach(def.curve, Curve.maxLevel(def.curve))
	local newXp = math.max(state.xp, math.min(state.xp + math.floor(amount), cap))
	local gained = newXp - state.xp
	state.xp = newXp
	return gained, before, ProfessionProgression.level(state, def), ProfessionProgression.refreshUnlocks(state, def)
end

function ProfessionProgression.hasUnlock(state: State?, unlockId: string): boolean
	return state ~= nil and state.unlocks[unlockId] == true
end

function ProfessionProgression.validateState(state: any): (boolean, string?)
	if type(state) ~= "table" or not Check.isNonNegativeInteger(state.xp) or type(state.unlocks) ~= "table" then
		return false, "invalid profession state"
	end
	return true, nil
end

return ProfessionProgression
