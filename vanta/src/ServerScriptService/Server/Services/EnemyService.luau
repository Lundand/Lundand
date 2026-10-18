--!strict
-- Enemies (M8). Spawns enemies for personal quest encounters (ServerData.Encounters) or by development
-- command, runs their behaviour ten times a second and reports strikes to CombatService. Enemies are owned by
-- the server so clients can't move them. A personal encounter can only be fought by its owner and their party.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CombatRules = require(Server.Domain.CombatRules)
local EnemyBrain = require(Server.Domain.EnemyBrain)
local QuestRules = require(Server.Domain.QuestRules)
local Models = require(Server.Tools.Models)
local Remotes = require(Server.Net.Remotes)
local Encounters = require(ServerStorage:WaitForChild("ServerData").Encounters)

local TICK = 0.1

local EnemyScaling = require(game:GetService("ReplicatedStorage").Shared.Domain.EnemyScaling)
local levelRandom = Random.new()

local EnemyService = {}
local services: any = nil
local enemies: {[Model]: any} = {}
local encounters: {[string]: {Model}} = {} -- "<userId>:<encounterId>" -> spawned models
local zones: {[string]: BasePart} = {}
local folder: Folder? = nil

function EnemyService.init(allServices: any)
	services = allServices
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function onDeath(model: Model)
	local info = enemies[model]
	if info == nil or info.dead then
		return
	end
	info.dead = true
	for _, key in ipairs(CombatRules.credited(info.damage, info.def.maxHealth, Content.combat.killCreditShare)) do
		local userId = tonumber(key)
		local player = userId and Players:GetPlayerByUserId(userId)
		if player then
			services.CombatService.onKill(player, info.id, info.def)
		end
	end
	task.delay(2, function()
		enemies[model] = nil
		services.CombatService.forget(model)
		model:Destroy()
	end)
end

function EnemyService.spawn(enemyId: string, cframe: CFrame, ownerUserId: number?, encounterKey: string?, level: number?): Model?
	local baseDef = Content.enemies[enemyId]
	local def = baseDef and EnemyScaling.atLevel(baseDef, level or EnemyScaling.rollLevel(baseDef, function(): number
		return levelRandom:NextNumber()
	end), Content.enemyProgression)
	local attack = Content.combat.enemyAttacks[enemyId] or (baseDef and Content.combat.archetypeAttacks[baseDef.archetype or "Melee"])
	if def == nil or attack == nil or folder == nil then
		return nil
	end
	local model
	if def.model == "Beast" then
		model = Models.wolf()
	else
		model = Models.humanoid(Models.palettes[enemyId])
	end
	model.Name = def.displayName
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("Level", def.level)
	local humanoid: any = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = def.maxHealth
	humanoid.Health = def.maxHealth
	humanoid.WalkSpeed = def.walkSpeed or 12
	model:PivotTo(cframe)
	model.Parent = folder
	if def.weapon ~= nil then
		Models.equipWeapon(model, def.weapon)
	end
	local root = rootOf(model)
	if root ~= nil then
		root:SetNetworkOwner(nil)
	end
	local home = cframe.Position
	enemies[model] = {
		id = enemyId,
		def = def,
		attack = attack,
		brain = EnemyBrain.new({ x = home.X, z = home.Z }),
		ownerUserId = ownerUserId,
		encounterKey = encounterKey,
		damage = {},
	}
	humanoid.Died:Connect(function()
		onDeath(model)
	end)
	return model
end

function EnemyService.definition(model: Model): any
	local info = enemies[model]
	return info and info.def
end

function EnemyService.canBeHitBy(model: Model, player: Player): boolean
	local info = enemies[model]
	if info == nil or info.dead then
		return false
	end
	if info.ownerUserId == nil or info.ownerUserId == player.UserId then
		return true
	end
	return services.PartyService.sameParty(info.ownerUserId, player.UserId)
end

function EnemyService.enemiesNear(position: Vector3, radius: number): {Model}
	local list = {}
	for model, info in pairs(enemies) do
		local root = rootOf(model)
		if not info.dead and root ~= nil and (root.Position - position).Magnitude <= radius then
			table.insert(list, model)
		end
	end
	return list
end

function EnemyService.damage(model: Model, player: Player, amount: number, staggers: boolean)
	local provoked = enemies[model]
	if provoked ~= nil and provoked.attack.passive then
		provoked.attack = table.clone(provoked.attack)
		provoked.attack.passive = false
		provoked.attack.aggroRange = 40 -- passive wildlife fights back once attacked
	end
	local info = enemies[model]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if info == nil or info.dead or humanoid == nil then
		return
	end
	CombatRules.recordDamage(info.damage, tostring(player.UserId), math.min(amount, humanoid.Health))
	humanoid:TakeDamage(amount)
	if info.brain.mode == "Idle" or info.brain.mode == "Return" then
		info.brain.mode = "Chase"
		info.brain.target = player.UserId
	end
	if staggers then
		EnemyService.stagger(model, Content.combat.staggerSeconds)
	end
	services.CombatService.hitFeedback(model, amount, "Hit", player.Character)
