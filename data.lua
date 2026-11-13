local util = require("util")
if not circuit_connector_definitions then require("circuit-connector-sprites") end
local SHARED = require("shared")
local pad_sprite = require("prototypes.launchpad-sprite")
-- Drone sprites: the packer writes this file next to the sheets it makes (Sheets/).
require("Sheets.drone-animations")

local MOD = "__WePlayDroneSwarms__/"
local GFX = MOD .. "graphics/entity/"
local PAD_ICON = MOD .. "graphics/icons/attack-drone-launchpad.png"
local DRONE_ICON = MOD .. "graphics/icons/attack-drone.png"

local PAD_COLLISION = { { -2.4, -2.4 }, { 2.4, 2.4 } }
local PAD_SELECTION = { { -2.5, -2.5 }, { 2.5, 2.5 } }
local DIRECTIONS = { "north", "east", "south", "west" } -- frame order in the sheets

-- Nudge the launchpad sprite (tiles, +y is down) to line it up with its 5x5
-- footprint without re-rendering: the render sat ~0.45 tiles too high.
local PAD_SHIFT_NUDGE = { 0, 0.45 }

local function layer(kind, frame, frames)
  local sheet = kind == "shadow" and pad_sprite.shadow or pad_sprite.diffuse
  return {
    filename = GFX .. (kind == "shadow" and "attack-drone-launchpad-shadow.png" or "attack-drone-launchpad.png"),
    width = sheet.width,
    height = sheet.height,
    x = frame and frame * sheet.width or nil,
    frames = frames,
    shift = { sheet.shift[1] + PAD_SHIFT_NUDGE[1], sheet.shift[2] + PAD_SHIFT_NUDGE[2] },
    scale = 0.5,
    draw_as_shadow = kind == "shadow" or nil,
  }
end

-- What players, robots and blueprints place. It rotates natively (R works in the
-- build preview, blueprints rotate), and control.lua swaps it for the matching pad.
data:extend({
  {
    type = "simple-entity-with-owner",
    name = "wp-attack-drone-launchpad-placer",
    localised_name = { "entity-name.wp-attack-drone-launchpad" },
    icon = PAD_ICON,
    hidden_in_factoriopedia = true,
    flags = { "placeable-player", "player-creation", "not-upgradable" },
    minable = { mining_time = 0.5, result = "wp-attack-drone-launchpad" },
    placeable_by = { item = "wp-attack-drone-launchpad", count = 1 },
    max_health = 800,
    collision_box = PAD_COLLISION,
    selection_box = PAD_SELECTION,
    render_layer = "object",
    picture = { sheets = { layer("diffuse", nil, 4), layer("shadow", nil, 4) } },
  },
})

-- The real launchpads: one chest per direction, holding the drones waiting to launch.
for frame, dir in pairs(DIRECTIONS) do
  data:extend({
    {
      type = "container",
      name = "wp-attack-drone-launchpad-" .. dir,
      localised_name = { "entity-name.wp-attack-drone-launchpad" },
      localised_description = { "entity-description.wp-attack-drone-launchpad" },
      icon = PAD_ICON,
      hidden_in_factoriopedia = dir ~= "north",
      flags = { "placeable-player", "player-creation" },
      minable = { mining_time = 0.5, result = "wp-attack-drone-launchpad" },
      placeable_by = { item = "wp-attack-drone-launchpad", count = 1 },
      max_health = 800,
      corpse = "big-remnants",
      dying_explosion = "big-explosion",
      collision_box = PAD_COLLISION,
      selection_box = PAD_SELECTION,
      inventory_size = 10,
      inventory_type = "with_filters_and_bar",
      picture = { layers = { layer("diffuse", frame - 1), layer("shadow", frame - 1) } },
      -- Wire connection point on the bottom-right corner of the pad.
      circuit_wire_max_distance = 9,
      circuit_connector = circuit_connector_definitions.create_vector(universal_connector_template, {
        { variation = 26, main_offset = util.by_pixel(62, 58), shadow_offset = util.by_pixel(68, 64), show_shadow = true },
      }),
    },
  })
