--!strict
-- Combat on the server (L-03, M3). Players ask to attack, parry or dodge; the server checks timing, weapon,
-- learned techniques and reach, applies damage, gives kill credit (XP, quest kills, mastery) and tells every
-- client which animation to play. Enemies strike through enemyStrike, which players can dodge or parry.
-- Also sets the third-person camera range (L-06) and puts the equipped weapon in the character's hand.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = script.Parent.Parent
local Content = require(Shared.Content)
local CharacterProgression = require(Shared.Domain.CharacterProgression)
local CombatRules = require(Server.Domain.CombatRules)
local AbilityRules = require(Shared.Domain.AbilityRules)
local HitShapes = require(Shared.Domain.HitShapes)
local CrowdControl = require(Shared.Domain.CrowdControl)
local ItemStats = require(Shared.Domain.ItemStats)
local EnemyScaling = require(Shared.Domain.EnemyScaling)
local Resources = require(Shared.Config.Resources)
local Remotes = require(Server.Net.Remotes)
local RateLimiter = require(Server.Net.RateLimiter)
local Models = require(Server.Tools.Models)

-- A character's derived stats including their equipment's percentage bonuses (S2: weapon and armour secondary stats).
local function playerStats(character: any): any
	return CharacterProgression.derivedStats(character.level, Content.stats, ItemStats.equipmentBonuses(character.equipment, Content.items, Content.gear))
end

local function mainHandDef(character: any): any
	local entry = character and character.equipment.MainHand
	return entry and Content.items[entry.itemId]
end

-- How fast this character's weapon attacks swing (S1): the weapon subtype's speed times the character's attack speed
-- (Agility and equipment bonuses). Windup and recovery are divided by it.
local function attackSpeedOf(character: any): number
	return ItemStats.handling(mainHandDef(character), Content.gear).speed * (playerStats(character).attackSpeed or 1)
end

-- A named weapon's trait (S3), built only from hit effects the game already has. trait.on is an attack id ("Combo3",
-- "Heavy"...), "Basic" for class basic attacks, or "Hit" for every weapon attack; trait.chance (optional) is rolled per
-- attack. Returns the attack, or a copy carrying the trait's effects.
local function withTrait(character: any, attackId: string, attack: any): any
	local def = mainHandDef(character)
	local trait = def and def.trait
	if trait == nil or (trait.on ~= "Hit" and trait.on ~= attackId) then
		return attack
	end
	if trait.chance ~= nil and math.random() >= trait.chance then
		return attack
	end
	local copy = table.clone(attack)
	if trait.staggers then
		copy.staggers = true
	end
	copy.mark = trait.mark or copy.mark
	copy.lifesteal = trait.lifesteal or copy.lifesteal
	copy.splash = trait.splash or copy.splash
	if trait.pierce then
		copy.pierce = true
	end
	return copy
end

local CombatService = {}
local services: any = nil
local states: {[any]: any} = {}
local limiter = RateLimiter.new(12, 8, os.clock)

function CombatService.init(allServices: any)
	services = allServices
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flat(vector: Vector3): any
	return { x = vector.X, z = vector.Z }
end

local function rootOf(model: Instance?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

function CombatService.stateFor(key: any): any
	local state = states[key]
	if state == nil then
		state = CombatRules.newState()
		states[key] = state
	end
	return state
end

function CombatService.forget(key: any)
	states[key] = nil
end

-- Plays an animation for everyone; `except` skips the player whose client already played it (prediction).
function CombatService.broadcast(actor: Model, animation: string, extra: any?, except: Player?)
	for _, viewer in ipairs(Players:GetPlayers()) do
		if viewer ~= except then
			Remotes.get("CombatEvent"):FireClient(viewer, actor, animation, extra)
		end
	end
end

-- attacker: who landed it, so their client can add hitstop and shake.
function CombatService.hitFeedback(target: Model, amount: number, result: string, attacker: Model?)
	Remotes.get("CombatHit"):FireAllClients(target, amount, result, attacker)
end

local function equippedWeapon(character: any): any
	local weapon = character.equipment.MainHand
	return weapon and Content.items[weapon.itemId]
end

-- The discipline this player fights with: the one their class taught them for the weapon in hand.
local function playerDiscipline(player: Player): (string?, any, any)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil or character.class.classId == nil then
		return nil, nil, character
	end
	local weapon = equippedWeapon(character)
	local weaponType = weapon and weapon.equipment and weapon.equipment.weaponType
	for disciplineId, discipline in pairs(Content.combat.disciplines) do
		if character.disciplines[disciplineId] ~= nil and discipline.weaponType == weaponType then
			return disciplineId, discipline, character
		end
	end
	return nil, nil, character
end

-- The equipped weapon's attack power for its item level and rarity (owner's equipment specification).
local function weaponPower(character: any): number
	local entry = character.equipment.MainHand
	local def = entry and Content.items[entry.itemId]
	if def == nil then
		return Content.combat.unarmedAttackPower
	end
	return ItemStats.compute(def, entry, Content.gear).attackPower or Content.combat.unarmedAttackPower
