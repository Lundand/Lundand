--[[
	PremiumPanel — the Robux "Premium Core", shown like an egg shop: every item of the pool as a spinning 3D
	model with its chance, the rarity chances, buy buttons for 1 or 3 Cores, and a DETAILS list of every
	possible result. Roblox's paid-random-items rules: all odds are shown before buying, and players where
	these items are restricted only see a notice.
	The 3D models are built only when the pool's zone changes and only spin while this panel is open.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Models = require(Shared:WaitForChild("Models"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Popup = require(script.Parent.Popup)

local PremiumPanel = {}

type View = { cam: Camera, center: Vector3, dist: number, lift: number, phase: number }

local built = false
local main: Frame
local blocked: Frame
local banner: TextLabel
local columns: { [string]: Frame } = {}
local columnHeads: { [string]: TextLabel } = {}
local views: { View } = {}
local builtZone = 0
local spin: RBXScriptConnection? = nil
local angle = 0
local priceLabels: { [string]: TextLabel } = {}
local saveChip: TextLabel
local prices: { [string]: number } = {}
local rgb = Color3.fromRGB

local REPRESENTATIVE_RARITY = 3 -- models are shown as Rare (the lowest rarity a Premium Core gives)
local SLOTS = {
	{ id = "w", icon = "⚔️", title = "WEAPONS", color = rgb(240, 110, 60), build = Models.Weapon },
	{ id = "c", icon = "🛡️", title = "CLASSES", color = rgb(64, 140, 255), build = Models.ClassEmblem },
	{ id = "a", icon = "✨", title = "ABILITIES", color = rgb(150, 90, 255), build = Models.AbilityTome },
}

local function price(name: string): number
	local product = Config.Products[name]
	local cached = prices[name]
	if cached then
		return cached
	end
	prices[name] = product.price
	if product.id > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				prices[name] = info.PriceInRobux
				if State.Data then
					PremiumPanel.Refresh(State.Data)
				end
			end
		end)
	end
	return product.price
end

local function zoneOf(data: any): number
	return tonumber(data.premiumZone) or Items.PremiumZone(data.zones)
end

--------------------------------------------------------------------------------
-- 3D item cards
--------------------------------------------------------------------------------
local function aim(view: View)
	local a = angle + view.phase
	local pos = view.center + Vector3.new(math.sin(a) * view.dist, view.lift, math.cos(a) * view.dist)
	view.cam.CFrame = CFrame.lookAt(pos, view.center)
end

local function viewport(parent: Instance, key: string, builder: (string) -> Model, phase: number)
	local vf = UI.Create("ViewportFrame", {
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Ambient = rgb(170, 170, 190),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.6, -1, -0.5),
		Name = "Model",
		Parent = parent,
	})
	local ok, result = pcall(builder, key)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[Premium] could not build a model for " .. key)
		return
	end
	local model = result :: Model
	Models.SetAnchored(model, true)
	local cf, size = model:GetBoundingBox()
	model.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vf
	vf.CurrentCamera = cam
	local radius = math.max(size.X, size.Y, size.Z) * 0.5 * 1.1
	local view: View = { cam = cam, center = cf.Position, dist = radius / math.tan(math.rad(15)), lift = radius * 0.35, phase = phase }
	aim(view)
	table.insert(views, view)
end

local function buildCards(zone: number)
	for _, column in columns do
		for _, child in column:GetChildren() do
			if child:IsA("GuiObject") and child.Name == "Item" then
				child:Destroy()
			end
		end
	end
	table.clear(views)
	local totals = { w = 0, c = 0, a = 0 }
	for n, entry in Items.PoolOdds(zone) do
		totals[entry.c] += entry.chance
		local look = SLOTS[entry.c == "w" and 1 or entry.c == "c" and 2 or 3]
		local card = UI.Card(columns[entry.c], { Size = UDim2.new(1, 0, 0, 108), Order = 1 + entry.i, Tint = look.color, TintAmount = 0.16, Accent = look.color, AccentT = 0.35, Name = "Item" })
		viewport(card, Items.Key(zone, entry.c, entry.i, REPRESENTATIVE_RARITY), look.build, n * 0.7)
		UI.Text(card, entry.name, { Size = UDim2.new(1, -110, 0, 38), Position = UDim2.fromOffset(104, 8), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 17, Outline = 2, Name = "Name" })
		UI.Text(card, UI.Percent(entry.chance), { Size = UDim2.new(1, -110, 0, 50), Position = UDim2.fromOffset(104, 48), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, MaxSize = 36, Gold = true, Outline = 3, Name = "Chance" })
	end
	for id, head in columnHeads do
		local look = SLOTS[id == "w" and 1 or id == "c" and 2 or 3]
		head.Text = look.icon .. " " .. look.title .. "  " .. UI.Percent(totals[id])
	end
	builtZone = zone
