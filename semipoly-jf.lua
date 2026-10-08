-- Just Friends: pitch on input 1, gates on input 2.
-- Match every detected rising gate to captured ADC-frame data.
-- No time debounce, per-note timers, coroutines, or overwriting pending notes.
-- Druid: semipoly_status(); semipoly_samples(2) to try more pitch lookahead.

local DEFAULT_LOOKAHEAD = 1 -- ADC frames after the gate; one frame is about 0.667 ms.
local MAX_LOOKAHEAD = 8
local HISTORY_SIZE = 16
local QUEUE_SIZE = 16
local FRAME_WRAP = 65536 -- Bounded frame arithmetic, including long runs.
local ERROR_LOG_INTERVAL_MS = 1000

local lookahead = DEFAULT_LOOKAHEAD
local frame = 0
local latest_pitch = nil
local queue_head, queue_count = 1, 0
local last_gate_state = false
local last_error_print_time = nil
local history, notes, stats = {}, {}, {}

-- Allocate fixed storage once. Event callbacks only update existing records.
for i = 1, HISTORY_SIZE do history[i] = {frame = -1, pitch = 0} end
for i = 1, QUEUE_SIZE do
  notes[i] = {gate_frame = 0, lookahead = 1, gate_pitch = 0,
              closed = false, end_frame = 0, id = 0}
end

local function age(newer, older)
  return (newer - older) % FRAME_WRAP
end

local function reset_state()
  frame, latest_pitch = 0, nil
  queue_head, queue_count = 1, 0
  last_gate_state = false
  last_error_print_time = nil
  for i = 1, HISTORY_SIZE do history[i].frame = -1 end
  stats.edges, stats.rises, stats.note_calls, stats.samples = 0, 0, 0, 0
  stats.errors, stats.overflow, stats.missing_samples = 0, 0, 0
  stats.clipped_windows, stats.short_windows, stats.max_pending = 0, 0, 0
  stats.last_error = nil
  stats.last_edge_pitch, stats.last_sent_pitch = nil, nil
  stats.last_capture_frames, stats.last_commit_frames, stats.last_note_id = nil, nil, nil
end

reset_state()

local function report_error(where, err)
  stats.errors = stats.errors + 1
  stats.last_error = where .. ': ' .. tostring(err)
  local now = time()
  if last_error_print_time == nil or now < last_error_print_time
      or now - last_error_print_time >= ERROR_LOG_INTERVAL_MS then
    last_error_print_time = now
    print('semipoly-jf error: ' .. stats.last_error)
  end
end

local function send_note(pitch)
  ii.jf.play_note(pitch, 5.0)
end

local function drain_notes()
  while queue_count > 0 do
    local note = notes[queue_head]
    local elapsed = age(frame, note.gate_frame)
    -- Wait one extra frame before committing the target sample: input 1's
    -- stream event precedes input 2's gate event from that same ADC frame.
    if not note.closed and elapsed <= note.lookahead then return end

    local capture_age = note.lookahead
    if note.closed then
      local window_age = age(note.end_frame, note.gate_frame)
      if window_age < capture_age then
        capture_age = window_age
        stats.clipped_windows = stats.clipped_windows + 1
      end
    end
    if capture_age == 0 then stats.short_windows = stats.short_windows + 1 end
    local capture_frame = (note.gate_frame + capture_age) % FRAME_WRAP
    local sample = history[capture_frame % HISTORY_SIZE + 1]

    -- Pop BEFORE the JF call. One Lua send error must not block later notes.
    queue_head = queue_head % QUEUE_SIZE + 1
    queue_count = queue_count - 1
    if sample.frame ~= capture_frame then
      stats.missing_samples = stats.missing_samples + 1
      report_error('pitch history', 'required captured sample is unavailable')
    else
      local ok, err = pcall(send_note, sample.pitch)
      if ok then
        stats.note_calls = stats.note_calls + 1 -- A returned Lua call, not a JF acknowledgement.
        stats.last_edge_pitch, stats.last_sent_pitch = note.gate_pitch, sample.pitch
        stats.last_capture_frames, stats.last_commit_frames = capture_age, elapsed
        stats.last_note_id = note.id
      else
        report_error('note', err)
      end
    end
  end
end

