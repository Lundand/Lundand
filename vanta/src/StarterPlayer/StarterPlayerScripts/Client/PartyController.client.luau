--!strict
-- Party interface (L-42). A compact panel with names and health appears only while you're in a party and
-- disappears when you leave. The party board opens only through the Party Clerk at the Adventurers'
-- Guild. Invitations show a small prompt. Every request is checked on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Ui = require(ReplicatedStorage:WaitForChild("Shared").Presentation.Ui)
local STEEL = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(213, 220, 230)), ColorSequenceKeypoint.new(0.35, Color3.fromRGB(140, 150, 167)), ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 48, 59)) })
local CRIMSON = ColorSequence.new(Color3.fromRGB(226, 98, 120), Color3.fromRGB(120, 16, 40))

-- UI v2 look: dark gradient panels with a thin line, Jura labels, the UI kit's buttons.
local function frame(parent: Instance, name: string): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.BackgroundColor3 = Ui.colors.navy
	item.BackgroundTransparency = 0.08
	item.BorderSizePixel = 0
	Ui.shade(item, 0.6)
	Ui.stroke(item, Ui.colors.line, 0.35)
	Ui.corner(item, 4)
	item.Parent = parent
	return item
end

local function text(parent: Instance, value: string, size: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.FontFace = if size >= 18 then Ui.fonts.title else Ui.fonts.labelBold
	item.TextSize = size
	item.TextColor3 = Ui.colors.text
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.RichText = true
	item.Text = value
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string, onClick: () -> ()): TextButton
	local item = Ui.button(parent, value, onClick)
	item.Size = UDim2.new(1, 0, 0, 28)
	return item
end

local function list(parent: Instance)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
end

local function clear(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function request(action: string, args: any?)
	remotes.PartyRequest:FireServer(action, args or {})
end

local gui = Instance.new("ScreenGui")
gui.Name = "Party"
gui.ResetOnSpawn = false

-- Compact party panel, top left, only while in a party.
local panel = frame(gui, "Panel")
panel.Position = UDim2.new(0, 16, 0, 16)
panel.Size = UDim2.new(0, 220, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Visible = false
list(panel)
do
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel
end

local function renderParty(state: any)
	clear(panel)
	if state == nil then
		panel.Visible = false
		return
	end
	panel.Visible = true
	for position, member in ipairs(state.members) do
		local row = Instance.new("Frame")
		row.Name = "Member"
		row.BackgroundTransparency = 1
		row.LayoutOrder = position
		row.Size = UDim2.new(1, 0, 0, 34)
		row.Parent = panel
		local name = text(row, (if member.leader then string.format("<font color='%s'>◆</font> ", Ui.hex.gold) else "") .. member.name, 13)
		name.Size = UDim2.new(1, 0, 0, 16)
		-- steel-framed crimson bar, like the HUD and the nameplates
		local back = Instance.new("Frame")
		back.Name = "HealthBack"
		back.BorderSizePixel = 0
		back.BackgroundColor3 = Color3.new(1, 1, 1)
		back.Position = UDim2.new(0, 0, 0, 20)
		back.Size = UDim2.new(1, 0, 0, 10)
		local steel = Instance.new("UIGradient")
		steel.Color = STEEL
		steel.Rotation = 90
		steel.Parent = back
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(17, 20, 26)
		edge.Thickness = 1.5
		edge.Parent = back
		back.Parent = row
		local recess = Instance.new("Frame")
		recess.BorderSizePixel = 0
		recess.BackgroundColor3 = Color3.fromRGB(11, 14, 20)
		recess.Position = UDim2.fromOffset(2, 2)
		recess.Size = UDim2.new(1, -4, 1, -4)
		recess.ClipsDescendants = true
		recess.Parent = back
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		local crimson = Instance.new("UIGradient")
		crimson.Color = CRIMSON
		crimson.Rotation = 90
		crimson.Parent = fill
		fill.Parent = recess
		local fraction = 0
		if member.maxHealth > 0 then
			fraction = math.clamp(member.health / member.maxHealth, 0, 1)
		end
		fill.Size = UDim2.new(fraction, 0, 1, 0)
	end
	local leave = button(panel, "Leave party", function()
		request("Leave")
	end)
	leave.LayoutOrder = 100
end

-- Party board, opened only at the Adventurers' Guild: a real window (UI v2), so the mouse is free while it is open
-- and the HUD steps aside.
local _, boardBody = Ui.window(gui, "PartyBoard", "Party board", 520, 480)
local boardData: any = nil

Ui.onRefresh("PartyBoard", function()
	Ui.clear(boardBody)
	local data = boardData
	if data == nil then
		return
	end
	local recruiting = Ui.section(boardBody, "Recruiting")
	if #data.parties == 0 then
		Ui.text(recruiting, "No parties are recruiting right now.", 14, Ui.colors.muted)
	end
	for _, party in ipairs(data.parties) do
		local row = Ui.row(recruiting)
		local label = Ui.text(row, string.format("<b>%s's party</b>   <font color='%s'>%s  ·  %d / %d</font>", tostring(party.leaderName), Ui.hex.muted, tostring(party.goal), party.size, party.maxSize), 14)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(0, 330, 0, 30)
		local partyId = party.id
		Ui.primary(Ui.button(row, "Join", function()
			request("Join", { partyId = partyId })
			Ui.close()
		end, 90))
	end
	local start = Ui.section(boardBody, "Start a party")
	Ui.text(start, "Your party is listed here for others to join.", 13, Ui.colors.muted)
	local goals = Ui.row(start)
	for _, goal in ipairs(data.goals) do
		Ui.button(goals, goal, function()
			request("Create", { goal = goal, listed = true })
			Ui.close()
		end, 104)
	end
end)

local function renderBoard(data: any)
	boardData = data
	Ui.open("PartyBoard")
end

-- Invitation: a small window, closing by itself after 30 seconds.
local _, inviteBody = Ui.window(gui, "PartyInvite", "Party invitation", 420, 230)
local inviteData: any = nil
local inviteToken = 0

Ui.onRefresh("PartyInvite", function()
	Ui.clear(inviteBody)
	local data = inviteData
	if data == nil then
		return
	end
	Ui.text(inviteBody, string.format("<b>%s</b> invited you to a party.", tostring(data.from)), 16)
	local row = Ui.row(inviteBody)
	local partyId = data.partyId
	Ui.primary(Ui.button(row, "Accept", function()
		request("Accept", { partyId = partyId })
		Ui.close()
	end, 130))
	Ui.button(row, "Decline", function()
		Ui.close()
	end, 110)
end)

local function renderInvite(data: any)
	inviteData = data
	inviteToken += 1
	local token = inviteToken
	Ui.open("PartyInvite")
	task.delay(30, function()
		if token == inviteToken and Ui.isOpen ~= nil and Ui.isOpen("PartyInvite") then
			Ui.close()
		end
	end)
end

remotes.PartyState.OnClientEvent:Connect(renderParty)
remotes.OpenInterface.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "PartyBoard" then
		renderBoard(data)
	elseif kind == "PartyInvite" then
		renderInvite(data)
	end
end)

gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
