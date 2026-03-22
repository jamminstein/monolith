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

b.STYLE_NAMES = {"FUNK", "ROCK", "ACID", "DUB", "CHAOS"}

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

---------- PATTERN MANAGEMENT ----------

local generators = {gen_funk, gen_rock, gen_acid, gen_dub, gen_chaos}

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
    local note = b.root + event.offset
    note = util.clamp(note, 20, 96)
    local vel = util.clamp(event.vel * (b.intensity / 10 + 0.4), 0.08, 1.0)

    -- apply slide: set glide before note
    if event.slide then
      engine.glide(0.12)
    else
      engine.glide(0)
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

  -- end of bar: evolve
  if b.step == 16 then
    b.bar = b.bar + 1
    if b.bar % b.phrase_len == 0 then
      -- phrase boundary: bigger change
      if math.random() < 0.35 then
        b.generate_pattern()
      else
        b.mutate_pattern()
        b.mutate_pattern() -- double mutation for more change
      end
    elseif b.bar % 2 == 0 then
      -- every 2 bars: subtle mutation
      b.mutate_pattern()
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
  b.style = util.clamp(style_num, 1, 5)
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

return b
