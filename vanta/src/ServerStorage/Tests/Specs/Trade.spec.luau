--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local Trade = require(Server.Domain.Trade)
local Transaction = require(Server.Domain.Transaction)
local ClassProgression = require(Shared.Domain.ClassProgression)
local Inventory = require(Shared.Domain.Inventory)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local function seller()
	local profile, deps = Fixtures.profile(), Fixtures.deps(1)
	ClassProgression.assignInitialClass(Fixtures.character(profile).class, "Swordmaster", Content.classes, "Awakening", 1)
	local crafted = { byUserId = 1, byName = "Jonathan", profession = "Blacksmithing", quality = "Masterwork" }
	local _, granted = Transaction.apply(profile, "main", {
		id = "setup-a",
		changes = {
			{ type = "GrantUnique", itemId = "LegendaryBookPlaceholder", origin = { kind = "Loot", source = "HiddenCave" } },
			{ type = "GrantUnique", itemId = "TrainingSword", origin = { kind = "Crafted" }, crafted = crafted },
			{ type = "GrantStack", itemId = "CopperOre", amount = 10 },
		},
	}, deps)
	return profile, granted.created[1], granted.created[2]
end

local function buyer(gold: number)
	local profile, deps = Fixtures.profile(), Fixtures.deps(2)
	ClassProgression.assignInitialClass(Fixtures.character(profile).class, "Swordmaster", Content.classes, "Awakening", 1)
	Transaction.apply(profile, "main", { id = "setup-b", changes = { { type = "AdjustCurrency", currency = "Gold", amount = gold } } }, deps)
	return profile
end

return function(t)
	local deps = Fixtures.deps()

	t.test("a class book changes hands without any reset", function()
		local a, bookUid = seller()
		local b = buyer(500)
		local ok, err = Trade.execute(a, "main", { uniques = { bookUid } }, b, "main", { gold = 500 }, "t1", deps)
		t.truthy(ok, tostring(err))
		local charA, charB = Fixtures.character(a), Fixtures.character(b)
		t.equal(charA.inventory.uniques[bookUid], nil)
		t.equal(charB.inventory.uniques[bookUid].itemId, "LegendaryBookPlaceholder")
		t.equal(charB.inventory.uniques[bookUid].origin.source, "HiddenCave", "origin kept")
		t.equal(charA.currencies.Gold, 500)
		t.equal(charB.currencies.Gold, 0)
		t.equal(charA.class.classId, "Swordmaster", "seller keeps class")
		t.equal(charB.class.classId, "Swordmaster", "buyer is not reset")
	end)

	t.test("the original crafter stays on a traded item", function()
		local a, _, swordUid = seller()
		local b = buyer(10)
		t.truthy(Trade.execute(a, "main", { uniques = { swordUid } }, b, "main", { gold = 10 }, "t2", deps))
		t.equal(Fixtures.character(b).inventory.uniques[swordUid].crafted.byName, "Jonathan")
	end)

	t.test("invalid trades change neither side", function()
		local a, bookUid = seller()
		local b = buyer(100)
		local beforeA, beforeB = Table.deepCopy(a), Table.deepCopy(b)
		t.falsy(Trade.execute(a, "main", { uniques = { bookUid } }, b, "main", { gold = 101 }, "t3", deps), "not enough gold")
		t.falsy(Trade.execute(a, "main", { uniques = { "nope" } }, b, "main", {}, "t4", deps), "missing item")
		t.falsy(Trade.execute(a, "main", { uniques = { bookUid, bookUid } }, b, "main", {}, "t5", deps), "item offered twice")
		t.falsy(Trade.execute(a, "main", { stacks = { CopperOre = 11 } }, b, "main", {}, "t6", deps), "too many ore")
		Fixtures.character(a).inventory.uniques[bookUid].boundTo = 1
		t.falsy(Trade.execute(a, "main", { uniques = { bookUid } }, b, "main", {}, "t7", deps), "bound item")
		Fixtures.character(a).inventory.uniques[bookUid].boundTo = nil
		t.falsy(Trade.execute(a, "main", {}, a, "main", {}, "t8", deps), "self trade")
		t.deepEqual(a, beforeA)
		t.deepEqual(b, beforeB)
	end)

	t.test("a full inventory on the receiving side cancels the trade", function()
		local a = seller()
		local b = buyer(0)
		local bag = Fixtures.character(b).inventory
		bag.capacity = 1
		Inventory.addStack(bag, Content.items, "OakLog", 99)
		t.falsy(Trade.execute(a, "main", { stacks = { CopperOre = 5 } }, b, "main", {}, "t9", deps))
		t.equal(Inventory.count(Fixtures.character(a).inventory, "CopperOre"), 10)
	end)

	t.test("a repeated trade ID does nothing", function()
		local a = seller()
		local b = buyer(50)
		t.truthy(Trade.execute(a, "main", { stacks = { CopperOre = 2 } }, b, "main", { gold = 50 }, "t10", deps))
		local ok, result = Trade.execute(a, "main", { stacks = { CopperOre = 2 } }, b, "main", { gold = 50 }, "t10", deps)
		t.truthy(ok)
		t.truthy(result.alreadyApplied)
		t.equal(Inventory.count(Fixtures.character(b).inventory, "CopperOre"), 2)
	end)
end
