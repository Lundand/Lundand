--!strict
-- Equipping (L-42, M10). Equipped items move out of the inventory into their slot; equipping over an item
-- swaps them. Items that bind on equip become bound to the player. All-or-nothing.
local Inventory = require(script.Parent.Inventory)

local ItemStats = require(script.Parent.ItemStats)

local Equipment = {}

Equipment.SLOTS = table.freeze({ MainHand = true, OffHand = true, Head = true, Chest = true, Legs = true, Feet = true, Hands = true, Back = true })

function Equipment.equip(character: any, uid: any, items: any, ownerUserId: number?, classes: any?, characterLevel: number?, gear: any?): (boolean, string?)
	local item = type(uid) == "string" and character.inventory.uniques[uid]
	if not item then
		return false, "item not found"
	end
	local def = items[item.itemId]
	if def == nil or def.kind ~= "Equipment" or def.equipment == nil or not Equipment.SLOTS[def.equipment.slot] then
		return false, "that can't be equipped"
	end
	-- Weapons only for classes that can use them (the owner's class specification).
	local weaponType = def.equipment.weaponType
	if classes ~= nil and weaponType ~= nil then
		local classDef = character.class and character.class.classId and classes[character.class.classId]
		if not classDef then
			return false, "you need a class to wield weapons"
		end
		if classDef.weaponTypes ~= nil and table.find(classDef.weaponTypes, weaponType) == nil then
			return false, "your class can't use that weapon"
		end
	end
	-- Required level and armour weight (owner's equipment specification).
	if characterLevel ~= nil and ItemStats.requiredLevel(def, item) > characterLevel then
		return false, string.format("requires level %d", ItemStats.requiredLevel(def, item))
	end
	if gear ~= nil and def.equipment.armorWeight ~= nil and not ItemStats.armorAllowed(character.class and character.class.classId, def.equipment.armorWeight, gear) then
		return false, "your class can't wear that armour"
	end
	local slot = def.equipment.slot
	local previous = character.equipment[slot]
	character.inventory.uniques[uid] = nil
	if previous ~= nil then
		character.inventory.uniques[previous.uid] = previous
	end
	if def.binding == "OnEquip" and item.boundTo == nil and ownerUserId ~= nil then
		item.boundTo = ownerUserId
	end
	character.equipment[slot] = item
	return true, nil
end

function Equipment.unequip(character: any, slot: any, items: any): (boolean, string?)
	local item = type(slot) == "string" and character.equipment[slot]
	if not item then
		return false, "nothing equipped there"
	end
	if Inventory.slotsUsed(character.inventory, items) >= character.inventory.capacity then
		return false, "inventory is full"
	end
	character.equipment[slot] = nil
	character.inventory.uniques[item.uid] = item
	return true, nil
end

return Equipment
