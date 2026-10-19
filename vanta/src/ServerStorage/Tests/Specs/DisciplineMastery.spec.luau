--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DisciplineMastery = require(Shared.Domain.DisciplineMastery)
local Content = require(Shared.Content)

return function(t)
	local swordArts = Content.disciplines.SwordArts
	local grant = Content.classes.Swordmaster.disciplines.SwordArts
	local rules = {
		repetition = { windowSeconds = 10, freeUses = 2, decayPerUse = 0.5, minimumMultiplier = 0.1 },
		repetitionSources = { Hit = true },
		xpPerMinuteCap = 1000,
		minTargetLevelOffset = -5,
	}
	local enemy = { hostile = true, level = 5 }

	local function fresh()
		local state = DisciplineMastery.newState()
		DisciplineMastery.refreshTechniques(state, swordArts, grant)
		return state, DisciplineMastery.newSession()
	end

	local function hit(state, session, now: number, step: number?)
		return DisciplineMastery.applyEvent(state, swordArts, grant, {
			kind = "Hit",
			techniqueId = "SwordCombo",
			step = step,
			target = enemy,
			now = now,
			characterLevel = 5,
		}, session, rules)
	end

	t.test("rank 1 unlocks the combo and parry", function()
		local state = DisciplineMastery.newState()
		t.deepEqual(DisciplineMastery.refreshTechniques(state, swordArts, grant), { "SwordCombo", "SwordParry" })
	end)

	t.test("ranks unlock techniques, and riposte also needs Iron Wall", function()
		local state = fresh()
		local _, unlocked = DisciplineMastery.grantXp(state, swordArts, grant, 900)
		t.deepEqual(unlocked, { "HeavyStrike" })
		t.equal(DisciplineMastery.rank(state, swordArts, grant), 3)
		t.equal(state.techniques.Riposte, nil)
		t.truthy(DisciplineMastery.completeMilestone(state, swordArts, grant, "IronWall"))
		t.truthy(state.techniques.Riposte)
		t.falsy(DisciplineMastery.completeMilestone(state, swordArts, grant, "IronWall"), "only once")
	end)

	t.test("XP stops at the class's rank ceiling", function()
		local state = DisciplineMastery.newState()
		local lowGrant = { maxRank = 2 }
		DisciplineMastery.grantXp(state, swordArts, lowGrant, 99999)
		t.equal(state.xp, swordArts.curve.thresholds[2])
		t.equal(DisciplineMastery.rank(state, swordArts, lowGrant), 2)
	end)

	t.test("events against invalid targets give nothing", function()
		local state, session = fresh()
		local cases = {
			{ target = { hostile = true, level = 5, dummy = true }, why = "dummy" },
			{ target = { hostile = false, level = 5 }, why = "not hostile" },
			{ target = { hostile = true, level = 1 }, why = "too low" },
		}
		for _, case in ipairs(cases) do
			local result = DisciplineMastery.applyEvent(state, swordArts, grant, {
				kind = "Hit",
				techniqueId = "SwordCombo",
				target = case.target,
				now = 1,
				characterLevel = 10,
			}, session, rules)
			t.falsy(result.accepted, case.why)
		end
		local locked = DisciplineMastery.applyEvent(state, swordArts, grant, {
			kind = "Hit",
			techniqueId = "CrescentSweep",
			target = enemy,
			now = 1,
			characterLevel = 5,
		}, session, rules)
		t.equal(locked.reason, "technique not unlocked")
		t.falsy(DisciplineMastery.applyEvent(state, swordArts, grant, { kind = "Dance", now = 1 }, session, rules).accepted)
		t.equal(state.xp, 0)
	end)

	t.test("repeating one technique step decays, other steps and time restore it", function()
		local state, session = fresh()
		t.equal(hit(state, session, 0).xpGained, 4)
		t.equal(hit(state, session, 1).xpGained, 4)
		t.equal(hit(state, session, 2).xpGained, 2, "third use in the window")
		t.equal(hit(state, session, 3).xpGained, 0, "floored at the minimum multiplier")
		t.equal(hit(state, session, 3, 2).xpGained, 4, "a different combo step")
		t.equal(hit(state, session, 30).xpGained, 4, "after the window")
	end)

	t.test("the per-minute cap limits automated XP", function()
		local state, session = fresh()
		local capped = { repetition = rules.repetition, repetitionSources = {}, xpPerMinuteCap = 10, minTargetLevelOffset = -5 }
		local total = 0
		for second = 1, 10 do
			local result = DisciplineMastery.applyEvent(state, swordArts, grant, {
				kind = "Hit",
				target = enemy,
				now = second,
				characterLevel = 5,
			}, session, capped)
			total += result.xpGained
		end
		t.equal(total, 10)
		t.equal(DisciplineMastery.applyEvent(state, swordArts, grant, {
			kind = "Hit",
			target = enemy,
			now = 70,
			characterLevel = 5,
		}, session, capped).xpGained, 4, "new minute")
	end)

	t.test("ten perfect parries complete Iron Wall once and pay its reward", function()
		local state, session = fresh()
		local completed = 0
		for second = 1, 11 do
			local result = DisciplineMastery.applyEvent(state, swordArts, grant, {
				kind = "PerfectParry",
				target = enemy,
				now = second,
				characterLevel = 5,
			}, session, rules)
			completed += #result.milestonesCompleted
		end
		t.equal(completed, 1)
		t.truthy(state.milestones.IronWall.completed)
		t.equal(state.xp, 11 * swordArts.xpSources.PerfectParry + swordArts.milestones.IronWall.rewardXp)
	end)

	t.test("Elite Duel needs an elite kill", function()
		local state, session = fresh()
		local function kill(elite: boolean)
			return DisciplineMastery.applyEvent(state, swordArts, grant, {
				kind = "Kill",
				target = { hostile = true, level = 5, elite = elite },
				now = 1,
				characterLevel = 5,
			}, session, rules)
		end
		t.deepEqual(kill(false).milestonesCompleted, {})
		t.deepEqual(kill(true).milestonesCompleted, { "EliteDuel" })
	end)

	t.test("drills pay fully once, then a limited amount per day", function()
		local state, session = fresh()
		local function drill(now: number)
			return DisciplineMastery.applyEvent(state, swordArts, grant, { kind = "DrillCompleted", drillId = "SwordDrill1", now = now }, session, rules)
		end
		local first = drill(100)
		t.equal(first.xpGained, 200)
		t.deepEqual(first.milestonesCompleted, { "TrainersDrill" })
		t.equal(drill(101).xpGained, 40)
		t.equal(drill(102).xpGained, 40)
		t.equal(drill(103).xpGained, 40)
		t.equal(drill(104).xpGained, 0, "daily limit")
		t.equal(drill(100 + 86400).xpGained, 40, "next day")
		t.equal(DisciplineMastery.applyEvent(state, swordArts, grant, { kind = "DrillCompleted", drillId = "Nope", now = 1 }, session, rules).reason, "unknown drill")
	end)
end
