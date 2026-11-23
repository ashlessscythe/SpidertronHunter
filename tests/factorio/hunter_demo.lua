-- Visual demo tests: tagged "visual" so the headless Docker run skips them.
-- Watch with: scripts/watch_factorio_tests.sh
local function surface() return game.surfaces[1] end

local function zoom_to(x, y, zoom)
  for _, p in pairs(game.connected_players) do
    if p.character then p.character.destructible = false end -- don't let biters kill the camera
    p.teleport({ x, y }, surface())
    p.zoom = zoom or 0.4
  end
end

local function clear_arena()
  -- everything except characters: spiders, biters, nests, corpses, rockets, fire, ...
  for _, e in pairs(surface().find_entities({ { -150, -150 }, { 150, 150 } })) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

-- Lake: rectangle of water tiles. Original tile is restored by clear_lake().
local lake_tiles_set
local original_tile
local function make_lake(x1, y1, x2, y2)
  original_tile = original_tile or surface().get_tile(0, 0).name
  local tiles = {}
  for x = x1, x2 do
    for y = y1, y2 do
      tiles[#tiles + 1] = { name = "water", position = { x, y } }
    end
  end
  surface().set_tiles(tiles)
  lake_tiles_set = { x1, y1, x2, y2 }
end

local function clear_lake()
  if not lake_tiles_set then return end
  local x1, y1, x2, y2 = table.unpack(lake_tiles_set)
  local tiles = {}
  for x = x1, x2 do
    for y = y1, y2 do
      tiles[#tiles + 1] = { name = original_tile, position = { x, y } }
    end
  end
  surface().set_tiles(tiles)
  lake_tiles_set = nil
end

-- Body may overhang the shore (legs stay on land), so only count it as "in the lake"
-- when the center is more than `margin` tiles inside the lake rectangle.
local function deep_in_lake(entity, margin)
  if not lake_tiles_set then return false end
  local x1, y1, x2, y2 = table.unpack(lake_tiles_set)
  local p = entity.position
  return p.x > x1 + margin and p.x < x2 + 1 - margin and p.y > y1 + margin and p.y < y2 + 1 - margin
end

local function spawn_nest(cx, cy, spawners, biters)
  for i = 1, spawners do
    surface().create_entity({ name = "biter-spawner", position = { cx + (i - 1) * 8, cy }, force = "enemy" })
  end
  for i = 1, biters do
    surface().create_entity({ name = "small-biter", position = { cx + (i % 6) * 2, cy + 6 + math.floor(i / 6) * 2 }, force = "enemy" })
  end
end

local function spawn_hunter(x, y)
  local spider = surface().create_entity({ name = "spidertron", position = { x, y }, force = "player" })
  spider.get_inventory(defines.inventory.spider_ammo).insert({ name = "rocket", count = 200 })
  return spider
end

local function count_enemies()
  return #surface().find_entities_filtered({ force = "enemy", area = { { -150, -150 }, { 150, 150 } } })
end

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
