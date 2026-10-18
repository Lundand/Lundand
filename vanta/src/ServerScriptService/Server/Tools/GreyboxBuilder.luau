--!strict
-- Builds the capital's greybox from ServerData.CityLayout (L-27): base, city walls with gate openings,
-- roads, plazas, and hollow placeholder buildings with doorways you can walk through. Places carry
-- LocationId / PropertyId attributes so gameplay finds them by ID, never by name or hierarchy.
-- Run in Studio edit mode, for example through the MCP server's execute_luau:
--   require(game.ServerScriptService.Server.Tools.GreyboxBuilder).build()
-- Rebuilding replaces Workspace.CityGreybox, so change the layout data rather than editing the parts.
local CollectionService = game:GetService("CollectionService")
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
local ServerStorage = game:GetService("ServerStorage")
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)

local GreyboxBuilder = {}

local COLORS = {
	Base = Color3.fromRGB(96, 110, 80),
	Ground = Color3.fromRGB(150, 145, 135),
	Road = Color3.fromRGB(120, 112, 100),
	Wall = Color3.fromRGB(110, 110, 115),
	Building = Color3.fromRGB(190, 180, 160),
	Property = Color3.fromRGB(170, 200, 230),
	Hidden = Color3.fromRGB(60, 50, 50),
	Water = Color3.fromRGB(90, 140, 200),
	Crystal = Color3.fromRGB(140, 90, 220),
	Npc = Color3.fromRGB(230, 120, 60),
}

local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.Position = position
	item.Color = color
	item.Material = Enum.Material.SmoothPlastic
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function tagPlace(target: Instance, entry: any)
	if entry.locationId then
		target:SetAttribute("LocationId", entry.locationId)
	end
	if entry.propertyId then
		target:SetAttribute("PropertyId", entry.propertyId)
	end
end

-- Floor, roof and four walls, with a doorway in the wall named by entry.door.
local function shell(parent: Instance, entry: any, color: Color3)
	local model = Instance.new("Model")
	model.Name = entry.id
	tagPlace(model, entry)
	local x, z = entry.center[1], entry.center[2]
	local width, depth, height = entry.size[1], entry.size[2], entry.height
	local thickness = 1
	local wallHeight = height - thickness
	part(model, "Floor", Vector3.new(width, 0.4, depth), Vector3.new(x, 0.2, z), color)
	part(model, "Roof", Vector3.new(width, thickness, depth), Vector3.new(x, height - thickness / 2, z), color)
	local walls = {
		North = { x = x, z = z - depth / 2 + thickness / 2, length = width, alongX = true },
		South = { x = x, z = z + depth / 2 - thickness / 2, length = width, alongX = true },
		West = { x = x - width / 2 + thickness / 2, z = z, length = depth - 2 * thickness, alongX = false },
		East = { x = x + width / 2 - thickness / 2, z = z, length = depth - 2 * thickness, alongX = false },
	}
	for side, wall in pairs(walls) do
		local function piece(name: string, length: number, offset: number, pieceHeight: number, y: number)
			if wall.alongX then
				part(model, name, Vector3.new(length, pieceHeight, thickness), Vector3.new(wall.x + offset, y, wall.z), color)
			else
				part(model, name, Vector3.new(thickness, pieceHeight, length), Vector3.new(wall.x, y, wall.z + offset), color)
			end
		end
		if side == entry.door then
			local doorWidth, doorHeight = Layout.door.width, Layout.door.height
			local sideLength = (wall.length - doorWidth) / 2
			local offset = doorWidth / 2 + sideLength / 2
			piece(side .. "WallLeft", sideLength, -offset, wallHeight, wallHeight / 2)
			piece(side .. "WallRight", sideLength, offset, wallHeight, wallHeight / 2)
			piece(side .. "Lintel", doorWidth, 0, wallHeight - doorHeight, doorHeight + (wallHeight - doorHeight) / 2)
		else
			piece(side .. "Wall", wall.length, 0, wallHeight, wallHeight / 2)
		end
	end
	model.Parent = parent
end

