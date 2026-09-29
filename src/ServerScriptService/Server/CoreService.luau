--[[
	CoreService — the heart of the game: "I found something incredibly rare. Now I need to get it home."

	* Kills roll a Core drop (luck-adjusted). The Core lands on the ground with its rarity and
	  1/N odds floating above it, a light pillar for Rare+, and is reserved for the finder for a while.
	* Picking it up puts it in your hands: you are slowed, can't attack or teleport, and everyone can see it.
	* Step onto your own base to secure it (it goes into an incubator or storage).
	* Die while carrying -> it drops where you died, reserved for you for a short time.
	* In contested zones other players can hold "Steal Core" on you (you can run away while they hold).
	* Leave the game / server shuts down while carrying -> you rejoin at the same spot, still carrying it.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Models = require(Shared:WaitForChild("Models"))

local CoreService = {}
local S: any
local FX: RemoteEvent

local GLOBAL_TOPIC = "CoreHunters_GlobalFinds"
local rng = Random.new()
local coresFolder: Folder
local rayParams = RaycastParams.new()

type CoreInfo = { z: number, r: number, odds: number, mob: string }
type Ground = {
	id: string,
	info: CoreInfo,
	model: Model,
	pos: Vector3,
	reservedFor: number,
	reserveUntil: number,
	despawnAt: number,
	deathDrop: boolean,
}
type Carry = {
	info: CoreInfo,
	model: Model,
	character: Model,
	shieldUntil: number,
	stealImmuneUntil: number,
	stealPrompt: ProximityPrompt?,
	lastPos: Vector3,
}

local grounds: { [string]: Ground } = {}
local carries: { [Player]: Carry } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function groundY(pos: Vector3): number
	local result = workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), rayParams)
	return result and result.Position.Y or pos.Y
end

local function newLabel(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Font = font
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = ""
	t.Parent = parent
	return t
end

local function copyInfo(info: any): CoreInfo
	return { z = tonumber(info.z) or 1, r = tonumber(info.r) or 1, odds = tonumber(info.odds) or 1, mob = tostring(info.mob or "?") }
end

function CoreService.GetCarry(player: Player): any
	local carry = carries[player]
	return carry and carry.info
end

--------------------------------------------------------------------------------
-- Announcements
--------------------------------------------------------------------------------
local function announce(text: string, r: number, global: boolean)
	S.Player.NotifyAll(text, "announce", { rarity = r })
	if global then
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(GLOBAL_TOPIC, { text = text, r = r, job = game.JobId })
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- Ground Cores
--------------------------------------------------------------------------------
function CoreService.SpawnGround(info: CoreInfo, pos: Vector3, reservedFor: Player?, reserveSeconds: number, despawnSeconds: number, deathDrop: boolean?): Ground
	local id = HttpService:GenerateGUID(false)
	local r = info.r
	local rarityColor = Items.RarityColor(r)
	local model = Models.Core(info.z, r, 1.25)
	model.Name = "GroundCore"
	Models.SetAnchored(model, true)
	local center = Vector3.new(pos.X, groundY(pos) + 2.8, pos.Z)
	model:PivotTo(CFrame.new(center))
	local core = model.PrimaryPart :: BasePart

	if r >= 3 then
		-- light shaft into the sky: a Beam that starts just above the Core's glass shell,
		-- so nothing overlaps the Core itself (a see-through part there used to flicker)
		local width = 0.8 + r * 0.45
		local bottom = Instance.new("Attachment")
		bottom.Name = "BeamBottom"
		bottom.Position = Vector3.new(0, 2.3, 0)
		bottom.Parent = core
		local top = Instance.new("Attachment")
		top.Name = "BeamTop"
		top.Position = Vector3.new(0, 240, 0)
		top.Parent = core
		local shaft = Instance.new("Beam")
		shaft.Name = "LightShaft"
		shaft.Attachment0 = bottom
		shaft.Attachment1 = top
		shaft.FaceCamera = true
		shaft.Segments = 1
		shaft.Width0 = width * 0.6
		shaft.Width1 = width * 1.4
		shaft.LightEmission = 1
		shaft.LightInfluence = 0
		shaft.Brightness = 2
		shaft.Color = ColorSequence.new(rarityColor)
		shaft.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.025, 0.35),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		shaft.Parent = core
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "Info"
	bb.Size = UDim2.fromOffset(250, 78)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = r >= 4
	bb.MaxDistance = 100 + r * 60
	bb.LightInfluence = 0
	bb.Adornee = core
	newLabel(bb, "Title", UDim2.new(1, 0, 0.4, 0), UDim2.new(), rarityColor, Enum.Font.FredokaOne).Text = Items.CoreTitle(info.z, r)
	newLabel(bb, "Odds", UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.4, 0), Color3.new(1, 1, 1), Enum.Font.GothamBlack).Text = Util.Odds(info.odds)
	newLabel(bb, "Status", UDim2.new(1, 0, 0.26, 0), UDim2.new(0, 0, 0.72, 0), Color3.fromRGB(255, 230, 140), Enum.Font.GothamBold)
	bb.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = Items.CoreTitle(info.z, r)
	prompt.HoldDuration = Config.Cores.PickupHold[r] or 0.5
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = core

	local ground: Ground = {
		id = id,
		info = info,
		model = model,
		pos = center,
		reservedFor = reservedFor and reservedFor.UserId or 0,
		reserveUntil = now() + reserveSeconds,
		despawnAt = now() + despawnSeconds,
		deathDrop = deathDrop == true,
	}
	model:SetAttribute("CoreId", id)
	model:SetAttribute("Rarity", r)
	model:SetAttribute("Zone", info.z)
	model:SetAttribute("ReservedFor", ground.reservedFor)
	model:SetAttribute("ReservedName", reservedFor and reservedFor.DisplayName or "")
	model:SetAttribute("ReserveUntil", ground.reserveUntil)
	model:SetAttribute("DespawnAt", ground.despawnAt)
	model:SetAttribute("Base", center)
	prompt.Triggered:Connect(function(who)
		CoreService.PickUp(who, id)
	end)
	model.Parent = coresFolder
	CollectionService:AddTag(model, "GroundCore")
	grounds[id] = ground
	return ground
