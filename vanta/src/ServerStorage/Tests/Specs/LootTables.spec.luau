--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LootRules = require(Shared.Domain.LootRules)
local Content = require(Shared.Content)

return function(t)
	t.test("every enemy's loot table exists and drops only real items that some recipe uses", function()
		local used = {}
		for _, recipe in pairs(Content.recipes) do
			for _, input in ipairs(recipe.inputs) do
				used[input.itemId] = true
			end
		end
		for id, def in pairs(Content.enemies) do
			local lootTable = Content.lootTables[def.lootTable]
			t.truthy(lootTable ~= nil, id .. " has a loot table")
			for _, entry in ipairs(lootTable and lootTable.materials or {}) do
				t.truthy(Content.items[entry.itemId] ~= nil, entry.itemId .. " exists")
				t.truthy(used[entry.itemId], entry.itemId .. " is used by a recipe")
			end
		end
	end)

	t.test("gold follows the level-difference rule; materials still drop", function()
		local always = function(): number return 0 end
		local lootTable = { gold = { min = 10, max = 10 }, materials = { { itemId = "WolfPelt", chance = 1, min = 1, max = 1 } } }
		local full = LootRules.rollTable(lootTable, 1, always)
		local none = LootRules.rollTable(lootTable, 0, always)
		t.equal(full.gold, 10)
		t.equal(none.gold, 0, "no gold from far weaker enemies")
		t.equal(#none.items, 1, "materials still drop")
	end)
end
