--!strict
-- Buildings seen from the street. Two kinds:
--   * houses (and other private or closed buildings): a solid shell with windows, a roof and a door. The door
--     takes you to the house's own interior (InteriorService builds it while someone is inside). Ordinary houses
--     are clones of a few house models per district (ServerStorage.CityAssets.Houses), painted per house.
--   * public buildings (inn, guild, forge...): the same outside, but the ground storey is a real room you walk
--     into; the storeys above are closed.
-- Everything is built in the building's frame: x across the facade, z towards the street (the door is in the
-- front wall at +z), y up. No two visible faces share a plane, so nothing flickers.
local Kit = require(script.Parent.Kit)

local Shell = {}
local C = Kit.colors
local M = Kit.materials
local rgb = Kit.rgb
type Frame = Kit.Frame

local NO = { collide = false, query = false }
local WALL = 1
local DOOR_HEIGHT = 8.4
local DOOR_YAW = { South = 0, North = 180, East = 90, West = -90 }
local TIMBERED = { Market = true, Residential = true, Craft = true }

-- Where a building's door is across its facade (x in its frame): a third of the way along, or the middle if narrow.
function Shell.doorX(W: number): number
	return if W >= 18 then -W / 6 else 0
end

-- A building's frame and its facade width (W) and depth (D) as seen from its door.
function Shell.frameOf(entry: any): (CFrame, number, number)
	local door = entry.door or "South"
	local W, D = entry.size[1], entry.size[2]
	if door == "East" or door == "West" then
		W, D = entry.size[2], entry.size[1]
	end
	local yaw = (entry.yaw or 0) + DOOR_YAW[door]
	return CFrame.new(entry.center[1], 0, entry.center[2]) * CFrame.Angles(0, math.rad(yaw), 0), W, D
end

local function paint(part: BasePart, role: string)
	part:SetAttribute("Paint", role)
end

local function windowColumns(width: number, spacing: number): {number}
	local count = math.max(1, math.floor((width - 4) / spacing))
	local spots = {}
	for index = 1, count do
		table.insert(spots, -width / 2 + width * (index - 0.5) / count)
	end
	return spots
end

export type Spec = { W: number, D: number, stories: number, roof: string, style: string, hollow: boolean?, doorWidth: number?, trapdoor: any?, floorHeight: number }