end

local function removeGround(id: string)
	local ground = grounds[id]
	if ground then
		grounds[id] = nil
		ground.model:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Carrying
--------------------------------------------------------------------------------
local function setShield(player: Player, character: Model, seconds: number)
	local carry = carries[player]
	if not carry or seconds <= 0 then
		return
	end
	carry.shieldUntil = os.clock() + seconds
	local old = character:FindFirstChild("CoreShield")
	if old then
		old:Destroy()
	end
	local ff = Instance.new("ForceField")
	ff.Name = "CoreShield"
	ff.Visible = true
	ff.Parent = character
	character:SetAttribute("ShieldUntil", now() + seconds)
	task.delay(seconds, function()
		if ff.Parent then
			ff:Destroy()
		end
	end)
end

-- C0/C1 of a character joint: a Motor6D, or the AnimationConstraint replacing it on upgraded R15 avatars
local function jointFrames(joint: Instance?): (CFrame?, CFrame?)
	if joint and joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	elseif joint and joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		if a0 and a1 then
			return a0.CFrame, a1.CFrame
		end
	end
	return nil, nil
end

--[[
	Where the carried Core sits (HumanoidRootPart space): just in front of the chest, low enough that both hands
	reach the lower sides of the shell (the client's Anim bends the arms onto it), yawed 22.5° so ring cubes sit
	between the hands. Measured from the rig's rest pose, so R6, R15 and scaled avatars all fit.
]]
local function carryOffset(character: Model, radius: number): CFrame
	local torso = character:FindFirstChild("UpperTorso")
	local torsoCF: CFrame? = nil
	local shoulder: CFrame? = nil
	local reach = 1.6
	if torso then
		local lower = character:FindFirstChild("LowerTorso")
		local r0, r1 = jointFrames(lower and lower:FindFirstChild("Root"))
		local w0, w1 = jointFrames(torso:FindFirstChild("Waist"))
		if r0 and r1 and w0 and w1 then
			torsoCF = r0 * r1:Inverse() * w0 * w1:Inverse()
		end
		local upperArm = character:FindFirstChild("RightUpperArm")
		local lowerArm = character:FindFirstChild("RightLowerArm")
		local hand = character:FindFirstChild("RightHand")
		local s0, s1 = jointFrames(upperArm and upperArm:FindFirstChild("RightShoulder"))
		local e0, e1 = jointFrames(lowerArm and lowerArm:FindFirstChild("RightElbow"))
		local h0 = jointFrames(hand and hand:FindFirstChild("RightWrist"))
		shoulder = s0
		if s1 and e0 and e1 and h0 then
			reach = (e0.Position - s1.Position).Magnitude + (h0.Position - e1.Position).Magnitude
		end
	else
		torso = character:FindFirstChild("Torso")
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local r0, r1 = jointFrames(rootPart and rootPart:FindFirstChild("RootJoint"))
		if r0 and r1 then
			torsoCF = r0 * r1:Inverse()
		end
		shoulder = jointFrames(torso and torso:FindFirstChild("Right Shoulder"))
		local arm = character:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			reach = arm.Size.Y * 0.8
		end
	end
	if not torso or not torso:IsA("BasePart") or not torsoCF or not shoulder then
		return CFrame.new(0, 0.9, -2.3) -- unknown rig
	end
	local front = (torsoCF * Vector3.new(0, 0, -torso.Size.Z / 2)).Z
	local height = (torsoCF * shoulder.Position).Y - reach * 0.3
	return CFrame.new(0, height, front - radius - 0.15) * CFrame.Angles(0, math.pi / 8, 0)
end

local function startCarry(player: Player, info: CoreInfo, shieldSeconds: number): boolean
	local character, hum, root = S.Player.GetCharacter(player)
	local data = S.Data.Get(player)
	if not character or not hum or not root or hum.Health <= 0 or not data or carries[player] then
		return false
	end
	local model = Models.Core(info.z, info.r, 0.95)
	model.Name = "CarriedCore"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local core = model.PrimaryPart :: BasePart
	local shell = model:FindFirstChild("Shell")
	local offset = carryOffset(character, if shell and shell:IsA("BasePart") then shell.Size.X / 2 else core.Size.X * 0.7)
	core.CFrame = root.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = core
	weld.C0 = offset
	weld.Parent = core

	local title = Items.CoreTitle(info.z, info.r)
	local bb = Instance.new("BillboardGui")
	bb.Name = "CarryInfo"
	bb.Size = UDim2.fromOffset(240, 46)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	bb.AlwaysOnTop = info.r >= 4
	bb.MaxDistance = 90 + info.r * 45
	bb.LightInfluence = 0
	bb.Adornee = core
	newLabel(bb, "Title", UDim2.new(1, 0, 0.55, 0), UDim2.new(), Items.RarityColor(info.r), Enum.Font.FredokaOne).Text = "📦 " .. title
	newLabel(bb, "Odds", UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0.56, 0), Color3.new(1, 1, 1), Enum.Font.GothamBlack).Text = Util.Odds(info.odds)
	bb.Parent = model
	model.Parent = character

	carries[player] = {
		info = info,
		model = model,
		character = character,
		shieldUntil = 0,
		stealImmuneUntil = 0,
		stealPrompt = nil,
		lastPos = root.Position,
	}
	character:SetAttribute("Carrying", true)
	character:SetAttribute("CarryRarity", info.r)
	player:SetAttribute("CarryTitle", title)
	player:SetAttribute("CarryRarity", info.r)
	player:SetAttribute("CarryOdds", info.odds)
	S.Player.SetWeaponVisible(character, false)
	S.Player.ApplyCharacterStats(player)
	setShield(player, character, shieldSeconds)

	data.carry = { z = info.z, r = info.r, odds = info.odds, mob = info.mob }
	if info.r >= 4 then
		S.Data.Save(player)
	end
	FX:FireAllClients("pickup", { pos = root.Position, rarity = info.r, player = player })
	return true
