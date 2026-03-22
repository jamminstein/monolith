-- monolith
-- brutal bass instrument
--
-- 6 voice modes of destruction
-- bandmate generative engine
-- compressor built in
--
-- ENC1: voice mode
-- ENC2: macro morph
-- ENC3: filter cutoff
-- KEY2: cycle voice mode
-- KEY3: toggle bandmate
-- MIDI: play + CC control
--
-- v1.0 @jamminstein

engine.name = "MollyThePoly"

local MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
local musicutil = require "musicutil"
local bandmate = include("lib/bandmate")

---------- CONSTANTS ----------

local MODE_NAMES = {
  "SUB DESTROY",
  "FUNK STAB",
  "ACID MORPH",
  "DIST WALL",
  "VOWEL BOT",
  "GNARLY",
}
local NUM_MODES = 6
local SCALE_NAMES = {
  "Minor Pentatonic", "Dorian", "Chromatic",
  "Minor", "Phrygian", "Mixolydian",
}
local ACT_LEN = 128

---------- STATE ----------

local voice_mode = 1
local macro = 0.5
local filter_base = 800
local root_note = 36
local scale_type = 1
local bandmate_active = false

local activity = {}
for i = 1, ACT_LEN do activity[i] = {vel = 0, age = 0} end
local act_head = 1
local current_notes = {}
local last_note = 0
local last_vel = 0

local midi_in_device
local midi_out_device
local midi_in_channel = 1
local midi_out_channel = 1
local screen_metro

---------- VOICE MODES ----------
-- each mode: base engine params, macro morph targets (lo/hi),
-- compressor settings

