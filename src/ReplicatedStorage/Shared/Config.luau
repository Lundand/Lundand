--[[
	CORE HUNTERS — Config
	Every tunable number in the game lives in this file.
	Change values here, press Play, and the whole game follows.

	Quick guide:
	  * Zones           -> world order, recommended Power, colours, mobs, core names
	  * DropOdds        -> 1-in-N chance per kill for each Core rarity (normal / elite / boss)
	  * Rarities        -> item multipliers, incubation times, protection shields
	  * Items           -> loot pools (3 weapons, 3 classes, 3 abilities per Core type)
	  * Upgrades        -> coin costs of base upgrades
	  * Products/Passes -> paste your Robux developer product / game pass IDs here (0 = disabled)
]]

local rgb = Color3.fromRGB

local Config = {}

Config.GameName = "CORE HUNTERS"
Config.Version = "1.5.2"

-- Extra admin user IDs (the game owner and anyone in Studio are always admins)
Config.Admins = {
	-- 123456789,
}

--------------------------------------------------------------------------------
-- PLAYER
--------------------------------------------------------------------------------
Config.Player = {
	WalkSpeed = 24,
	JumpHeight = 7.5,
	RespawnTime = 3,
	BaseHealth = 100,
}

--------------------------------------------------------------------------------
-- WORLD LAYOUT (studs). +X is "deeper into the world".
--------------------------------------------------------------------------------
Config.World = {
	GateX = 120, -- x where Grasslands begins; everything with x < GateX is the safe spawn/base area
	ZoneLength = 300,
	ZoneHalfWidth = 130,
	MobLaneHalfWidth = 70, -- mobs spawn and wander inside |z| < this
	SpawnPos = Vector3.new(58, 0, 0),
	RiftOrigin = Vector3.new(4200, 600, 0), -- where personal Endless arenas are created (in the sky)
	RiftSpacing = 460,
	RiftRadius = 88,
	Seed = 7331, -- decoration layout seed
}

--------------------------------------------------------------------------------
-- RARITIES (index 1..8). mult = item power multiplier.
-- incub = {seconds in zone 1, seconds in zone 8+} (0 = opens instantly on delivery). Timers run in real time,
--   also while the player is offline. Uncommon 1-4 min, Rare 15-45 min, Epic 1-3 h, Legendary 4-12 h,
--   Mythic 1-2 days, Divine 2-5 days, ??? 7 days.
-- shield = seconds of protection right after picking up a Core of this rarity
--------------------------------------------------------------------------------
Config.Rarities = {
	{ name = "Common", color = rgb(205, 210, 220), mult = 1.0, incub = { 0, 0 }, shield = 0 },
	{ name = "Uncommon", color = rgb(88, 222, 110), mult = 1.6, incub = { 60, 240 }, shield = 0 },
	{ name = "Rare", color = rgb(64, 160, 255), mult = 2.6, incub = { 900, 2700 }, shield = 4 },
	{ name = "Epic", color = rgb(186, 92, 255), mult = 4.2, incub = { 3600, 10800 }, shield = 8 },
	{ name = "Legendary", color = rgb(255, 196, 46), mult = 7.0, incub = { 14400, 43200 }, shield = 15 },
	{ name = "Mythic", color = rgb(255, 64, 110), mult = 11.5, incub = { 86400, 172800 }, shield = 20 },
	{ name = "Divine", color = rgb(120, 255, 240), mult = 19, incub = { 172800, 432000 }, shield = 30 },
	{ name = "???", color = rgb(255, 255, 255), mult = 32, incub = { 604800, 604800 }, shield = 30, secret = true },
}

-- 1-in-N odds per kill, per Core rarity (Common .. ???). Better Luck divides N.
Config.DropOdds = {
	normal = { 30, 150, 800, 6000, 50000, 500000, 5000000, 50000000 },
	elite = { 6, 30, 150, 1000, 10000, 100000, 1000000, 10000000 },
	boss = { 1, 4, 15, 80, 1000, 10000, 100000, 1000000 },
}

Config.AnnounceRarity = 4 -- Epic+ drops are announced to the whole server
Config.GlobalAnnounceRarity = 6 -- Mythic+ drops are announced to every server

-- When a Core is opened: chance the item comes out 0 / +1 / +2 rarities higher
Config.OpenUpgrade = { { 0, 88 }, { 1, 10 }, { 2, 2 } }
-- Weapon / Class / Ability weights when rolling an item
Config.CategoryWeights = { w = 40, c = 30, a = 30 }

--------------------------------------------------------------------------------
-- GROUND CORES & DELIVERY
--------------------------------------------------------------------------------
Config.Cores = {
	Despawn = 600, -- a dropped Core stays on the ground this long (10 min)
	Reserve = 45, -- seconds a fresh drop is reserved for the player who earned it
	DeathReserve = 45, -- seconds a Core dropped on death is reserved for its carrier
	ManualDropReserve = 30, -- seconds a Core you put down yourself stays reserved for you
	MinDespawnAfterDrop = 180, -- a Core dropped by a carrier stays at least this long
	CarrySlow = { 0.1, 0.12, 0.15, 0.18, 0.22, 0.25, 0.28, 0.3 }, -- walk speed penalty per rarity
	PickupHold = { 0.25, 0.35, 0.5, 0.6, 0.8, 1, 1.2, 1.2 },
	ResumeShield = 6, -- protection after rejoining with a Core you were carrying
	CarryJumpHeight = 4,
	-- Base full? A rarer Core still fits: the weakest Core waiting in storage is scrapped into Fragments
	ScrapWeakest = true,
	ScrapFragments = { 1, 15, 50, 150, 400, 1000, 3000, 3000 }, -- Fragments for a scrapped Core, per rarity
}

--------------------------------------------------------------------------------
-- PVP / CORE CONTESTS
-- Mode: "Off"        = PvE risk only (nobody can take your Core)
--       "Limited"    = Cores can be stolen only in zones with pvp = true (recommended)
--       "Everywhere" = Cores can be stolen in every zone (never in the spawn/base area)
--------------------------------------------------------------------------------
Config.PvP = {
	Mode = "Limited",
	StealHold = 1.6, -- seconds the thief must hold the prompt (carrier can run away)
	StealRange = 9,
	StealImmunity = 10, -- seconds before a Core that was just stolen can be stolen again
	StunTime = 1.5, -- victim is knocked down this long
}

