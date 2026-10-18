--!strict
-- Buying buildings (L-28, L-54). For-sale signs (parts tagged PropertySign with a PropertyId attribute) and the
-- counters of shops for sale open the property window. What a building costs depends on where it stands: its tier's
-- price moved by the foot traffic of its spot (Domain.PropertyPricing), so a shop on the square costs far more than one
-- in a back lane. A purchase follows PropertyOwnership's four steps across the shared record and the buyer's save:
-- reserve, charge, commit, record. Anything interrupted is settled when the buyer next joins: they get the building or
-- their gold back.
-- Entering is separate from owning: a house's door leads to its instanced interior (InteriorService), which lets in
-- anyone while the house is unowned and afterwards only those the owner allows. Owners choose Private, Friends or
-- Public from the property window; InteriorService shows out anyone no longer allowed.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local PropertyOwnership = require(Server.Domain.PropertyOwnership)
local PropertyPricing = require(Server.Domain.PropertyPricing)
local Layout = require(game:GetService("ServerStorage"):WaitForChild("ServerData").CityLayout)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local STORE = "Properties"
local SIGN_DISTANCE = 12
local KIND_NAMES = { House = "Home", Shop = "Shop", GuildHall = "Guild hall" }
local ACCESS_MODES = { "Private", "Friends", "Public" }

local PropertyService = {}
local services: any = nil
local limiter = RateLimiter.new(6, 1, os.clock)
local viewing: {[Player]: string} = {}

function PropertyService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function records(): any
	return services.SharedRecordService.store(STORE)
end

-- Each property's foot traffic, from the city layout: it sets the price (Domain.PropertyPricing).
local traffic: {[string]: number}? = nil
local function trafficOf(propertyId: string): number?
	if traffic == nil then
		local found = {}
		for _, entry in ipairs(Layout.blocks) do
			if entry.propertyId ~= nil then
				found[entry.propertyId] = entry.traffic
			end
		end
		traffic = found
	end
	return (traffic :: {[string]: number})[propertyId]
end

local function priceOf(property: any): number
	return PropertyPricing.priceOf(property, trafficOf(property.id), Content.propertyRules)
end

-- What a property costs where it stands (guild halls use this too).
function PropertyService.priceOf(propertyId: string): number?
	local property = Content.world.properties[propertyId]
	return if property ~= nil then priceOf(property) else nil
end

local function view(player: Player, propertyId: string): any
	local property = Content.world.properties[propertyId]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if property == nil or data == nil or character == nil then
		return nil
	end
	local readable, record = records():read(propertyId)
	local owner = readable and record and record.owner
	local district = Content.world.districts[property.district]
	local result: any = {
		id = propertyId,
		kind = KIND_NAMES[property.kind] or property.kind,
		district = (district and district.displayName) or property.district,
		price = priceOf(property),
		traffic = PropertyPricing.trafficLabel(trafficOf(propertyId)),
		gold = character.currencies.Gold or 0,
		ownerName = owner and owner.name,
		readable = readable,
		isShop = property.kind == "Shop",
		isMine = owner ~= nil and owner.userId == player.UserId,
		accessMode = readable and record and record.permissions and record.permissions.mode or "Private",
		accessModes = ACCESS_MODES,
	}
	if property.kind == Content.propertyRules.guildHall.kind then
		result.note = string.format("Guild halls are bought by a guild's leader, from the guild treasury, from guild level %d.", Content.guilds.hallRequiredLevel)
		if readable and owner == nil then
			result.hallOffer = services.GuildService.hallOffer(player, propertyId)
		end
	elseif readable and owner == nil then
		local can, reason = PropertyOwnership.canAcquire(data.account, property, Content.propertyRules)
		result.canBuy = can
		result.reason = reason
	end
	return result
end

local function open(player: Player, propertyId: string)
	local result = view(player, propertyId)
	if result ~= nil then
		viewing[player] = propertyId
		Remotes.get("OpenInterface"):FireClient(player, "Property", result)
	end
end

-- Opens a property's window (its deed) for a player standing at it: the deed plaque, or a shop's counter.
function PropertyService.open(player: Player, propertyId: string)
	if Content.world.properties[propertyId] ~= nil then
		open(player, propertyId)
	end
end

function PropertyService.isViewing(player: Player, propertyId: any): boolean
	return viewing[player] ~= nil and viewing[player] == propertyId
end

-- Settles purchases that were interrupted, against the shared records.
function PropertyService.reconcile(player: Player)
	local data = services.PlayerDataService.getData(player)
	if data == nil or next(data.account.pendingPurchases) == nil then
		return
	end
	local outcomes = PropertyOwnership.reconcile(data, player.UserId, function(propertyId: string): any
		local ok, record = records():read(propertyId, 0)
		if not ok then
			return nil
		end
		return record or PropertyOwnership.newRecord(propertyId)
	end, services.InventoryService.deps(player))
	for _, outcome in ipairs(outcomes) do
		if outcome.outcome == "Owned" then
			notify(player, "Your purchase finished: the building is yours.")
			services.InteriorService.recheck(outcome.propertyId)
		elseif outcome.outcome == "Refunded" then
			notify(player, "A building purchase didn't finish. Your gold was returned.")
		end
	end
	services.InventoryService.sendSnapshot(player)
