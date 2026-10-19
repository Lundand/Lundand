--!strict
-- Robux products other than cosmetics (cosmetics are listed in Config/Cosmetics). Only cosmetics and
-- community donations are sold (L-33). productId 0 means the developer product hasn't been created on the
-- Creator Dashboard yet. Donation tiers: one developer product per amount, priced exactly at robux
-- (L-47); the amount recorded is what Roblox reports as spent.
-- Enable each tier once its developer product exists.
local Table = require(script.Parent.Parent.Util.Table)

return Table.deepFreeze({
	CosmeticPlaceholderAura = {
		id = "CosmeticPlaceholderAura",
		kind = "Cosmetic",
		productId = 0,
		enabled = false,
		entitlementId = "PlaceholderAura",
	},
	RiftDonation10 = { id = "RiftDonation10", kind = "RiftDonation", robux = 10, productId = 0, enabled = false },
	RiftDonation25 = { id = "RiftDonation25", kind = "RiftDonation", robux = 25, productId = 0, enabled = false },
	RiftDonation50 = { id = "RiftDonation50", kind = "RiftDonation", robux = 50, productId = 0, enabled = false },
	RiftDonation100 = { id = "RiftDonation100", kind = "RiftDonation", robux = 100, productId = 0, enabled = false },
	RiftDonation250 = { id = "RiftDonation250", kind = "RiftDonation", robux = 250, productId = 0, enabled = false },
	RiftDonation500 = { id = "RiftDonation500", kind = "RiftDonation", robux = 500, productId = 0, enabled = false },
	RiftDonation1000 = { id = "RiftDonation1000", kind = "RiftDonation", robux = 1000, productId = 0, enabled = false },
	RiftDonation2500 = { id = "RiftDonation2500", kind = "RiftDonation", robux = 2500, productId = 0, enabled = false },
	RiftDonation5000 = { id = "RiftDonation5000", kind = "RiftDonation", robux = 5000, productId = 0, enabled = false },
	RiftDonation10000 = { id = "RiftDonation10000", kind = "RiftDonation", robux = 10000, productId = 0, enabled = false },
})
