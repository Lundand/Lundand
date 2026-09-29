--[[
	ShopPanel — Premium Cores, Robux boosts and game passes. Waiting is always free.
	Everything that is a "paid random item" (Premium Cores, luck, Coins that buy luck, 2x Luck) shows its odds
	before buying (ODDS buttons) and is hidden where Roblox restricts such items (data.restricted).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Popup = require(script.Parent.Popup)

local ShopPanel = {}

local player = Players.LocalPlayer
local built = false
local opener: ((string) -> ())? = nil -- set by Panels: opens another panel
local scroll: ScrollingFrame
local prices: { [string]: number } = {}
local rgb = Color3.fromRGB

local BOOSTS = {
	{ name = "TimeWarp", icon = "⏳", color = rgb(110, 90, 255), title = "Time Warp", desc = "-" .. Util.Duration(Config.Products.TimeWarp.seconds) .. " on every incubator" },
	{ name = "Luck", icon = "🍀", color = rgb(50, 190, 80), title = "x" .. Config.Products.Luck.mult .. " Luck", desc = "Better Core drops for " .. Util.Duration(Config.Products.Luck.seconds) },
	{ name = "ServerLuck", icon = "🌍", color = rgb(30, 180, 160), title = "Server Luck", desc = "x" .. Config.Products.ServerLuck.mult .. " luck for EVERYONE, " .. Util.Duration(Config.Products.ServerLuck.seconds) },
	{ name = "Coins", icon = "💰", color = rgb(255, 170, 30), title = "Coin Bag", desc = "Coins worth " .. Config.Products.Coins.kills .. " kills in your best zone" },
}
local PASS_ORDER = { "DoubleLuck", "DoubleCoins", "ExtraIncubators", "FastIncubation", "VIP" }
local PASS_LOOK = {
	DoubleLuck = { "🍀", rgb(50, 190, 80) },
	DoubleCoins = { "💰", rgb(255, 170, 30) },
	ExtraIncubators = { "🥚", rgb(60, 140, 255) },
	FastIncubation = { "⚡", rgb(255, 110, 40) },
	VIP = { "👑", rgb(150, 70, 255) },
}

local function isPaidRandom(list: { string }, name: string): boolean
	return table.find(list, name) ~= nil
end

-- The image each pass / product has in the Creator Dashboard (shown in the round badge instead of the emoji)
local icons: { [string]: string } = {}

local function price(key: string, id: number, fallback: number, infoType: Enum.InfoType): number
	local cached = prices[key]
	if cached then
		return cached
	end
	prices[key] = fallback
	if id > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			if ok and info then
				if info.PriceInRobux then
					prices[key] = info.PriceInRobux
				end
				local image = tonumber(info.IconImageAssetId) or 0
				if image > 0 then
					icons[key] = "rbxassetid://" .. image
				end
				if State.Data then
					ShopPanel.Refresh(State.Data)
				end
			end
		end)
	end
	return fallback
end

-- Config `image = "rbxassetid://..."` wins; otherwise the dashboard icon once it has loaded
local function iconOf(key: string, item: any): string?
	local image = item and item.image
	if type(image) == "string" and image ~= "" then
		return image
	end
	return icons[key]
end

--------------------------------------------------------------------------------
-- Odds popups (per-kill drop chances, shown before buying anything that changes luck)
--------------------------------------------------------------------------------
-- The monster zone the player is in, or their deepest unlocked zone while at spawn / in the bases
local function monsterZone(data: any): number
	local rift = tonumber(player:GetAttribute("RiftZone")) or 0
	if rift > 0 then
		return rift
	end
	local zone = tonumber(player:GetAttribute("Zone")) or 0
	if zone > 0 then
		return zone
	end
	return math.max(tonumber(data.zones) or 1, 1)
end

type OddsSpec = { intro: string?, mult: number?, active: ((any) -> boolean)?, activeText: string? }

local function oddsTable(content: Frame, spec: OddsSpec)
	local data = State.Data
	if not data then
		return
	end
	local zone = monsterZone(data)
	local luck = tonumber(data.luck) or 1
	local active = spec.active ~= nil and (spec.active :: (any) -> boolean)(data)
	local withLuck = spec.mult and (active and luck or luck * (spec.mult :: number)) or nil
	local now = Items.DropChances(zone, "normal", luck)
	local boosted = withLuck and Items.DropChances(zone, "normal", withLuck) or nil
	local list = UI.Scroll(content, { Gap = 4 })
	local intro = spec.intro and (spec.intro :: string) .. "\n" or ""
	UI.Text(list, intro .. "Chance per kill of a normal monster in the " .. UI.Span(string.upper(Items.ZoneName(zone)), Items.CoreColor(zone)) .. string.format("  (your luck now: x%.2f)", luck), { Size = UDim2.new(1, 0, 0, spec.intro and 64 or 40), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, Rich = true, MaxSize = 16, Outline = 1.5, Order = 1 })
	local function row(order: number, name: string, color: Color3, a: string, b: string?, head: boolean?)
		local line = UI.Frame(list, { Size = UDim2.new(1, 0, 0, 32), Color = head and UI.Colors.Outline or (order % 2 == 0 and UI.Colors.Card or UI.Colors.CardHi), Transparency = head and 0.1 or 0.25, Radius = 8, Order = order, Name = head and "Head" or "Row" })
		local font = head and UI.Fonts.Black or UI.Fonts.Title
		UI.Text(line, name, { Size = UDim2.new(0.4, -12, 1, -6), Position = UDim2.fromOffset(12, 3), Font = font, Color = color, AlignX = Enum.TextXAlignment.Left, MaxSize = head and 14 or 18, Outline = 2 })
		local right = b and 0.3 or 0.6
		UI.Text(line, a, { Size = UDim2.new(right, -12, 1, -6), Position = UDim2.new(0.4, 0, 0, 3), Font = UI.Fonts.Black, AlignX = Enum.TextXAlignment.Right, MaxSize = head and 14 or 17, Outline = 1.5, Color = head and UI.Colors.Muted or UI.Colors.Text })
		if b then
			UI.Text(line, b, { Size = UDim2.new(0.3, -12, 1, -6), Position = UDim2.new(0.7, 0, 0, 3), Font = UI.Fonts.Black, AlignX = Enum.TextXAlignment.Right, MaxSize = head and 14 or 17, Outline = 1.5, Color = head and UI.Colors.Muted or Color3.fromRGB(130, 240, 150) })
		end
	end
	row(2, "RARITY", UI.Colors.Muted, "NOW", boosted and "WITH THIS BOOST" or nil, true)
	for r, def in Config.Rarities do
		row(2 + r, def.name, def.color, UI.Percent(now[r] or 0), boosted and UI.Percent((boosted :: any)[r] or 0) or nil)
	end
	row(20, "No Core", UI.Colors.Muted, UI.Percent(now.none or 0), boosted and UI.Percent((boosted :: any).none or 0) or nil)
	if active and spec.activeText then
		UI.Chip(list, spec.activeText :: string, Color3.fromRGB(34, 150, 70), { Size = UDim2.new(1, 0, 0, 34), Order = 30, MaxSize = 16, Radius = 10, Font = UI.Fonts.Bold })
	end
	UI.Text(list, "Rounded — the exact chances add up to 100%.", { Size = UDim2.new(1, 0, 0, 30), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 15, Order = 40 })
end

local ODDS: { [string]: { title: string, color: Color3, spec: OddsSpec } } = {
	Luck = {
		title = "ODDS — x" .. Config.Products.Luck.mult .. " LUCK (" .. string.upper(Util.Duration(Config.Products.Luck.seconds)) .. ")",
		color = rgb(50, 190, 80),
		spec = {
			mult = Config.Products.Luck.mult,
			active = function(data)
				return (data.luckBoostUntil or 0) > State.Now()
			end,
			activeText = "✅ This boost is already active, so the chances don't change.",
		},
	},
	ServerLuck = {
		title = "ODDS — SERVER LUCK",
		color = rgb(30, 180, 160),
		spec = {
			mult = Config.Products.ServerLuck.mult,
			active = function(data)
				local untilTime = math.max(tonumber(data.serverLuckUntil) or 0, tonumber(workspace:GetAttribute("ServerLuckUntil")) or 0)
				return untilTime > State.Now()
			end,
			activeText = "✅ Server Luck is already active, so the chances don't change.",
		},
	},
	DoubleLuck = {
		title = "ODDS — 2X LUCK PASS",
		color = rgb(50, 190, 80),
		spec = {
			mult = (Config.Passes.DoubleLuck :: any).mult or 2,
			active = function(data)
				return data.passes ~= nil and data.passes.DoubleLuck == true
			end,
			activeText = "✅ You own this pass, so the chances don't change.",
		},
	},
	Coins = {
		title = "ODDS — COIN BAG",
		color = rgb(255, 170, 30),
		spec = {
			intro = "Coins can buy " .. UI.Span("CORE LUCK", UI.Colors.Gold) .. " upgrades in your base (+1% luck per level).",
		},
	},
}

local function showOdds(name: string)
	local o = ODDS[name]
	if o then
		Popup.Show(o.title, o.color, function(content)
			oddsTable(content, o.spec)
		end)
	end
end

--------------------------------------------------------------------------------
local function card(parent: Instance, order: number, icon: string, accent: Color3, title: string, desc: string, buttonText: string, color: Color3, enabled: boolean, onClick: () -> (), odds: string?, image: string?)
	local frame = UI.Card(parent, { Order = order, Tint = accent, TintAmount = 0.2, Accent = accent, AccentT = 0.2, Name = "Offer" })
	local badge = UI.Badge(frame, icon, accent, 80, { Position = UDim2.new(0, 14, 0.5, 0), Anchor = Vector2.new(0, 0.5), Ring = UI.Colors.GoldLight, RingThickness = 3.5 })
	if image then
		-- the store art fills the circle; the emoji and the gloss step aside
		local art = UI.Create("ImageLabel", {
			Name = "Art",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = badge.ZIndex + 2,
			Parent = badge,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = art })
		for _, name in { "Icon", "Shine" } do
			local child = badge:FindFirstChild(name)
			if child and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
	end
	UI.Text(frame, title, { Size = UDim2.new(1, -120, 0, 30), Position = UDim2.fromOffset(108, 12), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 24, Outline = 2.5 })
	UI.Text(frame, desc, { Size = UDim2.new(1, -120, 0, 30), Position = UDim2.fromOffset(108, 44), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 14 })
	local button = UI.Button(frame, buttonText, color, onClick, { Size = UDim2.fromOffset(160, 48), Position = UDim2.new(1, -172, 1, -56), MaxSize = 21 })
	UI.SetEnabled(button, enabled, color)
	if odds then
		UI.Button(frame, "📊 ODDS", UI.Colors.Blue, function()
			showOdds(odds :: string)
		end, { Size = UDim2.fromOffset(106, 48), Position = UDim2.new(1, -286, 1, -56), MaxSize = 18, Name = "Odds" })
	end
end

local function header(order: number, text: string)
	return UI.Text(scroll, text, { Size = UDim2.new(1, 0, 0, 40), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, Order = order, MaxSize = 30, Gold = true, Outline = 2.5, Name = "Header" })
end

local function grid(order: number, count: number, name: string): Frame
	local rows = math.max(1, math.ceil(count / 2))
	local frame = UI.Frame(scroll, { Size = UDim2.new(1, 0, 0, rows * 128 + (rows - 1) * 12), Transparency = 1, Radius = false, Order = order, Name = name })
	UI.Create("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 128), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
	return frame
end

-- Big card at the top that opens the Premium Core shop
local function premiumHero(order: number, data: any)
	local zone = tonumber(data.premiumZone) or Items.PremiumZone(data.zones)
	local hero = UI.Panel(scroll, { Size = UDim2.new(1, 0, 0, 150), Top = rgb(124, 52, 214), Bottom = rgb(40, 18, 96), Border = Color3.new(1, 1, 1), BorderThickness = 4, Radius = 20, Order = order, Name = "Premium" })
	local border = hero:FindFirstChild("Border")
	if border then
		UI.Rainbow(border)
	end
	local orb = UI.Orb(hero, UI.Colors.Gold, 108, { Position = UDim2.new(0, 22, 0.5, 0), Anchor = Vector2.new(0, 0.5) })
	local ring = orb:FindFirstChild("Ring")
	if ring then
		UI.Rainbow(ring)
	end
	local title = UI.Text(hero, "PREMIUM " .. string.upper(Items.CoreName(zone)), { Size = UDim2.new(1, -380, 0, 50), Position = UDim2.fromOffset(150, 18), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, MaxSize = 38, Outline = 3.5, Name = "Title" })
	title.TextColor3 = Color3.new(1, 1, 1)
	UI.Rainbow(title)
	UI.Text(hero, "Rare or better every time — opens instantly. See every item and its chance before you buy!", { Size = UDim2.new(1, -380, 0, 44), Position = UDim2.fromOffset(150, 72), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 16, Outline = 1.5 })
	local one = price("PremiumCore", Config.Products.PremiumCore.id, Config.Products.PremiumCore.price, Enum.InfoType.Product)
	UI.Chip(hero, "FROM R$ " .. one, rgb(60, 30, 120), { Size = UDim2.fromOffset(130, 26), Position = UDim2.fromOffset(150, 114), MaxSize = 14 })
	UI.Button(hero, "VIEW & BUY", UI.Colors.Robux, function()
		if opener then
			(opener :: (string) -> ())("premium")
		end
	end, { Size = UDim2.fromOffset(200, 64), Position = UDim2.new(1, -218, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 24, Name = "OpenPremium" })
end

function ShopPanel.SetOpener(fn: (string) -> ())
	opener = fn
end

function ShopPanel.Build(content: Frame)
	scroll = UI.Scroll(content, { Gap = 10 })
	built = true
end

function ShopPanel.Refresh(data: any)
	if not built or not data then
		return
	end
	UI.Clear(scroll)
	local restricted = data.restricted == true
	if restricted then
		UI.Chip(scroll, "🌍 Some items aren't available in your country", UI.Colors.Card, { Size = UDim2.new(1, 0, 0, 34), Order = 0, MaxSize = 16, Radius = 12, Font = UI.Fonts.Bold, TextColor = UI.Colors.Muted })
	else
		premiumHero(0, data)
	end

	header(1, "⚡ BOOSTS")
	local boosts = {}
	for _, boost in BOOSTS do
		if not (restricted and isPaidRandom(Config.PaidRandom.products, boost.name)) then
			table.insert(boosts, boost)
		end
	end
	local boostGrid = grid(2, #boosts, "Boosts")
	for i, boost in boosts do
		local product = Config.Products[boost.name]
		local robux = price(boost.name, product.id, product.price, Enum.InfoType.Product)
		card(boostGrid, i, boost.icon, boost.color, boost.title, boost.desc, "R$ " .. robux, UI.Colors.Robux, true, function()
			State.Request("buyProduct", { name = boost.name })
		end, ODDS[boost.name] and boost.name or nil, iconOf(boost.name, product))
	end

	header(3, "🎟️ GAME PASSES")
	local passes = {}
	for _, name in PASS_ORDER do
		if not (restricted and isPaidRandom(Config.PaidRandom.passes, name)) then
			table.insert(passes, name)
		end
	end
	local passGrid = grid(4, #passes, "Passes")
	for i, name in passes do
		local pass = Config.Passes[name]
		local owned = data.passes and data.passes[name] == true
		local robux = price("pass_" .. name, pass.id, pass.price, Enum.InfoType.GamePass)
		local look = PASS_LOOK[name] or { "⭐", UI.Colors.Blue }
		card(passGrid, i, look[1], look[2], pass.name, pass.desc, owned and "OWNED ✓" or ("R$ " .. robux), owned and UI.Colors.CardHi or UI.Colors.Robux, not owned, function()
			if not owned then
				State.Request("buyPass", { name = name })
			end
		end, ODDS[name] and name or nil, iconOf("pass_" .. name, pass))
	end
	UI.Text(scroll, "Waiting is always free. A Core can never be bought back or protected with Robux.", { Size = UDim2.new(1, 0, 0, 40), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, Order = 5, MaxSize = 15 })
end

return ShopPanel