end

local function buy(player: Player, propertyId: any)
	local property = type(propertyId) == "string" and Content.world.properties[propertyId]
	local data = services.PlayerDataService.getData(player)
	if not property or viewing[player] ~= propertyId or data == nil then
		return
	end
	local rules = Content.propertyRules
	local can, reason = PropertyOwnership.canAcquire(data.account, property, rules)
	if not can then
		notify(player, "Can't buy: " .. tostring(reason))
		return
	end
	local operationId = "property:" .. HttpService:GenerateGUID(false)
	local now = os.time()
	local reserved, answer = records():update(propertyId, function(record: any)
		local current = record or PropertyOwnership.newRecord(propertyId)
		local ok, err = PropertyOwnership.reserve(current, player.UserId, operationId, now, rules)
		if not ok then
			return nil, err
		end
		return current, true
	end)
	if not reserved or answer ~= true then
		notify(player, "Can't buy: " .. tostring(answer or "please try again"))
		return
	end
	local charged, err = PropertyOwnership.beginPurchase(data, data.activeCharacterId, property, priceOf(property), operationId, rules, services.InventoryService.deps(player))
	if not charged then
		notify(player, "Can't buy: " .. tostring(err))
		return
	end
	local committed, result = records():update(propertyId, function(record: any)
		if record == nil then
			return nil, "the record is missing"
		end
		local ok, commitErr = PropertyOwnership.commit(record, player.UserId, player.DisplayName, operationId, now)
		if not ok then
			return nil, commitErr
		end
		return record, true
	end)
	if committed and result == true then
		PropertyOwnership.finishPurchase(data, operationId)
		notify(player, "The building is yours.")
		-- anyone looking round it while it was for sale is shown out: a new home is private
		services.InteriorService.recheck(propertyId)
		if property.kind == "Shop" then
			task.spawn(services.ShopService.refresh, propertyId)
		end
	else
		PropertyService.reconcile(player)
	end
	services.InventoryService.sendSnapshot(player)
	open(player, propertyId)
end

local function setAccess(player: Player, propertyId: any, mode: any)
	local data = services.PlayerDataService.getData(player)
	if type(propertyId) ~= "string" or viewing[player] ~= propertyId or data == nil or data.account.properties[propertyId] == nil then
		return
	end
	local ok, answer = records():update(propertyId, function(record: any): (any, any)
		if record == nil then
			return nil, "the deed can't be found"
		end
		-- keep the owner's list of named guests; only the mode changes here
		local allowed = {}
		for visitorId in pairs(record.permissions.allowed or {}) do
			table.insert(allowed, tonumber(visitorId))
		end
		local changed, err = PropertyOwnership.setPermissions(record, player.UserId, mode, allowed, Content.propertyRules)
		if not changed then
			return nil, err
		end
		return record, true
	end)
	if ok and answer == true then
		notify(player, "Your home is now " .. string.lower(tostring(mode)) .. ".")
		services.InteriorService.recheck(propertyId)
	else
		notify(player, "Couldn't change who may enter: " .. tostring(answer))
	end
	open(player, propertyId)
end

local function setupSign(sign: Instance)
	local propertyId = sign:GetAttribute("PropertyId")
	if not sign:IsA("BasePart") or type(propertyId) ~= "string" or Content.world.properties[propertyId] == nil or sign:FindFirstChild("ViewPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ViewPrompt"
	prompt.ActionText = "View"
	prompt.ObjectText = "Property"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SIGN_DISTANCE - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
	prompt.Triggered:Connect(function(player: Player)
		local root: any = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if limiter:allow(player) and root ~= nil and (root.Position - sign.Position).Magnitude <= SIGN_DISTANCE then
			open(player, propertyId)
		end
	end)
end

function PropertyService.start()
	for _, sign in ipairs(CollectionService:GetTagged("PropertySign")) do
		setupSign(sign)
	end
	CollectionService:GetInstanceAddedSignal("PropertySign"):Connect(setupSign)
	Remotes.get("PropertyRequest").OnServerEvent:Connect(function(player: Player, action: any, propertyId: any, mode: any)
		if action == "Buy" and limiter:allow(player) then
			buy(player, propertyId)
		elseif action == "SetAccess" and limiter:allow(player) then
			setAccess(player, propertyId, mode)
		elseif action == "BuyHall" and limiter:allow(player) and viewing[player] == propertyId then
			services.GuildService.buyHall(player, propertyId)
			open(player, propertyId)
		end
	end)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		task.spawn(PropertyService.reconcile, player)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		viewing[player] = nil
		limiter:forget(player)
	end)
end

return PropertyService
