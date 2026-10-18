--!nocheck
-- lune run tools/inspect-city.luau — builds the city offline and checks:
--   * every house door is tagged HouseDoor and leads to an interior model that exists (with Entry and ExitDoor)
--   * every public building's doorway is clear, and every inn has its rooms door and room model
--   * flicker: no two visible faces of different parts lie in the same plane, facing the same way, overlapping
-- Prints the problems and a summary; exits 1 if there are any.
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Vector3 = roblox.Vector3
local Harness = require("./harness")
Harness.loadSource("src")
local game = Harness.game
local CityBuilder = Harness.require(Harness.find("ServerScriptService.Server.Tools.CityBuilder"))
local Content = Harness.require(Harness.find("ReplicatedStorage.Shared.Content"))
local Layout = Harness.require(Harness.find("ServerStorage.ServerData.CityLayout"))

local city = CityBuilder.build()
local problems = {}
local function problem(text)
	table.insert(problems, text)
end

local interiors = game:GetService("ServerStorage").CityAssets.Interiors
local models = {}
for _, d in city:GetDescendants() do
	if d:IsA("Model") then
		models[d.Name] = d
	end
end

-- doors and interiors
local doors = 0
for _, entry in Layout.blocks do
	local model = models[entry.id]
	if model ~= nil and model:GetAttribute("Use") ~= nil then
		if not CityBuilder.PUBLIC[entry.use] then
			local door = model:FindFirstChild("Door", true)
			if door == nil or not door:HasTag("HouseDoor") then
				problem(entry.id .. " has no tagged door")
			else
				doors += 1
				local key = door:GetAttribute("Interior")
				local room = interiors:FindFirstChild(key)
				if room == nil then
					problem(entry.id .. " leads to a missing interior " .. tostring(key))
				end
				if entry.propertyId ~= nil and door:GetAttribute("PropertyId") ~= entry.propertyId then
					problem(entry.id .. " door doesn't carry its property ID")
				end
			end
		end
	end
end
for _, room in interiors:GetChildren() do
	local entry, exit = room:FindFirstChild("Entry"), room:FindFirstChild("ExitDoor")
	if entry == nil or exit == nil then
		problem("interior " .. room.Name .. " is missing Entry or ExitDoor")
	end
end
for innId in Content.world.inns do
	if interiors:FindFirstChild("InnRoom_" .. innId) == nil then
		problem("no room model for inn " .. innId)
	end
	local found = false
	for _, d in city:GetDescendants() do
		if d.Name == "RoomsDoor" and d:GetAttribute("InnId") == innId and d:HasTag("InnRooms") then
			found = true
		end
	end
	if not found then
		problem("inn " .. innId .. " has no rooms door")
	end
end

-- doorways of public buildings: nothing solid in the opening
for _, entry in Layout.blocks do
	local model = models[entry.id]
	if model ~= nil and CityBuilder.PUBLIC[entry.use] then
		local yawDoor = ({ South = 0, North = 180, East = 90, West = -90 })[entry.door]
		local W, D = entry.size[1], entry.size[2]
		if entry.door == "East" or entry.door == "West" then
			W, D = entry.size[2], entry.size[1]
		end
		local frame = roblox.CFrame.new(entry.center[1], 0, entry.center[2]) * roblox.CFrame.Angles(0, math.rad((entry.yaw or 0) + yawDoor), 0)
		local doorX = if W >= 18 then -W / 6 else 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				local p = frame:PointToObjectSpace(part.CFrame.Position)
				local half = part.Size / 2
				local reach = math.max(half.X, half.Z)
				if math.abs(p.X - doorX) < 2.4 + reach and p.Z > D / 2 - 4 - reach and p.Z < D / 2 + 3 + reach and p.Y - half.Y < 7 and p.Y + half.Y > 1.2 then
					-- a wall piece beside or above the opening is fine; test the exact box against the doorway
					local lo = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(-half))
					local hi = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(half))
					local x0, x1 = math.min(lo.X, hi.X), math.max(lo.X, hi.X)
					local y0, y1 = math.min(lo.Y, hi.Y), math.max(lo.Y, hi.Y)
					local z0, z1 = math.min(lo.Z, hi.Z), math.max(lo.Z, hi.Z)
					if x1 > doorX - 2.4 and x0 < doorX + 2.4 and y1 > 1.2 and y0 < 7 and z1 > D / 2 - 4 and z0 < D / 2 + 3 then
						problem(entry.id .. " doorway blocked by " .. part.Name)
					end
				end
			end
		end
	end
end

