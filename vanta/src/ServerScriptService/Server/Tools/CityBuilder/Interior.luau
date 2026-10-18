--!strict
-- The room behind a house's door (and an inn room), built far above the map by InteriorService only while someone
-- is inside. For now an interior is only its walls: floor, four walls, ceiling, a lamp, and the door back out.
-- Built at the origin, the door in the front wall (+z). Templates live in ServerStorage.CityAssets.Interiors and can
-- be remodelled in Studio; InteriorService needs a part named "Entry" (where you appear, facing -z) and a part named
-- "ExitDoor".
local Kit = require(script.Parent.Kit)

local Interior = {}
local M = Kit.materials
local rgb = Kit.rgb

local HEIGHT = 12
local T = 1

function Interior.build(name: string, width: number, depth: number, style: string?): Model
	local model = Instance.new("Model")
	model.Name = name
	local f = Kit.frame(model, CFrame.new())
	local palette = Kit.palettes[style or "Residential"] or Kit.palettes.Residential
	local wall = palette.plaster[1]
	local hw, hd = width / 2, depth / 2
	f:box("Floor", Vector3.new(width + 2 * T, T, depth + 2 * T), 0, -T / 2, 0, rgb(132, 98, 66), M.WoodPlanks)
	f:box("Ceiling", Vector3.new(width + 2 * T, T, depth + 2 * T), 0, HEIGHT + T / 2, 0, rgb(110, 84, 58), M.WoodPlanks)
	f:box("WallBack", Vector3.new(width, HEIGHT, T), 0, HEIGHT / 2, -hd - T / 2, wall, M.Plaster)
	f:box("WallFront", Vector3.new(width, HEIGHT, T), 0, HEIGHT / 2, hd + T / 2, wall, M.Plaster)
	f:box("WallLeft", Vector3.new(T, HEIGHT, depth + 2 * T), -hw - T / 2, HEIGHT / 2, 0, wall, M.Plaster)
	f:box("WallRight", Vector3.new(T, HEIGHT, depth + 2 * T), hw + T / 2, HEIGHT / 2, 0, wall, M.Plaster)
	-- the door back to the street stands against the front wall, inside the room
	local doorX = if width >= 18 then -width / 6 else 0
	local exit = f:box("ExitDoor", Vector3.new(5, 8.4, 0.4), doorX, 4.2, hd - 0.2, rgb(84, 58, 38), M.WoodPlanks)
	exit.CanQuery = true
	-- where you appear, facing into the room (a part's front is -z)
	local entry = f:box("Entry", Vector3.new(2, 1, 2), doorX, 0.5, hd - 4, rgb(255, 255, 255), M.SmoothPlastic, { collide = false, query = false, transparency = 1, shadow = false })
	local lamp = f:box("CeilingLamp", Vector3.new(1.2, 0.6, 1.2), 0, HEIGHT - 0.6, 0, rgb(255, 220, 160), M.Neon, { collide = false, query = false, shadow = false })
	Kit.light(lamp, rgb(255, 214, 160), math.max(width, depth) + 6, 1.1)
	model.PrimaryPart = entry
	return model
end

return Interior
