--!strict
-- Development HUD: Studio only, hidden by default, F2 toggles it. Shows the progression and inventory
-- snapshots and runs development commands. Never part of the game's HUD (L-42).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local Content = require(ReplicatedStorage:WaitForChild("Shared").Content)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local state: {[string]: any} = {}
local messages: {string} = {}

local gui = Instance.new("ScreenGui")
gui.Name = "DevHud"
gui.ResetOnSpawn = false

local function label(name: string, size: UDim2, position: UDim2): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Size = size
	text.Position = position
	text.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	text.BackgroundTransparency = 0.25
	text.TextColor3 = Color3.fromRGB(235, 235, 235)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Font = Enum.Font.Code
	text.TextSize = 14
	text.TextWrapped = true
	text.Text = ""
	text.Parent = gui
	return text
end

local statePanel = label("State", UDim2.new(0, 380, 0, 430), UDim2.new(0, 10, 0, 10))
local messagePanel = label("Messages", UDim2.new(0, 380, 0, 110), UDim2.new(0, 10, 0, 450))

local buttonBar = Instance.new("Frame")
buttonBar.Name = "Buttons"
buttonBar.Size = UDim2.new(0, 190, 0, 430)
buttonBar.Position = UDim2.new(0, 400, 0, 10)
buttonBar.BackgroundTransparency = 1
buttonBar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = buttonBar

local function button(text: string, onClick: () -> ())
	local item = Instance.new("TextButton")
	item.Size = UDim2.new(1, 0, 0, 26)
	item.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	item.TextColor3 = Color3.fromRGB(240, 240, 240)
	item.Font = Enum.Font.Code
	item.TextSize = 14
	item.Text = text
	item.Parent = buttonBar
	item.Activated:Connect(onClick)
end

local function render()
	local lines = {}
	local progression = state.Progression
	if progression then
		local needed = "max"
		if progression.xpNeeded then
			needed = tostring(progression.xpNeeded)
		end
		table.insert(lines, string.format("Level %d   XP %d / %s", progression.level, progression.xpInto, needed))
		table.insert(lines, string.format("Class: %s%s", tostring(progression.className or "none"), (progression.legendary and " (legendary)") or ""))
		if progression.xpBonus then
			table.insert(lines, string.format("Catch-up bonus until level %d", progression.xpBonus.untilLevel))
		end
		table.insert(lines, string.format("Stat points available: %d", progression.availablePoints))
		for _, statId in ipairs(Content.stats.order) do
			table.insert(lines, string.format("  %-12s %d", statId, progression.allocated[statId] or 0))
		end
		for _, discipline in pairs(progression.disciplines) do
			local techniques = {}
			for techniqueId in pairs(discipline.techniques) do
				table.insert(techniques, techniqueId)
			end
			table.sort(techniques)
			table.insert(lines, string.format("%s rank %d/%d: %s", discipline.name, discipline.rank, discipline.maxRank, table.concat(techniques, ", ")))
		end
		for _, profession in pairs(progression.professions) do
			table.insert(lines, string.format("  %s level %d", profession.name, profession.level))
		end
	end
	local inventory = state.Inventory
	if inventory then
		table.insert(lines, string.format("Inventory %d/%d   Gold %d", inventory.used, inventory.capacity, inventory.currencies.Gold or 0))
		for _, entry in ipairs(inventory.entries) do
			local detail = ""
			if entry.craftedBy then
				detail = string.format("  (crafted by %s, %s)", entry.craftedBy, tostring(entry.quality))
			elseif entry.origin then
				detail = "  (" .. entry.origin .. ")"
			end
			table.insert(lines, string.format("  %s x%d%s", entry.name, entry.count, detail))
		end
	end
	statePanel.Text = table.concat(lines, "\n")
	messagePanel.Text = table.concat(messages, "\n")
end

local function dev(name: string, args: any)
	remotes.DevCommand:FireServer(name, args)
end

local function firstUid(itemId: string): string?
	local inventory = state.Inventory
	if inventory then
		for _, entry in ipairs(inventory.entries) do
			if entry.itemId == itemId and entry.uid then
				return entry.uid
			end
		end
	end
	return nil
end

for _, statId in ipairs(Content.stats.order) do
	button("+1 " .. statId, function()
		remotes.AllocateStats:FireServer({ [statId] = 1 })
	end)
end
button("Activate class book", function()
	local uid = firstUid("LegendaryBookPlaceholder")
	if uid then
		remotes.ActivateLegendaryBook:FireServer(uid, string.format("%d-%d", os.time(), math.random(1, 1000000000)))
	end
end)
button("[dev] Spawn thief", function()
	dev("spawnEnemy", { enemyId = "AlleyThief" })
end)
button("[dev] Spawn wolf", function()
	dev("spawnEnemy", { enemyId = "ForestWolf" })
end)
button("[dev] 3 thief kills", function()
	dev("simulateKill", { enemyId = "AlleyThief", count = 3 })
end)
local classCycle = { "Swordmaster", "Mage", "HeavyKnight", "Archer", "Rogue", "Acolyte", "Brawler", "Spellblade", "Shadowblade", "Summoner", "Paladin", "Stormcaller", "GrandSwordmaster" }
local classIndex = 0
button("[dev] Switch class", function()
	classIndex = classIndex % #classCycle + 1
	dev("setClass", { classId = classCycle[classIndex] })
end)
-- Legendary classes only come from class books: this gives the next one; read it from the inventory (I).
local legendaryBooks = { "VoidSwordmasterBook", "LichLordBook", "WorldbreakerBerserkerBook", "AstralArchmageBook", "SeraphicGuardianBook", "NightSovereignBook", "DragonbloodKnightBook", "ChronomancerBook", "ThunderSovereignBook", "WorldrootSageBook", "AbyssalWarlockBook", "BladeEmperorBook" }
local bookIndex = 0
button("[dev] Next Legendary book", function()
	bookIndex = bookIndex % #legendaryBooks + 1
	dev("giveItem", { itemId = legendaryBooks[bookIndex] })
end)
button("[dev] +500 XP", function()
	dev("grantXp", { amount = 500 })
end)
button("[dev] +300 Sword Arts", function()
	dev("grantDisciplineXp", { disciplineId = "SwordArts", amount = 300 })
end)
button("[dev] Iron Wall", function()
	dev("completeMilestone", { disciplineId = "SwordArts", milestoneId = "IronWall" })
end)
button("[dev] Pickaxe + hatchet", function()
	dev("giveItem", { itemId = "CopperPickaxe" })
	dev("giveItem", { itemId = "CopperHatchet" })
end)
button("[dev] Class book", function()
	dev("giveItem", { itemId = "LegendaryBookPlaceholder" })
end)
button("[dev] Reset character", function()
	dev("resetCharacter", {})
end)

remotes.Snapshot.OnClientEvent:Connect(function(section: string, data: any)
	state[section] = data
	render()
end)
remotes.Notify.OnClientEvent:Connect(function(message: string)
	table.insert(messages, message)
	while #messages > 6 do
		table.remove(messages, 1)
	end
	render()
end)

gui.Enabled = false
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.F2 then
		gui.Enabled = not gui.Enabled
	end
end)
gui.Parent = player:WaitForChild("PlayerGui")
remotes.RequestSnapshot:FireServer()
render()
