--!strict
-- Player shops (L-53). A shop is a shared record holding what its owner put up for sale, the gold set aside for
-- the owner's buy orders, and what the shop earned or bought while the owner was away. Every change is an
-- operation from a player's outbox: that player's save has already set aside the items or gold (prepare),
-- the shop applies the operation (apply), and the stored answer tells the save what to receive or get back
-- (settlement). Answers are remembered, so a retried operation returns the same answer and changes nothing
-- twice. Buy orders hold their gold in the shop until they are filled or cancelled. The royal market tax
-- (L-55) is taken from what the seller receives on every sale and leaves the game.
local Check = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Check)

local ShopRules = {}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in pairs(value) do
		result[key] = copy(inner)
	end
	return result
end

local function count(map: any): number
	local total = 0
	for _ in pairs(map) do
		total += 1
	end
	return total
end

local function royalTax(amount: number, rules: any): number
	return math.floor(amount * rules.marketTaxPercent / 100)
end

local function validQuantity(value: any, rules: any): boolean
	return Check.isPositiveInteger(value) and value <= rules.maxQuantity
end

local function validPrice(value: any, rules: any): boolean
	return Check.isPositiveInteger(value) and value <= rules.maxUnitPrice
end

function ShopRules.newShop(shopId: string, ownerUserId: number, ownerName: string)
	return {
		id = shopId,
		ownerUserId = ownerUserId,
		ownerName = ownerName,
		listings = {},
		orders = {},
		balance = 0, -- gold earned from sales, waiting for the owner
		collected = { stacks = {}, uniques = {} }, -- goods bought through buy orders, waiting for the owner
		taxPaid = 0, -- royal market tax paid on this shop's sales, for transparency
		results = {},
		resultOrder = {},
	}
end

-- Player side, step one: what to set aside in the player's own save, and the operation for the shop.
-- args by kind:
--   List   { by, stackKey, amount, price } or { by, uid, price }   (the owner puts goods up for sale)
--   Unlist { by, listingId }                                         (the owner takes a listing back)
--   Buy    { listingId, quantity, price }                            (a visitor buys at the shown price)
--   Order  { by, itemId, quantity, price }                           (the owner wants to buy; gold set aside)
--   Sell   { orderId, itemId, quantity, price }                      (a visitor sells into a buy order)
--   Cancel { by, orderId }  Claim { by }                             (the owner)
function ShopRules.prepare(kind: string, id: string, args: any, inventory: any, items: any, rules: any): (boolean, any)
	local op: any = { id = id, kind = kind, by = args.by }
	local changes = {}
	if kind == "List" then
		if not validPrice(args.price, rules) then
			return false, "invalid price"
		end
		op.price = args.price
		if type(args.uid) == "string" then
			local item = inventory.uniques[args.uid]
			if item == nil then
				return false, "item not found"
			end
			op.goods = { itemId = item.itemId, unique = copy(item), count = 1 }
			table.insert(changes, { type = "RemoveUnique", uid = args.uid })
		else
			local stack = type(args.stackKey) == "string" and inventory.stacks[args.stackKey]
			if not stack or not validQuantity(args.amount, rules) or args.amount > stack.count then
				return false, "invalid amount"
			end
			op.goods = { itemId = stack.itemId, count = args.amount, crafted = copy(stack.crafted) }
			table.insert(changes, { type = "ConsumeStack", stackKey = args.stackKey, amount = args.amount })
		end
	elseif kind == "Buy" then
		if not validQuantity(args.quantity, rules) or not validPrice(args.price, rules) then
			return false, "invalid amount"
		end
		op.listingId, op.quantity, op.paid = args.listingId, args.quantity, args.quantity * args.price
		table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = -op.paid })
	elseif kind == "Order" then
		local def = items[args.itemId]
		if def == nil or (def.maxStack or 1) == 1 then
			return false, "buy orders are for stackable goods"
		end
		if not validQuantity(args.quantity, rules) or not validPrice(args.price, rules) then
			return false, "invalid amount"
		end
		op.itemId, op.quantity, op.price, op.escrow = args.itemId, args.quantity, args.price, args.quantity * args.price
		table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = -op.escrow })
	elseif kind == "Sell" then
		if items[args.itemId] == nil or not validQuantity(args.quantity, rules) or not validPrice(args.price, rules) then
			return false, "invalid amount"
		end
		op.orderId, op.itemId, op.quantity, op.price = args.orderId, args.itemId, args.quantity, args.price
		table.insert(changes, { type = "ConsumeItem", itemId = args.itemId, amount = args.quantity })
	elseif kind == "Unlist" then
		op.listingId = args.listingId
	elseif kind == "Cancel" then
		op.orderId = args.orderId
	elseif kind ~= "Claim" then
		return false, "unknown operation"
	end
	return true, { changes = changes, op = op }
end

local handlers: {[string]: (any, any, any, any) -> any} = {}

handlers.List = function(shop, op, rules)
	if op.by ~= shop.ownerUserId or count(shop.listings) >= rules.maxListings or not validPrice(op.price, rules) then
		return { accepted = false, goods = op.goods }
	end
	shop.listings[op.id] = { itemId = op.goods.itemId, count = op.goods.count, crafted = op.goods.crafted, unique = op.goods.unique, price = op.price }
	return { accepted = true, listingId = op.id }
