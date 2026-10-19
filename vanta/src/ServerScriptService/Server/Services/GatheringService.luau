--!strict
-- Physical resource nodes (L-11). Builders tag node models or parts "ResourceNode" and set the
-- NodeType attribute (an ID in ServerData.ResourceNodes) and a unique NodeId attribute. A
-- ProximityPrompt is the placeholder Hold interaction; every rule is checked on the server.
-- Known limitation: the prompt always uses the base hold time, so faster gathering from levels and
-- tools is accepted by the server but not yet shown on the client.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Gathering = require(Server.Domain.Gathering)
local RateLimiter = require(Server.Net.RateLimiter)
local Remotes = require(Server.Net.Remotes)
local ResourceNodes = require(ServerStorage:WaitForChild("ServerData").ResourceNodes)

local TAG = "ResourceNode"
local HOLD_TOLERANCE = 0.85 -- allows for network delay when checking how long the prompt was held
local DISTANCE_MARGIN = 4

local GatheringService = {}
local services: any = nil
local nodeStates: {[Instance]: any} = {}
local holdStarts: {[Player]: {[Instance]: number}} = {}
local random = Random.new()
local limiter = RateLimiter.new(4, 1, os.clock)

function GatheringService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function nodePosition(instance: Instance): Vector3?
	local point = instance:FindFirstChild("GatherPoint", true)
	if point ~= nil and point:IsA("Attachment") then
		return point.WorldPosition -- near the base, where the prompt is (tall trees)
	end
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function nodeId(instance: Instance): string
	local id = instance:GetAttribute("NodeId")
	if type(id) == "string" and id ~= "" then
		return id
	end
	return instance:GetFullName()
end

local function onTriggered(instance: Instance, node: any, player: Player)
	if player.Character ~= nil then
		player.Character:SetAttribute("GatherNode", nil)
	end
	if not limiter:allow(player) then
		return
	end
	local starts = holdStarts[player]
	local startedAt = starts and starts[instance]
	if starts then
		starts[instance] = nil
	end
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local position = nodePosition(instance)
	if root == nil or position == nil or (root.Position - position).Magnitude > node.maxDistance + DISTANCE_MARGIN then
		return
	end
	local toolTier = 0
	if node.tool then
		toolTier = Gathering.bestToolTier(character.inventory, Content.items, node.tool.toolType)
	end
	local professionLevel = services.ProgressionService.professionLevel(player, node.profession)
	local allowed, reason = Gathering.check(node, toolTier, professionLevel)
	if not allowed then
		notify(player, "Can't gather: " .. tostring(reason))
		return
	end
	if startedAt == nil or os.clock() - startedAt < Gathering.duration(node, toolTier, professionLevel) * HOLD_TOLERANCE then
		return
	end
	local now = os.time()
	local id = nodeId(instance)
	local userKey = tostring(player.UserId)
	local state = nodeStates[instance]
	local readyAt = Gathering.readyAt(state, node, userKey, character.nodeCooldowns[id])
	if readyAt > now then
		notify(player, string.format("%s respawns in %d seconds", node.displayName, readyAt - now))
		return
	end
	local drops = Gathering.rollDrops(node, function()
		return random:NextNumber()
	end)
	local changes = {}
	for _, drop in ipairs(drops) do
		table.insert(changes, { type = "GrantStack", itemId = drop.itemId, amount = drop.amount })
	end
	if #changes > 0 then
		local granted, err = services.InventoryService.apply(player, "Gather", changes)
		if not granted then
			notify(player, "Can't gather: " .. tostring(err)) -- for example a full inventory; no cooldown used
			return
		end
	end
	local nextReady = Gathering.markGathered(state, node, userKey, now)
	if node.respawn.persist then
		local current = services.PlayerDataService.getCharacter(player)
		if current then
			current.nodeCooldowns[id] = nextReady
		end
	end
	services.ProgressionService.grantProfessionXp(player, node.profession, node.professionXp)
	for _, drop in ipairs(drops) do
		local def = Content.items[drop.itemId]
		notify(player, string.format("+%d %s", drop.amount, (def and def.displayName) or drop.itemId))
		services.QuestService.reportEvent(player, { kind = "Gather", target = drop.itemId, amount = drop.amount })
	end
	if instance:GetAttribute("AreaId") ~= nil then
		GatheringService.harvested(instance)
	end