end

--------------------------------------------------------------------------------
-- Details popup: every final result (item × rarity)
--------------------------------------------------------------------------------
local function details(content: Frame)
	local data = State.Data
	if not data then
		return
	end
	local zone = zoneOf(data)
	local scroll = UI.Scroll(content, { Gap = 4 })
	UI.Text(scroll, "Every " .. UI.Span("PREMIUM " .. string.upper(Items.CoreName(zone)), UI.Colors.GoldLight) .. " holds exactly one item. The chance of each result:", { Size = UDim2.new(1, 0, 0, 44), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, Rich = true, MaxSize = 17, Outline = 1.5, Order = 1 })
	local rows = {}
	for _, entry in Items.PoolOdds(zone) do
		for _, rarity in Items.PremiumOdds() do
			table.insert(rows, { key = Items.Key(zone, entry.c, entry.i, rarity.r), r = rarity.r, c = entry.c, chance = entry.chance * rarity.chance })
		end
	end
	table.sort(rows, function(a, b)
		if math.abs(a.chance - b.chance) > 1e-12 then
			return a.chance > b.chance
		end
		return a.key < b.key
	end)
	for i, row in rows do
		local line = UI.Frame(scroll, { Size = UDim2.new(1, 0, 0, 32), Color = i % 2 == 0 and UI.Colors.Card or UI.Colors.CardHi, Transparency = 0.25, Radius = 8, Order = 10 + i, Name = "Result" })
		local look = SLOTS[row.c == "w" and 1 or row.c == "c" and 2 or 3]
		UI.Text(line, look.icon, { Size = UDim2.fromOffset(30, 26), Position = UDim2.new(0, 6, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 20 })
		local name = UI.Text(line, Items.FullName(row.key), { Size = UDim2.new(1, -170, 1, -6), Position = UDim2.fromOffset(42, 3), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 18, Outline = 2 })
		UI.StyleRarity(name, row.r)
		UI.Text(line, UI.Percent(row.chance), { Size = UDim2.new(0, 120, 1, -6), Position = UDim2.new(1, -10, 0, 3), Anchor = Vector2.new(1, 0), Font = UI.Fonts.Black, AlignX = Enum.TextXAlignment.Right, MaxSize = 17, Outline = 1.5 })
	end
	UI.Text(scroll, "Rounded — the exact chances add up to 100%.", { Size = UDim2.new(1, 0, 0, 32), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 15, Order = 1000 })
end

--------------------------------------------------------------------------------
local function buyButton(parent: Instance, name: string, y: number): TextButton
	local button = UI.Button(parent, "", UI.Colors.Robux, function()
		State.Request("buyProduct", { name = name })
	end, { Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, y), Name = "Buy_" .. name })
	UI.RobuxIcon(button, 28, { Position = UDim2.new(0, 6, 0.5, 0), Anchor = Vector2.new(0, 0.5) })
	-- a short box keeps TextScaled on one line ("249 · 3 CORES")
	priceLabels[name] = UI.Text(button, "", { Size = UDim2.new(1, -44, 0, 30), Position = UDim2.new(0, 42, 0.5, 0), Anchor = Vector2.new(0, 0.5), Font = UI.Fonts.Title, MaxSize = 25, Wrap = false, Outline = 2, OutlineColor = UI.Shade(UI.Colors.Robux, -0.62), Name = "Price" })
	return button
end

