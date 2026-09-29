--[[
	BasePanel — Incubators, Storage, Upgrades and the Forge.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local BasePanel = {}

local containers: { [string]: Frame } = {}
local current = "inc"
local built = false
local selectTab: ((string) -> ())? = nil

local incScroll: ScrollingFrame
local openAllButton: TextButton
local autoButton: TextButton
local speedChip: TextLabel
local creditsChip: TextLabel
local storeScroll: ScrollingFrame
local storeCount: TextLabel
local upScroll: ScrollingFrame
local forgeFragments: TextLabel
local forgeFill: Frame
local forgeTarget: TextLabel
local forgeChips: { TextLabel } = {}
local forgeButton: TextButton

type Timer = { label: TextLabel, bar: Frame, s: number, e: number }
local timers: { Timer } = {}
local prices: { [number]: number } = {}

local UPGRADE_LOOK = {
	train = { "⚡", Color3.fromRGB(255, 150, 40) },
	luck = { "🍀", Color3.fromRGB(60, 200, 90) },
	slots = { "🥚", Color3.fromRGB(70, 150, 255) },
	speed = { "⏩", Color3.fromRGB(40, 190, 220) },
	storage = { "📦", Color3.fromRGB(200, 130, 60) },
	carry = { "💪", Color3.fromRGB(235, 80, 80) },
	style = { "🏰", Color3.fromRGB(160, 90, 255) },
}

local function priceOf(product: any): number
	if product.id and product.id > 0 then
		if prices[product.id] then
			return prices[product.id]
		end
		prices[product.id] = product.price
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				prices[product.id] = info.PriceInRobux
				if State.Data then
					BasePanel.Refresh(State.Data)
				end
			end
		end)
	end
	return product.price
end

local function skipFor(remaining: number): (number?, any)
	for tier, product in Config.Products.Skips do
		if product.max >= remaining then
			return tier, product
		end
	end
	return nil, nil
end

local function hasCredit(data: any, remaining: number): boolean
	for tier, product in Config.Products.Skips do
		if (data.skips[tier] or 0) > 0 and product.max >= remaining then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Incubators
--------------------------------------------------------------------------------
local function cardButton(card: Frame, text: string, color: Color3, onClick: () -> ()): TextButton
	return UI.Button(card, text, color, onClick, { Size = UDim2.new(1, -20, 0, 46), Position = UDim2.new(0, 10, 1, -54), MaxSize = 19 })
end

local function incCard(slot: number, data: any)
	local entry = data.inc[slot]
	local locked = slot > data.slots
	local now = State.Now()
	if locked then
		local card = UI.Card(incScroll, { Color = Color3.fromRGB(26, 28, 62), Order = slot, Name = "Locked" })
		UI.Text(card, "🔒", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, 0, 0, 10), Anchor = Vector2.new(0.5, 0), MaxSize = 38 })
		UI.Text(card, "LOCKED", { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 58), Font = UI.Fonts.Title, Color = UI.Colors.Muted, MaxSize = 21, Outline = 2 })
		UI.Text(card, "Incubator " .. slot, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 86), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 14 })
		cardButton(card, "UPGRADE", UI.Colors.Purple, function()
			if selectTab then
				selectTab("up")
			end
		end)
		return
	end
	if not entry then
		local card = UI.Card(incScroll, { Order = slot, Name = "Empty" })
		local ring = UI.Frame(card, { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0.5, 0, 0, 16), Anchor = Vector2.new(0.5, 0), Color = Color3.new(1, 1, 1), Transparency = 0.93, Radius = 28 })
		UI.Stroke(ring, Color3.new(1, 1, 1), 2, 0.6)
		UI.Text(ring, "+", { Size = UDim2.fromScale(1, 1), Font = UI.Fonts.Title, Color = UI.Colors.Muted, MaxSize = 30 })
		UI.Text(card, "EMPTY", { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 84), Font = UI.Fonts.Title, MaxSize = 21, Outline = 2 })
		UI.Text(card, "Deliver a Core to fill it", { Size = UDim2.new(1, -24, 0, 36), Position = UDim2.fromOffset(12, 112), Color = UI.Colors.Muted, MaxSize = 14 })
		return
	end
	local color = Items.RarityColor(entry.r)
	local remaining = entry.e - now
	local ready = remaining <= 0
	local card = UI.Card(incScroll, { Order = slot, Tint = color, TintAmount = 0.2, Accent = ready and UI.Colors.Good or color, AccentT = ready and 0 or 0.25, AccentThickness = ready and 3 or 2, Name = ready and "Ready" or "Incubating" })
	local title = UI.Text(card, Items.CoreTitle(entry.z, entry.r), { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 7), Font = UI.Fonts.Title, MaxSize = 18, Outline = 2, Name = "Title" })
	UI.StyleRarity(title, entry.r)
	UI.Orb(card, color, 40, { Position = UDim2.fromOffset(14, 52) })
	local sub = UI.Text(card, "", { Size = UDim2.new(1, -74, 0, 30), Position = UDim2.fromOffset(62, 57), Font = UI.Fonts.Black, AlignX = Enum.TextXAlignment.Left, MaxSize = 20, Outline = 2, Name = "Timer" })
	local _, bar = UI.Bar(card, color, { Size = UDim2.new(1, -24, 0, 12), Position = UDim2.fromOffset(12, 100) })
	if ready then
		sub.Text = "✨ READY!"
		sub.TextColor3 = UI.Colors.Good
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = UI.Colors.Good
		cardButton(card, "OPEN", UI.Colors.Good, function()
			State.Request("open", { slot = slot })
		end)
	else
		table.insert(timers, { label = sub, bar = bar, s = entry.s, e = entry.e })
		sub.Text = "⏳ " .. Util.Clock(remaining)
		bar.Size = UDim2.fromScale(math.clamp(1 - remaining / math.max(entry.e - entry.s, 1), 0, 1), 1)
		if hasCredit(data, remaining) then
			cardButton(card, "🎟️ USE SKIP", UI.Colors.Purple, function()
				State.Request("useSkipCredit", { slot = slot })
			end)
		else
			local _, product = skipFor(remaining)
			if product then
				cardButton(card, "⚡ OPEN NOW  R$" .. priceOf(product), UI.Colors.Robux, function()
					State.Request("buySkip", { slot = slot })
				end)
			end
		end
	end
