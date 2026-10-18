--!strict
-- Item definition rules (T-11). Tool, Equipment and ClassBook items are unique instances; the rest stack.
local Check = require(script.Parent.Parent.Util.Check)

local ItemRegistry = {}

ItemRegistry.KINDS = table.freeze({
	Material = true,
	Consumable = true,
	Tool = true,
	Equipment = true,
	ClassBook = true,
	Quest = true,
	Recipe = true,
})
ItemRegistry.UNIQUE_KINDS = table.freeze({ Tool = true, Equipment = true, ClassBook = true })
ItemRegistry.BINDINGS = table.freeze({ None = true, OnPickup = true, OnEquip = true })

function ItemRegistry.isUnique(def: any): boolean
	return ItemRegistry.UNIQUE_KINDS[def.kind] == true
end

function ItemRegistry.validate(items: any, classes: any, rarity: any): {string}
	local problems = {}
	local function problem(itemId: any, message: string)
		table.insert(problems, "item " .. tostring(itemId) .. ": " .. message)
	end
	for key, def in pairs(items) do
		if type(def) ~= "table" or def.id ~= key or not Check.isIdentifier(def.id) then
			problem(key, "id must match its key")
		else
			if type(def.displayName) ~= "string" or def.displayName == "" then
				problem(key, "missing displayName")
			end
			if not ItemRegistry.KINDS[def.kind] then
				problem(key, "unknown kind")
			end
			if not Check.isPositiveInteger(def.maxStack) then
				problem(key, "maxStack must be a positive whole number")
			elseif ItemRegistry.UNIQUE_KINDS[def.kind] and def.maxStack ~= 1 then
				problem(key, "unique items must have maxStack 1")
			end
			if not table.find(rarity.order, def.rarity) then
				problem(key, "unknown rarity")
			end
			if not ItemRegistry.BINDINGS[def.binding] then
				problem(key, "unknown binding")
			end
			if type(def.tradable) ~= "boolean" then
				problem(key, "tradable must be true or false")
			end
			if not Check.isNonNegativeInteger(def.vendorValue) then
				problem(key, "vendorValue must be a non-negative whole number")
			end
			if def.kind == "Tool" and (type(def.tool) ~= "table" or not Check.isIdentifier(def.tool.toolType) or not Check.isPositiveInteger(def.tool.toolTier)) then
				problem(key, "tools need toolType and toolTier")
			end
			if def.kind == "Equipment" and (type(def.equipment) ~= "table" or not Check.isIdentifier(def.equipment.slot)) then
				problem(key, "equipment needs a slot")
			end
			if def.kind == "ClassBook" then
				local classId = type(def.classBook) == "table" and def.classBook.classId
				local classDef = classId and classes[classId]
				if not classDef or classDef.rarity ~= "Legendary" then
					problem(key, "class books must point to a legendary class")
				end
			end
		end
	end
	table.sort(problems)
	return problems
end

return ItemRegistry
