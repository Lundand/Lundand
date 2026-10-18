--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local PropertyOwnership = require(Server.Domain.PropertyOwnership)
local Transaction = require(Server.Domain.Transaction)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local rules = Content.propertyRules
local nobleHouse = Content.world.properties.NobleHouse01
local slumHouse = Content.world.properties.SlumHouse01
local storefront = Content.world.properties.Storefront01

local function buyer(userId: number, gold: number)
	local profile, deps = Fixtures.profile(), Fixtures.deps(userId)
	Transaction.apply(profile, "main", { id = "setup", changes = { { type = "AdjustCurrency", currency = "Gold", amount = gold } } }, deps)
	return profile, deps
end

local function buy(profile: any, deps: any, record: any, property: any, userId: number, operationId: string)
	local price = rules.pricesByTier[property.tier]
	assert(PropertyOwnership.reserve(record, userId, operationId, deps.now(), rules))
	assert(PropertyOwnership.beginPurchase(profile, "main", property, price, operationId, rules, deps))
	assert(PropertyOwnership.commit(record, userId, "Buyer" .. userId, operationId, deps.now()))
	assert(PropertyOwnership.finishPurchase(profile, operationId))
end

return function(t)
	t.test("a player can own only one house", function()
		local profile, deps = buyer(1, 1000000)
		buy(profile, deps, PropertyOwnership.newRecord(nobleHouse.id), nobleHouse, 1, "buy-1")
		t.truthy(profile.account.properties.NobleHouse01)
		local allowed, reason = PropertyOwnership.canAcquire(profile.account, slumHouse, rules)
		t.falsy(allowed)
		t.equal(reason, "you already own a house")
		local gold = Fixtures.character(profile).currencies.Gold
		t.falsy(PropertyOwnership.beginPurchase(profile, "main", slumHouse, 25000, "buy-2", rules, deps))
		t.equal(Fixtures.character(profile).currencies.Gold, gold, "nothing charged")
		t.truthy(PropertyOwnership.canAcquire(profile.account, storefront, rules), "a storefront is a different kind")
	end)

	t.test("a purchase in progress also counts toward the limit", function()
		local profile, deps = buyer(1, 1000000)
		PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps)
		t.falsy(PropertyOwnership.canAcquire(profile.account, slumHouse, rules))
	end)

	t.test("only one buyer can hold a reservation until it expires", function()
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		t.truthy(PropertyOwnership.reserve(record, 1, "a", 100, rules))
		t.falsy(PropertyOwnership.reserve(record, 2, "b", 101, rules), "still reserved")
		t.truthy(PropertyOwnership.reserve(record, 2, "b", 100 + rules.reservationSeconds + 1, rules), "after expiry")
		t.falsy(PropertyOwnership.commit(record, 1, "First", "a", 300), "first buyer lost the reservation")
		t.truthy(PropertyOwnership.commit(record, 2, "Second", "b", 300))
		t.falsy(PropertyOwnership.reserve(record, 3, "c", 400, rules), "owned")
	end)

	t.test("the price is charged once and ownership is visible on the record", function()
		local profile, deps = buyer(1, 300000)
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		PropertyOwnership.reserve(record, 1, "buy-1", 0, rules)
		t.truthy(PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps))
		local _, again = PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps)
		t.truthy(again.alreadyApplied)
		t.equal(Fixtures.character(profile).currencies.Gold, 50000)
		PropertyOwnership.commit(record, 1, "Jonathan", "buy-1", 10)
		t.equal(record.owner.name, "Jonathan", "shown to the world")
		t.truthy(PropertyOwnership.commit(record, 1, "Jonathan", "buy-1", 11), "repeat commit is harmless")
	end)

	t.test("a buyer who can't afford the house is not charged", function()
		local profile, deps = buyer(1, 100)
		t.falsy(PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps))
		t.deepEqual(profile.account.pendingPurchases, {})
		t.equal(Fixtures.character(profile).currencies.Gold, 100)
	end)

	t.test("after a crash, a buyer who lost the house is refunded exactly once", function()
		local profile, deps = buyer(1, 300000)
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		PropertyOwnership.reserve(record, 1, "buy-1", 0, rules)
		PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps)
		-- the server stopped here; the reservation expired and someone else bought the house
		PropertyOwnership.reserve(record, 2, "other", 1000, rules)
		PropertyOwnership.commit(record, 2, "Someone", "other", 1001)
		local function recordFor()
			return record
		end
		local outcomes = PropertyOwnership.reconcile(profile, 1, recordFor, deps)
		t.equal(outcomes[1].outcome, "Refunded")
		t.equal(Fixtures.character(profile).currencies.Gold, 300000)
		PropertyOwnership.reconcile(profile, 1, recordFor, deps)
		t.equal(Fixtures.character(profile).currencies.Gold, 300000, "no second refund")
		t.truthy(PropertyOwnership.canAcquire(profile.account, slumHouse, rules), "free to buy another house")
	end)

	t.test("after a crash, a committed purchase is confirmed without a refund", function()
		local profile, deps = buyer(1, 300000)
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		PropertyOwnership.reserve(record, 1, "buy-1", 0, rules)
		PropertyOwnership.beginPurchase(profile, "main", nobleHouse, 250000, "buy-1", rules, deps)
		PropertyOwnership.commit(record, 1, "Jonathan", "buy-1", 5)
		local outcomes = PropertyOwnership.reconcile(profile, 1, function()
			return record
		end, deps)
		t.equal(outcomes[1].outcome, "Owned")
		t.truthy(profile.account.properties.NobleHouse01)
		t.equal(Fixtures.character(profile).currencies.Gold, 50000)
	end)

	t.test("unreadable records leave the purchase pending, and lost houses leave the save", function()
		local profile, deps = buyer(1, 1000000)
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		buy(profile, deps, record, nobleHouse, 1, "buy-1")
		record.owner = { userId = 99, name = "New owner", since = 50, operationId = "x" }
		local outcomes = PropertyOwnership.reconcile(profile, 1, function()
			return record
		end, deps)
		t.equal(outcomes[1].outcome, "Lost")
		t.equal(profile.account.properties.NobleHouse01, nil)
		local other, otherDeps = buyer(2, 1000000)
		PropertyOwnership.beginPurchase(other, "main", slumHouse, 25000, "buy-2", rules, otherDeps)
		local unknown = PropertyOwnership.reconcile(other, 2, function()
			return nil
		end, otherDeps)
		t.equal(unknown[1].outcome, "Unknown")
		t.truthy(other.account.pendingPurchases["buy-2"])
	end)

	t.test("visitors need the owner's permission", function()
		local record = PropertyOwnership.newRecord(nobleHouse.id)
		t.truthy(PropertyOwnership.canEnter(record, 5, false), "unowned houses can be viewed")
		PropertyOwnership.reserve(record, 1, "buy-1", 0, rules)
		PropertyOwnership.commit(record, 1, "Owner", "buy-1", 1)
		t.truthy(PropertyOwnership.canEnter(record, 1, false), "owner")
		t.falsy(PropertyOwnership.canEnter(record, 5, true), "private by default")
		t.falsy(PropertyOwnership.setPermissions(record, 5, "Public", {}, rules), "only the owner")
		t.truthy(PropertyOwnership.setPermissions(record, 1, "Friends", { 7 }, rules))
		t.truthy(PropertyOwnership.canEnter(record, 5, true), "friend")
		t.truthy(PropertyOwnership.canEnter(record, 7, false), "on the list")
		t.falsy(PropertyOwnership.canEnter(record, 8, false), "stranger")
		t.falsy(PropertyOwnership.setPermissions(record, 1, "Open house", {}, rules), "unknown mode")
	end)

	t.test("players may own one home and one shop; guild halls are bought by guilds", function()
		local rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content).propertyRules
		local account = { properties = {}, pendingPurchases = {} }
		t.truthy(PropertyOwnership.canAcquire(account, { id = "Storefront01", kind = "Shop" }, rules))
		account.properties.Storefront01 = { kind = "Shop", since = 0 }
		t.falsy(PropertyOwnership.canAcquire(account, { id = "Storefront02", kind = "Shop" }, rules), "one shop")
		t.truthy(PropertyOwnership.canAcquire(account, { id = "SlumHouse01", kind = "House" }, rules), "and still a home")
		t.falsy(PropertyOwnership.canAcquire(account, { id = "Hall01", kind = "GuildHall" }, rules))
	end)
end

