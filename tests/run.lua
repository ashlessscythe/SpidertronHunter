--- Expanded pure-Lua tests. Run with: lua tests/run.lua
--- Requires no Factorio runtime; scripts that touch game APIs are mocked lightly.

local harness = require("tests.harness")

package.path = "./?.lua;./?/init.lua;" .. package.path

-- Minimal Factorio-ish globals used by required modules.
storage = storage or {}
game = game or { tick = 0 }
log = log or function() end
script = script or {
  register_on_object_destroyed = function()
    return 1
  end,
}

local util = require("scripts.util")
local schema = require("scripts.schema")
local settings_mod = require("scripts.settings")
local States = require("scripts.states")

---------------------------------------------------------------------------
-- util
---------------------------------------------------------------------------

harness.run("util.distance 3-4-5", function()
  harness.assert_eq(util.distance({ x = 0, y = 0 }, { x = 3, y = 4 }), 5)
end)

harness.run("util.distance_squared", function()
  harness.assert_eq(util.distance_squared({ x = 1, y = 2 }, { x = 4, y = 6 }), 25)
end)

harness.run("util.chunk_key origin / +x / negative", function()
  harness.assert_eq(util.chunk_key({ x = 0, y = 0 }), 0)
  harness.assert_eq(util.chunk_key({ x = 32, y = 0 }), 65536)
  harness.assert_eq(util.chunk_key({ x = -1, y = -1 }), (-1) * 65536 + (-1))
  harness.assert_eq(util.chunk_key({ x = 31.9, y = 0 }), 0)
end)

harness.run("util.is_allowed_spidertron_name denylist", function()
  harness.assert_true(util.is_allowed_spidertron_name("spidertron"))
  harness.assert_true(util.is_allowed_spidertron_name("spidertron-mk2"))
  harness.assert_false(util.is_allowed_spidertron_name("constructron"))
  harness.assert_false(util.is_allowed_spidertron_name("constructron-rocket-powered"))
  harness.assert_false(util.is_allowed_spidertron_name("deconstructron"))
  harness.assert_false(util.is_allowed_spidertron_name("ss-docked-spidertron"))
  harness.assert_false(util.is_allowed_spidertron_name(nil))
end)

harness.run("util.is_valid_spidertron", function()
  harness.assert_false(util.is_valid_spidertron(nil))
  harness.assert_false(util.is_valid_spidertron({ valid = false }))
  harness.assert_false(util.is_valid_spidertron({
    valid = true,
    type = "car",
    name = "spidertron",
  }))
  harness.assert_false(util.is_valid_spidertron({
    valid = true,
    type = "spider-vehicle",
    name = "constructron",
  }))
  harness.assert_true(util.is_valid_spidertron({
    valid = true,
    type = "spider-vehicle",
    name = "spidertron",
  }))
end)

harness.run("util.defense_ratio hull only", function()
  local spider = { valid = true, health = 500, max_health = 1000 }
  harness.assert_near(util.defense_ratio(spider, false), 0.5)
end)

harness.run("util.defense_ratio with shields", function()
  local spider = {
    valid = true,
    health = 500,
    max_health = 1000,
    grid = {
      equipment = {
        { max_shield = 100, shield = 50 },
        { max_shield = 0, shield = 0 },
        { max_shield = 50, shield = 25 },
      },
    },
  }
  -- (500+50+25) / (1000+100+50) = 575/1150
  harness.assert_near(util.defense_ratio(spider, true), 575 / 1150)
end)

harness.run("util.for_n_of iterates and resumes", function()
  local tbl = { a = 1, b = 2, c = 3, d = 4 }
  local seen = {}
  local cursor, _, done = util.for_n_of(tbl, nil, 2, function(v, k)
    seen[k] = v
  end)
  harness.assert_false(done)
  local count = 0
  for _ in pairs(seen) do
    count = count + 1
  end
  harness.assert_eq(count, 2)

  local seen2 = {}
  cursor, _, done = util.for_n_of(tbl, cursor, 10, function(v, k)
    seen2[k] = v
  end)
  harness.assert_true(done)
  local count2 = 0
  for _ in pairs(seen2) do
    count2 = count2 + 1
  end
  harness.assert_eq(count2, 2)
end)

---------------------------------------------------------------------------
-- settings defaults
---------------------------------------------------------------------------

