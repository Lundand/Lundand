--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Transaction = require(ServerScriptService:WaitForChild("Server").Domain.Transaction)
local Inventory = require(Shared.Domain.Inventory)
local Table = require(Shared.Util.Table)
local Fixtures = require(script.Parent.Parent.Fixtures)

return function(t)
	t.test("grants items and currency together", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local ok, result = Transaction.apply(profile, "main", {
			id = "op-1",
			reason = "Test",
			changes = {
				{ type = "GrantStack", itemId = "CopperOre", amount = 3 },
				{ type = "AdjustCurrency", currency = "Gold", amount = 50 },
				{ type = "GrantUnique", itemId = "CopperPickaxe", origin = { kind = "Vendor" } },
			},
		}, deps)
		t.truthy(ok, tostring(result))
		local character = Fixtures.character(profile)
		t.equal(Inventory.count(character.inventory, "CopperOre"), 3)
		t.equal(character.currencies.Gold, 50)
		t.equal(#result.created, 1)
		t.equal(character.inventory.uniques[result.created[1]].origin.kind, "Vendor")
	end)

	t.test("a failing change leaves everything untouched", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local before = Table.deepCopy(profile)
		local ok = Transaction.apply(profile, "main", {
			id = "op-2",
			changes = {
				{ type = "GrantStack", itemId = "CopperOre", amount = 3 },
				{ type = "AdjustCurrency", currency = "Gold", amount = -1 },
			},
		}, deps)
		t.falsy(ok)
		t.deepEqual(profile, before)
	end)

	t.test("repeating an operation ID does nothing", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local operation = { id = "gather:1", changes = { { type = "GrantStack", itemId = "HealingHerb", amount = 2 } } }
		t.truthy(Transaction.apply(profile, "main", operation, deps))
		local ok, result = Transaction.apply(profile, "main", operation, deps)
		t.truthy(ok)
		t.truthy(result.alreadyApplied)
		t.equal(Inventory.count(Fixtures.character(profile).inventory, "HealingHerb"), 2)
	end)

	t.test("invalid operations are rejected", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		t.falsy(Transaction.apply(profile, "main", { id = "bad id", changes = {} }, deps), "bad id")
		t.falsy(Transaction.apply(profile, "main", { id = "op", changes = {} }, deps), "no changes")
		t.falsy(Transaction.apply(profile, "ghost", { id = "op", changes = { { type = "GrantStack", itemId = "OakLog", amount = 1 } } }, deps), "no character")
		t.falsy(Transaction.apply(profile, "main", { id = "op", changes = { { type = "Teleport" } } }, deps), "unknown change")
		t.falsy(Transaction.apply(profile, "main", { id = "op", changes = { { type = "AdjustCurrency", currency = "Gems", amount = 1 } } }, deps), "unknown currency")
		t.falsy(Transaction.apply(profile, "main", { id = "op", changes = { { type = "GrantStack", itemId = "OakLog", amount = 0 / 0 } } }, deps), "NaN amount")
	end)

	t.test("removing a unique item checks its type", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local _, granted = Transaction.apply(profile, "main", { id = "op-a", changes = { { type = "GrantUnique", itemId = "TrainingSword", origin = { kind = "Starter" } } } }, deps)
		local uid = granted.created[1]
		t.falsy(Transaction.apply(profile, "main", { id = "op-b", changes = { { type = "RemoveUnique", uid = uid, itemId = "CopperPickaxe" } } }, deps))
		t.truthy(Transaction.apply(profile, "main", { id = "op-c", changes = { { type = "RemoveUnique", uid = uid, itemId = "TrainingSword" } } }, deps))
		t.equal(Fixtures.character(profile).inventory.uniques[uid], nil)
	end)

	t.test("crafted records survive and keep stacks separate", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local crafted = { byUserId = 7, byName = "Jonathan", profession = "Alchemy", quality = "Fine" }
		Transaction.apply(profile, "main", {
			id = "craft-1",
			changes = {
				{ type = "GrantStack", itemId = "MinorHealthPotion", amount = 2, crafted = crafted },
				{ type = "GrantStack", itemId = "MinorHealthPotion", amount = 1 },
			},
		}, deps)
		local stacks = Fixtures.character(profile).inventory.stacks
		t.equal(Table.count(stacks), 2)
		t.equal(stacks[Inventory.stackKey("MinorHealthPotion", crafted)].crafted.byName, "Jonathan")
	end)

	t.test("the operation record stays bounded but keeps the newest ID", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		for index = 1, Transaction.MAX_RECENT_OPERATIONS + 20 do
			Transaction.apply(profile, "main", { id = string.format("op-%03d", index), changes = { { type = "AdjustCurrency", currency = "Gold", amount = 1 } } }, deps)
		end
		t.equal(Table.count(profile.recentOperations), Transaction.MAX_RECENT_OPERATIONS)
		t.truthy(Transaction.wasApplied(profile, string.format("op-%03d", Transaction.MAX_RECENT_OPERATIONS + 20)))
		t.truthy(#profile.audit <= Transaction.MAX_AUDIT_ENTRIES)
	end)
end
