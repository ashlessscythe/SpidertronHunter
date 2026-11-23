-- Visual demo tests: tagged "visual" so the headless Docker run skips them.
-- Watch with: scripts/watch_factorio_tests.sh
local H = require("tests/factorio/helpers")
local surface, zoom_to, clear_arena, clear_lake = H.surface, H.zoom_to, H.clear_arena, H.clear_lake
local make_lake, deep_in_lake, spawn_nest, spawn_hunter, count_enemies =
  H.make_lake, H.deep_in_lake, H.spawn_nest, H.spawn_hunter, H.count_enemies

tags("visual")
describe("hunter demo", function()
  before_each(function() clear_lake(); clear_arena() end)
  after_each(function() clear_arena(); clear_lake() end)

  test("hunter is enabled and gets a role", function()
    zoom_to(0, 0, 0.6)
    local spider = spawn_hunter(0, 0)
    assert(remote.call("SpidertronHunter", "enable", spider), "enable failed")
    assert(remote.call("SpidertronHunter", "is_enabled", spider), "not enabled")
    assert(remote.call("SpidertronHunter", "get_role", spider) == "hunter")
  end)

  test("hunter walks to a lone biter and kills it", function()
    zoom_to(20, 0, 0.5)
    local spider = spawn_hunter(0, 0)
    surface().create_entity({ name = "small-biter", position = { 40, 0 }, force = "enemy" })
    remote.call("SpidertronHunter", "enable", spider)
    async(60 * 90)
    on_tick(function()
      if count_enemies() == 0 then done() end
    end)
  end)

  test("hunter clears a nest", function()
    zoom_to(25, 0, 0.3)
    local spider = spawn_hunter(0, 0)
    spawn_nest(55, 0, 2, 8)
    remote.call("SpidertronHunter", "enable", spider)
    async(60 * 180)
    on_tick(function()
      if count_enemies() == 0 then done() end
    end)
  end)

  test("hunter goes around a lake to reach a biter", function()
    -- Lake spans x -25..25, y -40..40; spider starts west, biter sits east. Rocket range
    -- (~36) cannot reach across, so the hunter must walk around, never stepping on water.
    make_lake(-25, -40, 25, 40)
    zoom_to(0, 0, 0.25)
    local spider = spawn_hunter(-45, 0)
    surface().create_entity({ name = "small-biter", position = { 45, 0 }, force = "enemy" })
    remote.call("SpidertronHunter", "enable", spider)
    local max_abs_y = 0
    async(60 * 240)
    on_tick(function()
      if not spider.valid then error("spider died") end
      assert(not deep_in_lake(spider, 6), "spider walked into the lake at " .. serpent.line(spider.position))
      max_abs_y = math.max(max_abs_y, math.abs(spider.position.y))
      if count_enemies() == 0 then
        assert(max_abs_y > 35, "hunter did not detour around the lake (max |y| = " .. max_abs_y .. ")")
        done()
      end
    end)
  end)
end)
