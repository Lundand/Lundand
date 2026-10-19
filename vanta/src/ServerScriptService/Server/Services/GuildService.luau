--!strict
-- Player guilds on shared records (L-30, L-48, L-54). The guild desk at the Adventurers' Guild (through the Guild
-- Registrar) lists guilds by level, founds new ones and manages your own; the planning table in a guild's hall
-- will open the same view once halls are placed. Every change runs inside one update of the guild record, with
-- upkeep settled first. Founding takes the fee first and notes it in the save; if the name or record can't be
-- made, the fee comes back, also on the next join if a server stopped halfway.
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local GuildRules = require(Server.Domain.GuildRules)
local GuildEconomy = require(Server.Domain.GuildEconomy)
local Outbox = require(Server.Domain.Outbox)
local PropertyOwnership = require(Server.Domain.PropertyOwnership)
local Transaction = require(Server.Domain.Transaction)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local DESK_SECONDS = 600

local GuildService = {}
local services: any = nil
local limiter = RateLimiter.new(4, 1, os.clock)
local deskOpenUntil: {[Player]: number} = {}
local invitations: {[Player]: any} = {}

function GuildService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function newId(): string
	return (string.gsub(HttpService:GenerateGUID(false), "-", ""))
end

local function guilds(): any
	return services.SharedRecordService.store("Guilds")
end

local function names(): any
	return services.SharedRecordService.store("GuildNames")
end

local function properties(): any
	return services.SharedRecordService.store("Properties")
end

local function updateRanking(record: any)
	task.spawn(function()
		pcall(function()
			local level = GuildEconomy.level(record.xp, Content.guilds)
			DataStoreService:GetOrderedDataStore("GuildRanking"):SetAsync(record.id, GuildEconomy.leaderboardScore(level, record.xp))
		end)
	end)
end

local function allowedName(player: Player, name: string): boolean
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return ok and result == name
end

-- Runs a guild action inside one update of its record, settling upkeep first.
local function change(guildId: string, action: (any) -> (boolean, any)): (boolean, any)
	local now = os.time()
	local ok, answer = guilds():update(guildId, function(record: any)
		if record == nil or record.disbanded then
			return nil, { false, "that guild no longer exists" }
		end
		GuildEconomy.settleMaintenance(record, now, Content.guilds)
		local done, result = action(record)
		return record, { done, result }
	end)
	if not ok or answer == nil then
		return false, "the guild archive can't be reached; try again"
	end
	return answer[1], answer[2]
end

local function deskView(player: Player): any
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if data == nil or character == nil then
		return nil
	end
	local rules = Content.guilds
	local level = CharacterProgression.level(character.level, Content.progression)
	local gold = character.currencies.Gold or 0
	local mine = nil
	if data.account.guild.id ~= nil then
		local ok, record = guilds():read(data.account.guild.id)
		if ok and record ~= nil and not record.disbanded then
			mine = GuildEconomy.summary(record, player.UserId, rules)
		end
	end
	local ranking = {}
	local ok, pages = pcall(function()
		return DataStoreService:GetOrderedDataStore("GuildRanking"):GetSortedAsync(false, 20)
	end)
	if ok then
		for _, entry in ipairs(pages:GetCurrentPage()) do
			local readOk, record = guilds():read(entry.key)
			if readOk and record ~= nil and not record.disbanded then
				table.insert(ranking, {
					id = record.id,
					name = record.name,
					emblemAssetId = record.emblemAssetId,
					level = GuildEconomy.level(record.xp, rules),
					xp = record.xp,
					createdAt = record.createdAt,
					members = GuildRules.memberCount(record),
					taxRate = record.taxRate,
				})
			end
		end
	end
	local invitable = {}
	if mine ~= nil and mine.permissions.invite then
		for _, other in ipairs(Players:GetPlayers()) do
			local otherData = services.PlayerDataService.getData(other)
			if other ~= player and otherData ~= nil and GuildRules.canJoin(otherData.account) then
				table.insert(invitable, { userId = other.UserId, name = other.DisplayName })
			end
		end
	end
	local canFound, foundReason = GuildRules.canCreate(data.account, level, gold, rules)
	return {
		mine = mine,
		ranking = GuildEconomy.rank(ranking),
		invitation = invitations[player],
		invitable = invitable,
		taxRates = rules.taxRates,
		ranks = rules.ranks,
		founding = { cost = rules.creationCost, minLevel = rules.minLeaderLevel, level = level, gold = gold, canFound = canFound, reason = foundReason, nameMin = rules.nameMinLength, nameMax = rules.nameMaxLength },
	}
