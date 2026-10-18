--!nonstrict
-- Shared helpers for authoring a weapon set: key building, looping stances and re-basing the sword set's dodges and reactions
-- onto a weapon's own ready pose. Usage:  local kit = ClipKit.new("Spear", READY, CALM, { twoHand = true })
local ClipKit = {}
local TOOLS = script.Parent -- captured while the module is alive (it is loaded from a throwaway copy)

ClipKit.Action = Enum.AnimationPriority.Action
ClipKit.Movement = Enum.AnimationPriority.Movement
ClipKit.ALL = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
ClipKit.UPPER = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
ClipKit.IN = { ease = "Cubic", dir = "In", marker = "Hit" }
ClipKit.OUT = { ease = "Cubic", dir = "Out" }
ClipKit.SOFT = { ease = "Cubic", dir = "InOut" }
ClipKit.LIN = { ease = "Linear", dir = "Out" }

local function copy(v)
	return { v[1], v[2], v[3], v[4], v[5], v[6] }
end
ClipKit.copy = copy

function ClipKit.with(base, extra)
	local out = {}
	for n, v in pairs(base) do out[n] = v end
	for n, v in pairs(extra or {}) do out[n] = v end
	return out
end

local function loadSword()
	local copyOfModule = TOOLS.SwordClips:Clone()
	copyOfModule.Parent = TOOLS
	local ok, result = pcall(require, copyOfModule)
	copyOfModule:Destroy()
	assert(ok, result)
	return result
end

local function same(a, b)
	return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and (a[4] or 0) == (b[4] or 0) and (a[5] or 0) == (b[5] or 0) and (a[6] or 0) == (b[6] or 0)
end

-- A kit for one set. `options.twoHand`: the set's weapon is held in both hands (clips are flagged for the grip solver).
function ClipKit.new(prefix, READY, CALM, options)
	options = options or {}
	local kit = { prefix = prefix, READY = READY, CALM = CALM }

	function kit.K(t, over, o)
		o = o or {}
		local base = o.base or READY
		local j = {}
		for _, n in ipairs(o.upper and ClipKit.UPPER or ClipKit.ALL) do
			j[n] = copy(base[n] or { 0, 0, 0 })
		end
		for n, v in pairs(over or {}) do
			j[n] = v
		end
		return { t = t, j = j, ease = o.ease, dir = o.dir, marker = o.marker }
	end

	-- A clip table; `hit` is the strike moment used to scale the clip to an ability's windup, `alternates` a rotation of clips.
	function kit.clip(name, hit, keys, extra)
		local clip = ClipKit.with({ name = name, priority = ClipKit.Action, hit = hit, keys = keys, twoHand = options.twoHand }, extra or {})
		return clip
	end

	-- Looping upper-body stance (Movement priority).
	function kit.breathe(base, name, length, twoHand)
		local K = kit.K
		local mid = length / 2
		return { name = name, priority = ClipKit.Movement, loop = true, twoHand = twoHand, keys = {
			K(0, {}, { base = base, upper = true }),
			K(mid, { Waist = { base.Waist[1] + 2, base.Waist[2], 0 }, Neck = { base.Neck[1] - 1.5, base.Neck[2], 0 }, RightShoulder = { base.RightShoulder[1] + 2, base.RightShoulder[2], base.RightShoulder[3] + 1 }, LeftShoulder = { base.LeftShoulder[1] + 2, base.LeftShoulder[2], base.LeftShoulder[3] - 1 }, RightElbow = { base.RightElbow[1] + 3, 0, 0 } }, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
			K(length, {}, { base = base, upper = true, ease = "Cubic", dir = "InOut" }),
		} }
	end

	-- Adds <prefix>Dodge, DodgeForward/Left/Right, HitReactLight/Heavy and Stagger: the sword set's clips with the sword guard
	-- swapped for this set's ready pose. For two-handed sets only the first and last keys carry the grip (the others are `free`).
	function kit.addVariants(Clips)
		local Sword = loadSword()
		for _, name in ipairs({ "Dodge", "DodgeForward", "DodgeLeft", "DodgeRight", "HitReactLight", "HitReactHeavy", "Stagger" }) do
			local source = Sword[name]
			local out = { name = prefix .. name, priority = source.priority, keys = {}, twoHand = options.twoHand }
			for index, key in ipairs(source.keys) do
				local j = {}
				for joint, value in pairs(key.j) do
					if same(value, Sword.bases.GUARD[joint] or { 0, 0, 0 }) and READY[joint] ~= nil then
						j[joint] = copy(READY[joint])
					else
						j[joint] = copy(value)
					end
				end
				out.keys[index] = { t = key.t, j = j, ease = key.ease, dir = key.dir, marker = key.marker, free = options.twoHand and index ~= 1 and index ~= #source.keys or nil }
			end
			Clips[prefix .. name] = out
		end
	end

	-- The standard order list for a set: its own clips, then stances and variants.
	function kit.order(own)
		local list = {}
		for _, n in ipairs(own) do table.insert(list, n) end
		for _, n in ipairs({ "Equip", "Unequip", "Idle", "CombatIdle", "Dodge", "DodgeForward", "DodgeLeft", "DodgeRight", "HitReactLight", "HitReactHeavy", "Stagger" }) do
			table.insert(list, prefix .. n)
		end
		return list
	end

	-- Draw and sheathe, in the weapon's own style: `drawKeys` are the middle keys of the draw.
	function kit.equipUnequip(Clips, drawKeys)
		local K = kit.K
		local keys = { K(0, {}, { base = CALM }) }
		for _, key in ipairs(drawKeys) do
			keys[#keys + 1] = K(key.t, key.j, { base = CALM, ease = key.ease or "Cubic", dir = key.dir or "Out" })
		end
		local last = drawKeys[#drawKeys].t
		keys[#keys + 1] = K(last + 0.2, {}, { base = CALM, ease = "Cubic", dir = "InOut" })
		Clips[prefix .. "Equip"] = { name = prefix .. "Equip", priority = ClipKit.Action, keys = keys }
		Clips[prefix .. "Unequip"] = { name = prefix .. "Unequip", priority = ClipKit.Action, keys = {
			K(0, {}),
			K(0.18, { RightShoulder = { 50, 0, 12 }, RightElbow = { 60, 0, 0 }, Waist = { 0, 8, 0 } }, ClipKit.SOFT),
			K(0.4, {}, { base = CALM, ease = "Cubic", dir = "InOut" }),
		} }
	end

	return kit
end

return ClipKit
