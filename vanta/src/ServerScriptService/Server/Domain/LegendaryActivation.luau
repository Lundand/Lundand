--!strict
-- Legendary Class Book activation (L-22). Consumes the book and replaces the class with a full reset of
-- class progression in one step: the new character record is built on a copy and swapped in only when
-- everything succeeded. The book and the character live in the same save document, so a single save
-- commits both or neither; if the server stops before saving, nothing happened (no loss, no dupe).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Table = require(Shared.Util.Table)
local Check = require(Shared.Util.Check)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local DisciplineMastery = require(Shared.Domain.DisciplineMastery)
local Transaction = require(script.Parent.Transaction)

local LegendaryActivation = {}

LegendaryActivation.MAX_CLASS_HISTORY = 50

-- Checks without changing anything. Returns the book, class ID and class definition on success.
function LegendaryActivation.check(character: any, bookUid: any, deps: any): (boolean, any)
	local book = type(bookUid) == "string" and character.inventory.uniques[bookUid]
	if not book then
		return false, "book not found in inventory"
	end
	local itemDef = deps.items[book.itemId]
	if itemDef == nil or itemDef.kind ~= "ClassBook" then
		return false, "item is not a class book"
	end
	local classId = itemDef.classBook.classId
	local classDef = deps.classes[classId]
	if classDef == nil or classDef.rarity ~= "Legendary" then
		return false, "book does not grant a legendary class"
	end
	if classDef.developmentOnly and not deps.allowDevelopmentContent then
		return false, "this class is not available"
	end
	if character.class.classId == classId then
		return false, "character already has this class"
	end
	return true, { book = book, classId = classId, classDef = classDef }
end

-- deps: { items, classes, disciplines, progressionConfig, now: () -> number, allowDevelopmentContent: boolean }
function LegendaryActivation.activate(profileData: any, characterId: string, bookUid: any, operationId: any, deps: any): (boolean, any)
	if not Check.isToken(operationId, 100) then
		return false, "invalid operation id"
	end
	if Transaction.wasApplied(profileData, operationId) then
		return true, { alreadyApplied = true }
	end
	local character = profileData.characters[characterId]
	if character == nil then
		return false, "unknown character"
	end
	local ok, info = LegendaryActivation.check(character, bookUid, deps)
	if not ok then
		return false, info
	end
	local now = deps.now()
	local working = Table.deepCopy(character)
	local previousClassId = working.class.classId

	-- Consume the book.
	working.inventory.uniques[bookUid] = nil

	-- Reset character level and allocated stats. Bonus points from non-class sources are kept.
	local level = CharacterProgression.newState()
	level.bonusPoints = working.level.bonusPoints or 0
	local catchUp = deps.progressionConfig.legendaryCatchUp
	if catchUp.enabled then
		level.xpBonus = {
			kind = "LegendaryCatchUp",
			startMultiplier = catchUp.startMultiplier,
			endMultiplier = catchUp.endMultiplier,
			untilLevel = catchUp.untilLevel,
		}
	end
	working.level = level

	-- Replace the class. The previous class does not remain as a secondary class.
	working.class = { classId = info.classId, unlocks = {}, source = "LegendaryBook", assignedAt = now }

	-- Remove all previous discipline mastery, then start the legendary class's own disciplines.
	working.disciplines = {}
	for disciplineId, grant in pairs(info.classDef.disciplines) do
		local state = DisciplineMastery.newState()
		DisciplineMastery.refreshTechniques(state, deps.disciplines[disciplineId], grant)
		working.disciplines[disciplineId] = state
	end

	-- The legendary layer starts fresh.
	working.legendary = {
		active = true,
		classId = info.classId,
		activatedAt = now,
		bookItemId = info.book.itemId,
		bookUid = bookUid,
		trials = {},
	}

	-- Commit: swap in the new record, then record history and the operation.
	profileData.characters[characterId] = working
	local history = profileData.account.classHistory
	table.insert(history, {
		classId = previousClassId or "None",
		endedAt = now,
		reason = "LegendaryBook",
		characterId = characterId,
	})
	while #history > LegendaryActivation.MAX_CLASS_HISTORY do
		table.remove(history, 1)
	end
	Transaction.record(profileData, operationId, "LegendaryActivation", characterId, now)
	return true, { alreadyApplied = false, previousClassId = previousClassId, classId = info.classId }
end

return LegendaryActivation
