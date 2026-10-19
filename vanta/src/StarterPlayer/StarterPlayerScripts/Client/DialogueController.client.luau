--!strict
-- Dialogue box (L-40, L-42; UI v2 look). Text is typed out line by line. Click or tap the box, or press E, Space or
-- Enter, to finish the current line or move on. Skip (or Tab) jumps to the next decision, or ends the
-- conversation when there is none. Number keys pick choices. Conversations already seen show their text
-- at once. Talk prompts are hidden while talking. The server decides everything that matters.
-- The screen stays named "Dialogue" and opens by Enabled: the shoulder camera frees the mouse by it.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Ui = require(ReplicatedStorage:WaitForChild("Shared").Presentation.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local STEP_GRAPHEMES = 2
local STEP_SECONDS = 0.03
local NUMBER_KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5 }
local C, F = Ui.colors, Ui.fonts

local function label(parent: Instance, name: string, font: Font, size: number, color: Color3): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextWrapped = true
	text.RichText = true
	text.Parent = parent
	return text
end

-- quiet small button (Skip, X)
local function button(parent: Instance, text: string): TextButton
	local item = Ui.button(parent, text, function() end, 56)
	item.TextSize = 12
	item.TextColor3 = C.muted
	return item
end

local gui = Instance.new("ScreenGui")
gui.Name = "Dialogue"
gui.ResetOnSpawn = false
gui.Enabled = false

-- the box: v2 window treatment, compact at the bottom centre
local box = Instance.new("TextButton")
box.Name = "Box"
box.Text = ""
box.AutoButtonColor = false
box.AnchorPoint = Vector2.new(0.5, 1)
box.Position = UDim2.new(0.5, 0, 1, -28)
box.Size = UDim2.new(0.62, 0, 0, 168)
box.BackgroundColor3 = C.navy
box.BackgroundTransparency = 0.04
Ui.shade(box, 0.55)
Ui.stroke(box, C.line, 0.25)
Ui.corner(box, 4)
local limits = Instance.new("UISizeConstraint")
limits.MinSize = Vector2.new(320, 168)
limits.MaxSize = Vector2.new(860, 168)
limits.Parent = box
local inner = Instance.new("Frame")
inner.BackgroundTransparency = 1
inner.Position = UDim2.new(0, 5, 0, 5)
inner.Size = UDim2.new(1, -10, 1, -10)
Ui.stroke(inner, Color3.fromRGB(27, 40, 64), 0)
Ui.corner(inner, 2)
inner.Parent = box
for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	local cx, cy = corner[1], corner[2]
	local at = UDim2.new(cx, if cx == 0 then 10 else -10, cy, if cy == 0 then 10 else -10)
	for _, size in ipairs({ UDim2.new(0, 18, 0, 1), UDim2.new(0, 1, 0, 18) }) do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = C.gold
		line.BackgroundTransparency = 0.2
		line.AnchorPoint = Vector2.new(cx, cy)
		line.Position = at
		line.Size = size
		line.Parent = box
	end
end

-- name plate on the top edge: Cinzel name, small title beside it
local plate = Instance.new("Frame")
plate.Name = "Plate"
plate.AutomaticSize = Enum.AutomaticSize.X
plate.Position = UDim2.new(0, 28, 0, -18)
plate.Size = UDim2.new(0, 0, 0, 34)
plate.BackgroundColor3 = Color3.fromRGB(30, 26, 16)
plate.BackgroundTransparency = 0.02
Ui.stroke(plate, C.gold, 0.15)
Ui.corner(plate, 3)
local platePad = Instance.new("UIPadding")
platePad.PaddingLeft = UDim.new(0, 18)
platePad.PaddingRight = UDim.new(0, 18)
platePad.Parent = plate
Ui.list(plate, 10, true)
local speaker = label(plate, "Speaker", F.title, 17, Color3.fromRGB(231, 198, 126))
speaker.AutomaticSize = Enum.AutomaticSize.X
speaker.Size = UDim2.new(0, 0, 1, 0)
speaker.TextWrapped = false
speaker.TextYAlignment = Enum.TextYAlignment.Center
local role = label(plate, "Role", F.label, 12, C.muted)
role.AutomaticSize = Enum.AutomaticSize.X
role.Size = UDim2.new(0, 0, 1, 0)
role.TextWrapped = false
role.TextYAlignment = Enum.TextYAlignment.Center
plate.Parent = box

local body = label(box, "Body", F.body, 18, C.text)
body.LineHeight = 1.22
body.Position = UDim2.new(0, 30, 0, 30)
body.Size = UDim2.new(1, -60, 1, -66)
local hint = label(box, "Hint", F.label, 11, Color3.fromRGB(93, 106, 130))
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.Position = UDim2.new(0, 30, 1, -26)
hint.Size = UDim2.new(1, -60, 0, 14)
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	hint.Text = "Tap to continue"
else
	hint.Text = "E  continue   ·   Tab  skip   ·   1–5  choose"
end
local skipButton = button(box, "Skip")
skipButton.Position = UDim2.new(1, -112, 0, 12)
skipButton.Size = UDim2.new(0, 52, 0, 24)
local closeButton = button(box, "X")
closeButton.Position = UDim2.new(1, -52, 0, 12)
closeButton.Size = UDim2.new(0, 26, 0, 24)

