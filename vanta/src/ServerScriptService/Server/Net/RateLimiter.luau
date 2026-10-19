--!strict
-- Token bucket per key (usually a player) for remote requests. The clock is injected for testing.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: () -> number)
	return setmetatable({ capacity = capacity, refill = refillPerSecond, clock = clock, buckets = {} }, RateLimiter)
end

function RateLimiter:allow(key: any): boolean
	local now = self.clock()
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = { tokens = self.capacity, updated = now }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.capacity, bucket.tokens + math.max(0, now - bucket.updated) * self.refill)
	bucket.updated = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimiter:forget(key: any)
	self.buckets[key] = nil
end

return RateLimiter
