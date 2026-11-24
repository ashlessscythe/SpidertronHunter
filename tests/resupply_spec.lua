--- Pure-Lua tests: after a failed restock the hunter waits at home instead of ping-ponging.

local harness = require("tests.harness")
local States = require("scripts.states")
local settings_mod = require("scripts.settings")
local logistics = require("scripts.logistics")
local common = require("scripts.ai_common")
require("scripts.ai_states")

local function setup(overrides)
  storage = {
    spiders = {},
    path_statuses = {},
    path_queue = {},
    target_claims = {},
    settings_cache = setmetatable(overrides or {}, { __index = settings_mod.DEFAULTS }),
  }
  game.tick = 5000
end

local function make_spider(health)
  return {
    valid = true,
    type = "spider-vehicle",
    name = "spidertron",
    unit_number = 7,
    health = health or 3000,
    max_health = 3000,
    position = { x = 0, y = 0 },
    surface_index = 1,
    follow_target = nil,
    autopilot_destination = nil,
    force = { connected_players = {} },
  }
end

local function make_ai(spider, state)
  return {
    entity = spider,
    unit_number = spider.unit_number,
    role = "hunter",
    state = state,
    state_entered_tick = game.tick,
    home = { surface_index = 1, x = 0, y = 0 },
  }
end

--- Patch logistics for one test; returns a restore function.
local function patch_logistics(low_ammo, restock_done)
  local orig_below, orig_update = logistics.ammo_below_threshold, logistics.update_restock
  logistics.ammo_below_threshold = function() return low_ammo.value end
  logistics.update_restock = function() return restock_done == nil and true or restock_done end
  return function()
    logistics.ammo_below_threshold = orig_below
    logistics.update_restock = orig_update
  end
end

harness.run("resupply_blocker: low ammo, low health, both fine, scouts, restock disabled", function()
  setup()
  local low = { value = true }
  local restore = patch_logistics(low)
  local spider = make_spider(3000)
  local ai = make_ai(spider, "restocking")
  harness.assert_eq(common.resupply_blocker(ai), "no-ammo")
  low.value = false
  harness.assert_eq(common.resupply_blocker(ai), nil)
  spider.health = 300 -- 10% < 25% retreat threshold
  harness.assert_eq(common.resupply_blocker(ai), "damaged")
  spider.health = 3000
  ai.role = "scout"
  low.value = true
  harness.assert_eq(common.resupply_blocker(ai), nil)
  ai.role = "hunter"
  setup({ restock_enabled = false })
  harness.assert_eq(common.resupply_blocker(ai), nil)
  restore()
end)

harness.run("resupply_blocker: thresholds of 0 disable the checks", function()
  setup({ restock_ammo_percent = 0, retreat_health_percent = 0 })
  local restore = patch_logistics({ value = true })
  local spider = make_spider(10)
  harness.assert_eq(common.resupply_blocker(make_ai(spider, "restocking")), nil)
  restore()
end)

harness.run("restocking gives up with no ammo: hunter waits at home and does not resume", function()
  setup()
  local low = { value = true }
  local restore = patch_logistics(low)
  local spider = make_spider(3000)
  local ai = make_ai(spider, "restocking")
  storage.spiders[7] = ai
  States.update(ai)
  harness.assert_eq(ai.state, "waiting")
  harness.assert_eq(ai.wait_reason, "no-ammo")
  -- still no ammo many think cycles later: stays parked (this used to ping-pong every 60 s)
  for i = 1, 5 do
    game.tick = game.tick + 600
    States.update(ai)
  end
  harness.assert_eq(ai.state, "waiting")
  harness.assert_eq(ai.wait_reason, "no-ammo")
  restore()
end)

harness.run("waiting for ammo resumes patrol as soon as ammo is back", function()
  setup()
  local low = { value = true }
  local restore = patch_logistics(low)
  local spider = make_spider(3000)
  local ai = make_ai(spider, "restocking")
  storage.spiders[7] = ai
  States.update(ai)
  harness.assert_eq(ai.state, "waiting")
  low.value = false -- player (or bots) topped up the ammo
  game.tick = game.tick + 60
  States.update(ai)
  harness.assert_eq(ai.state, "patrol")
  harness.assert_eq(ai.wait_reason, nil)
  restore()
end)

harness.run("restocking gives up while damaged: waits for repair, then resumes", function()
  setup()
  local restore = patch_logistics({ value = false })
  local spider = make_spider(300)
  local ai = make_ai(spider, "restocking")
  storage.spiders[7] = ai
  States.update(ai)
  harness.assert_eq(ai.state, "waiting")
  harness.assert_eq(ai.wait_reason, "damaged")
  spider.health = 3000
  game.tick = game.tick + 60
  States.update(ai)
  harness.assert_eq(ai.state, "patrol")
  restore()
end)

harness.run("restocking finishing with ammo and health restored goes straight to patrol", function()
  setup()
  local restore = patch_logistics({ value = false })
  local ai = make_ai(make_spider(3000), "restocking")
  storage.spiders[7] = ai
  States.update(ai)
  harness.assert_eq(ai.state, "patrol")
  restore()
end)

harness.run("waiting for resupply re-engages the retreat origin when that setting is on", function()
  setup({ reengage_after_retreat = true })
  local low = { value = true }
  local restore = patch_logistics(low)
  local ai = make_ai(make_spider(3000), "restocking")
  ai.retreat_origin = { surface_index = 1, x = 50, y = 50 }
  storage.spiders[7] = ai
  States.update(ai)
  harness.assert_eq(ai.state, "waiting")
  low.value = false
  game.tick = game.tick + 60
  local orig_go_to = require("scripts.movement").go_to
  require("scripts.movement").go_to = function() end
  States.update(ai)
  require("scripts.movement").go_to = orig_go_to
  harness.assert_eq(ai.state, "reengaging")
  restore()
end)
