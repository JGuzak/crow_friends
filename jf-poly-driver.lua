-- A script for driving JF in poly synth mode.

local last_note_trigger_time = 0
local last_gate_state = false
local last_time_voltage = 5.0

-- TODO: trigger voices with just pitch changes as well as gates. In theory, the gate handler could be removed
function process_pitch_input(i)
  -- If notes overlap, trigger a new voice anyway
  if last_gate_state then
    ii.jf.play_note(input[1].volts, 5.0)
  end
end

function process_gate(state)
  -- ii.jf.get('time')
  last_gate_state = state
  if state then
    if (time() - last_note_trigger_time) > 5 then
      ii.jf.play_note(input[1].volts, 5.0)
    end
    last_note_trigger_time = time()
  end
end

-- TODO: add variable amplitude based on knob positions
-- ii.jf.event = function(e, value)
--   if e.name =="time" then
--     last_time_voltage = (10.0 - value) / 2.0
--   end
-- end

function init()
  crow.reset()
  ii.jf.mode(1)
  ii.jf.run_mode(1)

  -- input[1].mode("stream", 0.0001)
  -- input[1].change = function (x)
  --   delay(process_pitch_input(x), 0.0001)
  -- end

  input[2].mode("change", 4.0, 0.15, "both")
  input[2].change = function (x)
    delay(process_gate(x), 0.0001)
  end
end
