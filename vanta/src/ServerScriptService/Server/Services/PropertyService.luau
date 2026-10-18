--!strict
-- Buying buildings (L-28, L-54). For-sale signs (parts tagged PropertySign with a PropertyId attribute) open the
-- property window. A purchase follows PropertyOwnership's four steps across the shared record and the buyer's
-- save: reserve, charge, commit, record. Anything interrupted is settled when the buyer next joins: they get
-- the building or their gold back.
-- Entering is separate from owning: the city's property volumes (parts tagged PropertyVolume, built by CityBuilder)
-- are checked twice a second, and anyone inside an owned home its owner hasn't opened to them is shown out to the
-- door. Owners choose Private, Friends or Public from the property window.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local PropertyOwnership = require(Server.Domain.PropertyOwnership)
local PropertyAccess = require(Server.Domain.PropertyAccess)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local STORE = "Properties"
local SIGN_DISTANCE = 12
local KIND_NAMES = { House = "Home", Shop = "Shop", GuildHall = "Guild hall" }
local ACCESS_INTERVAL = 0.5
local ACCESS_MODES = { "Private", "Friends", "Public" }

local PropertyService = {}
local services: any = nil
local limiter = RateLimiter.new(6, 1, os.clock)
local viewing: {[Player]: string} = {}
local volumes = PropertyAccess.newIndex(64)
local friendCache: {[Player]: {[number]: boolean}} = {}
local lastWarned: {[Player]: number} = {}

function PropertyService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function records(): any
	return services.SharedRecordService.store(STORE)
end

local function priceOf(property: any): number
	return Content.propertyRules.pricesByTier[property.tier]
end

local function view(player: Player, propertyId: string): any
	local property = Content.world.properties[propertyId]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if property == nil or data == nil or character == nil then
		return nil
	end
	local readable, record = records():read(propertyId)
	local owner = readable and record and record.owner
	local district = Content.world.districts[property.district]
	local result: any = {
		id = propertyId,
		kind = KIND_NAMES[property.kind] or property.kind,
		district = (district and district.displayName) or property.district,
		price = priceOf(property),
		gold = character.currencies.Gold or 0,
		ownerName = owner and owner.name,
		readable = readable,
		isShop = property.kind == "Shop",
		isMine = owner ~= nil and owner.userId == player.UserId,
		accessMode = readable and record and record.permissions and record.permissions.mode or "Private",
		accessModes = ACCESS_MODES,
	}
	if property.kind == Content.propertyRules.guildHall.kind then
		result.note = string.format("Guild halls are bought by a guild's leader, from the guild treasury, from guild level %d.", Content.guilds.hallRequiredLevel)
		if readable and owner == nil then
			result.hallOffer = services.GuildService.hallOffer(player, propertyId)
		end
	elseif readable and owner == nil then
		local can, reason = PropertyOwnership.canAcquire(data.account, property, Content.propertyRules)
		result.canBuy = can
		result.reason = reason
	end
	return result
end

local function open(player: Player, propertyId: string)
	local result = view(player, propertyId)
	if result ~= nil then
		viewing[player] = propertyId
		Remotes.get("OpenInterface"):FireClient(player, "Property", result)
	end
end

function PropertyService.isViewing(player: Player, propertyId: any): boolean
	return viewing[player] ~= nil and viewing[player] == propertyId
end

-- Settles purchases that were interrupted, against the shared records.
function PropertyService.reconcile(player: Player)
	local data = services.PlayerDataService.getData(player)
	if data == nil or next(data.account.pendingPurchases) == nil then
		return
	end
	local outcomes = PropertyOwnership.reconcile(data, player.UserId, function(propertyId: string): any
		local ok, record = records():read(propertyId, 0)
		if not ok then
			return nil
		end
		return record or PropertyOwnership.newRecord(propertyId)
	end, services.InventoryService.deps(player))
	for _, outcome in ipairs(outcomes) do
		if outcome.outcome == "Owned" then
			notify(player, "Your purchase finished: the building is yours.")
		elseif outcome.outcome == "Refunded" then
			notify(player, "A building purchase didn't finish. Your gold was returned.")
		end
	end
	services.InventoryService.sendSnapshot(player)
