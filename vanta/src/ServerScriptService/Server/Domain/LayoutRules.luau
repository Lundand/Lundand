--!strict
-- Checks the city layout (L-27) without Studio: unique IDs, everything inside the walls, gates on the wall, no
-- overlapping buildings (footprints may be turned), no roads or wall towers through buildings, doors that fit, houses
-- that match their house model, every door reachable on foot from the south gate, and every location and property
-- from Config/World placed exactly once. Touching edges are allowed; walls and towers of a fortification may overlap
-- each other.
local LayoutRules = {}

local SIDES = { North = true, South = true, East = true, West = true }
local FORTIFICATION = { Wall = true, Tower = true, Gatehouse = true }
local function cornersOf(entry: any): {{number}}
	local x, z = entry.center[1], entry.center[2]
	local hw, hd = entry.size[1] / 2, entry.size[2] / 2
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	local out = {}
	for _, offset in ipairs({ { -hw, -hd }, { hw, -hd }, { hw, hd }, { -hw, hd } }) do
		table.insert(out, { x + offset[1] * c + offset[2] * s, z - offset[1] * s + offset[2] * c })
	end
	return out
end
LayoutRules.corners = cornersOf

-- Axis-aligned bounds of an entry's (possibly turned) footprint.
function LayoutRules.bounds(entry: any): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(cornersOf(entry)) do
		minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
		minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
	end
	return minX, maxX, minZ, maxZ
end

-- Separating axis test on the two footprints.
function LayoutRules.overlaps(a: any, b: any): boolean
	local ca, cb = cornersOf(a), cornersOf(b)
	for _, poly in ipairs({ ca, cb }) do
		for index = 1, 4 do
			local p1, p2 = poly[index], poly[index % 4 + 1]
			local ax, az = p2[2] - p1[2], p1[1] - p2[1]
			local length = math.sqrt(ax * ax + az * az)
			ax, az = ax / length, az / length
			local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(ca) do
				local d = p[1] * ax + p[2] * az
				minA, maxA = math.min(minA, d), math.max(maxA, d)
			end
			for _, p in ipairs(cb) do
				local d = p[1] * ax + p[2] * az
				minB, maxB = math.min(minB, d), math.max(maxB, d)
			end
			if maxA <= minB + 1e-6 or maxB <= minA + 1e-6 then
				return false
			end
		end
	end
	return true
end

-- Is a world point inside an entry's footprint?
function LayoutRules.contains(entry: any, point: {number}): boolean
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	local dx, dz = point[1] - entry.center[1], point[2] - entry.center[2]
	-- inverse of local (x, z) -> world (x c + z s, -x s + z c)
	local lx, lz = dx * c - dz * s, dx * s + dz * c
	return math.abs(lx) < entry.size[1] / 2 and math.abs(lz) < entry.size[2] / 2
end
local contains = LayoutRules.contains

-- The point on the street in front of an entry's door (2.5 studs out), in world coordinates.
function LayoutRules.doorStep(entry: any): {number}
	local hw, hd = entry.size[1] / 2, entry.size[2] / 2
	local local_ = ({ South = { 0, hd + 2.5 }, North = { 0, -hd - 2.5 }, East = { hw + 2.5, 0 }, West = { -hw - 2.5, 0 } })[entry.door]
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	return { entry.center[1] + local_[1] * c + local_[2] * s, entry.center[2] - local_[1] * s + local_[2] * c }
end

-- The strip of street in front of an entry's door side: as wide as that side, `depth` studs out (a shop's counter
-- and awning stand in it).
function LayoutRules.frontStrip(entry: any, depth: number): any
	local hw, hd = entry.size[1] / 2, entry.size[2] / 2
	local turned = entry.door == "East" or entry.door == "West"
	local local_ = ({ South = { 0, hd + depth / 2 }, North = { 0, -hd - depth / 2 }, East = { hw + depth / 2, 0 }, West = { -hw - depth / 2, 0 } })[entry.door]
	local yaw = math.rad(entry.yaw or 0)
	local c, s = math.cos(yaw), math.sin(yaw)
	return {
		center = { entry.center[1] + local_[1] * c + local_[2] * s, entry.center[2] - local_[1] * s + local_[2] * c },
		size = if turned then { depth, entry.size[2] } else { entry.size[1], depth },
		yaw = entry.yaw,
	}
