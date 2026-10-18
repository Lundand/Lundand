--!strict
-- Buying from NPC vendors (L-12). One transaction: pay and receive, or nothing happens.
local Pricing = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Domain.Pricing)

local VendorRules = {}

VendorRules.MAX_AMOUNT = 10

function VendorRules.plan(vendor: any, itemId: any, amount: any, items: any, gold: number): (boolean, any)
	local offer = nil
	for _, entry in ipairs(vendor.stock) do
		if entry.itemId == itemId then
			offer = entry
		end
	end
	local def = offer and items[offer.itemId]
	if not def then
		return false, "not sold here"
	end
	local unique = (def.maxStack or 1) == 1
	if type(amount) ~= "number" or amount % 1 ~= 0 or amount < 1 or amount > VendorRules.MAX_AMOUNT or (unique and amount ~= 1) then
		return false, "invalid amount"
	end
	local total = offer.price * amount
	if gold < total then
		return false, "not enough gold"
	end
	local changes = { { type = "AdjustCurrency", currency = "Gold", amount = -total } }
	if unique then
		table.insert(changes, { type = "GrantUnique", itemId = itemId, origin = { kind = "Vendor", source = vendor.id } })
	else
		table.insert(changes, { type = "GrantStack", itemId = itemId, amount = amount })
	end
	return true, { changes = changes, total = total }
end

-- Selling to a vendor (L-53): vendors buy anything at a low price. A stack by its inventory key, or one item
-- by its uid. Equipped items are not in the inventory, so they can't be sold by accident.
function VendorRules.planSale(inventory: any, items: any, buyBack: any, stackKey: any, uid: any, amount: any): (boolean, any)
	if type(uid) == "string" then
		local item = inventory.uniques[uid]
		local def = item and items[item.itemId]
		if not def then
			return false, "item not found"
		end
		local price = Pricing.vendorPays(def, buyBack)
		return true, {
			changes = { { type = "RemoveUnique", uid = uid }, { type = "AdjustCurrency", currency = "Gold", amount = price } },
			total = price,
			itemId = item.itemId,
		}
	end
	local stack = type(stackKey) == "string" and inventory.stacks[stackKey]
	local def = stack and items[stack.itemId]
	if not def then
		return false, "item not found"
	end
	if type(amount) ~= "number" or amount % 1 ~= 0 or amount < 1 or amount > stack.count then
		return false, "invalid amount"
	end
	local total = Pricing.vendorPays(def, buyBack) * amount
	return true, {
		changes = { { type = "ConsumeStack", stackKey = stackKey, amount = amount }, { type = "AdjustCurrency", currency = "Gold", amount = total } },
		total = total,
		itemId = stack.itemId,
	}
end

return VendorRules
