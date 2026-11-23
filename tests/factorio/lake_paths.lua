-- Lake-aware pathing scenarios: spiders must route around water, never wade into it.
-- Tagged "visual" like the other real-time scenarios (second CI step).
local H = require("tests/factorio/helpers")
local path_remote = require("scripts.path_remote")
local surface, zoom_to, clear_arena, clear_lake = H.surface, H.zoom_to, H.clear_arena, H.clear_lake
local make_lake, deep_in_lake, spawn_hunter, count_enemies, distance =
  H.make_lake, H.deep_in_lake, H.spawn_hunter, H.count_enemies, H.distance

local function call(method, ...) return remote.call("SpidertronHunter", method, ...) end

-- Lake spans x -25..25, y -40..40 (same as the hunter demo).
local function lake() make_lake(-25, -40, 25, 40) end

tags("visual")
describe("lake-aware pathing", function()
  before_each(function() clear_lake(); clear_arena() end)
  after_each(function() clear_arena(); clear_lake() end)

  test("Ctrl+RMB go-to (AI off) walks around the lake to a goal on the far side", function()
    lake()
    zoom_to(0, 0, 0.25)
    local spider = surface().create_entity({ name = "spidertron", position = { -45, 0 }, force = "player" })
    local goal = { x = 45, y = 0 }
    assert(path_remote.go_lake_aware(spider, goal, nil), "go_lake_aware refused the goal")
    local max_abs_y = 0
    async(60 * 240)
    on_tick(function()
      assert(spider.valid, "spider died")
      assert(not deep_in_lake(spider, 6), "spider walked into the lake at " .. serpent.line(spider.position))
      max_abs_y = math.max(max_abs_y, math.abs(spider.position.y))
      if distance(spider.position, goal) < 8 then
        assert(max_abs_y > 35, "no detour around the lake (max |y| = " .. max_abs_y .. ")")
        done()
      end
    end)
  end)

  test("a goal in the middle of the lake leaves the spider on the shore", function()
    lake()
    zoom_to(0, 0, 0.25)
    local spider = surface().create_entity({ name = "spidertron", position = { -45, 0 }, force = "player" })
    path_remote.go_lake_aware(spider, { x = 0, y = 0 }, nil)
    local start_tick = game.tick
    local settled_ticks = 0
    async(60 * 90)
    on_tick(function()
      assert(spider.valid, "spider died")
      assert(not deep_in_lake(spider, 6), "spider walked into the lake at " .. serpent.line(spider.position))
      if not spider.autopilot_destination and not spider.follow_target then
        settled_ticks = settled_ticks + 1
      else
        settled_ticks = 0
      end
      if settled_ticks > 60 then
        -- finished somewhere on land, not stuck at the start
        assert(spider.position.x > -44, "spider never left its start: " .. serpent.line(spider.position))
        done()
      elseif game.tick - start_tick > 60 * 60 then
        -- should have arrived at the shore (~20 tiles away) long before this
        error("spider still has a destination after 60s (stuck pushing at the shore?) at "
          .. serpent.line(spider.position) .. " -> " .. serpent.line(spider.autopilot_destination))
      end
    end)
  end)

  test("scout charts a waypoint beyond the lake without entering the water", function()
    lake()
    zoom_to(0, 0, 0.25)
    local spider = surface().create_entity({ name = "spidertron", position = { -45, 0 }, force = "player" })
    assert(call("set_scout_focus", spider, { x = -45, y = 0 }), "set_scout_focus failed")
    call("add_scout_waypoint", spider, { x = 45, y = 0 })
    async(60 * 300)
    on_tick(function()
      assert(spider.valid, "spider died")
      assert(not deep_in_lake(spider, 6), "scout walked into the lake at " .. serpent.line(spider.position))
      if distance(spider.position, { x = 45, y = 0 }) < 20 then
        assert(game.forces.player.is_chunk_charted(surface(), { x = 1, y = 0 }), "far side not charted")
        done()
      end
    end)
  end)

  test("hunter detours around the lake again on the way home", function()
    lake()
    zoom_to(0, 0, 0.25)
    local home = { x = -45, y = 0 }
    local spider = spawn_hunter(home.x, home.y)
    surface().create_entity({ name = "small-biter", position = { 45, 0 }, force = "enemy" })
    call("enable", spider)
    local killed_tick
    local max_abs_y_after_kill = 0
    async(60 * 420)
    on_tick(function()
      assert(spider.valid, "spider died")
      assert(not deep_in_lake(spider, 6), "spider walked into the lake at " .. serpent.line(spider.position))
      if not killed_tick and count_enemies() == 0 then killed_tick = game.tick end
      if killed_tick then
        max_abs_y_after_kill = math.max(max_abs_y_after_kill, math.abs(spider.position.y))
        if distance(spider.position, home) < 20 then
          assert(max_abs_y_after_kill > 35, "return trip did not detour (max |y| = " .. max_abs_y_after_kill .. ")")
          done()
        end
      end
    end)
  end)

  test("six hunters share the pathfinder budget and none enters the lake", function()
    lake()
    zoom_to(0, 0, 0.25)
    local spiders = {}
    for i = 1, 6 do
      spiders[i] = spawn_hunter(-45, -15 + i * 5)
      surface().create_entity({ name = "small-biter", position = { 45, -15 + i * 5 }, force = "enemy" })
      call("enable", spiders[i])
    end
    async(60 * 420)
    on_tick(function()
      for _, spider in pairs(spiders) do
        if spider.valid then
          assert(not deep_in_lake(spider, 6), "a hunter walked into the lake at " .. serpent.line(spider.position))
        end
      end
      if count_enemies() == 0 then done() end
    end)
  end)
end)
