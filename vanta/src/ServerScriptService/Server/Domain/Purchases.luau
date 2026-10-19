--!strict
-- Robux purchase grants (L-33, No Pay-to-Win). Each purchase is granted exactly once, keyed by Roblox's
-- PurchaseId. Only account-bound cosmetics are granted (P-15): nothing sold affects gameplay, and nothing
-- sold can be traded, so Robux can't be turned into class books or gear.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)

local Cosmetics = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Domain.Cosmetics)
local Outbox = require(script.Parent.Outbox)

local Purchases = {}

Purchases.MAX_RECEIPTS = 200

function Purchases.findProduct(products: any, productId: any): any
	if not Check.isPositiveInteger(productId) then
		return nil
	end
	for _, product in pairs(products) do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

local function pruneReceipts(receipts: any, keep: string)
	local entries = {}
	for purchaseId, receipt in pairs(receipts) do
		if purchaseId ~= keep then
			table.insert(entries, { id = purchaseId, at = receipt.at })
		end
	end
	local excess = #entries + 1 - Purchases.MAX_RECEIPTS
	if excess <= 0 then
		return
	end
	table.sort(entries, function(a, b)
		if a.at == b.at then
			return a.id < b.id
		end
		return a.at < b.at
	end)
	for index = 1, excess do
		receipts[entries[index].id] = nil
	end
end

-- Every Robux product: Config/Products (donation tiers and older entries) plus the cosmetic catalogue.
function Purchases.catalogue(products: any, cosmetics: any): {any}
	local list = {}
	for _, product in pairs(products) do
		table.insert(list, product)
	end
	for _, item in pairs(cosmetics.items) do
		table.insert(list, { id = item.id, kind = "Cosmetic", productId = item.productId, enabled = (item.productId or 0) > 0, cosmeticId = item.id })
	end
	return list
end

-- context: { robuxSpent = receipt CurrencySpent, eventId = the Rift event collecting donations }.
-- A paid cosmetic is granted even if it has since left the shop: the player paid for it.
function Purchases.grant(profileData: any, purchaseId: any, productId: any, products: any, now: number, context: any?): (boolean, any)
	if type(purchaseId) ~= "string" or #purchaseId == 0 or #purchaseId > 100 then
		return false, "invalid purchase id"
	end
	local account = profileData.account
	if account.receipts[purchaseId] ~= nil then
		return true, { alreadyGranted = true }
	end
	local product = Purchases.findProduct(products, productId)
	if product == nil or not product.enabled then
		return false, "unknown or disabled product"
	end
	if product.kind == "Cosmetic" and product.cosmeticId ~= nil then
		Cosmetics.grant(account, product.cosmeticId, "Purchase", now)
	elseif product.kind == "Cosmetic" then
		account.entitlements[product.entitlementId] = true
	elseif product.kind == "RiftDonation" then
		-- Recorded with the receipt in the player's save; the outbox worker adds it to the shared total.
		local robux = context and context.robuxSpent
		if not Check.isPositiveInteger(robux) then
			robux = product.robux
		end
		Outbox.add(account, purchaseId, { kind = "RiftDonation", eventId = (context and context.eventId) or "none", robux = robux, at = now })
	else
		return false, "unsupported product kind"
	end
	account.receipts[purchaseId] = { productId = productId, at = now }
	pruneReceipts(account.receipts, purchaseId)
	return true, { alreadyGranted = false, product = product.id }
end

return Purchases
