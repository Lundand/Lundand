--[[
	Util — number/time formatting and world-position helpers shared by server and client.
]]

local Config = require(script.Parent.Config)

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg" }

-- 1234567 -> "1,234,567"
function Util.Commas(n: number): string
	n = math.floor(n + 0.5)
	local neg = n < 0
	local s = string.format("%d", math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (neg and "-" or "") .. out
end

local function trimZeros(str: string): string
	if string.find(str, "%.") then
		str = (string.gsub(str, "0+$", ""))
		str = (string.gsub(str, "%.$", ""))
	end
	return str
end

-- 4320 -> "4,320", 123456 -> "123K", 2500000 -> "2.5M"
function Util.Abbrev(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local neg = n < 0
	local v = math.abs(n)
	if v < 10000 then
		return Util.Commas(n)
	end
	local i = 1
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local str
	if v >= 100 then
		str = string.format("%.0f", v)
	elseif v >= 10 then
		str = string.format("%.1f", v)
	else
		str = string.format("%.2f", v)
	end
	if (tonumber(str) or 0) >= 1000 and i < #SUFFIXES then
		i += 1
		str = "1"
	end
	return (neg and "-" or "") .. trimZeros(str) .. SUFFIXES[i]
end

-- "1/100,000"
function Util.Odds(den: number): string
	if den < 1e9 then
		return "1/" .. Util.Commas(den)
	end
	return "1/" .. Util.Abbrev(den)
end

-- 42*3600+31*60+18 -> "42:31:18", 261 -> "04:21"
function Util.Clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- 90 -> "1m 30s", 7200 -> "2h", 90000 -> "1d 1h"
function Util.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s"
	end
	if seconds < 3600 then
		local m, s = math.floor(seconds / 60), seconds % 60
		return s > 0 and string.format("%dm %ds", m, s) or string.format("%dm", m)
	end
	if seconds < 86400 then
		local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
		return m > 0 and string.format("%dh %dm", h, m) or string.format("%dh", h)
	end
	local d, h = math.floor(seconds / 86400), math.floor((seconds % 86400) / 3600)
	return h > 0 and string.format("%dd %dh", d, h) or string.format("%dd", d)
end

--------------------------------------------------------------------------------
-- World helpers
--------------------------------------------------------------------------------
local W = Config.World

function Util.ZoneStartX(i: number): number
	return W.GateX + (i - 1) * W.ZoneLength
end

function Util.ZoneEndX(i: number): number
	return W.GateX + i * W.ZoneLength
end

function Util.WorldEndX(): number
	return Util.ZoneEndX(#Config.Zones)
end

-- 0 = spawn/base safe area, 1..8 = main zones
function Util.ZoneAtX(x: number): number
	if x < W.GateX then
		return 0
	end
	local i = math.floor((x - W.GateX) / W.ZoneLength) + 1
	return math.clamp(i, 1, #Config.Zones)
end

-- Where Travel drops you for zone i
function Util.ZoneEntry(i: number): Vector3
	return Vector3.new(Util.ZoneStartX(i) + 16, 4, 0)
end

-- Rift portal and the pad you return to from the Endless Rift
function Util.RiftPortalPos(): Vector3
	return Vector3.new(Util.WorldEndX() - 22, 0, 0)
end

function Util.RiftReturnPos(): Vector3
	return Vector3.new(Util.WorldEndX() - 48, 4, 22)
end

-- Zone a player is standing in (uses the RiftZone attribute set by the server while in the Rift)
function Util.PlayerZone(player: Player, position: Vector3?): number
	local rift = player:GetAttribute("RiftZone")
	if type(rift) == "number" and rift > 0 then
		return rift
	end
	if position then
		return Util.ZoneAtX(position.X)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return Util.ZoneAtX(root.Position.X)
	end
	return 0
end

function Util.IsContested(zone: number): boolean
	if Config.PvP.Mode == "Off" or zone <= 0 then
		return false
	end
	if Config.PvP.Mode == "Everywhere" then
		return true
	end
	local z = Config.Zones[zone]
	return z ~= nil and z.pvp == true
end

function Util.FlatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function Util.IsFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	for _, c in { v.X, v.Y, v.Z } do
		if c ~= c or c == math.huge or c == -math.huge then
			return false
		end
	end
	return true
end

function Util.Lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function Util.Darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

return Util
