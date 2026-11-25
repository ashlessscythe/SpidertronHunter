-- UPS stress: a big fleet of hunters against many nests. Checks the per-tick budgets hold
-- (think stagger, path request queue) and that no hunter is starved, and logs how much Lua time
-- the mod's two periodic handlers use (LuaProfiler output cannot be compared in Lua, so timing is
-- reported in the log as "[stress] ..." lines rather than asserted).
-- Tagged "stress": slow, excluded from the default run. Run: scripts/run_factorio_tests.sh --run "stress"
local H = require("tests/factorio/helpers")
local surface, zoom_to, spawn_hunter, spawn_enemy, distance =
  H.surface, H.zoom_to, H.spawn_hunter, H.spawn_enemy, H.distance

local ai_mod = require("scripts.ai")
local States = require("scripts.states")
local pathfinder = require("scripts.pathfinder")
local settings_mod = require("scripts.settings")

local function call(method, ...) return remote.call("SpidertronHunter", method, ...) end

local function set_setting(name, value)
  local old = settings.global[name].value
  settings.global[name] = { value = value }
  storage.settings_cache = nil
  after_test(function()
    settings.global[name] = { value = old }
    storage.settings_cache = nil
  end)
end

--- Fleet of `count` hunters in a grid north of the arena centre, `nests` small nests to the south.
local function build(count, nests)
  local hunters = {}
  local cols = 10
  for i = 0, count - 1 do
    local x = -72 + (i % cols) * 16
    local y = -120 + math.floor(i / cols) * 14
    local spider = spawn_hunter(x, y)
    hunters[#hunters + 1] = { spider = spider, start = { x = x, y = y } }
  end
  for n = 1, nests do
    local x = -110 + (n - 1) * (220 / math.max(1, nests - 1))
    spawn_enemy("biter-spawner", x, 100)
    for b = 1, 4 do spawn_enemy("small-biter", x + b * 2, 106) end
  end
  return hunters
end

local function run_stress(count, nests, seconds)
  H.clear_lake(); H.clear_arena()
  set_setting("sh-alert-level", "off")
  zoom_to(0, 0, 0.1)
  -- A lake between fleet and nests makes the hunters request lake-aware paths all at once.
  H.make_lake(-100, -10, 100, 10)
  local hunters = build(count, nests)
  for _, h in ipairs(hunters) do call("enable", h.spider) end

  local cfg = settings_mod.get()
  local budget = cfg.spiders_per_think

  -- Instrument the mod's periodic handlers. control.lua looks both up on the module tables at
  -- call time, so swapping the fields is enough; restored after the test.
  local orig_think, orig_update, orig_reset = ai_mod.think_all, States.update, pathfinder.on_tick_reset_budget
  local think_profile, reset_profile = helpers.create_profiler(true), helpers.create_profiler(true)
  local profiler = helpers.create_profiler()
  local in_think, updates_this_think = false, 0
  local max_updates, thinks = 0, 0
  local seen = {}
  local max_queue = 0
  -- Per-window (10 s) averages show whether cost settles after the cold start.
  local win_think, win_reset = helpers.create_profiler(true), helpers.create_profiler(true)
  local win_thinks = 0
  ai_mod.think_all = function(...)
    in_think, updates_this_think = true, 0
    profiler.reset()
    orig_think(...)
    profiler.stop()
    think_profile.add(profiler)
    win_think.add(profiler)
    win_thinks = win_thinks + 1
    in_think = false
    thinks = thinks + 1
    max_updates = math.max(max_updates, updates_this_think)
  end
  States.update = function(ai, ...)
    if in_think then
      updates_this_think = updates_this_think + 1
      seen[ai.unit_number or 0] = true
    end
    return orig_update(ai, ...)
  end
  pathfinder.on_tick_reset_budget = function(...)
    profiler.reset()
    orig_reset(...)
    profiler.stop()
    reset_profile.add(profiler)
    win_reset.add(profiler)
    max_queue = math.max(max_queue, #(storage.path_queue or {}))
  end
  after_test(function()
    ai_mod.think_all, States.update, pathfinder.on_tick_reset_budget = orig_think, orig_update, orig_reset
  end)

  local start = game.tick
  local limit = 60 * seconds
  local moved_far = {}
  local function moved_count()
    local c = 0
    for i, h in ipairs(hunters) do
      if moved_far[i] then c = c + 1 end
    end
    return c
  end

  async(limit + 600)
  on_tick(function()
    local elapsed = game.tick - start
    if elapsed % 600 == 0 then
      log(string.format("[stress] %d hunters t=%ds moved=%d queue=%d", count, math.floor(elapsed / 60), moved_count(), max_queue))
      if elapsed > 0 and win_thinks > 0 then
        win_think.divide(win_thinks); win_reset.divide(600)
        log({ "", "[stress]   last 10s: think_all avg ", win_think, " per call, path handler avg ", win_reset, " per tick" })
        win_think, win_reset = helpers.create_profiler(true), helpers.create_profiler(true)
        win_thinks = 0
      end
    end
    for i, h in ipairs(hunters) do
      assert(h.spider.valid, "hunter " .. i .. " died")
      if not moved_far[i] and distance(h.spider.position, h.start) > 12 then moved_far[i] = true end
    end
    if elapsed < limit then return end

    local seen_count = 0
    for _ in pairs(seen) do seen_count = seen_count + 1 end
    log(string.format("[stress] %d hunters, %d nests, %ds: %d thinks, max %d updates/think (budget %d), max path queue %d",
      count, nests, math.floor(elapsed / 60), thinks, max_updates, budget, max_queue))
    local avg_think, avg_reset = helpers.create_profiler(true), helpers.create_profiler(true)
    avg_think.add(think_profile); avg_think.divide(math.max(1, thinks))
    avg_reset.add(reset_profile); avg_reset.divide(math.max(1, elapsed))
    log({ "", "[stress] think_all avg per call: ", avg_think, "  (total ", think_profile, ")" })
    log({ "", "[stress] path budget tick handler avg per tick: ", avg_reset, "  (total ", reset_profile, ")" })

    assert(thinks > 0, "think_all never ran")
    assert(max_updates <= budget, "think_all updated " .. max_updates .. " hunters in one call (budget " .. budget .. ")")
    assert(seen_count >= count, "only " .. seen_count .. "/" .. count .. " hunters were ever thought about (starved)")
    assert(moved_count() >= count, "only " .. moved_count() .. "/" .. count .. " hunters got going within " .. seconds .. "s")
    -- At most 8 requests start per tick and a think queues at most 8 hunters' worth, so the queue
    -- should stay tiny; a deep backlog means requests pile up faster than they drain.
    assert(max_queue <= count * 4, "path queue grew to " .. max_queue)
    done()
  end)
end

tags("stress")
describe("fleet stress", function()
  after_each(function() H.clear_arena(); H.clear_lake() end)
  test("50 hunters, 10 nests: budgets hold and nobody is starved", function() run_stress(50, 10, 40) end)
  test("100 hunters, 10 nests: budgets hold and nobody is starved", function() run_stress(100, 10, 60) end)
end)
