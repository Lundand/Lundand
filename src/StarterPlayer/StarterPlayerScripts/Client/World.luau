--[[
	World (client) — makes the shared world feel alive for this player:
	* blends lighting/atmosphere per zone and shows a banner when you enter one
	* gate barriers are solid only while you lack the Power to pass
	* live countdowns on incubators and ground Cores, spinning/bobbing Cores and trophies
	* hides prompts you can't use (your own steal prompt, other players' bases)
	* while carrying: a beam and a waypoint that point to your base
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Notify = require(script.Parent.Notify)

local World = {}

local player = Players.LocalPlayer
local currentZone: number? = nil
local barriers: { BasePart } = {}
local groundBase: { [Model]: Vector3 } = {}
local spinners: { [Model]: CFrame } = {} -- tag "Spin": decorative models that turn (attributes SpinSpeed, Bob)
local beam: Beam? = nil
local beamA0: Attachment? = nil
local beamA1: Attachment? = nil
local waypoint: BillboardGui? = nil

local function lightFor(zone: number): any
	if zone > #Config.Zones then
		return Config.RiftLight
	elseif zone <= 0 then
		return Config.SpawnLight
	end
	return Config.Zones[zone].light
end

local function applyLighting(zone: number, instant: boolean)
	local l = lightFor(zone)
	local info = TweenInfo.new(instant and 0 or 2, Enum.EasingStyle.Sine)
	local function go(inst: Instance?, props: { [string]: any })
		if inst then
			TweenService:Create(inst, info, props):Play()
		end
	end
	local clockDelta = math.abs(Lighting.ClockTime - l.clock)
	if clockDelta > 10 or instant then
		Lighting.ClockTime = l.clock
	else
		go(Lighting, { ClockTime = l.clock })
	end
	go(Lighting, { Ambient = l.ambient, OutdoorAmbient = l.outdoor, FogColor = l.fog, FogEnd = l.fogEnd })
	go(Lighting:FindFirstChildOfClass("Atmosphere"), { Color = l.atmo, Decay = l.atmo:Lerp(Color3.new(0, 0, 0), 0.4), Density = l.density })
	go(Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), { TintColor = l.tint, Saturation = l.sat })
end

local function zoneBanner(zone: number)
	if zone > #Config.Zones then
		return -- the Rift sends its own banner
	end
	if zone <= 0 then
		Notify.Banner("SPAWN & BASES", "Safe zone", Color3.fromRGB(140, 220, 255), 1.8, false)
		return
	end
	local z = Config.Zones[zone]
	local sub = "Recommended Power: " .. Util.Abbrev(z.rec)
	local contested = Util.IsContested(zone) and (workspace:GetAttribute("PvPMode") or Config.PvP.Mode) ~= "Off"
	if contested then
		sub ..= "   ⚠ CONTESTED — Cores can be stolen here!"
	end
	Notify.Banner(string.upper(z.name), sub, contested and Color3.fromRGB(255, 110, 90) or z.coreColor, 2.4, false)
end

local function currentZoneOf(): number
	local rift = player:GetAttribute("RiftZone")
	if type(rift) == "number" and rift > 0 then
		return rift
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return Util.ZoneAtX(root.Position.X)
	end
	return 0
end

--------------------------------------------------------------------------------
-- Gates
--------------------------------------------------------------------------------
local function refreshBarriers()
	local power = tonumber(player:GetAttribute("Power")) or 0
	local zoneMax = tonumber(player:GetAttribute("ZoneMax")) or 1
	for _, barrier in barriers do
		local zone = tonumber(barrier:GetAttribute("Zone")) or 1
		local open = zone <= zoneMax or power >= Items.Required(zone)
		barrier.CanCollide = not open
		barrier.Transparency = open and 0.82 or 0.15
		barrier.Color = open and Config.Zones[zone].coreColor or Color3.fromRGB(255, 70, 70)
	end
end

