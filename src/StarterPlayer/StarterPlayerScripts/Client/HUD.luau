--[[
	HUD — always-on screen elements:
	* Slim POWER bar at the bottom (Power + progress to the next zone) with the health bar and zone warnings
	  above it, and a small
	  context tip at the top that fades after a few seconds
	* Coins / Fragments pills and active boost chips (top left, under the Roblox top bar)
	* menu buttons (Base with a "ready" badge, Items, Travel, Shop, Admin): left on PC, top right on touch
	* carry objective card ("Return to your base! 342m") with a DROP button
	* ability button with a draining cooldown veil + countdown, big attack button on touch screens
	Every group is anchored to a screen edge and scaled with UI.AutoScale; touch controls keep clear of
	Roblox's jump button, the menu keeps clear of the thumbstick.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Panels = require(script.Parent.Panels)
local World = require(script.Parent.World)

local HUD = {}

local player = Players.LocalPlayer
local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local HUD_FIT = 640 -- design height fitted to short (phone) screens

local zoneLabel: TextLabel
local powerLabel: TextLabel
local barFill: Frame
local barText: TextLabel
local coinsLabel: TextLabel
local fragLabel: TextLabel
local boostChips: { TextLabel } = {}
local tipFrame: Frame
local tipLabel: TextLabel
local progressGroup: Frame
local healthFill: Frame
local healthText: TextLabel
local lastTip = ""
local tipShownAt = 0
local TIP_SECONDS = 12 -- a tip shows this long, and again whenever it changes
local badgeFrame: Frame
local badge: TextLabel
local adminButton: TextButton
local carryCard: Frame
local carryOrb: Frame
local carryTitle: TextLabel
local carryDistance: TextLabel
local carryShield: TextLabel
local carryWarn: TextLabel
local abilityButton: TextButton
local abilityIcon: TextLabel
local abilityCountdown: TextLabel
local abilityName: TextLabel
local veil: Frame
local veilGradient: UIGradient
local ABILITY_COLOR = Color3.fromRGB(128, 84, 255)
local ABILITY_DIM = Color3.fromRGB(62, 54, 104)
local ABILITY_ICONS = {
	dash = "💨",
	bolt = "🔮",
	nova = "💥",
	buff = "📣",
	stun = "🌀",
	heal = "💚",
	strike = "⚡",
	meteor = "☄️",
	dot = "🔥",
	shield = "🛡️",
	drain = "🦇",
	shadowstep = "👤",
	warp = "✨",
}

HUD.AttackButton = nil :: TextButton?
HUD.AbilityButton = nil :: TextButton?
HUD.DropButton = nil :: TextButton?

local abilityReadyAt = 0
local abilityTotal = 1
local wasCooling = false

local function group(anchor: Vector2, pos: UDim2, size: Vector2, name: string, parent: Instance): Frame
	local f = UI.Frame(parent, { Size = UDim2.fromOffset(size.X, size.Y), Position = pos, Anchor = anchor, Transparency = 1, Radius = false, Name = name })
	local scale = UI.AutoScale(f, HUD_FIT)
	scale.Name = "AutoScale"
	return f
end

-- currency pill: icon badge on the left, big outlined number
local function pill(parent: Instance, order: number, icon: string, color: Color3, top: Color3, bottom: Color3): TextLabel
	local frame = UI.Panel(parent, { Size = UDim2.fromOffset(236, 48), Radius = 24, Border = color, BorderThickness = 2.5, Order = order, Name = "Pill", GlossHeight = 18 })
	UI.Badge(frame, icon, UI.Shade(color, -0.1), 54, { Position = UDim2.fromOffset(-8, -3) })
	local label = UI.Text(frame, "0", { Size = UDim2.new(1, -66, 1, -8), Position = UDim2.fromOffset(54, 5), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, MaxSize = 30, Outline = 2.5, Name = "Value" })
	label.TextColor3 = Color3.new(1, 1, 1)
	UI.Gradient(label, top, bottom, 90)
	return label
end

local function menuButton(parent: Instance, order: number, icon: string, text: string, color: Color3, panel: string): TextButton
	local button = UI.Button(parent, "", color, function()
		Panels.Toggle(panel)
	end, { Size = UDim2.fromOffset(80, 80), Order = order, Radius = 20, Name = "Menu_" .. panel })
	UI.Text(button, icon, { Size = UDim2.new(1, 0, 0.64, 0), Position = UDim2.fromOffset(0, 0), MaxSize = 38, Name = "Icon" })
	UI.Text(button, text, { Size = UDim2.new(1, 8, 0.34, 0), Position = UDim2.new(0.5, 0, 0.66, 0), Anchor = Vector2.new(0.5, 0), Font = UI.Fonts.Title, MaxSize = 16, Outline = 2, OutlineColor = UI.Shade(color, -0.65), Name = "Caption" })
	return button
end

-- carry objective card (above the POWER bar on PC, top centre on touch where the tip usually is)
local function makeCarry(parent: Instance, width: number, pos: UDim2, anchor: Vector2, withDrop: boolean)
	carryCard = UI.Panel(parent, { Size = UDim2.fromOffset(width, 96), Position = pos, Anchor = anchor, Border = UI.Colors.Gold, BorderThickness = 3, Radius = 20, Visible = false, Name = "Carry" })
	carryOrb = UI.Orb(carryCard, UI.Colors.Gold, 64, { Position = UDim2.fromOffset(14, 16) })
	local right = withDrop and 164 or 16
	UI.Text(carryCard, "📦 RETURN TO YOUR BASE!", { Size = UDim2.new(1, -(92 + right), 0, 18), Position = UDim2.fromOffset(92, 7), Font = UI.Fonts.Black, Color = UI.Colors.Gold, AlignX = Enum.TextXAlignment.Left, MaxSize = 14, Outline = 1.5, Name = "Goal" })
	carryTitle = UI.Text(carryCard, "", { Size = UDim2.new(1, -(92 + right), 0, 30), Position = UDim2.fromOffset(92, 25), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 26, Outline = 2.5, Rich = true, Name = "Title" })
	local row = UI.Frame(carryCard, { Size = UDim2.new(1, -(92 + right), 0, 26), Position = UDim2.fromOffset(92, 60), Transparency = 1, Radius = false, Name = "Chips" })
	UI.List(row, 6, true)
	carryDistance = UI.Chip(row, "🏠 0m", UI.Colors.Blue, { Size = UDim2.fromOffset(110, 26), Order = 1 })
	carryShield = UI.Chip(row, "🛡 0s", Color3.fromRGB(40, 170, 200), { Size = UDim2.fromOffset(70, 26), Order = 2 })
	carryWarn = UI.Chip(row, "⚠ CAN BE STOLEN!", UI.Colors.Bad, { Size = UDim2.fromOffset(190, 26), Order = 3, MaxSize = 15 })
	if withDrop then
		HUD.DropButton = UI.Button(carryCard, "DROP [G]", UI.Colors.Bad, nil, { Size = UDim2.fromOffset(136, 58), Position = UDim2.new(1, -150, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 24, Name = "Drop" })
	end
end

local function abilityWidgets(button: TextButton, size: number)
	local fillSize, fillPos = UI.ButtonFill(button)
	veil = UI.Frame(button, { Size = fillSize, Position = fillPos, Color = Color3.new(0, 0, 0), Radius = math.floor(size / 2), Name = "Veil", Visible = false })
	veilGradient = UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.35), Parent = veil })
	abilityIcon = UI.Text(button, "💨", { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), MaxSize = math.floor(size * 0.46), Name = "Icon", Z = 2 })
	abilityCountdown = UI.Text(button, "", { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Font = UI.Fonts.Display, MaxSize = math.floor(size * 0.42), Gold = true, Outline = 2.5, Name = "Countdown", Z = 3 })
	abilityCountdown.Visible = false
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------
local function nextGoal(data: any): (string, number, number, boolean)
	-- returns label, current, target, reachedAlready
	local power = data.power or 0
	local zones = data.zones or 1
	if zones < #Config.Zones then
		local nextZone = zones + 1
		local required = Items.Required(nextZone)
		return string.upper(Config.Zones[nextZone].name), power, required, power >= required
	end
	local rift = math.max(data.rift or 0, Config.Rift.StartZone - 1) + 1
	return "ENDLESS ZONE " .. rift, power, Items.Rec(rift), power >= Items.Rec(rift)