harness.run("settings DEFAULTS cover combat + retreat", function()
  local d = settings_mod.DEFAULTS
  harness.assert_eq(d.combat_style, "strafe")
  harness.assert_eq(d.combat_range, 22)
  harness.assert_eq(d.post_combat_linger_ticks, 900)
  harness.assert_eq(d.retreat_health_percent, 25)
  harness.assert_true(d.retreat_include_shields)
  harness.assert_false(d.reengage_after_retreat)
  harness.assert_false(d.sticky_home_on_first_enable)
  harness.assert_eq(d.scan_interval, 60)
  harness.assert_eq(d.spiders_per_think, 8)
end)

---------------------------------------------------------------------------
-- FSM states
---------------------------------------------------------------------------

harness.run("nine FSM state constants", function()
  local names = {
    States.IDLE,
    States.PATROL,
    States.SEARCH,
    States.MOVING,
    States.ATTACKING,
    States.RETURNING,
    States.RESTOCKING,
    States.REENGAGING,
    States.WAITING,
  }
  harness.assert_eq(#names, 9)
  for i = 1, #names do
    harness.assert_true(schema.VALID_STATES[names[i]], names[i])
  end
end)

harness.run("States.transition invokes exit/enter", function()
  local log = {}
  States.register("test_a", {
    enter = function()
      log[#log + 1] = "a_enter"
    end,
    exit = function()
      log[#log + 1] = "a_exit"
    end,
    update = function() end,
  })
  States.register("test_b", {
    enter = function()
      log[#log + 1] = "b_enter"
    end,
    exit = function()
      log[#log + 1] = "b_exit"
    end,
    update = function() end,
  })
  local ai = { state = "test_a" }
  game.tick = 42
  States.transition(ai, "test_b")
  harness.assert_eq(ai.state, "test_b")
  harness.assert_eq(ai.state_entered_tick, 42)
  harness.assert_eq(log[1], "a_exit")
  harness.assert_eq(log[2], "b_enter")
end)

---------------------------------------------------------------------------
-- scanner pursuit gating (mirrored pure logic)
---------------------------------------------------------------------------

harness.run("allowed_target near-home vs deployed", function()
  local NEAR_HOME = 64
  local function allowed(home, spider_pos, enemy_pos, max_pursuit, search_radius)
    if util.distance(spider_pos, enemy_pos) > search_radius then
      return false
    end
    if util.distance(home, spider_pos) <= NEAR_HOME then
      return util.distance(home, enemy_pos) <= max_pursuit
    end
    return true
  end

  local home = { x = 0, y = 0 }
  -- Near home: reject enemy beyond max_pursuit even if within search_radius of spider.
  harness.assert_false(allowed(home, { x = 10, y = 0 }, { x = 600, y = 0 }, 512, 256))
  -- Near home: accept enemy within max_pursuit and search_radius.
  harness.assert_true(allowed(home, { x = 10, y = 0 }, { x = 200, y = 0 }, 512, 256))
  -- Deployed: accept enemy within search_radius regardless of home distance.
  harness.assert_true(allowed(home, { x = 100, y = 0 }, { x = 300, y = 0 }, 512, 256))
  -- Still reject beyond search_radius when deployed.
  harness.assert_false(allowed(home, { x = 100, y = 0 }, { x = 400, y = 0 }, 512, 256))
end)

---------------------------------------------------------------------------
-- soft claim scoring
---------------------------------------------------------------------------

harness.run("soft claim prefers unclaimed then nearest", function()
  local function score_entry(dsq, claimer, spider_unit, prioritization, entry_type)
    local score = dsq
    if claimer and claimer ~= spider_unit then
      score = score + 1e6
    end
    if prioritization == "spawners-first" then
      if entry_type == "unit-spawner" then
        score = score - 1e10
      elseif entry_type == "turret" then
        score = score - 1e9
      end
    elseif prioritization == "units-first" and entry_type == "unit" then
      score = score - 1e10
    end
    return score
  end

  local unclaimed = score_entry(100, nil, 1, "nearest", "unit")
  local claimed = score_entry(100, 2, 1, "nearest", "unit")
  harness.assert_true(unclaimed < claimed)

  local spawner = score_entry(500, nil, 1, "spawners-first", "unit-spawner")
  local unit = score_entry(10, nil, 1, "spawners-first", "unit")
  harness.assert_true(spawner < unit)
end)

---------------------------------------------------------------------------
-- combat reposition timing (pure)
---------------------------------------------------------------------------

harness.run("combat should_reposition spacing + pause", function()
  local function should_reposition(ai, dist, range, style, tick, move_interval, pause, urgent)
    if urgent then
      return true
    end
    if dist < range * 0.65 or dist > range * 1.35 then
      if not ai.combat_next_move_tick or tick >= ai.combat_next_move_tick then
        return true
      end
    end
    if style == "hold" then
      return false
    end
    local last = ai.combat_last_move_tick or 0
    if tick < last + pause then
      return false
    end
    if tick < last + move_interval then
      return false
    end
    return true
  end

  local ai = { combat_last_move_tick = 100, combat_next_move_tick = 145 }
  harness.assert_true(should_reposition(ai, 5, 22, "strafe", 200, 90, 45, false)) -- too close
  harness.assert_false(should_reposition(ai, 22, 22, "hold", 200, 90, 45, false))
  harness.assert_false(should_reposition(ai, 22, 22, "strafe", 120, 90, 45, false)) -- in pause
  harness.assert_true(should_reposition(ai, 22, 22, "strafe", 200, 90, 45, false))
  harness.assert_true(should_reposition(ai, 22, 22, "strafe", 100, 90, 45, true)) -- acid
end)

harness.run("combat flank_sign deterministic by unit_number", function()
  local function flank_sign(unit_number)
    return (unit_number % 2 == 0) and 1 or -1
  end
  harness.assert_eq(flank_sign(2), 1)
  harness.assert_eq(flank_sign(3), -1)
end)

---------------------------------------------------------------------------
-- multi-select toggle policy
---------------------------------------------------------------------------

harness.run("multi-select: any off → enable all; all on → disable all", function()
  local function decide(enabled_flags)
    local all_enabled = true
    for i = 1, #enabled_flags do
      if not enabled_flags[i] then
        all_enabled = false
        break
      end
    end
    return all_enabled and "disable" or "enable"
  end
  harness.assert_eq(decide({ true, true, true }), "disable")
  harness.assert_eq(decide({ true, false, true }), "enable")
  harness.assert_eq(decide({ false, false }), "enable")
end)

---------------------------------------------------------------------------
-- toggle debounce
---------------------------------------------------------------------------

harness.run("toggle debounce one per player per tick", function()
  local last = {}
  local function should_handle(player_index, tick)
    if last[player_index] == tick then
      return false
    end
    last[player_index] = tick
    return true
  end
  harness.assert_true(should_handle(1, 10))
  harness.assert_false(should_handle(1, 10))
  harness.assert_true(should_handle(2, 10))
  harness.assert_true(should_handle(1, 11))
end)

---------------------------------------------------------------------------
-- path queue: one pending job per spider
---------------------------------------------------------------------------

harness.run("path queue replaces older job for same spider", function()
  local function enqueue(queue, item)
    local dst = {}
    for i = 1, #queue do
      if queue[i].unit_number ~= item.unit_number then
        dst[#dst + 1] = queue[i]
      end
    end
    dst[#dst + 1] = item
    return dst
  end

  local q = {
    { unit_number = 1, goal = { x = 0, y = 0 } },
    { unit_number = 2, goal = { x = 1, y = 1 } },
  }
  q = enqueue(q, { unit_number = 1, goal = { x = 9, y = 9 } })
  harness.assert_eq(#q, 2)
  harness.assert_eq(q[1].unit_number, 2)
  harness.assert_eq(q[2].unit_number, 1)
  harness.assert_eq(q[2].goal.x, 9)
end)

harness.run("path queue clear_queue_for filters one spider", function()
  local function clear_for(queue, unit_number)
    local dst = {}
    for i = 1, #queue do
      if queue[i].unit_number ~= unit_number then
        dst[#dst + 1] = queue[i]
      end
    end
    return dst
  end
  local q = {
    { unit_number = 1 },
    { unit_number = 2 },
    { unit_number = 1 },
  }
  q = clear_for(q, 1)
  harness.assert_eq(#q, 1)
  harness.assert_eq(q[1].unit_number, 2)
end)

---------------------------------------------------------------------------
-- after-combat linger
---------------------------------------------------------------------------

harness.run("after_combat_clear linger then return", function()
  local function after_combat_clear(ai, tick, return_home, linger)
    if not return_home then
      ai.post_combat_since = nil
      return "patrol"
    end
    ai.post_combat_since = ai.post_combat_since or tick
    if tick - ai.post_combat_since >= linger then
      ai.post_combat_since = nil
      return "returning"
    end
    return "patrol"
  end

  local ai = {}
  harness.assert_eq(after_combat_clear(ai, 100, true, 900), "patrol")
  harness.assert_eq(ai.post_combat_since, 100)
  harness.assert_eq(after_combat_clear(ai, 999, true, 900), "patrol")
  harness.assert_eq(after_combat_clear(ai, 1000, true, 900), "returning")
  harness.assert_eq(ai.post_combat_since, nil)
  harness.assert_eq(after_combat_clear({}, 0, false, 900), "patrol")
end)

---------------------------------------------------------------------------
-- tactical retreat threshold
---------------------------------------------------------------------------

harness.run("tactical retreat when below threshold", function()
  local function should_retreat(ratio, threshold_percent)
    if threshold_percent <= 0 then
      return false
    end
    return ratio * 100 < threshold_percent
  end
  harness.assert_true(should_retreat(0.2, 25))
  harness.assert_false(should_retreat(0.5, 25))
  harness.assert_false(should_retreat(0.1, 0))
end)

harness.run("re-engage after restock only when toggled and origin set", function()
  local function next_after_restock(reengage, has_origin)
    if reengage and has_origin then
      return "reengaging"
    end
    return "patrol"
  end
  harness.assert_eq(next_after_restock(false, true), "patrol")
  harness.assert_eq(next_after_restock(true, false), "patrol")
  harness.assert_eq(next_after_restock(true, true), "reengaging")
  harness.assert_eq(next_after_restock(false, false), "patrol")
end)

---------------------------------------------------------------------------
-- schema / migrations
---------------------------------------------------------------------------

harness.run("schema.ensure_storage creates expected keys", function()
  storage = {}
  schema.ensure_storage()
  harness.assert_true(type(storage.spiders) == "table")
  harness.assert_true(type(storage.enemy_cache) == "table")
  harness.assert_true(type(storage.target_claims) == "table")
  harness.assert_true(type(storage.path_queue) == "table")
  harness.assert_true(type(storage.path_requests) == "table")
  harness.assert_true(type(storage.path_statuses) == "table")
  harness.assert_true(type(storage.destroy_regs) == "table")
  harness.assert_eq(storage.next_cache_id, 1)
end)

harness.run("schema.migrate_ai_records sanitizes bad state and claims", function()
  storage = {
    spiders = {
      [10] = {
        state = "bogus",
        home = { x = 5 },
        combat_style = "spin",
        keep_player_destination = true,
        pending_goal = { x = 1, y = 2 },
      },
      [11] = {
        state = "attacking",
        home = { surface_index = 2, x = 1, y = 2 },
        combat_style = "flank",
      },
    },
    target_claims = {
      [100] = 10,
      [101] = 999, -- orphan
    },
    path_requests = { [1] = {} },
    path_statuses = { [10] = {} },
    path_queue = { { unit_number = 10 } },
  }
  schema.migrate_ai_records()

  harness.assert_eq(storage.spiders[10].state, "idle")
  harness.assert_eq(storage.spiders[10].home.y, 0)
  harness.assert_eq(storage.spiders[10].home.surface_index, 1)
  harness.assert_false(storage.spiders[10].home_sticky)
  harness.assert_eq(storage.spiders[10].combat_style, nil)
  harness.assert_eq(storage.spiders[10].keep_player_destination, nil)
  harness.assert_eq(storage.spiders[10].pending_goal, nil)
  harness.assert_eq(storage.spiders[11].state, "attacking")
  harness.assert_eq(storage.spiders[11].combat_style, "flank")
  harness.assert_false(storage.spiders[11].home_sticky)
  harness.assert_eq(storage.target_claims[100], 10)
  harness.assert_eq(storage.target_claims[101], nil)
  harness.assert_eq(#storage.path_queue, 0)
  harness.assert_eq(next(storage.path_requests), nil)
end)

---------------------------------------------------------------------------
-- Sticky home
---------------------------------------------------------------------------

harness.run("sticky home enable policy", function()
  --- Mirrors ai.enable home assignment.
  local function apply_home_on_enable(ai, spider_pos, sticky_setting)
    if not sticky_setting or not ai.home_sticky then
      ai.home = {
        surface_index = spider_pos.surface_index,
        x = spider_pos.x,
        y = spider_pos.y,
      }
      if sticky_setting then
        ai.home_sticky = true
      end
    end
  end

  local function set_home(ai, pos)
    ai.home = { surface_index = pos.surface_index, x = pos.x, y = pos.y }
    ai.home_sticky = true
  end

  local function clear_home(ai)
    ai.home_sticky = false
  end

  -- Sticky off: always overwrite, never pin via enable.
  local ai_off = {
    home = { surface_index = 1, x = 0, y = 0 },
    home_sticky = false,
  }
  apply_home_on_enable(ai_off, { surface_index = 1, x = 10, y = 20 }, false)
  harness.assert_eq(ai_off.home.x, 10)
  harness.assert_eq(ai_off.home.y, 20)
  harness.assert_false(ai_off.home_sticky)
  apply_home_on_enable(ai_off, { surface_index = 1, x = 99, y = 88 }, false)
  harness.assert_eq(ai_off.home.x, 99)
  harness.assert_eq(ai_off.home.y, 88)

  -- Sticky on + unpinned: capture and pin.
  local ai_on = {
    home = { surface_index = 1, x = 0, y = 0 },
    home_sticky = false,
  }
  apply_home_on_enable(ai_on, { surface_index = 1, x = 5, y = 6 }, true)
  harness.assert_eq(ai_on.home.x, 5)
  harness.assert_eq(ai_on.home.y, 6)
  harness.assert_true(ai_on.home_sticky)

  -- Sticky on + pinned: keep home across re-enable.
  apply_home_on_enable(ai_on, { surface_index = 1, x = 100, y = 200 }, true)
  harness.assert_eq(ai_on.home.x, 5)
  harness.assert_eq(ai_on.home.y, 6)
  harness.assert_true(ai_on.home_sticky)

  -- Clear then enable refreshes.
  clear_home(ai_on)
  harness.assert_false(ai_on.home_sticky)
  apply_home_on_enable(ai_on, { surface_index = 1, x = 7, y = 8 }, true)
  harness.assert_eq(ai_on.home.x, 7)
  harness.assert_eq(ai_on.home.y, 8)
  harness.assert_true(ai_on.home_sticky)

  -- Set home pins even when sticky setting is off.
  local ai_set = {
    home = { surface_index = 1, x = 1, y = 1 },
    home_sticky = false,
  }
  set_home(ai_set, { surface_index = 2, x = 3, y = 4 })
  harness.assert_eq(ai_set.home.x, 3)
  harness.assert_eq(ai_set.home.y, 4)
  harness.assert_eq(ai_set.home.surface_index, 2)
  harness.assert_true(ai_set.home_sticky)
end)

---------------------------------------------------------------------------
-- GUI style index
---------------------------------------------------------------------------

harness.run("combat style dropdown index", function()
  local STYLE_ORDER = { "hold", "strafe", "circle", "flank" }
  local function style_index(style)
    for i = 1, #STYLE_ORDER do
      if STYLE_ORDER[i] == style then
        return i
      end
    end
    return 2
  end
  harness.assert_eq(style_index("hold"), 1)
  harness.assert_eq(style_index("strafe"), 2)
  harness.assert_eq(style_index("circle"), 3)
  harness.assert_eq(style_index("flank"), 4)
  harness.assert_eq(style_index("unknown"), 2)
end)

---------------------------------------------------------------------------
-- patrols soft-dep handoff
---------------------------------------------------------------------------

local patrols = require("scripts.patrols")

local function stub_patrols_remote(state)
  remote = {
    interfaces = {
      SpidertronPatrols = {
        get_patrol_data = true,
        set_on_patrol = true,
      },
    },
    call = function(iface, fn, spidertron, arg)
      harness.assert_eq(iface, "SpidertronPatrols")
      if fn == "get_patrol_data" then
        return { on_patrol = state.on_patrol, waypoints = state.waypoints or {} }
      end
      if fn == "set_on_patrol" then
        state.last_set = arg
        if arg then
          state.on_patrol = state.on_patrol or {}
        else
          state.on_patrol = nil
        end
        return
      end
      error("unknown remote " .. tostring(fn))
    end,
  }
  return state
end

harness.run("patrols no-op when interface absent", function()
  remote = { interfaces = {} }
  local spider = { valid = true }
  harness.assert_false(patrols.is_available())
  harness.assert_eq(patrols.get_was_auto(spider), nil)
  harness.assert_eq(patrols.capture_was_auto(spider), nil)
  harness.assert_false(patrols.set_manual(spider))
  harness.assert_false(patrols.restore(spider, true))
  harness.assert_false(patrols.restore(spider, false))
  harness.assert_false(patrols.restore(spider, nil))
end)

harness.run("patrols get_was_auto true/false", function()
  local state = stub_patrols_remote({ on_patrol = {} })
  harness.assert_true(patrols.get_was_auto({}))
  state.on_patrol = nil
  harness.assert_false(patrols.get_was_auto({}))
end)

harness.run("patrols capture assumes manual when read fails (no GUI)", function()
  -- Mirrors SpidertronPatrols remote that calls get_patrol_data but omits return.
  remote = {
    interfaces = {
      SpidertronPatrols = {
        get_patrol_data = true,
        set_on_patrol = true,
      },
    },
    call = function(iface, fn, spidertron, arg)
      if fn == "get_patrol_data" then
        return nil
      end
      if fn == "set_on_patrol" then
        remote._last_set = arg
        return
      end
    end,
  }
  game = { players = {} }
  harness.assert_true(patrols.is_available())
  harness.assert_eq(patrols.get_was_auto({}), nil)
  harness.assert_false(patrols.capture_was_auto({}))
  harness.assert_true(patrols.set_manual({}))
  harness.assert_eq(remote._last_set, false)
  -- Must not flip manual schedules to auto on disable.
  harness.assert_false(patrols.restore({}, false))
  harness.assert_eq(remote._last_set, false)
end)

harness.run("patrols capture reads open schedule switch", function()
  remote = {
    interfaces = {
      SpidertronPatrols = {
        get_patrol_data = true,
        set_on_patrol = true,
      },
    },
    call = function()
      return nil
    end,
  }
  local spider = { name = "spider" }
  local switch = {
    valid = true,
    name = "on_patrol_switch",
    type = "switch",
    switch_state = "left",
    children = {},
  }
  game = {
    players = {
      {
        valid = true,
        opened = spider,
        gui = {
          relative = {
            ["sp-relative-frame"] = {
              valid = true,
              name = "sp-relative-frame",
              children = { switch },
            },
          },
        },
      },
    },
  }
  harness.assert_true(patrols.capture_was_auto(spider))
  switch.switch_state = "right"
  harness.assert_false(patrols.capture_was_auto(spider))
end)

harness.run("patrols set_manual and restore previous auto", function()
  local state = stub_patrols_remote({ on_patrol = {} })
  harness.assert_true(patrols.capture_was_auto({}))
  harness.assert_true(patrols.set_manual({}))
  harness.assert_eq(state.last_set, false)
  harness.assert_eq(state.on_patrol, nil)
  harness.assert_true(patrols.restore({}, true))
  harness.assert_eq(state.last_set, true)
  harness.assert_true(state.on_patrol ~= nil)
end)

harness.run("patrols restore only when was auto", function()
  local state = stub_patrols_remote({ on_patrol = nil })
  harness.assert_false(patrols.capture_was_auto({}))
  harness.assert_false(patrols.restore({}, false))
  harness.assert_eq(state.last_set, nil)
  harness.assert_false(patrols.restore({}, nil))
  harness.assert_eq(state.last_set, nil)
end)

harness.run("patrols pcall survives remote errors", function()
  remote = {
    interfaces = {
      SpidertronPatrols = {
        get_patrol_data = true,
        set_on_patrol = true,
      },
    },
    call = function()
      error("boom")
    end,
  }
  game = { players = {} }
  harness.assert_eq(patrols.get_was_auto({}), nil)
  -- Unreadable → assume manual (do not restore auto)
  harness.assert_false(patrols.capture_was_auto({}))
  harness.assert_false(patrols.set_manual({}))
  harness.assert_false(patrols.restore({}, true))
end)

---------------------------------------------------------------------------
-- info.json / packaging name
---------------------------------------------------------------------------

harness.run("info.json name and version for portal zip", function()
  local f = assert(io.open("info.json", "r"))
  local raw = f:read("*a")
  f:close()
  local name = raw:match('"name"%s*:%s*"([^"]+)"')
  local version = raw:match('"version"%s*:%s*"([^"]+)"')
  harness.assert_eq(name, "SpidertronHunter")
  harness.assert_true(version:match("^%d+%.%d+%.%d+$") ~= nil, "semver")
  local zip = name .. "_" .. version .. ".zip"
  harness.assert_eq(zip, "SpidertronHunter_" .. version .. ".zip")
end)

harness.run("migration files exist for schema versions", function()
  for _, ver in ipairs({ "0.1.0", "0.1.5", "0.1.7", "0.1.9", "0.1.15" }) do
    local path = "migrations/" .. ver .. ".lua"
    local f = io.open(path, "r")
    harness.assert_true(f ~= nil, "missing " .. path)
    if f then
      f:close()
    end
  end
end)

---------------------------------------------------------------------------

if not harness.summary() then
  os.exit(1)
end

print("SpidertronHunter pure tests OK")
