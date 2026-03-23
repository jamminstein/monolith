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
  "TAPE SAT",
  "DOOM",
  "TALK BOX",
  "SYNTH POP",
  "RUBBER",
}
local NUM_MODES = 11
local SCALE_NAMES = {
  "Minor Pentatonic", "Dorian", "Chromatic",
  "Minor", "Phrygian", "Mixolydian",
  "Just Minor", "Arabic", "Slendro", "Hirajoshi",
}

---------- MICROTONAL ----------
-- scales defined in cents from root. standard 12-TET = nil (use musicutil)
-- microtonal scales bypass musicutil entirely
local MICRO_SCALES = {
  nil, nil, nil, nil, nil, nil, -- 1-6: standard scales, handled by musicutil

  -- 7: Just Intonation Minor (pure ratios, warmer than equal temperament)
  -- 1/1, 9/8, 6/5, 4/3, 3/2, 8/5, 9/5
  {0, 204, 316, 498, 702, 814, 1018},

  -- 8: Arabic Maqam Bayati (quarter-tone scale, haunting and exotic)
  -- root, 3/4tone, minor3, 4th, 5th, minor6, minor7
  {0, 150, 300, 500, 700, 800, 1000},

  -- 9: Gamelan Slendro (5-note, roughly equal ~240 cent spacing, meditative)
  {0, 240, 480, 720, 960},

  -- 10: Hirajoshi (Japanese, dark and beautiful)
  -- uses quarter-tone inflections on the 2nd and 5th
  {0, 200, 300, 700, 800},
}

-- convert a "virtual MIDI note" to frequency using microtonal scale
-- note_num is treated as: root + scale_degree (wrapping across octaves)
local function micro_to_freq(note_num, root, scale_cents)
  local degree = note_num - root
  local num_degrees = #scale_cents
  -- how many octaves up/down from root
  local octave = math.floor(degree / num_degrees)
  local idx = degree % num_degrees
  if idx < 0 then
    idx = idx + num_degrees
    octave = octave - 1
  end
  local root_freq = musicutil.note_num_to_freq(root)
  local cents = scale_cents[idx + 1] + (octave * 1200)
  return root_freq * (2 ^ (cents / 1200))
end

-- master freq function: handles both standard and microtonal
local function note_to_freq(note_num)
  local micro = MICRO_SCALES[scale_type]
  if micro then
    return micro_to_freq(note_num, root_note, micro)
  else
    return musicutil.note_num_to_freq(note_num)
  end
end

-- generate a scale as note numbers (works for both standard and microtonal)
-- for microtonal: returns sequential integers starting from root (each = one scale degree)
-- for standard: uses musicutil.generate_scale
local function gen_scale(root, octaves)
  local micro = MICRO_SCALES[scale_type]
  if micro then
    local notes = {}
    local degrees = #micro
    for oct = -1, octaves do
      for deg = 0, degrees - 1 do
        table.insert(notes, root + oct * degrees + deg)
      end
    end
    return notes
  else
    return musicutil.generate_scale(root, SCALE_NAMES[scale_type], octaves)
  end
end

-- how many notes per octave in current scale
local function notes_per_octave()
  local micro = MICRO_SCALES[scale_type]
  if micro then return #micro end
  local s = musicutil.generate_scale(0, SCALE_NAMES[scale_type], 1)
  return #s - 1 -- generate_scale includes the octave note
end
local ACT_LEN = 128

---------- STATE ----------

local voice_mode = 1
local macro = 0.5
local filter_base = 800
local root_note = 36
local scale_type = 1
local bandmate_active = false

-- morph state
local morph_active = false
local morph_mode_a = 1
local morph_mode_b = 5
local morph_rate = 4     -- index into MORPH_RATES
local morph_style = 1    -- 1=A/B, 2=drift, 3=random
local morph_blend = false -- false=hard cut, true=smooth
local morph_clock_id = nil
local morph_side = false  -- false=A, true=B
local morph_current = 1   -- current mode in drift/random
local MORPH_RATES = {1/16, 1/8, 1/4, 1/2, 1, 2, 4}
local MORPH_RATE_NAMES = {"1/16", "1/8", "1/4", "1/2", "1", "2", "4"}
local MORPH_STYLE_NAMES = {"A/B", "drift", "random"}

-- destroy state
local destroy = 0

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
local data_dir -- set in init()

-- snapshots
local snapshot_slots = {}
local SNAPSHOT_COUNT = 32

-- effects
local delay_on = false
local delay_time = 0.375
local delay_feedback = 0.45
local delay_level = 0.35
local harmonize_on = false
local harmonize_interval = 12 -- semitones (12=octave below by default)
local harmony_notes = {} -- track active harmony notes
local stutter_active = false
local stutter_clock_id = nil
local bass_drop_clock_id = nil

-- doubling
local doubling_mode = 1 -- 1=off, 2=oct below, 3=5th below, 4=oct+5th
local doubled_notes = {} -- [original_note] = {extra_ids}

-- arpeggiator
local arp_on = false
local arp_rate = 1
local arp_style = 1 -- 1=up, 2=down, 3=up-down, 4=random
local arp_range = 2
local arp_clock_id = nil
local arp_held_notes = {}
local arp_playing_note = nil
local arp_idx = 0
local arp_direction = 1
local ARP_RATES = {1/16, 1/8, 1/4, 1/2}
local ARP_RATE_NAMES = {"1/16", "1/8", "1/4", "1/2"}
local ARP_STYLE_NAMES = {"up", "down", "up-down", "random"}

-- chord progressions
local PROG_PRESETS = {
  {name = "I-IV-V-I", prog = {0, 5, 7, 0}},
  {name = "I-V-vi-IV", prog = {0, 7, 9, 5}},
  {name = "I-IV-I-V", prog = {0, 5, 0, 7}},
  {name = "12 bar blues", prog = {0,0,0,0, 5,5,0,0, 7,5,0,0}},
  {name = "i-iv-v", prog = {0, 5, 7}},
  {name = "i-VII-VI-v", prog = {0, 10, 8, 7}},
}
local PROG_NAMES = {}
for _, p in ipairs(PROG_PRESETS) do table.insert(PROG_NAMES, p.name) end

-- scale palettes: each scene has a home scale + related scales for form phases
-- index into SCALE_NAMES: 1=MinPent, 2=Dorian, 3=Chromatic, 4=Minor, 5=Phrygian, 6=Mixolydian
local SCALE_PALETTES = {
  nil, -- (none)
  -- HIT: minor home, dorian for departure (brighter), phrygian for grow (darker)
  {home = 4, depart = 2, grow = 5, silence = 4},
  -- SYNCOP: min pent home, dorian departure (funkier), mixolydian grow (bluesy)
  {home = 1, depart = 2, grow = 6, silence = 1},
  -- CLUB: dorian home (sweet), minor departure (emotional), mixolydian grow (euphoric)
  {home = 2, depart = 4, grow = 6, silence = 2},
  -- MINIMAL: min pent home, dorian departure (subtle shift), minor grow
  {home = 1, depart = 2, grow = 4, silence = 1},
  -- HEAVY: phrygian home (dark), minor departure, chromatic grow (dissonant build)
  {home = 5, depart = 4, grow = 3, silence = 5},
  -- WEIRD: min pent home, arabic departure (exotic), just minor grow (warm), slendro silence (alien)
  {home = 1, depart = 8, grow = 7, silence = 9},
}
local active_palette = nil  -- set when a scene is applied
local last_form_phase = nil -- track phase changes for scale shifts

