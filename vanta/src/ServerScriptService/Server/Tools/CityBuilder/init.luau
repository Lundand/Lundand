--!strict
-- Builds the capital from ServerData.CityLayout (L-27): ground, city walls and gates, the houses, the public
-- buildings, the castle and its library, the church, the harbour, the forest beyond the south gate and the thieves'
-- hideout under the slums. Places carry LocationId / PropertyId attributes, so gameplay finds them by ID, never by
-- name or hierarchy; NPC anchors, markers and property signs are tagged as before.
--
-- Houses are clones of a few house models (ServerStorage.CityAssets.Houses), painted per house; their doors (tagged
-- HouseDoor) lead to interiors InteriorService builds from ServerStorage.CityAssets.Interiors while someone is
-- inside. Both folders are filled with default models the first time; edit or replace a model there in Studio and
-- every house built from it follows (keep a part named "Door" on a house, and "Entry" and "ExitDoor" in a room).
--
-- The server builds the city at start when Workspace has none (Server/Main). To keep it in the place instead, run
-- in Studio edit mode (for example through the MCP server's execute_luau) and save:
--   require(game.ServerScriptService.Server.Tools.CityBuilder).build()
-- Rebuilding replaces Workspace.City, so change the layout data rather than editing the parts.
local ServerStorage = game:GetService("ServerStorage")
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)
local LayoutRules = require(script.Parent.Parent.Domain.LayoutRules)

local Kit = require(script.Kit)
local Furniture = require(script.Furniture)
local Shell = require(script.Shell)
local Interior = require(script.Interior)
local Landmarks = require(script.Landmarks)
local Outdoors = require(script.Outdoors)
local Forest = require(script.Forest)
local Hideout = require(script.Hideout)

local CityBuilder = {}
local rgb = Kit.rgb

export type Options = { yield: boolean?, parent: Instance? }

local LANDMARKS: {[string]: (any, Instance) -> Model} = {
	Crystal = Landmarks.heartOfRealms,
	Church = Landmarks.church,
	Keep = Landmarks.keep,
	Library = Landmarks.library,
	CastleWall = Landmarks.castleWall,
	Gatehouse = Landmarks.castleGatehouse,
	FishMarket = Landmarks.fishMarket,
}

-- Public buildings you walk into; every other building is a closed shell with an instanced interior.
local PUBLIC = { Inn = true, Guild = true, Forge = true, Apothecary = true, CraftGuild = true, SlumTavern = true, Tavern = true }
-- what a closed building's room has in it besides its walls (Interior.build)
local FITTINGS = { Storefront = "Shop", GuildHall = "GuildHall" }
CityBuilder.PUBLIC = PUBLIC