-- Builds a building's outside into `model` at `cf`. Returns the door part (solid shells) or nil (open doorways).
function Shell.build(model: Model, cf: CFrame, spec: Spec): BasePart?
	local f = Kit.frame(model, cf)
	local W, D, N, FH = spec.W, spec.D, spec.stories, spec.floorHeight
	local palette = Kit.palettes[spec.style] or Kit.palettes.Residential
	local hollow = spec.hollow == true
	local doorWidth = spec.doorWidth or (if hollow then 6 else 5)
	local doorX = Shell.doorX(W)
	local winW = if spec.style == "Noble" or spec.style == "Royal" then 3.4 elseif spec.style == "Slum" then 2.4 else 3
	local winH = if spec.style == "Noble" or spec.style == "Royal" then 6 elseif spec.style == "Slum" then 3.4 else 4.6
	local groundTop = 0.6 + FH
	local top = 0.6 + N * FH
	local function floorTop(k: number): number
		return 0.6 + k * FH
	end
	local front = windowColumns(W, 8)
	local back = windowColumns(W, 10)
	local function clearOfDoor(x: number): boolean
		return math.abs(x - doorX) > doorWidth / 2 + winW / 2 + 1
	end

	-- plinth (with the cellar stairwell left open when there is one)
	local plinthParts = {}
	if spec.trapdoor ~= nil then
		local before = #model:GetChildren()
		Kit.slab(f, "Plinth", { x0 = -W / 2, x1 = W / 2, z0 = -D / 2, z1 = D / 2 }, 0.6, 0.6, spec.trapdoor, palette.base[1], palette.baseMaterial)
		local children = model:GetChildren()
		for index = before + 1, #children do
			table.insert(plinthParts, children[index])
		end
	else
		table.insert(plinthParts, f:box("Plinth", Vector3.new(W, 0.6, D), 0, 0.3, 0, palette.base[1], palette.baseMaterial))
	end
	for _, part in ipairs(plinthParts) do
		paint(part :: BasePart, "Base")
	end

	-- ground storey: a solid block, or four walls round a room (public buildings)
	if hollow then
		local glass = {}
		local function windowOpenings(spots: {number}, skipDoor: boolean): {Kit.Opening}
			local list = {}
			for _, x in ipairs(spots) do
				if not skipDoor or clearOfDoor(x) then
					table.insert(list, { from = x - winW / 2, to = x + winW / 2, bottom = 0.6 + 3.2, top = 0.6 + 3.2 + winH })
					table.insert(glass, x)
				end
			end
			return list
		end
		local frontOpenings = windowOpenings(front, true)
		local frontGlass = #glass
		table.insert(frontOpenings, { from = doorX - doorWidth / 2, to = doorX + doorWidth / 2, bottom = 0, top = 0.6 + DOOR_HEIGHT })
		local backOpenings = windowOpenings(back, false)
		local before = #model:GetChildren()
		Kit.facade(f, "FrontWall", true, D / 2 - WALL / 2, -W / 2, W / 2, 0.6, groundTop, WALL, frontOpenings, palette.base[1], palette.baseMaterial)
		Kit.facade(f, "BackWall", true, -D / 2 + WALL / 2, -W / 2, W / 2, 0.6, groundTop, WALL, backOpenings, palette.base[1], palette.baseMaterial)
		Kit.facade(f, "SideWall", false, -W / 2 + WALL / 2, -D / 2 + WALL, D / 2 - WALL, 0.6, groundTop, WALL, {}, palette.base[1], palette.baseMaterial)
		Kit.facade(f, "SideWall", false, W / 2 - WALL / 2, -D / 2 + WALL, D / 2 - WALL, 0.6, groundTop, WALL, {}, palette.base[1], palette.baseMaterial)
		local children = model:GetChildren()
		for index = before + 1, #children do
			paint(children[index] :: BasePart, "Base")
		end
		-- panes a little smaller than their openings, set in the middle of the wall
		for index, x in ipairs(glass) do
			local z = if index <= frontGlass then D / 2 - WALL / 2 else -D / 2 + WALL / 2
			local pane = f:box("Glass", Vector3.new(winW - 0.2, winH - 0.2, 0.2), x, 0.6 + 3.2 + winH / 2, z, C.glass, M.Glass, { transparency = 0.5, shadow = false })
			paint(pane, "Glass")
		end
		-- a lamp under the ceiling
		local lamp = f:box("CeilingLamp", Vector3.new(1.2, 0.6, 1.2), 0, groundTop - 1.4, 0, rgb(255, 220, 160), M.Neon, NO)
		lamp.CastShadow = false
		Kit.light(lamp, rgb(255, 214, 160), math.max(W, D), 1)
	else
		paint(f:box("GroundStorey", Vector3.new(W, FH, D), 0, 0.6 + FH / 2, 0, palette.base[1], palette.baseMaterial), "Base")
	end
	if N > 1 then
		local upperMaterial = palette.upperMaterial or M.Plaster
		paint(f:box("UpperStoreys", Vector3.new(W, top - groundTop, D), 0, (groundTop + top) / 2, 0, palette.plaster[1], upperMaterial), "Upper")
	end

	-- windows on the closed storeys: dark panes standing a little proud of the wall
	-- (a pane sits on the wall's face and stands out from it; it never reaches into the wall)
	local function pane(x: number, k: number, z: number)
		local out = if z > 0 then 0.15 else -0.15
		paint(f:box("Window", Vector3.new(winW, winH, 0.3), x, floorTop(k) + 3.2 + winH / 2, z + out, rgb(52, 62, 74), M.Glass), "Window")
	end
	for k = (if hollow then 1 else 0), N - 1 do
		for _, x in ipairs(front) do
			if k > 0 or clearOfDoor(x) then
				pane(x, k, D / 2)
			end
		end
		for _, x in ipairs(back) do
			pane(x, k, -D / 2)
		end
	end

	-- timber framing on plastered upper storeys: a beam at every floor line, posts at the corners
	if N > 1 and TIMBERED[spec.style] then
		for k = 1, N - 1 do
			-- exactly the facade's width: a neighbour's beam at the same height must not overlap it
			paint(f:box("Beam", Vector3.new(W - 0.1, 0.6, 0.7), 0, floorTop(k), D / 2, rgb(70, 50, 34), M.Wood, NO), "Timber")
		end
		for _, s in ipairs({ -1, 1 }) do
			-- set in from the corner, so the post's side never lies in the building's side wall
			paint(f:box("Post", Vector3.new(0.6, top - groundTop - 0.2, 0.5), s * (W / 2 - 0.45), (groundTop + top) / 2, D / 2, rgb(70, 50, 34), M.Wood, NO), "Timber")
		end
	end

	-- the door: a closed door you use (houses), or an open doorway with a lintel (public buildings)
	local door: BasePart? = nil
	if not hollow then
		door = f:box("Door", Vector3.new(doorWidth, DOOR_HEIGHT, 0.4), doorX, 0.6 + DOOR_HEIGHT / 2, D / 2, rgb(84, 58, 38), M.WoodPlanks)
		paint(door :: BasePart, "Door")
	end
	-- (hanging a little below the door head, so its underside never lies in the wall's)
	paint(f:box("Lintel", Vector3.new(doorWidth + 1.2, 0.6, 0.9), doorX, 0.6 + DOOR_HEIGHT + 0.25, D / 2, rgb(70, 50, 34), M.Wood, NO), "Timber")
	paint(f:box("Step", Vector3.new(doorWidth + 1, 0.3, 1.2), doorX, 0.15, D / 2 + 0.6, palette.trim, M.Slate, NO), "Trim")

	-- roof: eaves to the street, or a gable end facing it
	local roofColor = palette.roof[1]
	local pitch = if spec.style == "Slum" then 0.45 elseif spec.style == "Noble" or spec.style == "Royal" then 0.75 else 0.7
	local ridge
	if spec.roof == "Gable" then
		local rise = W / 2 * pitch
		paint(f:wedgeAt("Roof", Vector3.new(D, rise, W / 2 + 0.6), CFrame.new(-(W / 2 + 0.6) / 2, top + rise / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), roofColor, palette.roofMaterial), "Roof")
		paint(f:wedgeAt("Roof", Vector3.new(D, rise, W / 2 + 0.6), CFrame.new((W / 2 + 0.6) / 2, top + rise / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0), roofColor, palette.roofMaterial), "Roof")
		-- the gable end on the street, standing just proud of the roof's end, in the storey below it: the upper
		-- storeys' plaster or boards, or the ground storey's stone on a one-storey house
		local role = if N > 1 then "Upper" else "Base"
		local gable = if N > 1 then palette.plaster[1] else palette.base[1]
		local gableMaterial = if N > 1 then palette.upperMaterial or M.Plaster else palette.baseMaterial
		paint(f:wedgeAt("Gable", Vector3.new(0.3, rise, W / 2), CFrame.new(-W / 4, top + rise / 2, D / 2 + 0.15) * CFrame.Angles(0, math.pi / 2, 0), gable, gableMaterial, NO), role)
		paint(f:wedgeAt("Gable", Vector3.new(0.3, rise, W / 2), CFrame.new(W / 4, top + rise / 2, D / 2 + 0.15) * CFrame.Angles(0, -math.pi / 2, 0), gable, gableMaterial, NO), role)
		ridge = top + rise
	else
		local half = D / 2 + 1
		local rise = half * pitch
		paint(f:wedgeAt("Roof", Vector3.new(W, rise, half), CFrame.new(0, top + rise / 2, half / 2) * CFrame.Angles(0, math.pi, 0), roofColor, palette.roofMaterial), "Roof")
		paint(f:wedgeAt("Roof", Vector3.new(W, rise, half), CFrame.new(0, top + rise / 2, -half / 2), roofColor, palette.roofMaterial), "Roof")
		ridge = top + rise
	end
	if spec.style ~= "Slum" then
		local h = ridge - top + 3
		paint(f:box("Chimney", Vector3.new(2.4, h, 2.4), W / 2 - 2.2, top + h / 2, -D / 4, palette.base[1], M.Brick, NO), "Base")
	end
	return door
end

-- A shop's front on the street (L-53): an awning above the ground-floor windows beside the door and a hanging sign,
-- so a shop shows from along the street; its counter is inside (Interior.build). Built in the building's frame (door
-- in the front wall at +z). Returns the sign; ShopService writes the owner's name on it.
function Shell.shopfront(model: Model, cf: CFrame, W: number, D: number, style: string, doorWidth: number, seed: number): BasePart
	local f = Kit.frame(model, cf)
	local doorX = Shell.doorX(W)
	local winH = if style == "Noble" or style == "Royal" then 6 elseif style == "Slum" then 3.4 else 4.6
	local head = 0.6 + 3.2 + winH -- top of the ground-floor windows
	local x0, x1 = doorX + doorWidth / 2 + 1.5, W / 2 - 1
	local width = math.min(9, x1 - x0)
	local cx = (x0 + x1) / 2
	local cloth = C.cloth[seed % #C.cloth + 1]
	-- the awning slopes down from the wall towards the street
	f:wedgeAt("Awning", Vector3.new(width + 1, 1.2, 2.4), CFrame.new(cx, head + 0.8, D / 2 + 1.2) * CFrame.Angles(0, math.pi, 0), cloth, M.Fabric, NO)
	-- a sign hanging from a bracket at the awning's far end, readable from both ways along the street
	local signX = cx + width / 2 - 0.3
	f:box("SignBracket", Vector3.new(0.3, 0.3, 3), signX, head + 3.55, D / 2 + 1.5, C.iron, M.Metal, NO)
	local board = f:box("ShopSign", Vector3.new(0.2, 1.6, 2.4), signX, head + 2.75, D / 2 + 1.6, C.darkWood, M.WoodPlanks, NO)
	Kit.sign(board, Enum.NormalId.Left, "Shop", rgb(240, 226, 190))
	Kit.sign(board, Enum.NormalId.Right, "Shop", rgb(240, 226, 190))
	return board
end

-- Repaints a building from its district palette: every part keeps its role ("Base", "Upper", "Roof"...), and the
-- house's own seed picks the shades, so neighbours built from the same model still look different.
function Shell.paint(model: Model, style: string, seed: number)
	local palette = Kit.palettes[style] or Kit.palettes.Residential
	local function shade(list: {Color3}, salt: number): Color3
		return list[(seed + salt) % #list + 1]
	end
	local colors = {
		Base = shade(palette.base, 1),
		Upper = shade(palette.plaster, 2),
		Roof = shade(palette.roof, 3),
	}
	local materials = {
		Base = palette.baseMaterial,
		Upper = palette.upperMaterial or M.Plaster,
		Roof = palette.roofMaterial,
	}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Paint")
			if type(role) == "string" and colors[role] ~= nil then
				part.Color = colors[role]
				if part.Name ~= "Chimney" then
					part.Material = materials[role]
				end
			end
		end
	end
end

return Shell