local function solid(parent: Instance, entry: any, color: Color3)
	local x, z = entry.center[1], entry.center[2]
	local item
	if entry.shape == "Cylinder" then
		item = part(parent, entry.id, Vector3.new(entry.height, entry.size[1], entry.size[2]), Vector3.new(x, entry.height / 2, z), color)
		item.Shape = Enum.PartType.Cylinder
		item.CFrame = CFrame.new(x, entry.height / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	elseif entry.shape == "Crystal" then
		item = part(parent, entry.id, Vector3.new(entry.size[1], entry.height, entry.size[2]), Vector3.new(x, entry.height / 2, z), color)
		item.CFrame = CFrame.new(x, entry.height / 2, z) * CFrame.Angles(0, math.rad(45), 0)
		item.Material = Enum.Material.Glass
	else
		item = part(parent, entry.id, Vector3.new(entry.size[1], entry.height, entry.size[2]), Vector3.new(x, entry.height / 2, z), color)
	end
	tagPlace(item, entry)
end

-- City walls on the four sides of the square, split around gates; invisible gate markers carry IDs.
local function cityWalls(parent: Instance)
	local half, thickness, height = Layout.walls.halfSize, Layout.walls.thickness, Layout.walls.height
	local inset = half - thickness / 2
	local sides = {
		{ name = "North", fixed = -half, alongX = true },
		{ name = "South", fixed = half, alongX = true },
		{ name = "West", fixed = -half, alongX = false },
		{ name = "East", fixed = half, alongX = false },
	}
	for _, side in ipairs(sides) do
		local openings = {}
		for _, gate in ipairs(Layout.gates) do
			local along, across = gate.center[1], gate.center[2]
			if not side.alongX then
				along, across = gate.center[2], gate.center[1]
			end
			if across == side.fixed then
				table.insert(openings, { along - gate.width / 2, along + gate.width / 2 })
			end
		end
		table.sort(openings, function(a, b)
			return a[1] < b[1]
		end)
		local segments = {}
		local start = -half
		for _, opening in ipairs(openings) do
			table.insert(segments, { start, opening[1] })
			start = opening[2]
		end
		table.insert(segments, { start, half })
		local across = math.sign(side.fixed) * inset
		for index, segment in ipairs(segments) do
			local length = segment[2] - segment[1]
			local middle = (segment[1] + segment[2]) / 2
			if length > 0 then
				local name = string.format("%sWall%d", side.name, index)
				if side.alongX then
					part(parent, name, Vector3.new(length, height, thickness), Vector3.new(middle, height / 2, across), COLORS.Wall)
				else
					part(parent, name, Vector3.new(thickness, height, length), Vector3.new(across, height / 2, middle), COLORS.Wall)
				end
			end
		end
	end
	for _, gate in ipairs(Layout.gates) do
		local x, z = gate.center[1], gate.center[2]
		local marker
		if math.abs(z) == half then
			marker = part(parent, gate.id, Vector3.new(gate.width, height, thickness), Vector3.new(x, height / 2, math.sign(z) * inset), COLORS.Wall)
		else
			marker = part(parent, gate.id, Vector3.new(thickness, height, gate.width), Vector3.new(math.sign(x) * inset, height / 2, z), COLORS.Wall)
		end
		marker.Transparency = 1
		marker.CanCollide = false
		marker:SetAttribute("LocationId", gate.locationId)
	end
end

function GreyboxBuilder.build(): Model
	local existing = workspace:FindFirstChild("CityGreybox")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "CityGreybox"
	local folders = {}
	for _, name in ipairs({ "Ground", "Roads", "Walls", "Buildings" }) do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		folders[name] = folder
	end
	local baseSize = Layout.walls.halfSize * 2 + 80
	part(folders.Ground, "Base", Vector3.new(baseSize, 1, baseSize), Vector3.new(0, -0.5, 0), COLORS.Base)
	for _, entry in ipairs(Layout.ground) do
		local ground = part(folders.Ground, entry.id, Vector3.new(entry.size[1], 0.2, entry.size[2]), Vector3.new(entry.center[1], 0.1, entry.center[2]), COLORS.Ground)
		tagPlace(ground, entry)
	end
	for _, entry in ipairs(Layout.roads) do
		part(folders.Roads, entry.id, Vector3.new(entry.size[1], 0.2, entry.size[2]), Vector3.new(entry.center[1], 0.12, entry.center[2]), COLORS.Road)
	end
	cityWalls(folders.Walls)
	for _, entry in ipairs(Layout.blocks) do
		local color = COLORS.Building
		if entry.propertyId then
			color = COLORS.Property
		elseif entry.hidden then
			color = COLORS.Hidden
		elseif entry.kind == "Wall" then
			color = COLORS.Wall
		elseif entry.shape == "Crystal" then
			color = COLORS.Crystal
		elseif entry.shape == "Cylinder" then
			color = COLORS.Water
		end
		if entry.door then
			shell(folders.Buildings, entry, color)
		else
			solid(folders.Buildings, entry, color)
		end
	end
	-- Placeholder NPCs: DialogueService gives every part tagged "Npc" a Talk prompt.
	local npcFolder = Instance.new("Folder")
	npcFolder.Name = "Npcs"
	npcFolder.Parent = root
	for _, placement in ipairs(Layout.npcs) do
		local body = part(npcFolder, placement.npcId, Vector3.new(2, 5, 1), Vector3.new(placement.at[1], 2.9, placement.at[2]), COLORS.Npc)
		body:SetAttribute("NpcId", placement.npcId)
		if Content.npcs[placement.npcId].opens ~= nil then
			-- an interactive object such as the Heart of Realms: an invisible anchor for its prompt
			body.Transparency = 1
			body.CanCollide = false
		end
		CollectionService:AddTag(body, "Npc")
	end
	-- For-sale signs in front of each property's door (L-28, L-54); PropertyService gives them a prompt.
	local DOOR_OFFSETS = { North = { 0, -1 }, South = { 0, 1 }, East = { 1, 0 }, West = { -1, 0 } }
	local signFolder = Instance.new("Folder")
	signFolder.Name = "PropertySigns"
	signFolder.Parent = root
	for _, entry in ipairs(Layout.blocks) do
		local side = entry.propertyId and DOOR_OFFSETS[entry.door or "South"]
		if side then
			local x = entry.center[1] + side[1] * (entry.size[1] / 2 + 3) + side[2] * 4
			local z = entry.center[2] + side[2] * (entry.size[2] / 2 + 3) + side[1] * 4
			local sign = part(signFolder, entry.propertyId .. "Sign", Vector3.new(2.5, 3, 0.4), Vector3.new(x, 1.9, z), COLORS.Npc)
			sign:SetAttribute("PropertyId", entry.propertyId)
			CollectionService:AddTag(sign, "PropertySign")
		end
	end

	-- Opening markers (L-43): the church start point, the ritual circle and the starting chest.
	local markerFolder = Instance.new("Folder")
	markerFolder.Name = "Markers"
	markerFolder.Parent = root
	for _, entry in ipairs(Layout.markers) do
		if entry.kind == "SpawnPoint" then
			local point = part(markerFolder, entry.id, Vector3.new(4, 1, 4), Vector3.new(entry.at[1], 0.9, entry.at[2]), COLORS.Npc)
			point.Transparency = 1
			point.CanCollide = false
			point:SetAttribute("SpawnId", entry.spawnId)
			CollectionService:AddTag(point, "SpawnPoint")
		elseif entry.kind == "RitualCircle" then
			local circle = part(markerFolder, entry.id, Vector3.new(12, 0.2, 12), Vector3.new(entry.at[1], 0.5, entry.at[2]), COLORS.Crystal)
			circle.CanCollide = false
			CollectionService:AddTag(circle, "RitualCircle")
		elseif entry.kind == "PlanningTable" then
			local planning = part(markerFolder, entry.id, Vector3.new(8, 3, 4), Vector3.new(entry.at[1], 1.9, entry.at[2]), COLORS.Npc)
			planning:SetAttribute("PropertyId", entry.propertyId)
			CollectionService:AddTag(planning, "PlanningTable")
		elseif entry.kind == "StarterChest" then
			local chest = part(markerFolder, entry.id, Vector3.new(4, 3, 2.5), Vector3.new(entry.at[1], 1.9, entry.at[2]), COLORS.Npc)
			CollectionService:AddTag(chest, "StarterChest")
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CitySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(Layout.spawn.center[1], 0.5, Layout.spawn.center[2])
	spawn.Parent = root
	root.Parent = workspace
	return root
end

return GreyboxBuilder
