--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local LegendaryActivation = require(Server.Domain.LegendaryActivation)
local Transaction = require(Server.Domain.Transaction)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local ClassProgression = require(Shared.Domain.ClassProgression)
local DisciplineMastery = require(Shared.Domain.DisciplineMastery)
local ProfessionProgression = require(Shared.Domain.ProfessionProgression)
local Inventory = require(Shared.Domain.Inventory)
local Table = require(Shared.Util.Table)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

-- A level-8 Swordmaster with stats, mastery, a profession, items, gold and a legendary class book.
local function veteran()
	local profile, deps = Fixtures.profile(), Fixtures.deps()
	local character = Fixtures.character(profile)
	ClassProgression.assignInitialClass(character.class, "Swordmaster", Content.classes, "Awakening", 1)
	CharacterProgression.grantXp(character.level, 5000, Content.stats, Content.progression)
	character.level.bonusPoints = 2
	CharacterProgression.allocate(character.level, { Strength = 5 }, Content.stats, Content.progression)
	ClassProgression.refreshUnlocks(character.class, Content.classes, { characterLevel = 8 })
	local swordArts = DisciplineMastery.newState()
	DisciplineMastery.grantXp(swordArts, Content.disciplines.SwordArts, Content.classes.Swordmaster.disciplines.SwordArts, 2000)
	character.disciplines.SwordArts = swordArts
	local mining = ProfessionProgression.newState()
	ProfessionProgression.grantXp(mining, Content.professions.Mining, 500)
	character.professions.Mining = mining
	local _, granted = Transaction.apply(profile, "main", {
		id = "setup",
		changes = {
			{ type = "GrantStack", itemId = "IronOre", amount = 7 },
			{ type = "GrantUnique", itemId = "TrainingSword", origin = { kind = "Starter" } },
			{ type = "GrantUnique", itemId = "LegendaryBookPlaceholder", origin = { kind = "Loot", source = "HiddenCave" } },
			{ type = "AdjustCurrency", currency = "Gold", amount = 300 },
		},
	}, deps)
	return profile, deps, granted.created[2], granted.created[1]
end

return function(t)
	t.test("activation fully resets class progression and keeps everything else", function()
		local profile, deps, bookUid, swordUid = veteran()
		local before = Table.deepCopy(Fixtures.character(profile))
		local ok, result = LegendaryActivation.activate(profile, "main", bookUid, "legendary:1", deps)
		t.truthy(ok, tostring(result))
		t.equal(result.previousClassId, "Swordmaster")
		local after = Fixtures.character(profile)
		-- reset
		t.equal(after.inventory.uniques[bookUid], nil, "book consumed")
		t.equal(after.level.xp, 0, "level 1")
		t.deepEqual(after.level.allocated, {}, "stats reset")
		t.equal(after.class.classId, "PlaceholderLegendary")
		t.deepEqual(after.class.unlocks, {}, "old class unlocks gone")
		t.equal(after.disciplines.SwordArts, nil, "old mastery removed")
		t.truthy(after.disciplines.PlaceholderLegendaryArts.techniques.LegendaryStrike, "new discipline from its start")
		t.truthy(after.legendary.active)
		t.equal(after.level.xpBonus.untilLevel, Content.progression.legendaryCatchUp.untilLevel)
		-- preserved
		t.equal(after.level.bonusPoints, 2, "non-class bonus points kept")
		t.deepEqual(after.professions, before.professions)
		t.deepEqual(after.currencies, before.currencies)
		t.deepEqual(after.inventory.uniques[swordUid], before.inventory.uniques[swordUid])
		t.equal(Inventory.count(after.inventory, "IronOre"), 7)
		t.equal(profile.account.classHistory[1].classId, "Swordmaster")
	end)

	t.test("a repeated request is a no-op and a new request finds no book", function()
		local profile, deps, bookUid = veteran()
		t.truthy(LegendaryActivation.activate(profile, "main", bookUid, "legendary:1", deps))
		local snapshot = Table.deepCopy(profile)
		local ok, result = LegendaryActivation.activate(profile, "main", bookUid, "legendary:1", deps)
		t.truthy(ok)
		t.truthy(result.alreadyApplied)
		local second = LegendaryActivation.activate(profile, "main", bookUid, "legendary:2", deps)
		t.falsy(second, "book already consumed")
		t.deepEqual(profile, snapshot)
	end)

	t.test("failed activations change nothing", function()
		local profile, deps, bookUid, swordUid = veteran()
		local snapshot = Table.deepCopy(profile)
		t.falsy(LegendaryActivation.activate(profile, "main", "missing-uid", "legendary:1", deps), "no such item")
		t.falsy(LegendaryActivation.activate(profile, "main", swordUid, "legendary:2", deps), "not a book")
		t.falsy(LegendaryActivation.activate(profile, "main", bookUid, "bad id", deps), "bad operation id")
		local production = Fixtures.deps()
		production.allowDevelopmentContent = false
		t.falsy(LegendaryActivation.activate(profile, "main", bookUid, "legendary:3", production), "development-only class")
		t.deepEqual(profile, snapshot)
	end)

	t.test("the catch-up bonus speeds up the new climb", function()
		local profile, deps, bookUid = veteran()
		LegendaryActivation.activate(profile, "main", bookUid, "legendary:1", deps)
		local level = Fixtures.character(profile).level
		local _, result = CharacterProgression.grantXp(level, 50, Content.stats, Content.progression)
		t.equal(result.gained, math.floor(50 * Content.progression.legendaryCatchUp.startMultiplier))
	end)
end
