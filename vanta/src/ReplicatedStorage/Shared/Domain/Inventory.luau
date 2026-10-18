--!strict
-- Containers hold stacks and unique items (T-11), with permanent origin and crafter records (L-31).
-- Every function validates fully before changing anything: a failed call leaves the container as it was.
--   Stacks are keyed by item ID plus crafting record, so items with different crafters or quality
--   never merge. Gathered, looted and bought materials carry no record and share one stack.
--   Unique items record where they came from (origin) and, if crafted, who made them (crafted).
--   Later work on an item is added to contributors; origin and crafted are never overwritten.
local Check = require(script.Parent.Parent.Util.Check)
local ItemRegistry = require(script.Parent.ItemRegistry)

local ItemStats = require(script.Parent.ItemStats)
local Gear = require(script.Parent.Parent.Config.Gear)

local Inventory = {}

export type Crafted = { byUserId: number, byName: string, profession: string, quality: string, recipeId: string? }
export type Stack = { itemId: string, count: number, crafted: Crafted? }
export type Origin = { kind: string, source: string?, at: number }
export type Contributor = { userId: number, name: string, action: string, at: number }
export type UniqueItem = { uid: string, itemId: string, createdBy: string, origin: Origin, crafted: Crafted?, contributors: {Contributor}?, boundTo: number?, data: {[string]: any}? }
export type Container = { capacity: number, stacks: {[string]: Stack}, uniques: {[string]: UniqueItem} }

Inventory.ORIGINS = table.freeze({
	Crafted = true,
	Gathered = true,
	Loot = true,
	Quest = true,
	Vendor = true,
	Reward = true,
	Trade = true,
	Starter = true,
	Development = true,
})
Inventory.MAX_CONTRIBUTORS = 20

function Inventory.newContainer(capacity: number): Container
	return { capacity = capacity, stacks = {}, uniques = {} }
end

function Inventory.isValidCrafted(crafted: any): boolean
	return type(crafted) == "table"
		and Check.isPositiveInteger(crafted.byUserId)
		and type(crafted.byName) == "string"
		and #crafted.byName > 0
		and #crafted.byName <= 50
		and Check.isIdentifier(crafted.profession)
		and Check.isIdentifier(crafted.quality)
		and (crafted.recipeId == nil or Check.isIdentifier(crafted.recipeId))
end

function Inventory.isValidOrigin(origin: any): boolean
	return type(origin) == "table"
		and Inventory.ORIGINS[origin.kind] == true
		and Check.isFiniteNumber(origin.at)
		and (origin.source == nil or Check.isToken(origin.source, 64))
end

local function copyCrafted(crafted: Crafted): Crafted
	return {
		byUserId = crafted.byUserId,
		byName = crafted.byName,
		profession = crafted.profession,
		quality = crafted.quality,
		recipeId = crafted.recipeId,
	}
end

function Inventory.stackKey(itemId: string, crafted: Crafted?): string
	if crafted == nil then
		return itemId
	end
	return string.format("%s|%d|%s|%s", itemId, crafted.byUserId, crafted.profession, crafted.quality)
end

function Inventory.slotsUsed(container: Container, items: any): number
	local used = 0
	for _, stack in pairs(container.stacks) do
		local def = items[stack.itemId]
		if def then
			used += math.ceil(stack.count / def.maxStack)
		else
			used += 1 -- unknown items still take space, so nothing is silently dropped
		end
	end
	for _ in pairs(container.uniques) do
		used += 1
	end
	return used
end

function Inventory.count(container: Container, itemId: string): number
	local total = 0
	for _, stack in pairs(container.stacks) do
		if stack.itemId == itemId then
			total += stack.count
		end
	end
	return total
end

function Inventory.addStack(container: Container, items: any, itemId: any, amount: any, crafted: any): (boolean, string?)
	local def = items[itemId]
	if type(itemId) ~= "string" or def == nil then
		return false, "unknown item"
	end
	if ItemRegistry.isUnique(def) then
		return false, "item is unique, not stackable"
	end
	if not Check.isPositiveInteger(amount) then
		return false, "amount must be a positive whole number"
	end
	if crafted ~= nil and not Inventory.isValidCrafted(crafted) then
		return false, "invalid crafting record"
	end
	local key = Inventory.stackKey(itemId, crafted)
	local existing = container.stacks[key]
	local current = 0
	if existing then
		current = existing.count
	end
	local extraSlots = math.ceil((current + amount) / def.maxStack) - math.ceil(current / def.maxStack)
	if Inventory.slotsUsed(container, items) + extraSlots > container.capacity then
		return false, "inventory full"
	end
	if existing then
		existing.count = current + amount
	else
		local stack = { itemId = itemId, count = amount }
		if crafted ~= nil then
			stack.crafted = copyCrafted(crafted)
		end
		container.stacks[key] = stack
	end
	return true, nil
end

-- Removes from one exact stack (keeps crafting records intact for the rest).
function Inventory.removeStack(container: Container, key: any, amount: any): (boolean, string?)
	if not Check.isPositiveInteger(amount) then
		return false, "amount must be a positive whole number"
	end
	local stack = type(key) == "string" and container.stacks[key]
	if not stack or stack.count < amount then
		return false, "not enough items"
	end
	stack.count -= amount
	if stack.count == 0 then
		container.stacks[key] = nil
	end
	return true, nil
end

