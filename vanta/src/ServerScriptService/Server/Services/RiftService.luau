--!strict
-- Community Rift events (L-36, L-47). Touching the Heart of Realms opens the contribution window: the shared total,
-- the target, what is being unlocked, and the fixed contribution amounts (each a developer product). A
-- contribution counts only after Roblox confirms it (receipt, then outbox, then shards). Every minute the total
-- is checked; the event update that sees the target reached opens the Rift for everyone, once, and the crystal
-- flares. Contributing never grants anything in play.
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local RiftDonations = require(Server.Domain.RiftDonations)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local REFRESH_SECONDS = 60
local TOPIC = "RiftOpened"

local RiftService = {}
local services: any = nil
local limiter = RateLimiter.new(3, 0.5, os.clock)
local prompting: {[Player]: boolean} = {}
local total = 0
local eventState: any = nil
local celebrated = false

function RiftService.init(allServices: any)
	services = allServices
end

local function activeEvent(): any
	return Content.riftEvents.events[Content.riftEvents.activeEventId]
end

-- The crystal flares violet and every player hears of it, once per server.
local function celebrate()
	if celebrated then
		return
	end
	celebrated = true
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("LocationId") == "HeartOfRealms" and instance.Size.Y > 4 then
			instance.Color = Color3.fromRGB(170, 110, 255)
			instance.Material = Enum.Material.Neon
			local light = Instance.new("PointLight")
			light.Color = instance.Color
			light.Brightness = 3
			light.Range = 40
			light.Parent = instance
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		Remotes.get("Notify"):FireClient(player, "The Heart of Realms flares violet: " .. activeEvent().displayName .. " has opened!")
	end
end

local function refresh()
	local event = activeEvent()
	local shardsStore = services.SharedRecordService.store("RiftShards")
	local shards = {}
	for index = 1, Content.riftEvents.shardCount do
		local ok, shard = shardsStore:read(event.id .. ":" .. index)
		if not ok then
			return
		end
		if shard ~= nil then
			table.insert(shards, shard)
		end
	end
	total = RiftDonations.total(shards)
	local now = os.time()
	local ok, state = services.SharedRecordService.store("RiftEvents"):update(event.id, function(record: any)
		local current = record or RiftDonations.newEvent(event.id)
		local opened = RiftDonations.tryOpen(current, total, event.target, now, event.openHours)
		if record ~= nil and not opened then
			return nil, current
		end
		return current, current
	end)
	if ok and state ~= nil then
		eventState = state
		if state.state == "Open" and RiftDonations.status(state, now) == "Open" then
			celebrate()
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { eventId = event.id })
			end)
		end
	end
end

function RiftService.openDonations(player: Player)
	local event = activeEvent()
	local now = os.time()
	local progress = RiftDonations.progress(total, event.target)
	local tiers = {}
	for key, product in pairs(Content.products) do
		if product.kind == "RiftDonation" then
			table.insert(tiers, { key = key, robux = product.robux, available = product.enabled and product.productId > 0 })
		end
	end
	table.sort(tiers, function(a, b)
		return a.robux < b.robux
	end)
	Remotes.get("OpenInterface"):FireClient(player, "RiftDonations", {
		name = event.displayName,
		description = event.description,
		total = progress.total,
		target = progress.target,
		remaining = progress.remaining,
		fraction = progress.fraction,
		status = eventState and RiftDonations.status(eventState, now) or "Collecting",
		tiers = tiers,
	})
end

local function onRequest(player: Player, action: any, args: any)
	if not limiter:allow(player) or action ~= "Donate" or type(args) ~= "table" then
		return
	end
	local product = type(args.product) == "string" and Content.products[args.product]
	if not product or product.kind ~= "RiftDonation" or not product.enabled or product.productId <= 0 then
		return
	end
	if eventState ~= nil and RiftDonations.status(eventState, os.time()) ~= "Collecting" then
		Remotes.get("Notify"):FireClient(player, "This Rift is no longer gathering strength.")
		return
	end
	if not prompting[player] then
		prompting[player] = true
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end
end

function RiftService.start()
	Remotes.get("RiftRequest").OnServerEvent:Connect(onRequest)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil and prompting[player] then
			prompting[player] = nil
			if purchased then
				Remotes.get("Notify"):FireClient(player, "Thank you. Your contribution reaches the crystal within a minute or two.")
			end
		end
	end)
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function()
				task.spawn(refresh)
			end)
		end)
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		prompting[player] = nil
		limiter:forget(player)
	end)
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return RiftService
