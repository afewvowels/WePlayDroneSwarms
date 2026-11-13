-- Numbers used by both the data stage (tooltips, research) and control.lua (the drones).
return {
  TARGET_RANGE = 1000,  -- tiles from the pad; only charted nests count
  ENGAGE_RANGE = 28,    -- beam reach from each drone, tiles
  LASER_DPS = 50 / 3,   -- per drone, before laser damage research, averaged over the pulse cycle

  -- Attack run length in seconds: base, then after each level of drone endurance research.
  ATTACK_SECONDS = { 15, 30, 60 },
  ENDURANCE_TECHS = { "wp-attack-drone-endurance-1", "wp-attack-drone-endurance-2" },

  -- Largest swarm a launchpad can be set to: base, then after each level of swarm size research.
  SWARM_SIZES = { 5, 10, 30 },
  SWARM_TECHS = { "wp-attack-drone-swarm-size-1", "wp-attack-drone-swarm-size-2" },
}