function PremiumPanel.Build(content: Frame)
	main = UI.Frame(content, { Size = UDim2.fromScale(1, 1), Transparency = 1, Radius = false, Name = "Main" })
	banner = UI.Text(main, "PREMIUM CORE", { Size = UDim2.new(1, 0, 0, 56), Font = UI.Fonts.Display, MaxSize = 50, Outline = 4, Name = "Banner" })
	banner.TextColor3 = Color3.new(1, 1, 1)
	UI.Rainbow(banner)

	-- rarity chances
	local strip = UI.Frame(main, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 62), Transparency = 1, Radius = false, Name = "Rarities" })
	UI.List(strip, 8, true, Enum.HorizontalAlignment.Center).VerticalAlignment = Enum.VerticalAlignment.Center
	for i, rarity in Items.PremiumOdds() do
		local def = Config.Rarities[rarity.r]
		UI.Chip(strip, string.upper(def.name) .. "  " .. UI.Percent(rarity.chance), UI.Shade(def.color, -0.35), { Size = UDim2.fromOffset(152, 34), Order = i, MaxSize = 16, Font = UI.Fonts.Title })
	end

	-- 3 columns of item cards (weapons / classes / abilities)
	for n, look in SLOTS do
		local column = UI.Frame(main, { Size = UDim2.fromOffset(200, 384), Position = UDim2.fromOffset((n - 1) * 210, 104), Transparency = 1, Radius = false, Name = "Column_" .. look.id })
		UI.List(column, 8)
		columnHeads[look.id] = UI.Chip(column, look.title, UI.Shade(look.color, -0.3), { Size = UDim2.new(1, 0, 0, 30), Order = 0, MaxSize = 16, Font = UI.Fonts.Title })
		columns[look.id] = column
	end

	-- buy side
	local side = UI.Frame(main, { Size = UDim2.new(1, -640, 0, 384), Position = UDim2.new(1, 0, 0, 104), Anchor = Vector2.new(1, 0), Transparency = 1, Radius = false, Name = "Buy" })
	local orb = UI.Orb(side, UI.Colors.Gold, 104, { Position = UDim2.new(0.5, 0, 0, 0), Anchor = Vector2.new(0.5, 0), Name = "Core" })
	local ring = orb:FindFirstChild("Ring")
	if ring then
		UI.Rainbow(ring)
	end
	UI.Text(side, "RARE OR BETTER!", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 108), Font = UI.Fonts.Title, MaxSize = 21, Gold = true, Outline = 2 })
	buyButton(side, "PremiumCore", 140)
	buyButton(side, "PremiumCore3", 212)
	saveChip = UI.Chip(side, "", UI.Colors.Bad, { Size = UDim2.fromOffset(100, 24), Position = UDim2.new(1, 8, 0, 198), Anchor = Vector2.new(1, 0), MaxSize = 14, Font = UI.Fonts.Title, Z = 3 })
	UI.Button(side, "📋 DETAILS", UI.Colors.Blue, function()
		Popup.Show("PREMIUM CORE — DETAILS", Color3.fromRGB(160, 90, 255), details)
	end, { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 288), MaxSize = 21, Name = "Details" })
	UI.Text(side, "Opens instantly — items go straight to your bag.", { Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 344), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 14 })

	-- restricted players only see this
	blocked = UI.Card(content, { Size = UDim2.new(1, -120, 0, 220), Position = UDim2.fromScale(0.5, 0.45), Anchor = Vector2.new(0.5, 0.5), Name = "Blocked", Visible = false })
	UI.Text(blocked, "🌍", { Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0.5, 0, 0, 18), Anchor = Vector2.new(0.5, 0), MaxSize = 64 })
	UI.Text(blocked, "Premium Cores aren't available in your country", { Size = UDim2.new(1, -60, 0, 44), Position = UDim2.fromOffset(30, 104), Font = UI.Fonts.Title, MaxSize = 30, Outline = 2.5 })
	UI.Text(blocked, "Roblox doesn't allow paid random items where you play. Everything else in the game works as usual.", { Size = UDim2.new(1, -80, 0, 44), Position = UDim2.fromOffset(40, 154), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 16 })

	built = true
end

-- the models spin only while this panel is open
function PremiumPanel.OnOpen()
	if spin then
		return
	end
	spin = RunService.RenderStepped:Connect(function(dt)
		if not main.Visible then
			return
		end
		angle += dt * 0.9
		for _, view in views do
			aim(view)
		end
	end)
end

function PremiumPanel.OnClose()
	if spin then
		(spin :: RBXScriptConnection):Disconnect()
		spin = nil
	end
end

function PremiumPanel.Refresh(data: any)
	if not built or not data then
		return
	end
	local restricted = data.restricted == true
	main.Visible = not restricted
	blocked.Visible = restricted
	if restricted then
		return
	end
	local zone = zoneOf(data)
	banner.Text = "PREMIUM " .. string.upper(Items.CoreName(zone))
	if zone ~= builtZone then
		buildCards(zone)
	end
	local one, three = price("PremiumCore"), price("PremiumCore3")
	local count1 = Config.Products.PremiumCore.count or 1
	local count3 = Config.Products.PremiumCore3.count or 3
	priceLabels.PremiumCore.Text = one .. " · " .. count1 .. (count1 == 1 and " CORE" or " CORES")
	priceLabels.PremiumCore3.Text = three .. " · " .. count3 .. " CORES"
	local save = 1 - (three / count3) / math.max(one / count1, 1e-6)
	saveChip.Visible = save >= 0.01
	saveChip.Text = "SAVE " .. math.floor(save * 100 + 0.5) .. "%"
end

return PremiumPanel
