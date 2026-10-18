--!strict
-- Summons (class specification: Summoner; later Lich Lord): server-managed allies with strict limits. Each summon
-- belongs to a group (Wisp, Legion) with its own cap and lifetime, and all of a player's summons share one cap; the
-- oldest makes way. A summon floats near its owner and strikes the commanded focus or the nearest enemy in reach
-- every few seconds, for damage the server computes. Summons are dismissed when the owner dies or leaves.
-- Placeholder look: glowing orbs.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SummonService = {}
local services: any = nil
local MAX_PER_PLAYER = 5
local active: {[Player]: any} = {}

function SummonService.init(allServices: any)
	services = allServices
end

local function folder(): Instance
	local existing = workspace:FindFirstChild("Summons")
	if existing ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Summons"
	created.Parent = workspace
	return created
end

local function stateFor(player: Player): any
	local state = active[player]
	if state == nil then
		state = { summons = {}, focus = nil, focusUntil = 0, bonus = 0, bonusUntil = 0 }
		active[player] = state
	end
	return state
end

local function rootOf(model: any): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function alive(enemy: any): boolean
	local humanoid = enemy and enemy.Parent and enemy:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function SummonService.summon(player: Player, spec: any)
	local root = rootOf(player.Character)
	if root == nil then
		return
	end
	local state = stateFor(player)
	local now = os.clock()
	for _ = 1, spec.count do
		local group = {}
		for _, entry in ipairs(state.summons) do
			if entry.spec.group == spec.group then
				table.insert(group, entry)
			end
		end
		if #group >= spec.max or #state.summons >= MAX_PER_PLAYER then
			local oldest = if #group >= spec.max then group[1] else state.summons[1]
			oldest.part:Destroy()
			table.remove(state.summons, table.find(state.summons, oldest) :: number)
		end
		local part = Instance.new("Part")
		part.Name = spec.group
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(spec.size, spec.size, spec.size)
		part.Material = Enum.Material.Neon
		part.Color = if spec.group == "Legion" then Color3.fromRGB(120, 200, 255) else Color3.fromRGB(170, 140, 255)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CFrame = root.CFrame * CFrame.new(0, 3, 2)
		part:SetAttribute("Owner", player.UserId)
		part.Parent = folder()
		table.insert(state.summons, { part = part, spec = spec, untilTime = now + spec.lifetime, nextAttack = now + spec.interval, angle = math.random() * math.pi * 2 })
	end
end

-- Command Minion: the summons focus the enemy nearest the aimed point, within reach of the owner, for a while.
function SummonService.command(player: Player, aim: Vector3?, command: any)
	local root = rootOf(player.Character)
	if root == nil then
		return
	end
	local point = aim or root.Position
	local best, bestDistance = nil, math.huge
	for _, enemy in ipairs(services.EnemyService.enemiesNear(root.Position, command.range)) do
		local enemyRoot = rootOf(enemy)
		if enemyRoot ~= nil and services.EnemyService.canBeHitBy(enemy, player) then
			local distance = (enemyRoot.Position - point).Magnitude
			if distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	local state = stateFor(player)
	state.focus, state.focusUntil = best, os.clock() + command.seconds
end

-- Soul Link: summons strike harder for a while.
function SummonService.empower(player: Player, empower: any)
	local state = stateFor(player)
	state.bonus, state.bonusUntil = empower.bonus, os.clock() + empower.seconds
end

function SummonService.count(player: Player): number
	local state = active[player]
	return if state then #state.summons else 0
end

function SummonService.dismiss(player: Player)
	local state = active[player]
	if state ~= nil then
		for _, entry in ipairs(state.summons) do
			entry.part:Destroy()
		end
	end
	active[player] = nil
end

local function strike(player: Player, state: any, entry: any, now: number)
	local target = nil
	if state.focus ~= nil and now < state.focusUntil and alive(state.focus) then
		target = state.focus
	else
		local bestDistance = entry.spec.range
		for _, enemy in ipairs(services.EnemyService.enemiesNear(entry.part.Position, entry.spec.range)) do
			local enemyRoot = rootOf(enemy)
			if enemyRoot ~= nil and alive(enemy) and services.EnemyService.canBeHitBy(enemy, player) then
				local distance = (enemyRoot.Position - entry.part.Position).Magnitude
				if distance <= bestDistance then
					target, bestDistance = enemy, distance
				end
			end
		end
	end
	if target == nil then
		return
	end
	local bonus = if now < state.bonusUntil then state.bonus else 0
	local amount = math.max(1, services.CombatService.damageFor(player, entry.spec.multiplier * (1 + bonus), "Magic"))
	services.EnemyService.damage(target, player, amount, false)
	services.CombatService.hitFeedback(target, amount, "Hit", nil)
end

local function step()
	local now = os.clock()
	for player, state in pairs(active) do
		local root = rootOf(player.Character)
		local kept = {}
		for index, entry in ipairs(state.summons) do
			if root == nil or now >= entry.untilTime or entry.part.Parent == nil then
				entry.part:Destroy()
			else
				table.insert(kept, entry)
				entry.angle += 0.04
				local offset = Vector3.new(math.cos(entry.angle + index * 2) * 4, 3, math.sin(entry.angle + index * 2) * 4)
				entry.part.CFrame = entry.part.CFrame:Lerp(CFrame.new((root :: BasePart).Position + offset), 0.2)
				if now >= entry.nextAttack then
					entry.nextAttack = now + entry.spec.interval
					strike(player, state, entry, now)
				end
			end
		end
		state.summons = kept
	end
end

function SummonService.start()
	RunService.Heartbeat:Connect(step)
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			SummonService.dismiss(player)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(SummonService.dismiss)
end

return SummonService
