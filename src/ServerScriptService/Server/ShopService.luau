--[[
	ShopService — Robux game passes and developer products.
	* Waiting is always free; Robux only speeds things up (never protects or recovers a Core).
	* Premium Cores are opened on the spot. They and everything that buys luck are "paid random items":
	  their odds are shown in the shop before buying, and players where Roblox's PolicyService restricts
	  paid random items can't see or buy them (Config.PaidRandom).
	* ProcessReceipt is idempotent: every PurchaseId is remembered in the player's save.
	* Paste your IDs into Config.Products / Config.Passes. While an ID is 0, admins testing
	  in Studio get the item for free so the whole flow can be tried before publishing.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local ShopService = {}
local S: any

local owned: { [Player]: { [string]: boolean } } = {}
local pendingSkip: { [Player]: number } = {}
local serverLuckUntil = 0
local productHandlers: { [number]: (Player) -> () } = {}
local restricted: { [Player]: boolean } = {} -- PolicyService: paid random items not allowed for this player
local restrictOverride: { [Player]: boolean } = {} -- admin test toggle
local rng = Random.new()
local RevealEvent: RemoteEvent

--------------------------------------------------------------------------------
-- Paid random items (Roblox policy): Premium Cores and anything that buys luck (Config.PaidRandom)
--------------------------------------------------------------------------------
function ShopService.LoadPolicy(player: Player)
	task.spawn(function()
		for attempt = 1, 4 do
			local ok, info = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			if ok and type(info) == "table" then
				restricted[player] = info.ArePaidRandomItemsRestricted == true
				S.Player.MarkDirty(player)
				return
			end
			if not player.Parent then
				return
			end
			task.wait(2 * attempt)
		end
		-- no answer from Roblox: stay on the safe side (restricted), except while testing in Studio
		restricted[player] = not RunService:IsStudio()
		S.Player.MarkDirty(player)
	end)
end

-- True while we don't know yet, so nothing restricted can be bought before Roblox has answered
function ShopService.IsRestricted(player: Player): boolean
	local override = restrictOverride[player]
	if override ~= nil then
		return override
	end
	return restricted[player] ~= false
end

-- Admin panel: flips the restriction for this session to test both versions of the shop
function ShopService.ToggleRestricted(player: Player): boolean
	restrictOverride[player] = not ShopService.IsRestricted(player)
	S.Player.MarkDirty(player)
	return restrictOverride[player]
end

local function isPaidRandom(kind: string, name: string): boolean
	local list = Config.PaidRandom and Config.PaidRandom[kind]
	return list ~= nil and table.find(list, name) ~= nil
end
ShopService.IsPaidRandom = isPaidRandom

local RESTRICTED_MESSAGE = "This item isn't available in your country."

function ShopService.LoadPasses(player: Player)
	local set = {}
	owned[player] = set
	for name, pass in Config.Passes do
		if pass.id and pass.id > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and has then
				set[name] = true
			end
		end
	end
end

function ShopService.HasPass(player: Player, name: string): boolean
	local set = owned[player]
	return set ~= nil and set[name] == true
end

function ShopService.OwnedPasses(player: Player): { [string]: boolean }
	return table.clone(owned[player] or {})
end

function ShopService.ServerLuckUntil(): number
	return serverLuckUntil
end

-- Applies a pass right away (after purchase or from the admin panel)
function ShopService.GrantPass(player: Player, name: string)
	if not Config.Passes[name] then
		return
	end
	local set = owned[player]
	if not set then
		set = {}
		owned[player] = set
	end
	set[name] = true
	if name == "ExtraIncubators" then
		S.Incubators.EnsureSlots(player)
		S.Incubators.Fill(player)
		S.Plots.RefreshIncubators(player)
	end
	S.Player.Invalidate(player)
	S.Player.Notify(player, "Thanks for your support! " .. Config.Passes[name].name .. " is active.", "success")
end

--------------------------------------------------------------------------------
-- Product effects
--------------------------------------------------------------------------------
local function grantSkip(player: Player, tier: number)
	local data = S.Data.Get(player)
	local cap = Config.Products.Skips[tier].max
	local slot = pendingSkip[player]
	pendingSkip[player] = nil
	local remaining = slot and S.Incubators.Remaining(player, slot) or 0
	if not slot or remaining <= 0 or remaining > cap then
		-- target already finished: use it on the longest timer it covers instead
		slot = nil
		local best = 0
		for i = 1, S.Incubators.SlotCount(player) do
			local left = S.Incubators.Remaining(player, i)
			if left > best and left <= cap then
				best, slot = left, i
			end
		end
	end
	if slot then
		S.Incubators.Skip(player, slot)
		S.Player.Notify(player, "⚡ Instant open! Your Core is ready.", "success")
	else
		data.skips[tier] = (data.skips[tier] or 0) + 1
		S.Player.Notify(player, "No timer to skip right now — saved as a Skip credit for later.", "info")
	end
end

local function grantProduct(player: Player, name: string)
	local data = S.Data.Get(player)
	local P = Config.Products
	if name == "TimeWarp" then
		S.Incubators.TimeWarp(player, P.TimeWarp.seconds)
		S.Player.Notify(player, "⏩ Time Warp! -" .. Util.Duration(P.TimeWarp.seconds) .. " on every incubator.", "success")
	elseif name == "Luck" then
		data.boosts.luck = math.max(os.time(), data.boosts.luck or 0) + P.Luck.seconds
		S.Player.Notify(player, "🍀 x" .. P.Luck.mult .. " Luck for " .. Util.Duration(P.Luck.seconds) .. "!", "success")
	elseif name == "ServerLuck" then
		serverLuckUntil = math.max(os.time(), serverLuckUntil) + P.ServerLuck.seconds
		workspace:SetAttribute("ServerLuckUntil", serverLuckUntil)
		S.Player.NotifyAll("🍀 " .. player.DisplayName .. " activated x" .. P.ServerLuck.mult .. " SERVER LUCK for " .. Util.Duration(P.ServerLuck.seconds) .. "!", "announce", { rarity = 5 })
		for _, other in Players:GetPlayers() do
			S.Player.MarkDirty(other)
		end
	elseif name == "Coins" then
		local amount = math.floor(S.Mobs.CoinValue(data.zones) * P.Coins.kills)
		S.Player.AddCoins(player, amount)
		S.Player.Notify(player, "💰 +" .. Util.Abbrev(amount) .. " Coins!", "success")
	elseif name == "PremiumCore" or name == "PremiumCore3" then
		ShopService.OpenPremium(player, P[name].count or 1)
	end
	S.Player.MarkDirty(player)
end

-- Opens Premium Cores on the spot: every item goes straight into the bag (even when it's full) with the reveal
function ShopService.OpenPremium(player: Player, count: number)
	local data = S.Data.Get(player)
	local z = Items.PremiumZone(data.zones)
	local chances = {}
	for _, e in Items.PremiumOdds() do
		chances[e.r] = e.chance
	end
	for _ = 1, count do
		local key, r = Items.RollPremium(z, rng)
		local before = S.Player.GetPower(player)
		local equipped = S.Player.GiveItem(player, key, true)
		local after = S.Player.GetPower(player)
		data.stats.opened += 1
		RevealEvent:FireClient(player, {
			z = z,
			r = r,
			odds = math.max(1, math.floor(1 / (chances[r] or 1) + 0.5)),
			key = key,
			rarity = r,
			bonus = 0,
			equipped = equipped,
			before = before,
			after = after,
			premium = true,
		})
		if r >= 5 then
			S.Player.NotifyAll(player.DisplayName .. " opened a Premium Core: " .. string.upper(Items.FullName(key)) .. "!", "announce", { rarity = r })
		end
	end
	S.Player.MarkDirty(player)
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = S.Data.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local handler = productHandlers[receipt.ProductId]
	if not handler then
		warn("[Shop] No handler for product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(handler, player)
	if not ok then
		warn("[Shop] Product grant failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.receipts, receipt.PurchaseId)
	while #data.receipts > 50 do
		table.remove(data.receipts, 1)
	end
	S.Player.MarkDirty(player)
	S.Data.SaveNow(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Free grants while testing in Studio with unset IDs
local function studioTest(player: Player): boolean
	return RunService:IsStudio() and S.Admin.IsAdmin(player)
end

local function registerHandlers()
	S.Player.Handle("buySkip", function(player, args)
		local slot = tonumber(args.slot) or 0
		local remaining = S.Incubators.Remaining(player, slot)
		if remaining <= 0 then
			return { ok = false, msg = "That Core is already ready!" }
		end
		for tier, product in Config.Products.Skips do
			if product.max >= remaining then
				if product.id > 0 then
					pendingSkip[player] = slot
					MarketplaceService:PromptProductPurchase(player, product.id)
					return { ok = true }
				elseif studioTest(player) then
					pendingSkip[player] = slot
					grantSkip(player, tier)
					return { ok = true, msg = "(Studio test) Skip granted for free." }
				end
				return { ok = false, msg = "Instant open isn't set up yet (add product IDs in Config.Products)." }
			end
		end
		return { ok = false, msg = "No skip covers this timer." }
	end)

	S.Player.Handle("buyProduct", function(player, args)
		local name = tostring(args.name)
		local product = Config.Products[name]
		if not product or name == "Skips" then
			return { ok = false, msg = "Unknown product." }
		end
		if isPaidRandom("products", name) and ShopService.IsRestricted(player) then
			return { ok = false, msg = RESTRICTED_MESSAGE }
		end
		if product.id > 0 then
			MarketplaceService:PromptProductPurchase(player, product.id)
			return { ok = true }
		elseif studioTest(player) then
			grantProduct(player, name)
			return { ok = true, msg = "(Studio test) Granted for free." }
		end
		return { ok = false, msg = "This product isn't set up yet (add its ID in Config.Products)." }
	end)

	S.Player.Handle("buyPass", function(player, args)
		local name = tostring(args.name)
		local pass = Config.Passes[name]
		if not pass then
			return { ok = false, msg = "Unknown pass." }
		end
		if ShopService.HasPass(player, name) then
			return { ok = false, msg = "You already own this!" }
		end
		if isPaidRandom("passes", name) and ShopService.IsRestricted(player) then
			return { ok = false, msg = RESTRICTED_MESSAGE }
		end
		if pass.id > 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
			return { ok = true }
		elseif studioTest(player) then
			ShopService.GrantPass(player, name)
			return { ok = true, msg = "(Studio test) Pass granted for this session." }
		end
		return { ok = false, msg = "This pass isn't set up yet (add its ID in Config.Passes)." }
	end)
end

function ShopService.Init(services: any)
	S = services
end

function ShopService.Start()
	RevealEvent = Net.Event("Reveal")
	registerHandlers()
	for tier, product in Config.Products.Skips do
		if product.id > 0 then
			productHandlers[product.id] = function(player)
				grantSkip(player, tier)
			end
		end
	end
	for name, product in Config.Products do
		if name ~= "Skips" and type(product) == "table" and (product.id or 0) > 0 then
			productHandlers[product.id] = function(player)
				grantProduct(player, name)
			end
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for name, pass in Config.Passes do
			if pass.id == passId then
				ShopService.GrantPass(player, name)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		pendingSkip[player] = nil
		restricted[player] = nil
		restrictOverride[player] = nil
	end)
	workspace:SetAttribute("ServerLuckUntil", 0)
end

return ShopService