local MODES = {
  ---- 1: SUB DESTROYER ----
  -- earthquake bass. room-shaking sub. pulse wave + maxed sub osc.
  -- macro: pure sub -> growling overtones
  {
    base = {
      oscWaveShape = 2, pwMod = 0.05,
      mainOscLevel = 0.85, subOscLevel = 1.0,
      subOscDetune = 0, noiseLevel = 0,
      hpFilterCutoff = 10,
      lpFilterCutoff = 300, lpFilterResonance = 0.15,
      lpFilterType = 1, lpFilterCutoffModEnv = 0.2,
      lpFilterCutoffModLfo = 0, lpFilterTracking = 1,
      env1Attack = 0.02, env1Decay = 0.5,
      env1Sustain = 0.8, env1Release = 0.4,
      env2Attack = 0.01, env2Decay = 0.3,
      env2Sustain = 0.9, env2Release = 0.5,
      chorusMix = 0, ringModMix = 0, ringModFreq = 50,
      amp = 8, glide = 0.08,
      lfoFreq = 0.5, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      lpFilterCutoff = {300, 2200},
      lpFilterResonance = {0.15, 0.7},
      ringModMix = {0, 0.45},
      noiseLevel = {0, 0.18},
      chorusMix = {0, 0.35},
      subOscDetune = {0, 0.3},
    },
  },

  ---- 2: STACCATO FUNK ----
  -- bootsy collins space bass. tight envelope, wah-like filter.
  -- macro: tight/punchy -> loose/wah
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 0.85, subOscLevel = 0.5,
      subOscDetune = 0, noiseLevel = 0,
      hpFilterCutoff = 10,
      lpFilterCutoff = 600, lpFilterResonance = 0.35,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.6,
      lpFilterCutoffModLfo = 0, lpFilterTracking = 1.2,
      env1Attack = 0.002, env1Decay = 0.15,
      env1Sustain = 0.2, env1Release = 0.08,
      env2Attack = 0.002, env2Decay = 0.2,
      env2Sustain = 0.3, env2Release = 0.1,
      chorusMix = 0.2, ringModMix = 0, ringModFreq = 50,
      amp = 7.5, glide = 0,
      lfoFreq = 1, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      env1Decay = {0.15, 0.55},
      env1Sustain = {0.2, 0.65},
      env2Decay = {0.2, 0.5},
      lpFilterCutoffModEnv = {0.6, 0.9},
      lpFilterResonance = {0.35, 0.65},
      chorusMix = {0.2, 0.55},
      subOscLevel = {0.5, 0.8},
    },
  },

  ---- 3: ACID MORPH ----
  -- 303 on steroids. squelch, scream, slide.
  -- macro: mellow acid -> full scream
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 0.9, subOscLevel = 0.3,
      subOscDetune = 0, noiseLevel = 0,
      hpFilterCutoff = 10,
      lpFilterCutoff = 200, lpFilterResonance = 0.75,
      lpFilterType = 1, lpFilterCutoffModEnv = 0.85,
      lpFilterCutoffModLfo = 0, lpFilterTracking = 0.8,
      env1Attack = 0.002, env1Decay = 0.3,
      env1Sustain = 0.05, env1Release = 0.12,
      env2Attack = 0.002, env2Decay = 0.4,
      env2Sustain = 0.1, env2Release = 0.15,
      chorusMix = 0, ringModMix = 0, ringModFreq = 50,
      amp = 7.5, glide = 0.15,
      lfoFreq = 0.5, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      lpFilterResonance = {0.75, 0.95},
      lpFilterCutoffModEnv = {0.85, 1.0},
      lpFilterCutoff = {200, 900},
      env1Decay = {0.3, 0.8},
      glide = {0.15, 0.4},
      subOscLevel = {0.3, 0.6},
    },
  },

  ---- 4: DISTORT WALL ----
  -- LCD soundsystem drop. chorused, thick, overwhelming.
  -- macro: clean thick -> ring-mod chaos
  {
    base = {
      oscWaveShape = 2, pwMod = 0.45,
      mainOscLevel = 0.85, subOscLevel = 0.7,
      subOscDetune = 0.08, noiseLevel = 0.12,
      hpFilterCutoff = 10,
      lpFilterCutoff = 1500, lpFilterResonance = 0.4,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.2,
      lpFilterCutoffModLfo = 0.15, lpFilterTracking = 1,
      env1Attack = 0.01, env1Decay = 0.4,
      env1Sustain = 0.7, env1Release = 0.5,
      env2Attack = 0.005, env2Decay = 0.3,
      env2Sustain = 0.8, env2Release = 0.6,
      chorusMix = 0.85, ringModMix = 0.25, ringModFreq = 80,
      amp = 7, glide = 0.02,
      lfoFreq = 3, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      ringModMix = {0.25, 0.85},
      chorusMix = {0.85, 1.0},
      noiseLevel = {0.12, 0.5},
      pwMod = {0.45, 0.85},
      lpFilterResonance = {0.4, 0.75},
      ampMod = {0, 0.35},
      freqModLfo = {0, 0.04},
    },
  },

  ---- 5: VOWEL MACHINE ----
  -- vocoder robot bass. formant-like ring mod sweeps.
  -- macro: dark vowel -> bright vowel sweep
  {
    base = {
      oscWaveShape = 2, pwMod = 0.5,
      mainOscLevel = 0.8, subOscLevel = 0.5,
      subOscDetune = 0, noiseLevel = 0.08,
      hpFilterCutoff = 10,
      lpFilterCutoff = 800, lpFilterResonance = 0.6,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.1,
      lpFilterCutoffModLfo = 0.5, lpFilterTracking = 1,
      env1Attack = 0.05, env1Decay = 0.3,
      env1Sustain = 0.6, env1Release = 0.3,
      env2Attack = 0.02, env2Decay = 0.25,
      env2Sustain = 0.7, env2Release = 0.4,
      chorusMix = 0.3, ringModMix = 0.5, ringModFreq = 150,
      amp = 7, glide = 0.05,
      lfoFreq = 2.5, lfoWaveShape = 0,
      ampMod = 0.15, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      ringModFreq = {60, 295},
      lpFilterCutoff = {400, 2500},
      lpFilterCutoffModLfo = {0.5, 0.9},
      lfoFreq = {1.0, 9.0},
      pwMod = {0.5, 0.9},
      ringModMix = {0.5, 0.85},
      noiseLevel = {0.08, 0.25},
    },
  },

  ---- 6: GNARLY GROWL ----
  -- maximum aggression. detuned, modulated, distorted.
  -- macro: rumble -> total shred
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 1.0, subOscLevel = 0.8,
      subOscDetune = 0.5, noiseLevel = 0.18,
      hpFilterCutoff = 10,
      lpFilterCutoff = 1000, lpFilterResonance = 0.65,
      lpFilterType = 1, lpFilterCutoffModEnv = 0.5,
      lpFilterCutoffModLfo = 0.3, lpFilterTracking = 1,
      env1Attack = 0.002, env1Decay = 0.2,
      env1Sustain = 0.5, env1Release = 0.2,
      env2Attack = 0.002, env2Decay = 0.15,
      env2Sustain = 0.6, env2Release = 0.25,
      chorusMix = 0.5, ringModMix = 0.35, ringModFreq = 55,
      amp = 8, glide = 0.03,
      lfoFreq = 6, lfoWaveShape = 2,
      ampMod = 0.2, freqModLfo = 0.04, freqModEnv = 0.08,
    },
    macro_targets = {
      lpFilterResonance = {0.65, 0.92},
      ringModMix = {0.35, 0.9},
      noiseLevel = {0.18, 0.6},
      freqModLfo = {0.04, 0.15},
      ampMod = {0.2, 0.55},
      chorusMix = {0.5, 1.0},
      lpFilterCutoffModLfo = {0.3, 0.75},
      subOscDetune = {0.5, 2.0},
      freqModEnv = {0.08, 0.3},
    },
  },
}

