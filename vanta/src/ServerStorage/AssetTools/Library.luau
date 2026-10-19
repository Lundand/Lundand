--!nonstrict
-- Authoring tool: builds ReplicatedStorage.Assets from the source meshes in ServerStorage.AssetSources (AI-generated, published
-- MeshParts). Every asset is normalised to the conventions the game already uses, so it drops into the existing systems:
--   Weapons / Tools: PrimaryPart "Grip" (invisible) sits in the hand; its +Y points along the blade or shaft towards the tip, exactly
--     like the old part-built models (Server.Tools.Models), so Models.grips and every animation keep working. Attachments on Grip:
--     GripAttachment (the hand), TipAttachment, and TrailBase/TrailTip on blades, NockAttachment on bows.
--   Projectiles: PrimaryPart "Root" at the centre, flight direction = Root's -Z (CFrame.lookAt convention); TrailFront/TrailBack.
--   Armor: PrimaryPart "Handle"; attributes BodyPart, Offset (CFrame from the body part's centre) and ReferenceWidth (the body
--     part width the piece was fitted to; it is scaled to the wearer's own).
--   Resource nodes: PrimaryPart is the rock; the pivot is at the base centre so it sits on the ground.
--   Items (materials, consumables): PrimaryPart is the mesh, pivot at the centre, longest side 1.2 studs (for previews and icons).
-- Run:  <fresh copy of this module>.build()
local Library = {}

local SOURCES = game.ServerStorage.AssetSources

local function sourceMesh(name, partName)
	local model = SOURCES:FindFirstChild(name)
	assert(model, "missing source " .. name)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") and (partName == nil or d.Name == partName) then
			return d
		end
	end
	error("no mesh in " .. name)
end

local function prepare(mesh, name, scale)
	local part = mesh:Clone()
	for _, child in ipairs(part:GetChildren()) do
		if not child:IsA("SurfaceAppearance") then child:Destroy() end
	end
	part.Name = name
	part.Size = mesh.Size * scale
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	return part
end

local function holder(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(0.25, 0.9, 0.25)
	p.Transparency = 1
	p.Anchored = false
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

-- `gripPoint`: the hand's position in the (scaled) mesh's own space; `rotation`: how the mesh is turned inside the grip frame.
local function gripModel(name, meshes, gripPoint, rotation, attrs)
	local model = Instance.new("Model")
	model.Name = name
	local grip = holder("Grip")
	grip.Parent = model
	model.PrimaryPart = grip
	local meshFrame = CFrame.new(-(rotation:PointToWorldSpace(gripPoint))) * rotation
	for _, entry in ipairs(meshes) do
		local part = entry.part
		part.CFrame = meshFrame * (entry.offset or CFrame.identity)
		part.Parent = model
		weld(grip, part)
	end
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

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
	if f == nil then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function put(parentFolder, model)
	local old = parentFolder:FindFirstChild(model.Name)
	if old then old:Destroy() end
	model.Parent = parentFolder
end

function Library.build()
	local assets = folder(game.ReplicatedStorage, "Assets")
	local weapons = folder(assets, "Weapons")
	local tools = folder(assets, "Tools")
	local armor = folder(assets, "Armor")
	local projectiles = folder(assets, "Projectiles")
	local resources = folder(assets, "ResourceNodes")
	local materials = folder(assets, "Materials")
	local consumables = folder(assets, "Consumables")
	local report = {}

	-- TrainingSword: source 2.86 tall, tip up; guard at y -0.62, grip centre y -1.02 (source units). Scaled to 4.2 long.
	do
		local s = 4.2 / 2.857
		local blade = prepare(sourceMesh("TrainingSword"), "Sword", s)
		-- rolled 90 degrees about the blade so the edges face the cut (up/down in guard) instead of lying flat; the blade line,
		-- and so every animation, is unchanged
		put(weapons, gripModel("TrainingSword", { { part = blade } }, Vector3.new(0, -1.02 * s, 0), CFrame.Angles(0, math.rad(90), 0), {
			ItemId = "TrainingSword", WeaponType = "Sword",
			TrailBase = Vector3.new(0, (-0.45 + 1.02) * s, 0), TrailTip = Vector3.new(0, (1.43 + 1.02) * s, 0), TipAttachment = Vector3.new(0, (1.43 + 1.02) * s, 0),
		}))
		table.insert(report, "Weapons/TrainingSword")
	end

	-- HuntingBow: limbs + string; string side faces the archer (-Z), the hand on the far side of the limbs, limbs along +Y.
	do
		local limbsSource = sourceMesh("HuntingBow", "bow limbs and grip")
		local stringSource = sourceMesh("HuntingBow", "bowstring")
		local limbs = prepare(limbsSource, "Limbs", 1)
		local bowstring = prepare(stringSource, "String", 1)
		local stringOffset = limbsSource.CFrame:ToObjectSpace(stringSource.CFrame)
		local gripPoint = Vector3.new(limbsSource.Size.X / 2 - 0.06, 0, 0)
		local rotation = CFrame.Angles(0, math.rad(-90), 0)
		local model = gripModel("HuntingBow", { { part = limbs }, { part = bowstring, offset = stringOffset } }, gripPoint, rotation, {
			ItemId = "HuntingBow", WeaponType = "Bow",
			TipAttachment = Vector3.new(0, limbsSource.Size.Y / 2, 0),
		})
		local nock = (CFrame.new(-(rotation:PointToWorldSpace(gripPoint))) * rotation * stringOffset).Position
		attachment(model.Grip, "NockAttachment", Vector3.new(nock.X, 0, nock.Z))
		put(weapons, model)
		table.insert(report, ("Weapons/HuntingBow (string %.2f studs behind the hand)"):format(-nock.Z))
	end

	-- CopperPickaxe: source 0.60 tall, head on top spanning X with the spike at +X; handle offset to +X; grip wrap at the bottom.
	-- Turned so the head spans Z with the spike forward (-Z), as the gathering animation swings it. Scaled to 3.4 tall.
	do
		local s = 3.4 / 0.5958
		local pick = prepare(sourceMesh("CopperPickaxe"), "Pickaxe", s)
		put(tools, gripModel("CopperPickaxe", { { part = pick } }, Vector3.new(0.035 * s, -0.22 * s, 0), CFrame.Angles(0, math.rad(90), 0), {
			ItemId = "CopperPickaxe", ToolType = "Pickaxe",
			TipAttachment = Vector3.new(0, (0.28 + 0.22) * s, -0.2 * s),
		}))
		table.insert(report, "Tools/CopperPickaxe")
	end

	-- Projectiles: Root at the centre, flying along Root's -Z; the mesh's +Y (the point) turned to -Z.
	local function projectile(name, sourceName, length, sourceLength)
		local s = length / sourceLength
		local model = Instance.new("Model")
		model.Name = name
		local root = holder("Root", Vector3.new(0.2, 0.2, 0.2))
		root.Parent = model
		model.PrimaryPart = root
		local mesh = prepare(sourceMesh(sourceName), "Body", s)
		mesh.CFrame = CFrame.Angles(math.rad(-90), 0, 0)
		mesh.Parent = model
		weld(root, mesh)
		attachment(root, "TrailFront", Vector3.new(0, 0, -length * 0.25))
		attachment(root, "TrailBack", Vector3.new(0, 0, length * 0.5))
		attachment(root, "Tip", Vector3.new(0, 0, -length / 2))
		model:SetAttribute("Length", length)
		return model, root, mesh
	end
	do
		local model, root = projectile("Arrow", "Arrow", 2.6, 0.22)
		-- a faint streak behind the arrow in flight
		local trail = Instance.new("Trail")
		trail.Attachment0 = root.TrailFront
		trail.Attachment1 = root.TrailBack
		trail.Lifetime = 0.12
		trail.Color = ColorSequence.new(Color3.fromRGB(235, 228, 210))
		trail.Transparency = NumberSequence.new(0.55, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.FaceCamera = true
		trail.Parent = root
		put(projectiles, model)
		table.insert(report, "Projectiles/Arrow")
	end
	do
		local model, root, mesh = projectile("ArcaneBolt", "ArcaneBolt", 1.6, 0.45)
		local violet = Color3.fromRGB(150, 120, 255)
		local trail = Instance.new("Trail")
		trail.Attachment0 = root.TrailFront
		trail.Attachment1 = root.TrailBack
		trail.Lifetime = 0.25
		trail.Color = ColorSequence.new(Color3.fromRGB(190, 170, 255), violet)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.LightEmission = 0.6
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.FaceCamera = true
		trail.Parent = root
		local motes = Instance.new("ParticleEmitter")
		motes.Name = "Motes"
		motes.Color = ColorSequence.new(Color3.fromRGB(205, 190, 255), violet)
		motes.LightEmission = 0.7
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new(0.2, 1)
		motes.Lifetime = NumberRange.new(0.25, 0.45)
		motes.Rate = 40
		motes.Speed = NumberRange.new(0.5, 1.5)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Parent = root.TrailBack
		local light = Instance.new("PointLight")
		light.Color = violet
		light.Brightness = 1.2
		light.Range = 7
		light.Parent = root
		put(projectiles, model)
		table.insert(report, "Projectiles/ArcaneBolt")
	end

	-- Spell projectiles per magic family (Shared.Presentation.SpellEffects.bolt picks them). Sources point their front up (+Y),
	-- which projectile() turns to the flight direction (-Z). Each gets a trail in its family colour; particles are added in flight.
	for _, spec in ipairs({
		{ "BoltHoly", 2.4, Color3.fromRGB(255, 235, 190), Color3.fromRGB(235, 195, 110), 0.5 },
		{ "BoltSoul", 1.8, Color3.fromRGB(215, 245, 230), Color3.fromRGB(130, 200, 170), 0.45 },
		{ "BoltAbyss", 1.6, Color3.fromRGB(190, 120, 255), Color3.fromRGB(45, 25, 70), 0.2 },
		{ "BoltAstral", 2.6, Color3.fromRGB(225, 235, 255), Color3.fromRGB(80, 110, 210), 0.55 },
		{ "BoltThorn", 1.8, Color3.fromRGB(200, 230, 150), Color3.fromRGB(90, 130, 70), 0 },
		{ "BoltTime", 1.0, Color3.fromRGB(200, 245, 235), Color3.fromRGB(70, 175, 170), 0.4 },
	}) do
		local name, length, front, back, glow = spec[1], spec[2], spec[3], spec[4], spec[5]
		local source = sourceMesh(name)
		local model, root = projectile(name, name, length, source.Size.Y)
		local trail = Instance.new("Trail")
		trail.Attachment0 = root.TrailFront
		trail.Attachment1 = root.TrailBack
		trail.Lifetime = 0.22
		trail.Color = ColorSequence.new(front, back)
		trail.Transparency = NumberSequence.new(0.35, 1)
		trail.LightEmission = glow
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.FaceCamera = true
		trail.Parent = root
		put(projectiles, model)
		table.insert(report, "Projectiles/" .. name)
	end

	-- IronHelm: worn on the Head; fitted to a head 1.2 studs wide, sitting slightly high so the brim clears the eyes.
	do
		local helm = prepare(sourceMesh("IronHelm"), "Handle", 1.12)
		local model = Instance.new("Model")
		model.Name = "IronHelm"
		helm.Parent = model
		model.PrimaryPart = helm
		model:SetAttribute("ItemId", "IronHelm")
		model:SetAttribute("BodyPart", "Head")
		model:SetAttribute("Offset", CFrame.new(0, 0.18, 0.02))
		model:SetAttribute("ReferenceWidth", 1.2)
		model:SetAttribute("HidesHair", true)
		put(armor, model)
		table.insert(report, "Armor/IronHelm")
	end

	-- CopperVein node: pivot at the base centre.
	do
		local rock = prepare(sourceMesh("CopperVein"), "Rock", 1.45)
		rock.Anchored = true
		rock.CanCollide = true
		rock.CanQuery = true
		rock.Massless = false
		rock.CFrame = CFrame.new(0, rock.Size.Y / 2, 0)
		local model = Instance.new("Model")
		model.Name = "CopperVein"
		rock.Parent = model
		model.PrimaryPart = rock
		rock.PivotOffset = CFrame.new(0, -rock.Size.Y / 2, 0) -- pivot at the base (WorldPivot doesn't stick once a PrimaryPart is set)
		model:SetAttribute("NodeType", "CopperVein")
		put(resources, model)
		table.insert(report, "ResourceNodes/CopperVein")
	end

	-- Items: centred, longest side 1.2 studs.
	local function item(targetFolder, name)
		local source = sourceMesh(name)
		local longest = math.max(source.Size.X, source.Size.Y, source.Size.Z)
		local part = prepare(source, "Body", 1.2 / longest)
		part.CFrame = CFrame.identity
		local model = Instance.new("Model")
		model.Name = name
		part.Parent = model
		model.PrimaryPart = part
		model:SetAttribute("ItemId", name)
		put(targetFolder, model)
		table.insert(report, targetFolder.Name .. "/" .. name)
	end
	item(materials, "CopperOre")
	item(materials, "ScrapMetal")
	item(consumables, "MinorHealthPotion")

	-- Phase 2 ------------------------------------------------------------------------------------------------------------
	-- Straight weapons, tip up in the source. `length`: the finished length; `gripY`: the grip centre's height in source units;
	-- `tipY`: the tip's height; `trailFromY`: where the swing trail starts along the blade or head (source units).
	local function straightWeapon(name, weaponType, length, gripY, tipY, trailFromY, extra, rotation)
		local source = sourceMesh(name)
		local s = length / source.Size.Y
		local part = prepare(source, "Body", s)
		local attrs = {
			ItemId = name, WeaponType = weaponType,
			TipAttachment = Vector3.new(0, (tipY - gripY) * s, 0),
			TrailBase = Vector3.new(0, (trailFromY - gripY) * s, 0), TrailTip = Vector3.new(0, (tipY - gripY) * s, 0),
		}
		for key, value in pairs(extra or {}) do
			attrs[key] = value
		end
		local model = gripModel(name, { { part = part } }, Vector3.new(0, gripY * s, 0), rotation or CFrame.identity, attrs)
		put(weapons, model)
		table.insert(report, "Weapons/" .. name)
		return model, s
	end
	-- measured source profiles (see ASSET_BATCH2_REPORT.md): guard/grip/tip heights in source units
	straightWeapon("SignetBlade", "Sword", 4.2, -1.1, 1.59, -0.55, nil, CFrame.Angles(0, math.rad(90), 0)) -- edges facing the cut, like TrainingSword
	straightWeapon("RustyDagger", "Dagger", 2.6, -0.5, 0.715, -0.15)
	straightWeapon("FangDagger", "Dagger", 2.6, -0.42, 0.67, 0)
	do
		local model, s = straightWeapon("ApprenticeStaff", "Staff", 5.0, -0.9, 1.93, 1.2)
		attachment(model.Grip, "FocusAttachment", Vector3.new(0, (1.6 + 0.9) * s, 0)) -- the crystal between the prongs
	end
	do
		local model, s = straightWeapon("TrainingMace", "Mace", 3.1, -0.6, 0.97, 0.4)
		attachment(model.Grip, "HeadAttachment", Vector3.new(0, (0.65 + 0.6) * s, 0))
	end
	straightWeapon("IronSpear", "Spear", 6.85, -2.39, 3.12, 2.0)

	-- IronGreataxe: double-bit head across the source X at the top; turned so the bits face forward and back (-Z / +Z of the grip).
	do
		local source = sourceMesh("IronGreataxe")
		local s = 4.6 / source.Size.Y
		local part = prepare(source, "Body", s)
		put(weapons, gripModel("IronGreataxe", { { part = part } }, Vector3.new(0, -0.28 * s, 0), CFrame.Angles(0, math.rad(90), 0), {
			ItemId = "IronGreataxe", WeaponType = "Greataxe",
			TipAttachment = Vector3.new(0, (0.355 + 0.28) * s, 0),
			TrailBase = Vector3.new(0, (0.12 + 0.28) * s, -0.2 * s), TrailTip = Vector3.new(0, (0.36 + 0.28) * s, -0.2 * s),
		}))
		table.insert(report, "Weapons/IronGreataxe")
	end

	-- WornKnuckles: a hand wrap with a plate; the source has the fingers at +Y. Held with the Fist grip (pitch -90), the grip's -Z
	-- runs down the hand towards the fingers (hand -Y) and its +Y is the hand's front (hand -Z): turned Rx(-90) and centred at hand
	-- (0, -0.2, -0.05), just below the hand's centre,
	-- stretched over the blocky R15 hand (0.98 x 0.32 x 1.03).
	do
		local source = sourceMesh("WornKnuckles")
		local part = prepare(source, "Body", 1)
		part.Size = Vector3.new(1.0, 0.8, 0.75)
		put(weapons, gripModel("WornKnuckles", { { part = part } }, Vector3.new(0, -0.05, 0.15), CFrame.Angles(math.rad(-90), 0, 0), {
			ItemId = "WornKnuckles", WeaponType = "Fist",
			TipAttachment = Vector3.new(0, 0.1, -0.3), -- the knuckles (the striking point), hand (0, -0.45, -0.3)
		}))
		table.insert(report, "Weapons/WornKnuckles")
	end

	-- OakShield: boss (front) at -Z in the source, as the old shield faced. PrimaryPart "Handle" at the shield's centre; strapped
	-- to the left forearm with Models.shieldGrip (0, 0.05, -0.75), so the mesh is pushed out until its back sits clear of the arm.
	do
		local s = 2.7 / sourceMesh("OakShield").Size.Y
		local plate = prepare(sourceMesh("OakShield"), "Plate", s)
		local model = Instance.new("Model")
		model.Name = "OakShield"
		local handle = holder("Handle", Vector3.new(0.3, 0.3, 0.3))
		handle.Parent = model
		model.PrimaryPart = handle
		plate.CFrame = CFrame.new(0, 0, -(plate.Size.Z / 2 - 0.11))
		plate.Parent = model
		weld(handle, plate)
		attachment(handle, "FaceAttachment", Vector3.new(0, 0, -plate.Size.Z + 0.11))
		model:SetAttribute("ItemId", "OakShield")
		model:SetAttribute("WeaponType", "Shield")
		put(weapons, model)
		table.insert(report, "Weapons/OakShield")
	end

	-- Tools (gathering props): head turned to face forward along the grip's -Z, like the CopperPickaxe.
	local function toolModel(name, toolType, length, gripX, gripY, topY, frontX)
		local source = sourceMesh(name)
		local s = length / source.Size.Y
		local part = prepare(source, "Body", s)
		put(tools, gripModel(name, { { part = part } }, Vector3.new(gripX * s, gripY * s, 0), CFrame.Angles(0, math.rad(90), 0), {
			ItemId = name, ToolType = toolType,
			TipAttachment = Vector3.new(0, (topY - gripY) * s, -frontX * s),
		}))
		table.insert(report, "Tools/" .. name)
	end
	toolModel("IronPickaxe", "Pickaxe", 3.4, 0.03, -1.05, 1.43, 0.8)
	toolModel("CopperHatchet", "Hatchet", 2.8, 0, -0.85, 1.1, 0.6)

	-- Chest armor: hollow shells fitted (non-uniformly) over the blocky R15 torso. Welded to UpperTorso (1.94 x 1.70 x 1.00;
	-- LowerTorso below it ends 1.25 under its centre). `size`: the fitted bounding box; `centreY`: its centre below UpperTorso's.
	local function chestArmor(name, size, centreY)
		local part = prepare(sourceMesh(name), "Handle", 1)
		part.Size = size
		local model = Instance.new("Model")
		model.Name = name
		part.Parent = model
		model.PrimaryPart = part
		model:SetAttribute("ItemId", name)
		model:SetAttribute("BodyPart", "UpperTorso")
		model:SetAttribute("Offset", CFrame.new(0, centreY, 0))
		model:SetAttribute("ReferenceWidth", 1.94)
		put(armor, model)
		table.insert(report, "Armor/" .. name)
	end
	chestArmor("LeatherJerkin", Vector3.new(3.3, 2.25, 1.43), -0.175) -- shoulders to the belt
	chestArmor("ApprenticeRobe", Vector3.new(3.2, 3.35, 1.64), -0.73) -- shoulders to the knees

	-- Resource nodes: pivot at the base centre. Walk-through plants are not collidable.
	local function node(name, scale, collidable, mainName)
		local part = prepare(sourceMesh(name), mainName or "Rock", scale)
		part.Anchored = true
		part.CanCollide = collidable
		part.CanQuery = true
		part.Massless = false
		part.CFrame = CFrame.new(0, part.Size.Y / 2, 0)
		local model = Instance.new("Model")
		model.Name = name
		part.Parent = model
		model.PrimaryPart = part
		part.PivotOffset = CFrame.new(0, -part.Size.Y / 2, 0) -- pivot at the base (WorldPivot doesn't stick once a PrimaryPart is set)
		model:SetAttribute("NodeType", name)
		put(resources, model)
		table.insert(report, ("ResourceNodes/%s (%.1f x %.1f x %.1f)"):format(name, part.Size.X, part.Size.Y, part.Size.Z))
	end
	node("IronVein", 1.15, true)
	node("SilverVein", 1.2, true)
	node("OakTree", 1.3, true, "Trunk")
	node("HealingHerbPatch", 1.5, false, "Herb")
	node("CaveMushroomCluster", 1.4, false, "Mushrooms")

	-- Phase 3: inventory models for every remaining material and the legendary class books (same item convention: centred,
	-- longest side 1.2). The development-only LegendaryBookPlaceholder gets no model.
	for _, name in ipairs({ "IronOre", "SilverOre", "OakLog", "HealingHerb", "CaveMushroom", "BoarHide", "WolfPelt", "WolfFang", "AlphaFang", "LeatherScraps", "LeaderSignet" }) do
		item(materials, name)
	end
	local books = folder(assets, "ClassBooks")
	-- Effects: meshes the spell effects use (Shared.Presentation.SpellEffects). Root: a gnarled root tendril, pivot at its base,
	-- 4 studs tall, rising out of the ground for the nature family's eruption.
	do
		local effects = folder(assets, "Effects")
		local source = sourceMesh("SpellRoot")
		local part = prepare(source, "Body", 4 / source.Size.Y)
		part.CastShadow = true
		part.CFrame = CFrame.new(0, part.Size.Y / 2, 0)
		local model = Instance.new("Model")
		model.Name = "Root"
		part.Parent = model
		model.PrimaryPart = part
		part.PivotOffset = CFrame.new(0, -part.Size.Y / 2, 0) -- pivot at the base (WorldPivot doesn't stick once a PrimaryPart is set)
		put(effects, model)
		table.insert(report, "Effects/Root")
	end
	for _, name in ipairs({
		"AbyssalWarlockBook", "AstralArchmageBook", "BladeEmperorBook", "ChronomancerBook", "DragonbloodKnightBook", "LichLordBook", "NightSovereignBook",
		"SeraphicGuardianBook", "ThunderSovereignBook", "VoidSwordmasterBook", "WorldbreakerBerserkerBook", "WorldrootSageBook",
	}) do
		item(books, name)
	end

	return table.concat(report, "\n")
end

return Library
