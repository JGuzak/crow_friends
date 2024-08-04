-- A script for driving JF in synth mode.

local last_note_trigger_time = 0
local last_gate_state = false
local last_time_voltage = 5.0

-- TODO: track cv + knob positions
-- ii.jf.event = function(e, value)
--   if e.name =="time" then
--     last_time_voltage = (10.0 - value) / 2.0
--   end
-- end

function pitch_input(i)
  -- If notes overlap, trigger a new voice anyway
  if last_gate_state then
    ii.jf.play_note(input[1].volts, 4.0)
  end
end

function gate_input(state)
  last_gate_state = state
  if state then
    if (time() - last_note_trigger_time) > 5 then
      ii.jf.play_note(input[1].volts, 5.0)
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

  -- TODO: setup outputs https://monome.org/docs/crow/reference/#output
  -- output[1].mode()
  -- output[2].mode()
  -- output[3].mode()
  -- output[4].mode()
end

function init()
  crow.reset()
  ii.jf.mode(1)
  ii.jf.run_mode(1)

  delay(setup_callbacks(), 0.1)
end
