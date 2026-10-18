--!strict
-- The thieves' hideout under the slums (quest: The Stolen Belongings). Its only way in is the trapdoor in the back
-- room of the Crooked Lantern: stairs down to the tavern cellar, a wine rack swung aside, a landing, and a long
-- stair down to the hideout's rooms (entrance, stolen-goods store, meeting hall, bunks, guarded inner room, and the
-- leader's room). Rooms keep the spawner zone IDs HideoutEntrance, HideoutHall, HideoutInner and HideoutThrone.
local Kit = require(script.Parent.Kit)
local Furniture = require(script.Parent.Furniture)

local Hideout = {}
local M = Kit.materials
local C = Kit.colors
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }
local ROOM_HEIGHT = 12
local TUNNEL_WIDTH = 8
local TUNNEL_HEIGHT = 9.5

local function rectOf(room: any): (number, number, number, number)
	return room.center[1] - room.size[1] / 2, room.center[1] + room.size[1] / 2, room.center[2] - room.size[2] / 2, room.center[2] + room.size[2] / 2
end

local function torch(f: Frame, x: number, y: number, z: number)
	f:box("TorchBracket", Vector3.new(0.4, 1.6, 0.4), x, y, z, C.iron, M.Metal, NO)
	local flame = f:box("Torch", Vector3.new(0.7, 0.9, 0.7), x, y + 1.1, z, rgb(255, 150, 60), M.Neon, NO)
	flame.CastShadow = false
	Kit.light(flame, rgb(255, 150, 70), 22, 1.2)
end

local function place(f: Frame, x: number, y: number, z: number, rot: number, fn: (Frame) -> ())
	local g = Furniture.at(f, x, y, z, rot)
	if g ~= nil then
		fn(g)
	end
end

