--!strict
-- The awakening ritual (L-43), played only on the awakened player's screen, so nobody else is disturbed.
-- The class is already saved on the server, so skipping changes nothing. Placeholder effects until the art
-- pass: runes light up, a circle spreads, energy gathers, light descends, a burst, then the class is shown.
-- Players who have awakened before on this account see a short version.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(230, 190, 90)
local VIOLET = Color3.fromRGB(150, 100, 230)
local LIGHT = Color3.fromRGB(255, 245, 220)

local gui = Instance.new("ScreenGui")
gui.Name = "Awakening"
gui.ResetOnSpawn = false
gui.Enabled = false
local reveal = Instance.new("TextLabel")
reveal.AnchorPoint = Vector2.new(0.5, 0.5)
reveal.Position = UDim2.new(0.5, 0, 0.3, 0)
reveal.Size = UDim2.new(0, 600, 0, 60)
reveal.BackgroundTransparency = 1
reveal.Font = Enum.Font.GothamBold
reveal.TextSize = 40
reveal.TextColor3 = GOLD
reveal.TextStrokeTransparency = 0.4
reveal.Visible = false
reveal.Parent = gui
local skipButton = Instance.new("TextButton")
skipButton.AnchorPoint = Vector2.new(1, 1)
skipButton.Position = UDim2.new(1, -24, 1, -24)
skipButton.Size = UDim2.new(0, 90, 0, 34)
skipButton.BackgroundColor3 = Color3.fromRGB(16, 22, 38)
skipButton.TextColor3 = GOLD
skipButton.Font = Enum.Font.GothamMedium
skipButton.TextSize = 16
skipButton.Text = "Skip"
skipButton.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local skipping = false
local playing = false
local effects: {Instance} = {}

local function effect(className: string, properties: {[string]: any}): any
	local instance: any = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	instance.Parent = workspace
	table.insert(effects, instance)
	return instance
end

local function glowPart(size: Vector3, cframe: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): any
	return effect("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Shape = shape or Enum.PartType.Block,
		Color = color,
		Transparency = transparency,
		Size = size,
		CFrame = cframe,
	})
end

local function tween(instance: Instance, seconds: number, goal: {[string]: any})
	TweenService:Create(instance, TweenInfo.new(seconds), goal):Play()
end

local function pause(seconds: number)
	local elapsed = 0
	while elapsed < seconds and not skipping do
		elapsed += task.wait()
	end
end

local function play(data: any)
	if playing then
		return
	end
	playing = true
	skipping = false
	gui.Enabled = true
	skipButton.Visible = true
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin: Vector3 = data.position or (root and root.Position) or Vector3.zero
	local pace = 1
	if data.quick then
		pace = 0.35
	end
	for index = 1, 12 do
		local angle = index / 12 * math.pi * 2
		local rune = glowPart(Vector3.new(1, 0.1, 1), CFrame.new(origin + Vector3.new(math.cos(angle) * 6, 0.2, math.sin(angle) * 6)), VIOLET, 1)
		tween(rune, 0.4 * pace, { Transparency = 0 })
		pause(0.08 * pace)
	end
	local circle = glowPart(Vector3.new(0.1, 1, 1), CFrame.new(origin + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, 0.4, Enum.PartType.Cylinder)
	tween(circle, 1.2 * pace, { Size = Vector3.new(0.1, 14, 14) })
	pause(1.2 * pace)
	if root ~= nil then
		local motes = Instance.new("ParticleEmitter")
		motes.Color = ColorSequence.new(VIOLET)
		motes.LightEmission = 1
		motes.Rate = 60
		motes.Speed = NumberRange.new(-4)
		motes.Lifetime = NumberRange.new(0.6)
		motes.Parent = root
		table.insert(effects, motes)
		local glow = Instance.new("PointLight")
		glow.Color = VIOLET
		glow.Range = 16
		glow.Brightness = 0
		glow.Parent = root
		table.insert(effects, glow)
		tween(glow, 1.2 * pace, { Brightness = 4 })
	end
	pause(1.2 * pace)
	local beam = glowPart(Vector3.new(4, 60, 4), CFrame.new(origin + Vector3.new(0, 30, 0)), LIGHT, 1)
	tween(beam, 0.8 * pace, { Transparency = 0.3 })
	pause(0.8 * pace)
	local burst = glowPart(Vector3.new(2, 2, 2), CFrame.new(origin + Vector3.new(0, 3, 0)), GOLD, 0.2, Enum.PartType.Ball)
	tween(burst, 0.6 * pace, { Size = Vector3.new(30, 30, 30), Transparency = 1 })
	pause(0.6 * pace)
	for _, instance in ipairs(effects) do
		instance:Destroy()
	end
	table.clear(effects)
	skipButton.Visible = false
	reveal.Text = "The System assigns your class: " .. tostring(data.className)
	reveal.Visible = true
	task.wait(2.5)
	reveal.Visible = false
	gui.Enabled = false
	playing = false
end

skipButton.Activated:Connect(function()
	skipping = true
end)
remotes.AwakeningRitual.OnClientEvent:Connect(function(data: any)
	task.spawn(play, data)
end)
