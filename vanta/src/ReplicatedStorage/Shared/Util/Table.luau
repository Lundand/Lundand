--!strict
-- Small table helpers shared by server and client code.

local Table = {}

function Table.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in pairs(value) do
		copy[Table.deepCopy(key)] = Table.deepCopy(item)
	end
	return copy
end

function Table.deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not Table.deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Freezes a table and everything inside it, so shared config can't be changed by accident.
function Table.deepFreeze(value: any): any
	if type(value) == "table" and not table.isfrozen(value) then
		for _, item in pairs(value) do
			Table.deepFreeze(item)
		end
		table.freeze(value)
	end
	return value
end

function Table.count(t: {[any]: any}): number
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count
end

function Table.sortedKeys(t: {[any]: any}): {any}
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Replaces the contents of target with source's keys while keeping the same table reference.
function Table.replaceContents(target: {[any]: any}, source: {[any]: any})
	table.clear(target)
	for key, value in pairs(source) do
		target[key] = value
	end
end

return Table
