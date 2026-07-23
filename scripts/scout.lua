--- Scout explore helpers: algorithms, waypoints, charting, standoff.
--- Pure math helpers are safe to unit-test without Factorio runtime.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")
local targeting = require("scripts.targeting")

local M = {}

local SCOUT_REMOTE_NAME = "sh-scout-remote"
local FRONTIER_SAMPLE_BUDGET = 48
local ARRIVAL_RADIUS = 12

M.SCOUT_REMOTE_NAME = SCOUT_REMOTE_NAME
M.ARRIVAL_RADIUS = ARRIVAL_RADIUS

-- Factorio inventory index; string fallback keeps pure tests working without `defines`.
local SPIDER_AMMO = (defines and defines.inventory and defines.inventory.spider_ammo) or "spider_ammo"

--- True if ammo slots have rounds or the grid has active-defense (e.g. laser defense).
--- Spidertrons always have gun mounts; "armed" means loaded / offensive equipment.
--- @param spidertron LuaEntity|table
--- @return boolean
function M.has_weapons(spidertron)
  if not spidertron or not spidertron.valid then
    return false
  end
  local get_inv = spidertron.get_inventory
  if type(get_inv) == "function" then
    local ammo = get_inv(SPIDER_AMMO)
    if ammo and not ammo.is_empty() then
      return true
    end
  end
  local grid = spidertron.grid
  if grid and grid.equipment then
    for _, eq in pairs(grid.equipment) do
      local eq_type = eq.type
      if not eq_type and eq.prototype then
        eq_type = eq.prototype.type
      end
      if eq_type == "active-defense-equipment" then
        return true
      end
    end
  end
  return false
end

--- @param player LuaPlayer?
--- @return boolean
function M.holding_scout_remote(player)
  if not player or not player.valid then
    return false
  end
  local stack = player.cursor_stack
  return stack ~= nil and stack.valid_for_read and stack.name == SCOUT_REMOTE_NAME
end

--- Focus center, else home.
--- @param ai table
--- @return MapPosition
function M.focus_or_home(ai)
  if ai.focus_pos then
    return { x = ai.focus_pos.x, y = ai.focus_pos.y }
  end
  return { x = ai.home.x, y = ai.home.y }
end

--- @param ai table
function M.clear_waypoints(ai)
  ai.waypoints = {}
end

