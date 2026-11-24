--- Pure-Lua tests for threat awareness (nest danger vs hunter capacity, remembered verdicts).

local harness = require("tests.harness")
local threat = require("scripts.threat")
local settings_mod = require("scripts.settings")

local function setup(mode, alert_level)
  storage = {
    settings_cache = setmetatable(
      { threat_awareness = mode, alert_level = alert_level or "off" },
      { __index = settings_mod.DEFAULTS }
    ),
  }
  game.tick = 1000
end

local function worms(name, n)
  local list = {}
  for i = 1, n do
    list[i] = { name = name, type = "turret", valid = true }
  end
  return list
end

--- Spider mock; `found` is what the surface returns for the area query.
local function make_spider(health, found, shield)
  local queries = { n = 0 }
  local spider = {
    valid = true,
    health = health,
    force = { connected_players = {} },
    entity_label = "T",
    surface = {
      find_entities_filtered = function(args)
        queries.n = queries.n + 1
        queries.last = args
        return found
      end,
    },
    grid = shield and { equipment = { { shield = shield } } } or nil,
  }
  return spider, queries
end

harness.run("threat: points scale with worm tier, spawners are cheap, units are free", function()
  harness.assert_eq(threat.points("small-worm-turret", "turret"), 3)
  harness.assert_eq(threat.points("medium-worm-turret", "turret"), 6)
  harness.assert_eq(threat.points("big-worm-turret", "turret"), 12)
  harness.assert_eq(threat.points("behemoth-worm-turret", "turret"), 30)
  harness.assert_eq(threat.points("biter-spawner", "unit-spawner"), 1)
  harness.assert_eq(threat.points("small-biter", "unit"), 0)
  harness.assert_true(threat.points("modded-flame-turret", "turret") > 0)
end)

