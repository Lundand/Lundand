--[[
	CombatService — server-validated attacks and abilities.
	Damage per hit = Power * style.dps / style.rate * class multipliers, so every weapon
	style has roughly the same DPS; styles differ in reach, arc and area.
	Abilities scale with Power too (dmg values in Config.Abilities are multiples of Power).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))

local CombatService = {}
local S: any
local FX: RemoteEvent

local rng = Random.new()
local lastAttack: { [Player]: number } = {}
local abilityReady: { [Player]: number } = {}

type Hit = { pos: Vector3, amount: number, crit: boolean }

local function fighter(player: Player): (Model?, Humanoid?, BasePart?, any)
	local character, hum, root = S.Player.GetCharacter(player)
	if not character or not hum or not root or hum.Health <= 0 then
		return nil, nil, nil, nil
	end
	if character:GetAttribute("Stunned") then
		return nil, nil, nil, nil
	end
	local stats = S.Player.GetStats(player)
	if not stats then
		return nil, nil, nil, nil
	end
	return character, hum, root, stats
end

-- Rolls crit/backstab and applies damage to one mob. Returns applied damage.
local function hitMob(player: Player, stats: any, mob: any, amount: number, origin: Vector3, hits: { Hit }): number
	local crit = rng:NextNumber() < stats.crit
	if crit then
		amount *= Config.Combat.CritMult
	end
	if stats.backstab > 0 then
		local toPlayer = Util.FlatUnit(origin - mob.root.Position)
		if mob.root.CFrame.LookVector:Dot(toPlayer) < -0.3 then
			amount *= 1 + stats.backstab
		end
	end
	local pos = mob.root.Position + Vector3.new(0, mob.height * 0.35, 0)
	local dealt = S.Mobs.Damage(mob, amount, player)
	if dealt > 0 then
		table.insert(hits, { pos = pos, amount = amount, crit = crit })
	end
	return dealt
end

local function sendHits(hits: { Hit })
	if #hits > 0 then
		FX:FireAllClients("hits", { list = hits })
	end
end

local function damageArea(player: Player, stats: any, center: Vector3, radius: number, amount: number): number
	local hits = {}
	local count = 0
	for _, mob in S.Mobs.GetMobsNear(center, radius) do
		if S.Mobs.IsAlive(mob) then
			hitMob(player, stats, mob, amount, center, hits)
			count += 1
		end
	end
	sendHits(hits)
	return count
end

-- Best mob near a point, or along the aim line
local function pickTarget(origin: Vector3, aimPoint: Vector3, range: number): any
	local best, bestScore = nil, math.huge
	local dir = aimPoint - origin
	local dirUnit = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
	for _, mob in S.Mobs.GetMobsNear(origin, range + 4) do
		local to = mob.root.Position - origin
		local along = to:Dot(dirUnit)
		if along > -2 then
			local perp = (to - dirUnit * along).Magnitude
			local nearPoint = (mob.root.Position - aimPoint).Magnitude
			local score = math.min(perp * 3 + along * 0.2, nearPoint)
			if (perp < 6 + mob.root.Size.Z * 0.5 or nearPoint < 10) and score < bestScore then
				best, bestScore = mob, score
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Basic attack
--------------------------------------------------------------------------------
local function onAttack(player: Player, aim: any)
	if not Util.IsFiniteVector(aim) then
		return
	end
	local _, hum, root, stats = fighter(player)
	if not hum or not root then
		return
	end
	if S.Cores.GetCarry(player) then
		return -- hands are full
	end
	local style = stats.style
	local now = os.clock()
	if now - (lastAttack[player] or 0) < (1 / style.rate) * 0.8 then
		return
	end
	lastAttack[player] = now

	local origin = root.Position
	local aimVec = aim :: Vector3
	local flatDir = Util.FlatUnit(aimVec)
	local kindMult = style.kind == "melee" and stats.melee or stats.ranged
	local base = stats.power * style.dps / style.rate * stats.dmg * kindMult * S.Player.DamageBuff(player)
	local hits: { Hit } = {}
	local targetPos: Vector3? = nil
	local landed = false

	if style.kind == "melee" then
		local cosHalf = math.cos(math.rad(style.arc / 2))
		for _, mob in S.Mobs.GetMobsNear(origin, style.range + 3) do
			local to = mob.root.Position - origin
			local flatTo = Vector3.new(to.X, 0, to.Z)
			if style.arc >= 360 or flatTo.Magnitude < 3 or Util.FlatUnit(to):Dot(flatDir) >= cosHalf then
				if hitMob(player, stats, mob, base, origin, hits) > 0 then
					landed = true
				end
			end
		end
	else
		local aimUnit = aimVec.Magnitude > 0.01 and aimVec.Unit or flatDir
		local target = pickTarget(origin, origin + aimUnit * style.range, style.range)
		if target then
			targetPos = target.root.Position
			if style.splash then
				for _, mob in S.Mobs.GetMobsNear(target.root.Position, style.splash) do
					if hitMob(player, stats, mob, base, origin, hits) > 0 then
						landed = true
					end
				end
			elseif hitMob(player, stats, target, base, origin, hits) > 0 then
				landed = true
			end
		else
			targetPos = origin + aimUnit * style.range
		end
	end

	if style.kind == "ranged" then
		S.Player.SetAimSlow(player)
	end
	FX:FireAllClients("swing", { player = player, style = stats.styleName, dir = flatDir, target = targetPos, rarity = 0 })
	sendHits(hits)
	if landed and stats.lifesteal > 0 then
		S.Player.Heal(player, stats.lifesteal / style.rate)
	end
end

