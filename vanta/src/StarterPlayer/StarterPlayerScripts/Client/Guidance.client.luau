--!strict
-- Temporary guidance (L-42, L-43). When a quest with guidance is accepted, a faint column of light rises
-- over the place for a few seconds, then fades. Nothing permanent, and nothing ever marks an NPC.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function findLocation(locationId: string): BasePart?
	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("LocationId") == locationId then
			return instance
		end
	end
	return nil
end

remotes.OpenInterface.OnClientEvent:Connect(function(kind: string, data: any)
	if kind ~= "Guidance" or type(data) ~= "table" or type(data.locationId) ~= "string" then
		return
	end
	local target = findLocation(data.locationId)
	if target == nil then
		return
	end
	local column = Instance.new("Part")
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CastShadow = false
	column.Material = Enum.Material.Neon
	column.Color = Color3.fromRGB(230, 190, 90)
	column.Transparency = 0.85
	column.Size = Vector3.new(3, 40, 3)
	column.Position = target.Position + Vector3.new(0, 20, 0)
	column.Parent = workspace
	task.delay(math.clamp(tonumber(data.seconds) or 10, 1, 60), function()
		local fade = TweenService:Create(column, TweenInfo.new(1.5), { Transparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		column:Destroy()
	end)
end)
