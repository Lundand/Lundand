--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")
local DialogueRules = require(Server.Domain.DialogueRules)
local QuestRules = require(Server.Domain.QuestRules)
local Awakening = require(Server.Domain.Awakening)
local Dialogue = require(ServerStorage:WaitForChild("ServerData").Dialogue)
local Content = require(Shared.Content)
local Fixtures = require(script.Parent.Parent.Fixtures)

local function contextFor(character: any)
	return DialogueRules.buildContext(character, Content.quests, 1, 1000)
end

local function choiceTexts(view: any): {string}
	local texts = {}
	for _, choice in ipairs(view.choices) do
		table.insert(texts, choice.text)
	end
	return texts
end

return function(t)
	t.test("the shipped conversations are valid and every NPC has a fallback", function()
		t.deepEqual(DialogueRules.validate(Dialogue, Content), {})
	end)

	t.test("NPCs pick the highest-priority conversation whose conditions are met", function()
		local character = Fixtures.character(Fixtures.profile())
		t.equal(DialogueRules.select("TheKing", Dialogue, contextFor(character)), "KingGreeting")
		t.equal(DialogueRules.select("ChurchPriest", Dialogue, contextFor(character)), "PriestAwakening")
		character.class.classId = "Swordmaster"
		t.equal(DialogueRules.select("ChurchPriest", Dialogue, contextFor(character)), "PriestBlessing")
		character.quests.AdventurerRegistration = { state = "Completed", progress = {}, completions = 1 }
		t.equal(DialogueRules.select("TheKing", Dialogue, contextFor(character)), "KingFirstAudience")
	end)

	t.test("registration works in one conversation, and choices follow the quest state", function()
		local profile, deps = Fixtures.profile(), Fixtures.deps()
		local character = Fixtures.character(profile)
		local dialogue = Dialogue.RegistrarWelcome
		local offer = DialogueRules.view("RegistrarWelcome", dialogue, "offer", contextFor(character), false)
		t.deepEqual(choiceTexts(offer), { "Sign me up.", "Not today." })
		local ok, result = DialogueRules.choose(dialogue, "offer", 1, contextFor(character))
		t.truthy(ok)
		t.equal(result.actions[1].kind, "AcceptQuest")
		-- what DialogueService does with that action: accept, and count the conversation as talking
		QuestRules.accept(character.quests, Content.quests.AdventurerRegistration, 1, 1000)
		QuestRules.applyEvent(character.quests, Content.quests, { kind = "Talk", target = "GuildRegistrar" })
		local sign = DialogueRules.view("RegistrarWelcome", dialogue, result.next, contextFor(character), false)
		t.deepEqual(choiceTexts(sign), { "Here's my signature." })
		local _, signed = DialogueRules.choose(dialogue, "sign", 1, contextFor(character))
		t.equal(signed.actions[1].kind, "TurnInQuest")
		t.truthy(QuestRules.turnIn(profile, "main", Content.quests.AdventurerRegistration, Content.items, deps))
		t.equal(DialogueRules.select("GuildRegistrar", Dialogue, contextFor(character)), "RegistrarBounties")
	end)

	t.test("hidden or invented choices are refused", function()
		local character = Fixtures.character(Fixtures.profile())
		t.falsy(DialogueRules.choose(Dialogue.RegistrarWelcome, "offer", 2, contextFor(character)), "turn-in not ready")
		t.falsy(DialogueRules.choose(Dialogue.RegistrarWelcome, "offer", 9, contextFor(character)), "no such option")
		t.falsy(DialogueRules.choose(Dialogue.RegistrarWelcome, "start", 1, contextFor(character)), "node has no options")
	end)

	t.test("skipping jumps over text to the next decision, never past it", function()
		local character = Fixtures.character(Fixtures.profile())
		character.quests.AdventurerRegistration = { state = "Completed", progress = {}, completions = 1 }
		local context = contextFor(character)
		t.equal(DialogueRules.skip(Dialogue.KingFirstAudience, "start", context), "ask")
		t.equal(DialogueRules.skip(Dialogue.KingFirstAudience, "ask", context), "ask")
		t.equal(DialogueRules.skip(Dialogue.ScholarRumours, "start", context), nil, "no decision: skip ends it")
		t.equal(DialogueRules.advance(Dialogue.KingFirstAudience, "start"), "ask")
	end)

	t.test("starting a conversation marks it seen and keeps its journal entry", function()
		local story = {}
		local seen = DialogueRules.begin(story, "ScholarLegend", Dialogue.ScholarLegend, 50)
		t.falsy(seen)
		t.equal(story.journal.ScholarLegend, 50)
		local seenAgain = DialogueRules.begin(story, "ScholarLegend", Dialogue.ScholarLegend, 60)
		t.truthy(seenAgain)
		t.equal(story.journal.ScholarLegend, 50, "first time kept")
	end)

	t.test("conversation checks catch broken links and unknown references", function()
		local broken = {
			Bad = {
				npc = "TheKing",
				requires = { questDone = "Nope" },
				nodes = {
					start = { lines = { "Hello" }, next = "missing", choices = { { text = "Go", actions = { { kind = "Teleport" } } } } },
					orphan = { lines = { "Unreachable" } },
				},
			},
		}
		local problems = DialogueRules.validate(broken, Content)
		local joined = table.concat(problems, "; ")
		t.truthy(string.find(joined, "unknown condition questDone", 1, true), joined)
		t.truthy(string.find(joined, "links to missing node missing", 1, true))
		t.truthy(string.find(joined, "unknown action Teleport", 1, true))
		t.truthy(string.find(joined, "node orphan can never be reached", 1, true))
		t.truthy(string.find(joined, "OldScholar: NPC needs one conversation without conditions", 1, true))
	end)

	t.test("the awakening rolls from the pool by weight and never gives a legendary class", function()
		local classes = {
			Common = { rarity = "Common", awakeningWeight = 90 },
			Rare = { rarity = "Rare", awakeningWeight = 10 },
			Legend = { rarity = "Legendary" },
			Test = { rarity = "Common", awakeningWeight = 50, developmentOnly = true },
		}
		t.equal(Awakening.roll(classes, function()
			return 0
		end), "Common")
		t.equal(Awakening.roll(classes, function()
			return 0.95
		end), "Rare")
		t.near(Awakening.odds(classes).Rare, 0.1, 0.0001)
		t.equal(Awakening.odds(classes).Legend, nil)
		local rolled = Awakening.roll(Content.classes, function()
			return 0.5
		end)
		t.truthy(rolled ~= nil and (Content.classes[rolled].awakeningWeight or 0) > 0, "rolls an awakenable class")
	end)
end
