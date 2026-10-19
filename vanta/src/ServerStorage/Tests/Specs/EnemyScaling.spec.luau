--!strict
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EnemyScaling = require(Shared.Domain.EnemyScaling)
local Content = require(Shared.Content)
local rules = Content.enemyProgression

return function(t)
	t.test("spawned levels stay in range and stats grow with level", function()
		local wolf = Content.enemies.ForestWolf
		for _, roll in ipairs({ 0, 0.5, 0.999 }) do
			local level = EnemyScaling.rollLevel(wolf, function(): number return roll end)
			t.truthy(level >= wolf.levelRange.min and level <= wolf.levelRange.max)
		end
		local low, high = EnemyScaling.atLevel(wolf, 3, rules), EnemyScaling.atLevel(wolf, 5, rules)
		t.truthy(high.maxHealth > low.maxHealth and high.damage >= low.damage and high.xp > low.xp)
		t.equal(low.maxHealth, wolf.maxHealth, "base level keeps base stats")
	end)

	t.test("far weaker enemies give no experience; similar ones give full; stronger give a little more", function()
		t.equal(EnemyScaling.rewardMultiplier(40, 3, rules), 0, "level 40 farming level 3 wolves")
		t.equal(EnemyScaling.rewardMultiplier(10, 10, rules), 1)
		t.equal(EnemyScaling.rewardMultiplier(10, 6, rules), 0.6)
		t.truthy(EnemyScaling.rewardMultiplier(10, 14, rules) > 1)
	end)

	t.test("every enemy has a level range within the cap, and a behaviour", function()
		for id, def in pairs(Content.enemies) do
			t.truthy(def.levelRange.min <= def.levelRange.max and def.levelRange.max <= Content.progression.characterCurve.maxLevel, id)
			t.truthy(Content.combat.enemyAttacks[id] ~= nil or Content.combat.archetypeAttacks[def.archetype] ~= nil, id .. " has an attack")
		end
	end)
end