end

local function setupNode(instance: Instance)
	if nodeStates[instance] then
		return
	end
	local nodeType = instance:GetAttribute("NodeType")
	local node = type(nodeType) == "string" and ResourceNodes[nodeType]
	if not node then
		warn("[Gathering] " .. instance:GetFullName() .. " has an unknown NodeType: " .. tostring(nodeType))
		return
	end
	local anchor: any = instance
	if instance:IsA("Model") then
		anchor = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	if anchor == nil or not anchor:IsA("BasePart") then
		warn("[Gathering] " .. instance:GetFullName() .. " needs a part for its prompt")
		return
	end
	nodeStates[instance] = Gathering.newNodeState()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GatherPrompt"
	prompt.ActionText = "Gather"
	prompt.ObjectText = node.displayName
	prompt.HoldDuration = node.baseDuration
	prompt.MaxActivationDistance = node.maxDistance
	prompt.RequiresLineOfSight = false
	local point = Instance.new("Attachment")
	point.Name = "GatherPoint"
	point.Position = Vector3.new(0, math.min(0, -anchor.Size.Y / 2 + 2.5), 0)
	point.Parent = anchor
	prompt.Parent = point
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local starts = holdStarts[player]
		if starts == nil then
			starts = {}
			holdStarts[player] = starts
		end
		starts[instance] = os.clock()
		-- presentation only: every client shows the gathering animation while the prompt is held (and the player has the tool)
		local gatherer = player.Character
		local data = services.PlayerDataService.getCharacter(player)
		if gatherer ~= nil and data ~= nil and (node.tool == nil or Gathering.bestToolTier(data.inventory, Content.items, node.tool.toolType) > 0) then
			-- which tool to show: the player's best one of the right type (its item id picks the model)
			local toolItem, toolTier = nil, 0
			if node.tool ~= nil then
				for _, unique in pairs(data.inventory.uniques) do
					local def = Content.items[unique.itemId]
					if def ~= nil and def.kind == "Tool" and def.tool.toolType == node.tool.toolType and def.tool.toolTier > toolTier then
						toolItem, toolTier = unique.itemId, def.tool.toolTier
					end
				end
			end
			gatherer:SetAttribute("GatherToolItem", toolItem)
			gatherer:SetAttribute("GatherNode", nodeType)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		if player.Character ~= nil then
			player.Character:SetAttribute("GatherNode", nil)
		end
	end)
	prompt.Triggered:Connect(function(player: Player)
		onTriggered(instance, node, player)
	end)
end

-- Gathering areas (ServerData.GatheringAreas): spots grow at random places in each area's zone; a gathered spot
-- disappears for everyone and regrows elsewhere in the area after a random delay.
local HttpService = game:GetService("HttpService")
local GatheringAreas = require(game:GetService("ServerStorage"):WaitForChild("ServerData"):WaitForChild("GatheringAreas"))
local areaRandom = Random.new()

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Placeholder looks for each kind of spot, standing on `ground`.
local function buildNode(nodeType: string, ground: Vector3): Model
	local model = Instance.new("Model")
	model.Name = nodeType
	local base = CFrame.new(ground) * CFrame.Angles(0, areaRandom:NextNumber(0, math.pi * 2), 0)
	-- a mesh model from the asset library (ReplicatedStorage.Assets.ResourceNodes.<nodeType>) when there is one; its pivot is its base
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild("ResourceNodes")
	local asset = library and library:FindFirstChild(nodeType)
	if asset ~= nil and asset:IsA("Model") then
		local fromLibrary = asset:Clone()
		fromLibrary.Name = nodeType
		fromLibrary:PivotTo(base)
		return fromLibrary
	end
	local main
	if nodeType == "OakTree" then
		local height = areaRandom:NextNumber(14, 20)
		main = part(model, "Trunk", Vector3.new(2.4, height, 2.4), base * CFrame.new(0, height / 2, 0), Color3.fromRGB(92, 64, 44), Enum.Material.Wood)
		part(model, "Leaves", Vector3.new(12, 10, 12), base * CFrame.new(0, height + 3, 0), Color3.fromRGB(58, 100, 52), Enum.Material.Grass, Enum.PartType.Ball)
	elseif nodeType == "HealingHerbPatch" then
		main = part(model, "Herb", Vector3.new(2.4, 1.4, 2.4), base * CFrame.new(0, 0.6, 0), Color3.fromRGB(96, 168, 92), Enum.Material.Grass, Enum.PartType.Ball)
	elseif nodeType == "IronVein" then
		main = part(model, "Rock", Vector3.new(6, 3.6, 5), base * CFrame.new(0, 1.6, 0), Color3.fromRGB(120, 118, 124), Enum.Material.Slate)
	else
		main = part(model, "Rock", Vector3.new(5, 3.2, 4), base * CFrame.new(0, 1.4, 0), Color3.fromRGB(176, 112, 76), Enum.Material.Slate)
	end
	model.PrimaryPart = main
	return model