local function collectBarriers()
	table.clear(barriers)
	local world = workspace:FindFirstChild("World")
	if not world then
		return
	end
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Barrier" then
			table.insert(barriers, d)
		end
	end
	refreshBarriers()
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------
local function myPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot :: Model
		end
	end
	return nil
end
World.MyPlot = myPlot

local function fixPrompt(prompt: ProximityPrompt)
	if prompt.Name == "StealPrompt" then
		local character = player.Character
		if character and prompt:IsDescendantOf(character) then
			prompt.Enabled = false
		end
		return
	end
	if prompt.Name == "OpenPrompt" then
		local plot = prompt:FindFirstAncestorWhichIsA("Model")
		while plot and not plot:GetAttribute("PlotIndex") do
			plot = plot.Parent and plot.Parent:FindFirstAncestorWhichIsA("Model")
		end
		if plot then
			prompt.Enabled = plot:GetAttribute("OwnerId") == player.UserId
		end
	end
end

local function watchPlots(plots: Instance)
	local function scan()
		for _, d in plots:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				fixPrompt(d)
			end
		end
	end
	plots.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(fixPrompt, d)
		end
	end)
	for _, plot in plots:GetChildren() do
		plot:GetAttributeChangedSignal("OwnerId"):Connect(scan)
	end
	plots.ChildAdded:Connect(function(plot)
		plot:GetAttributeChangedSignal("OwnerId"):Connect(scan)
		task.defer(scan)
	end)
	scan()
end

local function watchCharacter(character: Model)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(fixPrompt, d)
		end
	end)
end

--------------------------------------------------------------------------------
-- Carry guide
--------------------------------------------------------------------------------
local function clearGuide()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if beamA0 then
		beamA0:Destroy()
		beamA0 = nil
	end
	if beamA1 then
		beamA1:Destroy()
		beamA1 = nil
	end
	if waypoint then
		waypoint:Destroy()
		waypoint = nil
	end
end

local function updateGuide()
	local carrying = player:GetAttribute("CarryTitle") ~= nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plot = myPlot()
	local pad = plot and plot:FindFirstChild("DeliveryPad")
	if not carrying or not root or not pad or not pad:IsA("BasePart") then
		clearGuide()
		return
	end
	local r = tonumber(player:GetAttribute("CarryRarity")) or 1
	local color = Items.RarityColor(r)
	if not beam or beam.Parent == nil or (beamA0 and beamA0.Parent ~= root) then
		clearGuide()
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, -1.5, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = pad
		a1.WorldPosition = pad.Position + Vector3.new(0, 1, 0) -- the pad is a rotated cylinder, so place it in world space
		beamA0 = a0
		beamA1 = a1
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Width0 = 0.9
		b.Width1 = 0.9
		b.LightEmission = 1
		b.Segments = 1
		b.Transparency = NumberSequence.new(0.35)
		b.Parent = pad
		beam = b
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(200, 60)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.StudsOffset = Vector3.new(0, 9, 0)
		bb.Adornee = a1
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = bb
		bb.Parent = player:WaitForChild("PlayerGui")
		waypoint = bb
	end
	if beam then
		beam.Color = ColorSequence.new(color)
	end
	if waypoint then
		local label = waypoint:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = "🏠 YOUR BASE\n" .. math.floor(((root :: BasePart).Position - pad.Position).Magnitude) .. "m"
		end
	end
end