end

local function buy(player: Player, propertyId: any)
	local property = type(propertyId) == "string" and Content.world.properties[propertyId]
	local data = services.PlayerDataService.getData(player)
	if not property or viewing[player] ~= propertyId or data == nil then
		return
	end
	local rules = Content.propertyRules
	local can, reason = PropertyOwnership.canAcquire(data.account, property, rules)
	if not can then
		notify(player, "Can't buy: " .. tostring(reason))
		return
	end
	local operationId = "property:" .. HttpService:GenerateGUID(false)
	local now = os.time()
	local reserved, answer = records():update(propertyId, function(record: any)
		local current = record or PropertyOwnership.newRecord(propertyId)
		local ok, err = PropertyOwnership.reserve(current, player.UserId, operationId, now, rules)
		if not ok then
			return nil, err
		end
		return current, true
	end)
	if not reserved or answer ~= true then
		notify(player, "Can't buy: " .. tostring(answer or "please try again"))
		return
	end
	local charged, err = PropertyOwnership.beginPurchase(data, data.activeCharacterId, property, priceOf(property), operationId, rules, services.InventoryService.deps(player))
	if not charged then
		notify(player, "Can't buy: " .. tostring(err))
		return
	end
	local committed, result = records():update(propertyId, function(record: any)
		if record == nil then
			return nil, "the record is missing"
		end
		local ok, commitErr = PropertyOwnership.commit(record, player.UserId, player.DisplayName, operationId, now)
		if not ok then
			return nil, commitErr
		end
		return record, true
	end)
	if committed and result == true then
		PropertyOwnership.finishPurchase(data, operationId)
		notify(player, "The building is yours.")
	else
		PropertyService.reconcile(player)
	end
	services.InventoryService.sendSnapshot(player)
	open(player, propertyId)
end

local function setAccess(player: Player, propertyId: any, mode: any)
	local data = services.PlayerDataService.getData(player)
	if type(propertyId) ~= "string" or viewing[player] ~= propertyId or data == nil or data.account.properties[propertyId] == nil then
		return
	end
	local ok, answer = records():update(propertyId, function(record: any): (any, any)
		if record == nil then
			return nil, "the deed can't be found"
		end
		-- keep the owner's list of named guests; only the mode changes here
		local allowed = {}
		for visitorId in pairs(record.permissions.allowed or {}) do
			table.insert(allowed, tonumber(visitorId))
		end
		local changed, err = PropertyOwnership.setPermissions(record, player.UserId, mode, allowed, Content.propertyRules)
		if not changed then
			return nil, err
		end
		return record, true
	end)
	if ok and answer == true then
		notify(player, "Your home is now " .. string.lower(tostring(mode)) .. ".")
	else
		notify(player, "Couldn't change who may enter: " .. tostring(answer))
	end
	open(player, propertyId)
end

-- Is this player one of the owner's Roblox friends? nil until known (looked up once per pair, off the loop).
local function friendship(player: Player, ownerId: number): boolean?
	local known = friendCache[player]
	if known == nil then
		known = {}
		friendCache[player] = known
	end
	local cached = known[ownerId]
	if cached ~= nil then
		return cached
	end
	known[ownerId] = false
	task.spawn(function()
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(ownerId)
		end)
		if friendCache[player] ~= nil then
			friendCache[player][ownerId] = ok and isFriend == true
		end
	end)
	return nil
end