end

-- How deep the street in front of a shop must be, clear of everything: room for its counter and its customers.
LayoutRules.SHOP_FRONTAGE = 7

local function wallBounds(layout: any): (number, number, number, number)
	local b = layout.bounds
	local inset = layout.walls.thickness / 2
	return b.minX + inset, b.maxX - inset, b.minZ + inset, b.maxZ - inset
end

-- Walkable grid of the area inside the walls (cells of `cell` studs): false where a building, landmark or the
-- harbour water is. Returns a lookup and the grid size.
function LayoutRules.walkable(layout: any, cell: number): ((number, number) -> boolean, (number, number) -> (number, number))
	local minX, maxX, minZ, maxZ = wallBounds(layout)
	local nx, nz = math.floor((maxX - minX) / cell), math.floor((maxZ - minZ) / cell)
	local blocked: {[number]: boolean} = {}
	local function index(i: number, j: number): number
		return j * nx + i
	end
	local function toCell(x: number, z: number): (number, number)
		return math.floor((x - minX) / cell), math.floor((z - minZ) / cell)
	end
	local solids = {}
	for _, entry in ipairs(layout.blocks) do
		-- a gatehouse is walked through (its passage); everything else is solid ground floor to the street
		if entry.kind ~= "Gatehouse" then
			table.insert(solids, entry)
		end
	end
	for _, water in ipairs(layout.water or {}) do
		table.insert(solids, water)
	end
	for _, tower in ipairs(layout.wallTowers or {}) do
		table.insert(solids, tower)
	end
	for _, entry in ipairs(solids) do
		local x0, x1, z0, z1 = LayoutRules.bounds(entry)
		local i0, j0 = toCell(x0, z0)
		local i1, j1 = toCell(x1, z1)
		for i = math.max(0, i0), math.min(nx - 1, i1) do
			for j = math.max(0, j0), math.min(nz - 1, j1) do
				local cx, cz = minX + (i + 0.5) * cell, minZ + (j + 0.5) * cell
				if contains(entry, { cx, cz }) then
					blocked[index(i, j)] = true
				end
			end
		end
	end
	return function(i: number, j: number): boolean
		return i >= 0 and j >= 0 and i < nx and j < nz and not blocked[index(i, j)]
	end, toCell
end

-- Cells reachable on foot from a world point (4-neighbour flood fill over the walkable grid).
function LayoutRules.reachableFrom(layout: any, start: {number}, cell: number): (number, number) -> boolean
	local walkable, toCell = LayoutRules.walkable(layout, cell)
	local seen: {[string]: boolean} = {}
	local si, sj = toCell(start[1], start[2])
	local queue = { { si, sj } }
	local head = 1
	if walkable(si, sj) then
		seen[si .. "," .. sj] = true
	end
	while head <= #queue do
		local i, j = queue[head][1], queue[head][2]
		head += 1
		for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ni, nj = i + step[1], j + step[2]
			local key = ni .. "," .. nj
			if not seen[key] and walkable(ni, nj) then
				seen[key] = true
				table.insert(queue, { ni, nj })
			end
		end
	end
	return function(x: number, z: number): boolean
		local i, j = toCell(x, z)
		return seen[i .. "," .. j] == true
	end
end

