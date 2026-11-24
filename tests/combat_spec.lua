-- Laser-aware combat range.
local harness = require("tests.harness")
local combat = require("scripts.combat")

local function spider(has_laser)
  local finds = 0
  local grid = { valid = true, find = function(name) finds = finds + 1; return (has_laser and name == "personal-laser-defense-equipment") and {} or nil end }
  return { valid = true, grid = grid }, function() return finds end
end

harness.run("effective_range: setting off keeps combat range", function()
  game = { tick = 0 }
  local s = spider(true)
  harness.assert_eq(combat.effective_range({}, s, { combat_range = 22, laser_aware = false }), 22)
end)

harness.run("effective_range: lasers shrink the range, cached between checks", function()
  game = { tick = 0 }
  local s, finds = spider(true)
  local ai = {}
  local cfg = { combat_range = 22, laser_aware = true }
  harness.assert_eq(combat.effective_range(ai, s, cfg), 12)
  game.tick = 100
  harness.assert_eq(combat.effective_range(ai, s, cfg), 12)
  harness.assert_eq(finds(), 1)
  game.tick = 400
  combat.effective_range(ai, s, cfg)
  harness.assert_eq(finds(), 2)
end)

harness.run("effective_range: no lasers or short range is unchanged", function()
  game = { tick = 0 }
  harness.assert_eq(combat.effective_range({}, (spider(false)), { combat_range = 22, laser_aware = true }), 22)
  harness.assert_eq(combat.effective_range({}, (spider(true)), { combat_range = 10, laser_aware = true }), 10)
end)