--------------------------------------------------------------------------------
-- Timers on billboards
--------------------------------------------------------------------------------
local function setLabel(bb: Instance?, name: string, text: string)
	local label = bb and bb:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function tickTimers()
	local now = workspace:GetServerTimeNow()
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			for _, inc in plot:GetChildren() do
				if inc:GetAttribute("State") == "incubating" then
					local left = (tonumber(inc:GetAttribute("EndTime")) or 0) - now
					setLabel(inc:FindFirstChild("Info"), "Timer", left > 0 and ("⏳ " .. Util.Clock(left)) or "READY!")
				end
			end
		end
	end
	local cores = workspace:FindFirstChild("GroundCores")
	if cores then
		for _, model in cores:GetChildren() do
			local reservedFor = tonumber(model:GetAttribute("ReservedFor")) or 0
			local reserveLeft = (tonumber(model:GetAttribute("ReserveUntil")) or 0) - now
			local despawnLeft = (tonumber(model:GetAttribute("DespawnAt")) or 0) - now
			local text
			if reservedFor ~= 0 and reserveLeft > 0 then
				if reservedFor == player.UserId then
					text = "✅ Reserved for YOU (" .. Util.Clock(reserveLeft) .. ")"
				else
					text = "🔒 " .. tostring(model:GetAttribute("ReservedName") or "?") .. " (" .. Util.Clock(reserveLeft) .. ")"
				end
			else
				text = "Anyone can grab it! • " .. Util.Clock(despawnLeft)
			end
			setLabel(model:FindFirstChild("Info"), "Status", text)
		end
	end
end

function World.Init()
	task.spawn(function()
		workspace:WaitForChild("World", 60)
		collectBarriers()
	end)
	player:GetAttributeChangedSignal("Power"):Connect(refreshBarriers)
	player:GetAttributeChangedSignal("ZoneMax"):Connect(refreshBarriers)

	task.spawn(function()
		local plots = workspace:WaitForChild("Plots", 60)
		if plots then
			watchPlots(plots)
		end
	end)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(character)
		clearGuide()
	end)

	-- Zone lighting + banners
	task.spawn(function()
		while true do
			local zone = currentZoneOf()
			if zone ~= currentZone then
				local first = currentZone == nil
				currentZone = zone
				applyLighting(zone, first)
				if not first then
					zoneBanner(zone)
				end
			end
			task.wait(0.3)
		end
	end)

	-- Timers + carry guide
	task.spawn(function()
		while true do
			pcall(tickTimers)
			pcall(updateGuide)
			task.wait(0.25)
		end
	end)

	-- Decorative spinners (the Great Core, trophies, incubating Cores, base crests)
	local function addSpinner(inst: Instance)
		if inst:IsA("Model") and not spinners[inst] then
			spinners[inst] = inst:GetPivot()
		end
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(function(inst)
		task.defer(addSpinner, inst) -- wait a frame so the server-set pivot has arrived
	end)
	CollectionService:GetInstanceRemovedSignal("Spin"):Connect(function(inst)
		if inst:IsA("Model") then
			spinners[inst] = nil
		end
	end)
	for _, inst in CollectionService:GetTagged("Spin") do
		addSpinner(inst)
	end

	-- Ground Cores and spinners spin and bob
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local camPos = workspace.CurrentCamera.CFrame.Position
		for model, base in spinners do
			if model.Parent == nil then
				spinners[model] = nil
			elseif (base.Position - camPos).Magnitude < 300 then
				local speed = tonumber(model:GetAttribute("SpinSpeed")) or 0.6
				local bob = tonumber(model:GetAttribute("Bob")) or 0
				model:PivotTo(base * CFrame.new(0, math.sin(t * 1.6) * bob, 0) * CFrame.Angles(0, t * speed, 0))
			end
		end
		local cores = workspace:FindFirstChild("GroundCores")
		if not cores then
			return
		end
		for _, model in cores:GetChildren() do
			if model:IsA("Model") then
				local attr = model:GetAttribute("Base")
				local base = typeof(attr) == "Vector3" and attr or groundBase[model]
				if not base then
					base = model:GetPivot().Position
					groundBase[model] = base
					model.Destroying:Connect(function()
						groundBase[model] = nil
					end)
				end
				if (base - camPos).Magnitude < 250 then
					model:PivotTo(CFrame.new(base + Vector3.new(0, math.sin(t * 2) * 0.35, 0)) * CFrame.Angles(0, t * 1.4, 0))
				end
			end
		end
	end)
end

return World
