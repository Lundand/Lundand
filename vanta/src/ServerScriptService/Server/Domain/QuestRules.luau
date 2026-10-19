--!strict
-- Quest rules (L-30): accepting, progress from server events, turn-in and repeat cooldowns. State lives
-- in character.quests. Turn-in takes delivered items and grants rewards in one transaction, then marks
-- the quest complete in the same step, so rewards can't be collected twice.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local Inventory = require(Shared.Domain.Inventory)
local ItemRegistry = require(Shared.Domain.ItemRegistry)
local Transaction = require(script.Parent.Transaction)

local QuestRules = {}

QuestRules.EVENT_KINDS = table.freeze({ Talk = true, Gather = true, Kill = true, Craft = true })

-- Quest IDs completed at least once (used for prerequisites and facility unlocks).
function QuestRules.completedSet(quests: any): {[string]: boolean}
	local set = {}
	for questId, state in pairs(quests) do
		if (state.completions or 0) > 0 then
			set[questId] = true
		end
	end
	return set
end

-- Where a quest stands for this character. "Locked" means a prerequisite quest or story flag is missing;
-- "LevelTooLow" means everything else is met, so NPCs can say what level is needed (L-44).
function QuestRules.availability(quests: any, def: any, characterLevel: number, now: number, flags: any?): string
	local state = quests[def.id]
	if state ~= nil and state.state == "Active" then
		return "Active"
	end
	if state ~= nil and (state.completions or 0) > 0 then
		if def.repeatCooldownSeconds == nil then
			return "Completed"
		end
		if now < (state.availableAt or 0) then
			return "Cooldown"
		end
	end
	local requires = def.requires or {}
	local completed = QuestRules.completedSet(quests)
	for _, questId in ipairs(requires.quests or {}) do
		if not completed[questId] then
			return "Locked"
		end
	end
	for _, flag in ipairs(requires.flags or {}) do
		if not (flags and flags[flag]) then
			return "Locked"
		end
	end
	if requires.inGuild and not (flags and flags.InGuild) then
		return "Locked"
	end
	if characterLevel < (requires.characterLevel or 1) then
		return "LevelTooLow"
	end
	return "Available"
end

local REFUSALS = {
	Active = "quest already active",
	Completed = "quest already completed",
	Cooldown = "quest not available again yet",
	Locked = "an earlier step must be completed first",
	LevelTooLow = "level too low",
}

function QuestRules.canAccept(quests: any, def: any, characterLevel: number, now: number, flags: any?): (boolean, string?)
	local status = QuestRules.availability(quests, def, characterLevel, now, flags)
	if status == "Available" then
		return true, nil
	end
	return false, REFUSALS[status]
end

function QuestRules.accept(quests: any, def: any, characterLevel: number, now: number, flags: any?): (boolean, string?)
	local ok, reason = QuestRules.canAccept(quests, def, characterLevel, now, flags)
	if not ok then
		return false, reason
	end
	local previous = quests[def.id]
	quests[def.id] = {
		state = "Active",
		progress = {},
		acceptedAt = now,
		completions = (previous and previous.completions) or 0,
		availableAt = (previous and previous.availableAt) or 0,
	}
	return true, nil
end

-- event: { kind = "Talk" | "Gather" | "Kill" | "Craft", target = id, amount = n }.
-- Returns the IDs of quests that progressed, sorted.
function QuestRules.applyEvent(quests: any, definitions: any, event: any): {string}
	local progressed = {}
	if type(event) ~= "table" or not QuestRules.EVENT_KINDS[event.kind] or type(event.target) ~= "string" then
		return progressed
	end
	local amount = event.amount or 1
	if not Check.isPositiveInteger(amount) then
		return progressed
	end
	for questId, state in pairs(quests) do
		local def = definitions[questId]
		if state.state == "Active" and def then
			local changed = false
			for _, objective in ipairs(def.objectives) do
				local current = state.progress[objective.id] or 0
				if objective.kind == event.kind and objective.target == event.target and current < objective.count then
					state.progress[objective.id] = math.min(objective.count, current + amount)
					changed = true
				end
			end
			if changed then
				table.insert(progressed, questId)
			end
		end
	end
	table.sort(progressed)
	return progressed
end

function QuestRules.isComplete(state: any, def: any, inventory: any): boolean
	if state == nil or state.state ~= "Active" then
		return false
	end
	for _, objective in ipairs(def.objectives) do
		if objective.kind == "Deliver" then
			if Inventory.count(inventory, objective.target) < objective.count then
				return false
			end
		elseif (state.progress[objective.id] or 0) < objective.count then
			return false
		end
	end
	return true
end

-- Transaction changes for a turn-in: take delivered items, grant reward gold and items.
function QuestRules.turnInChanges(def: any, items: any): {any}
	local changes = {}
	for _, objective in ipairs(def.objectives) do
		if objective.kind == "Deliver" then
			table.insert(changes, { type = "ConsumeItem", itemId = objective.target, amount = objective.count })
		end
	end
	local rewards = def.rewards or {}
	if (rewards.gold or 0) > 0 then
		table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = rewards.gold })
	end
	for _, reward in ipairs(rewards.items or {}) do
		if ItemRegistry.isUnique(items[reward.itemId]) then
			for _ = 1, reward.amount do
				table.insert(changes, { type = "GrantUnique", itemId = reward.itemId, origin = { kind = "Quest", source = def.id } })
			end
		else
			table.insert(changes, { type = "GrantStack", itemId = reward.itemId, amount = reward.amount })
		end
	end
	return changes
end

function QuestRules.markCompleted(quests: any, def: any, now: number)
	local state = quests[def.id]
	state.state = "Completed"
	state.completions = (state.completions or 0) + 1
	state.completedAt = now
	state.progress = {}
	if def.repeatCooldownSeconds ~= nil then
		state.availableAt = now + def.repeatCooldownSeconds
	end
end

-- Returns ok and either a reason or the XP rewards the caller grants through ProgressionService.
function QuestRules.turnIn(profileData: any, characterId: string, def: any, items: any, deps: any): (boolean, any)
	local character = profileData.characters[characterId]
	if character == nil then
		return false, "unknown character"
	end
	local state = character.quests[def.id]
	if not QuestRules.isComplete(state, def, character.inventory) then
		return false, "objectives not complete"
	end
	local changes = QuestRules.turnInChanges(def, items)
	if #changes > 0 then
		local operationId = string.format("quest:%s:%d", def.id, (state.completions or 0) + 1)
		local ok, result = Transaction.apply(profileData, characterId, { id = operationId, reason = "QuestReward", changes = changes }, deps)
		if not ok then
			return false, result
		end
	end
	QuestRules.markCompleted(character.quests, def, deps.now())
	local rewards = def.rewards or {}
	return true, { characterXp = rewards.characterXp or 0, professionXp = rewards.professionXp or {}, guildXp = rewards.guildXp or 0 }
end

function QuestRules.abandon(quests: any, questId: string): boolean
	local state = quests[questId]
	if state == nil or state.state ~= "Active" then
		return false
	end
	if (state.completions or 0) > 0 then
		state.state = "Completed"
		state.progress = {}
	else
		quests[questId] = nil
	end
	return true
end

return QuestRules
