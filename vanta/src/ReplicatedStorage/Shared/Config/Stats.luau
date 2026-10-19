--!strict
-- Character stats allocated by the player (L-17). Values are placeholders to tune in playtests.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	order = { "Strength", "Agility", "Vitality", "Intelligence" },
	definitions = {
		Strength = { displayName = "Strength", description = "Raises physical damage." },
		Agility = { displayName = "Agility", description = "Raises attack speed and stamina recovery." },
		Vitality = { displayName = "Vitality", description = "Raises health and stamina." },
		Intelligence = { displayName = "Intelligence", description = "Raises magic power." },
	},
	startingPoints = 0,
	pointsPerLevel = 3,
	-- Effect of each allocated point. Agility never changes movement or dodge speed (PROGRESSION_SLICE.md).
	effectsPerPoint = {
		Strength = { physicalDamage = 0.02 },
		Agility = { attackSpeed = 0.01, staminaRegen = 0.02 },
		Vitality = { maxHealth = 10, maxStamina = 2 },
		Intelligence = { magicPower = 0.02 },
	},
	baseValues = {
		physicalDamage = 1,
		attackSpeed = 1,
		staminaRegen = 1,
		maxHealth = 100,
		maxStamina = 100,
		magicPower = 1,
	},
	-- Optional soft cap (P-12, awaiting approval), e.g. { threshold = 50, efficiencyAbove = 0.5 }. Off by default.
	softCap = nil,
})