end

function EnemyService.stagger(model: Model, seconds: number)
	CombatRules.stagger(services.CombatService.stateFor(model), workspace:GetServerTimeNow(), seconds)
end

-- Provoking Strike: the enemy turns on this player for a few seconds (never permanently).
function EnemyService.taunt(model: Model, player: Player, seconds: number)
	local info = enemies[model]
	if info ~= nil then
		info.tauntedBy = player.UserId
		info.tauntUntil = workspace:GetServerTimeNow() + seconds
	end
end

-- Crowd control from abilities (durations already reduced by diminishing returns): a slow by `amount` (0 to 1) or
-- a root; the enemy's normal speed returns when the latest control ends.
function EnemyService.control(model: Model, kind: string, amount: number, seconds: number)
	local info = enemies[model]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if info == nil or humanoid == nil then
		return
	end
	info.baseSpeed = info.baseSpeed or humanoid.WalkSpeed
	local factor = if kind == "root" then 0 else math.clamp(1 - amount, 0, 1)
	local token = {}
	info.controlToken = token
	humanoid.WalkSpeed = info.baseSpeed * factor
	task.delay(seconds, function()
		if info.controlToken == token and humanoid.Parent ~= nil then
			humanoid.WalkSpeed = info.baseSpeed
		end
	end)
end

-- Gravity Well: moves an enemy toward a point by up to `distance` studs, never past it.
function EnemyService.pull(model: Model, center: Vector3, distance: number)
	local root = rootOf(model)
	if root == nil then
		return
	end
	local offset = Vector3.new(center.X - root.Position.X, 0, center.Z - root.Position.Z)
	if offset.Magnitude < 1.5 then
		return
	end
	model:PivotTo(model:GetPivot() + offset.Unit * math.min(distance, offset.Magnitude - 1))
end

local function telegraph(center: Vector3, radius: number, seconds: number)
	local folder = workspace:FindFirstChild("Telegraphs")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Telegraphs"
		folder.Parent = workspace
	end
	local mark = Instance.new("Part")
	mark.Shape = Enum.PartType.Cylinder
	mark.Size = Vector3.new(0.2, radius * 2, radius * 2)
	mark.CFrame = CFrame.new(center - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	mark.Material = Enum.Material.Neon
	mark.Color = Color3.fromRGB(220, 40, 40)
	mark.Transparency = 0.55
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.Parent = folder
	game:GetService("Debris"):AddItem(mark, seconds + 0.2)
end

-- Boss and elite patterns (world specification): a telegraphed slam on a timer during a fight, and a call for help
-- once below a health share. Both reset if the enemy resets after leashing.
local function bossMechanics(model: Model, info: any, root: BasePart, humanoid: Humanoid, now: number)
	local mechanics = info.def.mechanics
	if mechanics == nil then
		return
	end
	if info.brain.target == nil then
		return
	end
	local slam = mechanics.slam
	if slam ~= nil then
		info.nextSlam = info.nextSlam or now + slam.every
		if info.slamAt == nil and now >= info.nextSlam then
			info.slamAt = now + slam.windup
			info.slamCenter = root.Position
			telegraph(root.Position, slam.radius, slam.windup)
		elseif info.slamAt ~= nil and now >= info.slamAt then
			local center = info.slamCenter
			for _, player in ipairs(Players:GetPlayers()) do
				local target = rootOf(player.Character)
				if target ~= nil and Vector3.new(target.Position.X - center.X, 0, target.Position.Z - center.Z).Magnitude <= slam.radius then
					services.CombatService.areaHit(player, model, info.def.damage * slam.damageMultiplier)
				end
			end
			info.slamAt = nil
			info.nextSlam = now + slam.every
		end
	end
	local help = mechanics.callForHelp
	if help ~= nil and not info.calledHelp and humanoid.Health <= humanoid.MaxHealth * help.atHealth then
		info.calledHelp = true
		for index = 1, help.count do
			local angle = index * (2 * math.pi / help.count)
			EnemyService.spawn(help.enemyId, CFrame.new(root.Position + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)), info.ownerUserId, info.encounterKey)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local target = rootOf(player.Character)
			if target ~= nil and (target.Position - root.Position).Magnitude <= 80 then
				Remotes.get("Notify"):FireClient(player, help.message)
			end
		end
	end
end