end

-- Worn armour's defence reduces damage taken, with diminishing returns; shields only protect while blocking.
local function armorReduction(player: Player): number
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return 0
	end
	local defense = 0
	for _, entry in pairs(character.equipment) do
		local def = entry and Content.items[entry.itemId]
		if def ~= nil and def.equipment ~= nil and def.equipment.weaponType ~= "Shield" then
			defense += ItemStats.compute(def, entry, Content.gear).defense or 0
		end
	end
	return math.min(Content.gear.armor.cap, defense / (defense + Content.gear.armor.constant))
end

-- Crowd control with diminishing returns (class specification: never permanent, bosses included). Pulls move an
-- enemy toward the centre of the effect; slows and roots last as long as diminishing returns allow.
local function applyControl(enemy: Model, control: any, center: Vector3, now: number)
	if control.kind == "pull" then
		services.EnemyService.pull(enemy, center, control.distance)
		return
	end
	local state = CombatService.stateFor(enemy)
	state.controlRecord = state.controlRecord or {}
	local seconds = CrowdControl.apply(state.controlRecord, control.seconds or 0, now, Content.combat.crowdControl)
	if seconds > 0 then
		services.EnemyService.control(enemy, control.kind, control.amount or 1, seconds)
	end
end

-- Resolves one hit of an attack or ability. hit.shape: "arc" (default, melee), "line" (a projectile along the aim,
-- first enemy only unless it pierces) or "area" (at `center`, or the aimed point kept within reach). `aim` is only
-- a request from the client: it sets a direction, never a position beyond the ability's reach.
-- Heals one player (never above max health) and shows the number.
local function healPlayer(target: Player, amount: number, source: Player)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health > 0 then
		local healed = math.floor(math.min(amount, humanoid.MaxHealth - humanoid.Health))
		if healed >= 1 then
			humanoid.Health += healed
			CombatService.hitFeedback(target.Character, healed, "Healed", source.Character)
		end
	end
end