end

local function tipFor(data: any): string
	local carrying = player:GetAttribute("CarryTitle") ~= nil
	if carrying then
		return ""
	end
	local now = State.Now()
	for i = 1, data.slots or 1 do
		local entry = data.inc[i]
		if entry and entry.e <= now then
			return "✨ A Core is ready! Open the BASE menu to open it."
		end
	end
	local cores = workspace:FindFirstChild("GroundCores")
	if cores then
		for _, model in cores:GetChildren() do
			if model:GetAttribute("ReservedFor") == player.UserId then
				return "💎 Your Core is on the ground! Walk to it and hold [E] to pick it up."
			end
		end
	end
	if (data.invCount or 0) >= (data.invMax or Config.Inventory.Max) then
		return "🎒 Your inventory is full! Sell items in ITEMS to open more Cores."
	end
	local label, current, target, reached = nextGoal(data)
	if reached and data.zones < #Config.Zones then
		return "🚪 You're strong enough for the " .. label .. "! Walk through the gate."
	end
	if (data.stats and data.stats.kills or 0) < 3 then
		return "⚔ Head into the Grasslands and defeat monsters! (Click / tap to attack, Q for your ability)"
	end
	if (data.stats and data.stats.delivered or 0) < 1 then
		return "🍀 Monsters can drop Cores. Carry them home to open them!"
	end
	if current < target then
		return "⚡ " .. Util.Abbrev(target - current) .. " more Power for the " .. label .. ". Open Cores or buy Power Training!"
	end
	return ""
