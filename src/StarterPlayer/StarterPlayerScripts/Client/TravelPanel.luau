--[[
	TravelPanel — teleport home or to any zone you've reached (never while carrying a Core),
	and enter the Endless Rift once the Void is unlocked.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local TravelPanel = {}

local player = Players.LocalPlayer
local built = false
local warning: TextLabel
local list: ScrollingFrame
local closer: (() -> ())? = nil

function TravelPanel.SetCloser(fn: () -> ())
	closer = fn
end

local function go(zone: number)
	local result = State.Request("travel", { zone = zone })
	if result.ok and closer then
		closer()
	end
end

function TravelPanel.Build(content: Frame)
	warning = UI.Chip(content, "", UI.Colors.CardHi, { Size = UDim2.new(1, 0, 0, 36), Font = UI.Fonts.Bold, MaxSize = 17, Radius = 12, Name = "Info" })
	list = UI.Scroll(content, { Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46) })
	built = true
end

local function goButton(row: Frame, text: string, color: Color3, width: number, x: number, onClick: () -> ()): TextButton
	return UI.Button(row, text, color, onClick, { Size = UDim2.fromOffset(width, 50), Position = UDim2.new(1, x, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 20 })
end

function TravelPanel.Refresh(data: any)
	if not built or not data then
		return
	end
	local carrying = player:GetAttribute("CarryTitle") ~= nil
	warning.Text = carrying and "📦 You're carrying a Core — no teleporting! Walk it home first." or "Teleport to your base or any zone you've already reached."
	warning.TextColor3 = carrying and Color3.new(1, 1, 1) or UI.Colors.Muted
	warning.BackgroundColor3 = carrying and UI.Colors.Bad or UI.Colors.Card
	UI.Clear(list)

	local home = UI.Card(list, { Size = UDim2.new(1, 0, 0, 64), Tint = UI.Colors.Blue, TintAmount = 0.25, Accent = UI.Colors.Blue, AccentT = 0.2, Order = 0, Name = "Home" })
	UI.Badge(home, "🏠", UI.Colors.Blue, 46, { Position = UDim2.new(0, 10, 0.5, 0), Anchor = Vector2.new(0, 0.5) })
	UI.Text(home, "YOUR BASE", { Size = UDim2.new(1, -270, 0, 30), Position = UDim2.fromOffset(68, 6), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 23, Outline = 2 })
	UI.Text(home, "Incubators, storage, upgrades and your trophies", { Size = UDim2.new(1, -270, 0, 18), Position = UDim2.fromOffset(68, 38), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 14 })
	local homeButton = goButton(home, "GO HOME", UI.Colors.Blue, 170, -182, function()
		go(0)
	end)
	UI.SetEnabled(homeButton, not carrying)

	for i, zone in Config.Zones do
		local unlocked = i <= data.zones
		local row = UI.Card(list, { Size = UDim2.new(1, 0, 0, 64), Color = unlocked and UI.Colors.Card or Color3.fromRGB(26, 28, 62), Tint = unlocked and zone.coreColor or nil, TintAmount = 0.12, Order = i, Name = "Zone" })
		local number = UI.Badge(row, tostring(i), unlocked and zone.coreColor or UI.Colors.Disabled, 46, { Position = UDim2.new(0, 10, 0.5, 0), Anchor = Vector2.new(0, 0.5), IconOutline = 2 })
		number.Name = "Number"
		UI.Text(row, string.upper(zone.name), { Size = UDim2.new(1, -400, 0, 30), Position = UDim2.fromOffset(68, 6), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, Color = unlocked and UI.Colors.Text or UI.Colors.Muted, MaxSize = 23, Outline = 2 })
		if zone.pvp then
			UI.Chip(row, "⚠ PVP", UI.Colors.Bad, { Size = UDim2.fromOffset(80, 24), Position = UDim2.new(1, -300, 0, 9), MaxSize = 13 })
		end
		local info = "Recommended ⚡" .. Util.Abbrev(zone.rec) .. "   •   " .. zone.core
		if i > 1 then
			info = "Needs ⚡" .. Util.Abbrev(Items.Required(i)) .. "   •   " .. info
		end
		UI.Text(row, info, { Size = UDim2.new(1, -240, 0, 18), Position = UDim2.fromOffset(68, 38), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 14 })
		if unlocked then
			local button = goButton(row, "GO", UI.Colors.Good, 130, -142, function()
				go(i)
			end)
			UI.SetEnabled(button, not carrying, UI.Colors.Good)
		else
			UI.Chip(row, "🔒 Walk there", Color3.fromRGB(40, 42, 80), { Size = UDim2.fromOffset(150, 34), Position = UDim2.new(1, -162, 0.5, 0), Anchor = Vector2.new(0, 0.5), TextColor = UI.Colors.Muted, MaxSize = 15 })
		end
	end

	local riftUnlocked = data.zones >= #Config.Zones
	local riftColor = Config.Rift.CoreColor
	local rift = UI.Panel(list, { Size = UDim2.new(1, 0, 0, 78), Top = Color3.fromRGB(24, 70, 130), Bottom = Color3.fromRGB(46, 20, 100), Border = riftColor, BorderThickness = 2.5, Radius = 16, Order = 100, Name = "Rift", GlossHeight = 20 })
	UI.Badge(rift, "∞", riftColor, 52, { Position = UDim2.new(0, 10, 0.5, 0), Anchor = Vector2.new(0, 0.5), IconOutline = 2 })
	UI.Text(rift, "ENDLESS RIFT", { Size = UDim2.new(1, -440, 0, 32), Position = UDim2.fromOffset(74, 8), Font = UI.Fonts.Display, AlignX = Enum.TextXAlignment.Left, Color = riftColor, MaxSize = 27, Outline = 2.5 })
	local best = math.max(data.rift or 0, Config.Rift.StartZone)
	UI.Text(rift, riftUnlocked and ("Highest reached: Zone " .. (data.rift or 0) .. "   •   Zone " .. best .. " needs ~⚡" .. Util.Abbrev(Items.Rec(best))) or ("Unlock the " .. Config.Zones[#Config.Zones].name .. " to open the Rift"), { Size = UDim2.new(1, -452, 0, 20), Position = UDim2.fromOffset(74, 44), Font = UI.Fonts.Bold, Color = Color3.fromRGB(200, 230, 255), AlignX = Enum.TextXAlignment.Left, MaxSize = 14 })
	if riftUnlocked then
		local cont = goButton(rift, "CONTINUE Z" .. best, UI.Colors.Blue, 180, -364, function()
			local result = State.Request("rift", { restart = false })
			if result.ok and closer then
				closer()
			end
		end)
		local restart = goButton(rift, "FROM ZONE " .. Config.Rift.StartZone, UI.Colors.CardHi, 170, -178, function()
			local result = State.Request("rift", { restart = true })
			if result.ok and closer then
				closer()
			end
		end)
		UI.SetEnabled(cont, not carrying)
		UI.SetEnabled(restart, not carrying, UI.Colors.CardHi)
	else
		UI.Chip(rift, "🔒 LOCKED", Color3.fromRGB(40, 42, 80), { Size = UDim2.fromOffset(140, 34), Position = UDim2.new(1, -152, 0.5, 0), Anchor = Vector2.new(0, 0.5), TextColor = UI.Colors.Muted, MaxSize = 15 })
	end
end

return TravelPanel
