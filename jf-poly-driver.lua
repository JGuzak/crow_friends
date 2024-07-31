-- A script for driving JF in poly synth mode.


local voice_pitches = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0}
local curernt_voice = 1
local gate_state = false


function next_voice(voice)
  voice = voice + 1
  if voice > 6 then
    return 1
  end

  return voice
end

function on_gate_change(gate)
  -- print("   raw pitch: " ..input[1].volts)
  gate_state = gate
  if gate_state then
    print("note played")
    ii.jf.play_voice(curernt_voice, input[1].volts, 5.0 )
    curernt_voice = next_voice(curernt_voice)
  else
    print("note released")
  end
end

function process_pitch(i)
  print("voltage: " .. i.volts)
  -- if current_pitch_voltage ~= i.volts then
  --   last_pitch_voltage = current_pitch_voltage
  --   current_pitch_voltage = i.volts
  -- end
  -- last_voice = ((last_voice + 1) % 6) + 1
  -- ii.jf.play_voice(last_voice, last_pitch_voltage, 5.0 )

  if gate_state then
    ii.jf.play_note(i.volts, 5.0 )
  else
  end
end

function init()
  ii.jf.mode(1)
  ii.jf.run_mode(1)

  input[1].mode ("scale", {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11})
  input[1].scale = process_pitch

  input[2].mode ("change", 1.0, 0.1, "both")
  input[2].change = on_gate_change
end