--------------------------------------------------------------------------------
-- COMBAT
--------------------------------------------------------------------------------
Config.Combat = {
	GapExponent = 0.75, -- how hard mobs hit when you are below their zone's Power
	MinDamageScale = 0.08,
	MaxDamageScale = 6,
	CritChance = 0.08,
	CritMult = 2,
	RegenDelay = 4, -- seconds without damage before out-of-combat regen
	RegenPerSec = 0.05, -- % of max HP per second out of combat
	RewardShare = 0.12, -- need to deal this share of a mob's HP to get its rewards
	BaseCoins = 4, -- coins for a normal kill at CoinReference Power
	CoinReference = 30,
	CoinExponent = 0.85,
	HazardDamage = 0.1, -- lava / toxic pools: % max HP per second
	RangedMoveSlow = 0.55, -- shooting a bow/staff slows you to 55% speed for a moment (no endless kiting)
	RangedSlowTime = 0.6,
}

Config.MobTiers = {
	-- chase = walk speed multiplier while a mob is chasing someone
	normal = { hp = 2.5, dmg = 0.06, cooldown = 1.3, coins = 1, frags = 1, aggro = 38, count = 12, respawn = 4, size = 1, range = 4.5, chase = 1.55 },
	elite = { hp = 10, dmg = 0.11, cooldown = 1.5, coins = 5, frags = 5, aggro = 46, count = 2, respawn = 25, size = 1.4, range = 5.5, chase = 1.6 },
	boss = {
		hp = 60,
		dmg = 0.16,
		cooldown = 1.8,
		coins = 40,
		frags = 25,
		aggro = 70,
		count = 1,
		respawn = 150,
		firstSpawn = 30,
		size = 2.4,
		range = 9,
		chase = 1.35,
		slam = { radius = 18, delay = 1.1, dmg = 0.3, every = 7 },
	},
}

-- Monsters get harder the deeper you go, on top of scaling with each zone's recommended Power.
-- Every zone after Grasslands adds these amounts; the Endless Rift keeps adding them.
Config.Difficulty = {
	Speed = 0.06, -- +6% move speed per zone
	Health = 0.25, -- +25% health per zone (Void monsters have 2.75x health)
	Damage = 0.07, -- +7% damage per zone
	AttackSpeed = 0.03, -- attacks 3% more often per zone
	Aggro = 2, -- spots you 2 studs further away per zone
	MaxSpeed = 1.8, -- caps
	MaxAttackSpeed = 0.6,
	MaxChaseSpeed = 26, -- a chasing monster never runs faster than this (players walk at 24)
}

--------------------------------------------------------------------------------
-- ZONES (in world order). required Power to pass a gate = rec * GateRequirement
--------------------------------------------------------------------------------
Config.GateRequirement = 0.5
-- Pacing (tests/sim.luau, efficient non-stop play): Forest ~8 min, Dark Forest ~1 h, Desert ~3 h,
-- Frozen Lands ~7 h, Volcano ~11 h, Wasteland ~19 h, Void ~26 h. Real players take longer.

export type ZoneLight = {
	clock: number,
	ambient: Color3,
	outdoor: Color3,
	fog: Color3,
	fogEnd: number,
	atmo: Color3,
	density: number,
	tint: Color3,
	sat: number,
}

export type Zone = {
	id: string,
	name: string,
	rec: number,
	richness: number,
	core: string,
	coreColor: Color3,
	ground: Enum.Material,
	groundColor: Color3,
	cliff: Enum.Material,
	cliffColor: Color3,
	mobs: { string },
	elite: string,
	boss: string,
	deco: string,
	light: ZoneLight,
	itemFactor: number?, -- overrides ItemBaseFactor for this zone's items
	hazard: string?, -- "lava" or "toxic" pools that hurt
	pvp: boolean?, -- contested zone: Cores can be stolen here (PvP Mode "Limited")
}

Config.Zones = {
	{
		id = "grasslands",
		name = "Grasslands",
		rec = 12,
		richness = 3, -- drop odds are divided by this: >1 = Cores drop more often (early zones), <1 = rarer (deep zones)
		itemFactor = 2.5, -- tutorial zone: its items are extra strong so the first Cores feel great
		core = "Meadow Core",
		coreColor = rgb(140, 225, 100),
		ground = Enum.Material.Grass,
		groundColor = rgb(98, 178, 72),
		cliff = Enum.Material.Rock,
		cliffColor = rgb(128, 128, 120),
		mobs = { "slime", "boar" },
		elite = "bandit",
		boss = "king_slime",
		deco = "grasslands",
		light = { clock = 14, ambient = rgb(110, 110, 120), outdoor = rgb(130, 130, 140), fog = rgb(200, 225, 255), fogEnd = 1800, atmo = rgb(199, 226, 255), density = 0.28, tint = rgb(255, 255, 255), sat = 0.1 },
	},
	{
		id = "forest",
		name = "Forest",
		rec = 100,
		richness = 2.2,
		core = "Nature Core",
		coreColor = rgb(60, 200, 90),
		ground = Enum.Material.LeafyGrass,
		groundColor = rgb(62, 130, 58),
		cliff = Enum.Material.Rock,
		cliffColor = rgb(128, 128, 120),
		mobs = { "wolf", "goblin" },
		elite = "treant",
		boss = "elder_treant",
		deco = "forest",
		light = { clock = 13, ambient = rgb(100, 115, 100), outdoor = rgb(120, 135, 120), fog = rgb(170, 210, 170), fogEnd = 1000, atmo = rgb(190, 230, 190), density = 0.35, tint = rgb(240, 255, 240), sat = 0.15 },
	},
	{
		id = "darkforest",
		name = "Dark Forest",
		rec = 350,
		richness = 1.6,
		core = "Shadow Core",
		coreColor = rgb(130, 70, 200),
		ground = Enum.Material.Mud,
		groundColor = rgb(48, 44, 58),
		cliff = Enum.Material.Rock,
		cliffColor = rgb(128, 128, 120),
		mobs = { "shadow_wisp", "skeleton" },
		elite = "werewolf",
		boss = "shadow_witch",
		deco = "darkforest",
		light = { clock = 18.4, ambient = rgb(70, 60, 90), outdoor = rgb(80, 70, 100), fog = rgb(60, 50, 80), fogEnd = 420, atmo = rgb(90, 80, 120), density = 0.45, tint = rgb(220, 210, 255), sat = -0.1 },
	},
	{
		id = "desert",
		name = "Desert",
		rec = 1500,
		richness = 1.2,
		core = "Desert Core",
		coreColor = rgb(240, 190, 90),
		ground = Enum.Material.Sand,
		groundColor = rgb(236, 208, 140),
		cliff = Enum.Material.Sandstone,
		cliffColor = rgb(214, 165, 105),
		mobs = { "scorpion", "sand_warrior" },
		elite = "desert_beast",
		boss = "sand_pharaoh",
		deco = "desert",
		light = { clock = 12.5, ambient = rgb(140, 120, 100), outdoor = rgb(160, 140, 110), fog = rgb(250, 225, 170), fogEnd = 1300, atmo = rgb(255, 225, 170), density = 0.3, tint = rgb(255, 245, 225), sat = 0.15 },
	},
	{
		id = "frozen",
		name = "Frozen Lands",
		rec = 7500,
		richness = 1,
		core = "Frost Core",
		coreColor = rgb(140, 210, 255),
		ground = Enum.Material.Snow,
		groundColor = rgb(235, 245, 255),
		cliff = Enum.Material.Glacier,
		cliffColor = rgb(160, 210, 240),
		mobs = { "frost_imp", "snow_wolf" },
		elite = "yeti",
		boss = "frost_giant",
		deco = "frozen",
		light = { clock = 15, ambient = rgb(130, 140, 160), outdoor = rgb(150, 160, 180), fog = rgb(220, 235, 255), fogEnd = 700, atmo = rgb(215, 230, 255), density = 0.4, tint = rgb(230, 240, 255), sat = -0.05 },
	},
	{
		id = "volcano",
		name = "Volcano",
		rec = 40000,
		richness = 0.75, -- deep zones: Cores are rarer, but their items are far stronger
		core = "Inferno Core",
		coreColor = rgb(255, 100, 30),
		ground = Enum.Material.Basalt,
		groundColor = rgb(52, 44, 42),
		cliff = Enum.Material.CrackedLava,
		cliffColor = rgb(255, 110, 40),
		mobs = { "lava_hound", "demon" },
		elite = "infernal_knight",
		boss = "magma_titan",
		deco = "volcano",
		hazard = "lava",
		light = { clock = 19, ambient = rgb(120, 60, 40), outdoor = rgb(140, 70, 50), fog = rgb(120, 40, 20), fogEnd = 600, atmo = rgb(255, 120, 70), density = 0.45, tint = rgb(255, 225, 210), sat = 0.1 },
	},
	{
		id = "wasteland",
		name = "Wasteland",
		rec = 250000,
		richness = 0.6,
		core = "Toxic Core",
		coreColor = rgb(170, 255, 60),
		ground = Enum.Material.Ground,
		groundColor = rgb(118, 108, 72),
		cliff = Enum.Material.Asphalt,
		cliffColor = rgb(90, 85, 80),
		mobs = { "mutant_rat", "scrap_bot" },
		elite = "toxic_brute",
		boss = "warlord",
		deco = "wasteland",
		hazard = "toxic",
		pvp = true,
		light = { clock = 16.5, ambient = rgb(110, 110, 80), outdoor = rgb(120, 120, 90), fog = rgb(160, 160, 100), fogEnd = 550, atmo = rgb(190, 190, 120), density = 0.45, tint = rgb(240, 245, 210), sat = -0.2 },
	},
	{
		id = "void",
		name = "Void",
		rec = 1800000,
		richness = 0.45,
		core = "Void Core",
		coreColor = rgb(160, 70, 255),
		ground = Enum.Material.Slate,
		groundColor = rgb(36, 24, 56),
		cliff = Enum.Material.Limestone,
		cliffColor = rgb(60, 40, 90),
		mobs = { "void_creature", "corrupted_knight" },
		elite = "void_lord",
		boss = "void_emperor",
		deco = "void",
		pvp = true,
		light = { clock = 0, ambient = rgb(80, 60, 120), outdoor = rgb(90, 70, 140), fog = rgb(40, 20, 70), fogEnd = 500, atmo = rgb(100, 60, 160), density = 0.5, tint = rgb(225, 210, 255), sat = 0.1 },
	},
} :: { Zone }