function LayoutRules.validate(layout: any, world: any, npcs: any): {string}
	local problems = {}
	local function add(message: string)
		table.insert(problems, message)
	end
	local minX, maxX, minZ, maxZ = wallBounds(layout)
	local ids, placedLocations, placedProperties = {}, {}, {}

	local function registerProperty(owner: string, propertyId: any)
		if world.properties[propertyId] == nil then
			add(owner .. " uses unknown property " .. tostring(propertyId))
		elseif placedProperties[propertyId] then
			add("property " .. propertyId .. " is placed twice")
		end
		placedProperties[propertyId] = true
	end
	local function register(entry: any)
		if ids[entry.id] then
			add("duplicate layout id " .. tostring(entry.id))
		end
		ids[entry.id] = true
		if entry.locationId ~= nil then
			if world.locations[entry.locationId] == nil then
				add(entry.id .. " uses unknown location " .. tostring(entry.locationId))
			elseif placedLocations[entry.locationId] then
				add("location " .. entry.locationId .. " is placed twice")
			end
			placedLocations[entry.locationId] = true
		end
		if entry.propertyId ~= nil then
			registerProperty(entry.id, entry.propertyId)
		end
	end

	local function inside(entry: any)
		local x0, x1, z0, z1 = LayoutRules.bounds(entry)
		if x0 < minX - 1e-6 or x1 > maxX + 1e-6 or z0 < minZ - 1e-6 or z1 > maxZ + 1e-6 then
			add(entry.id .. " is outside the city walls")
		end
	end

	for _, entry in ipairs(layout.blocks) do
		register(entry)
		inside(entry)
		if type(entry.height) ~= "number" or entry.height <= 0 then
			add(entry.id .. " needs a height")
		end
		if entry.door ~= nil then
			if not SIDES[entry.door] then
				add(entry.id .. " has an unknown door side")
			elseif entry.height < layout.door.height + 2 then
				add(entry.id .. " is too low for a doorway")
			end
		end
		if entry.template ~= nil then
			-- a house built from a model must have the model's footprint (facade along its door side)
			local template = (layout.templates or {})[entry.template]
			if template == nil then
				add(entry.id .. " uses unknown house model " .. tostring(entry.template))
			else
				local width, depth = entry.size[1], entry.size[2]
				if entry.door == "East" or entry.door == "West" then
					width, depth = depth, width
				end
				if math.abs(width - template.w) > 1e-6 or math.abs(depth - template.d) > 1e-6 or entry.stories ~= template.stories then
					add(entry.id .. " doesn't match its house model " .. entry.template)
				end
				if template.style ~= nil and entry.style ~= template.style then
					add(entry.id .. " is in a " .. tostring(entry.style) .. " district but its house model " .. entry.template .. " is " .. template.style)
				end
			end
			if entry.door == nil then
				add(entry.id .. " has a house model but no door")
			end
		end
	end
	for _, entry in ipairs(layout.roads) do
		register(entry)
		inside(entry)
	end
	for _, entry in ipairs(layout.ground) do
		register(entry)
	end
	local b = layout.bounds
	for _, gate in ipairs(layout.gates) do
		register(gate)
		local x, z = gate.center[1], gate.center[2]
		if x ~= b.minX and x ~= b.maxX and z ~= b.minZ and z ~= b.maxZ then
			add(gate.id .. " is not on the city wall")
		end
	end
	for index, entry in ipairs(layout.blocks) do
		for other = index + 1, #layout.blocks do
			local second = layout.blocks[other]
			if not (FORTIFICATION[entry.kind] and FORTIFICATION[second.kind]) and LayoutRules.overlaps(entry, second) then
				add(entry.id .. " overlaps " .. second.id)
			end
		end
		for _, road in ipairs(layout.roads) do
			if LayoutRules.overlaps(entry, road) then
				add(road.id .. " runs through " .. entry.id)
			end
		end
		for _, tower in ipairs(layout.wallTowers or {}) do
			if LayoutRules.overlaps(entry, tower) then
				add(entry.id .. " stands in the city wall's " .. tower.id)
			end
		end
	end
	-- a shop has street in front of it for its counter, and every deed names the district its building stands in and
	-- carries the spot's foot traffic (which sets its price)
	for _, entry in ipairs(layout.blocks) do
		if entry.shopfront then
			local strip = LayoutRules.frontStrip(entry, LayoutRules.SHOP_FRONTAGE)
			local x0, x1, z0, z1 = LayoutRules.bounds(strip)
			local blocked = x0 < minX or x1 > maxX or z0 < minZ or z1 > maxZ
			for _, list in ipairs({ layout.blocks, layout.wallTowers or {} }) do
				for _, other in ipairs(list) do
					if other ~= entry and LayoutRules.overlaps(strip, other) then
						blocked = true
					end
				end
			end
			if blocked then
				add(entry.id .. "'s shop counter has no room in the street")
			end
		end
		if entry.propertyId ~= nil then
			local property = world.properties[entry.propertyId]
			if property ~= nil and entry.district ~= nil and property.district ~= entry.district then
				add(entry.id .. " stands in " .. tostring(entry.district) .. " but its deed says " .. tostring(property.district))
			end
			if type(entry.traffic) ~= "number" or entry.traffic < 0 or entry.traffic > 1 then
				add(entry.id .. " has no foot traffic for its price")
			end
		end
	end

	-- the wall's towers stand clear of the streets and of planned open ground (gardens, yards, the wall stairs)
	for _, tower in ipairs(layout.wallTowers or {}) do
		register(tower)
		for _, list in ipairs({ layout.roads, layout.ground }) do
			for _, other in ipairs(list) do
				if LayoutRules.overlaps(tower, other) then
					add(tower.id .. " stands in " .. other.id)
				end
			end
		end
	end

	-- every door can be reached on foot from inside the south gate, and so can the other land gates
	local reachable = LayoutRules.reachableFrom(layout, { 0, maxZ - 12 }, 2)
	for _, entry in ipairs(layout.blocks) do
		if entry.door ~= nil and not FORTIFICATION[entry.kind] then
			local step = LayoutRules.doorStep(entry)
			if not reachable(step[1], step[2]) then
				add(entry.id .. "'s door can't be reached from the gates")
			end
		end
	end
	for _, gate in ipairs(layout.gates) do
		if gate.kind ~= "Sea" then
			local x, z = gate.center[1], gate.center[2]
			local inward = { if x == b.minX then 12 elseif x == b.maxX then -12 else 0, if z == b.minZ then 12 elseif z == b.maxZ then -12 else 0 }
			if not reachable(x + inward[1], z + inward[2]) then
				add(gate.id .. " can't be reached from the south gate")
			end
		end
	end

	-- NPCs stand inside their own building, or (for open-air locations) outside every solid block.
	local placedNpcs = {}
	for _, placement in ipairs(layout.npcs or {}) do
		local npc = npcs[placement.npcId]
		if npc == nil then
			add("unknown NPC " .. tostring(placement.npcId))
		else
			if placedNpcs[placement.npcId] then
				add("NPC " .. placement.npcId .. " is placed twice")
			end
			placedNpcs[placement.npcId] = true
			local home = nil
			for _, entry in ipairs(layout.blocks) do
				if entry.locationId == npc.locationId then
					home = entry
				end
			end
			if home ~= nil and home.door ~= nil then
				if not contains(home, placement.at) then
					add("NPC " .. placement.npcId .. " should stand inside " .. home.id)
				end
			else
				for _, entry in ipairs(layout.blocks) do
					if entry.door == nil and contains(entry, placement.at) then
						add("NPC " .. placement.npcId .. " stands inside " .. entry.id)
					end
				end
			end
		end
	end
	for _, marker in ipairs(layout.markers or {}) do
		local host = nil
		for _, entry in ipairs(layout.blocks) do
			if entry.id == marker.inside then
				host = entry
			end
		end
		if host == nil or not contains(host, marker.at) then
			add("marker " .. tostring(marker.id) .. " should be inside " .. tostring(marker.inside))
		end
	end
	for npcId in pairs(npcs) do
		if not placedNpcs[npcId] then
			add("NPC " .. npcId .. " is not placed")
		end
	end
	for locationId in pairs(world.locations) do
		if not placedLocations[locationId] then
			add("location " .. locationId .. " is not placed")
		end
	end
	for propertyId in pairs(world.properties) do
		if not placedProperties[propertyId] then
			add("property " .. propertyId .. " is not placed")
		end
	end
	table.sort(problems)
	return problems
end

return LayoutRules
