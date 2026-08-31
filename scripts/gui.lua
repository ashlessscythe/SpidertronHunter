--- Relative GUI mode + combat style on spider-vehicle (right side).
local ai = require("scripts.ai")
local util = require("scripts.util")
local persistence = require("scripts.persistence")

local M = {}

local FRAME_NAME = "sh-relative-frame"
local MODE_DROPDOWN = "sh-mode-dropdown"
local SET_HOME_BUTTON = "sh-set-home-button"
local CLEAR_HOME_BUTTON = "sh-clear-home-button"
local STYLE_DROPDOWN = "sh-combat-style-dropdown"

local MODE_ORDER = { "off", "hunter", "scout" }
local STYLE_ORDER = { "hold", "strafe", "circle", "flank" }

local function mode_index(role)
  for i = 1, #MODE_ORDER do
    if MODE_ORDER[i] == role then
      return i
    end
  end
  return 1
end

local function style_index(style)
  for i = 1, #STYLE_ORDER do
    if STYLE_ORDER[i] == style then
      return i
    end
  end
  return 2 -- strafe
end

--- @param player LuaPlayer
--- @return LuaEntity?
local function opened_spidertron(player)
  local opened = player.opened
  if opened and opened.object_name == "LuaEntity" and util.is_valid_spidertron(opened) then
    return opened
  end
  return nil
end

--- @param parent LuaGuiElement
--- @param caption LocalisedString
--- @return LuaGuiElement row
local function add_row(parent, caption)
  local row = parent.add({
    type = "flow",
    direction = "horizontal",
  })
  row.add({
    type = "label",
    caption = caption,
  })
  return row
end

--- @param player LuaPlayer
--- @param spidertron LuaEntity
local function build_gui(player, spidertron)
  local relative = player.gui.relative
  local existing = relative[FRAME_NAME]
  if existing then
    existing.destroy()
  end

  local role = ai.get_role(spidertron)
  local tags = { sh_unit_number = spidertron.unit_number }

  local frame = relative.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
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

  local body = frame.add({
    type = "flow",
    direction = "vertical",
    name = "sh-gui-body",
  })

  local mode_items = {}
  for i = 1, #MODE_ORDER do
    mode_items[i] = { "sh.mode-" .. MODE_ORDER[i] }
  end
  local mode_row = add_row(body, { "sh.mode-label" })
  mode_row.add({
    type = "drop-down",
    name = MODE_DROPDOWN,
    items = mode_items,
    selected_index = mode_index(role),
    tooltip = { "sh.mode-tooltip" },
    tags = tags,
  })

  if role == "hunter" then
    local style_items = {}
    for i = 1, #STYLE_ORDER do
      style_items[i] = { "sh.combat-style-" .. STYLE_ORDER[i] }
    end
    local current = ai.get_combat_style(spidertron)
    local style_row = add_row(body, { "sh.combat-style-label" })
    style_row.add({
      type = "drop-down",
      name = STYLE_DROPDOWN,
      items = style_items,
      selected_index = style_index(current),
      tooltip = { "sh.combat-style-tooltip" },
      tags = tags,
    })
  end

  local home_row = body.add({
    type = "flow",
    direction = "horizontal",
    name = "sh-home-row",
  })
  home_row.add({
    type = "button",
    name = SET_HOME_BUTTON,
    caption = { "sh.set-home-button" },
    tooltip = { "sh.set-home-tooltip" },
    style = "button",
    tags = tags,
  })
  home_row.add({
    type = "button",
    name = CLEAR_HOME_BUTTON,
    caption = { "sh.clear-home-button" },
    tooltip = { "sh.clear-home-tooltip" },
    style = "button",
    tags = tags,
  })

  local ai_data = persistence.get_ai_for_entity(spidertron)
  local status_caption
  if role ~= "off" and ai_data and ai_data.state then
    status_caption = { "sh.state-" .. ai_data.state }
  elseif role == "off" then
    status_caption = { "sh.disabled" }
  end
  if status_caption then
    body.add({
      type = "label",
      caption = status_caption,
      style = "caption_label",
      name = "sh-status-label",
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

--- @param unit_number integer?
--- @param player LuaPlayer
--- @return LuaEntity?
local function resolve_spidertron(unit_number, player)
  local spidertron = opened_spidertron(player)
  if spidertron then
    return spidertron
  end
  if unit_number then
    local ai_data = persistence.get_ai(unit_number)
    if ai_data and ai_data.entity and ai_data.entity.valid then
      return ai_data.entity
    end
  end
  return nil
end

--- @param event EventData.on_gui_click
function M.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then
    return
  end
  local name = element.name
  if name ~= SET_HOME_BUTTON and name ~= CLEAR_HOME_BUTTON then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  local spidertron = resolve_spidertron(element.tags and element.tags.sh_unit_number, player)
  if not spidertron then
    return
  end

  if name == SET_HOME_BUTTON then
    if ai.set_home(spidertron) then
      util.flying_text(player, { "sh.home-set" }, spidertron.position)
    end
  elseif name == CLEAR_HOME_BUTTON then
    if ai.clear_home(spidertron) then
      util.flying_text(player, { "sh.home-cleared" }, spidertron.position)
    end
  end

  if util.is_valid_spidertron(spidertron) then
    build_gui(player, spidertron)
  end
end

--- @param event EventData.on_gui_selection_state_changed
function M.on_gui_selection_state_changed(event)
  local element = event.element
  if not element or not element.valid then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local spidertron = resolve_spidertron(element.tags and element.tags.sh_unit_number, player)
  if not spidertron then
    return
  end

  if element.name == MODE_DROPDOWN then
    local role = MODE_ORDER[element.selected_index]
    if role then
      ai.set_role(spidertron, role, player)
    end
    if util.is_valid_spidertron(spidertron) then
      build_gui(player, spidertron)
    end
    return
  end

  if element.name ~= STYLE_DROPDOWN then
    return
  end
  local idx = element.selected_index
  local style = STYLE_ORDER[idx]
  if not style then
    return
  end
  ai.set_combat_style(spidertron, style)
  util.debug_log("style → " .. style, spidertron)
end

M.STYLE_ORDER = STYLE_ORDER
M.MODE_ORDER = MODE_ORDER

return M
