--!nonstrict
-- Authoring tool (not shipped to players): turns hand-written clip data into R15 KeyframeSequences, and previews
-- a clip on a rig in Edit mode. Clip format: { name, priority, loop, keys = { { t, ease, dir, j = { Joint = {rx,ry,rz,px,py,pz} }, marker } } }
-- Rotations are degrees in joint space (+X raises an arm or leg forward, +Z swings the right arm out), positions are studs.
local Builder = {}

local PART_OF = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}
local PARENT_OF = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
}
Builder.PART_OF = PART_OF

local function toCFrame(v)
	local c = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
	return CFrame.new(v[4] or 0, v[5] or 0, v[6] or 0) * c
end
Builder.toCFrame = toCFrame

function Builder.build(clip)
	local ks = Instance.new("KeyframeSequence")
	ks.Name = clip.name
	ks.Loop = clip.loop == true
	ks.Priority = clip.priority or Enum.AnimationPriority.Action
	for _, key in ipairs(clip.keys) do
		local kf = Instance.new("Keyframe")
		kf.Time = key.t
		local poses = {}
		local function poseFor(part, active)
			local p = poses[part]
			if p == nil then
				p = Instance.new("Pose")
				p.Name = part
				p.Weight = 0
				poses[part] = p
				local parentName = PARENT_OF[part]
				if parentName ~= nil then
					p.Parent = poseFor(parentName, false)
				else
					p.Parent = kf
				end
			end
			return p
		end
		poseFor("HumanoidRootPart", false)
		for joint, v in pairs(key.j or {}) do
			local pose = poseFor(PART_OF[joint], true)
			pose.CFrame = toCFrame(v)
			pose.Weight = 1
			pose.EasingStyle = Enum.PoseEasingStyle[(key.ease == "Quad" or key.ease == nil) and "Cubic" or key.ease]
			pose.EasingDirection = Enum.PoseEasingDirection[key.dir or "Out"]
		end
		if key.marker ~= nil then
			for _, name in ipairs(type(key.marker) == "table" and key.marker or { key.marker }) do
				local marker = Instance.new("KeyframeMarker")
				marker.Name = name
				marker.Parent = kf
			end
		end
		kf.Parent = ks
	end
	return ks
end

-- Samples joint transforms at time t (linear between the keys that mention the joint, eased per key).
local function ease(style, dir, a)
	if style == "Linear" then return a end
	local p = (style == "Quad") and 2 or (style == "Cubic") and 3 or (style == "Elastic") and 3 or 3
	if dir == "In" then return a ^ p
	elseif dir == "Out" then return 1 - (1 - a) ^ p
	else return a < 0.5 and 0.5 * (2 * a) ^ p or 1 - 0.5 * (2 * (1 - a)) ^ p end
end

function Builder.sample(clip, t)
	local out = {}
	for joint in pairs(PART_OF) do
		local prev, nextKey
		for _, key in ipairs(clip.keys) do
			if key.j and key.j[joint] then
				if key.t <= t then prev = key end
				if key.t > t and nextKey == nil then nextKey = key end
			end
		end
		if prev and nextKey then
			local a = (t - prev.t) / (nextKey.t - prev.t)
			a = ease(nextKey.ease or "Cubic", nextKey.dir or "Out", a)
			out[joint] = toCFrame(prev.j[joint]):Lerp(toCFrame(nextKey.j[joint]), a)
		elseif prev then
			out[joint] = toCFrame(prev.j[joint])
		elseif nextKey then
			out[joint] = toCFrame(nextKey.j[joint])
		end
	end
	return out
end

-- Forward kinematics on an anchored preview rig, plus the welded weapon.
function Builder.pose(model, transforms)
	local root = model.HumanoidRootPart
	local order = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
	for _, name in ipairs(order) do
		local con = model:FindFirstChild(name, true)
		if con ~= nil and con:IsA("AnimationConstraint") then
			con.Part1.CFrame = con.Part0.CFrame * con.C0 * (transforms[name] or CFrame.identity) * con.C1:Inverse()
		end
	end
	local weapon = model:FindFirstChild("Weapon")
	if weapon ~= nil then
		weapon:PivotTo(model[(model:GetAttribute("WeaponHand") or "Right") .. "Hand"].CFrame * (model:GetAttribute("GripOffset") or CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-90), 0, 0)))
	end
	local shield = model:FindFirstChild("Shield")
	if shield ~= nil then
		shield:PivotTo(model.LeftLowerArm.CFrame * (model:GetAttribute("ShieldGrip") or CFrame.new(0, 0.05, -0.75)))
	end
	local offhand = model:FindFirstChild("OffhandWeapon")
	if offhand ~= nil then
		offhand:PivotTo(model.LeftHand.CFrame * (model:GetAttribute("GripOffset") or CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-90), 0, 0)))
	end
