--!strict
-- Two-player trade applied to both characters all-or-nothing in memory (trading foundation, L-12).
-- Unique items move with their ID, origin and crafter intact and are never re-created (L-31), and
-- trading a Legendary Class Book never triggers a reset (L-22).
-- Not yet durable across two saves: both saves must commit together before trading goes live
-- (trade ledger protocol, docs/ARCHITECTURE.md).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Table = require(Shared.Util.Table)
local Check = require(Shared.Util.Check)
local Inventory = require(Shared.Domain.Inventory)
local Transaction = require(script.Parent.Transaction)

local Trade = {}

Trade.MAX_ENTRIES = 20

export type Offer = { stacks: {[string]: number}?, uniques: {string}?, gold: number? }

function Trade.validateOffer(character: any, offer: any, deps: any): (boolean, string?)
	if type(offer) ~= "table" or type(offer.stacks or {}) ~= "table" or type(offer.uniques or {}) ~= "table" then
		return false, "invalid offer"
	end
	local entries = 0
	for key, amount in pairs(offer.stacks or {}) do
		entries += 1
		local stack = type(key) == "string" and character.inventory.stacks[key]
		if not stack then
			return false, "offered stack not found"
		end
		if not Check.isPositiveInteger(amount) or amount > stack.count then
			return false, "invalid stack amount"
		end
		local def = deps.items[stack.itemId]
		if def == nil or not def.tradable or def.binding == "OnPickup" then
			return false, "item cannot be traded"
		end
	end
	local seen = {}
	for _, uid in ipairs(offer.uniques or {}) do
		entries += 1
		local item = type(uid) == "string" and character.inventory.uniques[uid]
		if not item or seen[uid] then
			return false, "offered item not found"
		end
		seen[uid] = true
		local def = deps.items[item.itemId]
		if def == nil or not def.tradable or item.boundTo ~= nil then
			return false, "item cannot be traded"
		end
	end
	if entries > Trade.MAX_ENTRIES then
		return false, "offer is too large"
	end
	local gold = offer.gold or 0
	if not Check.isNonNegativeInteger(gold) or gold > (character.currencies.Gold or 0) then
		return false, "not enough gold"
	end
	return true, nil
end

local function takeOffer(inventory: any, offer: any)
	local outgoing = { stacks = {}, uniques = {} }
	for key, amount in pairs(offer.stacks or {}) do
		local stack = inventory.stacks[key]
		table.insert(outgoing.stacks, { itemId = stack.itemId, count = amount, crafted = Table.deepCopy(stack.crafted) })
		Inventory.removeStack(inventory, key, amount)
	end
	for _, uid in ipairs(offer.uniques or {}) do
		local _, item = Inventory.removeUnique(inventory, uid)
		table.insert(outgoing.uniques, item)
	end
	return outgoing
end

local function deliver(inventory: any, outgoing: any, deps: any): (boolean, string?)
	for _, stack in ipairs(outgoing.stacks) do
		local ok, err = Inventory.addStack(inventory, deps.items, stack.itemId, stack.count, stack.crafted)
		if not ok then
			return false, err
		end
	end
	for _, item in ipairs(outgoing.uniques) do
		local ok, err = Inventory.addUnique(inventory, deps.items, item)
		if not ok then
			return false, err
		end
	end
	return true, nil
end

-- deps: { items, currencies, now: () -> number }
function Trade.execute(profileA: any, characterIdA: string, offerA: any, profileB: any, characterIdB: string, offerB: any, tradeId: any, deps: any): (boolean, any)
	if not Check.isToken(tradeId, 64) then
		return false, "invalid trade id"
	end
	if profileA == profileB then
		return false, "cannot trade with yourself"
	end
	local operationId = "trade:" .. tradeId
	local appliedA = Transaction.wasApplied(profileA, operationId)
	local appliedB = Transaction.wasApplied(profileB, operationId)
	if appliedA and appliedB then
		return true, { alreadyApplied = true }
	end
	if appliedA ~= appliedB then
		return false, "trade was only partly recorded and needs reconciliation"
	end
	local characterA = profileA.characters[characterIdA]
	local characterB = profileB.characters[characterIdB]
	if characterA == nil or characterB == nil then
		return false, "unknown character"
	end
	local okA, errA = Trade.validateOffer(characterA, offerA, deps)
	if not okA then
		return false, "first offer: " .. tostring(errA)
	end
	local okB, errB = Trade.validateOffer(characterB, offerB, deps)
	if not okB then
		return false, "second offer: " .. tostring(errB)
	end

	-- Take each side's outgoing items first, so space they free counts, then deliver.
	local inventoryA = Table.deepCopy(characterA.inventory)
	local inventoryB = Table.deepCopy(characterB.inventory)
	local toB = takeOffer(inventoryA, offerA)
	local toA = takeOffer(inventoryB, offerB)
	local delivered, err = deliver(inventoryB, toB, deps)
	if not delivered then
		return false, "second player: " .. tostring(err)
	end
	delivered, err = deliver(inventoryA, toA, deps)
	if not delivered then
		return false, "first player: " .. tostring(err)
	end
	local goldA = (characterA.currencies.Gold or 0) - (offerA.gold or 0) + (offerB.gold or 0)
	local goldB = (characterB.currencies.Gold or 0) - (offerB.gold or 0) + (offerA.gold or 0)
	if goldA > deps.currencies.Gold.max or goldB > deps.currencies.Gold.max then
		return false, "currency limit reached"
	end

	characterA.inventory = inventoryA
	characterB.inventory = inventoryB
	characterA.currencies.Gold = goldA
	characterB.currencies.Gold = goldB
	local now = deps.now()
	Transaction.record(profileA, operationId, "Trade", characterIdA, now)
	Transaction.record(profileB, operationId, "Trade", characterIdB, now)
	return true, { alreadyApplied = false }
end

return Trade
