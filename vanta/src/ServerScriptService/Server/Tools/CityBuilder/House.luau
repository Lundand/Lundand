--!strict
-- Every enterable building in the streets: shell, floors, stairs, rooms and furniture, built in the building's
-- own frame. x runs across the facade, z towards the street (the door is in the front wall at +z), y is up.
--
-- Floors are FLOOR_HEIGHT apart (ground floor top at y = 0.6). Stairs climb inside a lane along one side wall:
--   straight   one lane, every flight front-to-back above the last; rooms open onto the lane (houses, shops)
--   switchback two lanes, flights alternate direction, so landings and corridors never cross a room
--              (apartments, inns, guild buildings, mansions)
-- Each upper slab has a hole over the flight that arrives at it, wide enough for headroom on the way up.
local Kit = require(script.Parent.Kit)
local Furniture = require(script.Parent.Furniture)

local House = {}
local C = Kit.colors
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame
type Rect = Kit.Rect

local WALL = 1
local LANDING = 2.6
local NO = { collide = false, query = false }

local DOOR_YAW = { South = 0, North = 180, East = 90, West = -90 }
-- side names in the entry's frame, seen from a building turned to face its door side
local SIDES = {
	South = { front = "South", back = "North", right = "East", left = "West" },
	North = { front = "North", back = "South", right = "West", left = "East" },
	East = { front = "East", back = "West", right = "North", left = "South" },
	West = { front = "West", back = "East", right = "South", left = "North" },
}

