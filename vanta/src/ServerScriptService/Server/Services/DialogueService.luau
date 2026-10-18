--!strict
-- NPC conversations (L-40, L-42). NPCs are world models tagged "Npc" with an NpcId attribute, each with a
-- contextual Talk prompt that only appears nearby. The server picks the conversation, applies its onStart
-- effects at once (so skipping text can't miss them), sends one node at a time, checks distance on every
-- step, and runs the actions of chosen options.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local DialogueRules = require(Server.Domain.DialogueRules)
local Awakening = require(Server.Domain.Awakening)
local QuestPools = require(Server.Domain.QuestPools)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local Dialogue = require(ServerStorage:WaitForChild("ServerData").Dialogue)
local Models = require(Server.Tools.Models)

local TAG = "Npc"
local TALK_DISTANCE = 14
local POOL_SEED = "VANTA" -- same rotating offers on every server

local DialogueService = {}
local services: any = nil
local sessions: {[Player]: any} = {}
local npcInstances: {[string]: Instance} = {}
local limiter = RateLimiter.new(10, 5, os.clock)
local random = Random.new()

function DialogueService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function npcPosition(npcId: string): Vector3?
	local instance = npcInstances[npcId]
	if instance == nil then
		return nil
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function isNear(player: Player, npcId: string): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local position = npcPosition(npcId)
	return root ~= nil and position ~= nil and (root.Position - position).Magnitude <= TALK_DISTANCE
end

local function context(player: Player): any
	local character = services.PlayerDataService.getCharacter(player)
	local level = CharacterProgression.level(character.level, Content.progression)
	local now = os.time()
	local data = services.PlayerDataService.getData(player)
	local inGuild = data ~= nil and data.account.guild.id ~= nil
	return DialogueRules.buildContext(character, Content.quests, level, now, QuestPools.offeredSet(Content.questPools, now, POOL_SEED), { InGuild = inGuild })
end

local function send(player: Player, session: any)
	if session == nil then
		Remotes.get("DialogueView"):FireClient(player, nil)
		return
	end
	local dialogue = Dialogue[session.conversationId]
	local view = DialogueRules.view(session.conversationId, dialogue, session.nodeId, context(player), session.seen)
	view.token = session.token
	view.speaker = Content.npcs[dialogue.npc].displayName
	view.title = Content.npcs[dialogue.npc].title
	Remotes.get("DialogueView"):FireClient(player, view)
end

local function runAction(player: Player, action: any, npcId: string)
	local kind = action.kind
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return
	end
	if kind == "AcceptQuest" then
		local ok, err = services.QuestService.accept(player, action.questId)
		if ok then
			-- Accepting a quest from someone counts as talking to them.
			services.QuestService.reportEvent(player, { kind = "Talk", target = npcId })
		else
			notify(player, "Can't take that quest: " .. tostring(err))
		end
	elseif kind == "TurnInQuest" then
		local ok, err = services.QuestService.turnIn(player, action.questId)
		if not ok then
			notify(player, "Not finished yet: " .. tostring(err))
		end
	elseif kind == "SetFlag" then
		character.story.flags = character.story.flags or {}
		character.story.flags[action.flag] = true
	elseif kind == "Awaken" then
		if character.class.classId ~= nil then
			notify(player, "Your calling is already awake.")
			return
		end
		local classId = Awakening.roll(Content.classes, function()
			return random:NextNumber()
		end)
		if classId and services.ProgressionService.assignInitialClass(player, classId, "Awakening") then
			character.story.flags = character.story.flags or {}
			character.story.flags.Awakened = true
			-- Players who have awakened another character on this account see the short ritual.
			local data = services.PlayerDataService.getData(player)
			local quick = false
			for id, other in pairs(data.characters) do
				if id ~= data.activeCharacterId and other.class.classId ~= nil then
					quick = true
				end
			end
			services.OnboardingService.playAwakening(player, classId, quick)
		end
	elseif kind == "OpenPartyBoard" then
		services.PartyService.openBoard(player)
	elseif kind == "OpenCrafting" then
		services.CraftingService.open(player, action.facilityId)
	elseif kind == "OpenShop" then
		if action.shop == "Cosmetics" then
			services.CosmeticShopService.open(player)
		else
			services.VendorService.open(player, action.shop)
		end
	elseif kind == "OpenGuildDesk" then
		services.GuildService.openDesk(player)
	elseif kind == "OpenDonations" then
		if services.RiftService ~= nil then
			services.RiftService.openDonations(player)
		else
			notify(player, "The crystal hums quietly. Contributions open with the first Rift event.")
		end
	elseif kind == "OpenRentals" then
		Remotes.get("OpenInterface"):FireClient(player, "Rentals", { innId = action.innId })
	end
end

local function startConversation(player: Player, npcId: string)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil or not isNear(player, npcId) then
		return
	end
	local npc = Content.npcs[npcId]
	if npc.opens ~= nil then
		runAction(player, { kind = npc.opens }, npcId)
		return
	end
	services.QuestService.reportEvent(player, { kind = "Talk", target = npcId })
	local conversationId = DialogueRules.select(npcId, Dialogue, context(player))
	if conversationId == nil then
		return
	end
	local dialogue = Dialogue[conversationId]
	local seen, effects = DialogueRules.begin(character.story, conversationId, dialogue, os.time())
	for _, effect in ipairs(effects) do
		runAction(player, effect, npcId)
	end
	local session = {
		conversationId = conversationId,
		nodeId = "start",
		npcId = npcId,
		seen = seen,
		token = HttpService:GenerateGUID(false),
	}
	sessions[player] = session
	send(player, session)
end

local function onAction(player: Player, token: any, action: any, index: any)
	if not limiter:allow(player) then
		return
	end
	local session = sessions[player]
	if session == nil or token ~= session.token then
		return
	end
	if action == "Close" or not isNear(player, session.npcId) then
		sessions[player] = nil
		send(player, nil)
		return
	end
	local dialogue = Dialogue[session.conversationId]
	local nextNode = session.nodeId
	if action == "Continue" then
		local view = DialogueRules.view(session.conversationId, dialogue, session.nodeId, context(player), session.seen)
		if #view.choices > 0 then
			return
		end
		nextNode = DialogueRules.advance(dialogue, session.nodeId)
	elseif action == "Skip" then
		nextNode = DialogueRules.skip(dialogue, session.nodeId, context(player))
	elseif action == "Choose" then
		local ok, result = DialogueRules.choose(dialogue, session.nodeId, index, context(player))
		if not ok then
			return
		end
		for _, item in ipairs(result.actions) do
			runAction(player, item, session.npcId)
		end
		nextNode = result.next
	else
		return
	end
	if sessions[player] ~= session then
		return
	end
	if nextNode == nil then
		sessions[player] = nil
		send(player, nil)
	else
		session.nodeId = nextNode
		send(player, session)
	end
end

-- Story entries for the journal: titles and summaries of conversations the player has had.
function DialogueService.journalEntries(player: Player): {any}
	local character = services.PlayerDataService.getCharacter(player)
	local entries = {}
	if character == nil or character.story.journal == nil then
		return entries
	end
	for conversationId, at in pairs(character.story.journal) do
		local dialogue = Dialogue[conversationId]
		if dialogue and dialogue.journal then
			table.insert(entries, { id = conversationId, title = dialogue.journal.title, summary = dialogue.journal.summary, at = at })
		end
	end
	table.sort(entries, function(a, b)
		return a.at < b.at
	end)
	return entries
end

local function setupNpc(instance: Instance)
	local npcId = instance:GetAttribute("NpcId")
	local npc = type(npcId) == "string" and Content.npcs[npcId]
	if not npc then
		warn("[Dialogue] " .. instance:GetFullName() .. " has an unknown NpcId: " .. tostring(npcId))
		return
	end
	local anchor: any = instance
	if instance:IsA("Model") then
		anchor = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	if anchor == nil or not anchor:IsA("BasePart") or anchor:FindFirstChild("TalkPrompt") then
		return
	end
	npcInstances[npcId] = instance
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = npc.actionText or "Talk"
	prompt.ObjectText = npc.displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TALK_DISTANCE - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player: Player)
		if limiter:allow(player) then
			startConversation(player, npcId)
		end
	end)
	-- Greybox NPCs are plain blocks: give each person a standing placeholder body (L-41). The block stays,
	-- invisible, as the anchor for the Talk prompt.
	if npc.opens == nil and anchor == instance then
		task.spawn(function()
			local body = Models.humanoid(Models.palettes[npcId])
			body.Name = npc.displayName
			for _, part in ipairs(body:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			body:PivotTo(CFrame.new(anchor.Position + Vector3.new(0, 0.5, 0)))
			body.Parent = instance.Parent
			anchor.Transparency = 1
			anchor.CanCollide = false
		end)
	end
end

function DialogueService.start()
	for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
		setupNpc(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(setupNpc)
	Remotes.get("DialogueAction").OnServerEvent:Connect(onAction)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		sessions[player] = nil
		limiter:forget(player)
	end)
end

return DialogueService
