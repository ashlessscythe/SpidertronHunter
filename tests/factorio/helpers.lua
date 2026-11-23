-- Shared helpers for in-game tests (build arenas, spawn hunters/enemies, measure results).
local H = {}

local function surface() return game.surfaces[1] end
H.surface = surface

-- The player's physical character is moved to a separate parking surface so it is neither visible
-- nor hittable (rockets/acid) in the arena, and the player watches via remote view.
local function parking_surface()
  return game.get_surface("ft-parking") or game.create_surface("ft-parking")
end

local function park_character()
  for _, p in pairs(game.connected_players) do
    local c = p.character or storage.test_character
    if c and c.valid then
      c.destructible = false
      storage.test_character = c
      if c.surface.name ~= "ft-parking" then c.teleport({ 0, 0 }, parking_surface()) end
    end
  end
end

-- Camera: remote view over (x, y); character parked away unless keep_character. Falls back to teleporting the character.
local function zoom_to(x, y, zoom, keep_character)
  for _, p in pairs(game.connected_players) do
    if p.character then storage.test_character = p.character end
    local ok = pcall(p.set_controller, { type = defines.controllers.remote, position = { x, y }, surface = surface() })
    if ok then
      if not keep_character then park_character() end
    elseif p.character then
      p.character.destructible = false
      p.teleport({ x, y }, surface())
    end
    p.zoom = zoom or 0.4
  end
end

local function clear_arena()
  park_character()
  -- everything except characters: spiders, biters, nests, corpses, rockets, fire, ...
  for _, e in pairs(surface().find_entities({ { -150, -150 }, { 150, 150 } })) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

-- Lake: union of water rectangles {x1, y1, x2, y2}. Original tile is restored by clear_lake().
local lake_rects
local original_tile
local function make_water(rects)
  original_tile = original_tile or surface().get_tile(0, 0).name
  local tiles = {}
  for _, r in ipairs(rects) do
    for x = r[1], r[3] do
      for y = r[2], r[4] do
        tiles[#tiles + 1] = { name = "water", position = { x, y } }
      end
    end
  end
  surface().set_tiles(tiles)
  lake_rects = rects
end

local function make_lake(x1, y1, x2, y2)
  make_water({ { x1, y1, x2, y2 } })
end

-- U-shaped bay open to the west: land inside the U (x -25..14, y -29..29) is enclosed by water to
-- the north, south and east, so reaching the far side means leaving through the mouth and going
-- around the arms (|y| > 40).
local function make_bay()
  make_water({
    { -25, -40, 25, -30 }, -- north arm
    { -25, 30, 25, 40 }, -- south arm
    { 15, -40, 25, 40 }, -- back wall
  })
end

local function clear_lake()
  if not lake_rects then return end
  local tiles = {}
  for _, r in ipairs(lake_rects) do
    for x = r[1], r[3] do
      for y = r[2], r[4] do
        tiles[#tiles + 1] = { name = original_tile, position = { x, y } }
      end
    end
  end
  surface().set_tiles(tiles)
  lake_rects = nil
end

-- Body may overhang the shore (legs stay on land), so only count it as "in the lake"
-- when the center is more than `margin` tiles inside a water rectangle.
local function deep_in_lake(entity, margin)
  if not lake_rects then return false end
  local p = entity.position
  for _, r in ipairs(lake_rects) do
    if p.x > r[1] + margin and p.x < r[3] + 1 - margin and p.y > r[2] + margin and p.y < r[4] + 1 - margin then
      return true
    end
  end
  return false
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

H.park_character = park_character
H.zoom_to, H.clear_arena, H.make_lake, H.clear_lake = zoom_to, clear_arena, make_lake, clear_lake
H.make_water, H.make_bay = make_water, make_bay
H.deep_in_lake, H.spawn_nest, H.spawn_hunter, H.count_enemies = deep_in_lake, spawn_nest, spawn_hunter, count_enemies

--- Spawn an enemy entity (stationary things like worms/spawners are best for ordering tests).
function H.spawn_enemy(name, x, y)
  return surface().create_entity({ name = name, position = { x, y }, force = "enemy" })
end

function H.distance(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

--- Bring the test player's (invulnerable) character onto the arena surface at (x, y), e.g. as a
--- follow target. zoom_to / clear_arena park it again. Returns the player.
function H.player_character_to(x, y)
  local p = game.connected_players[1]
  local c = p and (p.character or storage.test_character)
  if c and c.valid then
    c.destructible = false
    c.teleport({ x, y }, surface())
  end
  return p
end

return H