end

local function refreshIncubators(data: any)
	UI.Clear(incScroll)
	table.clear(timers)
	local shown = math.min(12, math.max(data.slots + 1, 5))
	for slot = 1, shown do
		incCard(slot, data)
	end
	local ready = 0
	local now = State.Now()
	for i = 1, data.slots do
		local entry = data.inc[i]
		if entry and entry.e <= now then
			ready += 1
		end
	end
	openAllButton.Text = ready > 0 and ("OPEN ALL (" .. ready .. ")") or "OPEN ALL"
	UI.SetEnabled(openAllButton, ready > 0, UI.Colors.Good)
	local auto = data.settings.autoIncubate ~= false
	autoButton.Text = "AUTO-INCUBATE: " .. (auto and "ON" or "OFF")
	autoButton.BackgroundColor3 = auto and Color3.fromRGB(56, 120, 220) or UI.Colors.CardHi
	local credits = 0
	for _, n in data.skips do
		credits += n
	end
	local mult = data.incubationMult or 1
	speedChip.Text = string.format("⏩ SPEED x%.2f", 1 / mult)
	creditsChip.Text = "🎟️ " .. credits .. (credits == 1 and " SKIP CREDIT" or " SKIP CREDITS")
	creditsChip.Visible = credits > 0
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------
local function refreshStorage(data: any)
	UI.Clear(storeScroll)
	storeCount.Text = string.format("%d / %d", #data.store, data.storageCap)
	storeCount.BackgroundColor3 = #data.store >= data.storageCap and UI.Colors.Bad or UI.Colors.CardHi
	local free = false
	for i = 1, data.slots do
		if not data.inc[i] then
			free = true
		end
	end
	for index, info in data.store do
		local color = Items.RarityColor(info.r)
		local row = UI.Card(storeScroll, { Size = UDim2.new(1, 0, 0, 66), Tint = color, TintAmount = 0.14, Accent = color, AccentT = 0.45, Order = index, Name = "Stored" })
		UI.Orb(row, color, 44, { Position = UDim2.fromOffset(12, 11) })
		local name = UI.Text(row, Items.CoreTitle(info.z, info.r), { Size = UDim2.new(1, -260, 0, 28), Position = UDim2.fromOffset(68, 7), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 21, Outline = 2 })
		UI.StyleRarity(name, info.r)
		UI.Text(row, Util.Odds(info.odds or 1) .. "  •  from " .. tostring(info.mob) .. "  •  ⏳ " .. Util.Duration(Items.IncubateTime(info.z, info.r) * (data.incubationMult or 1)), { Size = UDim2.new(1, -260, 0, 20), Position = UDim2.fromOffset(68, 37), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 14 })
		local button = UI.Button(row, "INCUBATE", UI.Colors.Blue, function()
			State.Request("incubate", { index = index })
		end, { Size = UDim2.fromOffset(170, 50), Position = UDim2.new(1, -182, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 20 })
		UI.SetEnabled(button, free, UI.Colors.Blue)
	end
	if #data.store == 0 then
		local empty = UI.Card(storeScroll, { Size = UDim2.new(1, 0, 0, 96), Order = 1, Name = "Empty" })
		UI.Text(empty, "📭", { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0, 22, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 44 })
		UI.Text(empty, "Storage is empty. When every incubator is busy, delivered Cores wait here.", { Size = UDim2.new(1, -120, 1, -24), Position = UDim2.fromOffset(96, 12), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 18 })
	end
end

--------------------------------------------------------------------------------
-- Upgrades
--------------------------------------------------------------------------------
local function pct(v: number): string
	local p = v * 100
	if math.abs(p - math.floor(p + 0.5)) < 0.01 then
		return tostring(math.floor(p + 0.5)) .. "%"
	end
	return string.format("%.1f%%", p)
end

-- "now → next" text for an upgrade row
local function upgradeEffect(id: string, level: number): string
	local u = Config.Upgrades[id]
	local maxed = level >= Items.MaxLevel(id)
	local function arrow(now: string, nextText: string): string
		return maxed and (now .. " (MAX)") or (now .. " → " .. nextText)
	end
	if id == "train" then
		return arrow(string.format("Power x%.2f", 1 + level * u.per), string.format("x%.2f", 1 + (level + 1) * u.per))
	elseif id == "luck" then
		return arrow("+" .. pct(level * u.per) .. " luck", "+" .. pct((level + 1) * u.per))
	elseif id == "slots" then
		return arrow((u.values[level + 1] or 0) .. " slots", tostring(u.values[level + 2] or ""))
	elseif id == "speed" then
		return arrow("-" .. pct(level * u.per) .. " time", "-" .. pct((level + 1) * u.per))
	elseif id == "storage" then
		return arrow(Items.StorageCap(level) .. " Cores", tostring(Items.StorageCap(level + 1)))
	elseif id == "style" then
		local names = u.levels or {}
		return arrow(level > 0 and (names[level] or ("Level " .. level)) or "Plain", names[level + 1] or "")
	elseif id == "carry" then
		return arrow(string.format("-%s slowdown, +%.1fs shield", pct(level * u.per), level * u.shield), string.format("-%s, +%.1fs", pct((level + 1) * u.per), (level + 1) * u.shield))
	end
	return arrow("Level " .. level, tostring(level + 1))
end

local function refreshUpgrades(data: any)
	UI.Clear(upScroll)
	local ids = {}
	for id in Config.Upgrades do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return Config.Upgrades[a].order < Config.Upgrades[b].order
	end)
	for _, id in ids do
		local u = Config.Upgrades[id]
		local level = data.up[id] or 0
		local cost = Items.UpgradeCost(id, level)
		local look = UPGRADE_LOOK[id] or { "⭐", UI.Colors.Blue }
		local row = UI.Card(upScroll, { Size = UDim2.new(1, 0, 0, 72), Order = u.order, Name = "Upgrade" })
		UI.Badge(row, look[1], look[2], 52, { Position = UDim2.fromOffset(10, 10) })
		UI.Text(row, string.upper(u.name), { Size = UDim2.new(1, -400, 0, 28), Position = UDim2.fromOffset(74, 7), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 21, Outline = 2 })
		UI.Chip(row, "LV " .. level, cost and UI.Colors.CardHi or UI.Colors.Good, { Size = UDim2.fromOffset(86, 26), Position = UDim2.new(1, -300, 0, 9), MaxSize = 14 })
		UI.Text(row, u.desc .. "   •   " .. UI.Span(upgradeEffect(id, level), Color3.fromRGB(130, 240, 150)), { Size = UDim2.new(1, -300, 0, 22), Position = UDim2.fromOffset(74, 40), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 14, Rich = true })
		local label = cost and ("💰 " .. Util.Abbrev(cost)) or "MAX"
		local button = UI.Button(row, label, UI.Colors.Gold, function()
			State.Request("upgrade", { id = id })
		end, { Size = UDim2.fromOffset(184, 50), Position = UDim2.new(1, -196, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 22 })
		UI.SetEnabled(button, cost ~= nil and data.coins >= cost, UI.Colors.Gold)
	end
end

--------------------------------------------------------------------------------
-- Forge
--------------------------------------------------------------------------------
local function refreshForge(data: any)
	local zone = data.forgeZone or data.zones or 1
	local cost = Config.Forge.cost
	forgeFragments.Text = "💎 " .. Util.Commas(data.fragments) .. " / " .. Util.Commas(cost) .. " FRAGMENTS"
	UI.Tween(forgeFill, 0.3, { Size = UDim2.fromScale(math.clamp(data.fragments / cost, 0, 1), 1) })
	forgeTarget.Text = "Forges a " .. UI.Span(string.upper(Items.CoreName(zone)), Items.CoreColor(zone)) .. " (the zone you last fought in) straight into your base:"
	local total = 0
	for _, entry in Config.Forge.odds do
		total += entry[2]
	end
	for i, entry in Config.Forge.odds do
		local chip = forgeChips[i]
		if chip then
			chip.Text = string.format("%s %d%%", Config.Rarities[entry[1]].name, math.floor(entry[2] / total * 100 + 0.5))
		end
	end
	UI.SetEnabled(forgeButton, data.fragments >= cost, UI.Colors.Purple)
end

--------------------------------------------------------------------------------
function BasePanel.Build(content: Frame)
	local function container(id: string): Frame
		local f = UI.Frame(content, { Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Transparency = 1, Radius = false, Visible = false, Name = id })
		containers[id] = f
		return f
	end

	-- Incubators
	local inc = container("inc")
	local top = UI.Frame(inc, { Size = UDim2.new(1, 0, 0, 46), Transparency = 1, Radius = false, Name = "Toolbar" })
	openAllButton = UI.Button(top, "OPEN ALL", UI.Colors.Good, function()
		State.Request("openAll")
	end, { Size = UDim2.fromOffset(200, 46), MaxSize = 22 })
	autoButton = UI.Button(top, "AUTO-INCUBATE: ON", UI.Colors.CardHi, function()
		local data = State.Data
		if data then
			State.Request("settings", { autoIncubate = data.settings.autoIncubate == false })
		end
	end, { Size = UDim2.fromOffset(250, 46), Position = UDim2.fromOffset(212, 0), MaxSize = 18 })
	local chips = UI.Frame(top, { Size = UDim2.new(1, -474, 1, 0), Position = UDim2.new(1, 0, 0, 0), Anchor = Vector2.new(1, 0), Transparency = 1, Radius = false, Name = "Chips" })
	local chipList = UI.List(chips, 8, true, Enum.HorizontalAlignment.Right)
	chipList.VerticalAlignment = Enum.VerticalAlignment.Center
	speedChip = UI.Chip(chips, "", UI.Colors.CardHi, { Size = UDim2.fromOffset(150, 34), Order = 1, MaxSize = 15 })
	creditsChip = UI.Chip(chips, "", UI.Colors.Purple, { Size = UDim2.fromOffset(196, 34), Order = 2, MaxSize = 15 })
	incScroll = UI.Scroll(inc, { Size = UDim2.new(1, 0, 1, -56), Position = UDim2.fromOffset(0, 56), Grid = UDim2.fromOffset(196, 172), Gap = 12 })

	-- Storage
	local store = container("store")
	local head = UI.Frame(store, { Size = UDim2.new(1, 0, 0, 44), Transparency = 1, Radius = false, Name = "Header" })
	UI.Text(head, "📦 CORE STORAGE", { Size = UDim2.fromOffset(250, 40), Position = UDim2.fromOffset(4, 2), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 26, Outline = 2.5, Gold = true })
	storeCount = UI.Chip(head, "0 / 0", UI.Colors.CardHi, { Size = UDim2.fromOffset(96, 32), Position = UDim2.fromOffset(260, 6), MaxSize = 18 })
	UI.Text(head, "Secured Cores wait here for a free incubator", { Size = UDim2.new(1, -380, 0, 30), Position = UDim2.new(1, 0, 0, 7), Anchor = Vector2.new(1, 0), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Right, MaxSize = 15 })
	storeScroll = UI.Scroll(store, { Size = UDim2.new(1, 0, 1, -54), Position = UDim2.fromOffset(0, 54) })

	-- Upgrades
	local up = container("up")
	upScroll = UI.Scroll(up, {})

	-- Forge
	local forge = container("forge")
	local card = UI.Panel(forge, { Size = UDim2.new(1, 0, 1, -4), Top = Color3.fromRGB(78, 44, 150), Bottom = Color3.fromRGB(30, 22, 70), Border = Color3.fromRGB(190, 130, 255), BorderThickness = 3, Radius = 20, Name = "Forge" })
	UI.Badge(card, "⚒️", UI.Colors.Purple, 150, { Position = UDim2.fromOffset(36, 40), RingThickness = 5 })
	UI.Text(card, "THE FORGE", { Size = UDim2.new(1, -250, 0, 52), Position = UDim2.fromOffset(222, 22), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, MaxSize = 48, Gold = true, Outline = 3 })
	UI.Text(card, "Fragments drop from every monster you defeat. Spend them to forge a Core that goes straight into your base.", { Size = UDim2.new(1, -250, 0, 44), Position = UDim2.fromOffset(222, 76), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 17 })
	local fragBack
	fragBack, forgeFill = UI.Bar(card, UI.Colors.Cyan, { Size = UDim2.new(1, -250, 0, 32), Position = UDim2.fromOffset(222, 128) })
	forgeFragments = UI.Text(fragBack, "", { Size = UDim2.new(1, -20, 1, -6), Position = UDim2.fromOffset(10, 3), Font = UI.Fonts.Black, MaxSize = 17, Outline = 2, Z = 2 })
	forgeTarget = UI.Text(card, "", { Size = UDim2.new(1, -250, 0, 40), Position = UDim2.fromOffset(222, 170), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 16, Rich = true, Outline = 1.5 })
	local oddsRow = UI.Frame(card, { Size = UDim2.new(1, -250, 0, 30), Position = UDim2.fromOffset(222, 216), Transparency = 1, Radius = false, Name = "Odds" })
	UI.List(oddsRow, 8, true)
	for i, entry in Config.Forge.odds do
		forgeChips[i] = UI.Chip(oddsRow, "", UI.Shade(Config.Rarities[entry[1]].color, -0.35), { Size = UDim2.fromOffset(134, 30), Order = i, MaxSize = 15 })
	end
	forgeButton = UI.Button(card, "⚒️ FORGE A CORE", UI.Colors.Purple, function()
		State.Request("forge")
	end, { Size = UDim2.fromOffset(340, 72), Position = UDim2.new(0.5, 0, 1, -26), Anchor = Vector2.new(0.5, 1), MaxSize = 30 })

	selectTab = UI.Tabs(content, {
		{ id = "inc", label = "🥚 INCUBATORS", width = 206 },
		{ id = "store", label = "📦 STORAGE", width = 176 },
		{ id = "up", label = "⬆️ UPGRADES", width = 188 },
		{ id = "forge", label = "⚒️ FORGE", width = 150 },
	}, function(id)
		current = id
		for key, frame in containers do
			frame.Visible = key == id
		end
		if State.Data then
			BasePanel.Refresh(State.Data)
		end
	end)
	built = true
	if selectTab then
		selectTab(current)
	end

	-- live timers
	task.spawn(function()
		while true do
			task.wait(0.5)
			if containers.inc.Visible and containers.inc.Parent and #timers > 0 then
				local now = State.Now()
				local needRefresh = false
				for _, timer in timers do
					local left = timer.e - now
					if left <= 0 then
						needRefresh = true
					else
						timer.label.Text = "⏳ " .. Util.Clock(left)
						local total = math.max(timer.e - timer.s, 1)
						timer.bar.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
					end
				end
				if needRefresh and State.Data then
					BasePanel.Refresh(State.Data)
				end
			end
		end
	end)
end

function BasePanel.Refresh(data: any)
	if not built or not data then
		return
	end
	if current == "inc" then
		refreshIncubators(data)
	elseif current == "store" then
		refreshStorage(data)
	elseif current == "up" then
		refreshUpgrades(data)
	elseif current == "forge" then
		refreshForge(data)
	end
end

return BasePanel
