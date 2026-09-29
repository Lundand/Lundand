--[[
	UI — tiny toolkit so every screen shares the look of the store art:
	deep navy/indigo glass panels with bright borders, gold accents, chunky outlined text,
	3D bouncy buttons, rarity colours used boldly.
	Everything is designed at ~1280x800 and scaled with UIScale (phones get a larger share of the screen).
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local UI = {}

local player = Players.LocalPlayer
local rgb = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

UI.Colors = {
	Panel = rgb(22, 24, 60), -- window body (bottom of its gradient)
	PanelTop = rgb(48, 52, 122), -- window body (top of its gradient)
	Card = rgb(38, 42, 96),
	CardHi = rgb(60, 66, 140),
	Stroke = rgb(255, 255, 255),
	Text = rgb(250, 250, 255),
	Muted = rgb(176, 184, 230),
	Outline = rgb(20, 16, 46), -- dark outline around chunky text
	Gold = rgb(255, 202, 50),
	GoldLight = rgb(255, 242, 160),
	GoldDark = rgb(255, 140, 20),
	Good = rgb(62, 206, 94),
	Bad = rgb(236, 62, 78),
	Blue = rgb(54, 144, 255),
	Purple = rgb(148, 82, 255),
	Robux = rgb(30, 176, 86),
	Orange = rgb(255, 146, 36),
	Cyan = rgb(70, 214, 255),
	Disabled = rgb(94, 98, 134),
}

UI.Fonts = {
	Title = Enum.Font.FredokaOne,
	Display = Enum.Font.LuckiestGuy,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
	Body = Enum.Font.GothamMedium,
}

-- positive amount = lighter, negative = darker
function UI.Shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(WHITE, amount)
	end
	return color:Lerp(BLACK, -amount)
end

function UI.Create(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.Corner(parent: Instance, radius: number?): UICorner
	return UI.Create("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

-- Border stroke (outline of a frame or button)
function UI.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UI.Create("UIStroke", {
		Color = color or UI.Colors.Stroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Dark outline around text (chunky "simulator" lettering)
function UI.Outline(label: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UI.Create("UIStroke", {
		Color = color or UI.Colors.Outline,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Name = "Outline",
		Parent = label,
	})
end

function UI.Padding(parent: Instance, px: number): UIPadding
	return UI.Create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.List(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return UI.Create("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function UI.Gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	return UI.Create("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 90, Parent = parent })
end

-- Gold fill for display text (white text + this gradient), like the store art titles
function UI.GoldText(label: Instance): UIGradient
	return UI.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UI.Colors.GoldLight),
			ColorSequenceKeypoint.new(0.5, UI.Colors.Gold),
			ColorSequenceKeypoint.new(1, UI.Colors.GoldDark),
		}),
		Rotation = 90,
		Name = "GoldGradient",
		Parent = label,
	})
end

function UI.Rainbow(parent: Instance): UIGradient
	return UI.Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 70, 70)),
			ColorSequenceKeypoint.new(0.2, rgb(255, 200, 60)),
			ColorSequenceKeypoint.new(0.4, rgb(80, 255, 120)),
			ColorSequenceKeypoint.new(0.6, rgb(70, 200, 255)),
			ColorSequenceKeypoint.new(0.8, rgb(170, 90, 255)),
			ColorSequenceKeypoint.new(1, rgb(255, 70, 200)),
		}),
		Parent = parent,
	})
end

function UI.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

function UI.Frame(parent: Instance?, props: { [string]: any }?): Frame
	local p = props or {}
	local frame = UI.Create("Frame", {
		BackgroundColor3 = p.Color or UI.Colors.Card,
		BackgroundTransparency = p.Transparency or 0,
		BorderSizePixel = 0,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.Anchor or Vector2.zero,
		Name = p.Name or "Frame",
		LayoutOrder = p.Order or 0,
		ClipsDescendants = p.Clip or false,
		Visible = p.Visible ~= false,
		ZIndex = p.Z or 1,
		Parent = parent,
	})
	if p.Radius ~= false then
		UI.Corner(frame, p.Radius or 12)
	end
	return frame
