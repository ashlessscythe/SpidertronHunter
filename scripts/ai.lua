--- Enable/disable, orchestration, state handlers.
local States = require("scripts.states")
local persistence = require("scripts.persistence")
local settings_mod = require("scripts.settings")
local util = require("scripts.util")
local movement = require("scripts.movement")
local scanner = require("scripts.scanner")
local targeting = require("scripts.targeting")
local logistics = require("scripts.logistics")
local combat = require("scripts.combat")
local shortcut = require("scripts.shortcut")
local pathfinder = require("scripts.pathfinder")
local patrols = require("scripts.patrols")
local scout = require("scripts.scout")

local M = {}

local COMBAT_REACQUIRE_RADIUS = 64
local ARRIVAL_RADIUS = 8
local PLAYER_CLICK_ENEMY_RADIUS = 8

--- @param ai table?
--- @return boolean
local function is_scout(ai)
  return ai ~= nil and ai.role == "scout"
end

--- Inline dirty flag (cannot require manager_gui — it requires ai; Factorio forbids runtime require).
local function mark_manager_dirty()
  if (storage.manager_open_count or 0) > 0 then
    storage.manager_dirty = true
  end
end

--- Abort Scout if ammo / active-defense was loaded mid-run.
--- @param ai table
--- @return boolean aborted
local function abort_scout_if_armed(ai)
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) or not scout.has_weapons(spidertron) then
    return false
  end
  M.disable(spidertron, nil)
  if spidertron.valid then
    for _, player in pairs(game.connected_players) do
      if player.valid and player.surface_index == spidertron.surface_index then
        util.flying_text(player, { "sh.scout-aborted-weapons" }, spidertron.position)
      end
    end
  end
  return true
end

--- Decide whether to return home or keep hunting after an area goes quiet.
--- @param ai table
--- @return string next_state
local function after_combat_clear(ai)
  local cfg = settings_mod.get()
  if not cfg.return_home_after_combat then
    ai.post_combat_since = nil
    return States.PATROL
  end
  ai.post_combat_since = ai.post_combat_since or game.tick
  local linger = cfg.post_combat_linger_ticks or 0
  if game.tick - ai.post_combat_since >= linger then
    ai.post_combat_since = nil
    return States.RETURNING
  end
  -- Keep scanning locally during the linger window.
  return States.PATROL
end

local function release_claim(ai)
  if ai.claim_id then
    if storage.target_claims[ai.claim_id] == ai.unit_number then
      storage.target_claims[ai.claim_id] = nil
    end
    ai.claim_id = nil
  end
  ai.target_entity = nil
  ai.target_pos = nil
end

--- Soft claim: always succeeds so multiple spiders can share a target.
--- @param ai table
--- @param entity LuaEntity
--- @return boolean
local function claim_target(ai, entity)
  release_claim(ai)
  if not entity or not entity.valid then
    return false
  end
  local id = targeting.remember(entity)
  if not id then
    return false
  end
  storage.target_claims[id] = ai.unit_number
  ai.claim_id = id
  ai.target_entity = entity
  ai.target_pos = { x = entity.position.x, y = entity.position.y }
  return true
end

local function beyond_pursuit(ai, position)
  local spidertron = ai.entity
  if not spidertron or not spidertron.valid then
    return true
  end
  local home = { x = ai.home.x, y = ai.home.y }
  -- Once already out in the field, do not abort a fight for home-distance.
  if util.distance(home, spidertron.position) > scanner.NEAR_HOME_THRESHOLD then
    return false
  end
  return util.distance(home, position) > settings_mod.get().max_pursuit_distance
end

--- Abort in-flight AI path requests so they cannot overwrite a player order.
--- @param ai table
local function cancel_ai_pathing(ai)
  ai.pending_goal = nil
  ai.path_start_tick = nil
  ai.path_stuck_since = nil
  ai.path_stuck_pos = nil
  if storage.path_statuses and ai.unit_number then
    storage.path_statuses[ai.unit_number] = nil
  end
  pathfinder.clear_queue_for(ai.unit_number)
end

--- Tactical retreat when hull/shield integrity drops below the configured %.
--- @param ai table
--- @return string? next_state
local function check_tactical_retreat(ai)
  local cfg = settings_mod.get()
  local threshold = cfg.retreat_health_percent or 0
  if threshold <= 0 then
    return nil
  end
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end
  local ratio = util.defense_ratio(spidertron, cfg.retreat_include_shields)
  if ratio * 100 < threshold then
    release_claim(ai)
    cancel_ai_pathing(ai)
    ai.post_combat_since = nil
    ai.retreating = true
    -- Remember where the bail-out started so re-engage can return here.
    ai.retreat_origin = {
      surface_index = spidertron.surface_index,
      x = spidertron.position.x,
      y = spidertron.position.y,
    }
    util.debug_log(
      "retreat " .. string.format("%.0f", ratio * 100) .. "%",
      spidertron
    )
    return States.RETURNING
  end
  return nil