end

local function endCarry(player: Player): CoreInfo?
	local carry = carries[player]
	if not carry then
		return nil
	end
	carries[player] = nil
	local prompt = carry.stealPrompt
	if prompt then
		prompt:Destroy()
	end
	carry.model:Destroy()
	local character = carry.character
	if character and character.Parent then
		character:SetAttribute("Carrying", nil)
		character:SetAttribute("CarryRarity", nil)
		character:SetAttribute("ShieldUntil", nil)
		local ff = character:FindFirstChild("CoreShield")
		if ff then
			ff:Destroy()
		end
		S.Player.SetWeaponVisible(character, true)
	end
	player:SetAttribute("CarryTitle", nil)
	player:SetAttribute("CarryRarity", nil)
	player:SetAttribute("CarryOdds", nil)
	S.Player.ApplyCharacterStats(player)
	return carry.info
end

local function recordDiscovery(player: Player, info: CoreInfo)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	table.insert(data.best, { z = info.z, r = info.r, odds = info.odds, mob = info.mob, t = os.time() })
	table.sort(data.best, function(a, b)
		if a.odds == b.odds then
			return a.r > b.r
		end
		return a.odds > b.odds
	end)
	while #data.best > Config.MaxDiscoveries do
		table.remove(data.best)
	end
