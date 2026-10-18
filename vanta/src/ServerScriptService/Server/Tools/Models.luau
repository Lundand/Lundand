--!strict
-- Placeholder models until the art pass (L-41): standard R15 bodies for NPCs and human enemies, a part-built
-- wolf, and part-built weapons. Gameplay never depends on how these look.
local Players = game:GetService("Players")

local Models = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Clothing colours by NPC or enemy, in the district palettes of docs/ART_DIRECTION.md.
Models.palettes = {
	TheKing = { torso = rgb(28, 38, 72), legs = rgb(20, 26, 48) },
	ChurchPriest = { torso = rgb(230, 225, 210), legs = rgb(200, 190, 170) },
	WearyStranger = { torso = rgb(110, 90, 70), legs = rgb(80, 75, 70) },
	Clothier = { torso = rgb(90, 60, 130), legs = rgb(60, 60, 75) },
	ForgeMaster = { torso = rgb(95, 65, 40), legs = rgb(50, 40, 35) },
	GuildRegistrar = { torso = rgb(60, 85, 60), legs = rgb(55, 50, 45) },
	AlleyThief = { torso = rgb(40, 38, 46), legs = rgb(30, 28, 34), skin = rgb(190, 150, 120) },
}

local function weldAll(model: Model, root: BasePart)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