-- Lighting used in the spawn/base area and in the Endless Rift
Config.SpawnLight = Config.Zones[1].light
Config.RiftLight = { clock = 0, ambient = rgb(70, 90, 140), outdoor = rgb(80, 100, 150), fog = rgb(20, 30, 60), fogEnd = 900, atmo = rgb(60, 90, 160), density = 0.35, tint = rgb(210, 230, 255), sat = 0.2 } :: ZoneLight

--------------------------------------------------------------------------------
-- ENDLESS RIFT (Zone 9, 10, 11 ...). Personal arenas reached through the portal at the end of the Void.
--------------------------------------------------------------------------------
Config.Rift = {
	StartZone = 9,
	Growth = 3, -- recommended Power multiplies by this every endless zone
	WaveNormal = 6,
	WaveElite = 2,
	BossEvery = 5, -- zones 10, 15, 20 ... have a boss
	Mobs = { "rift_stalker", "star_wraith" },
	Elite = "rift_knight",
	Boss = "rift_titan",
	Core = "Rift Core",
	CoreColor = rgb(80, 220, 255),
	-- The Rift has its own drop table: nothing below Rare drops here (0 = can't drop)
	DropOdds = {
		normal = { 0, 0, 25, 200, 2000, 20000, 200000, 2000000 },
		elite = { 0, 0, 6, 40, 400, 4000, 40000, 400000 },
		boss = { 0, 0, 1, 8, 80, 800, 8000, 80000 },
	},
}

--------------------------------------------------------------------------------
-- MOBS  (arch = body shape: biped / quad / blob / floater / bug)
-- Everything after `speed` only changes how a monster LOOKS (see Models.luau):
--   body      biped: human / knight / small / brute / skeleton / tree / robot / robe / golem
--             quad: wolf / boar / beast / ram / hound / rat / cat   floater: wisp / jelly / eye / wraith
--   weapon    club / sword / dagger / spear / staff / axe / crook / saw / icicle / orb    shield: round / kite
--   hat       hood / witch / nemes   helm (with helmet = true): crest / great / spiked / fin / skull
--   hornStyle curved / ram / ice     earStyle pointy / long     crownStyle gold / ice / branch / star / void / flame
--   outfit    shirt / bare / linen   plus: mask, teeth, nose, tail, wings, cape, beard, fur, kilt, sack, tanks,
--             mane, ruff, shards (and the older flags ears, horns, tusks, crown, spikes, leaves, glow)
--------------------------------------------------------------------------------
Config.Mobs = {
	-- Grasslands
	slime = { name = "Slime", arch = "blob", color = rgb(110, 220, 90), color2 = rgb(70, 170, 60), eye = rgb(25, 25, 25), speed = 10 },
	boar = { name = "Wild Boar", arch = "quad", color = rgb(140, 95, 70), color2 = rgb(95, 62, 45), eye = rgb(30, 30, 30), speed = 13, tusks = true, body = "boar" },
	bandit = { name = "Bandit", arch = "biped", color = rgb(196, 150, 110), color2 = rgb(70, 60, 90), eye = rgb(30, 30, 30), speed = 14, hat = "hood", outfit = "shirt", mask = "bandana", weapon = "dagger", sack = true },
	king_slime = { name = "King Slime", arch = "blob", color = rgb(90, 190, 255), color2 = rgb(60, 140, 220), eye = rgb(25, 25, 25), speed = 10, crown = true, cape = true },
	-- Forest
	wolf = { name = "Wolf", arch = "quad", color = rgb(120, 120, 130), color2 = rgb(90, 90, 100), eye = rgb(255, 210, 60), speed = 15, ears = true, body = "wolf" },
	goblin = { name = "Goblin", arch = "biped", color = rgb(110, 170, 70), color2 = rgb(110, 80, 50), eye = rgb(255, 60, 60), speed = 14, ears = true, scale = 0.85, body = "small", earStyle = "long", nose = "big", teeth = "grin", weapon = "club" },
	treant = { name = "Treant", arch = "biped", color = rgb(100, 70, 45), color2 = rgb(60, 140, 60), eye = rgb(255, 230, 90), speed = 11, leaves = true, body = "tree" },
	elder_treant = { name = "Elder Treant", arch = "biped", color = rgb(80, 55, 35), color2 = rgb(40, 110, 45), eye = rgb(255, 230, 90), speed = 11, leaves = true, crown = true, body = "tree", crownStyle = "branch", beard = true },
	-- Dark Forest
	shadow_wisp = { name = "Shadow Wisp", arch = "floater", color = rgb(60, 30, 90), color2 = rgb(170, 90, 255), eye = rgb(255, 255, 255), speed = 13, body = "wisp" },
	skeleton = { name = "Skeleton", arch = "biped", color = rgb(225, 220, 200), color2 = rgb(170, 165, 150), eye = rgb(255, 60, 60), speed = 14, body = "skeleton", weapon = "sword" },
	werewolf = { name = "Werewolf", arch = "quad", color = rgb(60, 55, 70), color2 = rgb(40, 36, 48), eye = rgb(255, 220, 60), speed = 16, ears = true, body = "beast", mane = true },
	shadow_witch = { name = "Shadow Witch", arch = "biped", color = rgb(120, 90, 160), color2 = rgb(50, 30, 70), eye = rgb(170, 255, 90), speed = 12, hat = "witch", body = "robe", weapon = "staff", nose = "witch" },
	-- Desert
	scorpion = { name = "Scorpion", arch = "bug", color = rgb(190, 120, 60), color2 = rgb(140, 80, 40), eye = rgb(30, 30, 30), speed = 14 },
	sand_warrior = { name = "Sand Warrior", arch = "biped", color = rgb(210, 170, 110), color2 = rgb(170, 60, 50), eye = rgb(40, 40, 40), speed = 14, helmet = true, helm = "crest", outfit = "bare", kilt = true, weapon = "spear", shield = "round" },
	desert_beast = { name = "Desert Beast", arch = "quad", color = rgb(200, 150, 80), color2 = rgb(150, 100, 50), eye = rgb(255, 80, 40), speed = 15, horns = true, body = "ram", hornStyle = "ram", mane = true },
	sand_pharaoh = { name = "Sand Pharaoh", arch = "biped", color = rgb(235, 215, 165), color2 = rgb(40, 90, 200), eye = rgb(90, 220, 255), speed = 12, crown = true, hat = "nemes", outfit = "linen", kilt = true, beard = true, weapon = "crook" },
	-- Frozen Lands
	frost_imp = { name = "Frost Imp", arch = "biped", color = rgb(140, 200, 255), color2 = rgb(80, 140, 220), eye = rgb(255, 255, 255), speed = 15, horns = true, scale = 0.8, body = "small", hornStyle = "ice", ears = true, teeth = "fangs", tail = "icicle", weapon = "icicle" },
	snow_wolf = { name = "Snow Wolf", arch = "quad", color = rgb(235, 240, 250), color2 = rgb(200, 210, 230), eye = rgb(90, 180, 255), speed = 16, ears = true, body = "wolf", ruff = true, shards = true },
	yeti = { name = "Yeti", arch = "biped", color = rgb(240, 245, 255), color2 = rgb(150, 190, 230), eye = rgb(60, 60, 80), speed = 12, scale = 1.2, body = "brute", fur = true, teeth = "fangs" },
	frost_giant = { name = "Frost Giant", arch = "biped", color = rgb(120, 170, 230), color2 = rgb(200, 235, 255), eye = rgb(255, 255, 255), speed = 11, crown = true, spikes = true, body = "brute", crownStyle = "ice", beard = true, weapon = "club" },
	-- Volcano
	lava_hound = { name = "Lava Hound", arch = "quad", color = rgb(60, 40, 35), color2 = rgb(255, 120, 30), eye = rgb(255, 200, 60), speed = 16, glow = true, ears = true, body = "hound" },
	demon = { name = "Demon", arch = "biped", color = rgb(170, 30, 30), color2 = rgb(60, 20, 20), eye = rgb(255, 220, 60), speed = 14, horns = true, hornStyle = "curved", outfit = "bare", teeth = "fangs", wings = true, tail = "spade" },
	infernal_knight = { name = "Infernal Knight", arch = "biped", color = rgb(50, 40, 40), color2 = rgb(255, 90, 20), eye = rgb(255, 140, 40), speed = 13, helmet = true, glow = true, body = "knight", helm = "great", weapon = "sword", shield = "kite" },
	magma_titan = { name = "Magma Titan", arch = "biped", color = rgb(70, 40, 30), color2 = rgb(255, 120, 0), eye = rgb(255, 220, 80), speed = 11, spikes = true, glow = true, body = "golem", crownStyle = "flame" },
	-- Wasteland
	mutant_rat = { name = "Mutant Rat", arch = "quad", color = rgb(130, 140, 90), color2 = rgb(170, 255, 60), eye = rgb(170, 255, 60), speed = 16, ears = true, scale = 0.85, body = "rat" },
	scrap_bot = { name = "Scrap Bot", arch = "biped", color = rgb(140, 110, 90), color2 = rgb(90, 90, 95), eye = rgb(255, 60, 40), speed = 13, helmet = true, body = "robot", weapon = "saw" },
	toxic_brute = { name = "Toxic Brute", arch = "biped", color = rgb(110, 150, 60), color2 = rgb(170, 255, 60), eye = rgb(255, 255, 90), speed = 12, glow = true, scale = 1.15, body = "brute", mask = "gas", tanks = true },
	warlord = { name = "Wasteland Warlord", arch = "biped", color = rgb(90, 80, 70), color2 = rgb(200, 60, 40), eye = rgb(255, 80, 40), speed = 12, helmet = true, spikes = true, body = "brute", helm = "skull", weapon = "axe", cape = true },
	-- Void
	void_creature = { name = "Void Creature", arch = "floater", color = rgb(40, 20, 70), color2 = rgb(170, 80, 255), eye = rgb(255, 255, 255), speed = 15, body = "jelly" },
	corrupted_knight = { name = "Corrupted Knight", arch = "biped", color = rgb(40, 35, 55), color2 = rgb(150, 70, 255), eye = rgb(200, 120, 255), speed = 14, helmet = true, glow = true, body = "knight", helm = "spiked", weapon = "sword", cape = true },
	void_lord = { name = "Void Lord", arch = "biped", color = rgb(25, 15, 40), color2 = rgb(200, 90, 255), eye = rgb(255, 255, 255), speed = 13, horns = true, crown = true, glow = true, body = "robe", hornStyle = "curved", crownStyle = "void", weapon = "orb" },
	void_emperor = { name = "Void Emperor", arch = "floater", color = rgb(20, 10, 35), color2 = rgb(220, 120, 255), eye = rgb(255, 60, 200), speed = 12, crown = true, body = "eye" },
	-- Endless Rift
	rift_stalker = { name = "Rift Stalker", arch = "quad", color = rgb(20, 30, 60), color2 = rgb(80, 220, 255), eye = rgb(80, 220, 255), speed = 16, glow = true, ears = true, body = "cat" },
	star_wraith = { name = "Star Wraith", arch = "floater", color = rgb(30, 40, 90), color2 = rgb(255, 240, 120), eye = rgb(255, 255, 255), speed = 15, body = "wraith" },
	rift_knight = { name = "Rift Knight", arch = "biped", color = rgb(30, 40, 80), color2 = rgb(80, 220, 255), eye = rgb(80, 220, 255), speed = 14, helmet = true, glow = true, body = "knight", helm = "fin", weapon = "spear", shield = "round" },
	rift_titan = { name = "Rift Titan", arch = "biped", color = rgb(20, 20, 50), color2 = rgb(255, 255, 255), eye = rgb(80, 220, 255), speed = 12, crown = true, spikes = true, glow = true, body = "golem", crownStyle = "star" },
}

--------------------------------------------------------------------------------
-- WEAPON STYLES. Damage per hit = Power * dps / rate (so every style has ~equal DPS;
-- styles differ in feel, reach and area).
--------------------------------------------------------------------------------
Config.WeaponStyles = {
	sword = { rate = 1.7, range = 10, arc = 120, dps = 1.0, kind = "melee", grip = "forward" },
	katana = { rate = 2.5, range = 10, arc = 100, dps = 1.0, kind = "melee", grip = "forward" },
	greatsword = { rate = 0.95, range = 12.5, arc = 160, dps = 1.08, kind = "melee", grip = "forward" },
	scythe = { rate = 1.3, range = 12, arc = 360, dps = 0.9, kind = "melee", grip = "upright" },
	daggers = { rate = 3.2, range = 8, arc = 90, dps = 0.97, kind = "melee", grip = "forward" },
	spear = { rate = 1.5, range = 15, arc = 50, dps = 1.0, kind = "melee", grip = "forward" },
	hammer = { rate = 0.85, range = 11, arc = 360, dps = 0.95, kind = "melee", grip = "forward" },
	bow = { rate = 1.5, range = 55, dps = 0.8, kind = "ranged", grip = "upright" },
	staff = { rate = 1.2, range = 50, dps = 0.75, kind = "ranged", splash = 8, grip = "upright" },
}

--------------------------------------------------------------------------------
-- ABILITIES. dmg is a multiple of your Power.
-- Rarer copies of an ability recharge faster: -5% cooldown per rarity above Common
Config.AbilityRarityCooldown = 0.05
-- kinds: dash, shadowstep, warp (movement: disabled while carrying a Core), bolt, strike, nova,
--        meteor, stun, dot, heal, buff, shield, drain
--------------------------------------------------------------------------------
Config.Abilities = {
	dash = { kind = "dash", cd = 4, dist = 42, color = rgb(230, 230, 255), desc = "Dash forward" },
	pebble = { kind = "bolt", cd = 3, dmg = 1.8, radius = 6, range = 70, color = rgb(170, 160, 140), desc = "Throw a rock that bursts on impact" },
	gust = { kind = "nova", cd = 6, dmg = 2.2, radius = 14, color = rgb(220, 255, 220), desc = "Blast enemies around you" },
	war_cry = { kind = "buff", cd = 20, dur = 8, mult = 1.5, color = rgb(255, 120, 80), desc = "+50% damage for 8s" },
	vine_trap = { kind = "stun", cd = 10, dmg = 1.5, radius = 16, dur = 2.5, color = rgb(90, 200, 80), desc = "Root nearby enemies in place" },
	healing_leaves = { kind = "heal", cd = 12, heal = 0.45, color = rgb(120, 255, 120), desc = "Heal 45% HP" },
	nature_blast = { kind = "bolt", cd = 4, dmg = 3, radius = 9, range = 70, color = rgb(80, 220, 90), desc = "Explosive ball of nature magic" },
	shadow_step = { kind = "shadowstep", cd = 6, dmg = 4, range = 45, color = rgb(140, 80, 220), desc = "Teleport behind an enemy and strike it" },
	soul_drain = { kind = "drain", cd = 6, dmg = 4.5, heal = 0.15, range = 60, color = rgb(170, 90, 255), desc = "Drain an enemy and heal yourself" },
	nightmare = { kind = "stun", cd = 11, dmg = 2.5, radius = 18, dur = 2.5, color = rgb(110, 60, 180), desc = "Terrify and freeze nearby enemies" },
	sandstorm = { kind = "dot", cd = 12, dmg = 1.1, ticks = 6, radius = 16, color = rgb(230, 200, 130), desc = "A storm that shreds enemies around you" },
	sun_beam = { kind = "strike", cd = 7, dmg = 7, range = 70, color = rgb(255, 230, 120), desc = "Call down a beam of sunlight" },
	quicksand = { kind = "stun", cd = 10, dmg = 2, radius = 16, dur = 3, color = rgb(200, 160, 90), desc = "Sink enemies into the sand" },
	frost_nova = { kind = "stun", cd = 9, dmg = 3, radius = 18, dur = 3, color = rgb(150, 220, 255), desc = "Freeze everything around you" },
	ice_spear = { kind = "strike", cd = 5, dmg = 5.5, range = 80, color = rgb(170, 230, 255), desc = "Pierce a target with ice" },
	blizzard = { kind = "meteor", cd = 14, dmg = 9, radius = 22, delay = 0.8, range = 70, color = rgb(210, 240, 255), desc = "Huge freezing storm at a target" },
	fireball = { kind = "bolt", cd = 3.5, dmg = 3.5, radius = 10, range = 75, color = rgb(255, 120, 30), desc = "Hurl an exploding fireball" },
	inferno = { kind = "dot", cd = 12, dmg = 1.6, ticks = 5, radius = 17, color = rgb(255, 90, 20), desc = "Burn everything around you" },
	meteor = { kind = "meteor", cd = 16, dmg = 12, radius = 22, delay = 0.9, range = 75, color = rgb(255, 110, 30), desc = "Crash a meteor into your enemies" },
	toxic_cloud = { kind = "dot", cd = 11, dmg = 1.4, ticks = 6, radius = 16, color = rgb(170, 255, 60), desc = "Poison enemies around you" },
	lightning = { kind = "strike", cd = 6, dmg = 6.5, range = 75, color = rgb(160, 220, 255), desc = "High single-target lightning damage" },
	scrap_shield = { kind = "shield", cd = 18, dur = 8, reduce = 0.6, color = rgb(200, 170, 120), desc = "Take 60% less damage for 8s" },
	teleport = { kind = "warp", cd = 6, dmg = 5, radius = 14, range = 70, color = rgb(190, 110, 255), desc = "Warp to where you aim; void blasts hit enemies at both ends" },
	time_stop = { kind = "stun", cd = 16, dmg = 3, radius = 30, dur = 4.5, color = rgb(220, 200, 255), desc = "Freeze time for enemies nearby" },
	reality_rift = { kind = "meteor", cd = 12, dmg = 14, radius = 20, delay = 0.6, range = 75, color = rgb(200, 90, 255), desc = "Tear reality open under your enemies" },
	star_fall = { kind = "meteor", cd = 12, dmg = 15, radius = 22, delay = 0.7, range = 80, color = rgb(255, 240, 140), desc = "A star falls on your target" },
	rift_nova = { kind = "nova", cd = 7, dmg = 6, radius = 20, color = rgb(80, 220, 255), desc = "A burst of rift energy" },
	singularity = { kind = "stun", cd = 15, dmg = 5, radius = 28, dur = 4, color = rgb(120, 120, 255), desc = "Crush and hold every enemy nearby" },
}

--------------------------------------------------------------------------------
-- ITEMS: loot pools per Core type. Index = zone number (0 = starter kit, 9 = Endless Rift).
-- Item Power = zone recommended Power * ItemBaseFactor (or the zone's itemFactor) * rarity mult * slot share * var
-- With 0.5, a zone's Commons match the Power you enter it with (the gate requirement), Uncommons
-- are upgrades, and a kit of Rares (or one Epic weapon) plus some training opens the next gate.
-- weight = how often this item rolls (lower = rarer), var = power bonus for rarer items.
-- Class mods: hp, dmg, melee, ranged, ability, speed, regen, lifesteal, backstab,
--             crit, resist, carry, coins, luck, hazard
--------------------------------------------------------------------------------
Config.ItemBaseFactor = 0.5
Config.ItemShare = { w = 0.6, c = 0.25, a = 0.15 }
Config.StarterPower = { w = 7, c = 3, a = 2 }

Config.Items = {
	[0] = {
		w = { { name = "Wooden Sword", style = "sword", color = rgb(170, 120, 70), color2 = rgb(110, 75, 45) } },
		c = { { name = "Novice", mods = {} } },
		a = { { name = "Dash", ability = "dash" } },
	},
	[1] = {
		w = {
			{ name = "Stone Sword", style = "sword", color = rgb(160, 160, 160), color2 = rgb(120, 85, 55) },
			{ name = "Hunter's Bow", style = "bow", color = rgb(150, 100, 60), color2 = rgb(230, 230, 210) },
			{ name = "Farmer's Scythe", style = "scythe", color = rgb(190, 190, 180), color2 = rgb(130, 95, 60), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Warrior", mods = { hp = 0.3, melee = 0.2 } },
			{ name = "Scout", mods = { speed = 0.15, ranged = 0.15 } },
			{ name = "Squire", mods = { hp = 0.15, dmg = 0.1, resist = 0.05 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Pebble Toss", ability = "pebble" },
			{ name = "Gust", ability = "gust" },
			{ name = "War Cry", ability = "war_cry", weight = 0.4, var = 1.12 },
		},
	},
	[2] = {
		w = {
			{ name = "Thorn Sword", style = "sword", color = rgb(70, 160, 70), color2 = rgb(90, 60, 35) },
			{ name = "Nature Bow", style = "bow", color = rgb(80, 150, 60), color2 = rgb(200, 255, 180) },
			{ name = "Vine Staff", style = "staff", color = rgb(90, 70, 40), color2 = rgb(90, 255, 120), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Ranger", mods = { ranged = 0.25, speed = 0.1 } },
			{ name = "Druid", mods = { regen = 0.02, ability = 0.15 } },
			{ name = "Forest Guardian", mods = { hp = 0.5, resist = 0.1 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Vine Trap", ability = "vine_trap" },
			{ name = "Healing Leaves", ability = "healing_leaves" },
			{ name = "Nature Blast", ability = "nature_blast", weight = 0.4, var = 1.12 },
		},
	},
	[3] = {
		w = {
			{ name = "Shadow Katana", style = "katana", color = rgb(60, 40, 90), color2 = rgb(170, 90, 255) },
			{ name = "Nightfang Daggers", style = "daggers", color = rgb(90, 90, 110), color2 = rgb(200, 60, 255) },
			{ name = "Grave Scythe", style = "scythe", color = rgb(150, 150, 170), color2 = rgb(60, 40, 70), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Assassin", mods = { speed = 0.4, backstab = 0.6, crit = 0.1, hp = -0.2 } },
			{ name = "Necromancer", mods = { lifesteal = 0.05, ability = 0.2 } },
			{ name = "Shadow Knight", mods = { hp = 0.3, melee = 0.25 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Shadow Step", ability = "shadow_step" },
			{ name = "Soul Drain", ability = "soul_drain" },
			{ name = "Nightmare", ability = "nightmare", weight = 0.4, var = 1.12 },
		},
	},
	[4] = {
		w = {
			{ name = "Pharaoh's Blade", style = "sword", color = rgb(240, 200, 80), color2 = rgb(40, 90, 200) },
			{ name = "Sand Spear", style = "spear", color = rgb(210, 180, 120), color2 = rgb(120, 80, 40) },
			{ name = "Dune Bow", style = "bow", color = rgb(200, 150, 80), color2 = rgb(255, 230, 150), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Nomad", mods = { speed = 0.2, carry = 0.5 } },
			{ name = "Sun Priest", mods = { regen = 0.025, hp = 0.2 } },
			{ name = "Gladiator", mods = { melee = 0.35, hp = 0.2 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Sandstorm", ability = "sandstorm" },
			{ name = "Sun Beam", ability = "sun_beam" },
			{ name = "Quicksand", ability = "quicksand", weight = 0.4, var = 1.12 },
		},
	},
	[5] = {
		w = {
			{ name = "Frostbite Katana", style = "katana", color = rgb(170, 230, 255), color2 = rgb(60, 110, 180) },
			{ name = "Ice Staff", style = "staff", color = rgb(200, 230, 255), color2 = rgb(120, 210, 255) },
			{ name = "Glacier Hammer", style = "hammer", color = rgb(140, 200, 240), color2 = rgb(90, 120, 160), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Frost Mage", mods = { ability = 0.4 } },
			{ name = "Ice Ranger", mods = { ranged = 0.35, crit = 0.05 } },
			{ name = "Angel", mods = { hp = 0.5, regen = 0.03 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Frost Nova", ability = "frost_nova" },
			{ name = "Ice Spear", ability = "ice_spear" },
			{ name = "Blizzard", ability = "blizzard", weight = 0.4, var = 1.12 },
		},
	},
	[6] = {
		w = {
			{ name = "Flame Sword", style = "sword", color = rgb(255, 120, 40), color2 = rgb(60, 30, 20) },
			{ name = "Demon Scythe", style = "scythe", color = rgb(200, 30, 30), color2 = rgb(40, 20, 20) },
			{ name = "Infernal Greatsword", style = "greatsword", color = rgb(255, 90, 20), color2 = rgb(30, 25, 25), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Demon", mods = { dmg = 0.5, hazard = 0.8 } },
			{ name = "Hell Knight", mods = { hp = 0.4, melee = 0.3 } },
			{ name = "Flameborn", mods = { ability = 0.45, hazard = 0.5 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Fireball", ability = "fireball" },
			{ name = "Inferno", ability = "inferno" },
			{ name = "Meteor", ability = "meteor", weight = 0.4, var = 1.12 },
		},
	},
	[7] = {
		w = {
			{ name = "Rust Cleaver", style = "greatsword", color = rgb(160, 100, 60), color2 = rgb(70, 60, 55) },
			{ name = "Toxic Crossbow", style = "bow", color = rgb(90, 90, 95), color2 = rgb(170, 255, 60) },
			{ name = "Scrap Hammer", style = "hammer", color = rgb(130, 120, 110), color2 = rgb(255, 150, 40), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Scavenger", mods = { coins = 0.5, luck = 0.25 } },
			{ name = "Cyborg", mods = { hp = 0.35, dmg = 0.25 } },
			{ name = "Plague Doctor", mods = { regen = 0.03, lifesteal = 0.04, hazard = 0.8 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Toxic Cloud", ability = "toxic_cloud" },
			{ name = "Lightning", ability = "lightning" },
			{ name = "Scrap Shield", ability = "scrap_shield", weight = 0.4, var = 1.12 },
		},
	},
	[8] = {
		w = {
			{ name = "Void Blade", style = "katana", color = rgb(60, 20, 110), color2 = rgb(200, 110, 255) },
			{ name = "Void Scythe", style = "scythe", color = rgb(40, 20, 70), color2 = rgb(170, 80, 255) },
			{ name = "Reality Cutter", style = "greatsword", color = rgb(230, 220, 255), color2 = rgb(150, 60, 255), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Void Walker", mods = { speed = 0.3, carry = 0.6 } },
			{ name = "Abyssal Lord", mods = { hp = 0.6, dmg = 0.3 } },
			{ name = "Voidborn", mods = { dmg = 0.8 }, weight = 0.25, var = 1.25 },
		},
		a = {
			{ name = "Teleport", ability = "teleport" },
			{ name = "Time Stop", ability = "time_stop" },
			{ name = "Reality Rift", ability = "reality_rift", weight = 0.4, var = 1.12 },
		},
	},
	[9] = { -- Endless Rift (all zones 9+)
		w = {
			{ name = "Starforged Blade", style = "sword", color = rgb(255, 245, 200), color2 = rgb(80, 220, 255) },
			{ name = "Rift Bow", style = "bow", color = rgb(40, 60, 120), color2 = rgb(80, 220, 255) },
			{ name = "Cosmic Scythe", style = "scythe", color = rgb(20, 20, 40), color2 = rgb(255, 240, 140), weight = 0.4, var = 1.12 },
		},
		c = {
			{ name = "Celestial", mods = { hp = 0.4, regen = 0.03, ability = 0.3 } },
			{ name = "Starborn", mods = { dmg = 0.6, crit = 0.1 } },
			{ name = "Chronomancer", mods = { ability = 0.6, speed = 0.2 }, weight = 0.4, var = 1.12 },
		},
		a = {
			{ name = "Star Fall", ability = "star_fall" },
			{ name = "Rift Nova", ability = "rift_nova" },
			{ name = "Singularity", ability = "singularity", weight = 0.4, var = 1.12 },
		},
	},
}

-- Human-readable names for class mods (used by the UI)
Config.ModNames = {
	hp = "Max HP",
	dmg = "All damage",
	melee = "Melee damage",
	ranged = "Ranged damage",
	ability = "Ability damage",
	speed = "Move speed",
	regen = "HP regen /s",
	lifesteal = "Lifesteal",
	backstab = "Damage from behind",
	crit = "Crit chance",
	resist = "Damage reduction",
	carry = "Less carry slowdown",
	coins = "Coins",
	luck = "Core luck",
	hazard = "Lava/toxic resist",
}

--------------------------------------------------------------------------------
-- BASE UPGRADES (bought with Coins)
--------------------------------------------------------------------------------
-- Levelled upgrades: cost = base * growth ^ level, up to max levels. Small steps, many levels.
Config.Upgrades = {
	train = { order = 1, name = "Power Training", desc = "+2% Power per level", base = 20, growth = 1.35, max = 100000, per = 0.02 },
	luck = { order = 2, name = "Core Luck", desc = "+1% Core luck per level", base = 250, growth = 1.085, max = 100, per = 0.01 },
	slots = { order = 3, name = "Incubator Slots", desc = "More Cores incubating at once", costs = { 500, 7500, 150000, 3000000 }, values = { 1, 2, 3, 5, 10 } },
	speed = { order = 4, name = "Incubation Speed", desc = "-0.5% incubation time per level", base = 150, growth = 1.13, max = 60, per = 0.005 },
	storage = { order = 5, name = "Core Storage", desc = "+1 Core waiting to incubate per level", base = 500, growth = 1.55, max = 12, start = 3, per = 1 },
	carry = { order = 6, name = "Carry Strength", desc = "-1% carry slowdown, +0.1s pickup shield per level", base = 300, growth = 1.12, max = 50, per = 0.01, shield = 0.1 },
	style = {
		order = 7,
		name = "Base Style",
		desc = "Cosmetic: decorate your base",
		costs = { 5000, 100000, 2000000, 40000000, 800000000 },
		levels = { "Lanterns & flowers", "Banners & hedges", "Stone towers", "Crystal spire", "Golden base" },
	},
}

-- Fragments -> a guaranteed Uncommon+ Core of the zone you last fought in (goes straight into your base).
-- Forging the zone you farm (not your deepest zone) keeps it useful without skipping the grind.
-- Inventory: players hold a limited number of items and choose what to sell for coins
Config.Inventory = {
	Max = 30, -- starter items don't count
	SellKills = { 3, 8, 25, 80, 300, 1200, 5000, 20000 }, -- sells for this many kills' worth of coins in the item's zone
	ConfirmRarity = 3, -- Rare and rarer ask "Sure?" before selling
}

Config.Forge = {
	cost = 300, -- about 200 kills
	odds = { { 2, 55 }, { 3, 35 }, { 4, 9 }, { 5, 1 } }, -- { rarity, weight }
}

Config.MaxTrophies = 3 -- items displayed on pedestals in your base
Config.MaxDiscoveries = 5 -- rarest Cores listed on your base's trophy wall

--------------------------------------------------------------------------------
-- ROBUX. Create these in Creator Dashboard -> your game -> Monetization,
-- then paste the IDs here. An ID of 0 hides/disables that item.
-- The shop shows the image you upload for each pass/product in its round badge (the store-art PNGs);
-- add image = "rbxassetid://..." to an entry to use a different picture.
--------------------------------------------------------------------------------
Config.Products = {
	-- Instant-open tiers: the cheapest tier whose "max" covers the remaining time is offered
	Skips = {
		{ max = 600, id = 0, price = 15 },
		{ max = 3600, id = 0, price = 39 },
		{ max = 21600, id = 0, price = 99 },
		{ max = 86400, id = 0, price = 199 },
		{ max = math.huge, id = 0, price = 399 },
	},
	TimeWarp = { id = 0, price = 49, seconds = 3600 }, -- -1 hour on every incubator
	Luck = { id = 0, price = 49, seconds = 1800, mult = 2 }, -- personal x2 luck, 30 min
	ServerLuck = { id = 0, price = 99, seconds = 900, mult = 2 }, -- x2 luck for the whole server, 15 min
	Coins = { id = 0, price = 29, kills = 400 }, -- coins worth ~400 kills in your best zone
	-- Premium Cores: opened on the spot, item from the deepest zone the player has unlocked (odds: Config.Premium)
	PremiumCore = { id = 0, price = 99, count = 1 },
	PremiumCore3 = { id = 0, price = 249, count = 3 },
}

-- Premium Core contents: rarity odds in percent (they must add up to 100). The item inside is rolled from the
-- zone's pool with the normal item weights. The shop shows every chance before buying (Roblox rules).
Config.Premium = {
	odds = { { 3, 60 }, { 4, 30 }, { 5, 8 }, { 6, 1.8 }, { 7, 0.2 } }, -- { rarity, percent }
}

-- Roblox counts these as "paid random items" (random rewards or luck bought with Robux, also via bought Coins).
-- Players where PolicyService says ArePaidRandomItemsRestricted (e.g. UK, NL, BE, AU, BR) can't see or buy them.
Config.PaidRandom = {
	products = { "PremiumCore", "PremiumCore3", "Luck", "ServerLuck", "Coins" },
	passes = { "DoubleLuck" },
}

Config.Passes = {
	DoubleCoins = { id = 0, price = 199, name = "2x Coins", desc = "Double coins from every kill" },
	DoubleLuck = { id = 0, price = 299, name = "2x Luck", desc = "Double Core drop luck forever" },
	ExtraIncubators = { id = 0, price = 249, name = "+2 Incubators", desc = "Two extra incubator slots", slots = 2 },
	FastIncubation = { id = 0, price = 349, name = "Fast Incubation", desc = "Cores incubate 30% faster", mult = 0.7 },
	VIP = { id = 0, price = 149, name = "VIP", desc = "+20% coins and a VIP tag", coins = 0.2 },
}

--------------------------------------------------------------------------------
-- BADGES. Create them in Creator Dashboard -> your game -> Engagement -> Badges (5 free per day, then
-- 100 Robux each), then paste the IDs here. id = 0 means "not created yet": nothing is awarded, and in
-- Studio the Output says when a player would have earned it. name/desc are suggestions for the dashboard.
-- Every badge is checked against saved progress, so players also get it for what they did before.
--------------------------------------------------------------------------------
Config.Badges = {
	FirstCore = { id = 0, name = "First Core", desc = "Carry your first Core home." },
	Rare = { id = 0, name = "Shiny!", desc = "Secure a Rare Core (or rarer)." },
	Epic = { id = 0, name = "Epic Find", desc = "Secure an Epic Core (or rarer)." },
	Legendary = { id = 0, name = "Legendary", desc = "Secure a Legendary Core (or rarer)." },
	Mythic = { id = 0, name = "Mythic", desc = "Secure a Mythic Core (or rarer)." },
	Divine = { id = 0, name = "Divine", desc = "Secure a Divine Core (or rarer)." },
	Secret = { id = 0, name = "???", desc = "You found it. Don't tell anyone." },
	Forest = { id = 0, name = "Into the Woods", desc = "Unlock the Forest." },
	DarkForest = { id = 0, name = "Lights Out", desc = "Unlock the Dark Forest." },
	Desert = { id = 0, name = "Sand Everywhere", desc = "Unlock the Desert." },
	Frozen = { id = 0, name = "Cold Feet", desc = "Unlock the Frozen Lands." },
	Volcano = { id = 0, name = "Hot Stuff", desc = "Unlock the Volcano." },
	Wasteland = { id = 0, name = "Scavenger", desc = "Unlock the Wasteland." },
	Void = { id = 0, name = "Void Walker", desc = "Unlock the Void." },
	Rift = { id = 0, name = "No Way Back", desc = "Step into the Endless Rift." },
	Boss = { id = 0, name = "Boss Down", desc = "Defeat a boss." },
	Kills1K = { id = 0, name = "Monster Hunter", desc = "Defeat 1,000 monsters." },
	Kills25K = { id = 0, name = "Exterminator", desc = "Defeat 25,000 monsters." },
	Steal = { id = 0, name = "Yoink!", desc = "Steal a Core from another player." },
	Forge = { id = 0, name = "Forged", desc = "Forge a Core from Fragments." },
	CoreFarm = { id = 0, name = "Core Farm", desc = "Unlock all 10 incubators." },
	GoldenBase = { id = 0, name = "Golden Base", desc = "Max out your Base Style." },
}

--------------------------------------------------------------------------------
-- SOUNDS (built-in Roblox sounds; swap for your own asset IDs any time)
--------------------------------------------------------------------------------
Config.Sounds = {
	Swing = "rbxasset://sounds/swordslash.wav",
	Hit = "rbxasset://sounds/swordlunge.wav",
	Ability = "rbxasset://sounds/Rocket shot.wav",
	Explode = "rbxasset://sounds/collide.wav",
	CoreDrop = "rbxasset://sounds/electronicpingshort.wav",
	Pickup = "rbxasset://sounds/unsheath.wav",
	Deliver = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
}

Config.HowToPlay = {
	"1. Fight monsters in the world",
	"2. Monsters can drop CORES on the ground",
	"3. Pick up the Core and carry it home",
	"4. Walk into your base to secure it",
	"5. Incubate it, open it: Weapons, Classes & Abilities",
	"6. Bag full? SELL items in the ITEMS menu",
	"7. More POWER = deeper zones = rarer Cores!",
}

return Config