end

local function tipVisible(): boolean
	return player:GetAttribute("CarryTitle") == nil and tipLabel.Text ~= "" and os.clock() - tipShownAt < TIP_SECONDS
end

local function refresh(data: any)
	coinsLabel.Text = Util.Abbrev(data.coins or 0)
	fragLabel.Text = Util.Abbrev(data.fragments or 0)
	-- short form from 10K up (12.3K, 1.25M …) so the number always fits its spot
	powerLabel.Text = "⚡ " .. ((data.power or 0) >= 10000 and Util.Abbrev(data.power) or Util.Commas(math.floor(data.power or 0)))
	local label, current, target, reached = nextGoal(data)
	local ratio = target > 0 and math.clamp(current / target, 0, 1) or 1
	UI.Tween(barFill, 0.3, { Size = UDim2.fromScale(ratio, 1) })
	barFill.BackgroundColor3 = reached and UI.Colors.Good or UI.Colors.Gold
	if data.zones >= #Config.Zones then
		barText.Text = label .. "  ~⚡" .. Util.Abbrev(target)
	elseif reached then
		barText.Text = "✓ " .. label .. " — walk through the gate!"
	else
		barText.Text = string.format("%s  ⚡%s", label, Util.Abbrev(target))
	end
	adminButton.Visible = data.isAdmin == true

	local ready = 0
	local now = State.Now()
	for i = 1, data.slots or 1 do
		local entry = data.inc[i]
		if entry and entry.e <= now then
			ready += 1
		end
	end
	badgeFrame.Visible = ready > 0
	badge.Text = tostring(ready)
	local tip = tipFor(data)
	if tip ~= lastTip then
		lastTip = tip
		tipShownAt = os.clock()
	end
	tipLabel.Text = tip
	tipFrame.Visible = tipVisible()
	local key = data.eq and data.eq.a
	if key then
		local def = Items.Ability(key)
		abilityIcon.Text = ABILITY_ICONS[def.kind] or "✨"
	end
end

