--!nocheck
-- lune run tools/run-tests.luau   (from the vanta folder) — runs ServerStorage.Tests.RunAll offline.
local Harness = require("./harness")
Harness.loadSource("src")
local summary = Harness.require(Harness.find("ServerStorage.Tests.RunAll"))()
Harness.exit(if summary.failed == 0 then 0 else 1)
