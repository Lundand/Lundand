--[[
	Notify — toasts (small messages) and banners (big moments) on screen.
	The server sends { text, kind, extra } through the Notify remote.
	Toasts stack under the POWER card; banners pop in lower, so the two never cover each other.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent.UI)

local Notify = {}

local gui: ScreenGui
local toastList: Frame
local bannerHolder: Frame
local vignette: Frame
local bannerQueue: { { title: string, sub: string, color: Color3, time: number, big: boolean } } = {}
local bannerBusy = false
local MAX_TOASTS = 3
Notify.PanelOpener = nil :: ((string) -> ())?

local KIND_COLORS = {
	info = UI.Colors.Blue,
	success = UI.Colors.Good,
	error = UI.Colors.Bad,
	warn = Color3.fromRGB(255, 160, 50),
	carry = UI.Colors.Gold,
	ready = UI.Colors.Purple,
	danger = UI.Colors.Bad,
}
local KIND_ICONS = {
	info = "💬",
	success = "✅",
	error = "❌",
	warn = "⚠️",
	carry = "📦",
	ready = "✨",
	danger = "⚠️",
	drop = "💎",
}

local function rarityColor(extra: any): Color3?
	local r = type(extra) == "table" and tonumber(extra.rarity)
	local rarity = r and Config.Rarities[r]
	return rarity and rarity.color or nil
end

local function fadeOut(frame: Instance, time: number)
	for _, d in frame:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.Tween(d, time, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
		elseif d:IsA("UIStroke") then
			UI.Tween(d, time, { Transparency = 1 })
		elseif d:IsA("Frame") then
			UI.Tween(d, time, { BackgroundTransparency = 1 })
		end
	end
	if frame:IsA("Frame") then
		UI.Tween(frame, time, { BackgroundTransparency = 1 })
	end
end

function Notify.Toast(text: string, kind: string?, color: Color3?)
	local k = kind or "info"
	local accent = color or KIND_COLORS[k] or UI.Colors.Blue
	local toast = UI.Panel(toastList, { Size = UDim2.fromOffset(520, 50), Radius = 25, Top = Color3.fromRGB(40, 42, 92), Bottom = Color3.fromRGB(18, 20, 50), Border = accent, BorderThickness = 2.5, Name = "Toast", GlossHeight = 18 })
	toast.LayoutOrder = -math.floor(os.clock() * 100)
	UI.Badge(toast, KIND_ICONS[k] or "💬", accent, 40, { Position = UDim2.new(0, 6, 0.5, 0), Anchor = Vector2.new(0, 0.5), RingThickness = 2 })
	UI.Text(toast, text, { Size = UDim2.new(1, -66, 1, -10), Position = UDim2.fromOffset(52, 5), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, MaxSize = 17, Outline = 1.5, Name = "Text" })
	local scale = UI.Create("UIScale", { Scale = 0.6, Parent = toast })
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local items = 0
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			items += 1
		end
	end
	if items > MAX_TOASTS then
		local oldest, order = nil, math.huge
		for _, child in toastList:GetChildren() do
			if child:IsA("Frame") and -child.LayoutOrder < order then
				oldest, order = child, -child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(3.6, function()
		if toast.Parent then
			fadeOut(toast, 0.3)
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

local function showNextBanner()
	if bannerBusy or #bannerQueue == 0 then
		return
	end
	bannerBusy = true
	local b = table.remove(bannerQueue, 1) :: any
	local frame = UI.Frame(bannerHolder, { Size = UDim2.fromScale(1, 1), Transparency = 1, Radius = false, Name = "Banner" })
	local title = UI.Text(frame, string.upper(b.title), { Size = UDim2.new(1, 0, 0, b.big and 100 or 80), Position = UDim2.fromOffset(0, b.big and 0 or 10), Font = UI.Fonts.Display, MaxSize = b.big and 84 or 64, Outline = 5, OutlineColor = UI.Colors.Outline, Name = "Title" })
	title.TextColor3 = Color3.new(1, 1, 1)
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UI.Shade(b.color, 0.55)),
			ColorSequenceKeypoint.new(0.5, b.color),
			ColorSequenceKeypoint.new(1, UI.Shade(b.color, -0.2)),
		}),
		Parent = title,
	})
	if b.sub ~= "" then
		local pill = UI.Frame(frame, { Size = UDim2.fromOffset(760, 46), Position = UDim2.new(0.5, 0, 0, 104), Anchor = Vector2.new(0.5, 0), Color = UI.Colors.Outline, Transparency = 0.25, Radius = 23, Name = "Sub" })
		UI.Stroke(pill, b.color, 2, 0.3)
		UI.Text(pill, b.sub, { Size = UDim2.new(1, -40, 1, -8), Position = UDim2.fromOffset(20, 4), Font = UI.Fonts.Title, MaxSize = 26, Outline = 2 })
	end
	local scale = UI.Create("UIScale", { Scale = 0.3, Parent = frame })
	UI.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(b.time, function()
		UI.Tween(scale, 0.25, { Scale = 0.8 })
		fadeOut(frame, 0.25)
		task.wait(0.3)
		frame:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function Notify.Banner(title: string, sub: string?, color: Color3?, duration: number?, big: boolean?)
	table.insert(bannerQueue, { title = title, sub = sub or "", color = color or UI.Colors.Gold, time = duration or 2.4, big = big == true })
	if #bannerQueue > 4 then
		table.remove(bannerQueue, 1)
	end
	showNextBanner()
end

function Notify.Danger()
	vignette.BackgroundTransparency = 0.45
	UI.Tween(vignette, 0.9, { BackgroundTransparency = 1 })
end

function Notify.Handle(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local text = tostring(payload.text or "")
	local kind = tostring(payload.kind or "info")
	local extra = payload.extra
	local rColor = rarityColor(extra)
	local r = type(extra) == "table" and tonumber(extra.rarity) or 0

	if kind == "panel" then
		if Notify.PanelOpener and type(extra) == "table" then
			Notify.PanelOpener(tostring(extra.panel))
		end
	elseif kind == "drop" then
		UI.Sound(Config.Sounds.CoreDrop, 0.6)
		if r >= 3 then
			Notify.Banner("A CORE HAS DROPPED!", text:gsub("^A Core has dropped! ", ""), rColor, 2.6, r >= 5)
		else
			Notify.Toast(text, kind, rColor)
		end
	elseif kind == "announce" then
		Notify.Banner(text, "", rColor or UI.Colors.Gold, 2.8, false)
	elseif kind == "unlock" then
		Notify.Banner(text, "", UI.Colors.Gold, 3, true)
	elseif kind == "boss" then
		Notify.Banner(text, "", UI.Colors.Bad, 3, false)
	elseif kind == "secured" then
		UI.Sound(Config.Sounds.Deliver, 0.6)
		Notify.Banner("CORE SECURED!", text:gsub("^CORE SECURED! ", ""), rColor or UI.Colors.Good, 2.4, true)
	elseif kind == "rare" then
		Notify.Banner(text, "", UI.Colors.Gold, 2.6, false)
	elseif kind == "zone" then
		Notify.Banner(text, "", UI.Colors.Blue, 2.4, false)
	elseif kind == "danger" then
		Notify.Danger()
		Notify.Toast(text, kind)
	elseif kind == "carry" and r >= 4 then
		Notify.Banner("GET IT HOME!", text, rColor, 2.6, true)
	elseif text ~= "" then
		Notify.Toast(text, kind, kind == "carry" and rColor or nil)
	end
end

function Notify.Init()
	gui = UI.Screen("Notifications", 20)
	vignette = UI.Frame(gui, { Size = UDim2.fromScale(1, 1), Color = Color3.fromRGB(255, 0, 0), Transparency = 1, Radius = false, Name = "Vignette" })
	UI.Create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.9), NumberSequenceKeypoint.new(0.7, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Parent = vignette,
	})

	local root = UI.Frame(gui, { Size = UDim2.fromOffset(1280, 800), Position = UDim2.fromScale(0.5, 0), Anchor = Vector2.new(0.5, 0), Transparency = 1, Radius = false, Name = "Root" })
	UI.AutoScale(root, 640)
	toastList = UI.Frame(root, { Size = UDim2.fromOffset(540, 176), Position = UDim2.new(0.5, 0, 0, 216), Anchor = Vector2.new(0.5, 0), Transparency = 1, Radius = false, Name = "Toasts" })
	UI.List(toastList, 6, false, Enum.HorizontalAlignment.Center)
	bannerHolder = UI.Frame(root, { Size = UDim2.fromOffset(1000, 160), Position = UDim2.new(0.5, 0, 0, 400), Anchor = Vector2.new(0.5, 0), Transparency = 1, Radius = false, Name = "Banner" })

	Net.Event("Notify").OnClientEvent:Connect(Notify.Handle)
end

return Notify
