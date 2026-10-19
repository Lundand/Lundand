--!strict
-- VANTA interface kit (L-41, L-42, L-52). Every window uses these pieces so all screens look and behave alike:
-- dark navy and charcoal panels, silver lines, restrained gold, violet for magic. One window is open at a
-- time; windows open only on request and close with their Close button or by pressing their key again.
-- Built for PC first (L-52).
local Players = game:GetService("Players")

local Ui = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Design system (L-63, refined): dark translucent panels, thin restrained lines, gold for ornament and the most
-- important things, azure only for focus and selection. Glow is reserved for selected, rare and legendary items and
-- meaningful notifications. Colour keys keep their old names so every window keeps working.
Ui.colors = {
	navy = rgb(16, 24, 42), -- panel background
	charcoal = rgb(7, 10, 20), -- insets and tracks
	raised = rgb(22, 32, 54), -- buttons and headers
	silver = rgb(150, 162, 184), -- secondary text, neutral lines
	line = rgb(76, 112, 158), -- panel borders
	accent = rgb(110, 175, 235), -- focus and selection
	gold = rgb(214, 178, 104), -- titles, ornaments, legendary
	violet = rgb(150, 110, 230),
	text = rgb(232, 236, 244),
	muted = rgb(150, 162, 184),
	red = rgb(214, 70, 86),
	green = rgb(120, 190, 130),
	hp = rgb(196, 52, 70),
	stamina = rgb(212, 160, 64),
	mana = rgb(70, 120, 230),
	xp = rgb(110, 175, 235),
}
Ui.rarity = { Common = rgb(200, 200, 200), Uncommon = rgb(110, 200, 120), Rare = rgb(90, 150, 240), Epic = rgb(170, 100, 230), Legendary = rgb(240, 170, 60) }
-- Rarity is never colour alone: each tier also shows pips beside its name.
Ui.rarityPips = { Common = "◆", Uncommon = "◆◆", Rare = "◆◆◆", Epic = "◆◆◆◆", Legendary = "◆◆◆◆◆" }
-- Hex versions for rich text.
Ui.hex = { gold = "#d6b268", silver = "#96a2b8", muted = "#96a2b8", red = "#d64656", green = "#78be82", accent = "#6eafeb" }
Ui.fonts = {
	title = Font.new("rbxasset://fonts/families/Cinzel.json", Enum.FontWeight.Regular),
	label = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.SemiBold),
	labelBold = Font.new("rbxasset://fonts/families/Jura.json", Enum.FontWeight.Bold),
	body = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Regular),
	bodyBold = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.SemiBold),
}
-- Type scale (px) and spacing steps (4, 8, 12, 16, 24). Text never goes below 12 except key badges.
Ui.size = { title = 22, heading = 16, body = 15, label = 13, small = 12 }
-- Transition timing (seconds): subtle, never in the way.
Ui.timing = { open = 0.14, hover = 0.08, toastIn = 0.2, toastStay = 3.5, toastOut = 0.4 }

local windows: {[string]: any} = {}
local openName: string? = nil