---------- ENGINE HELPERS ----------

local function apply_engine_params(p)
  for name, val in pairs(p) do
    if engine[name] then
      engine[name](val)
    end
  end
end

local function apply_macro_val(val)
  macro = util.clamp(val, 0, 1)
  local mode = MODES[voice_mode]
  if not mode or not mode.macro_targets then return end
  for name, range in pairs(mode.macro_targets) do
    local lo, hi = range[1], range[2]
    local v = lo + (hi - lo) * macro
    if engine[name] then
      engine[name](v)
    end
  end
end

local function apply_voice(mode_num)
  voice_mode = util.clamp(mode_num, 1, NUM_MODES)
  local mode = MODES[voice_mode]
  apply_engine_params(mode.base)
  apply_macro_val(macro)
end

---------- NOTE HANDLING ----------

local function note_on(note, vel)
  local freq = musicutil.note_num_to_freq(note)
  engine.noteOn(note, freq, vel)
  current_notes[note] = vel
  last_note = note
  last_vel = vel
  -- seismograph
  activity[act_head] = {vel = vel, age = 0}
  act_head = act_head % ACT_LEN + 1
  -- midi out
  if midi_out_device and params:get("midi_out") == 2 then
    midi_out_device:note_on(note, math.floor(vel * 127), midi_out_channel)
  end
end

local function note_off(note)
  engine.noteOff(note)
  current_notes[note] = nil
  if midi_out_device and params:get("midi_out") == 2 then
    midi_out_device:note_off(note, 0, midi_out_channel)
  end
end

local function all_notes_off()
  engine.noteOffAll()
  for k, _ in pairs(current_notes) do
    if midi_out_device and params:get("midi_out") == 2 then
      midi_out_device:note_off(k, 0, midi_out_channel)
    end
  end
  current_notes = {}
end

---------- MIDI ----------

local function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.ch ~= midi_in_channel then return end

  if msg.type == "note_on" and msg.vel > 0 then
    note_on(msg.note, msg.vel / 127)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    note_off(msg.note)
  elseif msg.type == "cc" then
    if msg.cc == 1 then
      -- mod wheel -> macro
      params:set("macro", msg.val / 127)
    elseif msg.cc == 74 then
      -- filter cutoff
      filter_base = util.linexp(0, 127, 20, 18000, msg.val)
      engine.lpFilterCutoff(filter_base)
    elseif msg.cc == 2 then
      -- breath -> intensity (bandmate)
      params:set("bm_intensity", math.floor(msg.val / 127 * 9) + 1)
    end
  elseif msg.type == "pitchbend" then
    local bend = (msg.val - 8192) / 8192
    engine.pitchBendAll(math.pow(2, bend * 2 / 12))
  end
