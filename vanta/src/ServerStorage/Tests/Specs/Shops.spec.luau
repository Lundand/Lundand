--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local ShopRules = require(Server.Domain.ShopRules)
local VendorRules = require(Server.Domain.VendorRules)
local Transaction = require(Server.Domain.Transaction)
local Inventory = require(Shared.Domain.Inventory)
local Pricing = require(Shared.Domain.Pricing)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local rules = Content.economy.playerShops
local OWNER, SELLER_A, SELLER_B = 1, 2, 3

local function player(userId: number, gold: number, ore: number): any
	local profile = Fixtures.profile()
	local character = Fixtures.character(profile)
	character.currencies.Gold = gold
	if ore > 0 then
		Inventory.addStack(character.inventory, Content.items, "CopperOre", ore, nil)
	end
	return { profile = profile, deps = Fixtures.deps(userId), userId = userId }
end

-- The whole round trip: set aside in the player's save, apply to the shop, settle back into the save.
local function act(who: any, shop: any, kind: string, id: string, args: any): any
	local character = Fixtures.character(who.profile)
	local ok, prepared = ShopRules.prepare(kind, id, args, character.inventory, Content.items, rules)
	assert(ok, tostring(prepared))
	if #prepared.changes > 0 then
		assert(Transaction.apply(who.profile, "main", { id = "reserve:" .. id, reason = "Shop", changes = prepared.changes }, who.deps))
	end
	local result = ShopRules.apply(shop, prepared.op, rules)
	local settle = ShopRules.settlement(prepared.op, result)
	if #settle > 0 then
		assert(Transaction.apply(who.profile, "main", { id = "settle:" .. id, reason = "Shop", changes = settle }, who.deps))
	end
	return result, prepared.op
end

local function gold(who: any): number
	return Fixtures.character(who.profile).currencies.Gold
end

local function ore(who: any): number
	return Inventory.count(Fixtures.character(who.profile).inventory, "CopperOre")
end

