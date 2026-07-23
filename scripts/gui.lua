--- Relative GUI toggle + combat style on spider-vehicle (right side).
local ai = require("scripts.ai")
local util = require("scripts.util")
local persistence = require("scripts.persistence")

local M = {}

local FRAME_NAME = "sh-relative-frame"
local BUTTON_NAME = "sh-toggle-button"
local SET_HOME_BUTTON = "sh-set-home-button"
local CLEAR_HOME_BUTTON = "sh-clear-home-button"
local STYLE_DROPDOWN = "sh-combat-style-dropdown"

local STYLE_ORDER = { "hold", "strafe", "circle", "flank" }

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

--- @param player LuaPlayer
--- @param spidertron LuaEntity
local function build_gui(player, spidertron)
  local relative = player.gui.relative
  local existing = relative[FRAME_NAME]
  if existing then
    existing.destroy()
  end

  local enabled = ai.is_enabled(spidertron)
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

  frame.add({
    type = "button",
    name = SET_HOME_BUTTON,
    caption = { "sh.set-home-button" },
    tooltip = { "sh.set-home-tooltip" },
    style = "button",
    tags = { sh_unit_number = spidertron.unit_number },
  })

  frame.add({
    type = "button",
    name = CLEAR_HOME_BUTTON,
    caption = { "sh.clear-home-button" },
    tooltip = { "sh.clear-home-tooltip" },
    style = "button",
    tags = { sh_unit_number = spidertron.unit_number },
  })

  frame.add({
    type = "label",
    caption = { "sh.combat-style-label" },
  })

  local items = {}
  for i = 1, #STYLE_ORDER do
    items[i] = { "sh.combat-style-" .. STYLE_ORDER[i] }
  end
  local current = ai.get_combat_style(spidertron)
  frame.add({
    type = "drop-down",
    name = STYLE_DROPDOWN,
    items = items,
    selected_index = style_index(current),
    tooltip = { "sh.combat-style-tooltip" },
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
  if name ~= BUTTON_NAME and name ~= SET_HOME_BUTTON and name ~= CLEAR_HOME_BUTTON then
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

  if name == BUTTON_NAME then
    ai.toggle(spidertron, player)
  elseif name == SET_HOME_BUTTON then
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
  if not element or not element.valid or element.name ~= STYLE_DROPDOWN then
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
  local idx = element.selected_index
  local style = STYLE_ORDER[idx]
  if not style then
    return
  end
  ai.set_combat_style(spidertron, style)
  -- Also update global default so new hunters match the last GUI choice.
  -- Per-spider override is authoritative for this entity via ai.combat_style.
  util.debug_log("style → " .. style, spidertron)
end

M.STYLE_ORDER = STYLE_ORDER

return M
