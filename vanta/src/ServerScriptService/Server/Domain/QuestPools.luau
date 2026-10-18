--!strict
-- Rotating optional tasks (L-44). Each pool offers some of its repeatable quests per day, picked by a
-- deterministic hash of the day, so every server shows the same offers without coordination.
local QuestPools = {}

local DAY = 86400

local function hash(text: string): number
	local value = 7
	for index = 1, #text do
		value = (value * 31 + string.byte(text, index)) % 2147483647
	end
	return value
end

function QuestPools.dayIndex(now: number): number
	return math.floor(now / DAY)
end

function QuestPools.offers(pool: any, day: number, seed: string): {string}
	local ranked = {}
	for _, questId in ipairs(pool.quests) do
		table.insert(ranked, { id = questId, score = hash(seed .. ":" .. pool.id .. ":" .. tostring(day) .. ":" .. questId) })
	end
	table.sort(ranked, function(a, b)
		if a.score == b.score then
			return a.id < b.id
		end
		return a.score < b.score
	end)
	local offers = {}
	for index = 1, math.min(pool.count, #ranked) do
		table.insert(offers, ranked[index].id)
	end
	table.sort(offers)
	return offers
end

-- Every quest offered today across all pools, as a set.
function QuestPools.offeredSet(pools: any, now: number, seed: string): {[string]: boolean}
	local set = {}
	for _, pool in pairs(pools) do
		for _, questId in ipairs(QuestPools.offers(pool, QuestPools.dayIndex(now), seed)) do
			set[questId] = true
		end
	end
	return set
end

return QuestPools
