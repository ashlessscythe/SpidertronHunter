-- Qualitative hunter/scout behaviour tests (measure what the spiders actually do).
-- Tagged "visual": slow real-time scenarios, skipped by the default headless run.
local H = require("tests/factorio/helpers")
local surface, zoom_to, spawn_hunter, spawn_enemy, distance =
  H.surface, H.zoom_to, H.spawn_hunter, H.spawn_enemy, H.distance

local function call(method, ...) return remote.call("SpidertronHunter", method, ...) end
local function state_of(spider) local d = call("get_ai_data", spider); return d and d.state end

local function set_setting(name, value)
  local old = settings.global[name].value
  settings.global[name] = { value = value }
  storage.settings_cache = nil -- script-set values don't raise the mod's change event; force a re-read
  after_test(function()
    settings.global[name] = { value = old }
    storage.settings_cache = nil
  end)
end

tags("visual")
describe("hunter behaviour", function()
  before_each(function() H.clear_lake(); H.clear_arena() end)
  after_each(function() H.clear_arena(); H.clear_lake() end)

  test("disabling mid-chase stops the spider and leaves the target alone", function()
    zoom_to(40, 0, 0.35)
    local spider = spawn_hunter(0, 0)
    local worm = spawn_enemy("small-worm-turret", 90, 0)
    call("enable", spider)
    local stop_pos
    after_ticks(60 * 4, function()
      assert(spider.position.x > 10, "hunter never started moving (x=" .. spider.position.x .. ")")
      call("disable", spider)
      assert(call("get_role", spider) == "off", "role should be off after disable")
      -- let it coast to a stop, then it must stay put
      after_ticks(60, function()
        stop_pos = { x = spider.position.x, y = spider.position.y }
        after_ticks(60 * 4, function()
          assert(distance(spider.position, stop_pos) < 1,
            "spider kept moving after disable: " .. distance(spider.position, stop_pos) .. " tiles")
          assert(worm.valid, "target was attacked after disable")
        end)
      end)
    end)
  end)

  test("hunter returns home after clearing a target", function()
    zoom_to(15, 0, 0.45)
    local spider = spawn_hunter(0, 0)
    spawn_enemy("small-worm-turret", 45, 0)
    call("enable", spider)
    local killed = false
    async(60 * 120)
    on_tick(function()
      if not killed and H.count_enemies() == 0 then killed = true end
      if killed and distance(spider.position, { x = 0, y = 0 }) < 8 then
        assert(spider.position.x < 8, "sanity")
        done()
      end
    end)
  end)

  test("default priority attacks the nearest target first", function()
    zoom_to(0, 0, 0.25)
    local spider = spawn_hunter(0, 0)
    local near = spawn_enemy("small-worm-turret", 50, 0) -- outside rocket range, so the AI must choose
    local far = spawn_enemy("small-worm-turret", -95, 0)
    call("enable", spider)
    async(60 * 120)
    on_tick(function()
      if not near.valid or not far.valid then
        assert(not near.valid and far.valid, "far target died before the near one")
        done()
      end
    end)
  end)

  test("spawners-first priority skips a nearer turret for a spawner", function()
    set_setting("sh-enemy-prioritization", "spawners-first")
    zoom_to(0, 0, 0.25)
    local spider = spawn_hunter(0, 0)
    -- worm sits just outside rocket range (~36) so auto-targeting can't kill it before the AI chooses
    local worm = spawn_enemy("small-worm-turret", 50, 0)
    local spawner = spawn_enemy("biter-spawner", -95, 0)
    call("enable", spider)
    async(60 * 150)
    on_tick(function()
      if not worm.valid or not spawner.valid then
        assert(not spawner.valid and worm.valid, "worm died before the spawner")
        done()
      end
    end)
  end)

  test("badly damaged hunter retreats instead of engaging", function()
    zoom_to(10, 0, 0.4)
    local spider = spawn_hunter(0, 0)
    spider.health = spider.max_health * 0.10 -- below the 25% retreat threshold
    local worm = spawn_enemy("small-worm-turret", 45, 0)
    call("enable", spider)
    local seen = {}
    async(60 * 40)
    on_tick(function()
      local st = state_of(spider)
      if st then seen[st] = true end
      if seen.returning or seen.restocking then
        assert(worm.valid, "hunter attacked despite low health")
        done()
      end
    end)
  end)

  local function custom_alert_count()
    local n = 0
    local found = game.connected_players[1].get_alerts({ type = defines.alert_type.custom })
    for _, by_type in pairs(found) do
      for _, list in pairs(by_type) do n = n + #list end
    end
    return n
  end

  local function retreat_scenario(level, expect_alert)
    zoom_to(10, 0, 0.4)
    set_setting("sh-alert-level", level)
    game.connected_players[1].remove_alert({ type = defines.alert_type.custom })
    local spider = spawn_hunter(0, 0)
    spider.health = spider.max_health * 0.10 -- below the 25% retreat threshold
    spawn_enemy("small-worm-turret", 45, 0)
    call("enable", spider)
    local seen = {}
    async(60 * 40)
    on_tick(function()
      local st = state_of(spider)
      if st then seen[st] = true end
      if seen.returning or seen.restocking then
        if expect_alert then
          assert(custom_alert_count() >= 1, "no custom alert after retreat")
        else
          assert(custom_alert_count() == 0, "alert shown while alerts are off")
        end
        done()
      end
    end)
  end

  test("retreat raises a custom alert for the player", function() retreat_scenario("important", true) end)
  test("no alert when alerts are off", function() retreat_scenario("off", false) end)

  test("hunter keeps away from a heavily defended nest and says so", function()
    zoom_to(40, 0, 0.3)
    game.connected_players[1].remove_alert({ type = defines.alert_type.custom })
    local spider = spawn_hunter(0, 0)
    local nest = {}
    for i = 1, 4 do -- 4 x behemoth worm = 120 danger points > a 3000 hp spidertron's ~100
      nest[i] = spawn_enemy("behemoth-worm-turret", 80 + (i % 2) * 8, (i - 2) * 8)
    end
    call("enable", spider)
    local start_tick = game.tick
    local alert_seen = false
    async(60 * 30)
    on_tick(function()
      assert(spider.valid, "spider died")
      for _, w in ipairs(nest) do assert(w.valid, "hunter attacked a nest it should avoid") end
      assert(distance(spider.position, { x = 80, y = 0 }) > 50,
        "hunter closed in on the nest: " .. serpent.line(spider.position))
      -- custom alerts fade after a few seconds, so catch it when it appears
      if custom_alert_count() >= 1 then alert_seen = true end
      if game.tick - start_tick > 60 * 15 then
        assert(alert_seen, "no 'avoiding a nest' alert")
        done()
      end
    end)
  end)

  test("nearest mode falls back to a safe nest past a dangerous nearer one", function()
    zoom_to(40, 60, 0.2)
    local spider = spawn_hunter(0, 0)
    local danger, safe = {}, nil
    for i = 1, 4 do -- nearer nest, too dangerous for this hunter
      danger[i] = spawn_enemy("behemoth-worm-turret", 60 + (i % 2) * 8, (i - 2) * 8)
    end
    safe = spawn_enemy("biter-spawner", 0, 110) -- farther, harmless
    call("enable", spider)
    async(60 * 90)
    on_tick(function()
      assert(spider.valid, "spider died")
      for _, w in ipairs(danger) do assert(w.valid, "hunter attacked the dangerous nest") end
      if not safe.valid then done() end
    end)
  end)

  test("scout reaches its waypoint and charts it without attacking", function()
    zoom_to(0, -40, 0.3)
    -- scouts must be unarmed: no ammo inserted
    local spider = surface().create_entity({ name = "spidertron", position = { 0, 0 }, force = "player" })
    local worm = spawn_enemy("small-worm-turret", 90, -40) -- off the route, must be left alone
    assert(call("set_scout_focus", spider, { x = 0, y = 0 }), "set_scout_focus failed")
    call("add_scout_waypoint", spider, { x = 0, y = -80 })
    assert(call("get_role", spider) == "scout", "role should be scout")
    async(60 * 180)
    on_tick(function()
      if distance(spider.position, { x = 0, y = -80 }) < 20 then
        assert(worm.valid, "scout attacked something")
        assert(game.forces.player.is_chunk_charted(surface(), { x = 0, y = -3 }), "waypoint area not charted")
        done()
      end
    end)
  end)

  test("follow_player: spider tracks the player's character", function()
    local spider = spawn_hunter(0, 0)
    call("enable", spider)
    local p = H.player_character_to(0, 0)
    local char = p and (p.character or storage.test_character)
    assert(char and char.valid, "test player has no character")
    H.player_character_to(70, 0)
    assert(call("follow_player", spider, p), "follow_player refused")
    zoom_to(30, 0, 0.35, true) -- keep_character: the character is the follow target
    async(60 * 90)
    on_tick(function()
      if distance(spider.position, char.position) < 15 then done() end
    end)
  end)

  test("two hunters split two nests and both survive", function()
    zoom_to(0, 0, 0.2)
    local a = spawn_hunter(-6, 0)
    local b = spawn_hunter(6, 0)
    H.spawn_nest(60, -10, 1, 4)
    H.spawn_nest(-75, 10, 1, 4)
    call("enable", a)
    call("enable", b)
    local start_a, start_b = { x = a.position.x, y = a.position.y }, { x = b.position.x, y = b.position.y }
    local max_a, max_b = 0, 0
    async(60 * 240)
    on_tick(function()
      assert(a.valid and b.valid, "a hunter died")
      max_a = math.max(max_a, distance(a.position, start_a))
      max_b = math.max(max_b, distance(b.position, start_b))
      if H.count_enemies() == 0 then
        assert(max_a > 15 and max_b > 15, "one hunter sat out: " .. max_a .. " / " .. max_b)
        done()
      end
    end)
  end)

  test("hunter keeps its distance instead of hugging the target", function()
    zoom_to(30, 0, 0.4)
    local spider = spawn_hunter(0, 0)
    local worm = spawn_enemy("small-worm-turret", 60, 0)
    call("enable", spider)
    local min_dist = math.huge
    async(60 * 120)
    on_tick(function()
      if worm.valid then
        min_dist = math.min(min_dist, distance(spider.position, worm.position))
      else
        assert(min_dist >= 10, "hunter walked up to the target (closest " .. min_dist .. ")")
        done()
      end
    end)
  end)
end)
