--!strict
-- Cross-checks every shared config table, so content mistakes fail a test instead of breaking play.
local Check = require(script.Parent.Parent.Util.Check)
local Curve = require(script.Parent.Curve)
local ItemRegistry = require(script.Parent.ItemRegistry)

local ConfigValidation = {}

local MASTERY_EVENTS = { Hit = true, PerfectParry = true, ComboFinished = true, Kill = true, DrillCompleted = true }

local function curveMax(curve: any): number
	if Curve.validate(curve) then
		return Curve.maxLevel(curve)
	end
	return 0
end

function ConfigValidation.validate(content: any): {string}
	local problems = {}
	local function add(label: string, message: string)
		table.insert(problems, label .. ": " .. message)
	end
	local function curve(label: string, spec: any)
		local ok, err = Curve.validate(spec)
		if not ok then
			add(label, "curve " .. tostring(err))
		end
	end

	-- Stats
	local stats = content.stats
	for _, statId in ipairs(stats.order) do
		if stats.definitions[statId] == nil then
			add("stats", "order lists unknown stat " .. statId)
		end
	end
	for statId in pairs(stats.definitions) do
		if not table.find(stats.order, statId) then
			add("stats", statId .. " is missing from order")
		end
		for effect, perPoint in pairs(stats.effectsPerPoint[statId] or {}) do
			if stats.baseValues[effect] == nil then
				add("stats", "effect " .. effect .. " has no base value")
			end
			if not Check.isFiniteNumber(perPoint) then
				add("stats", "effect " .. effect .. " needs a number")
			end
		end
	end
	if not Check.isNonNegativeInteger(stats.pointsPerLevel) or not Check.isNonNegativeInteger(stats.startingPoints) then
		add("stats", "points must be non-negative whole numbers")
	end

	-- Character progression and the catch-up bonus
	local progression = content.progression
	curve("progression", progression.characterCurve)
	local catchUp = progression.legendaryCatchUp
	if type(catchUp.enabled) ~= "boolean" then
		add("progression", "legendaryCatchUp.enabled must be true or false")
	end
	if not Check.isFiniteNumber(catchUp.startMultiplier) or not Check.isFiniteNumber(catchUp.endMultiplier) or catchUp.endMultiplier < 1 or catchUp.startMultiplier < catchUp.endMultiplier then
		add("progression", "catch-up multipliers must satisfy start >= end >= 1")
	end
	if not Check.isPositiveInteger(catchUp.untilLevel) or catchUp.untilLevel > curveMax(progression.characterCurve) then
		add("progression", "catch-up untilLevel must be a level that exists")
	end

	-- Disciplines
	for key, def in pairs(content.disciplines) do
		local label = "discipline " .. tostring(key)
		if def.id ~= key then
			add(label, "id must match its key")
		end
		curve(label, def.curve)
		local maxRank = curveMax(def.curve)
		for techniqueId, technique in pairs(def.techniques) do
			if not Check.isPositiveInteger(technique.rank) or technique.rank > maxRank then
				add(label, "technique " .. techniqueId .. " has an invalid rank")
			end
			for _, milestoneId in ipairs(technique.milestones or {}) do
				if def.milestones[milestoneId] == nil then
					add(label, "technique " .. techniqueId .. " needs unknown milestone " .. milestoneId)
				end
			end
		end
		for milestoneId, milestone in pairs(def.milestones) do
			if not MASTERY_EVENTS[milestone.event] then
				add(label, "milestone " .. milestoneId .. " uses an unknown event")
			end
			if not Check.isPositiveInteger(milestone.count) or not Check.isNonNegativeInteger(milestone.rewardXp or 0) then
				add(label, "milestone " .. milestoneId .. " needs a positive count and whole-number reward")
			end
			if milestone.drillId ~= nil and def.drills[milestone.drillId] == nil then
				add(label, "milestone " .. milestoneId .. " uses an unknown drill")
			end
		end
		for event, xp in pairs(def.xpSources) do
			if not MASTERY_EVENTS[event] or event == "DrillCompleted" then
				add(label, "xp source " .. tostring(event) .. " must be a combat event")
			end
			if not Check.isFiniteNumber(xp) or xp < 0 then
				add(label, "xp source " .. tostring(event) .. " needs a non-negative number")
			end
		end
		for drillId, drill in pairs(def.drills) do
			if not Check.isNonNegativeInteger(drill.firstXp) or not Check.isNonNegativeInteger(drill.repeatXp) or not Check.isNonNegativeInteger(drill.repeatsPerDay) then
				add(label, "drill " .. drillId .. " needs non-negative whole numbers")
			end
		end
	end

	-- Classes
	for key, def in pairs(content.classes) do
		local label = "class " .. tostring(key)
		if def.id ~= key then
			add(label, "id must match its key")
		end
		if not table.find(content.rarity.classTiers or content.rarity.order, def.rarity) then
			add(label, "unknown rarity")
		elseif def.rarity == "Legendary" then
			if def.awakeningWeight ~= nil then
				add(label, "legendary classes cannot be in the awakening pool")
			end
		elseif not Check.isPositiveInteger(def.awakeningWeight) then
			add(label, "awakening classes need a positive awakeningWeight")
		end
		for disciplineId, grant in pairs(def.disciplines) do
			local discipline = content.disciplines[disciplineId]
			if discipline == nil then
				add(label, "grants unknown discipline " .. disciplineId)
			elseif not Check.isPositiveInteger(grant.maxRank) or grant.maxRank > curveMax(discipline.curve) then
				add(label, "invalid rank ceiling for " .. disciplineId)
			end
		end
		for unlockId, unlock in pairs(def.classUnlocks or {}) do
			local level = unlock.requires and unlock.requires.characterLevel
			if level ~= nil and not Check.isPositiveInteger(level) then
				add(label, "unlock " .. unlockId .. " needs a whole-number level")
			end
		end
	end

	-- Professions
	for key, def in pairs(content.professions) do
		local label = "profession " .. tostring(key)
		if def.id ~= key then
			add(label, "id must match its key")
		end
		if def.kind ~= "Gathering" and def.kind ~= "Crafting" then
			add(label, "kind must be Gathering or Crafting")
		end
		curve(label, def.curve)
		local seen = {}
		for _, unlock in ipairs(def.unlocks) do
			if not Check.isIdentifier(unlock.id) or seen[unlock.id] then
				add(label, "unlock IDs must be unique identifiers")
			end
			seen[unlock.id] = true
			if not Check.isPositiveInteger(unlock.level) or unlock.level > curveMax(def.curve) then
				add(label, "unlock " .. tostring(unlock.id) .. " has an invalid level")
			end
		end
	end

	-- Items, currencies, products
	for _, message in ipairs(ItemRegistry.validate(content.items, content.classes, content.rarity)) do
		table.insert(problems, message)
	end
	for key, currency in pairs(content.currencies) do
		if currency.id ~= key or not Check.isPositiveInteger(currency.max) then
			add("currency " .. tostring(key), "needs a matching id and a positive max")
		end
	end
	for key, product in pairs(content.products) do
		local label = "product " .. tostring(key)
		if product.id ~= key or not Check.isNonNegativeInteger(product.productId) or type(product.enabled) ~= "boolean" then
			add(label, "needs a matching id, a productId and an enabled flag")
		end
		if product.enabled and product.productId == 0 then
			add(label, "enabled products need a real productId")
		end
		if product.kind == "Cosmetic" then
			if not Check.isIdentifier(product.entitlementId) then
				add(label, "cosmetics need an entitlementId")
			end
		elseif product.kind == "RiftDonation" then
			-- Voluntary community donations grant nothing in play (L-36, L-47); checked with the Rift events.
		else
			add(label, "only cosmetic products may be sold (L-33, No Pay-to-Win)")
		end
	end
	for _, quality in ipairs(content.quality.order) do
		if not Check.isIdentifier(quality) then
			add("quality", "grades must be identifiers")
		end
	end

	-- Crafting (L-31)
	local previousMin = -1000000
	for _, entry in ipairs(content.crafting.quality.grades) do
		if not table.find(content.quality.order, entry.grade) or not Check.isFiniteNumber(entry.min) or entry.min <= previousMin then
			add("crafting", "quality grades must be known grades with increasing minimums")
		elseif Check.isFiniteNumber(entry.min) then
			previousMin = entry.min
		end
	end
	for key, recipe in pairs(content.recipes) do
		local label = "recipe " .. tostring(key)
		local profession = content.professions[recipe.profession]
		if recipe.id ~= key or profession == nil or profession.kind ~= "Crafting" then
			add(label, "needs a matching id and a crafting profession")
		end
		if not Check.isIdentifier(recipe.process) or not Check.isPositiveInteger(recipe.minProfessionLevel) or type(recipe.learned) ~= "boolean" then
			add(label, "needs a process, a minimum level and a learned flag")
		end
		for _, input in ipairs(recipe.inputs) do
			local def = content.items[input.itemId]
			if def == nil or ItemRegistry.isUnique(def) or not Check.isPositiveInteger(input.amount) then
				add(label, "inputs must be known stackable items with positive amounts")
			end
		end
		if content.items[recipe.output.itemId] == nil or not Check.isPositiveInteger(recipe.output.amount) then
			add(label, "output must be a known item with a positive amount")
		end
		if not Check.isNonNegativeInteger(recipe.professionXp) then
			add(label, "professionXp must be a whole number")
		end
	end
	local facilityKinds = { Npc = true, PlayerWorkshop = true, GuildFacility = true }
	for key, facility in pairs(content.facilities) do
		local label = "facility " .. tostring(key)
		if facility.id ~= key or not facilityKinds[facility.kind] then
			add(label, "needs a matching id and a known kind")
		end
		if content.world.locations[facility.locationId] == nil then
			add(label, "is placed at an unknown location")
		end
		for recipeId in pairs(facility.recipes or {}) do
			local recipe = content.recipes[recipeId]
			if recipe == nil or not facility.processes[recipe.process] then
				add(label, "offers recipe " .. tostring(recipeId) .. " it cannot make")
			end
		end
		if not Check.isNonNegativeInteger(facility.fee) or not Check.isFiniteNumber(facility.qualityBonus) or facility.qualityBonus < 0 then
			add(label, "fee and qualityBonus must be non-negative")
		end
		if facility.unlockQuest ~= nil and not Check.isIdentifier(facility.unlockQuest) then
			add(label, "unlockQuest must be an identifier")
		end
	end

	-- World (L-27 to L-30)
	local world = content.world
	for key, location in pairs(world.locations) do
		local label = "location " .. tostring(key)
		if location.id ~= key or world.districts[location.district] == nil then
			add(label, "needs a matching id and a known district")
		end
		if location.kind == "CraftingFacility" and content.facilities[location.facilityId] == nil then
			add(label, "points to an unknown facility")
		end
		if location.kind == "NpcGuild" and world.npcGuilds[location.guildId] == nil then
			add(label, "points to an unknown NPC guild")
		end
		if location.leadsTo ~= nil and world.regions[location.leadsTo] == nil then
			add(label, "leads to an unknown region")
		end
	end
	for key, property in pairs(world.properties) do
		local knownKind = content.propertyRules.limitsPerPlayer[property.kind] ~= nil or property.kind == content.propertyRules.guildHall.kind
		if property.id ~= key or world.districts[property.district] == nil or not knownKind then
			add("property " .. tostring(key), "needs a matching id, a known district and a kind from Config/PropertyRules")
		end
	end
	local propertyRules = content.propertyRules
	if propertyRules.limitsPerPlayer.House ~= 1 then
		add("property rules", "the house limit is one per player (L-28)")
	end
	for key, property in pairs(world.properties) do
		if not Check.isPositiveInteger(propertyRules.pricesByTier[property.tier]) then
			add("property " .. tostring(key), "has no price for its tier")
		end
	end
	for key, guild in pairs(world.npcGuilds) do
		if guild.id ~= key or world.locations[guild.locationId] == nil then
			add("npc guild " .. tostring(key), "needs a matching id and a known location")
		end
	end
	for key, inn in pairs(world.inns) do
		if inn.id ~= key or world.locations[inn.locationId] == nil then
			add("inn " .. tostring(key), "needs a matching id and a known location")
		end
		if not Check.isPositiveInteger(inn.pricePerDay) or type(inn.room) ~= "table" or not Check.isPositiveInteger(inn.room[1]) or not Check.isPositiveInteger(inn.room[2]) then
			add("inn " .. tostring(key), "needs a room size and a price per day")
		end
	end

	-- Quests (L-30)
	local objectiveKinds = { Talk = true, Gather = true, Kill = true, Craft = true, Deliver = true }
	for key, quest in pairs(content.quests) do
		local label = "quest " .. tostring(key)
		if quest.id ~= key or content.npcs[quest.giver] == nil then
			add(label, "needs a matching id and a known giver")
		end
		for _, questId in ipairs((quest.requires and quest.requires.quests) or {}) do
			if content.quests[questId] == nil then
				add(label, "requires unknown quest " .. tostring(questId))
			end
		end
		local seen = {}
		for _, objective in ipairs(quest.objectives) do
			local valid = objectiveKinds[objective.kind] == true and Check.isIdentifier(objective.id) and not seen[objective.id] and Check.isPositiveInteger(objective.count)
			if objective.kind == "Talk" and content.npcs[objective.target] == nil then
				valid = false
			elseif (objective.kind == "Gather" or objective.kind == "Deliver") and content.items[objective.target] == nil then
				valid = false
			elseif objective.kind == "Craft" and content.recipes[objective.target] == nil then
				valid = false
			elseif objective.kind == "Kill" and content.enemies[objective.target] == nil then
				valid = false
			end
			if not valid then
				add(label, "objective " .. tostring(objective.id) .. " is invalid")
			end
			seen[objective.id] = true
		end
		local rewards = quest.rewards or {}
		if not Check.isNonNegativeInteger(rewards.gold or 0) or not Check.isNonNegativeInteger(rewards.characterXp or 0) then
			add(label, "gold and XP rewards must be whole numbers")
		end
		for professionId, xp in pairs(rewards.professionXp or {}) do
			if content.professions[professionId] == nil or not Check.isPositiveInteger(xp) then
				add(label, "invalid profession XP reward")
			end
		end
		for _, reward in ipairs(rewards.items or {}) do
			if content.items[reward.itemId] == nil or not Check.isPositiveInteger(reward.amount) then
				add(label, "invalid item reward")
			end
		end
		if quest.repeatCooldownSeconds ~= nil and not Check.isPositiveInteger(quest.repeatCooldownSeconds) then
			add(label, "repeat cooldown must be a positive whole number")
		end
	end
	for key, facility in pairs(content.facilities) do
		if facility.unlockQuest ~= nil and content.quests[facility.unlockQuest] == nil then
			add("facility " .. tostring(key), "is unlocked by an unknown quest")
		end
	end

	-- Quest journal text, guidance and story-flag requirements (L-44)
	for key, quest in pairs(content.quests) do
		local label = "quest " .. tostring(key)
		if type(quest.description) ~= "string" or quest.description == "" then
			add(label, "needs a description for the journal")
		end
		if quest.guidance ~= nil and (world.locations[quest.guidance.locationId] == nil or not Check.isPositiveInteger(quest.guidance.seconds)) then
			add(label, "guidance needs a known location and a duration")
		end
		local guildXp = quest.rewards and quest.rewards.guildXp
		if guildXp ~= nil and (not Check.isPositiveInteger(guildXp) or not (quest.requires and quest.requires.inGuild)) then
			add(label, "guild XP rewards need a positive amount and a guild membership requirement")
		end
		for _, flag in ipairs((quest.requires and quest.requires.flags) or {}) do
			if not Check.isIdentifier(flag) then
				add(label, "required flags must be identifiers")
			end
		end
	end

	-- Enemies, rotating quests, character slots and starting weapons (L-43 to L-45)
	for key, enemy in pairs(content.enemies) do
		if enemy.id ~= key or type(enemy.displayName) ~= "string" or not Check.isPositiveInteger(enemy.level) or not Check.isPositiveInteger(enemy.maxHealth) or not Check.isNonNegativeInteger(enemy.xp) then
			add("enemy " .. tostring(key), "needs an id, a name, a level, health and XP")
		end
	end
	for key, pool in pairs(content.questPools) do
		if pool.id ~= key or content.npcs[pool.giver] == nil or not Check.isPositiveInteger(pool.count) then
			add("quest pool " .. tostring(key), "needs a matching id, a known giver and a count")
		end
		for _, questId in ipairs(pool.quests) do
			local quest = content.quests[questId]
			if quest == nil or quest.repeatCooldownSeconds == nil or quest.main then
				add("quest pool " .. tostring(key), "only repeatable side quests can rotate: " .. tostring(questId))
			end
		end
	end
	local slots = content.characterSlots
	if not Check.isPositiveInteger(slots.baseSlots) or not Check.isPositiveInteger(slots.maxSlots) or slots.baseSlots > slots.maxSlots or not Check.isPositiveInteger(slots.deletionConfirmSeconds) or not Check.isNonNegativeInteger(slots.deleteWaitSeconds) then
		add("character slots", "need base and maximum slots and a confirmation time")
	end
	for _, unlock in ipairs(slots.unlocks) do
		if not Check.isIdentifier(unlock.id) or not Check.isPositiveInteger(unlock.atLevel) then
			add("character slots", "each unlock needs an id and a level")
		end
	end
	for key, def in pairs(content.classes) do
		if (def.awakeningWeight or 0) > 0 and def.rarity ~= "Legendary" then
			local weapon = def.startingWeapon and content.items[def.startingWeapon]
			if not weapon or weapon.kind ~= "Equipment" or weapon.equipment == nil or weapon.equipment.weaponType == nil then
				add("class " .. tostring(key), "needs a starting weapon (L-43)")
			else
				for _, other in pairs(content.items) do
					if other.kind == "Equipment" and other.equipment and other.equipment.weaponType == weapon.equipment.weaponType and other.tier < weapon.tier then
						add("class " .. tostring(key), "starting weapon must be the weakest of its type (L-43)")
					end
				end
			end
		end
	end

	-- Cosmetic catalogue (L-46): looks only, priced, time limits only
	local cosmetics = content.cosmetics
	local productOwners = {}
	local function claimProductId(owner: string, productId: any)
		if Check.isPositiveInteger(productId) then
			if productOwners[productId] ~= nil then
				add(owner, "shares developer product " .. tostring(productId) .. " with " .. productOwners[productId])
			end
			productOwners[productId] = owner
		end
	end
	for key, item in pairs(cosmetics.items) do
		local label = "cosmetic " .. tostring(key)
		if item.id ~= key or type(item.displayName) ~= "string" or type(item.description) ~= "string" or table.find(cosmetics.categories, item.category) == nil then
			add(label, "needs a matching id, a name, a description and a known category")
		end
		if not Check.isPositiveInteger(item.price) or not Check.isNonNegativeInteger(item.productId) or (item.status ~= "Active" and item.status ~= "Retired") then
			add(label, "needs a Robux price, a product id (0 until created) and a status")
		end
		if item.quantity ~= nil or item.stock ~= nil then
			add(label, "limited quantities are not supported (L-46)")
		end
		if item.endsAt ~= nil and (not Check.isPositiveInteger(item.endsAt) or (item.startsAt ~= nil and item.endsAt <= item.startsAt)) then
			add(label, "endsAt must come after startsAt")
		end
		if item.category == "WeaponSkin" and type(item.weaponType) ~= "string" then
			add(label, "weapon skins need a weapon type")
		end
		for _, classId in ipairs(item.classes or {}) do
			if content.classes[classId] == nil then
				add(label, "unknown class " .. tostring(classId))
			end
		end
		for _, field in ipairs({ "stats", "xpBonus", "dropBonus", "luck" }) do
			if item[field] ~= nil then
				add(label, "cosmetics can't have gameplay effects (L-33)")
			end
		end
		claimProductId(label, item.productId)
	end

	-- Rift events and donation tiers (L-47)
	local rift = content.riftEvents
	if rift.events[rift.activeEventId] == nil or not Check.isPositiveInteger(rift.shardCount) then
		add("rift events", "need a known active event and a shard count")
	end
	for key, event in pairs(rift.events) do
		if event.id ~= key or not Check.isPositiveInteger(event.target) or not Check.isPositiveInteger(event.openHours) or not Check.isPositiveInteger(event.runsPerPlayer) then
			add("rift event " .. tostring(key), "needs a target, open hours and runs per player")
		end
	end
	for key, product in pairs(content.products) do
		if product.kind == "RiftDonation" and (not Check.isPositiveInteger(product.robux) or product.robux > rift.maxDonationRobux) then
			add("product " .. tostring(key), "donations need a Robux amount up to " .. tostring(rift.maxDonationRobux))
		end
		claimProductId("product " .. tostring(key), product.productId)
	end

	-- Guild economy (L-48)
	local guilds = content.guilds
	if not Check.isNonNegativeInteger(guilds.creationCost) or not Check.isPositiveInteger(guilds.minLeaderLevel) or not Check.isPositiveInteger(guilds.hallRequiredLevel) then
		add("guilds", "need a founding cost, a founder level and a hall level")
	end
	if table.find(guilds.taxRates, 0) == nil then
		add("guild tax", "0% must always be offered")
	end
	for _, rate in ipairs(guilds.taxRates) do
		if not Check.isNonNegativeInteger(rate) or rate > 100 then
			add("guild tax", "rates are whole percentages")
		end
	end
	for index, threshold in ipairs(guilds.levelThresholds) do
		if not Check.isPositiveInteger(threshold) or (index > 1 and threshold <= guilds.levelThresholds[index - 1]) then
			add("guild levels", "thresholds must rise")
		end
	end
	if guilds.hallStages[1].level ~= 1 or #guilds.maintenance.costByStage ~= #guilds.hallStages then
		add("guild halls", "stages start at level 1 and each needs an upkeep cost")
	end
	for key, upgrade in pairs(guilds.upgrades) do
		if upgrade.id ~= key or not Check.isPositiveInteger(upgrade.cost) or not Check.isPositiveInteger(upgrade.requiredLevel) or (upgrade.requires ~= nil and guilds.upgrades[upgrade.requires] == nil) then
			add("guild upgrade " .. tostring(key), "needs a cost, a level and a known prerequisite")
		end
	end

	-- NPC vendors (L-12): basics only
	for key, vendor in pairs(content.vendors) do
		if vendor.id ~= key or content.npcs[vendor.npc] == nil then
			add("vendor " .. tostring(key), "needs a matching id and a known NPC")
		end
		for _, offer in ipairs(vendor.stock) do
			local def = content.items[offer.itemId]
			if def == nil or not Check.isPositiveInteger(offer.price) then
				add("vendor " .. tostring(key), "sells an unknown item or has no price: " .. tostring(offer.itemId))
			elseif (def.tier or 1) > 1 then
				add("vendor " .. tostring(key), tostring(offer.itemId) .. " is above the first tier; vendors sell basics only (L-12)")
			end
		end
	end

	-- Trading (L-53)
	local buyBack = content.economy.vendorBuyBack
	if type(buyBack.rate) ~= "number" or buyBack.rate <= 0 or buyBack.rate >= 1 or #buyBack.valueByTier == 0 then
		add("vendor buy-back", "the rate must be between 0 and 1, with a value for each tier")
	end
	local marketTax = content.economy.playerShops.marketTaxPercent
	if not Check.isNonNegativeInteger(marketTax) or marketTax > 20 then
		add("player shops", "the royal market tax is a whole percentage, at most 20")
	end
	for _, field in ipairs({ "maxListings", "maxOrders", "maxQuantity", "maxUnitPrice", "recentOperationsKept" }) do
		if not Check.isPositiveInteger(content.economy.playerShops[field]) then
			add("player shops", field .. " must be a positive whole number")
		end
	end

	-- Character creation (L-38)
	for _, listName in ipairs({ "genders", "skinTones", "hairStyles", "hairColors", "faces" }) do
		local list = content.appearance[listName]
		local seen = {}
		if #list == 0 then
			add("appearance", listName .. " needs at least one option")
		end
		for _, option in ipairs(list) do
			local colorOk = option.color == nil or (#option.color == 3 and Check.isNonNegativeInteger(option.color[1]) and option.color[1] <= 255 and Check.isNonNegativeInteger(option.color[2]) and option.color[2] <= 255 and Check.isNonNegativeInteger(option.color[3]) and option.color[3] <= 255)
			if not Check.isIdentifier(option.id) or seen[option.id] or not colorOk or (option.assetId ~= nil and not Check.isNonNegativeInteger(option.assetId)) then
				add("appearance", listName .. " option " .. tostring(option.id) .. " needs a unique id and a valid colour or asset id")
			end
			for _, scale in ipairs({ "bodyType", "proportion" }) do
				local value = option[scale]
				if value ~= nil and (type(value) ~= "number" or value < 0 or value > 1) then
					add("appearance", listName .. " option " .. tostring(option.id) .. ": " .. scale .. " must be between 0 and 1")
				end
			end
			seen[option.id] = true
		end
	end

	-- Combat and animations (L-03, M3)
	for disciplineId, combat in pairs(content.combat.disciplines) do
		local discipline = content.disciplines[disciplineId]
		local label = "combat " .. tostring(disciplineId)
		if discipline == nil then
			add(label, "unknown discipline")
		else
			for attackId, attack in pairs(combat.attacks) do
				if discipline.techniques[attack.technique] == nil or content.animations[attack.animation] == nil then
					add(label, tostring(attackId) .. " needs a known technique and animation")
				end
				if attack.next ~= nil and combat.attacks[attack.next] == nil then
					add(label, tostring(attackId) .. " chains to an unknown attack")
				end
			end
			if discipline.techniques[combat.parry.technique] == nil or content.animations[combat.parry.animation] == nil then
				add(label, "parry needs a known technique and animation")
			end
		end
	end
	for enemyId, enemyDef in pairs(content.enemies) do
		-- an enemy's own attack, or the shared attack of its archetype (world specification)
		local attack = content.combat.enemyAttacks[enemyId] or (content.combat.archetypeAttacks and content.combat.archetypeAttacks[enemyDef.archetype or "Melee"])
		if attack == nil or content.animations[attack.animation] == nil then
			add("enemy " .. tostring(enemyId), "needs an attack with a known animation in Config/Combat")
		end
	end

	-- NPCs and parties (L-40, L-42)
	for key, npc in pairs(content.npcs) do
		if npc.id ~= key or world.locations[npc.locationId] == nil or type(npc.displayName) ~= "string" then
			add("npc " .. tostring(key), "needs a matching id, a display name and a known location")
		end
	end
	local parties = content.parties
	if not Check.isPositiveInteger(parties.maxSize) or parties.maxSize > 4 or #parties.goals == 0 then
		add("party rules", "parties hold one to four players (L-15) and need at least one goal")
	end

	-- Player guilds and inn rentals
	local guilds = content.guilds
	if guilds.ranks[1] ~= "Leader" or #guilds.ranks < 2 then
		add("guild rules", "ranks must start with Leader and have at least two ranks")
	end
	for _, rank in ipairs(guilds.ranks) do
		if type(guilds.permissions[rank]) ~= "table" then
			add("guild rules", "rank " .. tostring(rank) .. " needs permissions")
		end
	end
	if not Check.isPositiveInteger(guilds.maxMembers) or not Check.isPositiveInteger(guilds.inviteSeconds) or not Check.isNonNegativeInteger(guilds.creationCost) then
		add("guild rules", "size, invite time and cost must be whole numbers")
	end
	local rental = content.propertyRules.rental
	if not Check.isPositiveInteger(rental.pricePerDay) or not Check.isPositiveInteger(rental.maxDays) or not Check.isPositiveInteger(rental.dayLengthSeconds) or not Check.isNonNegativeInteger(rental.maxInvited) then
		add("rental rules", "prices, durations and guest limits must be whole numbers")
	end

	table.sort(problems)
	return problems
end

return ConfigValidation