-- the zone name shows as a banner when you walk in; above the bar we only keep what matters while there
local function refreshZone()
	local rift = tonumber(player:GetAttribute("RiftZone")) or 0
	if rift > 0 then
		local left = player:GetAttribute("RiftLeft")
		zoneLabel.Text = "∞ ENDLESS ZONE " .. rift .. (left and ("  •  " .. tostring(left) .. " enemies left") or "")
		zoneLabel.TextColor3 = Config.Rift.CoreColor
		zoneLabel.Visible = true
		return
	end
	local zone = tonumber(player:GetAttribute("Zone")) or 0
	local contested = zone > 0 and Util.IsContested(zone) and (workspace:GetAttribute("PvPMode") or Config.PvP.Mode) ~= "Off"
	zoneLabel.Text = "⚠ CONTESTED — Cores can be stolen here"
	zoneLabel.TextColor3 = Color3.fromRGB(255, 150, 130)
	zoneLabel.Visible = contested
end

local function refreshCarry()
	local title = player:GetAttribute("CarryTitle")
	carryCard.Visible = title ~= nil
	if HUD.DropButton then
		(HUD.DropButton :: TextButton).Visible = title ~= nil
	end
	tipFrame.Visible = tipVisible() -- hidden while carrying (tipFor returns "") and after a few seconds
	if not title then
		return
	end
	local r = tonumber(player:GetAttribute("CarryRarity")) or 1
	local color = Items.RarityColor(r)
	carryTitle.Text = tostring(title) .. "  " .. UI.Span(Util.Odds(tonumber(player:GetAttribute("CarryOdds")) or 1), Color3.fromRGB(235, 238, 255))
	UI.StyleRarity(carryTitle, r)
	UI.PaintOrb(carryOrb, color)
	local border = carryCard:FindFirstChild("Border")
	if border and border:IsA("UIStroke") then
		border.Color = color
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plot = World.MyPlot()
	local pad = plot and plot:FindFirstChild("DeliveryPad")
	local distance = (root and pad and root:IsA("BasePart") and pad:IsA("BasePart")) and math.floor((root.Position - pad.Position).Magnitude) or 0
	carryDistance.Text = "🏠 " .. Util.Commas(distance) .. "m"
	local shield = character and tonumber(character:GetAttribute("ShieldUntil")) or 0
	local shieldLeft = shield - State.Now()
	carryShield.Visible = shieldLeft > 0
	if shieldLeft > 0 then
		carryShield.Text = "🛡 " .. math.ceil(shieldLeft) .. "s"
	end
	local zone = Util.PlayerZone(player)
	carryWarn.Visible = Util.IsContested(zone) and (workspace:GetAttribute("PvPMode") or Config.PvP.Mode) ~= "Off" and zone > 0 and zone <= #Config.Zones
end

local function refreshBoosts(data: any?)
	local d = data or State.Data
	local parts = {}
	if d then
		local serverNow = State.Now()
		local personal = (d.luckBoostUntil or 0) - serverNow
		if personal > 0 then
			table.insert(parts, "🍀 x2 LUCK  " .. Util.Clock(personal))
		end
		local serverLuck = (tonumber(workspace:GetAttribute("ServerLuckUntil")) or 0) - serverNow
		if serverLuck > 0 then
			table.insert(parts, "🌍 SERVER LUCK  " .. Util.Clock(serverLuck))
		end
		if (d.luck or 1) > 1.001 then
			table.insert(parts, string.format("🎲 LUCK x%.2f", d.luck))
		end
	end
	for i, chip in boostChips do
		chip.Text = parts[i] or ""
		chip.Visible = parts[i] ~= nil
	end
end

function HUD.SetCooldown(readyAt: number, total: number)
	abilityReadyAt = readyAt
	abilityTotal = math.max(total or 1, 0.1)
end

function HUD.SetAbilityName(text: string)
	abilityName.Text = text
end

