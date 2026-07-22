--- Public remote interfaces for other mods / console debugging.
local ai = require("scripts.ai")
local persistence = require("scripts.persistence")
local targeting = require("scripts.targeting")
local util = require("scripts.util")

local function print_debug(player_index)
  local dump = ai.debug_dump()
  local lines = {
    string.format(
      "SpidertronHunter: %d spiders, cache entries=%d claims=%d",
      #dump.spiders,
      dump.cache.entries,
      dump.cache.claims
    ),
  }
  for i = 1, #dump.spiders do
    local s = dump.spiders[i]
    lines[#lines + 1] = string.format(
      "  #%s state=%s valid=%s target=%s wait=%s",
      tostring(s.unit_number),
      tostring(s.state),
      tostring(s.valid),
      tostring(s.target),
      tostring(s.wait_reason)
    )
  end
  local text = table.concat(lines, "\n")
  log("[SpidertronHunter]\n" .. text)
  if player_index then
    local player = game.get_player(player_index)
    if player then
      player.print(text)
    end
  else
    game.print(text)
  end
  return dump
end

local methods = {
  enable = function(spidertron)
    return ai.enable(spidertron, nil)
  end,

  disable = function(spidertron)
    ai.disable(spidertron, nil)
  end,

  is_enabled = function(spidertron)
    return ai.is_enabled(spidertron)
  end,

  get_ai_data = function(spidertron)
    local data = persistence.get_ai_for_entity(spidertron)
    if not data then
      return nil
    end
    return {
      state = data.state,
      home = data.home,
      unit_number = data.unit_number,
      claim_id = data.claim_id,
      wait_reason = data.wait_reason,
    }
  end,

  set_home = function(spidertron, position)
    if not util.is_valid_spidertron(spidertron) then
      return false
    end
    local data = persistence.get_ai_for_entity(spidertron)
    if not data then
      data = persistence.create_ai(spidertron)
    end
    data.home = {
      surface_index = spidertron.surface_index,
      x = position.x,
      y = position.y,
    }
    return true
  end,

  debug = function(player_index)
    return print_debug(player_index)
  end,

  reset = function()
    targeting.reset()
    for _, data in pairs(storage.spiders) do
      data.claim_id = nil
      data.target_entity = nil
      data.target_pos = nil
      data.pending_goal = nil
      data.path_start_tick = nil
      data.player_goal = nil
      data.wait_reason = nil
    end
    storage.path_requests = {}
    storage.path_statuses = {}
    log("[SpidertronHunter] reset cache and path state")
    return true
  end,

  scan = function(spidertron)
    return ai.force_scan(spidertron)
  end,
}

remote.add_interface("SpidertronHunter", methods)
-- Alias requested for console / scripting convenience.
remote.add_interface("spidertron_hunter", methods)
