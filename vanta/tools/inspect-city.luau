--!nocheck
-- lune run tools/inspect-city.luau — builds the city offline and checks every building House builds for things a
-- player would trip over: anything solid in the doorway or the first steps inside, on a stair lane, or on a
-- landing. Prints the problems and a summary; exits 1 if there are any.
local Harness = require("./harness")
Harness.loadSource("src")
local CityBuilder = Harness.require(Harness.find("ServerScriptService.Server.Tools.CityBuilder"))
local House = Harness.require(Harness.find("ServerScriptService.Server.Tools.CityBuilder.House"))
local Layout = Harness.require(Harness.find("ServerStorage.ServerData.CityLayout"))
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local city = CityBuilder.build()
local byId = {}
for _, model in city.Districts:GetDescendants() do
	if model:IsA("Model") then
		byId[model.Name] = model
	end
end
-- parts that are allowed in the clearance boxes: the stairs themselves, rails, floors
local ALLOWED = { StairsRamp = true, StairsStep = true, Rail = true, Slab = true, Floor = true, Plinth = true, JettyFloor = true }

local function localBox(frame, part)
	local cf, s = part.CFrame, part.Size / 2
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local p = frame:PointToObjectSpace(cf:PointToWorldSpace(roblox.Vector3.new(x * s.X, y * s.Y, z * s.Z)))
				minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
				maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
			end
		end
	end
	return minV, maxV
end

local problems, checked = {}, 0
local byKind = {}
for _, entry in Layout.blocks do
	local model = byId[entry.id]
	if model and entry.door then
		checked += 1
		local plan = House.plan(entry, Layout, roblox.Instance.new("Model"))
		local frame = plan.frame.cframe
		local boxes = {}
		for _, c in House.clearances(plan) do
			table.insert(boxes, { c[7], c[1], c[2], c[3], c[4], c[5], c[6] })
		end
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and not ALLOWED[part.Name] then
				local lo, hi = localBox(frame, part)
				for _, b in boxes do
					if hi.X > b[2] and lo.X < b[3] and hi.Y > b[4] and lo.Y < b[5] and hi.Z > b[6] and lo.Z < b[7] then
						local key = b[1]:gsub("%d+$", "") .. ":" .. part.Name
						byKind[key] = (byKind[key] or 0) + 1
						table.insert(problems, string.format("%s (%s) %s blocked by %s", entry.id, entry.use, b[1], part.Name))
					end
				end
			end
		end
	end
end
for key, n in byKind do
	print(string.format("%-36s %d", key, n))
end
for i = 1, math.min(20, #problems) do
	print(problems[i])
end
print(string.format("%d buildings checked, %d problems", checked, #problems))
Harness.exit(if #problems == 0 then 0 else 1)
