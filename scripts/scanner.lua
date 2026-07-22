--- Bounded incremental enemy scanning. Never scans the whole revealed world.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")
local targeting = require("scripts.targeting")

local M = {}

--- Priority type weights for filtered scans.
local TYPE_PRIORITY = {
  ["unit-spawner"] = 1,
  ["turret"] = 2,
  ["unit"] = 3,
  ["spider-unit"] = 3,
}

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

  -- Prefer shared cache (cheap).
  local cached = targeting.find_near(
    spidertron.surface_index,
    spidertron.position,
    radius,
    ai.unit_number,
    cfg.enemy_prioritization
  )
  if cached and cached.entity and cached.entity.valid then
    local from_home = util.distance(home, cached.position)
    if from_home <= max_pursuit then
      return cached.entity
    end
  end

  -- Budget: primary cheap probe.
  local budget = cfg.scan_budget
  local used = 0

  local nearest = spidertron.surface.find_nearest_enemy({
    position = spidertron.position,
    max_distance = radius,
    force = spidertron.force,
  })
  used = used + 1

  if nearest and nearest.valid then
    local from_home = util.distance(home, nearest.position)
    if from_home <= max_pursuit then
      targeting.remember(nearest)
      return nearest
    end
  end

  if used >= budget then
    return nil
  end

  -- Optional prioritization scan with hard limit.
  if cfg.enemy_prioritization ~= "nearest" then
    -- Do not filter by spidertron.force (that returns friendlies). Filter military
    -- targets then keep enemies of this force only.
    local found = spidertron.surface.find_entities_filtered({
      position = spidertron.position,
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
        local from_home = util.distance(home, e.position)
        if from_home <= max_pursuit then
          local rank = TYPE_PRIORITY[e.type] or 50
          if cfg.enemy_prioritization == "units-first" then
            if e.type == "unit" then
              rank = 0
            end
          end
          local dsq = util.distance_squared(spidertron.position, e.position)
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
--- @param ai table
--- @param center MapPosition
--- @param radius number
--- @return LuaEntity?
function M.find_nearby_combat(ai, center, radius)
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end
  local home = { x = ai.home.x, y = ai.home.y }
  local max_pursuit = settings_mod.get().max_pursuit_distance

  local nearest = spidertron.surface.find_nearest_enemy({
    position = center,
    max_distance = radius,
    force = spidertron.force,
  })
  if nearest and nearest.valid then
    if util.distance(home, nearest.position) <= max_pursuit then
      targeting.remember(nearest)
      return nearest
    end
  end
  return nil
end

return M
