--!strict
-- Combat HUD, ornate style (owner's reference image; Figma "HUD v3 — ornate art"). Brushed-steel frames with a dark
-- outline and highlight, a crimson health bar with pointed steel tips and pale-blue pennants, thin steel bars for
-- stamina (and mana when the class uses it), four gems showing the End Ability meter in quarters, and steel ability
-- slots (the End Ability in gold, glowing when ready). Everything sits at the bottom centre; a matching boss bar
-- appears at the top only near a living boss. Built from Roblox shapes (no image uploads), live data throughout.
-- Steps aside while a window is open. Hidden until a class is assigned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Content)
local Ui = require(Shared.Presentation.Ui)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local C, F = Ui.colors, Ui.fonts

local OUTLINE = Color3.fromRGB(17, 20, 26)
local RECESS_TOP, RECESS_BOTTOM = Color3.fromRGB(35, 42, 54), Color3.fromRGB(11, 14, 20)
local CLOTH = Color3.fromRGB(190, 220, 240)
local STEEL = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(213, 220, 230)), ColorSequenceKeypoint.new(0.3, Color3.fromRGB(140, 150, 167)), ColorSequenceKeypoint.new(0.62, Color3.fromRGB(76, 85, 102)), ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 48, 59)) })
local GOLD = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(251, 230, 166)), ColorSequenceKeypoint.new(0.3, Color3.fromRGB(211, 165, 78)), ColorSequenceKeypoint.new(0.62, Color3.fromRGB(142, 101, 38)), ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 62, 22)) })
local CRIMSON = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 98, 120)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(176, 36, 66)), ColorSequenceKeypoint.new(1, Color3.fromRGB(102, 13, 33)) })
local GEM = ColorSequence.new(Color3.fromRGB(242, 250, 255), Color3.fromRGB(80, 130, 186))

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false

local function frame(parent: Instance, props: any): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	for key, value in pairs(props) do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

local function paint(f: GuiObject, sequence: ColorSequence)
	local gradient = Instance.new("UIGradient")
	gradient.Color = sequence
	gradient.Rotation = 90
	gradient.Parent = f
end

