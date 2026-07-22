--- Relative GUI toggle on spider-vehicle (right side, above Patrols schedule when present).
local ai = require("scripts.ai")
local util = require("scripts.util")
local persistence = require("scripts.persistence")

local M = {}

local FRAME_NAME = "sh-relative-frame"
local BUTTON_NAME = "sh-toggle-button"

--- @param player LuaPlayer
--- @return LuaEntity?
local function opened_spidertron(player)
  local opened = player.opened
  if opened and opened.object_name == "LuaEntity" and util.is_valid_spidertron(opened) then
    return opened
  end
  return nil
end

--- @param player LuaPlayer
--- @param spidertron LuaEntity
local function build_gui(player, spidertron)
  local relative = player.gui.relative
  local existing = relative[FRAME_NAME]
  if existing then
    existing.destroy()
  end

  local enabled = ai.is_enabled(spidertron)
  -- Right side of the spidertron GUI — sits in the empty column above
  -- Spidertron Patrols' schedule/camera when that mod is present.
  local frame = relative.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "horizontal",
    anchor = {
      gui = defines.relative_gui_type.spider_vehicle_gui,
      position = defines.relative_gui_position.right,
      name = spidertron.name,
    },
  })

  frame.add({
    type = "label",
    caption = { "mod-name.SpidertronHunter" },
    style = "frame_title",
  })

  frame.add({
    type = "button",
    name = BUTTON_NAME,
    caption = enabled and { "sh.enabled" } or { "sh.toggle-button" },
    tooltip = { "sh.toggle-tooltip" },
    style = "button",
    tags = { sh_unit_number = spidertron.unit_number },
  })

  local ai_data = persistence.get_ai_for_entity(spidertron)
  if enabled and ai_data and ai_data.state then
    frame.add({
      type = "label",
      caption = { "sh.state-" .. ai_data.state },
    })
  elseif not enabled then
    frame.add({
      type = "label",
      caption = { "sh.disabled" },
    })
  end
end

--- @param event EventData.on_gui_opened
function M.on_gui_opened(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local entity = event.entity
  if entity and util.is_valid_spidertron(entity) then
    build_gui(player, entity)
  end
end

--- @param event EventData.on_gui_closed
function M.on_gui_closed(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local frame = player.gui.relative[FRAME_NAME]
  if frame then
    frame.destroy()
  end
end

--- @param event EventData.on_gui_click
function M.on_gui_click(event)
  local element = event.element
  if not element or not element.valid or element.name ~= BUTTON_NAME then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  local spidertron = opened_spidertron(player)
  if not spidertron then
    local unit_number = element.tags and element.tags.sh_unit_number
    local ai_data = unit_number and persistence.get_ai(unit_number)
    if ai_data and ai_data.entity and ai_data.entity.valid then
      spidertron = ai_data.entity
    end
  end
  if not spidertron then
    return
  end

  ai.toggle(spidertron, player)
  if util.is_valid_spidertron(spidertron) then
    build_gui(player, spidertron)
  end
end

return M
