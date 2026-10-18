--!strict
-- Cosmetic catalogue (L-33, L-34, L-46). Robux only, appearance only: nothing here changes stats, drops,
-- XP or access. To add a cosmetic, add an entry and its assets. Never delete an entry that has been sold:
-- set status = "Retired" so owners keep it, and take its developer product off sale on the Creator
-- Dashboard. productId 0 means the developer product hasn't been created yet, so it can't be bought.
-- Fields: id, displayName, description, category, price (Robux; must equal the Dashboard price, which the
-- server checks at startup), productId, status ("Active" | "Retired"), preview (image asset ID, 0 = none
-- yet), startsAt / endsAt (optional Unix seconds: limited-time), collection (optional, such as a Rift
-- theme), classes (optional: who can wear it), weaponType (weapon skins).
-- Limited quantities are not offered: purchases can't be reserved or refunded automatically, so stock
-- could be oversold. Only time limits exist, and only time limits are advertised.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	categories = { "Outfit", "WeaponSkin", "Cloak", "Mask", "Accessory", "Aura", "Effect", "Pet" },
	items = {
		NavyWardenCloak = {
			id = "NavyWardenCloak",
			displayName = "Navy Warden's Cloak",
			description = "Heavy navy wool with silver clasps, as worn by the palace wardens.",
			category = "Cloak",
			price = 150,
			productId = 0,
			status = "Active",
			preview = 0,
		},
		VioletEmberAura = {
			id = "VioletEmberAura",
			displayName = "Violet Ember Aura",
			description = "Faint violet embers drift around you, like sparks from the Heart of Realms.",
			category = "Aura",
			price = 300,
			productId = 0,
			status = "Active",
			preview = 0,
		},
		SilverfangSwordSkin = {
			id = "SilverfangSwordSkin",
			displayName = "Silverfang (sword skin)",
			description = "A silver-chased guard and a blade etched with old runes. Changes how your sword looks, nothing else.",
			category = "WeaponSkin",
			weaponType = "Sword",
			classes = { "Swordmaster" },
			price = 250,
			productId = 0,
			status = "Active",
			preview = 0,
		},
		LanternWisp = {
			id = "LanternWisp",
			displayName = "Lantern Wisp",
			description = "A small wisp of lantern light that follows you around. Company, nothing more.",
			category = "Pet",
			price = 400,
			productId = 0,
			status = "Active",
			preview = 0,
		},
		RiftTouchedMask = {
			id = "RiftTouchedMask",
			displayName = "Rift-Touched Mask",
			description = "A half-mask of violet glass from the season of the first Rift.",
			category = "Mask",
			collection = "RIFT_0001",
			startsAt = 1798761600, -- placeholder dates
			endsAt = 1799971200,
			price = 200,
			productId = 0,
			status = "Active",
			preview = 0,
		},
	},
})