local function folderIn(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function assetFolder(name: string): Folder
	return folderIn(folderIn(ServerStorage, "CityAssets"), name)
end

-- The interior a building's door leads to: its house model's room, or a room sized to the building; shops and guild
-- halls have their own (with a counter, or a planning table).
function CityBuilder.interiorKey(entry: any): string
	local fitting = FITTINGS[entry.use]
	local prefix = if fitting ~= nil then fitting .. "_" else ""
	if entry.template ~= nil then
		return prefix .. entry.template
	end
	local _, W, D = Shell.frameOf(entry)
	return string.format("%sRoom%dx%d", prefix, math.floor(W), math.floor(D))
end

local partCounts: {[Instance]: number} = {}
local function partCount(model: Model): number
	local count = partCounts[model]
	if count == nil then
		count = 0
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				count += 1
			end
		end
		partCounts[model] = count
	end
	return count :: number
end

-- The house model for a template, built (and kept in CityAssets) the first time it is needed, in its district's
-- style (window sizes, roof pitch, timber framing and chimney differ; colours are painted per house).
local function houseModel(templateId: string): Model
	local folder = assetFolder("Houses")
	local existing = folder:FindFirstChild(templateId)
	if existing ~= nil and existing:IsA("Model") then
		return existing
	end
	local t = Layout.templates[templateId]
	local model = Instance.new("Model")
	model.Name = templateId
	Shell.build(model, CFrame.new(), { W = t.w, D = t.d, stories = t.stories, roof = t.roof, style = t.style or "Residential", floorHeight = Layout.floorHeight })
	model.WorldPivot = CFrame.new()
	model.Parent = folder
	return model
end

local function ensureInterior(key: string, width: number, depth: number, style: string?, fitting: string?)
	local folder = assetFolder("Interiors")
	if folder:FindFirstChild(key) == nil then
		local room = Interior.build(key, width, depth, style, fitting)
		room.WorldPivot = CFrame.new()
		room.Parent = folder
	end
end

-- Front-wall openings near a door, as {x0, x1, y0, y1} in the door's frame (windows and glass on the facade).
local function frontOpenings(model: Model, face: CFrame): {{number}}
	local list = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and (part.Name == "Window" or part.Name == "Glass") then
			local p = face:PointToObjectSpace(part.CFrame.Position)
			if math.abs(p.Z) < 1.2 then
				local hx, hy = part.Size.X / 2, part.Size.Y / 2
				table.insert(list, { p.X - hx, p.X + hx, p.Y - hy, p.Y + hy })
			end
		end
	end
	return list
end

-- A deed plaque on the wall beside a door (PropertyService gives it the View prompt), reading towards the street.
-- `face` is the door's middle at its sill, on the front wall (+z out); the plaque goes on whichever side of the door
-- has no window, inside the facade (x from `left` to `right` in that frame), or low under the windows if both do.
local function deedSign(properties: Instance, propertyId: string, face: CFrame, doorWidth: number, left: number, right: number, openings: {{number}})
	local w, h, gap = 2.6, 1.8, 0.2
	local function clear(x: number, y: number): boolean
		if x - w / 2 < left + 0.3 or x + w / 2 > right - 0.3 then
			return false
		end
		for _, o in ipairs(openings) do
			if x + w / 2 + gap > o[1] and x - w / 2 - gap < o[2] and y + h / 2 + gap > o[3] and y - h / 2 - gap < o[4] then
				return false
			end
		end
		return true
	end
	local offset = doorWidth / 2 + 1.8
	local x, y = offset, 5.2
	if not clear(x, y) then
		if clear(-offset, y) then
			x = -offset
		elseif clear(offset, 2) then
			y = 2
		else
			x, y = -offset, 2
		end
	end
	local f = Kit.frame(properties, face)
	local sign = f:box(propertyId .. "Sign", Vector3.new(w, h, 0.3), x, y, 0.2, rgb(214, 196, 150), Enum.Material.WoodPlanks, { collide = false, query = false })
	sign:SetAttribute("PropertyId", propertyId)
	sign:AddTag("PropertySign")
	-- the plaque faces the street (+z), which is a part's back face
	Kit.sign(sign, Enum.NormalId.Back, "Deed: " .. propertyId, rgb(60, 40, 20))
end

-- Where the door to an inn's rooms goes in its back wall: as near a third of the way along as it can be without
-- standing in front of a window or over the cellar trapdoor.
local function roomsDoorX(model: Model, cf: CFrame, W: number, D: number, trapdoor: any?): number
	local blocked = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "Glass" then
			local p = cf:PointToObjectSpace(part.CFrame.Position)
			if p.Z < -D / 2 + 2 then
				table.insert(blocked, { p.X - part.Size.X / 2 - 0.2, p.X + part.Size.X / 2 + 0.2 })
			end
		end
	end
	if trapdoor ~= nil then
		table.insert(blocked, { trapdoor.x0 - 1, trapdoor.x1 + 1 })
	end
	local function clear(x: number): boolean
		if math.abs(x) > W / 2 - 4 then
			return false
		end
		for _, range in ipairs(blocked) do
			if x + 2.5 > range[1] and x - 2.5 < range[2] then
				return false
			end
		end
		return true
	end
	for step = 0, math.ceil(W) do
		for _, x in ipairs({ -W / 6 - step * 0.5, -W / 6 + step * 0.5 }) do
			if clear(x) then
				return x
			end
		end
	end
	return -W / 6
end

-- Neighbouring roofs at the same height can overlap at the eaves (houses turned round the square, a gable's overhang
-- past a gap). Where two would, one sits a few hundredths of a stud lower, so their undersides never share a plane.
-- Returns each building's level (0, 1, 2...); a roof sinks 0.04 studs per level.
local function roofLevels(): {[string]: number}
	local roofs = {}
	for _, entry in ipairs(Layout.blocks) do
		if entry.door ~= nil and LANDMARKS[entry.use] == nil and entry.kind ~= "Tower" then
			local _, W = Shell.frameOf(entry)
			local roof = if entry.template ~= nil then Layout.templates[entry.template].roof elseif W <= 24 then "Gable" else "Eaves"
			-- eaves overhang the front and back by a stud, a gable's slopes the sides by 0.6
			local alongW, alongD = if roof == "Eaves" then 0 else 1.2, if roof == "Eaves" then 2 else 0
			local turned = entry.door == "East" or entry.door == "West"
			local footprint = {
				center = entry.center,
				size = if turned then { entry.size[1] + alongD, entry.size[2] + alongW } else { entry.size[1] + alongW, entry.size[2] + alongD },
				yaw = entry.yaw,
			}
			local x0, x1, z0, z1 = LayoutRules.bounds(footprint)
			table.insert(roofs, { id = entry.id, stories = entry.stories, footprint = footprint, box = { x0, x1, z0, z1 } })
		end
	end
	local levels = {}
	for index, roof in ipairs(roofs) do
		local used = {}
		for other = 1, index - 1 do
			local o = roofs[other]
			local a, b = roof.box, o.box
			if o.stories == roof.stories and a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] and LayoutRules.overlaps(roof.footprint, o.footprint) then
				used[levels[o.id] :: number] = true
			end
		end
		local level = 0
		while used[level] do
			level += 1
		end
		levels[roof.id] = level
	end
	return levels