--------------------------------------------------------------------------------
-- Abilities
--------------------------------------------------------------------------------
local function onAbility(player: Player, aimPos: any, startPos: any)
	local _, hum, root, stats = fighter(player)
	if not hum or not root then
		return
	end
	local def = stats.abilityDef
	local now = os.clock()
	if now < (abilityReady[player] or 0) - 0.2 then
		return
	end
	local kind: string = def.kind
	if Items.MovementAbility[kind] and S.Cores.GetCarry(player) then
		S.Player.Notify(player, "Movement abilities are disabled while carrying a Core!", "error")
		return
	end
	abilityReady[player] = now + Items.AbilityCooldown(stats.abilityKey)

	local origin = root.Position
	-- movement abilities move the player on their own screen first, so they report where they started
	if Items.MovementAbility[kind] and Util.IsFiniteVector(startPos) and ((startPos :: Vector3) - origin).Magnitude <= (def.range or 60) + 15 then
		origin = startPos :: Vector3
	end
	local range = def.range or 40
	local target: Vector3
	if Util.IsFiniteVector(aimPos) and ((aimPos :: Vector3) - origin).Magnitude <= range + 20 then
		target = aimPos :: Vector3
	else
		target = origin + root.CFrame.LookVector * math.min(range, 30)
	end
	local power = stats.power * stats.dmg * stats.ability * S.Player.DamageBuff(player)
	local color = def.color
	local fx = { player = player, kind = kind, id = stats.abilityId, from = origin, to = target, radius = def.radius, color = color, dur = def.dur, delay = def.delay }

	if kind == "dash" then
		FX:FireAllClients("ability", fx)
	elseif kind == "shadowstep" then
		local mob = pickTarget(origin, target, range)
		if mob then
			fx.to = mob.root.Position
			local hits = {}
			hitMob(player, stats, mob, power * (def.dmg or 3), origin, hits)
			sendHits(hits)
		end
		FX:FireAllClients("ability", fx)
	elseif kind == "warp" then
		local offset = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
		if offset.Magnitude > range then
			offset = offset.Unit * range
		end
		local dest = origin + offset
		fx.to = dest
		FX:FireAllClients("ability", fx)
		damageArea(player, stats, origin, def.radius or 12, power * (def.dmg or 4))
		task.delay(0.12, function()
			damageArea(player, stats, dest, def.radius or 12, power * (def.dmg or 4))
		end)
	elseif kind == "bolt" then
		local mob = pickTarget(origin, target, range)
		local impact = mob and mob.root.Position or target
		fx.to = impact
		FX:FireAllClients("ability", fx)
		local travel = math.clamp((impact - origin).Magnitude / 120, 0.08, 0.6)
		task.delay(travel, function()
			damageArea(player, stats, impact, def.radius, power * def.dmg)
		end)
	elseif kind == "nova" then
		FX:FireAllClients("ability", fx)
		damageArea(player, stats, origin, def.radius, power * def.dmg)
	elseif kind == "meteor" then
		local mob = pickTarget(origin, target, range)
		local impact = mob and mob.root.Position or target
		fx.to = impact
		FX:FireAllClients("ability", fx)
		task.delay(def.delay or 0.8, function()
			damageArea(player, stats, impact, def.radius, power * def.dmg)
		end)
	elseif kind == "strike" or kind == "drain" then
		local mob = pickTarget(origin, target, range)
		if mob then
			fx.to = mob.root.Position
			local hits = {}
			hitMob(player, stats, mob, power * def.dmg, origin, hits)
			sendHits(hits)
			if kind == "drain" then
				S.Player.Heal(player, def.heal or 0.1)
			end
		end
		FX:FireAllClients("ability", fx)
	elseif kind == "stun" then
		FX:FireAllClients("ability", fx)
		for _, mob in S.Mobs.GetMobsNear(origin, def.radius) do
			S.Mobs.Stun(mob, def.dur or 2)
		end
		damageArea(player, stats, origin, def.radius, power * (def.dmg or 0))
	elseif kind == "dot" then
		fx.dur = def.ticks or 5
		FX:FireAllClients("ability", fx)
		for tick = 1, def.ticks or 5 do
			task.delay(tick - 0.5, function()
				local _, _, r = S.Player.GetCharacter(player)
				if r then
					damageArea(player, stats, r.Position, def.radius, power * def.dmg)
				end
			end)
		end
	elseif kind == "heal" then
		S.Player.Heal(player, def.heal or 0.3)
		FX:FireAllClients("ability", fx)
	elseif kind == "buff" then
		S.Player.SetDamageBuff(player, def.mult or 1.5, def.dur or 8)
		FX:FireAllClients("ability", fx)
	elseif kind == "shield" then
		S.Player.SetShield(player, def.reduce or 0.5, def.dur or 8)
		FX:FireAllClients("ability", fx)
	end
end

function CombatService.ResetCooldowns(player: Player)
	abilityReady[player] = 0
	lastAttack[player] = 0
end

function CombatService.Init(services: any)
	S = services
	FX = Net.Event("FX")
end

function CombatService.Start()
	Net.Event("Attack").OnServerEvent:Connect(function(player: Player, aim: any)
		local ok, err = pcall(onAttack, player, aim)
		if not ok then
			warn("[Combat] attack error: " .. tostring(err))
		end
	end)
	Net.Event("Ability").OnServerEvent:Connect(function(player: Player, aimPos: any, startPos: any)
		local ok, err = pcall(onAbility, player, aimPos, startPos)
		if not ok then
			warn("[Combat] ability error: " .. tostring(err))
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastAttack[player] = nil
		abilityReady[player] = nil
	end)
end

return CombatService
