--!strict
-- Player shops (L-53 to L-55). An owned shop building's sign opens its counter. Owners list goods, post buy
-- orders with the gold set aside, take goods back, cancel orders and collect earnings; visitors buy listings and
-- sell into buy orders. Each action sets aside items or gold in the player's save and goes through the outbox to
-- the shop's shared record; the shop's answer settles back into the save.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local ShopRules = require(Server.Domain.ShopRules)
local Outbox = require(Server.Domain.Outbox)
local Transaction = require(Server.Domain.Transaction)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local SESSION_SECONDS = 600
local KINDS = { List = true, Unlist = true, Buy = true, Order = true, Sell = true, Cancel = true, Claim = true }

local ShopService = {}
local services: any = nil
local sessions: {[Player]: any} = {}
local limiter = RateLimiter.new(4, 1, os.clock)

function ShopService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function shops(): any
	return services.SharedRecordService.store("Shops")
end

local function itemInfo(itemId: string): (string, any)
	local def = Content.items[itemId]
	return (def and def.displayName) or itemId, def and def.rarity
end

local function view(player: Player, shopId: string): any
	local ok, shop = shops():read(shopId)
	local propertyOk, property = services.SharedRecordService.store("Properties"):read(shopId)
	if not ok or not propertyOk then
		return { shopId = shopId, unreachable = true }
	end
	local owner = property and property.owner
	local isOwner = owner ~= nil and owner.userId == player.UserId
	local listings, orders = {}, {}
	for id, listing in pairs((shop and shop.listings) or {}) do
		local name, rarity = itemInfo(listing.itemId)
		local crafted = listing.crafted or (listing.unique and listing.unique.crafted)
		table.insert(listings, { id = id, itemId = listing.itemId, name = name, rarity = rarity, count = listing.count, price = listing.price, unique = listing.unique ~= nil, craftedBy = crafted and crafted.byName, quality = crafted and crafted.quality })
	end
	for id, order in pairs((shop and shop.orders) or {}) do
		local name = itemInfo(order.itemId)
		table.insert(orders, { id = id, itemId = order.itemId, name = name, remaining = order.remaining, price = order.price })
	end
	table.sort(listings, function(a, b)
		return a.name < b.name
	end)
	table.sort(orders, function(a, b)
		return a.name < b.name
	end)
	local result: any = {
		shopId = shopId,
		ownerName = owner and owner.name,
		isOwner = isOwner,
		listings = listings,
		orders = orders,
		taxPercent = Content.economy.playerShops.marketTaxPercent,
	}
	if isOwner and shop ~= nil then
		local goods = 0
		for _ in pairs(shop.collected.stacks) do
			goods += 1
		end
		result.balance = shop.balance
		result.collected = goods + #shop.collected.uniques
		result.taxPaid = shop.taxPaid
	end
	return result
end

local function send(player: Player, shopId: string)
	Remotes.get("OpenInterface"):FireClient(player, "ShopCounter", view(player, shopId))
end

function ShopService.open(player: Player, shopId: any)
	local property = type(shopId) == "string" and Content.world.properties[shopId]
	if not property or property.kind ~= "Shop" or not services.PropertyService.isViewing(player, shopId) then
		return
	end
	local ok, record = services.SharedRecordService.store("Properties"):read(shopId, 0)
	if not ok or record == nil or record.owner == nil then
		notify(player, "This shop has no owner yet.")
		return
	end
	if record.owner.userId == player.UserId then
		shops():update(shopId, function(shop: any)
			if shop ~= nil then
				return nil, nil
			end
			return ShopRules.newShop(shopId, player.UserId, player.DisplayName), nil
		end)
	end
	sessions[player] = { shopId = shopId, untilTime = os.clock() + SESSION_SECONDS }
	send(player, shopId)
end

-- The outbox handler: applies the operation to the shop once and returns what the player's save receives.
-- A shop that doesn't exist refuses everything, so goods and gold go back.
local function deliver(_id: string, entry: any): (boolean, any)
	local rules = Content.economy.playerShops
	local ok, result = shops():update(entry.shopId, function(shop: any)
		if shop == nil then
			return nil, ShopRules.apply(ShopRules.newShop(entry.shopId, -1, ""), entry.op, rules)
		end
		return shop, ShopRules.apply(shop, entry.op, rules)
	end)
	if not ok or result == nil then
		return false, nil
	end
	return true, ShopRules.settlement(entry.op, result)
end

local function onRequest(player: Player, action: any, args: any)
	if not limiter:allow(player) or type(action) ~= "string" or type(args) ~= "table" then
		return
	end
	if action == "Open" then
		ShopService.open(player, args.shopId)
		return
	end
	local session = sessions[player]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if session == nil or os.clock() > session.untilTime or not KINDS[action] or data == nil or character == nil then
		return
	end
	args.by = player.UserId
	local id = "shop:" .. string.gsub(HttpService:GenerateGUID(false), "-", "")
	local ok, prepared = ShopRules.prepare(action, id, args, character.inventory, Content.items, Content.economy.playerShops)
	if not ok then
		notify(player, "Shop: " .. tostring(prepared))
		return
	end
	if #prepared.changes > 0 then
		local reserved, err = Transaction.apply(data, data.activeCharacterId, { id = "reserve:" .. id, reason = "Shop", changes = prepared.changes }, services.InventoryService.deps(player))
		if not reserved then
			notify(player, "Shop: " .. tostring(err))
			return
		end
	end
	Outbox.add(data.account, id, { kind = "Shop", shopId = session.shopId, op = prepared.op, characterId = data.activeCharacterId, at = os.time() })
	services.InventoryService.sendSnapshot(player)
	services.OutboxService.deliverNow(player)
	send(player, session.shopId)
end

function ShopService.start()
	services.OutboxService.register("Shop", deliver)
	Remotes.get("ShopRequest").OnServerEvent:Connect(onRequest)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		sessions[player] = nil
		limiter:forget(player)
	end)
end

return ShopService
