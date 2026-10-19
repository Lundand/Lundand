--!strict
-- Character creation (L-38): characters are shaped from these choices only, on the standard R15 body, so nobody
-- brings an arbitrary Roblox avatar. Appearance never affects stats. Hair and face asset IDs are 0 until the art
-- pass picks catalog assets; until then those choices show no hair and the default face. Hair colour is kept for
-- when hair assets come in colour variants.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	-- Gender is part of who the character is. It never changes the body: animations and equipment are made for
	-- one body shape, so every character keeps the same one (owner, L-66). Never affects stats.
	genders = {
		{ id = "Male", displayName = "Male" },
		{ id = "Female", displayName = "Female" },
	},
	skinTones = {
		{ id = "Fair", color = { 245, 215, 190 } },
		{ id = "Light", color = { 230, 190, 160 } },
		{ id = "Warm", color = { 205, 160, 125 } },
		{ id = "Olive", color = { 180, 140, 100 } },
		{ id = "Brown", color = { 140, 95, 65 } },
		{ id = "Deep", color = { 95, 60, 40 } },
	},
	hairStyles = {
		{ id = "Short", displayName = "Short", assetId = 0 },
		{ id = "Long", displayName = "Long", assetId = 0 },
		{ id = "Braided", displayName = "Braided", assetId = 0 },
		{ id = "Shaved", displayName = "Shaved", assetId = 0 },
	},
	hairColors = {
		{ id = "Black", color = { 25, 20, 20 } },
		{ id = "Brown", color = { 90, 60, 40 } },
		{ id = "Auburn", color = { 140, 60, 35 } },
		{ id = "Blond", color = { 220, 190, 120 } },
		{ id = "Ash", color = { 170, 170, 165 } },
		{ id = "White", color = { 235, 235, 230 } },
	},
	faces = {
		{ id = "Calm", displayName = "Calm", assetId = 0 },
		{ id = "Determined", displayName = "Determined", assetId = 0 },
		{ id = "Gentle", displayName = "Gentle", assetId = 0 },
	},
	-- Starting clothes until outfits exist.
	clothing = { torso = { 70, 60, 50 }, legs = { 50, 45, 40 } },
})
