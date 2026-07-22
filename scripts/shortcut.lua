--- Toolbar shortcut toggle highlighting.
local persistence = require("scripts.persistence")
local util = require("scripts.util")

local M = {}

local SHORTCUT = "sh-toggle-autonomy"

--- @param player LuaPlayer
--- @return boolean
local function selection_has_enabled(player)
  if player.spidertron_remote_selection then
    for _, e in pairs(player.spidertron_remote_selection) do
      if util.is_valid_spidertron(e) then
        local ai = persistence.get_ai_for_entity(e)
        if ai and ai.state ~= "idle" then
          return true
        end
      end
    end
  end
  if player.vehicle and util.is_valid_spidertron(player.vehicle) then
    local ai = persistence.get_ai_for_entity(player.vehicle)
    if ai and ai.state ~= "idle" then
      return true
    end
  end
  if player.opened and player.opened.object_name == "LuaEntity"
    and util.is_valid_spidertron(player.opened)
  then
    local ai = persistence.get_ai_for_entity(player.opened)
    if ai and ai.state ~= "idle" then
      return true
    end
  end
  return false
end

--- @param player LuaPlayer
function M.sync_player(player)
  if not player or not player.valid then
    return
  end
  player.set_shortcut_toggled(SHORTCUT, selection_has_enabled(player))
end

--- Sync every connected player (after enable/disable that may affect shared fleets).
function M.sync_all()
  for _, player in pairs(game.connected_players) do
    M.sync_player(player)
  end
end

M.SHORTCUT = SHORTCUT

return M