end

---------- INIT ----------

function init()
  -- engine params (under the hood)
  MollyThePoly.add_params()

  -- monolith params
  params:add_separator("MONOLITH")

  params:add_option("voice_mode", "voice mode", MODE_NAMES, 1)
  params:set_action("voice_mode", function(val)
    apply_voice(val)
  end)

  params:add_control("macro", "macro",
    controlspec.new(0, 1, 'lin', 0.01, 0.5))
  params:set_action("macro", function(val)
    apply_macro_val(val)
  end)

  params:add_control("filter_cutoff", "filter cutoff",
    controlspec.new(20, 18000, 'exp', 0, 800, "hz"))
  params:set_action("filter_cutoff", function(val)
    filter_base = val
    engine.lpFilterCutoff(val)
  end)

  -- bandmate
  params:add_separator("BANDMATE")

  params:add_option("bandmate_on", "bandmate", {"off", "on"}, 1)
  params:set_action("bandmate_on", function(val)
    bandmate_active = val == 2
    if bandmate_active then
      bandmate.start()
    else
      bandmate.stop()
    end
  end)

  params:add_option("bm_style", "style", bandmate.STYLE_NAMES, 1)
  params:set_action("bm_style", function(val) bandmate.set_style(val) end)

  params:add_number("bm_intensity", "intensity", 1, 10, 5)
  params:set_action("bm_intensity", function(val) bandmate.intensity = val end)

  params:add_number("bm_phrase", "phrase length", 2, 16, 4)
  params:set_action("bm_phrase", function(val) bandmate.phrase_len = val end)

  -- music
  params:add_separator("MUSIC")

  params:add_number("root_note", "root note", 24, 48, 36)
  params:set_action("root_note", function(val)
    root_note = val
    bandmate.root = val
    bandmate.set_scale(val, SCALE_NAMES[scale_type])
  end)

  params:add_option("scale_type", "scale", SCALE_NAMES, 1)
  params:set_action("scale_type", function(val)
    scale_type = val
    bandmate.set_scale(root_note, SCALE_NAMES[val])
  end)

  -- midi
  params:add_separator("MIDI")

  params:add_number("midi_in_dev", "midi in device", 1, 16, 1)
  params:set_action("midi_in_dev", function(val)
    if midi_in_device then midi_in_device.event = nil end
    midi_in_device = midi.connect(val)
    midi_in_device.event = midi_event
  end)

  params:add_number("midi_in_ch", "midi in ch", 1, 16, 1)
  params:set_action("midi_in_ch", function(val) midi_in_channel = val end)

  params:add_option("midi_out", "midi out", {"off", "on"}, 1)

  params:add_number("midi_out_dev", "midi out device", 1, 16, 2)
  params:set_action("midi_out_dev", function(val)
    midi_out_device = midi.connect(val)
  end)

  params:add_number("midi_out_ch", "midi out ch", 1, 16, 1)
  params:set_action("midi_out_ch", function(val) midi_out_channel = val end)

  -- compressor
  params:add_separator("COMPRESSOR")
  params:add_option("comp_on", "compressor", {"off", "on"}, 2)
  params:set_action("comp_on", function(val)
    if val == 2 then
      pcall(audio.comp_on)
    else
      pcall(audio.comp_off)
    end
  end)

  -- init hardware
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
  midi_out_device = midi.connect(2)

  -- init bandmate
  bandmate.init(note_on, note_off, root_note, SCALE_NAMES[scale_type])

  -- compressor: on by default, use LEVELS menu to fine-tune
  pcall(audio.comp_on)

  -- apply first voice mode after engine loads
  clock.run(function()
    clock.sleep(0.5)
    apply_voice(1)
  end)

  -- screen metro
  screen_metro = metro.init()
  screen_metro.time = 1 / 15
  screen_metro.event = function()
    -- decay activity
    for i = 1, ACT_LEN do
      if activity[i].vel > 0 then
        activity[i].age = activity[i].age + 1
        if activity[i].age > 15 then
          activity[i].vel = activity[i].vel * 0.93
          if activity[i].vel < 0.02 then activity[i].vel = 0 end
        end
      end
    end
    redraw()
  end
  screen_metro:start()