end

--- @param ai table
--- @return MapPosition?
local function retreat_origin_position(ai)
  local origin = ai.retreat_origin
  if not origin then
    return nil
  end
  return { x = origin.x, y = origin.y }
end

--- @param surface LuaSurface
--- @param position MapPosition
--- @param force LuaForce
--- @return LuaEntity?
local function enemy_at_click(surface, position, force)
  local nearest = surface.find_nearest_enemy({
    position = position,
    max_distance = PLAYER_CLICK_ENEMY_RADIUS,
    force = force,
  })
  if nearest and nearest.valid then
    return nearest
  end
  local found = surface.find_entities_filtered({
    position = position,
    radius = PLAYER_CLICK_ENEMY_RADIUS,
    is_military_target = true,
    limit = 8,
  })
  for i = 1, #found do
    local e = found[i]
    if e.valid and e.force and force.is_enemy(e.force) then
      return e
    end
  end
  return nil
end

--- @param spidertron LuaEntity
--- @param player LuaPlayer?
--- @return boolean success
function M.enable(spidertron, player)
  if not util.is_valid_spidertron(spidertron) then
    if player then
      util.flying_text(player, { "sh.denied-denylist" }, spidertron and spidertron.position or nil)
    end
    return false
  end

  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    ai = persistence.create_ai(spidertron)
  else
    ai.entity = spidertron
  end

  -- Soft-dep handoff: force Patrols manual for the Hunter session; restore on disable.
  -- Always call set_manual when Patrols is present — do not gate on get_was_auto
  -- (Patrols' get_patrol_data remote often returns nil, so reads are unreliable).
  ai.patrols_was_auto = patrols.capture_was_auto(spidertron)
  if ai.patrols_was_auto ~= nil then
    patrols.set_manual(spidertron)
  end

  local cfg = settings_mod.get()
  local sticky = cfg.sticky_home_on_first_enable
  if not sticky or not ai.home_sticky then
    ai.home = {
      surface_index = spidertron.surface_index,
      x = spidertron.position.x,
      y = spidertron.position.y,
    }
    if sticky then
      ai.home_sticky = true
    end
  end
  release_claim(ai)
  cancel_ai_pathing(ai)
  ai.retreat_origin = nil
  ai.role = "hunter"
  scout.clear_waypoints(ai)
  ai.focus_pos = nil
  ai.scout_goal = nil
  ai.scout_algo_cursor = nil
  ai.scout_started_tick = nil
  -- Do not clear player destinations on enable — only stop AI-owned movement.
  spidertron.follow_target = nil

  local params = spidertron.vehicle_automatic_targeting_parameters
  if params then
    spidertron.vehicle_automatic_targeting_parameters = {
      auto_target_without_gunner = true,
      auto_target_with_gunner = params.auto_target_with_gunner,
    }
  end

  States.transition(ai, States.PATROL)

  script.raise_event("on_spidertron_hunter_enabled", {
    spidertron = spidertron,
    player_index = player and player.index or nil,
  })

  if player then
    util.flying_text(player, { "sh.enabled" }, spidertron.position)
  end
  shortcut.sync_all()
  mark_manager_dirty()
  return true
end

--- Enable Scout AI (explore / chart, never engage).
--- @param spidertron LuaEntity
--- @param player LuaPlayer?
--- @return boolean success
function M.enable_scout(spidertron, player)
  if not util.is_valid_spidertron(spidertron) then
    if player then
      util.flying_text(player, { "sh.denied-denylist" }, spidertron and spidertron.position or nil)
    end
    return false
  end

  if scout.has_weapons(spidertron) then
    if player then
      util.flying_text(player, { "sh.scout-denied-weapons" }, spidertron.position)
    end
    return false
  end

  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    ai = persistence.create_ai(spidertron)
  else
    ai.entity = spidertron
  end

  ai.patrols_was_auto = patrols.capture_was_auto(spidertron)
  if ai.patrols_was_auto ~= nil then
    patrols.set_manual(spidertron)
  end

  local cfg = settings_mod.get()
  local sticky = cfg.sticky_home_on_first_enable
  if not sticky or not ai.home_sticky then
    ai.home = {
      surface_index = spidertron.surface_index,
      x = spidertron.position.x,
      y = spidertron.position.y,
    }
    if sticky then
      ai.home_sticky = true
    end
  end

  release_claim(ai)
  cancel_ai_pathing(ai)
  ai.retreat_origin = nil
  ai.role = "scout"
  ai.focus_pos = ai.focus_pos or {
    x = spidertron.position.x,
    y = spidertron.position.y,
  }
  scout.reset_run(ai)
  spidertron.follow_target = nil

  local params = spidertron.vehicle_automatic_targeting_parameters
  if params then
    spidertron.vehicle_automatic_targeting_parameters = {
      auto_target_without_gunner = false,
      auto_target_with_gunner = params.auto_target_with_gunner,
    }
  end

  States.transition(ai, States.SCOUT_EXPLORE)

  script.raise_event("on_spidertron_scout_enabled", {
    spidertron = spidertron,
    player_index = player and player.index or nil,
  })

  if player then
    util.flying_text(player, { "sh.scout-enabled" }, spidertron.position)
  end
  shortcut.sync_all()
  mark_manager_dirty()
  return true
end

--- @param spidertron LuaEntity
--- @return string "off"|"hunter"|"scout"
function M.get_role(spidertron)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE then
    return "off"
  end
  if ai.role == "scout" then
    return "scout"
  end
  return "hunter"
end

--- @param spidertron LuaEntity
--- @param role string
--- @param player LuaPlayer?
--- @return boolean
function M.set_role(spidertron, role, player)
  if role == "off" then
    M.disable(spidertron, player)
    return true
  end
  if role == "scout" then
    return M.enable_scout(spidertron, player)
  end
  if role == "hunter" then
    return M.enable(spidertron, player)
  end
  return false
end

--- Pin home to a position (defaults to the spidertron's current position).
--- @param spidertron LuaEntity
--- @param position MapPosition?
--- @return boolean
function M.set_home(spidertron, position)
  if not util.is_valid_spidertron(spidertron) then
    return false
  end
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    ai = persistence.create_ai(spidertron)
  else
    ai.entity = spidertron
  end
  local pos = position or spidertron.position
  ai.home = {
    surface_index = spidertron.surface_index,
    x = pos.x,
    y = pos.y,
  }
  ai.home_sticky = true
  return true
end

--- Unpin sticky home so the next enable (with sticky setting on) re-captures.
--- @param spidertron LuaEntity
--- @return boolean
function M.clear_home(spidertron)
  if not util.is_valid_spidertron(spidertron) then
    return false
  end
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    return false
  end
  ai.home_sticky = false
  return true
end

--- Follow the player's character. Active AI pauses in WAITING; idle spiders just follow.
--- @param spidertron LuaEntity
--- @param player LuaPlayer
--- @return boolean
function M.follow_player(spidertron, player)
  if not util.is_valid_spidertron(spidertron) then
    return false
  end
  if not player or not player.valid or not player.character or not player.character.valid then
    return false
  end
  if spidertron.surface_index ~= player.character.surface_index then
    return false
  end

  local ai = persistence.get_ai_for_entity(spidertron)
  if ai and ai.state ~= States.IDLE then
    cancel_ai_pathing(ai)
    release_claim(ai)
    ai.player_goal = nil
    ai.keep_player_destination = nil
    ai.wait_reason = "follow-player"
    States.transition(ai, States.WAITING)
  end
  movement.follow(spidertron, player.character)
  return true
end

--- Send spidertron home. Active AI enters RETURNING; idle with a home record uses autopilot only.
--- @param spidertron LuaEntity
--- @return boolean
function M.return_home(spidertron)
  if not util.is_valid_spidertron(spidertron) then
    return false
  end
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or not ai.home then
    return false
  end
  if ai.state ~= States.IDLE then
    cancel_ai_pathing(ai)
    release_claim(ai)
    ai.player_goal = nil
    ai.keep_player_destination = nil
    ai.wait_reason = nil
    if spidertron.follow_target then
      spidertron.follow_target = nil
    end
    States.transition(ai, States.RETURNING)
    return true
  end
  movement.go_to(spidertron, movement.home_position(ai), true)
  return true
end

--- @param spidertron LuaEntity
--- @param player LuaPlayer?
function M.disable(spidertron, player)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    return
  end
  local was_scout = is_scout(ai)
  release_claim(ai)
  cancel_ai_pathing(ai)
  ai.retreat_origin = nil
  scout.clear_waypoints(ai)
  ai.focus_pos = nil
  ai.scout_goal = nil
  ai.scout_algo_cursor = nil
  ai.scout_started_tick = nil
  ai.scout_avoid = nil
  if spidertron and spidertron.valid then
    -- Leave any current player destination alone; only drop follow.
    spidertron.follow_target = nil
    patrols.restore(spidertron, ai.patrols_was_auto)
  end
  ai.patrols_was_auto = nil
  ai.role = "hunter"
  States.transition(ai, States.IDLE)

  if was_scout then
    script.raise_event("on_spidertron_scout_disabled", {
      spidertron = spidertron,
      player_index = player and player.index or nil,
    })
  else
    script.raise_event("on_spidertron_hunter_disabled", {
      spidertron = spidertron,
      player_index = player and player.index or nil,
    })
  end

  if player and spidertron and spidertron.valid then
    util.flying_text(player, { "sh.disabled" }, spidertron.position)
  end
  shortcut.sync_all()
  mark_manager_dirty()
end

--- @param spidertron LuaEntity
--- @return boolean
function M.is_enabled(spidertron)
  local ai = persistence.get_ai_for_entity(spidertron)
  return ai ~= nil and ai.state ~= States.IDLE
end

--- @param spidertron LuaEntity
--- @param player LuaPlayer?
function M.toggle(spidertron, player)
  if M.is_enabled(spidertron) then
    M.disable(spidertron, player)
  else
    M.enable(spidertron, player)
  end
end

--- @param player LuaPlayer
--- @return LuaEntity[]
local function collect_targets(player)
  local targets = {}
  if player.spidertron_remote_selection then
    for _, e in pairs(player.spidertron_remote_selection) do
      if util.is_valid_spidertron(e) then
        targets[#targets + 1] = e
      end
    end
  end
  if #targets == 0 and player.vehicle and util.is_valid_spidertron(player.vehicle) then
    targets[1] = player.vehicle
  end
  if #targets == 0 and player.opened and player.opened.object_name == "LuaEntity"
    and util.is_valid_spidertron(player.opened)
  then
    targets[1] = player.opened
  end
  return targets
end

--- Unify selection: if every target is enabled → disable all; otherwise enable
--- Off spiders as Hunter. Does not convert active Scouts to Hunter (use GUI Mode).
--- @param player LuaPlayer
function M.toggle_for_player(player)
  local targets = collect_targets(player)
  if #targets == 0 then
    util.flying_text(player, { "sh.no-selection" })
    return
  end

  local all_enabled = true
  for i = 1, #targets do
    if not M.is_enabled(targets[i]) then
      all_enabled = false
      break
    end
  end

  if all_enabled then
    for i = 1, #targets do
      M.disable(targets[i], player)
    end
  else
    for i = 1, #targets do
      if M.get_role(targets[i]) == "off" then
        M.enable(targets[i], player)
      end
    end
  end
  shortcut.sync_player(player)
end

--- Effective combat style for a spider (per-spider override, else global setting).
--- @param spidertron LuaEntity
--- @return string
function M.get_combat_style(spidertron)
  local ai_data = persistence.get_ai_for_entity(spidertron)
  if ai_data and ai_data.combat_style then
    return ai_data.combat_style
  end
  return settings_mod.get().combat_style or "strafe"
end

--- @param spidertron LuaEntity
--- @param style string
function M.set_combat_style(spidertron, style)
  if not util.is_valid_spidertron(spidertron) then
    return
  end
  local ai_data = persistence.get_ai_for_entity(spidertron)
  if not ai_data then
    ai_data = persistence.create_ai(spidertron)
    ai_data.state = States.IDLE
  end
  ai_data.combat_style = style
end

-- --- State handlers -------------------------------------------------------

States.register(States.IDLE, {
  enter = function(ai)
    release_claim(ai)
  end,
  update = function() end,
})

States.register(States.PATROL, {
  enter = function(ai)
    release_claim(ai)
    ai.next_think_tick = game.tick + 30
  end,
  update = function(ai)
    if is_scout(ai) then
      return States.SCOUT_EXPLORE
    end
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    local retreat = check_tactical_retreat(ai)
    if retreat then
      return retreat
    end
    if game.tick < (ai.next_think_tick or 0) then
      return
    end
    ai.next_think_tick = game.tick + settings_mod.get().scan_interval

    if spidertron.surface_index ~= ai.home.surface_index then
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end

    -- Hunt from current position. Do NOT magnetize back to home here —
    -- home return only happens via RETURNING after combat / retreat.
    return States.SEARCH
  end,
})

States.register(States.SEARCH, {
  update = function(ai)
    if is_scout(ai) then
      return States.SCOUT_EXPLORE
    end
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    local retreat = check_tactical_retreat(ai)
    if retreat then
      return retreat
    end
    local enemy = scanner.scan_for_enemy(ai)
    if enemy and claim_target(ai, enemy) then
      ai.post_combat_since = nil
      return States.MOVING
    end
    -- Still lingering after combat with nothing found — maybe time to go home.
    if ai.post_combat_since and settings_mod.get().return_home_after_combat then
      local linger = settings_mod.get().post_combat_linger_ticks or 0
      if game.tick - ai.post_combat_since >= linger then
        ai.post_combat_since = nil
        return States.RETURNING
      end
    end
    return States.PATROL
  end,
})

States.register(States.MOVING, {
  enter = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    if is_scout(ai) then
      local goal = ai.scout_goal
      if goal then
        movement.go_to(spidertron, goal, true)
      end
      return
    end
    -- Player already issued the destination (remote click on enemy).
    if ai.keep_player_destination then
      ai.keep_player_destination = nil
      return
    end
    local goal = ai.target_pos
    if ai.target_entity and ai.target_entity.valid then
      goal = { x = ai.target_entity.position.x, y = ai.target_entity.position.y }
      ai.target_pos = goal
    end
    if goal then
      movement.go_to(spidertron, goal, true)
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    local retreat = check_tactical_retreat(ai)
    if retreat then
      return retreat
    end

    if is_scout(ai) then
      if abort_scout_if_armed(ai) then
        return
      end
      local cfg = settings_mod.get()
      scout.chart_around(spidertron, cfg.scout_chart_radius)

      if scout.consume_path_failure(ai) then
        movement.clear(spidertron)
        return States.SCOUT_EXPLORE
      end
      if scout.goal_timed_out(ai) then
        scout.abandon_timed_out_goal(ai)
        movement.clear(spidertron)
        return States.SCOUT_EXPLORE
      end

      local threat = scout.find_standoff_enemy(spidertron, cfg.scout_standoff_distance)
      if threat then
        local detour = scout.handle_standoff(ai, spidertron, threat, cfg)
        movement.go_to(spidertron, detour, true)
        return
      end
      if scout.limits_exceeded(ai, cfg) then
        ai.scout_goal = nil
        return States.RETURNING
      end
      local goal = ai.scout_goal
      if not goal then
        return States.SCOUT_EXPLORE
      end
      if movement.is_near(spidertron, goal, scout.ARRIVAL_RADIUS) then
        if ai.scout_goal_kind == "waypoint" then
          scout.pop_waypoint(ai)
        end
        ai.scout_goal = nil
        ai.scout_goal_kind = nil
        ai.scout_goal_set_tick = nil
        movement.clear(spidertron)
        return States.SCOUT_EXPLORE
      end
      if not spidertron.autopilot_destination and not spidertron.follow_target then
        if game.tick - ai.state_entered_tick > 120 then
          movement.go_to(spidertron, goal, true)
        end
      else
        pathfinder.repath_if_stuck(spidertron, goal)
      end
      return
    end

    local target = ai.target_entity
    if not target or not target.valid then
      release_claim(ai)
      return States.SEARCH
    end
    ai.target_pos = { x = target.position.x, y = target.position.y }
    if beyond_pursuit(ai, target.position) then
      release_claim(ai)
      return after_combat_clear(ai)
    end
    if util.distance(spidertron.position, target.position) <= settings_mod.get().combat_range * 1.15 then
      ai.post_combat_since = nil
      return States.ATTACKING
    end
    if ai.pending_goal and util.distance(ai.pending_goal, target.position) > 32 then
      movement.go_to(spidertron, ai.target_pos, true)
    else
      pathfinder.repath_if_stuck(spidertron, ai.target_pos or target.position)
    end
  end,
})

States.register(States.ATTACKING, {
  enter = function(ai)
    if is_scout(ai) then
      return
    end
    ai.post_combat_since = nil
    ai.combat_last_move_tick = 0
    local spidertron = ai.entity
    if util.is_valid_spidertron(spidertron) then
      -- Do not follow into melee/acid — combat module kites at range.
      spidertron.follow_target = nil
      if ai.target_entity and ai.target_entity.valid then
        combat.update(ai, spidertron, ai.target_entity)
      end
    end
  end,
  update = function(ai)
    if is_scout(ai) then
      release_claim(ai)
      return States.SCOUT_EXPLORE
    end
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    local retreat = check_tactical_retreat(ai)
    if retreat then
      return retreat
    end

    local target = ai.target_entity
    if target and target.valid and not beyond_pursuit(ai, target.position) then
      ai.post_combat_since = nil
      combat.update(ai, spidertron, target)
      return
    end

    release_claim(ai)
    local reacquire_radius = math.max(
      COMBAT_REACQUIRE_RADIUS,
      settings_mod.get().search_radius * 0.25
    )
    local next_enemy = scanner.find_nearby_combat(ai, spidertron.position, reacquire_radius)
    if next_enemy and claim_target(ai, next_enemy) then
      ai.post_combat_since = nil
      combat.update(ai, spidertron, next_enemy)
      return
    end

    return after_combat_clear(ai)
  end,
  exit = function(ai)
    local spidertron = ai.entity
    if spidertron and spidertron.valid then
      spidertron.follow_target = nil
    end
  end,
})

States.register(States.RETURNING, {
  enter = function(ai)
    release_claim(ai)
    local spidertron = ai.entity
    if util.is_valid_spidertron(spidertron) then
      movement.go_to(spidertron, movement.home_position(ai), true)
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    if spidertron.surface_index ~= ai.home.surface_index then
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end
    if movement.is_near(spidertron, movement.home_position(ai), ARRIVAL_RADIUS) then
      movement.clear(spidertron)
      local was_retreating = ai.retreating
      ai.retreating = nil
      local cfg = settings_mod.get()
      if cfg.restock_enabled or cfg.repair_enabled or was_retreating then
        return States.RESTOCKING
      end
      if is_scout(ai) then
        if cfg.scout_auto_resume then
          scout.reset_run(ai)
          return States.SCOUT_EXPLORE
        end
        ai.wait_reason = "scout-idle"
        return States.WAITING
      end
      return States.PATROL
    end
    if not spidertron.autopilot_destination and not spidertron.follow_target then
      if game.tick - ai.state_entered_tick > 120 then
        movement.go_to(spidertron, movement.home_position(ai), true)
      end
    else
      pathfinder.repath_if_stuck(spidertron, movement.home_position(ai))
    end
  end,
})

States.register(States.RESTOCKING, {
  enter = function(ai)
    local spidertron = ai.entity
    if spidertron and spidertron.valid then
      movement.clear(spidertron)
    end
  end,
  update = function(ai)
    if logistics.update_restock(ai) then
      local cfg = settings_mod.get()
      if is_scout(ai) then
        ai.retreat_origin = nil
        if cfg.scout_auto_resume then
          scout.reset_run(ai)
          return States.SCOUT_EXPLORE
        end
        ai.wait_reason = "scout-idle"
        return States.WAITING
      end
      if cfg.reengage_after_retreat and ai.retreat_origin then
        return States.REENGAGING
      end
      ai.retreat_origin = nil
      return States.PATROL
    end
  end,
})

States.register(States.REENGAGING, {
  enter = function(ai)
    local spidertron = ai.entity
    local goal = retreat_origin_position(ai)
    if util.is_valid_spidertron(spidertron) and goal then
      movement.go_to(spidertron, goal, true)
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    local cfg = settings_mod.get()
    local origin = ai.retreat_origin
    local goal = retreat_origin_position(ai)
    if not cfg.reengage_after_retreat or not origin or not goal then
      ai.retreat_origin = nil
      return States.SEARCH
    end
    if spidertron.surface_index ~= origin.surface_index then
      ai.retreat_origin = nil
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end
    if movement.is_near(spidertron, goal, ARRIVAL_RADIUS) then
      movement.clear(spidertron)
      ai.retreat_origin = nil
      util.debug_log("re-engage", spidertron)
      return States.SEARCH
    end
    if not spidertron.autopilot_destination and not spidertron.follow_target then
      if game.tick - ai.state_entered_tick > 120 then
        movement.go_to(spidertron, goal, true)
      end
    else
      pathfinder.repath_if_stuck(spidertron, goal)
    end
  end,
})

States.register(States.WAITING, {
  enter = function(ai)
    cancel_ai_pathing(ai)
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end

    -- Manager / follow-player: stay until another order clears follow.
    if ai.wait_reason == "follow-player" then
      if spidertron.follow_target and spidertron.follow_target.valid then
        return
      end
      ai.wait_reason = nil
      if is_scout(ai) then
        return States.SCOUT_EXPLORE
      end
      return States.SEARCH
    end

    if is_scout(ai) then
      if ai.wait_reason == "scout-idle" then
        -- Stay parked until a remote order arrives.
        return
      end
      local arrived = not spidertron.autopilot_destination and not spidertron.follow_target
      if arrived or game.tick - ai.state_entered_tick >= settings_mod.get().max_idle_time then
        ai.wait_reason = nil
        ai.player_goal = nil
        return States.SCOUT_EXPLORE
      end
      return
    end

    local arrived = not spidertron.autopilot_destination and not spidertron.follow_target
    if ai.player_goal and not arrived then
      -- Still traveling on the player order.
      local max_idle = settings_mod.get().max_idle_time
      -- Generous travel budget: max_idle is a floor; long trips use distance heuristic.
      local travel_budget = math.max(max_idle, 3600)
      if game.tick - ai.state_entered_tick >= travel_budget then
        ai.wait_reason = nil
        ai.player_goal = nil
        return States.SEARCH
      end
      return
    end

    if arrived or game.tick - ai.state_entered_tick >= settings_mod.get().max_idle_time then
      ai.wait_reason = nil
      ai.player_goal = nil
      -- Resume hunting here — never snap home after a player move order.
      return States.SEARCH
    end
  end,
})

States.register(States.SCOUT_EXPLORE, {
  enter = function(ai)
    release_claim(ai)
    ai.next_think_tick = game.tick + 15
    if not ai.scout_started_tick then
      ai.scout_started_tick = game.tick
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return
    end
    if not is_scout(ai) then
      return States.PATROL
    end
    if abort_scout_if_armed(ai) then
      return
    end

    local cfg = settings_mod.get()
    scout.chart_around(spidertron, cfg.scout_chart_radius)

    if scout.consume_path_failure(ai) then
      movement.clear(spidertron)
    end

    local retreat = check_tactical_retreat(ai)
    if retreat then
      return retreat
    end

    local threat = scout.find_standoff_enemy(spidertron, cfg.scout_standoff_distance)
    if threat then
      scout.handle_standoff(ai, spidertron, threat, cfg)
      return States.MOVING
    end

    if scout.limits_exceeded(ai, cfg) then
      ai.scout_goal = nil
      return States.RETURNING
    end

    if game.tick < (ai.next_think_tick or 0) then
      return
    end
    ai.next_think_tick = game.tick + cfg.scan_interval

    if spidertron.surface_index ~= ai.home.surface_index then
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end

    -- Waypoints finished and auto-resume off → home / idle.
    if not scout.has_waypoints(ai) and ai.scout_waypoint_run and not cfg.scout_auto_resume then
      ai.scout_waypoint_run = nil
      return States.RETURNING
    end

    local goal, kind = scout.pick_goal(ai, cfg)
    if not goal then
      -- Nothing left to explore (e.g. frontier fully charted).
      return States.RETURNING
    end
    if kind == "waypoint" then
      ai.scout_waypoint_run = true
    end
    ai.scout_goal = goal
    ai.scout_goal_kind = kind
    ai.scout_goal_set_tick = game.tick
    return States.MOVING
  end,
})

--- Called when spider finishes an autopilot leg.
--- @param spidertron LuaEntity
function M.on_spider_command_completed(spidertron)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE then
    return
  end
  if ai.state == States.MOVING then
    States.update(ai)
  elseif ai.state == States.RETURNING or ai.state == States.REENGAGING then
    States.update(ai)
  elseif ai.state == States.WAITING and ai.wait_reason == "player-remote" then
    -- Waypoint finished; if queue empty, resume hunt / scout.
    if not spidertron.autopilot_destination then
      ai.wait_reason = nil
      ai.player_goal = nil
      if is_scout(ai) then
        States.transition(ai, States.SCOUT_EXPLORE)
      else
        States.transition(ai, States.SEARCH)
      end
    end
  end
end

--- Lake-aware go-to for scout Ctrl+right-click (same pathfinder hunters use).
--- @param spidertron LuaEntity
--- @param position MapPosition?
--- @param player LuaPlayer?
function M.on_alt_remote(spidertron, position, player)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE or not is_scout(ai) then
    return
  end
  if not position then
    return
  end

  cancel_ai_pathing(ai)
  release_claim(ai)
  if spidertron.follow_target then
    spidertron.follow_target = nil
  end

  local using_scout_remote = scout.holding_scout_remote(player)
  if using_scout_remote then
    -- Prepend so arrival pops the destination we are traveling to now.
    ai.waypoints = ai.waypoints or {}
    table.insert(ai.waypoints, 1, { x = position.x, y = position.y })
    if player then
      util.flying_text(player, { "sh.scout-waypoint-added" }, spidertron.position)
    end
  else
    scout.set_focus(ai, position)
    if player then
      util.flying_text(player, { "sh.scout-focus-set" }, spidertron.position)
    end
  end

  local goal = scout.ensure_walkable_goal(ai, spidertron, position)
  if not goal then
    if player then
      util.flying_text(player, { "no-path" }, position)
    end
    States.transition(ai, States.SCOUT_EXPLORE)
    return
  end

  ai.scout_goal = goal
  ai.scout_goal_kind = using_scout_remote and "waypoint" or "focus"
  ai.scout_goal_set_tick = game.tick
  ai.player_goal = nil
  ai.wait_reason = nil

  if ai.state == States.MOVING then
    movement.go_to(spidertron, goal, true)
  else
    States.transition(ai, States.MOVING)
  end
end

--- Player remote command. Scout remotes append waypoints; vanilla remote sets focus.
--- @param spidertron LuaEntity
--- @param position MapPosition?
--- @param player LuaPlayer?
function M.on_player_remote(spidertron, position, player)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE then
    return
  end

  if is_scout(ai) then
    cancel_ai_pathing(ai)
    release_claim(ai)
    if spidertron.follow_target then
      spidertron.follow_target = nil
    end
    if not position then
      return
    end
    if scout.holding_scout_remote(player) then
      scout.add_waypoint(ai, position)
      ai.wait_reason = nil
      if player then
        util.flying_text(player, { "sh.scout-waypoint-added" }, spidertron.position)
      end
      -- Start toward this waypoint on the next explore pick.
      if ai.state ~= States.MOVING then
        States.transition(ai, States.SCOUT_EXPLORE)
      end
      return
    end

    -- Vanilla remote (or other): set explore focus.
    scout.set_focus(ai, position)
    ai.wait_reason = nil
    if player then
      util.flying_text(player, { "sh.scout-focus-set" }, spidertron.position)
    end
    States.transition(ai, States.SCOUT_EXPLORE)
    return
  end

  cancel_ai_pathing(ai)
  release_claim(ai)

  if spidertron.follow_target then
    spidertron.follow_target = nil
  end

  local enemy = nil
  if position and spidertron.surface then
    enemy = enemy_at_click(spidertron.surface, position, spidertron.force)
  end

  if enemy then
    -- All selected hunters adopt this enemy; keep the player's autopilot path.
    claim_target(ai, enemy)
    ai.keep_player_destination = true
    ai.player_goal = nil
    ai.wait_reason = nil
    States.transition(ai, States.MOVING)
    return
  end

  -- Non-enemy click: let them finish the player move, then hunt from there.
  ai.player_goal = position and { x = position.x, y = position.y } or nil
  ai.wait_reason = "player-remote"
  States.transition(ai, States.WAITING)
end

--- Force an immediate scan for one spider (or all). Scouts are skipped.
--- @param spidertron LuaEntity?
--- @return integer found_count
function M.force_scan(spidertron)
  local count = 0
  local function scan_one(ai)
    if not ai or ai.state == States.IDLE or is_scout(ai) then
      return
    end
    local enemy = scanner.scan_for_enemy(ai)
    if enemy and claim_target(ai, enemy) then
      count = count + 1
      States.transition(ai, States.MOVING)
    end
  end

  if spidertron and spidertron.valid then
    scan_one(persistence.get_ai_for_entity(spidertron))
  else
    for _, ai in pairs(storage.spiders) do
      scan_one(ai)
    end
  end
  return count
end

--- Debug dump of AI states.
--- @return table
function M.debug_dump()
  local spiders = {}
  for unit_number, ai in pairs(storage.spiders) do
    local entity = ai.entity
    spiders[#spiders + 1] = {
      unit_number = unit_number,
      state = ai.state,
      role = ai.role,
      valid = entity and entity.valid or false,
      home = ai.home,
      focus = ai.focus_pos,
      waypoints = ai.waypoints and #ai.waypoints or 0,
      retreat_origin = ai.retreat_origin,
      target = ai.target_entity and ai.target_entity.valid and ai.target_entity.name or nil,
      wait_reason = ai.wait_reason,
      position = entity and entity.valid and entity.position or nil,
    }
  end
  return {
    spiders = spiders,
    cache = targeting.debug_stats(),
    settings = settings_mod.get(),
  }
end

--- Staggered think for all active spiders.
function M.think_all()
  local cfg = settings_mod.get()
  local n = cfg.spiders_per_think
  local from = storage.think_cursor
  local next_key = util.for_n_of(storage.spiders, from, n, function(ai)
    if not ai then
      return nil, true -- delete
    end
    -- Recover a stale entity ref before giving up (replacement races, etc.).
    if not ai.entity or not ai.entity.valid then
      local recovered = ai.unit_number and game.get_entity_by_unit_number(ai.unit_number)
      if recovered and util.is_valid_spidertron(recovered) then
        ai.entity = recovered
      else
        return nil, true -- delete — truly gone
      end
    end
    if ai.state ~= States.IDLE then
      States.update(ai)
    end
  end)
  storage.think_cursor = next_key
  targeting.prune(4)
end

return M
