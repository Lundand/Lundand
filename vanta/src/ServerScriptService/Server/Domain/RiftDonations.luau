--!strict
-- Community Rift donations (L-36, L-47). The shared total is split into shard records so many servers can
-- add at once; each shard remembers which purchases it counted, so a retried delivery counts once. The
-- event record opens exactly once: only the update that still sees "Collecting" with the target reached
-- changes it, and UpdateAsync applies updates to one key one at a time.
local RiftDonations = {}

local function hash(text: string): number
	local value = 7
	for index = 1, #text do
		value = (value * 31 + string.byte(text, index)) % 2147483647
	end
	return value
end

function RiftDonations.shardIndex(purchaseId: string, shardCount: number): number
	return hash(purchaseId) % shardCount + 1
end

function RiftDonations.newShard()
	return { total = 0, counted = {} }
end

-- Adds one purchase to a shard. False when it was already counted.
function RiftDonations.addToShard(shard: any, purchaseId: string, robux: number): boolean
	if shard.counted[purchaseId] ~= nil then
		return false
	end
	shard.counted[purchaseId] = robux
	shard.total += robux
	return true
end

function RiftDonations.total(shards: {any}): number
	local total = 0
	for _, shard in pairs(shards) do
		total += shard.total
	end
	return total
end

function RiftDonations.progress(total: number, target: number): any
	return {
		total = total,
		target = target,
		remaining = math.max(0, target - total),
		fraction = math.min(1, total / target),
	}
end

function RiftDonations.newEvent(eventId: string)
	return { id = eventId, state = "Collecting" }
end

-- Opens the Rift once. True only for the update that opened it.
function RiftDonations.tryOpen(event: any, total: number, target: number, now: number, openHours: number): boolean
	if event.state ~= "Collecting" or total < target then
		return false
	end
	event.state = "Open"
	event.openedAt = now
	event.closesAt = now + openHours * 3600
	return true
end

-- "Collecting", "Open" or "Closed".
function RiftDonations.status(event: any, now: number): string
	if event.state == "Open" and now >= event.closesAt then
		return "Closed"
	end
	return event.state
end

return RiftDonations
