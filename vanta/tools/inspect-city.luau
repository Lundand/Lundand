--!nocheck
-- lune run tools/inspect-city.luau — builds the city offline and checks:
--   * every house door is tagged HouseDoor and leads to an interior model that exists (with Entry and ExitDoor),
--     and the spot in front of it where you come out is clear
--   * every room sits on its pivot, fits its slot, and has Entry clear of its walls
--   * deed plaques read towards the street and hang clear of windows; estate gates line up with the mansion doors
--   * every public building's doorway is clear, and every inn has its rooms door (clear of windows) and room model
--   * every shop's room has its counter, with room for a customer in front, and every guild hall's its planning table
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
local LayoutRules = Harness.require(Harness.find("ServerScriptService.Server.Domain.LayoutRules"))

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

-- Separating-axis test between two boxes (CFrame, size); margin shrinks them (so touching isn't overlapping).
local function boxesOverlap(cfA, sizeA, cfB, sizeB, margin)
	local axesA = { cfA.RightVector, cfA.UpVector, cfA.LookVector }
	local axesB = { cfB.RightVector, cfB.UpVector, cfB.LookVector }
	local ha, hb = sizeA / 2, sizeB / 2
	local ea, eb = { ha.X, ha.Y, ha.Z }, { hb.X, hb.Y, hb.Z }
	local d = cfB.Position - cfA.Position
	local axes = {}
	for i = 1, 3 do
		table.insert(axes, axesA[i])
		table.insert(axes, axesB[i])
		for j = 1, 3 do
			local c = axesA[i]:Cross(axesB[j])
			if c.Magnitude > 1e-4 then
				table.insert(axes, c.Unit)
			end
		end
	end
	for _, axis in axes do
		local ra, rb = 0, 0
		for i = 1, 3 do
			ra += ea[i] * math.abs(axesA[i]:Dot(axis))
			rb += eb[i] * math.abs(axesB[i]:Dot(axis))
		end
		if math.abs(d:Dot(axis)) >= ra + rb - (margin or 0) then
			return false
		end
	end
	return true
end

-- every part of the city on a coarse grid, for "what is near here" questions
local nearGrid, NEAR = {}, 24
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		local p, half = d.CFrame.Position, d.Size / 2
		local r = half.Magnitude
		for i = math.floor((p.X - r) / NEAR), math.floor((p.X + r) / NEAR) do
			for j = math.floor((p.Z - r) / NEAR), math.floor((p.Z + r) / NEAR) do
				local key = i .. ":" .. j
				nearGrid[key] = nearGrid[key] or {}
				table.insert(nearGrid[key], d)
			end
		end
	end
end
local function partsNear(point)
	local seen, list = {}, {}
	for i = math.floor(point.X / NEAR) - 1, math.floor(point.X / NEAR) + 1 do
		for j = math.floor(point.Z / NEAR) - 1, math.floor(point.Z / NEAR) + 1 do
			for _, part in nearGrid[i .. ":" .. j] or {} do
				if not seen[part] then
					seen[part] = true
					table.insert(list, part)
				end
			end
		end
	end
	return list
end

-- rooms: InteriorService pivots a room onto its slot and measures its box; the box must sit on the slot, fit in it
-- with room to spare, and have Entry inside it, clear of the walls
local spacing = Layout.interiors.spacing
for _, room in interiors:GetChildren() do
	local copy = room:Clone()
	copy:PivotTo(roblox.CFrame.new(1000, 500, 1000))
	local entry = copy:FindFirstChild("Entry")
	local boxCf, size = copy:GetBoundingBox()
	local offset = boxCf.Position - Vector3.new(1000, 500, 1000)
	if math.abs(offset.X) > 0.5 or math.abs(offset.Z) > 0.5 then
		problem(string.format("interior %s is off its pivot by (%.1f, %.1f)", room.Name, offset.X, offset.Z))
	end
	if math.max(size.X, size.Z) + 16 > spacing then
		problem(string.format("interior %s (%.0f x %.0f) doesn't fit a %d-stud slot", room.Name, size.X, size.Z, spacing))
	end
	if entry ~= nil then
		local body = roblox.CFrame.new(entry.CFrame.Position + Vector3.new(0, 3, 0))
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and boxesOverlap(body, Vector3.new(2, 4.8, 2), part.CFrame, part.Size, 0.01) then
				problem("interior " .. room.Name .. "'s Entry stands in " .. part.Name)
			end
		end
	end
end

-- house doors: where you come out (InteriorService: 3 studs in front of the door) is clear for a character
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") and d:HasTag("HouseDoor") then
		local out = d.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))
		local feet = d.CFrame.Position - Vector3.new(0, d.Size.Y / 2, 0)
		local spot = feet + out * 3 + Vector3.new(0, 2.7, 0)
		local body = roblox.CFrame.lookAt(spot, spot + out)
		for _, part in partsNear(spot) do
			if part.CanCollide and part ~= d and boxesOverlap(body, Vector3.new(2, 5, 1.2), part.CFrame, part.Size, 0.01) then
				problem(tostring(d:GetAttribute("HouseId")) .. "'s way out runs into " .. part.Name)
				break
			end
		end
	end