end

-- Finishes a hall purchase: claims the building for the guild, or refunds the treasury if someone else got it
-- first. Safe to run again at any time; it runs whenever the guild's view is opened.
local function settleHall(guildId: string)
	local ok, record = guilds():read(guildId, 0)
	local pending = ok and record ~= nil and record.hallPending
	if not pending then
		return
	end
	local claimed, ours = properties():update(pending.propertyId, function(property: any)
		local current = property or PropertyOwnership.newRecord(pending.propertyId)
		if current.owner ~= nil then
			return nil, current.owner.guildId == guildId
		end
		current.owner = { userId = record.leaderUserId, name = record.name, guildId = guildId, since = os.time(), operationId = pending.operationId }
		return current, true
	end)
	if not claimed then
		return
	end
	change(guildId, function(current: any)
		local hall = current.hallPending
		current.hallPending = nil
		if hall ~= nil and not ours then
			GuildEconomy.refundHall(current, hall.price, os.time(), Content.guilds)
		end
		return true, nil
	end)
end

-- For the property window: whether the viewer can buy this hall for their guild, and why not.
function GuildService.hallOffer(player: Player, propertyId: string): any
	local data = services.PlayerDataService.getData(player)
	local guildId = data and data.account.guild.id
	local property = Content.world.properties[propertyId]
	if guildId == nil or property == nil then
		return nil
	end
	local ok, record = guilds():read(guildId)
	if not ok or record == nil then
		return nil
	end
	local rules = Content.guilds
	local price = services.PropertyService.priceOf(propertyId) :: number
	local member = record.members[tostring(player.UserId)]
	local reason = nil
	if member == nil or not rules.permissions[member.rank].spend then
		reason = "only your guild's leader can buy a hall"
	elseif record.hallPropertyId ~= nil then
		reason = "your guild already has a hall"
	elseif GuildEconomy.level(record.xp, rules) < rules.hallRequiredLevel then
		reason = string.format("your guild needs level %d", rules.hallRequiredLevel)
	elseif record.treasury < price then
		reason = string.format("the treasury has %d of %d gold", record.treasury, price)
	end
	return { guildName = record.name, price = price, allowed = reason == nil, reason = reason }
end

function GuildService.buyHall(player: Player, propertyId: any)
	local property = type(propertyId) == "string" and Content.world.properties[propertyId]
	local data = services.PlayerDataService.getData(player)
	local guildId = data and data.account.guild.id
	if not property or property.kind ~= Content.propertyRules.guildHall.kind or guildId == nil then
		return
	end
	local price = services.PropertyService.priceOf(propertyId) :: number
	local operationId = "hall:" .. newId()
	local now = os.time()
	local ok, result = change(guildId, function(record: any)
		local bought, reason = GuildEconomy.buyHall(record, player.UserId, propertyId, price, operationId, now, Content.guilds)
		if bought then
			record.hallPending = { propertyId = propertyId, price = price, operationId = operationId }
		end
		return bought, reason
	end)
	if not ok then
		notify(player, "Can't buy the hall: " .. tostring(result))
		return
	end
	settleHall(guildId)
	local readOk, record = guilds():read(guildId, 0)
	if readOk and record ~= nil and record.hallPropertyId == propertyId then
		notify(player, "The hall is your guild's.")
	else
		notify(player, "Someone else got that hall first. The treasury was refunded.")
	end
end

function GuildService.openDesk(player: Player, focus: string?)
	deskOpenUntil[player] = os.clock() + DESK_SECONDS
	local data = services.PlayerDataService.getData(player)
	if data ~= nil and data.account.guild.id ~= nil then
		settleHall(data.account.guild.id)
	end
	local view = deskView(player)
	if view ~= nil then
		view.focus = focus
	end
	if view ~= nil then
		Remotes.get("OpenInterface"):FireClient(player, "GuildDesk", view)
	end
