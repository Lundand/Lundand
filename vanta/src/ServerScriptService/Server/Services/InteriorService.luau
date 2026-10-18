--!strict
-- Instanced interiors (houses and inn rooms). A house's door (a part tagged HouseDoor) takes you to that house's room,
-- built far above the map from ServerStorage.CityAssets.Interiors only while someone is in it; everyone in the same
-- house shares one room. An inn room (RentalService) is one room per renter. The room's ExitDoor brings you back out.
-- Ownership decides who gets in: an unowned house can be looked round by anyone, an owned one only by those its owner
-- allows (checked at the door, and again whenever the owner changes who may enter). A room nobody is in is removed.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Server = script.Parent.Parent
local InteriorSlots = require(Server.Domain.InteriorSlots)
local PropertyAccess = require(Server.Domain.PropertyAccess)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)

local InteriorService = {}
local services: any = nil
local limiter = RateLimiter.new(3, 2, os.clock)

local DOOR_REACH = 14
local IDLE_SECONDS = 30
local SWEEP_SECONDS = 1

type Instance_ = { key: string, model: Model, origin: CFrame, exit: CFrame, propertyId: string?, size: Vector3 }

local slots = InteriorSlots.new(256)
local interiors: {[string]: Instance_} = {}
local occupants: {[Player]: string} = {}
local enteredAt: {[Player]: number} = {}
local ARRIVAL_GRACE = 4 -- seconds a teleport may take to land (streaming) before the sweep checks where you are
local folder: Folder? = nil

function InteriorService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function templateFor(key: string): Model?
	local assets = ServerStorage:FindFirstChild("CityAssets")
	local rooms = assets and assets:FindFirstChild("Interiors")
	local template = rooms and rooms:FindFirstChild(key)
	if template ~= nil and template:IsA("Model") then
		return template
	end
	return nil
end

