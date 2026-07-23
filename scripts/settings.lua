--- Cached runtime-global settings. Refresh on change; never read settings.global in hot loops.
local M = {}

local DEFAULTS = {
  search_radius = 256,
  max_pursuit_distance = 512,
  scan_interval = 60,
  scan_budget = 4,
  return_home_after_combat = true,
  sticky_home_on_first_enable = false,
  post_combat_linger_ticks = 900,
  retreat_health_percent = 25,
  retreat_include_shields = true,
  reengage_after_retreat = false,
  restock_enabled = true,
  repair_enabled = true,
  max_restock_ticks = 3600,
  enemy_prioritization = "nearest",
  max_idle_time = 600,
  spiders_per_think = 8,
  enemy_cache_ttl = 18000,
  debug_mode = false,
  combat_range = 22,
  combat_style = "strafe",
  avoid_acid = true,
  combat_move_interval = 90,
  combat_pause_ticks = 45,
  scout_algorithm = "frontier",
  scout_max_distance = 1024,
  scout_max_time_ticks = 36000,
  scout_standoff_distance = 48,
  scout_chart_radius = 64,
  scout_auto_resume = true,
}

--- @return table
function M.refresh()
  local g = settings.global
  local cache = {
    search_radius = g["sh-search-radius"].value,
    max_pursuit_distance = g["sh-max-pursuit-distance"].value,
    scan_interval = g["sh-scan-interval"].value,
    scan_budget = g["sh-scan-budget"].value,
    return_home_after_combat = g["sh-return-home-after-combat"].value,
    sticky_home_on_first_enable = g["sh-sticky-home-on-first-enable"].value,
    post_combat_linger_ticks = g["sh-post-combat-linger-ticks"].value,
    retreat_health_percent = g["sh-retreat-health-percent"].value,
    retreat_include_shields = g["sh-retreat-include-shields"].value,
    reengage_after_retreat = g["sh-reengage-after-retreat"].value,
    restock_enabled = g["sh-restock-enabled"].value,
    repair_enabled = g["sh-repair-enabled"].value,
    max_restock_ticks = g["sh-max-restock-ticks"].value,
    enemy_prioritization = g["sh-enemy-prioritization"].value,
    max_idle_time = g["sh-max-idle-time"].value,
    spiders_per_think = g["sh-spiders-per-think"].value,
    enemy_cache_ttl = g["sh-enemy-cache-ttl"].value,
    debug_mode = g["sh-debug-mode"].value,
    combat_range = g["sh-combat-range"].value,
    combat_style = g["sh-combat-style"].value,
    avoid_acid = g["sh-avoid-acid"].value,
    combat_move_interval = g["sh-combat-move-interval"].value,
    combat_pause_ticks = g["sh-combat-pause-ticks"].value,
    scout_algorithm = g["sh-scout-algorithm"].value,
    scout_max_distance = g["sh-scout-max-distance"].value,
    scout_max_time_ticks = g["sh-scout-max-time-ticks"].value,
    scout_standoff_distance = g["sh-scout-standoff-distance"].value,
    scout_chart_radius = g["sh-scout-chart-radius"].value,
    scout_auto_resume = g["sh-scout-auto-resume"].value,
  }
  storage.settings_cache = cache
  return cache
end

--- @return table
function M.get()
  return storage.settings_cache or M.refresh()
end

M.DEFAULTS = DEFAULTS

return M
