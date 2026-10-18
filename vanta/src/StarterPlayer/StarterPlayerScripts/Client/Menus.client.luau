--!strict
-- Character menus (L-42): Character (C), Inventory (I) and Journal (J), each opened only on request. The
-- profile previews stat upgrades (current value, proposed value, points used) before anything is confirmed.
-- Hides Roblox's default player list, backpack and health bar, which this game replaces or doesn't use.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local Ui = require(Shared.Presentation.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")

for _, coreGui in ipairs({ Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGui, false)
	end)
end

local snapshot: any = {}
local gui = Ui.screen("Menus")

local STATS = {
	{ id = "maxHealth", name = "Max health", percent = false },
	{ id = "physicalDamage", name = "Physical damage", percent = true },
	{ id = "attackSpeed", name = "Attack speed", percent = true },
	{ id = "maxStamina", name = "Max stamina", percent = false },
	{ id = "staminaRegen", name = "Stamina regeneration", percent = true },
	{ id = "magicPower", name = "Magic power", percent = true },
}
local SLOTS = { "MainHand", "OffHand", "Head", "Chest", "Hands", "Legs", "Feet", "Back" }
local SLOT_NAMES = { MainHand = "Main hand", OffHand = "Off hand", Head = "Head", Chest = "Chest", Hands = "Hands", Legs = "Legs", Feet = "Feet", Back = "Back" }

local function format(stat: any, value: number): string
	if stat.percent then
		return string.format("%d%%", math.floor(value * 100 + 0.5))
	end
	return tostring(math.floor(value + 0.5))
end

local function effectNames(statId: string): string
	local names = {}
	for effect in pairs(Content.stats.effectsPerPoint[statId] or {}) do
		for _, stat in ipairs(STATS) do
			if stat.id == effect then
				table.insert(names, stat.name)
			end
		end
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- Character (UI v2: name and level ring, attributes with -/+ and Confirm, derived stats with preview) ----------
local _, profileBody = Ui.window(gui, "Profile", "Character", 640, 720)
local pending: {[string]: number} = {}

local function pendingTotal(): number
	local total = 0
	for _, points in pairs(pending) do
		total += points
	end
	return total
end

local function plabel(parent: Instance, text: string, font: Font, size: number, color: Color3, props: any?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in pairs(props or {}) do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local renderProfile: () -> ()
renderProfile = function()
	Ui.clear(profileBody)
	local data = snapshot.Progression
	if data == nil then
		Ui.text(profileBody, "Loading...", 15, Ui.colors.muted)
		return
	end
	local C, F = Ui.colors, Ui.fonts
	local classDef = data.classId and Content.classes[data.classId]
	local canvas = Instance.new("Frame")
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.new(1, 0, 0, 620)
	canvas.Parent = profileBody

	-- header: name, class with rarity pips, level ring, experience
	plabel(canvas, string.upper(Players.LocalPlayer.DisplayName), F.title, 28, C.text, { Position = UDim2.new(0, 4, 0, 0), Size = UDim2.new(1, -110, 0, 36) })
	local tiers = { Common = 1, Rare = 2, Unique = 3, Epic = 4, Legendary = 5 }
	local classLine = if classDef then string.format("%s   <font color='%s'>%s</font>", classDef.displayName, Ui.hex.muted, string.rep("◆", tiers[classDef.rarity] or 1) .. "  " .. tostring(classDef.rarity)) else "No class yet"
	plabel(canvas, classLine, F.bodyBold, 16, C.text, { Position = UDim2.new(0, 4, 0, 40), Size = UDim2.new(1, -110, 0, 20) })
	local ring = Instance.new("Frame")
	ring.BackgroundColor3 = C.charcoal
	ring.Position = UDim2.new(1, -84, 0, 0)
	ring.Size = UDim2.new(0, 76, 0, 76)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = ring
	local ringStroke = Ui.stroke(ring, C.gold, 0.1)
	ringStroke.Thickness = 2
	plabel(ring, tostring(data.level), F.title, 28, C.gold, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 8), TextXAlignment = Enum.TextXAlignment.Center })
	plabel(ring, "LEVEL", F.labelBold, 9, C.muted, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center })
	ring.Parent = canvas
	local xpBar = Ui.bar(canvas, if data.xpNeeded > 0 then data.xpInto / data.xpNeeded else 1, C.xp)
	xpBar.Position = UDim2.new(0, 4, 0, 90)
	xpBar.Size = UDim2.new(1, -8, 0, 8)
	plabel(canvas, string.format("%d / %d EXP", data.xpInto, data.xpNeeded), F.label, 11, C.muted, { Position = UDim2.new(0, 4, 0, 102), Size = UDim2.new(0.5, 0, 0, 14) })
	local switch = Ui.button(canvas, "Characters", function()
		remotes.CharacterRequest:FireServer("List")
		Ui.open("Characters")
	end, 120)
	switch.Position = UDim2.new(1, -124, 0, 102)
	switch.Size = UDim2.new(0, 120, 0, 26)

	-- attributes
	local spent = pendingTotal()
	local y = 144
	plabel(canvas, "ATTRIBUTES", F.labelBold, 12, C.gold, { Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(0, 200, 0, 14) })
	y += 22
	for index, statId in ipairs(Content.stats.order) do
		local rowFrame = Instance.new("Frame")
		-- alternate rows: every other row clearly darker
		rowFrame.BackgroundColor3 = if index % 2 == 1 then C.charcoal else C.raised
		rowFrame.BackgroundTransparency = if index % 2 == 1 then 0.15 else 0.55
		rowFrame.Position = UDim2.new(0, 0, 0, y)
		rowFrame.Size = UDim2.new(1, 0, 0, 50)
		Ui.corner(rowFrame, 3)
		rowFrame.Parent = canvas
		plabel(rowFrame, string.upper(statId), F.labelBold, 14, C.text, { Position = UDim2.new(0, 14, 0, 7), Size = UDim2.new(0, 300, 0, 18) })
		plabel(rowFrame, effectNames(statId), F.body, 12, C.muted, { Position = UDim2.new(0, 14, 0, 27), Size = UDim2.new(0, 320, 0, 16) })
		local extra = pending[statId] or 0
		plabel(rowFrame, tostring(data.allocated[statId] or 0) .. (if extra > 0 then string.format("  <font color='%s'>+%d</font>", Ui.hex.green, extra) else ""), F.labelBold, 20, C.text, { Position = UDim2.new(1, -190, 0, 13), Size = UDim2.new(0, 90, 0, 24) })
		local minus = Ui.button(rowFrame, "−", function()
			if (pending[statId] or 0) > 0 then
				pending[statId] -= 1
				renderProfile()
			end
		end, 30)
		minus.Position = UDim2.new(1, -86, 0, 10)
		minus.Size = UDim2.new(0, 30, 0, 30)
		local plus = Ui.button(rowFrame, "+", function()
			if pendingTotal() < data.availablePoints then
				pending[statId] = (pending[statId] or 0) + 1
				renderProfile()
			end
		end, 30)
		plus.Position = UDim2.new(1, -46, 0, 10)
		plus.Size = UDim2.new(0, 30, 0, 30)
		plus.TextColor3 = C.gold
		y += 56
	end
	plabel(canvas, string.format("Points available   <font color='%s'>%d</font>", Ui.hex.gold, data.availablePoints - spent), F.bodyBold, 15, C.muted, { Position = UDim2.new(0, 4, 0, y + 10), Size = UDim2.new(0, 260, 0, 22) })
	if spent > 0 then
		local reset = Ui.button(canvas, "Reset", function()
			pending = {}
			renderProfile()
		end, 120)
		reset.Position = UDim2.new(1, -264, 0, y + 6)
		local confirm = Ui.button(canvas, "Confirm", function()
			remotes.AllocateStats:FireServer(pending)
			pending = {}
		end, 130)
		confirm.Position = UDim2.new(1, -134, 0, y + 6)
		Ui.primary(confirm)
	end
	y += 52

	-- derived stats, with the preview of pending points
	local proposed = table.clone(data.allocated)
	for statId, points in pairs(pending) do
		proposed[statId] = (proposed[statId] or 0) + points
	end
	local previewStats = CharacterProgression.derivedStats({ allocated = proposed } :: any, Content.stats)
	plabel(canvas, "DERIVED", F.labelBold, 12, C.gold, { Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(0, 200, 0, 14) })
	y += 24
	for index, stat in ipairs(STATS) do
		local x = if index % 2 == 1 then 4 else 312
		local before, later = data.derived[stat.id] or 0, previewStats[stat.id] or 0
		local value = format(stat, before)
		if spent > 0 and math.abs(later - before) > 0.000001 then
			value ..= string.format("  <font color='%s'>→ %s</font>", Ui.hex.green, format(stat, later))
		end
		plabel(canvas, stat.name, F.body, 14, C.muted, { Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, 160, 0, 18) })
		plabel(canvas, value, F.labelBold, 14, C.text, { Position = UDim2.new(0, x + 160, 0, y), Size = UDim2.new(0, 140, 0, 18) })
		if index % 2 == 0 then
			y += 30
		end
	end
	y += 16

	-- mastery and professions, compact
	if data.disciplines ~= nil and next(data.disciplines) ~= nil then
		plabel(canvas, "MASTERY", F.labelBold, 12, C.gold, { Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(0, 200, 0, 14) })
		y += 22
		for _, discipline in pairs(data.disciplines) do
			plabel(canvas, string.format("%s   <font color='%s'>rank %d / %d</font>", discipline.name, Ui.hex.muted, discipline.rank, discipline.maxRank), F.body, 14, C.text, { Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(1, -8, 0, 18) })
			local bar = Ui.bar(canvas, if discipline.xpNeeded > 0 then discipline.xpInto / discipline.xpNeeded else 1, C.violet)
			bar.Position = UDim2.new(0, 4, 0, y + 22)
			bar.Size = UDim2.new(1, -8, 0, 6)
			y += 38
		end
	end
	if data.professions ~= nil and next(data.professions) ~= nil then
		plabel(canvas, "PROFESSIONS", F.labelBold, 12, C.gold, { Position = UDim2.new(0, 4, 0, y), Size = UDim2.new(0, 200, 0, 14) })
		y += 22
		local index = 0
		for _, profession in pairs(data.professions) do
			local x = if index % 2 == 0 then 4 else 312
			plabel(canvas, string.format("%s   <font color='%s'>level %d</font>", profession.name, Ui.hex.gold, profession.level), F.body, 14, C.text, { Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, 300, 0, 18) })
			index += 1
			if index % 2 == 0 then
				y += 26
			end
		end
		y += 26
	end
	canvas.Size = UDim2.new(1, 0, 0, y + 10)
