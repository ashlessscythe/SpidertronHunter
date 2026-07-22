--- Enable/disable, orchestration, state handlers.
local States = require("scripts.states")
local persistence = require("scripts.persistence")
local settings_mod = require("scripts.settings")
local util = require("scripts.util")
local movement = require("scripts.movement")
local scanner = require("scripts.scanner")
local targeting = require("scripts.targeting")
local logistics = require("scripts.logistics")

local M = {}

local COMBAT_REACQUIRE_RADIUS = 48
local ARRIVAL_RADIUS = 8
local PATROL_WANDER_RADIUS = 32

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

local function claim_target(ai, entity)
  release_claim(ai)
  if not entity or not entity.valid then
    return false
  end
  local id = targeting.remember(entity)
  if not id then
    return false
  end
  local claimer = storage.target_claims[id]
  if claimer and claimer ~= ai.unit_number then
    return false
  end
  storage.target_claims[id] = ai.unit_number
  ai.claim_id = id
  ai.target_entity = entity
  ai.target_pos = { x = entity.position.x, y = entity.position.y }
  return true
end

local function beyond_pursuit(ai, position)
  local home = { x = ai.home.x, y = ai.home.y }
  return util.distance(home, position) > settings_mod.get().max_pursuit_distance
end

--- Deny enable while Spidertron Patrols reports on_patrol when the remote returns data.
--- Note: Patrols' remote `get_patrol_data` historically omitted `return`; if nil, we allow enable.
local function is_on_patrols(spidertron)
  if not remote.interfaces["SpidertronPatrols"] or not remote.interfaces["SpidertronPatrols"].get_patrol_data then
    return false
  end
  local ok, data = pcall(function()
    return remote.call("SpidertronPatrols", "get_patrol_data", spidertron)
  end)
  if not ok or type(data) ~= "table" then
    return false
  end
  return data.on_patrol ~= nil
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
  if is_on_patrols(spidertron) then
    if player then
      util.flying_text(player, { "sh.denied-patrols" }, spidertron.position)
    end
    return false
  end

  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    ai = persistence.create_ai(spidertron)
  else
    ai.entity = spidertron
  end

  ai.home = {
    surface_index = spidertron.surface_index,
    x = spidertron.position.x,
    y = spidertron.position.y,
  }
  release_claim(ai)
  movement.clear(spidertron)

  -- Ensure vanilla auto-targeting while hunting.
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
  return true
end

--- @param spidertron LuaEntity
--- @param player LuaPlayer?
function M.disable(spidertron, player)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai then
    return
  end
  release_claim(ai)
  if spidertron and spidertron.valid then
    movement.clear(spidertron)
  end
  States.transition(ai, States.IDLE)
  -- Keep record so GUI can show disabled; optional full remove:
  -- persistence.remove_ai(ai.unit_number)

  script.raise_event("on_spidertron_hunter_disabled", {
    spidertron = spidertron,
    player_index = player and player.index or nil,
  })

  if player and spidertron and spidertron.valid then
    util.flying_text(player, { "sh.disabled" }, spidertron.position)
  end
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
function M.toggle_for_player(player)
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
  if #targets == 0 then
    util.flying_text(player, { "sh.no-selection" })
    return
  end
  for i = 1, #targets do
    M.toggle(targets[i], player)
  end
end

-- --- State handlers -------------------------------------------------------

States.register(States.IDLE, {
  enter = function(ai)
    release_claim(ai)
  end,
  update = function()
    -- Disabled — nothing to do.
  end,
})

States.register(States.PATROL, {
  enter = function(ai)
    release_claim(ai)
    ai.next_think_tick = game.tick + 30
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return States.IDLE
    end
    if game.tick < (ai.next_think_tick or 0) then
      return
    end
    ai.next_think_tick = game.tick + settings_mod.get().scan_interval

    if spidertron.surface_index ~= ai.home.surface_index then
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end

    local home = movement.home_position(ai)
    if util.distance(spidertron.position, home) > PATROL_WANDER_RADIUS then
      movement.go_to(spidertron, home, true)
    end

    return States.SEARCH
  end,
})