end

-- Two-handed grips: for every key of a clip, finds a right-shoulder sideways angle (pulling the staff in towards the
-- middle of the body, where two hands can actually meet) plus left shoulder and elbow rotations that put the left hand on
-- the staff shaft, and writes them into the key. A pattern search over a two-bone chain on the posed rig. `rig` must be an
-- anchored preview rig holding the weapon. Keys marked `free` are left as authored. Returns a short report.
function Builder.solveTwoHand(clip, rig, preferred)
	preferred = preferred or 1.4
	local weapon = rig:FindFirstChild("Weapon")
	local shoulder = rig:FindFirstChild("LeftShoulder", true)
	local elbow = rig:FindFirstChild("LeftElbow", true)
	local wrist = rig:FindFirstChild("LeftWrist", true)
	local random = Random.new(7)
	local worst, total, count = 0, 0, 0
	local LIMITS = { { -1.0, 3.1 }, { -1.7, 1.7 }, { -1.9, 1.7 }, { 0, 2.5 } } -- left shoulder rx, ry, rz; elbow rx (radians)
	for _, key in ipairs(clip.keys) do
		if not key.free then
			local best = { score = math.huge }
			local authoredRz = (key.j.RightShoulder or { 0, 0, 0 })[3]
			for _, rightRz in ipairs({ math.min(authoredRz, -10), -22, -36, -50 }) do
				local transforms = {}
				for joint, v in pairs(key.j) do transforms[joint] = toCFrame(v) end
				local rs = key.j.RightShoulder or { 0, 0, 0 }
				transforms.RightShoulder = toCFrame({ rs[1], rs[2], rightRz })
				Builder.pose(rig, transforms)
				local upperTorso = rig.UpperTorso.CFrame
				local grip = weapon.PrimaryPart
				local base, axis = grip.Position, grip.CFrame.UpVector
				local function reach(v, target)
					local upper = upperTorso * shoulder.C0 * CFrame.Angles(v[1], v[2], v[3]) * shoulder.C1:Inverse()
					local lower = upper * elbow.C0 * CFrame.Angles(v[4], 0, 0) * elbow.C1:Inverse()
					local hand = lower * wrist.C0 * wrist.C1:Inverse()
					return (hand.Position - target).Magnitude
				end
				local authored = key.j.LeftShoulder or { 0, 0, 0 }
				for _, d in ipairs({ -0.8, -0.4, 0.2, 0.6, 1.0, 1.4, 1.8, 2.2 }) do
					local target = base + axis * d
					for attempt = 1, 4 do
						local v = {
							math.rad(authored[1]) + (attempt > 1 and random:NextNumber(-0.8, 0.8) or 0),
							math.rad(authored[2]) + (attempt > 1 and random:NextNumber(-0.6, 0.6) or 0),
							math.rad(authored[3]) + (attempt > 1 and random:NextNumber(-0.8, 0.8) or 0),
							math.rad((key.j.LeftElbow or { 40 })[1]) + (attempt > 1 and random:NextNumber(-0.8, 0.8) or 0),
						}
						for i = 1, 4 do v[i] = math.clamp(v[i], LIMITS[i][1], LIMITS[i][2]) end
						local err = reach(v, target)
						local step = 0.4
						for _ = 1, 60 do
							local improved = false
							for i = 1, 4 do
								for _, sign in ipairs({ 1, -1 }) do
									local old = v[i]
									v[i] = math.clamp(old + sign * step, LIMITS[i][1], LIMITS[i][2])
									local e = reach(v, target)
									if e < err - 1e-4 then err = e; improved = true else v[i] = old end
								end
							end
							if not improved then step *= 0.6 if step < 0.002 then break end end
						end
						-- prefer a right arm close to where it was authored, and hands a natural distance apart
						local spread = math.min(math.abs(d - 1.3), math.abs(d + 1.0)) -- hands about a shoulder-width apart, either side
						local score = err + 0.22 * spread + 0.004 * math.abs(rightRz - authoredRz)
						if score < best.score then best = { score = score, err = err, v = { v[1], v[2], v[3], v[4] }, rz = rightRz } end
						if err < 0.03 then break end
					end
				end
			end
			worst = math.max(worst, best.err)
			total += best.err
			count += 1
			if best.err <= 0.45 then
				local rs = key.j.RightShoulder or { 0, 0, 0 }
				key.j.RightShoulder = { rs[1], rs[2], best.rz }
				key.j.LeftShoulder = { math.deg(best.v[1]), math.deg(best.v[2]), math.deg(best.v[3]) }
				key.j.LeftElbow = { math.deg(best.v[4]), 0, 0 }
				key.j.LeftWrist = { 0, 0, 0 }
				key.solved = true
			end
		end
		task.wait()
	end
	return string.format("%s: %d keys, mean miss %.2f studs, worst %.2f", clip.name, count, count > 0 and total / count or 0, worst)
