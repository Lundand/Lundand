--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Inventory = require(Shared.Domain.Inventory)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)

return function(t)
	local items = Content.items
	local jonathan = { byUserId = 101, byName = "Jonathan", profession = "Alchemy", quality = "Fine" }
	local mira = { byUserId = 202, byName = "Mira", profession = "Alchemy", quality = "Fine" }

	local function unique(uid: string, itemId: string, originKind: string, crafted: any)
		return { uid = uid, itemId = itemId, createdBy = "op-" .. uid, origin = { kind = originKind, at = 1 }, crafted = crafted }
	end

	t.test("stacks fill slots by max stack size", function()
		local bag = Inventory.newContainer(10)
		t.truthy(Inventory.addStack(bag, items, "HealingHerb", 100))
		t.equal(Inventory.count(bag, "HealingHerb"), 100)
		t.equal(Inventory.slotsUsed(bag, items), 2)
	end)

	t.test("a full inventory rejects additions and stays unchanged", function()
		local bag = Inventory.newContainer(1)
		Inventory.addStack(bag, items, "CopperOre", 99)
		local before = Table.deepCopy(bag)
		local ok, err = Inventory.addStack(bag, items, "CopperOre", 1)
		t.falsy(ok)
		t.equal(err, "inventory full")
		t.deepEqual(bag, before)
	end)

	t.test("crafted stacks never merge across crafters or with plain stacks", function()
		local bag = Inventory.newContainer(10)
		Inventory.addStack(bag, items, "MinorHealthPotion", 2)
		Inventory.addStack(bag, items, "MinorHealthPotion", 3, jonathan)
		Inventory.addStack(bag, items, "MinorHealthPotion", 4, mira)
		Inventory.addStack(bag, items, "MinorHealthPotion", 1, jonathan)
		t.equal(Table.count(bag.stacks), 3)
		t.equal(bag.stacks[Inventory.stackKey("MinorHealthPotion", jonathan)].count, 4)
		t.equal(bag.stacks[Inventory.stackKey("MinorHealthPotion", jonathan)].crafted.byName, "Jonathan")
		t.equal(Inventory.count(bag, "MinorHealthPotion"), 10)
	end)

	t.test("invalid crafting records are rejected", function()
		local bag = Inventory.newContainer(10)
		t.falsy(Inventory.addStack(bag, items, "MinorHealthPotion", 1, { byUserId = 0, byName = "x", profession = "Alchemy", quality = "Fine" }))
		t.falsy(Inventory.addStack(bag, items, "MinorHealthPotion", 1, { byUserId = 5, byName = "", profession = "Alchemy", quality = "Fine" }))
	end)

	t.test("removeItem takes plain stacks first and removeStack is exact", function()
		local bag = Inventory.newContainer(10)
		Inventory.addStack(bag, items, "MinorHealthPotion", 2)
		Inventory.addStack(bag, items, "MinorHealthPotion", 3, jonathan)
		t.truthy(Inventory.removeItem(bag, "MinorHealthPotion", 3))
		t.equal(bag.stacks.MinorHealthPotion, nil)
		t.equal(Inventory.count(bag, "MinorHealthPotion"), 2)
		t.falsy(Inventory.removeItem(bag, "MinorHealthPotion", 3), "not enough")
		t.truthy(Inventory.removeStack(bag, Inventory.stackKey("MinorHealthPotion", jonathan), 2))
		t.equal(Inventory.count(bag, "MinorHealthPotion"), 0)
	end)

	t.test("unique items need a valid origin and only crafted ones carry a crafter", function()
		local bag = Inventory.newContainer(10)
		t.truthy(Inventory.addUnique(bag, items, unique("u1", "TrainingSword", "Loot", nil)))
		t.truthy(Inventory.addUnique(bag, items, unique("u2", "TrainingSword", "Crafted", { byUserId = 101, byName = "Jonathan", profession = "Blacksmithing", quality = "Masterwork" })))
		t.falsy(Inventory.addUnique(bag, items, unique("u3", "TrainingSword", "Loot", jonathan)), "loot with a crafter")
		t.falsy(Inventory.addUnique(bag, items, unique("u4", "TrainingSword", "Crafted", nil)), "crafted without a crafter")
		t.falsy(Inventory.addUnique(bag, items, unique("u5", "TrainingSword", "Stolen", nil)), "unknown origin")
		t.falsy(Inventory.addUnique(bag, items, unique("u1", "TrainingSword", "Loot", nil)), "duplicate id")
		t.falsy(Inventory.addUnique(bag, items, unique("u6", "HealingHerb", "Loot", nil)), "stackable item")
		t.falsy(Inventory.addStack(bag, items, "TrainingSword", 1), "unique item as a stack")
		t.equal(Table.count(bag.uniques), 2)
	end)

	t.test("contributors are added without changing the original crafter", function()
		local sword = unique("u1", "TrainingSword", "Crafted", { byUserId = 101, byName = "Jonathan", profession = "Blacksmithing", quality = "Fine" })
		for index = 1, 25 do
			Inventory.addContributor(sword, { userId = 300 + index, name = "Smith", action = "Repair", at = index })
		end
		t.equal(sword.crafted.byName, "Jonathan")
		t.equal(#sword.contributors, Inventory.MAX_CONTRIBUTORS)
	end)

	t.test("inspection shows the crafter only for crafted items", function()
		local crafted = Inventory.describe(unique("u1", "TrainingSword", "Crafted", { byUserId = 101, byName = "Jonathan", profession = "Blacksmithing", quality = "Masterwork" }), items)
		t.equal(crafted.craftedBy, "Jonathan")
		t.equal(crafted.quality, "Masterwork")
		local looted = Inventory.describe({ uid = "u2", itemId = "TrainingSword", origin = { kind = "Loot", source = "ForestElite", at = 1 } }, items)
		t.equal(looted.craftedBy, nil)
		t.equal(looted.origin, "Loot")
		t.equal(looted.source, "ForestElite")
	end)

	t.test("container validation catches tampered stack keys", function()
		local bag = Inventory.newContainer(10)
		Inventory.addStack(bag, items, "MinorHealthPotion", 1, jonathan)
		local key = Inventory.stackKey("MinorHealthPotion", jonathan)
		bag.stacks[key].crafted.byUserId = 999
		local problems = Inventory.validateContainer(bag, items)
		t.equal(#problems, 1)
	end)
end