local function outline(f: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or OUTLINE
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return stroke
end

local function round(f: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius >= 1000 then UDim.new(1, 0) else UDim.new(0, radius)
	corner.Parent = f
end

local function label(parent: Instance, text: string, font: Font, size: number, color: Color3, props: any?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	for key, value in pairs(props or {}) do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

-- a diamond: steel setting with a coloured centre
local function diamond(parent: Instance, size: number, centre: ColorSequence?, props: any?): (Frame, Frame)
	local setting = frame(parent, { Size = UDim2.fromOffset(size, size), Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5) })
	for key, value in pairs(props or {}) do
		(setting :: any)[key] = value
	end
	paint(setting, STEEL)
	outline(setting, OUTLINE, 1.2)
	local stone = frame(setting, { Size = UDim2.new(0.5, 0, 0.5, 0), Position = UDim2.new(0.25, 0, 0.25, 0) })
	paint(stone, centre or GEM)
	return setting, stone
end

local function rivet(parent: Instance, x: UDim, y: UDim)
	local r = frame(parent, { Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, y), BackgroundColor3 = Color3.fromRGB(227, 232, 239), ZIndex = 4 })
	round(r, 1000)
	outline(r, OUTLINE, 1)
end

-- An ornate steel bar: frame, dark recess, fill (left to right) and pointed tips; returns the bar, its fill and recess.
local function steelBar(parent: Instance, width: number, height: number, inset: number, fillColors: ColorSequence, tips: boolean, order: number): (Frame, Frame, Frame)
	local holder = frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(width, height), LayoutOrder = order })
	if tips then
		for _, side in ipairs({ 0, 1 }) do
			-- pennant behind the tip
			local cloth = frame(holder, { Size = UDim2.fromOffset(height * 0.55, height * 0.55), Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, if side == 0 then -height * 0.42 else height * 0.42, 0.5, -height * 0.32), BackgroundColor3 = CLOTH, ZIndex = 1 })
			outline(cloth, OUTLINE, 1.2)
			local tip = frame(holder, { Size = UDim2.fromOffset(height * 0.78, height * 0.78), Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, if side == 0 then -height * 0.12 else height * 0.12, 0.5, 0), ZIndex = 2 })
			paint(tip, STEEL)
			outline(tip, OUTLINE, 2)
		end
	end
	local body = frame(holder, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 })
	paint(body, STEEL)
	outline(body, OUTLINE, 2)
	round(body, 2)
	local recess = frame(body, { Size = UDim2.new(1, -2 * inset, 1, -2 * inset), Position = UDim2.fromOffset(inset, inset), ZIndex = 4, ClipsDescendants = true })
	paint(recess, ColorSequence.new(RECESS_TOP, RECESS_BOTTOM))
	outline(recess, Color3.fromRGB(5, 7, 10), 1)
	local fill = frame(recess, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
	paint(fill, fillColors)
	local shine = frame(fill, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.6, ZIndex = 6 })
	local highlight = frame(body, { Size = UDim2.new(1, -6, 0, 1), Position = UDim2.fromOffset(3, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.5, ZIndex = 4 })
	_ = shine
	_ = highlight
	if tips then
		rivet(holder, UDim.new(0, 6), UDim.new(0.5, 0))
		rivet(holder, UDim.new(1, -6), UDim.new(0.5, 0))
	end
	return holder, fill, recess
end

-- bottom cluster
local cluster = frame(gui, { Name = "Cluster", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y })
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = cluster
local message = label(cluster, "", F.labelBold, 14, C.red, { LayoutOrder = 0, Size = UDim2.fromOffset(560, 18), TextTransparency = 1, TextStrokeTransparency = 0.6 })
local hpBar, hpFill, hpRecess = steelBar(cluster, 500, 26, 5, CRIMSON, true, 2)
local hpText = label(hpRecess, "", F.labelBold, 13, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 1, 0), ZIndex = 7, TextStrokeTransparency = 0.4 })
local centreGem = diamond(hpBar, 13, nil, { Position = UDim2.new(0.5, 0, 0, -1), ZIndex = 8 })
_ = centreGem
local staminaBar, staminaFill = steelBar(cluster, 420, 11, 3, ColorSequence.new(Color3.fromRGB(250, 210, 115), Color3.fromRGB(178, 122, 30)), false, 3)
local manaBar, manaFill = steelBar(cluster, 420, 11, 3, ColorSequence.new(Color3.fromRGB(140, 180, 255), Color3.fromRGB(40, 80, 190)), false, 4)
_ = staminaBar
-- notches on the thin bars
for _, bar in ipairs({ staminaBar, manaBar }) do
	for q = 1, 3 do
		frame(bar, { Size = UDim2.new(0, 2, 1, 0), Position = UDim2.new(q / 4, -1, 0, 0), BackgroundColor3 = OUTLINE, ZIndex = 8 })
	end
end

-- End Ability meter in quarters, as gems
local gemRow = frame(cluster, { BackgroundTransparency = 1, Size = UDim2.fromOffset(560, 16), LayoutOrder = 5 })
local gems = {}
for index = 1, 4 do
	local setting, stone = diamond(gemRow, 12, nil, { Position = UDim2.new(0.5, (index - 2.5) * 24, 0.5, 0) })
	gems[index] = { setting = setting, stone = stone }
end

-- ability slots
local SLOT = 64
local row = frame(cluster, { BackgroundTransparency = 1, Size = UDim2.fromOffset(4 * SLOT + 3 * 14, SLOT + 18), LayoutOrder = 6 })
local slots = {}
for index = 1, 4 do
	local isEnd = index == 4
	local holder = frame(row, { BackgroundTransparency = 1, Size = UDim2.fromOffset(SLOT, SLOT + 18), Position = UDim2.fromOffset((index - 1) * (SLOT + 14), 0) })
	local plate = frame(holder, { Size = UDim2.fromOffset(SLOT, SLOT) })
	paint(plate, if isEnd then GOLD else STEEL)
	local stroke = outline(plate, if isEnd then Color3.fromRGB(42, 28, 8) else OUTLINE, 2)
	round(plate, 7)
	local recess = frame(plate, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), ClipsDescendants = true, ZIndex = 2 })
	paint(recess, ColorSequence.new(RECESS_TOP, RECESS_BOTTOM))
	outline(recess, Color3.fromRGB(5, 7, 10), 1.5)
	round(recess, 4)
	frame(plate, { Size = UDim2.new(1, -14, 0, 1), Position = UDim2.fromOffset(7, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, ZIndex = 3 })
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		rivet(plate, UDim.new(corner[1], if corner[1] == 0 then 3 else -3), UDim.new(corner[2], if corner[2] == 0 then 3 else -3))
	end
	diamond(plate, 8, if isEnd then GOLD else nil, { Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 5 })
	local meterFill = frame(recess, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.gold, BackgroundTransparency = 0.75, ZIndex = 3 })
	local name = label(recess, "", F.bodyBold, 11, C.text, { Position = UDim2.fromOffset(2, 10), Size = UDim2.new(1, -4, 1, -12), TextWrapped = true, ZIndex = 4 })
	local key = label(recess, tostring(index), F.labelBold, 12, if isEnd then C.gold else Color3.fromRGB(190, 220, 240), { Position = UDim2.fromOffset(4, 1), Size = UDim2.fromOffset(12, 13), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local cover = frame(recess, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, ZIndex = 5 })
	local timer = label(recess, "", F.labelBold, 20, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 1, 0), ZIndex = 6, TextStrokeTransparency = 0.5 })
	local cost = label(holder, "", F.labelBold, 11, Color3.fromRGB(226, 232, 240), { Position = UDim2.fromOffset(0, SLOT + 3), Size = UDim2.fromOffset(SLOT, 13), TextStrokeTransparency = 0.6 })
	slots[index] = { stroke = stroke, isEnd = isEnd, meter = meterFill, name = name, key = key, cover = cover, timer = timer, cost = cost, readyAt = 0, cooldown = 1, flashUntil = 0 }
