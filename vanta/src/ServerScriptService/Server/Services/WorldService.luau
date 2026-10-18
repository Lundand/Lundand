--!strict
-- World passages (the cellar door into the hideout and the ladder back up): the server builds each door and its
-- prompt at start from the list below, and moves the character when it is used (short cooldown per player).
local WorldService = {}
local lastUse: {[Player]: number} = {}

local HIDEOUT = Vector3.new(-200, -60, 230)
local PASSAGES = {
	{ name = "CellarDoor", position = Vector3.new(-262, 3.5, 262), size = Vector3.new(5, 7, 1), action = "Climb down", object = "Cellar door", destination = HIDEOUT + Vector3.new(-66, 3, 0) },
	{ name = "Ladder", position = HIDEOUT + Vector3.new(-72, 3.5, 0), size = Vector3.new(1, 7, 4), action = "Climb up", object = "Ladder", destination = Vector3.new(-262, 4, 256) },
}

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
	local folder = Instance.new("Folder")
	folder.Name = "Passages"
	folder.Parent = workspace
	for _, entry in ipairs(PASSAGES) do
		build(entry, folder)
	end
end

return WorldService
