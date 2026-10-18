--!strict
-- Checks the city greybox layout (L-27) without Studio: unique IDs, everything inside the walls, gates on
-- the wall, no overlapping buildings, no roads through buildings, doors that fit, and every location and
-- property from Config/World placed exactly once. Touching edges are allowed.
local LayoutRules = {}

local SIDES = { North = true, South = true, East = true, West = true }

function LayoutRules.bounds(entry: any): (number, number, number, number)
	local x, z = entry.center[1], entry.center[2]
	local halfWidth, halfDepth = entry.size[1] / 2, entry.size[2] / 2
	return x - halfWidth, x + halfWidth, z - halfDepth, z + halfDepth
end

function LayoutRules.overlaps(a: any, b: any): boolean
	local aMinX, aMaxX, aMinZ, aMaxZ = LayoutRules.bounds(a)
	local bMinX, bMaxX, bMinZ, bMaxZ = LayoutRules.bounds(b)
	return aMinX < bMaxX and bMinX < aMaxX and aMinZ < bMaxZ and bMinZ < aMaxZ
end

local function contains(entry: any, point: {number}): boolean
	local minX, maxX, minZ, maxZ = LayoutRules.bounds(entry)
	return point[1] > minX and point[1] < maxX and point[2] > minZ and point[2] < maxZ
end

function LayoutRules.validate(layout: any, world: any, npcs: any): {string}
	local problems = {}
	local function add(message: string)
		table.insert(problems, message)
	end
	local limit = layout.walls.halfSize - layout.walls.thickness
	local ids, placedLocations, placedProperties = {}, {}, {}

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
			if world.properties[entry.propertyId] == nil then
				add(entry.id .. " uses unknown property " .. tostring(entry.propertyId))
			elseif placedProperties[entry.propertyId] then
				add("property " .. entry.propertyId .. " is placed twice")
			end
			placedProperties[entry.propertyId] = true
		end
	end

	local function inside(entry: any)
		local minX, maxX, minZ, maxZ = LayoutRules.bounds(entry)
		if minX < -limit or maxX > limit or minZ < -limit or maxZ > limit then
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
	end
	for _, entry in ipairs(layout.roads) do
		register(entry)
		inside(entry)
	end
	for _, entry in ipairs(layout.ground) do
		register(entry)
		inside(entry)
	end
	for _, gate in ipairs(layout.gates) do
		register(gate)
		if math.abs(gate.center[1]) ~= layout.walls.halfSize and math.abs(gate.center[2]) ~= layout.walls.halfSize then
			add(gate.id .. " is not on the city wall")
		end
	end
	for index, entry in ipairs(layout.blocks) do
		for other = index + 1, #layout.blocks do
			if LayoutRules.overlaps(entry, layout.blocks[other]) then
				add(entry.id .. " overlaps " .. layout.blocks[other].id)
			end
		end
		for _, road in ipairs(layout.roads) do
			if LayoutRules.overlaps(entry, road) then
				add(road.id .. " runs through " .. entry.id)
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
