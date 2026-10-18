--!nonstrict
-- Authoring tool: reads a MeshPart's triangles and draws its silhouette as text (front: X across, Y up; side: Z across, Y up),
-- and reports width per height slice. Used to check the shape and orientation of generated meshes without the viewport.
local AssetService = game:GetService("AssetService")
local MeshProbe = {}

local function load(part)
	return AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
end

-- triangles in mesh space, scaled to the part's current size
function MeshProbe.triangles(part)
	local em = load(part)
	local minP, maxP = Vector3.one * math.huge, -Vector3.one * math.huge
	local positions = {}
	for _, v in ipairs(em:GetVertices()) do
		local p = em:GetPosition(v)
		positions[v] = p
		minP = minP:Min(p)
		maxP = maxP:Max(p)
	end
	local meshSize = maxP - minP
	local scale = Vector3.new(part.Size.X / math.max(meshSize.X, 1e-6), part.Size.Y / math.max(meshSize.Y, 1e-6), part.Size.Z / math.max(meshSize.Z, 1e-6))
	local center = (minP + maxP) / 2
	local tris = {}
	for _, f in ipairs(em:GetFaces()) do
		local ids = em:GetFaceVertices(f)
		local t = {}
		for i = 1, 3 do t[i] = (positions[ids[i]] - center) * scale end
		table.insert(tris, t)
	end
	em:Destroy()
	return tris, part.Size
end

local function raster(tris, size, axisU, axisV, cols, rows)
	local grid = {}
	for r = 1, rows do grid[r] = table.create(cols, " ") end
	local halfU, halfV = size[axisU] / 2, size[axisV] / 2
	local function cell(p)
		local u = (p[axisU] + halfU) / (2 * halfU)
		local v = (p[axisV] + halfV) / (2 * halfV)
		return u * (cols - 1) + 1, (1 - v) * (rows - 1) + 1
	end
	for _, t in ipairs(tris) do
		local ax, ay = cell(t[1]); local bx, by = cell(t[2]); local cx, cy = cell(t[3])
		local minX, maxX = math.floor(math.min(ax, bx, cx)), math.ceil(math.max(ax, bx, cx))
		local minY, maxY = math.floor(math.min(ay, by, cy)), math.ceil(math.max(ay, by, cy))
		for y = math.max(1, minY), math.min(rows, maxY) do
			for x = math.max(1, minX), math.min(cols, maxX) do
				-- barycentric inside test (with a small margin so thin triangles still show)
				local d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
				if math.abs(d) < 1e-9 then
					grid[y][x] = "#"
				else
					local l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / d
					local l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / d
					local l3 = 1 - l1 - l2
					if l1 >= -0.15 and l2 >= -0.15 and l3 >= -0.15 then grid[y][x] = "#" end
				end
			end
		end
	end
	local lines = {}
	for r = 1, rows do lines[r] = table.concat(grid[r]) end
	return table.concat(lines, "\n")
end

-- views: "front" (X,Y), "side" (Z,Y), "top" (X,Z)
function MeshProbe.draw(part, view, cols, rows)
	local tris, size = MeshProbe.triangles(part)
	local axes = { front = { "X", "Y" }, side = { "Z", "Y" }, top = { "X", "Z" } }
	local a = axes[view or "front"]
	return raster(tris, size, a[1], a[2], cols or 40, rows or 30)
end

return MeshProbe