end

handlers.Unlist = function(shop, op)
	local listing = shop.listings[op.listingId]
	if op.by ~= shop.ownerUserId or listing == nil then
		return { accepted = false }
	end
	shop.listings[op.listingId] = nil
	return { accepted = true, goods = { itemId = listing.itemId, count = listing.count, crafted = listing.crafted, unique = listing.unique } }
end

handlers.Buy = function(shop, op, rules)
	local listing = shop.listings[op.listingId]
	if listing == nil or op.quantity > listing.count or (listing.unique ~= nil and op.quantity ~= 1) or op.paid ~= listing.price * op.quantity then
		return { accepted = false }
	end
	listing.count -= op.quantity
	if listing.count <= 0 then
		shop.listings[op.listingId] = nil
	end
	local tax = royalTax(op.paid, rules)
	shop.balance += op.paid - tax
	shop.taxPaid += tax
	return { accepted = true, tax = tax, goods = { itemId = listing.itemId, count = op.quantity, crafted = listing.crafted, unique = listing.unique } }
end

handlers.Order = function(shop, op, rules)
	if op.by ~= shop.ownerUserId or count(shop.orders) >= rules.maxOrders then
		return { accepted = false }
	end
	shop.orders[op.id] = { itemId = op.itemId, price = op.price, remaining = op.quantity, escrow = op.escrow }
	return { accepted = true, orderId = op.id }
end

handlers.Sell = function(shop, op, rules)
	local order = shop.orders[op.orderId]
	if order == nil or order.itemId ~= op.itemId or order.price ~= op.price then
		return { accepted = false, sold = 0 }
	end
	local sold = math.min(op.quantity, order.remaining)
	local gross = sold * order.price
	local tax = royalTax(gross, rules)
	order.remaining -= sold
	order.escrow -= gross
	shop.taxPaid += tax
	shop.collected.stacks[order.itemId] = (shop.collected.stacks[order.itemId] or 0) + sold
	if order.remaining <= 0 then
		shop.orders[op.orderId] = nil
	end
	return { accepted = true, sold = sold, payout = gross - tax, tax = tax }
end

handlers.Cancel = function(shop, op)
	local order = shop.orders[op.orderId]
	if op.by ~= shop.ownerUserId or order == nil then
		return { accepted = false, refund = 0 }
	end
	shop.orders[op.orderId] = nil
	return { accepted = true, refund = order.escrow }
end

handlers.Claim = function(shop, op)
	if op.by ~= shop.ownerUserId then
		return { accepted = false }
	end
	local result = { accepted = true, gold = shop.balance, stacks = shop.collected.stacks, uniques = shop.collected.uniques }
	shop.balance = 0
	shop.collected = { stacks = {}, uniques = {} }
	return result
end

-- Shop side: applies an operation once and returns its answer (the same answer on every retry).
function ShopRules.apply(shop: any, op: any, rules: any): any
	local stored = shop.results[op.id]
	if stored ~= nil then
		return stored
	end
	local handler = handlers[op.kind]
	local result = (handler and handler(shop, op, rules, nil)) or { accepted = false }
	shop.results[op.id] = result
	table.insert(shop.resultOrder, op.id)
	while #shop.resultOrder > rules.recentOperationsKept do
		shop.results[table.remove(shop.resultOrder, 1)] = nil
	end
	return result
end

local function goodsChange(goods: any): any
	if goods.unique ~= nil then
		return { type = "InsertUnique", unique = copy(goods.unique) }
	end
	return { type = "GrantStack", itemId = goods.itemId, amount = goods.count, crafted = copy(goods.crafted) }
end

-- Player side, step two: what the player's save receives or gets back once the shop has answered.
function ShopRules.settlement(op: any, result: any): {any}
	local changes = {}
	local function gold(amount: number?)
		if amount ~= nil and amount > 0 then
			table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = amount })
		end
	end
	local kind = op.kind
	if kind == "List" or kind == "Unlist" or kind == "Buy" then
		if result.goods ~= nil and (kind ~= "List" or not result.accepted) then
			table.insert(changes, goodsChange(result.goods))
		end
		if kind == "Buy" and not result.accepted then
			gold(op.paid)
		end
	elseif kind == "Order" then
		if not result.accepted then
			gold(op.escrow)
		end
	elseif kind == "Sell" then
		local sold = result.sold or 0
		gold(result.payout)
		if op.quantity - sold > 0 then
			table.insert(changes, { type = "GrantStack", itemId = op.itemId, amount = op.quantity - sold })
		end
	elseif kind == "Cancel" then
		gold(result.refund)
	elseif kind == "Claim" and result.accepted then
		gold(result.gold)
		local itemIds = {}
		for itemId in pairs(result.stacks or {}) do
			table.insert(itemIds, itemId)
		end
		table.sort(itemIds)
		for _, itemId in ipairs(itemIds) do
			if result.stacks[itemId] > 0 then
				table.insert(changes, { type = "GrantStack", itemId = itemId, amount = result.stacks[itemId] })
			end
		end
		for _, unique in ipairs(result.uniques or {}) do
			table.insert(changes, { type = "InsertUnique", unique = copy(unique) })
		end
	end
	return changes
end

return ShopRules
