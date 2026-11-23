--- State handlers for the Hunter/Scout FSM. Registered on require.
local States = require("scripts.states")
local settings_mod = require("scripts.settings")
local util = require("scripts.util")
local movement = require("scripts.movement")
local scanner = require("scripts.scanner")
local targeting = require("scripts.targeting")
local logistics = require("scripts.logistics")
local combat = require("scripts.combat")
local pathfinder = require("scripts.pathfinder")
local scout = require("scripts.scout")
local common = require("scripts.ai_common")
local is_scout = common.is_scout
local mark_manager_dirty = common.mark_manager_dirty
local abort_scout_if_armed = common.abort_scout_if_armed
local after_combat_clear = common.after_combat_clear
local release_claim = common.release_claim
local claim_target = common.claim_target
local beyond_pursuit = common.beyond_pursuit
local cancel_ai_pathing = common.cancel_ai_pathing
local check_tactical_retreat = common.check_tactical_retreat
local check_low_ammo = common.check_low_ammo
local retreat_origin_position = common.retreat_origin_position
local COMBAT_REACQUIRE_RADIUS = common.COMBAT_REACQUIRE_RADIUS
local ARRIVAL_RADIUS = common.ARRIVAL_RADIUS

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
    local low_ammo = check_low_ammo(ai)
    if low_ammo then
      return low_ammo
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
    local low_ammo = check_low_ammo(ai)
    if low_ammo then
      return low_ammo
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
    -- Ctrl+RMB ground: lake-aware path to player_goal (pathfinder rejects WAITING).
    if ai.player_goal and not (ai.target_entity and ai.target_entity.valid) then
      movement.go_to(spidertron, ai.player_goal, true)
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
    local low_ammo = check_low_ammo(ai)
    if low_ammo then
      return low_ammo
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
    if (not target or not target.valid) and ai.player_goal then
      local goal = ai.player_goal
      if movement.is_near(spidertron, goal, ARRIVAL_RADIUS) then
        ai.player_goal = nil
        movement.clear(spidertron)
        return States.SEARCH
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

    if not target or not target.valid then
      -- Target died en route (e.g. auto-targeting rockets): start the post-combat linger so SEARCH
      -- can send the hunter home once the area stays quiet.
      release_claim(ai)
      ai.post_combat_since = ai.post_combat_since or game.tick
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
    local low_ammo = check_low_ammo(ai)
    if low_ammo then
      return low_ammo
    end

    local combat_range = settings_mod.get().combat_range
    local target = ai.target_entity
    if target and target.valid and not beyond_pursuit(ai, target.position) then
      ai.post_combat_since = nil
      if combat.needs_travel(util.distance(spidertron.position, target.position), combat_range) then
        -- Target moved/retreated far away: path lake-aware instead of kiting hops.
        return States.MOVING
      end
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
      if combat.needs_travel(util.distance(spidertron.position, next_enemy.position), combat_range) then
        -- Next mob is far (possibly across water): lake-aware travel, not straight-line kiting.
        return States.MOVING
      end
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
