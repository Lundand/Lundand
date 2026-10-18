--!nocheck
-- Offline harness: builds a DataModel from vanta/src (one ModuleScript/Script/LocalScript per file, folders for
-- directories) and runs modules in it with a Roblox-like `require`, `script` and `game`. Used by run-tests.luau
-- and build-city.luau. Needs Lune 0.10 (https://github.com/lune-org/lune).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local Harness = {}

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	if child == nil then
		error(self:GetFullName() .. " has no child " .. tostring(name), 2)
	end
	return child
end)

local game = roblox.Instance.new("DataModel")
Harness.game = game

local function classFor(fileName: string): (string?, string?)
	for suffix, className in { [".server.luau"] = "Script", [".client.luau"] = "LocalScript", [".luau"] = "ModuleScript" } do
		if string.sub(fileName, -#suffix) == suffix then
			-- longest suffix wins
			local base = string.sub(fileName, 1, -#suffix - 1)
			if className == "ModuleScript" and (string.find(base, "%.server$") or string.find(base, "%.client$")) then
				continue
			end
			return className, base
		end
	end
	return nil, nil
end

local function load(dir: string, parent: Instance)
	local initPath, initClass = nil, nil
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			local folder = parent:FindFirstChild(name) or roblox.Instance.new("Folder")
			folder.Name = name
			folder.Parent = parent
			load(path, folder)
		else
			local className, base = classFor(name)
			if className and base == "init" then
				initPath, initClass = path, className
			elseif className then
				local scriptInstance = roblox.Instance.new(className)
				scriptInstance.Name = base
				scriptInstance.Source = fs.readFile(path)
				scriptInstance.Parent = parent
			end
		end
	end
	if initPath then
		-- an init file turns its folder into the script itself, keeping the children
		local scriptInstance = roblox.Instance.new(initClass)
		scriptInstance.Name = parent.Name
		scriptInstance.Source = fs.readFile(initPath)
		for _, child in parent:GetChildren() do
			child.Parent = scriptInstance
		end
		scriptInstance.Parent = parent.Parent
		parent:Destroy()
	end
end

function Harness.loadSource(root: string)
	for _, serviceName in fs.readDir(root) do
		local service = game:GetService(serviceName)
		load(root .. "/" .. serviceName, service)
	end
end

-- Lune has no Random; a small deterministic stand-in (xorshift) with the methods the code uses.
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	local state = math.floor(seed or os.clock() * 1e6) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ state = state }, RandomShim)
end
function RandomShim:NextNumber(min: number?, max: number?): number
	self.state = (self.state * 48271) % 2147483647
	local unit = self.state / 2147483647
	if min ~= nil and max ~= nil then
		return min + (max - min) * unit
	end
	return unit
end
function RandomShim:NextInteger(min: number, max: number): number
	return math.min(max, min + math.floor(self:NextNumber() * (max - min + 1)))
end

local cache = {}
local globals = {
	game = game,
	workspace = game:GetService("Workspace"),
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	BrickColor = roblox.BrickColor,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Random = RandomShim,
	Font = roblox.Font,
	Rect = roblox.Rect,
	task = require("@lune/task"),
	tick = os.clock,
	warn = function(...)
		print("[warn]", ...)
	end,
}

local function requireModule(target: any)
	if typeof(target) ~= "Instance" then
		error("harness require only takes ModuleScripts, got " .. typeof(target), 2)
	end
	-- Lune hands out a new wrapper for an instance on every access, so modules are cached by their path
	local key = target:GetFullName()
	local cached = cache[key]
	if cached ~= nil then
		return cached.value
	end
	local env = { script = target }
	for key, value in globals do
		env[key] = value
	end
	env.require = requireModule
	local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = env, injectGlobals = true })
	local value = chunk()
	cache[key] = { value = value }
	return value
end
globals.require = requireModule
Harness.require = requireModule

function Harness.find(path: string): Instance
	local current: Instance = game
	for part in string.gmatch(path, "[^%.]+") do
		local nextInstance = if current == game then game:GetService(part) else current:FindFirstChild(part)
		if nextInstance == nil then
			error("no instance at " .. path)
		end
		current = nextInstance
	end
	return current
end

function Harness.exit(code: number)
	process.exit(code)
end

return Harness