end

function CoreService.PickUp(player: Player, id: string)
	local ground = grounds[id]
	if not ground or not S.Data.Get(player) then
		return
	end
	local _, hum, root = S.Player.GetCharacter(player)
	if not hum or not root or hum.Health <= 0 then
		return
	end
	if carries[player] then
		S.Player.Notify(player, "You're already carrying a Core!", "error")
		return
	end
	if (root.Position - ground.pos).Magnitude > 16 then
		return
	end
	if ground.reservedFor ~= 0 and ground.reservedFor ~= player.UserId and now() < ground.reserveUntil then
		local owner = Players:GetPlayerByUserId(ground.reservedFor)
		S.Player.Notify(player, string.format("Reserved for %s for %ds", owner and owner.DisplayName or "its finder", math.ceil(ground.reserveUntil - now())), "error")
		return
	end
	if not S.Incubators.HasRoom(player, ground.info.r) then
		if ground.info.r <= 1 then
			S.Player.Notify(player, "Your inventory and Core Storage are full! Sell items first.", "error")
		else
			S.Player.Notify(player, "Your base is full! Open Cores or upgrade Core Storage first.", "error")
		end
		return
	end
	local info = ground.info
	removeGround(id)
	local data = S.Data.Get(player)
	local shield = (Config.Rarities[info.r].shield or 0) + (data.up.carry or 0) * Config.Upgrades.carry.shield
	if startCarry(player, info, shield) then
		S.Player.Notify(player, "Return to your base to secure the " .. Items.CoreTitle(info.z, info.r) .. "!", "carry", { rarity = info.r })
	end
end

function CoreService.Deliver(player: Player)
	local carry = carries[player]
	local data = S.Data.Get(player)
	if not carry or not data then
		return
	end
	local _, _, root = S.Player.GetCharacter(player)
	local info = endCarry(player) :: CoreInfo
	data.carry = false
	data.stats.delivered += 1
	recordDiscovery(player, info)
	local result = S.Incubators.AddCore(player, info)
	local title = Items.CoreTitle(info.z, info.r)
	local message = "CORE SECURED! " .. title
	if result == "incubating" then
		message ..= " is incubating."
	elseif result == "stored" then
		message ..= " went to storage."
	elseif result == "full" then
		message ..= " is waiting in storage: your inventory is full, sell items to open it."
	end
	S.Player.Notify(player, message, "secured", { rarity = info.r })
	FX:FireAllClients("deliver", { pos = root and root.Position or Vector3.zero, rarity = info.r, player = player })
	if info.r >= Config.AnnounceRarity then
		announce(player.DisplayName .. " secured a " .. title .. " (" .. Util.Odds(info.odds) .. ")!", info.r, false)
	end
	S.Plots.RefreshTrophies(player)
	S.Boards.MarkDirty(player)
	S.Player.MarkDirty(player)
	S.Badges.Check(player)
	if info.r >= 3 then
		S.Data.Save(player)
	end
end

-- Player chose to put the Core down (press G)
function CoreService.Drop(player: Player)
	local carry = carries[player]
	local _, _, root = S.Player.GetCharacter(player)
	if not carry or not root then
		return
	end
	local pos = root.Position + root.CFrame.LookVector * 4
	local info = endCarry(player) :: CoreInfo
	local data = S.Data.Get(player)
	if data then
		data.carry = false
	end
	CoreService.SpawnGround(info, pos, player, Config.Cores.ManualDropReserve, math.max(Config.Cores.MinDespawnAfterDrop, Config.Cores.Despawn), false)
	S.Player.Notify(player, "You put the Core down. It stays reserved for you for " .. Config.Cores.ManualDropReserve .. "s.", "info")
