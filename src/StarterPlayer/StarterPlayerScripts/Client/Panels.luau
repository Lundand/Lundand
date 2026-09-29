--[[
	Panels — one window open at a time (Base, Items, Travel, Shop, Admin).
	Each panel module exposes Build(content) and Refresh(data) (+ optional OnOpen(), OnClose(), SetCloser(fn),
	SetOpener(fn) — fn(name) opens another panel).
	Window chrome: glassy navy body, accent-coloured title bar, round icon badge and close button.
]]

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Popup = require(script.Parent.Popup)

local Panels = {}

type Entry = { window: Frame, content: Frame, module: any, built: boolean }

local gui: ScreenGui
local root: Frame
local dim: TextButton
local entries: { [string]: Entry } = {}
local openName: string? = nil
Panels.Changed = Instance.new("BindableEvent")

local WIDTH, HEIGHT = 880, 580
local PANEL_FIT = 620 -- design height fitted to short (phone) screens

local META = {
	base = { title = "YOUR BASE", icon = "🏠", accent = Color3.fromRGB(64, 150, 255) },
	items = { title = "ITEMS", icon = "🎒", accent = Color3.fromRGB(255, 160, 40) },
	travel = { title = "TRAVEL", icon = "🗺️", accent = Color3.fromRGB(56, 196, 120) },
	shop = { title = "SHOP", icon = "🛒", accent = Color3.fromRGB(0, 186, 176) },
	admin = { title = "ADMIN (testing)", icon = "🛠️", accent = Color3.fromRGB(240, 96, 80) },
	premium = { title = "PREMIUM CORES", icon = "💎", accent = Color3.fromRGB(160, 90, 255) },
}

local function makeWindow(name: string): (Frame, Frame)
	local meta = META[name] or { title = string.upper(name), icon = "⭐", accent = UI.Colors.Blue }
	local accent: Color3 = meta.accent
	local window = UI.Panel(root, {
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Position = UDim2.fromScale(0.5, 0.5),
		Anchor = Vector2.new(0.5, 0.5),
		Radius = 24,
		Border = UI.Shade(accent, 0.25),
		BorderThickness = 4,
		Gloss = false,
		Visible = false,
		Name = name,
	})
	window.Active = true -- clicks on the window must not fall through to the dim background (which closes it)
	-- title bar
	local header = UI.Frame(window, { Size = UDim2.new(1, 0, 0, 64), Color = Color3.new(1, 1, 1), Radius = 24, Name = "Header" })
	UI.Gradient(header, UI.Shade(accent, 0.18), UI.Shade(accent, -0.28), 90)
	local square = UI.Frame(header, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), Color = Color3.new(1, 1, 1), Radius = false, Name = "Square" })
	UI.Gradient(square, UI.Shade(accent, -0.16), UI.Shade(accent, -0.28), 90)
	local gloss = UI.Frame(header, { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 5), Color = Color3.new(1, 1, 1), Transparency = 0.8, Radius = 14, Name = "Gloss" })
	UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1), Parent = gloss })
	UI.Frame(header, { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), Color = UI.Shade(accent, -0.55), Transparency = 0.2, Radius = false, Name = "Edge" })
	UI.Badge(header, meta.icon, accent, 76, { Position = UDim2.fromOffset(-16, -12), Name = "Icon", RingThickness = 4 })
	UI.Text(header, meta.title, { Size = UDim2.new(1, -170, 0, 44), Position = UDim2.fromOffset(74, 9), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 36, Outline = 3, OutlineColor = UI.Shade(accent, -0.7), Name = "Title" })
	local close = UI.Button(header, "X", UI.Colors.Bad, function()
		Panels.Close()
	end, { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(1, -38, 0, -10), Radius = 28, MaxSize = 30, Name = "Close" })
	close.ZIndex = 2
	local content = UI.Frame(window, { Size = UDim2.new(1, -40, 1, -92), Position = UDim2.fromOffset(20, 78), Transparency = 1, Radius = false, Name = "Content" })
	return window, content
end

function Panels.Register(name: string, module: any)
	local window, content = makeWindow(name)
	entries[name] = { window = window, content = content, module = module, built = false }
	if module.SetCloser then
		module.SetCloser(function()
			Panels.Close()
		end)
	end
	if module.SetOpener then
		module.SetOpener(function(other: string)
			Panels.Open(other)
		end)
	end
end

function Panels.Open(name: string)
	local entry = entries[name]
	if not entry then
		return
	end
	Popup.Close()
	if openName and openName ~= name then
		local old = entries[openName]
		if old then
			old.window.Visible = false
			if old.module.OnClose then
				old.module.OnClose()
			end
		end
	end
	if not entry.built then
		entry.built = true
		entry.module.Build(entry.content)
	end
	openName = name
	dim.Visible = true
	entry.window.Visible = true
	local scale = entry.window:FindFirstChildOfClass("UIScale") or UI.Create("UIScale", { Parent = entry.window })
	scale.Scale = 0.85
	UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	if entry.module.OnOpen then
		entry.module.OnOpen()
	end
	if State.Data then
		entry.module.Refresh(State.Data)
	end
	Panels.Changed:Fire(openName)
end

function Panels.Close()
	Popup.Close()
	if openName then
		local entry = entries[openName]
		if entry then
			entry.window.Visible = false
			if entry.module.OnClose then
				entry.module.OnClose()
			end
		end
	end
	openName = nil
	dim.Visible = false
	Panels.Changed:Fire(nil)
end

function Panels.Toggle(name: string)
	if openName == name then
		Panels.Close()
	else
		Panels.Open(name)
	end
end

function Panels.IsOpen(name: string?): boolean
	if name then
		return openName == name
	end
	return openName ~= nil
end

function Panels.Init()
	gui = UI.Screen("Panels", 10)
	dim = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 26),
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Name = "Dim",
		Parent = gui,
	})
	dim.Activated:Connect(function()
		Panels.Close()
	end)
	root = UI.Frame(gui, { Size = UDim2.fromOffset(1280, 800), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Transparency = 1, Radius = false, Name = "Root" })
	UI.AutoScale(root, PANEL_FIT)

	Panels.Register("base", require(script.Parent.BasePanel))
	Panels.Register("items", require(script.Parent.ItemsPanel))
	Panels.Register("travel", require(script.Parent.TravelPanel))
	Panels.Register("shop", require(script.Parent.ShopPanel))
	Panels.Register("admin", require(script.Parent.AdminPanel))
	Panels.Register("premium", require(script.Parent.PremiumPanel))

	State.OnChange(function(data)
		if openName then
			local entry = entries[openName]
			if entry and entry.built then
				entry.module.Refresh(data)
			end
		end
	end)
end

return Panels
