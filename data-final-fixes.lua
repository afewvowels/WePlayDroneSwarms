-- Laser damage research boosts attack drones (control.lua reads the force's laser
-- damage bonus). Say so on every research that raises it, whichever mod adds it.
local DRONE_ICON = "__WePlayDroneSwarms__/graphics/icons/attack-drone.png"

for _, tech in pairs(data.raw.technology) do
  local extra = {}
  for _, effect in pairs(tech.effects or {}) do
    if effect.type == "ammo-damage" and effect.ammo_category == "laser" and type(effect.modifier) == "number" then
      extra[#extra + 1] = {
        type = "nothing",
        icon = DRONE_ICON,
        icon_size = 64,
        effect_description = { "wp-attack-drones.effect-damage", tostring(math.floor(effect.modifier * 100 + 0.5)) },
      }
    end
  end
  for _, e in pairs(extra) do table.insert(tech.effects, e) end
end
