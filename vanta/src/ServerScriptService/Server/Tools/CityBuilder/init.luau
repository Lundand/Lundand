--!strict
-- Builds the capital from ServerData.CityLayout (L-27): ground and roads, city walls and gates, every building with
-- its interior, the castle and its library, the church, the harbour, the forest beyond the south gate and the
-- thieves' hideout under the slums. Places carry LocationId / PropertyId attributes, so gameplay finds them by ID,
-- never by name or hierarchy; NPC anchors, markers, property signs and access volumes are tagged as before.
--
-- The server builds the city at start when Workspace has none (Server/Main). To keep it in the place instead, run
-- in Studio edit mode (for example through the MCP server's execute_luau) and save:
--   require(game.ServerScriptService.Server.Tools.CityBuilder).build()
-- Rebuilding replaces Workspace.City, so change the layout data rather than editing the parts.
local ServerStorage = game:GetService("ServerStorage")
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)

local Kit = require(script.Kit)
local Furniture = require(script.Furniture)
local House = require(script.House)
local Landmarks = require(script.Landmarks)
local Outdoors = require(script.Outdoors)
local Forest = require(script.Forest)
local Hideout = require(script.Hideout)

local CityBuilder = {}
local rgb = Kit.rgb

export type Options = { yield: boolean?, parent: Instance? }

local LANDMARKS: {[string]: (any, Instance) -> Model} = {
	Fountain = Landmarks.fountain,
	Church = Landmarks.church,
	Keep = Landmarks.keep,
	Library = Landmarks.library,
	CastleWall = Landmarks.castleWall,
	Gatehouse = Landmarks.castleGatehouse,
	FishMarket = Landmarks.fishMarket,
}

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
			House.build(entry, Layout, folder, properties)
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

	-- location anchors: one invisible part per located building or yard (the fountain's crystal is its own)
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
	-- guild halls: a planning table in each hall's main room (L-54)
	for _, entry in ipairs(Layout.blocks) do
		if entry.use == "GuildHall" then
			local planning = Kit.part(markerFolder, entry.id .. "Table", Vector3.new(8, 3, 4), CFrame.new(entry.center[1], 2.1, entry.center[2]), rgb(120, 86, 56), Enum.Material.WoodPlanks)
			planning:SetAttribute("PropertyId", entry.propertyId)
			planning:AddTag("PlanningTable")
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
		m:wedgeAt("SnowCap", Vector3.new(60, h * 0.25, 40), CFrame.new(0, h * 0.88, 20) * CFrame.Angles(0, math.pi, 0), rgb(240, 242, 246), Enum.Material.Snow, { collide = false, query = false })
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

	root:SetAttribute("Parts", Kit.stats.parts)
	root:SetAttribute("Lights", Kit.stats.lights)
	root:SetAttribute("BuildSeconds", math.floor((os.clock() - started) * 100) / 100)
	Kit.setYield(0, nil)
	print(string.format("[CityBuilder] built %d parts, %d lights in %.1fs", Kit.stats.parts, Kit.stats.lights, os.clock() - started))
	return root
end

return CityBuilder