end

-- Bow draw: for every key carrying `draw` (studs the string is pulled back from rest, 0 to about 2.4), finds right shoulder
-- and elbow rotations that put the right hand on the string at that pull. The bow is in the left hand (rig attribute
-- WeaponHand = "Left"); the string's rest point is the bow's nock, (0, 0.6, -0.5) in weapon space, and pulling goes
-- further along -Z. Keys without `draw` are left as authored. Returns a short report.
function Builder.solveDraw(clip, rig)
	local weapon = rig:FindFirstChild("Weapon")
	local shoulder = rig:FindFirstChild("RightShoulder", true)
	local elbow = rig:FindFirstChild("RightElbow", true)
	local wrist = rig:FindFirstChild("RightWrist", true)
	local random = Random.new(11)
	local LIMITS = { { -1.0, 3.1 }, { -1.7, 1.7 }, { -1.7, 1.9 }, { 0, 2.5 } }
	local worst, total, count = 0, 0, 0
	for _, key in ipairs(clip.keys) do
		if key.draw ~= nil then
			local transforms = {}
			for joint, v in pairs(key.j) do transforms[joint] = toCFrame(v) end
			Builder.pose(rig, transforms)
			local upperTorso = rig.UpperTorso.CFrame
			local target = weapon.PrimaryPart.CFrame:PointToWorldSpace(Vector3.new(0, 0.6, -0.5 - math.max(key.draw, 1.1)))
			local function reach(v)
				local upper = upperTorso * shoulder.C0 * CFrame.Angles(v[1], v[2], v[3]) * shoulder.C1:Inverse()
				local lower = upper * elbow.C0 * CFrame.Angles(v[4], 0, 0) * elbow.C1:Inverse()
				local hand = lower * wrist.C0 * wrist.C1:Inverse()
				return (hand.Position - target).Magnitude
			end
			local authored = key.j.RightShoulder or { 0, 0, 0 }
			local bestErr, bestV = math.huge, nil
			for attempt = 1, 24 do
				local v = {
					math.rad(authored[1]) + (attempt > 1 and random:NextNumber(-1.0, 1.0) or 0),
					math.rad(authored[2]) + (attempt > 1 and random:NextNumber(-0.8, 0.8) or 0),
					math.rad(authored[3]) + (attempt > 1 and random:NextNumber(-1.0, 1.0) or 0),
					math.rad((key.j.RightElbow or { 60 })[1]) + (attempt > 1 and random:NextNumber(-1.0, 1.0) or 0),
				}
				for i = 1, 4 do v[i] = math.clamp(v[i], LIMITS[i][1], LIMITS[i][2]) end
				local err = reach(v)
				local step = 0.4
				for _ = 1, 70 do
					local improved = false
					for i = 1, 4 do
						for _, sign in ipairs({ 1, -1 }) do
							local old = v[i]
							v[i] = math.clamp(old + sign * step, LIMITS[i][1], LIMITS[i][2])
							local e = reach(v)
							if e < err - 1e-4 then err = e; improved = true else v[i] = old end
						end
					end
					if not improved then step *= 0.6 if step < 0.002 then break end end
				end
				if err < bestErr then bestErr, bestV = err, { v[1], v[2], v[3], v[4] } end
				if err < 0.03 then break end
			end
			worst = math.max(worst, bestErr)
			total += bestErr
			count += 1
			if bestErr <= 0.45 then
				key.j.RightShoulder = { math.deg(bestV[1]), math.deg(bestV[2]), math.deg(bestV[3]) }
				key.j.RightElbow = { math.deg(bestV[4]), 0, 0 }
				key.j.RightWrist = { 0, 0, 0 }
			end
		end
		task.wait()
	end
	return string.format("%s: %d drawn keys, mean miss %.2f studs, worst %.2f", clip.name, count, count > 0 and total / count or 0, worst)
end

return Builder
