--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Crafting = require(game:GetService("ServerScriptService").Server.Domain.Crafting)
local ItemStats = require(Shared.Domain.ItemStats)
local LootRules = require(Shared.Domain.LootRules)
local Content = require(Shared.Content)
local rules = Content.crafting.rarity
local gear = Content.gear

local function shares(levelsAbove: number, recipe: any, samples: number): any
	local random = Random.new(7)
	local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for _ = 1, samples do
		local rarity = Crafting.rollRarity(levelsAbove, recipe, rules, function(): number return random:NextNumber() end)
		counts[rarity] += 1
	end
	for rarity, count in pairs(counts) do
		counts[rarity] = count / samples
	end
	return counts
end

return function(t)
	t.test("smiths far above a recipe's level craft better rarities", function()
		local novice = shares(0, {}, 4000)
		local master = shares(30, {}, 4000)
		t.truthy(novice.Common > 0.6, "a beginner mostly makes Common")
		t.truthy(master.Rare + master.Epic > novice.Rare + novice.Epic + 0.15, "a master makes far more Rare and Epic")
		t.equal(master.Legendary, 0, "no Legendary unless the recipe allows it")
	end)

	t.test("Legendary is possible only from top recipes, and never more than the cap", function()
		local top = shares(200, { maxRarity = "Legendary" }, 6000)
		t.truthy(top.Legendary > 0, "possible")
		t.truthy(top.Legendary <= rules.legendaryCap + 0.01, "within the cap")
	end)

	t.test("crafting far below your level gives little or no profession XP", function()
		local recipe = { professionXp = 40 }
		t.equal(Crafting.professionXp(recipe, 0, Content.crafting.xpFalloff), 40)
		t.equal(Crafting.professionXp(recipe, 5, Content.crafting.xpFalloff), 20)
		t.equal(Crafting.professionXp(recipe, 10, Content.crafting.xpFalloff), 0)
	end)

	t.test("crafted quality makes a crafted item better than an equal drop", function()
		local def = { stats = { attackPower = 20 } }
		local dropped = ItemStats.compute(def, { data = { rarity = "Rare", itemLevel = 10 } }, gear).attackPower
		local crafted = ItemStats.compute(def, { data = { rarity = "Rare", itemLevel = 10 }, crafted = { quality = "Masterwork" } }, gear).attackPower
		t.truthy(crafted > dropped)
	end)

	t.test("equipment drops are extremely rare and never Legendary", function()
		local random = Random.new(11)
		local function roll(def: any): any
			return LootRules.roll(def, Content.items, gear.drops, gear.levelCap, function(): number return random:NextNumber() end)
		end
		local normal, bossDrops, legendary = 0, 0, 0
		for _ = 1, 20000 do
			local drop = roll({ level = 5 })
			if drop then
				normal += 1
				if drop.rarity == "Legendary" then legendary += 1 end
				t.equal(drop.itemLevel, 5)
			end
		end
		for _ = 1, 5000 do
			local drop = roll({ level = 80, boss = true })
			if drop then
				bossDrops += 1
				t.equal(drop.itemLevel, gear.levelCap, "item level within the cap")
			end
		end
		t.truthy(normal >= 15 and normal <= 80, "ordinary mobs: about 0.2 percent (" .. normal .. " in 20000)")
		t.truthy(bossDrops >= 120 and bossDrops <= 290, "bosses: about 4 percent (" .. bossDrops .. " in 5000)")
		t.equal(legendary, 0)
	end)
end