local function think(model: Model, info: any, now: number)
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local targets = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local target = rootOf(player.Character)
		local targetHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if target ~= nil and targetHumanoid ~= nil and targetHumanoid.Health > 0 and EnemyService.canBeHitBy(model, player) and not services.CombatService.isConcealed(player, now) then
			table.insert(targets, { key = player.UserId, x = target.Position.X, z = target.Position.Z })
		end
	end
	local state = services.CombatService.stateFor(model)
	if info.tauntUntil ~= nil and now < info.tauntUntil then
		for _, candidate in ipairs(targets) do
			if candidate.key == info.tauntedBy then
				targets = { candidate }
				info.brain.target = candidate.key
				break
			end
		end
	end
	local decision = EnemyBrain.update(info.brain, { x = root.Position.X, z = root.Position.Z }, targets, info.attack, now, state.staggeredUntil)
	if decision.moveTo ~= nil then
		humanoid:MoveTo(Vector3.new(decision.moveTo.x, root.Position.Y, decision.moveTo.z))
	end
	if decision.face ~= nil then
		humanoid:MoveTo(root.Position)
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(decision.face.x, root.Position.Y, decision.face.z))
	end
	local targetPosition = nil
	for _, candidate in ipairs(targets) do
		if candidate.key == info.brain.target then
			targetPosition = Vector3.new(candidate.x, root.Position.Y, candidate.z)
		end
	end
	if targetPosition ~= nil then
		local away = root.Position - targetPosition
		local fleeing = info.attack.fleeBelow ~= nil and humanoid.Health < humanoid.MaxHealth * info.attack.fleeBelow
		if away.Magnitude > 0.1 and (fleeing or (info.attack.keepDistance ~= nil and away.Magnitude < info.attack.keepDistance and not decision.strike)) then
			humanoid:MoveTo(root.Position + away.Unit * 10)
			if fleeing then
				return -- wounded wildlife runs instead of fighting
			end
		end
	end
	bossMechanics(model, info, root, humanoid, now)
	if decision.telegraph then
		services.CombatService.broadcast(model, info.attack.animation, { windup = info.attack.windup, telegraph = true })
	end
	if decision.strike then
		services.CombatService.enemyStrike(model, info.id)
	end
	if decision.reset then
		humanoid.Health = humanoid.MaxHealth
		info.damage = {}
		info.nextSlam, info.slamAt, info.calledHelp = nil, nil, false
	end
end

local function zoneOf(locationId: string): BasePart?
	local zone = zones[locationId]
	if zone ~= nil and zone.Parent ~= nil then
		return zone
	end
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("LocationId") == locationId then
			zones[locationId] = instance
			return instance
		end
	end
	return nil
end

local function inside(zone: BasePart, position: Vector3): boolean
	local offset = zone.CFrame:PointToObjectSpace(position)
	return math.abs(offset.X) <= zone.Size.X / 2 and math.abs(offset.Z) <= zone.Size.Z / 2
end

local function wantsKills(player: Player, encounter: any): boolean
	local character = services.PlayerDataService.getCharacter(player)
	local def = Content.quests[encounter.questId]
	local state = character and character.quests[encounter.questId]
	return state ~= nil and state.state == "Active" and not QuestRules.isComplete(state, def, character.inventory)
end

local function despawn(key: string)
	for _, model in ipairs(encounters[key] or {}) do
		enemies[model] = nil
		services.CombatService.forget(model)
		model:Destroy()
	end
	encounters[key] = nil
end

-- Personal encounters appear when the quest holder enters the place, and go when they leave, finish the
-- kills, or defeat everyone (a fresh group appears if kills are still needed).
local function updateEncounters()
	for encounterId, encounter in pairs(Encounters) do
		local zone = zoneOf(encounter.locationId)
		for _, player in ipairs(Players:GetPlayers()) do
			local key = tostring(player.UserId) .. ":" .. encounterId
			local root = rootOf(player.Character)
			local wanted = zone ~= nil and root ~= nil and wantsKills(player, encounter)
			local spawned = encounters[key]
			local zonePart: any = zone
			local rootPart: any = root
			if spawned == nil and wanted and inside(zonePart, rootPart.Position) then
				encounters[key] = {}
				for _ = 1, encounter.count do
					local offset = Vector3.new(math.random(-8, 8), 4, math.random(-8, 8))
					local model = EnemyService.spawn(encounter.enemyId, CFrame.new(zonePart.Position + offset), player.UserId, key)
					if model ~= nil and encounters[key] ~= nil then
						table.insert(encounters[key], model)
					end
				end
			elseif spawned ~= nil then
				local alive = false
				for _, model in ipairs(spawned) do
					if enemies[model] ~= nil and not enemies[model].dead then
						alive = true
					end
				end
				local far = root == nil or zone == nil or (zonePart.Position - rootPart.Position).Magnitude > encounter.despawnDistance
				if not wanted or far or not alive then
					despawn(key)
				end
			end
		end
	end
end

function EnemyService.start()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
	Players.PlayerRemoving:Connect(function(player: Player)
		for key in pairs(encounters) do
			if string.sub(key, 1, #tostring(player.UserId) + 1) == tostring(player.UserId) .. ":" then
				despawn(key)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local now = workspace:GetServerTimeNow()
			for model, info in pairs(enemies) do
				if not info.dead then
					think(model, info, now)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			updateEncounters()
		end
	end)
end

return EnemyService
