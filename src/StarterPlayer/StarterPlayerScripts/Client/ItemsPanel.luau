--[[
	ItemsPanel — Weapons / Classes / Abilities you own: equip, sell (one item at a time), auto-equip.
	The inventory has a limit (Config.Inventory.Max), so players choose what to sell.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local ItemsPanel = {}

local slot = "w"
local built = false
local equippedCards: { [string]: { name: TextLabel, power: TextLabel } } = {}
local breakdown: TextLabel
local autoButton: TextButton
local list: ScrollingFrame
local capacity: TextLabel
local armedKey: string? = nil
local armedAt = 0

local SLOT_LOOK = {
	w = { "⚔️", Color3.fromRGB(240, 110, 60) },
	c = { "🛡️", Color3.fromRGB(64, 140, 255) },
	a = { "✨", Color3.fromRGB(150, 90, 255) },
}
local SELL_COLOR = Color3.fromRGB(240, 142, 30)

local function row(key: string, count: number, data: any, order: number)
	local def, _, _, _, r = Items.Def(key)
	if not def then
		return
	end
	local equipped = data.eq[slot] == key
	local color = Items.RarityColor(r)
	local frame = UI.Card(list, {
		Size = UDim2.new(1, 0, 0, 68),
		Order = order,
		Tint = equipped and UI.Colors.Gold or color,
		TintAmount = equipped and 0.12 or 0.06,
		Accent = equipped and UI.Colors.Gold or nil,
		AccentT = 0,
		AccentThickness = equipped and 3 or 2,
		Name = equipped and "Equipped" or "Item",
	})
	UI.Frame(frame, { Size = UDim2.new(0, 8, 1, -16), Position = UDim2.fromOffset(9, 8), Color = color, Radius = 4, Name = "Rarity" })
	local name = UI.Text(frame, Items.FullName(key) .. (count > 1 and ("  ×" .. count) or ""), { Size = UDim2.new(1, -426, 0, 28), Position = UDim2.fromOffset(26, 7), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 21, Outline = 2 })
	UI.StyleRarity(name, r)
	local lines = Items.Describe(key)
	UI.Text(frame, table.concat(lines, "   •   "), { Size = UDim2.new(1, -426, 0, 20), Position = UDim2.fromOffset(26, 38), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 14 })
	UI.Chip(frame, "⚡ " .. Util.Abbrev(Items.Power(key)), Color3.fromRGB(120, 80, 10), { Size = UDim2.fromOffset(112, 32), Position = UDim2.new(1, -400, 0.5, 0), Anchor = Vector2.new(0, 0.5), TextColor = UI.Colors.GoldLight, MaxSize = 17, Transparency = 0.2 })
	if equipped then
		UI.Chip(frame, "✓ EQUIPPED", UI.Colors.Good, { Size = UDim2.fromOffset(128, 34), Position = UDim2.new(1, -278, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 16, Font = UI.Fonts.Title })
	else
		UI.Button(frame, "EQUIP", UI.Colors.Good, function()
			State.Request("equip", { key = key })
		end, { Size = UDim2.fromOffset(124, 50), Position = UDim2.new(1, -278, 0.5, 0), Anchor = Vector2.new(0, 0.5) })
	end
	local value = Items.SellValue(key)
	if value > 0 and (not equipped or count > 1) then
		local armed = armedKey == key and os.clock() - armedAt < 3
		local button
		button = UI.Button(frame, armed and ("SURE? 💰" .. Util.Abbrev(value)) or ("SELL 💰" .. Util.Abbrev(value)), armed and UI.Colors.Bad or SELL_COLOR, function()
			local needsConfirm = r >= Config.Inventory.ConfirmRarity
			if needsConfirm and not (armedKey == key and os.clock() - armedAt < 3) then
				armedKey = key
				armedAt = os.clock()
				button.Text = "SURE? 💰" .. Util.Abbrev(value)
				button.BackgroundColor3 = UI.Colors.Bad
				task.delay(3.05, function()
					if armedKey == key and os.clock() - armedAt >= 3 and button.Parent then
						armedKey = nil
						button.Text = "SELL 💰" .. Util.Abbrev(value)
						button.BackgroundColor3 = SELL_COLOR
					end
				end)
				return
			end
			armedKey = nil
			State.Request("sell", { key = key, count = 1 })
		end, { Size = UDim2.fromOffset(136, 50), Position = UDim2.new(1, -142, 0.5, 0), Anchor = Vector2.new(0, 0.5), MaxSize = 17 })
	end
end

function ItemsPanel.Build(content: Frame)
	local top = UI.Frame(content, { Size = UDim2.new(1, 0, 0, 90), Transparency = 1, Radius = false, Name = "Equipped" })
	UI.List(top, 12, true)
	for i, s in Items.Slots do
		local look = SLOT_LOOK[s]
		local card = UI.Card(top, { Size = UDim2.new(1 / 3, -8, 1, 0), Order = i, Tint = look[2], TintAmount = 0.12 })
		UI.Badge(card, look[1], look[2], 50, { Position = UDim2.new(0, 10, 0.5, 0), Anchor = Vector2.new(0, 0.5) })
		UI.Text(card, string.upper(Items.SlotNames[s]), { Size = UDim2.new(1, -80, 0, 16), Position = UDim2.fromOffset(70, 9), Font = UI.Fonts.Black, Color = UI.Colors.Muted, AlignX = Enum.TextXAlignment.Left, MaxSize = 13 })
		local name = UI.Text(card, "", { Size = UDim2.new(1, -80, 0, 30), Position = UDim2.fromOffset(70, 26), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, MaxSize = 20, Outline = 2 })
		local power = UI.Text(card, "", { Size = UDim2.new(1, -80, 0, 22), Position = UDim2.fromOffset(70, 58), Font = UI.Fonts.Black, Color = UI.Colors.Gold, AlignX = Enum.TextXAlignment.Left, MaxSize = 17, Outline = 1.5 })
		equippedCards[s] = { name = name, power = power }
	end
	breakdown = UI.Text(content, "", { Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 152), Font = UI.Fonts.Bold, AlignX = Enum.TextXAlignment.Left, Rich = true, MaxSize = 17, Outline = 1.5 })
	capacity = UI.Chip(content, "", UI.Colors.CardHi, { Size = UDim2.fromOffset(120, 34), Position = UDim2.new(1, -334, 0, 104), MaxSize = 18, Font = UI.Fonts.Title })
	autoButton = UI.Button(content, "AUTO-EQUIP: ON", UI.Colors.CardHi, function()
		local data = State.Data
		if data then
			State.Request("settings", { autoEquip = data.settings.autoEquip == false })
		end
	end, { Size = UDim2.fromOffset(204, 44), Position = UDim2.new(1, -204, 0, 99), MaxSize = 17 })
	list = UI.Scroll(content, { Size = UDim2.new(1, 0, 1, -186), Position = UDim2.fromOffset(0, 186) })

	local tabHolder = UI.Frame(content, { Size = UDim2.new(1, -350, 0, 44), Position = UDim2.fromOffset(0, 99), Transparency = 1, Radius = false, Name = "TabHolder" })
	local select = UI.Tabs(tabHolder, {
		{ id = "w", label = "⚔️ WEAPONS", width = 160 },
		{ id = "c", label = "🛡️ CLASSES", width = 150 },
		{ id = "a", label = "✨ ABILITIES", width = 160 },
	}, function(id)
		slot = id
		if State.Data then
			ItemsPanel.Refresh(State.Data)
		end
	end)
	built = true
	select(slot)
end

function ItemsPanel.Refresh(data: any)
	if not built or not data then
		return
	end
	for s, card in equippedCards do
		local key = data.eq[s]
		card.name.Text = Items.FullName(key)
		UI.StyleRarity(card.name, Items.Rarity(key))
		card.power.Text = "⚡ " .. Util.Abbrev(Items.Power(key))
	end
	breakdown.Text = string.format(
		"Items %s  ×  Training x%.2f  =  %s",
		Util.Abbrev(data.itemPower or 0),
		data.trainMult or 1,
		UI.Span("⚡ " .. Util.Abbrev(data.power or 0) .. " POWER", UI.Colors.Gold)
	)
	local auto = data.settings.autoEquip ~= false
	autoButton.Text = "AUTO-EQUIP: " .. (auto and "ON" or "OFF")
	autoButton.BackgroundColor3 = auto and Color3.fromRGB(56, 120, 220) or UI.Colors.CardHi
	local held, max = data.invCount or 0, data.invMax or Config.Inventory.Max
	capacity.Text = "🎒 " .. held .. " / " .. max .. (held >= max and " FULL" or "")
	capacity.BackgroundColor3 = held >= max and UI.Colors.Bad or (held >= max * 0.8 and Color3.fromRGB(220, 120, 30) or UI.Colors.CardHi)

	UI.Clear(list)
	local keys = {}
	for key, count in data.inv do
		if count > 0 and Items.Slot(key) == slot then
			table.insert(keys, key)
		end
	end
	Items.SortKeys(keys)
	for i, key in keys do
		row(key, data.inv[key], data, i)
	end
	if #keys == 0 then
		local empty = UI.Card(list, { Size = UDim2.new(1, 0, 0, 80), Order = 1, Name = "Empty" })
		UI.Text(empty, "Nothing here yet — open Cores to find new gear!", { Size = UDim2.new(1, -40, 1, -20), Position = UDim2.fromOffset(20, 10), Font = UI.Fonts.Bold, Color = UI.Colors.Muted, MaxSize = 18 })
	end
end

return ItemsPanel
