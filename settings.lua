data:extend({
  {
    type = "string-setting",
    name = "wp-attack-drone-laser-style",
    setting_type = "runtime-global",
    default_value = "pulsing",
    allowed_values = { "continuous", "pulsing" },
    order = "a",
  },
})

data:extend({
  {
    type = "bool-setting",
    name = "wp-drone-swarms-hard-mode",
    setting_type = "startup",
    default_value = false,
    order = "b",
  },
})
