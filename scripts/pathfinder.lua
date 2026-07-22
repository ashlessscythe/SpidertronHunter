--- Lake-aware pathfinding into vanilla autopilot waypoints.
--- Architectural reference: SpidertronEnhancements pathfinder.lua (owned implementation).
local util = require("scripts.util")

local M = {}

local MAX_PATH_REQUESTS_PER_TICK = 4
local SHORT_HOP_DISTANCE = 10

local function get_leg_collision_mask(spidertron)
  local legs = spidertron.get_spider_legs()
  if not legs or not legs[1] or not legs[1].valid then
    return { layers = { water_tile = true }, colliding_with_tiles_only = true, consider_tile_transitions = true }
  end
  local leg = legs[1]
  local leg_collision_mask = leg.prototype.collision_mask
  local path_collision_mask = {
    layers = leg_collision_mask.layers,
    colliding_with_tiles_only = true,
    consider_tile_transitions = true,
  }
  if leg_collision_mask.layers and leg_collision_mask.layers["player"] and prototypes.collision_layer["large_entity"] then
    path_collision_mask = {
      layers = { large_entity = true },
      colliding_with_tiles_only = false,
      consider_tile_transitions = true,
    }
  end
  return path_collision_mask, legs
end

--- @param spidertron LuaEntity
--- @param start_position MapPosition
--- @param target_position MapPosition
--- @param goal_position MapPosition
--- @param resolution integer
--- @param start_tick integer
--- @param leg_index integer
local function request_one_path(spidertron, start_position, target_position, goal_position, resolution, start_tick, leg_index)
  if (storage.path_requests_this_tick or 0) >= MAX_PATH_REQUESTS_PER_TICK then
    return nil
  end

  local path_collision_mask, legs = get_leg_collision_mask(spidertron)
  local leg = legs and legs[leg_index]
  local request_id = spidertron.surface.request_path({
    bounding_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
    collision_mask = path_collision_mask,
    start = { x = start_position.x, y = start_position.y },
    goal = target_position,
    force = spidertron.force,
    path_resolution_modifier = resolution,
    pathfind_flags = {
      prefer_straight_paths = false,
      cache = false,
      low_priority = true,
    },
    entity_to_ignore = leg,
  })

  storage.path_requests_this_tick = (storage.path_requests_this_tick or 0) + 1
  storage.path_requests[request_id] = {
    spidertron = spidertron,
    unit_number = spidertron.unit_number,
    start_position = start_position,
    target_position = target_position,
    goal_position = goal_position,
    resolution = resolution,
    start_tick = start_tick,
    leg_index = leg_index,
  }
  return request_id
end

--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @param resolution integer?
--- @return boolean started
function M.request_path_to(spidertron, goal, resolution)
  resolution = resolution or -3
  local dist = util.distance(spidertron.position, goal)
  if dist < SHORT_HOP_DISTANCE then
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    return true
  end

  local legs = spidertron.get_spider_legs()
  if not legs or #legs == 0 then
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    return true
  end

  local target_position = spidertron.surface.find_non_colliding_position(
    legs[1].name,
    goal,
    10,
    2
  ) or goal

  local start_tick = game.tick
  storage.path_statuses[spidertron.unit_number] = storage.path_statuses[spidertron.unit_number] or {}
  storage.path_statuses[spidertron.unit_number][start_tick] = {
    finished = 0,
    success = false,
    total = 0,
    goal = goal,
  }

  local total = 0
  for i, leg in pairs(legs) do
    if (i % 2 == 1) and leg.valid then
      local id = request_one_path(
        spidertron,
        leg.position,
        target_position,
        goal,
        resolution,
        start_tick,
        i
      )
      if id then
        total = total + 1
      end
    end
  end

  local status = storage.path_statuses[spidertron.unit_number][start_tick]
  status.total = total

  if total == 0 then
    -- Budget exhausted or no legs — fall back to direct.
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    storage.path_statuses[spidertron.unit_number][start_tick] = nil
    return true
  end

  local ai = storage.spiders[spidertron.unit_number]
  if ai then
    ai.path_start_tick = start_tick
    ai.pending_goal = { x = goal.x, y = goal.y }
  end
  return true
end

--- @param event EventData.on_script_path_request_finished
function M.on_path_finished(event)
  local info = storage.path_requests[event.id]
  if not info then
    return
  end
  storage.path_requests[event.id] = nil

  local spidertron = info.spidertron
  if not spidertron or not spidertron.valid then
    return
  end

  local unit_number = info.unit_number
  local statuses = storage.path_statuses[unit_number]
  if not statuses then
    return
  end
  local status = statuses[info.start_tick]
  if not status then
    return
  end

  local ai = storage.spiders[unit_number]
  -- Abort if goal superseded, AI disabled, or player has taken control.
  if not ai or ai.state == "idle" or ai.state == "waiting" then
    status.finished = status.finished + 1
    if status.finished >= status.total then
      statuses[info.start_tick] = nil
    end
    return
  end
  if ai.keep_player_destination then
    status.finished = status.finished + 1
    status.success = true
    if status.finished >= status.total then
      statuses[info.start_tick] = nil
    end
    return
  end
  if ai.pending_goal
    and (ai.pending_goal.x ~= info.goal_position.x or ai.pending_goal.y ~= info.goal_position.y)
  then
    status.finished = status.finished + 1
    status.success = true
    if status.finished >= status.total then
      statuses[info.start_tick] = nil
    end
    return
  end

  if status.success then
    status.finished = status.finished + 1
    if status.finished >= status.total then
      statuses[info.start_tick] = nil
    end
    return
  end

  if event.try_again_later then
    request_one_path(
      spidertron,
      info.start_position,
      info.target_position,
      info.goal_position,
      info.resolution,
      info.start_tick,
      info.leg_index
    )
    return
  end

  if not event.path then
    if info.resolution < 1 then
      request_one_path(
        spidertron,
        info.start_position,
        info.target_position,
        info.goal_position,
        info.resolution + 2,
        info.start_tick,
        info.leg_index
      )
      return
    end
    status.finished = status.finished + 1
    if status.finished >= status.total then
      -- All failed — direct fallback.
      spidertron.follow_target = nil
      spidertron.autopilot_destination = info.goal_position
      statuses[info.start_tick] = nil
    end
    return
  end

  -- Success: apply thinned waypoints.
  spidertron.follow_target = nil
  spidertron.autopilot_destination = nil

  local path = event.path
  local last_position = spidertron.position
  local min_distance = 1e9
  local min_i = 1
  for i, waypoint in pairs(path) do
    local d = util.distance(last_position, waypoint.position)
    if d < min_distance then
      min_distance = d
      min_i = i
    end
  end

  local height = spidertron.prototype.height or 1.5
  local min_spacing = (height + 0.5) * 7.5
  for i, waypoint in pairs(path) do
    if i >= min_i + 1 then
      local position = waypoint.position
      if util.distance(last_position, position) > min_spacing then
        spidertron.add_autopilot_destination(position)
        last_position = position
      end
    end
  end
  spidertron.add_autopilot_destination(info.goal_position)

  status.finished = status.finished + 1
  status.success = true
  if status.finished >= status.total then
    statuses[info.start_tick] = nil
  end
end

function M.on_tick_reset_budget()
  storage.path_requests_this_tick = 0
end

M.SHORT_HOP_DISTANCE = SHORT_HOP_DISTANCE

return M