end

-- props: Size, Position, Anchor, Font, Color, Scaled, TextSize, AlignX, AlignY, Rich, Name, Order, Z,
--        Stroke (legacy text stroke transparency), MaxSize, Outline (true or thickness), OutlineColor, Gold, Wrap
function UI.Text(parent: Instance?, text: string, props: { [string]: any }?): TextLabel
	local p = props or {}
	local label = UI.Create("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.Anchor or Vector2.zero,
		Font = p.Font or UI.Fonts.Bold,
		Text = text,
		TextColor3 = p.Color or UI.Colors.Text,
		TextScaled = p.Scaled ~= false,
		TextSize = p.TextSize or 18,
		TextWrapped = p.Wrap ~= false,
		TextXAlignment = p.AlignX or Enum.TextXAlignment.Center,
		TextYAlignment = p.AlignY or Enum.TextYAlignment.Center,
		RichText = p.Rich or false,
		Name = p.Name or "Label",
		LayoutOrder = p.Order or 0,
		ZIndex = p.Z or 1,
		Visible = p.Visible ~= false,
		Parent = parent,
	})
	if p.Stroke then
		label.TextStrokeTransparency = p.Stroke
	end
	if p.MaxSize then
		UI.Create("UITextSizeConstraint", { MaxTextSize = p.MaxSize, Parent = label })
	end
	if p.Outline then
		UI.Outline(label, type(p.Outline) == "number" and p.Outline or 2, p.OutlineColor)
	end
	if p.Gold then
		label.TextColor3 = WHITE
		UI.GoldText(label)
	end
	return label
end

-- Glassy panel: lighter indigo at the top, deep navy at the bottom, bright border
-- props: UI.Frame props + Top, Bottom (gradient colours), Border (colour), BorderThickness, BorderT, Gloss
function UI.Panel(parent: Instance?, props: { [string]: any }?): Frame
	local p = props or {}
	local frame = UI.Frame(parent, {
		Size = p.Size,
		Position = p.Position,
		Anchor = p.Anchor,
		Color = WHITE,
		Transparency = p.Transparency or 0,
		Radius = p.Radius or 18,
		Name = p.Name or "Panel",
		Order = p.Order,
		Visible = p.Visible,
		Clip = p.Clip,
		Z = p.Z,
	})
	UI.Gradient(frame, p.Top or UI.Colors.PanelTop, p.Bottom or UI.Colors.Panel, 90).Name = "Fill"
	if p.Border ~= false then
		local stroke = UI.Stroke(frame, p.Border or WHITE, p.BorderThickness or 3, p.BorderT or 0)
		stroke.Name = "Border"
	end
	if p.Gloss ~= false then
		-- soft highlight along the top edge
		local gloss = UI.Frame(frame, {
			Size = UDim2.new(1, -12, 0, math.min(p.GlossHeight or 26, 40)),
			Position = UDim2.fromOffset(6, 4),
			Color = WHITE,
			Transparency = 0.9,
			Radius = math.max((p.Radius or 18) - 4, 4),
			Name = "Gloss",
		})
		UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = gloss })
	end
	return frame
end

-- Card inside a panel. props: UI.Frame props + Accent (border colour), AccentT, Tint (colour mixed into the fill)
function UI.Card(parent: Instance?, props: { [string]: any }?): Frame
	local p = props or {}
	local base = p.Color or UI.Colors.Card
	if p.Tint then
		base = base:Lerp(p.Tint, p.TintAmount or 0.18)
	end
	local frame = UI.Frame(parent, {
		Size = p.Size,
		Position = p.Position,
		Anchor = p.Anchor,
		Color = WHITE,
		Transparency = p.Transparency or 0,
		Radius = p.Radius or 14,
		Name = p.Name or "Card",
		Order = p.Order,
		Visible = p.Visible,
		Clip = p.Clip,
		Z = p.Z,
	})
	UI.Gradient(frame, UI.Shade(base, 0.08), UI.Shade(base, -0.18), 90).Name = "Fill"
	local stroke = UI.Stroke(frame, p.Accent or WHITE, p.AccentThickness or 2, p.AccentT or (p.Accent and 0.15 or 0.86))
	stroke.Name = "Border"
	return frame
