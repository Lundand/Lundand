--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local QuestRules = require(Server.Domain.QuestRules)
local Crafting = require(Server.Domain.Crafting)
local Transaction = require(Server.Domain.Transaction)
local Inventory = require(Shared.Domain.Inventory)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local quests = Content.quests

return function(t)
	t.test("registration leads to the repeatable bounty", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local state = Fixtures.character(profile).quests
		t.falsy(QuestRules.accept(state, quests.BountyForestPests, 1, 0), "needs registration")
		t.truthy(QuestRules.accept(state, quests.AdventurerRegistration, 1, 0))
		t.falsy(QuestRules.accept(state, quests.AdventurerRegistration, 1, 0), "already active")
		t.deepEqual(QuestRules.applyEvent(state, quests, { kind = "Talk", target = "GuildRegistrar" }), { "AdventurerRegistration" })
		local ok, rewards = QuestRules.turnIn(profile, "main", quests.AdventurerRegistration, Content.items, deps)
		t.truthy(ok, tostring(rewards))
		t.equal(rewards.characterXp, 50)
		t.equal(Fixtures.character(profile).currencies.Gold, 25)
		t.falsy(QuestRules.turnIn(profile, "main", quests.AdventurerRegistration, Content.items, deps), "no second reward")
		t.falsy(QuestRules.accept(state, quests.AdventurerRegistration, 1, 10), "not repeatable")
		t.truthy(QuestRules.accept(state, quests.BountyForestPests, 1, 10))
	end)

	t.test("bounty progress is capped and the bounty repeats after its cooldown", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local state = Fixtures.character(profile).quests
		state.AdventurerRegistration = { state = "Completed", progress = {}, completions = 1, availableAt = 0 }
		QuestRules.accept(state, quests.BountyForestPests, 1, 0)
		QuestRules.applyEvent(state, quests, { kind = "Kill", target = "ForestWolf", amount = 3 })
		t.falsy(QuestRules.isComplete(state.BountyForestPests, quests.BountyForestPests, Fixtures.character(profile).inventory))
		QuestRules.applyEvent(state, quests, { kind = "Kill", target = "ForestWolf", amount = 9 })
		t.equal(state.BountyForestPests.progress.Wolves, 5, "capped")
		t.truthy(QuestRules.turnIn(profile, "main", quests.BountyForestPests, Content.items, deps))
		t.falsy(QuestRules.accept(state, quests.BountyForestPests, 1, deps.now() + 10), "cooldown")
		t.truthy(QuestRules.accept(state, quests.BountyForestPests, 1, deps.now() + 3600))
		QuestRules.applyEvent(state, quests, { kind = "Kill", target = "ForestWolf", amount = 5 })
		t.truthy(QuestRules.turnIn(profile, "main", quests.BountyForestPests, Content.items, deps))
		t.equal(state.BountyForestPests.completions, 2)
		t.equal(Fixtures.character(profile).currencies.Gold, 80, "paid twice, once per completion")
	end)

	t.test("the forge introduction takes delivered logs and unlocks the City Forge", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps(7)
		local character = Fixtures.character(profile)
		QuestRules.accept(character.quests, quests.CraftsmenIntroForge, 1, 0)
		QuestRules.applyEvent(character.quests, quests, { kind = "Gather", target = "CopperOre", amount = 4 })
		QuestRules.applyEvent(character.quests, quests, { kind = "Talk", target = "ForgeMaster" })
		t.falsy(QuestRules.turnIn(profile, "main", quests.CraftsmenIntroForge, Content.items, deps), "no logs yet")
		Transaction.apply(profile, "main", { id = "logs", changes = { { type = "GrantStack", itemId = "OakLog", amount = 3 } } }, deps)
		local ok, rewards = QuestRules.turnIn(profile, "main", quests.CraftsmenIntroForge, Content.items, deps)
		t.truthy(ok, tostring(rewards))
		t.equal(rewards.professionXp.Blacksmithing, 30)
		t.equal(Inventory.count(Fixtures.character(profile).inventory, "OakLog"), 1, "two logs delivered")
		local completed = QuestRules.completedSet(Fixtures.character(profile).quests)
		local allowed = Crafting.plan("TrainingSword", "CityBlacksmith", {
			recipes = Content.recipes,
			facilities = Content.facilities,
			items = Content.items,
			rules = Content.crafting,
			inventory = Fixtures.character(profile).inventory,
			gold = 100,
			professionLevel = 1,
			knownRecipes = {},
			completedQuests = completed,
			crafter = { userId = 7, name = "Jonathan" },
		}, function()
			return 0
		end)
		t.equal(allowed, false, "still missing copper, but no longer blocked by the introduction")
	end)

	t.test("invalid events are ignored and abandoning removes an unfinished quest", function()
		local state = {}
		QuestRules.accept(state, quests.AdventurerRegistration, 1, 0)
		t.deepEqual(QuestRules.applyEvent(state, quests, { kind = "Steal", target = "GuildRegistrar" }), {})
		t.deepEqual(QuestRules.applyEvent(state, quests, { kind = "Talk", target = "GuildRegistrar", amount = -1 }), {})
		t.truthy(QuestRules.abandon(state, "AdventurerRegistration"))
		t.equal(state.AdventurerRegistration, nil)
		t.falsy(QuestRules.abandon(state, "AdventurerRegistration"))
	end)
end