-- A small per-building generator so a building looks the same every time it is built.
local function generator(seed: number)
	local state = (seed % 2147483646) + 1
	local self = {}
	function self.unit(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function self.int(a: number, b: number): number
		return math.min(b, a + math.floor(self.unit() * (b - a + 1)))
	end
	function self.pick(list: {any}): any
		return list[self.int(1, #list)]
	end
	function self.chance(p: number): boolean
		return self.unit() < p
	end
	return self
end

local PUBLIC_DOORS = { Inn = true, Tavern = true, SlumTavern = true, Guild = true, CraftGuild = true, GuildHall = true, Customs = true, Office = true, Forge = true, Apothecary = true, Warehouse = true, Barracks = true, Chancery = true, Servants = true, Smithy = true }
local SWITCHBACK = { Apartments = true, Inn = true, Tavern = true, Guild = true, CraftGuild = true, Mansion = true, Customs = true, Chancery = true, Barracks = true, Servants = true, GuildHall = true }

export type Plan = {
	entry: any,
	frame: Frame,
	model: Model,
	W: number,
	D: number,
	N: number,
	FH: number,
	jetty: number,
	side: number,
	mode: string,
	laneX0: number,
	laneX1: number,
	laneA: {number},
	laneB: {number},
	zFront: number,
	zBack: number,
	roomX0: number,
	roomX1: number,
	doorX: number,
	doorWidth: number,
	floorTop: (number) -> number,
	front: (number) -> number,
	open: {[string]: boolean},
	rng: any,
	palette: any,
}

local function floorTopFn(FH: number): (number) -> number
	return function(k: number): number
		return 0.6 + k * FH
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Planning: dimensions, the stair lane, room region and door position
--------------------------------------------------------------------------------------------------------------------
function House.plan(entry: any, layout: any, model: Model): Plan
	local door = entry.door or "South"
	local yaw = (entry.yaw or 0) + DOOR_YAW[door]
	local W, D = entry.size[1], entry.size[2]
	if door == "East" or door == "West" then
		W, D = entry.size[2], entry.size[1]
	end
	local frame = Kit.frame(model, CFrame.new(entry.center[1], 0, entry.center[2]) * CFrame.Angles(0, math.rad(yaw), 0))
	local names = SIDES[door]
	local openWorld = entry.open or { [door] = true }
	local open = { front = openWorld[names.front] == true, back = openWorld[names.back] == true, left = openWorld[names.left] == true, right = openWorld[names.right] == true }
	open.front = true
	local rng = generator(entry.seed or 1)
	local palette = Kit.palettes[entry.style or "Residential"] or Kit.palettes.Residential
	local N = entry.stories or 2
	local FH = layout.floorHeight
	local use = entry.use or "Townhouse"
	local jetty = 0
	if N >= 2 and palette.jetty > 0 and not PUBLIC_DOORS[use] and use ~= "Apartments" and rng.chance(0.7) then
		jetty = palette.jetty
	end
	local mode = if SWITCHBACK[use] and W >= 18 then "switchback" else "straight"
	local laneWidth = if mode == "switchback" then (if use == "Mansion" then 5 else 4) else (if W >= 16 then 4 else 3.6)
	local coreWidth = if mode == "switchback" then laneWidth * 2 else laneWidth
	-- the lane goes against a shared wall when there is one, so the windows stay on the open side
	local side = 1
	if open.right and not open.left then
		side = -1
	elseif open.right == open.left and rng.chance(0.5) then
		side = -1
	end
	local laneX0, laneX1
	if side == 1 then
		laneX0, laneX1 = W / 2 - WALL - coreWidth, W / 2 - WALL
	else
		laneX0, laneX1 = -W / 2 + WALL, -W / 2 + WALL + coreWidth
	end
	-- lane A hugs the side wall, lane B is next to it (switchback only)
	local laneA, laneB
	if side == 1 then
		laneA = { laneX1 - laneWidth, laneX1 }
		laneB = { laneX0, laneX0 + laneWidth }
	else
		laneA = { laneX0, laneX0 + laneWidth }
		laneB = { laneX1 - laneWidth, laneX1 }
	end
	if mode == "straight" then
		laneA = { laneX0, laneX1 }
		laneB = laneA
	end
	local roomX0, roomX1
	if side == 1 then
		roomX0, roomX1 = -W / 2 + WALL, laneX0
	else
		roomX0, roomX1 = laneX1, W / 2 - WALL
	end
	local doorWidth = if PUBLIC_DOORS[use] then 6 else 5
	local doorX = (roomX0 + roomX1) / 2
	if use == "Apartments" then
		doorX = (laneX0 + laneX1) / 2
		doorWidth = math.min(5, coreWidth - 1)
	end
	local floorTop = floorTopFn(FH)
	local plan: Plan = {
		entry = entry,
		frame = frame,
		model = model,
		W = W,
		D = D,
		N = N,
		FH = FH,
		jetty = jetty,
		side = side,
		mode = mode,
		laneX0 = laneX0,
		laneX1 = laneX1,
		laneA = laneA,
		laneB = laneB,
		zFront = D / 2 - WALL - LANDING,
		zBack = -D / 2 + WALL + LANDING,
		roomX0 = roomX0,
		roomX1 = roomX1,
		doorX = doorX,
		doorWidth = doorWidth,
		floorTop = floorTop,
		front = function(k: number): number
			return if k == 0 then D / 2 else D / 2 + jetty
		end,
		open = open,
		rng = rng,
		palette = palette,
	}
	return plan
end

-- Which lane and direction flight k (from floor k-1 to floor k) uses.
local function flightOf(p: Plan, k: number): ({number}, number, number)
	if p.mode == "switchback" and k % 2 == 0 then
		return p.laneB, p.zBack, p.zFront -- climbs towards the front
	end
	return p.laneA, p.zFront, p.zBack -- climbs towards the back
end
House.flightOf = flightOf

-- The hole in slab k above flight k: the part of the run where headroom would be under 6 studs.
local function holeOf(p: Plan, k: number): Rect
	local lane, zLow, zHigh = flightOf(p, k)
	local run = zHigh - zLow
	local zCut = zLow + run * 0.42
	return { x0 = lane[1], x1 = lane[2], z0 = math.min(zCut, zHigh), z1 = math.max(zCut, zHigh) }
end
House.holeOf = holeOf

-- Space that must stay walkable, in the building's frame: { x0, x1, y0, y1, z0, z1, name }. The doorway and the
-- first steps inside it, the foot of every flight, and the landing each flight arrives at.
function House.clearances(p: Plan): {any}
	local boxes = {}
	local inset = if p.entry.use == "Apartments" then 2.6 else 4
	table.insert(boxes, { p.doorX - p.doorWidth / 2 + 0.6, p.doorX + p.doorWidth / 2 - 0.6, 1.2, 7, p.D / 2 - WALL - inset, p.D / 2 + 0.5, "door" })
	for k = 1, p.N - 1 do
		local lane, zLow, zHigh = flightOf(p, k)
		local y = p.floorTop(k - 1)
		local up = p.floorTop(k)
		local foot0, foot1 = if zLow > zHigh then zLow - 2 else zLow - 2.4, if zLow > zHigh then zLow + 2.4 else zLow + 2
		table.insert(boxes, { lane[1] + 0.3, lane[2] - 0.3, y + 1.2, y + 4, foot0, foot1, "stair" })
		local land0, land1 = if zHigh < zLow then zHigh - 2.4 else zHigh, if zHigh < zLow then zHigh else zHigh + 2.4
		table.insert(boxes, { lane[1] + 0.3, lane[2] - 0.3, up + 0.4, up + 5, land0, land1, "landing" })
	end
	return boxes
end

-- Bounds of a part in a frame (its eight corners taken into the frame).
local function boundsIn(frame: CFrame, part: BasePart): (Vector3, Vector3)
	local cf, half = part.CFrame, part.Size / 2
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				local q = frame:PointToObjectSpace(cf:PointToWorldSpace(Vector3.new(x * half.X, y * half.Y, z * half.Z)))
				lo = Vector3.new(math.min(lo.X, q.X), math.min(lo.Y, q.Y), math.min(lo.Z, q.Z))
				hi = Vector3.new(math.max(hi.X, q.X), math.max(hi.Y, q.Y), math.max(hi.Z, q.Z))
			end
		end
	end
	return lo, hi
end
House.boundsIn = boundsIn

--------------------------------------------------------------------------------------------------------------------
-- Shell: walls with doors and windows, timber framing, slabs, stairs, roof
--------------------------------------------------------------------------------------------------------------------
local function windowSpots(width: number, count: number, avoid: {{number}}?): {number}
	local spots = {}
	for index = 1, count do
		local x = -width / 2 + width * (index - 0.5) / count
		local blocked = false
		for _, range in ipairs(avoid or {}) do
			if x + 2 > range[1] and x - 2 < range[2] then
				blocked = true
			end
		end
		if not blocked then
			table.insert(spots, x)
		end
	end
	return spots
end

local function windowDetail(p: Plan, alongX: boolean, fixed: number, outward: number, at: number, sill: number, width: number, height: number, shutters: boolean, street: boolean?)
	local f = p.frame
	local function box(name: string, size: Vector3, a: number, y: number, depthOffset: number, color: Color3, material: Enum.Material, options: any)
		if alongX then
			f:box(name, size, a, y, fixed + outward * depthOffset, color, material, options)
		else
			f:box(name, Vector3.new(size.Z, size.Y, size.X), fixed + outward * depthOffset, y, a, color, material, options)
		end
	end
	if not street then
		return
	end
	if sill < 6 then
		box("Sill", Vector3.new(width + 0.8, 0.4, 0.8), at, sill - 0.2, 0.45, p.palette.trim, M.Slate, NO)
	end
	if shutters then
		local timber = p.palette.timber[1]
		for _, s in ipairs({ -1, 1 }) do
			box("Shutter", Vector3.new(width / 2, height, 0.2), at + s * (width * 0.75 + 0.1), sill + height / 2, 0.65, timber, M.WoodPlanks, NO)
		end
	end
end

local function buildShell(p: Plan)
	local f, W, D, N, FH = p.frame, p.W, p.D, p.N, p.FH
	local pal, rng, entry = p.palette, p.rng, p.entry
	local use = entry.use or "Townhouse"
	local baseColor = rng.pick(pal.base)
	local plaster = rng.pick(pal.plaster)
	local timber = rng.pick(pal.timber)
	local upperMaterial = pal.upperMaterial or M.Plaster
	local stoneGround = N == 1 and entry.style ~= "Slum"
	local timbered = upperMaterial == M.Plaster and entry.style ~= "Noble"
	local floorTop = p.floorTop
	local winW = if entry.style == "Noble" or entry.style == "Royal" then 3.4 elseif entry.style == "Slum" then 2.4 else 3
	local winH = if entry.style == "Noble" or entry.style == "Royal" then 6 elseif entry.style == "Slum" then 3.4 else 4.6
	local shutters = (entry.style == "Market" or entry.style == "Residential" or entry.style == "Slum" or entry.style == "Harbor") and rng.chance(0.45)
	local height = floorTop(N)

	-- ground slab and plinth
	local groundFloor = if use == "Shop" or use == "Tavern" or use == "Inn" or use == "Smithy" or use == "Forge" or use == "Warehouse" then M.Slate else M.WoodPlanks
	-- a building over a cellar keeps a stairwell open in its ground floor (entry.trapdoor, in this frame)
	local trap: Rect? = entry.trapdoor
	Kit.slab(f, "Plinth", { x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2 }, 0.6, 0.6, trap, baseColor, pal.baseMaterial)
	Kit.slab(f, "Floor", { x0 = -W / 2 + WALL, x1 = W / 2 - WALL, z0 = -D / 2 + WALL, z1 = D / 2 - WALL }, 0.66, 0.1, trap, if groundFloor == M.Slate then C.stoneFloor else C.floor, groundFloor)

	-- walls in two bands: the ground storey (stone) and the upper storeys together (plaster or the district's
	-- upper material). Windows stack in columns, so each facade of a band is one cut wall.
	local glassColor = if entry.style == "Slum" then rgb(120, 130, 120) else C.glass
	local function glassPane(alongX: boolean, fixed: number, inward: number, at: number, bottom: number, top: number)
		local size = if alongX then Vector3.new(winW, top - bottom, 0.2) else Vector3.new(0.2, top - bottom, winW)
		local x, z = if alongX then at else fixed - inward * WALL / 2, if alongX then fixed - inward * WALL / 2 else at
		f:box("Glass", size, x, (bottom + top) / 2, z, glassColor, M.Glass, { transparency = 0.55, shadow = false })
	end
	local function band(k0: number, k1: number)
		local ground = k0 == 0
		local y0 = floorTop(k0) - (if ground then 0.6 else 1)
		local y1 = if k1 == N - 1 then floorTop(N) else floorTop(k1 + 1) - 1
		local zf = p.front(k0)
		local color = if ground or stoneGround then baseColor else plaster
		local material = if ground or stoneGround then pal.baseMaterial else upperMaterial
		local count = math.max(1, math.floor((W - 2) / 8))
		local avoid = nil
		local front: {Kit.Opening} = {}
		if ground then
			avoid = { { p.doorX - p.doorWidth / 2 - 1, p.doorX + p.doorWidth / 2 + 1 } }
			table.insert(front, { from = p.doorX - p.doorWidth / 2, to = p.doorX + p.doorWidth / 2, bottom = y0, top = floorTop(0) + 8.4 })
			if use == "Smithy" or use == "Warehouse" or use == "Forge" then
				-- a wide second opening for carts and the forge's heat
				local other = if p.side == 1 then -W / 4 else W / 4
				if math.abs(other - p.doorX) > p.doorWidth + 6 then
					table.insert(front, { from = other - 4, to = other + 4, bottom = y0, top = floorTop(0) + 9 })
					table.insert(avoid, { other - 5, other + 5 })
				end
			end
		end
		local frontSpots = windowSpots(W, count, avoid)
		local backSpots: {number} = if p.open.back then windowSpots(W, 1, nil) else {}
		local runFrom, runTo = -D / 2 + WALL, zf - WALL
		local sideSpots = {}
		if D >= 14 then
			for _, z in ipairs(windowSpots(runTo - runFrom, math.max(1, math.floor((D - 4) / 12)), nil)) do
				table.insert(sideSpots, z + (runFrom + runTo) / 2)
			end
		end
		local back: {Kit.Opening}, left: {Kit.Opening}, right: {Kit.Opening} = {}, {}, {}
		local firstSill, lastTop = floorTop(k0) + 3.2, floorTop(k1) + 3.2 + winH
		for k = k0, k1 do
			local sill = floorTop(k) + 3.2
			for _, x in ipairs(frontSpots) do
				table.insert(front, { from = x - winW / 2, to = x + winW / 2, bottom = sill, top = sill + winH })
				windowDetail(p, true, zf, 1, x, sill, winW, winH, shutters, true)
			end
			for _, x in ipairs(backSpots) do
				table.insert(back, { from = x - winW / 2, to = x + winW / 2, bottom = sill, top = sill + winH })
			end
			for _, z in ipairs(sideSpots) do
				if p.open.left then
					table.insert(left, { from = z - winW / 2, to = z + winW / 2, bottom = sill, top = sill + winH })
				end
				if p.open.right then
					table.insert(right, { from = z - winW / 2, to = z + winW / 2, bottom = sill, top = sill + winH })
				end
			end
		end
		Kit.facade(f, "FrontWall", true, zf - WALL / 2, -W / 2, W / 2, y0, y1, WALL, front, color, material)
		Kit.facade(f, "BackWall", true, -D / 2 + WALL / 2, -W / 2, W / 2, y0, y1, WALL, back, color, material)
		Kit.facade(f, "SideWall", false, -(W / 2 - WALL / 2), runFrom, runTo, y0, y1, WALL, left, color, material)
		Kit.facade(f, "SideWall", false, W / 2 - WALL / 2, runFrom, runTo, y0, y1, WALL, right, color, material)
		-- one pane of glass per window column, set inside the wall
		for _, x in ipairs(frontSpots) do
			glassPane(true, zf, 1, x, firstSill, lastTop)
		end
		for _, x in ipairs(backSpots) do
			glassPane(true, -D / 2, -1, x, firstSill, lastTop)
		end
		for _, z in ipairs(sideSpots) do
			if p.open.left then
				glassPane(false, -W / 2, -1, z, firstSill, lastTop)
			end
			if p.open.right then
				glassPane(false, W / 2, 1, z, firstSill, lastTop)
			end
		end
		-- timber framing on plastered upper storeys: a beam at each floor, posts the full height of the band
		if timbered and not ground and not stoneGround then
			local postH = y1 - y0
			for k = k0, k1 do
				f:box("Beam", Vector3.new(W + 0.2, 0.7, 0.4), 0, floorTop(k) - 0.4, zf + 0.15, timber, M.Wood, NO)
				for _, s in ipairs({ -1, 1 }) do
					if (s == 1 and p.open.right) or (s == -1 and p.open.left) then
						f:box("Beam", Vector3.new(0.4, 0.7, D + p.jetty), s * (W / 2 + 0.15), floorTop(k) - 0.4, p.jetty / 2, timber, M.Wood, NO)
					end
				end
				if rng.chance(0.3) and #frontSpots >= 2 then
					local x = (frontSpots[1] + frontSpots[2]) / 2
					local brace = math.atan2(FH - 2, 3)
					f:boxAt("Brace", Vector3.new(0.5, (FH - 2) / math.sin(brace), 0.3), CFrame.new(x - 1.8, floorTop(k) + FH / 2 - 0.9, zf + 0.15) * CFrame.Angles(0, 0, -(math.pi / 2 - brace)), timber, M.Wood, NO)
				end
			end
			for _, x in ipairs({ -W / 2 + 0.35, W / 2 - 0.35 }) do
				f:box("Post", Vector3.new(0.7, postH, 0.4), x, (y0 + y1) / 2, zf + 0.15, timber, M.Wood, NO)
			end
			for index = 1, #frontSpots - 1 do
				local x = (frontSpots[index] + frontSpots[index + 1]) / 2
				f:box("Post", Vector3.new(0.6, postH, 0.4), x, (y0 + y1) / 2, zf + 0.15, timber, M.Wood, NO)
			end
		end
	end
	band(0, if stoneGround then N - 1 else 0)
	if N > 1 and not stoneGround then
		band(1, N - 1)
	end
	-- jetty: the slab and side walls of upper floors reach over the street; brackets carry them
	if N > 1 and p.jetty > 0 then
		for _, x in ipairs({ -W / 2 + 1, W / 2 - 1 }) do
			f:wedgeAt("Bracket", Vector3.new(0.6, 1.6, p.jetty + 0.4), CFrame.new(x, floorTop(1) - 1.8, D / 2 + (p.jetty + 0.4) / 2 - 0.2) * CFrame.Angles(0, math.pi, 0), timber, M.Wood, NO)
		end
	end

	-- upper floor slabs, with the stair holes
	for k = 1, N - 1 do
		local zf = p.front(k)
		Kit.slab(f, "Slab", { x0 = -W / 2 + WALL, x1 = W / 2 - WALL, z0 = -D / 2 + WALL, z1 = zf - WALL }, floorTop(k), 1, holeOf(p, k), C.floor, M.WoodPlanks)
		if p.jetty > 0 and k >= 1 then
			-- the overhang strip below the jettied front wall
			f:box("JettyFloor", Vector3.new(W, 1, p.jetty), 0, floorTop(k) - 0.5, D / 2 + p.jetty / 2, C.floor, M.WoodPlanks)
		end
	end
	-- stairs and a rail along each hole's room side
	for k = 1, N - 1 do
		local lane, zLow, zHigh = flightOf(p, k)
		Kit.flight(f, "Stairs", lane[1] + 0.05, lane[2] - 0.05, zLow, zHigh, floorTop(k - 1), floorTop(k), C.wood, C.darkWood)
		local hole = holeOf(p, k)
		-- rails on the hole's open long sides (never against the outside wall)
		for _, x in ipairs({ hole.x0, hole.x1 }) do
			if math.abs(math.abs(x) - (W / 2 - WALL)) > 0.2 then
				f:box("Rail", Vector3.new(0.3, 3.2, hole.z1 - hole.z0), x, floorTop(k) + 1.6, (hole.z0 + hole.z1) / 2, C.darkWood, M.Wood)
			end
		end
	end

	-- roof
	local roofBase = height
	local zFrontRoof = p.front(N - 1) + 1.1
	local zBackRoof = -D / 2 - 1.1
	local roofColor = rng.pick(pal.roof)
	local pitch = if entry.style == "Slum" then 0.45 elseif entry.style == "Noble" or entry.style == "Royal" then 0.75 else (0.6 + rng.unit() * 0.35)
	local gableFront = W <= 20 and D >= W and rng.chance(0.45) and entry.style ~= "Noble"
	local sideOverhang = if p.open.left and p.open.right then 0.6 else 0
	local roofW = W + 2 * sideOverhang
	local ridgeY
	if gableFront then
		local span = roofW
		local rise = span / 2 * pitch
		local length = zFrontRoof - zBackRoof
		local zm = (zFrontRoof + zBackRoof) / 2
		f:wedgeAt("Roof", Vector3.new(length, rise, span / 2), CFrame.new(-span / 4, roofBase + rise / 2, zm) * CFrame.Angles(0, math.pi / 2, 0), roofColor, pal.roofMaterial)
		f:wedgeAt("Roof", Vector3.new(length, rise, span / 2), CFrame.new(span / 4, roofBase + rise / 2, zm) * CFrame.Angles(0, -math.pi / 2, 0), roofColor, pal.roofMaterial)
		ridgeY = roofBase + rise
		f:box("Ridge", Vector3.new(0.8, 0.5, length), 0, ridgeY + 0.1, zm, roofColor:Lerp(Color3.new(0, 0, 0), 0.2), pal.roofMaterial, NO)
		-- gable faces on the street side (and the back when open)
		local gableFaces = { p.front(N - 1) + 0.12 }
		if p.open.back then
			table.insert(gableFaces, -D / 2 - 0.12)
		end
		for _, z in ipairs(gableFaces) do
			do
				local gable = if timbered then plaster else baseColor
				local gm = if timbered then M.Plaster else pal.baseMaterial
				f:wedgeAt("Gable", Vector3.new(0.3, rise - 0.1, W / 2), CFrame.new(-W / 4, roofBase + (rise - 0.1) / 2, z) * CFrame.Angles(0, math.pi / 2, 0), gable, gm, NO)
				f:wedgeAt("Gable", Vector3.new(0.3, rise - 0.1, W / 2), CFrame.new(W / 4, roofBase + (rise - 0.1) / 2, z) * CFrame.Angles(0, -math.pi / 2, 0), gable, gm, NO)
				if timbered then
					f:box("GableBeam", Vector3.new(0.5, rise * 0.8, 0.3), 0, roofBase + rise * 0.4, z + 0.05, timber, M.Wood, NO)
				end
			end
		end
	else
		local span = zFrontRoof - zBackRoof
		local rise = span / 2 * pitch
		local zm = (zFrontRoof + zBackRoof) / 2
		f:wedgeAt("Roof", Vector3.new(roofW, rise, zFrontRoof - zm), CFrame.new(0, roofBase + rise / 2, (zm + zFrontRoof) / 2) * CFrame.Angles(0, math.pi, 0), roofColor, pal.roofMaterial)
		f:wedgeAt("Roof", Vector3.new(roofW, rise, zm - zBackRoof), CFrame.new(0, roofBase + rise / 2, (zm + zBackRoof) / 2), roofColor, pal.roofMaterial)
		ridgeY = roofBase + rise
		f:box("Ridge", Vector3.new(roofW, 0.5, 0.8), 0, ridgeY + 0.1, zm, roofColor:Lerp(Color3.new(0, 0, 0), 0.2), pal.roofMaterial, NO)
		for _, s in ipairs({ -1, 1 }) do
			if (s == 1 and p.open.right) or (s == -1 and p.open.left) then
				local gable = if timbered then plaster else baseColor
				local gm = if timbered then M.Plaster else pal.baseMaterial
				local x = s * (W / 2 + 0.12)
				f:wedgeAt("Gable", Vector3.new(0.3, rise - 0.1, zFrontRoof - 1.1 - zm), CFrame.new(x, roofBase + (rise - 0.1) / 2, (zm + zFrontRoof - 1.1) / 2) * CFrame.Angles(0, math.pi, 0), gable, gm, NO)
				f:wedgeAt("Gable", Vector3.new(0.3, rise - 0.1, zm - zBackRoof - 1.1), CFrame.new(x, roofBase + (rise - 0.1) / 2, (zm + zBackRoof + 1.1) / 2), gable, gm, NO)
			end
		end
		-- a dormer on long street roofs
		if W >= 18 and rng.chance(0.35) and entry.style ~= "Slum" then
			local dz = (zm + zFrontRoof) / 2
			local dy = roofBase + rise * 0.45
			f:box("Dormer", Vector3.new(4, 4, 3), -W / 6, dy + 1, dz - 0.5, plaster, M.Plaster, NO)
			f:box("DormerWindow", Vector3.new(2, 2.2, 0.2), -W / 6, dy + 1, dz + 1.05, C.glass, M.Glass, { collide = false, query = false, transparency = 0.4 })
			f:wedgeAt("DormerRoof", Vector3.new(4.6, 1.6, 3.4), CFrame.new(-W / 6, dy + 3.8, dz - 0.3) * CFrame.Angles(0, math.pi, 0), roofColor, pal.roofMaterial, NO)
		end
	end
	-- chimney over the hearth wall (the side away from the stairs)
	if use ~= "Warehouse" and entry.style ~= "Slum" or rng.chance(0.4) then
		local cx = -p.side * (W / 2 - 1.6)
		f:box("Chimney", Vector3.new(2.4, ridgeY - roofBase + 3, 2.4), cx, roofBase + (ridgeY - roofBase + 3) / 2, -D / 4, baseColor, M.Brick, NO)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Rooms
--------------------------------------------------------------------------------------------------------------------
local function partition(p: Plan, k: number, z: number, x0: number, x1: number, doorAtX: number)
	local f = p.frame
	local y0, y1 = p.floorTop(k), p.floorTop(k + 1) - 1
	Kit.wall(f, "Partition", true, z, x0, x1, y0, y1, 0.6, { { from = doorAtX - 2, to = doorAtX + 2, bottom = y0, top = y0 + 8.4 } }, rgb(214, 204, 184), M.Plaster)
end

-- partition along the core (apartments, corridors): a wall at x from z0 to z1 with one doorway
local function coreWall(p: Plan, k: number, x: number, z0: number, z1: number, doorZ: number)
	local f = p.frame
	local y0, y1 = p.floorTop(k), p.floorTop(k + 1) - 1
	Kit.wall(f, "CoreWall", false, x, z0, z1, y0, y1, 0.6, { { from = doorZ - 2, to = doorZ + 2, bottom = y0, top = y0 + 8.4 } }, rgb(214, 204, 184), M.Plaster)
end

type Room = { x0: number, x1: number, z0: number, z1: number, y: number, kind: string, k: number, lit: boolean, door: number? }

local at = Furniture.at

-- Places furniture along a room's walls. "hearthWall" is the side away from the stairs.
local function furnish(p: Plan, room: Room)
	local f, rng = p.frame, p.rng
	local x0, x1, z0, z1, y = room.x0, room.x1, room.z0, room.z1, room.y
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local outer = if p.side == 1 then x0 else x1 -- the wall away from the stair lane
	local inwardFromOuter = if p.side == 1 then 90 else -90
	local outerX = outer + (if p.side == 1 then 1 else -1) * 1.2
	local kind = room.kind
	local shopKind = p.entry.shop or "GeneralGoods"
	local goods = Furniture.goods[shopKind] or Furniture.goods.GeneralGoods
	local clear = House.clearances(p)
	local function put(fn: (Frame) -> (), x: number, z: number, rot: number?)
		local g = at(f, x, y, z, rot)
		if g == nil then
			return
		end
		local before = #p.model:GetChildren()
		fn(g)
		-- a piece that would stand in a doorway or on the stairs is left out
		local piece = {}
		local children = p.model:GetChildren()
		for index = before + 1, #children do
			table.insert(piece, children[index])
		end
		for _, part in ipairs(piece) do
			if part:IsA("BasePart") and part.CanCollide then
				local lo, hi = boundsIn(f.cframe, part)
				for _, b in ipairs(clear) do
					if hi.X > b[1] and lo.X < b[2] and hi.Y > b[3] and lo.Y < b[4] and hi.Z > b[5] and lo.Z < b[6] then
						for _, other in ipairs(piece) do
							other:Destroy()
						end
						Kit.stats.parts -= #piece
						return
					end
				end
			end
		end
	end
	local blanket = rng.pick(C.cloth)
	if kind == "living" then
		put(function(g)
			Furniture.hearth(g, room.lit)
		end, outerX, cz, inwardFromOuter)
		put(function(g)
			Furniture.table(g, 5, 3.4)
		end, cx, cz)
		put(Furniture.chair, cx - 3.4, cz, 90)
		put(Furniture.chair, cx + 3.4, cz, -90)
		if room.k == 0 then
			put(function(g)
				Furniture.shelf(g, 5)
			end, cx, z0 + 1, 0)
		end
	elseif kind == "kitchen" then
		put(function(g)
			Furniture.counter(g, math.min(7, w - 4))
		end, cx, z0 + 1.4, 0)
		put(Furniture.barrel, x0 + 2 + (if p.side == 1 then 0 else w - 4), z0 + 2)
		put(function(g)
			Furniture.table(g, 4, 3)
		end, cx, cz + 1)
		put(Furniture.sacks, cx, z1 - 1.4, 180)
	elseif kind == "bedroom" then
		put(function(g)
			Furniture.bed(g, w >= 12, blanket)
		end, cx, z0 + 3.9, 0)
		put(Furniture.chest, cx, z0 + 8.5, 0)
		if rng.chance(0.5) then
			put(Furniture.wardrobe, outerX, z1 - 3, inwardFromOuter)
		end
	elseif kind == "storage" then
		put(function(g)
			Furniture.crates(g, 4)
		end, cx, z0 + 2, 0)
		put(Furniture.barrel, outerX, cz)
		put(Furniture.sacks, cx, z1 - 1.4, 180)
	elseif kind == "poor" then
		put(Furniture.strawBed, outerX + (if p.side == 1 then 1.2 else -1.2), z0 + 3.4, 0)
		put(function(g)
			Furniture.crate(g, 2.4)
		end, cx, cz)
		put(Furniture.stool, cx + 2.4, cz)
		put(function(g)
			Furniture.hearth(g, room.lit, rgb(96, 90, 84))
		end, cx, z0 + 0.6, 0)
	elseif kind == "studio" then
		put(function(g)
			Furniture.bed(g, false, blanket)
		end, outerX + (if p.side == 1 then 2 else -2), z0 + 3.9, 0)
		put(function(g)
			Furniture.hearth(g, room.lit)
		end, cx + (if p.side == 1 then 2 else -2), z1 - 0.6, 180)
		put(function(g)
			Furniture.table(g, 4, 3)
		end, cx, cz)
		put(Furniture.chair, cx - 3, cz, 90)
		put(Furniture.chest, outerX + (if p.side == 1 then 1.5 else -1.5), cz + 2, inwardFromOuter)
	elseif kind == "shop" then
		-- customers come in at the front; the counter runs across the back third
		put(function(g)
			Furniture.counter(g, math.max(4, w - 7))
		end, cx - (if p.side == 1 then 1.5 else -1.5), z0 + d * 0.38, 180)
		put(function(g)
			Furniture.shelf(g, math.min(8, w - 4), goods)
		end, cx, z0 + 1, 0)
		put(function(g)
			Furniture.shelf(g, 5, goods)
		end, outerX, cz + d * 0.2, inwardFromOuter)
		if shopKind == "Weapons" then
			put(Furniture.weaponRack, cx, z1 - 1, 180)
		elseif shopKind == "Armor" then
			put(Furniture.armorStand, cx - 2, cz + d * 0.25)
			put(Furniture.armorStand, cx + 2, cz + d * 0.25)
		elseif shopKind == "Potions" or shopKind == "MagicSupplies" then
			put(function(g)
				Furniture.bottles(g, 6)
			end, cx, z0 + 1, 0)
			put(Furniture.cauldron, outerX + (if p.side == 1 then 1.5 else -1.5), z0 + d * 0.25)
		elseif shopKind == "Tailor" or shopKind == "Weaver" then
			put(Furniture.loom, cx, cz + d * 0.22, 0)
		elseif shopKind == "Carpenter" or shopKind == "Workshop" or shopKind == "Tanner" or shopKind == "Cobbler" then
			put(Furniture.workbench, cx, cz + d * 0.2, 0)
		else
			put(function(g)
				Furniture.display(g, goods)
			end, cx, cz + d * 0.22)
		end
		put(Furniture.barrel, outerX, z1 - 2.5)
	elseif kind == "emptyShop" then
		put(function(g)
			Furniture.counter(g, math.max(4, w - 8))
		end, cx, z0 + d * 0.38, 180)
		put(function(g)
			Furniture.shelf(g, math.min(8, w - 4), { rgb(120, 100, 80) })
		end, cx, z0 + 1, 0)
	elseif kind == "forge" then
		put(Furniture.forge, cx, z0 + 3, 0)
		put(Furniture.anvil, cx, cz + 1)
		put(Furniture.barrel, outerX, cz)
		put(Furniture.weaponRack, outerX, z0 + 5, inwardFromOuter)
		put(function(g)
			Furniture.crates(g, 2)
		end, cx + 3, z1 - 2, 180)
	elseif kind == "tavern" then
		put(function(g)
			Furniture.counter(g, math.max(6, w - 8), C.darkWood)
		end, cx, z0 + 4, 180)
		put(function(g)
			Furniture.shelf(g, math.min(10, w - 4), { rgb(110, 70, 40), rgb(80, 120, 60) }, M.Glass)
		end, cx, z0 + 1, 0)
		put(Furniture.barrel, x0 + 2, z0 + 2.5)
		put(Furniture.barrel, x1 - 2, z0 + 2.5)
		put(function(g)
			Furniture.hearth(g, true)
		end, outerX, cz + 3, inwardFromOuter)
		local tables = math.max(1, math.floor((w - 6) / 8))
		for index = 1, tables do
			local tx = x0 + 3 + (w - 6) * (index - 0.5) / tables
			put(function(g)
				Furniture.table(g, 4, 3)
			end, tx, cz + 4)
			put(function(g)
				Furniture.bench(g, 4)
			end, tx, cz + 2)
			put(function(g)
				Furniture.bench(g, 4)
			end, tx, cz + 6)
		end
	elseif kind == "guestroom" then
		put(function(g)
			Furniture.bed(g, false, blanket)
		end, cx, z0 + 3.9, 0)
		put(Furniture.chest, cx, z1 - 1.5, 180)
	elseif kind == "office" then
		put(Furniture.desk, cx, z0 + 3, 180)
		put(Furniture.chair, cx, z0 + 1.2, 0)
		put(function(g)
			Furniture.bookshelf(g, math.min(6, w - 4))
		end, outerX, cz, inwardFromOuter)
		put(Furniture.chest, cx + 3, z1 - 1.4, 180)
	elseif kind == "hall" then
		put(function(g)
			Furniture.longTable(g, math.max(6, d - 8))
		end, cx, cz, 0)
		put(function(g)
			Furniture.hearth(g, true)
		end, outerX, cz, inwardFromOuter)
		put(function(g)
			Furniture.banner(g, C.cloth[2])
		end, cx, z0 + 0.6, 0)
	elseif kind == "bunks" then
		local count = math.max(1, math.floor((w - 2) / 5))
		for index = 1, count do
			put(Furniture.bunk, x0 + 1 + (w - 2) * (index - 0.5) / count, z0 + 4, 0)
		end
		put(Furniture.chest, cx, z1 - 1.4, 180)
	elseif kind == "dining" then
		put(function(g)
			Furniture.longTable(g, math.max(6, d - 7))
		end, cx, cz, 0)
		put(function(g)
			Furniture.painting(g, 5, 3.5, rgb(90, 110, 80))
		end, cx, z0 + 0.6, 0)
		put(function(g)
			Furniture.hearth(g, room.lit, rgb(180, 176, 168))
		end, outerX, cz, inwardFromOuter)
	elseif kind == "library" then
		put(function(g)
			Furniture.bookshelf(g, math.min(10, w - 4))
		end, cx, z0 + 1, 0)
		put(function(g)
			Furniture.bookshelf(g, 6)
		end, outerX, cz, inwardFromOuter)
		put(Furniture.desk, cx, cz + 2, 180)
		put(function(g)
			Furniture.rug(g, math.min(10, w - 4), math.min(8, d - 4), rgb(110, 30, 40))
		end, cx, cz)
	elseif kind == "nobleBedroom" then
		put(function(g)
			Furniture.fourPoster(g, blanket)
		end, cx, z0 + 4, 0)
		put(Furniture.wardrobe, outerX, z1 - 3, inwardFromOuter)
		put(Furniture.chest, cx, z0 + 9, 0)
		put(function(g)
			Furniture.rug(g, math.min(10, w - 4), 6, rgb(110, 30, 40))
		end, cx, cz + 2)
	elseif kind == "entrance" then
		put(function(g)
			Furniture.rug(g, 5, math.max(4, d - 4), rgb(120, 30, 36))
		end, p.doorX, cz)
		put(function(g)
			Furniture.painting(g, 4, 3, rgb(60, 70, 100))
		end, cx, z0 + 0.6, 0)
		put(function(g)
			Furniture.crest(g, 1)
		end, outerX + (if p.side == 1 then -0.4 else 0.4), cz, inwardFromOuter)
	elseif kind == "reception" then
		put(function(g)
			Furniture.counter(g, math.max(6, w - 10))
		end, cx, z0 + d * 0.35, 180)
		put(function(g)
			Furniture.shelf(g, math.min(8, w - 4))
		end, cx, z0 + 1, 0)
		put(function(g)
			Furniture.table(g, 4, 3)
		end, cx, z1 - 5)
		put(function(g)
			Furniture.bench(g, 4)
		end, cx, z1 - 3)
	elseif kind == "workshop" then
		put(Furniture.workbench, cx, z0 + 2, 0)
		put(Furniture.workbench, cx, cz + 2, 0)
		put(function(g)
			Furniture.crates(g, 3)
		end, outerX + (if p.side == 1 then 3 else -3), z1 - 2, 180)
	end
	if room.lit and kind ~= "living" and kind ~= "kitchen" and kind ~= "tavern" and kind ~= "forge" and kind ~= "hall" and kind ~= "studio" then
		put(function(g)
			Furniture.lamp(g, 9.4)
		end, cx, cz)
	end
end

-- Room plans by building use: { [floor] = { frontKind, backKind? } }
local function roomKinds(p: Plan, k: number): (string, string?)
	local use = p.entry.use or "Townhouse"
	local top = k == p.N - 1
	if use == "Townhouse" then
		if k == 0 then
			return "living", "kitchen"
		end
		return "bedroom", if top and p.N >= 3 then "storage" else "bedroom"
	elseif use == "Shack" then
		return "poor", nil
	elseif use == "Shop" then
		if k == 0 then
			return "shop", "storage"
		end
		return if k == 1 then "living" else "bedroom", if k == 1 then "kitchen" else "storage"
	elseif use == "Storefront" then
		if k == 0 then
			return "emptyShop", "storage"
		end
		return "living", "bedroom"
	elseif use == "Smithy" or use == "Forge" then
		if k == 0 then
			return "forge", nil
		end
		return "storage", "bedroom"
	elseif use == "Tavern" or use == "SlumTavern" or use == "Inn" then
		if k == 0 then
			return "tavern", "kitchen"
		end
		return "guestroom", "guestroom"
	elseif use == "Mansion" then
		if k == 0 then
			return "entrance", "dining"
		end
		return if k == 1 then "nobleBedroom" else "library", if k == 1 then "library" else "nobleBedroom"
	elseif use == "Warehouse" then
		return "storage", "storage"
	elseif use == "Customs" or use == "Office" or use == "Chancery" then
		if k == 0 then
			return "reception", "office"
		end
		return "office", "storage"
	elseif use == "Guild" then
		if k == 0 then
			return "reception", "hall"
		end
		return if k == 1 then "hall" else "office", "office"
	elseif use == "CraftGuild" then
		if k == 0 then
			return "workshop", "office"
		end
		return "hall", "storage"
	elseif use == "GuildHall" then
		if k == 0 then
			return "hall", nil
		end
		return "office", "storage"
	elseif use == "Apothecary" then
		if k == 0 then
			return "shop", "workshop"
		end
		return "storage", nil
	elseif use == "Barracks" then
		if k == 0 then
			return "bunks", "storage"
		end
		return "bunks", "office"
	elseif use == "Servants" then
		if k == 0 then
			return "kitchen", "storage"
		end
		return "bunks", nil
	end
	return "living", "storage"
end

local function buildRooms(p: Plan)
	local D = p.D
	local use = p.entry.use or "Townhouse"
	local lightCount = 0
	for k = 0, p.N - 1 do
		local y = p.floorTop(k)
		local z0, z1 = -D / 2 + WALL, p.front(k) - WALL
		local x0, x1 = p.roomX0, p.roomX1
		if use == "Apartments" then
			-- a wall between the stair core and the unit, with the unit's door on the landing people arrive at
			local wallX = if p.side == 1 then p.laneX0 - 0.3 else p.laneX1 + 0.3
			local arrivesBack = k % 2 == 1
			local doorZ = if arrivesBack then p.zBack - LANDING / 2 + 0.2 else p.zFront + LANDING / 2 - 0.2
			coreWall(p, k, wallX, z0, z1, doorZ)
			furnish(p, { x0 = x0 + (if p.side == 1 then 0 else 0.6), x1 = x1 - (if p.side == 1 then 0.6 else 0), z0 = z0, z1 = z1, y = y, kind = "studio", k = k, lit = true })
		elseif (use == "Inn" or use == "Tavern" or use == "Guild" or use == "Mansion") and k >= 1 and p.mode == "switchback" and (x1 - x0) >= 14 then
			-- upper floors: a corridor along the core, rooms off it
			local corridor = 4.4
			local cx0, cx1
			if p.side == 1 then
				cx0, cx1 = x1 - corridor, x1
			else
				cx0, cx1 = x0, x0 + corridor
			end
			local wallX = if p.side == 1 then cx0 - 0.3 else cx1 + 0.3
			local roomsX0 = if p.side == 1 then x0 else cx1 + 0.6
			local roomsX1 = if p.side == 1 then cx0 - 0.6 else x1
			local count = math.max(1, math.floor((z1 - z0) / 12))
			local kindA, kindB = roomKinds(p, k)
			for index = 1, count do
				local rz0 = z0 + (z1 - z0) * (index - 1) / count
				local rz1 = z0 + (z1 - z0) * index / count
				if index > 1 then
					p.frame:box("RoomWall", Vector3.new(roomsX1 - roomsX0, p.FH - 1, 0.6), (roomsX0 + roomsX1) / 2, y + (p.FH - 1) / 2, rz0, rgb(214, 204, 184), M.Plaster)
				end
				coreWall(p, k, wallX, rz0, rz1, (rz0 + rz1) / 2)
				furnish(p, { x0 = roomsX0, x1 = roomsX1, z0 = rz0 + 0.3, z1 = rz1 - 0.3, y = y, kind = if index % 2 == 1 then kindA else (kindB or kindA), k = k, lit = index == 1 })
			end
		else
			local kindFront, kindBack = roomKinds(p, k)
			local depth = z1 - z0
			local lit = lightCount < 2 and (use ~= "Townhouse" or k == 0)
			if kindBack ~= nil and depth >= 17 then
				local split = z0 + math.max(7.5, depth * 0.4)
				local doorAt = if p.side == 1 then x1 - 2.6 else x0 + 2.6
				partition(p, k, split, x0, x1, doorAt)
				furnish(p, { x0 = x0, x1 = x1, z0 = split + 0.3, z1 = z1, y = y, kind = kindFront, k = k, lit = lit })
				furnish(p, { x0 = x0, x1 = x1, z0 = z0, z1 = split - 0.3, y = y, kind = kindBack, k = k, lit = false })
			else
				furnish(p, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, y = y, kind = kindFront, k = k, lit = lit })
			end
			if lit then
				lightCount += 1
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Street front: door, sign, awning, lantern
--------------------------------------------------------------------------------------------------------------------
local function buildFront(p: Plan)
	local f, entry = p.frame, p.entry
	local use = entry.use or "Townhouse"
	local timber = p.palette.timber[1]
	local zf = p.D / 2
	local dw = p.doorWidth
	-- frame and an open door leaf turned inwards against the wall
	f:box("Lintel", Vector3.new(dw + 1.2, 0.7, 0.7), p.doorX, 0.6 + 8.75, zf + 0.1, timber, M.Wood, NO)
	local hingeX = p.doorX - dw / 2
	f:box("Door", Vector3.new(0.3, 8.2, dw - 0.4), hingeX + 0.35, 0.6 + 4.1, zf - WALL - (dw - 0.4) / 2, timber:Lerp(Color3.new(0, 0, 0), 0.15), M.WoodPlanks, NO)
	f:box("Step", Vector3.new(dw + 1, 0.3, 1.2), p.doorX, 0.15, zf + 0.6, p.palette.trim, M.Slate, NO)
	-- hanging sign for businesses
	if entry.name ~= nil and use ~= "Guild" then
		local sx = p.doorX + (if p.doorX < 0 then dw / 2 + 2.4 else -dw / 2 - 2.4)
		f:box("SignArm", Vector3.new(0.3, 0.3, 3.6), sx, 10.6, zf + 1.8, C.iron, M.Metal, NO)
		local board = f:box("Sign", Vector3.new(0.25, 2.2, 3.2), sx, 9.2, zf + 2.2, rgb(90, 64, 40), M.WoodPlanks, NO)
		Kit.sign(board, Enum.NormalId.Left, entry.name)
		Kit.sign(board, Enum.NormalId.Right, entry.name)
	end
	if use == "Shop" or use == "Storefront" or entry.shop ~= nil then
		local cloth = p.rng.pick(C.cloth)
		f:boxAt("Awning", Vector3.new(p.W - 1, 0.25, 3.2), CFrame.new(0, 10.4, zf + 1.4) * CFrame.Angles(math.rad(-18), 0, 0), cloth, M.Fabric, NO)
	end
	if use == "Inn" or use == "Tavern" or use == "SlumTavern" or use == "Guild" or use == "Customs" or (p.rng.chance(0.25) and use ~= "Shack") then
		local lamp = f:box("DoorLantern", Vector3.new(0.9, 1.2, 0.9), p.doorX + dw / 2 + 1.2, 8.4, zf + 0.9, rgb(255, 214, 150), M.Neon, NO)
		lamp.CastShadow = false
		Kit.light(lamp, rgb(255, 200, 140), 18, 0.9)
	end
	-- slum extras: a lean-to and laundry over the door
	if entry.style == "Slum" and p.rng.chance(0.5) then
		f:boxAt("LeanTo", Vector3.new(p.W * 0.6, 0.3, 3), CFrame.new(-p.W * 0.15, 7.6, zf + 1.4) * CFrame.Angles(math.rad(-14), 0, 0), rgb(110, 92, 70), M.WoodPlanks, NO)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Properties: for-sale signs, access volumes, apartment plaques
--------------------------------------------------------------------------------------------------------------------
local function propertyVolume(p: Plan, folder: Instance, propertyId: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, exit: Vector3)
	local f = p.frame
	local volume = f:box("PropertyVolume", Vector3.new(x1 - x0, y1 - y0, z1 - z0), (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, rgb(90, 140, 210), M.SmoothPlastic, { collide = false, query = false, transparency = 1, shadow = false })
	volume.Name = propertyId .. "Volume"
	volume:SetAttribute("PropertyId", propertyId)
	volume:SetAttribute("Exit", f:world(exit.X, exit.Y, exit.Z))
	volume:AddTag("PropertyVolume")
	volume.Parent = folder
end

local function propertySign(p: Plan, folder: Instance, propertyId: string, x: number, y: number, z: number, wallMounted: boolean)
	local f = p.frame
	local sign
	if wallMounted then
		sign = f:box(propertyId .. "Sign", Vector3.new(2.4, 1.6, 0.3), x, y, z, rgb(214, 196, 150), M.WoodPlanks, NO)
	else
		f:box("SignPost", Vector3.new(0.4, 4, 0.4), x, 2, z, C.darkWood, M.Wood, NO)
		sign = f:box(propertyId .. "Sign", Vector3.new(2.6, 1.8, 0.3), x, 3.9, z + 0.3, rgb(214, 196, 150), M.WoodPlanks, NO)
	end
	sign.Name = propertyId .. "Sign"
	sign:SetAttribute("PropertyId", propertyId)
	sign:AddTag("PropertySign")
	sign.Parent = folder
	Kit.sign(sign, Enum.NormalId.Front, "Deed: " .. propertyId, rgb(60, 40, 20))
end

local function buildProperties(p: Plan, properties: Instance)
	local entry = p.entry
	local W, D = p.W, p.D
	local interior = { x0 = -W / 2 + WALL, x1 = W / 2 - WALL, z0 = -D / 2 + WALL }
	if entry.propertyId ~= nil then
		local signX = p.doorX + (if p.doorX <= 0 then p.doorWidth / 2 + 2.4 else -p.doorWidth / 2 - 2.4)
		propertySign(p, properties, entry.propertyId, signX, 0, D / 2 + 2.2, false)
		propertyVolume(p, properties, entry.propertyId, interior.x0, interior.x1, 0.6, p.floorTop(p.N), interior.z0, p.front(p.N - 1) - WALL, Vector3.new(p.doorX, 3.5, D / 2 + 4))
	end
	if entry.units ~= nil then
		for _, unit in ipairs(entry.units) do
			local k = unit.floor
			local y = p.floorTop(k)
			local arrivesBack = k % 2 == 1
			local landingZ = if arrivesBack then p.zBack - LANDING / 2 + 0.2 else p.zFront + LANDING / 2 - 0.2
			local laneMid = (p.laneX0 + p.laneX1) / 2
			local wallX = if p.side == 1 then p.laneX0 - 0.3 else p.laneX1 + 0.3
			-- the plaque hangs on the core wall beside the unit door
			propertySign(p, properties, unit.propertyId, wallX + (if p.side == 1 then 0.5 else -0.5), y + 5.5, landingZ + (if arrivesBack then 3.2 else -3.2), true)
			local ux0 = if p.side == 1 then interior.x0 else wallX + 0.3
			local ux1 = if p.side == 1 then wallX - 0.3 else interior.x1
			propertyVolume(p, properties, unit.propertyId, ux0, ux1, y, y + p.FH - 1, interior.z0, p.front(k) - WALL, Vector3.new(laneMid, y + 3, landingZ))
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
function House.build(entry: any, layout: any, parent: Instance, properties: Instance): Model
	local model = Kit.model(parent, entry.id)
	if entry.locationId then
		model:SetAttribute("LocationId", entry.locationId)
	end
	if entry.propertyId then
		model:SetAttribute("PropertyId", entry.propertyId)
	end
	model:SetAttribute("Access", entry.access or "Npc")
	model:SetAttribute("Use", entry.use or "Townhouse")
	local p = House.plan(entry, layout, model)
	-- real lights per building: public houses get a few, homes at most one (the rest only glow)
	local use = entry.use or "Townhouse"
	if PUBLIC_DOORS[use] or use == "Mansion" or use == "SlumTavern" then
		Kit.lightBudget = 3
	elseif use == "Shop" or use == "Storefront" then
		Kit.lightBudget = 1
	else
		Kit.lightBudget = if p.rng.chance(0.3) then 1 else 0
	end
	buildShell(p)
	buildRooms(p)
	buildFront(p)
	buildProperties(p, properties)
	Kit.lightBudget = math.huge
	return model
end

House.furnish = furnish
House.WALL = WALL
House.LANDING = LANDING

return House