function Hideout.build(layout: any, root: Instance, tavern: any): Folder
	local spec = layout.hideout
	local folder = Kit.folder(root, "Hideout")
	local f = Kit.frame(folder, CFrame.new())
	local wallColor, floorColor = rgb(96, 88, 80), rgb(84, 78, 72)
	local rooms: {[string]: any} = {}
	for _, room in ipairs(spec.rooms) do
		rooms[room.id] = room
	end

	-- openings each room needs in its walls, from the tunnels between rooms
	local openings: {[string]: {[string]: {Kit.Opening}}} = {}
	local function addOpening(roomId: string, side: string, at: number, bottom: number, top: number, width: number?)
		openings[roomId] = openings[roomId] or {}
		openings[roomId][side] = openings[roomId][side] or {}
		local w = width or TUNNEL_WIDTH
		table.insert(openings[roomId][side], { from = at - w / 2, to = at + w / 2, bottom = bottom, top = top })
	end
	local tunnels = {}
	for _, link in ipairs(spec.tunnels) do
		local a, b = rooms[link.from], rooms[link.to]
		local ax0, ax1, az0, az1 = rectOf(a)
		local bx0, bx1, bz0, bz1 = rectOf(b)
		local y = spec.floorY
		if ax1 <= bx0 or bx1 <= ax0 then
			-- side by side along x: the tunnel runs along x through the overlap in z
			local zMid = (math.max(az0, bz0) + math.min(az1, bz1)) / 2
			local left, right = if ax1 <= bx0 then a else b, if ax1 <= bx0 then b else a
			local lx1 = select(2, rectOf(left))
			local rx0 = rectOf(right)
			addOpening(left.id, "East", zMid, y, y + TUNNEL_HEIGHT)
			addOpening(right.id, "West", zMid, y, y + TUNNEL_HEIGHT)
			table.insert(tunnels, { x0 = lx1, x1 = rx0, z0 = zMid - TUNNEL_WIDTH / 2, z1 = zMid + TUNNEL_WIDTH / 2, alongX = true })
		else
			local xMid = (math.max(ax0, bx0) + math.min(ax1, bx1)) / 2
			local top, bottom = if az1 <= bz0 then a else b, if az1 <= bz0 then b else a
			local _, _, _, tz1 = rectOf(top)
			local _, _, bz0b = rectOf(bottom)
			addOpening(top.id, "South", xMid, y, y + TUNNEL_HEIGHT)
			addOpening(bottom.id, "North", xMid, y, y + TUNNEL_HEIGHT)
			table.insert(tunnels, { x0 = xMid - TUNNEL_WIDTH / 2, x1 = xMid + TUNNEL_WIDTH / 2, z0 = tz1, z1 = bz0b, alongX = false })
		end
	end

	-- the way down: tavern trapdoor -> cellar -> landing -> entrance room
	local cellar = rooms.HideoutCellar
	local entrance = rooms.HideoutEntrance
	local tcx, tcz = tavern.center[1], tavern.center[2]
	local trap = tavern.trapdoor
	local stairX0, stairX1 = tcx + trap.x0, tcx + trap.x1
	local trapZ0, trapZ1 = tcz + trap.z0, tcz + trap.z1
	local cellarY = cellar.floorY
	local _, _, cz0, cz1 = rectOf(cellar)
	Kit.flight(f, "CellarStairs", stairX0 + 0.1, stairX1 - 0.1, cz0 + 2.2, trapZ1, cellarY, 0.6, rgb(110, 90, 66), rgb(80, 64, 48))
	-- rails round the trapdoor up in the tavern and an open hatch leaf
	f:box("TrapRail", Vector3.new(0.3, 3, trapZ1 - trapZ0), if trap.x0 > 0 then stairX0 else stairX1, 2.1, (trapZ0 + trapZ1) / 2, C.darkWood, M.Wood)
	f:box("Hatch", Vector3.new(stairX1 - stairX0, 0.3, 4), (stairX0 + stairX1) / 2, 2.6, trapZ0 - 0.1, rgb(90, 64, 40), M.WoodPlanks, NO)
	-- cellar: from cellarY up to the street's paving (which is its ceiling)
	addOpening(cellar.id, "South", entrance.center[1] + 4, cellarY, cellarY + 8, 5)
	local landingX = entrance.center[1] + 4
	local _, _, ez0 = rectOf(entrance)
	local entranceTop = cellarY + 10 -- the entrance room is tall: its ceiling is level with the cellar's
	addOpening(entrance.id, "North", landingX, cellarY, cellarY + 8, 5)
	-- landing in the entrance room at cellar level, then the long stair down along it
	local landingZ1 = ez0 + 4
	f:box("Landing", Vector3.new(8, 1, landingZ1 - cz1), landingX, cellarY - 0.5, (cz1 + landingZ1) / 2, rgb(110, 90, 66), M.WoodPlanks)
	local flightZLow = ez0 + 4 + math.abs(cellarY - spec.floorY) * 1.1
	Kit.flight(f, "HideoutStairs", landingX - 3, landingX + 3, flightZLow, landingZ1, spec.floorY, cellarY, rgb(110, 90, 66), rgb(80, 64, 48))
	f:box("StairRail", Vector3.new(0.3, 3, flightZLow - landingZ1), landingX - 3, cellarY + 1.5 - 8, (flightZLow + landingZ1) / 2, C.darkWood, M.Wood, NO)
	-- the passage between cellar and entrance room (it crosses the gap between them)
	f:box("PassageFloor", Vector3.new(6, 1, cz1 - cz1 + (ez0 - cz1) + 0.01), landingX, cellarY - 0.5, (cz1 + ez0) / 2, floorColor, M.Slate)
	for _, s in ipairs({ -1, 1 }) do
		f:box("PassageWall", Vector3.new(1, 8, ez0 - cz1 + 0.01), landingX + s * 3, cellarY + 4, (cz1 + ez0) / 2, wallColor, M.Cobblestone)
	end
	f:box("PassageCeiling", Vector3.new(7, 1, ez0 - cz1 + 0.01), landingX, cellarY + 8.5, (cz1 + ez0) / 2, wallColor, M.Cobblestone)
	-- the wine rack that hides the way, swung aside
	f:boxAt("SwungRack", Vector3.new(5, 7, 1.2), CFrame.new(landingX - 4.5, cellarY + 3.5, cz1 - 2.2) * CFrame.Angles(0, math.rad(70), 0), C.darkWood, M.Wood, NO)

	-- rooms
	for _, room in ipairs(spec.rooms) do
		local x0, x1, z0, z1 = rectOf(room)
		local y = room.floorY or spec.floorY
		local height = room.height or ROOM_HEIGHT
		if room.id == entrance.id then
			height = entranceTop - spec.floorY
		end
		local top = y + height
		local list: any = openings[room.id] or {}
		local mat = if room.kind == "Cellar" then M.Brick else M.Cobblestone
		Kit.slab(f, "RoomFloor", { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, y, 1, nil, floorColor, M.Slate)
		if room.kind ~= "Cellar" then
			Kit.slab(f, "RoomCeiling", { x0 = x0, x1 = x1, z0 = z0, z1 = z1 }, top + 1, 1, nil, wallColor, M.Cobblestone)
		end
		local wallTop = if room.kind == "Cellar" then -2 else top
		Kit.wall(f, "RoomWall", true, z0 - 0.5, x0 - 1, x1 + 1, y, wallTop, 1, list.North or {}, wallColor, mat)
		Kit.wall(f, "RoomWall", true, z1 + 0.5, x0 - 1, x1 + 1, y, wallTop, 1, list.South or {}, wallColor, mat)
		Kit.wall(f, "RoomWall", false, x0 - 0.5, z0, z1, y, wallTop, 1, list.West or {}, wallColor, mat)
		Kit.wall(f, "RoomWall", false, x1 + 0.5, z0, z1, y, wallTop, 1, list.East or {}, wallColor, mat)
		torch(f, x0 + 0.6, y + 6, (z0 + z1) / 2)
		if room.size[1] > 26 then
			torch(f, x1 - 0.6, y + 6, (z0 + z1) / 2)
		end
		local cx, cz = room.center[1], room.center[2]
		local w, d = room.size[1], room.size[2]
		if room.kind == "Cellar" then
			for k = 0, 2 do
				place(f, x0 + 1, y, z0 + 3 + k * 4, 90, function(g)
					Furniture.shelf(g, 3.6, { rgb(80, 30, 40), rgb(60, 80, 40) }, M.Glass)
				end)
			end
			place(f, cx - 4, y, z1 - 3, 0, Furniture.barrel)
			place(f, cx - 7, y, z1 - 3, 0, Furniture.barrel)
		elseif room.kind == "Entrance" then
			place(f, x0 + 4, y, z1 - 4, 0, function(g)
				Furniture.crates(g, 3)
			end)
			place(f, x1 - 3, y, z1 - 6, -90, Furniture.chair)
			place(f, x1 - 4, y, z1 - 10, 0, Furniture.barrel)
		elseif room.kind == "Store" then
			-- the stolen goods: chests, sacks, a rack of blades, rolled rugs, a painting leaning on the wall
			for k = 0, 3 do
				place(f, x0 + 4 + k * 6, y, z0 + 2, 0, function(g)
					Furniture.chest(g, if k % 2 == 0 then rgb(110, 70, 40) else rgb(70, 50, 40))
				end)
			end
			place(f, cx, y, cz, 0, function(g)
				Furniture.crates(g, 6)
			end)
			place(f, x1 - 4, y, z1 - 2, 180, Furniture.sacks)
			place(f, x0 + 1.2, y, cz + 6, 90, Furniture.weaponRack)
			place(f, x0 + 1.2, y, cz - 6, 90, function(g)
				Furniture.painting(g, 4, 3, rgb(90, 110, 140))
			end)
			place(f, cx + 6, y, z1 - 3, 0, function(g)
				g:box("RolledRug", Vector3.new(6, 1.4, 1.4), 0, 0.7, 0, rgb(130, 40, 40), M.Fabric).Shape = Enum.PartType.Cylinder
			end)
		elseif room.kind == "Hall" then
			-- the meeting area: a long table, a board of jobs, a hearth
			place(f, cx, y, cz, 90, function(g)
				Furniture.longTable(g, 16)
			end)
			place(f, cx, y, z0 + 0.8, 0, function(g)
				Furniture.board(g, "Jobs", 8)
			end)
			place(f, x1 - 2, y, z0 + 3, 0, Furniture.barrel)
			place(f, x0 + 4, y, z1 - 3, 0, function(g)
				Furniture.crates(g, 2)
			end)
		elseif room.kind == "Bunks" then
			local count = math.max(1, math.floor((w - 4) / 6))
			for k = 0, count - 1 do
				local bx = x0 + 3 + k * (w - 6) / math.max(1, count - 1)
				if math.abs(bx - cx) > 5 then
					place(f, bx, y, z1 - 4, 180, Furniture.bunk)
				end
			end
			place(f, x0 + 3, y, z0 + 4, 0, Furniture.strawBed)
			place(f, x1 - 3, y, z0 + 4, 0, Furniture.strawBed)
		elseif room.kind == "Inner" then
			-- guarded: the takings, weapons, a table with coins
			place(f, x1 - 1.2, y, cz, -90, Furniture.weaponRack)
			place(f, cx, y, z0 + 3, 0, function(g)
				Furniture.table(g, 5, 3)
				for k = -1, 1 do
					g:box("Coins", Vector3.new(0.8, 0.3, 0.8), k * 1.2, 3.15, 0, C.lundandGold, M.Metal, NO)
				end
			end)
			place(f, x0 + 3, y, z0 + 2, 0, function(g)
				Furniture.chest(g, rgb(90, 60, 40))
			end)
			place(f, x0 + 7, y, z0 + 2, 0, function(g)
				Furniture.chest(g, rgb(90, 60, 40))
			end)
		elseif room.kind == "Throne" then
			-- the leader's room: a rough throne on a dais, a red banner, chests of trophies
			place(f, cx, y, z1 - 4, 180, function(g)
				g:box("Dais", Vector3.new(10, 1, 7), 0, 0.5, 0, rgb(80, 70, 64), M.Cobblestone)
				g:box("Seat", Vector3.new(4, 2.4, 3), 0, 2.2, 0.4, rgb(90, 60, 40), M.Wood)
				g:box("SeatBack", Vector3.new(4, 6, 0.8), 0, 4.4, 1.8, rgb(90, 60, 40), M.Wood, NO)
			end)
			place(f, cx, y, z1 - 0.6, 180, function(g)
				Furniture.banner(g, rgb(110, 20, 24), 7)
			end)
			place(f, x0 + 3, y, z1 - 3, 0, Furniture.chest)
			place(f, x1 - 3, y, z1 - 3, 0, Furniture.chest)
			place(f, cx, y, cz, 0, function(g)
				Furniture.rug(g, 10, 8, rgb(120, 30, 30))
			end)
		end
		if room.locationId ~= nil then
			local marker = f:box(room.locationId, Vector3.new(w - 4, 10, d - 4), cx, y + 5, cz, rgb(255, 60, 200), M.SmoothPlastic, { collide = false, query = false, transparency = 1, shadow = false })
			marker:SetAttribute("LocationId", room.locationId)
		end
	end
	for _, t in ipairs(tunnels) do
		local y = spec.floorY
		local length = if t.alongX then t.x1 - t.x0 else t.z1 - t.z0
		if length > 0.05 then
			Kit.slab(f, "TunnelFloor", { x0 = t.x0, x1 = t.x1, z0 = t.z0, z1 = t.z1 }, y, 1, nil, floorColor, M.Slate)
			Kit.slab(f, "TunnelCeiling", { x0 = t.x0, x1 = t.x1, z0 = t.z0, z1 = t.z1 }, y + TUNNEL_HEIGHT + 1, 1, nil, wallColor, M.Cobblestone)
			if t.alongX then
				f:box("TunnelWall", Vector3.new(length, TUNNEL_HEIGHT, 1), (t.x0 + t.x1) / 2, y + TUNNEL_HEIGHT / 2, t.z0 - 0.5, wallColor, M.Cobblestone)
				f:box("TunnelWall", Vector3.new(length, TUNNEL_HEIGHT, 1), (t.x0 + t.x1) / 2, y + TUNNEL_HEIGHT / 2, t.z1 + 0.5, wallColor, M.Cobblestone)
			else
				f:box("TunnelWall", Vector3.new(1, TUNNEL_HEIGHT, length), t.x0 - 0.5, y + TUNNEL_HEIGHT / 2, (t.z0 + t.z1) / 2, wallColor, M.Cobblestone)
				f:box("TunnelWall", Vector3.new(1, TUNNEL_HEIGHT, length), t.x1 + 0.5, y + TUNNEL_HEIGHT / 2, (t.z0 + t.z1) / 2, wallColor, M.Cobblestone)
			end
		end
	end
	return folder
end

return Hideout
