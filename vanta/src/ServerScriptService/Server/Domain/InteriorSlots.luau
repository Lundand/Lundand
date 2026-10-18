--!strict
-- Where instanced interiors go (houses, inn rooms). Each interior that someone is in gets a slot in a grid far above
-- the map; a house shares one slot among everyone inside it, and an inn room is one slot per renter. An interior
-- nobody has been in for a while gives its slot back, and when every slot is taken the one left empty longest is
-- handed on. Pure bookkeeping, so it can be tested offline.
local InteriorSlots = {}

export type State = {
	maxSlots: number,
	free: {number},
	nextSlot: number,
	byKey: {[string]: { slot: number, lastUsed: number }},
	bySlot: {[number]: string},
}

function InteriorSlots.new(maxSlots: number): State
	return { maxSlots = maxSlots, free = {}, nextSlot = 0, byKey = {}, bySlot = {} }
end

-- The slot for an interior, and whether it was just made. nil when every slot is taken.
function InteriorSlots.acquire(state: State, key: string, now: number): (number?, boolean)
	local existing = state.byKey[key]
	if existing ~= nil then
		existing.lastUsed = now
		return existing.slot, false
	end
	local slot
	if #state.free > 0 then
		table.sort(state.free)
		slot = table.remove(state.free, 1)
	elseif state.nextSlot < state.maxSlots then
		slot = state.nextSlot
		state.nextSlot += 1
	else
		return nil, false
	end
	state.byKey[key] = { slot = slot :: number, lastUsed = now }
	state.bySlot[slot :: number] = key
	return slot, true
end

function InteriorSlots.touch(state: State, key: string, now: number)
	local entry = state.byKey[key]
	if entry ~= nil then
		entry.lastUsed = now
	end
end

function InteriorSlots.slotOf(state: State, key: string): number?
	local entry = state.byKey[key]
	return if entry ~= nil then entry.slot else nil
end

-- The interior holding a slot, if any.
function InteriorSlots.keyAt(state: State, slot: number): string?
	return state.bySlot[slot]
end

local function release(state: State, key: string)
	local entry = state.byKey[key]
	if entry ~= nil then
		table.insert(state.free, entry.slot)
		state.bySlot[entry.slot] = nil
		state.byKey[key] = nil
	end
end

-- Frees the interiors nobody is in and nobody has been in for idleSeconds; returns their keys. Being inside counts as
-- using the interior, so the idle time starts when the last person leaves.
function InteriorSlots.sweep(state: State, occupied: {[string]: boolean}, now: number, idleSeconds: number): {string}
	local released = {}
	for key, entry in pairs(state.byKey) do
		if occupied[key] then
			entry.lastUsed = now
		elseif now - entry.lastUsed >= idleSeconds then
			table.insert(released, key)
		end
	end
	table.sort(released)
	for _, key in ipairs(released) do
		release(state, key)
	end
	return released
end

-- Frees the interior that has stood empty longest (none in `keep`) and returns its key; nil when every one is in use.
function InteriorSlots.evictOldest(state: State, keep: {[string]: boolean}): string?
	local oldestKey, oldest = nil, math.huge
	for key, entry in pairs(state.byKey) do
		if not keep[key] and (entry.lastUsed < oldest or (entry.lastUsed == oldest and oldestKey ~= nil and key < oldestKey)) then
			oldestKey, oldest = key, entry.lastUsed
		end
	end
	if oldestKey ~= nil then
		release(state, oldestKey)
	end
	return oldestKey
end

-- The slot's place in the grid: rows of perRow along x, rows along z.
function InteriorSlots.position(slot: number, origin: {number}, spacing: number, perRow: number): (number, number, number)
	local column = slot % perRow
	local row = math.floor(slot / perRow)
	return origin[1] + column * spacing, origin[2], origin[3] + row * spacing
end

-- The slot whose cell a point on the grid's plane lies in (nil off the grid).
function InteriorSlots.slotAt(x: number, z: number, origin: {number}, spacing: number, perRow: number, maxSlots: number): number?
	local column = math.floor((x - origin[1]) / spacing + 0.5)
	local row = math.floor((z - origin[3]) / spacing + 0.5)
	if column < 0 or column >= perRow or row < 0 then
		return nil
	end
	local slot = row * perRow + column
	return if slot < maxSlots then slot else nil
end

return InteriorSlots