function Ui.screen(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Ui.stroke(parent: Instance, color: Color3?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Ui.colors.line
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Ui.corner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 4)
	corner.Parent = parent
end

-- A soft vertical shade over a frame's colour (top brighter).
function Ui.shade(parent: Instance, bottom: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	local b = bottom or 0.62
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(b, b, b))
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function Ui.list(parent: Instance, gap: number?, horizontal: boolean?)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap or 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if horizontal then
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Wraps = true
	end
	layout.Parent = parent
end

-- Large numbers read better grouped: 100000 -> 100,000. Only standalone numbers of 5+ digits (so years, short
-- numbers and names with digits such as "Storefront01" are left alone).
function Ui.groupNumbers(text: string): string
	return (string.gsub(text, "%f[%w]([1-9]%d%d%d%d+)()%f[%W]", function(digits: string, after: number): string
		-- only amounts: what follows must be a unit ("gold", "Robux", "EXP", "XP"), "of", "/" or "%", so names
		-- made of digits (a player called "0009000") are never touched
		local rest = string.sub(text, after, after + 8)
		if not (string.find(rest, "^%s*gold") or string.find(rest, "^%s*Robux") or string.find(rest, "^%s*EXP") or string.find(rest, "^%s*XP") or string.find(rest, "^%s*of%f[%W]") or string.find(rest, "^%s*/") or string.find(rest, "^%s*%%") or string.find(rest, "^</font>%s*gold")) then
			return digits
		end
		local formatted = digits
		while true do
			local count
			formatted, count = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
			if count == 0 then
				break
			end
		end
		return formatted
	end))
end

function Ui.text(parent: Instance, value: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.RichText = true
	label.FontFace = if bold then Ui.fonts.bodyBold else Ui.fonts.body
	label.TextSize = size or Ui.size.body
	label.TextColor3 = color or Ui.colors.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.LineHeight = 1.1
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 0)
	label.Text = Ui.groupNumbers(value)
	label.Parent = parent
	return label
end

-- Buttons: quiet by default, an azure edge on hover, darker while pressed.
function Ui.button(parent: Instance, value: string, onClick: () -> (), width: number?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = Ui.colors.raised
	button.BackgroundTransparency = 0.08
	button.TextColor3 = Ui.colors.text
	button.FontFace = Ui.fonts.label
	button.TextSize = 14
	button.Text = Ui.groupNumbers(value)
	button.Size = if width then UDim2.new(0, width, 0, 30) else UDim2.new(1, 0, 0, 32)
	local stroke = Ui.stroke(button)
	Ui.corner(button, 3)
	local hover = Color3.fromRGB(30, 44, 72)
	button.MouseEnter:Connect(function()
		stroke.Color = Ui.colors.accent
		stroke.Transparency = 0.1
		button.BackgroundColor3 = hover
	end)
	button.MouseLeave:Connect(function()
		local isSelected = button:GetAttribute("Selected") == true
		local isPrimary = button:GetAttribute("Primary") == true
		local isDanger = button:GetAttribute("Danger") == true
		stroke.Color = if isSelected then Ui.colors.accent elseif isPrimary then Ui.colors.gold elseif isDanger then Ui.colors.red else Ui.colors.line
		stroke.Transparency = if isSelected then 0 elseif isPrimary then 0.15 elseif isDanger then 0.4 else 0.35
		button.BackgroundColor3 = Ui.colors.raised
	end)
	button.MouseButton1Down:Connect(function()
		button.BackgroundColor3 = Ui.colors.charcoal
	end)
	button.MouseButton1Up:Connect(function()
		button.BackgroundColor3 = hover
	end)
	button.Activated:Connect(onClick)
	button.Parent = parent
	return button
end

function Ui.bar(parent: Instance, fraction: number, color: Color3?): Frame
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Ui.colors.charcoal
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, 0, 0, 8)
	Ui.corner(back, 2)
	Ui.stroke(back, Ui.colors.line, 0.6)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color or Ui.colors.xp
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(math.max(0, math.min(1, fraction)), 0, 1, 0)
	Ui.corner(fill, 2)
	Ui.shade(fill, 0.75)
	fill.Parent = back
	back.Parent = parent
	return back
end

-- The primary action of a window (design system): gold text and border, kept through hover. Returns the button.
function Ui.primary(button: TextButton): TextButton
	button:SetAttribute("Primary", true)
	button.TextColor3 = Ui.colors.gold
	button.FontFace = Ui.fonts.labelBold
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil then
		stroke.Color = Ui.colors.gold
		stroke.Transparency = 0.15
	end
	return button
end

-- A destructive action (leave, disband, remove for good): red text and border, kept through hover.
function Ui.danger(button: TextButton): TextButton
	button:SetAttribute("Danger", true)
	button.TextColor3 = Ui.colors.red
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil then
		stroke.Color = Ui.colors.red
		stroke.Transparency = 0.4
	end
	return button
end

-- The selected state for a button (design system): an azure 2 px border that stays through hover.
function Ui.markSelected(button: GuiObject)
	button:SetAttribute("Selected", true)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke == nil then
		stroke = Ui.stroke(button)
	end
	stroke.Color = Ui.colors.accent
	stroke.Transparency = 0
	stroke.Thickness = 2
	if button:IsA("TextButton") then
		button.TextColor3 = Ui.colors.text
	end
end

-- A titled group inside a window: small gold capitals over an inset panel.
function Ui.section(parent: Instance, title: string): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Ui.colors.charcoal
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, 0, 0, 0)
	Ui.corner(frame)
	Ui.stroke(frame, Ui.colors.line, 0.65)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame
	Ui.list(frame, 6)
	local heading = Ui.text(frame, string.upper(title), Ui.size.label, Ui.colors.gold)
	heading.FontFace = Ui.fonts.labelBold
	frame.Parent = parent
	return frame
end

-- A horizontal line of controls.
function Ui.row(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, 0, 0, 0)
	Ui.list(frame, 8, true)
	frame.Parent = parent
	return frame
end