-- ability cooldown: a number counting down and a dark veil draining away (only works while cooling)
local function tickCooldown()
	local left = abilityReadyAt - os.clock()
	local cooling = left > 0.05
	if cooling then
		abilityCountdown.Text = left < 10 and string.format("%.1f", left) or tostring(math.ceil(left))
		local f = math.clamp(left / abilityTotal, 0.002, 0.996)
		veilGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(f, 0.3),
			NumberSequenceKeypoint.new(f + 0.003, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		if not wasCooling then
			abilityButton.BackgroundColor3 = ABILITY_DIM
			abilityCountdown.Visible = true
			abilityIcon.Visible = false
			veil.Visible = true
		end
	elseif wasCooling then
		abilityButton.BackgroundColor3 = ABILITY_COLOR
		abilityCountdown.Visible = false
		abilityIcon.Visible = true
		veil.Visible = false
		local scale = abilityButton:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.15
			UI.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	wasCooling = cooling
end

-- health bar: shows max health too, so Classes with +Health are visible
local HEALTH_GOOD = Color3.fromRGB(80, 220, 110)
local HEALTH_MID = Color3.fromRGB(255, 190, 60)
local HEALTH_LOW = Color3.fromRGB(240, 70, 70)

local function watchHealth(character: Model)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	local humanoid = hum :: Humanoid
	local function update()
		if player.Character ~= character then
			return -- an old character (respawn) must not overwrite the new one's health
		end
		local max = math.max(humanoid.MaxHealth, 1)
		local hp = math.clamp(humanoid.Health, 0, max)
		local ratio = hp / max
		UI.Tween(healthFill, 0.15, { Size = UDim2.fromScale(ratio, 1) })
		healthFill.BackgroundColor3 = ratio > 0.5 and HEALTH_GOOD or (ratio > 0.25 and HEALTH_MID or HEALTH_LOW)
		local function num(n: number): string
			return n >= 100000 and Util.Abbrev(n) or Util.Commas(n)
		end
		healthText.Text = "❤ " .. num(math.ceil(hp)) .. " / " .. num(math.floor(max))
	end
	humanoid.HealthChanged:Connect(update)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	update()
end

--------------------------------------------------------------------------------
function HUD.Init()
	local gui = UI.Screen("HUD", 5)

	-- small context tip (top centre); the carry card uses this spot on touch screens
	local top = group(Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), Vector2.new(560, 110), "Top", gui)
	tipFrame = UI.Frame(top, { Size = UDim2.fromOffset(500, 32), Position = UDim2.new(0.5, 0, 0, 0), Anchor = Vector2.new(0.5, 0), Color = UI.Colors.Outline, Transparency = 0.35, Radius = 16, Name = "Tip", Visible = false })
	UI.Stroke(tipFrame, Color3.new(1, 1, 1), 1.5, 0.8)
	tipLabel = UI.Text(tipFrame, "", { Size = UDim2.new(1, -24, 1, -6), Position = UDim2.fromOffset(12, 3), Font = UI.Fonts.Bold, MaxSize = 15, Outline = 1.5, Name = "Text" })

	-- slim POWER bar (bottom centre): Power on the left, progress to the next zone on the right
	local barWidth = touch and 360 or 440
	progressGroup = group(Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), Vector2.new(barWidth, 106), "Progress", gui)
	local panel = UI.Panel(progressGroup, { Size = UDim2.new(1, 0, 0, 42), Position = UDim2.new(0, 0, 1, 0), Anchor = Vector2.new(0, 1), Border = UI.Colors.Gold, BorderThickness = 2.5, Radius = 21, Name = "PowerBar" })
	powerLabel = UI.Text(panel, "⚡ 0", { Size = UDim2.new(0, 116, 1, -8), Position = UDim2.fromOffset(12, 4), Font = UI.Fonts.Display, MaxSize = 26, Gold = true, Outline = 2.5, Name = "Power" })
	local barBack
	barBack, barFill = UI.Bar(panel, UI.Colors.Gold, { Size = UDim2.new(1, -148, 0, 22), Position = UDim2.fromOffset(134, 10) })
	barText = UI.Text(barBack, "", { Size = UDim2.new(1, -12, 1, -2), Position = UDim2.fromOffset(6, 1), Font = UI.Fonts.Black, MaxSize = 13, Outline = 2, Name = "Goal", Z = 2 })
	local hpBack
	hpBack, healthFill = UI.Bar(progressGroup, HEALTH_GOOD, { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 38), Name = "HealthBar" })
	healthText = UI.Text(hpBack, "", { Size = UDim2.new(1, -12, 1, -2), Position = UDim2.fromOffset(6, 1), Font = UI.Fonts.Black, MaxSize = 12, Outline = 2, Name = "Health", Z = 2 })
	zoneLabel = UI.Chip(progressGroup, "", UI.Colors.Outline, { Size = UDim2.fromOffset(barWidth - 40, 26), Position = UDim2.new(0.5, 0, 0, 0), Anchor = Vector2.new(0.5, 0), MaxSize = 14, Transparency = 0.2, Name = "Zone" })
	zoneLabel.Visible = false

	-- Currencies + boosts (top left, under the Roblox top bar)
	local left = group(Vector2.new(0, 0), UDim2.new(0, 14, 0, 64), Vector2.new(250, 250), "Currency", gui)
	UI.List(left, 8)
	coinsLabel = pill(left, 1, "💰", UI.Colors.Gold, UI.Colors.GoldLight, UI.Colors.Gold)
	fragLabel = pill(left, 2, "💎", UI.Colors.Cyan, Color3.fromRGB(235, 250, 255), Color3.fromRGB(110, 205, 255))
	for i = 1, 3 do
		local chip = UI.Chip(left, "", Color3.fromRGB(40, 150, 80), { Size = UDim2.fromOffset(236, 28), Order = 2 + i, MaxSize = 15, Name = "Boost" })
		chip.TextXAlignment = Enum.TextXAlignment.Left
		chip.Visible = false
		boostChips[i] = chip
	end

	-- Menu: left middle on PC, top right on touch screens (keeps clear of the thumbstick)
	local menu = touch and group(Vector2.new(1, 0), UDim2.new(1, -12, 0, 64), Vector2.new(176, 270), "Menu", gui)
		or group(Vector2.new(0, 0.5), UDim2.new(0, 14, 0.5, 70), Vector2.new(176, 270), "Menu", gui)
	UI.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(80, 80),
		CellPadding = UDim2.fromOffset(12, 12),
		FillDirectionMaxCells = 2,
		HorizontalAlignment = touch and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	local baseButton = menuButton(menu, 1, "🏠", "BASE", Color3.fromRGB(58, 140, 255), "base")
	badgeFrame = UI.Frame(baseButton, { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -13, 0, -12), Color = UI.Colors.Bad, Radius = 15, Name = "Badge", Visible = false, Z = 3 })
	UI.Stroke(badgeFrame, Color3.new(1, 1, 1), 2, 0)
	badge = UI.Text(badgeFrame, "0", { Size = UDim2.fromScale(1, 1), Font = UI.Fonts.Title, MaxSize = 18, Outline = 1.5, OutlineColor = Color3.fromRGB(90, 10, 20), Z = 3 })
	menuButton(menu, 2, "🎒", "ITEMS", Color3.fromRGB(255, 150, 30), "items")
	menuButton(menu, 3, "🗺️", "TRAVEL", Color3.fromRGB(46, 190, 110), "travel")
	menuButton(menu, 4, "🛒", "SHOP", Color3.fromRGB(0, 176, 170), "shop")
	adminButton = menuButton(menu, 5, "🛠️", "ADMIN", Color3.fromRGB(230, 80, 70), "admin")
	adminButton.Visible = false

	-- Ability (+ attack and drop on touch screens)
	if touch then
		-- Roblox's jump button: 70px at (W-95, H-90) on phones, 120px at (W-170, H-210) on bigger touch screens
		local attackGroup = group(Vector2.new(1, 1), UDim2.new(1, -105, 1, -14), Vector2.new(124, 124), "Attack", gui)
		local abilityGroup = group(Vector2.new(0.5, 1), UDim2.new(1, -150, 1, -100), Vector2.new(110, 126), "Ability", gui)
		local dropGroup = group(Vector2.new(1, 1), UDim2.new(1, -190, 1, -14), Vector2.new(92, 92), "DropControl", gui)
		local attack = UI.Button(attackGroup, "", Color3.fromRGB(240, 70, 60), nil, { Size = UDim2.fromOffset(124, 124), Radius = 62, Name = "Attack" })
		UI.Text(attack, "⚔️", { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), MaxSize = 58, Name = "Icon", Z = 2 })
		HUD.AttackButton = attack
		abilityButton = UI.Button(abilityGroup, "", ABILITY_COLOR, nil, { Size = UDim2.fromOffset(96, 96), Position = UDim2.new(0.5, 0, 0, 0), Anchor = Vector2.new(0.5, 0), Radius = 48, Name = "Ability" })
		abilityWidgets(abilityButton, 96)
		abilityName = UI.Chip(abilityGroup, "Ability", UI.Colors.Outline, { Size = UDim2.fromOffset(110, 24), Position = UDim2.new(0.5, 0, 1, 0), Anchor = Vector2.new(0.5, 1), MaxSize = 14, Transparency = 0.25 })
		local drop = UI.Button(dropGroup, "DROP", UI.Colors.Bad, nil, { Size = UDim2.fromOffset(92, 92), Radius = 46, MaxSize = 24, Name = "Drop" })
		drop.Visible = false
		HUD.DropButton = drop
		local camera = workspace.CurrentCamera
		local function place()
			local size = camera.ViewportSize
			local s = UI.ScaleFor(size, HUD_FIT)
			local small = math.min(size.X, size.Y) <= 500
			local jumpLeft = small and 95 or 170
			local bottom = small and 14 or 90
			local attackW = 124 * s
			attackGroup.Position = UDim2.new(1, -(jumpLeft + 10), 1, -bottom)
			abilityGroup.Position = UDim2.new(1, -(jumpLeft + 10 + attackW / 2 + 8 * s), 1, -(bottom + attackW + 10))
			dropGroup.Position = UDim2.new(1, -(jumpLeft + 10 + attackW + 14), 1, -bottom)
		end
		place()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	else
		local controls = group(Vector2.new(1, 1), UDim2.new(1, -16, 1, -16), Vector2.new(150, 136), "Controls", gui)
		abilityButton = UI.Button(controls, "", ABILITY_COLOR, nil, { Size = UDim2.fromOffset(96, 96), Position = UDim2.new(0.5, 0, 0, 0), Anchor = Vector2.new(0.5, 0), Radius = 48, Name = "Ability" })
		abilityWidgets(abilityButton, 96)
		local key = UI.Frame(controls, { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0.5, -52, 0, -6), Color = UI.Colors.Outline, Transparency = 0.1, Radius = 8, Name = "Key", Z = 3 })
		UI.Stroke(key, Color3.new(1, 1, 1), 2, 0.2)
		UI.Text(key, "Q", { Size = UDim2.fromScale(1, 1), Font = UI.Fonts.Title, MaxSize = 20, Z = 3 })
		abilityName = UI.Chip(controls, "Ability", UI.Colors.Outline, { Size = UDim2.fromOffset(140, 28), Position = UDim2.new(0.5, 0, 1, 0), Anchor = Vector2.new(0.5, 1), MaxSize = 15, Transparency = 0.25 })
	end
	HUD.AbilityButton = abilityButton

	-- Carry objective
	if touch then
		makeCarry(top, 540, UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0), false)
	else
		local bottom = group(Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -14), Vector2.new(640, 100), "Bottom", gui)
		makeCarry(bottom, 640, UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), true)
		-- right above the POWER and health bars, which stay visible while carrying
		local camera = workspace.CurrentCamera
		local function placeCarry()
			local scale = UI.ScaleFor(camera.ViewportSize, HUD_FIT)
			bottom.Position = UDim2.new(0.5, 0, 1, -(8 + 106 * scale + 6))
		end
		placeCarry()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeCarry)
	end
	if HUD.DropButton then
		(HUD.DropButton :: TextButton).Visible = false
	end

	-- data
	State.OnChange(refresh)
	for _, attr in { "Zone", "RiftZone", "RiftLeft" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshZone)
	end
	for _, attr in { "CarryTitle", "CarryRarity", "CarryOdds" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshCarry)
	end
	refreshZone()
	refreshCarry()
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	player.CharacterAdded:Connect(watchHealth)

	task.spawn(function()
		while true do
			task.wait(0.25)
			pcall(refreshCarry)
			pcall(refreshBoosts, nil)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			if State.Data then
				pcall(refresh, State.Data)
			end
		end
	end)

	RunService.RenderStepped:Connect(tickCooldown)
end

return HUD