end

-- Small rounded pill with text. props: Size, Position, Anchor, Order, TextColor, Font, MaxSize, Transparency, Name
function UI.Chip(parent: Instance?, text: string, color: Color3?, props: { [string]: any }?): TextLabel
	local p = props or {}
	local c = color or UI.Colors.CardHi
	local chip = UI.Text(parent, text, {
		Size = p.Size or UDim2.fromOffset(120, 26),
		Position = p.Position,
		Anchor = p.Anchor,
		Order = p.Order,
		Font = p.Font or UI.Fonts.Black,
		Color = p.TextColor or UI.Colors.Text,
		MaxSize = p.MaxSize or 15,
		Outline = p.Outline or 1.5,
		OutlineColor = UI.Shade(c, -0.6),
		Name = p.Name or "Chip",
		Visible = p.Visible,
		Rich = p.Rich,
		Z = p.Z,
	})
	chip.BackgroundTransparency = p.Transparency or 0.1
	chip.BackgroundColor3 = c
	UI.Corner(chip, p.Radius or 100)
	UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = chip })
	local border = UI.Stroke(chip, UI.Shade(c, 0.35), 1.5, 0.2)
	border.Name = "Border"
	return chip
end

-- Round icon badge (emoji on a glossy coloured disc with a white ring)
function UI.Badge(parent: Instance?, icon: string, color: Color3, size: number, props: { [string]: any }?): Frame
	local p = props or {}
	local badge = UI.Frame(parent, {
		Size = UDim2.fromOffset(size, size),
		Position = p.Position,
		Anchor = p.Anchor,
		Color = WHITE,
		Radius = math.floor(size / 2),
		Name = p.Name or "Badge",
		Order = p.Order,
		Z = p.Z,
	})
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UI.Shade(color, 0.35)),
			ColorSequenceKeypoint.new(0.55, color),
			ColorSequenceKeypoint.new(1, UI.Shade(color, -0.35)),
		}),
		Parent = badge,
	})
	UI.Stroke(badge, p.Ring or WHITE, p.RingThickness or math.max(2, size / 22), p.RingT or 0).Name = "Ring"
	local shine = UI.Frame(badge, { Size = UDim2.fromScale(0.5, 0.26), Position = UDim2.fromScale(0.2, 0.1), Color = WHITE, Transparency = 0.62, Radius = 100, Name = "Shine", Z = p.Z })
	UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1), Parent = shine })
	local label = UI.Text(badge, icon, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.5, 0.52), Anchor = Vector2.new(0.5, 0.5), Font = UI.Fonts.Title, MaxSize = math.floor(size * 0.62), Name = "Icon", Outline = p.IconOutline, Z = p.Z })
	label.TextColor3 = WHITE
	return badge
end

-- A Core: glowing glassy sphere in its rarity colour
function UI.Orb(parent: Instance?, color: Color3, size: number, props: { [string]: any }?): Frame
	local p = props or {}
	local orb = UI.Frame(parent, {
		Size = UDim2.fromOffset(size, size),
		Position = p.Position,
		Anchor = p.Anchor,
		Color = WHITE,
		Radius = math.floor(size / 2),
		Name = p.Name or "Orb",
		Order = p.Order,
		Z = p.Z,
	})
	UI.Create("UIGradient", {
		Rotation = 60,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UI.Shade(color, 0.6)),
			ColorSequenceKeypoint.new(0.45, color),
			ColorSequenceKeypoint.new(1, UI.Shade(color, -0.5)),
		}),
		Name = "Fill",
		Parent = orb,
	})
	local ring = UI.Stroke(orb, UI.Shade(color, 0.25), math.max(2, size / 18), 0.1)
	ring.Name = "Ring"
	local shine = UI.Frame(orb, { Size = UDim2.fromScale(0.34, 0.22), Position = UDim2.fromScale(0.2, 0.14), Color = WHITE, Transparency = 0.25, Radius = 100, Name = "Shine", Z = p.Z })
	shine.Rotation = -30
	return orb