end

-- deed plaques read towards the street and hang clear of windows
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") and d:HasTag("PropertySign") then
		local gui = d:FindFirstChildOfClass("SurfaceGui")
		local facing = nil
		if gui ~= nil and gui.Face == roblox.Enum.NormalId.Back then
			facing = d.CFrame.LookVector * -1
		elseif gui ~= nil and gui.Face == roblox.Enum.NormalId.Front then
			facing = d.CFrame.LookVector
		end
		local owner = nil
		for _, entry in Layout.blocks do
			if entry.propertyId ~= nil and entry.propertyId == d:GetAttribute("PropertyId") then
				owner = entry
			end
		end
		if facing == nil or owner == nil then
			problem("deed plaque " .. d.Name .. " has no text or no building")
		else
			local ahead = d.CFrame.Position + facing
			if LayoutRules.contains(owner, { ahead.X, ahead.Z }) then
				problem("deed plaque " .. d.Name .. " reads towards the wall")
			end
			-- in the facade's plane: glass is set into the wall, windows stand proud of it
			for _, part in partsNear(d.CFrame.Position) do
				if part.Name == "Window" or part.Name == "Glass" then
					local q = d.CFrame:PointToObjectSpace(part.CFrame.Position)
					if math.abs(q.Z) < 1.2 and math.abs(q.X) < (d.Size.X + part.Size.X) / 2 and math.abs(q.Y) < (d.Size.Y + part.Size.Y) / 2 then
						problem("deed plaque " .. d.Name .. " hangs over a window")
						break
					end
				end
			end
		end
	end
end

-- shops and guild halls: the room behind the door has its counter (with room for a customer in front of it) or its
-- planning table
for _, entry in Layout.blocks do
	local fitting = if entry.shopfront then "ShopCounter" elseif entry.use == "GuildHall" then "PlanningTable" else nil
	local model = models[entry.id]
	local door = model and model:FindFirstChild("Door", true)
	if fitting ~= nil then
		local room = door and interiors:FindFirstChild(door:GetAttribute("Interior"))
		local part = room and room:FindFirstChild(fitting)
		if part == nil then
			problem(entry.id .. "'s room has no " .. fitting)
		elseif fitting == "ShopCounter" then
			local front = part.CFrame * roblox.CFrame.new(0, 1.1, part.Size.Z / 2 + 1.2)
			for _, other in room:GetDescendants() do
				if other:IsA("BasePart") and other.CanCollide and other ~= part and boxesOverlap(front, Vector3.new(2, 4.5, 1.2), other.CFrame, other.Size, 0.01) then
					problem(entry.id .. "'s counter has no room for a customer: " .. other.Name)
					break
				end
			end
		end
	end
end

-- inn rooms doors stand clear of the back windows
for _, d in city:GetDescendants() do
	if d.Name == "RoomsDoor" and d:IsA("BasePart") then
		for _, part in d.Parent:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Glass" then
				local p = d.CFrame:PointToObjectSpace(part.CFrame.Position)
				if math.abs(p.X) < d.Size.X / 2 + part.Size.X / 2 and math.abs(p.Z) < 2 then
					problem(d.Parent.Name .. "'s rooms door stands in front of a window")
				end
			end
		end
	end
end