States.register(States.SEARCH, {
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return States.IDLE
    end
    local enemy = scanner.scan_for_enemy(ai)
    if enemy and claim_target(ai, enemy) then
      return States.MOVING
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
      return States.IDLE
    end
    local target = ai.target_entity
    if not target or not target.valid then
      release_claim(ai)
      return States.SEARCH
    end
    ai.target_pos = { x = target.position.x, y = target.position.y }
    if beyond_pursuit(ai, target.position) then
      release_claim(ai)
      if settings_mod.get().return_home_after_combat then
        return States.RETURNING
      end
      return States.PATROL
    end
    -- Close enough to engage (guns have range; don't wait for exact tile).
    if util.distance(spidertron.position, target.position) <= ARRIVAL_RADIUS + 16 then
      return States.ATTACKING
    end
    -- Refresh path occasionally if target moved far from pending goal.
    if ai.pending_goal and util.distance(ai.pending_goal, target.position) > 32 then
      movement.go_to(spidertron, ai.target_pos, true)
    end
  end,
})

States.register(States.ATTACKING, {
  enter = function(ai)
    local spidertron = ai.entity
    if util.is_valid_spidertron(spidertron) and ai.target_entity and ai.target_entity.valid then
      -- Stick close: follow when practical, else point destination.
      movement.follow(spidertron, ai.target_entity)
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return States.IDLE
    end

    local target = ai.target_entity
    if target and target.valid and not beyond_pursuit(ai, target.position) then
      if spidertron.follow_target ~= target then
        movement.follow(spidertron, target)
      end
      return
    end

    -- Current target gone — reacquire nearby.
    release_claim(ai)
    local next_enemy = scanner.find_nearby_combat(ai, spidertron.position, COMBAT_REACQUIRE_RADIUS)
    if next_enemy and claim_target(ai, next_enemy) then
      movement.follow(spidertron, next_enemy)
      return
    end

    if settings_mod.get().return_home_after_combat then
      return States.RETURNING
    end
    return States.PATROL
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
      return States.IDLE
    end
    if spidertron.surface_index ~= ai.home.surface_index then
      ai.wait_reason = "wrong-surface"
      return States.WAITING
    end
    if movement.is_near(spidertron, movement.home_position(ai), ARRIVAL_RADIUS) then
      movement.clear(spidertron)
      local cfg = settings_mod.get()
      if cfg.restock_enabled or cfg.repair_enabled then
        return States.RESTOCKING
      end
      return States.PATROL
    end
    -- Re-issue path if idle too long without destination.
    if not spidertron.autopilot_destination and not spidertron.follow_target then
      if game.tick - ai.state_entered_tick > 120 then
        movement.go_to(spidertron, movement.home_position(ai), true)
      end
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
      return States.PATROL
    end
  end,
})

States.register(States.WAITING, {
  enter = function(ai)
    local spidertron = ai.entity
    if spidertron and spidertron.valid then
      -- Leave current destinations; player may have overridden.
    end
  end,
  update = function(ai)
    local spidertron = ai.entity
    if not util.is_valid_spidertron(spidertron) then
      return States.IDLE
    end
    local max_idle = settings_mod.get().max_idle_time
    if game.tick - ai.state_entered_tick >= max_idle then
      ai.wait_reason = nil
      return States.PATROL
    end
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
  elseif ai.state == States.RETURNING then
    States.update(ai)
  end
end

--- Player remote command — pause AI briefly so we don't fight the player.
--- @param spidertron LuaEntity
function M.on_player_remote(spidertron)
  local ai = persistence.get_ai_for_entity(spidertron)
  if not ai or ai.state == States.IDLE then
    return
  end
  ai.wait_reason = "player-remote"
  States.transition(ai, States.WAITING)
end

--- Staggered think for all active spiders.
function M.think_all()
  local cfg = settings_mod.get()
  local n = cfg.spiders_per_think
  local from = storage.think_cursor
  local next_key = util.for_n_of(storage.spiders, from, n, function(ai)
    if not ai or not ai.entity or not ai.entity.valid then
      return nil, true -- delete
    end
    if ai.state ~= States.IDLE then
      States.update(ai)
    end
  end)
  storage.think_cursor = next_key
  targeting.prune(4)
end

return M
