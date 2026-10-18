--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local RiftDonations = require(ServerScriptService:WaitForChild("Server").Domain.RiftDonations)

return function(t)
	t.test("each purchase always lands in the same shard", function()
		for _, purchaseId in ipairs({ "a", "purchase-123", "zz-999" }) do
			local index = RiftDonations.shardIndex(purchaseId, 8)
			t.truthy(index >= 1 and index <= 8)
			t.equal(RiftDonations.shardIndex(purchaseId, 8), index)
		end
	end)

	t.test("a retried delivery is counted once", function()
		local shards = { RiftDonations.newShard(), RiftDonations.newShard() }
		t.truthy(RiftDonations.addToShard(shards[1], "p1", 100))
		t.falsy(RiftDonations.addToShard(shards[1], "p1", 100))
		RiftDonations.addToShard(shards[2], "p2", 250)
		t.equal(RiftDonations.total(shards), 350)
		local progress = RiftDonations.progress(350, 1000)
		t.equal(progress.remaining, 650)
		t.near(progress.fraction, 0.35, 0.0001)
		t.equal(RiftDonations.progress(1500, 1000).fraction, 1)
	end)

	t.test("the Rift opens exactly once, then closes after its hours", function()
		local event = RiftDonations.newEvent("RIFT_0001")
		t.falsy(RiftDonations.tryOpen(event, 900, 1000, 0, 10), "target not reached")
		t.truthy(RiftDonations.tryOpen(event, 1000, 1000, 50, 10))
		t.falsy(RiftDonations.tryOpen(event, 5000, 1000, 60, 10), "a second server's update changes nothing")
		t.equal(event.openedAt, 50)
		t.equal(RiftDonations.status(event, 50 + 10 * 3600 - 1), "Open")
		t.equal(RiftDonations.status(event, 50 + 10 * 3600), "Closed")
	end)
end
