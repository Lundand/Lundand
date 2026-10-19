--!strict
-- Dialogue rules (L-40, L-42). The server keeps each player's place in a conversation and sends one node
-- at a time; the client only presents text and lets the player skip it. Effects happen only through a
-- conversation's onStart effects and through chosen options, both decided here and run by the server,
-- so skipping text can never skip progress, rewards or story state.
local QuestRules = require(script.Parent.QuestRules)

local DialogueRules = {}

DialogueRules.ACTIONS = table.freeze({
	AcceptQuest = true,
	TurnInQuest = true,
	SetFlag = true,
	OpenPartyBoard = true,
	OpenCrafting = true,
	OpenRentals = true,
	Awaken = true,
	OpenShop = true,
	OpenDonations = true,
	OpenGuildDesk = true,
})
DialogueRules.CONDITIONS = table.freeze({
	questCompleted = true,
	questNotCompleted = true,
	questActive = true,
	questNotStarted = true,
	questReady = true,
	questAvailable = true,
	questLevelTooLow = true,
	questOffered = true,
	flag = true,
	notFlag = true,
	minLevel = true,
	hasClass = true,
})
DialogueRules.MAX_LINE_LENGTH = 300

-- Everything conditions can look at, built from the character on the server.
-- offered: today's rotating quests (QuestPools.offeredSet); extraFlags: facts from outside the character's
-- story, such as InGuild. Both optional.
function DialogueRules.buildContext(character: any, questDefs: any, characterLevel: number, now: number, offered: any?, extraFlags: any?): any
	local flags = table.clone((character.story and character.story.flags) or {})
	for flag, value in pairs(extraFlags or {}) do
		flags[flag] = value
	end
	local ready, available, levelTooLow = {}, {}, {}
	for questId, def in pairs(questDefs) do
		if QuestRules.isComplete(character.quests[questId], def, character.inventory) then
			ready[questId] = true
		end
		local status = QuestRules.availability(character.quests, def, characterLevel, now, flags)
		if status == "Available" then
			available[questId] = true
		elseif status == "LevelTooLow" then
			levelTooLow[questId] = true
		end
	end
	return {
		quests = character.quests,
		completed = QuestRules.completedSet(character.quests),
		ready = ready,
		available = available,
		levelTooLow = levelTooLow,
		offered = offered or {},
		flags = flags,
		level = characterLevel,
		hasClass = character.class.classId ~= nil,
	}
end

function DialogueRules.meets(requires: any, context: any): boolean
	if requires == nil then
		return true
	end
	if requires.questCompleted ~= nil and not context.completed[requires.questCompleted] then
		return false
	end
	if requires.questNotCompleted ~= nil and context.completed[requires.questNotCompleted] then
		return false
	end
	if requires.questActive ~= nil then
		local state = context.quests[requires.questActive]
		if state == nil or state.state ~= "Active" then
			return false
		end
	end
	if requires.questNotStarted ~= nil and context.quests[requires.questNotStarted] ~= nil then
		return false
	end
	if requires.questReady ~= nil and not context.ready[requires.questReady] then
		return false
	end
	if requires.questAvailable ~= nil and not context.available[requires.questAvailable] then
		return false
	end
	if requires.questLevelTooLow ~= nil and not context.levelTooLow[requires.questLevelTooLow] then
		return false
	end
	if requires.questOffered ~= nil and not context.offered[requires.questOffered] then
		return false
	end
	if requires.flag ~= nil and not context.flags[requires.flag] then
		return false
	end
	if requires.notFlag ~= nil and context.flags[requires.notFlag] then
		return false
	end
	if requires.minLevel ~= nil and (context.level or 1) < requires.minLevel then
		return false
	end
	if requires.hasClass ~= nil and requires.hasClass ~= (context.hasClass == true) then
		return false
	end
	return true
end

-- The conversation an NPC offers right now: the highest priority one whose conditions are met.
function DialogueRules.select(npcId: string, dialogues: any, context: any): string?
	local bestId, bestPriority = nil, -1000000
	for conversationId, dialogue in pairs(dialogues) do
		if dialogue.npc == npcId and DialogueRules.meets(dialogue.requires, context) then
			local priority = dialogue.priority or 0
			if priority > bestPriority or (priority == bestPriority and bestId ~= nil and conversationId < bestId) then
				bestId, bestPriority = conversationId, priority
			end
		end
	end
	return bestId
end

-- What the client shows for a node: lines and the choices this player may pick (with their original index).
function DialogueRules.view(conversationId: string, dialogue: any, nodeId: string, context: any, seen: boolean): any
	local node = dialogue.nodes[nodeId]
	local choices = {}
	for index, choice in ipairs(node.choices or {}) do
		if DialogueRules.meets(choice.requires, context) then
			table.insert(choices, { index = index, text = choice.text })
		end
	end
	return {
		conversationId = conversationId,
		nodeId = nodeId,
		npc = dialogue.npc,
		lines = node.lines or {},
		choices = choices,
		final = #choices == 0 and node.next == nil,
		seen = seen,
	}
end

-- Starts a conversation: marks it seen, keeps its journal entry, and returns whether it was seen before
-- plus the onStart effects for the server to apply immediately.
function DialogueRules.begin(story: any, conversationId: string, dialogue: any, now: number): (boolean, {any})
	story.seen = story.seen or {}
	story.journal = story.journal or {}
	local seenBefore = story.seen[conversationId] ~= nil
	story.seen[conversationId] = now
	if dialogue.journal ~= nil and story.journal[conversationId] == nil then
		story.journal[conversationId] = now
	end
	return seenBefore, dialogue.onStart or {}
