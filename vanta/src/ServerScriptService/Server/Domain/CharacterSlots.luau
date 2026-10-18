--!strict
-- Character slots (L-45). Accounts start with one slot; more come from account-level unlocks (level
-- thresholds in Config/CharacterSlots, empty until decided). Each character keeps its own data, and a new
-- character can never overwrite another. Deleting needs a short-lived confirmation token issued by the
-- server, so an accidental tap or a forged request can't delete anything.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Check = require(Shared.Util.Check)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)

local CharacterSlots = {}

function CharacterSlots.count(profileData: any): number
	local count = 0
	for _ in pairs(profileData.characters) do
		count += 1
	end
	return count
end

function CharacterSlots.unlockedSlots(account: any, rules: any): number
	local count = rules.baseSlots
	for _ in pairs(account.slots.earned or {}) do
		count += 1
	end
	return math.min(count, rules.maxSlots)
end

-- Records a character's level on the account and grants any slot unlocks reached. Unlocks belong to the
-- account and stay even if the character that earned them is deleted.
function CharacterSlots.recordLevel(account: any, level: number, rules: any): {string}
	local slots = account.slots
	slots.earned = slots.earned or {}
	slots.highestLevel = math.max(slots.highestLevel or 1, level)
	local granted = {}
	for _, unlock in ipairs(rules.unlocks) do
		if slots.highestLevel >= unlock.atLevel and not slots.earned[unlock.id] then
			slots.earned[unlock.id] = true
			table.insert(granted, unlock.id)
		end
	end
	return granted
end

function CharacterSlots.create(profileData: any, characterId: any, now: number, rules: any): (boolean, string?)
	if not Check.isToken(characterId, 64) or profileData.characters[characterId] ~= nil then
		return false, "invalid character id"
	end
	if CharacterSlots.count(profileData) >= CharacterSlots.unlockedSlots(profileData.account, rules) then
		return false, "no free character slot"
	end
	local character = PlayerSchema.newCharacter(characterId)
	character.createdAt = now
	profileData.characters[characterId] = character
	return true, nil
end

function CharacterSlots.select(profileData: any, characterId: any): (boolean, string?)
	if type(characterId) ~= "string" or profileData.characters[characterId] == nil then
		return false, "unknown character"
	end
	profileData.activeCharacterId = characterId
	return true, nil
end

-- When a character may be deleted (L-49): one that has awakened only after the waiting period since its
-- awakening, so re-rolling the class costs real time; one that hasn't awakened, any time.
function CharacterSlots.deletableAt(character: any, rules: any): number
	if character.class.classId == nil then
		return 0
	end
	return (character.class.assignedAt or 0) + (rules.deleteWaitSeconds or 0)
end

-- Step one of deleting: the server issues a token the client must send back within the time limit.
function CharacterSlots.requestDeletion(profileData: any, characterId: any, token: string, now: number, rules: any): (boolean, string?)
	if type(characterId) ~= "string" or profileData.characters[characterId] == nil then
		return false, "unknown character"
	end
	if now < CharacterSlots.deletableAt(profileData.characters[characterId], rules) then
		return false, "can't be deleted yet"
	end
	profileData.account.deletion = { characterId = characterId, token = token, expiresAt = now + rules.deletionConfirmSeconds }
	return true, nil
end

-- Step two. The account always keeps a character: deleting the last one leaves a fresh character in its
-- place, under replacementId. If the active character was deleted, another one becomes active.
function CharacterSlots.confirmDeletion(profileData: any, characterId: any, token: any, replacementId: string, now: number, rules: any): (boolean, string?)
	local pending = profileData.account.deletion
	if pending == nil or pending.characterId ~= characterId or pending.token ~= token or (pending.expiresAt or 0) <= now then
		return false, "deletion was not confirmed"
	end
	if profileData.characters[characterId] == nil then
		return false, "unknown character"
	end
	if now < CharacterSlots.deletableAt(profileData.characters[characterId], rules) then
		profileData.account.deletion = {}
		return false, "can't be deleted yet"
	end
	profileData.characters[characterId] = nil
	profileData.account.deletion = {}
	if next(profileData.characters) == nil then
		local fresh = PlayerSchema.newCharacter(replacementId)
		fresh.createdAt = now
		profileData.characters[replacementId] = fresh
	end
	if profileData.characters[profileData.activeCharacterId] == nil then
		local ids = {}
		for id in pairs(profileData.characters) do
			table.insert(ids, id)
		end
		table.sort(ids)
		profileData.activeCharacterId = ids[1]
	end
	return true, nil
end

return CharacterSlots
