--!strict
-- The opening (L-43). Characters that haven't awakened start in the church. After the awakening, the
-- chest by the church door gives the class's starting weapon exactly once per character, and puts it in
-- hand when the hand is empty.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Equipment = require(Shared.Domain.Equipment)
local Transaction = require(script.Parent.Transaction)

local Onboarding = {}

function Onboarding.spawnPoint(character: any): string
	if character.class.classId == nil then
		return "Church"
	end
	return "Plaza"
end

function Onboarding.claimStarterWeapon(profileData: any, characterId: string, deps: any): (boolean, any)
	local character = profileData.characters[characterId]
	if character == nil then
		return false, "unknown character"
	end
	if character.claims.StarterWeapon then
		return false, "the chest is empty"
	end
	local classDef = character.class.classId and deps.classes[character.class.classId]
	if not classDef then
		return false, "the chest won't open until the System has given you a class"
	end
	local itemId = classDef.startingWeapon
	local def = itemId and deps.items[itemId]
	if not def then
		return false, "no starting weapon for this class"
	end
	local ok, result = Transaction.apply(profileData, characterId, {
		id = "starter:" .. characterId,
		reason = "StarterWeapon",
		changes = { { type = "GrantUnique", itemId = itemId, origin = { kind = "Starter", source = "ChurchChest" } } },
	}, deps)
	if not ok then
		return false, result
	end
	character = profileData.characters[characterId]
	character.claims.StarterWeapon = true
	local uid = result.created[1]
	local equipped = false
	if uid ~= nil and character.equipment[def.equipment.slot] == nil then
		equipped = Equipment.equip(character, uid, deps.items, deps.ownerUserId, deps.classes)
	end
	return true, { itemId = itemId, uid = uid, equipped = equipped }
end

return Onboarding
