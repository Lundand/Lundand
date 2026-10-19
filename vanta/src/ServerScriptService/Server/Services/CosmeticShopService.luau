--!strict
-- The cosmetic shop (L-46). The Clothier's conversation opens it. The server builds the catalogue view, prompts a
-- Robux purchase only for an item that is on sale and not owned (one prompt at a time), and lets players wear and
-- remove what they own. Items are granted only by the receipt handler (MonetizationService). At startup each
-- configured price is checked against the Creator Dashboard; an item whose price differs is not sold.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local Cosmetics = require(Shared.Domain.Cosmetics)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)

local CosmeticShopService = {}
local services: any = nil
local limiter = RateLimiter.new(4, 1, os.clock)
local prompting: {[Player]: boolean} = {}
local priceMismatch: {[string]: boolean} = {}

function CosmeticShopService.init(allServices: any)
	services = allServices
end

local function notify(player: Player, message: string)
	Remotes.get("Notify"):FireClient(player, message)
end

local function view(player: Player): any
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if data == nil or character == nil then
		return nil
	end
	local now = os.time()
	local items = {}
	for id, item in pairs(Content.cosmetics.items) do
		local availability = Cosmetics.availability(item, now)
		if priceMismatch[id] then
			availability = "NotConfigured"
		end
		local owned = Cosmetics.owns(data.account, id)
		if owned or (availability ~= "Retired" and availability ~= "Ended") then
			table.insert(items, {
				id = id,
				name = item.displayName,
				description = item.description,
				category = item.category,
				price = item.price,
				label = Cosmetics.label(item),
				endsAt = item.endsAt,
				availability = availability,
				owned = owned,
				wearKey = Cosmetics.wearKey(item),
			})
		end
	end
	table.sort(items, function(a, b)
		if a.category ~= b.category then
			return a.category < b.category
		end
		return a.name < b.name
	end)
	return { items = items, worn = table.clone(character.appearance.cosmetics or {}) }
end

function CosmeticShopService.open(player: Player)
	local shop = view(player)
	if shop ~= nil then
		Remotes.get("OpenInterface"):FireClient(player, "CosmeticShop", shop)
	end
end

local function onRequest(player: Player, action: any, cosmeticId: any)
	if not limiter:allow(player) or type(cosmeticId) ~= "string" then
		return
	end
	local item = Content.cosmetics.items[cosmeticId]
	local data = services.PlayerDataService.getData(player)
	local character = services.PlayerDataService.getCharacter(player)
	if item == nil or data == nil or character == nil then
		return
	end
	if action == "Buy" then
		local ok, reason = Cosmetics.canBuy(data.account, item, os.time())
		if not ok or priceMismatch[cosmeticId] then
			notify(player, "Not available: " .. tostring(reason or "not on sale"))
			return
		end
		if not prompting[player] then
			prompting[player] = true
			MarketplaceService:PromptProductPurchase(player, item.productId)
		end
		return
	elseif action == "Wear" then
		local ok, reason = Cosmetics.equip(data.account, character, cosmeticId, Content.cosmetics)
		if not ok then
			notify(player, "Can't wear that: " .. tostring(reason))
		end
	elseif action == "Remove" then
		Cosmetics.unequip(character, Cosmetics.wearKey(item))
	else
		return
	end
	CosmeticShopService.open(player)
end

function CosmeticShopService.start()
	Remotes.get("CosmeticRequest").OnServerEvent:Connect(onRequest)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
		local player = Players:GetPlayerByUserId(userId)
		if player == nil then
			return
		end
		prompting[player] = nil
		if purchased then
			task.delay(2, CosmeticShopService.open, player)
		end
	end)
	services.PlayerDataService.Releasing:Connect(function(player: Player)
		prompting[player] = nil
		limiter:forget(player)
	end)
	task.spawn(function()
		for id, item in pairs(Content.cosmetics.items) do
			if (item.productId or 0) > 0 then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(item.productId, Enum.InfoType.Product)
				end)
				if not ok or info.PriceInRobux ~= item.price then
					priceMismatch[id] = true
					warn("[CosmeticShop] " .. id .. " is not sold: its Dashboard price differs from the config or couldn't be read")
				end
			end
		end
	end)
end

return CosmeticShopService
