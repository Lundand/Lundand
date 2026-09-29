--[[
	PlayerService — the hub for everything about a player:
	join/leave flow, characters, POWER and class stats, zone tracking + gates,
	regen and hazards, coins/items/equipment, upgrades, travel,
	client syncing, notifications and the Request router used by the UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local PlayerService = {}
local S: any

local SyncEvent: RemoteEvent
local NotifyEvent: RemoteEvent
local RequestFn: RemoteFunction
local ActionEvent: RemoteEvent

type Session = {
	lastDamaged: number,
	dirty: boolean,
	stats: any?,
	requests: number,
	requestWindow: number,
	lastTravel: number,
	resumeCarry: boolean,
	gateWarn: number,
	shieldUntil: number,
	shieldReduce: number,
	dmgBuffUntil: number,
	dmgBuff: number,
	aimSlowUntil: number,
}

local sessions: { [Player]: Session } = {}
local handlers: { [string]: (Player, any) -> any } = {}
local actionHandlers: { [string]: (Player, any) -> () } = {}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
function PlayerService.GetSession(player: Player): Session?
	return sessions[player]
end

function PlayerService.GetCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, hum, root
end

-- LoadCharacterAsync is the current API; fall back to the older LoadCharacter if needed
function PlayerService.Spawn(player: Player)
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok and player.Parent then
		pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
end

function PlayerService.IsAlive(player: Player): boolean
	local _, hum, root = PlayerService.GetCharacter(player)
	return hum ~= nil and root ~= nil and hum.Health > 0
end

function PlayerService.Notify(player: Player, text: string, kind: string?, extra: any?)
	NotifyEvent:FireClient(player, { text = text, kind = kind or "info", extra = extra })
end

function PlayerService.NotifyAll(text: string, kind: string?, extra: any?)
	NotifyEvent:FireAllClients({ text = text, kind = kind or "info", extra = extra })
end

function PlayerService.Handle(action: string, fn: (Player, any) -> any)
	handlers[action] = fn
end

function PlayerService.HandleAction(action: string, fn: (Player, any) -> ())
	actionHandlers[action] = fn
end

--------------------------------------------------------------------------------
-- Stats & Power
--------------------------------------------------------------------------------
function PlayerService.Invalidate(player: Player)
	local session = sessions[player]
	if session then
		session.stats = nil
	end
	local stats = PlayerService.GetStats(player)
	if not stats then
		return
	end
	player:SetAttribute("Power", stats.power)
	player:SetAttribute("ClassName", Items.Name(stats.classKey))
	local ls = player:FindFirstChild("leaderstats")
	local powerValue = ls and ls:FindFirstChild("Power")
	if powerValue and powerValue:IsA("StringValue") then
		powerValue.Value = Util.Abbrev(stats.power)
	end
	PlayerService.ApplyCharacterStats(player)
	PlayerService.UpdateTag(player)
	PlayerService.MarkDirty(player)
end

function PlayerService.GetStats(player: Player): any
	local session = sessions[player]
	local data = S.Data.Get(player)
	if not session or not data then
		return nil
	end
	if session.stats then
		return session.stats
	end
	local w, c, a = data.eq.w, data.eq.c, data.eq.a
	local itemPower = Items.Power(w) + Items.Power(c) + Items.Power(a)
	local trainMult = 1 + (data.up.train or 0) * Config.Upgrades.train.per
	local mods = Items.Mods(c)
	local style, styleName = Items.Style(w)
	local ability, abilityId = Items.Ability(a)
	local coinMult = 1 + (mods.coins or 0)
	if S.Shop.HasPass(player, "DoubleCoins") then
		coinMult *= 2
	end
	if S.Shop.HasPass(player, "VIP") then
		coinMult *= 1 + (Config.Passes.VIP.coins or 0)
	end
	local stats = {
		power = itemPower * trainMult,
		itemPower = itemPower,
		trainMult = trainMult,
		hpMult = math.max(0.3, 1 + (mods.hp or 0)),
		dmg = 1 + (mods.dmg or 0),
		melee = 1 + (mods.melee or 0),
		ranged = 1 + (mods.ranged or 0),
		ability = 1 + (mods.ability or 0),
		speed = 1 + (mods.speed or 0),
		regen = mods.regen or 0,
		lifesteal = mods.lifesteal or 0,
		backstab = mods.backstab or 0,
		crit = Config.Combat.CritChance + (mods.crit or 0),
		resist = math.clamp(mods.resist or 0, 0, 0.8),
		carry = math.clamp(mods.carry or 0, 0, 1),
		hazard = math.clamp(mods.hazard or 0, 0, 1),
		classLuck = mods.luck or 0,
		coinMult = coinMult,
		style = style,
		styleName = styleName,
		abilityDef = ability,
		abilityId = abilityId,
		weaponKey = w,
		classKey = c,
		abilityKey = a,
	}
	session.stats = stats
	return stats
end

function PlayerService.GetPower(player: Player): number
	local stats = PlayerService.GetStats(player)
	return stats and stats.power or 0
end

-- Total Core luck multiplier (upgrades, class, passes, boosts)
function PlayerService.GetLuck(player: Player): number
	local data = S.Data.Get(player)
	local stats = PlayerService.GetStats(player)
	if not data or not stats then
		return 1
	end
	local luck = (1 + (data.up.luck or 0) * Config.Upgrades.luck.per) * (1 + stats.classLuck)
	if S.Shop.HasPass(player, "DoubleLuck") then
		luck *= 2
	end
	if (data.boosts.luck or 0) > os.time() then
		luck *= Config.Products.Luck.mult
	end
	if S.Shop.ServerLuckUntil() > os.time() then
		luck *= Config.Products.ServerLuck.mult
	end
	return luck
end

function PlayerService.UpdateZoneStat(player: Player)
	local ls = player:FindFirstChild("leaderstats")
	local zoneStat = ls and ls:FindFirstChild("Zone")
	if zoneStat and zoneStat:IsA("IntValue") then
		zoneStat.Value = PlayerService.HighestZone(player)
	end
end

function PlayerService.HighestZone(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 1
	end
	return math.max(data.zones or 1, data.rift or 0)
end

--------------------------------------------------------------------------------
-- Character
--------------------------------------------------------------------------------
-- Hides/shows the whole weapon, off-hand dagger included (it stays inside the EquippedWeapon model)
local function setWeaponVisible(character: Model, visible: boolean)
	local weapon = character:FindFirstChild("EquippedWeapon")
	if not weapon then
		return
	end
	for _, d in weapon:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.Transparency = visible and 0 or 1
		elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") then
			d.Enabled = visible
		elseif d:IsA("Trail") and not visible then
			d.Enabled = false -- swing trails are only switched on by the client during a strike
		end
	end
end
PlayerService.SetWeaponVisible = setWeaponVisible

-- Where a weapon's Handle (origin = grip point, blade along +Y) sits on the hand (R6: arm) holding it
local function weaponGrip(styleName: string, style: any, hand: BasePart): CFrame
	if styleName == "bow" then
		-- held beside the arm (not through it), belly forward, string behind
		return CFrame.new(0.95, -hand.Size.Y / 2 + 0.1, -0.35)
	elseif style.grip == "upright" then
		return CFrame.new(0.7, -hand.Size.Y / 2, -0.25)
	end
	-- blade forward when the arm hangs down
	return CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end

function PlayerService.AttachWeapon(player: Player)
	local character = player.Character
	local data = S.Data.Get(player)
	if not character or not data then
		return
	end
	local old = character:FindFirstChild("EquippedWeapon")
	if old then
		old:Destroy()
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local key = data.eq.w
	local model = Models.Weapon(key)
	model.Name = "EquippedWeapon"
	local handle = model.PrimaryPart
	if not handle then
		model:Destroy()
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local style, styleName = Items.Style(key)
	local grip = weaponGrip(styleName, style, hand)
	handle.CFrame = hand.CFrame * grip
	local weld = Instance.new("Weld")
	weld.Name = "WeaponGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = grip
	weld.Parent = handle
	-- paired weapons (daggers): the second blade's assembly moves from the Handle to the left hand
	local offHandle = model:FindFirstChild("OffHandle", true)
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if offHandle and offHandle:IsA("BasePart") and leftHand and leftHand:IsA("BasePart") then
		local joined = model:FindFirstChild("OffHandWeld", true)
		if joined then
			joined:Destroy()
		end
		local offGrip = weaponGrip(styleName, style, leftHand)
		offHandle.CFrame = leftHand.CFrame * offGrip
		local offWeld = Instance.new("Weld")
		offWeld.Name = "OffHandGrip"
		offWeld.Part0 = leftHand
		offWeld.Part1 = offHandle
		offWeld.C0 = offGrip
		offWeld.Parent = offHandle
	end
	model.Parent = character
	if character:GetAttribute("Carrying") then
		setWeaponVisible(character, false)
	end
end

-- Walk speed, jump and max health from class + carrying
function PlayerService.ApplyCharacterStats(player: Player)
	local character, hum = PlayerService.GetCharacter(player)
	local stats = PlayerService.GetStats(player)
	if not character or not hum or not stats then
		return
	end
	local speed = Config.Player.WalkSpeed * stats.speed
	local carry = S.Cores.GetCarry(player)
	if carry then
		local slow = Config.Cores.CarrySlow[carry.r] or 0.2
		local data = S.Data.Get(player)
		local reduce = math.clamp(stats.carry + (data.up.carry or 0) * Config.Upgrades.carry.per, 0, 0.95)
		speed *= 1 - slow * (1 - reduce)
		hum.JumpHeight = Config.Cores.CarryJumpHeight
	else
		hum.JumpHeight = Config.Player.JumpHeight
	end
	local session = sessions[player]
	if session and session.aimSlowUntil > os.clock() then
		speed *= Config.Combat.RangedMoveSlow
	end
	if character:GetAttribute("Stunned") then
		speed = 0
	end
	hum.WalkSpeed = speed
	local maxHealth = Config.Player.BaseHealth * stats.hpMult
	if math.abs(hum.MaxHealth - maxHealth) > 0.01 then
		local ratio = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 1
		hum.MaxHealth = maxHealth
		hum.Health = math.clamp(maxHealth * ratio, 1, maxHealth)
	end
end

-- Shooting a bow/staff slows the shooter briefly so ranged weapons can't kite forever
function PlayerService.SetAimSlow(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local wasSlow = session.aimSlowUntil > os.clock()
	session.aimSlowUntil = os.clock() + Config.Combat.RangedSlowTime
	if not wasSlow then
		PlayerService.ApplyCharacterStats(player)
	end
	task.delay(Config.Combat.RangedSlowTime + 0.05, function()
		if sessions[player] == session and session.aimSlowUntil <= os.clock() then
			PlayerService.ApplyCharacterStats(player)
		end
	end)
end

function PlayerService.UpdateTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local stats = PlayerService.GetStats(player)
	if not head or not stats then
		return
	end
	local tag = head:FindFirstChild("Tag")
	if not tag then
		local bb = Instance.new("BillboardGui")
		bb.Name = "Tag"
		bb.Size = UDim2.fromOffset(200, 48)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		bb.Adornee = head
		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.4
		name.Parent = bb
		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.BackgroundTransparency = 1
		info.Size = UDim2.new(1, 0, 0.42, 0)
		info.Position = UDim2.new(0, 0, 0.56, 0)
		info.Font = Enum.Font.GothamBold
		info.TextScaled = true
		info.TextColor3 = Color3.fromRGB(255, 220, 90)
		info.TextStrokeTransparency = 0.4
		info.Parent = bb
		bb.Parent = head
		tag = bb
	end
	local vip = S.Shop.HasPass(player, "VIP")
	local nameLabel = (tag :: Instance):FindFirstChild("PlayerName") :: TextLabel
	local infoLabel = (tag :: Instance):FindFirstChild("Info") :: TextLabel
	nameLabel.Text = (vip and "[VIP] " or "") .. player.DisplayName
	nameLabel.TextColor3 = vip and Color3.fromRGB(255, 215, 80) or Color3.new(1, 1, 1)
	infoLabel.Text = "⚡ " .. Util.Abbrev(stats.power) .. "  •  " .. Items.Name(stats.classKey)
	infoLabel.TextColor3 = Items.RarityColor(Items.Rarity(stats.classKey))
end

local function onCharacterAdded(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root then
		return
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.UseJumpPower = false
	hum.BreakJointsOnDeath = true
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and d.CollisionGroup ~= "Players" and d.Parent and d.Parent.Name ~= "EquippedWeapon" and d.Parent.Name ~= "CarriedCore" then
			d.CollisionGroup = "Players"
		end
	end)

	local session = sessions[player]
	if session then
		session.lastDamaged = 0
	end
	PlayerService.ApplyCharacterStats(player)
	hum.Health = hum.MaxHealth
	task.defer(function()
		PlayerService.AttachWeapon(player)
		PlayerService.UpdateTag(player)
	end)

	hum.Died:Connect(function()
		local data = S.Data.Get(player)
		if data then
			data.stats.deaths += 1
		end
		local pos = root.Position
		pcall(S.Cores.OnDeath, player, pos)
		pcall(S.Rift.OnDeath, player)
		task.delay(Config.Player.RespawnTime, function()
			if player.Parent and player.Character == character then
				PlayerService.Spawn(player)
			end
		end)
	end)

	-- Rejoined while carrying a Core? Put it back in their hands where they left off
	if session and session.resumeCarry then
		session.resumeCarry = false
		task.delay(0.5, function()
			if player.Character == character then
				S.Cores.Resume(player)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Economy & inventory
--------------------------------------------------------------------------------
function PlayerService.AddCoins(player: Player, amount: number)
	local data = S.Data.Get(player)
	if not data or amount ~= amount then
		return
	end
	data.coins = math.max(0, data.coins + amount)
	PlayerService.MarkDirty(player)
end

function PlayerService.AddFragments(player: Player, amount: number)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	data.fragments = math.max(0, data.fragments + math.floor(amount))
	PlayerService.MarkDirty(player)
end

function PlayerService.Equip(player: Player, key: string): (boolean, string?)
	local data = S.Data.Get(player)
	if not data then
		return false, "Loading..."
	end
	if not Items.Valid(key) or (data.inv[key] or 0) <= 0 then
		return false, "You don't own that item."
	end
	local slot = Items.Slot(key)
	if not slot then
		return false, "Invalid item."
	end
	data.eq[slot] = key
	PlayerService.Invalidate(player)
	if slot == "w" then
		PlayerService.AttachWeapon(player)
	end
	return true, nil
end

-- Items that count toward Config.Inventory.Max (starter items don't)
function PlayerService.InventoryCount(player: Player): number
	local data = S.Data.Get(player)
	return data and Items.InventoryCount(data.inv) or 0
end

function PlayerService.InventoryFull(player: Player): boolean
	return PlayerService.InventoryCount(player) >= Config.Inventory.Max
end

-- Adds an item; auto-equips it if it is stronger and the setting is on. Returns true if equipped.
-- Callers check InventoryFull first; `force` (admin) ignores the limit.
function PlayerService.GiveItem(player: Player, key: string, force: boolean?): boolean
	local data = S.Data.Get(player)
	if not data or not Items.Valid(key) then
		return false
	end
	if not force and PlayerService.InventoryFull(player) then
		return false
	end
	data.inv[key] = (data.inv[key] or 0) + 1
	local slot = Items.Slot(key) :: string
	local equipped = false
	if data.settings.autoEquip ~= false and Items.Power(key) > Items.Power(data.eq[slot]) then
		equipped = PlayerService.Equip(player, key)
	end
	S.Plots.RefreshTrophies(player)
	PlayerService.MarkDirty(player)
	return equipped
end

-- Sells copies of one item for coins. The last copy of an equipped item and starter items can't be sold.
local function sell(player: Player, key: string, count: number): (number, string?)
	local data = S.Data.Get(player)
	local owned = data.inv[key] or 0
	if owned <= 0 or not Items.Valid(key) then
		return 0, "You don't own that item."
	end
	if Items.Zone(key) == 0 then
		return 0, "Starter items can't be sold."
	end
	local slot = Items.Slot(key) :: string
	local keep = data.eq[slot] == key and 1 or 0
	count = math.clamp(math.floor(count), 0, owned - keep)
	if count <= 0 then
		return 0, "Equip something else before selling this."
	end
	local value = Items.SellValue(key) * count
	data.inv[key] = owned - count
	if data.inv[key] <= 0 then
		data.inv[key] = nil
	end
	data.coins += value
	return value, nil
end

--------------------------------------------------------------------------------
-- Sync
--------------------------------------------------------------------------------
function PlayerService.MarkDirty(player: Player)
	local session = sessions[player]
	if session then
		session.dirty = true
	end
end

local function snapshot(player: Player): any
	local data = S.Data.Get(player)
	local stats = PlayerService.GetStats(player)
	if not data or not stats then
		return nil
	end
	return {
		coins = data.coins,
		fragments = data.fragments,
		inv = data.inv,
		eq = data.eq,
		inc = data.inc,
		store = data.store,
		up = data.up,
		zones = data.zones,
		rift = data.rift,
		best = data.best,
		stats = data.stats,
		settings = data.settings,
		skips = data.skips,
		luckBoostUntil = data.boosts.luck or 0,
		power = stats.power,
		itemPower = stats.itemPower,
		trainMult = stats.trainMult,
		slots = S.Incubators.SlotCount(player),
		storageCap = S.Incubators.StorageCap(player),
		luck = PlayerService.GetLuck(player),
		coinMult = stats.coinMult,
		passes = S.Shop.OwnedPasses(player),
		serverLuckUntil = S.Shop.ServerLuckUntil(),
		invCount = Items.InventoryCount(data.inv),
		invMax = Config.Inventory.Max,
		temporary = S.Data.IsTemporary(player),
		isAdmin = S.Admin.IsAdmin(player),
		incubationMult = S.Incubators.SpeedMult(player),
		forgeZone = S.Incubators.ForgeZone(player),
		restricted = S.Shop.IsRestricted(player), -- paid random items (Premium Cores, luck) not allowed here
		premiumZone = Items.PremiumZone(data.zones),
		serverTime = os.time(),
	}
end

local function flush(player: Player)
	local session = sessions[player]
	if not session or not session.dirty then
		return
	end
	local snap = snapshot(player)
	if snap then
		session.dirty = false
		SyncEvent:FireClient(player, snap)
	end
end

--------------------------------------------------------------------------------
-- Damage & healing
--------------------------------------------------------------------------------
function PlayerService.DamagePlayer(player: Player, amount: number, _source: string?)
	local character, hum = PlayerService.GetCharacter(player)
	local session = sessions[player]
	if not character or not hum or hum.Health <= 0 or not session then
		return
	end
	if character:GetAttribute("God") then
		return
	end
	local stats = PlayerService.GetStats(player)
	if stats then
		amount *= 1 - stats.resist
	end
	if session.shieldUntil > os.clock() then
		amount *= 1 - session.shieldReduce
	end
	session.lastDamaged = os.clock()
	hum:TakeDamage(amount)
end

-- Damage from a mob, scaled by how far the player is below the zone's recommended Power
function PlayerService.DamageFromMob(player: Player, zone: number, tierDamage: number)
	local _, hum = PlayerService.GetCharacter(player)
	local power = PlayerService.GetPower(player)
	if not hum or power <= 0 then
		return
	end
	local C = Config.Combat
	local gap = (Items.Rec(zone) / power) ^ C.GapExponent
	local scale = math.clamp(gap, C.MinDamageScale, C.MaxDamageScale)
	PlayerService.DamagePlayer(player, hum.MaxHealth * tierDamage * scale, "mob")
end

function PlayerService.Heal(player: Player, fraction: number)
	local _, hum = PlayerService.GetCharacter(player)
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * fraction)
	end
end

function PlayerService.SetShield(player: Player, reduce: number, duration: number)
	local session = sessions[player]
	if session then
		session.shieldReduce = reduce
		session.shieldUntil = os.clock() + duration
	end
end

function PlayerService.SetDamageBuff(player: Player, mult: number, duration: number)
	local session = sessions[player]
	if session then
		session.dmgBuff = mult
		session.dmgBuffUntil = os.clock() + duration
	end
end

function PlayerService.DamageBuff(player: Player): number
	local session = sessions[player]
	if session and session.dmgBuffUntil > os.clock() then
		return session.dmgBuff
	end
	return 1
end

--------------------------------------------------------------------------------
-- Teleporting
--------------------------------------------------------------------------------
function PlayerService.Teleport(player: Player, cf: CFrame)
	local character, _, root = PlayerService.GetCharacter(player)
	if character and root then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
	end
end

--------------------------------------------------------------------------------
-- Zone tracking, gates, regen, hazards
--------------------------------------------------------------------------------
local function trackPlayer(player: Player, dt: number)
	local data = S.Data.Get(player)
	local session = sessions[player]
	local character, hum, root = PlayerService.GetCharacter(player)
	if not data or not session or not character or not hum or not root or hum.Health <= 0 then
		return
	end
	local pos = root.Position
	local inRift = (player:GetAttribute("RiftZone") or 0) > 0

	-- fell out of the world
	if pos.Y < -60 and not inRift then
		local zone = math.max(Util.ZoneAtX(pos.X), 1)
		PlayerService.Teleport(player, CFrame.new(Util.ZoneEntry(math.min(zone, data.zones))))
		return
	end

	local zone = inRift and player:GetAttribute("RiftZone") or Util.ZoneAtX(pos.X)
	if not inRift and zone >= 2 and zone > data.zones then
		local stats = PlayerService.GetStats(player)
		local required = Items.Required(zone)
		if zone == data.zones + 1 and stats.power >= required then
			data.zones = zone
			PlayerService.UpdateZoneStat(player)
			player:SetAttribute("ZoneMax", data.zones)
			PlayerService.Notify(player, "NEW ZONE UNLOCKED: " .. string.upper(Config.Zones[zone].name) .. "!", "unlock", { zone = zone })
			S.Boards.MarkDirty(player)
			PlayerService.MarkDirty(player)
			S.Badges.Check(player)
		else
			local allowed = data.zones + 1
			local gateX = Util.ZoneStartX(allowed)
			PlayerService.Teleport(player, CFrame.new(gateX - 10, pos.Y + 2, math.clamp(pos.Z, -100, 100)) * CFrame.Angles(0, math.pi / 2, 0))
			if os.clock() - session.gateWarn > 2 then
				session.gateWarn = os.clock()
				PlayerService.Notify(
					player,
					string.format("You need %s Power to enter the %s (you have %s)", Util.Abbrev(Items.Required(allowed)), Config.Zones[allowed].name, Util.Abbrev(stats.power)),
					"error"
				)
			end
			return
		end
	end
	if player:GetAttribute("Zone") ~= zone then
		player:SetAttribute("Zone", zone)
	end

	-- regeneration
	local stats = PlayerService.GetStats(player)
	if stats and hum.Health < hum.MaxHealth then
		local rate = stats.regen
		if os.clock() - session.lastDamaged > Config.Combat.RegenDelay then
			rate += Config.Combat.RegenPerSec
		end
		if rate > 0 then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * rate * dt)
		end
	end

	-- lava / toxic pools
	if not inRift and zone >= 1 and Config.Zones[zone] and Config.Zones[zone].hazard and stats then
		for _, hazard in S.World.Hazards do
			local d = Vector3.new(pos.X - hazard.pos.X, 0, pos.Z - hazard.pos.Z).Magnitude
			if d < hazard.radius and pos.Y < hazard.pos.Y + 6 then
				PlayerService.DamagePlayer(player, hum.MaxHealth * Config.Combat.HazardDamage * dt * (1 - stats.hazard), "hazard")
				break
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Join / leave
--------------------------------------------------------------------------------
local function validateData(data: any)
	for _, slot in Items.Slots do
		local key = data.eq[slot]
		if type(key) ~= "string" or not Items.Valid(key) or (data.inv[key] or 0) <= 0 then
			local starter = Items.Key(0, slot, 1, 1)
			data.inv[starter] = math.max(data.inv[starter] or 0, 1)
			data.eq[slot] = starter
		end
	end
	for key, count in data.inv do
		if not Items.Valid(key) or type(count) ~= "number" or count <= 0 then
			data.inv[key] = nil
		end
	end
	data.zones = math.clamp(tonumber(data.zones) or 1, 1, #Config.Zones)
end

local function onPlayerAdded(player: Player)
	sessions[player] = {
		lastDamaged = 0,
		dirty = true,
		stats = nil,
		requests = 0,
		requestWindow = os.clock(),
		lastTravel = 0,
		resumeCarry = false,
		gateWarn = 0,
		shieldUntil = 0,
		shieldReduce = 0,
		dmgBuffUntil = 0,
		dmgBuff = 1,
		aimSlowUntil = 0,
	}
	local data = S.Data.Load(player)
	if not data or not player.Parent then
		return
	end
	validateData(data)

	S.Shop.LoadPasses(player)
	S.Shop.LoadPolicy(player)
	S.Incubators.EnsureSlots(player)
	S.Plots.Assign(player)

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local zoneStat = Instance.new("IntValue")
	zoneStat.Name = "Zone"
	zoneStat.Value = PlayerService.HighestZone(player)
	zoneStat.Parent = ls
	local powerStat = Instance.new("StringValue")
	powerStat.Name = "Power"
	powerStat.Parent = ls
	ls.Parent = player

	player:SetAttribute("ZoneMax", data.zones)
	player:SetAttribute("IsAdmin", S.Admin.IsAdmin(player))
	PlayerService.Invalidate(player)

	local session = sessions[player]
	if session and data.carry then
		session.resumeCarry = true
	end

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player:SetAttribute("Loaded", true)
	PlayerService.Spawn(player)

	task.delay(4, function()
		if not player.Parent then
			return
		end
		local ready = S.Incubators.ReadyCount(player)
		if ready > 0 then
			PlayerService.Notify(player, ready .. (ready == 1 and " Core is" or " Cores are") .. " ready to open!", "rare")
		end
		if S.Data.IsTemporary(player) then
			PlayerService.Notify(player, "Progress is not being saved this session (Studio: enable API Services).", "warn")
		end
	end)
end

-- Called before autosaves (final = false) and when leaving/shutting down (final = true)
function PlayerService.BeforeSave(player: Player, final: boolean)
	if final then
		-- Cores first: it needs to know whether the player was in the Rift
		pcall(S.Cores.OnLeave, player)
		pcall(S.Rift.OnLeave, player)
	else
		pcall(S.Cores.Snapshot, player)
	end
end

local function onPlayerRemoving(player: Player)
	if S.Data.Get(player) then
		PlayerService.BeforeSave(player, true)
		pcall(S.Boards.Submit, player)
		S.Plots.Release(player)
		S.Data.Release(player)
	end
	sessions[player] = nil
end

--------------------------------------------------------------------------------
-- Request handlers (UI)
--------------------------------------------------------------------------------
local function registerHandlers()
	PlayerService.Handle("equip", function(player, args)
		local ok, err = PlayerService.Equip(player, tostring(args.key))
		if not ok then
			return { ok = false, msg = err }
		end
		return { ok = true, msg = "Equipped " .. Items.FullName(tostring(args.key)) }
	end)

	PlayerService.Handle("sell", function(player, args)
		local key = tostring(args.key)
		local name = Items.FullName(key)
		local gained, err = sell(player, key, tonumber(args.count) or 1)
		if err then
			return { ok = false, msg = err }
		end
		S.Plots.RefreshTrophies(player)
		PlayerService.MarkDirty(player)
		return { ok = true, msg = "Sold " .. name .. " for " .. Util.Abbrev(gained) .. " Coins" }
	end)

	PlayerService.Handle("settings", function(player, args)
		local data = S.Data.Get(player)
		if type(args.autoEquip) == "boolean" then
			data.settings.autoEquip = args.autoEquip
		end
		if type(args.autoIncubate) == "boolean" then
			data.settings.autoIncubate = args.autoIncubate
			if args.autoIncubate then
				S.Incubators.Fill(player)
			end
		end
		PlayerService.MarkDirty(player)
		return { ok = true }
	end)

	PlayerService.Handle("upgrade", function(player, args)
		local id = tostring(args.id)
		local u = Config.Upgrades[id]
		local data = S.Data.Get(player)
		if not u then
			return { ok = false, msg = "Unknown upgrade." }
		end
		local level = data.up[id] or 0
		local cost = Items.UpgradeCost(id, level)
		if not cost then
			return { ok = false, msg = "Already maxed!" }
		end
		if data.coins < cost then
			return { ok = false, msg = "Not enough Coins (need " .. Util.Abbrev(cost) .. ")" }
		end
		data.coins -= cost
		data.up[id] = level + 1
		if id == "train" or id == "carry" then
			PlayerService.Invalidate(player)
		elseif id == "slots" then
			S.Incubators.EnsureSlots(player)
			S.Incubators.Fill(player)
			S.Plots.RefreshIncubators(player)
		elseif id == "style" then
			S.Plots.RefreshStyle(player)
		end
		PlayerService.MarkDirty(player)
		S.Badges.Check(player)
		return { ok = true, msg = u.name .. " → level " .. data.up[id] }
	end)

	PlayerService.Handle("travel", function(player, args)
		local data = S.Data.Get(player)
		local session = sessions[player]
		if not PlayerService.IsAlive(player) then
			return { ok = false, msg = "You can't travel right now." }
		end
		if S.Cores.GetCarry(player) then
			return { ok = false, msg = "You can't teleport while carrying a Core! Walk it home." }
		end
		if os.clock() - session.lastTravel < 2 then
			return { ok = false, msg = "Slow down!" }
		end
		local zone = tonumber(args.zone) or 0
		if (player:GetAttribute("RiftZone") or 0) > 0 then
			S.Rift.Leave(player, true)
		end
		session.lastTravel = os.clock()
		if zone <= 0 then
			local home = S.Plots.HomeCFrame(player)
			PlayerService.Teleport(player, home or CFrame.new(Config.World.SpawnPos + Vector3.new(0, 4, 0)))
			return { ok = true, msg = "Welcome home!" }
		end
		if zone > data.zones then
			return { ok = false, msg = "Reach that zone on foot first to unlock travel." }
		end
		PlayerService.Teleport(player, CFrame.new(Util.ZoneEntry(zone)) * CFrame.Angles(0, -math.pi / 2, 0))
		return { ok = true, msg = "Traveled to " .. Config.Zones[zone].name }
	end)
end

function PlayerService.Init(services: any)
	S = services
	SyncEvent = Net.Event("Sync")
	NotifyEvent = Net.Event("Notify")
	RequestFn = Net.Function("Request")
	ActionEvent = Net.Event("Action")
end

function PlayerService.Start()
	registerHandlers()

	RequestFn.OnServerInvoke = function(player: Player, action: any, args: any)
		local session = sessions[player]
		if type(action) ~= "string" or not session or not S.Data.Get(player) then
			return { ok = false, msg = "Still loading..." }
		end
		local now = os.clock()
		if now - session.requestWindow > 1 then
			session.requestWindow = now
			session.requests = 0
		end
		session.requests += 1
		if session.requests > 25 then
			return { ok = false, msg = "Slow down!" }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false, msg = "Unknown action" }
		end
		local ok, result = pcall(handler, player, type(args) == "table" and args or {})
		if not ok then
			warn("[Request] " .. action .. " failed: " .. tostring(result))
			return { ok = false, msg = "Something went wrong." }
		end
		return result or { ok = true }
	end

	ActionEvent.OnServerEvent:Connect(function(player: Player, action: any, args: any)
		if type(action) ~= "string" or not S.Data.Get(player) then
			return
		end
		local handler = actionHandlers[action]
		if handler then
			local ok, err = pcall(handler, player, type(args) == "table" and args or {})
			if not ok then
				warn("[Action] " .. action .. " failed: " .. tostring(err))
			end
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- 4x per second: zones, gates, regen, hazards
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = math.min(now - last, 1)
			last = now
			for player in sessions do
				local ok, err = pcall(trackPlayer, player, dt)
				if not ok then
					warn("[Track] " .. tostring(err))
				end
			end
		end
	end)

	-- client sync, throttled
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in sessions do
				flush(player)
			end
		end
	end)
end

return PlayerService