end

-- After reading a node that offers no choice. nil ends the conversation.
function DialogueRules.advance(dialogue: any, nodeId: string): string?
	return dialogue.nodes[nodeId].next
end

-- Skip: the first node from here that offers a visible choice, or nil for the end.
-- A decision is never skipped for the player; only the text before it is.
function DialogueRules.skip(dialogue: any, nodeId: string, context: any): string?
	local current = nodeId
	local steps = 0
	while current ~= nil and steps < 50 do
		local node = dialogue.nodes[current]
		for _, choice in ipairs(node.choices or {}) do
			if DialogueRules.meets(choice.requires, context) then
				return current
			end
		end
		current = node.next
		steps += 1
	end
	return nil
end

function DialogueRules.choose(dialogue: any, nodeId: string, index: any, context: any): (boolean, any)
	local node = dialogue.nodes[nodeId]
	local choice = type(index) == "number" and node.choices ~= nil and node.choices[index]
	if not choice or not DialogueRules.meets(choice.requires, context) then
		return false, "that option isn't available"
	end
	return true, { actions = choice.actions or {}, next = choice.next }
end

function DialogueRules.validate(dialogues: any, content: any): {string}
	local problems = {}
	local fallback = {}
	local function add(conversationId: any, message: string)
		table.insert(problems, "dialogue " .. tostring(conversationId) .. ": " .. message)
	end
	local function checkRequires(conversationId: any, requires: any)
		for key, value in pairs(requires or {}) do
			if not DialogueRules.CONDITIONS[key] then
				add(conversationId, "unknown condition " .. tostring(key))
			elseif string.sub(key, 1, 5) == "quest" and content.quests[value] == nil then
				add(conversationId, "condition " .. key .. " names unknown quest " .. tostring(value))
			end
		end
	end
	local function checkAction(conversationId: any, action: any)
		if not DialogueRules.ACTIONS[action.kind] then
			add(conversationId, "unknown action " .. tostring(action.kind))
		elseif (action.kind == "AcceptQuest" or action.kind == "TurnInQuest") and content.quests[action.questId] == nil then
			add(conversationId, "action names unknown quest " .. tostring(action.questId))
		elseif action.kind == "OpenCrafting" and content.facilities[action.facilityId] == nil then
			add(conversationId, "action names unknown facility " .. tostring(action.facilityId))
		elseif action.kind == "OpenRentals" and content.world.inns[action.innId] == nil then
			add(conversationId, "action names unknown inn " .. tostring(action.innId))
		elseif action.kind == "OpenShop" and action.shop ~= "Cosmetics" and content.vendors[action.shop] == nil then
			add(conversationId, "OpenShop needs \"Cosmetics\" or a known vendor")
		elseif action.kind == "SetFlag" and (type(action.flag) ~= "string" or action.flag == "") then
			add(conversationId, "SetFlag needs a flag")
		end
	end
	for conversationId, dialogue in pairs(dialogues) do
		if content.npcs[dialogue.npc] == nil then
			add(conversationId, "unknown NPC " .. tostring(dialogue.npc))
		end
		if dialogue.requires == nil then
			fallback[dialogue.npc] = true
		end
		checkRequires(conversationId, dialogue.requires)
		for _, effect in ipairs(dialogue.onStart or {}) do
			checkAction(conversationId, effect)
		end
		if type(dialogue.nodes) ~= "table" or dialogue.nodes.start == nil then
			add(conversationId, "needs a start node")
		else
			local reachable, queue = { start = true }, { "start" }
			while #queue > 0 do
				local nodeId = table.remove(queue, 1)
				local node = dialogue.nodes[nodeId]
				if node == nil then
					add(conversationId, "links to missing node " .. tostring(nodeId))
				else
					for _, text in ipairs(node.lines or {}) do
						if type(text) ~= "string" or text == "" or #text > DialogueRules.MAX_LINE_LENGTH then
							add(conversationId, "node " .. nodeId .. " has an empty or overlong line")
						end
					end
					local targets = {}
					if node.next ~= nil then
						table.insert(targets, node.next)
					end
					for _, choice in ipairs(node.choices or {}) do
						if type(choice.text) ~= "string" or choice.text == "" then
							add(conversationId, "node " .. nodeId .. " has a choice without text")
						end
						checkRequires(conversationId, choice.requires)
						for _, action in ipairs(choice.actions or {}) do
							checkAction(conversationId, action)
						end
						if choice.next ~= nil then
							table.insert(targets, choice.next)
						end
					end
					for _, target in ipairs(targets) do
						if not reachable[target] then
							reachable[target] = true
							table.insert(queue, target)
						end
					end
				end
			end
			for nodeId in pairs(dialogue.nodes) do
				if not reachable[nodeId] then
					add(conversationId, "node " .. tostring(nodeId) .. " can never be reached")
				end
			end
		end
	end
	for npcId, npc in pairs(content.npcs) do
		if npc.opens ~= nil and not DialogueRules.ACTIONS[npc.opens] then
			add(npcId, "object opens an unknown action " .. tostring(npc.opens))
		end
		if npc.opens == nil and not fallback[npcId] then
			add(npcId, "NPC needs one conversation without conditions")
		end
	end
	table.sort(problems)
	return problems
end

return DialogueRules