end

local function finishFounding(player: Player, created: boolean)
	local data = services.PlayerDataService.getData(player)
	local pending = data and data.account.guild.pendingFounding
	if pending == nil then
		return
	end
	if created then
		data.account.guild = { id = pending.guildId, joinedAt = os.time() }
		local ok, record = guilds():read(pending.guildId, 0)
		if ok and record ~= nil then
			updateRanking(record)
		end
		notify(player, "Your guild is founded: " .. pending.name .. ".")
		return
	end
	Transaction.apply(data, pending.characterId, {
		id = "found-refund:" .. pending.guildId,
		reason = "GuildFoundingRefund",
		changes = { { type = "AdjustCurrency", currency = "Gold", amount = Content.guilds.creationCost } },
	}, services.InventoryService.deps(player))
	names():update(GuildRules.nameKey(pending.name), function(entry: any)
		if entry ~= nil and entry.guildId == pending.guildId then
			return { released = true }, nil
		end
		return nil, nil
	end)
	data.account.guild = {}
	notify(player, "The guild couldn't be founded (the name may be taken). Your gold was returned.")
	services.InventoryService.sendSnapshot(player)
end

local function found(player: Player, name: any, emblemAssetId: any)
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if data == nil or character == nil then
		return
	end
	local rules = Content.guilds
	local level = CharacterProgression.level(character.level, Content.progression)
	local ok, reason = GuildRules.canCreate(data.account, level, character.currencies.Gold or 0, rules)
	if ok then
		ok, reason = GuildRules.validName(name, rules)
	end
	if ok and not allowedName(player, name) then
		ok, reason = false, "that name isn't allowed"
	end
	if not ok then
		notify(player, "Can't found a guild: " .. tostring(reason))
		return
	end
	local guildId = newId()
	local now = os.time()
	local charged = Transaction.apply(data, data.activeCharacterId, {
		id = "found:" .. guildId,
		reason = "GuildFounding",
		changes = { { type = "AdjustCurrency", currency = "Gold", amount = -rules.creationCost } },
	}, services.InventoryService.deps(player))
	if not charged then
		notify(player, "Can't found a guild: not enough gold")
		return
	end
	data.account.guild = { pendingFounding = { guildId = guildId, name = name, characterId = data.activeCharacterId, at = now } }
	local claimed, free = names():update(GuildRules.nameKey(name), function(entry: any)
		if entry ~= nil and entry.guildId ~= nil and entry.guildId ~= guildId then
			return nil, false
		end
		return { guildId = guildId }, true
	end)
	local created = false
	if claimed and free then
		local wrote, answer = guilds():update(guildId, function(record: any)
			if record ~= nil then
				return nil, true
			end
			local fresh = GuildRules.newRecord(guildId, name, player.UserId, player.DisplayName, now)
			local emblem = tonumber(emblemAssetId)
			if emblem ~= nil and GuildEconomy.validEmblemId(emblem) then
				GuildEconomy.setEmblem(fresh, player.UserId, emblem, now, rules)
			end
			return fresh, true
		end)
		created = wrote and answer == true
	end
	finishFounding(player, created)
end

-- On join: finish or refund an interrupted founding, and drop membership of a guild that left you.
local function reconcile(player: Player)
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return
	end
	local pending = data.account.guild.pendingFounding
	if pending ~= nil then
		local ok, record = guilds():read(pending.guildId, 0)
		if ok then
			finishFounding(player, record ~= nil and record.leaderUserId == player.UserId)
		end
	elseif data.account.guild.id ~= nil then
		local ok, record = guilds():read(data.account.guild.id, 0)
		if ok and (record == nil or GuildRules.reconcileMembership(data.account, record, player.UserId)) then
			if record == nil then
				data.account.guild = {}
			end
			notify(player, "You are no longer in your guild.")
		end
	end
end