end

-- Recolours an orb made by UI.Orb (e.g. when a rarity changes)
function UI.PaintOrb(orb: Frame, color: Color3)
	local fill = orb:FindFirstChild("Fill")
	if fill and fill:IsA("UIGradient") then
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UI.Shade(color, 0.6)),
			ColorSequenceKeypoint.new(0.45, color),
			ColorSequenceKeypoint.new(1, UI.Shade(color, -0.5)),
		})
	end
	local ring = orb:FindFirstChild("Ring")
	if ring and ring:IsA("UIStroke") then
		ring.Color = UI.Shade(color, 0.25)
	end
end

-- Progress bar with a gradient fill and a shine. Returns (back, fill); size the fill with UDim2.fromScale(ratio, 1)
function UI.Bar(parent: Instance?, color: Color3, props: { [string]: any }?): (Frame, Frame)
	local p = props or {}
	local back = UI.Frame(parent, {
		Size = p.Size or UDim2.new(1, 0, 0, 14),
		Position = p.Position,
		Anchor = p.Anchor,
		Color = rgb(12, 12, 32),
		Transparency = p.Transparency or 0.05,
		Radius = 100,
		Name = p.Name or "Bar",
		Order = p.Order,
		Clip = false,
	})
	UI.Stroke(back, BLACK, 2, 0.45).Name = "Border"
	local fill = UI.Frame(back, { Size = UDim2.fromScale(p.Ratio or 0, 1), Color = color, Radius = 100, Name = "Fill" })
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, rgb(235, 235, 235)),
			ColorSequenceKeypoint.new(1, rgb(170, 170, 170)),
		}),
		Parent = fill,
	})
	UI.Frame(fill, { Size = UDim2.new(1, -8, 0.32, 0), Position = UDim2.new(0, 4, 0.12, 0), Color = WHITE, Transparency = 0.55, Radius = 100, Name = "Shine" })
	return back, fill
end

local clickSound: Sound? = nil
function UI.Click()
	if not clickSound then
		clickSound = UI.Create("Sound", { SoundId = Config.Sounds.Click, Volume = 0.4, Parent = SoundService })
	end
	local sound = clickSound :: Sound
	sound:Play()
end

function UI.Sound(id: string, volume: number?)
	local sound = UI.Create("Sound", { SoundId = id, Volume = volume or 0.5, Parent = SoundService })
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- keeps a chunky button's rim and text outline in tone with its body colour
local function tone(button: TextButton)
	local base = button.BackgroundColor3
	local outline = button:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = UI.Shade(base, -0.62)
	end
	local rim = button:FindFirstChild("Rim")
	local rimStroke = rim and rim:FindFirstChildOfClass("UIStroke")
	if rimStroke then
		rimStroke.Color = UI.Shade(base, -0.5)
	end
end

