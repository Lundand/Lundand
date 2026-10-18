--!strict
-- Inn rooms (L-29): every player can have somewhere to stay. Each inn rents one kind of room, the same for as many
-- players as want it, and each renter gets their own instanced copy (InteriorService). Rooms are small and get
-- bigger and dearer with the inn: the Crooked Lantern in the slums, the Salt and Anchor at the harbour, the Square
-- Inn. The Innkeeper's "I'd like a room" and each inn's rooms door (a part tagged InnRooms) open the rental window,
-- where you rent, pay for more nights, or (at the door, with a rental running) go up to your room. Renting follows Domain.Rentals: gold is taken and the
-- rental made or extended in one step, so nobody pays without getting the room. Each request is a new payment.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Rentals = require(Server.Domain.Rentals)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local RentalService = {}
local services: any = nil
local limiter = RateLimiter.new(4, 2, os.clock)
local DOOR_REACH = 14
local doors: {[string]: BasePart} = {}
local viewing: {[Player]: string} = {}

function RentalService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

-- The rental rules with this inn's own price.
local function rulesFor(inn: any): any
	local rules = table.clone(Content.propertyRules.rental)
	rules.pricePerDay = inn.pricePerDay
	return rules
end

-- Is the player at the inn's rooms door, inside the inn? (The door stands in the back wall; the inn is on its +z side.)
local function nearDoor(player: Player, innId: string): boolean
	local door = doors[innId]
	local root: any = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not door or not root then
		return false
	end
	local offset = root.Position - door.Position
	return offset.Magnitude <= DOOR_REACH and offset:Dot(door.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))) > 0
end

function RentalService.open(player: Player, innId: any)
	local inn = type(innId) == "string" and Content.world.inns[innId]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if not inn or data == nil or character == nil then
		return
	end
	local now = os.time()
	local activeInn, active = Rentals.activeRental(data.account, now)
	local rules = Content.propertyRules.rental
	viewing[player] = innId
	Remotes.get("OpenInterface"):FireClient(player, "Rentals", {
		innId = innId,
		innName = inn.displayName,
		room = inn.room,
		pricePerDay = inn.pricePerDay,
		maxDays = rules.maxDays,
		dayLengthSeconds = rules.dayLengthSeconds,
		gold = character.currencies.Gold or 0,
		activeInn = activeInn,
		activeInnName = activeInn and Content.world.inns[activeInn] and Content.world.inns[activeInn].displayName,
		secondsLeft = active and math.max(0, active.expiresAt - now) or 0,
		atDoor = nearDoor(player, innId),
	})
end

local function rent(player: Player, innId: any, days: any)
	local inn = type(innId) == "string" and Content.world.inns[innId]
	local data = services.PlayerDataService.getData(player)
	if not inn or data == nil or viewing[player] ~= innId then
		return
	end
	local operationId = "rent:" .. HttpService:GenerateGUID(false)
	local ok, result = Rentals.rent(data, data.activeCharacterId, innId, days, operationId, Content.world.inns, rulesFor(inn), services.InventoryService.deps(player))
	if ok then
		notify(player, string.format("Your room at %s is ready. The door to the rooms is at the back.", inn.displayName))
	else
		notify(player, "Can't rent: " .. tostring(result))
	end
	services.InventoryService.sendSnapshot(player)
	RentalService.open(player, innId)
end

local function goToRoom(player: Player, innId: string)
	local data = services.PlayerDataService.getData(player)
	local door = doors[innId]
	if data == nil or not door or not nearDoor(player, innId) then
		return
	end
	local activeInn = Rentals.activeRental(data.account, os.time())
	if activeInn ~= innId then
		RentalService.open(player, innId)
		return
	end
	services.InteriorService.enterRoom(player, innId, door)
end

local function setupDoor(instance: Instance)
	local attribute = instance:GetAttribute("InnId")
	if not instance:IsA("BasePart") or type(attribute) ~= "string" or Content.world.inns[attribute] == nil or instance:FindFirstChild("RoomsPrompt") then
		return
	end
	local innId = attribute :: string
	local door = instance :: BasePart
	doors[innId] = door
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoomsPrompt"
	prompt.ActionText = "Rooms"
	prompt.ObjectText = Content.world.inns[innId].displayName
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = true -- not through the back wall from the street
	prompt.Parent = door
	-- the door opens the rental window: rent or pay for more nights there, or go up to your room
	prompt.Triggered:Connect(function(player: Player)
		if limiter:allow(player) and nearDoor(player, innId) then
			RentalService.open(player, innId)
		end
	end)
end

function RentalService.start()
	for _, door in ipairs(CollectionService:GetTagged("InnRooms")) do
		setupDoor(door)
	end
	CollectionService:GetInstanceAddedSignal("InnRooms"):Connect(setupDoor)
	Remotes.get("RentalRequest").OnServerEvent:Connect(function(player: Player, action: any, innId: any, days: any)
		if not limiter:allow(player) then
			return
		end
		if action == "Rent" then
			rent(player, innId, days)
		elseif action == "Enter" and type(innId) == "string" and Content.world.inns[innId] ~= nil then
			goToRoom(player, innId)
		end
	end)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		local data = services.PlayerDataService.getData(player)
		if data ~= nil then
			Rentals.pruneExpired(data.account, os.time())
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		viewing[player] = nil
		limiter:forget(player)
	end)
end

return RentalService
