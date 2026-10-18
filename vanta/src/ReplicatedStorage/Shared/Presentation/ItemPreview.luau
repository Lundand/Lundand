--!strict
-- Item previews (asset pass): shows an item's 3D model from the asset library (ReplicatedStorage.Assets) in a ViewportFrame,
-- for inventory tiles and the inspection panel. Presentation only. Items without a model get no preview (callers keep their
-- text fallback).
--   ItemPreview.has(itemId)                     -> whether a model exists
--   ItemPreview.view(parent, itemId, options)   -> ViewportFrame?   options: { layout = "tile" | "panel", motion = boolean }
-- Framing: models face -Z (the library convention), so the camera looks from the -Z side. Long items (weapons, tools) lie
-- diagonally in tiles and horizontally in the wide panel; the panel preview sways gently while it is shown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemPreview = {}

local FOV = 30

local function template(itemId: string?): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil or itemId == nil then
		return nil
	end
	for _, library in ipairs(assets:GetChildren()) do
		if library.Name ~= "Projectiles" and library.Name ~= "ResourceNodes" and library.Name ~= "Subtypes" and library.Name ~= "Effects" then
			local found = library:FindFirstChild(itemId)
			if found ~= nil and found:IsA("Model") then
				return found
			end
		end
	end
	-- no model of its own: its weapon subtype's model (the same order the held models use)
	local Content = require(ReplicatedStorage:WaitForChild("Shared").Content)
	local def = Content.items[itemId]
	local subtype = def and def.equipment and def.equipment.subtype
	local subtypes = assets:FindFirstChild("Subtypes")
	local found = subtype and subtypes and subtypes:FindFirstChild(subtype)
	if found ~= nil and found:IsA("Model") then
		return found
	end
	return nil
end

function ItemPreview.has(itemId: string?): boolean
	return template(itemId) ~= nil
end

-- world-aligned bounds of the visible parts (holder parts such as Grip/Root/Handle are invisible and left out)
local function bounds(model: Model): (Vector3, Vector3)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local half = part.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						low = low:Min(corner)
						high = high:Max(corner)
					end
				end
			end
		end
	end
	if low.X == math.huge then
		return Vector3.zero, Vector3.one
	end
	return (low + high) / 2, high - low
end

function ItemPreview.view(parent: Instance, itemId: string?, options: { layout: string?, motion: boolean? }?): ViewportFrame?
	local source = template(itemId)
	if source == nil then
		return nil
	end
	local layout = (options and options.layout) or "tile"
	local model = source:Clone()
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
		elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Light") or item:IsA("Beam") then
			item:Destroy()
		end
	end
	-- orient: broadest horizontal side to the camera; long items laid diagonal (tile) or flat (panel)
	model:PivotTo(CFrame.identity)
	local _, raw = bounds(model)
	local orientation = CFrame.identity
	if raw.Z > raw.X * 1.15 then
		orientation = CFrame.Angles(0, math.rad(90), 0)
	end
	model:PivotTo(orientation)
	local _, turned = bounds(model)
	local long = turned.Y > math.max(turned.X, turned.Z) * 1.6
	if long then
		-- seen from -Z, a roll about Z by +a tips the top towards screen right
		orientation = CFrame.Angles(0, 0, math.rad(if layout == "panel" then 90 else 45)) * orientation
	end
	orientation = CFrame.Angles(math.rad(-8), math.rad(-22), 0) * orientation -- a little depth
	model:PivotTo(orientation)
	local centre, extent = bounds(model)

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ItemPreview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(150, 146, 140)
	viewport.LightColor = Color3.fromRGB(255, 244, 228)
	viewport.LightDirection = Vector3.new(-0.45, -1, 0.65)
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport

	-- fit: the camera looks from the -Z side, slightly above; distance so the screen-plane extent fills the frame
	local aspect = 1
	if parent:IsA("GuiObject") and parent.AbsoluteSize.Y > 0 then
		aspect = parent.AbsoluteSize.X / parent.AbsoluteSize.Y
	end
	local halfFov = math.rad(FOV / 2)
	local fill = if layout == "panel" then 0.8 else 0.86
	local needY = (extent.Y / 2) / math.tan(halfFov)
	local needX = (extent.X / 2) / (math.tan(halfFov) * aspect)
	local distance = math.max(needX, needY) / fill + extent.Z / 2
	local direction = Vector3.new(0, 0.12, -1).Unit
	camera.CFrame = CFrame.lookAt(centre + direction * distance, centre)
	viewport.Parent = parent

	if options and options.motion then
		-- a slow sway about the vertical axis through the model's centre
		local base = model:GetPivot()
		local started = os.clock()
		local step: RBXScriptConnection
		step = RunService.RenderStepped:Connect(function()
			if viewport.Parent == nil or model.Parent == nil then
				step:Disconnect()
				return
			end
			local angle = math.sin((os.clock() - started) * 0.9) * math.rad(28)
			model:PivotTo(CFrame.new(centre) * CFrame.Angles(0, angle, 0) * CFrame.new(-centre) * base)
		end)
		viewport.Destroying:Connect(function()
			step:Disconnect()
		end)
	end
	return viewport
end

return ItemPreview
