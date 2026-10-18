--!strict
-- Where instanced interiors go (houses, inn rooms). Each interior that someone is in gets a slot in a grid far above
-- the map; a house shares one slot among everyone inside it, and an inn room is one slot per renter. An interior
-- nobody has been in for a while gives its slot back. Pure bookkeeping, so it can be tested offline.
local InteriorSlots = {}

export type State = { maxSlots: number, free: {number}, nextSlot: number, byKey: {[string]: { slot: number, lastUsed: number }} }

function InteriorSlots.new(maxSlots: number): State
	return { maxSlots = maxSlots, free = {}, nextSlot = 0, byKey = {} }
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

-- Frees the interiors nobody is in and nobody has used for idleSeconds; returns their keys.
function InteriorSlots.sweep(state: State, occupied: {[string]: boolean}, now: number, idleSeconds: number): {string}
	local released = {}
	for key, entry in pairs(state.byKey) do
		if not occupied[key] and now - entry.lastUsed >= idleSeconds then
			table.insert(released, key)
		end
	end
	table.sort(released)
	for _, key in ipairs(released) do
		table.insert(state.free, state.byKey[key].slot)
		state.byKey[key] = nil
	end
	return released
end

-- The slot's place in the grid: rows of perRow along x, rows along z.
function InteriorSlots.position(slot: number, origin: {number}, spacing: number, perRow: number): (number, number, number)
	local column = slot % perRow
	local row = math.floor(slot / perRow)
	return origin[1] + column * spacing, origin[2], origin[3] + row * spacing
end

return InteriorSlots