end

-- EXP line on the bottom edge
local xpTrack = frame(gui, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromRGB(7, 10, 20), BackgroundTransparency = 0.25 })
local xpFill = frame(xpTrack, { BackgroundColor3 = C.xp, Size = UDim2.new(0, 0, 1, 0) })
_ = xpFill

-- boss bar, top centre, same ornate language
local boss = frame(gui, { Name = "Boss", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(660, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
local bossLayout = Instance.new("UIListLayout")
bossLayout.Padding = UDim.new(0, 4)
bossLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bossLayout.SortOrder = Enum.SortOrder.LayoutOrder
bossLayout.Parent = boss
local bossName = label(boss, "", F.title, 22, Color3.fromRGB(246, 228, 214), { LayoutOrder = 1, Size = UDim2.fromOffset(660, 26), TextStrokeTransparency = 0.45 })
local bossLevel = label(boss, "", F.labelBold, 12, Color3.fromRGB(226, 232, 240), { LayoutOrder = 2, Size = UDim2.fromOffset(660, 14), TextStrokeTransparency = 0.6 })
local _, bossFill = steelBar(boss, 620, 22, 4, CRIMSON, true, 3)

gui.Parent = player:WaitForChild("PlayerGui")

local progression: any = {}
local messageUntil = 0
local REVEAL_DELAY = 4 -- seconds after the System assigns the first class
local sawNoClass = false
local revealAt = 0
remotes.Snapshot.OnClientEvent:Connect(function(section: string, data: any)
	if section == "Progression" and type(data) == "table" then
		if data.classId == nil then
			sawNoClass = true
		elseif sawNoClass then
			-- the class was just assigned: let the moment play out before the HUD appears
			sawNoClass = false
			revealAt = os.clock() + REVEAL_DELAY
		end
		progression = data
	end
end)

-- Conversations and the class ritual take the screen: the HUD waits until they are over.
local function sceneOpen(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, name in ipairs({ "Dialogue", "Awakening" }) do
		local screen = playerGui and playerGui:FindFirstChild(name)
		if screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled then
			return true
		end
	end
	return false
end
remotes.RequestSnapshot:FireServer()

remotes.AbilityResult.OnClientEvent:Connect(function(slot: number, ok: boolean, detail: any)
	local entry = slots[slot]
	if entry == nil then
		return
	end
	if ok then
		entry.cooldown = math.max(0.1, tonumber(detail) or 1)
		entry.readyAt = os.clock() + entry.cooldown
	else
		entry.flashUntil = os.clock() + 0.35
		message.Text = tostring(detail)
		messageUntil = os.clock() + 1.6
	end
end)

local function fraction(value: any, max: any): number
	local v, m = tonumber(value) or 0, tonumber(max) or 0
	return if m > 0 then math.clamp(v / m, 0, 1) else 0
end

local function costText(ability: any): string
	if ability.endAbility then
		return "END"
	end
	local cost = ability.cost or {}
	local parts = {}
	if (cost.stamina or 0) > 0 then
		table.insert(parts, cost.stamina .. " ST")
	end
	if (cost.mana or 0) > 0 then
		table.insert(parts, cost.mana .. " MP")
	end
	return if #parts > 0 then table.concat(parts, " · ") else "free"
end

local function nearestBoss(root: BasePart?): Model?
	local folder = workspace:FindFirstChild("Enemies")
	if folder == nil or root == nil then
		return nil
	end
	local best, bestDistance = nil, 90
	for _, enemy in ipairs(folder:GetChildren()) do
		local def = Content.enemies[enemy:GetAttribute("EnemyId") or ""]
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
		if def ~= nil and def.boss and humanoid ~= nil and humanoid.Health > 0 and enemyRoot ~= nil then
			local distance = (enemyRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local classDef = progression.classId and Content.classes[progression.classId]
	gui.Enabled = character ~= nil and classDef ~= nil
	if not gui.Enabled or character == nil or classDef == nil then
		return
	end
	local oldHealth = player.PlayerGui:FindFirstChild("Health")
	if oldHealth ~= nil and oldHealth:IsA("ScreenGui") then
		oldHealth.Enabled = false
	end
	local now = os.clock()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	hpFill.Size = UDim2.new(fraction(humanoid and humanoid.Health, humanoid and humanoid.MaxHealth), 0, 1, 0)
	hpText.Text = if humanoid then string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth)) else ""
	staminaFill.Size = UDim2.new(fraction(character:GetAttribute("Stamina"), character:GetAttribute("MaxStamina")), 0, 1, 0)
	manaFill.Size = UDim2.new(fraction(character:GetAttribute("Mana"), character:GetAttribute("MaxMana")), 0, 1, 0)
	xpFill.Size = UDim2.new(fraction(progression.xpInto, progression.xpNeeded), 0, 1, 0)
	local endFill = fraction(character:GetAttribute("Ultimate"), character:GetAttribute("UltimateMax"))
	for index, gem in ipairs(gems) do
		local lit = endFill >= index / 4
		gem.stone.BackgroundTransparency = if lit then 0 else 0.75
		gem.setting.BackgroundTransparency = if lit then 0 else 0.35
	end
	local usesMana = false
	for index, entry in ipairs(slots) do
		local abilityId = classDef.abilities and classDef.abilities[index]
		local ability = abilityId and Content.abilities[abilityId]
		if ability ~= nil and ability.cost ~= nil and (ability.cost.mana or 0) > 0 then
			usesMana = true
		end
		local locked = ability ~= nil and (progression.level or 1) < (ability.requiredLevel or 1)
		entry.name.Text = if ability then ability.displayName else ""
		entry.name.TextColor3 = if locked then C.muted else C.text
		entry.cost.Text = if ability == nil then "" elseif locked then "Lv " .. tostring(ability.requiredLevel) else costText(ability)
		local remaining = entry.readyAt - now
		entry.cover.Size = UDim2.new(1, 0, if remaining > 0 then remaining / entry.cooldown else 0, 0)
		entry.timer.Text = if remaining > 0 then string.format("%d", math.ceil(remaining)) else ""
		local fill = if ability ~= nil and ability.endAbility then endFill else 0
		entry.meter.Size = UDim2.new(1, 0, fill, 0)
		local ready = ability ~= nil and ability.endAbility and fill >= 1 and remaining <= 0 and not locked
		if now < entry.flashUntil then
			entry.stroke.Color, entry.stroke.Thickness = C.red, 3
		elseif ready then
			entry.stroke.Color, entry.stroke.Thickness = Color3.fromRGB(255, 220, 130), 3
		else
			entry.stroke.Color, entry.stroke.Thickness = if entry.isEnd then Color3.fromRGB(42, 28, 8) else OUTLINE, 2
		end
	end
	manaBar.Visible = usesMana
	-- the HUD steps aside while a window, a conversation or the ritual is open, and before its first reveal
	local hidden = Ui.anyOpen() or sceneOpen() or now < revealAt
	cluster.Visible = not hidden
	message.TextTransparency = if now < messageUntil then 0 else 1
	message.TextStrokeTransparency = if now < messageUntil then 0.6 else 1
	local bossModel = nearestBoss(character:FindFirstChild("HumanoidRootPart") :: BasePart?)
	boss.Visible = bossModel ~= nil and not hidden
	if bossModel ~= nil then
		local def = Content.enemies[bossModel:GetAttribute("EnemyId")]
		local bossHumanoid = bossModel:FindFirstChildOfClass("Humanoid") :: Humanoid
		bossName.Text = string.upper(def.displayName)
		bossLevel.Text = string.format("BOSS  ·  LV %s", tostring(bossModel:GetAttribute("Level") or def.level))
		bossFill.Size = UDim2.new(fraction(bossHumanoid.Health, bossHumanoid.MaxHealth), 0, 1, 0)
	end
end)
