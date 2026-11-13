local Flight = require("__WePlayFlightLib__/flight")
local SHARED = require("shared")

local PLACER = "wp-attack-drone-launchpad-placer"
local DRONE = "wp-attack-drone"
local POWER = "wp-attack-drone-launchpad-power"
local SIGNALS = "wp-attack-drone-launchpad-signals"
local CIRCUIT_IDS = { defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }
local GUI = "wp_attack_drone_panel"

local D = defines.direction
local PAD_BY_DIR = {
  [D.north] = "wp-attack-drone-launchpad-north",
  [D.east] = "wp-attack-drone-launchpad-east",
  [D.south] = "wp-attack-drone-launchpad-south",
  [D.west] = "wp-attack-drone-launchpad-west",
}
local DIR_BY_PAD, PAD_NAMES = {}, {}
for dir, name in pairs(PAD_BY_DIR) do
  DIR_BY_PAD[name] = dir
  PAD_NAMES[#PAD_NAMES + 1] = name
end

-- Squad size
local DEFAULT_THRESHOLD = 5
local MAX_THRESHOLD = SHARED.SWARM_SIZES[#SHARED.SWARM_SIZES] -- with all the research

-- Launching
local LAUNCH_INTERVAL = 120          -- ticks between launches from one pad
local LAUNCH_ENERGY = 2000000        -- 2 MJ per launch (the pad's buffer holds 4 MJ)
local POWER_IDLE = 100000 / 60       -- 100 kW

-- Loitering over the pad: each drone on its own ring, like over a nest.
local LOITER_RINGS = { 14, 19, 24, 29 }

-- Swarm behaviour. Everything wobbles a little, slowly and out of step, so the
-- squad churns like a swarm instead of flying neat circles.
local RING_BREATHE = { 2.5, 5 }      -- ring radius drifts in and out by this many tiles...
local RING_PERIOD = { 180, 420 }     -- ...over this many ticks
local SPEED_WOBBLE = 0.15            -- +/- 15% speed, over 2 to 5 s
local ALTITUDE_WOBBLE = 1            -- +/- tiles around cruise altitude
-- In transit the squad flies as a loose cloud behind the leader, not a neat V.
local CLOUD_BEHIND = { 2, 14 }       -- tiles behind the leader
local CLOUD_SIDE = 9                 -- tiles either side
local CLOUD_DRIFT = 0.5              -- each drone wanders around its spot by this much
-- Swarming up: the drones meet at a rally point part of the way to the target,
-- each flying to its own spot in the cloud there, timed to arrive with the leader.
local RALLY_AT = 0.3                 -- fraction of the way to the target...
local RALLY_MIN, RALLY_MAX = 40, 200 -- ...but at least / at most this many tiles out
local RALLY_SPEED = { 0.8, 1.3 }     -- speed limits while timing the meet-up (x own speed)
-- Late anyway? Catch up with the cloud: just fast enough to make it by the time
-- the leader reaches the target, kept between these limits (x own speed). It's
-- fine for a straggler to slot in right as the attack starts.
local CATCH_UP_MIN, CATCH_UP_MAX = 1.15, 1.4

-- Finding targets
local TARGET_RANGE = SHARED.TARGET_RANGE -- tiles from the pad; only charted nests count
local TARGET_RETRY = 300             -- ticks between searches when nothing is in range
-- Map reveal: like artillery, the swarm charts the map around itself on the way
-- out and over the target, so you see where it went and what it hit.
local REVEAL_RADIUS = 48             -- tiles around the leader (in flight) or the target (attacking)
local REVEAL_INTERVAL = 60           -- ticks between reveals
local CLUSTER_RADIUS = 32            -- nests this close to another squad's target are left to that squad

-- Attack run: like crows over a carcass. Each drone circles the nest on its own
-- ring, some clockwise and some counter-clockwise, at slightly different speeds.
local RING_RADII = { 8, 13, 18, 23 } -- drone i gets ring ((i - 1) % #RING_RADII) + 1 (attack)
local RING_JITTER = 1.5              -- +/- tiles, so drones on the same ring don't stack
local SPEED_JITTER = 0.12            -- +/- 12% cruise speed per drone
local ATTACK_TURN_RADIUS = 9         -- tighter turns than in transit (20), so they wheel like crows
local BREAK_STAGGER = { 5, 50 }      -- ticks: wingmen peel off one by one, not all at once
local ENTRY_SPREAD = 0.6             -- each drone picks its own line in: any entry up to 60% longer than the best
local CRASH_EASE = 0.035             -- how fast crashing drones lose altitude

-- Lasers: beams that stay locked on a target. Pulsing (the default "Laser style")
-- is 3 s on, 1 s off; continuous never stops. Damage per second is the same either way.
local ENGAGE_RANGE = SHARED.ENGAGE_RANGE -- beam reach from each drone, tiles
local LASER_DPS = SHARED.LASER_DPS       -- per drone, averaged over the pulse cycle (before research)
local DAMAGE_INTERVAL = 10           -- ticks between damage ticks while the beam is on
local PULSE_ON, PULSE_OFF = 180, 60  -- ticks, pulsing style
local RETARGET_INTERVAL = 15         -- ticks between target searches for a drone without a target
local LASER_COLOR = { 0.3, 1, 0.45 }
local BEAM_SPRITE = "wp-attack-drone-laser-beam"
local BEAM_LAYER = "higher-object-above" -- above nests and biters, below the drones ("air-object")
local BEAM_THICKNESS = 0.5           -- y_scale of the 16 px beam texture (0.25 tiles)
-- Pulse-laser "pearls": bright beads that run down the beam from drone to target,
-- like a snake that's swallowed a string of eggs. They keep going to the target
-- after a pulse ends, so the last ones land after the beam is gone.
local BEADS = false                  -- off since 0.6.4: they didn't read in the chaos. true to bring them back.
local BEAD_SPRITE = "wp-attack-drone-laser-bead"
local BEAD_SPEED = 0.9               -- tiles per tick
local BEAD_SPACING = 17.5            -- average tiles between beads...
local BEAD_SPREAD = 0.7              -- ...each gap randomly 30% to 170% of that
local BEAD_POOL = 6                  -- most beads on one beam at once
-- End of a pulse: the beam lets go of the drone and its tail runs down to the
-- target, swallowing any beads it catches up with.
local RETRACT = false                -- off since 0.6.7: beams just switch off. true to bring it back.
local RETRACT_SPEED = 1.2            -- tiles per tick
local BEAD_LENGTH = 0.6              -- tiles long (stretched along the beam)...
local BEAD_WIDTH = 0.38              -- ...and wide, so it bulges past the beam's 0.25

local PRIMARY_TARGETS = { "unit-spawner", "turret" }   -- nests and worms first
local PRIMARY_LOOKUP = { ["unit-spawner"] = true, ["turret"] = true }
local PRIMARY_REACH = 36             -- tiles: drones reach a bit further for nests and worms than for biters
local SECONDARY_TARGETS = { "unit", "spider-unit" }    -- then whatever is defending them

local DRONE_LOOKS = {
  sprites = { body = "wp-attack-drone-hull", shadow = "wp-attack-drone-shadow", glow = "wp-attack-drone-glow" },
  glow_tint = LASER_COLOR,
  banks = 5,
  split_banks = true, -- one animation per bank (wp-attack-drone-hull-0 ... -4); 320 frames is over Factorio's 255 limit
  bank_flip = false,  -- set true if the drones lean the wrong way in turns
  map = { sprite = "item/" .. DRONE, tint = { 1, 0.25, 0.25 }, scale = 2 },
}

--[[ storage
  pads[id] = { id, entity, direction, threshold, power, squad (loitering squad id), next_launch, target_info }
  by_unit[unit_number] = pad id
  squads[id] = {
    id, pad_id, surface, force,
    state = "loiter" | "transit" | "attack" | "crash",
    leader,            -- the lead drone's flight
    drones = {},       -- every flight in the squad, leader first
    center,            -- where it's circling
    ends,              -- tick the attack run ends
    claimed,           -- unit_number of the nest it's after
  }
  claimed[unit_number] = squad id
  open[player_index] = pad id
]]

local function ensure_storage()
  storage.pads = storage.pads or {}
  storage.by_unit = storage.by_unit or {}
  storage.squads = storage.squads or {}
  storage.claimed = storage.claimed or {}
  storage.open = storage.open or {}
  storage.next_id = storage.next_id or 1
end

local function new_id()
  local id = storage.next_id
  storage.next_id = id + 1
  return id
end

local function get_pad(entity)
  local id = entity and entity.valid and storage.by_unit[entity.unit_number]
  return id and storage.pads[id]
end

-- How long an attack run lasts. Endurance research goes here later, e.g.
--   + 15 s for each level of "wp-attack-drone-endurance".
-- Laser damage research (vanilla's, or any mod's) boosts the drones like any laser.
local function laser_bonus(force)
  return force.get_ammo_damage_modifier("laser")
end

local function laser_dps(force)
  return LASER_DPS * (1 + laser_bonus(force))
end

-- How far the research has got: 0 = none, 1, 2, ...
local function tech_level(force, names)
  local level = 0
  for i, name in ipairs(names) do
    local tech = force.technologies[name]
    if tech and tech.researched then level = i end
  end
  return level
end

-- Attack run length: 15 s, 30 s with Drone endurance 1, 60 s with Drone endurance 2.
local function attack_ticks(force)
  return SHARED.ATTACK_SECONDS[tech_level(force, SHARED.ENDURANCE_TECHS) + 1] * 60
end

-- Largest swarm a launchpad can send: 5, 10 with Swarm size 1, 30 with Swarm size 2.
local function swarm_cap(force)
  return SHARED.SWARM_SIZES[tech_level(force, SHARED.SWARM_TECHS) + 1]
end

-- The squad size a pad actually uses: its setting, within what's been researched.
local function squad_size(pad)
  return math.min(pad.threshold, swarm_cap(pad.entity.force))
end

-- Launchpads -----------------------------------------------------------------------

local function ensure_power(pad)
  if pad.power and pad.power.valid then return end
  local e = pad.entity
  pad.power = e.surface.create_entity({ name = POWER, position = e.position, force = e.force })
  if pad.power then
    pad.power.destructible = false
    pad.power.power_usage = POWER_IDLE
  end
end

-- Hidden signal combinator under the pad, joined to it by invisible script wires,
-- so the drone signals reach whatever the pad is wired to.
local function ensure_signals(pad)
  local e = pad.entity
  if not (pad.signals and pad.signals.valid) then
    pad.signals = e.surface.create_entity({ name = SIGNALS, position = e.position, force = e.force })
    if pad.signals then pad.signals.destructible = false end
    pad.signal_cache = nil
  end
  if not pad.signals then return end
  for _, id in pairs(CIRCUIT_IDS) do
    local a = e.get_wire_connector(id, true)
    local b = pad.signals.get_wire_connector(id, true)
    if a and b and not a.is_connected_to(b, defines.wire_origin.script) then
      a.connect_to(b, false, defines.wire_origin.script)
    end
  end
end

local function bind(pad, entity)
  pad.entity = entity
  pad.direction = DIR_BY_PAD[entity.name]
  storage.by_unit[entity.unit_number] = pad.id
  script.register_on_object_destroyed(entity)
end

local function register_pad(entity, tags)
  local pad = { id = new_id(), threshold = DEFAULT_THRESHOLD, next_launch = 0 }
  if tags and type(tags.wp_threshold) == "number" then
    pad.threshold = math.max(1, math.min(MAX_THRESHOLD, math.floor(tags.wp_threshold)))
  end
  storage.pads[pad.id] = pad
  bind(pad, entity)
  ensure_power(pad)
  ensure_signals(pad)
  return pad
end

local function rescan()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = PAD_NAMES })) do
      if not get_pad(entity) then register_pad(entity) end
    end
  end
end

script.on_init(ensure_storage)
script.on_configuration_changed(function()
  ensure_storage()
  for id, pad in pairs(storage.pads) do
    if not (pad.entity and pad.entity.valid) then storage.pads[id] = nil end
  end
  rescan()
  for _, pad in pairs(storage.pads) do
    ensure_power(pad)
    ensure_signals(pad)
  end
  -- Drones already in the air from older versions: give them the newer fields.
  for _, squad in pairs(storage.squads) do
    for _, f in pairs(squad.drones) do
      f.wp_phase = f.wp_phase or math.random(0, 48)
    end
  end
end)

local function swap_placer(placer, player_index, tags)
  local surface, position = placer.surface, placer.position
  local direction, force, quality, last_user = placer.direction, placer.force, placer.quality, placer.last_user
  placer.destroy()
  local entity = surface.create_entity({
    name = PAD_BY_DIR[direction] or PAD_BY_DIR[D.north],
    position = position,
    force = force,
    quality = quality,
    player = player_index or last_user,
    create_build_effect_smoke = false,
  })
  if entity then register_pad(entity, tags) end
end

local function on_built(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name == PLACER then
    swap_placer(entity, event.player_index, event.tags)
  elseif DIR_BY_PAD[entity.name] and not get_pad(entity) then
    register_pad(entity, event.tags)
  end
end

local build_filter = { { filter = "name", name = PLACER } }
for _, name in pairs(PAD_NAMES) do build_filter[#build_filter + 1] = { filter = "name", name = name } end
script.on_event(defines.events.on_built_entity, on_built, build_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, build_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, build_filter)
script.on_event(defines.events.script_raised_built, on_built, build_filter)
script.on_event(defines.events.script_raised_revive, on_built, build_filter)

-- Forward declarations (squads and lasers are below).
local start_crash, beam_destroy

script.on_event(defines.events.on_object_destroyed, function(event)
  local id = storage.by_unit[event.useful_id]
  if not id then return end -- rotating unbinds first, so this only fires for real removals
  storage.by_unit[event.useful_id] = nil
  local pad = storage.pads[id]
  if not pad then return end
  if pad.power and pad.power.valid then pad.power.destroy() end
  if pad.signals and pad.signals.valid then pad.signals.destroy() end
  -- A squad still waiting over a pad that's gone has nowhere to report: it goes down.
  local squad = pad.squad and storage.squads[pad.squad]
  if squad and squad.state == "loiter" then start_crash(squad) end
  storage.pads[id] = nil
end)

-- Rotating a placed launchpad -------------------------------------------------------

local function rotate_pad(pad, reverse)
  local old = pad.entity
  local surface, position, force, quality = old.surface, old.position, old.force, old.quality
  local health, last_user = old.health, old.last_user
  local old_inv = old.get_inventory(defines.inventory.chest)
  local temp = game.create_inventory(#old_inv)
  for i = 1, #old_inv do temp[i].transfer_stack(old_inv[i]) end

  -- Player-made wires, to put back on the new pad.
  local wires = {}
  for _, id in pairs(CIRCUIT_IDS) do
    local connector = old.get_wire_connector(id, false)
    if connector then
      for _, connection in pairs(connector.connections) do
        if connection.origin == defines.wire_origin.player then
          wires[#wires + 1] = { id = id, target = connection.target }
        end
      end
    end
  end

  storage.by_unit[old.unit_number] = nil
  old.destroy()
  local entity = surface.create_entity({
    name = PAD_BY_DIR[(pad.direction + (reverse and 12 or 4)) % 16],
    position = position,
    force = force,
    quality = quality,
    player = last_user,
    create_build_effect_smoke = false,
  })
  local inv = entity.get_inventory(defines.inventory.chest)
  for i = 1, #temp do inv[i].transfer_stack(temp[i]) end
  temp.destroy()
  entity.health = health
  bind(pad, entity)
  ensure_power(pad)
  ensure_signals(pad)
  for _, wire in pairs(wires) do
    if wire.target.valid then
      entity.get_wire_connector(wire.id, true).connect_to(wire.target, false, defines.wire_origin.player)
    end
  end
end

local function on_rotate(event, reverse)
  local player = game.get_player(event.player_index)
  if not player then return end
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read then return end -- holding something: let the game rotate it
  local pad = get_pad(player.selected)
  if pad and player.selected.force == player.force then
    local viewers = {}
    for index, id in pairs(storage.open) do if id == pad.id then viewers[#viewers + 1] = index end end
    rotate_pad(pad, reverse)
    for _, index in pairs(viewers) do
      local p = game.get_player(index)
      if p then p.opened = pad.entity end
    end
  end
end

script.on_event("wp-attack-drone-rotate", function(event) on_rotate(event, false) end)
script.on_event("wp-attack-drone-reverse-rotate", function(event) on_rotate(event, true) end)

-- Squads ---------------------------------------------------------------------------

local function runway_dir(pad) return Flight.dir_vector(pad.direction) end

local function offset(p, d, k) return { x = p.x + d.x * k, y = p.y + d.y * k } end

local function loiter_center(pad)
  return { x = pad.entity.position.x, y = pad.entity.position.y }
end

local function release_claim(squad)
  if squad.claimed and storage.claimed[squad.claimed] == squad.id then storage.claimed[squad.claimed] = nil end
  squad.claimed = nil
end

local function chunk_charted(force, surface, position)
  return force.is_chunk_charted(surface, { x = math.floor(position.x / 32), y = math.floor(position.y / 32) })
end

-- Nearest charted enemy nest within `range` of `from` that no other squad is after.
local function find_nest(surface, force, from, range, me)
  local taken = {}
  for _, squad in pairs(storage.squads) do
    if squad ~= me and squad.surface == surface and (squad.state == "transit" or squad.state == "attack") then
      taken[#taken + 1] = squad.center
    end
  end
  local best, best_d
  for _, nest in pairs(surface.find_entities_filtered({
    type = "unit-spawner", position = from, radius = range, force = "enemy",
  })) do
    local claimed = storage.claimed[nest.unit_number]
    local free = not (claimed and storage.squads[claimed] and storage.squads[claimed] ~= me)
    for _, c in pairs(taken) do
      local cx, cy = nest.position.x - c.x, nest.position.y - c.y
      if cx * cx + cy * cy < CLUSTER_RADIUS * CLUSTER_RADIUS then free = false end
    end
    if free and chunk_charted(force, surface, nest.position) then
      local dx, dy = nest.position.x - from.x, nest.position.y - from.y
      local d = dx * dx + dy * dy
      if not best or d < best_d then best, best_d = nest, d end
    end
  end
  return best, best and math.sqrt(best_d)
end

local function claim(squad, nest)
  release_claim(squad)
  squad.claimed = nest.unit_number
  storage.claimed[nest.unit_number] = squad.id
end

local function new_squad(pad)
  local squad = {
    id = new_id(),
    pad_id = pad.id,
    surface = pad.entity.surface,
    force = pad.entity.force,
    state = "loiter",
    drones = {},
  }
  storage.squads[squad.id] = squad
  pad.squad = squad.id
  return squad
end

local function rand(lo, hi) return lo + math.random() * (hi - lo) end

-- Give a new drone its own wobbles.
local function init_swarm(f)
  f.wp_base_speed = f.speed * (1 + rand(-1, 1) * SPEED_JITTER)
  f.speed = f.wp_base_speed
  f.wp_wobble = {
    ring_amp = rand(RING_BREATHE[1], RING_BREATHE[2]),
    ring_w = 2 * math.pi / rand(RING_PERIOD[1], RING_PERIOD[2]),
    speed_w = 2 * math.pi / rand(120, 300),
    alt_w = 2 * math.pi / rand(150, 400),
    drift_w = 2 * math.pi / rand(90, 240),
    phase = rand(0, 2 * math.pi),
  }
  f.wp_cloud = { forward = -rand(CLOUD_BEHIND[1], CLOUD_BEHIND[2]), right = rand(-CLOUD_SIDE, CLOUD_SIDE) }
end

-- Put a drone on its own ring around `center`: ring by its number in the squad,
-- every other drone going the other way.
local function circle(f, center, rings, opts)
  local i = f.wp_index or 1
  f.wp_ring = rings[(i - 1) % #rings + 1] + rand(-1, 1) * RING_JITTER
  if f.wp_clockwise == nil then f.wp_clockwise = i % 2 == 0 end
  f.turn_radius = ATTACK_TURN_RADIUS
  opts = opts or {}
  -- Break the way it'll be circling (right for clockwise, left for counter-clockwise),
  -- along a line of its own.
  opts.first_turn = f.wp_clockwise and "R" or "L"
  opts.entry_spread = ENTRY_SPREAD
  Flight.orbit(f, center, f.wp_ring, f.wp_clockwise, opts)
end

-- Once a tick, before moving: wobble the ring, speed, altitude and cloud spot.
local function swarm_tick(f, tick)
  local w = f.wp_wobble
  if not w then return end
  local t = tick + w.phase * 100
  f.speed = f.wp_base_speed * (f.wp_rally_speed or 1) * (1 + SPEED_WOBBLE * math.sin(t * w.speed_w + w.phase))
  if f.wp_state ~= "crash" then
    f.cruise_altitude = Flight.DEFAULTS.cruise_altitude + ALTITUDE_WOBBLE * math.sin(t * w.alt_w)
  end
  if f.mode == "orbit" and f.orbit and f.wp_ring and not f.orbit.target_radius then
    -- Slewed, so the ring never jumps (e.g. right after the drone joins it).
    local want = math.max(4, f.wp_ring + w.ring_amp * math.sin(t * w.ring_w))
    local r = f.orbit.radius
    f.orbit.radius = r + math.max(-0.08, math.min(0.08, want - r))
  elseif f.mode == "follow" and f.slot and f.wp_cloud then
    f.slot.forward = f.wp_cloud.forward + CLOUD_DRIFT * math.sin(t * w.drift_w)
    f.slot.right = f.wp_cloud.right + CLOUD_DRIFT * math.cos(t * w.drift_w * 0.7 + w.phase)
  end
end

local function launch(pad)
  local squad = pad.squad and storage.squads[pad.squad]
  if not squad then squad = new_squad(pad) end
  local e = pad.entity
  local opts = { from_pad = e.position, from_dir = runway_dir(pad) }

  local tower_end = offset(e.position, runway_dir(pad), -Flight.DEFAULTS.runway_back)
  local options = { surface = e.surface, position = tower_end, direction = pad.direction }
  for k, v in pairs(DRONE_LOOKS) do options[k] = v end
  local f = Flight.new(options)
  init_swarm(f)
  f.wp_phase = math.random(0, PULSE_ON + PULSE_OFF)
  f.wp_index = #squad.drones + 1
  f.wp_state = "loiter"
  squad.center = loiter_center(pad)
  circle(f, squad.center, LOITER_RINGS, opts)

  squad.drones[#squad.drones + 1] = f
  pad.launched = (pad.launched or 0) + 1
  e.surface.play_sound({ path = "wp-attack-drone-launch", position = e.position })
end

-- Everyone's up and circling.
local function formed(squad)
  for _, f in pairs(squad.drones) do
    if f.mode ~= "orbit" then return false end
  end
  return #squad.drones > 0
end

-- Forward declaration: regroup is below.
local regroup

-- Send a full squad after the nearest nest. Returns false if there's nothing to hit.
local function dispatch(squad, pad)
  local nest, distance = find_nest(squad.surface, squad.force, pad.entity.position, TARGET_RANGE, squad)
  pad.target_info = nest and math.floor(distance) or false
  if not nest then return false end
  claim(squad, nest)
  squad.center = { x = nest.position.x, y = nest.position.y }
  regroup(squad, pad.entity.position)
  pad.squad = nil -- the pad starts a fresh squad
  pad.out = squad.id
  return true
end

-- One attack at a time per launchpad: is its last swarm still out there fighting?
-- (Once it's crashing, it's done.)
local function attack_out(pad)
  local out = pad.out and storage.squads[pad.out]
  return out ~= nil and out.state ~= "crash"
end

function start_crash(squad)
  release_claim(squad)
  squad.state = "crash"
  for _, f in pairs(squad.drones) do
    beam_destroy(f)
    f.wp_state = "crash"
    f.cruise_altitude = 0
    f.altitude_ease = CRASH_EASE * (0.7 + math.random() * 0.6) -- not all at once
    Flight.cruise(f)
  end
  local pad = storage.pads[squad.pad_id]
  if pad and pad.squad == squad.id then pad.squad = nil end
end

local function end_squad(squad)
  release_claim(squad)
  for _, f in pairs(squad.drones) do
    beam_destroy(f)
    Flight.destroy(f)
  end
  storage.squads[squad.id] = nil
end

-- Lasers ----------------------------------------------------------------------------

local BEAM_PARTS = { "beam", "spark", "muzzle" }

local function hide_beads(b)
  for _, r in pairs(b.beads or {}) do
    if r.valid then r.visible = false end
  end
  b.emits, b.next_emit = {}, nil
end

-- Beam off. With `tick`, beads already in flight carry on to the target;
-- without it (target lost, regrouping) they vanish too.
local function beam_off(f)
  local b = f.wp_beam
  if not b then return end
  for _, key in pairs(BEAM_PARTS) do
    local r = b[key]
    if r and r.valid then r.visible = false end
  end
  hide_beads(b)
  b.on = false
  b.retract_tick, b.retract_from = nil, nil
end

function beam_destroy(f)
  local b = f.wp_beam
  if not b then return end
  for _, key in pairs({ "beam", "spark", "muzzle", "halo", "core" }) do -- halo/core: 0.2.x lines
    local r = b[key]
    if r and r.valid then r.destroy() end
  end
  for _, r in pairs(b.beads or {}) do
    if r.valid then r.destroy() end
  end
  f.wp_beam = nil
end

-- Move the beads along the beam from `from` to `to`. While the beam is on, a
-- new bead leaves the drone every so often, at random gaps; beads already on
-- their way keep going to the target after the beam switches off.
local function update_beads(squad, b, from, to, tick, on, tail)
  if not BEADS then return end
  tail = tail or 0
  b.emits = b.emits or {}
  if on then
    if not b.next_emit then
      b.next_emit = tick + math.random(0, math.floor(BEAD_SPACING / BEAD_SPEED)) -- first one: random delay
    end
    if tick >= b.next_emit and #b.emits < BEAD_POOL then
      b.emits[#b.emits + 1] = tick
      local gap = BEAD_SPACING * (1 + (math.random() * 2 - 1) * BEAD_SPREAD)
      b.next_emit = tick + math.max(1, math.floor(gap / BEAD_SPEED))
    end
  else
    b.next_emit = nil
  end

  local dx, dy = to.x - from.x, to.y - from.y
  local length = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / math.max(length, 0.001), dy / math.max(length, 0.001)
  local orientation = (math.atan2(dy, dx) / (2 * math.pi)) % 1
  b.beads = b.beads or {}

  local alive = {}
  for i, emitted in ipairs(b.emits) do
    local d = (tick - emitted) * BEAD_SPEED
    if d <= length and d >= tail then
      alive[#alive + 1] = emitted
      local slot = #alive
      local r = b.beads[slot]
      if not (r and r.valid) then
        r = rendering.draw_sprite({
          sprite = BEAD_SPRITE, target = from, surface = squad.surface, render_layer = BEAM_LAYER,
        })
        b.beads[slot] = r
      end
      r.target = { x = from.x + ux * d, y = from.y + uy * d }
      r.orientation = orientation
      -- Swell a little as it travels, like a drop gathering itself.
      local swell = 1 + 0.25 * math.sin(d / math.max(length, 0.001) * math.pi)
      r.x_scale, r.y_scale = BEAD_LENGTH * swell, BEAD_WIDTH * swell
      r.visible = true
    end
  end
  b.emits = alive
  for slot, r in pairs(b.beads) do
    if slot > #alive and r.valid then r.visible = false end
  end
end

local function in_range(f, target)
  local g = Flight.ground(f)
  local dx, dy = target.position.x - g.x, target.position.y - g.y
  return dx * dx + dy * dy <= (ENGAGE_RANGE + 4) ^ 2
end

-- Nests and worms always come first: a drone only shoots biters when there are no
-- nests or worms within reach.
local function find_primary(squad, f)
  local targets = squad.surface.find_entities_filtered({
    type = PRIMARY_TARGETS, position = Flight.ground(f), radius = PRIMARY_REACH, force = "enemy",
  })
  if #targets == 0 then return nil end
  return targets[math.random(#targets)]
end

local function pick_target(squad, f)
  local primary = find_primary(squad, f)
  if primary then return primary end
  local targets = squad.surface.find_entities_filtered({
    type = SECONDARY_TARGETS, position = Flight.ground(f), radius = ENGAGE_RANGE, force = "enemy",
  })
  if #targets == 0 then return nil end
  return targets[math.random(#targets)]
end

local function in_range(f, target)
  local g = Flight.ground(f)
  local dx, dy = target.position.x - g.x, target.position.y - g.y
  local reach = PRIMARY_LOOKUP[target.type] and PRIMARY_REACH or ENGAGE_RANGE
  return dx * dx + dy * dy <= (reach + 4) ^ 2
end

local function pick_target(squad, f)
  local ground = Flight.ground(f)
  local targets = squad.surface.find_entities_filtered({
    type = PRIMARY_TARGETS, position = ground, radius = ENGAGE_RANGE, force = "enemy",
  })
  if #targets == 0 then
    targets = squad.surface.find_entities_filtered({
      type = SECONDARY_TARGETS, position = ground, radius = ENGAGE_RANGE, force = "enemy",
    })
  end
  if #targets == 0 then return nil end
  return targets[math.random(#targets)]
end

-- Stretch and turn the beam sprite so it runs from the drone to the target.
local function place_beam(beam, from, to, tick, phase)
  local dx, dy = to.x - from.x, to.y - from.y
  local length = math.sqrt(dx * dx + dy * dy)
  beam.target = { x = (from.x + to.x) / 2, y = (from.y + to.y) / 2 }
  beam.orientation = (math.atan2(dy, dx) / (2 * math.pi)) % 1
  beam.x_scale = math.max(0.01, length / 2) -- the texture is 64 px = 2 tiles long
  -- A little shimmer so it reads as energy, not a wire.
  beam.y_scale = BEAM_THICKNESS * (1 + 0.25 * math.sin((tick + phase) * 0.6))
end

-- Point the beam at a target, making its parts if needed. Returns true when it
-- just switched on (for the sound).
local function beam_aim(squad, f, target, tick)
  local b = f.wp_beam
  if not b then
    b = {}
    f.wp_beam = b
  end
  for _, key in pairs({ "halo", "core" }) do -- lines from 0.2.0/0.2.1
    if b[key] and b[key].valid then b[key].destroy() end
    b[key] = nil
  end
  local from = Flight.air(f)
  local surface = squad.surface
  -- Each part is checked on its own: a light attached to a target is destroyed
  -- by the game along with that target.
  if not (b.beam and b.beam.valid) then
    b.beam = rendering.draw_sprite({
      sprite = BEAM_SPRITE, target = from, surface = surface, render_layer = BEAM_LAYER, visible = false,
    })
    b.on = false
  end
  if not (b.spark and b.spark.valid) or b.spark_for ~= target then
    if b.spark and b.spark.valid then b.spark.destroy() end
    b.spark = rendering.draw_light({
      sprite = "utility/light_small", target = target, surface = surface,
      color = LASER_COLOR, intensity = 0.9, scale = 0.8, visible = b.on,
    })
    b.spark_for = target
  end
  if not (b.muzzle and b.muzzle.valid) then
    b.muzzle = rendering.draw_light({
      sprite = "utility/light_small", target = from, surface = surface,
      color = LASER_COLOR, intensity = 0.7, scale = 0.4, visible = b.on,
    })
  end
  place_beam(b.beam, from, target.position, tick, f.wp_phase)
  b.muzzle.target = from
  if not b.on then
    for _, key in pairs(BEAM_PARTS) do b[key].visible = true end
    b.on = true
    b.retract_tick, b.retract_from = nil, nil
    return true
  end
  return false
end

-- One tick of one drone's laser. `pulsing` is the map setting.
local function update_laser(squad, f, tick, cause, pulsing)
  -- Drones launched before 0.2.0 have no pulse phase yet.
  if not f.wp_phase then f.wp_phase = math.random(0, PULSE_ON + PULSE_OFF) end
  local target = f.wp_target
  if not (target and target.valid and in_range(f, target)) then
    target = nil
    f.wp_target = nil
    beam_off(f)
    if tick < (f.wp_next_search or 0) then return end
    f.wp_next_search = tick + RETARGET_INTERVAL
    target = pick_target(squad, f)
    if not target then return end
    f.wp_target = target
  elseif not PRIMARY_LOOKUP[target.type] and tick >= (f.wp_next_search or 0) then
    -- Shooting a biter: switch the moment a nest or worm comes within reach.
    f.wp_next_search = tick + RETARGET_INTERVAL
    local primary = find_primary(squad, f)
    if primary then
      beam_off(f)
      target = primary
      f.wp_target = target
    end
  end

  local on = true
  local scale = 1
  if pulsing then
    on = (tick + f.wp_phase) % (PULSE_ON + PULSE_OFF) < PULSE_ON
    scale = (PULSE_ON + PULSE_OFF) / PULSE_ON
  end
  if not on then
    local b = f.wp_beam
    if not b then return end
    if not RETRACT then
      if b.on then beam_off(f) end
      return
    end
    if b.on then
      -- Pulse over: let go of the drone, right where it is now.
      b.on = false
      b.retract_tick, b.retract_from = tick, Flight.air(f)
      if b.muzzle and b.muzzle.valid then b.muzzle.visible = false end
    end
    if b.retract_tick then
      local from, to = b.retract_from, target.position
      local dx, dy = to.x - from.x, to.y - from.y
      local length = math.sqrt(dx * dx + dy * dy)
      local tail = (tick - b.retract_tick) * RETRACT_SPEED
      if tail >= length or not (b.beam and b.beam.valid) then
        beam_off(f) -- fully shrunk into the target
      else
        local k = tail / math.max(length, 0.001)
        place_beam(b.beam, { x = from.x + dx * k, y = from.y + dy * k }, to, tick, f.wp_phase)
        update_beads(squad, b, from, to, tick, false, tail)
      end
    end
    return
  end

  if beam_aim(squad, f, target, tick) and (not squad.sound_tick or tick - squad.sound_tick >= 12) then
    squad.sound_tick = tick
    if helpers.is_valid_sound_path("wp-attack-drone-laser") then
      squad.surface.play_sound({ path = "wp-attack-drone-laser", position = Flight.air(f) })
    end
  end
  update_beads(squad, f.wp_beam, Flight.air(f), target.position, tick, true)
  if (tick + f.wp_phase) % DAMAGE_INTERVAL == 0 then
    -- The pad is the "cause", so the nests send their revenge at it, like artillery.
    target.damage(laser_dps(squad.force) * DAMAGE_INTERVAL / 60 * scale, squad.force, "laser", nil, cause)
  end
end

-- Over the target: every drone on its own ring. The leader breaks first; the
-- wingmen peel off one by one, each banking the way it'll circle.
local function spread_out(squad, tick)
  for i, f in ipairs(squad.drones) do
    if f.wp_state ~= "crash" then
      f.wp_index = f.wp_index or i
      if f == squad.leader or not tick then
        f.wp_state = "attack"
        f.wp_break_at = nil
        circle(f, squad.center, RING_RADII)
      else
        f.wp_state = "breaking"
        f.follow_max = CATCH_UP_MIN -- don't chase the leader's tight turn
        f.wp_break_at = tick + math.random(BREAK_STAGGER[1], BREAK_STAGGER[2])
      end
    end
  end
end

-- Ticking ---------------------------------------------------------------------------

-- Fly to squad.center as a loose cloud behind a leader. Used to head out from the
-- launchpad and, when a nest is cleared, to move on to the next one (the attack
-- timer keeps running, so a squad can run dry and crash on the way).
function regroup(squad, from)
  squad.state = "transit"
  local any
  for _, f in ipairs(squad.drones) do
    if f.wp_state ~= "crash" then any = f break end
  end
  if not any then return end

  -- The rally point, on the straight line from `from` to the target.
  from = from or any.pos
  local dx, dy = squad.center.x - from.x, squad.center.y - from.y
  local distance = math.max(1, math.sqrt(dx * dx + dy * dy))
  local dir = { x = dx / distance, y = dy / distance }
  local right = { x = -dir.y, y = dir.x }
  local along = math.min(distance * 0.6, math.max(RALLY_MIN, math.min(RALLY_MAX, distance * RALLY_AT)))
  local rally = { x = from.x + dir.x * along, y = from.y + dir.y * along }

  -- Lead with the drone that can get to the rally point soonest (one already
  -- heading that way). A leader that has to loop back past the launchpad would
  -- drag its wingmen back with it.
  local leader, best
  for _, f in ipairs(squad.drones) do
    if f.wp_state ~= "crash" then
      f.turn_radius = Flight.DEFAULTS.turn_radius
      Flight.fly_to(f, rally, dir)
      local t = f.path.total / f.wp_base_speed
      if not best or t < best then leader, best = f, t end
    end
  end
  squad.leader = leader

  for _, f in ipairs(squad.drones) do
    beam_off(f)
    f.wp_target = nil
    f.wp_ring = nil
    f.wp_break_at = nil
    f.wp_rally_speed = nil
    f.turn_radius = Flight.DEFAULTS.turn_radius
    f.wp_leg = "rally"
    if f == leader then
      f.wp_state = "lead"
      Flight.fly_to(f, rally, dir)
    else
      f.wp_state = "wing"
      if not f.wp_cloud then init_swarm(f) end
      -- Its own spot in the cloud at the rally point.
      local c = f.wp_cloud
      local spot = {
        x = rally.x + dir.x * c.forward + right.x * c.right,
        y = rally.y + dir.y * c.forward + right.y * c.right,
      }
      Flight.fly_to(f, spot, dir)
    end
  end
  -- Time everyone to get there together: each drone's speed is set so its own
  -- path takes as long as the leader's.
  local leader_time = leader.path.total / leader.wp_base_speed
  for _, f in ipairs(squad.drones) do
    if f ~= leader and f.path then
      local want = f.path.total / leader_time / f.wp_base_speed
      f.wp_rally_speed = math.max(RALLY_SPEED[1], math.min(RALLY_SPEED[2], want))
    end
  end
end

-- A wingman falls in behind the leader, catching up if it's late.
local function fall_in(squad, f)
  f.wp_waiting = nil
  f.wp_rally_speed = nil
  local leader = squad.leader
  local gap = math.sqrt((f.pos.x - leader.pos.x) ^ 2 + (f.pos.y - leader.pos.y) ^ 2)
  local left = math.sqrt((leader.pos.x - squad.center.x) ^ 2 + (leader.pos.y - squad.center.y) ^ 2)
  f.follow_max = math.max(CATCH_UP_MIN, math.min(CATCH_UP_MAX, 1 + gap / math.max(40, left)))
  Flight.follow(f, leader, f.wp_cloud)
end

-- A drone reached the rally point: the leader heads on to the target, wingmen
-- fall in behind it. A wingman that beat the leader there doesn't turn back for
-- it: it carries on slowly toward the target and falls in once the leader is through.
local function rallied(squad, f)
  f.wp_leg = nil
  f.wp_rally_speed = nil
  if f == squad.leader then
    Flight.orbit(f, squad.center, RING_RADII[#RING_RADII], false)
    for _, w in ipairs(squad.drones) do
      if w.wp_waiting then fall_in(squad, w) end
    end
  elseif squad.leader.wp_leg == "rally" then
    f.wp_waiting = true
    f.wp_rally_speed = 0.7
    Flight.cruise(f)
  else
    fall_in(squad, f)
  end
end

local function enemies_near(surface, center)
  return surface.count_entities_filtered({
    type = PRIMARY_TARGETS, position = center, radius = RING_RADII[#RING_RADII] + ENGAGE_RANGE,
    force = "enemy", limit = 1,
  }) > 0
end

local function update_squad(squad, tick, pulsing)
  if not squad.surface.valid then
    end_squad(squad)
    return
  end
  local pad = storage.pads[squad.pad_id]
  local cause = pad and pad.entity.valid and pad.entity or nil

  -- Move everyone (the leader is first in the list, so wingmen follow its new spot).
  local survivors = {}
  for _, f in ipairs(squad.drones) do
    if f.wp_break_at and tick >= f.wp_break_at and squad.state == "attack" then
      f.wp_break_at = nil
      f.wp_state = "attack"
      circle(f, squad.center, RING_RADII)
    end
    swarm_tick(f, tick)
    local event = Flight.step(f)
    local keep = true
    if f.wp_state == "crash" then
      if f.altitude < 0.3 then
        squad.surface.create_entity({ name = "medium-explosion", position = Flight.ground(f) })
        Flight.destroy(f)
        keep = false
      end
    elseif event == "arrived" and f.wp_leg == "rally" and squad.state == "transit" then
      rallied(squad, f)
    elseif event == "arrived" and f.wp_state == "joining" then
      -- (0.3.x and older) a drone that was flying out to join a formation
      circle(f, squad.center, LOITER_RINGS)
    elseif event == "orbiting" and f == squad.leader and squad.state == "transit" then
      -- Over the target: break formation and scatter onto the rings. The timer
      -- starts at the first nest and keeps running from nest to nest.
      squad.state = "attack"
      squad.ends = squad.ends or (tick + attack_ticks(squad.force))
      squad.next_check = tick + 60
      spread_out(squad, tick)
    end
    if keep then survivors[#survivors + 1] = f end
  end
  squad.drones = survivors

  if squad.state == "crash" then
    if #survivors == 0 then end_squad(squad) end
    return
  end

  if squad.ends and tick >= squad.ends then
    start_crash(squad) -- out of battery, wherever they are
    return
  end
  if (squad.state == "transit" or squad.state == "attack") and tick % REVEAL_INTERVAL == squad.id % REVEAL_INTERVAL then
    local at = squad.state == "attack" and squad.center or (squad.leader and squad.leader.pos)
    if at then
      squad.force.chart(squad.surface, {
        { at.x - REVEAL_RADIUS, at.y - REVEAL_RADIUS }, { at.x + REVEAL_RADIUS, at.y + REVEAL_RADIUS },
      })
    end
  end
  if squad.state == "attack" then
    for _, f in pairs(survivors) do update_laser(squad, f, tick, cause, pulsing) end
    if tick >= squad.next_check then
      squad.next_check = tick + 60
      if not enemies_near(squad.surface, squad.center) then
        -- This nest is done: squad up and head for the nearest one left.
        local nest = find_nest(squad.surface, squad.force, squad.center, TARGET_RANGE, squad)
        if nest then
          claim(squad, nest)
          local from = squad.center
          squad.center = { x = nest.position.x, y = nest.position.y }
          regroup(squad, from)
        end
      end
    end
  end
end

-- Why a pad isn't launching, for its panel.
local function update_pads(tick)
  for _, pad in pairs(storage.pads) do
    local e = pad.entity
    if e.valid then
      local squad = pad.squad and storage.squads[pad.squad]
      local count = squad and #squad.drones or 0
      if count < squad_size(pad) then
        local power = pad.power
        local inv = e.get_inventory(defines.inventory.chest)
        if inv.get_item_count(DRONE) == 0 then
          pad.status = "no-drones"
        elseif not (power and power.valid and power.energy >= LAUNCH_ENERGY) then
          pad.status = "low-power"
        else
          pad.status = "launching"
          if tick >= pad.next_launch and inv.remove({ name = DRONE, count = 1 }) > 0 then
            power.energy = power.energy - LAUNCH_ENERGY
            pad.next_launch = tick + LAUNCH_INTERVAL
            launch(pad)
          end
        end
      elseif not formed(squad) then
        pad.status = "forming"
      elseif attack_out(pad) then
        pad.status = "waiting"
      elseif tick >= (pad.next_search or 0) then
        if dispatch(squad, pad) then
          pad.status = "launching"
        else
          pad.status = "no-target"
          pad.next_search = tick + TARGET_RETRY
        end
      end
    end
  end
end

script.on_event(defines.events.on_tick, function(event)
  local tick = event.tick
  if tick % 10 == 0 then update_pads(tick) end
  local pulsing = settings.global["wp-attack-drone-laser-style"].value == "pulsing"
  for _, squad in pairs(storage.squads) do update_squad(squad, tick, pulsing) end
  if tick % 28 == 0 and next(storage.squads) then
    local all = {}
    for _, squad in pairs(storage.squads) do
      for _, f in pairs(squad.drones) do all[#all + 1] = f end
    end
    Flight.play_sounds(all, "wp-attack-drone-flying")
  end
end)

-- GUI -------------------------------------------------------------------------------

local function seconds(ticks) return math.floor(ticks / 60 + 0.5) end

local function refresh_gui(player)
  local frame = player.gui.relative[GUI]
  local pad = storage.pads[storage.open[player.index] or 0]
  if not (frame and pad) then return end

  local squad = pad.squad and storage.squads[pad.squad]
  local count = squad and #squad.drones or 0
  frame.wp_status.caption = { "wp-attack-drones.loitering", count, squad_size(pad) }
  frame.wp_reason.caption = { "wp-attack-drones.status-" .. (pad.status or "launching"), TARGET_RANGE }

  local out, attacking = 0, 0
  for _, s in pairs(storage.squads) do
    if s.pad_id == pad.id and s.state ~= "loiter" and s.state ~= "crash" then
      out = out + 1
      if s.state == "attack" then attacking = attacking + 1 end
    end
  end
  frame.wp_squads.caption = { "wp-attack-drones.squads-out", out, attacking }
  local airborne = 0
  for _, s in pairs(storage.squads) do
    if s.pad_id == pad.id then airborne = airborne + #s.drones end
  end
  frame.wp_counts.caption = { "wp-attack-drones.counts", pad.launched or 0, airborne }

  local power = pad.power
  frame.wp_power.caption = (power and power.valid and power.energy >= LAUNCH_ENERGY)
    and { "wp-attack-drones.power-ok" } or { "wp-attack-drones.power-low" }

  if pad.target_info == false then
    frame.wp_target.caption = { "wp-attack-drones.no-target", TARGET_RANGE }
  elseif pad.target_info then
    frame.wp_target.caption = { "wp-attack-drones.last-target", pad.target_info }
  else
    frame.wp_target.caption = { "wp-attack-drones.target-range", TARGET_RANGE }
  end
  frame.wp_attack_time.caption = { "wp-attack-drones.attack-time", seconds(attack_ticks(pad.entity.force)) }
  local force = pad.entity.force
  frame.wp_damage.caption = { "wp-attack-drones.damage", string.format("%.1f", laser_dps(force)),
    math.floor(laser_bonus(force) * 100 + 0.5) }
end

local function destroy_gui(player)
  local frame = player.gui.relative[GUI]
  if frame then frame.destroy() end
  storage.open[player.index] = nil
end

local function build_gui(player, pad)
  destroy_gui(player)
  local frame = player.gui.relative.add({
    type = "frame",
    name = GUI,
    caption = { "wp-attack-drones.panel-title" },
    direction = "vertical",
    anchor = { gui = defines.relative_gui_type.container_gui, position = defines.relative_gui_position.right },
  })
  frame.add({ type = "label", name = "wp_status", style = "caption_label" })
  local reason = frame.add({ type = "label", name = "wp_reason" })
  reason.style.single_line = false
  reason.style.maximal_width = 240
  frame.add({ type = "label", name = "wp_squads" })
  frame.add({ type = "label", name = "wp_counts" })
  frame.add({ type = "label", name = "wp_power" })
  local target = frame.add({ type = "label", name = "wp_target" })
  target.style.single_line = false
  target.style.maximal_width = 240
  frame.add({ type = "label", name = "wp_attack_time" })
  frame.add({ type = "label", name = "wp_damage" })

  frame.add({ type = "line" })
  frame.add({
    type = "label",
    caption = { "wp-attack-drones.threshold" },
    tooltip = { "wp-attack-drones.threshold-tooltip" },
    style = "caption_label",
  })
  local row = frame.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.add({
    type = "slider",
    name = "wp_threshold_slider",
    minimum_value = 1,
    maximum_value = swarm_cap(pad.entity.force),
    value = squad_size(pad),
    value_step = 1,
    discrete_values = true,
    tooltip = { "wp-attack-drones.threshold-tooltip" },
  }).style.width = 160
  local box = row.add({
    type = "textfield",
    name = "wp_threshold_text",
    text = tostring(squad_size(pad)),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    tooltip = { "wp-attack-drones.threshold-tooltip" },
  })
  box.style.width = 50

  storage.open[player.index] = pad.id
  refresh_gui(player)
end

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  local pad = get_pad(event.entity)
  if player and pad then build_gui(player, pad) end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if player and storage.open[player.index] then destroy_gui(player) end
end)

local function set_threshold(event, value)
  local pad = storage.pads[storage.open[event.player_index] or 0]
  if not (pad and value) then return end
  pad.threshold = math.max(1, math.min(swarm_cap(pad.entity.force), math.floor(value)))
  pad.next_search = nil
  local frame = game.get_player(event.player_index).gui.relative[GUI]
  if frame then
    local row = event.element.parent
    if row.wp_threshold_slider and event.element.name ~= "wp_threshold_slider" then
      row.wp_threshold_slider.slider_value = pad.threshold
    end
    if row.wp_threshold_text and event.element.name ~= "wp_threshold_text" then
      row.wp_threshold_text.text = tostring(pad.threshold)
    end
    refresh_gui(game.get_player(event.player_index))
  end
end

script.on_event(defines.events.on_gui_value_changed, function(event)
  if event.element.name == "wp_threshold_slider" then set_threshold(event, event.element.slider_value) end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  if event.element.name == "wp_threshold_text" then set_threshold(event, tonumber(event.element.text)) end
end)

-- Write a pad's signals (only when they change).
local function update_signals(pad)
  local signals = pad.signals
  if not (signals and signals.valid and pad.entity.valid) then return end
  local squad = pad.squad and storage.squads[pad.squad]
  local circling = 0
  if squad then
    for _, f in pairs(squad.drones) do
      if f.mode == "orbit" or f.wp_state == "loiter" then circling = circling + 1 end
    end
  end
  local in_pad = pad.entity.get_inventory(defines.inventory.chest).get_item_count(DRONE)
  local attacking = attack_out(pad) and 1 or 0
  local key = in_pad .. "/" .. circling .. "/" .. attacking
  if pad.signal_cache == key then return end
  pad.signal_cache = key

  local cb = signals.get_or_create_control_behavior()
  local section = cb.sections_count > 0 and cb.get_section(1) or cb.add_section()
  section.filters = {
    { value = { type = "virtual", name = "wp-attack-drones-in-launchpad", quality = "normal" }, min = in_pad },
    { value = { type = "virtual", name = "wp-attack-drones-circling", quality = "normal" }, min = circling },
    { value = { type = "virtual", name = "wp-attack-drones-attacking", quality = "normal" }, min = attacking },
  }
end

script.on_nth_tick(30, function()
  for _, pad in pairs(storage.pads) do update_signals(pad) end
  for index in pairs(storage.open) do
    local player = game.get_player(index)
    if player then refresh_gui(player) end
  end
end)

-- Copy settings and blueprints --------------------------------------------------------

script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local source, destination = get_pad(event.source), get_pad(event.destination)
  if source and destination then destination.threshold = source.threshold end
end)

-- Blueprints save pads as rotatable placers carrying their threshold.
script.on_event(defines.events.on_player_setup_blueprint, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local bp = event.stack
  if not (bp and bp.valid_for_read and bp.is_blueprint) then
    bp = player.blueprint_to_setup
    if not (bp and bp.valid_for_read) then bp = player.cursor_stack end
  end
  if not (bp and bp.valid_for_read and bp.is_blueprint) then return end

  local entities = bp.get_blueprint_entities()
  if not entities then return end
  local mapping = event.mapping.get()
  local changed = false
  for _, bp_entity in pairs(entities) do
    if DIR_BY_PAD[bp_entity.name] then
      local pad = get_pad(mapping[bp_entity.entity_number])
      local tags = bp_entity.tags or {}
      tags.wp_threshold = pad and pad.threshold or DEFAULT_THRESHOLD
      bp_entity.direction = DIR_BY_PAD[bp_entity.name]
      bp_entity.name = PLACER
      bp_entity.bar = nil
      bp_entity.tags = tags
      changed = true
    end
  end
  if changed then bp.set_blueprint_entities(entities) end
end)

-- /wp-drone-swarms-clear: remove every attack drone in the air (for testing, or
-- to clean up drones left over from an older version).
commands.add_command("wp-drone-swarms-clear", { "wp-attack-drones.clear-help" }, function(command)
  local player = command.player_index and game.get_player(command.player_index)
  if player and not player.admin then
    player.print({ "wp-attack-drones.clear-admin" })
    return
  end
  local count = 0
  for _, squad in pairs(storage.squads) do
    for _, f in pairs(squad.drones) do
      beam_destroy(f)
      Flight.destroy(f)
      count = count + 1
    end
  end
  storage.squads = {}
  storage.claimed = {}
  for _, pad in pairs(storage.pads) do pad.squad = nil end
  game.print({ "wp-attack-drones.cleared", count })
end)

-- Mining a launchpad (to move it) packs up the swarm circling over it: those
-- drones come back as items along with the pad. A pad that's destroyed still
-- loses its swarm (see on_object_destroyed).
local function on_pad_mined(event)
  local pad = get_pad(event.entity)
  local squad = pad and pad.squad and storage.squads[pad.squad]
  if not (squad and squad.state == "loiter") then return end
  local count = 0
  for _, f in pairs(squad.drones) do
    if f.wp_state ~= "crash" then count = count + 1 end
  end
  end_squad(squad)
  pad.squad = nil
  if count > 0 then
    local inserted = event.buffer and event.buffer.insert({ name = DRONE, count = count }) or 0
    if inserted < count then
      event.entity.surface.spill_item_stack({
        position = event.entity.position,
        stack = { name = DRONE, count = count - inserted },
        enable_looted = true,
        force = event.entity.force,
      })
    end
  end
end

local mined_filter = {}
for _, name in pairs(PAD_NAMES) do mined_filter[#mined_filter + 1] = { filter = "name", name = name } end
script.on_event(defines.events.on_player_mined_entity, on_pad_mined, mined_filter)
script.on_event(defines.events.on_robot_mined_entity, on_pad_mined, mined_filter)
script.on_event(defines.events.on_space_platform_mined_entity, on_pad_mined, mined_filter)
