--- Scout explore helpers: algorithms, waypoints, charting, standoff.
--- Pure math helpers are safe to unit-test without Factorio runtime.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")
local targeting = require("scripts.targeting")
local pathfinder = require("scripts.pathfinder")

local M = {}

local SCOUT_REMOTE_NAME = "sh-scout-remote"
local FRONTIER_SAMPLE_BUDGET = 48
local ARRIVAL_RADIUS = 12
--- How long a blocked goal / nest stays off-limits after a standoff (45s).
local AVOID_TTL_TICKS = 2700
local AVOID_LIST_CAP = 16
--- Abandon a scout goal that never arrives (90s).
local GOAL_TIMEOUT_TICKS = 5400

M.SCOUT_REMOTE_NAME = SCOUT_REMOTE_NAME
M.ARRIVAL_RADIUS = ARRIVAL_RADIUS
M.AVOID_TTL_TICKS = AVOID_TTL_TICKS
M.GOAL_TIMEOUT_TICKS = GOAL_TIMEOUT_TICKS

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
  ai.scout_avoid = nil
end

--- @param ai table
function M.reset_run(ai)
  ai.scout_started_tick = game.tick
  ai.scout_algo_cursor = nil
  ai.scout_goal = nil
  ai.scout_avoid = nil
end