end

-- Hidden power interface under each pad.
data:extend({
  {
    type = "electric-energy-interface",
    name = "wp-attack-drone-launchpad-power",
    localised_name = { "entity-name.wp-attack-drone-launchpad" },
    icon = PAD_ICON,
    hidden = true,
    flags = {
      "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game",
      "not-flammable", "not-repairable", "not-upgradable",
    },
    max_health = 1,
    collision_box = PAD_COLLISION, -- so poles covering any part of the pad power it
    collision_mask = { layers = {} },
    energy_source = {
      type = "electric",
      usage_priority = "secondary-input",
      buffer_capacity = "4MJ",
      input_flow_limit = "1MW",
      output_flow_limit = "0W",
    },
    energy_usage = "100kW",
    picture = util.empty_sprite(),
  },
})

-- Signals: a hidden constant combinator under each pad, joined to it by script
-- wires, puts the drone counts on whatever network the pad is wired into.
local signals = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
signals.name = "wp-attack-drone-launchpad-signals"
signals.localised_name = { "entity-name.wp-attack-drone-launchpad" }
signals.icon = PAD_ICON
signals.icons = nil
signals.hidden = true
signals.flags = {
  "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game",
  "not-flammable", "not-repairable", "not-upgradable",
}
signals.minable = nil
signals.placeable_by = nil
signals.fast_replaceable_group = nil
signals.next_upgrade = nil
signals.collision_mask = { layers = {} }
signals.selection_box = nil
signals.sprites = util.empty_sprite()
signals.activity_led_sprites = util.empty_sprite()
signals.draw_circuit_wires = false
signals.corpse = nil
signals.dying_explosion = nil
data:extend({ signals })

local function signal_icon(tint)
  return { { icon = DRONE_ICON, icon_size = 64, tint = tint } }
end
data:extend({
  { type = "item-subgroup", name = "wp-attack-drone-signals", group = "signals", order = "z[wp-attack-drones]" },
  {
    type = "virtual-signal",
    name = "wp-attack-drones-in-launchpad",
    icons = signal_icon({ 1, 1, 1 }),
    subgroup = "wp-attack-drone-signals",
    order = "a",
  },
  {
    type = "virtual-signal",
    name = "wp-attack-drones-circling",
    icons = signal_icon({ 0.6, 1, 0.6 }),
    subgroup = "wp-attack-drone-signals",
    order = "b",
  },
  {
    type = "virtual-signal",
    name = "wp-attack-drones-attacking",
    icons = signal_icon({ 1, 0.4, 0.4 }),
    subgroup = "wp-attack-drone-signals",
    order = "c",
  },
})

-- Items, recipes, research ----------------------------------------------------------

