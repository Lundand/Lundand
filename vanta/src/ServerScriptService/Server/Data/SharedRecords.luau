--!strict
-- Shared records (T-23): data that belongs to no single player, such as buildings, guilds, shops and Rift
-- totals, kept in DataStores so every server sees the same thing. Each change is a transform run inside
-- UpdateAsync, which applies changes to one key one at a time, so two servers never overwrite each other.
-- Failed calls are retried with a growing delay. Reads are cached briefly and dropped when another server
-- announces a change. The store is anything with UpdateAsync and GetAsync, so tests can use a stand-in.
local SharedRecords = {}
SharedRecords.__index = SharedRecords

-- options: { now = () -> number, wait = (seconds) -> (), announce = (key) -> ()?, ttl = seconds?, retries = n? }
function SharedRecords.new(store: any, options: any)
	return setmetatable({
		store = store,
		cache = {},
		ttl = options.ttl or 30,
		retries = options.retries or 4,
		now = options.now,
		wait = options.wait,
		announce = options.announce,
	}, SharedRecords)
end

local function attempt(self: any, call: () -> any): (boolean, any)
	local delay = 0.5
	local lastError = nil
	for index = 1, self.retries do
		local ok, result = pcall(call)
		if ok then
			return true, result
		end
		lastError = result
		if index < self.retries then
			self.wait(delay)
			delay *= 2
		end
	end
	return false, lastError
end

-- transform(current) returns the new record and an answer for the caller; returning no record leaves the
-- stored record untouched. Domain rules run inside it, so a retried call sees the latest record.
function SharedRecords.update(self: any, key: string, transform: (any) -> (any, any)): (boolean, any)
	local answer = nil
	local ok, result = attempt(self, function()
		return self.store:UpdateAsync(key, function(current: any)
			local record, response = transform(current)
			answer = response
			return record
		end)
	end)
	if not ok then
		return false, result
	end
	if result ~= nil then
		self.cache[key] = { value = result, at = self.now() }
		if self.announce ~= nil then
			self.announce(key)
		end
	end
	return true, answer
end

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

-- maxAge 0 always fetches from the store. Cached records are handed out as copies, so callers can't change them.
function SharedRecords.read(self: any, key: string, maxAge: number?): (boolean, any)
	local cached = self.cache[key]
	if cached ~= nil and maxAge ~= 0 and self.now() - cached.at <= (maxAge or self.ttl) then
		return true, copy(cached.value)
	end
	local ok, value = attempt(self, function()
		return self.store:GetAsync(key)
	end)
	if ok then
		self.cache[key] = { value = value, at = self.now() }
	end
	return ok, value
end

-- Called when another server announces a change to this key.
function SharedRecords.invalidate(self: any, key: string)
	self.cache[key] = nil
end

return SharedRecords