-- scenes: full instrument presets that configure everything at once
local SCENE_NAMES = {"(none)", "HIT", "SYNCOP", "CLUB", "MINIMAL", "HEAVY", "WEIRD"}
local SCENES = {
  -- 1: (none) = do nothing
  nil,
  -- 2: HIT — iconic crowd-moving lines. steady, simple, powerful.
  {
    voice_mode = 1, macro = 0.3, destroy = 0,
    bm_style = 2, bm_intensity = 5, bm_swing = 0, bm_phrase = 16,
    bandmate_on = 2, doubling = 2, -- oct below
    delay_on = 1, harmonize_on = 1,
    rev_level = 0.1, rev_size = 1.5, rev_damp = 4000, -- tight room
    bm_prog_mode = 1, bm_lock = 1,
    bm_form = 2, bm_form_type = 1, -- A-B-A form
    scale_type = 4, -- minor
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
  -- 3: SYNCOP — ultra locked groove for drummers. tight, funky, controlled.
  {
    voice_mode = 2, macro = 0.35, destroy = 0,
    bm_style = 1, bm_intensity = 6, bm_swing = 0.35, bm_phrase = 16,
    bandmate_on = 2, doubling = 1,
    delay_on = 1, harmonize_on = 1,
    rev_level = 0.05, rev_size = 0.8, rev_damp = 3000, -- dry and tight
    bm_prog_mode = 1, bm_lock = 1,
    bm_form = 2, bm_form_type = 3, -- call-response
    scale_type = 1, -- minor pentatonic
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
  -- 4: CLUB — dance, sweet, structured. predictable changes, steady groove.
  {
    voice_mode = 10, macro = 0.4, destroy = 0,
    bm_style = 7, bm_intensity = 4, bm_swing = 0.15, bm_phrase = 16,
    bandmate_on = 2, doubling = 1,
    delay_on = 2, delay_feedback = 0.35, delay_level = 0.25,
    harmonize_on = 1,
    rev_level = 0.3, rev_size = 5, rev_damp = 8000, -- spacious club
    bm_prog_mode = 2, bm_prog_type = 2, bm_prog_rate = 8,
    scale_type = 2, bm_lock = 1, -- dorian for club
    bm_form = 2, bm_form_type = 5, -- arc form
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
  -- 5: MINIMAL — stripped, hypnotic. locked pattern, very slow evolution.
  {
    voice_mode = 3, macro = 0.25, destroy = 0,
    bm_style = 4, bm_intensity = 3, bm_swing = 0, bm_phrase = 16,
    bandmate_on = 2, doubling = 1,
    delay_on = 2, delay_feedback = 0.5, delay_level = 0.2,
    harmonize_on = 1,
    rev_level = 0.2, rev_size = 8, rev_damp = 5000, -- big empty space
    bm_prog_mode = 1, bm_lock = 1,
    bm_form = 2, bm_form_type = 1, -- A-B-A
    scale_type = 1,
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
  -- 6: HEAVY — maximum weight. steady crushing groove.
  {
    voice_mode = 8, macro = 0.4, destroy = 0.1,
    bm_style = 8, bm_intensity = 3, bm_swing = 0, bm_phrase = 16,
    bandmate_on = 2, doubling = 4, -- oct+5th
    delay_on = 1, harmonize_on = 1,
    rev_level = 0.08, rev_size = 2, rev_damp = 3500, -- tight, heavy room
    bm_prog_mode = 1, bm_lock = 1,
    bm_form = 2, bm_form_type = 2, -- build-drop
    scale_type = 5, -- phrygian
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
  -- 7: WEIRD — experimental but still musical. controlled chaos.
  {
    voice_mode = 9, macro = 0.5, destroy = 0.15,
    bm_style = 5, bm_intensity = 5, bm_swing = 0.2, bm_phrase = 8,
    bandmate_on = 2, doubling = 1,
    delay_on = 2, delay_feedback = 0.5, delay_level = 0.3,
    harmonize_on = 2, harmonize_int = 2,
    rev_level = 0.45, rev_size = 14, rev_damp = 12000, -- massive cathedral
    bm_prog_mode = 2, bm_prog_type = 6, bm_prog_rate = 8,
    scale_type = 1, bm_lock = 1,
    bm_form = 2, bm_form_type = 4, -- rondo
    stutter_enabled = 1, bass_drop_enabled = 1, time_warp_enabled = 1,
    morph_on = 1, arp_enabled = 1,
  },
}

local function apply_scene(idx)
  if idx <= 1 or not SCENES[idx] then return end
  local s = SCENES[idx]
  -- save scene values as anchors for conductor taming
  scene_anchors = {}
  for k, v in pairs(s) do
    scene_anchors[k] = v
    pcall(function() params:set(k, v) end)
  end
  -- activate scale palette for form-aware scale shifting
  active_palette = SCALE_PALETTES[idx]
  last_form_phase = nil
end

-- robot
local robot_personality = 1
local PERSONALITY_NAMES = {"chill", "aggressive", "chaotic"}

---------- CONDUCTOR ----------
-- coordinates robot, bandmate, form, breathing, morph, and personality
-- prevents systems from fighting each other
local conductor_clock_id = nil
local scene_anchors = nil  -- original scene param values for taming

local function start_conductor()
  if conductor_clock_id then return end
  conductor_clock_id = clock.run(function()
    while true do
      clock.sync(4) -- check every bar

      -- personality taming strength: how hard we pull back to musicality
      -- chill=strong pull, aggressive=moderate, chaotic=minimal
      local tame = ({0.25, 0.08, 0.02})[robot_personality] or 0.08

      -- FORM-AWARENESS: adjust params to match what the bandmate is doing
      if bandmate.form_enabled then
        local phase = bandmate.form_phase

        if phase == "silence" then
          -- quiet moment: pull down energy-related params
          local m = params:get("macro")
          if m > 0.15 then params:set("macro", m * 0.85) end
          local d = params:get("destroy")
          if d > 0.03 then params:set("destroy", d * 0.7) end
          local rl = params:get("rev_level")
          if rl > 0.1 then params:set("rev_level", rl * 0.9) end

        elseif phase == "home" then
          -- home theme: stabilize toward scene anchors
          if scene_anchors then
            for _, name in ipairs({"macro", "destroy", "rev_level",
                                    "bm_swing"}) do
              if scene_anchors[name] then
                local cur = params:get(name)
                local target = scene_anchors[name]
                params:set(name, cur + (target - cur) * tame)
              end
            end
          end

        elseif phase == "grow" then
          -- building: allow upward movement, nudge macro up
          local m = params:get("macro")
          if m < 0.65 then params:set("macro", m + 0.015) end

        elseif phase == "depart" then
          -- variation: allow more freedom but keep within bounds
          local d = params:get("destroy")
          if d > 0.6 then params:set("destroy", d * 0.92) end
        end
      end

      -- RING MOD / WAH TAMING: these are harsh, keep them musical
      -- robot can push ring_mod_mix up but conductor pulls it back gently
      local rm = params:get("ring_mod_mix") or 0
      if rm > 0.4 then
        -- ring mod above 0.4 gets harsh fast — pull back
        params:set("ring_mod_mix", rm - (rm - 0.4) * tame * 2)
      end
      local res = params:get("lp_filter_resonance") or 0
      if res > 0.65 then
        -- resonance above 0.65 = screaming wah — pull back
        params:set("lp_filter_resonance", res - (res - 0.65) * tame * 2)
      end

      -- GENERAL TAMING: prevent params from going to extremes
      local destroy = params:get("destroy")
      if destroy > 0.7 then
        params:set("destroy", destroy - (destroy - 0.7) * tame)
      end

      -- SCALE SHIFTING: change scale based on form phase
      if active_palette and bandmate.form_enabled then
        local phase = bandmate.form_phase
        if phase ~= last_form_phase then
          last_form_phase = phase
          local target_scale = active_palette[phase] or active_palette.home
          if target_scale and target_scale ~= scale_type then
            params:set("scale_type", target_scale)
          end
        end
      end

    end
  end)
end

local function stop_conductor()
  if conductor_clock_id then
    clock.cancel(conductor_clock_id)
    conductor_clock_id = nil
  end
end

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
  -- warm aggression. thick detuned saw, chorus over ring mod,
  -- 12dB filter for body, sine LFO for organic movement.
  -- macro: warm rumble -> saturated growl
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 0.9, subOscLevel = 0.95,
      subOscDetune = 0.2, noiseLevel = 0.06,
      hpFilterCutoff = 10,
      lpFilterCutoff = 900, lpFilterResonance = 0.45,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.55,
      lpFilterCutoffModLfo = 0.2, lpFilterTracking = 1.1,
      env1Attack = 0.008, env1Decay = 0.25,
      env1Sustain = 0.55, env1Release = 0.3,
      env2Attack = 0.005, env2Decay = 0.2,
      env2Sustain = 0.65, env2Release = 0.35,
      chorusMix = 0.7, ringModMix = 0.1, ringModFreq = 45,
      amp = 8, glide = 0.05,
      lfoFreq = 3.5, lfoWaveShape = 0,
      ampMod = 0.08, freqModLfo = 0.02, freqModEnv = 0.04,
    },
    macro_targets = {
      lpFilterResonance = {0.45, 0.78},
      ringModMix = {0.1, 0.55},
      noiseLevel = {0.06, 0.3},
      freqModLfo = {0.02, 0.08},
      ampMod = {0.08, 0.35},
      chorusMix = {0.7, 1.0},
      lpFilterCutoffModLfo = {0.2, 0.5},
      subOscDetune = {0.2, 0.8},
      lpFilterCutoffModEnv = {0.55, 0.85},
    },
  },

  ---- 7: TAPE SAT ----
  -- warm lo-fi cassette bass. gentle saturation, tape hiss, dark filter.
  -- macro: clean tape -> saturated wobble
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 0.85, subOscLevel = 0.7,
      subOscDetune = 0.05, noiseLevel = 0.04,
      hpFilterCutoff = 30,
      lpFilterCutoff = 1200, lpFilterResonance = 0.2,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.25,
      lpFilterCutoffModLfo = 0.08, lpFilterTracking = 1,
      env1Attack = 0.015, env1Decay = 0.35,
      env1Sustain = 0.6, env1Release = 0.4,
      env2Attack = 0.01, env2Decay = 0.3,
      env2Sustain = 0.7, env2Release = 0.45,
      chorusMix = 0.4, ringModMix = 0.12, ringModFreq = 40,
      amp = 7, glide = 0.04,
      lfoFreq = 0.8, lfoWaveShape = 0,
      ampMod = 0.03, freqModLfo = 0.01, freqModEnv = 0,
    },
    macro_targets = {
      ringModMix = {0.12, 0.5},
      noiseLevel = {0.04, 0.25},
      lpFilterCutoff = {1200, 600},
      lpFilterResonance = {0.2, 0.5},
      freqModLfo = {0.01, 0.06},
      chorusMix = {0.4, 0.7},
      ampMod = {0.03, 0.15},
    },
  },

  ---- 8: DOOM ----
  -- ultra heavy ultra slow. monolithic sustain, earthquake sub.
  -- macro: heavy -> apocalyptic
  {
    base = {
      oscWaveShape = 2, pwMod = 0.1,
      mainOscLevel = 0.9, subOscLevel = 1.0,
      subOscDetune = 0.15, noiseLevel = 0.03,
      hpFilterCutoff = 10,
      lpFilterCutoff = 500, lpFilterResonance = 0.3,
      lpFilterType = 1, lpFilterCutoffModEnv = 0.15,
      lpFilterCutoffModLfo = 0.05, lpFilterTracking = 0.8,
      env1Attack = 0.05, env1Decay = 1.0,
      env1Sustain = 0.85, env1Release = 1.5,
      env2Attack = 0.03, env2Decay = 0.8,
      env2Sustain = 0.9, env2Release = 2.0,
      chorusMix = 0.6, ringModMix = 0.05, ringModFreq = 30,
      amp = 9, glide = 0.2,
      lfoFreq = 0.3, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      lpFilterCutoff = {500, 1800},
      lpFilterResonance = {0.3, 0.7},
      subOscDetune = {0.15, 1.0},
      noiseLevel = {0.03, 0.3},
      ringModMix = {0.05, 0.4},
      chorusMix = {0.6, 1.0},
      freqModLfo = {0, 0.05},
    },
  },

  ---- 9: TALK BOX ----
  -- extreme formant sweeps. zapp, roger troutman, robot voice.
  -- macro: slow talk -> fast babble
  {
    base = {
      oscWaveShape = 2, pwMod = 0.6,
      mainOscLevel = 0.8, subOscLevel = 0.4,
      subOscDetune = 0, noiseLevel = 0.05,
      hpFilterCutoff = 10,
      lpFilterCutoff = 1000, lpFilterResonance = 0.65,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.15,
      lpFilterCutoffModLfo = 0.6, lpFilterTracking = 1.2,
      env1Attack = 0.02, env1Decay = 0.3,
      env1Sustain = 0.7, env1Release = 0.3,
      env2Attack = 0.01, env2Decay = 0.25,
      env2Sustain = 0.75, env2Release = 0.35,
      chorusMix = 0.2, ringModMix = 0.55, ringModFreq = 180,
      amp = 7, glide = 0.06,
      lfoFreq = 2.5, lfoWaveShape = 0,
      ampMod = 0.05, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      lfoFreq = {2.5, 12},
      ringModFreq = {180, 295},
      ringModMix = {0.55, 0.85},
      lpFilterResonance = {0.65, 0.85},
      lpFilterCutoffModLfo = {0.6, 0.95},
      pwMod = {0.6, 0.9},
      noiseLevel = {0.05, 0.2},
    },
  },

  ---- 10: SYNTH POP ----
  -- bright bouncy new order / depeche mode bass.
  -- macro: clean pop -> acid pop
  {
    base = {
      oscWaveShape = 1, pwMod = 0,
      mainOscLevel = 0.85, subOscLevel = 0.3,
      subOscDetune = 0, noiseLevel = 0,
      hpFilterCutoff = 30,
      lpFilterCutoff = 2500, lpFilterResonance = 0.2,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.4,
      lpFilterCutoffModLfo = 0, lpFilterTracking = 1.3,
      env1Attack = 0.002, env1Decay = 0.2,
      env1Sustain = 0.35, env1Release = 0.15,
      env2Attack = 0.002, env2Decay = 0.25,
      env2Sustain = 0.4, env2Release = 0.2,
      chorusMix = 0.5, ringModMix = 0, ringModFreq = 50,
      amp = 6.5, glide = 0,
      lfoFreq = 1, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0,
    },
    macro_targets = {
      lpFilterResonance = {0.2, 0.6},
      lpFilterCutoffModEnv = {0.4, 0.8},
      chorusMix = {0.5, 0.85},
      subOscLevel = {0.3, 0.65},
      ringModMix = {0, 0.2},
      env1Decay = {0.2, 0.5},
    },
  },

  ---- 11: RUBBER ----
  -- elastic cartoon bass. bouncy pitch bends, playful.
  -- macro: subtle bounce -> extreme elastic
  {
    base = {
      oscWaveShape = 0, pwMod = 0,
      mainOscLevel = 0.85, subOscLevel = 0.6,
      subOscDetune = 0, noiseLevel = 0,
      hpFilterCutoff = 10,
      lpFilterCutoff = 1800, lpFilterResonance = 0.25,
      lpFilterType = 0, lpFilterCutoffModEnv = 0.3,
      lpFilterCutoffModLfo = 0, lpFilterTracking = 1,
      env1Attack = 0.002, env1Decay = 0.12,
      env1Sustain = 0.15, env1Release = 0.1,
      env2Attack = 0.002, env2Decay = 0.15,
      env2Sustain = 0.2, env2Release = 0.12,
      chorusMix = 0.3, ringModMix = 0, ringModFreq = 50,
      amp = 7, glide = 0.18,
      lfoFreq = 2, lfoWaveShape = 0,
      ampMod = 0, freqModLfo = 0, freqModEnv = 0.25,
    },
    macro_targets = {
      freqModEnv = {0.25, 0.7},
      glide = {0.18, 0.5},
      lpFilterCutoff = {1800, 3000},
      env1Decay = {0.12, 0.05},
      chorusMix = {0.3, 0.6},
      subOscLevel = {0.6, 0.9},
      lpFilterResonance = {0.25, 0.5},
    },
  },
}

