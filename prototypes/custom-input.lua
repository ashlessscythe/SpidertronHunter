data:extend({
  {
    type = "custom-input",
    name = "sh-toggle-autonomy",
    key_sequence = "CONTROL + SHIFT + H",
    consuming = "game-only",
    action = "lua",
  },
  {
    type = "shortcut",
    name = "sh-toggle-autonomy",
    order = "e[spidertron]-h[hunter]",
    action = "lua",
    localised_name = { "shortcut-name.sh-toggle-autonomy" },
    associated_control_input = "sh-toggle-autonomy",
    technology_to_unlock = "spidertron",
    unavailable_until_unlocked = true,
    icon = "__SpidertronHunter__/graphics/shortcut/hunter-x56.png",
    icon_size = 56,
    small_icon = "__SpidertronHunter__/graphics/shortcut/hunter-x24.png",
    small_icon_size = 24,
  },
})