-- Chunky 3D button: glossy body, darker lip along the bottom, dark rim, white outlined text, bouncy hover/press.
-- Returns the TextButton (its Text, BackgroundColor3, TextTransparency can be changed later); onClick gets no args.
-- props: Size, Position, Anchor, Font, TextColor, Name, Order, Z, Radius, MaxSize, Lip, Outline
function UI.Button(parent: Instance?, text: string, color: Color3?, onClick: (() -> ())?, props: { [string]: any }?): TextButton
	local p = props or {}
	local base = color or UI.Colors.Blue
	local size: UDim2 = p.Size or UDim2.fromOffset(120, 40)
	local button = UI.Create("TextButton", {
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = size,
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.Anchor or Vector2.zero,
		Font = p.Font or UI.Fonts.Title,
		Text = text,
		TextColor3 = p.TextColor or UI.Colors.Text,
		TextScaled = true,
		TextWrapped = false,
		Name = p.Name or "Button",
		LayoutOrder = p.Order or 0,
		ZIndex = p.Z or 1,
		Parent = parent,
	})
	local radius = p.Radius or 12
	UI.Corner(button, radius)
	UI.Create("UITextSizeConstraint", { MaxTextSize = p.MaxSize or 22, Parent = button })
	local height = size.Y.Scale == 0 and size.Y.Offset or 40
	local lip = p.Lip or math.clamp(math.floor(height * 0.12 + 0.5), 3, 7)
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, lip + 2),
		Parent = button,
	})
	-- body: bright top, soft middle, hard darker lip at the bottom (a raised "key")
	local edge = math.clamp(1 - lip / math.max(height, 1), 0.6, 0.97)
	UI.Create("UIGradient", {
		Name = "Body",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(math.max(edge - 0.03, 0.01), rgb(214, 214, 214)),
			ColorSequenceKeypoint.new(edge, rgb(138, 138, 138)),
			ColorSequenceKeypoint.new(1, rgb(120, 120, 120)),
		}),
		Parent = button,
	})
	UI.Outline(button, p.Outline or 2, UI.Shade(base, -0.62))
	-- children sit inside the UIPadding, so full-size overlays are grown back to the button's edges
	local fillSize, fillPos = UI.ButtonFill(button)
	local rim = UI.Frame(button, { Size = fillSize, Position = fillPos, Transparency = 1, Radius = radius, Name = "Rim" })
	UI.Stroke(rim, UI.Shade(base, -0.5), 2, 0)
	-- gloss on the upper part; on round buttons a smaller oval so it never pokes out past the circle
	local width = size.X.Scale == 0 and size.X.Offset or 120
	local round = radius * 2 >= math.min(width, height) - 2
	local inset = math.min(6, radius / 2)
	local shine = UI.Frame(rim, {
		Size = round and UDim2.fromScale(0.58, 0.24) or UDim2.new(1, -inset * 2, 0.3, 0),
		Position = round and UDim2.fromScale(0.21, 0.09) or UDim2.fromOffset(inset, 2),
		Color = WHITE,
		Transparency = 0.8,
		Radius = round and 100 or math.max(radius - 4, 3),
		Name = "Shine",
	})
	UI.Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 1), Parent = shine })
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		tone(button)
	end)
	local scale = UI.Create("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		UI.Tween(scale, 0.12, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		UI.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.Tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if onClick then
		button.Activated:Connect(function()
			UI.Click()
			onClick()
		end)
	end
	return button
end

-- Size/Position that make a child of a UI.Button cover the whole button (undoing its UIPadding)
function UI.ButtonFill(button: GuiObject): (UDim2, UDim2)
	local pad = button:FindFirstChildOfClass("UIPadding")
	if not pad then
		return UDim2.fromScale(1, 1), UDim2.new()
	end
	local l, r, t, b = pad.PaddingLeft.Offset, pad.PaddingRight.Offset, pad.PaddingTop.Offset, pad.PaddingBottom.Offset
	return UDim2.new(1, l + r, 1, t + b), UDim2.fromOffset(-l, -t)
end

-- Greys a button out (still clickable so it can explain why)
function UI.SetEnabled(button: TextButton, enabled: boolean, color: Color3?)
	button.BackgroundColor3 = enabled and (color or UI.Colors.Blue) or UI.Colors.Disabled
	button.TextTransparency = enabled and 0 or 0.3
end

function UI.Screen(name: string, order: number): ScreenGui
	local gui = UI.Create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		Parent = player:WaitForChild("PlayerGui"),
	})
	return gui
end

-- Scale for the ~1280x800 design. On short screens (phones in landscape) `fitHeight` design pixels are
-- fitted to the screen height instead, so text and buttons stay large enough to read and tap.
function UI.ScaleFor(size: Vector2, fitHeight: number?): number
	local s = math.min(size.X / 1280, size.Y / 800)
	if fitHeight and size.Y < 600 then
		s = math.max(s, math.min(size.Y / fitHeight, size.X / 1000))
	end
	return math.clamp(s, 0.5, 1.35)
end

-- Adds a UIScale that keeps the ~1280x800 design readable on every screen
function UI.AutoScale(target: Instance, fitHeight: number?): UIScale
	local scale = UI.Create("UIScale", { Parent = target })
	local camera = workspace.CurrentCamera
	local function update()
		scale.Scale = UI.ScaleFor(camera.ViewportSize, fitHeight)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return scale
