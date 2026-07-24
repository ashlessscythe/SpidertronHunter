--- storage schema helpers shared by init and migrations.

local M = {}

local VALID_STATES = {
  idle = true,
  patrol = true,
  search = true,
  moving = true,
  attacking = true,
  returning = true,
  restocking = true,
  reengaging = true,
  waiting = true,
  ["scout-explore"] = true,
}

local VALID_COMBAT_STYLES = {
  hold = true,
  strafe = true,
  circle = true,
  flank = true,
}

local VALID_ROLES = {
  hunter = true,
  scout = true,
}

--- Ensure top-level storage tables exist (idempotent).
function M.ensure_storage()
  storage.spiders = storage.spiders or {}
  storage.enemy_cache = storage.enemy_cache or {}
  storage.target_claims = storage.target_claims or {}
  storage.destroy_regs = storage.destroy_regs or {}
  storage.path_requests = storage.path_requests or {}
  storage.path_statuses = storage.path_statuses or {}
  storage.path_queue = storage.path_queue or {}
  storage.scan_cursor = storage.scan_cursor or nil
  storage.think_cursor = storage.think_cursor or nil
  storage.settings_cache = storage.settings_cache or {}
  storage.next_cache_id = storage.next_cache_id or 1
  storage.path_requests_this_tick = storage.path_requests_this_tick or 0
end

--- Backfill / sanitize per-spider AI records after version upgrades.
function M.migrate_ai_records()
  M.ensure_storage()
  for unit_number, ai in pairs(storage.spiders) do
    if type(ai) ~= "table" then
      storage.spiders[unit_number] = nil
    else
      ai.unit_number = ai.unit_number or unit_number
      if type(ai.state) ~= "string" or not VALID_STATES[ai.state] then
        ai.state = "idle"
      end
      if type(ai.home) ~= "table" then
        ai.home = { surface_index = 1, x = 0, y = 0 }
      else
        ai.home.x = ai.home.x or 0
        ai.home.y = ai.home.y or 0
        ai.home.surface_index = ai.home.surface_index or 1
      end
      if ai.home_sticky ~= true then
        ai.home_sticky = false
      end
      ai.path_request_ids = ai.path_request_ids or {}
      ai.scan_offset = ai.scan_offset or 0
      ai.next_think_tick = ai.next_think_tick or 0
      ai.state_entered_tick = ai.state_entered_tick or 0
      if ai.combat_style and not VALID_COMBAT_STYLES[ai.combat_style] then
        ai.combat_style = nil
      end
      if type(ai.role) ~= "string" or not VALID_ROLES[ai.role] then
        ai.role = "hunter"
      end
      if type(ai.waypoints) ~= "table" then
        ai.waypoints = {}
      end
      if ai.focus_pos ~= nil and type(ai.focus_pos) ~= "table" then
        ai.focus_pos = nil
      end
      if ai.scout_algo_cursor ~= nil and type(ai.scout_algo_cursor) ~= "table" then
        ai.scout_algo_cursor = nil
      end
      -- Transient combat / path flags should not block upgraded saves.
      ai.keep_player_destination = nil
      ai.path_stuck_since = nil
      ai.path_stuck_pos = nil
      ai.path_start_tick = nil
      ai.pending_goal = nil
      ai.player_goal = nil
      ai.wait_reason = nil
      ai.retreating = nil
      ai.retreat_origin = nil
      ai.post_combat_since = nil
      ai.combat_last_move_tick = nil
      ai.combat_next_move_tick = nil
      ai.orbit_angle = nil
      ai.strafe_sign = nil
      ai.flank_sign = nil
      ai.scout_goal = nil
      ai.scout_goal_kind = nil
      ai.scout_waypoint_run = nil
      ai.scout_started_tick = nil
      ai.scout_avoid = nil
      ai.scout_goal_set_tick = nil
      ai.path_failed_goal = nil
    end
  end

  -- Drop claims pointing at missing spiders.
  for claim_id, owner in pairs(storage.target_claims) do
    if not storage.spiders[owner] then
      storage.target_claims[claim_id] = nil
    end
  end

  -- Drop in-flight path state; pathfinder will re-request as needed.
  storage.path_requests = {}
  storage.path_statuses = {}
  storage.path_queue = {}
  storage.path_requests_this_tick = 0
end

M.VALID_STATES = VALID_STATES
M.VALID_COMBAT_STYLES = VALID_COMBAT_STYLES
M.VALID_ROLES = VALID_ROLES

return M