end

local function groundPoint(zone: BasePart, avoid: {Vector3}): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { zone }
	for _, name in ipairs({ "GatheringNodes", "Enemies" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	params.FilterDescendantsInstances = exclude
	for _ = 1, 12 do
		local offset = Vector3.new(areaRandom:NextNumber(-0.45, 0.45) * zone.Size.X, zone.Size.Y / 2, areaRandom:NextNumber(-0.45, 0.45) * zone.Size.Z)
		local top = zone.CFrame:PointToWorldSpace(offset)
		local hit = workspace:Raycast(top + Vector3.new(0, 5, 0), Vector3.new(0, -60, 0), params)
		if hit ~= nil and hit.Instance.CanCollide and hit.Instance.Name ~= "Trunk" and hit.Instance.Name ~= "Leaves" then
			local clear = true
			for _, other in ipairs(avoid) do
				if (Vector3.new(other.X, 0, other.Z) - Vector3.new(hit.Position.X, 0, hit.Position.Z)).Magnitude < 8 then
					clear = false
					break
				end
			end
			if clear then
				return hit.Position
			end
		end
	end
	return nil
end

local function zoneOf(locationId: string): BasePart?
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("LocationId") == locationId then
			return instance
		end
	end
	return nil
end

local function growInArea(areaId: string)
	local area = GatheringAreas[areaId]
	local zone = area and zoneOf(area.locationId)
	if zone == nil then
		return
	end
	local folder = workspace:FindFirstChild("GatheringNodes")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "GatheringNodes"
		folder.Parent = workspace
	end
	local taken = {}
	for _, other in ipairs(folder:GetChildren()) do
		if other:IsA("Model") then
			table.insert(taken, other:GetPivot().Position)
		end
	end
	local ground = groundPoint(zone, taken)
	if ground == nil then
		task.delay(10, growInArea, areaId) -- no room right now; try again shortly
		return
	end
	local model = buildNode(area.nodeType, ground)
	model:SetAttribute("NodeType", area.nodeType)
	model:SetAttribute("AreaId", areaId)
	model:SetAttribute("NodeId", HttpService:GenerateGUID(false))
	model.Parent = folder
	CollectionService:AddTag(model, TAG)
end

-- A gathered spot disappears for everyone; a new one grows somewhere in its area after a random delay.
function GatheringService.harvested(instance: Instance)
	local areaId = instance:GetAttribute("AreaId")
	instance:Destroy()
	local area = type(areaId) == "string" and GatheringAreas[areaId]
	if area then
		task.delay(areaRandom:NextNumber(area.respawnSeconds[1], area.respawnSeconds[2]), growInArea, areaId)
	end
end

local function startAreas()
	for areaId, area in pairs(GatheringAreas) do
		for _ = 1, area.count do
			growInArea(areaId)
		end
	end
end

function GatheringService.start()
	task.defer(startAreas)
	for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
		setupNode(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(setupNode)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		nodeStates[instance] = nil
	end)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		local character = services.PlayerDataService.getCharacter(player)
		if character then
			Gathering.pruneCooldowns(character.nodeCooldowns, os.time())
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		holdStarts[player] = nil
		limiter:forget(player)
	end)
end

return GatheringService
