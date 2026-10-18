--!strict
-- Instanced interiors (houses and inn rooms). A house's door (a part tagged HouseDoor) takes you to that house's room,
-- built far above the map from ServerStorage.CityAssets.Interiors only while someone is in it; everyone in the same
-- house shares one room. An inn room (RentalService) is one room per renter. The room's ExitDoor brings you back out.
-- Ownership decides who gets in: an unowned house can be looked round by anyone, an owned one only by those its owner
-- allows; a shop lets in every customer, and a guild's hall the guild's members. That is checked at the door, again for everyone inside whenever the owner changes who may enter or the
-- house is bought, and every few seconds besides (deeds also change on other servers). A room nobody is in is
-- removed after a while.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Server = script.Parent.Parent
local InteriorSlots = require(Server.Domain.InteriorSlots)
local PropertyAccess = require(Server.Domain.PropertyAccess)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)
local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)

local InteriorService = {}
local services: any = nil
local limiter = RateLimiter.new(3, 2, os.clock)

local DOOR_REACH = 14
local IDLE_SECONDS = 30
local SWEEP_SECONDS = 1
local ACCESS_SECONDS = 5 -- how often everyone inside an owned home is checked against its deed
local FRIEND_SECONDS = 120 -- how long a friendship answer is trusted
local ARRIVAL_GRACE = 3 -- seconds after landing in a room before the sweep checks where you are (replication lag)
local EXIT_DISTANCE = 3 -- how far in front of a door you come out (lanes by the city wall are 4 wide)
local MAX_SLOTS = 256

type Interior = { key: string, model: Model, center: CFrame, size: Vector3, exit: CFrame, propertyId: string? }

local slots = InteriorSlots.new(MAX_SLOTS)
local interiors: {[string]: Interior} = {}
local occupants: {[Player]: string} = {}
local arrivedAt: {[Player]: number} = {} -- when the move into the current room landed
local moves: {[Player]: number} = {} -- the latest move's number; a move only lands if no later one has started
local moving: {[Player]: boolean} = {}
local friends: {[Player]: {[number]: { value: boolean, at: number }}} = {}
local folder: Folder? = nil

function InteriorService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function properties(): any
	return services.SharedRecordService.store("Properties")
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
	local spot = feet + out * EXIT_DISTANCE + Vector3.new(0, 3, 0)
	return CFrame.lookAt(spot, spot + out)
end

-- Is a point inside a room (its bounding box, with a little to spare)?
local function inside(interior: Interior, position: Vector3): boolean
	local offset = interior.center:PointToObjectSpace(position)
	local half = interior.size / 2
	return math.abs(offset.X) <= half.X + 4 and math.abs(offset.Y) <= half.Y + 6 and math.abs(offset.Z) <= half.Z + 4
end

-- The room a point is in, if any (rooms sit on a grid, so this is one lookup).
local function roomAt(position: Vector3): Interior?
	local config = Layout.interiors
	if position.Y < config.origin[2] - 50 then
		return nil
	end
	local slot = InteriorSlots.slotAt(position.X, position.Z, config.origin, config.spacing, config.perRow, MAX_SLOTS)
	local key = if slot ~= nil then InteriorSlots.keyAt(slots, slot) else nil
	local interior = if key ~= nil then interiors[key] else nil
	if interior ~= nil and inside(interior, position) then
		return interior
	end
	return nil
end

