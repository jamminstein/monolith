-- bandmate.lua
-- generative bass line engine for monolith
--
-- 5 styles of bass line generation:
-- FUNK: bootsy collins, syncopated ghost notes, the ONE
-- ROCK: driving 8ths, tim commerford power
-- ACID: 303 squelch, slides, 16th note runs
-- DUB: space and weight, robbie shakespeare
-- CHAOS: squarepusher meets lightning bolt

local musicutil = require "musicutil"

local b = {}

b.STYLE_NAMES = {"FUNK", "ROCK", "ACID", "DUB", "CHAOS", "HIP-HOP", "SHUFFLE", "HALFTIME", "LATIN"}

-- state
b.playing = false
b.style = 1
b.intensity = 5
b.root = 36
b.scale_notes = {}
b.pattern = {}
b.step = 0
b.bar = 0
b.phrase_len = 4
b.clock_id = nil
b.current_note = nil
b.note_on_fn = nil
b.note_off_fn = nil

-- breathing: long-form energy arc
b.energy = 1.0      -- 0=silent, 1=full
b.breathing = true   -- enable breathing
b.breath_bar = 0     -- counter for breath cycle
b.breath_phase = "play" -- "play", "fade", "silence", "build"

-- per-mode glide (set by host)
b.mode_glide = 0

-- pattern lock + favorites
b.locked = false
b.favorites = {}
b.favorites_mode = false
b.favorites_order = "sequential"
b.favorites_idx = 1

---------- NOTE SELECTION ----------

