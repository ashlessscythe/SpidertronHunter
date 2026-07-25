--- Fleet manager: portrait group cards on the current surface.
local ai = require("scripts.ai")
local util = require("scripts.util")

local M = {}

local FRAME_NAME = "sh-manager-gui"
local CLOSE_BUTTON = "sh-manager-close"
local PIN_BUTTON = "sh-manager-pin"
local BTN_FOLLOW = "sh-mgr-follow"
local BTN_REMOTE = "sh-mgr-remote"
local BTN_HOME = "sh-mgr-home"
local BTN_VIEW = "sh-mgr-view"
local BTN_SETTINGS = "sh-mgr-settings"
local BTN_AI = "sh-mgr-ai"

local SMALL_BTN = 28

--- @param spidertron LuaEntity
--- @return string
local function group_display_name(spidertron)
  if spidertron.entity_label and spidertron.entity_label ~= "" then
    return spidertron.entity_label
  end
  return spidertron.name
end

--- @param player LuaPlayer
--- @return table<string, LuaEntity[]>
local function find_groups(player)
  local groups = {}
  local found = player.surface.find_entities_filtered({
    type = "spider-vehicle",
    force = player.force,
    to_be_deconstructed = false,
  })
  table.sort(found, function(a, b)
    return group_display_name(a) < group_display_name(b)
  end)
  for i = 1, #found do
    local spidertron = found[i]
    if spidertron.valid then
      local name = group_display_name(spidertron)
      local list = groups[name]
      if not list then
        list = {}
        groups[name] = list
      end
      list[#list + 1] = spidertron
    end
  end
  return groups
end

--- @param groups table<string, LuaEntity[]>
--- @return string[]
local function sorted_group_names(groups)
  local names = {}
  for name in pairs(groups) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- @param player_index integer
--- @return boolean
local function is_pinned(player_index)
  storage.manager_pinned = storage.manager_pinned or {}
  return storage.manager_pinned[player_index] == true
end

--- @param player_index integer
--- @param pinned boolean
local function set_pinned(player_index, pinned)
  storage.manager_pinned = storage.manager_pinned or {}
  storage.manager_pinned[player_index] = pinned or nil
end

--- @param members LuaEntity[]
--- @return boolean any_eligible, boolean all_enabled
local function group_ai_status(members)
  local any = false
  for i = 1, #members do
    local spidertron = members[i]
    if util.is_valid_spidertron(spidertron) then
      any = true
      if not ai.is_enabled(spidertron) then
        return true, false
      end
    end
  end
  return any, any
end

--- @param parent LuaGuiElement
--- @param action string
--- @param tooltip LocalisedString
--- @param sprite string
--- @param group_name string
--- @param opts {size: integer?, toggled: boolean?}?
local function add_action_button(parent, action, tooltip, sprite, group_name, opts)
  opts = opts or {}
  local btn = parent.add({
    type = "sprite-button",
    name = action .. "/" .. group_name,
    style = "slot_button",
    tooltip = tooltip,
    sprite = sprite,
    toggled = opts.toggled or false,
    tags = { sh_mgr = action, sh_group = group_name },
  })
  local size = opts.size or SMALL_BTN
  btn.style.size = size
  btn.style.padding = 0
  return btn
end

--- @param player LuaPlayer
local function remember_location(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid and frame.location then
    storage.manager_window_position = frame.location
  end
end

--- @param player LuaPlayer
local function destroy_gui(player)
  remember_location(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid then
    frame.destroy()
  end
end

--- @param gui LuaGuiElement
--- @param player LuaPlayer
local function add_titlebar(gui, player)
  local titlebar = gui.add({ type = "flow", name = "sh-manager-titlebar" })
  titlebar.drag_target = gui
  titlebar.add({
    type = "label",
    style = "frame_title",
    caption = { "sh.manager-title" },
    ignored_by_interaction = true,
  })
  local filler = titlebar.add({
    type = "empty-widget",
    style = "draggable_space",
    ignored_by_interaction = true,
  })
  filler.style.height = 24
  filler.style.horizontally_stretchable = true

  local pinned = is_pinned(player.index)
  titlebar.add({
    type = "sprite-button",
    name = PIN_BUTTON,
    style = "frame_action_button",
    sprite = "utility/pin_center",
    tooltip = { "sh.manager-pin-tooltip" },
    toggled = pinned,
  })
  titlebar.add({
    type = "sprite-button",
    name = CLOSE_BUTTON,
    style = "frame_action_button",
    sprite = "utility/close",
    tooltip = { "gui.close-instruction" },
  })
end

--- @param list LuaGuiElement
--- @param player LuaPlayer
--- @param group_name string
--- @param members LuaEntity[]
local function add_group_card(list, player, group_name, members)
  local card = list.add({
    type = "frame",
    name = "sh-mgr-card/" .. group_name,
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  card.style.horizontally_stretchable = true
  card.style.padding = 6
  card.style.top_margin = 2
  card.style.bottom_margin = 2

  local header = card.add({ type = "flow", direction = "horizontal", name = "header" })
  header.style.vertical_align = "center"
  header.style.horizontally_stretchable = true

  local leader = members[1]
  local swatch = header.add({ type = "label", caption = "●" })
  if leader and leader.color then
    swatch.style.font_color = leader.color
  end

  local title = header.add({
    type = "label",
    caption = group_name .. "  ×" .. tostring(#members),
    style = "caption_label",
  })
  title.style.horizontally_stretchable = true

  local can_follow = player.character
    and player.character.valid
    and player.character.surface_index == player.surface_index
  if can_follow then
    add_action_button(
      header,
      BTN_FOLLOW,
      { "sh.manager-follow-tooltip" },
      "utility/player_force_icon",
      group_name,
      { size = 36 }
    )
  end

  local actions = card.add({ type = "flow", direction = "horizontal", name = "actions" })
  actions.style.horizontal_spacing = 2
  actions.style.top_margin = 4

  add_action_button(actions, BTN_REMOTE, { "sh.manager-remote-tooltip" }, "item/spidertron-remote", group_name)
  add_action_button(actions, BTN_HOME, { "sh.manager-home-tooltip" }, "utility/shoot_cursor_green", group_name)
  add_action_button(actions, BTN_VIEW, { "sh.manager-view-tooltip" }, "utility/search_icon", group_name)
  add_action_button(actions, BTN_SETTINGS, { "sh.manager-settings-tooltip" }, "utility/equipment_grid", group_name)

  local any_eligible, all_on = group_ai_status(members)
  if any_eligible then
    add_action_button(
      actions,
      BTN_AI,
      { "sh.manager-ai-tooltip" },
      all_on and "utility/check_mark_green" or "utility/stop",
      group_name,
      { toggled = all_on }
    )
  end
end

--- @param player LuaPlayer
--- @param rebuild boolean?
function M.open(player, rebuild)
  if not player or not player.valid then
    return
  end
  if not rebuild then
    destroy_gui(player)
  else
    remember_location(player)
    local existing = player.gui.screen[FRAME_NAME]
    if existing and existing.valid then
      existing.destroy()
    end
  end

  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
  })
  frame.style.minimal_width = 220
  frame.style.maximal_width = 280
  if storage.manager_window_position then
    frame.location = storage.manager_window_position
  else
    frame.auto_center = true
  end
  add_titlebar(frame, player)

  local groups = find_groups(player)
  local names = sorted_group_names(groups)
  if #names == 0 then
    frame.add({
      type = "label",
      caption = { "sh.manager-empty" },
    })
  else
    local scroll = frame.add({
      type = "scroll-pane",
      name = "sh-manager-scroll",
      direction = "vertical",
      horizontal_scroll_policy = "never",
      vertical_scroll_policy = "auto",
    })
    scroll.style.maximal_height = 420
    scroll.style.horizontally_stretchable = true

    local list = scroll.add({
      type = "flow",
      name = "sh-manager-list",
      direction = "vertical",
    })
    list.style.horizontally_stretchable = true
    list.style.vertical_spacing = 0

    for i = 1, #names do
      add_group_card(list, player, names[i], groups[names[i]])
    end
  end

  -- Pinned windows stay up when opening entity GUIs / Esc elsewhere.
  if not is_pinned(player.index) then
    player.opened = frame
  elseif player.opened and player.opened.object_name == "LuaGuiElement" and player.opened.name == FRAME_NAME then
    player.opened = nil
  end
end

--- @param player LuaPlayer
function M.close(player)
  if not player or not player.valid then
    return
  end
  destroy_gui(player)
end

--- @param player LuaPlayer
function M.toggle(player)
  if not player or not player.valid then
    return
  end
  if player.gui.screen[FRAME_NAME] then
    M.close(player)
  else
    M.open(player)
  end
end

--- @param player LuaPlayer
--- @param group_name string
--- @return LuaEntity[]?
local function group_members(player, group_name)
  return find_groups(player)[group_name]
end

--- @param spidertron LuaEntity
--- @param player LuaPlayer
local function vanilla_follow(spidertron, player)
  if not spidertron or not spidertron.valid then
    return
  end
  if not player.character or not player.character.valid then
    return
  end
  if spidertron.surface_index ~= player.character.surface_index then
    return
  end
  spidertron.autopilot_destination = nil
  spidertron.follow_target = player.character
end

--- Enable Off spiders as Hunter; if all already on, disable all.
--- @param members LuaEntity[]
--- @param player LuaPlayer
local function toggle_group_ai(members, player)
  local eligible = {}
  local any_off = false
  for i = 1, #members do
    local spidertron = members[i]
    if util.is_valid_spidertron(spidertron) then
      eligible[#eligible + 1] = spidertron
      if not ai.is_enabled(spidertron) then
        any_off = true
      end
    end
  end
  if #eligible == 0 then
    return
  end
  if any_off then
    for i = 1, #eligible do
      if not ai.is_enabled(eligible[i]) then
        ai.enable(eligible[i], player)
      end
    end
  else
    for i = 1, #eligible do
      ai.disable(eligible[i], player)
    end
  end
end

--- @param event EventData.on_gui_click
function M.on_gui_click(event)
  local element = event.element
  if not element or not element.valid then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if element.name == CLOSE_BUTTON then
    M.close(player)
    return
  end

  if element.name == PIN_BUTTON then
    local pinned = not is_pinned(player.index)
    set_pinned(player.index, pinned)
    M.open(player, true)
    return
  end

  local action = element.tags and element.tags.sh_mgr
  if type(action) ~= "string" then
    return
  end
  if action ~= BTN_FOLLOW
    and action ~= BTN_REMOTE
    and action ~= BTN_HOME
    and action ~= BTN_VIEW
    and action ~= BTN_SETTINGS
    and action ~= BTN_AI
  then
    return
  end

  local group_name = element.tags.sh_group
  if type(group_name) ~= "string" then
    return
  end
  local members = group_members(player, group_name)
  if not members or #members == 0 then
    return
  end

  if action == BTN_FOLLOW then
    for i = 1, #members do
      local spidertron = members[i]
      if not ai.follow_player(spidertron, player) then
        vanilla_follow(spidertron, player)
      end
    end
    return
  end

  if action == BTN_REMOTE then
    if not player.is_cursor_empty() then
      return
    end
    local cursor = player.cursor_stack
    if not cursor then
      return
    end
    cursor.set_stack({ name = "spidertron-remote" })
    player.spidertron_remote_selection = members
    return
  end

  if action == BTN_HOME then
    -- Click = go home; Ctrl-click = set each spider's home to its current position.
    if event.control then
      for i = 1, #members do
        ai.set_home(members[i])
      end
      util.flying_text(player, { "sh.home-set" }, player.position)
    else
      for i = 1, #members do
        ai.return_home(members[i])
      end
    end
    return
  end

  if action == BTN_VIEW then
    local spidertron = members[1]
    if spidertron and spidertron.valid then
      player.set_controller({
        type = defines.controllers.remote,
        position = spidertron.position,
      })
    end
    return
  end

  if action == BTN_SETTINGS then
    local spidertron = members[1]
    if spidertron and spidertron.valid then
      player.set_controller({
        type = defines.controllers.remote,
        position = spidertron.position,
      })
      player.opened = spidertron
      -- Unpinned manager closes when opened changes; pinned stays up.
    end
    return
  end

  if action == BTN_AI then
    toggle_group_ai(members, player)
    M.open(player, true)
  end
end

--- @param event EventData.on_gui_closed
function M.on_gui_closed(event)
  if not event.element or not event.element.valid then
    return
  end
  if event.element.name ~= FRAME_NAME then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  -- Pinned: ignore Esc / opened replacement; only Close / shortcut dismiss it.
  if is_pinned(player.index) then
    return
  end
  if event.element.location then
    storage.manager_window_position = event.element.location
  end
  event.element.destroy()
end

M.FRAME_NAME = FRAME_NAME

return M
