--!strict
-- Quests on the server (L-30, L-42). Quests are accepted and turned in through NPCs (DialogueService);
-- progress comes from server events (talking and gathering now, combat and crafting later). Players
-- review quests in the journal, opened on request. There is no permanent on-screen tracker (L-42).
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local QuestRules = require(Server.Domain.QuestRules)
local Outbox = require(Server.Domain.Outbox)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local QuestService = {}
local services: any = nil
local limiter = RateLimiter.new(3, 1, os.clock)

function QuestService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

function QuestService.accept(player: Player, questId: any): (boolean, string?)
	local character = services.PlayerDataService.getCharacter(player)
	local def = type(questId) == "string" and Content.quests[questId]
	if character == nil or not def then
		return false, "quest not available"
	end
	local level = CharacterProgression.level(character.level, Content.progression)
	local flags = table.clone(character.story.flags or {})
	local data = services.PlayerDataService.getData(player)
	flags.InGuild = data ~= nil and data.account.guild.id ~= nil
	local ok, err = QuestRules.accept(character.quests, def, level, os.time(), flags)
	if ok then
		notify(player, "Quest accepted: " .. def.displayName)
		if def.guidance ~= nil then
			Remotes.get("OpenInterface"):FireClient(player, "Guidance", { locationId = def.guidance.locationId, seconds = def.guidance.seconds })
		end
	end
	return ok, err
end

function QuestService.turnIn(player: Player, questId: any): (boolean, string?)
	local data = services.PlayerDataService.getData(player)
	local def = type(questId) == "string" and Content.quests[questId]
	if data == nil or not def then
		return false, "quest not available"
	end
	local ok, result = QuestRules.turnIn(data, data.activeCharacterId, def, Content.items, services.InventoryService.deps(player))
	if not ok then
		return false, result
	end
	if result.characterXp > 0 then
		services.ProgressionService.grantCharacterXp(player, result.characterXp, "Quest")
	end
	if (result.guildXp or 0) > 0 and data.account.guild.id ~= nil then
		local id = "guildxp:" .. HttpService:GenerateGUID(false)
		Outbox.add(data.account, id, { kind = "GuildXp", guildId = data.account.guild.id, amount = result.guildXp, source = "GuildQuest", at = os.time() })
		task.spawn(services.OutboxService.deliverNow, player)
	end
	for professionId, xp in pairs(result.professionXp) do
		services.ProgressionService.grantProfessionXp(player, professionId, xp)
	end
	services.InventoryService.sendSnapshot(player)
	notify(player, "Quest complete: " .. def.displayName)
	if (def.rewards.gold or 0) > 0 then
		task.spawn(services.GuildService.taxReward, player, def.rewards.gold, "QuestReward")
	end
	return true, nil
end

-- Server-verified events only: { kind = "Talk" | "Gather" | "Kill" | "Craft", target, amount }.
function QuestService.reportEvent(player: Player, event: any)
	local character = services.PlayerDataService.getCharacter(player)
	if character ~= nil then
		QuestRules.applyEvent(character.quests, Content.quests, event)
	end
end

-- For the journal interface: quests with progress, and story entries from conversations.
function QuestService.journal(player: Player): any
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return nil
	end
	local active, completed = {}, {}
	for questId, state in pairs(character.quests) do
		local def = Content.quests[questId]
		if def then
			local objectives = {}
			for _, objective in ipairs(def.objectives) do
				table.insert(objectives, {
					kind = objective.kind,
					target = objective.target,
					count = objective.count,
					progress = state.progress[objective.id] or 0,
				})
			end
			local entry = { id = questId, name = def.displayName, main = def.main == true, objectives = objectives }
			if state.state == "Active" then
				table.insert(active, entry)
			else
				table.insert(completed, entry)
			end
		end
	end
	return { active = active, completed = completed, story = services.DialogueService.journalEntries(player) }
end

function QuestService.start()
	Remotes.get("RequestJournal").OnServerEvent:Connect(function(player: Player)
		if limiter:allow(player) then
			Remotes.get("Snapshot"):FireClient(player, "Journal", QuestService.journal(player))
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		limiter:forget(player)
	end)
end

return QuestService
