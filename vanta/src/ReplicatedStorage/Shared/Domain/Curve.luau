--!strict
-- XP curves (T-09). Levels and ranks are always derived from stored XP, never stored themselves.
--   Power: XP from level L to L + 1 is floor(base * L ^ exponent), up to maxLevel. Optional slowFrom / slowMultiplier:
--   from level slowFrom on, each level costs slowMultiplier times as much (a late band that takes longer).
local function stepXp(spec: any, level: number): number
	local cost = spec.base * level ^ spec.exponent
	if spec.slowFrom ~= nil and level >= spec.slowFrom then
		cost *= spec.slowMultiplier or 1
	end
	return math.floor(cost)
end
--   Table: thresholds[n] is the total XP needed to reach level n (thresholds[1] must be 0).

local Curve = {}

export type Spec = { kind: string, base: number?, exponent: number?, maxLevel: number?, thresholds: {number}? }

function Curve.maxLevel(spec: any): number
	if spec.kind == "Table" then
		return #spec.thresholds
	end
	return spec.maxLevel
end

-- Total XP needed to reach `level` starting from level 1.
function Curve.xpToReach(spec: any, level: number): number
	local target = math.clamp(math.floor(level), 1, Curve.maxLevel(spec))
	if spec.kind == "Table" then
		return spec.thresholds[target]
	end
	local total = 0
	for current = 1, target - 1 do
		total += stepXp(spec, current)
	end
	return total
end

function Curve.levelForXp(spec: any, xp: number): number
	local maxLevel = Curve.maxLevel(spec)
	local level = 1
	if spec.kind == "Table" then
		for index = 2, maxLevel do
			if xp >= spec.thresholds[index] then
				level = index
			else
				break
			end
		end
		return level
	end
	local total = 0
	while level < maxLevel do
		local nextTotal = total + stepXp(spec, level)
		if xp < nextTotal then
			break
		end
		level += 1
		total = nextTotal
	end
	return level
end

-- Returns level, XP into the current level, and XP the current level needs (nil at max level).
function Curve.progress(spec: any, xp: number): (number, number, number?)
	local level = Curve.levelForXp(spec, xp)
	local floorXp = Curve.xpToReach(spec, level)
	if level >= Curve.maxLevel(spec) then
		return level, xp - floorXp, nil
	end
	return level, xp - floorXp, Curve.xpToReach(spec, level + 1) - floorXp
end

function Curve.validate(spec: any): (boolean, string?)
	if type(spec) ~= "table" then
		return false, "must be a table"
	end
	if spec.kind == "Table" then
		local thresholds = spec.thresholds
		if type(thresholds) ~= "table" or #thresholds < 1 then
			return false, "needs thresholds"
		end
		if thresholds[1] ~= 0 then
			return false, "first threshold must be 0"
		end
		for index = 2, #thresholds do
			if type(thresholds[index]) ~= "number" or thresholds[index] <= thresholds[index - 1] then
				return false, "thresholds must increase"
			end
		end
		return true, nil
	elseif spec.kind == "Power" then
		if type(spec.base) ~= "number" or spec.base < 1 then
			return false, "base must be at least 1"
		end
		if type(spec.exponent) ~= "number" or spec.exponent < 0 then
			return false, "exponent must not be negative"
		end
		if type(spec.maxLevel) ~= "number" or spec.maxLevel < 1 or math.floor(spec.maxLevel) ~= spec.maxLevel then
			return false, "maxLevel must be a positive whole number"
		end
		return true, nil
	end
	return false, "unknown kind"
end

return Curve
