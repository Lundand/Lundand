--!nonstrict
-- Authoring tool: builds ReplicatedStorage.Assets.Subtypes (one model per weapon subtype and shield type in Config.Gear)
-- and ReplicatedStorage.Assets.ArmorSets.<Weight>.<Slot> from generated sources in ServerStorage.AssetSources
-- (named "Sub_<Subtype>" / "Armor_<Weight>_<Slot>", or an existing source a spec reuses).
-- Unlike the hand-measured Library, every mesh here is measured automatically from its vertices:
--   * its length axis is turned to +Y, and it is flipped so the business end is up (a sword's guard sits low; an axe's,
--     hammer's or polearm's head is the wider end, up);
--   * blades and heads are rolled so their width lies along the grip's Z (edges facing the cut, the swing plane);
--   * the grip is found (just below a blade's guard, or a set fraction up a haft), and the model is scaled to its length.
-- Conventions are the Library's: PrimaryPart "Grip", +Y to the tip, attachments TipAttachment / TrailBase / TrailTip;
-- bows get a drawn string between their limb tips and a NockAttachment, with the arrow side towards the grip's +Z.
-- Run:  <fresh copy of this module>.build()
local SubtypeBuilder = {}

local SOURCES = game.ServerStorage.AssetSources

-- kind: "blade" (guard low), "head" (wide end up), "bow", "crossbow", "glove", "orb"
-- length: finished length in studs; grip: for heads, the grip's height as a fraction of the length
SubtypeBuilder.WEAPONS = {
	ShortSword = { family = "Sword", kind = "blade", length = 3.4 },
	ArmingSword = { family = "Sword", kind = "blade", length = 4.0 },
	Longsword = { family = "Sword", kind = "blade", length = 4.6 },
	KnightsSword = { family = "Sword", kind = "blade", length = 4.3 },
	Saber = { family = "Sword", kind = "blade", length = 4.0 },
	Scimitar = { family = "Sword", kind = "blade", length = 3.9 },
	Rapier = { family = "Sword", kind = "blade", length = 4.4 },
	Katana = { family = "Sword", kind = "blade", length = 4.3 },
	BastardSword = { family = "Sword", kind = "blade", length = 4.8 },
	Greatsword = { family = "Greatsword", kind = "blade", length = 5.8 },
	Zweihander = { family = "Greatsword", kind = "blade", length = 6.4 },
	Claymore = { family = "Greatsword", kind = "blade", length = 5.8 },
	ExecutionersSword = { family = "Greatsword", kind = "blade", length = 5.4 },
	HeavyBlade = { family = "Greatsword", kind = "blade", length = 5.6 },
	Dagger = { family = "Dagger", kind = "blade", length = 2.6 },
	DualDaggers = { family = "Dagger", kind = "blade", length = 2.6 },
	Stiletto = { family = "Dagger", kind = "blade", length = 2.5 },
	Kris = { family = "Dagger", kind = "blade", length = 2.6 },
	AssassinsBlade = { family = "Dagger", kind = "blade", length = 2.8 },
	ThrowingKnives = { family = "Dagger", kind = "blade", length = 2.0 },
	HandAxe = { family = "Axe", kind = "head", length = 2.8, grip = 0.18 },
	Hatchet = { family = "Axe", kind = "head", length = 2.6, grip = 0.18 },
	BattleAxe = { family = "Axe", kind = "head", length = 3.4, grip = 0.16 },
	GreatAxe = { family = "Greataxe", kind = "head", length = 4.8, grip = 0.12 },
	ExecutionersAxe = { family = "Greataxe", kind = "head", length = 4.8, grip = 0.12 },
	DoubleHeadedAxe = { family = "Greataxe", kind = "head", length = 4.6, grip = 0.12, source = "IronGreataxe" },
	Mace = { family = "Mace", kind = "head", length = 3.1, grip = 0.18, source = "TrainingMace" },
	Warhammer = { family = "Mace", kind = "head", length = 3.2, grip = 0.18 },
	Club = { family = "Mace", kind = "head", length = 3.0, grip = 0.18 },
	Maul = { family = "Maul", kind = "head", length = 4.8, grip = 0.12 },
	GreatHammer = { family = "Maul", kind = "head", length = 5.0, grip = 0.12 },
	HeavyWarhammer = { family = "Maul", kind = "head", length = 5.0, grip = 0.12 },
	Spear = { family = "Spear", kind = "head", length = 6.85, grip = 0.12, source = "IronSpear" },
	Pike = { family = "Spear", kind = "head", length = 8.0, grip = 0.12 },
	Lance = { family = "Spear", kind = "blade", length = 7.4 }, -- measured like a blade: its vamplate is the widest part, low, the grip just below it
	Halberd = { family = "Spear", kind = "head", length = 7.0, grip = 0.12 },
	Glaive = { family = "Spear", kind = "head", length = 6.8, grip = 0.12 },
	Poleaxe = { family = "Spear", kind = "head", length = 6.4, grip = 0.12 },
	Trident = { family = "Spear", kind = "head", length = 6.6, grip = 0.12 },
	Shortbow = { family = "Bow", kind = "bow", length = 3.6 },
	Longbow = { family = "Bow", kind = "bow", length = 5.4 },
	RecurveBow = { family = "Bow", kind = "bow", length = 4.2 },
	HuntingBow = { family = "Bow", kind = "library", source = "HuntingBow" },
	WarBow = { family = "Bow", kind = "bow", length = 5.0 },
	LightCrossbow = { family = "Crossbow", kind = "crossbow", length = 2.6 },
	HeavyCrossbow = { family = "Crossbow", kind = "crossbow", length = 3.2 },
	RepeatingCrossbow = { family = "Crossbow", kind = "crossbow", length = 2.8 },
	Arbalest = { family = "Crossbow", kind = "crossbow", length = 3.6 },
	ApprenticeStaff = { family = "Staff", kind = "library", source = "ApprenticeStaff" },
	WizardStaff = { family = "Staff", kind = "head", length = 5.4, grip = 0.32 },
	BattleStaff = { family = "Staff", kind = "head", length = 5.2, grip = 0.3 },
	ElementalStaff = { family = "Staff", kind = "head", length = 5.4, grip = 0.32 },
	ArcaneStaff = { family = "Staff", kind = "head", length = 5.6, grip = 0.32 },
	RitualStaff = { family = "Staff", kind = "head", length = 5.4, grip = 0.32 },
	ApprenticeWand = { family = "Wand", kind = "head", length = 1.5, grip = 0.22 },
	ArcaneWand = { family = "Wand", kind = "head", length = 1.6, grip = 0.22 },
	ElementalWand = { family = "Wand", kind = "head", length = 1.6, grip = 0.22 },
	BattleWand = { family = "Wand", kind = "head", length = 1.8, grip = 0.22 },
	RitualWand = { family = "Wand", kind = "head", length = 1.6, grip = 0.22 },
	ArcaneOrb = { family = "Catalyst", kind = "orb", length = 1.5 },
	ElementalOrb = { family = "Catalyst", kind = "orb", length = 1.5 },
	SoulOrb = { family = "Catalyst", kind = "orb", length = 1.5 },
	CrystalCatalyst = { family = "Catalyst", kind = "orb", length = 1.6 },
	RuneCatalyst = { family = "Catalyst", kind = "orb", length = 1.5 },
	SpellFocus = { family = "Catalyst", kind = "orb", length = 1.4 },
	Knuckles = { family = "Fist", kind = "library", source = "WornKnuckles" },
	Claws = { family = "Fist", kind = "glove", length = 1.5 },
	Gauntlets = { family = "Fist", kind = "glove", length = 1.2 },
	Tonfa = { family = "Fist", kind = "head", length = 2.2, grip = 0.3 },
	MartialBracers = { family = "Fist", kind = "glove", length = 1.3 },
}
-- shields: height in studs (the Oak Shield already is a heater shield)
SubtypeBuilder.SHIELDS = {
	Buckler = { height = 1.6 }, RoundShield = { height = 2.4 }, KiteShield = { height = 3.2 },
	HeaterShield = { height = 2.7, source = "OakShield" }, TowerShield = { height = 4.0 }, Greatshield = { height = 4.4 },
}
-- armor set pieces: the body part(s) worn on, the fitted box (studs, R15 blocky body), its centre from the body part's
-- centre, and a turn (fingers and boots are generated upright; gloves are flipped so the fingers point down the arm)
SubtypeBuilder.ARMOR_SLOTS = {
	Head = { parts = "Head", size = Vector3.new(1.55, 1.5, 1.6), offset = CFrame.new(0, 0.18, 0.02), hidesHair = true },
	Chest = { parts = "UpperTorso", size = Vector3.new(3.3, 2.3, 1.45), offset = CFrame.new(0, -0.15, 0) },
	Hands = { parts = "LeftLowerArm,RightLowerArm", size = Vector3.new(1.18, 1.3, 1.18), offset = CFrame.new(0, -0.45, 0) * CFrame.Angles(math.rad(180), 0, 0) },
	Legs = { parts = "LeftUpperLeg,RightUpperLeg", size = Vector3.new(1.16, 1.5, 1.12), offset = CFrame.new(0, 0.05, 0) },
	Feet = { parts = "LeftLowerLeg,RightLowerLeg", size = Vector3.new(1.14, 1.75, 1.3), offset = CFrame.new(0, -0.3, -0.06) },
	Back = { parts = "UpperTorso", size = Vector3.new(2.4, 3.4, 0.55), offset = CFrame.new(0, -0.75, 0.68) },
}

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if f == nil then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function sourceMesh(name)
	local model = SOURCES:FindFirstChild(name)
	if model == nil then
		return nil
	end
	if model:IsA("MeshPart") then
		return model
	end
	return model:FindFirstChildWhichIsA("MeshPart", true)
end

local function prepare(mesh, name)
	local part = mesh:Clone()
	for _, child in ipairs(part:GetChildren()) do
		if not child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	part.Name = name
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

local function holder(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(0.25, 0.9, 0.25)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = CFrame.identity
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function attachment(parent, name, position)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

-- the mesh's vertices in its own (unscaled-size) space, via the probe tool
local Probe
local function vertices(part)
	if Probe == nil then
		local src = game.ServerStorage.AssetTools.MeshProbe -- (not script.Parent: this module runs from a fresh copy)
		local c = src:Clone()
		c.Parent = src.Parent
		Probe = require(c)
		c:Destroy()
	end
	local verts = {}
	for _, t in ipairs(Probe.triangles(part)) do
		for _, v in ipairs(t) do
			table.insert(verts, v)
		end
	end
	return verts
end

local function bounds(verts)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, v in ipairs(verts) do
		low = low:Min(v)
		high = high:Max(v)
	end
	return low, high
end

-- slices along Y: per slice, the horizontal span (max of X and Z extents) and the X/Z extents
local function slices(verts, count)
	local low, high = bounds(verts)
	local height = math.max(high.Y - low.Y, 1e-4)
	local bins = {}
	for i = 1, count do
		bins[i] = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge, sumX = 0, sumZ = 0, n = 0 }
	end
	for _, v in ipairs(verts) do
		local i = math.clamp(math.floor((v.Y - low.Y) / height * count) + 1, 1, count)
		local b = bins[i]
		b.minX = math.min(b.minX, v.X)
		b.maxX = math.max(b.maxX, v.X)
		b.minZ = math.min(b.minZ, v.Z)
		b.maxZ = math.max(b.maxZ, v.Z)
		b.sumX += v.X
		b.sumZ += v.Z
		b.n += 1
	end
	for i, b in ipairs(bins) do
		b.y = low.Y + (i - 0.5) / count * height
		b.spanX = if b.n > 0 then b.maxX - b.minX else 0
		b.spanZ = if b.n > 0 then b.maxZ - b.minZ else 0
		b.span = math.max(b.spanX, b.spanZ)
		b.cx = if b.n > 0 then b.sumX / b.n else 0
		b.cz = if b.n > 0 then b.sumZ / b.n else 0
	end
	return bins, low, high
end

local function rotateAll(verts, rotation)
	local out = table.create(#verts)
	for i, v in ipairs(verts) do
		out[i] = rotation:VectorToWorldSpace(v)
	end
	return out
end

-- turns the longest axis to +Y
local function lengthwise(size)
	if size.X >= size.Y and size.X >= size.Z then
		return CFrame.Angles(0, 0, math.rad(90))
	elseif size.Z >= size.Y and size.Z >= size.X then
		return CFrame.Angles(math.rad(-90), 0, 0)
	end
	return CFrame.identity
end

local function averageSpan(bins, from, to)
	local total, n = 0, 0
	for i = from, to do
		if bins[i].n > 0 then
			total += bins[i].span
			n += 1
		end
	end
	return if n > 0 then total / n else 0
end

-- Measures a long weapon and returns (rotation, gripPoint, attachments, scale) for gripModel.
local function measureLong(part, spec)
	local raw = vertices(part)
	local rotation = lengthwise(part.Size)
	local verts = rotateAll(raw, rotation)
	local count = 24
	local bins = slices(verts, count)
	-- flip so the business end is up
	local flip = false
	if spec.kind == "blade" then
		local widest, widestIndex = -1, 1
		for i, b in ipairs(bins) do
			if b.span > widest then
				widest, widestIndex = b.span, i
			end
		end
		flip = widestIndex > count / 2 -- the guard belongs in the lower half
	else
		flip = averageSpan(bins, 1, 6) > averageSpan(bins, count - 5, count) -- the head is the wider end
	end
	if flip then
		rotation = CFrame.Angles(math.rad(180), 0, 0) * rotation
		verts = rotateAll(raw, rotation)
		bins = slices(verts, count)
	end
	-- roll so the width of the business end lies along Z (the swing plane)
	local from = if spec.kind == "blade" then math.floor(count * 0.35) else count - 6
	local sx, sz = 0, 0
	for i = from, count do
		sx = math.max(sx, bins[i].spanX)
		sz = math.max(sz, bins[i].spanZ)
	end
	if sx > sz * 1.1 then
		rotation = CFrame.Angles(0, math.rad(90), 0) * rotation
		verts = rotateAll(raw, rotation)
		bins = slices(verts, count)
	end
	local low, high = bounds(verts)
	local length = high.Y - low.Y
	local scale = spec.length / length
	-- the grip
	local gripY, trailFromY
	if spec.kind == "blade" then
		local widest, guardY = -1, low.Y + length * 0.2
		for i = 1, math.floor(count / 2) do
			if bins[i].span > widest then
				widest, guardY = bins[i].span, bins[i].y
			end
		end
		gripY = (low.Y + guardY) / 2
		trailFromY = guardY + length * 0.15
	else
		gripY = low.Y + length * (spec.grip or 0.15)
		trailFromY = high.Y - length * 0.3
	end
	-- the haft's centre line at the grip
	local gx, gz, n = 0, 0, 0
	for _, b in ipairs(bins) do
		if math.abs(b.y - gripY) < length / count * 1.5 and b.n > 0 then
			gx += (b.minX + b.maxX) / 2
			gz += (b.minZ + b.maxZ) / 2
			n += 1
		end
	end
	if n > 0 then
		gx /= n
		gz /= n
	end
	-- everything in the rotated frame, scaled; gripModel wants the grip in the mesh's own (scaled) space
	local gripRotated = Vector3.new(gx, gripY, gz) * scale
	local gripPoint = rotation:VectorToObjectSpace(gripRotated)
	local attrs = {
		TipAttachment = Vector3.new(0, high.Y * scale - gripRotated.Y, 0),
		TrailBase = Vector3.new(0, trailFromY * scale - gripRotated.Y, 0),
		TrailTip = Vector3.new(0, high.Y * scale - gripRotated.Y, 0),
	}
	return rotation, gripPoint, attrs, scale
end

local function gripModel(name, part, gripPoint, rotation, attrs)
	local model = Instance.new("Model")
	model.Name = name
	local grip = holder("Grip")
	grip.Parent = model
	model.PrimaryPart = grip
	part.CFrame = CFrame.new(-(rotation:PointToWorldSpace(gripPoint))) * rotation
	part.Parent = model
	weld(grip, part)
	attachment(grip, "GripAttachment", Vector3.zero)
	for key, value in pairs(attrs or {}) do
		if typeof(value) == "Vector3" then
			attachment(grip, key, value)
		else
			model:SetAttribute(key, value)
		end
	end
	return model
end

local function buildLong(name, spec, mesh)
	local rotation, gripPoint, attrs, scale = measureLong(mesh, spec)
	local part = prepare(mesh, "Body")
	part.Size = mesh.Size * scale
	attrs.Subtype = name
	attrs.WeaponType = spec.family
	return gripModel(name, part, gripPoint * 1, rotation, attrs)
end

-- Bows: limbs upright, the grip at the middle of the limb, the string drawn tip to tip on the archer's side; the arrow
-- side (the bow's belly, away from the string) towards the grip's +Z, as the Hunting Bow and CombatFeedback expect.
local function buildBow(name, spec, mesh)
	local raw = vertices(mesh)
	local rotation = lengthwise(mesh.Size)
	local verts = rotateAll(raw, rotation)
	local low, high = bounds(verts)
	local length = high.Y - low.Y
	local function extreme(top)
		local best = nil
		for _, v in ipairs(verts) do
			if best == nil or (top and v.Y > best.Y) or (not top and v.Y < best.Y) then
				best = v
			end
		end
		return best
	end
	local tipTop, tipBottom = extreme(true), extreme(false)
	local midY = (low.Y + high.Y) / 2
	local mx, mz, n = 0, 0, 0
	for _, v in ipairs(verts) do
		if math.abs(v.Y - midY) < length * 0.04 then
			mx += v.X
			mz += v.Z
			n += 1
		end
	end
	local grip = if n > 0 then Vector3.new(mx / n, midY, mz / n) else Vector3.new(0, midY, 0)
	local chordMid = (tipTop + tipBottom) / 2
	local belly = Vector3.new(grip.X - chordMid.X, 0, grip.Z - chordMid.Z)
	if belly.Magnitude > 1e-3 then
		-- turn about Y so the belly points to +Z
		local angle = math.atan2(belly.X, belly.Z)
		local turn = CFrame.Angles(0, -angle, 0)
		rotation = turn * rotation
		grip = turn:VectorToWorldSpace(grip)
		tipTop = turn:VectorToWorldSpace(tipTop)
		tipBottom = turn:VectorToWorldSpace(tipBottom)
	end
	local scale = spec.length / length
	local part = prepare(mesh, "Limbs")
	part.Size = mesh.Size * scale
	local gripRotated = grip * scale
	local model = gripModel(name, part, rotation:VectorToObjectSpace(gripRotated), rotation, {
		Subtype = name, WeaponType = spec.family,
		TipAttachment = tipTop * scale - gripRotated,
	})
	-- the string, tip to tip (in the grip's space)
	local a, b = tipTop * scale - gripRotated, tipBottom * scale - gripRotated
	local stringPart = Instance.new("Part")
	stringPart.Name = "String"
	stringPart.Shape = Enum.PartType.Cylinder
	stringPart.Material = Enum.Material.SmoothPlastic
	stringPart.Color = Color3.fromRGB(225, 218, 200)
	stringPart.Size = Vector3.new((a - b).Magnitude, 0.05, 0.05)
	stringPart.CFrame = CFrame.lookAt((a + b) / 2, a) * CFrame.Angles(0, math.rad(90), 0)
	stringPart.CanCollide = false
	stringPart.CanQuery = false
	stringPart.CanTouch = false
	stringPart.Massless = true
	stringPart.Parent = model
	weld(model.Grip, stringPart)
	local nock = (a + b) / 2
	attachment(model.Grip, "NockAttachment", Vector3.new(nock.X, 0, nock.Z))
	return model
end

-- Crossbows: held in the off hand like a bow, so the stock runs along the grip's Z (the prod, at the front, towards +Z),
-- the prod across X; the hand under the fore-stock.
local function buildCrossbow(name, spec, mesh)
	local raw = vertices(mesh)
	local size = mesh.Size
	-- the stock is the longest axis, the prod the widest of the other two at the prod end
	local axes = { { v = Vector3.xAxis, s = size.X }, { v = Vector3.yAxis, s = size.Y }, { v = Vector3.zAxis, s = size.Z } }
	table.sort(axes, function(p, q)
		return p.s > q.s
	end)
	local stock, second, third = axes[1].v, axes[2].v, axes[3].v
	-- which end of the stock has the prod: the end whose vertices spread widest across `second`
	local lowProj, highProj = math.huge, -math.huge
	for _, v in ipairs(raw) do
		local p = v:Dot(stock)
		lowProj = math.min(lowProj, p)
		highProj = math.max(highProj, p)
	end
	local length = highProj - lowProj
	local function spreadNear(atHigh)
		local lo, hi = math.huge, -math.huge
		for _, v in ipairs(raw) do
			local p = v:Dot(stock)
			if (atHigh and p > highProj - length * 0.3) or (not atHigh and p < lowProj + length * 0.3) then
				local s = v:Dot(second)
				lo = math.min(lo, s)
				hi = math.max(hi, s)
			end
		end
		return hi - lo
	end
	local front = if spreadNear(true) >= spreadNear(false) then stock else -stock
	-- frame: Z = front, X = prod (second), Y = Z x X (kept right-handed)
	local x = second
	local y = front:Cross(x)
	if y:Dot(third) < 0 then
		x = -x
		y = front:Cross(x)
	end
	local rotation = CFrame.fromMatrix(Vector3.zero, x, y, front):Inverse()
	local verts = rotateAll(raw, rotation)
	local low, high = bounds(verts)
	local scale = spec.length / (high.Z - low.Z)
	-- the hand: 40% along the stock from the back, under its centre line
	local gz = low.Z + (high.Z - low.Z) * 0.4
	local gx, gy, n = 0, math.huge, 0
	for _, v in ipairs(verts) do
		if math.abs(v.Z - gz) < (high.Z - low.Z) * 0.05 then
			gx += v.X
			gy = math.min(gy, v.Y)
			n += 1
		end
	end
	gx = if n > 0 then gx / n else 0
	if gy == math.huge then
		gy = low.Y
	end
	local gripRotated = Vector3.new(gx, gy + 0.08 / scale, gz) * scale
	local part = prepare(mesh, "Body")
	part.Size = mesh.Size * scale
	local model = gripModel(name, part, rotation:VectorToObjectSpace(gripRotated), rotation, {
		Subtype = name, WeaponType = spec.family,
		TipAttachment = Vector3.new(0, 0, high.Z * scale - gripRotated.Z),
	})
	attachment(model.Grip, "NockAttachment", Vector3.new(0, (high.Y + low.Y) / 2 * scale - gripRotated.Y, (low.Z + (high.Z - low.Z) * 0.55) * scale - gripRotated.Z))
	return model
end

-- Catalysts (orbs, crystals, foci): held upright above the hand; the grip at the bottom of the holder.
local function buildOrb(name, spec, mesh)
	local raw = vertices(mesh)
	local low, high = bounds(raw)
	local scale = spec.length / math.max(mesh.Size.Y, mesh.Size.X, mesh.Size.Z)
	local gripRotated = Vector3.new((low.X + high.X) / 2, low.Y + (high.Y - low.Y) * 0.15, (low.Z + high.Z) / 2) * scale
	local part = prepare(mesh, "Body")
	part.Size = mesh.Size * scale
	return gripModel(name, part, gripRotated, CFrame.identity, {
		Subtype = name, WeaponType = spec.family,
		TipAttachment = Vector3.new(0, high.Y * scale - gripRotated.Y, 0),
		FocusAttachment = Vector3.new(0, (low.Y + (high.Y - low.Y) * 0.75) * scale - gripRotated.Y, 0),
	})
end

-- Fist gloves (claws, gauntlets, bracers): like the Worn Knuckles, worn over the hand: fingers (generated up) turned
-- down the hand with the Fist grip (pitch -90); the hand's centre (the lower 40% of the mesh) lands at hand (0, -0.2, -0.05).
local function buildGlove(name, spec, mesh)
	local raw = vertices(mesh)
	local low, high = bounds(raw)
	local scale = spec.length / math.max(mesh.Size.Y, 0.01)
	local cx, cy, cz, n = 0, 0, 0, 0
	for _, v in ipairs(raw) do
		if v.Y < low.Y + (high.Y - low.Y) * 0.4 then
			cx += v.X
			cy += v.Y
			cz += v.Z
			n += 1
		end
	end
	local handCentre = (if n > 0 then Vector3.new(cx / n, cy / n, cz / n) else Vector3.zero) * scale
	local part = prepare(mesh, "Body")
	part.Size = mesh.Size * scale
	-- gripPoint = P - R^-1 * c, with c = (0, -0.15, -0.05) in grip space and R = Rx(-90)
	local gripPoint = handCentre + Vector3.new(0, -0.05, 0.15)
	return gripModel(name, part, gripPoint, CFrame.Angles(math.rad(-90), 0, 0), {
		Subtype = name, WeaponType = spec.family,
		TipAttachment = Vector3.new(0, 0.1, -0.3),
	})
end

local function buildShield(name, spec, mesh)
	local s = spec.height / mesh.Size.Y
	local plate = prepare(mesh, "Plate")
	plate.Size = mesh.Size * s
	local model = Instance.new("Model")
	model.Name = name
	local handle = holder("Handle", Vector3.new(0.3, 0.3, 0.3))
	handle.Parent = model
	model.PrimaryPart = handle
	-- face (boss) at -Z, as generated and as the Oak Shield; back pushed clear of the forearm (Models.shieldGrip)
	plate.CFrame = CFrame.new(0, 0, -(plate.Size.Z / 2 - 0.11))
	plate.Parent = model
	weld(handle, plate)
	attachment(handle, "FaceAttachment", Vector3.new(0, 0, -plate.Size.Z + 0.11))
	model:SetAttribute("Subtype", name)
	model:SetAttribute("WeaponType", "Shield")
	return model
end

local function buildArmor(weight, slot, mesh)
	local spec = SubtypeBuilder.ARMOR_SLOTS[slot]
	local part = prepare(mesh, "Handle")
	part.Size = spec.size
	local model = Instance.new("Model")
	model.Name = slot
	part.Parent = model
	model.PrimaryPart = part
	model:SetAttribute("ArmorWeight", weight)
	model:SetAttribute("Slot", slot)
	if string.find(spec.parts, ",", 1, true) then
		model:SetAttribute("BodyParts", spec.parts)
	else
		model:SetAttribute("BodyPart", spec.parts)
	end
	model:SetAttribute("Offset", spec.offset)
	-- the width of the body part it was fitted to (Models.applyArmor scales to the wearer's)
	local reference = { Head = 1.2, UpperTorso = 1.94, LeftLowerArm = 1, RightLowerArm = 1, LeftUpperLeg = 1, RightUpperLeg = 1, LeftLowerLeg = 1, RightLowerLeg = 1 }
	local first = string.match(spec.parts, "[^,]+")
	model:SetAttribute("ReferenceWidth", reference[first] or 1)
	if spec.hidesHair then
		model:SetAttribute("HidesHair", true)
	end
	return model
end

function SubtypeBuilder.build()
	local assets = folder(game.ReplicatedStorage, "Assets")
	local subtypes = folder(assets, "Subtypes")
	local sets = folder(assets, "ArmorSets")
	local built, missing, failed = {}, {}, {}
	local function put(parent, model)
		local old = parent:FindFirstChild(model.Name)
		if old then
			old:Destroy()
		end
		model.Parent = parent
	end
	for name, spec in pairs(SubtypeBuilder.WEAPONS) do
		local ok, err = pcall(function()
			if spec.kind == "library" then
				local own = assets.Weapons:FindFirstChild(spec.source)
				if own == nil then
					table.insert(missing, name)
					return
				end
				local copy = own:Clone()
				copy.Name = name
				copy:SetAttribute("ItemId", nil)
				copy:SetAttribute("Subtype", name)
				put(subtypes, copy)
				table.insert(built, name)
				return
			end
			local mesh = sourceMesh(spec.source or ("Sub_" .. name))
			if mesh == nil then
				table.insert(missing, name)
				return
			end
			local model
			if spec.kind == "bow" then
				model = buildBow(name, spec, mesh)
			elseif spec.kind == "crossbow" then
				model = buildCrossbow(name, spec, mesh)
			elseif spec.kind == "orb" then
				model = buildOrb(name, spec, mesh)
			elseif spec.kind == "glove" then
				model = buildGlove(name, spec, mesh)
			else
				model = buildLong(name, spec, mesh)
			end
			put(subtypes, model)
			table.insert(built, name)
		end)
		if not ok then
			table.insert(failed, name .. ": " .. tostring(err))
		end
	end
	for name, spec in pairs(SubtypeBuilder.SHIELDS) do
		local mesh = sourceMesh(spec.source or ("Sub_" .. name))
		if mesh == nil then
			table.insert(missing, name)
		else
			put(subtypes, buildShield(name, spec, mesh))
			table.insert(built, name)
		end
	end
	for _, weight in ipairs({ "Light", "Medium", "Heavy" }) do
		local weightFolder = folder(sets, weight)
		for slot in pairs(SubtypeBuilder.ARMOR_SLOTS) do
			local mesh = sourceMesh("Armor_" .. weight .. "_" .. slot)
			if mesh == nil then
				table.insert(missing, weight .. "/" .. slot)
			else
				put(weightFolder, buildArmor(weight, slot, mesh))
				table.insert(built, weight .. "/" .. slot)
			end
		end
	end
	table.sort(built)
	table.sort(missing)
	return string.format("built %d: %s\nmissing %d: %s\nfailed %d: %s", #built, table.concat(built, ", "), #missing, table.concat(missing, ", "), #failed, table.concat(failed, "; "))
end

return SubtypeBuilder
