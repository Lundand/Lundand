--!strict
-- Validation helpers for anything that crosses a trust boundary (remotes, saves, config).

local Check = {}

function Check.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Check.isInteger(value: any): boolean
	return Check.isFiniteNumber(value) and math.floor(value) == value
end

function Check.isPositiveInteger(value: any): boolean
	return Check.isInteger(value) and value > 0
end

function Check.isNonNegativeInteger(value: any): boolean
	return Check.isInteger(value) and value >= 0
end

-- Content IDs: a letter followed by letters, digits or underscores.
function Check.isIdentifier(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local limit = maxLength or 64
	if #value == 0 or #value > limit then
		return false
	end
	return string.match(value, "^%a[%w_]*$") ~= nil
end

-- Operation IDs, item UIDs and request IDs: letters, digits and _ : - .
function Check.isToken(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local limit = maxLength or 100
	if #value == 0 or #value > limit then
		return false
	end
	return string.match(value, "^[%w_:%-%.]+$") ~= nil
end

return Check
