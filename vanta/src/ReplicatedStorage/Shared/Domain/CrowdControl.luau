--!strict
-- Crowd control (class specification: never permanent, bosses included). Each control on the same target within the
-- window lasts a fraction of the one before (diminishing returns); after the maximum number the target is immune until
-- the window passes. Every duration is capped.
local CrowdControl = {}

-- Returns how long this control actually lasts (0 when the target is immune), and updates the target's record.
function CrowdControl.apply(record: any, seconds: number, now: number, rules: any): number
	if now >= (record.resetAt or 0) then
		record.count = 0
	end
	record.count = record.count or 0
	if record.count >= rules.maxStacks or seconds <= 0 then
		return 0
	end
	local effective = math.min(seconds, rules.maxSeconds) * (rules.falloff ^ record.count)
	record.count += 1
	record.resetAt = now + rules.window
	return effective
end

return CrowdControl
