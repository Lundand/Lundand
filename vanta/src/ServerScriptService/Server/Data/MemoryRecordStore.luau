--!strict
-- An in-memory stand-in for a DataStore, used only in Studio when DataStores can't be reached (an unpublished place,
-- or API access turned off), so buildings, guilds, shops and the Rift can be tried locally. Nothing is kept after the
-- session, and other servers can't see it.
local MemoryRecordStore = {}
MemoryRecordStore.__index = MemoryRecordStore

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in pairs(value) do
		result[key] = copy(inner)
	end
	return result
end

function MemoryRecordStore.new()
	return setmetatable({ data = {} }, MemoryRecordStore)
end

function MemoryRecordStore.UpdateAsync(self: any, key: string, transform: (any) -> any): any
	local updated = transform(copy(self.data[key]))
	if updated == nil then
		return nil
	end
	self.data[key] = copy(updated)
	return copy(updated)
end

function MemoryRecordStore.GetAsync(self: any, key: string): any
	return copy(self.data[key])
end

return MemoryRecordStore
