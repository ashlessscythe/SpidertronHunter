--- Pure-Lua tests for scanner target selection, mainly the "nearest" mode fallback past a
--- nest that threat awareness rejected.

local harness = require("tests.harness")
local scanner = require("scripts.scanner")
local settings_mod = require("scripts.settings")

local function enemy(name, type, x, y)
  return { valid = true, name = name, type = type, position = { x = x, y = y }, surface_index = 1 }
end

--- Hunter at the origin. `world` is every enemy; area queries return those within radius.
--- Nest A (dangerous: big worms) is nearest, nest B (one small worm) is farther.
local function setup(world, health, opts)
  opts = opts or {}
  storage = {
    enemy_cache = {},
    target_claims = {},
    next_cache_id = 1,
    settings_cache = setmetatable({
      threat_awareness = opts.mode or "normal",
      alert_level = "off",
      enemy_prioritization = opts.prioritization or "nearest",
      search_radius = 256,
      max_pursuit_distance = 512,
    }, { __index = settings_mod.DEFAULTS }),
  }
  game = { tick = 1000, forces = { enemy = {} } }
  local queries = 0
  local surface = {}
  function surface.find_nearest_enemy()
    local best, best_d
    for _, e in ipairs(world) do
      local d = e.position.x ^ 2 + e.position.y ^ 2
      if e.valid and (not best_d or d < best_d) then
        best, best_d = e, d
      end
    end
    return best
  end
  function surface.find_entities_filtered(args)
    queries = queries + 1
    local out = {}
    local types
    if args.type then
      types = {}
      for _, t in ipairs(type(args.type) == "table" and args.type or { args.type }) do
        types[t] = true
      end
    end
    for _, e in ipairs(world) do
      local dx, dy = e.position.x - args.position.x, e.position.y - args.position.y
      if e.valid and (not types or types[e.type]) and dx * dx + dy * dy <= args.radius ^ 2 then
        out[#out + 1] = e
      end
    end
    return out
  end
  local spider = {
    valid = true,
    type = "spider-vehicle",
    name = "spidertron",
    health = health,
    unit_number = 7,
    surface_index = 1,
    surface = surface,
    force = { connected_players = {}, is_enemy = function() return true end },
    entity_label = "T",
    position = { x = 0, y = 0 },
  }
  surface.spider = spider
  local ai = { entity = spider, unit_number = 7, home = { x = 0, y = 0 } }
  return spider, ai, function() return queries end
end

local function nest_a() -- 2 big worms = 24 points, plus a spawner and biters
  return {
    enemy("big-worm-turret", "turret", 60, 0),
    enemy("big-worm-turret", "turret", 66, 0),
    enemy("biter-spawner", "unit-spawner", 63, 5),
    enemy("small-biter", "unit", 58, 2),
  }
end

local function nest_b() -- 1 small worm + spawner = 4 points
  return {
    enemy("small-worm-turret", "turret", 0, 120),
    enemy("biter-spawner", "unit-spawner", 3, 124),
  }
end

local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, e in ipairs(list) do
      out[#out + 1] = e
    end
  end
  return out
end

harness.run("scanner: nearest mode falls back to the next safe nest when the nearest is too dangerous", function()
  local a, b = nest_a(), nest_b()
  -- 600 hp / 30 = 20 capacity: nest A (24+1) is rejected, nest B (4) is fine.
  local spider, ai = setup(concat(a, b), 600)
  local target = scanner.scan_for_enemy(ai)
  harness.assert_true(target ~= nil, "must pick a target instead of idling")
  harness.assert_true(target.position.y >= 100, "target must be in nest B, got y=" .. target.position.y)
end)

harness.run("scanner: fallback picks the nearest acceptable enemy, not just any", function()
  local b_near = enemy("small-biter", "unit", 0, 90)
  local b_far = enemy("small-biter", "unit", 0, 200)
  local spider, ai = setup(concat(nest_a(), { b_far, b_near }), 600)
  harness.assert_eq(scanner.scan_for_enemy(ai), b_near)
end)

harness.run("scanner: nearest mode idles when every nest is too dangerous", function()
  local spider, ai = setup(nest_a(), 600)
  harness.assert_eq(scanner.scan_for_enemy(ai), nil)
end)

harness.run("scanner: healthy hunter still goes for the nearest nest", function()
  local a = nest_a()
  local spider, ai = setup(concat(a, nest_b()), 3000)
  local target = scanner.scan_for_enemy(ai)
  harness.assert_true(target.position.x >= 50, "should attack nest A, got x=" .. target.position.x)
end)

harness.run("scanner: awareness off ignores danger and takes the nearest", function()
  local spider, ai = setup(concat(nest_a(), nest_b()), 600, { mode = "off" })
  local target = scanner.scan_for_enemy(ai)
  harness.assert_true(target.position.x >= 50, "should attack nest A, got x=" .. target.position.x)
end)

harness.run("scanner: a big rejected nest costs one assessment, not one per enemy", function()
  local crowd = {}
  for i = 1, 40 do
    crowd[#crowd + 1] = enemy("medium-biter", "unit", 55 + (i % 8), i % 5)
  end
  local spider, ai, queries = setup(concat(nest_a(), crowd, nest_b()), 600)
  local target = scanner.scan_for_enemy(ai)
  harness.assert_true(target and target.position.y >= 100, "must reach nest B past the crowd")
  -- nest A assessment + fallback listing + nest B assessment
  harness.assert_true(queries() <= 4, "too many area queries: " .. queries())
end)

harness.run("scanner: fallback is skipped for non-nearest prioritisation", function()
  local spider, ai = setup(nest_a(), 600, { prioritization = "units-first" })
  harness.assert_eq(scanner.scan_for_enemy(ai), nil)
end)
