-- monolith
-- engine: MollyThePoly
-- brutal bass instrument with 6 voice modes and bandmate engine
--
-- robot strategy: MUSICAL FIRST. the conductor clock in monolith.lua
-- coordinates robot changes with bandmate form, breathing, and personality.
--
-- macro is the main lever — ride it like a DJ rides a filter.
-- destroy is a BRIEF weapon — conductor tames it above 0.7.
-- ring mod and resonance are HARSH — kept to low ranges.
-- voice mode and bandmate style are RARE structural shifts.
-- the conductor pulls params back toward scene anchors during "home" phases,
-- quiets everything during "silence", and blocks voice changes during morph.
--
-- personality scales everything: chill=strong taming, aggressive=moderate, chaotic=free.

return {
  name = "monolith",
  description = "Brutal synth bass - 11 voice modes, effects, grid, snapshots, bandmate with 9 styles",
  phrase_len = 16,
  recommended_modes = {1, 3, 7, 10}, -- FUNK, APHEX, DRUNK, CHAOS
  never_touch = {
    "clock_tempo",
    "clock_source",
    "midi_in_dev",
    "midi_in_ch",
    "midi_out_dev",
    "midi_out_ch",
    "midi_out",
    "comp_on",
    "snap_slot",
    "snap_save",
    "snap_load",
    "bm_save_slot",
    "bm_save_now",
    "arp_rate",
    "arp_style",
    "arp_range",
    "bm_prog_rate",
  },

  params = {
    ---------- PRIMARY: macro + destroy ----------
    destroy = {
      group = "timbral",
      weight = 0.5,
      sensitivity = 0.35,
      direction = "both",
      -- brief bursts only. conductor tames above 0.7.
      range_lo = 0,
      range_hi = 0.5,
    },
    macro = {
      group = "timbral",
      weight = 0.95,
      sensitivity = 0.7,
      direction = "both",
      -- robot should ride this like a DJ rides a filter.
      -- slow sweeps for builds, sudden jumps for drops.
    },

    ---------- TIMBRAL ----------
    filter_cutoff = {
      group = "timbral",
      weight = 0.65,
      sensitivity = 0.4,
      direction = "both",
      -- keep filter in musical range. extreme lows kill the bass,
      -- extreme highs sound thin.
      range_lo = 200,
      range_hi = 4000,
    },
    lp_filter_resonance = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.3,
      direction = "both",
      -- resonance above 0.5 = screaming wah. keep it musical.
      -- conductor also tames this above 0.65.
      range_lo = 0,
      range_hi = 0.55,
    },
    chorus_mix = {
      group = "timbral",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
    },
    ring_mod_mix = {
      group = "timbral",
      weight = 0.3,
      sensitivity = 0.2,
      direction = "up",
      -- ring mod is HARSH. use sparingly — brief moments of grit.
      -- conductor also tames this above 0.4.
      range_lo = 0,
      range_hi = 0.35,
    },
    ring_mod_freq = {
      group = "timbral",
      weight = 0.25,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 40,
      range_hi = 180,
    },
    sub_osc_level = {
      group = "timbral",
      weight = 0.55,
      sensitivity = 0.4,
      direction = "both",
    },
    noise_level = {
      group = "timbral",
      weight = 0.2,
      sensitivity = 0.2,
      direction = "up",
      -- noise adds hiss/texture. keep subtle.
      range_lo = 0,
      range_hi = 0.2,
    },
    amp_mod = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.35,
      direction = "both",
    },

    ---------- RHYTHMIC ----------
    bm_intensity = {
      group = "rhythmic",
      weight = 0.75,
      sensitivity = 0.6,
      direction = "both",
      -- intensity is the density knob. robot uses this for
      -- sparse-to-dense transitions. builds.
    },
    lfo_freq = {
      group = "rhythmic",
      weight = 0.55,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0.1,
      range_hi = 14,
    },
    env_1_decay = {
      group = "rhythmic",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
    },
    env_1_sustain = {
      group = "rhythmic",
      weight = 0.5,
      sensitivity = 0.4,
      direction = "both",
    },
    env_1_release = {
      group = "rhythmic",
      weight = 0.4,
      sensitivity = 0.4,
      direction = "both",
    },

    ---------- MELODIC ----------
    root_note = {
      group = "melodic",
      weight = 0.45,
      sensitivity = 0.3,
      direction = "both",
      range_lo = 24,
      range_hi = 48,
      -- robot can shift the key center. stay in bass range.
    },
    glide = {
      group = "melodic",
      weight = 0.45,
      sensitivity = 0.4,
      direction = "both",
      range_lo = 0,
      range_hi = 0.5,
    },
    scale_type = {
      group = "melodic",
      weight = 0.25,
      sensitivity = 1.0,
      direction = "both",
    },

    ---------- STRUCTURAL ----------
    voice_mode = {
      group = "structural",
      weight = 0.12,
      sensitivity = 1.0,
      direction = "both",
      -- voice mode switches are BIG moments. very rare.
      -- blocked entirely when morph is active.
    },
    bm_style = {
      group = "structural",
      weight = 0.1,
      sensitivity = 1.0,
      direction = "both",
      -- bandmate style changes are disruptive. keep rare.
    },
    bm_phrase = {
      group = "structural",
      weight = 0.15,
      sensitivity = 0.5,
      direction = "both",
    },
    bandmate_on = {
      group = "structural",
      weight = 0.08,
      sensitivity = 1.0,
      direction = "both",
      -- turning bandmate on/off is very disruptive. almost never.
    },
    morph_on = {
      group = "structural",
      weight = 0.1,
      sensitivity = 1.0,
      direction = "both",
      -- morph is dramatic. toggle sparingly.
    },
    morph_mode_a = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
    },
    morph_mode_b = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
    },
    morph_rate = {
      group = "rhythmic",
      weight = 0.3,
      sensitivity = 1.0,
      direction = "both",
    },
    morph_style = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
    },
    bm_lock = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
      -- robot can lock a good pattern to ride it longer.
    },
    bm_fav_mode = {
      group = "structural",
      weight = 0.15,
      sensitivity = 1.0,
      direction = "both",
    },
    bm_fav_order = {
      group = "structural",
      weight = 0.1,
      sensitivity = 1.0,
      direction = "both",
    },
    delay_on = {
      group = "timbral",
      weight = 0.35,
      sensitivity = 1.0,
      direction = "both",
      -- tape delay adds space. robot can toggle for texture shifts.
    },
    delay_feedback = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0.1,
      range_hi = 0.8,
    },
    delay_level = {
      group = "timbral",
      weight = 0.35,
      sensitivity = 0.4,
      direction = "both",
    },
    rev_level = {
      group = "timbral",
      weight = 0.4,
      sensitivity = 0.3,
      direction = "both",
      -- reverb adds space. subtle changes for atmosphere.
    },
    rev_size = {
      group = "timbral",
      weight = 0.25,
      sensitivity = 0.3,
      direction = "both",
    },
    rev_damp = {
      group = "timbral",
      weight = 0.2,
      sensitivity = 0.25,
      direction = "both",
    },
    harmonize_on = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
      -- harmonize is dramatic. use rarely for big moments.
    },
    harmonize_int = {
      group = "melodic",
      weight = 0.15,
      sensitivity = 1.0,
      direction = "both",
    },
    robot_personality = {
      group = "structural",
      weight = 0.1,
      sensitivity = 1.0,
      direction = "both",
    },
    bm_swing = {
      group = "rhythmic",
      weight = 0.65,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0,
      range_hi = 0.6,
      -- swing is the groove knob. robot should ride it.
    },
    bm_prog_mode = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
    },
    bm_prog_type = {
      group = "structural",
      weight = 0.15,
      sensitivity = 1.0,
      direction = "both",
    },
    doubling = {
      group = "structural",
      weight = 0.15,
      sensitivity = 1.0,
      direction = "both",
      -- doubling is dramatic. use sparingly for big moments.
    },
    arp_enabled = {
      group = "structural",
      weight = 0.1,
      sensitivity = 1.0,
      direction = "both",
      -- arp is player territory. robot should barely touch this.
    },
  },
}
