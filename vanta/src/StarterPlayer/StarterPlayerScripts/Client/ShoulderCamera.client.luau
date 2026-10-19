--!strict
-- Shoulder camera ("first person, but still third"): the camera sits behind the character, a little to the right, and turns with the
-- mouse; the character always faces where the camera looks (like shift-lock, but always on). The mouse is locked to the middle of
-- the screen for looking and aiming, with a small dot as the crosshair. Whenever a menu or a dialogue is open, or the Roblox menu
-- or a text box is in use, the mouse is released so you can click around, and the camera and character stay as they are.
-- Gamepad and touch players keep Roblox's normal camera.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(ReplicatedStorage:WaitForChild("Shared").Presentation.Ui)

local START_PITCH = 14 -- degrees the camera looks down at the start
local PITCH_LIMITS = { min = -22, max = 55 }
local DISTANCE = { near = 6, far = 24, start = 12 }
local ZOOM_STEP = 2
local SHOULDER = 1.3 -- studs to the right of the character
local FOCUS_HEIGHT = 2.6 -- the point the camera looks past, about head height
local FIELD_OF_VIEW = 70
local RADIANS_PER_PIXEL = 0.0045 -- mouse look speed (also scaled by the player's mouse sensitivity setting)
local TURN_SPEED = 60 -- how fast the character swings round to face the camera
local PAUSE_GUIS = { "Dialogue", "Awakening" } -- screens that take over the mouse

local player = Players.LocalPlayer
local settings = UserSettings():GetService("UserGameSettings")
local camera = workspace.CurrentCamera
local yaw: number? = nil -- radians, positive turns left
local pitch = math.rad(START_PITCH) -- radians the camera looks down
local distance = DISTANCE.start
local wasFree = false

-- a dot in the middle of the screen while the mouse is locked
local crosshair = Instance.new("ScreenGui")
crosshair.Name = "Crosshair"
crosshair.ResetOnSpawn = false
crosshair.IgnoreGuiInset = true
crosshair.DisplayOrder = 5
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0.5, 0.5)
dot.Position = UDim2.fromScale(0.5, 0.5)
dot.Size = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.fromRGB(240, 232, 210)
dot.BorderSizePixel = 0
dot.Parent = crosshair
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot
local dotStroke = Instance.new("UIStroke")
dotStroke.Color = Color3.fromRGB(16, 22, 38)
dotStroke.Thickness = 1
dotStroke.Parent = dot
crosshair.Parent = player:WaitForChild("PlayerGui")

local function characterParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character ~= nil and humanoid ~= nil and root ~= nil and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function screenTakesMouse(): boolean
	local gui = player:FindFirstChild("PlayerGui")
	if gui == nil then
		return false
	end
	for _, name in ipairs(PAUSE_GUIS) do
		local screen = gui:FindFirstChild(name)
		if screen ~= nil and screen:IsA("ScreenGui") and screen.Enabled then
			return true
		end
	end
	return false
end

UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel and not wasFree then
		distance = math.clamp(distance - input.Position.Z * ZOOM_STEP, DISTANCE.near, DISTANCE.far)
	end
end)

player.CharacterAdded:Connect(function()
	yaw = nil -- a new character: look the way it faces
end)

RunService:BindToRenderStep("ShoulderCamera", Enum.RenderPriority.Camera.Value, function(dt: number)
	camera = workspace.CurrentCamera or camera
	-- no mouse (gamepad, touch): leave everything to Roblox's own camera and controls
	if not UserInputService.MouseEnabled then
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		crosshair.Enabled = false
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = FIELD_OF_VIEW
	local character, humanoid, root = characterParts()
	if character == nil or humanoid == nil or root == nil then
		return
	end
	if yaw == nil then
		local look = root.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
	end
	local heading: number = yaw :: number

	-- free the mouse for menus, dialogue, the Roblox menu and typing
	local free = Ui.anyOpen() or screenTakesMouse() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil or humanoid.Health <= 0
	if free then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		humanoid.AutoRotate = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
		local scale = RADIANS_PER_PIXEL * settings.MouseSensitivity
		heading -= delta.X * scale
		pitch = math.clamp(pitch + delta.Y * scale, math.rad(PITCH_LIMITS.min), math.rad(PITCH_LIMITS.max))
		yaw = heading
		-- the character faces where the camera looks
		humanoid.AutoRotate = false
		local goal = CFrame.Angles(0, heading, 0)
		root.CFrame = CFrame.new(root.Position) * root.CFrame.Rotation:Lerp(goal, 1 - math.exp(-TURN_SPEED * dt))
	end
	wasFree = free
	crosshair.Enabled = not free

	-- the camera: behind the character and a little to the right, looking where the mouse points
	local rotation = CFrame.Angles(0, heading, 0) * CFrame.Angles(-pitch, 0, 0)
	local right = CFrame.Angles(0, heading, 0).RightVector
	local focus = root.Position + Vector3.new(0, FOCUS_HEIGHT, 0) + right * SHOULDER
	local wanted = focus - rotation.LookVector * distance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(focus, wanted - focus, params)
	local position = wanted
	if hit ~= nil then
		position = hit.Position + (focus - wanted).Unit * 0.6 -- stop in front of the wall
	end
	camera.CFrame = CFrame.new(position) * rotation
end)
