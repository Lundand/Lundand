--!strict
-- NPC vendors (L-12). A vendor's conversation opens their shop for a few minutes; each purchase is planned by
-- VendorRules and applied as one transaction.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local VendorRules = require(Server.Domain.VendorRules)
local Transaction = require(Server.Domain.Transaction)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local SESSION_SECONDS = 300

local VendorService = {}
local services: any = nil
local sessions: {[Player]: any} = {}
local limiter = RateLimiter.new(4, 1, os.clock)

function VendorService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

function VendorService.open(player: Player, vendorId: any)
	local vendor = type(vendorId) == "string" and Content.vendors[vendorId]
	if not vendor then
		return
	end
	sessions[player] = { vendorId = vendorId, untilTime = os.clock() + SESSION_SECONDS }
	local stock = {}
	for _, offer in ipairs(vendor.stock) do
		local def = Content.items[offer.itemId]
		table.insert(stock, {
			itemId = offer.itemId,
			name = def.displayName,
			description = def.description,
			rarity = def.rarity,
			price = offer.price,
			stackable = (def.maxStack or 1) > 1,
		})
	end
	Remotes.get("OpenInterface"):FireClient(player, "Vendor", { id = vendorId, name = vendor.displayName, stock = stock })
end

local function onBuy(player: Player, vendorId: any, itemId: any, amount: any)
	local session = sessions[player]
	if not limiter:allow(player) or session == nil or session.vendorId ~= vendorId or os.clock() > session.untilTime then
		return
	end
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if data == nil or character == nil then
		return
	end
	local ok, plan = VendorRules.plan(Content.vendors[vendorId], itemId, amount, Content.items, character.currencies.Gold or 0)
	if not ok then
		notify(player, "Can't buy that: " .. tostring(plan))
		return
	end
	local applied, err = Transaction.apply(data, data.activeCharacterId, {
		id = "buy:" .. HttpService:GenerateGUID(false),
		reason = "Vendor",
		changes = plan.changes,
	}, services.InventoryService.deps(player))
	if not applied then
		notify(player, "Can't buy that: " .. tostring(err))
		return
	end
	notify(player, string.format("Bought %s for %d gold.", Content.items[itemId].displayName, plan.total))
	services.InventoryService.sendSnapshot(player)
end

-- Vendors buy anything, at a low price (L-53).
local function onSell(player: Player, vendorId: any, stackKey: any, uid: any, amount: any)
	local session = sessions[player]
	if not limiter:allow(player) or session == nil or session.vendorId ~= vendorId or os.clock() > session.untilTime then
		return
	end
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if data == nil or character == nil then
		return
	end
	local ok, plan = VendorRules.planSale(character.inventory, Content.items, Content.economy.vendorBuyBack, stackKey, uid, amount)
	if not ok then
		notify(player, "Can't sell that: " .. tostring(plan))
		return
	end
	local applied, err = Transaction.apply(data, data.activeCharacterId, {
		id = "sell:" .. HttpService:GenerateGUID(false),
		reason = "VendorSale",
		changes = plan.changes,
	}, services.InventoryService.deps(player))
	if not applied then
		notify(player, "Can't sell that: " .. tostring(err))
		return
	end
	notify(player, string.format("Sold %s for %d gold.", Content.items[plan.itemId].displayName, plan.total))
	services.InventoryService.sendSnapshot(player)
end

function VendorService.start()
	Remotes.get("VendorBuy").OnServerEvent:Connect(onBuy)
	Remotes.get("VendorSell").OnServerEvent:Connect(onSell)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		sessions[player] = nil
		limiter:forget(player)
	end)
end

return VendorService