---------- VELOCITY CURVES ----------
-- per-mode velocity response. some modes want sensitive dynamics,
-- others want compressed always-heavy response.

local VEL_CURVES = {
  function(v) return 0.7 + v * 0.3 end,   -- 1 SUB DESTROY: always heavy
  function(v) return v end,                 -- 2 FUNK STAB: full sensitivity
  function(v) return 0.3 + v * 0.7 end,   -- 3 ACID MORPH: slight compress
  function(v) return 0.6 + v * 0.4 end,   -- 4 DIST WALL: always loud
  function(v) return 0.4 + v * 0.6 end,   -- 5 VOWEL BOT: moderate
  function(v) return 0.35 + v * 0.65 end, -- 6 GNARLY: floor + sensitive
  function(v) return 0.4 + v * 0.6 end,  -- 7 TAPE SAT: moderate warmth
  function(v) return 0.75 + v * 0.25 end, -- 8 DOOM: compressed, always heavy
  function(v) return 0.4 + v * 0.6 end,  -- 9 TALK BOX: moderate
  function(v) return v end,                -- 10 SYNTH POP: full sensitivity
  function(v) return 0.3 + v * 0.7 end,  -- 11 RUBBER: bouncy with floor
}

local function apply_vel_curve(vel)
  local curve = VEL_CURVES[voice_mode]
  if curve then return curve(vel) end
  return vel