-- choices: numbered rows above the box, same width
local choicesFrame = Instance.new("Frame")
choicesFrame.Name = "Choices"
choicesFrame.BackgroundTransparency = 1
choicesFrame.AnchorPoint = Vector2.new(0.5, 1)
choicesFrame.Position = UDim2.new(0.5, 0, 1, -216)
choicesFrame.Size = UDim2.new(0.62, 0, 0, 0)
choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
local choiceLimits = Instance.new("UISizeConstraint")
choiceLimits.MaxSize = Vector2.new(860, math.huge)
choiceLimits.Parent = choicesFrame
choicesFrame.Parent = gui
local choiceLayout = Instance.new("UIListLayout")
choiceLayout.Padding = UDim.new(0, 6)
choiceLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
choiceLayout.Parent = choicesFrame

box.Parent = gui
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- one choice row: a number badge and the text; azure on hover
local function choiceRow(position: number, text: string): TextButton
	local row = Instance.new("TextButton")
	row.Text = ""
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = C.navy
	row.BackgroundTransparency = 0.08
	Ui.shade(row, 0.7)
	local stroke = Ui.stroke(row, C.line, 0.35)
	Ui.corner(row, 3)
	local key = label(row, "Key", F.labelBold, 14, C.accent)
	key.Text = tostring(position)
	key.Position = UDim2.new(0, 16, 0, 0)
	key.Size = UDim2.new(0, 20, 1, 0)
	key.TextYAlignment = Enum.TextYAlignment.Center
	local words = label(row, "Text", F.bodyBold, 16, C.text)
	words.Text = text
	words.Position = UDim2.new(0, 44, 0, 0)
	words.Size = UDim2.new(1, -60, 1, 0)
	words.TextYAlignment = Enum.TextYAlignment.Center
	row.MouseEnter:Connect(function()
		stroke.Color = C.accent
		stroke.Transparency = 0.05
	end)
	row.MouseLeave:Connect(function()
		stroke.Color = C.line
		stroke.Transparency = 0.35
	end)
	row.Parent = choicesFrame
	return row
end

local view: any = nil
local lineIndex = 0
local typing = false

local function send(action: string, index: number?)
	if view then
		remotes.DialogueAction:FireServer(view.token, action, index)
	end
end

local function clearChoices()
	for _, child in ipairs(choicesFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function choose(position: number)
	local choice = view and view.choices[position]
	if choice then
		clearChoices()
		send("Choose", choice.index)
	end
end

local function showChoices()
	clearChoices()
	if view == nil then
		return
	end
	for position, choice in ipairs(view.choices) do
		local item = choiceRow(position, choice.text)
		item.Activated:Connect(function()
			choose(position)
		end)
	end
end

local function finishLine()
	typing = false
	body.MaxVisibleGraphemes = -1
	if view and lineIndex >= #view.lines and #view.choices > 0 then
		showChoices()
	end
end

local function showLine()
	if view == nil then
		return
	end
	if #view.lines == 0 then
		body.Text = ""
		showChoices()
		return
	end
	local text = view.lines[lineIndex]
	body.Text = text
	if view.seen then
		finishLine()
		return
	end
	typing = true
	body.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown = 0
		local total = utf8.len(text) or #text
		while typing and body.Text == text and shown < total do
			shown += STEP_GRAPHEMES
			body.MaxVisibleGraphemes = shown
			task.wait(STEP_SECONDS)
		end
		if typing and body.Text == text then
			finishLine()
		end
	end)
end

local function advance()
	if view == nil then
		return
	end
	if typing then
		finishLine()
	elseif lineIndex < #view.lines then
		lineIndex += 1
		showLine()
	elseif #view.choices == 0 then
		send("Continue")
	end
end

local function skip()
	if view == nil then
		return
	end
	lineIndex = math.max(#view.lines, 1)
	if #view.lines > 0 then
		body.Text = view.lines[#view.lines]
	end
	finishLine()
	if #view.choices == 0 then
		send("Skip")
	end
end

local function hide()
	view = nil
	typing = false
	clearChoices()
	gui.Enabled = false
	ProximityPromptService.Enabled = true
end

local function close()
	send("Close")
	hide()
end

remotes.DialogueView.OnClientEvent:Connect(function(newView: any)
	clearChoices()
	if newView == nil then
		hide()
		return
	end
	view = newView
	speaker.Text = string.upper(tostring(newView.speaker))
	role.Text = tostring(newView.title or "")
	lineIndex = 1
	gui.Enabled = true
	ProximityPromptService.Enabled = false
	showLine()
end)

box.Activated:Connect(advance)
skipButton.Activated:Connect(skip)
closeButton.Activated:Connect(close)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if view == nil or (processed and NUMBER_KEYS[input.KeyCode] == nil) then
		return
	end
	local code = input.KeyCode
	if code == Enum.KeyCode.E or code == Enum.KeyCode.Space or code == Enum.KeyCode.Return then
		advance()
	elseif code == Enum.KeyCode.Tab then
		skip()
	elseif NUMBER_KEYS[code] and not typing then
		choose(NUMBER_KEYS[code])
	end
end)