function pitch_stream(volts)
  frame = (frame + 1) % FRAME_WRAP
  stats.samples = stats.samples + 1
  latest_pitch = volts
  local sample = history[frame % HISTORY_SIZE + 1]
  sample.frame, sample.pitch = frame, volts
  -- Use captured callback values, never a later read of input[1].volts.
  drain_notes()
end

local function protected_pitch_stream(volts)
  local ok, err = pcall(pitch_stream, volts)
  if not ok then report_error('pitch stream', err) end
end

function gate_input(state)
  stats.edges = stats.edges + 1
  last_gate_state = state
  if not state then return end -- Falling edges do not cancel queued notes.
  stats.rises = stats.rises + 1

  if queue_count > 0 then
    local previous = notes[(queue_head + queue_count - 2) % QUEUE_SIZE + 1]
    previous.closed = true
    -- A new gate closes the old note's pitch window BEFORE the new gate frame.
    -- Same-frame triggers have no distinct post-gate sample; retain their
    -- triggers with the gate-frame sample and expose short_windows instead.
    previous.end_frame = frame == previous.gate_frame and frame
                        or (frame - 1) % FRAME_WRAP
  end

  if queue_count == QUEUE_SIZE then
    stats.overflow = stats.overflow + 1
    report_error('gate queue', 'full; detected gate could not be retained')
    return -- Never overwrite an earlier pending note.
  end
  local note = notes[(queue_head + queue_count - 1) % QUEUE_SIZE + 1]
  note.gate_frame, note.lookahead, note.gate_pitch = frame, lookahead, latest_pitch
  note.closed, note.end_frame, note.id = false, frame, stats.rises
  queue_count = queue_count + 1
  if queue_count > stats.max_pending then stats.max_pending = queue_count end
end

local function protected_gate_input(state)
  local ok, err = pcall(gate_input, state)
  if not ok then report_error('gate', err) end
end

function setup_callbacks()
  input[1].stream = protected_pitch_stream
  input[2].change = protected_gate_input
  -- Crow clamps this request to one ADC block, about 1500 samples/second.
  input[1].mode('stream', 0.0005)
  input[2].mode('change', 4.0, 0.15, 'both')
end

function semipoly_samples(n)
  if n ~= nil then
    if type(n) ~= 'number' or n < 1 or n > MAX_LOOKAHEAD or n % 1 ~= 0 then
      error('pitch lookahead must be a whole number from 1 to 8 ADC samples')
    end
    lookahead = n -- Pending records retain their own captured setting.
  end
  print('semipoly-jf lookahead=' .. lookahead .. ' ADC sample(s), plus one commit frame')
end

function semipoly_status()
  local clocks = 0
  if clock and clock.threads then
    for _ in pairs(clock.threads) do clocks = clocks + 1 end
  end
  print(string.format(
    'semipoly-jf: edges=%d rises=%d note_calls=%d pending=%d max_pending=%d',
    stats.edges, stats.rises, stats.note_calls, queue_count, stats.max_pending))
  print(string.format(
    'samples=%d lookahead=%d clipped_windows=%d short_windows=%d',
    stats.samples, lookahead, stats.clipped_windows, stats.short_windows))
  print(string.format(
    'overflow=%d missing_samples=%d errors=%d lua_kb=%.1f clocks=%d',
    stats.overflow, stats.missing_samples, stats.errors, collectgarbage('count'), clocks))
  print(string.format('gate=%s pitch_v=%.5f gate_v=%.3f',
    tostring(last_gate_state), input[1].volts, input[2].volts))
  if stats.last_sent_pitch ~= nil then
    print(string.format(
      'note_id=%d sampled_pitch_v=%.5f capture_frames=%d commit_frames=%d',
      stats.last_note_id, stats.last_sent_pitch, stats.last_capture_frames, stats.last_commit_frames))
    if stats.last_edge_pitch ~= nil then
      print(string.format('edge_pitch_v=%.5f delta_cents=%.2f',
        stats.last_edge_pitch, (stats.last_sent_pitch - stats.last_edge_pitch) * 1200))
    end
  end
  if stats.last_error then print('last_error: ' .. stats.last_error) end
end

function init()
  crow.reset()
  reset_state()
  ii.jf.mode(1)
  ii.jf.run_mode(1)
  setup_callbacks()
end
