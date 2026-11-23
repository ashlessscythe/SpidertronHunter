--- Shared helpers for the Hunter/Scout AI (used by ai.lua and ai_states.lua).
local States = require("scripts.states")
local settings_mod = require("scripts.settings")
local util = require("scripts.util")
local alerts = require("scripts.alerts")
local scanner = require("scripts.scanner")
local targeting = require("scripts.targeting")
local logistics = require("scripts.logistics")
local pathfinder = require("scripts.pathfinder")
local scout = require("scripts.scout")

local C = {}

C.COMBAT_REACQUIRE_RADIUS = 64
C.ARRIVAL_RADIUS = 8

--- Set by ai.lua (avoids a circular require).
--- @type fun(spidertron: LuaEntity, player: LuaPlayer?)
C.disable = function() end

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
  C.disable(spidertron, nil)
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
    alerts.notify(spidertron, "retreat", ai, string.format("%.0f", ratio * 100))
    return States.RETURNING
  end
  return nil
end

--- Return home to restock when average ammo fill drops below the configured %.
--- @param ai table
--- @return string? next_state
local function check_low_ammo(ai)
  if is_scout(ai) then
    return nil
  end
  local cfg = settings_mod.get()
  if not cfg.restock_enabled then
    return nil
  end
  local threshold = cfg.restock_ammo_percent or 0
  if threshold <= 0 then
    return nil
  end
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return nil
  end
  local home = ai.home
  if home and util.distance({ x = home.x, y = home.y }, spidertron.position) <= scanner.NEAR_HOME_THRESHOLD then
    return nil
  end
  if not logistics.ammo_below_threshold(spidertron, threshold, ai) then
    return nil
  end
  local current, desired = logistics.ammo_counts(spidertron, ai)
  local ratio = logistics.ratio_from_counts(current, desired)
  release_claim(ai)
  cancel_ai_pathing(ai)
  ai.post_combat_since = nil
  util.debug_log(
    "low ammo "
      .. string.format("%.0f", ratio * 100)
      .. "% ("
      .. tostring(current)
      .. "/"
      .. tostring(desired)
      .. ")",
    spidertron
  )
  alerts.notify(spidertron, "low-ammo", ai)
  return States.RETURNING
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

C.is_scout = is_scout
C.mark_manager_dirty = mark_manager_dirty
C.abort_scout_if_armed = abort_scout_if_armed
C.after_combat_clear = after_combat_clear
C.release_claim = release_claim
C.claim_target = claim_target
C.beyond_pursuit = beyond_pursuit
C.cancel_ai_pathing = cancel_ai_pathing
C.check_tactical_retreat = check_tactical_retreat
C.check_low_ammo = check_low_ammo
C.retreat_origin_position = retreat_origin_position

return C
