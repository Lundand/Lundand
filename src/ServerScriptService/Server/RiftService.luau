--[[
	RiftService — the Endless Rift (Zone 9, 10, 11 ...).
	The portal at the end of the Void opens a personal arena in the sky. Clear the wave to open
	the portal to the next zone; enemies and rewards grow every zone (Config.Rift.Growth).
	Rift Cores still have to be carried home: the exit portal drops you at the end of the Void,
	so the whole walk back is part of the risk.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))

local RiftService = {}
local S: any

local UP = CFrame.Angles(0, 0, math.pi / 2)

type Arena = {
	player: Player,
	slot: number,
	center: Vector3,
	folder: Folder,
	zone: number,
	spawner: any,
	cleared: boolean,
	platform: BasePart,
	rim: BasePart,
	nextPortal: BasePart,
	nextPrompt: ProximityPrompt,
	sign: TextLabel,
	closing: boolean,
}

local arenas: { [Player]: Arena } = {}
local usedSlots: { [number]: boolean } = {}
local rootFolder: Folder

local function P(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function zoneColors(zone: number): (Color3, Color3)
	local hue = (zone * 0.085) % 1
	return Color3.fromHSV(hue, 0.55, 0.32), Color3.fromHSV(hue, 0.75, 1)
end

local function portal(parent: Instance, center: Vector3, color: Color3, label: string): (BasePart, ProximityPrompt)
	local c = center + Vector3.new(0, 7, 0)
	for k = 0, 11 do
		local a = k * math.pi * 2 / 12
		local seg = P(parent, "PortalRing", Vector3.new(1.4, 1.4, 2.6), CFrame.new(c + Vector3.new(0, math.cos(a) * 6, math.sin(a) * 6)) * CFrame.Angles(a, 0, 0), color, Enum.Material.Neon, false)
		seg.CastShadow = false
	end
	local disc = P(parent, "Portal", Vector3.new(0.4, 11, 11), CFrame.new(c), color, Enum.Material.ForceField, false, Enum.PartType.Cylinder)
	disc.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = label
	prompt.ObjectText = "Rift Portal"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = disc
	return disc, prompt
end

local function paint(arena: Arena)
	local base, glow = zoneColors(arena.zone)
	arena.platform.Color = base
	arena.rim.Color = glow
	arena.sign.Text = "∞ ENDLESS ZONE " .. arena.zone
	arena.sign.TextColor3 = glow
end

local function buildArena(arena: Arena)
	local c = arena.center
	local R = Config.World.RiftRadius
	local folder = arena.folder
	arena.platform = P(folder, "Platform", Vector3.new(6, R * 2, R * 2), CFrame.new(c - Vector3.new(0, 3, 0)) * UP, Color3.new(0.2, 0.2, 0.3), Enum.Material.Slate, true, Enum.PartType.Cylinder)
	arena.rim = P(folder, "Rim", Vector3.new(0.7, R * 2 + 3, R * 2 + 3), CFrame.new(c - Vector3.new(0, 0.5, 0)) * UP, Color3.new(1, 1, 1), Enum.Material.Neon, false, Enum.PartType.Cylinder)
	arena.rim.CastShadow = false
	for k = 0, 23 do
		local a = k * math.pi * 2 / 24
		local pos = c + Vector3.new(math.cos(a) * (R + 1), 18, math.sin(a) * (R + 1))
		local wall = P(folder, "Wall", Vector3.new(2, 44, (R + 1) * 2 * math.pi / 24 + 1), CFrame.lookAt(pos, c + Vector3.new(0, 18, 0)) * CFrame.Angles(0, math.pi / 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true)
		wall.Transparency = 1
	end
	local _, glow = zoneColors(arena.zone)
	for k = 0, 5 do
		local a = k * math.pi / 3 + math.pi / 6
		local pos = c + Vector3.new(math.cos(a) * (R - 6), 0, math.sin(a) * (R - 6))
		P(folder, "Pillar", Vector3.new(4, 16, 4), CFrame.new(pos + Vector3.new(0, 8, 0)), Color3.fromRGB(25, 25, 40), Enum.Material.Slate, true)
		local top = P(folder, "PillarTop", Vector3.new(3, 3, 3), CFrame.new(pos + Vector3.new(0, 18, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), glow, Enum.Material.Neon, false)
		top.CastShadow = false
	end

	local exitPortal, exitPrompt = portal(folder, c + Vector3.new(-(R - 12), 0, 0), Color3.fromRGB(255, 255, 255), "Leave the Rift")
	exitPortal.Name = "ExitPortal"
	exitPrompt.Triggered:Connect(function(who)
		if who == arena.player then
			RiftService.Leave(who, false)
		end
	end)
	local nextPortal, nextPrompt = portal(folder, c + Vector3.new(R - 12, 0, 0), glow, "Enter the next zone")
	nextPortal.Name = "NextPortal"
	nextPrompt.Enabled = false
	nextPortal.Transparency = 1
	nextPrompt.Triggered:Connect(function(who)
		if who == arena.player and arena.cleared then
			RiftService.Next(who)
		end
	end)
	arena.nextPortal = nextPortal
	arena.nextPrompt = nextPrompt

	local anchor = P(folder, "SignAnchor", Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, 26, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
	anchor.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(420, 70)
	bb.MaxDistance = 400
	bb.LightInfluence = 0
	bb.Adornee = anchor
	local sign = Instance.new("TextLabel")
	sign.BackgroundTransparency = 1
	sign.Size = UDim2.fromScale(1, 1)
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.TextStrokeTransparency = 0.3
	sign.Parent = bb
	bb.Parent = anchor
	arena.sign = sign
	paint(arena)
end

local function startPos(arena: Arena): CFrame
	local R = Config.World.RiftRadius
	local pos = arena.center + Vector3.new(-(R - 26), 4, 0)
	return CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
end

local function setPortal(arena: Arena, open: boolean)
	arena.nextPrompt.Enabled = open
	arena.nextPortal.Transparency = open and 0 or 1
end

local function updateLeft(arena: Arena)
	local left = arena.spawner and S.Mobs.AliveCount(arena.spawner) or 0
	arena.player:SetAttribute("RiftLeft", left)
	if left == 0 and not arena.cleared and not arena.closing then
		arena.cleared = true
		setPortal(arena, true)
		S.Player.Notify(arena.player, "ZONE " .. arena.zone .. " CLEARED! Step into the portal to go deeper.", "unlock")
	end
end

local function startWave(arena: Arena)
	local zone = arena.zone
	local R = Config.Rift
	local entries = {
		{ mobId = R.Mobs[1], tier = "normal", count = math.ceil(R.WaveNormal / 2) },
		{ mobId = R.Mobs[2], tier = "normal", count = math.floor(R.WaveNormal / 2) },
		{ mobId = R.Elite, tier = "elite", count = R.WaveElite },
	}
	if zone % R.BossEvery == 0 then
		table.insert(entries, { mobId = R.Boss, tier = "boss", count = 1 })
	end
	arena.cleared = false
	setPortal(arena, false)
	arena.spawner = S.Mobs.CreateSpawner({
		zone = zone,
		region = { kind = "circle", center = arena.center, radius = Config.World.RiftRadius - 18, minX = 0, maxX = 0, minZ = 0, maxZ = 0 },
		entries = entries,
		owner = arena.player,
		wave = true,
		onDeath = function()
			updateLeft(arena)
		end,
	})
	arena.player:SetAttribute("RiftZone", zone)
	updateLeft(arena)
	S.Player.Notify(arena.player, "∞ ENDLESS ZONE " .. zone .. " — Recommended Power " .. Util.Abbrev(Items.Rec(zone)), "zone", { zone = zone })
end

local function reachZone(player: Player, zone: number)
	local data = S.Data.Get(player)
	if data and zone > (data.rift or 0) then
		data.rift = zone
		S.Player.UpdateZoneStat(player)
		S.Boards.MarkDirty(player)
		S.Player.MarkDirty(player)
		S.Badges.Check(player)
	end
end

local function destroyArena(arena: Arena)
	if arena.closing then
		return
	end
	arena.closing = true
	if arena.spawner then
		S.Mobs.RemoveSpawner(arena.spawner)
		arena.spawner = nil
	end
	-- Cores left on the platform go to the Rift return pad instead of vanishing with the arena
	pcall(S.Cores.Relocate, arena.center, Config.World.RiftRadius + 10, Util.RiftReturnPos(), arena.player)
	arena.folder:Destroy()
	usedSlots[arena.slot] = nil
	if arenas[arena.player] == arena then
		arenas[arena.player] = nil
	end
end

function RiftService.Enter(player: Player, restart: boolean): (boolean, string?)
	local data = S.Data.Get(player)
	if not data then
		return false, "Loading..."
	end
	if data.zones < #Config.Zones then
		return false, "Reach the " .. Config.Zones[#Config.Zones].name .. " to unlock the Endless Rift."
	end
	if arenas[player] then
		return false, "You're already in the Rift."
	end
	if S.Cores.GetCarry(player) then
		return false, "Deliver your Core before entering the Rift."
	end
	if not S.Player.IsAlive(player) then
		return false, "You can't enter right now."
	end
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	local folder = Instance.new("Folder")
	folder.Name = "Arena_" .. player.UserId
	folder.Parent = rootFolder
	local zone = restart and Config.Rift.StartZone or math.max(Config.Rift.StartZone, data.rift or 0)
	local arena: Arena = {
		player = player,
		slot = slot,
		center = Config.World.RiftOrigin + Vector3.new(0, 0, (slot - 1) * Config.World.RiftSpacing),
		folder = folder,
		zone = zone,
		spawner = nil,
		cleared = false,
		platform = nil :: any,
		rim = nil :: any,
		nextPortal = nil :: any,
		nextPrompt = nil :: any,
		sign = nil :: any,
		closing = false,
	}
	arenas[player] = arena
	buildArena(arena)
	player:SetAttribute("RiftZone", zone)
	S.Player.Teleport(player, startPos(arena))
	reachZone(player, zone)
	startWave(arena)
	return true, nil
end

function RiftService.Next(player: Player)
	local arena = arenas[player]
	if not arena or not arena.cleared then
		return
	end
	if arena.spawner then
		S.Mobs.RemoveSpawner(arena.spawner)
		arena.spawner = nil
	end
	arena.zone += 1
	paint(arena)
	S.Player.Teleport(player, startPos(arena))
	reachZone(player, arena.zone)
	startWave(arena)
end

-- noTeleport: the caller moves the player itself (travel menu)
function RiftService.Leave(player: Player, noTeleport: boolean)
	local arena = arenas[player]
	if not arena then
		return
	end
	player:SetAttribute("RiftZone", 0)
	player:SetAttribute("RiftLeft", nil)
	if not noTeleport then
		local pos = Util.RiftReturnPos()
		S.Player.Teleport(player, CFrame.lookAt(pos, pos - Vector3.new(1, 0, 0)))
	end
	destroyArena(arena)
end

function RiftService.OnDeath(player: Player)
	local arena = arenas[player]
	if not arena then
		return
	end
	player:SetAttribute("RiftZone", 0)
	player:SetAttribute("RiftLeft", nil)
	task.delay(0.5, function()
		destroyArena(arena)
	end)
end

function RiftService.OnLeave(player: Player)
	local arena = arenas[player]
	if arena then
		destroyArena(arena)
	end
end

function RiftService.Init(services: any)
	S = services
end

function RiftService.Start()
	rootFolder = Instance.new("Folder")
	rootFolder.Name = "RiftArenas"
	rootFolder.Parent = workspace

	local portalPart = S.World.RiftPortal
	local prompt = portalPart and portalPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			local ok, err = RiftService.Enter(player, false)
			if not ok and err then
				S.Player.Notify(player, err, "error")
			end
		end)
	end

	S.Player.Handle("rift", function(player, args)
		local ok, err = RiftService.Enter(player, args.restart == true)
		return { ok = ok, msg = err }
	end)

	-- keep players on their platform
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, arena in arenas do
				local _, hum, root = S.Player.GetCharacter(player)
				if hum and root and hum.Health > 0 and root.Position.Y < arena.center.Y - 40 then
					S.Player.Teleport(player, startPos(arena))
				end
			end
		end
	end)
end

return RiftService
