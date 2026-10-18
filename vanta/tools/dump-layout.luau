--!nocheck
-- lune run tools/dump-layout.luau [out.json] — writes ServerData.CityLayout as JSON (for tools/render_plan.py).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Harness = require("./harness")
Harness.loadSource("src")
local layout = Harness.require(Harness.find("ServerStorage.ServerData.CityLayout"))
local out = process.args[1] or "build/layout.json"
fs.writeDir("build")
fs.writeFile(out, serde.encode("json", layout))
print("wrote " .. out)
