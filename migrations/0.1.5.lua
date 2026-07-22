-- v0.1.5: combat kiting + per-spider combat_style on AI records.
local persistence = require("scripts.persistence")
persistence.init_storage()

for _, ai in pairs(storage.spiders or {}) do
  if type(ai) == "table" then
    -- Leave existing overrides; nil means fall back to global setting.
    if ai.combat_style ~= nil
      and ai.combat_style ~= "hold"
      and ai.combat_style ~= "strafe"
      and ai.combat_style ~= "circle"
      and ai.combat_style ~= "flank"
    then
      ai.combat_style = nil
    end
    ai.combat_last_move_tick = nil
    ai.combat_next_move_tick = nil
    ai.orbit_angle = nil
    ai.strafe_sign = nil
    ai.flank_sign = nil
  end
end