end

function CoreService.OnDeath(player: Player, pos: Vector3)
	local carry = carries[player]
	if not carry then
		return
	end
	local inRift = (player:GetAttribute("RiftZone") or 0) > 0
	local dropPos = inRift and Util.RiftReturnPos() or pos
	local info = endCarry(player) :: CoreInfo
	local data = S.Data.Get(player)
	if data then
		data.carry = false
		data.stats.lost += 1
	end
	CoreService.SpawnGround(info, dropPos, player, Config.Cores.DeathReserve, Config.Cores.Despawn, true)
	local title = Items.CoreTitle(info.z, info.r)
	S.Player.Notify(player, "You dropped your " .. title .. "! It's reserved for you for " .. Config.Cores.DeathReserve .. "s — go get it back!", "error", { rarity = info.r })
	if info.r >= Config.AnnounceRarity then
		announce(player.DisplayName .. " dropped a " .. title .. "! It's up for grabs soon...", info.r, false)
	end
end

function CoreService.Steal(thief: Player, victim: Player)
	if Config.PvP.Mode == "Off" or thief == victim then
		return
	end
	local carry = carries[victim]
	if not carry then
		return
	end
	if carries[thief] then
		S.Player.Notify(thief, "Your hands are full!", "error")
		return
	end
	local _, thiefHum, thiefRoot = S.Player.GetCharacter(thief)
	local victimChar, victimHum, victimRoot = S.Player.GetCharacter(victim)
	if not thiefHum or not thiefRoot or thiefHum.Health <= 0 or not victimChar or not victimHum or not victimRoot then
		return
	end
	if (thiefRoot.Position - victimRoot.Position).Magnitude > Config.PvP.StealRange + 4 then
		return
	end
	if not Util.IsContested(Util.PlayerZone(victim, victimRoot.Position)) or (victim:GetAttribute("RiftZone") or 0) > 0 then
		return
	end
	if os.clock() < carry.shieldUntil or os.clock() < carry.stealImmuneUntil then
		return
	end

	local info = endCarry(victim) :: CoreInfo
	local victimData = S.Data.Get(victim)
	if victimData then
		victimData.carry = false
		victimData.stats.lost += 1
	end

	-- knock the victim down
	victimChar:SetAttribute("Stunned", true)
	victimHum.PlatformStand = true
	victimRoot.AssemblyLinearVelocity = Util.FlatUnit(victimRoot.Position - thiefRoot.Position) * 45 + Vector3.new(0, 25, 0)
	S.Player.ApplyCharacterStats(victim)
	task.delay(Config.PvP.StunTime, function()
		if victimChar.Parent then
			victimChar:SetAttribute("Stunned", nil)
			victimHum.PlatformStand = false
			S.Player.ApplyCharacterStats(victim)
		end
	end)

	if startCarry(thief, info, 0) then
		local newCarry = carries[thief]
		if newCarry then
			newCarry.stealImmuneUntil = os.clock() + Config.PvP.StealImmunity
		end
		local thiefData = S.Data.Get(thief)
		if thiefData then
			thiefData.stats.stolen += 1
			S.Badges.Check(thief)
		end
		local title = Items.CoreTitle(info.z, info.r)
		S.Player.Notify(victim, thief.DisplayName .. " stole your " .. title .. "! Chase them down!", "error", { rarity = info.r })
		S.Player.Notify(thief, "You stole a " .. title .. "! Get it home!", "carry", { rarity = info.r })
		if info.r >= 3 then
			announce(thief.DisplayName .. " stole " .. victim.DisplayName .. "'s " .. title .. "!", info.r, false)
		end
		FX:FireAllClients("steal", { pos = victimRoot.Position, rarity = info.r })
	else
		CoreService.SpawnGround(info, victimRoot.Position, nil, 0, Config.Cores.Despawn, false)
	end
end

