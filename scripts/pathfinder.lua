--- Lake-aware pathfinding into vanilla autopilot waypoints.
--- See NOTICE for attribution of adapted pathfinding logic.
---
--- Fleet note: never fall back to direct autopilot when the path budget is full —
--- queue instead. Direct-into-water is what made some group members get stuck.
local util = require("scripts.util")

local M = {}

local MAX_PATH_REQUESTS_PER_TICK = 8
local SHORT_HOP_DISTANCE = 10
--- Re-path if a spider barely moves while still far from its goal.
local STUCK_TICKS = 180
local STUCK_MOVE_EPS = 1.5

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

local function ensure_queue()
  storage.path_queue = storage.path_queue or {}
end

--- Drop queued work for one spider (or wipe the whole queue).
--- @param unit_number integer?
function M.clear_queue_for(unit_number)
  ensure_queue()
  if not unit_number then
    storage.path_queue = {}
    return
  end
  local src = storage.path_queue
  local dst = {}
  for i = 1, #src do
    local item = src[i]
    if item.unit_number ~= unit_number then
      dst[#dst + 1] = item
    end
  end
  storage.path_queue = dst
end

local function enqueue(item)
  ensure_queue()
  -- One pending job per spider: newer goals replace older queued work.
  local src = storage.path_queue
  local dst = {}
  for i = 1, #src do
    if src[i].unit_number ~= item.unit_number then
      dst[#dst + 1] = src[i]
    end
  end
  dst[#dst + 1] = item
  storage.path_queue = dst
end

--- @param spidertron LuaEntity
--- @param start_position MapPosition
--- @param target_position MapPosition
--- @param goal_position MapPosition
--- @param resolution integer
--- @param start_tick integer
--- @param leg_index integer
--- @return integer? request_id
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

--- Pick a start leg that is likely on walkable ground (first odd valid leg).
--- @param spidertron LuaEntity
--- @return integer? leg_index
--- @return MapPosition? start_position
local function pick_start_leg(spidertron)
  local legs = spidertron.get_spider_legs()
  if not legs or #legs == 0 then
    return nil, nil
  end
  for i, leg in pairs(legs) do
    if (i % 2 == 1) and leg.valid then
      return i, { x = leg.position.x, y = leg.position.y }
    end
  end
  local leg = legs[1]
  if leg and leg.valid then
    return 1, { x = leg.position.x, y = leg.position.y }
  end
  return nil, nil
end

--- Mark AI as waiting on this goal (in-flight or queued).
--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @param start_tick integer?
local function mark_pending(spidertron, goal, start_tick)
  local ai = storage.spiders[spidertron.unit_number]
  if not ai then
    return
  end
  ai.path_start_tick = start_tick
  ai.pending_goal = { x = goal.x, y = goal.y }
  ai.path_stuck_since = nil
  ai.path_stuck_pos = nil
end

--- Attempt to issue one path request. Does not queue.
--- @return "ok"|"budget"|"direct"
local function try_start_path(spidertron, goal, resolution)
  local dist = util.distance(spidertron.position, goal)
  if dist < SHORT_HOP_DISTANCE then
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    mark_pending(spidertron, goal, nil)
    return "direct"
  end

  local leg_index, start_position = pick_start_leg(spidertron)
  if not leg_index or not start_position then
    spidertron.follow_target = nil
    spidertron.autopilot_destination = goal
    mark_pending(spidertron, goal, nil)
    return "direct"
  end

  local legs = spidertron.get_spider_legs()
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
    total = 1,
    goal = goal,
  }

  local id = request_one_path(
    spidertron,
    start_position,
    target_position,
    goal,
    resolution,
    start_tick,
    leg_index
  )

  if not id then
    storage.path_statuses[spidertron.unit_number][start_tick] = nil
    return "budget"
  end

  mark_pending(spidertron, goal, start_tick)
  return "ok"
end

--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @param resolution integer?
--- @return boolean started
function M.request_path_to(spidertron, goal, resolution)
  resolution = resolution or -3
  M.clear_queue_for(spidertron.unit_number)

  local result = try_start_path(spidertron, goal, resolution)
  if result == "budget" then
    -- Do not walk straight into water — wait for a free path slot.
    spidertron.follow_target = nil
    spidertron.autopilot_destination = nil
    mark_pending(spidertron, goal, nil)
    enqueue({
      kind = "start",
      unit_number = spidertron.unit_number,
      goal = { x = goal.x, y = goal.y },
      resolution = resolution,
    })
  end
  return true
end

--- Drain queued path work after the per-tick budget reset.
function M.process_queue()
  ensure_queue()
  local queue = storage.path_queue
  if #queue == 0 then
    return
  end

  -- Take ownership so enqueue during retries cannot corrupt iteration.
  storage.path_queue = {}
  local remaining = {}

  for i = 1, #queue do
    local item = queue[i]
    local ai = storage.spiders[item.unit_number]
    local spidertron = ai and ai.entity
    if not ai or not spidertron or not spidertron.valid then
      -- drop
    elseif item.kind == "start" then
      local result = try_start_path(spidertron, item.goal, item.resolution or -3)
      if result == "budget" then
        remaining[#remaining + 1] = item
      end
    elseif item.kind == "retry" then
      local id = request_one_path(
        spidertron,
        item.start_position,
        item.target_position,
        item.goal_position,
        item.resolution,
        item.start_tick,
        item.leg_index
      )
      if not id then
        remaining[#remaining + 1] = item
      end
    end
  end

  storage.path_queue = remaining
end

--- Re-request a lake-aware path if the spider is not making progress toward goal.
--- @param spidertron LuaEntity
--- @param goal MapPosition
--- @return boolean did_repath
function M.repath_if_stuck(spidertron, goal)
  if not util.is_valid_spidertron(spidertron) or not goal then
    return false
  end
  local ai = storage.spiders[spidertron.unit_number]
  if not ai then
    return false
  end
  if ai.keep_player_destination then
    return false
  end

  local pos = spidertron.position
  if util.distance(pos, goal) < SHORT_HOP_DISTANCE then
    ai.path_stuck_since = nil
    ai.path_stuck_pos = nil
    return false
  end

  -- Still waiting on queued work.
  ensure_queue()
  for i = 1, #storage.path_queue do
    if storage.path_queue[i].unit_number == ai.unit_number then
      return false
    end
  end
  -- Still waiting on an in-flight path.
  if ai.path_start_tick and storage.path_statuses[ai.unit_number] and storage.path_statuses[ai.unit_number][ai.path_start_tick] then
    return false
  end

  local moving = spidertron.autopilot_destination ~= nil or spidertron.follow_target ~= nil
  if not moving then
    M.request_path_to(spidertron, goal)
    return true
  end

  local stuck_pos = ai.path_stuck_pos
  if not stuck_pos or util.distance(pos, stuck_pos) > STUCK_MOVE_EPS then
    ai.path_stuck_pos = { x = pos.x, y = pos.y }
    ai.path_stuck_since = game.tick
    return false
  end

  if game.tick - (ai.path_stuck_since or game.tick) < STUCK_TICKS then
    return false
  end

  ai.path_stuck_since = nil
  ai.path_stuck_pos = nil
  spidertron.follow_target = nil
  spidertron.autopilot_destination = nil
  M.request_path_to(spidertron, goal)
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

  local function retry_or_queue(resolution)
    local id = request_one_path(
      spidertron,
      info.start_position,
      info.target_position,
      info.goal_position,
      resolution,
      info.start_tick,
      info.leg_index
    )
    if not id then
      enqueue({
        kind = "retry",
        unit_number = unit_number,
        start_position = info.start_position,
        target_position = info.target_position,
        goal_position = info.goal_position,
        resolution = resolution,
        start_tick = info.start_tick,
        leg_index = info.leg_index,
      })
    end
  end

  if event.try_again_later then
    retry_or_queue(info.resolution)
    return
  end

  if not event.path then
    if info.resolution < 1 then
      retry_or_queue(info.resolution + 2)
      return
    end
    status.finished = status.finished + 1
    if status.finished >= status.total then
      -- All resolutions failed — direct fallback as last resort.
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

  if ai then
    ai.path_stuck_since = nil
    ai.path_stuck_pos = nil
  end

  status.finished = status.finished + 1
  status.success = true
  if status.finished >= status.total then
    statuses[info.start_tick] = nil
  end
end

function M.on_tick_reset_budget()
  storage.path_requests_this_tick = 0
  M.process_queue()
end

M.SHORT_HOP_DISTANCE = SHORT_HOP_DISTANCE

return M
