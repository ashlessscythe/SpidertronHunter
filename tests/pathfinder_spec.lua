--- Pure-Lua pathfinder tests: water/lake handling, budget, queue, retries, stuck recovery.
--- Loaded from tests/run.lua. Uses a fake surface with a rectangular lake.

local harness = require("tests.harness")
local pf = require("scripts.pathfinder")

--- Fake surface: records request_path calls; `find_non_colliding_position` fails inside the lake.
local function make_surface(lake)
  local surface = { requests = {}, next_id = 1 }
  local function in_lake(p)
    return lake and p.x >= lake[1] and p.x <= lake[3] and p.y >= lake[2] and p.y <= lake[4]
  end
  surface.in_lake = in_lake
  function surface.request_path(args)
    local id = surface.next_id
    surface.next_id = id + 1
    surface.requests[#surface.requests + 1] = { id = id, args = args }
    return id
  end
  --- Snap to the nearest point just outside the lake (west shore), or nil when too far.
  function surface.find_non_colliding_position(_name, goal, radius, _step)
    if not in_lake(goal) then
      return { x = goal.x, y = goal.y }
    end
    local shore = { x = lake[1] - 1, y = goal.y }
    if goal.x - shore.x <= radius then
      return shore
    end
    return nil
  end
  return surface
end

local function make_spider(surface, unit_number, x, y)
  local added = {}
  local leg = {
    valid = true,
    name = "spidertron-leg-1",
    position = { x = x, y = y },
    prototype = { collision_mask = { layers = { water_tile = true } } },
  }
  local spider = {
    valid = true,
    type = "spider-vehicle",
    name = "spidertron",
    unit_number = unit_number,
    position = { x = x, y = y },
    surface = surface,
    force = "player",
    prototype = { height = 1.5 },
    autopilot_destination = nil,
    follow_target = nil,
    added = added,
    get_spider_legs = function() return { leg } end,
    add_autopilot_destination = function(p) added[#added + 1] = p end,
  }
  return spider
end

local function reset(spiders)
  storage = {
    spiders = spiders or {},
    path_only = {},
    path_requests = {},
    path_statuses = {},
    path_queue = {},
    path_requests_this_tick = 0,
    destroy_regs = {},
    settings_cache = {},
  }
  game.tick = 100
end

local function ai_record(role, state)
  return { role = role, state = state or "moving" }
end

local LAKE = { 0, -40, 50, 40 } -- x1, y1, x2, y2

---------------------------------------------------------------------------
-- starting a path: water / walkable snapping
---------------------------------------------------------------------------

harness.run("pathfinder: far goal on land requests a path with a tiles-only water mask", function()
  reset()
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 1, -60, 0)
  harness.assert_true(pf.request_path_to(spider, { x = -200, y = 0 }))
  harness.assert_eq(#surface.requests, 1)
  local args = surface.requests[1].args
  harness.assert_true(args.collision_mask.colliding_with_tiles_only)
  harness.assert_true(args.collision_mask.layers.water_tile)
  harness.assert_eq(args.goal.x, -200)
  harness.assert_eq(args.path_resolution_modifier, -3)
  harness.assert_eq(storage.path_requests_this_tick, 1)
end)

harness.run("pathfinder: hunter goal inside a lake is snapped to the shore for pathing but keeps the goal", function()
  reset({ [2] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 2, -60, 0)
  harness.assert_true(pf.request_path_to(spider, { x = 5, y = 0 }))
  local req = storage.path_requests[1]
  harness.assert_eq(req.target_position.x, LAKE[1] - 1) -- walkable snap
  harness.assert_eq(req.goal_position.x, 5) -- hunter keeps raw goal (combat range)
end)

harness.run("pathfinder: scout goal inside a lake with no shore in range is unreachable", function()
  reset({ [3] = ai_record("scout") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 3, -60, 0)
  spider.autopilot_destination = { x = 1, y = 1 }
  -- deep in the lake: nearest shore is farther than the search radius
  harness.assert_false(pf.request_path_to(spider, { x = 49, y = 0 }))
  harness.assert_eq(#surface.requests, 0)
  harness.assert_eq(spider.autopilot_destination, nil)
  harness.assert_eq(storage.spiders[3].path_failed_goal.x, 49)
end)

harness.run("pathfinder: scout goal in a lake near shore snaps to land", function()
  reset({ [4] = ai_record("scout") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 4, -60, 0)
  harness.assert_true(pf.request_path_to(spider, { x = 5, y = 0 }))
  local req = storage.path_requests[1]
  harness.assert_eq(req.goal_position.x, LAKE[1] - 1)
  harness.assert_eq(req.target_position.x, LAKE[1] - 1)
end)

harness.run("pathfinder: AI-off go-to inside a lake ends on the shore, not in the water", function()
  reset()
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 8, -60, 0)
  harness.assert_true(pf.request_path_to(spider, { x = 5, y = 0 }))
  local req = storage.path_requests[1]
  harness.assert_eq(req.goal_position.x, LAKE[1] - 1)
  harness.assert_eq(storage.path_only[8].pending_goal.x, LAKE[1] - 1)
  pf.on_path_finished({ id = 1, path = { { position = { x = -40, y = 0 } }, { position = { x = -20, y = 0 } } } })
  local last = spider.added[#spider.added]
  harness.assert_eq(last.x, LAKE[1] - 1)
end)

harness.run("pathfinder: hunter goal deep in a lake falls back to the raw goal", function()
  reset({ [5] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 5, -60, 0)
  harness.assert_true(pf.request_path_to(spider, { x = 49, y = 0 }))
  local req = storage.path_requests[1]
  harness.assert_eq(req.target_position.x, 49)
  harness.assert_eq(req.goal_position.x, 49)
end)

harness.run("pathfinder: short hop skips the pathfinder and walks directly to land", function()
  reset()
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 6, -5, 0)
  harness.assert_true(pf.request_path_to(spider, { x = 2, y = 0 })) -- 7 tiles, goal in lake
  harness.assert_eq(#surface.requests, 0)
  harness.assert_eq(spider.autopilot_destination.x, LAKE[1] - 1)
end)

harness.run("pathfinder: standalone (AI-off) request creates path_only state and registers destroy", function()
  reset()
  local registered = 0
  script.register_on_object_destroyed = function()
    registered = registered + 1
    return registered
  end
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 7, -60, 0)
  pf.request_path_to(spider, { x = -200, y = 0 })
  harness.assert_true(storage.path_only[7] ~= nil)
  harness.assert_eq(storage.path_only[7].pending_goal.x, -200)
  harness.assert_eq(registered, 1)
  script.register_on_object_destroyed = function() return 1 end
end)

---------------------------------------------------------------------------
-- budget and queue
---------------------------------------------------------------------------

harness.run("pathfinder: full budget queues instead of walking straight into water", function()
  reset()
  storage.path_requests_this_tick = 8
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 8, -60, 0)
  spider.autopilot_destination = { x = 1, y = 1 }
  harness.assert_true(pf.request_path_to(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 0)
  harness.assert_eq(spider.autopilot_destination, nil)
  harness.assert_eq(#storage.path_queue, 1)
  harness.assert_eq(storage.path_queue[1].kind, "start")
end)

harness.run("pathfinder: queued start runs once the budget resets", function()
  reset()
  storage.path_requests_this_tick = 8
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 9, -60, 0)
  pf.request_path_to(spider, { x = 100, y = 0 })
  harness.assert_eq(#surface.requests, 0)
  pf.on_tick_reset_budget()
  harness.assert_eq(#surface.requests, 1)
  harness.assert_eq(#storage.path_queue, 0)
  harness.assert_eq(storage.path_requests_this_tick, 1)
end)

harness.run("pathfinder: queue is FIFO and never exceeds the per-tick budget", function()
  reset()
  storage.path_requests_this_tick = 8
  local surface = make_surface(LAKE)
  local spiders = {}
  for i = 1, 12 do
    spiders[i] = make_spider(surface, 100 + i, -60, i * 3)
    storage.path_only[100 + i] = { entity = spiders[i] }
    pf.request_path_to(spiders[i], { x = 100, y = i * 3 })
  end
  harness.assert_eq(#storage.path_queue, 12)
  pf.on_tick_reset_budget()
  harness.assert_eq(#surface.requests, 8)
  harness.assert_eq(#storage.path_queue, 4)
  -- the first 8 queued spiders were served; the last 4 remain, in order
  harness.assert_eq(storage.path_queue[1].unit_number, 109)
  harness.assert_eq(storage.path_queue[4].unit_number, 112)
  pf.on_tick_reset_budget()
  harness.assert_eq(#storage.path_queue, 0)
  harness.assert_eq(#surface.requests, 12)
end)

harness.run("pathfinder: re-requesting a queued spider keeps its place with the newest goal", function()
  reset()
  storage.path_requests_this_tick = 8
  local surface = make_surface(LAKE)
  local a = make_spider(surface, 21, -60, 0)
  local b = make_spider(surface, 22, -60, 10)
  local c = make_spider(surface, 23, -60, 20)
  pf.request_path_to(a, { x = 100, y = 0 })
  pf.request_path_to(b, { x = 100, y = 10 })
  pf.request_path_to(c, { x = 100, y = 20 })
  pf.request_path_to(a, { x = 120, y = 5 }) -- goal changed while waiting
  harness.assert_eq(#storage.path_queue, 3)
  harness.assert_eq(storage.path_queue[1].unit_number, 21)
  harness.assert_eq(storage.path_queue[1].goal.x, 120)
  harness.assert_eq(storage.path_queue[2].unit_number, 22)
  harness.assert_eq(storage.path_queue[3].unit_number, 23)
end)

harness.run("pathfinder: queue drops jobs for destroyed spiders", function()
  reset()
  storage.path_requests_this_tick = 8
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 31, -60, 0)
  pf.request_path_to(spider, { x = 100, y = 0 })
  spider.valid = false
  pf.on_tick_reset_budget()
  harness.assert_eq(#surface.requests, 0)
  harness.assert_eq(#storage.path_queue, 0)
end)

---------------------------------------------------------------------------
-- engine results: busy, no path, success
---------------------------------------------------------------------------

--- Issue a request and return the engine request id plus the spider.
local function start_request(spiders, unit_number, goal)
  reset(spiders)
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, unit_number, -60, 0)
  if storage.spiders[unit_number] then
    storage.spiders[unit_number].entity = spider
  end
  pf.request_path_to(spider, goal)
  return surface, spider, 1
end

harness.run("pathfinder: try_again_later backs off instead of re-requesting immediately", function()
  local surface, _, id = start_request({ [41] = ai_record("hunter") }, 41, { x = 100, y = 0 })
  pf.on_path_finished({ id = id, try_again_later = true })
  harness.assert_eq(#surface.requests, 1) -- no immediate retry
  harness.assert_eq(#storage.path_queue, 1)
  harness.assert_eq(storage.path_queue[1].kind, "retry")
  harness.assert_true(storage.path_queue[1].not_before > game.tick)
  pf.on_tick_reset_budget()
  harness.assert_eq(#surface.requests, 1) -- still backing off
  game.tick = storage.path_queue[1].not_before
  pf.on_tick_reset_budget()
  harness.assert_eq(#surface.requests, 2)
  harness.assert_eq(#storage.path_queue, 0)
end)

harness.run("pathfinder: no path retries at coarser resolution", function()
  local surface, _, id = start_request({ [42] = ai_record("hunter") }, 42, { x = 100, y = 0 })
  pf.on_path_finished({ id = id, path = nil })
  harness.assert_eq(#surface.requests, 2)
  harness.assert_eq(surface.requests[2].args.path_resolution_modifier, -1)
  pf.on_path_finished({ id = surface.requests[2].id, path = nil })
  harness.assert_eq(#surface.requests, 3)
  harness.assert_eq(surface.requests[3].args.path_resolution_modifier, 1)
end)

harness.run("pathfinder: exhausted path makes a hunter go direct to its goal", function()
  local surface, spider, id = start_request({ [43] = ai_record("hunter") }, 43, { x = 100, y = 0 })
  pf.on_path_finished({ id = id, path = nil })
  pf.on_path_finished({ id = surface.requests[2].id, path = nil })
  pf.on_path_finished({ id = surface.requests[3].id, path = nil })
  harness.assert_eq(spider.autopilot_destination.x, 100)
  harness.assert_eq(storage.path_statuses[43][100], nil)
end)

harness.run("pathfinder: exhausted path marks a scout goal failed and never walks it", function()
  local surface, spider, id = start_request({ [44] = ai_record("scout") }, 44, { x = 100, y = 0 })
  pf.on_path_finished({ id = id, path = nil })
  pf.on_path_finished({ id = surface.requests[2].id, path = nil })
  pf.on_path_finished({ id = surface.requests[3].id, path = nil })
  harness.assert_eq(spider.autopilot_destination, nil)
  harness.assert_eq(storage.spiders[44].path_failed_goal.x, 100)
  harness.assert_eq(storage.spiders[44].pending_goal, nil)
end)

harness.run("pathfinder: lake path is thinned and ends at the goal", function()
  local _, spider, id = start_request({ [45] = ai_record("hunter") }, 45, { x = 100, y = 0 })
  -- A detour around the lake: north shore waypoints every 2 tiles.
  local path = {}
  for i = 0, 40 do
    path[#path + 1] = { position = { x = -60 + i * 4, y = -(math.sin(i / 40 * math.pi) * 45) } }
  end
  pf.on_path_finished({ id = id, path = path })
  harness.assert_true(#spider.added >= 2)
  harness.assert_true(#spider.added < #path, "waypoints must be thinned")
  local last = spider.added[#spider.added]
  harness.assert_eq(last.x, 100)
  harness.assert_eq(last.y, 0)
  -- thinned waypoints are spaced at least (height + 0.5) * 7.5 apart
  for i = 2, #spider.added - 1 do
    local a, b = spider.added[i - 1], spider.added[i]
    local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    harness.assert_true(d > 15, "waypoint spacing " .. d)
  end
  harness.assert_eq(storage.path_statuses[45][100], nil)
end)

harness.run("pathfinder: result for a superseded goal is ignored", function()
  local _, spider, id = start_request({ [46] = ai_record("hunter") }, 46, { x = 100, y = 0 })
  storage.spiders[46].pending_goal = { x = -300, y = 0 } -- AI picked a new goal meanwhile
  pf.on_path_finished({ id = id, path = { { position = { x = 0, y = -50 } } } })
  harness.assert_eq(#spider.added, 0)
end)

harness.run("pathfinder: result for a destroyed spider is dropped cleanly", function()
  local _, spider, id = start_request({ [47] = ai_record("hunter") }, 47, { x = 100, y = 0 })
  spider.valid = false
  pf.on_path_finished({ id = id, path = { { position = { x = 0, y = -50 } } } })
  harness.assert_eq(storage.path_requests[id], nil)
  harness.assert_eq(#spider.added, 0)
end)

harness.run("pathfinder: result with no matching request is a no-op", function()
  reset()
  pf.on_path_finished({ id = 999, path = {} })
  harness.assert_eq(next(storage.path_requests), nil)
end)

---------------------------------------------------------------------------
-- stuck recovery
---------------------------------------------------------------------------

harness.run("pathfinder: idle spider far from goal re-requests a path", function()
  reset({ [51] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 51, -60, 0)
  harness.assert_true(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 1)
end)

harness.run("pathfinder: moving spider that makes progress is left alone", function()
  reset({ [52] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 52, -60, 0)
  spider.autopilot_destination = { x = 100, y = 0 }
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  game.tick = game.tick + 400
  spider.position = { x = -50, y = 0 } -- moved > STUCK_MOVE_EPS
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 0)
end)

harness.run("pathfinder: spider that stops moving re-paths after the stuck window", function()
  reset({ [53] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 53, -60, 0)
  spider.autopilot_destination = { x = 100, y = 0 }
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 })) -- starts the timer
  game.tick = game.tick + 100
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 })) -- not long enough
  harness.assert_eq(#surface.requests, 0)
  game.tick = game.tick + 100 -- 200 >= STUCK_TICKS
  harness.assert_true(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 1)
end)

harness.run("pathfinder: stuck check waits while a path is in flight or queued", function()
  reset({ [54] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 54, -60, 0)
  pf.request_path_to(spider, { x = 100, y = 0 }) -- in flight
  spider.autopilot_destination = nil
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 1)
end)

harness.run("pathfinder: stuck check never overrides a player destination", function()
  reset({ [55] = { role = "hunter", state = "moving", keep_player_destination = true } })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 55, -60, 0)
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
  harness.assert_eq(#surface.requests, 0)
end)

harness.run("pathfinder: stuck check ignores spiders with no AI or path state", function()
  reset()
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 56, -60, 0)
  harness.assert_false(pf.repath_if_stuck(spider, { x = 100, y = 0 }))
end)

harness.run("pathfinder: stuck check stops near the goal", function()
  reset({ [57] = ai_record("hunter") })
  local surface = make_surface(LAKE)
  local spider = make_spider(surface, 57, -60, 0)
  harness.assert_false(pf.repath_if_stuck(spider, { x = -55, y = 0 }))
  harness.assert_eq(#surface.requests, 0)
end)
