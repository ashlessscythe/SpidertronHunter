--- Scout spidertron remote: spawnable cursor item (same pattern as vanilla remote).
local remote = data.raw["spidertron-remote"]["spidertron-remote"]

data:extend({
  {
    type = "spidertron-remote",
    name = "sh-scout-remote",
    icon = "__base__/graphics/icons/spidertron-remote.png",
    icon_color_indicator_mask = "__base__/graphics/icons/spidertron-remote-mask.png",
    flags = remote and remote.flags or { "not-stackable", "only-in-cursor", "spawnable", "always-show" },
    auto_recycle = false,
    subgroup = "spawnables",
    inventory_move_sound = remote and remote.inventory_move_sound or nil,
    pick_sound = remote and remote.pick_sound or nil,
    drop_sound = remote and remote.drop_sound or nil,
    stack_size = 1,
    select = {
      border_color = { 80, 180, 255 },
      mode = { "controllable" },
      cursor_box_type = "spidertron-remote-to-be-selected",
    },
    alt_select = {
      border_color = { 120, 200, 255 },
      mode = { "controllable-add" },
      cursor_box_type = "spidertron-remote-to-be-selected",
    },
    reverse_select = {
      border_color = { 246, 255, 0 },
      mode = { "controllable-remove" },
      cursor_box_type = "not-allowed",
    },
  },
  {
    type = "custom-input",
    name = "give-sh-scout-remote",
    key_sequence = "ALT + SHIFT + A",
    consuming = "game-only",
    item_to_spawn = "sh-scout-remote",
    action = "spawn-item",
  },
  {
    type = "shortcut",
    name = "give-sh-scout-remote",
    order = "e[spidertron]-s[scout-remote]",
    action = "spawn-item",
    localised_name = { "shortcut-name.give-sh-scout-remote" },
    associated_control_input = "give-sh-scout-remote",
    technology_to_unlock = "spidertron",
    unavailable_until_unlocked = true,
    item_to_spawn = "sh-scout-remote",
    icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-rts-tool-x56.png",
    icon_size = 56,
    small_icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-rts-tool-x24.png",
    small_icon_size = 24,
  },
})
