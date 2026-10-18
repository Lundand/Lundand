--!strict
-- The early-game forest beyond the south gate: a dirt road from the gate that winds into the trees, side paths,
-- clearings, low hills, rocks, roots, fallen logs, a few abandoned structures, and the wolves' den in a rocky hollow.
-- The spawner and gathering zones keep their IDs (ForestEdge, ForestDeep, ForestDen).
local Kit = require(script.Parent.Kit)

local Forest = {}
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }

local function generator(seed: number)
	local state = seed * 7919 + 17
	local self = {}
	function self.unit(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function self.range(a: number, b: number): number
		return a + (b - a) * self.unit()
	end
	return self
end

local function distanceToSegment(px: number, pz: number, a: {number}, b: {number}): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
	local cx, cz = a[1] + t * dx, a[2] + t * dz
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

local function pathDistance(spec: any, x: number, z: number): number
	local best = math.huge
	local lines = { spec.path }
	for _, branch in ipairs(spec.branches) do
		table.insert(lines, branch)
	end
	for _, line in ipairs(lines) do
		for index = 1, #line - 1 do
			best = math.min(best, distanceToSegment(x, z, line[index], line[index + 1]))
		end
	end
	return best
end

local function tree(f: Frame, x: number, z: number, scale: number, rng: any, dark: boolean)
	local trunkH = 9 * scale
	f:cyl("Trunk", trunkH, 1.6 * scale, x, 0, z, rgb(92, 66, 44), M.Wood)
	local leaves: {Color3} = if dark then { rgb(40, 74, 44), rgb(36, 66, 40) } else { rgb(62, 112, 52), rgb(74, 126, 58), rgb(54, 100, 48) }
	for index = 1, 3 do
		local a = index * 2.1 + rng.unit()
		local r = 1.6 * scale
		local size = (5.5 + rng.unit() * 2.5) * scale
		local leaf = f:box("Leaves", Vector3.new(size, size, size), x + math.cos(a) * r, trunkH + (index - 1) * 1.2 * scale, z + math.sin(a) * r, leaves[(index % #leaves) + 1], M.Grass, NO)
		leaf.Shape = Enum.PartType.Ball
	end
	if scale > 1.2 and rng.unit() < 0.5 then
		-- exposed roots
		for _, a in ipairs({ rng.unit() * 6.28, rng.unit() * 6.28 }) do
			f:boxAt("Root", Vector3.new(0.7 * scale, 0.6 * scale, 4 * scale), CFrame.new(x + math.cos(a) * 1.8 * scale, 0.25, z + math.sin(a) * 1.8 * scale) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(8), 0, 0), rgb(84, 60, 40), M.Wood, NO)
		end
	end
end

local function pine(f: Frame, x: number, z: number, scale: number)
	f:cyl("Trunk", 6 * scale, 1.2 * scale, x, 0, z, rgb(84, 60, 40), M.Wood)
	local y, w = 4 * scale, 8 * scale
	for index = 1, 3 do
		f:boxAt("Needles", Vector3.new(w, 3.4 * scale, w), CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(45 * index), 0), rgb(40, 82, 50), M.Grass, NO)
		y += 3 * scale
		w *= 0.68
	end
end

local function rock(f: Frame, x: number, z: number, size: number, rng: any)
	f:boxAt("Rock", Vector3.new(size, size * 0.6, size * 0.85), CFrame.new(x, size * 0.2, z) * CFrame.Angles(rng.unit() * 0.4, rng.unit() * 6.28, rng.unit() * 0.4), rgb(118, 116, 108), M.Slate)
end

local function hill(f: Frame, x: number, z: number, w: number, d: number, h: number)
	local color, material = rgb(86, 124, 66), M.Grass
	local slope = h * 3
	f:box("HillTop", Vector3.new(w, h, d), x, h / 2 - 0.1, z, color, material)
	f:wedgeAt("HillSide", Vector3.new(w, h, slope), CFrame.new(x, h / 2 - 0.1, z + d / 2 + slope / 2) * CFrame.Angles(0, math.pi, 0), color, material)
	f:wedgeAt("HillSide", Vector3.new(w, h, slope), CFrame.new(x, h / 2 - 0.1, z - d / 2 - slope / 2), color, material)
	f:wedgeAt("HillSide", Vector3.new(d, h, slope), CFrame.new(x + w / 2 + slope / 2, h / 2 - 0.1, z) * CFrame.Angles(0, -math.pi / 2, 0), color, material)
	f:wedgeAt("HillSide", Vector3.new(d, h, slope), CFrame.new(x - w / 2 - slope / 2, h / 2 - 0.1, z) * CFrame.Angles(0, math.pi / 2, 0), color, material)
end

local function ruin(f: Frame, spec: any)
	local x, z = spec.center[1], spec.center[2]
	local stone, wood = rgb(130, 126, 118), rgb(96, 74, 52)
	if spec.kind == "Cabin" then
		-- a hunter's cabin, roof fallen in, door gone
		f:box("CabinFloor", Vector3.new(16, 0.6, 12), x, 0.3, z, rgb(110, 86, 60), M.WoodPlanks)
		f:box("CabinWall", Vector3.new(15.8, 7, 1), x, 3.5, z - 5.5, wood, M.WoodPlanks)
		f:box("CabinWall", Vector3.new(1, 5, 10), x - 7.4, 2.5, z, wood, M.WoodPlanks)
		f:box("CabinWall", Vector3.new(1, 3, 5.5), x + 7.4, 1.5, z - 2.25, wood, M.WoodPlanks)
		f:box("CabinWall", Vector3.new(4.8, 7, 1), x - 5.3, 3.5, z + 5.4, wood, M.WoodPlanks)
		f:boxAt("FallenRoof", Vector3.new(14, 0.6, 8), CFrame.new(x + 1, 3, z - 1) * CFrame.Angles(math.rad(25), 0, math.rad(8)), rgb(90, 76, 60), M.WoodPlanks)
		f:box("Hearth", Vector3.new(4, 4, 2), x - 5, 2, z - 4.4, stone, M.Cobblestone)
	elseif spec.kind == "Watchtower" then
		-- an old forest watchtower: posts, a tilted platform, a broken ladder
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				f:box("TowerPost", Vector3.new(1, 16, 1), x + sx * 4, 8, z + sz * 4, wood, M.Wood)
			end
		end
		f:boxAt("TowerPlatform", Vector3.new(10, 0.8, 10), CFrame.new(x, 15, z) * CFrame.Angles(0, 0, math.rad(6)), wood, M.WoodPlanks)
		f:box("Ladder", Vector3.new(2, 10, 0.4), x, 5, z + 4.6, wood, M.Wood, NO)
		f:boxAt("BrokenBeam", Vector3.new(0.6, 0.6, 9), CFrame.new(x + 6, 0.4, z + 3) * CFrame.Angles(0, 0.6, 0), wood, M.Wood)
	else
		-- a forgotten shrine of the old faith, overgrown
		f:box("ShrinePlinth", Vector3.new(10, 1.2, 10), x, 0.6, z, stone, M.Cobblestone)
		f:box("ShrineStone", Vector3.new(3, 9, 1.6), x, 5.7, z - 2, stone, M.Slate)
		local rune = f:box("ShrineRune", Vector3.new(1.2, 1.2, 0.2), x, 7, z - 1.1, rgb(140, 170, 255), M.Neon, NO)
		rune.Transparency = 0.4
		for _, sx in ipairs({ -1, 1 }) do
			f:box("ShrineCandle", Vector3.new(0.6, 1, 0.6), x + sx * 2, 1.7, z + 1, rgb(220, 210, 180), M.SmoothPlastic, NO)
		end
	end
end

function Forest.build(layout: any, root: Instance): Folder
	local spec = layout.forest
	local folder = Kit.folder(root, "Forest")
	local f = Kit.frame(folder, CFrame.new())
	local rng = generator(spec.seed)
	local b = spec.bounds
	local groundPart = f:box("ForestGround", Vector3.new(b.maxX - b.minX, 2, b.maxZ - b.minZ), (b.minX + b.maxX) / 2, -1, (b.minZ + b.maxZ) / 2, rgb(78, 116, 60), M.LeafyGrass)
	groundPart.CastShadow = false
	-- the road out of the gate and the side paths
	local function trail(line: {{number}}, width: number)
		for index = 1, #line - 1 do
			local a, c = line[index], line[index + 1]
			local dx, dz = c[1] - a[1], c[2] - a[2]
			local length = math.sqrt(dx * dx + dz * dz)
			-- joints overlap, so neighbouring segments sit at different heights (no flicker where they cross)
			local lift = (index % 2) * 0.08 + (if width < 8 then 0.16 else 0)
			local seg = f:boxAt("Trail", Vector3.new(width, 0.2, length + width * 0.6), CFrame.new((a[1] + c[1]) / 2, 0.02 + lift, (a[2] + c[2]) / 2) * CFrame.Angles(0, math.atan2(dx, dz), 0), rgb(122, 98, 70), M.Ground)
			seg.CastShadow = false
		end
	end
	trail(spec.path, 9)
	for _, branch in ipairs(spec.branches) do
		trail(branch, 6)
	end
	for _, clearing in ipairs(spec.clearings) do
		local c = f:boxAt("Clearing", Vector3.new(0.2, clearing.radius * 2, clearing.radius * 2), CFrame.new(clearing.center[1], 0.01, clearing.center[2]) * CFrame.Angles(0, 0, math.pi / 2), rgb(104, 140, 72), M.Grass, { shape = Enum.PartType.Cylinder })
		c.CastShadow = false
	end
	for _, r in ipairs(spec.ruins) do
		ruin(f, r)
	end
	local function blocked(x: number, z: number, margin: number): boolean
		if pathDistance(spec, x, z) < margin then
			return true
		end
		for _, clearing in ipairs(spec.clearings) do
			if math.sqrt((x - clearing.center[1]) ^ 2 + (z - clearing.center[2]) ^ 2) < clearing.radius then
				return true
			end
		end
		for _, r in ipairs(spec.ruins) do
			if math.sqrt((x - r.center[1]) ^ 2 + (z - r.center[2]) ^ 2) < 16 then
				return true
			end
		end
		return false
	end
	-- low hills away from the paths
	local hills = 0
	for _ = 1, 80 do
		if hills >= 16 then
			break
		end
		local x, z = rng.range(b.minX + 40, b.maxX - 40), rng.range(b.minZ + 80, b.maxZ - 40)
		local w, d, h = rng.range(24, 50), rng.range(24, 50), rng.range(2, 5)
		if pathDistance(spec, x, z) > math.max(w, d) / 2 + h * 3 + 10 and not blocked(x, z, 0) then
			hill(f, x, z, w, d, h)
			hills += 1
		end
	end
	-- trees: a light fringe near the gate, thick woods beyond, darker towards the den
	local placed = 0
	for _ = 1, 2400 do
		if placed >= 300 then
			break
		end
		local x, z = rng.range(b.minX + 6, b.maxX - 6), rng.range(b.minZ + 6, b.maxZ - 6)
		local depth = (z - b.minZ) / (b.maxZ - b.minZ)
		local density = 0.25 + depth * 0.75
		if rng.unit() < density and not blocked(x, z, 9) then
			local scale = 1 + rng.unit() * 0.6 + depth * 0.5
			if rng.unit() < 0.35 + depth * 0.2 then
				pine(f, x, z, scale)
			else
				tree(f, x, z, scale, rng, depth > 0.7)
			end
			placed += 1
		end
	end
	-- undergrowth, rocks, logs, stumps
	for index = 1, 220 do
		local x, z = rng.range(b.minX + 4, b.maxX - 4), rng.range(b.minZ + 4, b.maxZ - 4)
		if not blocked(x, z, 6) then
			local roll = index % 6
			if roll <= 2 then
				local size = rng.range(3, 6)
				local bush = f:box("Bush", Vector3.new(size, size, size), x, size * 0.3, z, rgb(66, 110, 54), M.Grass, NO)
				bush.Shape = Enum.PartType.Ball
			elseif roll == 3 then
				rock(f, x, z, rng.range(3, 9), rng)
			elseif roll == 4 then
				local length = rng.range(10, 22)
				f:boxAt("FallenLog", Vector3.new(length, 2.2, 2.2), CFrame.new(x, 1, z) * CFrame.Angles(0, rng.unit() * 6.28, 0), rgb(90, 66, 44), M.Wood).Shape = Enum.PartType.Cylinder
			else
				f:cyl("Stump", 1.6, 2.4, x, 0, z, rgb(96, 70, 46), M.Wood)
			end
		end
	end
	-- the den: a ring of boulders round a hollow, bones, a cave mouth
	for _, zone in ipairs(spec.zones) do
		if zone.id == "ForestDen" then
			local cx, cz = zone.center[1], zone.center[2]
			for index = 0, 13 do
				local a = index / 14 * math.pi * 2
				if index ~= 10 and index ~= 11 then -- the way in, from the path
					rock(f, cx + math.cos(a) * 46, cz + math.sin(a) * 38, rng.range(8, 14), rng)
				end
			end
			f:box("CaveRock", Vector3.new(30, 18, 14), cx + 10, 9, cz + 30, rgb(96, 94, 90), M.Slate)
			f:box("CaveMouth", Vector3.new(8, 7, 0.4), cx + 10, 3.5, cz + 22.8, rgb(18, 16, 16), M.SmoothPlastic, NO)
			for k = 0, 5 do
				f:boxAt("Bone", Vector3.new(0.4, 0.4, 2), CFrame.new(cx + rng.range(-10, 10), 0.2 + k * 0.05, cz + rng.range(-10, 10)) * CFrame.Angles(0, rng.unit() * 6, 0), rgb(232, 226, 210), M.SmoothPlastic, NO)
			end
		end
	end
	-- outbuildings by the gate: the city gives way to fields
	local shed = Kit.frame(folder, CFrame.new(-44, 0, 360))
	shed:box("ShedFloor", Vector3.new(14, 0.6, 10), 0, 0.3, 0, rgb(110, 86, 60), M.WoodPlanks)
	shed:box("ShedWall", Vector3.new(13.8, 6.4, 0.8), 0, 3.8, -4.6, rgb(120, 92, 62), M.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		shed:box("ShedWall", Vector3.new(0.8, 6.9, 9), s * 6.5, 3.55, 0.3, rgb(120, 92, 62), M.WoodPlanks)
	end
	shed:wedgeAt("ShedRoof", Vector3.new(15, 3, 11), CFrame.new(0, 8.5, 0) * CFrame.Angles(0, math.pi, 0), rgb(110, 84, 64), M.WoodPlanks)
	for k = 0, 7 do
		shed:box("Fence", Vector3.new(0.4, 3, 6), 12 + k * 6, 1.5, -6, rgb(120, 92, 62), M.Wood, NO)
	end
	-- spawner and gathering zones (flat, above the ground; spawns raycast down onto it)
	for _, zone in ipairs(spec.zones) do
		local marker = f:box(zone.id, Vector3.new(zone.size[1], 10, zone.size[2]), zone.center[1], 5, zone.center[2], rgb(200, 60, 60), M.SmoothPlastic, { collide = false, query = false, transparency = 1, shadow = false })
		marker:SetAttribute("LocationId", zone.id)
	end
	-- the edge of the woods: an invisible fence keeps everyone on the map
	for _, wall in ipairs({ { b.minX, b.minZ, b.minX, b.maxZ }, { b.maxX, b.minZ, b.maxX, b.maxZ }, { b.minX, b.maxZ, b.maxX, b.maxZ } }) do
		local dx, dz = wall[3] - wall[1], wall[4] - wall[2]
		local length = math.sqrt(dx * dx + dz * dz)
		f:boxAt("Boundary", Vector3.new(2, 200, length), CFrame.new((wall[1] + wall[3]) / 2, 100, (wall[2] + wall[4]) / 2) * CFrame.Angles(0, math.atan2(dx, dz), 0), rgb(255, 255, 255), M.SmoothPlastic, { transparency = 1, shadow = false, query = false })
	end
	return folder
end

return Forest