local function updateStealPrompt(player: Player, carry: Carry, root: BasePart)
	local zone = Util.PlayerZone(player, root.Position)
	local stealable = Config.PvP.Mode ~= "Off"
		and Util.IsContested(zone)
		and (player:GetAttribute("RiftZone") or 0) == 0
		and os.clock() >= carry.shieldUntil
		and os.clock() >= carry.stealImmuneUntil
	if stealable and not carry.stealPrompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal Core"
		prompt.ObjectText = player.DisplayName .. "'s " .. Items.CoreTitle(carry.info.z, carry.info.r)
		prompt.HoldDuration = Config.PvP.StealHold
		prompt.MaxActivationDistance = Config.PvP.StealRange
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.Parent = root
		prompt.PromptButtonHoldBegan:Connect(function(thief)
			if thief ~= player then
				S.Player.Notify(player, "⚠ " .. thief.DisplayName .. " is stealing your Core! RUN!", "danger")
			end
		end)
		prompt.Triggered:Connect(function(thief)
			CoreService.Steal(thief, player)
		end)
		carry.stealPrompt = prompt
	elseif not stealable and carry.stealPrompt then
		local prompt = carry.stealPrompt
		carry.stealPrompt = nil
		if prompt then
			prompt:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- Drops from kills
--------------------------------------------------------------------------------
function CoreService.TryDrop(player: Player, mob: any)
	local odds = Items.DropTable(mob.zone, mob.tier)
	local luck = S.Player.GetLuck(player) * Items.Richness(mob.zone)
	local rarity: number? = nil
	for r = #odds, 1, -1 do
		if odds[r] > 0 and rng:NextNumber() < math.min(luck / odds[r], 0.95) then
			rarity = r
			break
		end
	end
	if not rarity then
		return
	end
	local info: CoreInfo = { z = mob.zone, r = rarity, odds = Items.Odds(mob.zone, rarity, mob.tier), mob = mob.def.name }
	local pos = mob.root.Position
	CoreService.SpawnGround(info, pos, player, Config.Cores.Reserve, Config.Cores.Despawn, false)
	local data = S.Data.Get(player)
	if data then
		data.stats.cores += 1
	end
	local title = Items.CoreTitle(info.z, rarity)
	S.Player.Notify(player, "A Core has dropped! " .. title .. " (" .. Util.Odds(info.odds) .. ")", "drop", { rarity = rarity })
	FX:FireAllClients("coreDrop", { pos = pos, rarity = rarity, player = player })
	if rarity >= Config.AnnounceRarity then
		local text = player.DisplayName .. " found a " .. title .. " (" .. Util.Odds(info.odds) .. ")!"
		announce(text, rarity, rarity >= Config.GlobalAnnounceRarity)
	end
end

-- Moves every ground Core near `center` to `target` (used when a Rift arena closes)
function CoreService.Relocate(center: Vector3, radius: number, target: Vector3, owner: Player?)
	local k = 0
	for _, ground in grounds do
		if (ground.pos - center).Magnitude <= radius then
			k += 1
			local pos = target + Vector3.new(math.cos(k) * 5, 0, math.sin(k) * 5)
			local newCenter = Vector3.new(pos.X, groundY(pos) + 2.8, pos.Z)
			ground.model:PivotTo(CFrame.new(newCenter))
			ground.pos = newCenter
			ground.model:SetAttribute("Base", newCenter)
			if owner and ground.reservedFor == owner.UserId then
				ground.reserveUntil = math.max(ground.reserveUntil, now() + Config.Cores.DeathReserve)
				ground.model:SetAttribute("ReserveUntil", ground.reserveUntil)
			end
		end
	end
end

-- Admin/testing: drop a Core right in front of a player
function CoreService.GiveGround(player: Player, z: number, r: number)
	local _, _, root = S.Player.GetCharacter(player)
	if not root then
		return
	end
	local info: CoreInfo = { z = z, r = r, odds = math.max(1, Items.Odds(z, r, "normal")), mob = "Admin" }
	CoreService.SpawnGround(info, root.Position + root.CFrame.LookVector * 8, player, Config.Cores.Reserve, Config.Cores.Despawn, false)
	FX:FireAllClients("coreDrop", { pos = root.Position + root.CFrame.LookVector * 8, rarity = r, player = player })
end

--------------------------------------------------------------------------------
-- Leaving, autosave snapshots, rejoining
--------------------------------------------------------------------------------
local function carryPosition(player: Player, carry: Carry): Vector3
	if (player:GetAttribute("RiftZone") or 0) > 0 then
		return Util.RiftReturnPos()
	end
	local _, _, root = S.Player.GetCharacter(player)
	return root and root.Position or carry.lastPos
