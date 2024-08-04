-- A script for driving JF in synth mode.

local last_note_trigger_time = 0
local last_gate_state = false
local last_time_voltage = 5.0

function pitch_input(i)
  -- If notes overlap, change pitch without retriggering
  if last_gate_state then
    ii.jf.play_note(input[1].volts, 4.0)
  end
end

function gate_input(state)
  last_gate_state = state
  if state then
    if (time() - last_note_trigger_time) > 5 then
      ii.wsyn.play_note(input[1].volts, 5.0)
    end
    last_note_trigger_time = time()
  end
end

function setup_callbacks()
  -- TODO: trigger voices with just pitch changes as well as gates.
  -- input[1].mode("stream", 0.0001)
  -- input[1].change = function (x)
  --   if pcall(delay(pitch_input(x), 0.0001)) then
  --   else
  --     print('failed to execute pitch_input callback')
  --   end
  -- end

  input[2].mode("change", 4.0, 0.15, "both")
  input[2].change = function (x)
    if pcall(delay(gate_input(x), 0.0001)) then
    else
      print('failed to execute gate_input callback')
    end
  end

  -- output[1].mode()
  -- output[2].mode()
  -- output[3].mode()
  -- output[4].mode()
end

function init()
  crow.reset()
  ii.wsyn.voices(15)

  -- TODO: Attach patch points to wsyn params

  delay(setup_callbacks(), 0.1)
end