end

---------- DESTROY (D-inspired) ----------
-- destruction layer: applied on top of any voice mode.
-- inspired by justmat's "d" script (decimate, distort, disintegrate).
-- since we share one engine, we abuse ring mod, resonance, noise,
-- and pitch instability to simulate decimation/bitcrush/saturation.

local DESTROY_TARGETS = {
  -- param             = {clean, fully destroyed}
  ringModMix           = {0, 0.95},
  ringModFreq          = {50, 280},
  lpFilterResonance    = {0, 0.92},
  noiseLevel           = {0, 0.55},
  freqModLfo           = {0, 0.12},
  ampMod               = {0, 0.45},
  subOscDetune         = {0, 3.0},
  lpFilterCutoffModLfo = {0, 0.6},
  lfoFreq              = {1, 18},
}

---------- ENGINE HELPERS ----------

local function apply_engine_params(p)
  for name, val in pairs(p) do
    if engine[name] then
      engine[name](val)
    end
  end
end

local function apply_destroy_layer()
  -- layer destruction on top of current voice+macro state.
  -- at destroy=0 this is a no-op (targets lerp from mode's own values).
  -- at destroy=1 we override toward maximum destruction.
  if destroy <= 0 then return end
  local mode = MODES[voice_mode]
  for name, range in pairs(DESTROY_TARGETS) do
    -- find current "clean" value from mode base + macro
    local clean = mode.base[name] or 0
    if mode.macro_targets and mode.macro_targets[name] then
      local lo, hi = mode.macro_targets[name][1], mode.macro_targets[name][2]
      clean = lo + (hi - lo) * macro
    end
    local dirty = range[2]
    local v = clean + (dirty - clean) * destroy
    if engine[name] then
      engine[name](v)
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
  apply_destroy_layer()
end

local function apply_voice(mode_num)
  voice_mode = util.clamp(mode_num, 1, NUM_MODES)
  local mode = MODES[voice_mode]
  apply_engine_params(mode.base)
  apply_macro_val(macro)
  -- pass mode glide to bandmate
  bandmate.mode_glide = mode.base.glide or 0
end

---------- MODE MORPH ----------

local function morph_apply_blend(mix)
  -- mix: 0.0 = pure mode A, 1.0 = pure mode B
  local a = MODES[morph_mode_a].base
  local b = MODES[morph_mode_b].base
  for name, val_a in pairs(a) do
    local val_b = b[name] or val_a
    local v = val_a + (val_b - val_a) * mix
    if engine[name] then
      engine[name](v)
    end
  end
  -- also blend macro targets at current macro position
  local ma = MODES[morph_mode_a].macro_targets or {}
  local mb = MODES[morph_mode_b].macro_targets or {}
  local all_keys = {}
  for k in pairs(ma) do all_keys[k] = true end
  for k in pairs(mb) do all_keys[k] = true end
  for name in pairs(all_keys) do
    local va = ma[name] and (ma[name][1] + (ma[name][2] - ma[name][1]) * macro) or (MODES[morph_mode_a].base[name] or 0)
    local vb = mb[name] and (mb[name][1] + (mb[name][2] - mb[name][1]) * macro) or (MODES[morph_mode_b].base[name] or 0)
    local v = va + (vb - va) * mix
    if engine[name] then
      engine[name](v)
    end
  end
  apply_destroy_layer()
end

local function morph_pick_next_drift()
  -- cycle through modes organically: mostly sequential,
  -- sometimes skip one, occasionally jump
  local next_mode
  if math.random() < 0.65 then
    -- sequential (forward or backward)
    local dir = math.random() < 0.7 and 1 or -1
    next_mode = ((morph_current - 1 + dir) % NUM_MODES) + 1
  elseif math.random() < 0.7 then
    -- skip one
    local dir = math.random() < 0.5 and 2 or -2
    next_mode = ((morph_current - 1 + dir) % NUM_MODES) + 1
  else
    -- random jump
    next_mode = math.random(NUM_MODES)
    if next_mode == morph_current then
      next_mode = next_mode % NUM_MODES + 1
    end
  end
  return next_mode
end

local function morph_pick_next_random()
  local next_mode = math.random(NUM_MODES)
  -- avoid repeating same mode twice
  if next_mode == morph_current then
    next_mode = next_mode % NUM_MODES + 1
  end
  return next_mode
end

local function morph_start()
  if morph_clock_id then return end
  morph_active = true
  morph_side = false
  morph_current = voice_mode
  morph_clock_id = clock.run(function()
    while morph_active do
      local rate = MORPH_RATES[morph_rate]

      if morph_style == 1 then
        ---------- A/B: classic toggle ----------
        clock.sync(rate)
        morph_side = not morph_side
        if morph_blend then
          local from = morph_side and 0 or 1
          local to = morph_side and 1 or 0
          local steps = 4
          for s = 1, steps do
            local mix = from + (to - from) * (s / steps)
            morph_apply_blend(mix)
            clock.sync(rate / steps)
          end
        else
          local target = morph_side and morph_mode_b or morph_mode_a
          voice_mode = target
          morph_current = target
          apply_voice(target)
        end

      elseif morph_style == 2 then
        ---------- DRIFT: organic cycling ----------
        -- variable hold time: 1x to 3x the rate (organic feel)
        local hold = rate * (1 + math.random() * 2)
        clock.sync(hold)
        local prev = morph_current
        morph_current = morph_pick_next_drift()
        if morph_blend then
          local steps = 6
          for s = 1, steps do
            local mix = s / steps
            morph_mode_a = prev
            morph_mode_b = morph_current
            morph_apply_blend(mix)
            clock.sync(rate / steps)
          end
        else
          voice_mode = morph_current
          apply_voice(morph_current)
        end

      else
        ---------- RANDOM: unpredictable ----------
        -- random hold: 0.5x to 4x rate
        local hold = rate * (0.5 + math.random() * 3.5)
        clock.sync(hold)
        local prev = morph_current
        morph_current = morph_pick_next_random()
        if morph_blend then
          local steps = 4
          for s = 1, steps do
            local mix = s / steps
            morph_mode_a = prev
            morph_mode_b = morph_current
            morph_apply_blend(mix)
            clock.sync(rate / steps)
          end
        else
          voice_mode = morph_current
          apply_voice(morph_current)
        end
      end
    end
  end)
end

local function morph_stop()
  morph_active = false
  if morph_clock_id then
    clock.cancel(morph_clock_id)
    morph_clock_id = nil
  end
end

---------- SNAPSHOTS ----------

local function snapshot_capture()
  local mode = MODES[voice_mode]
  local state = {voice_mode = voice_mode, macro = macro, filter_cutoff = filter_base, destroy = destroy}
  -- capture computed engine state
  state.engine = {}
  for name, val in pairs(mode.base) do
    state.engine[name] = val
  end
  -- apply macro on top
  if mode.macro_targets then
    for name, range in pairs(mode.macro_targets) do
      state.engine[name] = range[1] + (range[2] - range[1]) * macro
    end
  end
  return state
end

local function snapshot_save(slot)
  if not data_dir then return end
  local path = data_dir .. "snapshots/"
  util.make_dir(path)
  local state = snapshot_capture()
  local f = io.open(path .. string.format("slot_%02d.dat", slot), "w")
  if not f then return end
  f:write(string.format("voice_mode=%d\n", state.voice_mode))
  f:write(string.format("macro=%f\n", state.macro))
  f:write(string.format("filter_cutoff=%f\n", state.filter_cutoff))
  f:write(string.format("destroy=%f\n", state.destroy))
  for name, val in pairs(state.engine) do
    f:write(string.format("e_%s=%f\n", name, val))
  end
  f:close()
  snapshot_slots[slot] = true
  print("monolith: snapshot saved to slot " .. slot)
end

local function snapshot_load(slot)
  if not data_dir then return end
  local path = data_dir .. "snapshots/" .. string.format("slot_%02d.dat", slot)
  local f = io.open(path, "r")
  if not f then return end
  local state = {engine = {}}
  for line in f:lines() do
    local k, v = line:match("^(.-)=(.+)$")
    if k and v then
      if k == "voice_mode" then state.voice_mode = tonumber(v)
      elseif k == "macro" then state.macro = tonumber(v)
      elseif k == "filter_cutoff" then state.filter_cutoff = tonumber(v)
      elseif k == "destroy" then state.destroy = tonumber(v)
      elseif k:sub(1,2) == "e_" then
        state.engine[k:sub(3)] = tonumber(v)
      end
    end
  end
  f:close()
  -- apply
  if state.voice_mode then
    voice_mode = state.voice_mode
    params:set("voice_mode", voice_mode, true) -- silent
  end
  if state.engine then apply_engine_params(state.engine) end
  if state.macro then macro = state.macro; params:set("macro", macro, true) end
  if state.filter_cutoff then
    filter_base = state.filter_cutoff
    engine.lpFilterCutoff(filter_base)
  end
  if state.destroy then
    destroy = state.destroy
    params:set("destroy", destroy, true)
    apply_destroy_layer()
  end
  print("monolith: snapshot loaded from slot " .. slot)
end

local function snapshot_scan()
  snapshot_slots = {}
  if not data_dir then return end
  for slot = 1, SNAPSHOT_COUNT do
    local path = data_dir .. "snapshots/" .. string.format("slot_%02d.dat", slot)
    local f = io.open(path, "r")
    if f then f:close(); snapshot_slots[slot] = true end
  end
end

---------- EFFECTS ----------

local function setup_softcut_delay()
  softcut.reset()
  audio.level_eng_cut(1)
  audio.level_eng_rev(0.15)  -- default reverb send
  audio.level_cut(0) -- start silent, enable when delay is on
  -- voice 1: delay line
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, delay_level)
  softcut.pan(1, 0)
  softcut.rate(1, 1)
  softcut.loop(1, 1)
  softcut.loop_start(1, 0)
  softcut.loop_end(1, delay_time)
  softcut.position(1, 0)
  softcut.play(1, 1)
  softcut.rec(1, 1)
  softcut.rec_level(1, 1)
  softcut.pre_level(1, delay_feedback)
  softcut.level_slew_time(1, 0.05)
  softcut.rate_slew_time(1, 0.1)
  softcut.filter_dry(1, 0.7)
  softcut.filter_lp(1, 0.3)
  softcut.filter_fc(1, 2000)
