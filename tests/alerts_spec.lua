--- Pure-Lua tests for player alerts: levels, cooldown, stuck counting, death message.

local harness = require("tests.harness")
local alerts = require("scripts.alerts")
local settings_mod = require("scripts.settings")

local function setup(level)
  storage = { settings_cache = setmetatable({ alert_level = level }, { __index = settings_mod.DEFAULTS }) }
  game.tick = 1000
end

local function make_force(n_players)
  local calls, printed = {}, {}
  local players = {}
  for i = 1, n_players do
    players[i] = {
      valid = true,
      add_custom_alert = function(entity, icon, message, on_map)
        calls[#calls + 1] = { entity = entity, icon = icon, message = message, on_map = on_map }
      end,
    }
  end
  return {
    connected_players = players,
    print = function(message, color) printed[#printed + 1] = { message = message, color = color } end,
  }, calls, printed
end

local function make_spider(force, label)
  return {
    valid = true,
    name = "spidertron",
    entity_label = label,
    localised_name = { "entity-name.spidertron" },
    force = force,
    position = { x = 10.7, y = -3.2 },
    surface = { name = "nauvis" },
  }
end

harness.run("alerts: level off shows nothing; important skips low-ammo; all shows it", function()
  setup("off")
  harness.assert_false(alerts.is_enabled("retreat"))
  harness.assert_false(alerts.is_enabled("died"))
  setup("important")
  harness.assert_true(alerts.is_enabled("retreat"))
  harness.assert_true(alerts.is_enabled("stuck"))
  harness.assert_true(alerts.is_enabled("died"))
  harness.assert_false(alerts.is_enabled("low-ammo"))
  setup("all")
  harness.assert_true(alerts.is_enabled("low-ammo"))
  harness.assert_false(alerts.is_enabled("unknown-kind"))
end)

harness.run("alerts: notify sends a custom alert to every connected player on the force", function()
  setup("important")
  local force, calls = make_force(2)
  local spider = make_spider(force, "Alpha")
  local ai = {}
  harness.assert_true(alerts.notify(spider, "retreat", ai, "18"))
  harness.assert_eq(#calls, 2)
  harness.assert_true(calls[1].entity == spider)
  harness.assert_true(calls[1].on_map)
  harness.assert_eq(calls[1].message[1], "sh.alert-retreat")
  harness.assert_eq(calls[1].message[2], "Alpha")
  harness.assert_eq(calls[1].message[3], "18")
end)

harness.run("alerts: unlabeled spidertron falls back to its localised name", function()
  setup("important")
  local force, calls = make_force(1)
  local spider = make_spider(force, "")
  alerts.notify(spider, "stuck", {})
  harness.assert_eq(calls[1].message[2][1], "entity-name.spidertron")
end)

harness.run("alerts: same kind is throttled per spider, other kinds and spiders are not", function()
  setup("all")
  local force, calls = make_force(1)
  local a, b = make_spider(force, "A"), make_spider(force, "B")
  local ai_a, ai_b = {}, {}
  harness.assert_true(alerts.notify(a, "retreat", ai_a, "10"))
  harness.assert_false(alerts.notify(a, "retreat", ai_a, "9")) -- cooldown
  harness.assert_true(alerts.notify(a, "low-ammo", ai_a)) -- different kind
  harness.assert_true(alerts.notify(b, "retreat", ai_b, "10")) -- different spider
  harness.assert_eq(#calls, 3)
  game.tick = game.tick + alerts.COOLDOWN_TICKS
  harness.assert_true(alerts.notify(a, "retreat", ai_a, "8")) -- cooldown over
end)

harness.run("alerts: disabled level, invalid spider or missing AI record show nothing", function()
  setup("off")
  local force, calls = make_force(1)
  local spider = make_spider(force, "A")
  harness.assert_false(alerts.notify(spider, "retreat", {}, "10"))
  setup("all")
  harness.assert_false(alerts.notify(spider, "retreat", nil, "10"))
  spider.valid = false
  harness.assert_false(alerts.notify(spider, "retreat", {}, "10"))
  harness.assert_eq(#calls, 0)
end)

harness.run("alerts: stuck alert fires after repeated re-paths in the same place", function()
  setup("important")
  local force, calls = make_force(1)
  local spider = make_spider(force, "A")
  local ai = {}
  alerts.on_stuck_repath(spider, ai)
  alerts.on_stuck_repath(spider, ai)
  harness.assert_eq(#calls, 0)
  alerts.on_stuck_repath(spider, ai)
  harness.assert_eq(#calls, 1)
  harness.assert_eq(calls[1].message[1], "sh.alert-stuck")
  harness.assert_eq(ai.stuck_count, 0)
end)

harness.run("alerts: moving away resets the stuck counter", function()
  setup("important")
  local force, calls = make_force(1)
  local spider = make_spider(force, "A")
  local ai = {}
  alerts.on_stuck_repath(spider, ai)
  alerts.on_stuck_repath(spider, ai)
  spider.position = { x = 200, y = 0 } -- freed itself, then got stuck somewhere else
  alerts.on_stuck_repath(spider, ai)
  harness.assert_eq(ai.stuck_count, 1)
  harness.assert_eq(#calls, 0)
end)

harness.run("alerts: stuck counting ignores spiders without an AI record", function()
  setup("important")
  local force, calls = make_force(1)
  alerts.on_stuck_repath(make_spider(force, "A"), nil)
  harness.assert_eq(#calls, 0)
end)

harness.run("alerts: died prints a chat line with a map ping and honours the level", function()
  setup("important")
  local force, _, printed = make_force(1)
  local spider = make_spider(force, "Alpha")
  harness.assert_true(alerts.died(spider))
  harness.assert_eq(#printed, 1)
  harness.assert_eq(printed[1].message[1], "sh.alert-died")
  harness.assert_eq(printed[1].message[2], "Alpha")
  harness.assert_eq(printed[1].message[3], "[gps=10,-4,nauvis]")
  setup("off")
  harness.assert_false(alerts.died(spider))
  harness.assert_eq(#printed, 1)
end)

harness.run("alerts: settings default and locale keys exist", function()
  harness.assert_eq(settings_mod.DEFAULTS.alert_level, "important")
  local f = assert(io.open("locale/en/spidertron-hunter.cfg", "r"))
  local cfg = f:read("*a")
  f:close()
  for _, key in ipairs({ "alert-retreat", "alert-stuck", "alert-low-ammo", "alert-died", "sh-alert-level" }) do
    harness.assert_true(cfg:find(key .. "=", 1, true) ~= nil, "missing locale key " .. key)
  end
end)

harness.run("alerts: out-of-ammo and needs-repair are important and re-alert only rarely", function()
  setup("important")
  harness.assert_true(alerts.is_enabled("out-of-ammo"))
  harness.assert_true(alerts.is_enabled("needs-repair"))
  local force, calls = make_force(1)
  local spider = make_spider(force, "A")
  local ai = {}
  harness.assert_true(alerts.notify(spider, "out-of-ammo", ai))
  game.tick = game.tick + alerts.COOLDOWN_TICKS + 1 -- normal cooldown has passed...
  harness.assert_false(alerts.notify(spider, "out-of-ammo", ai)) -- ...but these repeat far less often
  game.tick = game.tick + 18000
  harness.assert_true(alerts.notify(spider, "out-of-ammo", ai))
  harness.assert_eq(#calls, 2)
end)