function Ui.clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A centred window: gold ornament and Cinzel title, a fading gold divider, a compact close button and a scrolling
-- body. Opens with a subtle scale-in. Returns the window and its body.
function Ui.window(gui: ScreenGui, name: string, title: string, width: number?, height: number?): (Frame, ScrollingFrame)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	-- Designed at 1920x1080: the window keeps its layout and scales as a whole to fit smaller screens (see the
	-- UIScale below), so nothing inside is ever squeezed or cut off.
	local designWidth, designHeight = width or 560, height or 560
	frame.Size = UDim2.fromOffset(designWidth, designHeight)
	frame.BackgroundColor3 = Ui.colors.navy
	frame.BackgroundTransparency = 0.06
	frame.Visible = false
	Ui.shade(frame, 0.55)
	Ui.stroke(frame, Ui.colors.line, 0.3)
	Ui.corner(frame)
	-- v2 chrome (Figma "UI v2"): a second inner line, gold filigree corners, the title centred between gold rules,
	-- a fine divider under the header, and a quiet X to close.
	local inner = Instance.new("Frame")
	inner.Name = "InnerLine"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.new(0, 5, 0, 5)
	inner.Size = UDim2.new(1, -10, 1, -10)
	Ui.stroke(inner, Color3.fromRGB(27, 40, 64), 0)
	Ui.corner(inner, 2)
	inner.Parent = frame
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local cx, cy = corner[1], corner[2]
		local at = UDim2.new(cx, if cx == 0 then 10 else -10, cy, if cy == 0 then 10 else -10)
		for _, size in ipairs({ UDim2.new(0, 22, 0, 1), UDim2.new(0, 1, 0, 22) }) do
			local line = Instance.new("Frame")
			line.BorderSizePixel = 0
			line.BackgroundColor3 = Ui.colors.gold
			line.BackgroundTransparency = 0.15
			line.AnchorPoint = Vector2.new(cx, cy)
			line.Position = at
			line.Size = size
			line.Parent = frame
		end
		local gem = Instance.new("Frame")
		gem.BorderSizePixel = 0
		gem.BackgroundColor3 = Color3.fromRGB(231, 198, 126)
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Rotation = 45
		gem.Size = UDim2.new(0, 5, 0, 5)
		gem.Position = at
		gem.Parent = frame
	end
	local heading = Ui.text(frame, string.upper(title), 20, Ui.colors.text)
	heading.Name = "Title"
	heading.FontFace = Ui.fonts.title
	heading.TextXAlignment = Enum.TextXAlignment.Center
	heading.Position = UDim2.new(0, 0, 0, 18)
	heading.Size = UDim2.new(1, 0, 0, 28)
	heading.AutomaticSize = Enum.AutomaticSize.None
	for side = 0, 1 do
		local rule = Instance.new("Frame")
		rule.BorderSizePixel = 0
		rule.BackgroundColor3 = Ui.colors.gold
		rule.Position = UDim2.new(if side == 0 then 0.1 else 0.7, 0, 0, 32)
		rule.Size = UDim2.new(0.2, 0, 0, 1)
		local fade = Instance.new("UIGradient")
		fade.Transparency = if side == 0
			then NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
			else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = rule
		rule.Parent = frame
	end
	local divider = Instance.new("Frame")
	divider.BorderSizePixel = 0
	divider.BackgroundColor3 = Ui.colors.line
	divider.Position = UDim2.new(0, 24, 0, 60)
	divider.Size = UDim2.new(1, -48, 0, 1)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = divider
	divider.Parent = frame
	local close = Ui.button(frame, "X", function()
		Ui.close()
	end, 28)
	close.Name = "Close"
	close.Size = UDim2.new(0, 28, 0, 28)
	close.TextColor3 = Ui.colors.muted
	close.Position = UDim2.new(1, -58, 0, 20)
	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.new(0, 24, 0, 74)
	body.Size = UDim2.new(1, -48, 1, -92)
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = Ui.colors.line
	body.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar -- content never runs under the scroll bar
	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingRight = UDim.new(0, 10)
	bodyPadding.PaddingBottom = UDim.new(0, 8)
	bodyPadding.PaddingTop = UDim.new(0, 4)
	bodyPadding.PaddingLeft = UDim.new(0, 4)
	bodyPadding.Parent = body
	Ui.list(body, 12)
	body.Parent = frame
	-- subtle scale-in when shown
	local scale = Instance.new("UIScale")
	local function fit(): number
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
		return math.min(1, viewport.X * 0.95 / designWidth, (viewport.Y - 60) * 0.92 / designHeight)
	end
	scale.Scale = fit()
	scale.Parent = frame
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			local target = fit()
			scale.Scale = target * 0.97
			game:GetService("TweenService"):Create(scale, TweenInfo.new(Ui.timing.open, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target }):Play()
		end
	end)
	local camera = workspace.CurrentCamera
	if camera ~= nil then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			scale.Scale = fit()
		end)
	end
	frame.Parent = gui
	windows[name] = { frame = frame, refresh = function() end, closed = function() end }
	return frame, body
end

function Ui.onRefresh(name: string, refresh: () -> ())
	windows[name].refresh = refresh
end

function Ui.onClose(name: string, closed: () -> ())
	windows[name].closed = closed
end

function Ui.close()
	local current = openName and windows[openName]
	if current ~= nil then
		current.frame.Visible = false
		openName = nil
		current.closed()
	end
end

function Ui.open(name: string)
	if openName ~= nil and openName ~= name then
		Ui.close()
	end
	local window = windows[name]
	if window ~= nil then
		window.frame.Visible = true
		openName = name
		window.refresh()
	end
end

function Ui.toggle(name: string)
	if openName == name then
		Ui.close()
	else
		Ui.open(name)
	end
end

function Ui.isOpen(name: string): boolean
	return openName == name
end

function Ui.refresh(name: string)
	if openName == name then
		windows[name].refresh()
	end
end


-- Whether any window is open (the combat HUD steps aside while one is).
function Ui.anyOpen(): boolean
	return openName ~= nil
end

return Ui