local function pick_interval(style)
  local pools = {
    -- FUNK: root-heavy with color tones
    {0, 0, 0, 0, 7, 12, -12, 3, 5, 10},
    -- ROCK: power intervals
    {0, 0, 0, 0, 7, 7, 12, 12, -12, -12},
    -- ACID: minor pentatonic wandering
    {0, 0, 0, 3, 5, 7, 10, 12, -12, 3, 5},
    -- DUB: root and octave dominance
    {0, 0, 0, 0, 0, 0, 7, -12, 12},
    -- CHAOS: wide intervals, dissonance welcome
    {0, 3, 5, 7, 10, 12, -12, -5, -7, 15, 14, 2, 1, -1, 17, 19},
    -- HIP-HOP: root and sub octave heavy
    {0, 0, 0, 0, 0, -12, -12, 7, 12},
    -- SHUFFLE: stepwise walking
    {0, 0, 0, 2, 3, 5, 7, -2, -5, 10},
    -- HALFTIME: root and power
    {0, 0, 0, 0, -12, 7, 12},
    -- LATIN: root with fifth color
    {0, 0, 0, 7, 7, 5, -12, 12, 3},
  }
  local pool = pools[style] or pools[1]
  return pool[math.random(#pool)]
end

local function chromatic_approach()
  local approaches = {-1, 1, -2, 2, 11, -11}
  return approaches[math.random(#approaches)]
end

---------- PATTERN GENERATORS ----------

local function gen_funk(intensity)
  local p = {}
  local int = intensity / 10

  -- the ONE is sacred in funk
  p[1] = {offset = 0, vel = 0.9 + math.random() * 0.1, gate = 0.5 + math.random() * 0.2}

  -- syncopated hit on "and" of 2 or 3
  if math.random() < 0.85 then
    local pos = math.random() < 0.5 and 5 or 7
    p[pos] = {
      offset = pick_interval(1),
      vel = 0.7 + math.random() * 0.2,
      gate = 0.25 + math.random() * 0.25,
    }
  end

  -- beat 3 anchor
  if math.random() < 0.75 then
    p[9] = {offset = 0, vel = 0.8 + math.random() * 0.15, gate = 0.4}
  end

  -- late syncopation (and of 3, beat 4 area)
  if math.random() < 0.7 then
    local pos = ({11, 13, 15})[math.random(3)]
    p[pos] = {
      offset = pick_interval(1),
      vel = 0.6 + math.random() * 0.25,
      gate = 0.2 + math.random() * 0.15,
    }
  end

  -- chromatic approach before next downbeat
  if math.random() < 0.5 then
    p[16] = {offset = chromatic_approach(), vel = 0.5 + math.random() * 0.2, gate = 0.12}
  end

  -- second syncopation for busier patterns
  if int > 0.5 and math.random() < 0.5 then
    local pos = ({4, 6, 8, 10, 12, 14})[math.random(6)]
    if not p[pos] then
      p[pos] = {
        offset = pick_interval(1),
        vel = 0.55 + math.random() * 0.2,
        gate = 0.2 + math.random() * 0.15,
      }
    end
  end

  -- ghost notes (the secret sauce)
  if int > 0.3 then
    for i = 1, 16 do
      if not p[i] and math.random() < (int - 0.2) * 0.18 then
        p[i] = {
          offset = 0,
          vel = 0.1 + math.random() * 0.2,
          gate = 0.08 + math.random() * 0.08,
        }
      end
    end
  end

  return p
end

local function gen_rock(intensity)
  local p = {}
  local int = intensity / 10

  -- driving 8th notes
  for i = 1, 16, 2 do
    if math.random() < 0.75 + int * 0.25 then
      local offset = i == 1 and 0 or pick_interval(2)
      p[i] = {
        offset = offset,
        vel = 0.7 + math.random() * 0.25,
        gate = 0.55 + math.random() * 0.15,
      }
    end
  end

  -- the 1 is always strong
  p[1] = {offset = 0, vel = 0.95, gate = 0.6}

  -- 16th note fills at high intensity
  if int > 0.5 then
    for i = 2, 16, 2 do
      if not p[i] and math.random() < (int - 0.4) * 0.35 then
        p[i] = {
          offset = pick_interval(2),
          vel = 0.5 + math.random() * 0.25,
          gate = 0.25 + math.random() * 0.15,
        }
      end
    end
  end

  -- occasional octave drop for power
  if math.random() < 0.4 then
    local pos = ({5, 9, 13})[math.random(3)]
    if p[pos] then p[pos].offset = -12 end
  end

  return p
end

local function gen_acid(intensity)
  local p = {}
  local int = intensity / 10

  -- 16th note pattern with rests
  for i = 1, 16 do
    if math.random() < 0.35 + int * 0.4 then
      local has_slide = math.random() < 0.25
      p[i] = {
        offset = pick_interval(3),
        vel = 0.45 + math.random() * 0.5,
        gate = has_slide and 0.95 or (0.15 + math.random() * 0.4),
        slide = has_slide,
      }
    end
  end

  -- always hit the 1
  p[1] = p[1] or {offset = 0, vel = 0.85, gate = 0.35}

  -- accent patterns (groups of 2-3 notes)
  if math.random() < 0.6 then
    local start = math.random(10)
    for i = start, math.min(16, start + math.random(2)) do
      if p[i] then
        p[i].vel = math.min(1.0, p[i].vel + 0.2)
      end
    end
  end

  return p
end

local function gen_dub(intensity)
  local p = {}
  local int = intensity / 10

  -- heavy root on the 1 - long and powerful
  p[1] = {offset = 0, vel = 1.0, gate = 0.85}

  -- maybe beat 3
  if math.random() < 0.55 then
    p[9] = {offset = 0, vel = 0.85, gate = 0.7}
  end

  -- single fill note
  if math.random() < 0.25 + int * 0.15 then
    local pos = ({7, 11, 13, 15})[math.random(4)]
    p[pos] = {
      offset = pick_interval(4),
      vel = 0.5 + math.random() * 0.3,
      gate = 0.25 + math.random() * 0.2,
    }
  end

  -- octave drop anticipation
  if math.random() < 0.35 then
    p[16] = {offset = -12, vel = 0.7, gate = 0.15}
  end

  -- at high intensity, add a second fill
  if int > 0.7 and math.random() < 0.4 then
    local pos = ({5, 6, 14})[math.random(3)]
    if not p[pos] then
      p[pos] = {offset = pick_interval(4), vel = 0.4 + math.random() * 0.2, gate = 0.2}
    end
  end

  return p
end

local function gen_chaos(intensity)
  local p = {}
  local int = intensity / 10

  -- dense, unpredictable fills
  for i = 1, 16 do
    if math.random() < 0.25 + int * 0.55 then
      p[i] = {
        offset = pick_interval(5),
        vel = 0.25 + math.random() * 0.75,
        gate = 0.04 + math.random() * 0.5,
      }
    end
  end

  -- accent clusters (machine gun bursts)
  if math.random() < 0.6 then
    local start = math.random(12)
    local len = 2 + math.random(3)
    for i = start, math.min(16, start + len) do
      p[i] = {
        offset = pick_interval(5),
        vel = 0.8 + math.random() * 0.2,
        gate = 0.06 + math.random() * 0.1,
      }
    end
  end

  -- sudden silence gaps
  if math.random() < 0.3 then
    local gap_start = math.random(8)
    for i = gap_start, math.min(16, gap_start + 2 + math.random(2)) do
      p[i] = nil
    end
  end

  return p
end

local function gen_hiphop(intensity)
  local p = {}
  local int = intensity / 10

  -- heavy 808 hit on the 1
  p[1] = {offset = -12, vel = 1.0, gate = 0.7 + math.random() * 0.2}

  -- hit on beat 3
  if math.random() < 0.7 then
    p[9] = {offset = 0, vel = 0.9, gate = 0.6}
  end

  -- sliding 808: long sustained note with slide
  if math.random() < 0.4 + int * 0.2 then
    local pos = ({5, 7, 13})[math.random(3)]
    p[pos] = {offset = pick_interval(6), vel = 0.7 + math.random() * 0.2, gate = 0.8, slide = true}
  end

  -- triplet-feel hits at high intensity
  if int > 0.5 then
    local triplet_pos = {4, 7, 10, 13}
    for _, pos in ipairs(triplet_pos) do
      if not p[pos] and math.random() < (int - 0.4) * 0.3 then
        p[pos] = {offset = pick_interval(6), vel = 0.5 + math.random() * 0.3, gate = 0.2}
      end
    end
  end

  -- occasional 16th ghost
  if int > 0.6 and math.random() < 0.3 then
    local pos = math.random(16)
    if not p[pos] then
      p[pos] = {offset = 0, vel = 0.15 + math.random() * 0.15, gate = 0.1}
    end
  end

  return p
end

local function gen_shuffle(intensity)
  local p = {}
  local int = intensity / 10

  -- shuffle feel: approximate triplet swing on 16th grid
  -- strong on 1, 4, 5, 8, 9, 12, 13, 16 (swing 8ths)
  local swing_hits = {1, 4, 5, 8, 9, 12, 13, 16}
  local walk_offset = 0

  for _, pos in ipairs(swing_hits) do
    if math.random() < 0.65 + int * 0.3 then
      -- walking motion: move up or down by scale step
      if math.random() < 0.6 then
        walk_offset = walk_offset + ({-2, -1, 1, 2, 3, 5})[math.random(6)]
        walk_offset = util.clamp(walk_offset, -12, 12)
      end
      p[pos] = {
        offset = walk_offset,
        vel = (pos == 1 or pos == 9) and (0.85 + math.random() * 0.15) or (0.5 + math.random() * 0.35),
        gate = 0.35 + math.random() * 0.25,
      }
    end
  end

  -- always hit the 1
  p[1] = p[1] or {offset = 0, vel = 0.9, gate = 0.45}

  -- passing tones between swing hits at high intensity
  if int > 0.6 then
    for i = 1, 16 do
      if not p[i] and math.random() < (int - 0.5) * 0.2 then
        p[i] = {offset = walk_offset + ({-1, 1})[math.random(2)], vel = 0.3 + math.random() * 0.2, gate = 0.15}
      end
    end
  end

  return p
end

local function gen_halftime(intensity)
  local p = {}
  local int = intensity / 10

  -- very sparse: strong hit on 1 with long sustain
  p[1] = {offset = 0, vel = 1.0, gate = 0.9}

  -- maybe a second hit way later (feels like half-speed)
  if math.random() < 0.5 then
    p[9] = {offset = 0, vel = 0.8, gate = 0.8}
  end

  -- at higher intensity, one fill note near end
  if int > 0.5 and math.random() < 0.4 then
    local pos = ({13, 14, 15})[math.random(3)]
    p[pos] = {
      offset = pick_interval(8),
      vel = 0.5 + math.random() * 0.3,
      gate = 0.3,
    }
  end

  -- rare octave drop anticipation
  if math.random() < 0.25 then
    p[16] = {offset = -12, vel = 0.65, gate = 0.2}
  end

  return p
end

local function gen_latin(intensity)
  local p = {}
  local int = intensity / 10

  -- tumbao: the anticipated bass pattern
  -- classic feel: and-of-2 (step 5), beat 3 (step 9), and-of-4 (step 13)
  p[5] = {offset = pick_interval(9), vel = 0.8 + math.random() * 0.15, gate = 0.35}
  p[9] = {offset = 0, vel = 0.9 + math.random() * 0.1, gate = 0.4}
  p[13] = {offset = pick_interval(9), vel = 0.75 + math.random() * 0.2, gate = 0.3}

  -- anticipated downbeat (step 16 leads into next bar's 1)
  if math.random() < 0.65 then
    p[16] = {offset = 0, vel = 0.85, gate = 0.25}
  end

  -- beat 1 anchor (sometimes absent in tumbao for tension)
  if math.random() < 0.6 then
    p[1] = {offset = 0, vel = 0.85 + math.random() * 0.1, gate = 0.35}
  end

  -- chromatic approaches at higher intensity
  if int > 0.5 then
    if not p[4] and math.random() < 0.4 then
      p[4] = {offset = chromatic_approach(), vel = 0.4 + math.random() * 0.2, gate = 0.12}
    end
    if not p[12] and math.random() < 0.35 then
      p[12] = {offset = chromatic_approach(), vel = 0.4 + math.random() * 0.2, gate = 0.12}
    end
  end

  -- ghost notes for deeper groove
  if int > 0.6 then
    for i = 1, 16 do
      if not p[i] and math.random() < (int - 0.5) * 0.12 then
        p[i] = {offset = 0, vel = 0.12 + math.random() * 0.15, gate = 0.08}
      end
    end
  end

  return p
end

---------- PATTERN MANAGEMENT ----------

local generators = {gen_funk, gen_rock, gen_acid, gen_dub, gen_chaos, gen_hiphop, gen_shuffle, gen_halftime, gen_latin}

function b.generate_pattern()
  b.pattern = generators[b.style](b.intensity)
end

function b.mutate_pattern()
  local p = b.pattern
  for i = 1, 16 do
    if p[i] then
      -- small chance to remove
      if math.random() < 0.08 then
        p[i] = nil
      else
        -- velocity drift
        p[i].vel = util.clamp(p[i].vel + (math.random() - 0.5) * 0.12, 0.08, 1.0)
        -- occasional note swap
        if math.random() < 0.15 then
          p[i].offset = pick_interval(b.style)
        end
        -- gate variation
        if math.random() < 0.1 then
          p[i].gate = util.clamp(p[i].gate + (math.random() - 0.5) * 0.15, 0.04, 0.95)
        end
      end
    else
      -- small chance to add a note
      if math.random() < 0.06 then
        p[i] = {
          offset = pick_interval(b.style),
          vel = 0.25 + math.random() * 0.35,
          gate = 0.15 + math.random() * 0.25,
        }
      end
    end
  end
end

---------- TRANSPORT ----------

function b.advance()
  if not b.playing then return end

  b.step = b.step % 16 + 1

  -- release previous note
  if b.current_note and b.note_off_fn then
    b.note_off_fn(b.current_note)
    b.current_note = nil
  end

  local event = b.pattern[b.step]
  if event then
    -- breathing: skip notes when energy is low
    if b.breathing and b.energy < 1 then
      -- at energy 0: silence. at 0.5: skip ~50% of notes.
      -- always keep the 1 (step 1) longer than other notes
      local skip_chance = 1 - b.energy
      if b.step ~= 1 and math.random() < skip_chance then
        event = nil -- skip this note
      end
    end
  end
  if event then
    local note = b.root + event.offset
    note = util.clamp(note, 20, 96)
    -- energy scales velocity down during low moments
    local energy_scale = b.breathing and (0.3 + 0.7 * b.energy) or 1
    local vel = util.clamp(event.vel * (b.intensity / 10 + 0.4) * energy_scale, 0.08, 1.0)

    -- apply glide: respect mode's base glide + slide flag
    if event.slide then
      engine.glide(math.max(0.1, b.mode_glide * 1.5))
    else
      engine.glide(b.mode_glide)
    end

    if b.note_on_fn then
      b.note_on_fn(note, vel)
      b.current_note = note
    end

    -- schedule note off based on gate
    if event.gate < 0.9 then
      clock.run(function()
        clock.sync(event.gate * (1/4))
        if b.current_note == note and b.note_off_fn then
          b.note_off_fn(note)
          if b.current_note == note then b.current_note = nil end
        end
      end)
    end
  end

  -- end of bar: evolve + breathe
  if b.step == 16 then
    b.bar = b.bar + 1
    b.breath_bar = b.breath_bar + 1

    -- breathing: creates silent/low moments in the song
    if b.breathing then
      if b.breath_phase == "play" then
        -- playing normally. after 4-12 bars, maybe start fading
        if b.breath_bar > 4 and math.random() < 0.15 then
          b.breath_phase = "fade"
          b.breath_bar = 0
        end
      elseif b.breath_phase == "fade" then
        -- fading out over 2-4 bars
        b.energy = math.max(0, b.energy - (0.25 + math.random() * 0.2))
        if b.energy <= 0.05 then
          b.breath_phase = "silence"
          b.energy = 0
          b.breath_bar = 0
        end
      elseif b.breath_phase == "silence" then
        -- total silence for 1-4 bars
        b.energy = 0
        if b.breath_bar > 1 and math.random() < 0.4 then
          b.breath_phase = "build"
          b.breath_bar = 0
        end
      elseif b.breath_phase == "build" then
        -- building back up over 2-4 bars
        b.energy = math.min(1, b.energy + (0.2 + math.random() * 0.25))
        if b.energy >= 0.95 then
          b.breath_phase = "play"
          b.energy = 1
          b.breath_bar = 0
        end
      end
    end

    -- pattern evolution (skip if locked)
    if not b.locked then
      if b.favorites_mode and #b.favorites > 0 then
        -- scroll through saved favorites at phrase boundaries
        if b.bar % b.phrase_len == 0 then
          if b.favorites_order == "random" then
            b.favorites_idx = math.random(#b.favorites)
          else
            b.favorites_idx = (b.favorites_idx % #b.favorites) + 1
          end
          b.pattern = b.deep_copy_pattern(b.favorites[b.favorites_idx])
        end
      elseif b.bar % b.phrase_len == 0 then
        -- phrase boundary: bigger change
        if math.random() < 0.35 then
          b.generate_pattern()
        else
          b.mutate_pattern()
          b.mutate_pattern()
        end
      elseif b.bar % 2 == 0 then
        -- every 2 bars: subtle mutation
        b.mutate_pattern()
      end
    end
  end
end

function b.start()
  if b.clock_id then return end
  b.playing = true
  b.step = 0
  b.bar = 0
  b.generate_pattern()
  b.clock_id = clock.run(function()
    while b.playing do
      clock.sync(1/4) -- 16th note
      b.advance()
    end
  end)
end

function b.stop()
  b.playing = false
  if b.clock_id then
    clock.cancel(b.clock_id)
    b.clock_id = nil
  end
  if b.current_note and b.note_off_fn then
    b.note_off_fn(b.current_note)
    b.current_note = nil
  end
end

---------- CONFIG ----------

function b.set_style(style_num)
  b.style = util.clamp(style_num, 1, #b.STYLE_NAMES)
  b.generate_pattern()
end

function b.set_scale(root, scale_name)
  b.root = root
  b.scale_notes = musicutil.generate_scale(root - 12, scale_name, 3)
end

function b.init(note_on_fn, note_off_fn, root, scale_name)
  b.note_on_fn = note_on_fn
  b.note_off_fn = note_off_fn
  b.root = root or 36
  b.set_scale(b.root, scale_name or "Minor Pentatonic")
  b.generate_pattern()
end

---------- PATTERN PERSISTENCE ----------

function b.deep_copy_pattern(src)
  local dst = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = {}
      for kk, vv in pairs(v) do dst[k][kk] = vv end
    else
      dst[k] = v
    end
  end
  return dst
end

function b.save_pattern(slot, data_dir)
  if not data_dir then return end
  local path = data_dir .. "patterns/"
  util.make_dir(path)
  -- serialize pattern as a flat string we can reload
  local f = io.open(path .. string.format("slot_%02d.dat", slot), "w")
  if not f then return end
  for step = 1, 16 do
    local e = b.pattern[step]
    if e then
      f:write(string.format("%d,%f,%f,%f,%s\n",
        step, e.offset or 0, e.vel or 0.5, e.gate or 0.3, e.slide and "1" or "0"))
    end
  end
  f:close()
end

function b.load_pattern(slot, data_dir)
  if not data_dir then return nil end
  local path = data_dir .. "patterns/" .. string.format("slot_%02d.dat", slot)
  local f = io.open(path, "r")
  if not f then return nil end
  local p = {}
  for line in f:lines() do
    local step, offset, vel, gate, slide = line:match("(%d+),([%-%.%d]+),([%.%d]+),([%.%d]+),(%d)")
    if step then
      p[tonumber(step)] = {
        offset = tonumber(offset),
        vel = tonumber(vel),
        gate = tonumber(gate),
        slide = slide == "1",
      }
    end
  end
  f:close()
  return p
end

function b.load_all_favorites(data_dir)
  b.favorites = {}
  if not data_dir then return end
  for slot = 1, 32 do
    local p = b.load_pattern(slot, data_dir)
    if p and next(p) then
      table.insert(b.favorites, p)
    end
  end
end

function b.save_to_next_slot(data_dir)
  if not data_dir then return 0 end
  -- find next empty slot
  for slot = 1, 32 do
    local path = data_dir .. "patterns/" .. string.format("slot_%02d.dat", slot)
    local f = io.open(path, "r")
    if f then
      f:close()
    else
      b.save_pattern(slot, data_dir)
      -- add to favorites
      table.insert(b.favorites, b.deep_copy_pattern(b.pattern))
      return slot
    end
  end
  -- all full, overwrite slot 32
  b.save_pattern(32, data_dir)
  return 32
end

function b.toggle_lock()
  b.locked = not b.locked
  return b.locked
end

return b