return function(t)
	t.test("a buy order sets the gold aside and fills from several sellers", function()
		local owner, a, b = player(OWNER, 150, 0), player(SELLER_A, 0, 60), player(SELLER_B, 0, 50)
		local shop = ShopRules.newShop("s1", OWNER, "Owner")
		local placed = act(owner, shop, "Order", "o1", { by = OWNER, itemId = "CopperOre", quantity = 100, price = 1 })
		t.truthy(placed.accepted)
		t.equal(gold(owner), 50, "100 gold set aside")
		act(a, shop, "Sell", "sell-a", { orderId = "o1", itemId = "CopperOre", quantity = 60, price = 1 })
		t.equal(gold(a), 60 - math.floor(60 * rules.marketTaxPercent / 100), "paid, less the royal market tax")
		t.equal(ore(a), 0)
		local result = act(b, shop, "Sell", "sell-b", { orderId = "o1", itemId = "CopperOre", quantity = 50, price = 1 })
		t.equal(result.sold, 40, "only what the order still wanted")
		t.equal(gold(b), 40 - math.floor(40 * rules.marketTaxPercent / 100))
		t.equal(ore(b), 10, "the rest comes back")
		t.equal(shop.orders.o1, nil, "filled")
		act(owner, shop, "Claim", "claim1", { by = OWNER })
		t.equal(ore(owner), 100)
		t.equal(gold(owner) + gold(a) + gold(b) + shop.taxPaid, 150, "no gold created or lost: only the royal tax leaves")
	end)

	t.test("cancelling returns the gold still set aside, and a retry changes nothing", function()
		local owner, a = player(OWNER, 100, 0), player(SELLER_A, 0, 35)
		local shop = ShopRules.newShop("s1", OWNER, "Owner")
		act(owner, shop, "Order", "o1", { by = OWNER, itemId = "CopperOre", quantity = 100, price = 1 })
		act(a, shop, "Sell", "sell-a", { orderId = "o1", itemId = "CopperOre", quantity = 30, price = 1 })
		local _, op = act(owner, shop, "Cancel", "cancel1", { by = OWNER, orderId = "o1" })
		t.equal(gold(owner), 70)
		local again = ShopRules.apply(shop, op, rules)
		t.equal(again.refund, 70, "the same answer")
		t.falsy(act(a, shop, "Sell", "sell-late", { orderId = "o1", itemId = "CopperOre", quantity = 5, price = 1 }).accepted)
		t.equal(ore(a), 5, "a refused sale gives the goods back")
	end)

	t.test("listings sell the exact item, with its record, and the owner collects the gold", function()
		local owner, buyer = player(OWNER, 0, 0), player(SELLER_A, 500, 0)
		local character = Fixtures.character(owner.profile)
		character.class.classId = "Swordmaster"
		local _, granted = Transaction.apply(owner.profile, "main", { id = "make", reason = "Test", changes = { { type = "GrantUnique", itemId = "TrainingSword", origin = { kind = "Loot", source = "Test" } } } }, owner.deps)
		local uid = granted.created[1]
		local shop = ShopRules.newShop("s1", OWNER, "Owner")
		local listed = act(owner, shop, "List", "l1", { by = OWNER, uid = uid, price = 120 })
		t.truthy(listed.accepted)
		t.equal(Fixtures.character(owner.profile).inventory.uniques[uid], nil, "out of the owner's bags while listed")
		t.falsy(act(buyer, shop, "Buy", "b0", { listingId = "l1", quantity = 1, price = 100 }).accepted, "wrong price: refused")
		t.equal(gold(buyer), 500, "and refunded")
		t.truthy(act(buyer, shop, "Buy", "b1", { listingId = "l1", quantity = 1, price = 120 }).accepted)
		t.equal(gold(buyer), 380)
		t.equal(Fixtures.character(buyer.profile).inventory.uniques[uid].itemId, "TrainingSword", "same item, same ID")
		t.falsy(act(buyer, shop, "Buy", "b2", { listingId = "l1", quantity = 1, price = 120 }).accepted, "sold out")
		act(owner, shop, "Claim", "c1", { by = OWNER })
		t.equal(gold(owner), 120 - math.floor(120 * rules.marketTaxPercent / 100), "the sale, less the royal market tax")
		t.equal(gold(owner) + gold(buyer) + shop.taxPaid, 500)
	end)

	t.test("only the owner manages the shop, and limits hold", function()
		local stranger = player(SELLER_A, 100, 0)
		local shop = ShopRules.newShop("s1", OWNER, "Owner")
		t.falsy(act(stranger, shop, "Order", "o1", { by = SELLER_A, itemId = "CopperOre", quantity = 10, price = 1 }).accepted)
		t.equal(gold(stranger), 100, "refused orders give the gold back")
		t.falsy(ShopRules.prepare("Order", "o2", { by = OWNER, itemId = "TrainingSword", quantity = 1, price = 5 }, Fixtures.character(stranger.profile).inventory, Content.items, rules), "buy orders are for stackable goods")
		t.falsy(ShopRules.prepare("Order", "o3", { by = OWNER, itemId = "CopperOre", quantity = rules.maxQuantity + 1, price = 1 }, Fixtures.character(stranger.profile).inventory, Content.items, rules))
	end)

	t.test("NPC vendors buy anything, at a low price", function()
		local seller = player(SELLER_A, 0, 20)
		local character = Fixtures.character(seller.profile)
		local key = next(character.inventory.stacks)
		local ok, sale = VendorRules.planSale(character.inventory, Content.items, Content.economy.vendorBuyBack, key, nil, 20)
		t.truthy(ok)
		local each = Pricing.vendorPays(Content.items.CopperOre, Content.economy.vendorBuyBack)
		t.truthy(each < Pricing.value(Content.items.CopperOre, Content.economy.vendorBuyBack), "below value")
		t.equal(sale.total, 20 * each)
		t.truthy(Transaction.apply(seller.profile, "main", { id = "sale", reason = "Vendor", changes = sale.changes }, seller.deps))
		t.equal(ore(seller), 0)
		t.equal(gold(seller), 20 * each)
		t.falsy(VendorRules.planSale(character.inventory, Content.items, Content.economy.vendorBuyBack, key, nil, 1), "nothing left")
	end)

	t.test("an operation on a shop that doesn't exist yet is refused, and everything goes back", function()
		local nobody = ShopRules.newShop("missing", -1, "")
		local listing = ShopRules.apply(nobody, { id = "x1", kind = "List", by = OWNER, price = 5, goods = { itemId = "CopperOre", count = 3 } }, rules)
		t.deepEqual(ShopRules.settlement({ kind = "List" }, listing)[1], { type = "GrantStack", itemId = "CopperOre", amount = 3, crafted = nil })
		local buy = ShopRules.apply(nobody, { id = "x2", kind = "Buy", listingId = "l1", quantity = 1, paid = 50 }, rules)
		t.deepEqual(ShopRules.settlement({ kind = "Buy", paid = 50 }, buy), { { type = "AdjustCurrency", currency = "Gold", amount = 50 } })
		local sell = ShopRules.apply(nobody, { id = "x3", kind = "Sell", orderId = "o1", itemId = "CopperOre", quantity = 4, price = 1 }, rules)
		t.deepEqual(ShopRules.settlement({ kind = "Sell", itemId = "CopperOre", quantity = 4, price = 1 }, sell), { { type = "GrantStack", itemId = "CopperOre", amount = 4 } })
	end)
end

