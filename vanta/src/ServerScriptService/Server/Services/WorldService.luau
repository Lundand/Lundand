--!strict
-- World passages: doors with a prompt that move the character somewhere else (short cooldown per player). The
-- hideout is now reached on foot (stairs from the Crooked Lantern's cellar), so the city layout lists none; any
-- passage added to ServerData.CityLayout.passages ({ name, position, size, action, object, destination }) is built.
local ServerStorage = game:GetService("ServerStorage")
local Layout = require(ServerStorage:WaitForChild("ServerData").CityLayout)

local WorldService = {}
local lastUse: {[Player]: number} = {}

local PASSAGES = Layout.passages or {}

function WorldService.init(_: any) end

local function build(entry: any, folder: Instance)
	local door = Instance.new("Part")
	door.Name = entry.name
	door.Anchored = true
	door.Size = entry.size
	door.CFrame = CFrame.new(entry.position)
	door.Color = Color3.fromRGB(80, 56, 36)
	door.Material = Enum.Material.Wood
	door.Parent = folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = entry.action
	prompt.ObjectText = entry.object
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastUse[player] or 0) < 1 or player.Character == nil then
			return
		end
		lastUse[player] = now
		player.Character:PivotTo(CFrame.new(entry.destination + Vector3.new(0, 3, 0)))
	end)
end

function WorldService.start()
	if #PASSAGES == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Passages"
	folder.Parent = workspace
	for _, entry in ipairs(PASSAGES) do
		build(entry, folder)
	end
end

return WorldService
