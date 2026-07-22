--- Bounded incremental enemy scanning. Never scans the whole revealed world.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")
local targeting = require("scripts.targeting")

local M = {}

--- When the spider is still near home, max_pursuit is enforced from home.
--- Once deployed farther out, allow any enemy within search_radius of the spider
--- (otherwise hunters go blind until the player re-enables and resets home).
local NEAR_HOME_THRESHOLD = 64

local TYPE_PRIORITY = {
  ["unit-spawner"] = 1,
  ["turret"] = 2,
  ["unit"] = 3,
  ["spider-unit"] = 3,
}

--- @param home MapPosition
--- @param spider_pos MapPosition
--- @param enemy_pos MapPosition
--- @param max_pursuit number
--- @param search_radius number
--- @return boolean
local function allowed_target(home, spider_pos, enemy_pos, max_pursuit, search_radius)
  if util.distance(spider_pos, enemy_pos) > search_radius then
    return false
  end
  local spider_from_home = util.distance(home, spider_pos)
  if spider_from_home <= NEAR_HOME_THRESHOLD then
    return util.distance(home, enemy_pos) <= max_pursuit
  end
  return true
end

--- @param ai table
--- @return LuaEntity?
function M.scan_for_enemy(ai)
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end

  local cfg = settings_mod.get()
  local radius = cfg.search_radius
  local home = { x = ai.home.x, y = ai.home.y }
  local max_pursuit = cfg.max_pursuit_distance
  local spider_pos = spidertron.position

  local cached = targeting.find_near(
    spidertron.surface_index,
    spider_pos,
    radius,
    ai.unit_number,
    cfg.enemy_prioritization
  )
  if cached and cached.entity and cached.entity.valid then
    if allowed_target(home, spider_pos, cached.position, max_pursuit, radius) then
      return cached.entity
    end
  end

  local budget = cfg.scan_budget
  local used = 0

  local nearest = spidertron.surface.find_nearest_enemy({
    position = spider_pos,
    max_distance = radius,
    force = spidertron.force,
  })
  used = used + 1

  if nearest and nearest.valid then
    if allowed_target(home, spider_pos, nearest.position, max_pursuit, radius) then
      targeting.remember(nearest)
      return nearest
    end
  end

  if used >= budget then
    return nil
  end

  if cfg.enemy_prioritization ~= "nearest" then
    local found = spidertron.surface.find_entities_filtered({
      position = spider_pos,
      radius = radius,
      is_military_target = true,
      limit = math.min(8, budget - used + 1),
    })
    used = used + 1

    local best = nil
    local best_rank = 99
    local best_dsq = 1e18
    for i = 1, #found do
      local e = found[i]
      if e.valid and e.force and spidertron.force.is_enemy(e.force) then
        if allowed_target(home, spider_pos, e.position, max_pursuit, radius) then
          local rank = TYPE_PRIORITY[e.type] or 50
          if cfg.enemy_prioritization == "units-first" and e.type == "unit" then
            rank = 0
          end
          local dsq = util.distance_squared(spider_pos, e.position)
          if rank < best_rank or (rank == best_rank and dsq < best_dsq) then
            best_rank = rank
            best_dsq = dsq
            best = e
          end
          targeting.remember(e)
        end
      end
    end
    if best then
      return best
    end
  end

  return nil
end

--- Find another enemy near current combat position (pursuit).
--- Deployed spiders are not gated by home distance here.
--- @param ai table
--- @param center MapPosition
--- @param radius number
--- @return LuaEntity?
function M.find_nearby_combat(ai, center, radius)
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end

  local nearest = spidertron.surface.find_nearest_enemy({
    position = center,
    max_distance = radius,
    force = spidertron.force,
  })
  if nearest and nearest.valid then
    targeting.remember(nearest)
    return nearest
  end
  return nil
end

M.NEAR_HOME_THRESHOLD = NEAR_HOME_THRESHOLD

return M