end

local function update_delay()
  if delay_on then
    audio.level_cut(1)
    softcut.level(1, delay_level)
    softcut.loop_end(1, math.max(0.05, delay_time))
    softcut.pre_level(1, delay_feedback)
  else
    audio.level_cut(0)
  end
end

local function sync_delay_to_tempo()
  -- delay time synced to beat divisions
  local beat_sec = 60 / clock.get_tempo()
  delay_time = beat_sec * 0.5 -- dotted 8th feel
  if delay_on then
    softcut.loop_end(1, math.max(0.05, delay_time))
  end
end

local function trigger_stutter()
  if params:get("stutter_enabled") == 1 then return end
  if stutter_clock_id then clock.cancel(stutter_clock_id) end
  stutter_active = true
  stutter_clock_id = clock.run(function()
    local rates = {1/16, 1/16, 1/16, 1/8, 1/8, 1/4, 1/4, 1/2, 1/4, 1/8, 1/16, 1/16}
    local vel_decay = 1.0
    for i, rate in ipairs(rates) do
      if not stutter_active then break end
      if last_note > 0 then
        note_off(last_note)
        note_on(last_note, last_vel * vel_decay)
        vel_decay = vel_decay * 0.92
      end
      clock.sync(rate)
    end
    if last_note > 0 then note_off(last_note) end
    stutter_active = false
    stutter_clock_id = nil
  end)
end

local function trigger_bass_drop()
  if params:get("bass_drop_enabled") == 1 then return end
  if bass_drop_clock_id then clock.cancel(bass_drop_clock_id) end
  bass_drop_clock_id = clock.run(function()
    -- dramatic pitch dive: play root 2 octaves down with max glide
    local drop_note = math.max(20, root_note - 24)
    engine.glide(0.4)
    note_on(drop_note, 1.0)
    clock.sync(2) -- sustain for 2 beats
    note_off(drop_note)
    -- restore mode glide
    engine.glide(MODES[voice_mode].base.glide or 0)
    bass_drop_clock_id = nil
  end)
end

local function trigger_time_warp()
  if params:get("time_warp_enabled") == 1 then return end
  -- the slow-down / catch-up effect
  -- smoothly changes bandmate step rate: normal -> slow -> slower -> catches back up
  bandmate.warp_active = true
  clock.run(function()
    local curve = {1.0, 1.5, 2.5, 4.0, 4.0, 3.0, 2.0, 1.5, 1.0}
    for _, rate in ipairs(curve) do
      bandmate.warp_rate = rate
      clock.sync(0.5) -- each stage lasts half a beat
    end
    bandmate.warp_rate = 1.0
    bandmate.warp_active = false
  end)
end

---------- GRID ----------

local g = grid.connect()
local grid_dirty = true
local grid_page = 1
local grid_clock_id = nil
local grid_held = {} -- held grid note keys
local grid_note_map = {} -- [row][col] = midi note