local function piece(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = CFrame.new(offset)
	part.Parent = model
	return part
end

-- A standard R15 body without name or health labels (L-42). Yields while Roblox builds it.
function Models.humanoid(palette: any?): Model
	local description = Instance.new("HumanoidDescription")
	local skin = (palette and palette.skin) or rgb(214, 170, 135)
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = (palette and palette.torso) or rgb(80, 70, 60)
	description.LeftLegColor = (palette and palette.legs) or rgb(55, 50, 45)
	description.RightLegColor = (palette and palette.legs) or rgb(55, 50, 45)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	local humanoid: any = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	return model
end

function Models.wolf(): Model
	local model = Instance.new("Model")
	local fur, dark = rgb(120, 115, 110), rgb(70, 65, 62)
	local root = piece(model, "HumanoidRootPart", Vector3.new(1.6, 1.4, 3.2), Vector3.zero, fur, Enum.Material.SmoothPlastic)
	root.Massless = false
	piece(model, "Head", Vector3.new(1.1, 1.0, 1.2), Vector3.new(0, 0.5, -2.0), fur, Enum.Material.SmoothPlastic)
	piece(model, "Snout", Vector3.new(0.6, 0.5, 0.8), Vector3.new(0, 0.3, -2.9), dark, Enum.Material.SmoothPlastic)
	piece(model, "Tail", Vector3.new(0.3, 0.3, 1.2), Vector3.new(0, 0.4, 2.1), dark, Enum.Material.SmoothPlastic)
	for _, x in ipairs({ -0.55, 0.55 }) do
		for _, z in ipairs({ -1.1, 1.1 }) do
			piece(model, "Leg", Vector3.new(0.4, 1.2, 0.4), Vector3.new(x, -1.2, z), dark, Enum.Material.SmoothPlastic)
		end
	end
	weldAll(model, root)
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 1.1
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	return model
end

-- Item-specific models from the asset library (ReplicatedStorage.Assets.Weapons.<itemId>) are used when one exists; they follow
-- the same grip convention as the part-built shapes below (PrimaryPart "Grip" in the hand, +Y towards the tip).
local function libraryModel(folderName: string, itemId: string?): Model?
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild(folderName)
	local asset = itemId and library and library:FindFirstChild(itemId)
	if asset ~= nil and asset:IsA("Model") then
		return asset:Clone()
	end
	return nil
end

-- An item without its own model can still look right: its subtype (equipment.subtype, one of Config.Gear's weapon subtypes
-- or shield types) has a model in ReplicatedStorage.Assets.Subtypes. Lookup order everywhere: the item's own model, its
-- subtype's model, the part-built placeholder.
local function subtypeModel(itemId: string?): Model?
	if itemId == nil then
		return nil
	end
	local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
	local def = Content.items[itemId]
	local subtype = def and def.equipment and def.equipment.subtype
	return if type(subtype) == "string" then libraryModel("Subtypes", subtype) else nil
end

-- Weapons are built along +Y from the grip; callers weld the grip into a hand.
function Models.weapon(weaponType: string, itemId: string?): Model?
	local fromLibrary = libraryModel("Weapons", itemId) or subtypeModel(itemId)
	if fromLibrary ~= nil then
		fromLibrary.Name = "Weapon"
		return fromLibrary
	end
	local model = Instance.new("Model")
	model.Name = "Weapon"
	local gold, steel = rgb(200, 170, 90), rgb(190, 195, 205)
	local grip = piece(model, "Grip", Vector3.new(0.25, 0.9, 0.25), Vector3.zero, rgb(70, 45, 30), Enum.Material.Wood)
	if weaponType == "Sword" then
		piece(model, "Guard", Vector3.new(1.0, 0.15, 0.3), Vector3.new(0, 0.5, 0), gold, Enum.Material.Metal)
		piece(model, "Blade", Vector3.new(0.3, 3.4, 0.08), Vector3.new(0, 2.27, 0), steel, Enum.Material.Metal)
		piece(model, "Pommel", Vector3.new(0.3, 0.25, 0.3), Vector3.new(0, -0.55, 0), gold, Enum.Material.Metal)
	elseif weaponType == "Greatsword" then
		piece(model, "Guard", Vector3.new(1.5, 0.2, 0.36), Vector3.new(0, 0.55, 0), gold, Enum.Material.Metal)
		piece(model, "Blade", Vector3.new(0.5, 4.6, 0.1), Vector3.new(0, 3.0, 0), steel, Enum.Material.Metal)
		piece(model, "Pommel", Vector3.new(0.4, 0.3, 0.4), Vector3.new(0, -0.6, 0), gold, Enum.Material.Metal)
	elseif weaponType == "Pickaxe" or weaponType == "Hatchet" then
		model:Destroy()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Presentation.ToolProps).build(weaponType)
	elseif weaponType == "Knife" then
		piece(model, "Blade", Vector3.new(0.2, 1.1, 0.06), Vector3.new(0, 1.0, 0), steel, Enum.Material.Metal)
	elseif weaponType == "Staff" or weaponType == "Wand" then
		-- Placeholder: a long shaft with a glowing focus at the top.
		local long = weaponType == "Staff"
		piece(model, "Shaft", Vector3.new(0.22, long and 4.6 or 1.2, 0.22), Vector3.new(0, long and 1.3 or 0.6, 0), rgb(90, 60, 38), Enum.Material.Wood)
		piece(model, "Focus", Vector3.new(0.45, 0.45, 0.45), Vector3.new(0, long and 3.75 or 1.35, 0), rgb(150, 120, 255), Enum.Material.Neon)
	elseif weaponType == "Mace" then
		piece(model, "Haft", Vector3.new(0.2, 1.8, 0.2), Vector3.new(0, 1.2, 0), rgb(90, 60, 38), Enum.Material.Wood)
		piece(model, "Head", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 2.3, 0), steel, Enum.Material.Metal)
	elseif weaponType == "Bow" or weaponType == "Crossbow" then
		piece(model, "Limb", Vector3.new(0.15, 4.2, 0.25), Vector3.new(0, 0.6, 0), rgb(110, 75, 45), Enum.Material.Wood)
		piece(model, "String", Vector3.new(0.04, 4.0, 0.04), Vector3.new(0, 0.6, -0.5), rgb(230, 225, 210), Enum.Material.SmoothPlastic)
	elseif weaponType == "Dagger" then
		piece(model, "Guard", Vector3.new(0.6, 0.12, 0.2), Vector3.new(0, 0.5, 0), gold, Enum.Material.Metal)
		piece(model, "Blade", Vector3.new(0.3, 1.8, 0.08), Vector3.new(0, 1.45, 0), steel, Enum.Material.Metal)
	elseif weaponType == "Fist" then
		piece(model, "Knuckles", Vector3.new(0.5, 0.35, 0.6), Vector3.new(0, 0.1, 0), steel, Enum.Material.Metal)
	elseif weaponType == "Greataxe" then
		piece(model, "Haft", Vector3.new(0.25, 4.2, 0.25), Vector3.new(0, 1.6, 0), rgb(90, 60, 38), Enum.Material.Wood)
		piece(model, "Blade", Vector3.new(0.15, 1.6, 1.6), Vector3.new(0, 3.3, 0.6), steel, Enum.Material.Metal)
	elseif weaponType == "Spear" then
		piece(model, "Shaft", Vector3.new(0.18, 6.0, 0.18), Vector3.new(0, 2.2, 0), rgb(90, 60, 38), Enum.Material.Wood)
		piece(model, "Point", Vector3.new(0.3, 0.9, 0.08), Vector3.new(0, 5.6, 0), steel, Enum.Material.Metal)
	else
		model:Destroy()
		return nil
	end
	weldAll(model, grip)
	model.PrimaryPart = grip
	return model
