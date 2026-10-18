--!strict
-- The church awakening (L-08): a free roll for the first combat class from the awakening pool, weighted by
-- awakeningWeight. Legendary and development-only classes are never in the pool (L-22). Never sold (L-33).
local Awakening = {}

function Awakening.pool(classes: any): {any}
	local pool = {}
	for classId, def in pairs(classes) do
		if def.rarity ~= "Legendary" and not def.developmentOnly and (def.awakeningWeight or 0) > 0 then
			table.insert(pool, { classId = classId, weight = def.awakeningWeight })
		end
	end
	table.sort(pool, function(a, b)
		return a.classId < b.classId
	end)
	return pool
end

-- Chance of each class, for showing players the odds.
function Awakening.odds(classes: any): {[string]: number}
	local pool = Awakening.pool(classes)
	local total = 0
	for _, entry in ipairs(pool) do
		total += entry.weight
	end
	local odds = {}
	for _, entry in ipairs(pool) do
		odds[entry.classId] = entry.weight / total
	end
	return odds
end

-- random: returns a number in [0, 1).
function Awakening.roll(classes: any, random: () -> number): string?
	local pool = Awakening.pool(classes)
	local total = 0
	for _, entry in ipairs(pool) do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local pick = random() * total
	for _, entry in ipairs(pool) do
		pick -= entry.weight
		if pick < 0 then
			return entry.classId
		end
	end
	return pool[#pool].classId
end

return Awakening