end

function CoreService.Snapshot(player: Player)
	local carry = carries[player]
	local data = S.Data.Get(player)
	if carry and data then
		local p = carryPosition(player, carry)
		data.carry = { z = carry.info.z, r = carry.info.r, odds = carry.info.odds, mob = carry.info.mob, p = { p.X, p.Y, p.Z } }
	end
end

function CoreService.OnLeave(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local carry = carries[player]
	if carry then
		CoreService.Snapshot(player)
		endCarry(player)
		return
	end
	-- A Core this player dropped on death is still reserved for them: keep it safe
	for id, ground in grounds do
		if ground.deathDrop and ground.reservedFor == player.UserId and now() < ground.reserveUntil then
			local p = ground.pos
			data.carry = { z = ground.info.z, r = ground.info.r, odds = ground.info.odds, mob = ground.info.mob, p = { p.X, p.Y, p.Z } }
			removeGround(id)
			break
		end
	end
end

function CoreService.Resume(player: Player)
	local data = S.Data.Get(player)
	local saved = data and data.carry
	if type(saved) ~= "table" or carries[player] then
		return
	end
	local info = copyInfo(saved)
	if not Config.Rarities[info.r] then
		data.carry = false
		return
	end
	local target: Vector3
	local p = saved.p
	if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
		target = Vector3.new(p[1], p[2], p[3])
	else
		target = Util.ZoneEntry(math.clamp(info.z, 1, data.zones))
	end
	if target.Y < -40 or target.Y > 300 or target.X > Util.WorldEndX() + 10 or target.X < -360 or math.abs(target.Z) > 140 then
		target = Util.ZoneEntry(math.clamp(info.z, 1, data.zones))
	end
	S.Player.Teleport(player, CFrame.new(target + Vector3.new(0, 3, 0)))
	task.wait(0.2)
	if startCarry(player, info, Config.Cores.ResumeShield) then
		S.Player.Notify(player, "Welcome back! You're still carrying your " .. Items.CoreTitle(info.z, info.r) .. " — bring it home!", "carry", { rarity = info.r })
	end
end

function CoreService.Init(services: any)
	S = services
	FX = Net.Event("FX")
end

function CoreService.Start()
	coresFolder = Instance.new("Folder")
	coresFolder.Name = "GroundCores"
	coresFolder.Parent = workspace
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { coresFolder }
	rayParams.CollisionGroup = "Mobs"
	rayParams.IgnoreWater = true

	S.Player.HandleAction("drop", function(player)
		CoreService.Drop(player)
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(GLOBAL_TOPIC, function(message)
				local d = message.Data
				if type(d) == "table" and d.job ~= game.JobId and type(d.text) == "string" then
					S.Player.NotifyAll("🌍 " .. d.text, "announce", { rarity = tonumber(d.r) or 6 })
				end
			end)
		end)
		if not ok then
			warn("[Cores] Global announcements unavailable: " .. tostring(err))
		end
	end)

	-- carriers: delivery, steal prompts, safety
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player, carry in carries do
				local character, hum, root = S.Player.GetCharacter(player)
				if not character or character ~= carry.character or not hum or not root then
					-- character vanished without a death event: drop the Core where it was
					local info = endCarry(player)
					if info then
						local data = S.Data.Get(player)
						if data then
							data.carry = false
						end
						CoreService.SpawnGround(info, carry.lastPos, player, Config.Cores.DeathReserve, Config.Cores.Despawn, true)
					end
					continue
				end
				if hum.Health <= 0 then
					continue
				end
				local pos = root.Position
				carry.lastPos = pos
				if S.Plots.IsOnOwnPlot(player, pos) then
					CoreService.Deliver(player)
					continue
				end
				if pos.Y < -60 then
					local zone = math.max(Util.ZoneAtX(pos.X), 1)
					S.Player.Teleport(player, CFrame.new(Util.ZoneEntry(zone)))
				end
				updateStealPrompt(player, carry, root)
			end
		end
	end)

	-- despawn old ground Cores
	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			for id, ground in grounds do
				if t >= ground.despawnAt then
					removeGround(id)
				end
			end
		end
	end)
end

return CoreService