local function addVolume(instance: Instance)
	local propertyId = instance:GetAttribute("PropertyId")
	if not instance:IsA("BasePart") or type(propertyId) ~= "string" or Content.world.properties[propertyId] == nil then
		return
	end
	local part = instance :: BasePart
	local cf, size = part.CFrame, part.Size
	local half = size / 2
	-- axis-aligned bounds of the (possibly turned) box for the grid, the exact test in its own frame
	local extent = Vector3.new(
		math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
		half.Y,
		math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
	)
	local exit = part:GetAttribute("Exit")
	volumes:add({
		propertyId = propertyId,
		minX = cf.Position.X - extent.X,
		maxX = cf.Position.X + extent.X,
		minZ = cf.Position.Z - extent.Z,
		maxZ = cf.Position.Z + extent.Z,
		minY = cf.Position.Y - half.Y,
		maxY = cf.Position.Y + half.Y,
		exit = if typeof(exit) == "Vector3" then exit else cf.Position,
		contains = function(x: number, y: number, z: number): boolean
			local offset = cf:PointToObjectSpace(Vector3.new(x, y, z))
			return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
		end,
	} :: any)
end

-- Shows anyone out of an owned home they may not be in. Unowned homes stay open for viewing.
local function enforceAccess()
	for _, player in ipairs(Players:GetPlayers()) do
		local root: any = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root ~= nil then
			local p = root.Position
			for _, volume: any in ipairs(volumes:query(p.X, p.Y, p.Z)) do
				local readable, record = records():read(volume.propertyId)
				if readable and record ~= nil and record.owner ~= nil then
					local isFriend = if record.permissions and record.permissions.mode == "Friends" then friendship(player, record.owner.userId) else false
					if PropertyAccess.shouldEject(record, player.UserId, isFriend) then
						player.Character:PivotTo(CFrame.new(volume.exit + Vector3.new(0, 3, 0)))
						local now = os.clock()
						if now - (lastWarned[player] or 0) > 4 then
							lastWarned[player] = now
							notify(player, "That home belongs to " .. tostring(record.owner.name) .. ". It's private.")
						end
						break
					end
				end
			end
		end
	end
end

local function setupSign(sign: Instance)
	local propertyId = sign:GetAttribute("PropertyId")
	if not sign:IsA("BasePart") or type(propertyId) ~= "string" or Content.world.properties[propertyId] == nil or sign:FindFirstChild("ViewPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ViewPrompt"
	prompt.ActionText = "View"
	prompt.ObjectText = "Property"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SIGN_DISTANCE - 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
	prompt.Triggered:Connect(function(player: Player)
		local root: any = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if limiter:allow(player) and root ~= nil and (root.Position - sign.Position).Magnitude <= SIGN_DISTANCE then
			open(player, propertyId)
		end
	end)
end

function PropertyService.start()
	for _, sign in ipairs(CollectionService:GetTagged("PropertySign")) do
		setupSign(sign)
	end
	CollectionService:GetInstanceAddedSignal("PropertySign"):Connect(setupSign)
	for _, part in ipairs(CollectionService:GetTagged("PropertyVolume")) do
		addVolume(part)
	end
	CollectionService:GetInstanceAddedSignal("PropertyVolume"):Connect(addVolume)
	task.spawn(function()
		while true do
			task.wait(ACCESS_INTERVAL)
			local ok, err: any = pcall(enforceAccess)
			if not ok then
				warn("[PropertyService] access check failed: " .. tostring(err))
			end
		end
	end)
	Remotes.get("PropertyRequest").OnServerEvent:Connect(function(player: Player, action: any, propertyId: any, mode: any)
		if action == "Buy" and limiter:allow(player) then
			buy(player, propertyId)
		elseif action == "SetAccess" and limiter:allow(player) then
			setAccess(player, propertyId, mode)
		elseif action == "BuyHall" and limiter:allow(player) and viewing[player] == propertyId then
			services.GuildService.buyHall(player, propertyId)
			open(player, propertyId)
		end
	end)
	services.PlayerDataService.Loaded:Connect(function(player: Player)
		task.spawn(PropertyService.reconcile, player)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		viewing[player] = nil
		friendCache[player] = nil
		lastWarned[player] = nil
		limiter:forget(player)
	end)
end

return PropertyService
