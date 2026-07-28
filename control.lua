local persistence = require("scripts.persistence")
local settings_mod = require("scripts.settings")
local ai = require("scripts.ai")
local pathfinder = require("scripts.pathfinder")
local targeting = require("scripts.targeting")
local gui = require("scripts.gui")
local manager_gui = require("scripts.manager_gui")
local shortcut = require("scripts.shortcut")

require("scripts.remote-interface")

-- Debounce: associated_control_input can fire both custom-input and on_lua_shortcut.
local last_manager_tick = {}

local function toggle_manager(player)
  if not player or not player.valid then
    return
  end
  local tick = game.tick
  if last_manager_tick[player.index] == tick then
    return
  end
  last_manager_tick[player.index] = tick
  manager_gui.toggle(player)
end

--- Re-bind nth-tick handlers. Re-registering the same tick replaces the previous handler.
local function register_nth_tick(interval)
  interval = math.max(10, math.floor(interval or 60))

  local previous = storage.registered_scan_interval
  if previous and previous ~= interval then
    script.on_nth_tick(previous, nil)
  end
  storage.registered_scan_interval = interval

  script.on_nth_tick(1, function()
    pathfinder.on_tick_reset_budget()
    manager_gui.flush_dirty()
  end)

  script.on_nth_tick(interval, function()
    ai.think_all()
  end)
end

script.on_init(function()
  persistence.init_storage()
  settings_mod.refresh()
  manager_gui.reset_tracking()
  register_nth_tick(settings_mod.get().scan_interval)
end)

script.on_load(function()
  -- Must not write storage here (save/load + MP safety). GUI open-count is
  -- reconciled in manager_gui.flush_dirty after load (custom GUIs are not saved).
  local interval = (storage.settings_cache and storage.settings_cache.scan_interval) or 60
  register_nth_tick(interval)
end)

