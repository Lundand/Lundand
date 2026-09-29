--[[
	Reveal — the Core opening moment: the loot pool spins, slows down, lands on your item,
	shows "LUCKY!" if the rarity upgraded, and how much Power you gained.
	Rarity-coloured sunburst + glow behind a glassy card with a rarity ribbon.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent.UI)

local Reveal = {}

local overlay: TextButton
local card: Frame
local rays: Frame
local rayList: { Frame } = {}
local glow: { Frame } = {}
local ribbon: Frame
local ribbonFill: UIGradient
local title: TextLabel
local roll: TextLabel
local chips: Frame
local rarityChip: TextLabel
local slotChip: TextLabel
local powerChip: TextLabel
local sub: TextLabel
local lucky: TextLabel
local gain: TextLabel
local hint: TextLabel
local hintTween: Tween? = nil
local queue: { any } = {}
local busy = false
local waiting = false
local rng = Random.new()
local SLOT_ICONS = { w = "⚔️", c = "🛡️", a = "✨" }

local function finish()
	waiting = false
end

-- r = nil paints the neutral Premium look (gold + rainbow ribbon) so the spin doesn't give the rarity away
local function paint(r: number?)
	local rarity = r and Config.Rarities[r]
	local color = r and Items.RarityColor(r) or UI.Colors.Gold
	for _, ray in rayList do
		ray.BackgroundColor3 = color
	end
	for _, g in glow do
		g.BackgroundColor3 = color
	end
	local border = card:FindFirstChild("Border")
	if border and border:IsA("UIStroke") then
		border.Color = color
	end
	ribbon.BackgroundColor3 = color
	local rainbow = ribbon:FindFirstChild("RarityGradient")
	if r == nil or (rarity and rarity.secret) then
		ribbonFill.Enabled = false
		if not rainbow then
			UI.Rainbow(ribbon).Name = "RarityGradient"
		end
	else
		ribbonFill.Enabled = true
		if rainbow then
			rainbow:Destroy()
		end
	end
end

local function show(p: any)
	overlay.Visible = true
	local r = tonumber(p.r) or 1
	local final = tonumber(p.rarity) or r
	local premium = p.premium == true
	title.Text = premium and ("💎 PREMIUM " .. string.upper(Items.CoreName(p.z))) or ("OPENING " .. Items.CoreTitle(p.z, r))
	paint(if premium then nil else r)
	sub.Text = ""
	chips.Visible = false
	lucky.Visible = false
	gain.Visible = false
	hint.Text = ""
	for _, ray in rayList do
		ray.BackgroundTransparency = 0.55
	end
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	UI.Tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- spin through the loot pool
	local names = Items.PoolNames(p.z)
	local delay = 0.035
	local started = os.clock()
	while os.clock() - started < 1.6 do
		roll.Text = string.upper(names[rng:NextInteger(1, #names)]) -- the display font has no real lowercase
		local shown = premium and rng:NextInteger(3, math.min(7, #Config.Rarities)) or math.clamp(r + rng:NextInteger(-1, 1), 1, #Config.Rarities)
		roll.TextColor3 = Config.Rarities[shown].color
		task.wait(delay)
		delay *= 1.13
	end

	-- land
	roll.Text = string.upper(Items.FullName(p.key))
	UI.StyleRarity(roll, final)
	local rollScale = roll:FindFirstChildOfClass("UIScale") :: UIScale
	rollScale.Scale = 1.6
	UI.Tween(rollScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	paint(final)
	local _, _, slot = Items.Def(p.key)
	local rarity = Config.Rarities[final]
	rarityChip.Text = string.upper(rarity and rarity.name or "?")
	rarityChip.BackgroundColor3 = UI.Shade(Items.RarityColor(final), -0.3)
	slotChip.Text = (SLOT_ICONS[slot] or "⭐") .. " " .. string.upper(Items.SlotNames[slot] or "Item")
	powerChip.Text = "⚡ " .. Util.Abbrev(Items.Power(p.key))
	chips.Visible = true
	sub.Text = table.concat(Items.Describe(p.key), "  •  ")
	for _, ray in rayList do
		UI.Tween(ray, 0.4, { BackgroundTransparency = 0.25 })
	end
	if (tonumber(p.bonus) or 0) > 0 then
		lucky.Visible = true
		lucky.Text = "🍀 LUCKY! +" .. p.bonus .. " RARITY!"
	end
	local before, after = tonumber(p.before) or 0, tonumber(p.after) or 0
	gain.Visible = true
	if after > before + 0.01 then
		gain.Text = "EQUIPPED!  +⚡ " .. Util.Abbrev(after - before) .. " POWER"
		gain.BackgroundColor3 = Color3.fromRGB(34, 150, 70)
		gain.TextColor3 = Color3.new(1, 1, 1)
	else
		gain.Text = "Added to your Items"
		gain.BackgroundColor3 = UI.Colors.Card
		gain.TextColor3 = UI.Colors.Muted
	end
	UI.Sound(Config.Sounds.CoreDrop, final >= 5 and 0.8 or 0.5)
	hint.Text = "Tap anywhere to continue"
	waiting = true
	local timeout = os.clock() + 6
	while waiting and os.clock() < timeout do
		task.wait(0.05)
	end
	waiting = false
end

local function run()
	if busy then
		return
	end
	busy = true
	hintTween = TweenService:Create(hint, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 })
	if hintTween then
		hintTween:Play()
	end
	while #queue > 0 do
		local p = table.remove(queue, 1)
		local ok, err = pcall(show, p)
		if not ok then
			warn("[Reveal] " .. tostring(err))
		end
	end
	if hintTween then
		hintTween:Cancel()
		hintTween = nil
	end
	hint.TextTransparency = 0
	overlay.Visible = false
	busy = false
end

function Reveal.Show(payload: any)
	table.insert(queue, payload)
	task.spawn(run)
end

function Reveal.Init()
	local gui = UI.Screen("Reveal", 30)
	overlay = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 26),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = gui,
	})
	overlay.Activated:Connect(finish)
	local root = UI.Frame(overlay, { Size = UDim2.fromOffset(1280, 800), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Transparency = 1, Radius = false, Name = "Root" })
	UI.AutoScale(root, 620)

	-- sunburst: thin rays that fade out towards the ends, spun as one frame
	rays = UI.Frame(root, { Size = UDim2.fromOffset(1400, 1400), Position = UDim2.fromScale(0.5, 0.48), Anchor = Vector2.new(0.5, 0.5), Transparency = 1, Radius = false, Name = "Rays" })
	for i = 1, 10 do
		local ray = UI.Frame(rays, { Size = UDim2.new(0, 110, 1, 0), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Transparency = 0.55, Radius = false, Name = "Ray" })
		ray.Rotation = i * 18
		UI.Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.75),
				NumberSequenceKeypoint.new(0.5, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		table.insert(rayList, ray)
	end
	for i, size in { 760, 560 } do
		local g = UI.Frame(root, { Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.48), Anchor = Vector2.new(0.5, 0.5), Transparency = i == 1 and 0.86 or 0.75, Radius = size // 2, Name = "Glow" })
		table.insert(glow, g)
	end

	card = UI.Panel(root, { Size = UDim2.fromOffset(680, 380), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Radius = 28, BorderThickness = 5, Name = "Card" })
	UI.Create("UIScale", { Parent = card })
	ribbon = UI.Frame(card, { Size = UDim2.fromOffset(500, 52), Position = UDim2.new(0.5, 0, 0, -24), Anchor = Vector2.new(0.5, 0), Color = UI.Colors.Gold, Radius = 26, Name = "Ribbon" })
	ribbonFill = UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
		}),
		Parent = ribbon,
	})
	UI.Stroke(ribbon, Color3.new(1, 1, 1), 3, 0)
	title = UI.Text(ribbon, "", { Size = UDim2.new(1, -30, 1, -10), Position = UDim2.fromOffset(15, 5), Font = UI.Fonts.Title, MaxSize = 26, Outline = 2.5, Name = "Title" })
	roll = UI.Text(card, "", { Size = UDim2.new(1, -48, 0, 84), Position = UDim2.fromOffset(24, 46), Font = UI.Fonts.Display, MaxSize = 58, Outline = 4, Name = "Roll" })
	UI.Create("UIScale", { Parent = roll })
	chips = UI.Frame(card, { Size = UDim2.new(1, -48, 0, 34), Position = UDim2.fromOffset(24, 136), Transparency = 1, Radius = false, Name = "Chips", Visible = false })
	local chipList = UI.List(chips, 10, true, Enum.HorizontalAlignment.Center)
	chipList.VerticalAlignment = Enum.VerticalAlignment.Center
	rarityChip = UI.Chip(chips, "", UI.Colors.CardHi, { Size = UDim2.fromOffset(150, 32), Order = 1, MaxSize = 17, Font = UI.Fonts.Title })
	slotChip = UI.Chip(chips, "", UI.Colors.CardHi, { Size = UDim2.fromOffset(150, 32), Order = 2, MaxSize = 17, Font = UI.Fonts.Title })
	powerChip = UI.Chip(chips, "", Color3.fromRGB(120, 80, 10), { Size = UDim2.fromOffset(150, 32), Order = 3, MaxSize = 17, Font = UI.Fonts.Title, TextColor = UI.Colors.GoldLight })
	sub = UI.Text(card, "", { Size = UDim2.new(1, -60, 0, 24), Position = UDim2.fromOffset(30, 180), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 17, Name = "Details" })
	lucky = UI.Text(card, "", { Size = UDim2.new(1, -60, 0, 40), Position = UDim2.fromOffset(30, 210), Font = UI.Fonts.Display, Color = Color3.fromRGB(120, 255, 140), MaxSize = 32, Outline = 3, OutlineColor = Color3.fromRGB(10, 60, 20), Name = "Lucky" })
	gain = UI.Chip(card, "", Color3.fromRGB(34, 150, 70), { Size = UDim2.fromOffset(460, 46), Position = UDim2.new(0.5, 0, 0, 256), Anchor = Vector2.new(0.5, 0), MaxSize = 24, Font = UI.Fonts.Title, Name = "Gain" })
	hint = UI.Text(card, "", { Size = UDim2.new(1, -40, 0, 24), Position = UDim2.new(0, 20, 1, -40), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 16, Name = "Hint" })

	RunService.RenderStepped:Connect(function(dt)
		if overlay.Visible then
			rays.Rotation += dt * 16
		end
	end)
	Net.Event("Reveal").OnClientEvent:Connect(Reveal.Show)
end

return Reveal
