--!nocheck
-- lune run tools/export-parts.luau x0 x1 z0 z1 [out.json] — builds the city offline and writes every part whose
-- centre lies in the box (x0..x1, z0..z1) as JSON, for tools/render_view.py.
-- lune run tools/export-parts.luau model Name [out.json] — only the parts of the model (or folder) called Name.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Harness = require("./harness")
local Enum = require("@lune/roblox").Enum
Harness.loadSource("src")
local CityBuilder = Harness.require(Harness.find("ServerScriptService.Server.Tools.CityBuilder"))
local city = CityBuilder.build()
local scope, out = city, nil
local x0, x1, z0, z1 = -math.huge, math.huge, -math.huge, math.huge
if process.args[1] == "model" then
	for _, d in city:GetDescendants() do
		if d.Name == process.args[2] and (d:IsA("Model") or d:IsA("Folder")) then
			scope = d
			break
		end
	end
	out = process.args[3] or "build/parts.json"
else
	x0, x1, z0, z1 = tonumber(process.args[1]), tonumber(process.args[2]), tonumber(process.args[3]), tonumber(process.args[4])
	out = process.args[5] or "build/parts.json"
end
local parts = {}
for _, p in scope:GetDescendants() do
	if p:IsA("BasePart") and p.Transparency < 0.95 then
		local pos = p.CFrame.Position
		if pos.X >= x0 and pos.X <= x1 and pos.Z >= z0 and pos.Z <= z1 then
			local c = { p.CFrame:GetComponents() }
			table.insert(parts, {
				c = c,
				s = { p.Size.X, p.Size.Y, p.Size.Z },
				k = if p:IsA("WedgePart") then "w" elseif p.Shape == Enum.PartType.Cylinder then "c" elseif p.Shape == Enum.PartType.Ball then "b" else "p",
				rgb = { math.floor(p.Color.R * 255), math.floor(p.Color.G * 255), math.floor(p.Color.B * 255) },
				t = p.Transparency,
				n = p.Name,
			})
		end
	end
end
fs.writeDir("build")
fs.writeFile(out, serde.encode("json", parts))
print(#parts .. " parts -> " .. out)