end

local function sinkRoof(model: Model, level: number?)
	if level == nil or level == 0 then
		return
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "Roof" then
			part.CFrame = part.CFrame - Vector3.new(0, level * 0.04, 0)
		end
	end
end

-- What a closed building's door is called on its prompt.
local DOOR_NAMES = { Storefront = "Shop", Warehouse = "Warehouse", GuildHall = "Guild hall" }

local BACK_OF = { South = "North", North = "South", East = "West", West = "East" }

-- Is a point on the ground inside some other building or a wall tower? (a coarse grid over the layout's footprints)
local function obstacleLookup(): (Vector3, any) -> boolean
	local CELL = 32
	local cells: {[string]: {any}} = {}
	local function add(entry: any)
		local x0, x1, z0, z1 = LayoutRules.bounds(entry)
		for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
			for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
				local key = i .. ":" .. j
				cells[key] = cells[key] or {}
				table.insert(cells[key], entry)
			end
		end
	end
	for _, entry in ipairs(Layout.blocks) do
		add(entry)
	end
	for _, tower in ipairs(Layout.wallTowers) do
		add(tower)
	end
	return function(point: Vector3, self: any): boolean
		for _, other in ipairs(cells[math.floor(point.X / CELL) .. ":" .. math.floor(point.Z / CELL)] or {}) do
			if other ~= self and LayoutRules.contains(other, { point.X, point.Z }) then
				return true
			end
		end
		return false
	end
end

-- A house model has windows front and back. Where the back of the lot meets a neighbour or a wall they go, and so
-- does any window with another building or a wall tower right in front of it.
local function closeWindows(model: Model, cf: CFrame, entry: any, blocked: (Vector3, any) -> boolean)
	local open = entry.open or {}
	local backOpen = open[BACK_OF[entry.door or "South"]] == true
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "Window" then
			local p = cf:PointToObjectSpace(part.CFrame.Position)
			local outward = if p.Z > 0 then 1 else -1
			if (p.Z < 0 and not backOpen) or blocked(cf:PointToWorldSpace(Vector3.new(p.X, p.Y, p.Z + outward)), entry) then
				part:Destroy()
			end
		end
	end
end

-- Parts left by earlier versions of the map: the greybox, and the hand-placed forest and hideout it replaces.
local function removeOld(parent: Instance)
	for _, name in ipairs({ "CityGreybox", "City", "Passages" }) do
		local old = parent:FindFirstChild(name)
		if old ~= nil then
			old:Destroy()
		end
	end
	local world = parent:FindFirstChild("World")
	if world ~= nil then
		for _, name in ipairs({ "SouthernWoods", "CriminalHideout" }) do
			local old = world:FindFirstChild(name)
			if old ~= nil then
				old:Destroy()
			end
		end
		if #world:GetChildren() == 0 then
			world:Destroy()
		end
	end
end

local function point(at: {number}, y: number): Vector3
	return Vector3.new(at[1], y, at[2])
end

local function anchor(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	return Kit.part(parent, name, size, cf, color, Enum.Material.SmoothPlastic, { collide = false, query = false, transparency = 1, shadow = false })
end

local function boundary(parent: Instance, x0: number, z0: number, x1: number, z1: number)
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	local wall = Kit.part(parent, "Boundary", Vector3.new(2, 300, length), CFrame.new((x0 + x1) / 2, 140, (z0 + z1) / 2) * CFrame.Angles(0, math.atan2(dx, dz), 0), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { transparency = 1, query = false, shadow = false })
	wall.CastShadow = false
end

function CityBuilder.build(options: Options?): Model
	local opts: Options = options or {}
	local parent = opts.parent or workspace
	local started = os.clock()
	Kit.stats.parts, Kit.stats.lights = 0, 0
	table.clear(partCounts)
	Kit.setYield(if opts.yield then 2500 else 0, if opts.yield then function()
		task.wait()
	end else nil)
	removeOld(parent)

	local root = Instance.new("Model")
	root.Name = "City"
	local districts = Kit.folder(root, "Districts")
	local landmarks = Kit.folder(root, "Landmarks")
	local properties = Kit.folder(root, "Properties")
	-- places, NPC anchors and markers stay loaded on every client even with streaming on
	local places = Instance.new("Model")
	places.Name = "Places"
	pcall(function()
		(places :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	places.Parent = root

	-- keep NPC spots, markers and the cellar stairs clear of furniture
	local clearPoints = {}
	for _, npc in ipairs(Layout.npcs) do
		table.insert(clearPoints, point(npc.at, 2))
	end
	for _, marker in ipairs(Layout.markers) do
		table.insert(clearPoints, point(marker.at, 2))
	end
	local tavern: any = nil
	local holes = {}
	for _, entry in ipairs(Layout.blocks) do
		if entry.trapdoor ~= nil then
			tavern = entry
			local t = entry.trapdoor
			local x, z = entry.center[1], entry.center[2]
			table.insert(holes, { x + t.x0, x + t.x1, z + t.z0, z + t.z1 })
			for k = 0, 3 do
				table.insert(clearPoints, Vector3.new(x + (t.x0 + t.x1) / 2, 2, z + t.z0 + (t.z1 - t.z0) * k / 3))
			end
		end
	end
	Furniture.setKeepClear(clearPoints)

	-- the ground and the spawn go in first, so anyone joining while the rest is built lands on solid paving
	Outdoors.ground(Layout, root, holes)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CitySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CFrame = CFrame.new(Layout.spawn.center[1], 0.6, Layout.spawn.center[2])
	spawn.Parent = places
	root.Parent = parent
	Outdoors.roads(Layout, root)
	Outdoors.walls(Layout, root)

	local byDistrict: {[string]: Folder} = {}
	local blocked = obstacleLookup()
	local roofLevel = roofLevels()
	local innByLocation = {}
	for innId, inn in pairs(Content.world.inns) do
		innByLocation[inn.locationId] = innId
		ensureInterior("InnRoom_" .. innId, inn.room[1], inn.room[2], inn.style)
	end
	for _, entry in ipairs(Layout.blocks) do
		local builder = LANDMARKS[entry.use]
		if builder ~= nil then
			builder(entry, landmarks)
		elseif entry.kind == "Tower" then
			Landmarks.tower(entry, landmarks, true)
		else
			local district = entry.district or "City"
			local folder = byDistrict[district] or Kit.folder(districts, district)
			byDistrict[district] = folder
			local cf, W, D = Shell.frameOf(entry)
			local model
			if entry.use == "Ruin" then
				-- a house fallen in: no door, no roof
				model = Kit.model(folder, entry.id)
				Shell.ruin(model, cf, W, D, entry.style or "Slum", entry.seed or 1)
			elseif PUBLIC[entry.use] then
				-- a public building: a real ground-floor room behind an open doorway
				model = Kit.model(folder, entry.id)
				Kit.lightBudget = 1
				Shell.build(model, cf, { W = W, D = D, stories = entry.stories, roof = if W <= 24 then "Gable" else "Eaves", style = entry.style or "Residential", hollow = true, trapdoor = entry.trapdoor, floorHeight = Layout.floorHeight })
				Kit.lightBudget = math.huge
				local innId = innByLocation[entry.locationId]
				if innId ~= nil then
					-- the door to the rented rooms, against the back wall
					local x = roomsDoorX(model, cf, W, D, entry.trapdoor)
					local roomsDoor = Kit.part(model, "RoomsDoor", Vector3.new(5, 8.4, 0.4), cf * CFrame.new(x, 0.6 + 4.2, -D / 2 + 1.2), rgb(84, 58, 38), Enum.Material.WoodPlanks)
					roomsDoor:SetAttribute("InnId", innId)
					roomsDoor:AddTag("InnRooms")
				end
				if entry.propertyId ~= nil then
					local doorX = Shell.doorX(W)
					local face = cf * CFrame.new(doorX, 0.6, D / 2)
					deedSign(properties, entry.propertyId, face, 6, -W / 2 - doorX, W / 2 - doorX, frontOpenings(model, face))
				end
			else
				-- a house: a painted clone of its model (or a shell sized to it), the door leading to its interior
				if entry.template ~= nil then
					local template = houseModel(entry.template)
					model = template:Clone()
					model.Name = entry.id
					model:PivotTo(cf)
					model.Parent = folder
					Kit.count(partCount(template))
				else
					model = Kit.model(folder, entry.id)
					Shell.build(model, cf, { W = W, D = D, stories = entry.stories, roof = if W <= 24 then "Gable" else "Eaves", style = entry.style or "Residential", floorHeight = Layout.floorHeight })
				end
				Shell.paint(model, entry.style or "Residential", entry.seed or 1)
				closeWindows(model, cf, entry, blocked)
				local key = CityBuilder.interiorKey(entry)
				ensureInterior(key, W - 2, D - 2, entry.style, FITTINGS[entry.use])
				local door = model:FindFirstChild("Door", true)
				if door ~= nil and door:IsA("BasePart") then
					door:SetAttribute("HouseId", entry.id)
					door:SetAttribute("Interior", key)
					door:SetAttribute("DisplayName", entry.name or DOOR_NAMES[entry.use] or (if entry.propertyId then "Home" else "House"))
					if entry.propertyId ~= nil then
						door:SetAttribute("PropertyId", entry.propertyId)
						-- the door's middle at its sill, on the front wall
						local face = door.CFrame * CFrame.new(0, -door.Size.Y / 2, 0)
						local doorX = cf:PointToObjectSpace(face.Position).X
						deedSign(properties, entry.propertyId, face, door.Size.X, -W / 2 - doorX, W / 2 - doorX, frontOpenings(model, face))
					end
					door:AddTag("HouseDoor")
				else
					warn("[CityBuilder] house model for " .. entry.id .. " has no part named Door")
				end
			end
			if entry.template ~= nil and entry.style == "Slum" and entry.use ~= "Ruin" then
				Shell.weather(model, cf, W, D, entry.seed or 1)
			end
			if entry.dressing and not entry.shopfront and entry.use ~= "Ruin" and entry.use ~= "GuildHall" then
				Shell.frontDressing(model, cf, W, D, entry.style or "Residential", entry.seed or 1)
			end
			if entry.shopfront and entry.propertyId ~= nil then
				-- a player shop: an awning and a hanging sign on the street; its counter is inside
				local sign = Shell.shopfront(model, cf, W, D, entry.style or "Residential", 5, entry.seed or 1)
				sign:SetAttribute("ShopId", entry.propertyId)
				sign:AddTag("ShopSign")
			end
			sinkRoof(model, roofLevel[entry.id])
			model:SetAttribute("Access", entry.access or "Npc")
			model:SetAttribute("Use", entry.use or "Townhouse")
			if entry.locationId then
				model:SetAttribute("LocationId", entry.locationId)
			end
			if entry.propertyId then
				model:SetAttribute("PropertyId", entry.propertyId)
			end
		end
	end
	Outdoors.estates(Layout, root)
	Outdoors.harbour(Layout, root)
	Outdoors.dressing(Layout, root)
	Outdoors.landmarkYards(Layout, root)
	Forest.build(Layout, root)
	if tavern ~= nil then
		Hideout.build(Layout, root, tavern)
	end

	-- location anchors: one invisible part per located building or yard (the Heart of Realms carries its own)
	for _, entry in ipairs(Layout.blocks) do
		if entry.locationId ~= nil and entry.locationId ~= "HeartOfRealms" then
			local part = anchor(places, entry.locationId, Vector3.new(entry.size[1] - 2, 10, entry.size[2] - 2), CFrame.new(entry.center[1], 5.6, entry.center[2]) * CFrame.Angles(0, math.rad(entry.yaw or 0), 0), rgb(220, 190, 70))
			part:SetAttribute("LocationId", entry.locationId)
		end
	end
	for _, zone in ipairs(Layout.ground) do
		if zone.locationId ~= nil then
			local part = anchor(places, zone.locationId, Vector3.new(zone.size[1], 1, zone.size[2]), CFrame.new(zone.center[1], 0.6, zone.center[2]) * CFrame.Angles(0, math.rad(zone.yaw or 0), 0), rgb(220, 190, 70))
			part:SetAttribute("LocationId", zone.locationId)
		end
	end
	-- NPCs: DialogueService dresses each anchor and gives it a Talk prompt
	local npcFolder = Kit.folder(places, "Npcs")
	for _, placement in ipairs(Layout.npcs) do
		local body = Kit.part(npcFolder, placement.npcId, Vector3.new(2, 5, 1), CFrame.new(placement.at[1], 2.9, placement.at[2]), rgb(230, 120, 60))
		body:SetAttribute("NpcId", placement.npcId)
		if Content.npcs[placement.npcId].opens ~= nil then
			-- an interactive object such as the Heart of Realms: an invisible anchor for its prompt
			body.Transparency = 1
			body.CanCollide = false
			body.CFrame = CFrame.new(placement.at[1], 6, placement.at[2])
		end
		body:AddTag("Npc")
	end
	-- opening markers (L-43)
	local markerFolder = Kit.folder(places, "Markers")
	for _, entry in ipairs(Layout.markers) do
		if entry.kind == "SpawnPoint" then
			local spawnPoint = anchor(markerFolder, entry.id, Vector3.new(4, 1, 4), CFrame.new(entry.at[1], 0.9, entry.at[2]), rgb(230, 120, 60))
			spawnPoint:SetAttribute("SpawnId", entry.spawnId)
			spawnPoint:AddTag("SpawnPoint")
		elseif entry.kind == "RitualCircle" then
			local circle = Kit.part(markerFolder, entry.id, Vector3.new(12, 0.2, 12), CFrame.new(entry.at[1], 0.7, entry.at[2]), rgb(140, 90, 220), Enum.Material.SmoothPlastic, { collide = false, query = false, transparency = 1 })
			circle:AddTag("RitualCircle")
		elseif entry.kind == "StarterChest" then
			local chest = Kit.part(markerFolder, entry.id, Vector3.new(4, 3, 2.5), CFrame.new(entry.at[1], 2.1, entry.at[2]), rgb(120, 82, 46), Enum.Material.WoodPlanks)
			Kit.part(markerFolder, "ChestBand", Vector3.new(4.1, 0.4, 2.6), CFrame.new(entry.at[1], 2.9, entry.at[2]), Kit.colors.iron, Enum.Material.Metal, { collide = false, query = false })
			chest:AddTag("StarterChest")
		end
	end

	-- the road north towards the mountains, the mountains on the horizon, and the edges of the map
	local outer = Kit.folder(root, "OuterRoad")
	local from, to = Layout.outerRoad.from, Layout.outerRoad.to
	local dx, dz = to[1] - from[1], to[2] - from[2]
	local length = math.sqrt(dx * dx + dz * dz)
	Kit.part(outer, "Road", Vector3.new(14, 0.2, length), CFrame.new((from[1] + to[1]) / 2, -0.15, (from[2] + to[2]) / 2) * CFrame.Angles(0, math.atan2(dx, dz), 0), rgb(122, 98, 70), Enum.Material.Ground).CastShadow = false
	local barrier = Kit.frame(outer, CFrame.new(to[1], 0, to[2] + 20))
	barrier:box("Barricade", Vector3.new(20, 3, 1), 0, 2.5, 0, rgb(110, 84, 58), Enum.Material.WoodPlanks)
	local sign = barrier:box("RoadSign", Vector3.new(6, 2.4, 0.3), 0, 5.6, 0.8, rgb(90, 64, 40), Enum.Material.WoodPlanks, { collide = false, query = false })
	Kit.sign(sign, Enum.NormalId.Back, "Northern Mountains - road closed by rockfall")
	for index = 0, 8 do
		local x = -700 + index * 180
		local h = 160 + (index * 53) % 120
		local m = Kit.frame(outer, CFrame.new(x, -2, -1180 - (index % 3) * 40))
		m:wedgeAt("Mountain", Vector3.new(170, h, 120), CFrame.new(0, h / 2, 60) * CFrame.Angles(0, math.pi, 0), rgb(120, 118, 116), Enum.Material.Rock, { collide = false, query = false })
		m:wedgeAt("Mountain", Vector3.new(170, h, 120), CFrame.new(0, h / 2, -60), rgb(110, 108, 106), Enum.Material.Rock, { collide = false, query = false })
		m:wedgeAt("SnowCap", Vector3.new(60, h * 0.25, 39), CFrame.new(0, h * 0.88, 20.5) * CFrame.Angles(0, math.pi, 0), rgb(240, 242, 246), Enum.Material.Snow, { collide = false, query = false })
	end
	local edges = Kit.folder(root, "Boundaries")
	local water = Layout.water[1]
	local seaX0 = water.center[1] - water.size[1] / 2
	boundary(edges, -760, -1120, -760, 340)
	boundary(edges, -760, -1120, 760, -1120)
	boundary(edges, 760, -1120, 760, water.center[2] - water.size[2] / 2)
	boundary(edges, 900, water.center[2] - water.size[2] / 2, 900, 340)
	boundary(edges, Layout.forest.bounds.maxX, 340, 900, 340)
	boundary(edges, -760, 340, Layout.forest.bounds.minX, 340)
	boundary(edges, 760, water.center[2] - water.size[2] / 2, 900, water.center[2] - water.size[2] / 2)
	local _ = seaX0

	-- what the city really holds (cloned houses never pass through Kit.part, and templates live in ServerStorage)
	local parts, lights = 0, 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then
			parts += 1
		elseif item:IsA("Light") then
			lights += 1
		end
	end
	root:SetAttribute("Parts", parts)
	root:SetAttribute("Lights", lights)
	root:SetAttribute("BuildSeconds", math.floor((os.clock() - started) * 100) / 100)
	Kit.setYield(0, nil)
	print(string.format("[CityBuilder] built %d parts, %d lights in %.1fs", parts, lights, os.clock() - started))
	return root
end

return CityBuilder