end

-- Grips: where each weapon sits in the hand and how it is turned. The animations are authored against these, so change them
-- together. Pitch -135 points a blade (or staff, or spear) forward and up in a guard pose and level in a thrust. Daggers are
-- held reverse-grip, one in each hand, the blade along the forearm; fists are a pair of knuckle guards; a bow sits in the left
-- hand, upright, with the string towards the archer (the right hand draws it).
local function pitch(degrees: number): CFrame
	return CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(degrees), 0, 0)
end
local BOW_GRIP = CFrame.new(0, -0.15, -0.2) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
Models.grips = {
	Sword = { cf = pitch(-135) },
	Staff = { cf = pitch(-135) },
	Wand = { cf = pitch(-135) },
	Mace = { cf = pitch(-135) },
	Spear = { cf = pitch(-135) },
	Greataxe = { cf = pitch(-135) },
	Greatsword = { cf = pitch(-135) },
	Pickaxe = { cf = pitch(-135) },
	Hatchet = { cf = pitch(-135) },
	Dagger = { cf = CFrame.new(0, -0.1, 0.7), pair = true },
	Fist = { cf = pitch(-90), pair = true },
	Bow = { hand = "Left", cf = BOW_GRIP },
	Crossbow = { hand = "Left", cf = BOW_GRIP },
}

-- Puts a weapon in a character's hand (offsets need tuning in Studio).
function Models.equipWeapon(character: Model, weaponType: string, itemId: string?): boolean
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	local oldOffhand = character:FindFirstChild("OffhandWeapon")
	if oldOffhand then
		oldOffhand:Destroy()
	end
	local weapon = Models.weapon(weaponType, itemId)
	local grip = Models.grips[weaponType] or { cf = pitch(-90) }
	local holder = character:FindFirstChild((grip.hand or "Right") .. "Hand")
	if holder == nil or not holder:IsA("BasePart") or weapon == nil then
		return false
	end
	local function attach(model: Model, hand: BasePart)
		model:PivotTo(hand.CFrame * grip.cf)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = model.PrimaryPart
		weld.Parent = model.PrimaryPart
		model.Parent = character
	end
	attach(weapon, holder)
	if grip.pair then
		local leftHand = character:FindFirstChild("LeftHand")
		local second = Models.weapon(weaponType, itemId)
		if leftHand ~= nil and leftHand:IsA("BasePart") and second ~= nil then
			second.Name = "OffhandWeapon"
			attach(second, leftHand)
		end
	end
	return true
end

-- A round-cornered wooden shield strapped to the left forearm, face outwards (placeholder art).
Models.shieldGrip = CFrame.new(0, 0.05, -0.75)
-- A shield item with a library model (ReplicatedStorage.Assets.Weapons.<itemId>, PrimaryPart "Handle" at its centre, face at -Z)
-- is shown instead of the placeholder.
function Models.equipShield(character: Model, itemId: string?): boolean
	local old = character:FindFirstChild("Shield")
	if old then
		old:Destroy()
	end
	local arm = character:FindFirstChild("LeftLowerArm")
	if arm == nil or not arm:IsA("BasePart") then
		return false
	end
	local fromLibrary = libraryModel("Weapons", itemId) or subtypeModel(itemId)
	if fromLibrary ~= nil and fromLibrary.PrimaryPart ~= nil then
		fromLibrary.Name = "Shield"
		fromLibrary:PivotTo(arm.CFrame * Models.shieldGrip)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = arm
		weld.Part1 = fromLibrary.PrimaryPart
		weld.Parent = fromLibrary.PrimaryPart
		fromLibrary.Parent = character
		return true
	end
	local model = Instance.new("Model")
	model.Name = "Shield"
	local plate = piece(model, "Plate", Vector3.new(2.1, 2.7, 0.22), Vector3.zero, rgb(110, 75, 45), Enum.Material.Wood)
	piece(model, "Boss", Vector3.new(0.8, 0.8, 0.3), Vector3.new(0, 0, -0.12), rgb(190, 195, 205), Enum.Material.Metal)
	piece(model, "RimTop", Vector3.new(2.1, 0.14, 0.3), Vector3.new(0, 1.35, 0), rgb(190, 195, 205), Enum.Material.Metal)
	piece(model, "RimBottom", Vector3.new(2.1, 0.14, 0.3), Vector3.new(0, -1.35, 0), rgb(190, 195, 205), Enum.Material.Metal)
	weldAll(model, plate)
	model.PrimaryPart = plate
	model:PivotTo(arm.CFrame * Models.shieldGrip)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = plate
	weld.Parent = plate
	model.Parent = character
	return true
