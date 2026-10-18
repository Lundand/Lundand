--!strict
-- Cosmetic rules (L-34, L-46): when an item can be bought, ownership, and wearing. Ownership is account-wide
-- and permanent (account.cosmetics.owned); what each character wears is saved with that character
-- (appearance.cosmetics). Nothing here touches stats.
local Cosmetics = {}

-- "Available", "Upcoming", "Ended", "Retired" or "NotConfigured" (no developer product yet).
function Cosmetics.availability(item: any, now: number): string
	if item.status == "Retired" then
		return "Retired"
	end
	if (item.productId or 0) <= 0 then
		return "NotConfigured"
	end
	if item.startsAt ~= nil and now < item.startsAt then
		return "Upcoming"
	end
	if item.endsAt ~= nil and now >= item.endsAt then
		return "Ended"
	end
	return "Available"
end

-- The shop's label. Only time limits exist, so nothing is ever labelled as limited in quantity.
function Cosmetics.label(item: any): string
	if item.endsAt ~= nil then
		return "LimitedTime"
	end
	return "Permanent"
end

function Cosmetics.owns(account: any, cosmeticId: any): boolean
	return account.cosmetics.owned ~= nil and account.cosmetics.owned[cosmeticId] ~= nil
end

-- Checked on the server before it prompts a purchase.
function Cosmetics.canBuy(account: any, item: any, now: number): (boolean, string?)
	if Cosmetics.availability(item, now) ~= "Available" then
		return false, "not on sale"
	end
	if Cosmetics.owns(account, item.id) then
		return false, "already owned"
	end
	return true, nil
end

-- Records ownership once; granting an owned item again changes nothing.
function Cosmetics.grant(account: any, cosmeticId: string, source: string, at: number): boolean
	account.cosmetics.owned = account.cosmetics.owned or {}
	if account.cosmetics.owned[cosmeticId] ~= nil then
		return false
	end
	account.cosmetics.owned[cosmeticId] = { source = source, at = at }
	return true
end

-- Where an item is worn: one per category, and one weapon skin per weapon type.
function Cosmetics.wearKey(item: any): string
	if item.category == "WeaponSkin" then
		return "WeaponSkin." .. tostring(item.weaponType)
	end
	return item.category
end

-- Retired items stay wearable by their owners.
function Cosmetics.equip(account: any, character: any, cosmeticId: any, catalogue: any): (boolean, string?)
	local item = type(cosmeticId) == "string" and catalogue.items[cosmeticId]
	if not item or not Cosmetics.owns(account, cosmeticId) then
		return false, "you don't own that"
	end
	if item.classes ~= nil and (character.class.classId == nil or table.find(item.classes, character.class.classId) == nil) then
		return false, "your class can't wear that"
	end
	character.appearance.cosmetics = character.appearance.cosmetics or {}
	character.appearance.cosmetics[Cosmetics.wearKey(item)] = cosmeticId
	return true, nil
end

function Cosmetics.unequip(character: any, wearKey: any): (boolean, string?)
	local worn = character.appearance.cosmetics
	if type(wearKey) ~= "string" or worn == nil or worn[wearKey] == nil then
		return false, "nothing worn there"
	end
	worn[wearKey] = nil
	return true, nil
end

return Cosmetics
