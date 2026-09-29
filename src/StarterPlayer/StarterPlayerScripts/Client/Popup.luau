--[[
	Popup — a modal dialog on top of the panels (odds tables, Premium Core details).
	Popup.Show(title, accent, build) calls build(content) now and again whenever the player's data changes
	(so chances follow luck boosts), until the dialog is closed.
]]

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Popup = {}

local gui: ScreenGui? = nil
local dim: TextButton
local window: Frame
local header: Frame
local headerFill: UIGradient
local titleLabel: TextLabel
local content: Frame
local border: UIStroke
local build: ((Frame) -> ())? = nil

local function rebuild()
	UI.Clear(content)
	if build then
		local ok, err = pcall(build :: (Frame) -> (), content)
		if not ok then
			warn("[Popup] " .. tostring(err))
		end
	end
end

local function init()
	local screen = UI.Screen("Popup", 15)
	gui = screen
	dim = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 8, 26),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Name = "Dim",
		Parent = screen,
	})
	dim.Activated:Connect(function()
		Popup.Close()
	end)
	local root = UI.Frame(dim, { Size = UDim2.fromOffset(1280, 800), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Transparency = 1, Radius = false, Name = "Root" })
	UI.AutoScale(root, 620)
	window = UI.Panel(root, { Size = UDim2.fromOffset(700, 540), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Radius = 24, BorderThickness = 4, Gloss = false, Name = "Dialog" })
	window.Active = true -- clicks inside the dialog must not reach the dim background
	border = window:FindFirstChild("Border") :: UIStroke
	header = UI.Frame(window, { Size = UDim2.new(1, 0, 0, 58), Color = Color3.new(1, 1, 1), Radius = 24, Name = "Header" })
	headerFill = UI.Gradient(header, Color3.new(1, 1, 1), Color3.new(0.6, 0.6, 0.6), 90)
	local square = UI.Frame(header, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), Color = Color3.new(1, 1, 1), Radius = false, Name = "Square" })
	UI.Gradient(square, Color3.new(0.78, 0.78, 0.78), Color3.new(0.6, 0.6, 0.6), 90)
	titleLabel = UI.Text(header, "", { Size = UDim2.new(1, -110, 0, 40), Position = UDim2.fromOffset(22, 9), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 30, Outline = 3, Name = "Title" })
	local close = UI.Button(header, "X", UI.Colors.Bad, function()
		Popup.Close()
	end, { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, -36, 0, -10), Radius = 26, MaxSize = 28, Name = "Close" })
	close.ZIndex = 2
	content = UI.Frame(window, { Size = UDim2.new(1, -36, 1, -84), Position = UDim2.fromOffset(18, 70), Transparency = 1, Radius = false, Name = "Content" })
	State.OnChange(function()
		if dim.Visible then
			rebuild()
		end
	end)
end

function Popup.Show(title: string, accent: Color3, builder: (Frame) -> ())
	if not gui then
		init()
	end
	titleLabel.Text = title
	local outline = titleLabel:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = UI.Shade(accent, -0.7)
	end
	header.BackgroundColor3 = accent
	for _, d in header:GetChildren() do
		if d:IsA("Frame") and d.Name == "Square" then
			d.BackgroundColor3 = accent
		end
	end
	headerFill.Enabled = true
	border.Color = UI.Shade(accent, 0.25)
	build = builder
	rebuild()
	dim.Visible = true
	local scale = window:FindFirstChildOfClass("UIScale") or UI.Create("UIScale", { Parent = window })
	scale.Scale = 0.85
	UI.Tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Popup.Close()
	if gui and dim.Visible then
		dim.Visible = false
		build = nil
		UI.Clear(content)
	end
end

function Popup.IsOpen(): boolean
	return gui ~= nil and dim.Visible
end

return Popup
