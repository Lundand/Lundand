--!strict
-- Item stats for one item instance (owner's equipment specification): the definition's base stats, grown by the
-- instance's item level and scaled by its rarity. Instances may carry their own itemLevel and rarity (drops and crafts
-- roll them); otherwise the definition's apply. Also: level bands, required level, and armour weight rules.
local ItemStats = {}

function ItemStats.itemLevel(def: any, instance: any?): number
	return (instance and (instance.itemLevel or (instance.data and instance.data.itemLevel))) or def.itemLevel or 1
end

function ItemStats.rarity(def: any, instance: any?): string
	return (instance and (instance.rarity or (instance.data and instance.data.rarity))) or def.rarity or "Common"
end

function ItemStats.compute(def: any, instance: any?, gear: any): {[string]: number}
	local growth = 1 + (ItemStats.itemLevel(def, instance) - 1) * gear.levelGrowth
	local multiplier = gear.rarityMultiplier[ItemStats.rarity(def, instance)] or 1
	local quality = instance and instance.crafted and instance.crafted.quality
	if quality ~= nil and gear.qualityBonus ~= nil then
		multiplier *= 1 + (gear.qualityBonus[quality] or 0)
	end
	local stats = {}
	for stat, base in pairs(def.stats or {}) do
		stats[stat] = math.floor(base * growth * multiplier * 10 + 0.5) / 10
	end
	return stats
end

-- Weapon handling (S1): the weapon's subtype profile from Config.Gear.weaponFamilies (speed, reach, damage, relative to
-- the family's standard weapon). Weapons without a subtype handle as the standard: { speed = 1, reach = 1, damage = 1 }.
function ItemStats.handling(def: any, gear: any): { speed: number, reach: number, damage: number }
	local equipment = def and def.equipment
	local family = equipment and gear.weaponFamilies and gear.weaponFamilies[equipment.weaponType]
	local profile = family and equipment.subtype and family.subtypes[equipment.subtype]
	if profile == nil then
		return { speed = 1, reach = 1, damage = 1 }
	end
	return { speed = profile.speed, reach = profile.reach, damage = profile.damage }
end

-- Secondary stats (S2): an item's percentage bonuses to the character's derived stats (attackSpeed, physicalDamage,
-- magicPower, maxHealth, maxStamina, staminaRegen), e.g. { attackSpeed = 0.03 } is +3%. Better rarity strengthens them
-- by the same multiplier as the item's base stats.
function ItemStats.bonuses(def: any, instance: any?, gear: any): {[string]: number}
	local multiplier = gear.rarityMultiplier[ItemStats.rarity(def, instance)] or 1
	local result = {}
	for stat, value in pairs(def.bonuses or {}) do
		result[stat] = math.floor(value * multiplier * 1000 + 0.5) / 1000
	end
	return result
end

-- The sum of every equipped item's bonuses (equipment: slot -> item instance).
function ItemStats.equipmentBonuses(equipment: any, items: any, gear: any): {[string]: number}
	local total = {}
	for _, entry in pairs(equipment or {}) do
		local def = entry and items[entry.itemId]
		if def ~= nil then
			for stat, value in pairs(ItemStats.bonuses(def, entry, gear)) do
				total[stat] = (total[stat] or 0) + value
			end
		end
	end
	return total
end

-- The character level needed to use the item: its item level unless the definition says otherwise.
function ItemStats.requiredLevel(def: any, instance: any?): number
	return def.requiredLevel or ItemStats.itemLevel(def, instance)
end

function ItemStats.band(level: number, gear: any): string?
	for _, band in ipairs(gear.bands) do
		if level >= band.from and level <= band.to then
			return band.name
		end
	end
	return nil
end

function ItemStats.armorAllowed(classId: any, weight: any, gear: any): boolean
	if weight == nil then
		return true
	end
	if weight == "Heavy" then
		return table.find(gear.heavyArmorClasses, classId) ~= nil
	end
	if weight == "Medium" then
		return table.find(gear.lightOnlyClasses, classId) == nil
	end
	return true
end

return ItemStats
