--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CharacterSlots = require(ServerScriptService:WaitForChild("Server").Domain.CharacterSlots)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local rules = Content.characterSlots

return function(t)
	t.test("accounts start with one slot", function()
		local profile = Fixtures.profile()
		t.equal(CharacterSlots.unlockedSlots(profile.account, rules), 1)
		t.falsy(CharacterSlots.create(profile, "second", 0, rules))
	end)

	t.test("slot unlocks come from the account's best level and outlive the character that earned them", function()
		local profile = Fixtures.profile()
		local custom = { baseSlots = 1, maxSlots = 3, deletionConfirmSeconds = 60, unlocks = { { id = "Slot2", atLevel = 10 } } }
		t.deepEqual(CharacterSlots.recordLevel(profile.account, 9, custom), {})
		t.deepEqual(CharacterSlots.recordLevel(profile.account, 10, custom), { "Slot2" })
		t.truthy(CharacterSlots.create(profile, "second", 5, custom))
		t.falsy(CharacterSlots.create(profile, "second", 5, custom), "never overwrites")
		t.falsy(CharacterSlots.create(profile, "third", 5, custom), "slots full")
		t.equal(profile.characters.second.createdAt, 5)
		t.truthy(CharacterSlots.select(profile, "second"))
		t.equal(profile.activeCharacterId, "second")
		CharacterSlots.requestDeletion(profile, "main", "token", 0, custom)
		t.truthy(CharacterSlots.confirmDeletion(profile, "main", "token", "fresh", 1, custom))
		t.equal(CharacterSlots.unlockedSlots(profile.account, custom), 2, "unlock kept")
		t.equal(profile.characters.fresh, nil, "another character remains, so no fresh one")
	end)

	t.test("deleting needs the matching, unexpired token, and the account always keeps a character", function()
		local profile = Fixtures.profile()
		t.falsy(CharacterSlots.confirmDeletion(profile, "main", "guess", "fresh", 0, rules), "never requested")
		CharacterSlots.requestDeletion(profile, "main", "token", 0, rules)
		t.falsy(CharacterSlots.confirmDeletion(profile, "main", "wrong", "fresh", 1, rules))
		t.falsy(CharacterSlots.confirmDeletion(profile, "main", "token", "fresh", rules.deletionConfirmSeconds, rules), "expired")
		CharacterSlots.requestDeletion(profile, "main", "token2", 0, rules)
		t.truthy(CharacterSlots.confirmDeletion(profile, "main", "token2", "fresh", 1, rules))
		t.equal(profile.characters.main, nil)
		t.equal(profile.activeCharacterId, "fresh")
		t.equal(profile.characters.fresh.class.classId, nil, "starts over from the awakening")
	end)

	t.test("an awakened character can only be deleted after the waiting period, so rerolls cost real time", function()
		local profile = Fixtures.profile()
		local wait = rules.deleteWaitSeconds
		t.truthy(wait >= 86400, "at least a day")
		local character = Fixtures.character(profile)
		character.class.classId = "Swordmaster"
		character.class.assignedAt = 1000
		t.equal(CharacterSlots.deletableAt(character, rules), 1000 + wait)
		t.falsy(CharacterSlots.requestDeletion(profile, "main", "token", 1000 + wait - 1, rules), "too soon")
		t.truthy(CharacterSlots.requestDeletion(profile, "main", "token", 1000 + wait, rules))
		character.class.assignedAt = 1000 + wait
		t.falsy(CharacterSlots.confirmDeletion(profile, "main", "token", "fresh", 1000 + wait + 1, rules), "confirming checks again")
		t.truthy(profile.characters.main ~= nil, "still there")
	end)
end
