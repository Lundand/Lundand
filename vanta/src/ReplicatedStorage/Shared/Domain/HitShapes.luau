--!strict
-- Where attacks land (class specification: aimed and directional abilities). Melee arcs, straight lines
-- (projectiles, optionally piercing) and areas at an aimed point. Positions are flattened to the ground plane.
-- The server uses these with positions it trusts; an aimed point from a client is only a request, kept in range.
local HitShapes = {}

function HitShapes.arc(origin: Vector3, facing: Vector3, target: Vector3, range: number, arc: number, leniency: number?): boolean
	local dx, dz = target.X - origin.X, target.Z - origin.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > range + (leniency or 0) then
		return false
	end
	if distance < 0.5 or arc >= 360 then
		return true
	end
	local fx, fz = facing.X, facing.Z
	local length = math.sqrt(fx * fx + fz * fz)
	if length == 0 then
		return false
	end
	local cosine = (dx * fx + dz * fz) / (distance * length)
	return cosine >= math.cos(math.rad(arc / 2))
end

-- Returns whether the target is on the line, and how far along it (for travel time and ordering).
function HitShapes.line(origin: Vector3, direction: Vector3, target: Vector3, range: number, radius: number): (boolean, number)
	local length = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
	if length == 0 then
		return false, 0
	end
	local ux, uz = direction.X / length, direction.Z / length
	local dx, dz = target.X - origin.X, target.Z - origin.Z
	local along = dx * ux + dz * uz
	if along < 0 or along > range then
		return false, along
	end
	return math.abs(dx * uz - dz * ux) <= radius, along
end

function HitShapes.area(center: Vector3, target: Vector3, radius: number): boolean
	local dx, dz = target.X - center.X, target.Z - center.Z
	return dx * dx + dz * dz <= radius * radius
end

-- An aimed point, kept within reach of the origin.
function HitShapes.clampTarget(origin: Vector3, requested: Vector3, maxRange: number): Vector3
	local offset = Vector3.new(requested.X - origin.X, 0, requested.Z - origin.Z)
	if offset.Magnitude <= maxRange then
		return Vector3.new(requested.X, origin.Y, requested.Z)
	end
	local clamped = offset.Unit * maxRange
	return Vector3.new(origin.X + clamped.X, origin.Y, origin.Z + clamped.Z)
end

-- Damage reduction from active defences: frontal ones only count against attacks from the front; capped.
function HitShapes.reduction(defenses: {any}, now: number, fromFront: boolean, cap: number): number
	local total = 0
	for _, defense in ipairs(defenses) do
		if now < defense.untilTime and (not defense.frontal or fromFront) then
			total += defense.reduction
		end
	end
	return math.clamp(total, -0.5, cap) -- negative: vulnerability (Unyielding Rage), at most 50 percent more damage
end

return HitShapes
