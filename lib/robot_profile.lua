-- monolith
-- engine: MollyThePoly
-- brutal bass instrument with 6 voice modes and bandmate engine
--
-- robot strategy: the macro knob is the main lever. robot should ride it
-- like a DJ rides a filter — slow builds, sudden drops, tension and release.
-- voice mode switches are dramatic structural moments (use sparingly).
-- the destroy knob is the wildcard — robot can push it for D-style decimation
-- moments then pull back to clean. morph between modes for rapid texture shifts.
-- the bass should BREATHE — alternate between sub-heavy quiet and
-- gnarly aggressive peaks. never settle.

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
  },

  params = {
    ---------- PRIMARY: macro + destroy ----------
    destroy = {
      group = "timbral",
      weight = 0.8,
      sensitivity = 0.6,
      direction = "both",
      -- D-style decimation layer. robot should use this for
      -- brief bursts of chaos, not sustained destruction.
      -- push it up fast, pull back slow. dramatic weapon.
      range_lo = 0,
      range_hi = 0.85,
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
      weight = 0.85,
      sensitivity = 0.6,
      direction = "both",
      range_lo = 40,
      range_hi = 10000,
    },
    lp_filter_resonance = {
      group = "timbral",
      weight = 0.7,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 0,
      range_hi = 0.9,
    },
    chorus_mix = {
      group = "timbral",
      weight = 0.6,
      sensitivity = 0.5,
      direction = "both",
    },
    ring_mod_mix = {
      group = "timbral",
      weight = 0.6,
      sensitivity = 0.4,
      direction = "up",
      -- ring mod adds the gnarly. robot should push it up for aggression.
      range_lo = 0,
      range_hi = 0.8,
    },
    ring_mod_freq = {
      group = "timbral",
      weight = 0.5,
      sensitivity = 0.5,
      direction = "both",
      range_lo = 20,
      range_hi = 280,
    },
    sub_osc_level = {
      group = "timbral",
      weight = 0.55,
      sensitivity = 0.4,
      direction = "both",
    },
    noise_level = {
      group = "timbral",
      weight = 0.35,
      sensitivity = 0.3,
      direction = "up",
      range_lo = 0,
      range_hi = 0.45,
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
      weight = 0.3,
      sensitivity = 1.0,
      direction = "both",
      -- voice mode switches are BIG moments. robot should use
      -- these for dramatic shifts, not constant cycling.
    },
    bm_style = {
      group = "structural",
      weight = 0.25,
      sensitivity = 1.0,
      direction = "both",
    },
    bm_phrase = {
      group = "structural",
      weight = 0.15,
      sensitivity = 0.5,
      direction = "both",
    },
    bandmate_on = {
      group = "structural",
      weight = 0.2,
      sensitivity = 1.0,
      direction = "both",
      -- robot can turn bandmate on/off for texture shifts.
    },
    morph_on = {
      group = "structural",
      weight = 0.25,
      sensitivity = 1.0,
      direction = "both",
      -- morph creates rapid texture oscillation. dramatic tool.
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
      -- robot can shift its own personality. meta.
    },
  },
}
