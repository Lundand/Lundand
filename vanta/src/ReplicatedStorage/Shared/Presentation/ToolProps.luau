--!strict
-- Placeholder gathering tools, shown in a character's hand while they gather (mining, woodcutting). Built like the weapon
-- models: along +Y from the grip, welded, the grip as PrimaryPart. Shared so the animation tools and the game show the same shapes.
local ToolProps = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function piece(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = CFrame.new(offset)
	part.Parent = model
	return part
end

function ToolProps.build(toolType: string, itemId: string?): Model?
	-- a mesh model from the asset library (ReplicatedStorage.Assets.Tools): the item's own model when given and present,
	-- otherwise the first one of this tool type (attribute ToolType)
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild("Tools")
	local own = itemId and library and library:FindFirstChild(itemId)
	if own ~= nil and own:IsA("Model") and own:GetAttribute("ToolType") == toolType then
		local copy = own:Clone()
		copy.Name = "Weapon"
		return copy
	end
	if library ~= nil then
		for _, asset in ipairs(library:GetChildren()) do
			if asset:IsA("Model") and asset:GetAttribute("ToolType") == toolType then
				local copy = asset:Clone()
				copy.Name = "Weapon"
				return copy
			end
		end
	end
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local wood, steel = rgb(100, 70, 44), rgb(150, 154, 164)
	local grip = piece(model, "Grip", Vector3.new(0.24, 0.9, 0.24), Vector3.zero, wood, Enum.Material.Wood)
	if toolType == "Pickaxe" then
		piece(model, "Haft", Vector3.new(0.22, 2.4, 0.22), Vector3.new(0, 1.4, 0), wood, Enum.Material.Wood)
		piece(model, "Head", Vector3.new(0.3, 0.3, 1.9), Vector3.new(0, 2.7, 0), steel, Enum.Material.Metal)
		piece(model, "PointFront", Vector3.new(0.22, 0.22, 0.5), Vector3.new(0, 2.65, -1.15), steel, Enum.Material.Metal)
	elseif toolType == "Hatchet" then
		piece(model, "Haft", Vector3.new(0.2, 1.5, 0.2), Vector3.new(0, 1.0, 0), wood, Enum.Material.Wood)
		piece(model, "Blade", Vector3.new(0.12, 0.9, 0.8), Vector3.new(0, 1.65, -0.45), steel, Enum.Material.Metal)
	else
		model:Destroy()
		return nil
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= grip then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = grip
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.PrimaryPart = grip
	return model
end

return ToolProps
