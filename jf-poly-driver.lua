-- A script for driving JF in poly synth mode.

local last_note_trigger_time = 0

function roughly_equivalent(value, comparator, delta)
  lower_bound = comparator - delta
  upper_bound = comparator + delta

  if lower_bound <= value and value <= upper_bound then
    return true
  end

  return false
end

function process_pitch(i)
  print("note: " .. i.note)

  if (time() - last_note_trigger_time) > 20 then
    ii.jf.play_note(i.note/12, 5.0)
  end
  -- if gate_state then
  -- end
  -- last_callback_changed_pitch = true
  last_note_trigger_time = time()
  -- print(last_note_trigger_time)
end

function init()
  crow.reset()
  ii.jf.mode(1)
  ii.jf.run_mode(1)

  input[1].mode("scale", {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11})
  -- input[1].hysteresis = 0.4
  -- input[1].time = 0.15
  input[1].scale = process_pitch
end