local function resolvePlayerHit(player: Player, disciplineId: string?, attack: any, aim: Vector3?, center: Vector3?)
	local model = player.Character
	local root = rootOf(model)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local character = services.PlayerDataService.getCharacter(player)
	if root == nil or humanoid == nil or humanoid.Health <= 0 or character == nil then
		return
	end
	CombatService.stateFor(player).concealedUntil = 0 -- attacking ends Veil
	local weapon = equippedWeapon(character)
	local power = weaponPower(character)
	local stats = playerStats(character)
	local classDef = character.class.classId and Content.classes[character.class.classId]
	local scale = if attack.damageType == "Magic" then stats.magicPower else stats.physicalDamage
	scale *= (classDef and classDef.traits and classDef.traits.damageMultiplier) or 1
	local amount = CombatRules.damage(power, attack.multiplier, scale)
	-- weapon handling (S1): physical attacks deal the subtype's damage share; melee arcs reach as far as the weapon does
	if attack.damageType ~= "Magic" then
		local handling = ItemStats.handling(weapon, Content.gear)
		amount = math.max(1, math.floor(amount * handling.damage + 0.5))
		if (attack.shape or "arc") == "arc" and handling.reach ~= 1 then
			attack = table.clone(attack)
			attack.range = (attack.range or 8) * handling.reach
		end
	end
	local shape = attack.shape or "arc"
	local origin = root.Position
	local look = root.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z).Unit
	if aim ~= nil then
		local toward = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
		if toward.Magnitude > 0.1 then
			direction = toward.Unit
		end
	end
	if attack.spread ~= nil then
		direction = CFrame.Angles(0, math.rad(attack.spread), 0):VectorToWorldSpace(direction)
	end
	local searchCenter, searchRadius = origin, (attack.range or 8) + 10
	if shape == "area" then
		center = center or HitShapes.clampTarget(origin, aim or (origin + direction * attack.maxRange), attack.maxRange)
		searchCenter, searchRadius = center :: Vector3, attack.radius + 10
	end
	local hits = {}
	for _, enemy in ipairs(services.EnemyService.enemiesNear(searchCenter, searchRadius)) do
		local enemyRoot = rootOf(enemy)
		if enemyRoot ~= nil and services.EnemyService.canBeHitBy(enemy, player) and shape ~= "chain" then
			if shape == "line" then
				local onLine, along = HitShapes.line(origin, direction, enemyRoot.Position, attack.range, attack.radius)
				if onLine then
					table.insert(hits, { enemy = enemy, root = enemyRoot, delay = along / (attack.speed or 80), along = along })
				end
			elseif shape == "area" then
				if HitShapes.area(center :: Vector3, enemyRoot.Position, attack.radius) then
					table.insert(hits, { enemy = enemy, root = enemyRoot, delay = 0, along = 0 })
				end
			elseif HitShapes.arc(origin, look, enemyRoot.Position, attack.range, attack.arc, Content.combat.hitLeniencyStuds) then
				table.insert(hits, { enemy = enemy, root = enemyRoot, delay = 0, along = 0 })
			end
		end
	end
	if shape == "line" and not attack.pierce and #hits > 1 then
		table.sort(hits, function(a, b)
			return a.along < b.along
		end)
		hits = { hits[1] }
	end
	-- Chain lightning: the nearest enemy along the aim, then jumps to the nearest enemy not yet struck, losing
	-- strength with each jump, up to the ability's number of jumps.
	if shape == "chain" then
		local candidates = services.EnemyService.enemiesNear(origin, attack.range + attack.jumps * attack.jumpRange)
		local current, firstAlong = nil, math.huge
		for _, enemy in ipairs(candidates) do
			local enemyRoot = rootOf(enemy)
			if enemyRoot ~= nil and services.EnemyService.canBeHitBy(enemy, player) then
				local onLine, along = HitShapes.line(origin, direction, enemyRoot.Position, attack.range, attack.radius)
				if onLine and along < firstAlong then
					current, firstAlong = enemy, along
				end
			end
		end
		local used, scale = {}, 1
		while current ~= nil and #hits <= attack.jumps do
			used[current] = true
			local currentRoot = rootOf(current) :: BasePart
			table.insert(hits, { enemy = current, root = currentRoot, delay = #hits * 0.08, along = 0, scale = scale })
			scale *= attack.falloff
			local nextEnemy, nextDistance = nil, attack.jumpRange
			for _, enemy in ipairs(candidates) do
				local enemyRoot = rootOf(enemy)
				if enemyRoot ~= nil and not used[enemy] and services.EnemyService.canBeHitBy(enemy, player) then
					local distance = (enemyRoot.Position - currentRoot.Position).Magnitude
					if distance <= nextDistance then
						nextEnemy, nextDistance = enemy, distance
					end
				end
			end
			current = nextEnemy
		end
	end
	-- Healing bolts (Holy Bolt): party members the bolt passes through are healed as it reaches them.
	if attack.allyHeal ~= nil and shape == "line" then
		local healAmount = math.floor(attack.allyHeal.amount * (stats.magicPower or 1) + 0.5)
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = rootOf(other.Character)
			if other ~= player and otherRoot ~= nil and services.PartyService.sameParty(player.UserId, other.UserId) then
				local onLine, along = HitShapes.line(origin, direction, otherRoot.Position, attack.range, attack.allyHeal.radius or attack.radius)
				if onLine then
					task.delay(along / (attack.speed or 80), healPlayer, other, healAmount, player)
				end
			end
		end
	end
	local dashed = false
	for _, entry in ipairs(hits) do
		local function land()
			local enemy = entry.enemy
			if enemy.Parent == nil then
				return
			end
			local def = services.EnemyService.definition(enemy)
			local target = { hostile = true, level = def.level, elite = def.elite == true, moving = entry.root.AssemblyLinearVelocity.Magnitude > 1 }
			local hitNow = serverNow()
			local bonus = AbilityRules.consumeBonuses(CombatService.stateFor(enemy), CombatService.stateFor(player), player.UserId, hitNow)
			local playerState = CombatService.stateFor(player)
			if attack.consumeFury ~= nil then
				bonus *= 1 + (playerState.fury or 0) * attack.consumeFury
				playerState.fury = 0
			end
			if attack.furyGain ~= nil then
				playerState.fury = math.min(100, (playerState.fury or 0) + attack.furyGain)
			end
			if attack.control ~= nil then
				applyControl(enemy, attack.control, center or origin, hitNow)
			end
			if attack.drain ~= nil then
				services.ResourceService.restore(player, attack.drain)
			end
			local dealt = math.max(1, math.floor(amount * bonus * (entry.scale or 1) + 0.5))
			local impactPosition = entry.root.Position
			services.EnemyService.damage(enemy, player, dealt, attack.staggers == true)
			-- Life drain (Soul Bolt): heals the caster for a share of the damage dealt.
			if attack.lifesteal ~= nil then
				healPlayer(player, math.floor(dealt * attack.lifesteal + 0.5), player)
			end
			-- Splash (Magic Bolt): the burst also hits other enemies near the one struck, for its own multiplier.
			if attack.splash ~= nil then
				local splashAmount = math.max(1, math.floor(CombatRules.damage(power, attack.splash.multiplier, scale) + 0.5))
				for _, other in ipairs(services.EnemyService.enemiesNear(impactPosition, attack.splash.radius + 4)) do
					local otherRoot = rootOf(other)
					if other ~= enemy and otherRoot ~= nil and services.EnemyService.canBeHitBy(other, player) and (otherRoot.Position - impactPosition).Magnitude <= attack.splash.radius then
						services.EnemyService.damage(other, player, splashAmount, false)
					end
				end
			end
			services.ResourceService.addMeter(player, Resources.ultimate.perHitDealt)
			if attack.dashOnHit ~= nil and not dashed then
				dashed = true
				Remotes.get("AbilityResult"):FireClient(player, 0, true, nil, attack.dashOnHit)
			end
			if attack.mark ~= nil then
				AbilityRules.applyMark(CombatService.stateFor(enemy), player.UserId, attack.mark, hitNow)
			end
			if attack.taunt ~= nil then
				services.EnemyService.taunt(enemy, player, attack.taunt)
			end
			if disciplineId ~= nil and attack.technique ~= nil then
				services.ProgressionService.reportCombatEvent(player, disciplineId, { kind = "Hit", techniqueId = attack.technique, step = attack.step, target = target })
				if attack.finisher then
					services.ProgressionService.reportCombatEvent(player, disciplineId, { kind = "ComboFinished", techniqueId = attack.technique, target = target })
				end
			end
		end
		if entry.delay > 0.02 then
			task.delay(entry.delay, land)
		else
			land()
		end
	end
end

-- The aimed point, if it is a real position; anything else is ignored.
local function validAim(aim: any): Vector3?
	if typeof(aim) ~= "Vector3" or aim.X ~= aim.X or aim.Y ~= aim.Y or aim.Z ~= aim.Z or aim.Magnitude > 1e6 then
		return nil
	end
	return aim
end

local function aimDirection(root: BasePart, aim: Vector3?): Vector3
	if aim ~= nil then
		local toward = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if toward.Magnitude > 0.1 then
			return toward.Unit
		end
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

-- Defences: damage reduction for a while (Shield Wall, Bulwark Advance, Fortress of the Last Stand).
local function addDefense(player: Player, defense: any, now: number)
	local state = CombatService.stateFor(player)
	local active = {}
	for _, existing in ipairs(state.defenses or {}) do
		if existing.untilTime > now then
			table.insert(active, existing)
		end
	end
	table.insert(active, { reduction = defense.reduction, frontal = defense.frontal == true, untilTime = now + defense.seconds })
	state.defenses = active
end

-- Blink: as far as the way is clear, up to the distance.
local function blinkDestination(model: Model, root: BasePart, direction: Vector3, distance: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local result = workspace:Raycast(root.Position, direction * distance, params)
	local travel = distance
	if result ~= nil then
		travel = math.max(0, (result.Position - root.Position).Magnitude - 2)
	end
	return root.Position + direction * travel
end

-- Classes without a discipline (Mage, Heavy Knight) attack with the basic attack in their class configuration.
local function classBasicAttack(player: Player, model: Model, state: any, character: any, now: number, aim: Vector3?)
	local classDef = character and character.class.classId and Content.classes[character.class.classId]
	local basic = classDef and classDef.basicAttack
	local weapon = character and equippedWeapon(character)
	local root = rootOf(model)
	if basic == nil or root == nil or not AbilityRules.weaponAllowed(classDef, weapon and weapon.equipment and weapon.equipment.weaponType) then
		return
	end
	if now < state.busyUntil or now < state.staggeredUntil then
		return
	end
	-- weapon handling (S1): faster weapons and higher attack speed shorten windup and recovery
	local speed = attackSpeedOf(character)
	local windup = basic.windup / speed
	state.busyUntil = now + (basic.windup + basic.active + basic.recovery) / speed
	local direction = aimDirection(root, aim)
	-- caster (presentation only): which class's bolt to show
	CombatService.broadcast(model, basic.animation, { windup = windup, effect = basic.effect, origin = root.Position, direction = direction, range = basic.hit.range, speed = basic.hit.speed, radius = basic.hit.radius, caster = character.class.classId })
	task.delay(windup, resolvePlayerHit, player, nil, withTrait(character, "Basic", basic.hit), aim)
end

-- Damage of an attack by this player at a multiplier (summons use it for their strikes).
function CombatService.damageFor(player: Player, multiplier: number, damageType: string?): number
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil then
		return 0
	end
	local weapon = equippedWeapon(character)
	local power = weaponPower(character)
	local stats = playerStats(character)
	local scale = if damageType == "Magic" then stats.magicPower else stats.physicalDamage
	return CombatRules.damage(power, multiplier, scale)
end

-- Healing (Minor Heal, Divine Sanctuary): "ally" heals the party member nearest the aimed point within range (or
-- yourself); "area" heals you and party members within the radius. Scales with magic power; never above maximum.
local function healFrom(player: Player, heal: any, aim: Vector3?)
	local root = rootOf(player.Character)
	local character = services.PlayerDataService.getCharacter(player)
	if root == nil or character == nil then
		return
	end
	local stats = playerStats(character)
	local amount = math.floor(heal.amount * (stats.magicPower or 1) + 0.5)
	local targets = { player }
	if heal.target == "ally" then
		local point = aim or root.Position
		local best, bestDistance = player, (root.Position - point).Magnitude
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = rootOf(other.Character)
			if other ~= player and otherRoot ~= nil and (otherRoot.Position - root.Position).Magnitude <= heal.range and services.PartyService.sameParty(player.UserId, other.UserId) then
				local distance = (otherRoot.Position - point).Magnitude
				if distance < bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
		targets = { best }
	elseif heal.target == "area" then
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = rootOf(other.Character)
			if other ~= player and otherRoot ~= nil and (otherRoot.Position - root.Position).Magnitude <= heal.radius and services.PartyService.sameParty(player.UserId, other.UserId) then
				table.insert(targets, other)
			end
		end
	end
	for _, target in ipairs(targets) do
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health > 0 then
			local healed = math.floor(math.min(amount, humanoid.MaxHealth - humanoid.Health))
			if healed >= 1 then
				humanoid.Health += healed
				CombatService.hitFeedback(target.Character, healed, "Healed", player.Character)
			end
		end
	end
end

-- Veil: enemies don't see a concealed player until it ends or the player attacks.
function CombatService.isConcealed(player: Player, now: number): boolean
	local state = states[player]
	return state ~= nil and (state.concealedUntil or 0) > now
end

-- Abilities in slots 1 to 4 (the owner's class specification), checked and paid for on the server.
local function useAbility(player: Player, model: Model, state: any, slot: any, now: number, aim: Vector3?)
	local character = services.PlayerDataService.getCharacter(player)
	if character == nil or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 4 then
		return
	end
	local classDef = character.class.classId and Content.classes[character.class.classId]
	local abilityId = classDef and classDef.abilities and classDef.abilities[slot]
	local ability = abilityId and Content.abilities[abilityId]
	local weapon = equippedWeapon(character)
	local ok, reason = AbilityRules.check(ability, abilityId, {
		classDef = classDef,
		weaponType = weapon and weapon.equipment and weapon.equipment.weaponType,
		level = CharacterProgression.level(character.level, Content.progression),
		now = now,
		busyUntil = state.busyUntil,
		staggeredUntil = state.staggeredUntil,
		cooldowns = state.cooldowns,
		meter = services.ResourceService.meter(player),
		canAfford = function(cost: any): boolean
			return services.ResourceService.canAfford(player, cost)
		end,
	})
	if not ok then
		Remotes.get("AbilityResult"):FireClient(player, slot, false, reason)
		return
	end
	services.ResourceService.spend(player, ability.cost)
	if ability.meterCost ~= nil then
		services.ResourceService.spendMeter(player, ability.meterCost)
	end
	local schedule = AbilityRules.start(state, ability, abilityId, now)
	if ability.guardWindow ~= nil then
		state.parryFrom = now
		state.parryTo = now + ability.guardWindow
	end
	local root = rootOf(model)
	if root == nil then
		return
	end
	local direction = aimDirection(root, aim)
	if ability.defense ~= nil then
		addDefense(player, ability.defense, now)
	end
	if ability.empower ~= nil then
		AbilityRules.empower(state, ability.empower, now)
	end
	if ability.conceal ~= nil then
		state.concealedUntil = now + ability.conceal.seconds
	end
	if ability.summon ~= nil then
		task.delay(ability.windup, services.SummonService.summon, player, ability.summon)
	end
	if ability.command ~= nil then
		services.SummonService.command(player, aim, ability.command)
	end
	if ability.summonEmpower ~= nil then
		services.SummonService.empower(player, ability.summonEmpower)
	end
	if ability.heal ~= nil then
		for tick = 0, (ability.heal.ticks or 1) - 1 do
			task.delay(ability.windup + tick * (ability.heal.interval or 1), healFrom, player, ability.heal, aim)
		end
	end
	if ability.haste ~= nil then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			local base = humanoid.WalkSpeed
			humanoid.WalkSpeed = base * ability.haste.multiplier
			task.delay(ability.haste.seconds, function()
				if humanoid.Parent ~= nil then
					humanoid.WalkSpeed = base
				end
			end)
		end
	end
	if ability.allyDefense ~= nil then
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = rootOf(other.Character)
			if other ~= player and otherRoot ~= nil and (otherRoot.Position - root.Position).Magnitude <= ability.allyDefense.radius and services.PartyService.sameParty(player.UserId, other.UserId) then
				addDefense(other, ability.allyDefense, now)
			end
		end
	end
	local blinkTo = nil
	if ability.blink ~= nil then
		blinkTo = blinkDestination(model, root, direction, ability.blink.distance)
	end
	-- Rewind Step: only to a position the server recorded for this character; nothing else is undone.
	if ability.rewind ~= nil then
		local wanted, best = now - ability.rewind.seconds, nil
		for _, entry in ipairs(state.history or {}) do
			if best == nil or math.abs(entry.time - wanted) < math.abs(best.time - wanted) then
				best = entry
			end
		end
		if best ~= nil then
			blinkTo = best.position
		end
	end
	-- Areas land where the player aimed, kept within reach; decided now so everyone sees the same spot.
	local center = nil
	for _, entry in ipairs(schedule) do
		if entry.hit.shape == "area" and center == nil then
			center = HitShapes.clampTarget(root.Position, aim or (root.Position + direction * entry.hit.maxRange), entry.hit.maxRange)
		end
	end
	Remotes.get("AbilityResult"):FireClient(player, slot, true, ability.cooldown, ability.dash, blinkTo)
	local first = schedule[1] and schedule[1].hit
	-- presentation only: which ability (its spell effect) and when each area pulse lands, in seconds after the windup
	local pulses = {}
	for _, entry in ipairs(schedule) do
		if entry.hit.shape == "area" then
			table.insert(pulses, entry.delay - ability.windup)
		end
	end
	CombatService.broadcast(model, ability.animation, {
		windup = ability.windup,
		effect = ability.effect,
		ability = abilityId,
		pulses = pulses,
		origin = root.Position,
		direction = direction,
		target = center or blinkTo,
		range = first and first.range,
		speed = first and first.speed,
		radius = (first and first.radius) or (ability.allyDefense and ability.allyDefense.radius),
	})
	for _, entry in ipairs(schedule) do
		task.delay(entry.delay, resolvePlayerHit, player, nil, entry.hit, aim, center)
	end
end

-- Dodge body animations the client may name (presentation only: the dodge's timing, cost and invulnerability are
-- unchanged). Anything else falls back to the configured dodge animation.
local DODGE_ANIMATIONS = { Dodge = true, DodgeForward = true, DodgeLeft = true, DodgeRight = true }

local function onAction(player: Player, action: any, slot: any, aim: any)
	if not limiter:allow(player) or type(action) ~= "string" then
		return
	end
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local state = CombatService.stateFor(player)
	local now = serverNow()
	if action == "Dodge" then
		local cost = Content.combat.dodge.cost
		if services.ResourceService.canAfford(player, cost) and CombatRules.startDodge(state, Content.combat, now) then
			services.ResourceService.spend(player, cost)
			local dodgeAnimation = if type(slot) == "string" and DODGE_ANIMATIONS[slot] then slot else Content.combat.dodge.animation
			CombatService.broadcast(model, dodgeAnimation, nil, player)
		end
		return
	end
	local disciplineId, discipline, character = playerDiscipline(player)
	local aimPoint = validAim(aim)
	if action == "Ability" then
		useAbility(player, model, state, slot, now, aimPoint)
		return
	end
	if disciplineId == nil then
		if action == "Attack" then
			classBasicAttack(player, model, state, character, now, aimPoint)
		end
		return
	end
	local learned = character.disciplines[disciplineId].techniques or {}
	if action == "Parry" then
		if CombatRules.startParry(state, discipline, learned, now) then
			CombatService.broadcast(model, discipline.parry.animation, nil, player)
		end
		return
	end
	local attackId = CombatRules.resolveAttack(state, discipline, action, learned, now)
	if attackId == nil then
		return
	end
	local attackDef = discipline.attacks[attackId]
	if attackDef ~= nil and not services.ResourceService.canAfford(player, attackDef.cost) then
		return
	end
	local ok, started = CombatRules.startAttack(state, discipline, attackId, learned, now, Content.combat)
	if not ok then
		return
	end
	services.ResourceService.spend(player, started.attack.cost)
	-- weapon handling (S1): the weapon's speed and the character's attack speed scale windup and recovery (the combo
	-- window follows the shortened attack)
	local speed = attackSpeedOf(character)
	local windup = started.attack.windup / speed
	if speed ~= 1 then
		state.busyUntil = now + (started.attack.windup + started.attack.active + started.attack.recovery) / speed
		if state.comboNext ~= nil then
			state.comboUntil = state.busyUntil + Content.combat.comboResetSeconds
		end
	end
	-- Basic attacks are predicted by the attacker's client; heavier techniques are shown to everyone by the server.
	local predicted = action == "Attack"
	CombatService.broadcast(model, started.attack.animation, { windup = windup }, predicted and player or nil)
	task.delay(windup, resolvePlayerHit, player, disciplineId, withTrait(character, started.id, started.attack))
end

-- Called by EnemyService when an enemy's windup ends.
function CombatService.enemyStrike(enemy: Model, enemyId: string)
	local root = rootOf(enemy)
	-- The spawned enemy's own definition (stats at its rolled level) and its attack: its own, or its archetype's.
	local def = services.EnemyService.definition(enemy) or Content.enemies[enemyId]
	local attack = Content.combat.enemyAttacks[enemyId] or (def and Content.combat.archetypeAttacks[def.archetype or "Melee"])
	if root == nil or attack == nil then
		return
	end
	local now = serverNow()
	for _, player in ipairs(Players:GetPlayers()) do
		local target = rootOf(player.Character)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if target ~= nil and humanoid ~= nil and humanoid.Health > 0 and services.EnemyService.canBeHitBy(enemy, player) and CombatRules.inArc(flat(root.Position), flat(root.CFrame.LookVector), flat(target.Position), attack.range, attack.arc, Content.combat.hitLeniencyStuds) then
			local disciplineId, discipline = playerDiscipline(player)
			local result = CombatRules.receiveHit(CombatService.stateFor(player), discipline, now)
			local amount = 0
			if result == "Hit" then
				local fromFront = HitShapes.arc(target.Position, target.CFrame.LookVector, root.Position, math.huge, 120)
				local reduction = HitShapes.reduction(CombatService.stateFor(player).defenses or {}, now, fromFront, Content.combat.maxDamageReduction)
				amount = math.max(1, math.floor(def.damage * (1 - reduction) * (1 - armorReduction(player)) + 0.5))
				humanoid:TakeDamage(amount)
				services.ResourceService.addMeter(player, Resources.ultimate.perHitTaken)
			elseif result == "Parried" then
				services.EnemyService.stagger(enemy, Content.combat.parryStaggerSeconds)
				if disciplineId ~= nil then
					services.ProgressionService.reportCombatEvent(player, disciplineId, { kind = "PerfectParry", techniqueId = discipline.parry.technique, target = { hostile = true, level = def.level, moving = true } })
				end
			end
			CombatService.hitFeedback(player.Character, amount, result, enemy)
		end
	end
end

-- Kill credit from EnemyService: XP, the quest kill and the mastery event.
function CombatService.onKill(player: Player, enemyId: string, def: any)
	services.LootService.onKill(player, enemyId, def)
	-- Experience by level difference: far weaker enemies give none (world specification).
	local killer = services.PlayerDataService.getCharacter(player)
	local playerLevel = if killer then CharacterProgression.level(killer.level, Content.progression) else 1
	local rewardScale = EnemyScaling.rewardMultiplier(playerLevel, def.level, Content.enemyProgression)
	if rewardScale > 0 then
		services.ProgressionService.grantCharacterXp(player, math.floor(def.xp * rewardScale + 0.5), "Kill")
	end
	services.QuestService.reportEvent(player, { kind = "Kill", target = enemyId, amount = 1 })
	local disciplineId = playerDiscipline(player)
	if disciplineId ~= nil then
		services.ProgressionService.reportCombatEvent(player, disciplineId, { kind = "Kill", target = { hostile = true, level = def.level, elite = def.elite == true, moving = true } })
	end
end

-- Puts the equipped weapon in hand and tells clients whether combat controls apply (WeaponType attribute).
function CombatService.attachWeapon(player: Player)
	local model = player.Character
	local character = services.PlayerDataService.getCharacter(player)
	if model == nil or character == nil then
		return
	end
	local weapon = equippedWeapon(character)
	local weaponType = weapon and weapon.equipment and weapon.equipment.weaponType
	if weaponType ~= nil and Models.equipWeapon(model, weaponType, weapon.id) then
		model:SetAttribute("WeaponType", weaponType)
	else
		model:SetAttribute("WeaponType", nil)
	end
	-- an equipped off-hand shield is shown on the left forearm (HasShield tells the animations to carry it)
	local offhand = character.equipment.OffHand
	local offhandDef = offhand and Content.items[offhand.itemId]
	if offhandDef ~= nil and offhandDef.equipment ~= nil and offhandDef.equipment.weaponType == "Shield" and Models.equipShield(model, offhand.itemId) then
		model:SetAttribute("HasShield", true)
	else
		Models.removeShield(model)
		model:SetAttribute("HasShield", nil)
	end
	-- worn armor: every equipped item that is not a weapon or shield, shown when the asset library has a model for it
	local armorIds = {}
	for _, entry in pairs(character.equipment) do
		local def = entry and Content.items[entry.itemId]
		if def ~= nil and def.equipment ~= nil and def.equipment.weaponType == nil then
			table.insert(armorIds, entry.itemId)
		end
	end
	Models.applyArmor(model, armorIds)
	-- equipment bonuses (S2) can change max health: keep the same share of health
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.MaxHealth > 0 then
		local classDef = character.class.classId and Content.classes[character.class.classId]
		local traits = (classDef and classDef.traits) or {}
		local maxHealth = math.floor(playerStats(character).maxHealth * (traits.healthMultiplier or 1))
		if maxHealth ~= humanoid.MaxHealth then
			local share = humanoid.Health / humanoid.MaxHealth
			humanoid.MaxHealth = maxHealth
			humanoid.Health = math.min(maxHealth, maxHealth * share)
		end
	end
	-- rarity shows on everything held and worn (Models.applyRarity: none for Common, glints up to gold embers for Legendary)
	local function rarityOf(entry: any): string?
		local def = entry and Content.items[entry.itemId]
		return def and ItemStats.rarity(def, entry)
	end
	local mainRarity = rarityOf(character.equipment.MainHand)
	Models.applyRarity(model:FindFirstChild("Weapon"), mainRarity)
	Models.applyRarity(model:FindFirstChild("OffhandWeapon"), mainRarity)
	Models.applyRarity(model:FindFirstChild("Shield"), rarityOf(character.equipment.OffHand))
	for _, entry in pairs(character.equipment) do
		if entry ~= nil then
			-- paired set pieces (gloves, boots...) are Armor_<id> and Armor_<id>_2
			local prefix = "Armor_" .. tostring(entry.itemId)
			for _, child in ipairs(model:GetChildren()) do
				if child.Name == prefix or string.sub(child.Name, 1, #prefix + 1) == prefix .. "_" then
					Models.applyRarity(child, rarityOf(entry))
				end
			end
		end
	end
end

local function onCharacter(player: Player, model: Model)
	local character = nil
	for _ = 1, 50 do
		character = services.PlayerDataService.getCharacter(player)
		if character ~= nil or model.Parent == nil then
			break
		end
		task.wait(0.2)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil then
		return
	end
	CombatService.forget(player)
	local stats = playerStats(character)
	local classDef = character.class.classId and Content.classes[character.class.classId]
	local traits = (classDef and classDef.traits) or {}
	local maxHealth = math.floor(stats.maxHealth * (traits.healthMultiplier or 1))
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = traits.walkSpeed or 16
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:WaitForChild("RightHand", 10)
	CombatService.attachWeapon(player)
end

local function watch(player: Player)
	player.CameraMinZoomDistance = 6
	player.CameraMaxZoomDistance = 24
	player.DevEnableMouseLock = false -- the shoulder camera (Client.ShoulderCamera) is always locked behind the character, so Roblox's own shift-lock is off
	player.CharacterAdded:Connect(function(model: Model)
		task.spawn(onCharacter, player, model)
	end)
	if player.Character ~= nil then
		task.spawn(onCharacter, player, player.Character)
	end
end

-- Telegraphed area attacks from bosses: a dodge's invulnerability avoids them; defences and armour reduce them.
function CombatService.areaHit(player: Player, attacker: Model, baseDamage: number)
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if model == nil or humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local now = serverNow()
	local state = CombatService.stateFor(player)
	if now < (state.invulnerableUntil or 0) then
		CombatService.hitFeedback(model, 0, "Dodged", attacker)
		return
	end
	local reduction = HitShapes.reduction(state.defenses or {}, now, false, Content.combat.maxDamageReduction)
	local amount = math.max(1, math.floor(baseDamage * (1 - reduction) * (1 - armorReduction(player)) + 0.5))
	humanoid:TakeDamage(amount)
	services.ResourceService.addMeter(player, Resources.ultimate.perHitTaken)
	CombatService.hitFeedback(model, amount, "Hit", attacker)
end

function CombatService.start()
	Remotes.get("CombatAction").OnServerEvent:Connect(onAction)
	-- Where each player stood over the last few seconds, for Rewind Step (cleared on respawn with the combat state).
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = serverNow()
			for _, player in ipairs(Players:GetPlayers()) do
				local root = rootOf(player.Character)
				if root ~= nil then
					local state = CombatService.stateFor(player)
					state.history = state.history or {}
					table.insert(state.history, { time = now, position = root.Position })
					while #state.history > 24 do
						table.remove(state.history, 1)
					end
				end
			end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		CombatService.forget(player)
		limiter:forget(player)
	end)
end

return CombatService