script.on_configuration_changed(function()
  persistence.init_storage()
  -- Versioned migrations/*.lua also run; this catches missing tables on reload.
  settings_mod.refresh()
  manager_gui.reset_tracking()
  register_nth_tick(settings_mod.get().scan_interval)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting_type ~= "runtime-global" then
    return
  end
  if string.sub(event.setting, 1, 3) ~= "sh-" then
    return
  end
  local old_interval = storage.settings_cache and storage.settings_cache.scan_interval
  settings_mod.refresh()
  local new_interval = settings_mod.get().scan_interval
  if old_interval ~= new_interval then
    register_nth_tick(new_interval)
  end
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  persistence.on_object_destroyed(event)
end)

script.on_event(defines.events.on_spider_command_completed, function(event)
  local vehicle = event.vehicle
  if vehicle and vehicle.valid then
    ai.on_spider_command_completed(vehicle)
  end
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
  pathfinder.on_path_finished(event)
end)

script.on_event(defines.events.on_player_used_spidertron_remote, function(event)
  local player = game.get_player(event.player_index)
  if not player or not player.spidertron_remote_selection then
    return
  end
  local position = event.position
  for _, spidertron in pairs(player.spidertron_remote_selection) do
    if spidertron and spidertron.valid then
      ai.on_player_remote(spidertron, position, player)
    end
  end
end)

-- Ctrl+right-click: lake-aware path for hunters and scouts (Hunter pathfinder).
script.on_event("sh-use-alt-spidertron-remote", function(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid or not player.spidertron_remote_selection then
    return
  end
  local cursor = player.cursor_stack
  if not cursor or not cursor.valid_for_read then
    return
  end
  if cursor.type ~= "spidertron-remote" or cursor.name == "sp-spidertron-patrol-remote" then
    return
  end
  local position = event.cursor_position
  if not position then
    return
  end
  for _, spidertron in pairs(player.spidertron_remote_selection) do
    if spidertron and spidertron.valid then
      ai.on_alt_remote(spidertron, position, player)
    end
  end
end)

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return
  end
  if entity.type == "spider-vehicle" then
    manager_gui.mark_dirty()
    return
  end
  targeting.remove_entity(entity)
end, {
  { filter = "type", type = "unit-spawner" },
  { filter = "type", type = "unit" },
  { filter = "type", type = "turret" },
  { filter = "type", type = "spider-unit" },
  { filter = "type", type = "spider-vehicle" },
})

-- Debounce: associated_control_input can fire both the custom-input event and
-- on_lua_shortcut on one keypress. Handling either alone can miss click or key.
local last_toggle_tick = {}

local function toggle_autonomy(player)
  if not player or not player.valid then
    return
  end
  local tick = game.tick
  if last_toggle_tick[player.index] == tick then
    return
  end
  last_toggle_tick[player.index] = tick
  ai.toggle_for_player(player)
  shortcut.sync_player(player)
end

script.on_event("sh-toggle-autonomy", function(event)
  toggle_autonomy(game.get_player(event.player_index))
end)

script.on_event("sh-open-manager", function(event)
  toggle_manager(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "sh-toggle-autonomy" then
    toggle_autonomy(game.get_player(event.player_index))
    return
  end
  if event.prototype_name == "sh-open-manager" then
    toggle_manager(game.get_player(event.player_index))
  end
end)

-- Keep toolbar highlight in sync with remote selection.
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then
    shortcut.sync_player(player)
  end
end)

script.on_event(defines.events.on_gui_opened, function(event)
  gui.on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if player then
    shortcut.sync_player(player)
  end
end)
script.on_event(defines.events.on_gui_closed, function(event)
  manager_gui.on_gui_closed(event)
  gui.on_gui_closed(event)
end)
script.on_event(defines.events.on_gui_click, function(event)
  manager_gui.on_gui_click(event)
  gui.on_gui_click(event)
  local player = game.get_player(event.player_index)
  if player then
    shortcut.sync_player(player)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, gui.on_gui_selection_state_changed)

--- Register an event only when the id exists (2.0 / 2.1 single-codebase).
--- @param event_id defines.events|uint|string|nil
--- @param handler fun(event: EventData)
--- @param filters EventFilter[]?
local function on_event(event_id, handler, filters)
  if event_id then
    script.on_event(event_id, handler, filters)
  end
end

local SPIDER_FILTER = { { filter = "type", type = "spider-vehicle" } }

--- @param _event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.script_raised_built|EventData.script_raised_destroy|EventData.script_raised_revive|EventData.on_entity_cloned|EventData.on_space_platform_built_entity|EventData.on_space_platform_mined_entity
local function mark_manager_spider_event(_event)
  manager_gui.mark_dirty()
end

on_event(defines.events.on_built_entity, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.on_robot_built_entity, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.on_player_mined_entity, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.on_robot_mined_entity, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.script_raised_built, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.script_raised_revive, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.script_raised_destroy, mark_manager_spider_event, SPIDER_FILTER)
on_event(defines.events.on_entity_cloned, mark_manager_spider_event, SPIDER_FILTER)

if script.feature_flags and script.feature_flags.space_travel then
  on_event(defines.events.on_space_platform_built_entity, mark_manager_spider_event, SPIDER_FILTER)
  on_event(defines.events.on_space_platform_mined_entity, mark_manager_spider_event, SPIDER_FILTER)
end

--- @param event EventData.on_entity_renamed
local function on_entity_renamed(event)
  local entity = event.entity
  if entity and entity.valid and entity.type == "spider-vehicle" then
    manager_gui.mark_dirty()
  end
end
on_event(defines.events.on_entity_renamed, on_entity_renamed)

--- @param event EventData.on_entity_color_changed
local function on_entity_color_changed(event)
  local entity = event.entity
  if entity and entity.valid and entity.type == "spider-vehicle" then
    manager_gui.mark_dirty()
  end
end
on_event(defines.events.on_entity_color_changed, on_entity_color_changed)

--- @param event EventData.on_player_changed_surface
local function on_player_changed_surface(event)
  local player = game.get_player(event.player_index)
  if player and player.valid and player.gui.screen[manager_gui.FRAME_NAME] then
    manager_gui.mark_dirty()
  end
end
on_event(defines.events.on_player_changed_surface, on_player_changed_surface)

-- Soft-compat: remap when another mod replaces a spidertron entity.
if prototypes.custom_event["on_spidertron_replaced"] then
  script.on_event("on_spidertron_replaced", function(event)
    local old = event.old_spidertron
    local new = event.new_spidertron
    if old and old.valid and new and new.valid then
      persistence.remap_spidertron(old.unit_number, new)
    elseif event.unit_number and new and new.valid then
      persistence.remap_spidertron(event.unit_number, new)
    end
    manager_gui.mark_dirty()
  end)
end
