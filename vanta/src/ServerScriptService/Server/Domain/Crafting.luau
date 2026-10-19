--!strict
-- One crafting system for every facility (L-31). A craft is planned here as a list of transaction
-- changes (consume materials, pay the fee, grant the item with its permanent crafting record, L-32)
-- that Transaction then applies all-or-nothing. Facilities change fees, recipes and quality bonuses;
-- they never replace profession level, known recipes or materials.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local ItemRegistry = require(Shared.Domain.ItemRegistry)
local Inventory = require(Shared.Domain.Inventory)

local Crafting = {}

function Crafting.rollQuality(levelsAbove: number, facility: any, rules: any, random: () -> number): string
	local score = levelsAbove * rules.quality.perLevel + (facility.qualityBonus or 0) + random() * rules.quality.spread
	local grade = rules.quality.grades[1].grade
	for _, entry in ipairs(rules.quality.grades) do
		if score >= entry.min then
			grade = entry.grade
		end
	end
	return grade
end

local ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- The rarity of a crafted item: better odds the further the crafter is above the recipe's level, never above the
-- recipe's maximum, Legendary never more than the cap (L-60).
local function rarityWeights(levelsAbove: number, recipe: any, rules: any): ({number}, number)
	local maxIndex = table.find(ORDER, recipe.maxRarity or rules.defaultMax) or 4
	local weights, total = {}, 0
	for index, rarity in ipairs(ORDER) do
		local weight = 0
		if index <= maxIndex then
			weight = rules.base[rarity] * math.max(0.1, 1 + math.max(0, levelsAbove) * rules.growth[rarity])
		end
		weights[index] = weight
		total += weight
	end
	if maxIndex >= 5 and total > 0 and weights[5] / total > rules.legendaryCap then
		local others = total - weights[5]
		weights[5] = others * rules.legendaryCap / (1 - rules.legendaryCap)
		total = others + weights[5]
	end
	return weights, total
end

function Crafting.rollRarity(levelsAbove: number, recipe: any, rules: any, random: () -> number): string
	local weights, total = rarityWeights(levelsAbove, recipe, rules)
	local pick = random() * total
	for index, weight in ipairs(weights) do
		pick -= weight
		if pick < 0 then
			return ORDER[index]
		end
	end
	return ORDER[1]
end

-- Profession XP for a craft, reduced when the recipe is far below the crafter's level.
function Crafting.professionXp(recipe: any, levelsAbove: number, falloff: any): number
	for _, step in ipairs(falloff or {}) do
		if levelsAbove >= step.levelsAbove then
			return math.floor((recipe.professionXp or 0) * step.share)
		end
	end
	return recipe.professionXp or 0
end

-- context: { recipes, facilities, items, rules, inventory, gold, professionLevel, knownRecipes,
--            completedQuests, crafter = { userId, name } }
-- Returns ok and either a reason or { changes, quality, profession, professionXp }.-- The chance of each rarity at this many levels above the recipe, from the same weights the roll uses (shown in
-- the crafting window).
function Crafting.rarityChances(levelsAbove: number, recipe: any, rules: any): {any}
	local weights, total = rarityWeights(levelsAbove, recipe, rules)
	local result = {}
	for index, weight in ipairs(weights) do
		if weight > 0 and total > 0 then
			table.insert(result, { rarity = ORDER[index], chance = weight / total })
		end
	end
	return result
end

function Crafting.plan(recipeId: any, facilityId: any, context: any, random: () -> number): (boolean, any)
	local recipe = type(recipeId) == "string" and context.recipes[recipeId]
	if not recipe then
		return false, "unknown recipe"
	end
	local facility = type(facilityId) == "string" and context.facilities[facilityId]
	if not facility then
		return false, "unknown facility"
	end
	if not facility.processes[recipe.process] or (facility.recipes ~= nil and not facility.recipes[recipeId]) then
		return false, "this facility cannot make that"
	end
	if facility.unlockQuest ~= nil and not context.completedQuests[facility.unlockQuest] then
		return false, "complete this facility's introduction first"
	end
	if context.professionLevel < recipe.minProfessionLevel then
		return false, string.format("needs %s level %d", recipe.profession, recipe.minProfessionLevel)
	end
	if recipe.learned and not context.knownRecipes[recipeId] then
		return false, "recipe not learned"
	end
	for _, input in ipairs(recipe.inputs) do
		if Inventory.count(context.inventory, input.itemId) < input.amount then
			return false, "missing materials"
		end
	end
	local fee = facility.fee or 0
	if fee > context.gold then
		return false, "cannot afford the service fee"
	end
	if not Check.isPositiveInteger(context.crafter.userId) or type(context.crafter.name) ~= "string" then
		return false, "invalid crafter"
	end
	local levelsAbove = context.professionLevel - recipe.minProfessionLevel
	local quality = Crafting.rollQuality(levelsAbove, facility, context.rules, random)
	local outputDef = context.items[recipe.output.itemId]
	local isGear = outputDef ~= nil and outputDef.kind == "Equipment"
	local rarity = if isGear and context.rules.rarity ~= nil then Crafting.rollRarity(levelsAbove, recipe, context.rules.rarity, random) else nil
	local crafted = {
		byUserId = context.crafter.userId,
		byName = context.crafter.name,
		profession = recipe.profession,
		quality = quality,
		recipeId = recipeId,
	}
	local changes = {}
	for _, input in ipairs(recipe.inputs) do
		table.insert(changes, { type = "ConsumeItem", itemId = input.itemId, amount = input.amount })
	end
	if fee > 0 then
		table.insert(changes, { type = "AdjustCurrency", currency = "Gold", amount = -fee })
	end
	if ItemRegistry.isUnique(context.items[recipe.output.itemId]) then
		for _ = 1, recipe.output.amount do
			table.insert(changes, {
				type = "GrantUnique",
				itemId = recipe.output.itemId,
				origin = { kind = "Crafted", source = facilityId },
				crafted = crafted,
				data = if rarity ~= nil then { rarity = rarity, itemLevel = recipe.itemLevel or outputDef.itemLevel or 1 } else nil,
			})
		end
	else
		table.insert(changes, { type = "GrantStack", itemId = recipe.output.itemId, amount = recipe.output.amount, crafted = crafted })
	end
	return true, { changes = changes, quality = quality, rarity = rarity, profession = recipe.profession, professionXp = Crafting.professionXp(recipe, levelsAbove, context.rules.xpFalloff) }
end

return Crafting
