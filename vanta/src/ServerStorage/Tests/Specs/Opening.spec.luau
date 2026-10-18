--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local Onboarding = require(Server.Domain.Onboarding)
local QuestRules = require(Server.Domain.QuestRules)
local QuestPools = require(Server.Domain.QuestPools)
local DialogueRules = require(Server.Domain.DialogueRules)
local Equipment = require(Shared.Domain.Equipment)
local Content = require(Shared.Content)
local Dialogue = require(ServerStorage:WaitForChild("ServerData").Dialogue)
local Fixtures = require(script.Parent.Parent.Fixtures)

return function(t)
	t.test("new characters start in the church until they awaken", function()
		local character = Fixtures.character(Fixtures.profile())
		t.equal(Onboarding.spawnPoint(character), "Church")
		character.class.classId = "Swordmaster"
		t.equal(Onboarding.spawnPoint(character), "Plaza")
	end)

	t.test("the church chest gives the class weapon exactly once and puts it in hand", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps(42)
		t.falsy(Onboarding.claimStarterWeapon(profile, "main", deps), "not awakened yet")
		Fixtures.character(profile).class.classId = "Swordmaster"
		local ok, result = Onboarding.claimStarterWeapon(profile, "main", deps)
		t.truthy(ok)
		t.equal(result.itemId, "TrainingSword")
		t.truthy(result.equipped)
		local character = Fixtures.character(profile)
		t.equal(character.equipment.MainHand.itemId, "TrainingSword")
		t.equal(character.equipment.MainHand.origin.kind, "Starter")
		t.falsy(Onboarding.claimStarterWeapon(profile, "main", deps), "only once")
		t.equal(next(character.inventory.uniques), nil, "no second copy")
	end)

	t.test("equipping swaps items, and unequipping needs room", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps(42)
		Fixtures.character(profile).class.classId = "Swordmaster"
		Onboarding.claimStarterWeapon(profile, "main", deps)
		local character = Fixtures.character(profile)
		t.falsy(Equipment.unequip(character, "OffHand", Content.items), "nothing there")
		t.truthy(Equipment.unequip(character, "MainHand", Content.items))
		local uid = next(character.inventory.uniques)
		t.truthy(Equipment.equip(character, uid, Content.items, 42))
		t.equal(character.equipment.MainHand.uid, uid)
		t.falsy(Equipment.equip(character, "missing", Content.items, 42))
		character.inventory.capacity = 0
		t.falsy(Equipment.unequip(character, "MainHand", Content.items), "no room")
	end)

	t.test("the stolen belongings: found through dialogue, finished by server kill events", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps(42)
		local function context()
			return DialogueRules.buildContext(Fixtures.character(profile), Content.quests, 1, 1000)
		end
		t.equal(DialogueRules.select("WearyStranger", Dialogue, context()), "StrangerQuiet", "nothing before the awakening")
		local character = Fixtures.character(profile)
		character.story.flags = { Awakened = true }
		t.equal(DialogueRules.select("WearyStranger", Dialogue, context()), "StrangerPlea")
		local quest = Content.quests.TheStolenBelongings
		t.falsy(QuestRules.accept(character.quests, quest, 1, 1000), "needs the awakening")
		t.truthy(QuestRules.accept(character.quests, quest, 1, 1000, character.story.flags))
		t.equal(DialogueRules.select("WearyStranger", Dialogue, context()), "StrangerWaiting")
		t.falsy(context().ready.TheStolenBelongings)
		for _ = 1, 3 do
			QuestRules.applyEvent(character.quests, Content.quests, { kind = "Kill", target = "AlleyThief", amount = 1 })
		end
		t.truthy(context().ready.TheStolenBelongings)
		local ok, rewards = QuestRules.turnIn(profile, "main", quest, Content.items, deps)
		t.truthy(ok)
		t.equal(rewards.characterXp, 80)
		t.equal(Fixtures.character(profile).currencies.Gold, 20)
		t.equal(DialogueRules.select("WearyStranger", Dialogue, context()), "StrangerThanks")
	end)

	t.test("level requirements are explained instead of hidden", function()
		local character = Fixtures.character(Fixtures.profile())
		character.story.flags = { Awakened = true }
		local quest = Content.quests.HuntersRequest
		t.equal(QuestRules.availability(character.quests, quest, 1, 0, character.story.flags), "LevelTooLow")
		t.equal(QuestRules.availability(character.quests, quest, 2, 0, {}), "Locked", "story flag missing")
		t.equal(DialogueRules.select("Hunter", Dialogue, DialogueRules.buildContext(character, Content.quests, 1, 0)), "HunterTooSoon")
		t.equal(DialogueRules.select("Hunter", Dialogue, DialogueRules.buildContext(character, Content.quests, 2, 0)), "HunterRequest")
	end)

	t.test("rotating bounties match on every server for a day and change between days", function()
		local pool = Content.questPools.GuildBounties
		local today = QuestPools.offers(pool, 100, "VANTA")
		t.equal(#today, pool.count)
		t.deepEqual(QuestPools.offers(pool, 100, "VANTA"), today)
		local rotates = false
		for day = 101, 110 do
			if table.concat(QuestPools.offers(pool, day, "VANTA"), ",") ~= table.concat(today, ",") then
				rotates = true
			end
		end
		t.truthy(rotates)
		local set = QuestPools.offeredSet(Content.questPools, 100 * 86400, "VANTA")
		t.truthy(set[today[1]] and set[today[2]])
	end)

	t.test("guild contracts are for guild members and pay guild XP", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps(42)
		local character = Fixtures.character(profile)
		local contract = Content.quests.ContractOreForTheHalls
		t.equal(QuestRules.availability(character.quests, contract, 5, 0, {}), "Locked", "not in a guild")
		t.equal(QuestRules.availability(character.quests, contract, 5, 0, { InGuild = true }), "Available")
		local context = DialogueRules.buildContext(character, Content.quests, 5, 0, nil, { InGuild = true })
		t.truthy(context.available.ContractOreForTheHalls)
		t.falsy(DialogueRules.buildContext(character, Content.quests, 5, 0).available.ContractOreForTheHalls)
		QuestRules.accept(character.quests, contract, 5, 0, { InGuild = true })
		require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Domain.Inventory).addStack(character.inventory, Content.items, "CopperOre", 15, nil)
		local ok, rewards = QuestRules.turnIn(profile, "main", contract, Content.items, deps)
		t.truthy(ok)
		t.equal(rewards.guildXp, contract.rewards.guildXp)
	end)
end

