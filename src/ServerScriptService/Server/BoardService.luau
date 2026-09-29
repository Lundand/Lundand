--[[
	BoardService — global leaderboards at spawn (OrderedDataStores, shared by every server):
	Highest Zone reached, Most Power, Rarest Core found.
	Without DataStore access (unpublished Studio place) the boards show the current server instead,
	and each board says which one it shows. A temporary DataStore error only pauses the boards for a minute.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local BoardService = {}
local S: any

type Board = { key: string, store: OrderedDataStore?, part: BasePart? }

local boards: { Board } = {
	{ key = "zone", store = nil, part = nil },
	{ key = "power", store = nil, part = nil },
	{ key = "rarest", store = nil, part = nil },
}
local STORE_NAMES = { zone = "CH_HighestZone_v1", power = "CH_Power_v1", rarest = "CH_Rarest_v1" }
local dirty: { [Player]: boolean } = {}
local lastSent: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}
local storesWork = true -- false only when this place can't use DataStores at all (Studio without API access)
local pausedUntil = 0 -- a temporary error (throttling, outage) pauses DataStore calls until then

local function failed(err: any)
	local text = tostring(err)
	if string.find(text, "StudioAccessToApisNotAllowed", 1, true) or string.find(text, "403", 1, true) or string.find(text, "API Services", 1, true) then
		storesWork = false
	else
		pausedUntil = os.clock() + 60
	end
	warn("[Boards] DataStore request failed: " .. text)
end

local function storesReady(): boolean
	return storesWork and os.clock() >= pausedUntil
end

-- Power can grow past what an integer holds, so it is stored as log10 * 1e6
local function encodePower(power: number): number
	return math.floor(math.log10(math.max(power, 1)) * 1e6)
end
local function decodePower(value: number): number
	return 10 ^ (value / 1e6)
end

local function scores(player: Player): { [string]: number }?
	local data = S.Data.Get(player)
	if not data then
		return nil
	end
	local best = data.best and data.best[1]
	return {
		zone = S.Player.HighestZone(player),
		power = encodePower(S.Player.GetPower(player)),
		rarest = best and math.floor(best.odds or 0) or 0,
	}
end

local function format(key: string, value: number): string
	if key == "zone" then
		if value > #Config.Zones then
			return "Zone " .. value .. " ∞"
		end
		local zone = Config.Zones[math.max(value, 1)]
		return "Zone " .. value .. " • " .. (zone and zone.name or "?")
	elseif key == "power" then
		return "⚡ " .. Util.Abbrev(decodePower(value))
	end
	return value > 0 and Util.Odds(value) or "-"
end

local function nameFor(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and name or ("User " .. userId)
	return names[userId]
end

function BoardService.MarkDirty(player: Player)
	dirty[player] = true
end

function BoardService.Submit(player: Player)
	if not storesReady() then
		dirty[player] = true -- try again later
		return
	end
	local values = scores(player)
	if not values then
		return
	end
	local sent = lastSent[player] or {}
	lastSent[player] = sent
	for _, board in boards do
		local value = values[board.key]
		if board.store and value and value > 0 and sent[board.key] ~= value then
			local ok, err = pcall(function()
				(board.store :: OrderedDataStore):SetAsync("p_" .. player.UserId, value)
			end)
			if ok then
				sent[board.key] = value
			else
				failed(err)
				dirty[player] = true
				return
			end
		end
	end
end

local function render(board: Board, rows: { { name: string, value: number } }, global: boolean)
	local part = board.part
	local display = part and part:FindFirstChild("Display")
	local list = display and display:FindFirstChild("List")
	if not list or not display then
		return
	end
	-- small line under the title: every server, or only this one
	local scope = display:FindFirstChild("Scope")
	if not scope then
		local label = Instance.new("TextLabel")
		label.Name = "Scope"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0.04, 0)
		label.Position = UDim2.new(0, 0, 0.152, 0)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(170, 176, 200)
		label.Parent = display
		scope = label
	end
	(scope :: TextLabel).Text = global and "🌍 ALL SERVERS  •  TOP 10" or "THIS SERVER ONLY (no DataStore access here)"
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, row in rows do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0.095, 0)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 80) or (i == 2 and Color3.fromRGB(220, 220, 235) or (i == 3 and Color3.fromRGB(230, 160, 100) or Color3.fromRGB(235, 235, 240)))
		label.Text = string.format("#%d  %s   —   %s", i, row.name, format(board.key, row.value))
		label.LayoutOrder = i
		label.Parent = list
	end
	if #rows == 0 then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0.1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(180, 180, 190)
		label.Text = "No scores yet — be the first!"
		label.Parent = list
	end
end

local function refresh()
	if storesWork and not storesReady() then
		return -- paused after a DataStore error: keep showing the last global lists
	end
	for _, board in boards do
		local rows = {}
		if storesWork and board.store then
			local store = board.store :: OrderedDataStore
			local ok, err = pcall(function()
				local page = store:GetSortedAsync(false, 10):GetCurrentPage()
				for _, entry in page do
					local userId = tonumber(string.match(entry.key, "%d+")) or 0
					table.insert(rows, { name = nameFor(userId), value = entry.value })
				end
			end)
			if ok then
				render(board, rows, true)
			else
				failed(err)
				if storesWork then
					return -- temporary: keep the old lists, try again later
				end
			end
		end
		if not storesWork then
			-- no DataStores here (Studio without API access): show this server's players
			rows = {}
			for _, player in Players:GetPlayers() do
				local values = scores(player)
				if values then
					table.insert(rows, { name = player.DisplayName, value = values[board.key] })
				end
			end
			table.sort(rows, function(x, y)
				return x.value > y.value
			end)
			while #rows > 10 do
				table.remove(rows)
			end
			render(board, rows, false)
		end
	end
end

function BoardService.Init(services: any)
	S = services
	for _, board in boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(STORE_NAMES[board.key])
		end)
		if ok then
			board.store = store
		else
			storesWork = false
		end
	end
end

function BoardService.Start()
	for _, board in boards do
		board.part = S.World.Boards[board.key]
	end
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastSent[player] = nil
	end)
	task.spawn(function()
		task.wait(8)
		refresh()
		local elapsed = 0
		while true do
			task.wait(30)
			elapsed += 30
			for player in dirty do
				dirty[player] = nil
				if player.Parent then
					BoardService.Submit(player)
					task.wait(1)
				end
			end
			if elapsed >= 90 or not storesWork then
				elapsed = 0
				refresh()
			end
		end
	end)
end

return BoardService
