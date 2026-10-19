--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Gathering = require(ServerScriptService:WaitForChild("Server").Domain.Gathering)
local Inventory = require(Shared.Domain.Inventory)
local Content = require(Shared.Content)
local ResourceNodes = require(ServerStorage:WaitForChild("ServerData").ResourceNodes)

local function sequence(values: {number})
	local index = 0
	return function()
		index += 1
		return values[index]
	end
end

return function(t)
	t.test("the shipped node definitions are valid", function()
		t.deepEqual(Gathering.validateNodes(ResourceNodes, Content.items, Content.professions), {})
	end)

	t.test("requirements check tool tier and profession level", function()
		local silver = ResourceNodes.SilverVein
		t.falsy(Gathering.check(silver, 1, 20), "copper pickaxe")
		t.falsy(Gathering.check(silver, 2, 9), "level too low")
		t.truthy(Gathering.check(silver, 2, 10))
		t.truthy(Gathering.check(ResourceNodes.HealingHerbPatch, 0, 1), "herbs need no tool")
	end)

	t.test("the best tool in the inventory is found", function()
		local bag = Inventory.newContainer(10)
		Inventory.addUnique(bag, Content.items, { uid = "a", itemId = "CopperPickaxe", createdBy = "x", origin = { kind = "Vendor", at = 1 } })
		Inventory.addUnique(bag, Content.items, { uid = "b", itemId = "IronPickaxe", createdBy = "x", origin = { kind = "Vendor", at = 1 } })
		t.equal(Gathering.bestToolTier(bag, Content.items, "Pickaxe"), 2)
		t.equal(Gathering.bestToolTier(bag, Content.items, "Axe"), 0)
	end)

	t.test("gather time shrinks with level and tool tier, within its limit", function()
		local copper = ResourceNodes.CopperVein
		t.equal(Gathering.duration(copper, 1, 1), copper.baseDuration)
		t.truthy(Gathering.duration(copper, 2, 11) < copper.baseDuration)
		t.near(Gathering.duration(copper, 9, 50), copper.baseDuration * (1 - copper.efficiency.maxReduction), 0.0001)
	end)

	t.test("drops stay within their ranges and honour chances", function()
		local silver = ResourceNodes.SilverVein
		t.deepEqual(Gathering.rollDrops(silver, sequence({ 0, 0.9 })), { { itemId = "SilverOre", amount = 1 } })
		t.deepEqual(Gathering.rollDrops(silver, sequence({ 0.9999, 0.1, 0.5 })), {
			{ itemId = "IronOre", amount = 1 },
			{ itemId = "SilverOre", amount = 2 },
		})
	end)

	t.test("personal nodes respawn per player and saved cooldowns win", function()
		local herb = ResourceNodes.HealingHerbPatch
		local state = Gathering.newNodeState()
		Gathering.markGathered(state, herb, "1", 100)
		t.equal(Gathering.readyAt(state, herb, "1", nil), 100 + herb.respawn.seconds)
		t.equal(Gathering.readyAt(state, herb, "2", nil), 0, "another player is unaffected")
		t.equal(Gathering.readyAt(state, herb, "2", 5000), 5000, "saved cooldown from another server")
		local cooldowns = { a = 50, b = 500 }
		t.equal(Gathering.pruneCooldowns(cooldowns, 100), 1)
		t.equal(cooldowns.a, nil)
	end)
end