harness.run("threat: danger sums entities and ignores invalid ones", function()
  local list = worms("medium-worm-turret", 3)
  list[#list + 1] = { name = "biter-spawner", type = "unit-spawner", valid = true }
  list[#list + 1] = { name = "big-worm-turret", type = "turret", valid = false }
  harness.assert_eq(threat.danger(list), 3 * 6 + 1)
end)

harness.run("threat: capacity counts hull and shields and scales by mode", function()
  setup("normal")
  harness.assert_near(threat.capacity({ health = 3000 }, "normal"), 100, 1e-9)
  harness.assert_near(threat.capacity({ health = 3000 }, "cautious"), 50, 1e-9)
  harness.assert_near(threat.capacity({ health = 3000, grid = { equipment = { { shield = 600 }, {} } } }, "normal"), 120, 1e-9)
  harness.assert_eq(threat.capacity({ health = 3000 }, "off"), nil)
end)

harness.run("threat: a damaged hunter has less capacity", function()
  harness.assert_true(threat.capacity({ health = 600 }, "normal") < threat.capacity({ health = 3000 }, "normal"))
end)

harness.run("threat: judge accepts a small nest and rejects a heavily defended one", function()
  setup("normal")
  local small = make_spider(3000, worms("medium-worm-turret", 6)) -- 36 < 100
  harness.assert_true(threat.judge({}, small, { x = 0, y = 0 }))
  local big = make_spider(3000, worms("behemoth-worm-turret", 4)) -- 120 > 100
  harness.assert_false(threat.judge({}, big, { x = 0, y = 0 }))
end)

harness.run("threat: cautious mode is stricter than normal", function()
  setup("normal")
  local spider = make_spider(3000, worms("medium-worm-turret", 12)) -- 72: under 100, over 50
  harness.assert_true(threat.judge({}, spider, { x = 0, y = 0 }))
  setup("cautious")
  harness.assert_false(threat.judge({}, spider, { x = 0, y = 0 }))
end)

harness.run("threat: a damaged hunter avoids a nest it would have taken on at full health", function()
  setup("normal")
  local found = worms("medium-worm-turret", 8) -- 48
  harness.assert_true(threat.judge({}, make_spider(3000, found), { x = 0, y = 0 }))
  harness.assert_false(threat.judge({}, make_spider(1000, found), { x = 0, y = 0 })) -- capacity ~33
end)

harness.run("threat: off mode and scouts are never blocked and never search", function()
  setup("off")
  local spider, queries = make_spider(100, worms("behemoth-worm-turret", 10))
  harness.assert_true(threat.judge({}, spider, { x = 0, y = 0 }))
  setup("normal")
  harness.assert_true(threat.judge({ role = "scout" }, spider, { x = 0, y = 0 }))
  harness.assert_eq(queries.n, 0)
end)

harness.run("threat: the assessed area is enemy turrets and spawners around the target", function()
  setup("normal")
  local spider, queries = make_spider(3000, {})
  threat.judge({}, spider, { x = 5, y = 6 })
  harness.assert_eq(queries.last.position.x, 5)
  harness.assert_eq(queries.last.radius, threat.ASSESS_RADIUS)
  harness.assert_eq(queries.last.force, "enemy")
end)

harness.run("threat: verdicts are remembered so the area is not re-searched every scan", function()
  setup("normal")
  local ai = {}
  local spider, queries = make_spider(3000, worms("behemoth-worm-turret", 4))
  harness.assert_false(threat.judge(ai, spider, { x = 0, y = 0 }))
  harness.assert_false(threat.judge(ai, spider, { x = 10, y = 10 })) -- inside the zone
  harness.assert_false(threat.judge(ai, spider, { x = 0, y = 30 }))
  harness.assert_eq(queries.n, 1)
  threat.judge(ai, spider, { x = 500, y = 0 }) -- far away: a fresh assessment
  harness.assert_eq(queries.n, 2)
end)

harness.run("threat: an avoid verdict expires", function()
  setup("normal")
  local ai = {}
  local spider, queries = make_spider(3000, worms("behemoth-worm-turret", 4))
  harness.assert_false(threat.judge(ai, spider, { x = 0, y = 0 }))
  game.tick = game.tick + threat.AVOID_TICKS + 1
  -- hunter has been repaired/rearmed since: same nest is fine now
  spider, queries = make_spider(9000, worms("behemoth-worm-turret", 4))
  harness.assert_true(threat.judge(ai, spider, { x = 0, y = 0 }))
  harness.assert_eq(queries.n, 1)
end)

harness.run("threat: avoid beats safe where zones overlap", function()
  setup("normal")
  local ai = { threat_zones = {
    { x = 0, y = 0, radius = 40, verdict = "safe", expires = 5000 },
    { x = 10, y = 0, radius = 40, verdict = "avoid", expires = 5000 },
  } }
  harness.assert_eq(threat.remembered_verdict(ai, { x = 5, y = 0 }, 1000), "avoid")
end)

harness.run("threat: zone memory is bounded", function()
  setup("normal")
  local ai = {}
  local spider = make_spider(3000, {})
  for i = 1, 40 do
    threat.judge(ai, spider, { x = i * 1000, y = 0 })
  end
  harness.assert_true(#ai.threat_zones <= 16)
end)

harness.run("threat: avoiding a nest raises an alert when alerts are on", function()
  setup("normal", "important")
  local alerted = {}
  local spider = make_spider(3000, worms("behemoth-worm-turret", 4))
  spider.force = {
    connected_players = { { valid = true, add_custom_alert = function(_, _, msg) alerted[#alerted + 1] = msg end } },
  }
  spider.position = { x = 0, y = 0 }
  threat.judge({}, spider, { x = 0, y = 0 })
  harness.assert_eq(#alerted, 1)
  harness.assert_eq(alerted[1][1], "sh.alert-too-dangerous")
  harness.assert_eq(alerted[1][3], "120")
end)

harness.run("threat: settings default and locale keys exist", function()
  harness.assert_eq(settings_mod.DEFAULTS.threat_awareness, "normal")
  local f = assert(io.open("locale/en/spidertron-hunter.cfg", "r"))
  local cfg = f:read("*a")
  f:close()
  for _, key in ipairs({ "sh-threat-awareness", "alert-too-dangerous" }) do
    harness.assert_true(cfg:find(key .. "=", 1, true) ~= nil, "missing locale key " .. key)
  end
end)

harness.run("threat: an easily-handled nest scores well under a healthy hunter's capacity", function()
  -- Calibration anchor: 2 spawners + 2 medium + 1 small worm (a nest that cost ~250 hp in-game).
  local nest = worms("medium-worm-turret", 2)
  nest[#nest + 1] = { name = "small-worm-turret", type = "turret", valid = true }
  nest[#nest + 1] = { name = "biter-spawner", type = "unit-spawner", valid = true }
  nest[#nest + 1] = { name = "spitter-spawner", type = "unit-spawner", valid = true }
  local danger = threat.danger(nest)
  harness.assert_eq(danger, 17)
  harness.assert_true(danger < threat.capacity({ health = 3000 }, "cautious"))
end)
