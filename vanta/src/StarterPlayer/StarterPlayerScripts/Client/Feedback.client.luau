--!strict
-- Brief feedback (L-42; UI v2 and L-65): server messages appear as small System messages at the top right, slide
-- in, stay a few seconds and fade. At most three at a time; nothing stays on screen. The server sends plain text,
-- so the kind (quest, level, item) is recognised from the wording only to colour and label it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ui = require(ReplicatedStorage:WaitForChild("Shared").Presentation.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local C, F = Ui.colors, Ui.fonts
local MAX_VISIBLE = 3
local WIDTH = 340

local gui = Instance.new("ScreenGui")
gui.Name = "Feedback"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(1, 0)
holder.Position = UDim2.new(1, -24, 0, 96)
holder.Size = UDim2.new(0, WIDTH, 0, 0)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Parent = gui
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = holder
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- the kind of message, from its wording: label and colour
local function kindOf(text: string): (string, Color3, boolean)
	local lower = string.lower(text)
	if string.find(lower, "level up", 1, true) or string.find(lower, "reached level", 1, true) or string.find(lower, "you are now level", 1, true) then
		return "LEVEL UP", C.gold, true
	elseif string.find(lower, "quest", 1, true) then
		return "QUEST", C.gold, false
	elseif string.find(lower, "you craft", 1, true) or string.find(lower, "you gather", 1, true) or string.find(lower, "you receive", 1, true) or string.find(lower, "you found", 1, true) or string.find(lower, "loot", 1, true) or string.find(lower, "you buy", 1, true) or string.find(lower, "you sell", 1, true) then
		return "ITEM", C.accent, false
	end
	return "", C.line, false
end

local shown: {CanvasGroup} = {}
local order = 0

local function remove(toast: CanvasGroup)
	local index = table.find(shown, toast)
	if index then
		table.remove(shown, index)
	end
	toast:Destroy()
end

remotes.Notify.OnClientEvent:Connect(function(message: any)
	local text = tostring(message)
	local kind, color, important = kindOf(text)
	order += 1
	local toast = Instance.new("CanvasGroup")
	toast.LayoutOrder = order
	toast.BackgroundTransparency = 1
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	local back = Instance.new("Frame")
	back.BorderSizePixel = 0
	back.BackgroundColor3 = C.navy
	back.Size = UDim2.new(1, 0, 1, 0)
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = back
	back.Parent = toast
	local edge = Instance.new("Frame")
	edge.BorderSizePixel = 0
	edge.BackgroundColor3 = color
	edge.Size = UDim2.new(0, 2, 1, 0)
	edge.Parent = toast
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = content
	Ui.list(content, 2)
	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.FontFace = F.labelBold
	head.TextSize = 11
	head.TextColor3 = if kind == "" then C.muted else color
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Size = UDim2.new(1, 0, 0, 14)
	head.Text = "◆ SYSTEM" .. (if kind ~= "" then "  ·  " .. kind else "")
	head.Parent = content
	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.FontFace = if important then F.title else F.bodyBold
	body.TextSize = if important then 17 else 14
	body.TextColor3 = C.text
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextWrapped = true
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Text = text
	body.Parent = content
	content.Parent = toast
	if important then
		local glow = Ui.stroke(toast, C.gold, 0.55)
		glow.Thickness = 1
	end
	-- slide in from the right, stay, fade out
	toast.GroupTransparency = 1
	toast.Position = UDim2.new(0, 24, 0, 0)
	toast.Parent = holder
	table.insert(shown, toast)
	while #shown > MAX_VISIBLE do
		remove(shown[1])
	end
	TweenService:Create(toast, TweenInfo.new(Ui.timing.toastIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	task.delay(Ui.timing.toastStay + (if important then 1.5 else 0), function()
		if toast.Parent then
			local out = TweenService:Create(toast, TweenInfo.new(Ui.timing.toastOut), { GroupTransparency = 1 })
			out:Play()
			out.Completed:Wait()
			if toast.Parent then
				remove(toast)
			end
		end
	end)
end)
