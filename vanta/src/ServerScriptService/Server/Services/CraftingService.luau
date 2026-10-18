--!strict
-- Crafting at workshops (L-31, L-32). A craftsman's conversation opens the workshop for a few minutes; the
-- server plans every craft with the shared crafting rules and applies it as one transaction (materials and
-- fee out, item with its permanent crafting record in), then grants profession XP and the quest event.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Curve = require(Shared.Domain.Curve)
local Crafting = require(Server.Domain.Crafting)
local QuestRules = require(Server.Domain.QuestRules)
local Transaction = require(Server.Domain.Transaction)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local SESSION_SECONDS = 300

local CraftingService = {}
local services: any = nil
local sessions: {[Player]: any} = {}
local limiter = RateLimiter.new(3, 1, os.clock)
local random = Random.new()

function CraftingService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function context(player: Player, character: any, recipe: any): any
	local level = 1
	if recipe ~= nil then
		local state = character.professions[recipe.profession]
		level = Curve.progress(Content.professions[recipe.profession].curve, (state and state.xp) or 0)
	end
	return {
		recipes = Content.recipes,
		facilities = Content.facilities,
		items = Content.items,
		rules = Content.crafting,
		inventory = character.inventory,
		gold = character.currencies.Gold or 0,
		professionLevel = level,
		knownRecipes = character.recipes,
		completedQuests = QuestRules.completedSet(character.quests),
		crafter = { userId = player.UserId, name = player.DisplayName },
	}
end

-- What the workshop window shows: each recipe, its materials, and why it can't be made yet, if it can't.
function CraftingService.view(player: Player, facilityId: string): any
	local facility = Content.facilities[facilityId]
	local character = services.PlayerDataService.getCharacter(player)
	if facility == nil or character == nil then
		return nil
	end
	local ids = {}
	for recipeId in pairs(facility.recipes) do
		table.insert(ids, recipeId)
	end
	table.sort(ids)
	local recipes = {}
	for _, recipeId in ipairs(ids) do
		local recipe = Content.recipes[recipeId]
		if recipe ~= nil then
			local inputs = {}
			for _, input in ipairs(recipe.inputs) do
				table.insert(inputs, { itemId = input.itemId, name = Content.items[input.itemId].displayName, amount = input.amount })
			end
			local planContext = context(player, character, recipe)
			local ok, reason = Crafting.plan(recipeId, facilityId, planContext, function()
				return 0.5
			end)
			-- what it makes, and (for equipment) the rarity chances at the crafter's level: shown, not rolled
			local outputDef = recipe.output and Content.items[recipe.output.itemId]
			local levelsAbove = planContext.professionLevel - recipe.minProfessionLevel
			local chances = nil
			if outputDef ~= nil and outputDef.kind == "Equipment" and levelsAbove >= 0 and planContext.rules ~= nil and planContext.rules.rarity ~= nil then
				chances = Crafting.rarityChances(levelsAbove, recipe, planContext.rules.rarity) -- the same rules the craft rolls with
			end
			table.insert(recipes, {
				id = recipeId,
				name = recipe.displayName,
				profession = Content.professions[recipe.profession].displayName,
				minLevel = recipe.minProfessionLevel,
				yourLevel = planContext.professionLevel,
				output = if outputDef then { name = outputDef.displayName, amount = recipe.output.amount or 1, equipment = outputDef.kind == "Equipment", itemLevel = recipe.itemLevel } else nil,
				chances = chances,
				inputs = inputs,
				blocked = (not ok) and tostring(reason) or nil,
			})
		end
	end
	return { facilityId = facilityId, name = facility.displayName, fee = facility.fee or 0, recipes = recipes }
end

function CraftingService.open(player: Player, facilityId: any)
	local view = type(facilityId) == "string" and CraftingService.view(player, facilityId)
	if not view then
		return
	end
	sessions[player] = { facilityId = facilityId, untilTime = os.clock() + SESSION_SECONDS }
	Remotes.get("OpenInterface"):FireClient(player, "Crafting", view)
end

local function onCraft(player: Player, recipeId: any)
	local session = sessions[player]
	if not limiter:allow(player) or session == nil or os.clock() > session.untilTime then
		return
	end
	local facility = Content.facilities[session.facilityId]
	local recipe = type(recipeId) == "string" and Content.recipes[recipeId]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if not recipe or not facility.recipes[recipeId] or data == nil or character == nil then
		return
	end
	local ok, plan = Crafting.plan(recipeId, session.facilityId, context(player, character, recipe), function()
		return random:NextNumber()
	end)
	if not ok then
		notify(player, "Can't craft that: " .. tostring(plan))
		return
	end
	local applied, err = Transaction.apply(data, data.activeCharacterId, {
		id = "craft:" .. HttpService:GenerateGUID(false),
		reason = "Craft",
		changes = plan.changes,
	}, services.InventoryService.deps(player))
	if not applied then
		notify(player, "Can't craft that: " .. tostring(err))
		return
	end
	services.ProgressionService.grantProfessionXp(player, plan.profession, plan.professionXp)
	services.QuestService.reportEvent(player, { kind = "Craft", target = recipeId, amount = 1 })
	notify(player, string.format("You craft %s (%s%s).", recipe.displayName, if plan.rarity ~= nil then tostring(plan.rarity) .. ", " else "", tostring(plan.quality)))
	services.InventoryService.sendSnapshot(player)
	Remotes.get("OpenInterface"):FireClient(player, "Crafting", CraftingService.view(player, session.facilityId))
end

function CraftingService.start()
	Remotes.get("CraftRequest").OnServerEvent:Connect(onCraft)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		sessions[player] = nil
		limiter:forget(player)
	end)
end

return CraftingService