local function build_grid_note_map()
  grid_note_map = {}
  local scale = gen_scale(root_note - 24, 7)
  local npo = notes_per_octave()
  -- rows 4-8: 5 playable rows, row 8=lowest, row 4=highest
  for row = 4, 8 do
    grid_note_map[row] = {}
    local oct_offset = (8 - row) * npo
    for col = 1, 16 do
      local idx = oct_offset + col
      if idx >= 1 and idx <= #scale then
        grid_note_map[row][col] = scale[idx]
      end
    end
  end
end

local function grid_redraw()
  if not g.device then return end
  g:all(0)

  if grid_page == 1 then
    ---- PAGE 1: PERFORM ----

    -- row 1: mode select (1-11) + morph (13) + delay (14) + harmonize (15) + page (16)
    local cur_mode = morph_active and morph_current or voice_mode
    for i = 1, NUM_MODES do
      g:led(i, 1, cur_mode == i and 15 or 3)
    end
    g:led(13, 1, morph_active and 12 or 2)
    g:led(14, 1, delay_on and 12 or 2)
    g:led(15, 1, harmonize_on and 12 or 2)
    g:led(16, 1, 6) -- page toggle

    -- row 2: bandmate (1-9) + on/off (11) + lock (12) + stutter (13) + drop (14) + warp (15) + destroy bar (16)
    for i = 1, math.min(9, #bandmate.STYLE_NAMES) do
      g:led(i, 2, bandmate.style == i and 12 or 2)
    end
    g:led(11, 2, bandmate_active and 12 or 2)
    g:led(12, 2, bandmate.locked and 15 or 2)
    local stut_en = params:get("stutter_enabled") == 2
    local drop_en = params:get("bass_drop_enabled") == 2
    local warp_en = params:get("time_warp_enabled") == 2
    g:led(13, 2, stutter_active and 15 or (stut_en and 5 or 1)) -- stutter
    g:led(14, 2, drop_en and 5 or 1) -- bass drop
    g:led(15, 2, bandmate.warp_active and 15 or (warp_en and 5 or 1)) -- time warp
    g:led(16, 2, math.floor(2 + destroy * 13)) -- destroy level

    -- row 3: pattern viz (16 steps)
    for i = 1, 16 do
      local e = bandmate.pattern[i]
      if e then
        local bright = math.floor(e.vel * 10) + 2
        if bandmate.playing and bandmate.step == i then bright = 15 end
        g:led(i, 3, math.min(15, bright))
      else
        g:led(i, 3, bandmate.playing and bandmate.step == i and 6 or 0)
      end
    end

    -- rows 4-8: playable scale pad
    for row = 4, 8 do
      if grid_note_map[row] then
        for col = 1, 16 do
          local note = grid_note_map[row][col]
          if note then
            local key = row .. "_" .. col
            if grid_held[key] then
              g:led(col, row, 15)
            elseif note % 12 == root_note % 12 then
              g:led(col, row, 8) -- root note highlighted
            else
              g:led(col, row, 3) -- scale note dim
            end
          end
        end
      end
    end

  else
    ---- PAGE 2: BANKS ----

    -- rows 1-2: pattern slots (32)
    for slot = 1, 32 do
      local col = ((slot - 1) % 16) + 1
      local row = slot <= 16 and 1 or 2
      local has = bandmate.favorites[slot] and true or false
      -- check disk too
      if not has and data_dir then
        local path = data_dir .. "patterns/" .. string.format("slot_%02d.dat", slot)
        local f = io.open(path, "r")
        if f then f:close(); has = true end
      end
      g:led(col, row, has and 8 or 1)
    end

    -- rows 3-4: snapshot slots (32)
    for slot = 1, 32 do
      local col = ((slot - 1) % 16) + 1
      local row = slot <= 16 and 3 or 4
      g:led(col, row, snapshot_slots[slot] and 8 or 1)
    end

    -- row 5: favorites controls
    g:led(1, 5, bandmate.favorites_mode and 12 or 3) -- fav mode
    g:led(3, 5, bandmate.favorites_order == "sequential" and 12 or 3)
    g:led(5, 5, bandmate.favorites_order == "random" and 12 or 3)

    -- row 8: page toggle
    g:led(16, 8, 6)
  end

  g:refresh()
end

g.key = function(x, y, z)
  if z == 0 then
    -- key release: note off for grid notes
    if grid_page == 1 and y >= 4 and y <= 8 then
      local key = y .. "_" .. x
      local note = grid_held[key]
      if note then
        manual_note_off(note)
        grid_held[key] = nil
      end
    end
    grid_dirty = true
    return
  end

  -- key press (z == 1)
  if grid_page == 1 then
    if y == 1 then
      if x >= 1 and x <= NUM_MODES then
        params:set("voice_mode", x)
      elseif x == 13 then
        params:set("morph_on", morph_active and 1 or 2)
      elseif x == 14 then
        params:set("delay_on", delay_on and 1 or 2)
      elseif x == 15 then
        params:set("harmonize_on", harmonize_on and 1 or 2)
      elseif x == 16 then
        grid_page = 2
      end
    elseif y == 2 then
      if x >= 1 and x <= math.min(9, #bandmate.STYLE_NAMES) then
        params:set("bm_style", x)
      elseif x == 11 then
        params:set("bandmate_on", bandmate_active and 1 or 2)
      elseif x == 12 then
        bandmate.toggle_lock()
        params:set("bm_lock", bandmate.locked and 2 or 1, true)
      elseif x == 13 then
        trigger_stutter()
      elseif x == 14 then
        trigger_bass_drop()
      elseif x == 15 then
        trigger_time_warp()
      elseif x == 16 then
        -- destroy: cycle through levels 0, 0.3, 0.6, 1.0
        local levels = {0, 0.3, 0.6, 1.0}
        local cur_idx = 1
        for i, lv in ipairs(levels) do
          if math.abs(destroy - lv) < 0.1 then cur_idx = i end
        end
        params:set("destroy", levels[(cur_idx % #levels) + 1])
      end
    elseif y == 3 then
      -- row 3: pattern EDIT — tap to toggle steps
      if bandmate.pattern[x] then
        bandmate.pattern[x] = nil -- remove step
      else
        bandmate.pattern[x] = {
          offset = 0,
          vel = 0.7 + math.random() * 0.2,
          gate = 0.3 + math.random() * 0.2,
        }
      end
    elseif y >= 4 and y <= 8 then
      -- note pad
      if grid_note_map[y] and grid_note_map[y][x] then
        local note = grid_note_map[y][x]
        local key = y .. "_" .. x
        grid_held[key] = note
        manual_note_on(note, 0.85)
      end
    end

  elseif grid_page == 2 then
    if y == 1 or y == 2 then
      -- pattern slot
      local slot = (y - 1) * 16 + x
      local p = bandmate.load_pattern(slot, data_dir)
      if p and next(p) then
        bandmate.pattern = p
        bandmate.locked = true
        params:set("bm_lock", 2, true)
        print("monolith: loaded pattern slot " .. slot)
      end
    elseif y == 3 or y == 4 then
      -- snapshot slot
      local slot = (y - 3) * 16 + x
      if snapshot_slots[slot] then
        snapshot_load(slot)
      else
        snapshot_save(slot)
      end
    elseif y == 5 then
      if x == 1 then
        bandmate.favorites_mode = not bandmate.favorites_mode
        params:set("bm_fav_mode", bandmate.favorites_mode and 2 or 1, true)
      elseif x == 3 then
        bandmate.favorites_order = "sequential"
        params:set("bm_fav_order", 1, true)
      elseif x == 5 then
        bandmate.favorites_order = "random"
        params:set("bm_fav_order", 2, true)
      end
    elseif y == 8 and x == 16 then
      grid_page = 1
    end
  end

  grid_dirty = true
end

---------- NOTE HANDLING ----------

local function note_on(note, vel)
  vel = apply_vel_curve(vel)
  local freq = note_to_freq(note)
  engine.noteOn(note, freq, vel)
  current_notes[note] = vel
  last_note = note
  last_vel = vel
  -- auto-harmonize
  if harmonize_on then
    local h_note = note - harmonize_interval
    if h_note >= 20 and h_note <= 108 then
      local h_freq = note_to_freq(h_note)
      engine.noteOn(h_note + 1000, h_freq, vel * 0.6)
      harmony_notes[note] = h_note
    end
  end
  -- octave/5th doubling
  if doubling_mode > 1 then
    local extras = {}
    if doubling_mode == 2 or doubling_mode == 4 then
      local dn = note - 12
      if dn >= 20 then
        engine.noteOn(note + 2000, note_to_freq(dn), vel * 0.5)
        table.insert(extras, note + 2000)
      end
    end
    if doubling_mode == 3 or doubling_mode == 4 then
      local fn = note - 7
      if fn >= 20 then
        engine.noteOn(note + 3000, note_to_freq(fn), vel * 0.45)
        table.insert(extras, note + 3000)
      end
    end
    if #extras > 0 then doubled_notes[note] = extras end
  end
  -- seismograph
  activity[act_head] = {vel = vel, age = 0}
  act_head = act_head % ACT_LEN + 1
  -- midi out
  if midi_out_device and params:get("midi_out") == 2 then
    midi_out_device:note_on(note, math.floor(vel * 127), midi_out_channel)
  end
  grid_dirty = true
end

local function note_off(note)
  engine.noteOff(note)
  current_notes[note] = nil
  -- harmony note off
  if harmony_notes[note] then
    engine.noteOff(harmony_notes[note] + 1000)
    harmony_notes[note] = nil
  end
  -- doubled notes off
  if doubled_notes[note] then
    for _, id in ipairs(doubled_notes[note]) do engine.noteOff(id) end
    doubled_notes[note] = nil
  end
  if midi_out_device and params:get("midi_out") == 2 then
    midi_out_device:note_off(note, 0, midi_out_channel)
  end
  grid_dirty = true
end

---------- ARPEGGIATOR ----------

local function build_arp_pattern()
  -- build scale run from held notes
  if #arp_held_notes == 0 then return {} end
  local base = arp_held_notes[1]
  local scale = gen_scale(base, arp_range)
  if arp_style == 2 then
    -- reverse for down
    local rev = {}
    for i = #scale, 1, -1 do table.insert(rev, scale[i]) end
    return rev
  end
  return scale
end

local function arp_start()
  if arp_clock_id then return end
  arp_idx = 0
  arp_direction = 1
  arp_clock_id = clock.run(function()
    while arp_on and #arp_held_notes > 0 do
      local pattern = build_arp_pattern()
      if #pattern == 0 then break end

      -- advance index based on style
      if arp_style == 4 then
        -- random
        arp_idx = math.random(#pattern)
      elseif arp_style == 3 then
        -- up-down
        arp_idx = arp_idx + arp_direction
        if arp_idx > #pattern then
          arp_direction = -1
          arp_idx = #pattern - 1
        elseif arp_idx < 1 then
          arp_direction = 1
          arp_idx = 2
        end
        arp_idx = util.clamp(arp_idx, 1, #pattern)
      else
        -- up or down (already handled by pattern order)
        arp_idx = (arp_idx % #pattern) + 1
      end

      -- play note
      if arp_playing_note then note_off(arp_playing_note) end
      local n = pattern[arp_idx]
      if n then
        note_on(n, 0.8)
        arp_playing_note = n
      end

      clock.sync(ARP_RATES[arp_rate])
    end
    -- cleanup
    if arp_playing_note then note_off(arp_playing_note); arp_playing_note = nil end
    arp_clock_id = nil
  end)
end

local function arp_stop()
  arp_on = false
  if arp_clock_id then
    clock.cancel(arp_clock_id)
    arp_clock_id = nil
  end
  if arp_playing_note then note_off(arp_playing_note); arp_playing_note = nil end
  arp_held_notes = {}
end

-- manual_note_on/off: routes through arp for keyboard/grid input
-- bandmate calls note_on/note_off directly (bypasses arp)
local function manual_note_on(note, vel)
  if arp_on then
    -- add to arp held notes
    for _, n in ipairs(arp_held_notes) do
      if n == note then return end -- already held
    end
    table.insert(arp_held_notes, note)
    if not arp_clock_id then arp_start() end
  else
    note_on(note, vel)
  end
end

local function manual_note_off(note)
  if arp_on then
    for i, n in ipairs(arp_held_notes) do
      if n == note then
        table.remove(arp_held_notes, i)
        break
      end
    end
    -- if no more held notes, arp will stop naturally
  else
    note_off(note)
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
    manual_note_on(msg.note, msg.vel / 127)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    manual_note_off(msg.note)
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

  params:add_option("scene", ">> SCENE", SCENE_NAMES, 1)
  params:set_action("scene", function(val)
    apply_scene(val)
  end)

  params:add_option("voice_mode", "voice mode", MODE_NAMES, 1)
  params:set_action("voice_mode", function(val)
    -- block voice_mode changes during active morph (morph owns the voice)
    if morph_active then return end
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

  -- morph
  params:add_separator("MODE MORPH")

  params:add_option("morph_on", "morph", {"off", "on"}, 1)
  params:set_action("morph_on", function(val)
    if val == 2 then morph_start() else morph_stop() end
  end)

  params:add_option("morph_style", "style", MORPH_STYLE_NAMES, 1)
  params:set_action("morph_style", function(val) morph_style = val end)

  params:add_option("morph_mode_a", "mode A", MODE_NAMES, 1)
  params:set_action("morph_mode_a", function(val) morph_mode_a = val end)

  params:add_option("morph_mode_b", "mode B", MODE_NAMES, 5)
  params:set_action("morph_mode_b", function(val) morph_mode_b = val end)

  params:add_option("morph_rate", "rate", MORPH_RATE_NAMES, 4)
  params:set_action("morph_rate", function(val) morph_rate = val end)

  params:add_option("morph_blend", "blend", {"hard cut", "smooth"}, 1)
  params:set_action("morph_blend", function(val) morph_blend = val == 2 end)

  -- destroy
  params:add_separator("DESTROY")

  params:add_control("destroy", "destroy",
    controlspec.new(0, 1, 'lin', 0.01, 0, ""))
  params:set_action("destroy", function(val)
    destroy = val
    apply_destroy_layer()
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

  params:add_option("bm_lock", "pattern lock", {"off", "on"}, 1)
  params:set_action("bm_lock", function(val) bandmate.locked = val == 2 end)

  params:add_option("bm_fav_mode", "favorites mode", {"off", "on"}, 1)
  params:set_action("bm_fav_mode", function(val) bandmate.favorites_mode = val == 2 end)

  params:add_option("bm_fav_order", "favorites order", {"sequential", "random"}, 1)
  params:set_action("bm_fav_order", function(val)
    bandmate.favorites_order = val == 1 and "sequential" or "random"
  end)

  params:add_number("bm_save_slot", "save pattern to slot", 1, 32, 1)

  params:add_trigger("bm_save_now", ">> save pattern")
  params:set_action("bm_save_now", function()
    local slot = params:get("bm_save_slot")
    bandmate.save_pattern(slot, data_dir)
    table.insert(bandmate.favorites, bandmate.deep_copy_pattern(bandmate.pattern))
    print("monolith: saved pattern to slot " .. slot)
  end)

  params:add_option("bm_form", "song form", {"off", "on"}, 1)
  params:set_action("bm_form", function(val)
    bandmate.form_enabled = val == 2
    if val == 2 then
      bandmate.home_pattern = bandmate.deep_copy_pattern(bandmate.pattern)
      bandmate.form_section = 1
      bandmate.form_bar = 0
      bandmate.form_phase = "home"
    end
  end)

  params:add_option("bm_form_type", "form type", bandmate.FORM_NAMES, 1)
  params:set_action("bm_form_type", function(val)
    bandmate.form_type = val
    bandmate.form_section = 1
    bandmate.form_bar = 0
  end)

  params:add_control("bm_swing", "swing",
    controlspec.new(0, 0.7, 'lin', 0.01, 0))
  params:set_action("bm_swing", function(val) bandmate.swing = val end)

  params:add_option("bm_prog_mode", "chord progression", {"off", "on"}, 1)
  params:set_action("bm_prog_mode", function(val)
    bandmate.progression_mode = val == 2
    bandmate.progression_idx = 1
  end)

  params:add_option("bm_prog_type", "progression", PROG_NAMES, 1)
  params:set_action("bm_prog_type", function(val)
    bandmate.progression = PROG_PRESETS[val].prog
    bandmate.progression_idx = 1
  end)

  params:add_number("bm_prog_rate", "bars per chord", 1, 16, 4)
  params:set_action("bm_prog_rate", function(val) bandmate.progression_rate = val end)

  -- music
  params:add_separator("MUSIC")

  params:add_number("root_note", "root note", 24, 48, 36)
  params:set_action("root_note", function(val)
    root_note = val
    bandmate.root = val
    bandmate.set_scale(val, SCALE_NAMES[scale_type])
    build_grid_note_map()
    grid_dirty = true
  end)

  params:add_option("scale_type", "scale", SCALE_NAMES, 1)
  params:set_action("scale_type", function(val)
    scale_type = val
    bandmate.set_scale(root_note, SCALE_NAMES[val])
    build_grid_note_map()
    grid_dirty = true
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

  -- snapshots
  params:add_separator("SNAPSHOTS")

  params:add_number("snap_slot", "slot", 1, 32, 1)

  params:add_trigger("snap_save", ">> save snapshot")
  params:set_action("snap_save", function()
    snapshot_save(params:get("snap_slot"))
  end)

  params:add_trigger("snap_load", "<< load snapshot")
  params:set_action("snap_load", function()
    snapshot_load(params:get("snap_slot"))
  end)

  -- effects
  params:add_separator("EFFECTS")

  params:add_control("rev_level", "reverb amount",
    controlspec.new(0, 1, 'lin', 0.01, 0.15))
  params:set_action("rev_level", function(val)
    audio.level_eng_rev(val)
  end)

  params:add_control("rev_size", "reverb size",
    controlspec.new(0.1, 16, 'exp', 0.1, 4, 's'))
  params:set_action("rev_size", function(val)
    -- norns reverb: mid_rt60 controls room size (0.1-16 seconds)
    audio.rev_param("mid_rt60", val)
  end)

  params:add_control("rev_damp", "reverb damp",
    controlspec.new(1500, 20000, 'exp', 10, 6000, 'hz'))
  params:set_action("rev_damp", function(val)
    -- norns reverb: hf_damp controls high frequency damping (hz)
    -- lower = darker/warmer tail, higher = brighter
    audio.rev_param("hf_damp", val)
  end)

  params:add_option("delay_on", "tape delay", {"off", "on"}, 1)
  params:set_action("delay_on", function(val)
    delay_on = val == 2
    update_delay()
  end)

  params:add_control("delay_feedback", "delay feedback",
    controlspec.new(0, 0.9, 'lin', 0.01, 0.45))
  params:set_action("delay_feedback", function(val)
    delay_feedback = val
    if delay_on then softcut.pre_level(1, val) end
  end)

  params:add_control("delay_level", "delay level",
    controlspec.new(0, 1, 'lin', 0.01, 0.35))
  params:set_action("delay_level", function(val)
    delay_level = val
    if delay_on then softcut.level(1, val) end
  end)

  params:add_option("harmonize_on", "auto-harmonize", {"off", "on"}, 1)
  params:set_action("harmonize_on", function(val) harmonize_on = val == 2 end)

  params:add_option("harmonize_int", "harmony interval",
    {"octave below", "5th below", "5th above", "octave above"}, 1)
  params:set_action("harmonize_int", function(val)
    local intervals = {12, 7, -7, -12}
    harmonize_interval = intervals[val]
  end)

  params:add_option("stutter_enabled", "stutter", {"off", "on"}, 2)

  params:add_option("bass_drop_enabled", "bass drop", {"off", "on"}, 2)

  params:add_option("time_warp_enabled", "time warp", {"off", "on"}, 2)

  params:add_option("doubling", "note doubling",
    {"off", "oct below", "5th below", "oct+5th"}, 1)
  params:set_action("doubling", function(val) doubling_mode = val end)

  params:add_option("arp_enabled", "arpeggiator", {"off", "on"}, 1)
  params:set_action("arp_enabled", function(val)
    if val == 2 then
      arp_on = true
    else
      arp_stop()
    end
  end)

  params:add_option("arp_rate", "arp rate", ARP_RATE_NAMES, 2)
  params:set_action("arp_rate", function(val) arp_rate = val end)

  params:add_option("arp_style", "arp style", ARP_STYLE_NAMES, 1)
  params:set_action("arp_style", function(val) arp_style = val end)

  params:add_number("arp_range", "arp range (oct)", 1, 3, 2)
  params:set_action("arp_range", function(val) arp_range = val end)

  -- robot
  params:add_separator("ROBOT")

  params:add_option("robot_personality", "personality", PERSONALITY_NAMES, 1)
  params:set_action("robot_personality", function(val) robot_personality = val end)

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

  -- data directories
  data_dir = _path.data .. "monolith/"
  util.make_dir(data_dir)
  util.make_dir(data_dir .. "patterns/")
  util.make_dir(data_dir .. "snapshots/")

  -- init hardware
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
  midi_out_device = midi.connect(2)

  -- init bandmate
  bandmate.init(note_on, note_off, root_note, SCALE_NAMES[scale_type])
  bandmate.load_all_favorites(data_dir)

  -- init effects + snapshots + grid
  setup_softcut_delay()
  snapshot_scan()
  build_grid_note_map()

  -- compressor: on by default, use LEVELS menu to fine-tune
  pcall(audio.comp_on)

  -- apply first voice mode after engine loads
  clock.run(function()
    clock.sleep(0.5)
    apply_voice(1)
  end)

  -- start conductor (coordinates robot, form, personality, effects)
  start_conductor()

  -- grid refresh clock
  grid_clock_id = clock.run(function()
    while true do
      clock.sleep(1/30)
      if grid_dirty and g.device then
        grid_redraw()
        grid_dirty = false
      end
    end
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
    if bandmate_active then grid_dirty = true end
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

  -- mode name (or morph indicator)
  screen.level(15)
  screen.move(2, 18)
  if morph_active then
    local cur = morph_style == 1
      and (morph_side and MODE_NAMES[morph_mode_b] or MODE_NAMES[morph_mode_a])
      or MODE_NAMES[morph_current]
    screen.text(cur)
    -- morph style indicator
    screen.level(6)
    screen.move(screen.text_extents(cur) + 6, 18)
    local tag = ({"<>", "~", "?"})[morph_style]
    screen.text(tag)
  else
    screen.text(MODE_NAMES[voice_mode])
  end

  -- destroy indicator (right side, bar)
  if destroy > 0.01 then
    local dx = 104
    screen.level(3)
    screen.rect(dx, 11, 22, 5)
    screen.stroke()
    screen.level(math.floor(4 + destroy * 11))
    screen.rect(dx, 11, math.floor(22 * destroy), 5)
    screen.fill()
    screen.level(6)
    screen.move(dx, 10)
    screen.text("D")
  end

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
  arp_stop()
  morph_stop()
  stop_conductor()
  bandmate.stop()
  if screen_metro then screen_metro:stop() end
  if grid_clock_id then clock.cancel(grid_clock_id) end
  pcall(audio.comp_off)
end