-- Streams the spot in for the player, then moves their character there. Returns whether the move landed: a later
-- move (another door, the way out) takes over from one still waiting for streaming.
local function moveTo(player: Player, cf: CFrame): boolean
	local number = (moves[player] or 0) + 1
	moves[player] = number
	moving[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	if moves[player] ~= number then
		return false
	end
	moving[player] = nil
	if player.Parent == nil then
		-- left the game while the room streamed in
		moves[player] = nil
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	character:PivotTo(cf)
	return true
end

local function destroy(key: string)
	local interior = interiors[key]
	interiors[key] = nil
	if interior ~= nil then
		interior.model:Destroy()
	end
end

-- The rooms someone is in, is on their way into, or is standing in.
local function inUse(): {[string]: boolean}
	local keys = {}
	for _, key in pairs(occupants) do
		keys[key] = true
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local interior = if root ~= nil then roomAt(root.Position) else nil
		if interior ~= nil then
			keys[interior.key] = true
		end
	end
	return keys
end

-- Builds (or finds) the room for `key` and returns it; nil when no room can be made right now.
local function open(key: string, templateKey: string, exit: CFrame, propertyId: string?): Interior?
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
		-- every slot is taken: hand on the room that has stood empty longest
		local evicted = InteriorSlots.evictOldest(slots, inUse())
		if evicted ~= nil then
			destroy(evicted)
			slot = InteriorSlots.acquire(slots, key, os.clock())
		end
	end
	if not slot then
		return nil
	end
	local config = Layout.interiors
	local x, y, z = InteriorSlots.position(slot, config.origin, config.spacing, config.perRow)
	local model = template:Clone()
	model.Name = key
	model:PivotTo(CFrame.new(x, y, z))
	-- measure where the room really is: a model saved with a PrimaryPart pivots on that part, not on its floor
	local center, size = model:GetBoundingBox()
	-- a shop's counter and a hall's planning table belong to this building (ShopService and GuildService wire them up
	-- as the room appears)
	for _, part in ipairs(model:GetDescendants()) do
		if part.Name == "ShopCounter" or part.Name == "PlanningTable" then
			part:SetAttribute(if part.Name == "ShopCounter" then "ShopId" else "PropertyId", propertyId)
		end
	end
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
	local interior: Interior = { key = key, model = model, center = center, size = size, exit = exit, propertyId = propertyId }
	interiors[key] = interior
	return interior
end

local function enter(player: Player, interior: Interior)
	local entry = interior.model:FindFirstChild("Entry", true)
	local spot = if entry ~= nil and entry:IsA("BasePart") then entry.CFrame + Vector3.new(0, 3, 0) else interior.center
	occupants[player] = interior.key
	arrivedAt[player] = nil
	if moveTo(player, spot) and occupants[player] == interior.key then
		arrivedAt[player] = os.clock()
	end
end

-- Is this player a friend of that owner? With `ask`, asks Roblox and waits for the answer (nil if it fails);
-- otherwise answers from what is known (nil if nothing is) and refreshes it in the background.
local function friendOf(player: Player, ownerId: number, ask: boolean): boolean?
	if player.Parent == nil then
		return nil
	end
	local known = friends[player]
	if known == nil then
		known = {}
		friends[player] = known
	end
	local cached = known[ownerId]
	if cached ~= nil and os.clock() - cached.at < FRIEND_SECONDS then
		return cached.value
	end
	local function lookup(): boolean?
		local ok, result = pcall(function()
			return player:IsFriendsWith(ownerId)
		end)
		if not ok then
			return nil
		end
		if friends[player] ~= nil then
			friends[player][ownerId] = { value = result == true, at = os.clock() }
		end
		return result == true
	end
	if ask then
		return lookup()
	end
	task.spawn(lookup)
	return if cached ~= nil then cached.value else nil
end

-- May this player be in this property? At the door, an unreadable deed or an unanswered friendship keeps the door
-- shut; for someone already inside, not knowing never turns them out.
local function allowed(player: Player, propertyId: string, atDoor: boolean): (boolean, string?)
	local kind = Content.world.properties[propertyId] and Content.world.properties[propertyId].kind
	if kind == "Shop" then
		-- a shop is open to every customer
		return true, nil
	end
	local readable, record = properties():read(propertyId)
	if not readable then
		return not atDoor, "The door won't open right now. Try again shortly."
	end
	if record == nil or record.owner == nil then
		return true, nil
	end
	if kind == "GuildHall" then
		-- a guild's hall: its members only
		local data = services.PlayerDataService.getData(player)
		local guildId = data and data.account.guild.id
		if guildId ~= nil and guildId == record.owner.guildId then
			return true, nil
		end
		return false, "That hall belongs to " .. tostring(record.owner.name) .. ". Only its members may enter."
	end
	local isFriend: boolean? = false
	if record.permissions ~= nil and record.permissions.mode == "Friends" and record.owner.userId ~= player.UserId then
		isFriend = friendOf(player, record.owner.userId, atDoor)
		if atDoor and isFriend == nil then
			isFriend = false
		end
	end
	if PropertyAccess.shouldEject(record, player.UserId, isFriend) then
		return false, "That building belongs to " .. tostring(record.owner.name) .. ". The door is locked."
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
		local before = moves[player]
		local ok, reason = allowed(player, propertyId, true)
		if not ok then
			notify(player, reason or "The door is locked.")
			return
		end
		-- the check can take a moment: go in only if the player is still at this door and hasn't gone elsewhere
		local again = rootOf(player)
		if again == nil or (again.Position - door.Position).Magnitude > DOOR_REACH or occupants[player] ~= nil or moves[player] ~= before then
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

-- Shows a player out of the room they are in (without waiting for the move).
function InteriorService.leave(player: Player)
	local key = occupants[player]
	occupants[player] = nil
	arrivedAt[player] = nil
	local interior = if key ~= nil then interiors[key] else nil
	if interior ~= nil then
		InteriorSlots.touch(slots, interior.key, os.clock())
		task.spawn(moveTo, player, interior.exit)
	end
end

function InteriorService.isInside(player: Player): boolean
	return occupants[player] ~= nil
end

-- Shows out everyone inside an owned home who may no longer be there: in one home, or (propertyId nil) in all.
local function showOut(propertyId: string?)
	-- the list first: the checks below can wait on the deed store and on Roblox
	local list = {}
	for player, key in pairs(occupants) do
		local interior = interiors[key]
		if interior ~= nil and interior.propertyId ~= nil and (propertyId == nil or interior.propertyId == propertyId) then
			table.insert(list, { player = player, key = key, propertyId = interior.propertyId :: string })
		end
	end
	for _, item in ipairs(list) do
		if occupants[item.player] == item.key then
			local ok = allowed(item.player, item.propertyId, false)
			if not ok and occupants[item.player] == item.key then
				InteriorService.leave(item.player)
				notify(item.player, "This home is closed to visitors now.")
			end
		end
	end
end

-- After an owner changes who may come in, or the house is bought: anyone inside who no longer may is shown out.
function InteriorService.recheck(propertyId: string)
	showOut(propertyId)
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
-- that isn't theirs is sent out to that room's street, and rooms nobody is in are taken down. Never waits.
local function sweep()
	local occupied = {}
	local now = os.clock()
	for player, key in pairs(occupants) do
		local interior = interiors[key]
		local root = rootOf(player)
		local landed = arrivedAt[player]
		if interior == nil then
			occupants[player] = nil
		elseif moving[player] or (landed ~= nil and now - landed < ARRIVAL_GRACE) then
			occupied[key] = true
		elseif landed == nil or root == nil or not inside(interior, root.Position) then
			occupants[player] = nil
			arrivedAt[player] = nil
		else
			occupied[key] = true
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local interior = if root ~= nil then roomAt(root.Position) else nil
		if interior ~= nil and not moving[player] and occupants[player] ~= interior.key then
			occupants[player] = nil
			arrivedAt[player] = nil
			occupied[interior.key] = true
			task.spawn(moveTo, player, interior.exit)
		end
	end
	for _, key in ipairs(InteriorSlots.sweep(slots, occupied, now, IDLE_SECONDS)) do
		destroy(key)
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
	task.spawn(function()
		while true do
			task.wait(ACCESS_SECONDS)
			local ok, err = pcall(showOut :: (string?) -> any, nil)
			if not ok then
				warn("[InteriorService] access check failed: " .. tostring(err))
			end
		end
	end)
	-- (also on leaving: Releasing only fires for players whose data had loaded)
	local function forget(player: Player)
		occupants[player] = nil
		arrivedAt[player] = nil
		moves[player] = nil
		moving[player] = nil
		friends[player] = nil
		limiter:forget(player)
	end
	services.PlayerDataService.Releasing:Connect(forget)
	Players.PlayerRemoving:Connect(forget)
end

return InteriorService
