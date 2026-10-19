--!strict
-- Runs the open-world spawners in ServerData.Spawns (owner's world specification). A spawner works only while a player
-- is near its zone; after a minute with nobody near, its enemies are removed. Enemies spawn at random points on the
-- ground inside the zone. Rewards come from the normal kill path (each credited player once per kill).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SpawnRules = require(Shared.Domain.SpawnRules)
local Spawns = require(ServerStorage:WaitForChild("ServerData"):WaitForChild("Spawns"))

local SpawnService = {}
local services: any = nil
local ACTIVATION_RANGE = 140
local IDLE_SECONDS = 60
local states: {[string]: any} = {}
local random = Random.new()

function SpawnService.init(allServices: any)
	services = allServices
end

local function zoneOf(locationId: string): BasePart?
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("LocationId") == locationId then
			return instance
		end
	end
	return nil
end

local function playerNear(zone: BasePart): boolean
	local reach = ACTIVATION_RANGE + math.max(zone.Size.X, zone.Size.Z) / 2
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local position = if root ~= nil then (root :: BasePart).Position else Vector3.zero
		-- Underground zones (the hideout) only count players at roughly their own depth, not the street above.
		local sameLevel = zone.Position.Y > -20 or math.abs(position.Y - zone.Position.Y) < 25
		if root ~= nil and sameLevel and Vector3.new(position.X - zone.Position.X, 0, position.Z - zone.Position.Z).Magnitude <= reach then
			return true
		end
	end
	return false
end

local function spawnPoint(zone: BasePart): CFrame?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { zone }
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(exclude, enemies)
	end
	params.FilterDescendantsInstances = exclude
	for _ = 1, 6 do
		local offset = Vector3.new(random:NextNumber(-0.45, 0.45) * zone.Size.X, zone.Size.Y / 2, random:NextNumber(-0.45, 0.45) * zone.Size.Z)
		local top = zone.CFrame:PointToWorldSpace(offset)
		local hit = workspace:Raycast(top + Vector3.new(0, 5, 0), Vector3.new(0, -60, 0), params)
		if hit ~= nil and hit.Instance.CanCollide then
			return CFrame.new(hit.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		end
	end
	return nil
end

local function step()
	local now = os.clock()
	for id, spawner in pairs(Spawns) do
		local state = states[id]
		if state == nil then
			state = SpawnRules.newState()
			state.models = {}
			state.lastNear = 0
			states[id] = state
		end
		local zone = zoneOf(spawner.locationId)
		if zone ~= nil then
			if playerNear(zone) then
				state.lastNear = now
				if not state.active then
					SpawnRules.activate(spawner, state, now)
				end
			elseif state.active and now - state.lastNear > IDLE_SECONDS then
				for model in pairs(state.models) do
					model:Destroy()
				end
				state.models = {}
				SpawnRules.deactivate(state)
			end
			for _ = 1, SpawnRules.due(spawner, state, now) do
				local point = spawnPoint(zone)
				local model = point and services.EnemyService.spawn(spawner.enemyId, point, nil, "spawn:" .. id)
				if model ~= nil then
					SpawnRules.spawned(state)
					state.models[model] = true
					local humanoid = model:FindFirstChildOfClass("Humanoid")
					if humanoid ~= nil then
						humanoid.Died:Connect(function()
							if state.models[model] then
								state.models[model] = nil
								SpawnRules.died(spawner, state, os.clock())
							end
						end)
					end
				else
					table.insert(state.pending, now + 5) -- no room to spawn yet; try again shortly
				end
			end
		end
	end
end

function SpawnService.start()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step)
			if not ok then
				warn("[SpawnService] " .. tostring(err))
			end
		end
	end)
end

return SpawnService
