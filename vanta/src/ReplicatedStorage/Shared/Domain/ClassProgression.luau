--!strict
-- Class layer (L-17): the character's class and the class unlocks (abilities and mechanics) granted
-- so far. Replacing the class with a legendary one is handled by LegendaryActivation (L-22).

local ClassProgression = {}

export type State = { classId: string?, unlocks: {[string]: boolean}, source: string?, assignedAt: number? }

function ClassProgression.newState(): State
	return { unlocks = {} }
end

-- The first class, from the church awakening (or a development tool). Never a legendary class.
function ClassProgression.assignInitialClass(state: State, classId: any, classes: any, source: string, now: number): (boolean, string?)
	if state.classId ~= nil then
		return false, "character already has a class"
	end
	local def = classes[classId]
	if type(classId) ~= "string" or def == nil then
		return false, "unknown class"
	end
	if def.rarity == "Legendary" then
		return false, "legendary classes only come from class books"
	end
	state.classId = classId
	state.unlocks = {}
	state.source = source
	state.assignedAt = now
	return true, nil
end

function ClassProgression.meetsRequirements(requires: any, context: any): boolean
	if requires == nil then
		return true
	end
	if requires.characterLevel ~= nil and (context.characterLevel or 0) < requires.characterLevel then
		return false
	end
	if requires.quest ~= nil and not (context.completedQuests and context.completedQuests[requires.quest]) then
		return false
	end
	return true
end

-- Grants every class unlock whose requirements are met. Returns the new unlock IDs, sorted.
function ClassProgression.refreshUnlocks(state: State, classes: any, context: any): {string}
	local granted = {}
	local def = state.classId and classes[state.classId]
	if not def then
		return granted
	end
	for unlockId, unlock in pairs(def.classUnlocks or {}) do
		if not state.unlocks[unlockId] and ClassProgression.meetsRequirements(unlock.requires, context) then
			state.unlocks[unlockId] = true
			table.insert(granted, unlockId)
		end
	end
	table.sort(granted)
	return granted
end

-- The disciplines the current class grants: { [disciplineId] = { maxRank, extraTechniques? } }.
function ClassProgression.disciplineGrants(state: State, classes: any): {[string]: any}
	local def = state.classId and classes[state.classId]
	if not def then
		return {}
	end
	return def.disciplines
end

function ClassProgression.validateState(state: any, classes: any): (boolean, string?)
	if type(state) ~= "table" or type(state.unlocks) ~= "table" then
		return false, "class layer missing"
	end
	if state.classId ~= nil and type(state.classId) ~= "string" then
		return false, "classId must be a string"
	end
	return true, nil
end

return ClassProgression
