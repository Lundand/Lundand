--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ProfessionProgression = require(Shared.Domain.ProfessionProgression)
local Curve = require(Shared.Domain.Curve)
local Content = require(Shared.Content)

return function(t)
	local mining = Content.professions.Mining

	t.test("profession XP raises the level and grants unlocks", function()
		local state = ProfessionProgression.newState()
		local needed = Curve.xpToReach(mining.curve, 5)
		local gained, before, after, unlocked = ProfessionProgression.grantXp(state, mining, needed)
		t.equal(gained, needed)
		t.equal(before, 1)
		t.equal(after, 5)
		t.deepEqual(unlocked, { "MiningEfficiency1" })
		t.truthy(ProfessionProgression.hasUnlock(state, "MiningEfficiency1"))
		t.falsy(ProfessionProgression.hasUnlock(state, "OreSense1"))
	end)

	t.test("XP stops at the max level and bad amounts are ignored", function()
		local state = ProfessionProgression.newState()
		ProfessionProgression.grantXp(state, mining, 999999999)
		t.equal(ProfessionProgression.level(state, mining), Curve.maxLevel(mining.curve))
		local before = state.xp
		t.equal(ProfessionProgression.grantXp(state, mining, -1), 0)
		t.equal(ProfessionProgression.grantXp(state, mining, 0 / 0), 0)
		t.equal(state.xp, before)
	end)
end