end

-- Worn armor (helmets, chest pieces...): models from ReplicatedStorage.Assets.Armor.<itemId>, welded to the body part they name
-- (attribute BodyPart) at their Offset, scaled to the wearer's body part (ReferenceWidth = the width they were fitted to).
-- Pieces marked HidesHair hide hair and hat accessories while worn. Items without a model are simply not shown.
function Models.applyArmor(character: Model, itemIds: {string})
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute("ArmorPiece") then
			child:Destroy()
		end
	end
	local hideHair = false
	-- the pieces an item puts on: its own model, or (without one) the armor set piece for its weight and slot
	-- (ReplicatedStorage.Assets.ArmorSets.<Weight>.<Slot>). Set pieces for paired slots name both body parts
	-- (attribute BodyParts, e.g. "LeftHand,RightHand") and are worn on each.
	local function piecesFor(itemId: string): { Model }
		local own = libraryModel("Armor", itemId)
		if own ~= nil then
			return { own }
		end
		local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Content)
		local def = Content.items[itemId]
		local equipment = def and def.equipment
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		local sets = assets and assets:FindFirstChild("ArmorSets")
		local weight = equipment and sets and sets:FindFirstChild(tostring(equipment.armorWeight))
		local template = weight and weight:FindFirstChild(tostring(equipment.slot))
		if template == nil or not template:IsA("Model") then
			return {}
		end
		local pieces = {}
		local parts = template:GetAttribute("BodyParts")
		if type(parts) == "string" then
			for name in string.gmatch(parts, "[^,]+") do
				local copy = template:Clone()
				copy:SetAttribute("BodyPart", name)
				table.insert(pieces, copy)
			end
		else
			table.insert(pieces, template:Clone())
		end
		return pieces
	end
	for _, itemId in ipairs(itemIds) do
	  for index, piece in ipairs(piecesFor(itemId)) do
		local bodyPart = character:FindFirstChild(piece:GetAttribute("BodyPart") or "")
		if bodyPart ~= nil and bodyPart:IsA("BasePart") and piece.PrimaryPart ~= nil then
			local scale = bodyPart.Size.X / (piece:GetAttribute("ReferenceWidth") or bodyPart.Size.X)
			piece:ScaleTo(scale)
			local offset: CFrame = piece:GetAttribute("Offset") or CFrame.identity
			piece:PivotTo(bodyPart.CFrame * (offset.Rotation + offset.Position * scale))
			for _, part in ipairs(piece:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = false
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.Massless = true
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = bodyPart
					weld.Part1 = part
					weld.Parent = part
				end
			end
			piece.Name = if index == 1 then "Armor_" .. itemId else "Armor_" .. itemId .. "_" .. index
			piece:SetAttribute("ArmorPiece", true)
			piece.Parent = character
			hideHair = hideHair or piece:GetAttribute("HidesHair") == true
		else
			piece:Destroy()
		end
	  end
	end
	character:SetAttribute("ArmorHidesHair", hideHair or nil)
	local function shade(accessory: Instance)
		if not accessory:IsA("Accessory") then
			return
		end
		local kind = accessory.AccessoryType
		if kind ~= Enum.AccessoryType.Hair and kind ~= Enum.AccessoryType.Hat then
			return
		end
		local handle = accessory:FindFirstChild("Handle")
		if handle ~= nil and handle:IsA("BasePart") then
			if character:GetAttribute("ArmorHidesHair") then
				if handle:GetAttribute("ShownTransparency") == nil then
					handle:SetAttribute("ShownTransparency", handle.Transparency)
				end
				handle.Transparency = 1
			elseif handle:GetAttribute("ShownTransparency") ~= nil then
				handle.Transparency = handle:GetAttribute("ShownTransparency")
				handle:SetAttribute("ShownTransparency", nil)
			end
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		shade(child)
	end
	if not character:GetAttribute("ArmorWatch") then
		-- hair added later (appearance applied after the armor) is hidden too
		character:SetAttribute("ArmorWatch", true)
		character.ChildAdded:Connect(function(child: Instance)
			task.defer(shade, child)
		end)
	end
end

-- Rarity on worn and held gear (asset pass): the better the item, the more it shows. Common is plain; Uncommon glints;
-- Rare shimmers; Epic sheds drifting motes and a soft light; Legendary rises with gold embers and a warmer light. Colours
-- are the game's rarity colours (Config.Gear.rarityColors). The model also carries a Rarity attribute (swing trails tint
-- by it). Emitters sit on each visible part, scaled by its size so big armor and small daggers read alike.
-- haze: a soft coloured glow clinging to the item (big faint particles), from Rare up
local RARITY_LOOK = {
	Uncommon = { rate = 5, size = 0.2, lifetime = 0.7, speed = 0.2, light = 0, haze = 0 },
	Rare = { rate = 10, size = 0.24, lifetime = 0.9, speed = 0.4, light = 0.5, haze = 5 },
	Epic = { rate = 11, size = 0.24, lifetime = 1.0, speed = 0.8, light = 0.8, haze = 6 },
	Legendary = { rate = 16, size = 0.28, lifetime = 1.3, speed = 1.4, light = 1.2, haze = 9 },
}
function Models.applyRarity(model: Instance?, rarity: string?)
	if model == nil then
		return
	end
	for _, old in ipairs(model:GetDescendants()) do
		if old.Name == "RarityGlint" or old.Name == "RarityLight" then
			old:Destroy()
		end
	end
	model:SetAttribute("Rarity", rarity)
	local look = rarity and RARITY_LOOK[rarity]
	if look == nil then
		return
	end
	local Gear = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.Gear)
	local c = Gear.rarityColors[rarity :: string]
	local color = Color3.fromRGB(c[1], c[2], c[3])
	local pale = color:Lerp(Color3.new(1, 1, 1), 0.5)
	local largest: BasePart? = nil
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			local e = Instance.new("ParticleEmitter")
			e.Name = "RarityGlint"
			e.Color = ColorSequence.new(pale, color)
			e.LightEmission = 0.7
			e.LightInfluence = 0.3
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, look.size), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.15, 1)
			e.Lifetime = NumberRange.new(look.lifetime * 0.6, look.lifetime)
			e.Speed = NumberRange.new(look.speed * 0.5, look.speed)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = Vector3.new(0, if rarity == "Legendary" then 1.5 else 0.3, 0)
			e.Rate = look.rate * math.clamp(volume / 1.5, 0.4, 2.5)
			e.LockedToPart = false
			e.Parent = part
			if look.haze > 0 then
				local haze = Instance.new("ParticleEmitter")
				haze.Name = "RarityGlint"
				haze.Color = ColorSequence.new(color)
				haze.LightEmission = 0.8
				haze.LightInfluence = 0
				haze.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 0.9) })
				haze.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) })
				haze.Lifetime = NumberRange.new(0.5, 0.9)
				haze.Speed = NumberRange.new(0, 0.2)
				haze.Rate = look.haze * math.clamp(volume / 1.5, 0.4, 2.5)
				haze.LockedToPart = true
				haze.Parent = part
			end
			if largest == nil or volume > (largest :: BasePart).Size.X * (largest :: BasePart).Size.Y * (largest :: BasePart).Size.Z then
				largest = part
			end
		end
	end
	if look.light > 0 and largest ~= nil then
		local light = Instance.new("PointLight")
		light.Name = "RarityLight"
		light.Color = color
		light.Brightness = look.light
		light.Range = if rarity == "Legendary" then 7 else 5
		light.Shadows = false
		light.Parent = largest
	end
end

function Models.removeShield(character: Model)
	local old = character:FindFirstChild("Shield")
	if old then
		old:Destroy()
	end
end

return Models