end
Ui.onRefresh("Profile", renderProfile)
Ui.onClose("Profile", function()
	pending = {}
end)

-- Inventory (UI v2: equipped column, bag grid, inspection with comparison) ----------------------------------------
local inventoryWindow, inventoryBody = Ui.window(gui, "Inventory", "Inventory", 1120, 700)
local ItemStats = require(Shared.Domain.ItemStats)
local ItemPreview = require(Shared.Presentation.ItemPreview)
local selected: any = nil -- { place = "bag" | "equipped", uid?, key?, slot? }
local C, F = Ui.colors, Ui.fonts
local TILE, GAP = 60, 8

local function label(parent: Instance, text: string, font: Font, size: number, color: Color3, props: any?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = true
	for key, value in pairs(props or {}) do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

local RARITY_TIER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- A slot tile: rarity frame treatment (never colour alone), pips, the item's 3D model (or its initial when it has none),
-- count, equipped badge, selection.
local function tile(parent: Instance, entry: any?, x: number, y: number, isSelected: boolean, equipped: boolean, onClick: (() -> ())?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.Position = UDim2.new(0, x, 0, y)
	button.Size = UDim2.new(0, TILE, 0, TILE)
	button.BackgroundColor3 = if entry then C.raised else C.charcoal
	button.BackgroundTransparency = if entry then 0.05 else 0.4
	Ui.corner(button, 3)
	local color = entry and (Ui.rarity[entry.rarity] or C.silver) or C.line
	local tier = entry and (RARITY_TIER[entry.rarity] or 1) or 0
	local stroke = Ui.stroke(button, if isSelected then C.accent elseif entry then color else C.line, if isSelected then 0 elseif entry then (if tier == 1 then 0.45 else 0.05) else 0.7)
	stroke.Thickness = if isSelected or tier == 5 then 2 else 1
	if entry then
		Ui.shade(button, 0.6)
		if tier >= 3 then
			local inner = Instance.new("Frame")
			inner.BackgroundTransparency = 1
			inner.Position = UDim2.new(0, 3, 0, 3)
			inner.Size = UDim2.new(1, -6, 1, -6)
			Ui.stroke(inner, color, 0.5)
			Ui.corner(inner, 2)
			inner.Parent = button
		end
		if tier >= 4 then
			for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
				local gem = Instance.new("Frame")
				gem.BorderSizePixel = 0
				gem.BackgroundColor3 = color
				gem.AnchorPoint = Vector2.new(0.5, 0.5)
				gem.Rotation = 45
				gem.Size = UDim2.new(0, 5, 0, 5)
				gem.Position = UDim2.new(corner[1], 0, corner[2], 0)
				gem.Parent = button
			end
		end
		if not ItemPreview.has(entry.itemId) then
			label(button, string.upper(string.sub(entry.name, 1, 1)), F.title, 26, C.text, { Size = UDim2.new(1, 0, 1, -8), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.15 })
		end
		label(button, string.rep("◆", tier), F.labelBold, 8, color, { Position = UDim2.new(0, 5, 1, -13), Size = UDim2.new(1, -10, 0, 10) })
		if (entry.count or 1) > 1 then
			label(button, tostring(entry.count), F.labelBold, 12, C.text, { Position = UDim2.new(0, 0, 1, -16), Size = UDim2.new(1, -5, 0, 14), TextXAlignment = Enum.TextXAlignment.Right })
		end
		if equipped then
			local badge = Instance.new("Frame")
			badge.BorderSizePixel = 0
			badge.BackgroundColor3 = C.gold
			badge.Position = UDim2.new(1, -16, 0, 4)
			badge.Size = UDim2.new(0, 12, 0, 12)
			Ui.corner(badge, 2)
			label(badge, "E", F.labelBold, 9, C.charcoal, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
			badge.Parent = button
		end
	end
	if onClick then
		button.MouseEnter:Connect(function()
			if not isSelected then
				stroke.Color = C.accent
			end
		end)
		button.MouseLeave:Connect(function()
			if not isSelected then
				stroke.Color = if entry then color else C.line
			end
		end)
		button.Activated:Connect(onClick)
	end
	button.Parent = parent
	if entry and ItemPreview.has(entry.itemId) then
		-- under the pips, count and badge (lower ZIndex), inset so the rarity frame stays clear
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(0, 4, 0, 3)
		holder.Size = UDim2.new(1, -8, 1, -12)
		holder.ZIndex = 0
		holder.Parent = button
		local preview = ItemPreview.view(holder, entry.itemId, { layout = "tile" })
		if preview ~= nil then
			preview.ZIndex = 0
		end
	end
	return button
end

local function sectionLabel(parent: Instance, text: string, x: number, y: number)
	label(parent, text, F.labelBold, 12, C.gold, { Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, 300, 0, 16) })
end

local function statName(stat: string): string
	local names = { attackPower = "Attack power", defense = "Defence" }
	return names[stat] or stat
end

local renderInventory: () -> ()
renderInventory = function()
	Ui.clear(inventoryBody)
	local data = snapshot.Inventory
	if data == nil then
		Ui.text(inventoryBody, "Loading...", 15, C.muted)
		return
	end
	local canvas = Instance.new("Frame")
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.new(1, 0, 0, 600)
	canvas.Parent = inventoryBody
	local equipment = data.equipment or {}

	-- find the selected entry
	local current, currentSlot = nil, nil
	if selected ~= nil then
		if selected.place == "equipped" then
			current, currentSlot = equipment[selected.slot], selected.slot
		else
			for _, entry in ipairs(data.entries) do
				if (selected.uid ~= nil and entry.uid == selected.uid) or (selected.key ~= nil and entry.key == selected.key) then
					current = entry
				end
			end
		end
	end
	if current == nil then
		selected = nil
	end

	-- equipped column
	sectionLabel(canvas, "EQUIPPED", 0, 0)
	for index, slot in ipairs(SLOTS) do
		local x, y = ((index - 1) % 2) * 110, 24 + math.floor((index - 1) / 2) * 98
		local item = equipment[slot]
		local isSelected = selected ~= nil and selected.place == "equipped" and selected.slot == slot
		tile(canvas, item, x, y, isSelected, item ~= nil, if item then function()
			selected = { place = "equipped", slot = slot }
			renderInventory()
		end else nil)
		label(canvas, SLOT_NAMES[slot], F.label, 11, C.muted, { Position = UDim2.new(0, x, 0, y + TILE + 4), Size = UDim2.new(0, 100, 0, 14) })
	end
	local rule = Instance.new("Frame")
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = C.line
	rule.BackgroundTransparency = 0.4
	rule.Position = UDim2.new(0, 236, 0, 0)
	rule.Size = UDim2.new(0, 1, 0, 560)
	rule.Parent = canvas

	-- bag grid
	local gx = 260
	sectionLabel(canvas, "BAG", gx, 0)
	label(canvas, string.format("%d / %d", data.used, data.capacity), F.label, 12, C.muted, { Position = UDim2.new(0, gx + 6 * (TILE + GAP) - 108, 0, 0), Size = UDim2.new(0, 100, 0, 16), TextXAlignment = Enum.TextXAlignment.Right })
	local cells = math.max(36, math.ceil(#data.entries / 6) * 6)
	for index = 1, cells do
		local entry = data.entries[index]
		local x, y = gx + ((index - 1) % 6) * (TILE + GAP), 24 + math.floor((index - 1) / 6) * (TILE + GAP)
		local isSelected = entry ~= nil and selected ~= nil and selected.place == "bag" and ((selected.uid ~= nil and selected.uid == entry.uid) or (selected.key ~= nil and selected.key == entry.key))
		tile(canvas, entry, x, y, isSelected, false, if entry then function()
			selected = { place = "bag", uid = entry.uid, key = entry.key }
			renderInventory()
		end else nil)
	end
	local gridBottom = 24 + math.ceil(cells / 6) * (TILE + GAP)
	label(canvas, string.format("GOLD   <font color='%s'>%d</font>", Ui.hex.gold, data.currencies.Gold or 0), F.labelBold, 14, C.muted, { Position = UDim2.new(0, gx, 0, gridBottom + 6), Size = UDim2.new(0, 300, 0, 18) })
	canvas.Size = UDim2.new(1, 0, 0, math.max(600, gridBottom + 40))

	-- inspection panel
	local px = gx + 6 * (TILE + GAP) + 16
	local panel = Instance.new("Frame")
	panel.BackgroundColor3 = C.charcoal
	panel.BackgroundTransparency = 0.3
	panel.Position = UDim2.new(0, px, 0, 0)
	panel.Size = UDim2.new(1, -px, 0, 560)
	Ui.corner(panel, 4)
	panel.Parent = canvas
	if current == nil then
		Ui.stroke(panel, C.line, 0.6)
		label(panel, "Select an item to inspect it.", F.body, 14, C.muted, { Position = UDim2.new(0, 20, 0, 20), Size = UDim2.new(1, -40, 0, 20) })
		return
	end
	local def = Content.items[current.itemId]
	local color = Ui.rarity[current.rarity] or C.text
	Ui.stroke(panel, color, 0.35)
	local y = 18
	if ItemPreview.has(current.itemId) then
		local stage = Instance.new("Frame")
		stage.BackgroundColor3 = C.charcoal
		stage.BackgroundTransparency = 0.35
		stage.Position = UDim2.new(0, 14, 0, 14)
		stage.Size = UDim2.new(1, -28, 0, 150)
		Ui.corner(stage, 3)
		stage.Parent = panel
		ItemPreview.view(stage, current.itemId, { layout = "panel", motion = true })
		y = 176
	end
	label(panel, string.upper(current.name), F.title, 20, color, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 26), TextWrapped = true })
	y += 32
	local meta = { string.rep("◆", RARITY_TIER[current.rarity] or 1) .. "  " .. tostring(current.rarity or "") }
	if current.quality then
		table.insert(meta, tostring(current.quality))
	end
	if current.itemLevel and def and def.kind == "Equipment" then
		table.insert(meta, "Item level " .. tostring(current.itemLevel))
	end
	label(panel, table.concat(meta, "  ·  "), F.label, 12, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 16) })
	y += 22
	if def and def.equipment then
		local parts = { SLOT_NAMES[def.equipment.slot] or def.equipment.slot }
		if def.equipment.weaponType then
			table.insert(parts, 1, def.equipment.weaponType)
		end
		if def.equipment.armorWeight then
			table.insert(parts, 1, def.equipment.armorWeight .. " armour")
		end
		table.insert(parts, "Requires level " .. tostring(ItemStats.requiredLevel(def, current)))
		label(panel, table.concat(parts, "  ·  "), F.body, 13, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
		y += 28
	elseif def then
		label(panel, tostring(def.kind), F.body, 13, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
		y += 28
	end
	-- stats compared with what is equipped in the same slot
	if current.stats and next(current.stats) ~= nil then
		local worn = def and def.equipment and equipment[def.equipment.slot]
		local comparing = selected.place == "bag" and worn ~= nil and worn.stats ~= nil
		label(panel, if comparing then "COMPARED WITH EQUIPPED" else "STATS", F.labelBold, 11, C.gold, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 14) })
		y += 22
		local better, worse = 0, 0
		for stat, value in pairs(current.stats) do
			label(panel, statName(stat), F.body, 14, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(0, 150, 0, 18) })
			label(panel, tostring(value), F.labelBold, 15, C.text, { Position = UDim2.new(0, 170, 0, y), Size = UDim2.new(0, 70, 0, 18) })
			if comparing then
				local diff = value - (worn.stats[stat] or 0)
				local text = if diff > 0.05 then string.format("▲ +%.1f", diff) elseif diff < -0.05 then string.format("▼ %.1f", diff) else "="
				label(panel, text, F.labelBold, 13, if diff > 0.05 then C.green elseif diff < -0.05 then C.red else C.muted, { Position = UDim2.new(0, 250, 0, y), Size = UDim2.new(0, 90, 0, 18) })
				if diff > 0.05 then better += 1 elseif diff < -0.05 then worse += 1 end
			end
			y += 26
		end
		if comparing and (better > 0 or worse > 0) then
			local verdict = if better > 0 and worse == 0 then "UPGRADE" elseif worse > 0 and better == 0 then "DOWNGRADE" else "MIXED"
			label(panel, verdict, F.labelBold, 12, if verdict == "UPGRADE" then C.green elseif verdict == "DOWNGRADE" then C.red else C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 16) })
			y += 26
		end
	end
	-- weapon progression: how it handles, what it adds, and a named weapon's trait
	if current.handling then
		local h = current.handling
		local subtypeName = string.gsub(tostring(current.subtype), "(%l)(%u)", "%1 %2")
		label(panel, string.format("%s  ·  Speed %d%%  ·  Reach %d%%  ·  Damage %d%%", subtypeName, math.floor(h.speed * 100 + 0.5), math.floor(h.reach * 100 + 0.5), math.floor(h.damage * 100 + 0.5)), F.body, 13, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
		y += 24
	end
	if current.bonuses and next(current.bonuses) ~= nil then
		local names = {}
		for _, stat in ipairs(STATS) do
			names[stat.id] = stat.name
		end
		for stat, value in pairs(current.bonuses) do
			label(panel, string.format("+%s%% %s", tostring(math.floor(value * 1000 + 0.5) / 10), names[stat] or stat), F.labelBold, 13, C.green, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
			y += 20
		end
		y += 4
	end
	if current.trait then
		local trait = label(panel, "<font color='" .. Ui.hex.gold .. "'>TRAIT</font>   " .. current.trait, F.body, 13, C.text, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
		trait.LineHeight = 1.2
		y += 36
	end
	if def and def.description then
		local description = label(panel, def.description, F.body, 14, C.text, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
		description.LineHeight = 1.25
		y += 60
	end
	if current.craftedBy then
		label(panel, string.format("Crafted by  <font color='%s'>%s</font>", Ui.hex.gold, tostring(current.craftedBy)), F.body, 14, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
		y += 28
	elseif current.origin then
		label(panel, "Origin: " .. tostring(current.origin), F.body, 13, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 18) })
		y += 26
	end
	-- actions
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.Position = UDim2.new(0, 20, 1, -54)
	actions.Size = UDim2.new(1, -40, 0, 34)
	Ui.list(actions, 10, true)
	actions.Parent = panel
	if selected.place == "equipped" then
		Ui.button(actions, "Unequip", function()
			remotes.UnequipItem:FireServer(currentSlot)
			selected = nil
		end, 150)
	elseif current.uid ~= nil and def ~= nil and def.kind == "Equipment" then
		local uid = current.uid
		local equipButton = Ui.button(actions, "Equip", function()
			remotes.EquipItem:FireServer(uid)
		end, 150)
		Ui.primary(equipButton)
	end
	-- Class books: reading one replaces your class (Legendary classes come only from these books). It can't be
	-- undone, so the button asks for a second click.
	if current.uid ~= nil and def ~= nil and def.kind == "ClassBook" and def.classBook ~= nil then
		local uid = current.uid
		local target = Content.classes[def.classBook.classId]
		label(panel, "Reading this makes you a " .. (if target then target.displayName else "new class") .. ". Your class and level start over (with a catch-up bonus); your items, gold, home and discoveries stay.", F.body, 13, C.muted, { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
		local armed = false
		local readButton: any = nil
		readButton = Ui.button(actions, "Read", function()
			if not armed then
				armed = true
				if typeof(readButton) == "Instance" and readButton:IsA("TextButton") then
					readButton.Text = "Click again to read"
				end
				return
			end
			remotes.ActivateLegendaryBook:FireServer(uid, string.format("%d-%d", os.time(), math.random(1, 1000000000)))
		end, 180)
	end
end
Ui.onRefresh("Inventory", renderInventory)

-- Journal ---------------------------------------------------------------------------------------------
local _, journalBody = Ui.window(gui, "Journal", "Journal", 600, 620)
local journalTab = "Active"

local function carried(itemId: string): number
	local total = 0
	for _, entry in ipairs((snapshot.Inventory and snapshot.Inventory.entries) or {}) do
		if entry.itemId == itemId then
			total += entry.count
		end
	end
	return total
end

local function objectiveLine(objective: any): string
	local need = objective.count
	local done = math.min(objective.progress or 0, need)
	local target = objective.target
	if objective.kind == "Talk" then
		local npc = Content.npcs[target]
		return string.format("Speak with %s%s", (npc and npc.displayName) or target, done >= need and "  (done)" or "")
	elseif objective.kind == "Kill" then
		local enemy = Content.enemies[target]
		return string.format("Defeat %s  %d / %d", (enemy and enemy.displayName) or target, done, need)
	elseif objective.kind == "Gather" then
		local item = Content.items[target]
		return string.format("Gather %s  %d / %d", (item and item.displayName) or target, done, need)
	elseif objective.kind == "Deliver" then
		local item = Content.items[target]
		return string.format("Bring %s  %d / %d", (item and item.displayName) or target, math.min(carried(target), need), need)
	elseif objective.kind == "Craft" then
		local recipe = Content.recipes[target]
		return string.format("Craft %s  %d / %d", (recipe and recipe.displayName) or target, done, need)
	end
	return tostring(target)
end

local renderJournal: () -> ()
renderJournal = function()
	Ui.clear(journalBody)
	local tabs = Ui.row(journalBody)
	for _, tab in ipairs({ "Active", "Completed", "Story" }) do
		local button = Ui.button(tabs, tab, function()
			journalTab = tab
			renderJournal()
		end, 120)
		if tab == journalTab then
			Ui.markSelected(button)
		end
	end
	local data = snapshot.Journal
	if data == nil then
		Ui.text(journalBody, "Loading...", 15, Ui.colors.muted)
		return
	end
	if journalTab == "Active" then
		if #data.active == 0 then
			Ui.text(journalBody, "No quests right now. The people of Lundand often need help; talk to them.", 14, Ui.colors.muted)
		end
		table.sort(data.active, function(a: any, b: any)
			if a.main ~= b.main then
				return a.main == true
			end
			return a.name < b.name
		end)
		for _, quest in ipairs(data.active) do
			local def = Content.quests[quest.id]
			local section = Ui.section(journalBody, (quest.main and "◆ Main story:  " or "") .. quest.name)
			if def ~= nil then
				Ui.text(section, def.description, 14)
			end
			-- objectives: a green check when done, a dash while open; when all are done, where to report in gold
			local allDone = #quest.objectives > 0
			for _, objective in ipairs(quest.objectives) do
				local done = if objective.kind == "Deliver" then carried(objective.target) >= objective.count else (objective.progress or 0) >= objective.count
				allDone = allDone and done
				Ui.text(section, string.format("<font color='%s'>%s</font>  %s", if done then Ui.hex.green else Ui.hex.muted, if done then "✓" else "–", objectiveLine(objective)), 14, if done then Ui.colors.muted else Ui.colors.text)
			end
			local giver = def and Content.npcs[def.giver]
			if giver ~= nil then
				if allDone then
					Ui.text(section, "Ready: report to " .. giver.displayName, 13, Ui.colors.gold)
				else
					Ui.text(section, "Report to " .. giver.displayName, 13, Ui.colors.muted)
				end
			end
		end
	elseif journalTab == "Completed" then
		if #data.completed == 0 then
			Ui.text(journalBody, "Nothing finished yet.", 14, Ui.colors.muted)
		end
		for _, quest in ipairs(data.completed) do
			Ui.text(journalBody, string.format("<font color='%s'>✓</font>  %s", Ui.hex.green, quest.name), 14, Ui.colors.silver)
		end
	else
		if #data.story == 0 then
			Ui.text(journalBody, "Your story is still unwritten.", 14, Ui.colors.muted)
		end
		for _, entry in ipairs(data.story) do
			local section = Ui.section(journalBody, entry.title)
			Ui.text(section, entry.summary, 14)
		end
	end
end
Ui.onRefresh("Journal", renderJournal)

-- Characters (L-45, L-49) ------------------------------------------------------------------------------
local _, charactersBody = Ui.window(gui, "Characters", "Characters", 560, 560)
local characterState: any = nil
local pendingDelete: any = nil

local function describeWait(seconds: number): string
	if seconds >= 86400 then
		return string.format("%d day(s)", math.ceil(seconds / 86400))
	end
	return string.format("%d hour(s)", math.max(1, math.ceil(seconds / 3600)))
end

local renderCharacters: () -> ()
renderCharacters = function()
	Ui.clear(charactersBody)
	if characterState == nil then
		Ui.text(charactersBody, "Loading...", 15, Ui.colors.muted)
		return
	end
	Ui.text(charactersBody, string.format("Character slots: %d of %d in use", #characterState.characters, characterState.slots), 14, Ui.colors.muted)
	for _, entry in ipairs(characterState.characters) do
		local classDef = entry.classId and Content.classes[entry.classId]
		local section = Ui.section(charactersBody, string.format("%s, level %d%s", (classDef and classDef.displayName) or "No class yet", entry.level, entry.active and "   (playing)" or ""))
		local row = Ui.row(section)
		local characterId = entry.id
		if not entry.active then
			Ui.button(row, "Play", function()
				remotes.CharacterRequest:FireServer("Select", { characterId = characterId })
			end, 100)
		end
		local waitLeft = (entry.deletableAt or 0) - os.time()
		if waitLeft > 0 then
			Ui.text(row, "Can be deleted in " .. describeWait(waitLeft), 13, Ui.colors.muted).Size = UDim2.new(0, 260, 0, 26)
		else
			Ui.button(row, "Delete", function()
				remotes.CharacterRequest:FireServer("RequestDelete", { characterId = characterId })
			end, 100)
		end
		if pendingDelete ~= nil and pendingDelete.characterId == characterId then
			local warning = Ui.section(section, "Delete this character?")
			Ui.text(warning, "This cannot be undone. The character's level, class, items, gold, quests and story are lost for good. Type DELETE to confirm.", 14, Ui.colors.red)
			local box = Instance.new("TextBox")
			box.BackgroundColor3 = Ui.colors.charcoal
			box.TextColor3 = Ui.colors.text
			box.PlaceholderText = "DELETE"
			box.Font = Enum.Font.Gotham
			box.TextSize = 15
			box.Text = ""
			box.ClearTextOnFocus = false
			box.Size = UDim2.new(0, 200, 0, 30)
			box.Parent = warning
			local token = pendingDelete.token
			Ui.button(warning, "Delete forever", function()
				if box.Text == "DELETE" then
					remotes.CharacterRequest:FireServer("ConfirmDelete", { characterId = characterId, token = token })
					pendingDelete = nil
				end
			end, 160)
			Ui.button(warning, "Keep this character", function()
				pendingDelete = nil
				renderCharacters()
			end, 180)
		end
	end
	if #characterState.characters < characterState.slots then
		Ui.button(charactersBody, "Create a new character", function()
			remotes.CharacterRequest:FireServer("Create")
		end, 220)
	end
end
Ui.onRefresh("Characters", renderCharacters)
Ui.onClose("Characters", function()
	pendingDelete = nil
end)

remotes.CharacterState.OnClientEvent:Connect(function(state: any)
	characterState = state
	Ui.refresh("Characters")
end)
remotes.OpenInterface.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "ConfirmDelete" and type(data) == "table" then
		pendingDelete = data
		Ui.refresh("Characters")
	end
end)

-- Keys and data ---------------------------------------------------------------------------------------
local KEYS = { [Enum.KeyCode.C] = "Profile", [Enum.KeyCode.J] = "Journal", [Enum.KeyCode.B] = "Inventory" } -- B as well as I (I has never reached the game in Studio)

local function toggleMenu(name: string)
	if not Ui.isOpen(name) then
		if name == "Journal" then
			remotes.RequestJournal:FireServer()
		else
			remotes.RequestSnapshot:FireServer()
		end
	end
	Ui.toggle(name)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	local name = KEYS[input.KeyCode]
	if not processed and name ~= nil then
		toggleMenu(name)
	end
end)

-- I opens the inventory, like C and J: a direct key listener, so the key works whatever else is bound to I.
-- Roblox's camera also zooms with I; the sink binding below only stops that zoom. Ignored while typing.
ContextActionService:BindActionAtPriority("BlockCameraZoomOnI", function(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 1000, Enum.KeyCode.I)
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.I and UserInputService:GetFocusedTextBox() == nil then
		toggleMenu("Inventory")
	end
end)

remotes.Snapshot.OnClientEvent:Connect(function(section: string, data: any)
	snapshot[section] = data
	if section == "Progression" then
		Ui.refresh("Profile")
	elseif section == "Inventory" then
		Ui.refresh("Inventory")
		Ui.refresh("Profile")
		Ui.refresh("Journal")
	elseif section == "Journal" then
		Ui.refresh("Journal")
	end
end)

-- One quiet reminder of the keys after joining.
task.delay(6, function()
	local hint = Ui.text(gui, "C  Character      B  Bag      J  Journal", 14, Ui.colors.silver)
	hint.AutomaticSize = Enum.AutomaticSize.None
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.new(0, 420, 0, 20)
	task.wait(8)
	hint:Destroy()
end)
