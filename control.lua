local persistence = require("scripts.persistence")
local settings_mod = require("scripts.settings")
local ai = require("scripts.ai")
local pathfinder = require("scripts.pathfinder")
local targeting = require("scripts.targeting")
local gui = require("scripts.gui")
local shortcut = require("scripts.shortcut")

require("scripts.remote-interface")

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
  end)

  script.on_nth_tick(interval, function()
    ai.think_all()
  end)
end

script.on_init(function()
  persistence.init_storage()
  settings_mod.refresh()
  register_nth_tick(settings_mod.get().scan_interval)
end)

script.on_load(function()
  local interval = (storage.settings_cache and storage.settings_cache.scan_interval) or 60
  register_nth_tick(interval)
end)

script.on_configuration_changed(function()
  persistence.init_storage()
  settings_mod.refresh()
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
      ai.on_player_remote(spidertron, position)
    end
  end
end)

script.on_event(defines.events.on_entity_died, function(event)
  local entity = event.entity
  if entity and entity.valid then
    targeting.remove_entity(entity)
  end
end, {
  { filter = "type", type = "unit-spawner" },
  { filter = "type", type = "unit" },
  { filter = "type", type = "turret" },
  { filter = "type", type = "spider-unit" },
})

script.on_event("sh-toggle-autonomy", function(event)
  local player = game.get_player(event.player_index)
  if player then
    ai.toggle_for_player(player)
    shortcut.sync_player(player)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "sh-toggle-autonomy" then
    return
  end
  local player = game.get_player(event.player_index)
  if player then
    ai.toggle_for_player(player)
    shortcut.sync_player(player)
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
script.on_event(defines.events.on_gui_closed, gui.on_gui_closed)
script.on_event(defines.events.on_gui_click, function(event)
  gui.on_gui_click(event)
  local player = game.get_player(event.player_index)
  if player then
    shortcut.sync_player(player)
  end
end)

-- Soft-compat with SpidertronEnhancements entity replace (same pattern as Patrols).
if prototypes.custom_event["on_spidertron_replaced"] then
  script.on_event("on_spidertron_replaced", function(event)
    local old = event.old_spidertron
    local new = event.new_spidertron
    if old and old.valid and new and new.valid then
      persistence.remap_spidertron(old.unit_number, new)
    elseif event.unit_number and new and new.valid then
      persistence.remap_spidertron(event.unit_number, new)
    end
  end)
end
