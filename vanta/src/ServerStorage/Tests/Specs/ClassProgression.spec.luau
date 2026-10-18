--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ClassProgression = require(Shared.Domain.ClassProgression)
local Content = require(Shared.Content)

return function(t)
	local classes = Content.classes

	t.test("the first class can be assigned once", function()
		local state = ClassProgression.newState()
		t.truthy(ClassProgression.assignInitialClass(state, "Swordmaster", classes, "Awakening", 100))
		t.equal(state.classId, "Swordmaster")
		t.equal(state.source, "Awakening")
		t.falsy(ClassProgression.assignInitialClass(state, "Swordmaster", classes, "Awakening", 101), "second time")
	end)

	t.test("legendary and unknown classes cannot be assigned directly", function()
		t.falsy(ClassProgression.assignInitialClass(ClassProgression.newState(), "PlaceholderLegendary", classes, "Awakening", 1))
		t.falsy(ClassProgression.assignInitialClass(ClassProgression.newState(), "NoSuchClass", classes, "Awakening", 1))
		t.falsy(ClassProgression.assignInitialClass(ClassProgression.newState(), 42, classes, "Awakening", 1))
	end)

	t.test("class unlocks arrive at their level, once", function()
		local state = ClassProgression.newState()
		ClassProgression.assignInitialClass(state, "Swordmaster", classes, "Awakening", 1)
		t.deepEqual(ClassProgression.refreshUnlocks(state, classes, { characterLevel = 4 }), {})
		t.deepEqual(ClassProgression.refreshUnlocks(state, classes, { characterLevel = 5 }), { "BattleFocus" })
		t.deepEqual(ClassProgression.refreshUnlocks(state, classes, { characterLevel = 9 }), {})
		t.truthy(state.unlocks.BattleFocus)
	end)

	t.test("quest requirements are checked", function()
		t.falsy(ClassProgression.meetsRequirements({ quest = "Intro" }, { completedQuests = {} }))
		t.truthy(ClassProgression.meetsRequirements({ quest = "Intro" }, { completedQuests = { Intro = true } }))
	end)

	t.test("the Swordmaster grants Sword Arts with its ceiling", function()
		local state = ClassProgression.newState()
		t.deepEqual(ClassProgression.disciplineGrants(state, classes), {})
		ClassProgression.assignInitialClass(state, "Swordmaster", classes, "Awakening", 1)
		t.equal(ClassProgression.disciplineGrants(state, classes).SwordArts.maxRank, 5)
	end)
end
