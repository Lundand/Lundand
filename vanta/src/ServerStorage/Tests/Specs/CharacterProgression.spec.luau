--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local Content = require(Shared.Content)

return function(t)
	local stats = Content.stats
	local progression = {
		characterCurve = { kind = "Table", thresholds = { 0, 100, 300, 600, 1000, 1500 } },
		maxXpGrant = 100000,
	}

	t.test("a new character is level 1 with only starting points", function()
		local state = CharacterProgression.newState()
		t.equal(CharacterProgression.level(state, progression), 1)
		t.equal(CharacterProgression.availablePoints(state, stats, progression), stats.startingPoints)
	end)

	t.test("levelling up grants stat points", function()
		local state = CharacterProgression.newState()
		local ok, result = CharacterProgression.grantXp(state, 300, stats, progression)
		t.truthy(ok)
		t.equal(result.levelBefore, 1)
		t.equal(result.levelAfter, 3)
		t.equal(result.pointsGained, stats.pointsPerLevel * 2)
		t.equal(CharacterProgression.availablePoints(state, stats, progression), stats.startingPoints + stats.pointsPerLevel * 2)
	end)

	t.test("invalid XP amounts are rejected and change nothing", function()
		local state = CharacterProgression.newState()
		for _, amount in ipairs({ 0, -5, 0 / 0, math.huge, 100001 }) do
			t.falsy(CharacterProgression.grantXp(state, amount, stats, progression), tostring(amount))
		end
		t.falsy(CharacterProgression.grantXp(state, 10, stats, progression, 0), "zero multiplier")
		t.equal(state.xp, 0)
	end)

	t.test("XP stops at the max level", function()
		local state = CharacterProgression.newState()
		CharacterProgression.grantXp(state, 99999, stats, progression)
		t.equal(state.xp, 1500)
		t.equal(CharacterProgression.level(state, progression), 6)
		local ok, result = CharacterProgression.grantXp(state, 50, stats, progression)
		t.truthy(ok)
		t.equal(result.gained, 0)
	end)

	t.test("allocation applies all or nothing", function()
		local state = CharacterProgression.newState()
		CharacterProgression.grantXp(state, 300, stats, progression)
		local available = CharacterProgression.availablePoints(state, stats, progression)
		t.truthy(CharacterProgression.allocate(state, { Strength = 2 }, stats, progression))
		t.equal(state.allocated.Strength, 2)
		t.falsy(CharacterProgression.allocate(state, { Vitality = 1, Luck = 1 }, stats, progression), "unknown stat")
		t.falsy(CharacterProgression.allocate(state, { Vitality = 1.5 }, stats, progression), "fraction")
		t.falsy(CharacterProgression.allocate(state, { Vitality = 0 }, stats, progression), "zero")
		t.falsy(CharacterProgression.allocate(state, { Vitality = available }, stats, progression), "more than available")
		t.falsy(CharacterProgression.allocate(state, {}, stats, progression), "empty")
		t.falsy(CharacterProgression.allocate(state, "Strength", stats, progression), "not a table")
		t.equal(state.allocated.Vitality, nil)
		t.equal(CharacterProgression.availablePoints(state, stats, progression), available - 2)
	end)

	t.test("resetting allocation refunds every point", function()
		local state = CharacterProgression.newState()
		CharacterProgression.grantXp(state, 300, stats, progression)
		CharacterProgression.allocate(state, { Strength = 1, Agility = 2 }, stats, progression)
		t.equal(CharacterProgression.resetAllocation(state), 3)
		t.deepEqual(state.allocated, {})
	end)

	t.test("over-allocation after a config change is detected", function()
		local state = CharacterProgression.newState()
		state.allocated = { Strength = 5 }
		t.truthy(CharacterProgression.isOverAllocated(state, stats, progression))
	end)

	t.test("the catch-up bonus multiplies XP and ends at its level", function()
		local state = CharacterProgression.newState()
		state.xpBonus = { kind = "LegendaryCatchUp", startMultiplier = 2, endMultiplier = 1, untilLevel = 4 }
		local ok, first = CharacterProgression.grantXp(state, 50, stats, progression)
		t.truthy(ok)
		t.equal(first.gained, 100, "double XP at level 1")
		t.near(CharacterProgression.bonusMultiplier(state, 2), 2 - 1 / 3, 0.0001, "falls linearly")
		local _, second = CharacterProgression.grantXp(state, 500, stats, progression)
		t.truthy(second.bonusEnded)
		t.equal(state.xpBonus, nil)
	end)

	t.test("an extra multiplier such as an XP boost is applied", function()
		local state = CharacterProgression.newState()
		local _, result = CharacterProgression.grantXp(state, 100, stats, progression, 1.5)
		t.equal(result.gained, 150)
	end)

	t.test("derived stats add each allocated point's effect", function()
		local state = CharacterProgression.newState()
		state.allocated = { Vitality = 3 }
		local derived = CharacterProgression.derivedStats(state, stats)
		t.equal(derived.maxHealth, stats.baseValues.maxHealth + 3 * stats.effectsPerPoint.Vitality.maxHealth)
		t.equal(derived.physicalDamage, stats.baseValues.physicalDamage)
	end)

	t.test("a soft cap reduces points above its threshold", function()
		t.equal(CharacterProgression.effectivePoints(60, { threshold = 50, efficiencyAbove = 0.5 }), 55)
		t.equal(CharacterProgression.effectivePoints(40, { threshold = 50, efficiencyAbove = 0.5 }), 40)
		t.equal(CharacterProgression.effectivePoints(60, nil), 60)
	end)

	t.test("state validation catches broken saves", function()
		t.truthy(CharacterProgression.validateState(CharacterProgression.newState(), stats))
		t.falsy(CharacterProgression.validateState({ xp = "10", allocated = {}, bonusPoints = 0 }, stats))
	end)

	t.test("the profile can preview an upgrade without changing anything", function()
		local state = CharacterProgression.newState()
		CharacterProgression.grantXp(state, 300, stats, progression)
		local ok, preview = CharacterProgression.previewAllocation(state, { Vitality = 2 }, stats, progression)
		t.truthy(ok)
		t.equal(preview.after.maxHealth - preview.before.maxHealth, 2 * stats.effectsPerPoint.Vitality.maxHealth)
		t.equal(preview.pointsBefore - preview.pointsAfter, 2)
		t.deepEqual(state.allocated, {}, "nothing changed")
		t.falsy(CharacterProgression.previewAllocation(state, { Vitality = 99 }, stats, progression))
	end)

	t.test("points on a retired stat are refunded instead of blocking the save", function()
		local state = { xp = 300, allocated = { Strength = 2, Luck = 3 }, bonusPoints = 0 }
		t.truthy(CharacterProgression.validateState(state, stats))
		t.equal(CharacterProgression.dropUnknownStats(state, stats), 3)
		t.deepEqual(state.allocated, { Strength = 2 })
	end)

	t.test("raising the level cap keeps level and XP and grants nothing", function()
		local capped = { characterCurve = { kind = "Power", base = 100, exponent = 1.5, maxLevel = 10 }, maxXpGrant = 100000000 }
		local raised = { characterCurve = { kind = "Power", base = 100, exponent = 1.5, maxLevel = 20 }, maxXpGrant = 100000000 }
		local state = CharacterProgression.newState()
		CharacterProgression.grantXp(state, 99999999, stats, capped)
		local xpAtCap = state.xp
		local pointsAtCap = CharacterProgression.availablePoints(state, stats, capped)
		t.equal(CharacterProgression.level(state, capped), 10)
		local _, atCap = CharacterProgression.grantXp(state, 5000, stats, capped)
		t.equal(atCap.gained, 0, "XP at the cap is not banked")
		t.equal(CharacterProgression.level(state, raised), 10, "same level after the cap rises")
		t.equal(state.xp, xpAtCap)
		t.equal(CharacterProgression.availablePoints(state, stats, raised), pointsAtCap, "no free stat points")
		local _, after = CharacterProgression.grantXp(state, 100, stats, raised)
		t.truthy(after.gained > 0, "XP is earned again under the new cap")
	end)
end