-- Where you come out: in front of a door, facing away from it (a part's front is -z, so the street is +z).
local function outsideOf(door: BasePart): CFrame
	local out = door.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local feet = door.Position - Vector3.new(0, door.Size.Y / 2, 0)
	local spot = feet + out * 4 + Vector3.new(0, 3, 0)
	return CFrame.lookAt(spot, spot + out)
end

local function inside(interior: Instance_, position: Vector3): boolean
	local offset = interior.origin:PointToObjectSpace(position)
	local half = interior.size / 2
	return math.abs(offset.X) <= half.X + 4 and offset.Y >= -6 and offset.Y <= interior.size.Y + 6 and math.abs(offset.Z) <= half.Z + 4
end

local function moveTo(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	character:PivotTo(cf)
end

-- Builds (or finds) the room for `key` and returns it; nil when no room can be made right now.
local function open(key: string, templateKey: string, exit: CFrame, propertyId: string?): Instance_?
	local existing = interiors[key]
	if existing ~= nil and existing.model.Parent ~= nil then
		InteriorSlots.touch(slots, key, os.clock())
		return existing
	end
	local template = templateFor(templateKey)
	if not template then
		warn("[InteriorService] no interior model " .. templateKey)
		return nil
	end
	local slot = InteriorSlots.acquire(slots, key, os.clock())
	if not slot then
		return nil
	end
	local config = Layout.interiors
	local x, y, z = InteriorSlots.position(slot, config.origin, config.spacing, config.perRow)
	local model = template:Clone()
	model.Name = key
	local origin = CFrame.new(x, y, z)
	model:PivotTo(origin)
	local _, size = model:GetBoundingBox()
	local exitDoor = model:FindFirstChild("ExitDoor", true)
	if exitDoor ~= nil and exitDoor:IsA("BasePart") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Leave"
		prompt.ObjectText = "Door"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = exitDoor
		prompt.Triggered:Connect(function(player: Player)
			if occupants[player] == key then
				InteriorService.leave(player)
			end
		end)
	end
	model.Parent = folder
	local interior: Instance_ = { key = key, model = model, origin = origin, exit = exit, propertyId = propertyId, size = size }
	interiors[key] = interior
	return interior
end

local function enter(player: Player, interior: Instance_)
	local entry = interior.model:FindFirstChild("Entry", true)
	local spot = if entry ~= nil and entry:IsA("BasePart") then entry.CFrame + Vector3.new(0, 3, 0) else interior.origin + Vector3.new(0, 4, 0)
	occupants[player] = interior.key
	enteredAt[player] = os.clock()
	moveTo(player, spot)
end

-- May this player go into this property? An unreadable deed keeps the door shut rather than guessing.
local function mayEnter(player: Player, propertyId: string): (boolean, string?)
	local readable, record = services.SharedRecordService.store("Properties"):read(propertyId)
	if not readable then
		return false, "The door won't open right now. Try again shortly."
	end
	if record == nil or record.owner == nil then
		return true, nil
	end
	local isFriend = false
	if record.permissions ~= nil and record.permissions.mode == "Friends" and record.owner.userId ~= player.UserId then
		local ok, result = pcall(function()
			return player:IsFriendsWith(record.owner.userId)
		end)
		isFriend = ok and result == true
	end
	if PropertyAccess.shouldEject(record, player.UserId, isFriend) then
		return false, "That home belongs to " .. tostring(record.owner.name) .. ". The door is locked."
	end
	return true, nil
end

local function enterHouse(player: Player, door: BasePart)
	local root = rootOf(player)
	if root == nil or not limiter:allow(player) or (root.Position - door.Position).Magnitude > DOOR_REACH then
		return
	end
	local houseId, templateKey = door:GetAttribute("HouseId"), door:GetAttribute("Interior")
	if type(houseId) ~= "string" or type(templateKey) ~= "string" then
		return
	end
	local attribute = door:GetAttribute("PropertyId")
	local propertyId: string? = if type(attribute) == "string" then attribute else nil
	if propertyId then
		local allowed, reason = mayEnter(player, propertyId)
		if not allowed then
			notify(player, reason or "The door is locked.")
			return
		end
	end
	local interior = open("house:" .. (houseId :: string), templateKey :: string, outsideOf(door), propertyId)
	if not interior then
		notify(player, "The door is stuck. Try again in a moment.")
		return
	end
	enter(player, interior)
end

-- Takes a renter to their own room at an inn (RentalService checks the rental first).
function InteriorService.enterRoom(player: Player, innId: string, door: BasePart)
	local interior = open("room:" .. innId .. ":" .. player.UserId, "InnRoom_" .. innId, outsideOf(door), nil)
	if not interior then
		notify(player, "Every room is taken right now. Try again in a moment.")
		return
	end
	enter(player, interior)
end

function InteriorService.leave(player: Player)
	local key = occupants[player]
	occupants[player] = nil
	local interior = key and interiors[key]
	if interior ~= nil then
		InteriorSlots.touch(slots, interior.key, os.clock())
		moveTo(player, interior.exit)
	end
end

function InteriorService.isInside(player: Player): boolean
	return occupants[player] ~= nil
end

-- After an owner changes who may come in: anyone inside who no longer may is shown out.
function InteriorService.recheck(propertyId: string)
	for player, key in pairs(occupants) do
		local interior = interiors[key]
		if interior ~= nil and interior.propertyId == propertyId then
			local allowed = mayEnter(player, propertyId)
			if not allowed then
				InteriorService.leave(player)
				notify(player, "The owner has closed this home to visitors.")
			end
		end
	end
end

local function setupDoor(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild("EnterPrompt") then
		return
	end
	local door = instance :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Enter"
	local name = door:GetAttribute("DisplayName")
	prompt.ObjectText = if type(name) == "string" then name else "House"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player: Player)
		enterHouse(player, door)
	end)
end

-- Keeps the bookkeeping honest: people who left by dying or respawning are no longer inside, anyone found in a room
-- they didn't come in by the door is sent back out, and rooms nobody is in are taken down.
local function sweep()
	local occupied = {}
	for player, key in pairs(occupants) do
		local interior = interiors[key]
		local root = rootOf(player)
		local arriving = os.clock() - (enteredAt[player] or 0) < ARRIVAL_GRACE
		if interior == nil or (not arriving and (root == nil or not inside(interior, root.Position))) then
			occupants[player] = nil
		else
			occupied[key] = true
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root ~= nil and occupants[player] == nil and root.Position.Y > Layout.interiors.origin[2] - 50 then
			for _, interior in pairs(interiors) do
				if inside(interior, root.Position) then
					moveTo(player, interior.exit)
					break
				end
			end
		end
	end
	for _, key in ipairs(InteriorSlots.sweep(slots, occupied, os.clock(), IDLE_SECONDS)) do
		local interior = interiors[key]
		interiors[key] = nil
		if interior ~= nil then
			interior.model:Destroy()
		end
	end
end

function InteriorService.start()
	local f = Instance.new("Folder")
	f.Name = "Interiors"
	f.Parent = workspace
	folder = f
	for _, door in ipairs(CollectionService:GetTagged("HouseDoor")) do
		setupDoor(door)
	end
	CollectionService:GetInstanceAddedSignal("HouseDoor"):Connect(setupDoor)
	task.spawn(function()
		while true do
			task.wait(SWEEP_SECONDS)
			local ok, err = pcall(sweep :: () -> any)
			if not ok then
				warn("[InteriorService] sweep failed: " .. tostring(err))
			end
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		occupants[player] = nil
		enteredAt[player] = nil
		limiter:forget(player)
	end)
end

return InteriorService
