--!strict
-- Enemy level and rewards (owner's world specification): a spawned enemy's level within its range and its stats at
-- that level; the reward multiplier from the level difference between player and enemy.
local EnemyScaling = {}

function EnemyScaling.rollLevel(def: any, random: () -> number): number
	local range = def.levelRange
	if range == nil then
		return def.level
	end
	return math.clamp(range.min + math.floor(random() * (range.max - range.min + 1)), range.min, range.max)
end

-- A copy of the definition with the stats for `level`.
function EnemyScaling.atLevel(def: any, level: number, rules: any): any
	local steps = level - def.level
	local scaled = table.clone(def)
	scaled.level = level
	scaled.maxHealth = math.floor(def.maxHealth * rules.growthPerLevel.health ^ steps + 0.5)
	scaled.damage = math.max(1, math.floor(def.damage * rules.growthPerLevel.damage ^ steps + 0.5))
	scaled.xp = math.floor(def.xp * rules.growthPerLevel.xp ^ steps + 0.5)
	return scaled
end

function EnemyScaling.rewardMultiplier(playerLevel: number, enemyLevel: number, rules: any): number
	local difference = enemyLevel - playerLevel
	for _, step in ipairs(rules.levelDifference) do
		if difference <= step.atMost then
			return step.multiplier
		end
	end
	return rules.aboveMultiplier
end

return EnemyScaling