-- Guild tax on an eligible gold reward (L-48): taken from the player now, delivered to the treasury later.
function GuildService.taxReward(player: Player, amount: number, source: string)
	local data = services.PlayerDataService.getData(player)
	local guildId = data and data.account.guild.id
	if guildId == nil or not Content.guilds.taxableSources[source] then
		return
	end
	local ok, record = guilds():read(guildId)
	if not ok or record == nil or (record.taxRate or 0) <= 0 or record.members[tostring(player.UserId)] == nil then
		return
	end
	local _, tax = GuildEconomy.splitTax(amount, record.taxRate)
	if tax <= 0 then
		return
	end
	local id = "tax:" .. newId()
	local applied = Transaction.apply(data, data.activeCharacterId, {
		id = id,
		reason = "GuildTax",
		changes = { { type = "AdjustCurrency", currency = "Gold", amount = -tax } },
	}, services.InventoryService.deps(player))
	if applied then
		Outbox.add(data.account, id, { kind = "GuildTax", guildId = guildId, amount = tax, userId = player.UserId, characterId = data.activeCharacterId, at = os.time() })
		notify(player, string.format("%d gold went to your guild's treasury (%d%% guild tax).", tax, record.taxRate))
		services.InventoryService.sendSnapshot(player)
	end
end

local function deliverTax(id: string, entry: any): (boolean, any)
	local ok, answer = guilds():update(entry.guildId, function(record: any)
		if record == nil or record.disbanded then
			return nil, "gone"
		end
		GuildEconomy.creditTax(record, id, entry.amount, entry.userId, os.time(), Content.guilds)
		return record, "credited"
	end)
	if not ok then
		return false, nil
	end
	if answer == "gone" then
		return true, { { type = "AdjustCurrency", currency = "Gold", amount = entry.amount } }
	end
	return true, nil
end

local function onRequest(player: Player, action: any, args: any)
	if not limiter:allow(player) or type(action) ~= "string" or (deskOpenUntil[player] or 0) < os.clock() then
		return
	end
	if type(args) ~= "table" then
		args = {}
	end
	local data = services.PlayerDataService.getData(player)
	if data == nil then
		return
	end
	local rules = Content.guilds
	local now = os.time()
	local guildId = data.account.guild.id
	local ok, result = true, nil
	if action == "Found" then
		found(player, args.name, args.emblemAssetId)
	elseif action == "Accept" then
		local invitation = invitations[player]
		if invitation ~= nil and GuildRules.canJoin(data.account) then
			ok, result = change(invitation.guildId, function(record: any)
				return GuildRules.accept(record, player.UserId, player.DisplayName, now, rules)
			end)
			if ok then
				data.account.guild = { id = invitation.guildId, joinedAt = now }
			end
			invitations[player] = nil
		end
	elseif action == "Decline" then
		invitations[player] = nil
	elseif guildId == nil then
		return
	elseif action == "Invite" then
		local target = type(args.userId) == "number" and Players:GetPlayerByUserId(args.userId)
		if not target then
			return
		end
		local guildName = nil
		ok, result = change(guildId, function(record: any)
			guildName = record.name
			return GuildRules.invite(record, player.UserId, target.UserId, now, rules)
		end)
		if ok then
			invitations[target] = { guildId = guildId, name = guildName, from = player.DisplayName }
			notify(target, string.format("%s invited you to the guild %s. Accept at the guild desk in the Adventurers' Guild.", player.DisplayName, tostring(guildName)))
		end
	elseif action == "Leave" then
		ok, result = change(guildId, function(record: any)
			return GuildRules.leave(record, player.UserId)
		end)
		if ok then
			data.account.guild = {}
		end
	elseif action == "Kick" then
		ok, result = change(guildId, function(record: any)
			return GuildRules.kick(record, player.UserId, args.userId, rules)
		end)
		local target = ok and type(args.userId) == "number" and Players:GetPlayerByUserId(args.userId)
		local targetData = target and services.PlayerDataService.getData(target)
		if targetData ~= nil and targetData.account.guild.id == guildId then
			targetData.account.guild = {}
		end
	elseif action == "TransferLeadership" then
		ok, result = change(guildId, function(record: any)
			return GuildRules.transferLeadership(record, player.UserId, args.userId, rules)
		end)
	elseif action == "Disband" then
		local guildName, hall = nil, nil
		ok, result = change(guildId, function(record: any)
			guildName, hall = record.name, record.hallPropertyId
			if args.confirmName ~= record.name then
				return false, "type the guild's exact name to confirm"
			end
			return GuildRules.disband(record, player.UserId)
		end)
		if ok then
			data.account.guild = {}
			names():update(GuildRules.nameKey(guildName), function(entry: any)
				if entry ~= nil and entry.guildId == guildId then
					return { released = true }, nil
				end
				return nil, nil
			end)
			pcall(function()
				DataStoreService:GetOrderedDataStore("GuildRanking"):RemoveAsync(guildId)
			end)
			if hall ~= nil then
				properties():update(hall, function(property: any)
					if property ~= nil and property.owner ~= nil and property.owner.guildId == guildId then
						property.owner = nil
						return property, nil
					end
					return nil, nil
				end)
			end
			notify(player, "The guild has been disbanded.")
		end
	elseif action == "SetRank" then
		ok, result = change(guildId, function(record: any)
			return GuildRules.setRank(record, player.UserId, args.userId, args.rank, rules)
		end)
	elseif action == "SetTax" then
		ok, result = change(guildId, function(record: any)
			return GuildEconomy.setTaxRate(record, player.UserId, args.rate, rules)
		end)
	elseif action == "BuyUpgrade" then
		local operationId = "upgrade:" .. newId()
		ok, result = change(guildId, function(record: any)
			return GuildEconomy.buyUpgrade(record, player.UserId, args.upgradeId, operationId, now, rules)
		end)
	elseif action == "SetEmblem" then
		ok, result = change(guildId, function(record: any)
			return GuildEconomy.setEmblem(record, player.UserId, tonumber(args.assetId) or args.assetId, now, rules)
		end)
	elseif action == "Restore" then
		ok, result = change(guildId, function(record: any)
			return GuildEconomy.restore(record, player.UserId, now, rules)
		end)
	elseif action ~= "Refresh" then
		return
	end
	if not ok then
		notify(player, "Guild: " .. tostring(result))
	end
	GuildService.openDesk(player)
