--!strict
-- Minimal test framework. The same specs run in Studio (through RunAll), under Lune, and in the
-- offline harness (tools/offline), so it uses nothing Roblox-specific.

local TestKit = {}

export type Failure = { suite: string, test: string, message: string }
export type Summary = { passed: number, failed: number, failures: {Failure} }

local FAILURE_TAG = "__testkitFailure"

local function describe(value: any, depth: number): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	if depth >= 3 then
		return "{...}"
	end
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, tostring(key) .. " = " .. describe(value[key], depth + 1))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function fail(label: string?, message: string)
	local text = message
	if label then
		text = label .. ": " .. message
	end
	error({ [FAILURE_TAG] = true, message = text }, 0)
end

local function newContext(tests: {any})
	local t = {}

	function t.test(name: string, fn: () -> ())
		table.insert(tests, { name = name, fn = fn })
	end

	function t.equal(actual: any, expected: any, label: string?)
		if actual ~= expected then
			fail(label, "expected " .. describe(expected, 0) .. ", got " .. describe(actual, 0))
		end
	end

	function t.deepEqual(actual: any, expected: any, label: string?)
		if not deepEqual(actual, expected) then
			fail(label, "expected " .. describe(expected, 0) .. ", got " .. describe(actual, 0))
		end
	end

	function t.truthy(value: any, label: string?)
		if not value then
			fail(label, "expected a truthy value, got " .. describe(value, 0))
		end
	end

	function t.falsy(value: any, label: string?)
		if value then
			fail(label, "expected a falsy value, got " .. describe(value, 0))
		end
	end

	function t.near(actual: any, expected: number, tolerance: number, label: string?)
		if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
			fail(label, "expected " .. tostring(expected) .. " +/- " .. tostring(tolerance) .. ", got " .. describe(actual, 0))
		end
	end

	function t.errors(fn: () -> (), label: string?)
		local ok = pcall(fn)
		if ok then
			fail(label, "expected an error")
		end
	end

	return t
end

function TestKit.run(suites: {any}, log: ((string) -> ())?): Summary
	local write = log or print
	local summary = { passed = 0, failed = 0, failures = {} }

	local function record(suiteName: string, testName: string, err: any)
		local message = "error: " .. tostring(err)
		if type(err) == "table" and err[FAILURE_TAG] then
			message = err.message
		end
		summary.failed += 1
		table.insert(summary.failures, { suite = suiteName, test = testName, message = message })
	end

	for _, suite in ipairs(suites) do
		local tests = {}
		local defined, defineError = pcall(suite.define, newContext(tests))
		if not defined then
			record(suite.name, "(defining tests)", defineError)
		end
		for _, case in ipairs(tests) do
			local ok, err = pcall(case.fn)
			if ok then
				summary.passed += 1
			else
				record(suite.name, case.name, err)
			end
		end
	end

	for _, failure in ipairs(summary.failures) do
		write("FAIL " .. failure.suite .. " > " .. failure.test .. ": " .. failure.message)
	end
	write(string.format("%d passed, %d failed", summary.passed, summary.failed))
	return summary
end

return TestKit