data:extend({
  {
    type = "item",
    name = "wp-attack-drone-launchpad",
    icon = PAD_ICON,
    subgroup = "turret",
    order = "z[wp-attack-drones]-a[launchpad]",
    place_result = "wp-attack-drone-launchpad-placer",
    stack_size = 10,
  },
  {
    type = "recipe",
    name = "wp-attack-drone-launchpad",
    enabled = false,
    energy_required = 15,
    ingredients = {
      { type = "item", name = "steel-plate", amount = 50 },
      { type = "item", name = "concrete", amount = 50 },
      { type = "item", name = "electric-engine-unit", amount = 10 },
      { type = "item", name = "advanced-circuit", amount = 20 },
      { type = "item", name = "radar", amount = 1 },
    },
    results = { { type = "item", name = "wp-attack-drone-launchpad", amount = 1 } },
  },
  {
    type = "item",
    name = "wp-attack-drone",
    icon = DRONE_ICON,
    custom_tooltip_fields = {
      {
        name = { "wp-attack-drones.tooltip-damage" },
        value = { "wp-attack-drones.tooltip-damage-value", string.format("%.1f", SHARED.LASER_DPS) },
        order = 1,
      },
      {
        name = { "wp-attack-drones.tooltip-range" },
        value = { "wp-attack-drones.tooltip-tiles", tostring(SHARED.ENGAGE_RANGE) },
        order = 2,
      },
      {
        name = { "wp-attack-drones.tooltip-attack-time" },
        value = { "wp-attack-drones.tooltip-attack-time-value", tostring(SHARED.ATTACK_SECONDS[1]),
                  tostring(SHARED.ATTACK_SECONDS[#SHARED.ATTACK_SECONDS]) },
        order = 3,
      },
      {
        name = { "wp-attack-drones.tooltip-target-range" },
        value = { "wp-attack-drones.tooltip-tiles", tostring(SHARED.TARGET_RANGE) },
        order = 4,
      },
    },
    subgroup = "turret",
    order = "z[wp-attack-drones]-b[drone]",
    stack_size = 10,
  },
  {
    type = "recipe",
    name = "wp-attack-drone",
    enabled = false,
    energy_required = 10,
    ingredients = {
      { type = "item", name = "flying-robot-frame", amount = 1 },
      { type = "item", name = "battery", amount = 4 },
      { type = "item", name = "steel-plate", amount = 5 },
      { type = "item", name = "advanced-circuit", amount = 3 },
    },
    results = { { type = "item", name = "wp-attack-drone", amount = 1 } },
  },
  {
    type = "technology",
    name = "wp-attack-drones",
    icon = MOD .. "graphics/technology/attack-drones.png",
    icon_size = 256,
    prerequisites = { "robotics", "laser-turret", "chemical-science-pack" },
    effects = {
      { type = "unlock-recipe", recipe = "wp-attack-drone-launchpad" },
      { type = "unlock-recipe", recipe = "wp-attack-drone" },
    },
    unit = {
      count = 250,
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
        { "military-science-pack", 1 },
        { "chemical-science-pack", 1 },
      },
      time = 30,
    },
  },

  -- Rotate placed launchpads with the normal rotate keys.
  { type = "custom-input", name = "wp-attack-drone-rotate", key_sequence = "", linked_game_control = "rotate" },
  { type = "custom-input", name = "wp-attack-drone-reverse-rotate", key_sequence = "", linked_game_control = "reverse-rotate" },

  -- Sounds (the same clips as Long Haul Logistics for now).
  {
    type = "sound",
    name = "wp-attack-drone-launch",
    filename = MOD .. "sound/wp-attack-drone-launch.ogg",
    volume = 0.7,
    audible_distance_modifier = 0.8,
  },
  {
    type = "sound",
    name = "wp-attack-drone-flying",
    filename = MOD .. "sound/wp-attack-drone-flying.ogg",
    volume = 0.35,
    audible_distance_modifier = 0.6,
  },
})

-- Laser beam: a soft green line, stretched and rotated by control.lua. Drawn as a
-- sprite (not a line) so it can sit on a render layer below the drones.
data:extend({
  {
    type = "sprite",
    name = "wp-attack-drone-laser-beam",
    filename = GFX .. "laser-beam.png",
    width = 64,
    height = 16,
    blend_mode = "additive",
    draw_as_glow = true,
    flags = { "no-crop" },
  },
  {
    -- The "pearls" that travel down each beam.
    type = "sprite",
    name = "wp-attack-drone-laser-bead",
    filename = GFX .. "laser-bead.png",
    width = 32,
    height = 32,
    blend_mode = "additive",
    draw_as_glow = true,
    flags = { "no-crop" },
  },
})

-- Research: drone endurance (longer attack runs) and swarm size ----------------------

local TECH = MOD .. "graphics/technology/"

-- The drone with a battery in the bottom-right corner (vanilla's battery icon).
local endurance_icons = {
  { icon = TECH .. "drone-endurance.png", icon_size = 256 },
  { icon = "__base__/graphics/icons/battery.png", icon_size = 64, scale = 0.75, shift = { 40, 40 } },
}
local swarm_icons = { { icon = TECH .. "drone-swarm.png", icon_size = 256 } }

local function packs(names)
  local list = {}
  for _, name in pairs(names) do list[#list + 1] = { name, 1 } end
  return list
end
local MID = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack" }
local HIGH = { "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
               "utility-science-pack" }

local function effect(key, value)
  return { type = "nothing", icon = DRONE_ICON, icon_size = 64, effect_description = { key, tostring(value) } }
end

data:extend({
  {
    type = "technology",
    name = SHARED.ENDURANCE_TECHS[1],
    localised_name = { "technology-name.wp-attack-drone-endurance" },
    localised_description = { "technology-description.wp-attack-drone-endurance" },
    icons = endurance_icons,
    prerequisites = { "wp-attack-drones" },
    effects = { effect("wp-attack-drones.effect-attack-time", SHARED.ATTACK_SECONDS[2]) },
    unit = { count = 300, ingredients = packs(MID), time = 30 },
    upgrade = true,
  },
  {
    type = "technology",
    name = SHARED.ENDURANCE_TECHS[2],
    localised_name = { "technology-name.wp-attack-drone-endurance" },
    localised_description = { "technology-description.wp-attack-drone-endurance" },
    icons = endurance_icons,
    prerequisites = { SHARED.ENDURANCE_TECHS[1], "utility-science-pack" },
    effects = { effect("wp-attack-drones.effect-attack-time", SHARED.ATTACK_SECONDS[3]) },
    unit = { count = 500, ingredients = packs(HIGH), time = 45 },
    upgrade = true,
  },
  {
    type = "technology",
    name = SHARED.SWARM_TECHS[1],
    localised_name = { "technology-name.wp-attack-drone-swarm-size" },
    localised_description = { "technology-description.wp-attack-drone-swarm-size" },
    icons = swarm_icons,
    prerequisites = { "wp-attack-drones" },
    effects = { effect("wp-attack-drones.effect-swarm-size", SHARED.SWARM_SIZES[2]) },
    unit = { count = 300, ingredients = packs(MID), time = 30 },
    upgrade = true,
  },
  {
    type = "technology",
    name = SHARED.SWARM_TECHS[2],
    localised_name = { "technology-name.wp-attack-drone-swarm-size" },
    localised_description = { "technology-description.wp-attack-drone-swarm-size" },
    icons = swarm_icons,
    prerequisites = { SHARED.SWARM_TECHS[1], "utility-science-pack" },
    effects = { effect("wp-attack-drones.effect-swarm-size", SHARED.SWARM_SIZES[3]) },
    unit = { count = 500, ingredients = packs(HIGH), time = 45 },
    upgrade = true,
  },
})

-- Laser sound: borrow the laser turret's, if we can find its files.
local turret = data.raw["electric-turret"] and data.raw["electric-turret"]["laser-turret"]
local sound = turret and turret.attack_parameters and turret.attack_parameters.sound
local variations = {}
if type(sound) == "table" then
  if sound.filename then
    variations[1] = { filename = sound.filename, volume = sound.volume }
  else
    for _, s in pairs(sound.variations or sound) do
      if type(s) == "table" and s.filename then variations[#variations + 1] = { filename = s.filename, volume = s.volume } end
    end
  end
end
if #variations > 0 then
  data:extend({
    {
      type = "sound",
      name = "wp-attack-drone-laser",
      variations = variations,
      audible_distance_modifier = 0.7,
    },
  })
end

-- Hard mode (startup setting): every drone carries a real laser turret.
if settings.startup["wp-drone-swarms-hard-mode"].value then
  local recipe = data.raw.recipe["wp-attack-drone"]
  table.insert(recipe.ingredients, { type = "item", name = "laser-turret", amount = 1 })
end
