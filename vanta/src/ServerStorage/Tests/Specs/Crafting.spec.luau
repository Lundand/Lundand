--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local Crafting = require(Server.Domain.Crafting)
local Transaction = require(Server.Domain.Transaction)
local Inventory = require(Shared.Domain.Inventory)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local function low()
	return 0
end

local function high()
	return 0.999
end

-- A crafter with materials and gold who has finished both introduction quests.
local function workshop()
	local profile, deps = Fixtures.profile(), Fixtures.deps(7)
	Transaction.apply(profile, "main", {
		id = "setup",
		changes = {
			{ type = "GrantStack", itemId = "CopperOre", amount = 20 },
			{ type = "GrantStack", itemId = "OakLog", amount = 10 },
			{ type = "GrantStack", itemId = "HealingHerb", amount = 10 },
			{ type = "AdjustCurrency", currency = "Gold", amount = 100 },
		},
	}, deps)
	local character = Fixtures.character(profile)
	local function context(overrides: any?)
		local result = {
			recipes = Content.recipes,
			facilities = Content.facilities,
			items = Content.items,
			rules = Content.crafting,
			inventory = character.inventory,
			gold = character.currencies.Gold,
			professionLevel = 1,
			knownRecipes = {},
			completedQuests = { CraftsmenIntroForge = true, CraftsmenIntroBrewing = true },
			crafter = { userId = 7, name = "Jonathan" },
		}
		for key, value in pairs(overrides or {}) do
			result[key] = value
		end
		return result
	end
	return profile, deps, context
end

return function(t)
	t.test("NPC facilities need their introduction quest", function()
		local _, _, context = workshop()
		local ok, reason = Crafting.plan("TrainingSword", "CityBlacksmith", context({ completedQuests = {} }), low)
		t.falsy(ok)
		t.equal(reason, "complete this facility's introduction first")
	end)

	t.test("profession level, learned recipes and the facility's process are required", function()
		local _, _, context = workshop()
		t.falsy(Crafting.plan("IronPickaxe", "CityBlacksmith", context({ professionLevel = 4 }), low), "level")
		t.falsy(Crafting.plan("IronPickaxe", "CityBlacksmith", context({ professionLevel = 5 }), low), "not learned")
		t.falsy(Crafting.plan("MinorHealthPotion", "CityBlacksmith", context(), low), "wrong facility")
		t.falsy(Crafting.plan("TrainingSword", "Nowhere", context(), low), "unknown facility")
	end)

	t.test("materials and the fee must be available", function()
		local _, _, context = workshop()
		t.falsy(Crafting.plan("TrainingSword", "CityBlacksmith", context({ gold = 9 }), low), "fee")
		t.falsy(Crafting.plan("TrainingSword", "CityBlacksmith", context({ inventory = Inventory.newContainer(5) }), low), "materials")
	end)

	t.test("a crafted sword records its crafter, profession, quality and origin", function()
		local profile, deps, context = workshop()
		local ok, plan = Crafting.plan("TrainingSword", "CityBlacksmith", context(), low)
		t.truthy(ok, tostring(plan))
		local applied, result = Transaction.apply(profile, "main", { id = "craft-1", reason = "Craft", changes = plan.changes }, deps)
		t.truthy(applied, tostring(result))
		local character = Fixtures.character(profile)
		local sword = character.inventory.uniques[result.created[1]]
		t.equal(sword.crafted.byName, "Jonathan")
		t.equal(sword.crafted.byUserId, 7)
		t.equal(sword.crafted.profession, "Blacksmithing")
		t.equal(sword.crafted.quality, plan.quality)
		t.equal(sword.origin.kind, "Crafted")
		t.equal(sword.origin.source, "CityBlacksmith")
		t.equal(Inventory.count(character.inventory, "CopperOre"), 16)
		t.equal(character.currencies.Gold, 90)
	end)

	t.test("crafted potions keep their own stack apart from bought ones", function()
		local profile, deps, context = workshop()
		Transaction.apply(profile, "main", { id = "bought", changes = { { type = "GrantStack", itemId = "MinorHealthPotion", amount = 3 } } }, deps)
		local _, plan = Crafting.plan("MinorHealthPotion", "CityAlchemist", context(), low)
		Transaction.apply(profile, "main", { id = "brew-1", changes = plan.changes }, deps)
		local stacks = Fixtures.character(profile).inventory.stacks
		t.equal(stacks.MinorHealthPotion.count, 3)
		t.equal(Table.count(stacks) >= 2, true)
		local key = Inventory.stackKey("MinorHealthPotion", { byUserId = 7, byName = "Jonathan", profession = "Alchemy", quality = plan.quality })
		t.equal(stacks[key].crafted.byName, "Jonathan")
	end)

	t.test("quality rises with skill and luck, within the grade list", function()
		local blacksmith = Content.facilities.CityBlacksmith
		t.equal(Crafting.rollQuality(0, blacksmith, Content.crafting, low), "Standard")
		t.equal(Crafting.rollQuality(30, blacksmith, Content.crafting, high), "Masterwork")
		t.equal(Crafting.rollQuality(10, blacksmith, Content.crafting, low), "Standard", "0.5 is below Fine")
		t.equal(Crafting.rollQuality(12, blacksmith, Content.crafting, low), "Fine", "0.6 reaches Fine")
	end)

	t.test("a failed craft charges nothing and consumes nothing", function()
		local profile, deps = workshop()
		local before = Table.deepCopy(profile)
		local ok = Transaction.apply(profile, "main", {
			id = "craft-bad",
			changes = {
				{ type = "ConsumeItem", itemId = "CopperOre", amount = 4 },
				{ type = "AdjustCurrency", currency = "Gold", amount = -10 },
				{ type = "ConsumeItem", itemId = "IronOre", amount = 1 },
			},
		}, deps)
		t.falsy(ok)
		t.deepEqual(profile, before)
	end)
end
