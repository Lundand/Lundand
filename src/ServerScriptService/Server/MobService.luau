--[[
	MobService — spawns and runs every monster.
	* Each main zone has a spawner (2 normal mob types, elites and a boss) that only
	  runs while a player is nearby, so empty zones cost nothing.
	* Simple, readable AI: wander -> aggro -> chase -> attack -> leash back home.
	* Bosses telegraph a ground slam.
	* Kills pay Coins + Fragments to everyone who helped and roll a Core drop for each of them.
	* The Endless Rift creates its own wave spawners through CreateSpawner.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local MobService = {}
local S: any
local FX: RemoteEvent

local rng = Random.new()
local mobFolder: Folder
local rayParams = RaycastParams.new()

type Region = { kind: string, minX: number, maxX: number, minZ: number, maxZ: number, center: Vector3, radius: number }
type Entry = { mobId: string, tier: string, count: number, respawn: number, first: number?, alive: number, nextSpawn: number }
export type Spawner = {
	zone: number,
	region: Region,
	entries: { Entry },
	active: boolean,
	lastSeen: number,
	owner: Player?,
	wave: boolean,
	onDeath: ((any, Player?) -> ())?,
	mobs: { [any]: boolean },
	removed: boolean,
	activated: boolean,
}
export type Mob = {
	model: Model,
	root: BasePart,
	hum: Humanoid,
	def: any,
	mobId: string,
	tier: string,
	tc: any,
	zone: number,
	maxHp: number,
	hp: number,
	home: Vector3,
	spawner: Spawner,
	entry: Entry,
	target: Player?,
	speed: number,
	aggro: number,
	cooldown: number,
	dmg: number,
	lastAttack: number,
	nextWander: number,
	damageBy: { [Player]: number },
	stunUntil: number,
	dead: boolean,
	fill: Frame,
	height: number,
	reach: number,
	slamAt: number,
	returning: boolean,
	stuckCheck: number,
	stuckPos: Vector3,
}

local mobs: { [Mob]: boolean } = {}
local spawners: { Spawner } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function randomPoint(region: Region): Vector3
	if region.kind == "circle" then
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * region.radius
		return region.center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	return Vector3.new(rng:NextNumber(region.minX, region.maxX), 0, rng:NextNumber(region.minZ, region.maxZ))
end

local function inRegion(region: Region, pos: Vector3, margin: number): boolean
	if region.kind == "circle" then
		local d = Vector3.new(pos.X - region.center.X, 0, pos.Z - region.center.Z).Magnitude
		return d <= region.radius + margin and math.abs(pos.Y - region.center.Y) < 60
	end
	return pos.X >= region.minX - margin and pos.X <= region.maxX + margin and pos.Z >= region.minZ - margin and pos.Z <= region.maxZ + margin
end

local function groundY(pos: Vector3): number
	local result = workspace:Raycast(Vector3.new(pos.X, pos.Y + 120, pos.Z), Vector3.new(0, -300, 0), rayParams)
	return result and result.Position.Y or pos.Y
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Coins for one normal kill in a zone (used by rewards and the coin pack)
function MobService.CoinValue(zone: number): number
	return Items.CoinValue(zone)
end

local function updateBar(mob: Mob)
	local ratio = math.clamp(mob.hp / mob.maxHp, 0, 1)
	mob.fill.Size = UDim2.new(ratio, 0, 1, 0)
end

local function playerRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then
		return nil, nil
	end
	return root, hum
end

local function eligible(mob: Mob, player: Player): (boolean, BasePart?)
	local root = playerRoot(player)
	if not root then
		return false, nil
	end
	local spawner = mob.spawner
	if spawner.owner then
		if spawner.owner ~= player then
			return false, nil
		end
	elseif (player:GetAttribute("RiftZone") or 0) > 0 then
		return false, nil
	end
	local pos = root.Position
	if spawner.region.kind == "rect" and Util.ZoneAtX(pos.X) ~= mob.zone then
		return false, nil
	end
	if not inRegion(spawner.region, pos, 30) then
		return false, nil
	end
	return true, root
end

--------------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------------
local function spawnMob(spawner: Spawner, entry: Entry): Mob?
	local def = Config.Mobs[entry.mobId]
	if not def then
		warn("[Mobs] Unknown mob id " .. tostring(entry.mobId))
		return nil
	end
	local tc = Config.MobTiers[entry.tier]
	local scale = tc.size * (def.scale or 1)
	local model, root, hum, height = Models.Mob(def, entry.tier, scale)

	local point = randomPoint(spawner.region)
	local y = spawner.region.kind == "circle" and spawner.region.center.Y or groundY(Vector3.new(point.X, 0, point.Z))
	local home = Vector3.new(point.X, y, point.Z)
	model:PivotTo(CFrame.new(home + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.3, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))

	local rec = Items.Rec(spawner.zone)
	local diff = Items.Difficulty(spawner.zone)
	local maxHp = rec * tc.hp * diff.hp
	local titleColor = entry.tier == "boss" and Color3.fromRGB(255, 90, 90) or (entry.tier == "elite" and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(255, 255, 255))
	local prefix = entry.tier == "boss" and "☠ " or (entry.tier == "elite" and "★ " or "")
	local title = prefix .. (entry.tier == "boss" and string.upper(def.name) or def.name) .. "  ⚡" .. Util.Abbrev(rec)
	local fill = Models.HealthBar(model, root, height - (hum.HipHeight + root.Size.Y / 2) + 1.5, title, titleColor, entry.tier == "boss")

	model:SetAttribute("MobId", entry.mobId)
	model:SetAttribute("Tier", entry.tier)
	model:SetAttribute("Zone", spawner.zone)
	model:SetAttribute("Arch", def.arch)
	model.Parent = mobFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, "Mob")

	local mob: Mob = {
		model = model,
		root = root,
		hum = hum,
		def = def,
		mobId = entry.mobId,
		tier = entry.tier,
		tc = tc,
		zone = spawner.zone,
		maxHp = maxHp,
		hp = maxHp,
		home = home,
		spawner = spawner,
		entry = entry,
		target = nil,
		speed = (def.speed or 12) * diff.speed,
		aggro = tc.aggro + diff.aggro,
		cooldown = tc.cooldown * diff.cooldown,
		dmg = tc.dmg * diff.dmg,
		lastAttack = 0,
		nextWander = os.clock() + rng:NextNumber(1, 4),
		damageBy = {},
		stunUntil = 0,
		dead = false,
		fill = fill,
		height = height,
		reach = tc.range + root.Size.Z * 0.5,
		slamAt = os.clock() + 4,
		returning = false,
		stuckCheck = os.clock(),
		stuckPos = home,
	}
	mobs[mob] = true
	spawner.mobs[mob] = true
	entry.alive += 1

	if entry.tier == "boss" and not spawner.owner then
		S.Player.NotifyAll("☠ " .. string.upper(def.name) .. " has appeared in the " .. Items.ZoneName(spawner.zone) .. "!", "boss")
	end
	return mob
end

local function despawn(mob: Mob)
	mobs[mob] = nil
	mob.spawner.mobs[mob] = nil
	if not mob.dead then
		mob.dead = true
		mob.entry.alive -= 1
	end
	mob.model:Destroy()
end

function MobService.CreateSpawner(opts: any): Spawner
	local entries = {}
	for _, e in opts.entries do
		table.insert(entries, { mobId = e.mobId, tier = e.tier, count = e.count, respawn = e.respawn or 5, first = e.first, alive = 0, nextSpawn = 0 })
	end
	local spawner: Spawner = {
		zone = opts.zone,
		region = opts.region,
		entries = entries,
		active = opts.wave == true,
		lastSeen = os.clock(),
		owner = opts.owner,
		wave = opts.wave == true,
		onDeath = opts.onDeath,
		mobs = {},
		removed = false,
		activated = false,
	}
	table.insert(spawners, spawner)
	if spawner.wave then
		for _, entry in spawner.entries do
			for _ = 1, entry.count do
				spawnMob(spawner, entry)
			end
		end
	end
	return spawner
end

function MobService.RemoveSpawner(spawner: Spawner)
	spawner.removed = true
	for mob in spawner.mobs do
		despawn(mob)
	end
	local index = table.find(spawners, spawner)
	if index then
		table.remove(spawners, index)
	end
end

function MobService.AliveCount(spawner: Spawner): number
	local n = 0
	for mob in spawner.mobs do
		if not mob.dead then
			n += 1
		end
	end
	return n
end

local function updateSpawner(spawner: Spawner, now: number)
	if spawner.wave or spawner.removed then
		return
	end
	local region = spawner.region
	local anyone = false
	for _, player in Players:GetPlayers() do
		local root = playerRoot(player)
		if root and (player:GetAttribute("RiftZone") or 0) == 0 then
			local x = root.Position.X
			if x >= region.minX - 70 and x <= region.maxX + 70 then
				anyone = true
				break
			end
		end
	end
	if anyone then
		spawner.lastSeen = now
		if not spawner.activated then
			spawner.activated = true
			for _, entry in spawner.entries do
				if entry.first then
					entry.nextSpawn = math.max(entry.nextSpawn, now + entry.first)
				end
			end
		end
		for _, entry in spawner.entries do
			if entry.alive < entry.count and now >= entry.nextSpawn then
				spawnMob(spawner, entry)
				entry.nextSpawn = now + 0.35
			end
		end
	elseif now - spawner.lastSeen > 45 and next(spawner.mobs) then
		for mob in spawner.mobs do
			if mob.tier == "boss" then
				mob.entry.nextSpawn = now + (mob.entry.first or 30)
			end
			despawn(mob)
		end
		spawner.activated = false
	end
end

--------------------------------------------------------------------------------
-- AI
--------------------------------------------------------------------------------
local function faceTowards(mob: Mob, pos: Vector3)
	local rootPos = mob.root.Position
	local look = Vector3.new(pos.X, rootPos.Y, pos.Z)
	if (look - rootPos).Magnitude > 0.1 then
		mob.root.CFrame = CFrame.lookAt(rootPos, look)
	end
end

local function attack(mob: Mob, target: Player)
	mob.lastAttack = os.clock()
	FX:FireAllClients("mobAttack", { model = mob.model })
	task.delay(0.25, function()
		if mob.dead then
			return
		end
		local root = playerRoot(target)
		if root and flatDist(root.Position, mob.root.Position) <= mob.reach + 2.5 then
			S.Player.DamageFromMob(target, mob.zone, mob.dmg)
		end
	end)
end

local function slam(mob: Mob)
	local slamCfg = mob.tc.slam
	if not slamCfg then
		return
	end
	local center = mob.root.Position - Vector3.new(0, mob.hum.HipHeight + mob.root.Size.Y / 2, 0)
	FX:FireAllClients("slam", { pos = center, radius = slamCfg.radius, delay = slamCfg.delay, color = mob.def.color2 or mob.def.color })
	task.delay(slamCfg.delay, function()
		if mob.dead then
			return
		end
		for _, player in Players:GetPlayers() do
			local ok, root = eligible(mob, player)
			if ok and root and flatDist(root.Position, center) <= slamCfg.radius then
				S.Player.DamageFromMob(player, mob.zone, slamCfg.dmg * (mob.dmg / mob.tc.dmg))
			end
		end
	end)
end

local function resetMob(mob: Mob)
	mob.target = nil
	mob.returning = true
	mob.hp = mob.maxHp
	table.clear(mob.damageBy)
	updateBar(mob)
end

local function think(mob: Mob, now: number)
	local root, hum = mob.root, mob.hum
	local pos = root.Position
	if pos.Y < -80 then
		mob.model:PivotTo(CFrame.new(mob.home + Vector3.new(0, 6, 0)))
		resetMob(mob)
		return
	end
	if mob.stunUntil > now then
		hum:MoveTo(pos)
		return
	end

	-- keep or drop the current target
	local target = mob.target
	local targetRoot: BasePart? = nil
	if target then
		local ok, r = eligible(mob, target)
		if ok and r and flatDist(r.Position, mob.home) < mob.aggro + 70 and flatDist(r.Position, pos) < mob.aggro * 2.5 then
			targetRoot = r
		else
			resetMob(mob)
			target = nil
		end
	end
	if not target and not mob.returning then
		local best, bestDist = nil, mob.aggro
		for _, player in Players:GetPlayers() do
			local ok, r = eligible(mob, player)
			if ok and r then
				local d = flatDist(r.Position, pos)
				if d < bestDist then
					best, bestDist, targetRoot = player, d, r
				end
			end
		end
		if best then
			mob.target = best
			target = best
		end
	end

	-- mobs sprint while chasing, so nobody can outrun them forever
	local speed = target and math.min(mob.speed * (mob.tc.chase or 1.5), Config.Difficulty.MaxChaseSpeed) or mob.speed
	if hum.WalkSpeed ~= speed then
		hum.WalkSpeed = speed
	end

	if target and targetRoot then
		local tpos = targetRoot.Position
		local d = flatDist(tpos, pos)
		if d > mob.reach then
			hum:MoveTo(tpos)
			if now - mob.stuckCheck > 2 then
				if (pos - mob.stuckPos).Magnitude < 1 then
					local dir = Util.FlatUnit(tpos - pos)
					mob.model:PivotTo(root.CFrame + dir * 4 + Vector3.new(0, 1, 0))
				end
				mob.stuckCheck = now
				mob.stuckPos = pos
			end
		else
			hum:MoveTo(pos)
			faceTowards(mob, tpos)
			if now - mob.lastAttack >= mob.cooldown then
				attack(mob, target)
			end
		end
		if mob.tier == "boss" and now >= mob.slamAt then
			mob.slamAt = now + mob.tc.slam.every
			slam(mob)
		end
		return
	end

	-- no target: go home or wander
	if mob.returning then
		if flatDist(pos, mob.home) > 6 then
			hum:MoveTo(mob.home)
		else
			mob.returning = false
		end
		return
	end
	if now >= mob.nextWander then
		mob.nextWander = now + rng:NextNumber(3, 7)
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber(4, 16)
		local goal = mob.home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if inRegion(mob.spawner.region, goal, 0) then
			hum:MoveTo(goal)
		end
	end
end

--------------------------------------------------------------------------------
-- Damage & death
--------------------------------------------------------------------------------
function MobService.IsAlive(mob: Mob): boolean
	return mobs[mob] == true and not mob.dead
end

function MobService.GetMobsNear(pos: Vector3, radius: number): { Mob }
	local list = {}
	for mob in mobs do
		if not mob.dead and (mob.root.Position - pos).Magnitude <= radius + mob.root.Size.Z * 0.5 then
			table.insert(list, mob)
		end
	end
	return list
end

function MobService.FromModel(model: Instance): Mob?
	for mob in mobs do
		if mob.model == model then
			return mob
		end
	end
	return nil
end

local function reward(player: Player, mob: Mob)
	local data = S.Data.Get(player)
	local stats = S.Player.GetStats(player)
	if not data or not stats then
		return
	end
	local coins = math.max(1, math.floor(MobService.CoinValue(mob.zone) * mob.tc.coins * stats.coinMult + 0.5))
	S.Player.AddCoins(player, coins)
	S.Player.AddFragments(player, mob.tc.frags)
	data.forgeZone = math.clamp(mob.zone, 1, #Config.Zones) -- Rift fragments forge Void Cores
	data.stats.kills += 1
	if mob.tier == "boss" then
		data.stats.bosses += 1
	end
	if mob.tier == "boss" or data.stats.kills % 250 == 0 then
		S.Badges.Check(player) -- Boss Down / kill-count badges
	end
	FX:FireClient(player, "reward", { pos = mob.root.Position + Vector3.new(0, mob.height * 0.5, 0), coins = coins, frags = mob.tc.frags })
	S.Cores.TryDrop(player, mob)
end

function MobService.Kill(mob: Mob, killer: Player?)
	if mob.dead then
		return
	end
	mob.dead = true
	mob.entry.alive -= 1
	mob.entry.nextSpawn = math.max(mob.entry.nextSpawn, os.clock() + mob.entry.respawn)
	mobs[mob] = nil
	mob.model:SetAttribute("Dead", true)
	FX:FireAllClients("mobDie", { pos = mob.root.Position, color = mob.def.color, color2 = mob.def.color2 or mob.def.color, size = mob.height })

	local share = mob.maxHp * Config.Combat.RewardShare
	for player, dealt in mob.damageBy do
		if player.Parent and (dealt >= share or player == killer) then
			local ok, err = pcall(reward, player, mob)
			if not ok then
				warn("[Mobs] reward failed: " .. tostring(err))
			end
		end
	end

	local spawner = mob.spawner
	spawner.mobs[mob] = nil
	if spawner.onDeath then
		task.spawn(spawner.onDeath, mob, killer)
	end
	task.delay(0.1, function()
		mob.model:Destroy()
	end)
end

-- Returns the damage actually applied
function MobService.Damage(mob: Mob, amount: number, player: Player): number
	if mob.dead or amount ~= amount or amount <= 0 then
		return 0
	end
	local dealt = math.min(amount, mob.hp)
	mob.hp -= amount
	mob.damageBy[player] = (mob.damageBy[player] or 0) + dealt
	if not mob.target and eligible(mob, player) then
		mob.target = player
		mob.returning = false
	end
	updateBar(mob)
	if mob.hp <= 0 then
		MobService.Kill(mob, player)
	end
	return dealt
end

function MobService.Stun(mob: Mob, duration: number)
	if mob.dead then
		return
	end
	mob.stunUntil = os.clock() + duration
	mob.model:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + duration)
end

-- Admin helper: spawn the boss of a zone right now
function MobService.SpawnBoss(zone: number): boolean
	for _, spawner in spawners do
		if spawner.zone == zone and not spawner.owner then
			for _, entry in spawner.entries do
				if entry.tier == "boss" then
					if entry.alive >= entry.count then
						return false
					end
					spawnMob(spawner, entry)
					return true
				end
			end
		end
	end
	return false
end

function MobService.Init(services: any)
	S = services
	FX = Net.Event("FX")
end

function MobService.Start()
	mobFolder = Instance.new("Folder")
	mobFolder.Name = "Mobs"
	mobFolder.Parent = workspace
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { mobFolder }
	rayParams.CollisionGroup = "Mobs"
	rayParams.IgnoreWater = true

	local W = Config.World
	local lane = W.MobLaneHalfWidth
	for i, zone in Config.Zones do
		local normalCount = Config.MobTiers.normal.count
		local perType = math.ceil(normalCount / #zone.mobs)
		local entries = {}
		for _, mobId in zone.mobs do
			table.insert(entries, { mobId = mobId, tier = "normal", count = perType, respawn = Config.MobTiers.normal.respawn })
		end
		table.insert(entries, { mobId = zone.elite, tier = "elite", count = Config.MobTiers.elite.count, respawn = Config.MobTiers.elite.respawn })
		table.insert(entries, { mobId = zone.boss, tier = "boss", count = Config.MobTiers.boss.count, respawn = Config.MobTiers.boss.respawn, first = Config.MobTiers.boss.firstSpawn })
		MobService.CreateSpawner({
			zone = i,
			region = {
				kind = "rect",
				minX = Util.ZoneStartX(i) + 18,
				maxX = Util.ZoneEndX(i) - 18,
				minZ = -lane,
				maxZ = lane,
				center = Vector3.zero,
				radius = 0,
			},
			entries = entries,
		})
	end

	-- spawners: twice a second
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, spawner in table.clone(spawners) do
				local ok, err = pcall(updateSpawner, spawner, now)
				if not ok then
					warn("[Mobs] spawner error: " .. tostring(err))
				end
			end
		end
	end)

	-- AI: five times a second
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for mob in mobs do
				if not mob.dead then
					local ok, err = pcall(think, mob, now)
					if not ok then
						warn("[Mobs] AI error: " .. tostring(err))
					end
				end
			end
		end
	end)
end

return MobService