-- estate gates: the path from a mansion's door straight out to its garden wall goes through the gate
for _, entry in Layout.blocks do
	if entry.estate ~= nil and models[entry.id] ~= nil then
		local door = models[entry.id]:FindFirstChild("Door", true)
		if door ~= nil then
			local out = door.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1))
			local from = door.CFrame.Position - Vector3.new(0, door.Size.Y / 2 - 1.5, 0)
			local blocked = false
			-- out to just past its own garden wall
			local garden = { center = entry.estate.center, size = { entry.estate.size[1] + 4, entry.estate.size[2] + 4 } }
			for step = 1, 80 do
				local point = from + out * step
				if not LayoutRules.contains(garden, { point.X, point.Z }) then
					break
				end
				for _, part in partsNear(point) do
					if part.Name == "GardenWall" and boxesOverlap(roblox.CFrame.new(point), Vector3.new(2, 1, 0.5), part.CFrame, part.Size, 0) then
						blocked = true
					end
				end
			end
			if blocked then
				problem(entry.id .. "'s garden gate doesn't line up with its door")
			end
		end
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
			local centre = cf.Position + n * sizes[axis]
			-- a face turned down at street level rests on the ground
			if keep and not (n.Y < -0.9 and centre.Y < 0.5) then
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
			-- on the boundary counts: a point where two abutting blocks meet is inside the pair of them
			if math.abs(q.X) <= half.X + 0.01 and math.abs(q.Y) <= half.Y + 0.01 and math.abs(q.Z) <= half.Z + 0.01 then
				return true
			end
		end
	end
	return false
end

local flicker = {}
local function extent(face, axis)
	return math.abs(face.u:Dot(axis)) * face.hu + math.abs(face.v:Dot(axis)) * face.hv
end
local function comparePair(a, b)
	if a.part == b.part or math.abs(a.d - b.d) >= 0.02 then
		return
	end
	-- overlap of the two rectangles, measured in a's plane
	local delta = b.centre - a.centre
	local su, sv = delta:Dot(a.u), delta:Dot(a.v)
	local u0, u1 = math.max(-a.hu, su - extent(b, a.u)), math.min(a.hu, su + extent(b, a.u))
	local v0, v1 = math.max(-a.hv, sv - extent(b, a.v)), math.min(a.hv, sv + extent(b, a.v))
	if u1 - u0 <= 0.05 or v1 - v0 <= 0.05 then
		return
	end
	-- hidden only if the overlap is covered all over: its middle and four points round it, just in front of the faces
	local mu, mv = (u0 + u1) / 2, (v0 + v1) / 2
	local qu, qv = (u1 - u0) / 4, (v1 - v0) / 4
	for _, at in { { 0, 0 }, { -qu, -qv }, { qu, -qv }, { -qu, qv }, { qu, qv } } do
		local point = a.centre + a.u * (mu + at[1]) + a.v * (mv + at[2]) + a.n * 0.05
		if not covered(point, a.part, b.part) then
			local key = a.part.Name .. " / " .. b.part.Name
			flicker[key] = (flicker[key] or 0) + 1
			if process.env.FLICKER_DETAIL and (flicker[key] == 1 or process.env.FLICKER_DETAIL == "all") then
				print(string.format("  %s: normal (%.2f %.2f %.2f) at (%.1f %.1f %.1f) in %s / %s", key, a.n.X, a.n.Y, a.n.Z, a.centre.X, a.centre.Y, a.centre.Z, a.part.Parent.Name, b.part.Parent.Name))
			end
			return
		end
	end
end
-- faces in the same plane are compared when their rectangles share a cell, so a plane every house shares (storey
-- lines, lintels, eaves) is checked in full without comparing every face with every other
local PAIR_CELL = 32
for _, list in buckets do
	if #list > 1 then
		local cells = {}
		for index, f in list do
			local ex = math.abs(f.u.X) * f.hu + math.abs(f.v.X) * f.hv
			local ey = math.abs(f.u.Y) * f.hu + math.abs(f.v.Y) * f.hv
			local ez = math.abs(f.u.Z) * f.hu + math.abs(f.v.Z) * f.hv
			local c = f.centre
			for i = math.floor((c.X - ex) / PAIR_CELL), math.floor((c.X + ex) / PAIR_CELL) do
				for j = math.floor((c.Y - ey) / PAIR_CELL), math.floor((c.Y + ey) / PAIR_CELL) do
					for k = math.floor((c.Z - ez) / PAIR_CELL), math.floor((c.Z + ez) / PAIR_CELL) do
						local key = i .. ":" .. j .. ":" .. k
						cells[key] = cells[key] or {}
						table.insert(cells[key], index)
					end
				end
			end
		end
		local compared = {}
		for _, members in cells do
			for x = 1, #members do
				for y = x + 1, #members do
					local pairKey = members[x] * 1000000 + members[y]
					if not compared[pairKey] then
						compared[pairKey] = true
						comparePair(list[members[x]], list[members[y]])
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