end

local function deliverGuildXp(id: string, entry: any): (boolean, any)
	local ok, record = guilds():update(entry.guildId, function(current: any)
		if current == nil or current.disbanded then
			return nil, nil
		end
		GuildEconomy.addXp(current, id, entry.amount, entry.source, Content.guilds)
		return current, current
	end)
	if not ok then
		return false, nil
	end
	if record ~= nil then
		updateRanking(record)
	end
	return true, nil
end

-- Planning tables in guild halls open the guild's management view, for that guild's members only.
local function setupPlanningTable(planning: Instance)
	local propertyId = planning:GetAttribute("PropertyId")
	if not planning:IsA("BasePart") or type(propertyId) ~= "string" or planning:FindFirstChild("PlanPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlanPrompt"
	prompt.ActionText = "Plan"
	prompt.ObjectText = "Planning table"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = planning
	prompt.Triggered:Connect(function(player: Player)
		if not limiter:allow(player) then
			return
		end
		local data = services.PlayerDataService.getData(player)
		local guildId = data and data.account.guild.id
		local ok, record = false, nil
		if guildId ~= nil then
			ok, record = guilds():read(guildId)
		end
		if ok and record ~= nil and record.hallPropertyId == propertyId then
			GuildService.openDesk(player, "My guild")
		else
			notify(player, "This planning table belongs to another guild's hall.")
		end
	end)
end

function GuildService.start()
	Remotes.get("GuildRequest").OnServerEvent:Connect(onRequest)
	services.OutboxService.register("GuildTax", deliverTax)
	services.OutboxService.register("GuildXp", deliverGuildXp)
	for _, planning in ipairs(CollectionService:GetTagged("PlanningTable")) do
		setupPlanningTable(planning)
	end
	CollectionService:GetInstanceAddedSignal("PlanningTable"):Connect(setupPlanningTable)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		task.spawn(reconcile, player)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		deskOpenUntil[player] = nil
		invitations[player] = nil
		limiter:forget(player)
	end)
end

return GuildService
