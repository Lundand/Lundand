--[[
	AdminPanel — quick testing tools (only visible to admins: Studio, the owner, Config.Admins).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local AdminPanel = {}

local zone = 1
local rarity = 5
local built = false
local zoneButtons: { TextButton } = {}
local rarityButtons: { TextButton } = {}
local resetArmed = 0

local function cmd(name: string, args: { [string]: any }?)
	local payload = args or {}
	payload.cmd = name
	State.Request("admin", payload)
end

local function section(parent: Instance, order: number, title: string): Frame
	UI.Text(parent, string.upper(title), { Size = UDim2.new(1, 0, 0, 28), Font = UI.Fonts.Title, AlignX = Enum.TextXAlignment.Left, Order = order, MaxSize = 21, Gold = true, Outline = 2 })
	local row = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 44), Transparency = 1, Radius = false, Order = order + 1 })
	UI.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Wraps = true, Parent = row })
	row.AutomaticSize = Enum.AutomaticSize.Y
	return row
end

local function paintSelectors()
	for i, button in zoneButtons do
		button.BackgroundColor3 = i == zone and UI.Colors.Gold or UI.Colors.CardHi
	end
	for i, button in rarityButtons do
		button.BackgroundColor3 = i == rarity and Config.Rarities[i].color or UI.Colors.CardHi
	end
end

function AdminPanel.Build(content: Frame)
	local scroll = UI.Scroll(content, { Gap = 8 })

	local quick = section(scroll, 1, "Quick")
	local actions = {
		{ "+ Coins", "coins" },
		{ "+ Fragments", "fragments" },
		{ "Finish incubators", "finish" },
		{ "+10 Training", "train" },
		{ "Unlock all zones", "unlock" },
		{ "Spawn boss here", "boss" },
		{ "God mode", "god" },
		{ "x2 luck 30m", "luck" },
		{ "Cycle PvP mode", "pvp" },
	}
	for i, a in actions do
		UI.Button(quick, a[1], UI.Colors.Blue, function()
			cmd(a[2])
		end, { Size = UDim2.fromOffset(190, 44), Order = i, MaxSize = 17 })
	end

	local zones = section(scroll, 3, "Zone (for Cores, items and teleport)")
	for i = 1, #Config.Zones + 1 do
		local label = i <= #Config.Zones and Config.Zones[i].name or ("Rift Z" .. Config.Rift.StartZone)
		zoneButtons[i] = UI.Button(zones, label, UI.Colors.CardHi, function()
			zone = i
			paintSelectors()
		end, { Size = UDim2.fromOffset(126, 40), Order = i, MaxSize = 15 })
	end

	local rarities = section(scroll, 5, "Rarity")
	for i, r in Config.Rarities do
		rarityButtons[i] = UI.Button(rarities, r.name, UI.Colors.CardHi, function()
			rarity = i
			paintSelectors()
		end, { Size = UDim2.fromOffset(126, 40), Order = i, MaxSize = 15 })
	end

	local give = section(scroll, 7, "Give")
	UI.Button(give, "Drop Core in front of me", UI.Colors.Good, function()
		cmd("core", { z = zone <= #Config.Zones and zone or Config.Rift.StartZone, r = rarity })
	end, { Size = UDim2.fromOffset(260, 44), Order = 1, MaxSize = 17 })
	UI.Button(give, "Give random item", UI.Colors.Good, function()
		cmd("item", { z = zone <= #Config.Zones and zone or Config.Rift.StartZone, r = rarity })
	end, { Size = UDim2.fromOffset(210, 44), Order = 2, MaxSize = 17 })
	UI.Button(give, "Teleport to zone", UI.Colors.Purple, function()
		cmd("tp", { zone = math.min(zone, #Config.Zones) })
	end, { Size = UDim2.fromOffset(210, 44), Order = 3, MaxSize = 17 })

	local passes = section(scroll, 9, "Game passes (this session)")
	local order = 0
	for name, pass in Config.Passes do
		order += 1
		UI.Button(passes, pass.name, UI.Colors.Robux, function()
			cmd("pass", { name = name })
		end, { Size = UDim2.fromOffset(180, 44), Order = order, MaxSize = 16 })
	end

	local danger = section(scroll, 11, "Danger")
	local reset
	reset = UI.Button(danger, "Reset MY data", UI.Colors.Bad, function()
		if os.clock() - resetArmed < 3 then
			resetArmed = 0
			reset.Text = "Reset MY data"
			cmd("reset")
		else
			resetArmed = os.clock()
			reset.Text = "Click again to confirm"
			task.delay(3, function()
				reset.Text = "Reset MY data"
			end)
		end
	end, { Size = UDim2.fromOffset(250, 44), Order = 1, MaxSize = 17 })

	local premium = section(scroll, 13, "Premium Cores & paid-random rules")
	UI.Button(premium, "Open Premium Core (free)", Color3.fromRGB(150, 80, 255), function()
		cmd("premium")
	end, { Size = UDim2.fromOffset(280, 44), Order = 1, MaxSize = 17 })
	UI.Button(premium, "Toggle paid-random restriction", UI.Colors.CardHi, function()
		cmd("policy")
	end, { Size = UDim2.fromOffset(300, 44), Order = 2, MaxSize = 17 })

	paintSelectors()
	built = true
end

function AdminPanel.Refresh(_data: any)
	if built then
		paintSelectors()
	end
end

return AdminPanel
