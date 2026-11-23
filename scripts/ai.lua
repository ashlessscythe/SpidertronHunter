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

local common = require("scripts.ai_common")
require("scripts.ai_states")

local M = {}

local PLAYER_CLICK_ENEMY_RADIUS = 8

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
  if spidertron and spidertron.valid and storage.path_only then
    storage.path_only[spidertron.unit_number] = nil
  end
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
  ai.ammo_baseline = logistics.snapshot_ammo_baseline(spidertron)
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
  if spidertron and spidertron.valid and storage.path_only then
    storage.path_only[spidertron.unit_number] = nil
  end
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

--- Lake-aware go-to for Ctrl+right-click (hunters and scouts).
--- @param spidertron LuaEntity
--- @param position MapPosition?
--- @param player LuaPlayer?
function M.on_alt_remote(spidertron, position, player)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE then
    return
  end
  if not position then
    return
  end

  if is_scout(ai) then
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
    return
  end

  -- Hunter: lake-aware path (plain RMB keeps vanilla straight autopilot).
  cancel_ai_pathing(ai)
  release_claim(ai)
  if spidertron.follow_target then
    spidertron.follow_target = nil
  end

  local enemy = nil
  if spidertron.surface then
    enemy = enemy_at_click(spidertron.surface, position, spidertron.force)
  end

  if enemy then
    claim_target(ai, enemy)
    ai.keep_player_destination = nil
    ai.player_goal = nil
    ai.wait_reason = nil
    if ai.state == States.MOVING then
      movement.go_to(spidertron, ai.target_pos, true)
    else
      States.transition(ai, States.MOVING)
    end
    return
  end

  ai.player_goal = { x = position.x, y = position.y }
  ai.keep_player_destination = nil
  ai.wait_reason = nil
  if ai.state == States.MOVING then
    movement.go_to(spidertron, ai.player_goal, true)
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
  local next_key = util.for_n_of(storage.spiders, from, n, function(ai, key)
    if not ai then
      return nil, true -- delete
    end
    -- Recover a stale entity ref before giving up (replacement races, etc.).
    if not ai.entity or not ai.entity.valid then
      local recovered = ai.unit_number and game.get_entity_by_unit_number(ai.unit_number)
      if recovered and util.is_valid_spidertron(recovered) then
        ai.entity = recovered
      else
        persistence.release_ai_resources(ai.unit_number or key, ai)
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

common.disable = M.disable

return M