--- Drop expired avoid entries. Pure aside from game.tick.
--- @param ai table
function M.prune_avoid(ai)
  local list = ai.scout_avoid
  if not list then
    return
  end
  local tick = (game and game.tick) or 0
  local dst = {}
  for i = 1, #list do
    local e = list[i]
    if e.until_tick > tick then
      dst[#dst + 1] = e
    end
  end
  ai.scout_avoid = dst
end

--- Mark a map position as temporarily unsafe (blocked corridor / nest).
--- @param ai table
--- @param pos MapPosition
--- @param ttl_ticks integer?
function M.remember_avoid(ai, pos, ttl_ticks)
  if not pos then
    return
  end
  ai.scout_avoid = ai.scout_avoid or {}
  local tick = (game and game.tick) or 0
  ai.scout_avoid[#ai.scout_avoid + 1] = {
    x = pos.x,
    y = pos.y,
    until_tick = tick + (ttl_ticks or AVOID_TTL_TICKS),
  }
  while #ai.scout_avoid > AVOID_LIST_CAP do
    table.remove(ai.scout_avoid, 1)
  end
end

--- @param ai table
--- @param pos MapPosition
--- @param radius number
--- @return boolean
function M.is_avoided(ai, pos, radius)
  if not pos or not radius or radius <= 0 then
    return false
  end
  M.prune_avoid(ai)
  local list = ai.scout_avoid
  if not list or #list == 0 then
    return false
  end
  local r2 = radius * radius
  for i = 1, #list do
    if util.distance_squared(pos, list[i]) <= r2 then
      return true
    end
  end
  return false
end

--- Pure filter: keep candidates farther than radius from any avoid entry.
--- @param candidates MapPosition[]
--- @param avoid_list table[]?
--- @param radius number
--- @param now_tick integer?
--- @return MapPosition[]
function M.filter_avoided_candidates(candidates, avoid_list, radius, now_tick)
  if not candidates or #candidates == 0 then
    return {}
  end
  if not avoid_list or #avoid_list == 0 or not radius or radius <= 0 then
    local copy = {}
    for i = 1, #candidates do
      copy[i] = candidates[i]
    end
    return copy
  end
  now_tick = now_tick or 0
  local r2 = radius * radius
  local out = {}
  for i = 1, #candidates do
    local c = candidates[i]
    local bad = false
    for j = 1, #avoid_list do
      local a = avoid_list[j]
      if a.until_tick > now_tick and util.distance_squared(c, a) <= r2 then
        bad = true
        break
      end
    end
    if not bad then
      out[#out + 1] = c
    end
  end
  return out
end

--- @param spidertron LuaEntity
--- @param position MapPosition
--- @param radius number
--- @return boolean
function M.position_has_enemy(spidertron, position, radius)
  if not spidertron or not spidertron.surface or not position then
    return false
  end
  local enemy = spidertron.surface.find_nearest_enemy({
    position = position,
    max_distance = radius,
    force = spidertron.force,
  })
  return enemy ~= nil and enemy.valid
end

--- Snap onto land or reject (ocean / cliff). Blacklists raw goal when rejected.
--- @param ai table
--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @return MapPosition?
function M.ensure_walkable_goal(ai, spidertron, goal)
  if not goal or not util.is_valid_spidertron(spidertron) then
    return nil
  end
  local walkable = pathfinder.find_walkable_near(spidertron, goal, pathfinder.WALKABLE_SEARCH_RADIUS)
  if not walkable then
    M.remember_avoid(ai, goal, AVOID_TTL_TICKS)
    return nil
  end
  return walkable
end

--- Consume a pathfinder failure: blacklist and clear the current scout goal.
--- @param ai table
--- @return boolean handled
function M.consume_path_failure(ai)
  local failed = ai.path_failed_goal
  if not failed then
    return false
  end
  M.remember_avoid(ai, failed, AVOID_TTL_TICKS)
  if ai.scout_goal then
    M.remember_avoid(ai, ai.scout_goal, AVOID_TTL_TICKS)
  end
  if ai.scout_goal_kind == "waypoint" then
    M.pop_waypoint(ai)
  end
  ai.path_failed_goal = nil
  ai.scout_goal = nil
  ai.scout_goal_kind = nil
  ai.scout_goal_set_tick = nil
  return true
end

--- True if the current scout goal has been pursued too long without arrival.
--- @param ai table
--- @return boolean
function M.goal_timed_out(ai)
  local started = ai.scout_goal_set_tick
  if not started or not ai.scout_goal then
    return false
  end
  return game.tick - started >= GOAL_TIMEOUT_TICKS
end

--- Abandon current goal after timeout (same blacklist treatment as path failure).
--- @param ai table
function M.abandon_timed_out_goal(ai)
  if ai.scout_goal then
    M.remember_avoid(ai, ai.scout_goal, AVOID_TTL_TICKS)
  end
  if ai.scout_goal_kind == "waypoint" then
    M.pop_waypoint(ai)
  end
  ai.scout_goal = nil
  ai.scout_goal_kind = nil
  ai.scout_goal_set_tick = nil
  ai.path_failed_goal = nil
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
  local standoff = cfg.scout_standoff_distance or 48
  local avoid_r = standoff * 1.5
  local candidates = M.sample_uncharted_chunks(
    spidertron.force,
    spidertron.surface,
    center,
    cfg.scout_max_distance,
    FRONTIER_SAMPLE_BUDGET
  )
  M.prune_avoid(ai)
  local filtered = M.filter_avoided_candidates(
    candidates,
    ai.scout_avoid,
    avoid_r,
    game.tick
  )
  -- Prefer goals that are not sitting on a nest.
  local safe = {}
  for i = 1, #filtered do
    local c = filtered[i]
    if not M.position_has_enemy(spidertron, c, standoff) then
      safe[#safe + 1] = c
    end
  end
  if #safe == 0 then
    safe = filtered
  end
  -- Try nearest candidates until one snaps onto land (chunk centers are often water).
  local ordered = {}
  for i = 1, #safe do
    ordered[i] = safe[i]
  end
  table.sort(ordered, function(a, b)
    return util.distance_squared(spidertron.position, a) < util.distance_squared(spidertron.position, b)
  end)
  for i = 1, math.min(#ordered, 12) do
    local walkable = M.ensure_walkable_goal(ai, spidertron, ordered[i])
    if walkable then
      return walkable
    end
  end
  return nil
end

--- @param ai table
--- @param cfg table?
--- @return MapPosition?
function M.pick_algorithm_goal(ai, cfg)
  cfg = cfg or settings_mod.get()
  local center = M.focus_or_home(ai)
  local step = math.max(24, (cfg.scout_chart_radius or 64) * 0.75)
  local algo = cfg.scout_algorithm or "frontier"
  local standoff = cfg.scout_standoff_distance or 48
  local avoid_r = standoff * 1.5

  if algo == "lawnmower" or algo == "spiral" then
    local spidertron = ai.entity
    for _ = 1, 12 do
      local goal, cursor
      if algo == "lawnmower" then
        goal, cursor = M.lawnmower_next(center, cfg.scout_max_distance, step, ai.scout_algo_cursor)
      else
        goal, cursor = M.spiral_next(center, cfg.scout_max_distance, step, ai.scout_algo_cursor)
      end
      ai.scout_algo_cursor = cursor
      if not goal then
        return nil
      end
      local skip = M.is_avoided(ai, goal, avoid_r)
      if not skip and util.is_valid_spidertron(spidertron) and M.position_has_enemy(spidertron, goal, standoff) then
        M.remember_avoid(ai, goal, AVOID_TTL_TICKS)
        skip = true
      end
      if not skip and util.is_valid_spidertron(spidertron) then
        local walkable = M.ensure_walkable_goal(ai, spidertron, goal)
        if not walkable then
          skip = true
        else
          return walkable
        end
      elseif not skip then
        return goal
      end
    end
    return nil
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
  local standoff = cfg.scout_standoff_distance or 48
  local avoid_r = standoff * 1.5
  local spidertron = ai.entity

  -- Skip waypoints that were recently blocked or sit on biters.
  while M.has_waypoints(ai) do
    local wp = M.peek_waypoint(ai)
    if not wp then
      break
    end
    local blocked = M.is_avoided(ai, wp, avoid_r)
    if not blocked and util.is_valid_spidertron(spidertron) then
      blocked = M.position_has_enemy(spidertron, wp, standoff)
    end
    if blocked then
      M.remember_avoid(ai, wp, AVOID_TTL_TICKS)
      M.pop_waypoint(ai)
    else
      if util.is_valid_spidertron(spidertron) then
        local walkable = M.ensure_walkable_goal(ai, spidertron, wp)
        if not walkable then
          M.pop_waypoint(ai)
        else
          -- Keep waypoint in queue until arrival; navigate to snapped land.
          return walkable, "waypoint"
        end
      else
        return wp, "waypoint"
      end
    end
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

--- On standoff: blacklist the blocked goal/corridor and threat so we do not
--- immediately re-path through the same nest (zigzag). Returns a detour hop.
--- @param ai table
--- @param spidertron LuaEntity
--- @param threat LuaEntity
--- @param cfg table?
--- @return MapPosition detour
function M.handle_standoff(ai, spidertron, threat, cfg)
  cfg = cfg or settings_mod.get()
  local standoff = cfg.scout_standoff_distance or 48
  local kind = ai.scout_goal_kind
  local goal = ai.scout_goal
  if kind and kind ~= "detour" and goal then
    M.remember_avoid(ai, goal, AVOID_TTL_TICKS)
    M.remember_avoid(ai, {
      x = (spidertron.position.x + goal.x) * 0.5,
      y = (spidertron.position.y + goal.y) * 0.5,
    }, AVOID_TTL_TICKS)
    if kind == "waypoint" then
      M.pop_waypoint(ai)
    end
  end
  if threat and threat.valid then
    M.remember_avoid(ai, threat.position, AVOID_TTL_TICKS)
  end
  local detour = M.safe_detour(spidertron.position, threat.position, standoff * 1.25)
  local walkable = M.ensure_walkable_goal(ai, spidertron, detour) or detour
  ai.scout_goal = walkable
  ai.scout_goal_kind = "detour"
  ai.scout_goal_set_tick = game.tick
  return walkable
end

return M