end

-- Vertical scrolling list that grows with its content
function UI.Scroll(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local p = props or {}
	local scroll = UI.Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = rgb(150, 160, 230),
		ScrollBarImageTransparency = 0.15,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Name = p.Name or "Scroll",
		Parent = parent,
	})
	if p.Grid then
		UI.Create("UIGridLayout", {
			CellSize = p.Grid,
			CellPadding = UDim2.fromOffset(p.Gap or 10, p.Gap or 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	else
		UI.List(scroll, p.Gap or 8)
	end
	UI.Create("UIPadding", { PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 4), Parent = scroll })
	return scroll
end

function UI.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Row of tab buttons (gold = selected). tabs: { id, label, width? }. Returns a function select(id)
function UI.Tabs(parent: Instance, tabs: { { id: string, label: string, width: number? } }, onSelect: (string) -> ()): (string) -> ()
	local bar = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 48), Transparency = 1, Radius = false, Name = "Tabs" })
	UI.List(bar, 8, true)
	local buttons: { [string]: TextButton } = {}
	local function select(id: string)
		for tabId, button in buttons do
			button.BackgroundColor3 = tabId == id and UI.Colors.Gold or UI.Colors.CardHi
		end
		onSelect(id)
	end
	for i, tab in tabs do
		local button = UI.Button(bar, tab.label, UI.Colors.CardHi, function()
			select(tab.id)
		end, { Size = UDim2.fromOffset(tab.width or 170, 46), Order = i, MaxSize = 19, Radius = 14 })
		button.Name = "Tab_" .. tab.id
		buttons[tab.id] = button
	end
	return select
end

-- 0..1 -> "60%", "16.7%", "1.8%", "0.2%", "0.00012%" (two significant digits for small chances, no rounding to 0)
function UI.Percent(p: number): string
	local x = p * 100
	if x <= 0 then
		return "0%"
	elseif x >= 100 then
		return "100%"
	end
	local s
	if x >= 99 then
		s = string.format("%.3f", x)
	elseif x >= 10 then
		s = string.format("%.1f", x)
	elseif x >= 1 then
		s = string.format("%.2f", x)
	else
		local digits = math.clamp(math.floor(-math.log10(x)) + 2, 2, 12)
		s = string.format("%." .. digits .. "f", x)
	end
	if string.find(s, ".", 1, true) then
		s = (string.gsub(s, "0+$", ""))
		s = (string.gsub(s, "%.$", ""))
	end
	return s .. "%"
end

-- Robux logo drawn with frames (rounded ring with a square in the middle), so no image asset is needed
function UI.RobuxIcon(parent: Instance?, size: number, props: { [string]: any }?): Frame
	local p = props or {}
	local icon = UI.Frame(parent, { Size = UDim2.fromOffset(size, size), Position = p.Position, Anchor = p.Anchor, Transparency = 1, Radius = math.floor(size * 0.3), Name = "Robux", Order = p.Order, Z = p.Z })
	UI.Stroke(icon, p.Color or WHITE, math.max(2, size * 0.17), 0)
	UI.Frame(icon, { Size = UDim2.fromScale(0.36, 0.36), Position = UDim2.fromScale(0.5, 0.5), Anchor = Vector2.new(0.5, 0.5), Color = p.Color or WHITE, Radius = 2, Name = "Square", Z = p.Z })
	return icon
end

-- A rich-text coloured span
function UI.Span(text: string, color: Color3): string
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

-- Cheap rarity styling for a label: colour, plus an animated rainbow for "???"
function UI.StyleRarity(label: TextLabel, r: number)
	local rarity = Config.Rarities[r]
	label.TextColor3 = rarity and rarity.color or UI.Colors.Text
	local old = label:FindFirstChild("RarityGradient")
	if old then
		old:Destroy()
	end
	if rarity and rarity.secret then
		local g = UI.Rainbow(label)
		g.Name = "RarityGradient"
		label.TextColor3 = WHITE
		task.spawn(function()
			while g.Parent do
				g.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.5, 0)
				task.wait(0.05)
			end
		end)
	end
end

return UI