-- flicker: coplanar faces of different parts facing the same way and overlapping
local faces = {}
local function addFaces(part)
	if part.Transparency >= 0.95 then
		return
	end
	local cf, half = part.CFrame, part.Size / 2
	local axes = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local sizes = { half.X, half.Y, half.Z }
	local isWedge = part:IsA("WedgePart")
	local shaped = part:IsA("Part") and part.Shape ~= roblox.Enum.PartType.Block
	if shaped then
		return
	end
	for axis = 1, 3 do
		for _, sign in { -1, 1 } do
			-- a wedge's sloped face and its triangles aren't rectangles: keep only its bottom (-y) and back (+z) faces
			local keep = true
			if isWedge then
				keep = (axis == 2 and sign == -1) or (axis == 3 and sign == 1)
			end
			local n = axes[axis] * sign
			-- faces turned to the ground rest on something; flicker there can't be seen
			if keep and n.Y > -0.9 then
				local centre = cf.Position + n * sizes[axis]
				local u = axes[axis % 3 + 1]
				local v = axes[(axis + 1) % 3 + 1]
				local hu, hv = sizes[axis % 3 + 1], sizes[(axis + 1) % 3 + 1]
				table.insert(faces, { part = part, n = n, d = n:Dot(centre), centre = centre, u = u, v = v, hu = hu, hv = hv })
			end
		end
	end
end
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		addFaces(d)
	end
end
local buckets = {}
for _, f in faces do
	local key = string.format("%d,%d,%d|%d", math.floor(f.n.X * 100 + 0.5), math.floor(f.n.Y * 100 + 0.5), math.floor(f.n.Z * 100 + 0.5), math.floor(f.d * 20 + 0.5))
	buckets[key] = buckets[key] or {}
	table.insert(buckets[key], f)
end
-- a face covered by a third part (both faces hidden inside it) can't flicker: occluders on a coarse grid
local occluders = {}
local CELL = 16
for _, d in city:GetDescendants() do
	if d:IsA("Part") and d.Shape == roblox.Enum.PartType.Block and d.Transparency < 0.5 then
		local p, half = d.CFrame.Position, d.Size / 2
		local r = math.max(half.X, half.Y, half.Z) * 1.8
		for i = math.floor((p.X - r) / CELL), math.floor((p.X + r) / CELL) do
			for j = math.floor((p.Z - r) / CELL), math.floor((p.Z + r) / CELL) do
				local key = i .. ":" .. j
				occluders[key] = occluders[key] or {}
				table.insert(occluders[key], d)
			end
		end
	end
end
local function covered(point, a, b)
	for _, part in occluders[math.floor(point.X / CELL) .. ":" .. math.floor(point.Z / CELL)] or {} do
		if part ~= a and part ~= b then
			local q = part.CFrame:PointToObjectSpace(point)
			local half = part.Size / 2
			if math.abs(q.X) < half.X - 0.01 and math.abs(q.Y) < half.Y - 0.01 and math.abs(q.Z) < half.Z - 0.01 then
				return true
			end
		end
	end
	return false
end

local flicker = {}
for _, list in buckets do
	if #list > 1 and #list < 400 then
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if a.part ~= b.part and math.abs(a.d - b.d) < 0.02 then
					-- overlap of the two rectangles, measured in a's plane
					local function extent(face, axis)
						return math.abs(face.u:Dot(axis)) * face.hu + math.abs(face.v:Dot(axis)) * face.hv
					end
					local delta = b.centre - a.centre
					local du, dv = math.abs(delta:Dot(a.u)), math.abs(delta:Dot(a.v))
					local overlapU = a.hu + extent(b, a.u) - du
					local overlapV = a.hv + extent(b, a.v) - dv
					local hidden = false
					if overlapU > 0.05 and overlapV > 0.05 then
						-- the middle of the overlap, just in front of the faces
						local su, sv = delta:Dot(a.u), delta:Dot(a.v)
						local u0, u1 = math.max(-a.hu, su - extent(b, a.u)), math.min(a.hu, su + extent(b, a.u))
						local v0, v1 = math.max(-a.hv, sv - extent(b, a.v)), math.min(a.hv, sv + extent(b, a.v))
						local point = a.centre + a.u * ((u0 + u1) / 2) + a.v * ((v0 + v1) / 2) + a.n * 0.05
						hidden = covered(point, a.part, b.part)
					end
					if overlapU > 0.05 and overlapV > 0.05 and not hidden then
						local key = a.part.Name .. " / " .. b.part.Name
						flicker[key] = (flicker[key] or 0) + 1
						if process.env.FLICKER_DETAIL and flicker[key] == 1 then
							print(string.format("  %s: normal (%.2f %.2f %.2f) at (%.1f %.1f %.1f) in %s / %s", key, a.n.X, a.n.Y, a.n.Z, a.centre.X, a.centre.Y, a.centre.Z, a.part.Parent.Name, b.part.Parent.Name))
						end
					end
				end
			end
		end
	end
end
local flickerCount = 0
for key, n in flicker do
	flickerCount += n
	problem(string.format("flicker: %s (%d)", key, n))
end

for i = 1, math.min(tonumber(os.getenv and "200" or "200"), #problems) do
	print(problems[i])
end
local parts, lights = 0, 0
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	elseif d:IsA("PointLight") then
		lights += 1
	end
end
print(string.format("%d house doors, %d interior models, %d parts, %d lights, %d coplanar overlaps, %d problems", doors, #interiors:GetChildren(), parts, lights, flickerCount, #problems))
Harness.exit(if #problems == 0 then 0 else 1)
