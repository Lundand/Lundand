--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local RateLimiter = require(ServerScriptService:WaitForChild("Server").Net.RateLimiter)

return function(t)
	t.test("allows a burst, then refills over time", function()
		local now = 0
		local limiter = RateLimiter.new(3, 1, function()
			return now
		end)
		t.truthy(limiter:allow("p"))
		t.truthy(limiter:allow("p"))
		t.truthy(limiter:allow("p"))
		t.falsy(limiter:allow("p"), "burst used up")
		t.truthy(limiter:allow("other"), "separate key")
		now = 2
		t.truthy(limiter:allow("p"))
		t.truthy(limiter:allow("p"))
		t.falsy(limiter:allow("p"))
	end)
end
