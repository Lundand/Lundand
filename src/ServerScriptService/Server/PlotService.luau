--[[
	PlotService — every player gets a personal base along the avenue west of spawn:
	* an entrance arch with the owner's name and avatar
	* a glowing delivery pad (walking onto your base with a Core secures it — see CoreService)
	* up to 12 incubators lining the carpet, with live timers
	* a trophy hall: your 3 best items float above pedestals, plus a "Rarest Cores Found" board
	* Base Style upgrades add lanterns & flowers, banners & hedges, towers, a crystal spire and gold
	The Base menu opens from the BASE button in the HUD (no terminal needed).

	Every surface sits at its own height so nothing flickers (z-fighting):
	ground 0 · foundation 0.9 · floor 1.15 · carpet 1.27 · incubator bays 1.4 · pad 1.5/1.65/1.8 · dais 2.15
	Labels use unrotated parts/attachments, so they always float above what they describe.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Util = require(Shared:WaitForChild("Util"))
local Models = require(Shared:WaitForChild("Models"))

local PlotService = {}
local S: any

local rgb = Color3.fromRGB
local UP = CFrame.Angles(0, 0, math.pi / 2) -- stands a Cylinder part upright
local MAX_PLOTS = 10
local PLOT_W, PLOT_D = 64, 84
local HALF_W, HALF_D = PLOT_W / 2, PLOT_D / 2
local MAX_INCUBATORS = 12
local FLOOR = 1.15 -- top of the floor
local PAD_LZ = -30 -- delivery pad (local z; the entrance is at -HALF_D)
local HALL_LZ = 34 -- trophy pedestals
local INCUBATOR_X = 15

local STONE = rgb(228, 222, 208)
local WALL = rgb(128, 132, 146)
local STONE_DARK = rgb(84, 88, 102)
local WOOD = rgb(176, 134, 90)
local GOLD = rgb(214, 172, 80)
local INK = rgb(30, 32, 46)
local METAL = rgb(62, 66, 80)
local PETALS = { rgb(255, 120, 160), rgb(255, 230, 90), rgb(255, 255, 255), rgb(180, 120, 255), rgb(255, 150, 70) }

local PALETTE = {
	rgb(90, 170, 255),
	rgb(255, 120, 120),
	rgb(120, 220, 120),
	rgb(255, 200, 80),
	rgb(190, 120, 255),
	rgb(255, 150, 70),
	rgb(80, 220, 210),
	rgb(255, 120, 200),
	rgb(170, 200, 90),
	rgb(150, 160, 255),
}

type Incubator = {
	model: Model,
	ring: BasePart,
	dome: BasePart,
	cap: BasePart,
	lamp: BasePart,
	info: BillboardGui,
	state: string,
	stamp: any,
	core: Model?,
}
type Plot = {
	index: number,
	center: Vector3,
	side: number,
	color: Color3,
	owner: Player?,
	model: Model,
	incubators: { Incubator },
	stands: { Vector3 },
	plaques: { SurfaceGui },
	trophies: Folder,
	style: Folder,
	board: TextLabel,
	signs: { SurfaceGui },
	pad: BasePart,
	styleLevel: number,
}

local plots: { Plot } = {}
local byPlayer: { [Player]: Plot } = {}
local folder: Folder

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function P(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.CanQuery = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Upright cylinder standing on `bottom`
local function vcyl(parent: Instance, name: string, bottom: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return P(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * UP, color, material, collide, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return P(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, material, collide, Enum.PartType.Ball)
end

local function text(parent: Instance, value: string, size: UDim2, pos: UDim2, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = value
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.45
	t.Parent = parent
	return t
end

local function surface(part: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pixelsPerStud
	sg.LightInfluence = 0
	sg.MaxDistance = 260
	sg.Adornee = part
	sg.Parent = part
	return sg
end

local function setText(parent: Instance, childName: string, value: string, color: Color3?)
	local label = parent:FindFirstChild(childName)
	if label and label:IsA("TextLabel") then
		label.Text = value
		if color then
			label.TextColor3 = color
		end
	end
end

local function setImage(parent: Instance, childName: string, image: string)
	local label = parent:FindFirstChild(childName)
	if label and label:IsA("ImageLabel") then
		label.Image = image
	end
end

-- A small model the clients spin (tag "Spin", see client World)
local function spinner(parent: Instance, name: string, center: Vector3, size: number, color: Color3, speed: number, bob: number): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = name
	local gem = P(m, "Gem", Vector3.new(size, size, size), CFrame.new(center) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color, Enum.Material.Neon, false)
	gem.CastShadow = false
	local pivot = P(m, "Pivot", Vector3.new(0.2, 0.2, 0.2), CFrame.new(center), color, Enum.Material.SmoothPlastic, false)
	pivot.Transparency = 1
	m.PrimaryPart = pivot
	m:SetAttribute("SpinSpeed", speed)
	m:SetAttribute("Bob", bob)
	CollectionService:AddTag(m, "Spin")
	m.Parent = parent
	return m, gem
end

local function lantern(parent: Instance, pos: Vector3, height: number)
	vcyl(parent, "LanternPost", pos, height, 0.5, rgb(45, 45, 55), Enum.Material.Metal, true)
	local top = pos + Vector3.new(0, height, 0)
	local glass = P(parent, "Lantern", Vector3.new(1.4, 1.8, 1.4), CFrame.new(top + Vector3.new(0, 0.9, 0)), rgb(255, 225, 160), Enum.Material.Glass, false)
	glass.Transparency = 0.3
	local flame = P(parent, "Flame", Vector3.new(0.6, 0.9, 0.6), CFrame.new(top + Vector3.new(0, 0.9, 0)), rgb(255, 205, 120), Enum.Material.Neon, false)
	flame.CastShadow = false
	P(parent, "LanternCap", Vector3.new(1.8, 0.35, 1.8), CFrame.new(top + Vector3.new(0, 1.98, 0)), rgb(45, 45, 55), Enum.Material.Metal, false)
	Models.Light(flame, rgb(255, 215, 150), 20, 1)
end

local function plotCenter(index: number): (Vector3, number)
	local side = index % 2 == 1 and 1 or -1
	local col = math.floor((index - 1) / 2)
	return Vector3.new(-24 - col * 72, 0, side * 62), side
end

-- Local plot coordinates: lx across the plot, lz from the entrance (-) to the back (+)
local function at(plot: Plot, lx: number, y: number, lz: number): Vector3
	return plot.center + Vector3.new(lx, y, lz * plot.side)
end

-- CFrame at a local position whose Front face looks out toward the entrance/avenue
local function facingOut(plot: Plot, lx: number, y: number, lz: number): CFrame
	local pos = at(plot, lx, y, lz)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -plot.side))
end

-- Box spanning local x0..x1, y0..y1, z0..z1
local function block(plot: Plot, parent: Instance, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	return P(parent, name, size, CFrame.new(at(plot, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), color, material, collide)
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------
local function buildIncubator(plot: Plot, slot: number): Incubator
	local row = math.ceil(slot / 2)
	local lx = (slot % 2 == 1 and -1 or 1) * INCUBATOR_X
	local lz = -24 + (row - 1) * 9
	local model = Instance.new("Model")
	model.Name = "Incubator" .. slot
	block(plot, model, "Bay", lx - 3.7, lx + 3.7, 0.95, 1.4, lz - 3.7, lz + 3.7, STONE, Enum.Material.Marble, true)
	local foot = at(plot, lx, 0, lz)
	vcyl(model, "Base", foot + Vector3.new(0, 1.2, 0), 1.5, 6, METAL, Enum.Material.Metal, true)
	local ring = vcyl(model, "Ring", foot + Vector3.new(0, 1.75, 0), 0.35, 6.3, rgb(120, 125, 140), Enum.Material.Neon, false)
	ring.CastShadow = false
	local dome = ball(model, "Dome", foot + Vector3.new(0, 4.65, 0), 5.2, rgb(200, 230, 255), Enum.Material.Glass, false)
	dome.Transparency = 0.65
	dome.CastShadow = false
	local cap = vcyl(model, "Cap", foot + Vector3.new(0, 7.05, 0), 0.45, 1.6, METAL, Enum.Material.Metal, false)
	local lamp = ball(model, "Lamp", foot + Vector3.new(0, 7.85, 0), 0.8, rgb(60, 60, 70), Enum.Material.SmoothPlastic, false)
	lamp.CastShadow = false

	local info = Instance.new("BillboardGui")
	info.Name = "Info"
	info.Size = UDim2.fromOffset(180, 54)
	info.StudsOffsetWorldSpace = Vector3.new(0, 4.9, 0) -- the dome is an unrotated ball, so "up" really is up
	info.MaxDistance = 40
	info.LightInfluence = 0
	info.Adornee = dome
	local title = text(info, "", UDim2.new(1, 0, 0.5, 0), UDim2.new(), rgb(220, 220, 230))
	title.Name = "Title"
	local timer = text(info, "", UDim2.new(1, 0, 0.45, 0), UDim2.new(0, 0, 0.52, 0), rgb(255, 255, 255))
	timer.Name = "Timer"
	info.Parent = model

	model:SetAttribute("Slot", slot)
	model:SetAttribute("State", "empty")
	model.Parent = plot.model
	return { model = model, ring = ring, dome = dome, cap = cap, lamp = lamp, info = info, state = "", stamp = nil, core = nil }
end

-- Visual state of one incubator: "off" (free base), "locked", "empty", "incubating", "ready"
local function setIncubatorLook(inc: Incubator, look: string, color: Color3?)
	local c = color or rgb(120, 125, 140)
	local closed = look == "off" or look == "locked"
	-- a locked slot is an empty socket: the glass dome appears once it's unlocked
	inc.cap.Transparency = closed and 1 or 0
	inc.lamp.Transparency = closed and 1 or 0
	inc.info.StudsOffsetWorldSpace = closed and Vector3.new(0, -1, 0) or Vector3.new(0, 4.9, 0)
	if closed then
		inc.ring.Color = rgb(52, 54, 62)
		inc.dome.Transparency = 1
		inc.info.MaxDistance = 26
	elseif look == "empty" then
		inc.ring.Color = rgb(125, 130, 145)
		inc.lamp.Color = rgb(190, 196, 210)
		inc.lamp.Material = Enum.Material.Neon
		inc.dome.Color = rgb(200, 230, 255)
		inc.dome.Transparency = 0.65
		inc.info.MaxDistance = 40
	else
		inc.ring.Color = c
		inc.lamp.Color = c
		inc.lamp.Material = Enum.Material.Neon
		inc.dome.Color = rgb(200, 230, 255)
		inc.dome.Transparency = 0.7
		inc.info.MaxDistance = 100
	end
end

local function buildArch(plot: Plot, build: Instance)
	local color = plot.color
	for _, sx in { -1, 1 } do
		local x0, x1 = sx < 0 and -11 or 8, sx < 0 and -8 or 11
		block(plot, build, "ArchPillar", x0, x1, 0.5, 13.4, -42.75, -39.75, STONE, Enum.Material.Marble, true)
		block(plot, build, "ArchPlinth", x0 - 0.4, x1 + 0.4, 0.5, 1.9, -43.15, -39.35, STONE_DARK, Enum.Material.Slate, true)
		-- wall sconce facing the avenue
		local bracket = P(build, "Sconce", Vector3.new(0.4, 0.4, 0.8), facingOut(plot, sx * 9.5, 8.6, -43.15), METAL, Enum.Material.Metal, false)
		bracket.CastShadow = false
		local lamp = P(build, "SconceLamp", Vector3.new(0.9, 1.3, 0.9), facingOut(plot, sx * 9.5, 9.2, -43.75), rgb(255, 214, 150), Enum.Material.Neon, false)
		lamp.CastShadow = false
		Models.Light(lamp, rgb(255, 214, 150), 16, 0.9)
	end
	-- the sign board spans the pillars; Front faces the avenue, Back faces into the base
	local sign = P(build, "ArchSign", Vector3.new(23, 4.2, 1.2), facingOut(plot, 0, 15, -41.25), INK, Enum.Material.SmoothPlastic, true)
	block(plot, build, "SignFrame", -11.8, 11.8, 17.1, 17.6, -42.05, -40.45, GOLD, Enum.Material.SmoothPlastic, true)
	block(plot, build, "SignFrame", -11.8, 11.8, 12.5, 12.9, -42.05, -40.45, GOLD, Enum.Material.SmoothPlastic, true)
	for _, sx in { -1, 1 } do
		local x0 = sx < 0 and -11.8 or 11.5
		block(plot, build, "SignFrame", x0, x0 + 0.3, 12.9, 17.1, -42.05, -40.45, GOLD, Enum.Material.SmoothPlastic, true)
	end
	block(plot, build, "CrestStand", -1.2, 1.2, 17.6, 18.4, -42.05, -40.45, GOLD, Enum.Material.SmoothPlastic, false)
	local _, gem = spinner(build, "Crest", at(plot, 0, 20.2, -41.25), 1.8, color, 1, 0.3)
	Models.Light(gem, color, 18, 1.2)

	plot.signs = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = surface(sign, face, 28)
		sg.Name = face == Enum.NormalId.Front and "OwnerSign" or "OwnerSignInside"
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = color
		avatar.BackgroundTransparency = 0
		avatar.Size = UDim2.new(0.84, 0, 0.84, 0)
		avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
		avatar.Position = UDim2.new(0.02, 0, 0.08, 0)
		avatar.ScaleType = Enum.ScaleType.Fit
		avatar.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = avatar
		avatar.Parent = sg
		local owner = text(sg, "FREE BASE", UDim2.new(0.76, 0, 0.56, 0), UDim2.new(0.21, 0, 0.06, 0), rgb(255, 255, 255))
		owner.Name = "Owner"
		local sub = text(sg, "", UDim2.new(0.76, 0, 0.3, 0), UDim2.new(0.21, 0, 0.64, 0), color, Enum.Font.GothamBold)
		sub.Name = "Sub"
		table.insert(plot.signs, sg)
	end
end

local function buildPad(plot: Plot, build: Instance)
	local color = plot.color
	local center = at(plot, 0, 0, PAD_LZ)
	local base = vcyl(build, "PadBase", center + Vector3.new(0, 1.0, 0), 0.5, 15, STONE_DARK, Enum.Material.Slate, true)
	base.CastShadow = false
	local pad = vcyl(plot.model, "DeliveryPad", center + Vector3.new(0, 1.45, 0), 0.2, 13.4, color, Enum.Material.Neon, false)
	pad.Transparency = 0.1
	pad.CastShadow = false
	plot.pad = pad
	local middle = vcyl(build, "PadCenter", center + Vector3.new(0, 1.6, 0), 0.2, 9.4, INK, Enum.Material.Slate, false)
	middle.CastShadow = false
	local rise = Instance.new("ParticleEmitter")
	rise.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rise.Color = ColorSequence.new(color)
	rise.LightEmission = 1
	rise.Rate = 4
	rise.Lifetime = NumberRange.new(1.5, 2.5)
	rise.Speed = NumberRange.new(2, 4)
	rise.SpreadAngle = Vector2.new(8, 8)
	rise.EmissionDirection = Enum.NormalId.Right -- the cylinder's +X points up
	rise.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	rise.Parent = pad
	local _, gem = spinner(build, "PadBeacon", center + Vector3.new(0, 4.6, 0), 1.4, color, 1.4, 0.4)
	gem.Transparency = 0.2
	Models.Light(gem, color, 16, 1)
	for k = 0, 3 do
		local a = math.rad(45 + k * 90)
		local p = center + Vector3.new(math.cos(a) * 8.9, 0, math.sin(a) * 8.9)
		vcyl(build, "Bollard", p + Vector3.new(0, FLOOR - 0.05, 0), 1.45, 0.8, METAL, Enum.Material.Metal, true)
		local top = ball(build, "BollardLight", p + Vector3.new(0, FLOOR + 1.75, 0), 0.9, color, Enum.Material.Neon, false)
		top.CastShadow = false
	end
end

local function buildHall(plot: Plot, build: Instance)
	local roofColor = plot.color:Lerp(rgb(70, 70, 80), 0.3)
	block(plot, build, "DaisStep", -23.5, 23.5, 0.95, 1.65, 27, 28.4, STONE, Enum.Material.Marble, true)
	block(plot, build, "Dais", -23.5, 23.5, 0.95, 2.15, 28.4, 40.5, STONE, Enum.Material.Marble, true)
	block(plot, build, "HallWall", -23.5, 23.5, 0.9, 21, 40.5, 42, rgb(234, 228, 216), Enum.Material.Marble, true)
	block(plot, build, "Roof", -24.5, 24.5, 21, 22, 26.5, 42.5, roofColor, Enum.Material.ClayRoofTiles, true)
	block(plot, build, "RoofTrim", -24.5, 24.5, 20.55, 22.2, 26.2, 26.5, GOLD, Enum.Material.SmoothPlastic, false)
	for _, sx in { -1, 1 } do
		ball(build, "RoofFinial", at(plot, sx * 24.2, 22.75, 26.6), 1.1, GOLD, Enum.Material.SmoothPlastic, false)
	end
	for _, lx in { -21.5, 21.5 } do
		local foot = at(plot, lx, 0, 30)
		vcyl(build, "ColumnBase", foot + Vector3.new(0, 2.15, 0), 0.6, 2.8, STONE_DARK, Enum.Material.Slate, true)
		vcyl(build, "Column", foot + Vector3.new(0, 2.75, 0), 17.65, 2, STONE, Enum.Material.Marble, true)
		vcyl(build, "ColumnCap", foot + Vector3.new(0, 20.4, 0), 0.6, 2.8, GOLD, Enum.Material.SmoothPlastic, true)
	end
	for _, lx in { -9, 9 } do
		local l = vcyl(build, "HallLight", at(plot, lx, 20.8, HALL_LZ), 0.2, 2, rgb(255, 236, 200), Enum.Material.Neon, false)
		l.CastShadow = false
		Models.Light(l, rgb(255, 230, 190), 24, 1.1)
	end

	-- "Rarest Cores Found" board on the hall wall
	local board = P(build, "DiscoveryBoard", Vector3.new(32, 7.6, 0.4), facingOut(plot, 0, 16.4, 40.3), INK, Enum.Material.SmoothPlastic, true)
	block(plot, build, "BoardFrame", -16.35, 16.35, 20.2, 20.55, 39.9, 40.5, GOLD, Enum.Material.SmoothPlastic, false)
	block(plot, build, "BoardFrame", -16.35, 16.35, 12.25, 12.6, 39.9, 40.5, GOLD, Enum.Material.SmoothPlastic, false)
	block(plot, build, "BoardFrame", -16.35, -16, 12.6, 20.2, 39.9, 40.5, GOLD, Enum.Material.SmoothPlastic, false)
	block(plot, build, "BoardFrame", 16, 16.35, 12.6, 20.2, 39.9, 40.5, GOLD, Enum.Material.SmoothPlastic, false)
	local wg = surface(board, Enum.NormalId.Front, 24)
	wg.Name = "Discoveries"
	text(wg, "🏆 RAREST CORES FOUND", UDim2.new(1, 0, 0.2, 0), UDim2.new(0, 0, 0.03, 0), rgb(255, 210, 80))
	local lines = text(wg, "", UDim2.new(0.94, 0, 0.7, 0), UDim2.new(0.03, 0, 0.26, 0), rgb(235, 235, 240), Enum.Font.GothamBold)
	lines.Name = "Lines"
	lines.RichText = true
	lines.TextYAlignment = Enum.TextYAlignment.Top
	lines.TextXAlignment = Enum.TextXAlignment.Left
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 26
	limit.Parent = lines
	plot.board = lines

	-- trophy pedestals with a plaque on the front
	plot.stands = {}
	plot.plaques = {}
	for k = 1, Config.MaxTrophies do
		local lx = (k - (Config.MaxTrophies + 1) / 2) * 13
		block(plot, build, "PedestalBase", lx - 2.3, lx + 2.3, 2.0, 2.6, HALL_LZ - 2.3, HALL_LZ + 2.3, STONE_DARK, Enum.Material.Slate, true)
		P(build, "Pedestal", Vector3.new(3.4, 3.2, 3.4), facingOut(plot, lx, 4.2, HALL_LZ), rgb(242, 238, 230), Enum.Material.Marble, true)
		block(plot, build, "PedestalCap", lx - 2.2, lx + 2.2, 5.8, 6.3, HALL_LZ - 2.2, HALL_LZ + 2.2, GOLD, Enum.Material.SmoothPlastic, true)
		local plaque = P(build, "Plaque", Vector3.new(3.0, 1.9, 0.12), facingOut(plot, lx, 4.2, HALL_LZ - 1.76), INK, Enum.Material.SmoothPlastic, false)
		local sg = surface(plaque, Enum.NormalId.Front, 60)
		sg.MaxDistance = 60
		text(sg, "", UDim2.new(0.94, 0, 0.4, 0), UDim2.new(0.03, 0, 0.04, 0), rgb(235, 235, 240)).Name = "Name"
		text(sg, "", UDim2.new(0.94, 0, 0.26, 0), UDim2.new(0.03, 0, 0.45, 0), rgb(200, 200, 210), Enum.Font.GothamBold).Name = "Kind"
		text(sg, "", UDim2.new(0.94, 0, 0.24, 0), UDim2.new(0.03, 0, 0.72, 0), rgb(255, 214, 90), Enum.Font.GothamBold).Name = "Stats"
		plot.plaques[k] = sg
		plot.stands[k] = at(plot, lx, 7.2, HALL_LZ)
	end
end

local function buildPlot(index: number): Plot
	local center, side = plotCenter(index)
	local color = PALETTE[(index - 1) % #PALETTE + 1]
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	local plot: Plot = {
		index = index,
		center = center,
		side = side,
		color = color,
		owner = nil,
		model = model,
		incubators = {},
		stands = {},
		plaques = {},
		trophies = Instance.new("Folder"),
		style = Instance.new("Folder"),
		board = nil :: any,
		signs = {},
		pad = nil :: any,
		styleLevel = -1,
	}
	local build = Instance.new("Folder")
	build.Name = "Structure"
	build.Parent = model

	-- foundation, floor, carpet
	block(plot, build, "Foundation", -HALF_W, HALF_W, -0.4, 0.9, -HALF_D, HALF_D, STONE_DARK, Enum.Material.Slate, true).CastShadow = false
	block(plot, build, "Floor", -HALF_W + 1.5, HALF_W - 1.5, 0.75, FLOOR, -HALF_D + 1.5, HALF_D - 1.5, WOOD, Enum.Material.WoodPlanks, true).CastShadow = false
	block(plot, build, "Carpet", -3.5, 3.5, 1.05, 1.27, -22.2, 27, color:Lerp(rgb(20, 20, 30), 0.35), Enum.Material.Carpet, true).CastShadow = false
	for _, sx in { -1, 1 } do
		local x0 = sx < 0 and -3.85 or 3.5
		block(plot, build, "CarpetEdge", x0, x0 + 0.35, 1.05, 1.29, -22.2, 27, GOLD, Enum.Material.SmoothPlastic, true).CastShadow = false
	end

	-- low stone walls: the side walls own the corners, the front leaves room for the arch
	for _, sx in { -1, 1 } do
		local function x(a: number, b: number): (number, number)
			if sx < 0 then
				return -b, -a
			end
			return a, b
		end
		local a, b = x(HALF_W - 1.5, HALF_W)
		block(plot, build, "Wall", a, b, 0.9, 3.4, -HALF_D, HALF_D, WALL, Enum.Material.Slate, true)
		a, b = x(HALF_W - 1.75, HALF_W + 0.25)
		block(plot, build, "WallCap", a, b, 3.4, 3.8, -HALF_D - 0.25, HALF_D + 0.25, STONE, Enum.Material.Marble, true)
		a, b = x(11, HALF_W - 1.5)
		block(plot, build, "Wall", a, b, 0.9, 3.4, -HALF_D, -HALF_D + 1.5, WALL, Enum.Material.Slate, true)
		a, b = x(10.75, HALF_W - 1.75)
		block(plot, build, "WallCap", a, b, 3.4, 3.8, -HALF_D - 0.25, -HALF_D + 1.75, STONE, Enum.Material.Marble, true)
		a, b = x(23.5, HALF_W - 1.5)
		block(plot, build, "Wall", a, b, 0.9, 3.4, HALF_D - 1.5, HALF_D, WALL, Enum.Material.Slate, true)
		a, b = x(23.5, HALF_W - 1.75)
		block(plot, build, "WallCap", a, b, 3.4, 3.8, HALF_D - 1.75, HALF_D + 0.25, STONE, Enum.Material.Marble, true)
		for _, sz in { -1, 1 } do
			local cx, cz = sx * (HALF_W - 0.75), sz * (HALF_D - 0.75)
			block(plot, build, "CornerPost", cx - 1.4, cx + 1.4, 0.9, 5.1, cz - 1.4, cz + 1.4, WALL, Enum.Material.Slate, true)
			block(plot, build, "CornerCap", cx - 1.7, cx + 1.7, 5.1, 5.6, cz - 1.7, cz + 1.7, STONE, Enum.Material.Marble, true)
			ball(build, "CornerOrb", at(plot, cx, 6.3, cz), 1.2, color, Enum.Material.Neon, false).CastShadow = false
		end
	end

	-- entrance: walkway from the avenue, threshold, arch with the owner's name
	block(plot, build, "Walkway", -6.5, 6.5, 0.4, 1.0, -HALF_D - 7.8, -HALF_D, rgb(172, 166, 158), Enum.Material.Cobblestone, true).CastShadow = false
	for _, sx in { -1, 1 } do
		local x0 = sx < 0 and -7.5 or 6.5
		block(plot, build, "WalkwayEdge", x0, x0 + 1, 0.3, 1.15, -HALF_D - 6.8, -HALF_D, STONE_DARK, Enum.Material.Slate, true)
	end
	block(plot, build, "Threshold", -8, 8, 0.9, 1.3, -HALF_D, -HALF_D + 2.5, STONE, Enum.Material.Marble, true).CastShadow = false
	buildArch(plot, build)
	buildPad(plot, build)

	for slot = 1, MAX_INCUBATORS do
		local inc = buildIncubator(plot, slot)
		setIncubatorLook(inc, "off")
		plot.incubators[slot] = inc
	end

	buildHall(plot, build)
	plot.trophies.Name = "Trophies"
	plot.trophies.Parent = model
	plot.style.Name = "Style"
	plot.style.Parent = model
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerId", 0)
	model.Parent = folder
	return plot
end

--------------------------------------------------------------------------------
-- Visual refreshers
--------------------------------------------------------------------------------
function PlotService.RefreshIncubators(player: Player)
	local plot = byPlayer[player]
	local data = S.Data.Get(player)
	if not plot or not data then
		return
	end
	local slots = S.Incubators.SlotCount(player)
	local now = os.time()
	for slot, inc in plot.incubators do
		local entry = data.inc[slot]
		local state
		if slot > slots then
			state = "locked"
		elseif not entry then
			state = "empty"
		elseif now >= entry.e then
			state = "ready"
		else
			state = "incubating"
		end
		local stamp = entry and (tostring(entry.s) .. ":" .. tostring(entry.e) .. ":" .. tostring(entry.r)) or state
		if inc.state == state and inc.stamp == stamp then
			continue
		end
		inc.state = state
		inc.stamp = stamp
		inc.model:SetAttribute("State", state)

		local old = inc.core
		if old then
			old:Destroy()
			inc.core = nil
		end
		local prompt = inc.dome:FindFirstChild("OpenPrompt")
		if prompt then
			prompt:Destroy()
		end

		if state == "locked" then
			setIncubatorLook(inc, "locked")
			setText(inc.info, "Title", "🔒 LOCKED", rgb(170, 170, 180))
			setText(inc.info, "Timer", "Unlock in BASE ▸ Upgrades", rgb(200, 200, 210))
		elseif state == "empty" then
			setIncubatorLook(inc, "empty")
			setText(inc.info, "Title", "EMPTY", rgb(215, 215, 225))
			setText(inc.info, "Timer", "Bring a Core home!", rgb(200, 200, 210))
		else
			local r = entry.r
			local core = Models.Core(entry.z, r, 1.05)
			Models.SetAnchored(core, true)
			core:PivotTo(CFrame.new(inc.dome.Position))
			core:SetAttribute("SpinSpeed", 0.9)
			core:SetAttribute("Bob", 0.2)
			CollectionService:AddTag(core, "Spin")
			core.Parent = inc.model
			inc.core = core
			setText(inc.info, "Title", Items.CoreTitle(entry.z, r), Items.RarityColor(r))
			inc.model:SetAttribute("EndTime", entry.e)
			if state == "ready" then
				setIncubatorLook(inc, "ready", rgb(90, 255, 120))
				setText(inc.info, "Timer", "✨ READY! Open it!", rgb(140, 255, 160))
				local open = Instance.new("ProximityPrompt")
				open.Name = "OpenPrompt"
				open.ActionText = "Open Core"
				open.ObjectText = Items.CoreTitle(entry.z, r)
				open.HoldDuration = 0.3
				open.MaxActivationDistance = 10
				open.RequiresLineOfSight = false
				open.Parent = inc.dome
				open.Triggered:Connect(function(who)
					if who == player then
						local ok, msg = S.Incubators.Open(player, slot)
						if not ok and msg then
							S.Player.Notify(player, msg, "error")
						end
					end
				end)
			else
				setIncubatorLook(inc, "incubating", Items.RarityColor(r))
				setText(inc.info, "Timer", "⏳ " .. Util.Clock(entry.e - now), rgb(255, 255, 255))
			end
		end
	end
end

local function itemScore(key: string): number
	return Items.Rarity(key) * 1e12 + math.min(Items.Power(key), 1e12 - 1) / 1e12 * 1e11
end

-- Floats a trophy above pedestal k (weapon, class emblem or ability tome), scaled to fit, spinning
local function showTrophy(plot: Plot, k: number, key: string)
	local _, _, c = Items.Def(key)
	local display: Model
	local spin = 0.8
	if c == "w" then
		display = Models.Weapon(key)
	elseif c == "c" then
		display = Models.ClassEmblem(key) -- heraldic crest: zone shape, class symbol, rarity trim
		spin = 0.5 -- flat crests read better turning slowly
	else
		display = Models.AbilityTome(key) -- open spell book with the ability's sigil above it
		spin = 0.55
	end
	Models.SetAnchored(display, true)
	-- fit inside ~5 studs; small items (daggers) grow a little so they still read from across the hall
	local _, size = display:GetBoundingBox()
	local largest = math.max(size.X, size.Y, size.Z, 0.1)
	local scale = 1
	if size.Y > 5 then
		scale = 5 / size.Y
	elseif largest < 3.2 then
		scale = math.min(3.2 / largest, 1.4)
	end
	if scale ~= 1 then
		pcall(function()
			display:ScaleTo(display:GetScale() * scale)
		end)
	end
	local box, fitted = display:GetBoundingBox()
	local target = plot.stands[k] + Vector3.new(0, fitted.Y / 2, 0)
	display:PivotTo(display:GetPivot() + (target - box.Position))
	display:SetAttribute("SpinSpeed", spin)
	display:SetAttribute("Bob", 0.25)
	CollectionService:AddTag(display, "Spin")
	display.Parent = plot.trophies
end

function PlotService.RefreshTrophies(player: Player)
	local plot = byPlayer[player]
	local data = S.Data.Get(player)
	if not plot or not data then
		return
	end
	local keys = {}
	for key, count in data.inv do
		if count > 0 and Items.Zone(key) > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		return itemScore(a) > itemScore(b)
	end)
	plot.trophies:ClearAllChildren()
	for k, sg in plot.plaques do
		local key = keys[k]
		if key then
			local def, _, c, _, r = Items.Def(key)
			showTrophy(plot, k, key)
			setText(sg, "Name", string.upper(def and def.name or "?"), Items.RarityColor(r))
			setText(sg, "Kind", Items.RarityName(r) .. " " .. Items.SlotNames[c], rgb(210, 210, 220))
			setText(sg, "Stats", Util.Odds(Items.OddsLabel(key)) .. "  •  ⚡" .. Util.Abbrev(Items.Power(key)), rgb(255, 214, 90))
		else
			setText(sg, "Name", "EMPTY", rgb(150, 150, 160))
			setText(sg, "Kind", "Your #" .. k .. " best item", rgb(150, 150, 160))
			setText(sg, "Stats", "", rgb(150, 150, 160))
		end
	end

	-- discovery board
	local lines = {}
	for _, find in data.best or {} do
		local color = Items.RarityColor(find.r)
		table.insert(
			lines,
			string.format(
				'<font color="#%s">%s</font>  %s  <font color="#AAAAAA">from %s</font>',
				color:ToHex(),
				Items.CoreTitle(find.z, find.r),
				Util.Odds(find.odds or 1),
				tostring(find.mob or "?")
			)
		)
	end
	plot.board.Text = #lines > 0 and table.concat(lines, "\n") or '<font color="#AAAAAA">Bring rare Cores home to show them off here!</font>'
end

--------------------------------------------------------------------------------
-- Base Style (cosmetic): each level adds to the previous ones
--------------------------------------------------------------------------------
local function styleLanterns(plot: Plot, f: Folder)
	for _, sx in { -1, 1 } do
		for _, lz in { -36.5, 24.5 } do
			lantern(f, at(plot, sx * 27.5, FLOOR, lz), 6.5)
		end
		for _, range in { { -31, -13 }, { -8, 18 } } do
			local x0, x1 = sx < 0 and -29.6 or 26.6, sx < 0 and -26.6 or 29.6
			block(plot, f, "Planter", x0, x1, 1.0, 2.3, range[1], range[2], rgb(165, 95, 72), Enum.Material.Brick, true)
			block(plot, f, "Soil", x0 + 0.3, x1 - 0.3, 2.0, 2.45, range[1] + 0.3, range[2] - 0.3, rgb(96, 170, 70), Enum.Material.Grass, false)
			local n = math.floor((range[2] - range[1]) / 3)
			for i = 0, n - 1 do
				local lz = range[1] + 1.6 + i * (range[2] - range[1] - 3.2) / math.max(n - 1, 1)
				local bloom = ball(f, "Bloom", at(plot, sx * 28.1 + ((i % 2 == 0) and 0.5 or -0.5), 2.95, lz), 1.1, PETALS[(i + plot.index) % #PETALS + 1], Enum.Material.SmoothPlastic, false)
				bloom.CastShadow = false
			end
		end
	end
end

local function styleBanners(plot: Plot, f: Folder)
	local color = plot.color
	for _, lx in { -19, 19 } do
		block(plot, f, "BannerRod", lx - 2, lx + 2, 20.1, 20.4, 26.05, 26.2, GOLD, Enum.Material.SmoothPlastic, false)
		local banner = P(f, "Banner", Vector3.new(3.2, 5.6, 0.15), facingOut(plot, lx, 17.3, 25.98), color, Enum.Material.Fabric, false)
		banner.CastShadow = false
		local mark = P(f, "BannerMark", Vector3.new(1.1, 1.1, 0.1), facingOut(plot, lx, 17.6, 25.84) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Enum.Material.SmoothPlastic, false)
		mark.CastShadow = false
	end
	-- hedges along the outside of the front wall, trees in pots by the walkway
	for _, sx in { -1, 1 } do
		local x0, x1 = sx < 0 and -29.4 or 11.8, sx < 0 and -11.8 or 29.4
		block(plot, f, "Hedge", x0, x1, 0.3, 2.9, -HALF_D - 2.3, -HALF_D - 0.2, rgb(62, 128, 58), Enum.Material.Grass, true)
		local pot = at(plot, sx * 11.5, 0, -HALF_D - 5.5)
		vcyl(f, "Pot", pot, 1.8, 2.2, rgb(180, 110, 80), Enum.Material.Slate, true)
		vcyl(f, "PotTrunk", pot + Vector3.new(0, 1.8, 0), 2, 0.5, rgb(115, 80, 50), Enum.Material.Wood, false)
		ball(f, "PotTree", pot + Vector3.new(0, 4.6, 0), 3.4, rgb(96, 180, 72), Enum.Material.Grass, false)
	end
end

local function styleTowers(plot: Plot, f: Folder)
	local color = plot.color
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local foot = at(plot, sx * (HALF_W - 0.75), 0, sz * (HALF_D - 0.75))
			vcyl(f, "Tower", foot + Vector3.new(0, 0.5, 0), 12.5, 6, WALL, Enum.Material.Cobblestone, true)
			vcyl(f, "TowerRim", foot + Vector3.new(0, 13, 0), 1, 7, STONE, Enum.Material.Marble, true)
			vcyl(f, "TowerRoof", foot + Vector3.new(0, 14, 0), 1, 6.2, color, Enum.Material.ClayRoofTiles, true)
			vcyl(f, "TowerRoof", foot + Vector3.new(0, 15, 0), 1.2, 4.4, color, Enum.Material.ClayRoofTiles, true)
			vcyl(f, "TowerRoof", foot + Vector3.new(0, 16.2, 0), 1.4, 2.4, color, Enum.Material.ClayRoofTiles, true)
			vcyl(f, "FlagPole", foot + Vector3.new(0, 17.6, 0), 5, 0.3, rgb(220, 220, 225), Enum.Material.Metal, false)
			local flag = block(plot, f, "Flag", 0, 0.15, 0, 2.2, 0, 3.4, color, Enum.Material.Fabric, false)
			flag.CFrame = CFrame.new(foot + Vector3.new(0, 21.4, 0) + Vector3.new(0, 0, 1.75 * plot.side))
		end
		-- battlements on the side walls
		for lz = -35, 35, 7 do
			local x0 = sx < 0 and -(HALF_W - 0.05) or (HALF_W - 1.45)
			block(plot, f, "Merlon", x0, x0 + 1.4, 3.8, 5.0, lz - 1, lz + 1, STONE, Enum.Material.Marble, true)
		end
	end
end

local function styleSpire(plot: Plot, f: Folder)
	local color = plot.color
	local foot = at(plot, 0, 0, HALL_LZ)
	vcyl(f, "SpireBase", foot + Vector3.new(0, 22, 0), 3, 4.4, STONE_DARK, Enum.Material.Slate, true)
	P(f, "Spire", Vector3.new(2.2, 12, 2.2), CFrame.new(foot + Vector3.new(0, 31, 0)) * CFrame.Angles(0, math.rad(45), 0), rgb(40, 40, 60), Enum.Material.Slate, true)
	local crystal, gem = spinner(f, "SpireCrystal", foot + Vector3.new(0, 40, 0), 3, color, 0.7, 0.6)
	local aura = ball(crystal, "Aura", foot + Vector3.new(0, 40, 0), 5.5, color, Enum.Material.ForceField, false)
	aura.CastShadow = false
	Models.Light(gem, color, 40, 2)
	Models.Sparkles(gem, color, 8, 0.6)
	for _, sx in { -1, 1 } do
		local x0 = sx < 0 and -4.4 or 4.1
		local rune = block(plot, f, "RuneStrip", x0, x0 + 0.3, 1.05, 1.27, -22, 26.8, color, Enum.Material.Neon, false)
		rune.CastShadow = false
	end
end

local function styleGold(plot: Plot, f: Folder)
	for _, sx in { -1, 1 } do
		local a, b = sx < 0 and -(HALF_W + 0.15) or (HALF_W - 1.65), sx < 0 and -(HALF_W - 1.65) or (HALF_W + 0.15)
		block(plot, f, "GoldTrim", a, b, 3.8, 3.95, -HALF_D - 0.15, HALF_D + 0.15, GOLD, Enum.Material.Foil, false)
		local c0, c1 = sx < 0 and -(HALF_W - 1.85) or 10.85, sx < 0 and -10.85 or (HALF_W - 1.85)
		block(plot, f, "GoldTrim", c0, c1, 3.8, 3.95, -HALF_D - 0.15, -HALF_D + 1.65, GOLD, Enum.Material.Foil, false)
		for _, y in { 4.5, 7.1, 12.2 } do -- (the wall sconces sit at 8.6-9.8)
			local x0, x1 = sx < 0 and -11.15 or 7.85, sx < 0 and -7.85 or 11.15
			block(plot, f, "PillarBand", x0, x1, y - 0.3, y + 0.3, -42.9, -39.6, GOLD, Enum.Material.Foil, false)
		end
	end
	local halo = Instance.new("Model")
	halo.Name = "Halo"
	local center = at(plot, 0, 44, HALL_LZ)
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		local seg = P(halo, "HaloSeg", Vector3.new(2.6, 0.35, 0.6), CFrame.new(center + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6)) * CFrame.Angles(0, -a + math.pi / 2, 0), rgb(255, 215, 90), Enum.Material.Neon, false)
		seg.CastShadow = false
	end
	local pivot = P(halo, "Pivot", Vector3.new(0.2, 0.2, 0.2), CFrame.new(center), GOLD, Enum.Material.SmoothPlastic, false)
	pivot.Transparency = 1
	halo.PrimaryPart = pivot
	halo:SetAttribute("SpinSpeed", 0.35)
	halo:SetAttribute("Bob", 0.5)
	CollectionService:AddTag(halo, "Spin")
	halo.Parent = f
	local glow = P(f, "GoldGlow", Vector3.new(1, 1, 1), CFrame.new(at(plot, 0, 19, -41.25)), GOLD, Enum.Material.SmoothPlastic, false)
	glow.Transparency = 1
	Models.Sparkles(glow, rgb(255, 215, 90), 14, 0.7)
end

local STYLE_BUILDERS = { styleLanterns, styleBanners, styleTowers, styleSpire, styleGold }

function PlotService.RefreshStyle(player: Player)
	local plot = byPlayer[player]
	local data = S.Data.Get(player)
	if not plot or not data then
		return
	end
	local level = data.up.style or 0
	if plot.styleLevel == level then
		return
	end
	plot.styleLevel = level
	plot.style:ClearAllChildren()
	for k = 1, math.min(level, #STYLE_BUILDERS) do
		STYLE_BUILDERS[k](plot, plot.style)
	end
end

--------------------------------------------------------------------------------
-- Assignment
--------------------------------------------------------------------------------
local function setSigns(plot: Plot, owner: string, sub: string)
	for _, sg in plot.signs do
		setText(sg, "Owner", owner)
		setText(sg, "Sub", sub)
	end
end

function PlotService.Assign(player: Player): Plot?
	if byPlayer[player] then
		return byPlayer[player]
	end
	local chosen: Plot? = nil
	for _, plot in plots do
		if not plot.owner then
			chosen = plot
			break
		end
	end
	if not chosen and #plots < MAX_PLOTS then
		local fresh = buildPlot(#plots + 1)
		table.insert(plots, fresh)
		chosen = fresh
	end
	if not chosen then
		warn("[Plots] No free base for " .. player.Name .. " — lower Max Players to " .. MAX_PLOTS)
		return nil
	end
	local plot = chosen :: Plot
	plot.owner = player
	byPlayer[player] = plot
	plot.model:SetAttribute("OwnerId", player.UserId)
	player:SetAttribute("PlotIndex", plot.index)

	setSigns(plot, string.upper(player.DisplayName) .. "'S BASE", "@" .. player.Name)
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
		end)
		if ok and plot.owner == player then
			for _, sg in plot.signs do
				setImage(sg, "Avatar", image)
				local avatar = sg:FindFirstChild("Avatar")
				if avatar and avatar:IsA("ImageLabel") then
					avatar.Visible = true
				end
			end
		end
	end)

	plot.styleLevel = -1
	for _, inc in plot.incubators do
		inc.state = ""
		inc.stamp = nil
	end
	PlotService.RefreshIncubators(player)
	PlotService.RefreshTrophies(player)
	PlotService.RefreshStyle(player)
	return plot
end

function PlotService.Release(player: Player)
	local plot = byPlayer[player]
	if not plot then
		return
	end
	byPlayer[player] = nil
	plot.owner = nil
	plot.model:SetAttribute("OwnerId", 0)
	setSigns(plot, "FREE BASE", "")
	for _, sg in plot.signs do
		setImage(sg, "Avatar", "")
		local avatar = sg:FindFirstChild("Avatar")
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Visible = false
		end
	end
	for _, sg in plot.plaques do
		setText(sg, "Name", "")
		setText(sg, "Kind", "")
		setText(sg, "Stats", "")
	end
	plot.trophies:ClearAllChildren()
	plot.style:ClearAllChildren()
	plot.styleLevel = -1
	plot.board.Text = ""
	for _, inc in plot.incubators do
		if inc.core then
			inc.core:Destroy()
			inc.core = nil
		end
		local prompt = inc.dome:FindFirstChild("OpenPrompt")
		if prompt then
			prompt:Destroy()
		end
		inc.state = "off"
		inc.stamp = nil
		inc.model:SetAttribute("State", "empty")
		setIncubatorLook(inc, "off")
		setText(inc.info, "Title", "")
		setText(inc.info, "Timer", "")
	end
end

function PlotService.Get(player: Player): Plot?
	return byPlayer[player]
end

-- Is this world position on the player's own base?
function PlotService.IsOnOwnPlot(player: Player, pos: Vector3): boolean
	local plot = byPlayer[player]
	if not plot then
		return false
	end
	local d = pos - plot.center
	return math.abs(d.X) <= HALF_W + 1 and math.abs(d.Z) <= HALF_D + 1 and pos.Y < 40
end

function PlotService.PadPosition(player: Player): Vector3?
	local plot = byPlayer[player]
	return plot and plot.pad.Position
end

function PlotService.HomeCFrame(player: Player): CFrame?
	local plot = byPlayer[player]
	if not plot then
		return nil
	end
	local pos = at(plot, 0, 4, -18)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, plot.side))
end

function PlotService.Init(services: any)
	S = services
end

function PlotService.Start()
	folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = workspace
	for index = 1, 8 do
		table.insert(plots, buildPlot(index))
	end
	-- incubator timers flip to READY without anyone touching them
	task.spawn(function()
		while true do
			task.wait(1)
			for player in byPlayer do
				if player.Parent then
					PlotService.RefreshIncubators(player)
				end
			end
		end
	end)
end

return PlotService