end

---------- INPUT ----------

function enc(n, d)
  if n == 1 then
    local new_mode = util.clamp(voice_mode + d, 1, NUM_MODES)
    if new_mode ~= voice_mode then
      params:set("voice_mode", new_mode)
    end
  elseif n == 2 then
    params:set("macro", util.clamp(macro + d * 0.02, 0, 1))
  elseif n == 3 then
    local mult = d > 0 and 1.06 or (1 / 1.06)
    params:set("filter_cutoff", util.clamp(filter_base * mult, 20, 18000))
  end
end

function key(n, z)
  if n == 2 and z == 1 then
    params:set("voice_mode", voice_mode % NUM_MODES + 1)
  elseif n == 3 and z == 1 then
    params:set("bandmate_on", bandmate_active and 1 or 2)
  end
end

---------- SCREEN ----------

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  -- title
  screen.level(3)
  screen.move(2, 7)
  screen.text("MONOLITH")

  -- mode dots
  for i = 1, NUM_MODES do
    local lvl = i == voice_mode and 15 or 2
    screen.level(lvl)
    screen.rect(88 + (i - 1) * 7, 2, 4, 4)
    screen.fill()
  end

  -- mode name
  screen.level(15)
  screen.move(2, 18)
  screen.text(MODE_NAMES[voice_mode])

  -- separator
  screen.level(3)
  screen.move(0, 21)
  screen.line(128, 21)
  screen.stroke()

  -- seismograph: activity display
  local viz_base = 42
  local viz_h = 18
  for i = 1, ACT_LEN do
    local idx = ((act_head - 2 + i) % ACT_LEN) + 1
    local v = activity[idx].vel
    if v > 0.01 then
      local fade = math.max(0.15, 1 - activity[idx].age / 50)
      local brightness = math.max(1, math.floor(15 * v * fade))
      screen.level(brightness)
      local bar_h = math.floor(v * viz_h)
      -- draw from baseline up and down for stereo feel
      local half = math.floor(bar_h / 2)
      screen.move(i, viz_base - half)
      screen.line(i, viz_base + half)
      screen.stroke()
    end
  end

  -- bandmate step indicator
  if bandmate_active and bandmate.playing then
    local step_x = math.floor((bandmate.step - 1) * 8) + 4
    screen.level(12)
    screen.rect(step_x, viz_base + 1, 3, 2)
    screen.fill()
  end

  -- separator
  screen.level(2)
  screen.move(0, 48)
  screen.line(128, 48)
  screen.stroke()

  -- status bar
  screen.font_size(8)

  -- root note
  screen.level(10)
  screen.move(2, 58)
  screen.text(musicutil.note_num_to_name(root_note, true))

  -- macro bar
  screen.level(3)
  screen.rect(28, 51, 32, 5)
  screen.stroke()
  screen.level(11)
  screen.rect(28, 51, math.floor(32 * macro), 5)
  screen.fill()

  -- bandmate
  if bandmate_active then
    screen.level(15)
    screen.move(68, 58)
    screen.text(bandmate.STYLE_NAMES[bandmate.style])
  else
    screen.level(3)
    screen.move(68, 58)
    screen.text("--")
  end

  -- bpm
  screen.level(5)
  screen.move(104, 58)
  screen.text(math.floor(clock.get_tempo()))

  -- held note indicator (bright dot when note playing)
  local n_held = 0
  for _, _ in pairs(current_notes) do n_held = n_held + 1 end
  if n_held > 0 then
    screen.level(15)
    screen.rect(122, 2, 4, 4)
    screen.fill()
  end

  screen.update()
end

---------- CLEANUP ----------

function cleanup()
  all_notes_off()
  bandmate.stop()
  if screen_metro then screen_metro:stop() end
  pcall(audio.comp_off)
end