-- Removes `amount` of an item across its stacks: plain stacks first, then crafted stacks by key.
function Inventory.removeItem(container: Container, itemId: any, amount: any): (boolean, string?)
	if not Check.isPositiveInteger(amount) then
		return false, "amount must be a positive whole number"
	end
	if type(itemId) ~= "string" or Inventory.count(container, itemId) < amount then
		return false, "not enough items"
	end
	local keys = {}
	for key, stack in pairs(container.stacks) do
		if stack.itemId == itemId then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local aPlain = a == itemId
		local bPlain = b == itemId
		if aPlain ~= bPlain then
			return aPlain
		end
		return a < b
	end)
	local remaining = amount
	for _, key in ipairs(keys) do
		if remaining <= 0 then
			break
		end
		local stack = container.stacks[key]
		local take = math.min(stack.count, remaining)
		stack.count -= take
		remaining -= take
		if stack.count == 0 then
			container.stacks[key] = nil
		end
	end
	return true, nil
end

function Inventory.addUnique(container: Container, items: any, unique: any): (boolean, string?)
	if type(unique) ~= "table" or not Check.isToken(unique.uid, 64) or not Check.isToken(unique.createdBy, 100) then
		return false, "invalid unique item"
	end
	local def = items[unique.itemId]
	if type(unique.itemId) ~= "string" or def == nil then
		return false, "unknown item"
	end
	if not ItemRegistry.isUnique(def) then
		return false, "item is stackable, not unique"
	end
	if not Inventory.isValidOrigin(unique.origin) then
		return false, "invalid origin"
	end
	local isCrafted = unique.origin.kind == "Crafted"
	if isCrafted ~= (unique.crafted ~= nil) then
		return false, "crafted items need a crafting record, and only crafted items may have one"
	end
	if unique.crafted ~= nil and not Inventory.isValidCrafted(unique.crafted) then
		return false, "invalid crafting record"
	end
	if container.uniques[unique.uid] ~= nil then
		return false, "duplicate item id"
	end
	if Inventory.slotsUsed(container, items) + 1 > container.capacity then
		return false, "inventory full"
	end
	container.uniques[unique.uid] = unique
	return true, nil
end

function Inventory.removeUnique(container: Container, uid: any): (boolean, any)
	local unique = type(uid) == "string" and container.uniques[uid]
	if not unique then
		return false, "item not found"
	end
	container.uniques[uid] = nil
	return true, unique
end

-- Records later work (repair, upgrade, enchant) without touching the original crafter.
function Inventory.addContributor(unique: UniqueItem, contributor: Contributor): (boolean, string?)
	if not Check.isPositiveInteger(contributor.userId) or not Check.isIdentifier(contributor.action) then
		return false, "invalid contributor"
	end
	local list = unique.contributors or {}
	table.insert(list, {
		userId = contributor.userId,
		name = contributor.name,
		action = contributor.action,
		at = contributor.at,
	})
	while #list > Inventory.MAX_CONTRIBUTORS do
		table.remove(list, 1)
	end
	unique.contributors = list
	return true, nil
end

-- Data for the item inspection panel. Never invents a crafter for non-crafted items.
function Inventory.describe(entry: any, items: any): {[string]: any}
	local def = items[entry.itemId]
	local info = {
		itemId = entry.itemId,
		name = (def and def.displayName) or entry.itemId,
		rarity = def and ItemStats.rarity(def, entry),
		itemLevel = def and ItemStats.itemLevel(def, entry),
	}
	-- Equipment shows its real stats: item level, rolled rarity and crafted quality included.
	if def ~= nil and def.kind == "Equipment" then
		info.stats = ItemStats.compute(def, entry, Gear)
		-- weapon progression: handling (subtype), secondary bonuses and a named weapon's trait
		info.bonuses = ItemStats.bonuses(def, entry, Gear)
		if def.equipment and def.equipment.subtype then
			info.subtype = def.equipment.subtype
			info.handling = ItemStats.handling(def, Gear)
		end
		if def.trait and def.trait.text then
			info.trait = def.trait.text
		end
	end
	if entry.crafted then
		info.craftedBy = entry.crafted.byName
		info.craftedByUserId = entry.crafted.byUserId
		info.profession = entry.crafted.profession
		info.quality = entry.crafted.quality
	end
	if entry.origin then
		info.origin = entry.origin.kind
		info.source = entry.origin.source
	end
	return info
end

function Inventory.validateContainer(container: any, items: any): ({string}, {string})
	local problems, warnings = {}, {}
	if type(container) ~= "table" or not Check.isPositiveInteger(container.capacity) then
		table.insert(problems, "container needs a positive capacity")
		return problems, warnings
	end
	if type(container.stacks) ~= "table" or type(container.uniques) ~= "table" then
		table.insert(problems, "container needs stacks and uniques")
		return problems, warnings
	end
	for key, stack in pairs(container.stacks) do
		if type(stack) ~= "table" or not Check.isPositiveInteger(stack.count) or type(stack.itemId) ~= "string" then
			table.insert(problems, "invalid stack " .. tostring(key))
		elseif key ~= Inventory.stackKey(stack.itemId, stack.crafted) then
			table.insert(problems, "stack key does not match its contents: " .. tostring(key))
		elseif items[stack.itemId] == nil then
			table.insert(warnings, "unknown item kept in inventory: " .. stack.itemId)
		end
	end
	for uid, unique in pairs(container.uniques) do
		if type(unique) ~= "table" or unique.uid ~= uid or type(unique.itemId) ~= "string" then
			table.insert(problems, "invalid unique item " .. tostring(uid))
		elseif items[unique.itemId] == nil then
			table.insert(warnings, "unknown unique item kept in inventory: " .. unique.itemId)
		end
	end
	return problems, warnings
end

return Inventory
