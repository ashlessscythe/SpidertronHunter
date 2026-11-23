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

H.park_character = park_character
H.zoom_to, H.clear_arena, H.make_lake, H.clear_lake = zoom_to, clear_arena, make_lake, clear_lake
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
