--- Public remote interface for other mods.
local ai = require("scripts.ai")
local persistence = require("scripts.persistence")
local util = require("scripts.util")

remote.add_interface("SpidertronHunter", {
  --- @param spidertron LuaEntity
  enable = function(spidertron)
    return ai.enable(spidertron, nil)
  end,

  --- @param spidertron LuaEntity
  disable = function(spidertron)
    ai.disable(spidertron, nil)
  end,

  --- @param spidertron LuaEntity
  --- @return boolean
  is_enabled = function(spidertron)
    return ai.is_enabled(spidertron)
  end,

  --- @param spidertron LuaEntity
  --- @return table?
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
    }
  end,

  --- @param spidertron LuaEntity
  --- @param position MapPosition
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
})