--- @param ai table
--- @param position MapPosition
function M.add_waypoint(ai, position)
  ai.waypoints = ai.waypoints or {}
  ai.waypoints[#ai.waypoints + 1] = { x = position.x, y = position.y }
end

--- @param ai table
--- @return MapPosition?
function M.peek_waypoint(ai)
  local wps = ai.waypoints
  if not wps or #wps == 0 then
    return nil
  end
  return wps[1]
end

--- @param ai table
--- @return MapPosition?
function M.pop_waypoint(ai)
  local wps = ai.waypoints
  if not wps or #wps == 0 then
    return nil
  end
  return table.remove(wps, 1)
end

--- @param ai table
--- @return boolean
function M.has_waypoints(ai)
  return ai.waypoints ~= nil and #ai.waypoints > 0
end

--- @param ai table
--- @param position MapPosition
function M.set_focus(ai, position)
  ai.focus_pos = { x = position.x, y = position.y }
  M.clear_waypoints(ai)
  ai.scout_algo_cursor = nil
  ai.scout_started_tick = game.tick
  ai.scout_goal = nil
  ai.scout_goal_kind = nil
  ai.scout_waypoint_run = nil
end

--- @param ai table
function M.reset_run(ai)
  ai.scout_started_tick = game.tick
  ai.scout_algo_cursor = nil
  ai.scout_goal = nil
end

--- @param ai table
--- @param cfg table?
--- @return boolean
function M.limits_exceeded(ai, cfg)
  cfg = cfg or settings_mod.get()
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return true
  end
  local center = M.focus_or_home(ai)
  if util.distance(center, spidertron.position) > cfg.scout_max_distance then
    return true
  end
  local started = ai.scout_started_tick or ai.state_entered_tick or game.tick
  if game.tick - started >= cfg.scout_max_time_ticks then
    return true
  end
  return false
end

--- Nearest candidate within max_dist of center. Pure.
--- @param center MapPosition
--- @param max_dist number
--- @param candidates MapPosition[]
--- @return MapPosition?
function M.nearest_within(center, max_dist, candidates)
  local best = nil
  local best_d2 = max_dist * max_dist
  for i = 1, #candidates do
    local c = candidates[i]
    local d2 = util.distance_squared(center, c)
    if d2 <= best_d2 then
      best_d2 = d2
      best = c
    end
  end
  return best
end

--- Lawnmower strip sweep. Cursor: { strip, dir, x }. Pure.
--- Strips run parallel to X, spaced by `step`, covering a square of half-size max_dist.
--- @param center MapPosition
--- @param max_dist number
--- @param step number
--- @param cursor table?
--- @return MapPosition goal
--- @return table next_cursor
function M.lawnmower_next(center, max_dist, step, cursor)
  step = math.max(8, step or 48)
  local strips = math.max(1, math.floor((max_dist * 2) / step))
  cursor = cursor or { strip = 0, dir = 1 }
  local strip = cursor.strip or 0
  if strip > strips then
    strip = 0
  end
  local dir = cursor.dir or 1
  local y = center.y - max_dist + strip * step
  local x
  if dir > 0 then
    x = center.x + max_dist
  else
    x = center.x - max_dist
  end
  local goal = { x = x, y = y }
  local next_cursor = {
    strip = strip + 1,
    dir = -dir,
  }
  if next_cursor.strip > strips then
    next_cursor.strip = 0
    next_cursor.dir = 1
  end
  return goal, next_cursor
end

--- Expanding square spiral. Cursor: { index }. Pure.
--- @param center MapPosition
--- @param max_dist number
--- @param step number
--- @param cursor table?
--- @return MapPosition? goal
--- @return table next_cursor
function M.spiral_next(center, max_dist, step, cursor)
  step = math.max(8, step or 48)
  cursor = cursor or { index = 0 }
  local index = cursor.index or 0
  -- Generate points on an archimedean-ish square spiral.
  local ring = 0
  local remaining = index
  while true do
    local side = math.max(1, ring * 8)
    if ring == 0 then
      side = 1
    end
    if remaining < side then
      break
    end
    remaining = remaining - side
    ring = ring + 1
    if ring * step > max_dist then
      return nil, { index = 0 }
    end
  end

  local radius = ring * step
  local goal
  if ring == 0 then
    goal = { x = center.x, y = center.y }
  else
    local per_side = ring * 2
    local side_i = math.floor(remaining / per_side)
    local along = remaining % per_side
    if side_i == 0 then
      goal = { x = center.x - radius + along * step, y = center.y - radius }
    elseif side_i == 1 then
      goal = { x = center.x + radius, y = center.y - radius + along * step }
    elseif side_i == 2 then
      goal = { x = center.x + radius - along * step, y = center.y + radius }
    else
      goal = { x = center.x - radius, y = center.y + radius - along * step }
    end
  end

  if util.distance(center, goal) > max_dist then
    return nil, { index = 0 }
  end
  return goal, { index = index + 1 }
end

--- Collect uncharted chunk centers around `center` (Factorio runtime).
--- @param force LuaForce
--- @param surface LuaSurface
--- @param center MapPosition
--- @param max_dist number
--- @param budget integer
--- @return MapPosition[]
function M.sample_uncharted_chunks(force, surface, center, max_dist, budget)
  budget = budget or FRONTIER_SAMPLE_BUDGET
  local results = {}
  local cx = math.floor(center.x / 32)
  local cy = math.floor(center.y / 32)
  local chunk_radius = math.max(1, math.floor(max_dist / 32))
  -- Spiral outward from center chunk so nearer fog is preferred.
  local dx, dy = 0, -1
  local x, y = 0, 0
  local checked = 0
  local max_checks = (chunk_radius * 2 + 1) * (chunk_radius * 2 + 1)
  while checked < max_checks and #results < budget do
    if math.abs(x) <= chunk_radius and math.abs(y) <= chunk_radius then
      local chunk = { x = cx + x, y = cy + y }
      if surface.is_chunk_generated(chunk) and not force.is_chunk_charted(surface, chunk) then
        results[#results + 1] = {
          x = (chunk.x + 0.5) * 32,
          y = (chunk.y + 0.5) * 32,
        }
      end
      checked = checked + 1
    end
    if x == y or (x < 0 and x == -y) or (x > 0 and x == 1 - y) then
      dx, dy = -dy, dx
    end
    x, y = x + dx, y + dy
  end
  return results
end

--- @param ai table
--- @param cfg table?
--- @return MapPosition?
function M.pick_frontier_goal(ai, cfg)
  cfg = cfg or settings_mod.get()
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end
  local center = M.focus_or_home(ai)
  local candidates = M.sample_uncharted_chunks(
    spidertron.force,
    spidertron.surface,
    center,
    cfg.scout_max_distance,
    FRONTIER_SAMPLE_BUDGET
  )
  return M.nearest_within(spidertron.position, cfg.scout_max_distance * 2, candidates)
    or M.nearest_within(center, cfg.scout_max_distance, candidates)
end

--- @param ai table
--- @param cfg table?
--- @return MapPosition?
function M.pick_algorithm_goal(ai, cfg)
  cfg = cfg or settings_mod.get()
  local center = M.focus_or_home(ai)
  local step = math.max(24, (cfg.scout_chart_radius or 64) * 0.75)
  local algo = cfg.scout_algorithm or "frontier"

  if algo == "lawnmower" then
    local goal, cursor = M.lawnmower_next(center, cfg.scout_max_distance, step, ai.scout_algo_cursor)
    ai.scout_algo_cursor = cursor
    return goal
  end

  if algo == "spiral" then
    local goal, cursor = M.spiral_next(center, cfg.scout_max_distance, step, ai.scout_algo_cursor)
    ai.scout_algo_cursor = cursor
    return goal
  end

  -- frontier (default)
  return M.pick_frontier_goal(ai, cfg)
end

--- Next scout destination: waypoints first, else algorithm.
--- @param ai table
--- @param cfg table?
--- @return MapPosition?
--- @return string kind "waypoint"|"explore"|nil
function M.pick_goal(ai, cfg)
  cfg = cfg or settings_mod.get()
  local wp = M.peek_waypoint(ai)
  if wp then
    return wp, "waypoint"
  end
  local goal = M.pick_algorithm_goal(ai, cfg)
  if goal then
    return goal, "explore"
  end
  return nil, nil
end

--- Chart fog around the scout.
--- @param spidertron LuaEntity
--- @param radius number?
function M.chart_around(spidertron, radius)
  if not util.is_valid_spidertron(spidertron) then
    return
  end
  radius = radius or settings_mod.get().scout_chart_radius
  local p = spidertron.position
  spidertron.force.chart(spidertron.surface, {
    { x = p.x - radius, y = p.y - radius },
    { x = p.x + radius, y = p.y + radius },
  })
end

--- Nearest enemy within standoff; remembers into shared cache.
--- @param spidertron LuaEntity
--- @param standoff number?
--- @return LuaEntity?
function M.find_standoff_enemy(spidertron, standoff)
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end
  standoff = standoff or settings_mod.get().scout_standoff_distance
  local enemy = spidertron.surface.find_nearest_enemy({
    position = spidertron.position,
    max_distance = standoff,
    force = spidertron.force,
  })
  if enemy and enemy.valid then
    targeting.remember(enemy)
    return enemy
  end
  return nil
end

--- Step away from a threat while staying near the intended travel direction.
--- @param from MapPosition
--- @param threat MapPosition
--- @param distance number
--- @return MapPosition
function M.safe_detour(from, threat, distance)
  local dx = from.x - threat.x
  local dy = from.y - threat.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.1 then
    dx, dy, len = 1, 0, 1
  end
  local scale = distance / len
  return {
    x = from.x + dx * scale,
    y = from.y + dy * scale,
  }
end

return M
