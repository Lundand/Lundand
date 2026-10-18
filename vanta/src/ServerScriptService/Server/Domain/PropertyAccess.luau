--!strict
-- Who may be inside an owned property (L-28), kept separate from buying it: walking into a building never grants
-- ownership, and an unowned building can be looked round by anyone. The server keeps a grid of property volumes
-- (each a footprint on the X/Z plane plus a height range) so a check per player costs one cell lookup, whether
-- the server has 5 players or 200.
local PropertyOwnership = require(script.Parent.PropertyOwnership)

local PropertyAccess = {}

export type Volume = { propertyId: string, minX: number, maxX: number, minZ: number, maxZ: number, minY: number, maxY: number, contains: ((number, number, number) -> boolean)? }

local Index = {}
Index.__index = Index

function PropertyAccess.newIndex(cellSize: number?)
	return setmetatable({ cell = cellSize or 64, cells = {}, count = 0 }, Index)
end

local function key(i: number, j: number): string
	return i .. ":" .. j
end

function Index.add(self: any, volume: Volume)
	local c = self.cell
	for i = math.floor(volume.minX / c), math.floor(volume.maxX / c) do
		for j = math.floor(volume.minZ / c), math.floor(volume.maxZ / c) do
			local k = key(i, j)
			local list = self.cells[k]
			if list == nil then
				list = {}
				self.cells[k] = list
			end
			table.insert(list, volume)
		end
	end
	self.count += 1
end

-- Volumes that contain the point (the bounds first, then the volume's own exact test if it has one).
function Index.query(self: any, x: number, y: number, z: number): {Volume}
	local list = self.cells[key(math.floor(x / self.cell), math.floor(z / self.cell))]
	local found = {}
	if list == nil then
		return found
	end
	for _, volume in ipairs(list) do
		if x >= volume.minX and x <= volume.maxX and z >= volume.minZ and z <= volume.maxZ and y >= volume.minY and y <= volume.maxY then
			if volume.contains == nil or volume.contains(x, y, z) then
				table.insert(found, volume)
			end
		end
	end
	return found
end

-- Must this visitor be shown out? Only owned properties are private; the owner's permissions decide the rest.
-- isFriend is nil while the friendship isn't known yet: then nobody is turned out on a Friends-only home.
function PropertyAccess.shouldEject(record: any, visitorUserId: number, isFriend: boolean?): boolean
	if record == nil or record.owner == nil then
		return false
	end
	local permissions = record.permissions or { mode = "Private", allowed = {} }
	if permissions.mode == "Friends" and isFriend == nil and record.owner.userId ~= visitorUserId then
		return false
	end
	return not PropertyOwnership.canEnter(record, visitorUserId, isFriend == true)
end

return PropertyAccess
