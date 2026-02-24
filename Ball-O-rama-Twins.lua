-- (AW) presents:
-- BALL-o-RAMA Twins
-- Two balls, one grid
-- cut in two
-- balls triggers a note
-- (best with grid)
-- GRID
-- press any cell
-- to toggle a block
-- NO GRID?
-- E1 turning adds/removes
-- blocks on BOTH halvese
-- BALL SPEED
-- E2: L-ball speed
-- E3: R-ball speed
-- RANDOM BLOCK MOVE (per side)
-- K1 held + E2: L-side
-- K1 held + E3: R-side 
-- SOUND SHAPE
-- K2 held + E2: L pitch
-- K3 held + E2: R pitch 
-- K2 held + E3: L release
-- K3 held + E3: R release
-- CLEAR (hold 1 second)
-- Hold K1+K2 clear L
-- Hold K1+K3 clear R
-- DELAY MODULATION (menu params)
-- BLOCK DESTRUCTION (menu param)

engine.name = "DualPerc"
MusicUtil = require "musicutil"
hs = include("lib/halfsecond")

g = grid.connect()
m = midi.connect()
local MIDI_VELOCITY = 100

local GRID_W = 16
local GRID_H = 8
local HALF_W = GRID_W / 2
local DT = 1/30

-- PERF: localize hot functions
local abs = math.abs
local floor = math.floor
local random = math.random
local clamp = util.clamp
local linlin = util.linlin
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local atan = math.atan
local pi = math.pi

------------------------------------------------------------
-- BALLS
------------------------------------------------------------

local function new_ball(xmin, xmax)
  return {
    x = random(xmin, xmax),
    y = random(1, GRID_H),
    vx = (random() - 0.5) * 0.6,
    vy = (random() - 0.5) * 0.6,
    -- debounce: trigger once per block until leaving
    last_block_x = -1,
    last_block_y = -1,
  }
end

local ball_left  = new_ball(1, HALF_W)
local ball_right = new_ball(HALF_W + 1, GRID_W)

------------------------------------------------------------
-- CELLS
------------------------------------------------------------

local cells_left = {}
local cells_right = {}
for x = 1, HALF_W do
  cells_left[x] = {}
  cells_right[x] = {}
  for y = 1, GRID_H do
    cells_left[x][y] = false
    cells_right[x][y] = false
  end
end

------------------------------------------------------------
-- FLASHES
------------------------------------------------------------

local ball_flash_left = 0
local ball_flash_right = 0
local BALL_FLASH_FRAMES = 4

local block_flash_left = {}
local block_flash_right = {}
for x = 1, HALF_W do
  block_flash_left[x] = {}
  block_flash_right[x] = {}
  for y = 1, GRID_H do
    block_flash_left[x][y] = 0
    block_flash_right[x][y] = 0
  end
end
local BLOCK_FLASH_FRAMES = 6

local function decay_flashes()
  if ball_flash_left > 0 then ball_flash_left = ball_flash_left - 1 end
  if ball_flash_right > 0 then ball_flash_right = ball_flash_right - 1 end

  for x = 1, HALF_W do
    local bl = block_flash_left[x]
    local br = block_flash_right[x]
    for y = 1, GRID_H do
      if bl[y] > 0 then bl[y] = bl[y] - 1 end
      if br[y] > 0 then br[y] = br[y] - 1 end
    end
  end
end

------------------------------------------------------------
-- MUSICAL
------------------------------------------------------------

local scale_notes = MusicUtil.generate_scale(60, 1, 2)
local root_note = scale_notes[1]
local freq_base = MusicUtil.note_num_to_freq(root_note)

local speed_left = 1
local speed_right = 1

local pitch_factor_left = 1
local pitch_factor_right = 1

local min_speed = 0.2

------------------------------------------------------------
-- KEYS
------------------------------------------------------------

local key1_held = false
local key2_held = false
local key3_held = false

local clear_left_clock = nil
local clear_right_clock = nil

------------------------------------------------------------
-- RANDOM MOVEMENT
------------------------------------------------------------

local random_speed_left = 0
local random_speed_right = 0

------------------------------------------------------------
-- INIT
------------------------------------------------------------

function init()
  hs.init()

  params:add_separator("BALL-o-RAMA-twins")

  ------------------------------------------------------------
  -- DELAY MODULATION
  ------------------------------------------------------------
  params:add_group("DELAY MODULATION", 5)
  params:add_option("auto_map", "auto map ball > delay", {"off", "on"}, 1)
  params:add_control("auto_map_depth", "map depth", controlspec.new(0.1, 2.0, "lin", 0, 1.0))
  params:add_option("mod_target", "controls", {"rate (x)", "feedback (y)", "both (x,y)"}, 3)
  params:add_option("delay_left_enable", "Left delay modulation", {"off", "on"}, 2)
  params:add_option("delay_right_enable", "Right delay modulation", {"off", "on"}, 2)

  ------------------------------------------------------------
  -- BLOCK DESTRUCTION
  ------------------------------------------------------------
  params:add_group("BLOCK DESTRUCTION", 1)
  params:add_option("block_destroy", "destroy blocks", {"off", "on"}, 2)

  ------------------------------------------------------------
  -- MIDI CHANNELS
  ------------------------------------------------------------
  params:add_group("MIDI CHANNELS", 2)
  params:add_option("midi_ch_left", "L-ball MIDI channel",
    {"1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16"}, 1)
  params:add_option("midi_ch_right", "R-ball MIDI channel",
    {"1","2","3","4","5","6","7","8","9","10","11","12","13","14","15","16"}, 1)

  ------------------------------------------------------------
  -- DUALPERC ENGINE PARAMS (persistent baseline)
  ------------------------------------------------------------
  params:add_group("DUALPERC ENGINE", 12)

  -- LEFT
  params:add_control("dp_amp_left", "L amp", controlspec.new(0, 1, "lin", 0, 0.3))
  params:set_action("dp_amp_left", function(v) engine.amp_left(v) end)

  params:add_control("dp_pw_left", "L pulse width", controlspec.new(0.05, 0.95, "lin", 0, 0.5))
  params:set_action("dp_pw_left", function(v) engine.pw_left(v) end)

  params:add_control("dp_release_left", "L release", controlspec.new(0.01, 2, "lin", 0, 0.5))
  params:set_action("dp_release_left", function(v) engine.release_left(v) end)

  params:add_control("dp_cutoff_left", "L cutoff", controlspec.new(100, 8000, "exp", 0, 1000))
  params:set_action("dp_cutoff_left", function(v) engine.cutoff_left(v) end)

  params:add_control("dp_gain_left", "L filter gain", controlspec.new(0.1, 4, "lin", 0, 2))
  params:set_action("dp_gain_left", function(v) engine.gain_left(v) end)

  params:add_control("dp_pitch_factor_left", "L pitch factor", controlspec.new(0.25, 4, "exp", 0, 1))
  params:set_action("dp_pitch_factor_left", function(v) pitch_factor_left = v end)

  -- RIGHT
  params:add_control("dp_amp_right", "R amp", controlspec.new(0, 1, "lin", 0, 0.3))
  params:set_action("dp_amp_right", function(v) engine.amp_right(v) end)

  params:add_control("dp_pw_right", "R pulse width", controlspec.new(0.05, 0.95, "lin", 0, 0.5))
  params:set_action("dp_pw_right", function(v) engine.pw_right(v) end)

  params:add_control("dp_release_right", "R release", controlspec.new(0.01, 2, "lin", 0, 0.5))
  params:set_action("dp_release_right", function(v) engine.release_right(v) end)

  params:add_control("dp_cutoff_right", "R cutoff", controlspec.new(100, 8000, "exp", 0, 1000))
  params:set_action("dp_cutoff_right", function(v) engine.cutoff_right(v) end)

  params:add_control("dp_gain_right", "R filter gain", controlspec.new(0.1, 4, "lin", 0, 2))
  params:set_action("dp_gain_right", function(v) engine.gain_right(v) end)

  params:add_control("dp_pitch_factor_right", "R pitch factor", controlspec.new(0.25, 4, "exp", 0, 1))
  params:set_action("dp_pitch_factor_right", function(v) pitch_factor_right = v end)

  params:bang()

  clock.run(update_loop)
  clock.run(random_movement_loop)
end

------------------------------------------------------------
-- DELAY AUTO-MAP (combined, avoids overwrite order)
------------------------------------------------------------

local function delay_from_ball(ball, depth)
  local rate_val = linlin(1, HALF_W, 0.05, 1.5, ball.x)
  local fb_val   = linlin(1, GRID_H, 0.1, 0.9, GRID_H - ball.y + 1)
  return clamp(rate_val * depth, 0.05, 2.0), clamp(fb_val * depth, 0.0, 0.95)
end

local function update_delay_mapping()
  if params:get("auto_map") ~= 2 then return end

  local depth  = params:get("auto_map_depth")
  local target = params:get("mod_target")

  local use_l = (params:get("delay_left_enable") == 2)
  local use_r = (params:get("delay_right_enable") == 2)
  if not use_l and not use_r then return end

  local rate, fb

  if use_l and use_r then
    local lr, lf = delay_from_ball(ball_left, depth)
    local rr, rf = delay_from_ball(ball_right, depth)
    rate = (lr + rr) * 0.5
    fb   = (lf + rf) * 0.5
  elseif use_l then
    rate, fb = delay_from_ball(ball_left, depth)
  else
    rate, fb = delay_from_ball(ball_right, depth)
  end

  if target == 1 or target == 3 then params:set("delay_rate", rate) end
  if target == 2 or target == 3 then params:set("delay_feedback", fb) end
end

------------------------------------------------------------
-- UPDATE LOOP
------------------------------------------------------------

function update_loop()
  while true do
    clock.sleep(DT)

    update_delay_mapping()

    update_ball(ball_left, cells_left, block_flash_left, true)
    update_ball(ball_right, cells_right, block_flash_right, false)

    decay_flashes()

    redraw()
    if g then gridredraw() end
  end
end

------------------------------------------------------------
-- RANDOM MOVEMENT (optimized: avoid building full list each move)
------------------------------------------------------------

local function find_random_filled_cell(cells)
  -- try random sampling first (fast, no allocations)
  for _ = 1, 24 do
    local x = random(1, HALF_W)
    local y = random(1, GRID_H)
    if cells[x][y] then return x, y end
  end
  -- fallback scan
  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if cells[x][y] then return x, y end
    end
  end
  return nil, nil
end

local function move_one_block(cells)
  local x, y = find_random_filled_cell(cells)
  if not x then return end

  local dir = random(4)
  local nx, ny = x, y
  if dir == 1 then ny = y - 1
  elseif dir == 2 then ny = y + 1
  elseif dir == 3 then nx = x - 1
  else nx = x + 1 end

  if nx < 1 or nx > HALF_W or ny < 1 or ny > GRID_H then return end
  if cells[nx][ny] then return end

  cells[x][y] = false
  cells[nx][ny] = true
end

local function apply_random(cells, speed)
  local n = floor(speed)
  for i = 1, n do
    move_one_block(cells)
  end
end

function random_movement_loop()
  while true do
    clock.sleep(0.2)
    local changed = false

    if random_speed_left > 0 then
      apply_random(cells_left, random_speed_left)
      changed = true
    end
    if random_speed_right > 0 then
      apply_random(cells_right, random_speed_right)
      changed = true
    end

    if changed and g then gridredraw() end
  end
end

------------------------------------------------------------
-- BALL PHYSICS
------------------------------------------------------------

local function jitter_bounce(ball, ix, iy)
  local speed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
  local angle = atan(ball.vy, ball.vx)

  angle = pi - angle

  local dx = ball.x - ix
  local dy = ball.y - iy

  local max_jitter = pi / 12
  angle = angle
        + dx * (pi / 8)
        + dy * (pi / 8)
        + (random() * 2 - 1) * max_jitter

  ball.vx = cos(angle) * speed
  ball.vy = sin(angle) * speed
end

function update_ball(ball, cells, block_flash, is_left)
  local speed = is_left and speed_left or speed_right

  ball.x = ball.x + ball.vx * speed
  ball.y = ball.y + ball.vy * speed

  local x_min = is_left and 1 or HALF_W + 1
  local x_max = is_left and HALF_W or GRID_W

  if ball.x < x_min then ball.x = x_min; ball.vx = abs(ball.vx) end
  if ball.x > x_max then ball.x = x_max; ball.vx = -abs(ball.vx) end
  if ball.y < 1 then ball.y = 1; ball.vy = abs(ball.vy) end
  if ball.y > GRID_H then ball.y = GRID_H; ball.vy = -abs(ball.vy) end

  local ix = floor(ball.x + 0.5)
  local iy = floor(ball.y + 0.5)
  local cx = is_left and ix or (ix - HALF_W)

  if cells[cx][iy] then
    -- trigger only if NEW block
    if cx ~= ball.last_block_x or iy ~= ball.last_block_y then
      play_cell_sound(cx, iy, is_left)

      if is_left then ball_flash_left = BALL_FLASH_FRAMES else ball_flash_right = BALL_FLASH_FRAMES end
      block_flash[cx][iy] = BLOCK_FLASH_FRAMES

      jitter_bounce(ball, ix, iy)

      if abs(ball.vx) < min_speed then ball.vx = min_speed * (ball.vx < 0 and -1 or 1) end
      if abs(ball.vy) < min_speed then ball.vy = min_speed * (ball.vy < 0 and -1 or 1) end

      -- push out so we can leave the cell
      ball.x = ball.x + ball.vx * 0.1
      ball.y = ball.y + ball.vy * 0.1

      ball.last_block_x = cx
      ball.last_block_y = iy
    end
  else
    ball.last_block_x = -1
    ball.last_block_y = -1
  end
end

------------------------------------------------------------
-- BLOCK EXPLOSION
------------------------------------------------------------

function explode_block(x, y, cells)
  for i = math.max(1, x - 1), math.min(HALF_W, x + 1) do
    for j = math.max(1, y - 1), math.min(GRID_H, y + 1) do
      cells[i][j] = false
    end
  end
end

------------------------------------------------------------
-- SOUND TRIGGER (freq_base cached)
------------------------------------------------------------

function play_cell_sound(cx, y, is_left)
  local freq
  if is_left then
    freq = freq_base * pitch_factor_left * (1 + (y - 1) / GRID_H * 2)
    engine.hz_left(freq)
  else
    freq = freq_base * pitch_factor_right * (1 + (y - 1) / GRID_H * 2)
    engine.hz_right(freq)
  end

  local note_num = root_note + (y - 1)
  local ch = is_left and params:get("midi_ch_left") or params:get("midi_ch_right")

  m:note_on(note_num, MIDI_VELOCITY, ch)
  clock.run(function()
    clock.sleep(0.2)
    m:note_off(note_num, MIDI_VELOCITY, ch)
  end)
end

------------------------------------------------------------
-- REDRAW
------------------------------------------------------------

function redraw()
  local RECT_SIZE = 5
  local OFFSET = 2
  screen.clear()

  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if cells_left[x][y] then
        screen.level(15)
        screen.rect((x - 1) * 8 + OFFSET, (y - 1) * 8 + OFFSET, RECT_SIZE, RECT_SIZE)
        if block_flash_left[x][y] > 0 then screen.fill() else screen.stroke() end
      end
    end
  end

  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if cells_right[x][y] then
        screen.level(15)
        screen.rect((x - 1 + HALF_W) * 8 + OFFSET, (y - 1) * 8 + OFFSET, RECT_SIZE, RECT_SIZE)
        if block_flash_right[x][y] > 0 then screen.fill() else screen.stroke() end
      end
    end
  end

  screen.level(15)
  screen.circle((ball_left.x - 1) * 8 + 4, (ball_left.y - 1) * 8 + 4, 3)
  if ball_flash_left > 0 then screen.fill() else screen.stroke() end

  screen.circle((ball_right.x - 1) * 8 + 4, (ball_right.y - 1) * 8 + 4, 3)
  if ball_flash_right > 0 then screen.fill() else screen.stroke() end

  screen.level(5)
  local mid_x = 64
  for y = 0, 63, 6 do
    screen.move(mid_x, y)
    screen.line(mid_x, y + 3)
    screen.stroke()
  end

  screen.update()
end

------------------------------------------------------------
-- GRID
------------------------------------------------------------

function gridredraw()
  if not g then return end
  g:all(0)

  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if cells_left[x][y] then
        local lvl = (block_flash_left[x][y] > 0) and 0 or 8
        g:led(x, y, lvl)
      end
    end
  end

  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if cells_right[x][y] then
        local lvl = (block_flash_right[x][y] > 0) and 0 or 8
        g:led(x + HALF_W, y, lvl)
      end
    end
  end

  local bx_l = floor(ball_left.x + 0.5)
  local by_l = floor(ball_left.y + 0.5)
  g:led(bx_l, by_l, 15)

  local bx_r = floor(ball_right.x + 0.5)
  local by_r = floor(ball_right.y + 0.5)
  g:led(bx_r, by_r, 15)

  g:refresh()
end

function g.key(x, y, z)
  if z > 0 then
    if x <= HALF_W then
      cells_left[x][y] = not cells_left[x][y]
    else
      local cx = x - HALF_W
      cells_right[cx][y] = not cells_right[cx][y]
    end
    gridredraw()
  end
end

------------------------------------------------------------
-- RANDOM BLOCKS VIA ENC1
------------------------------------------------------------

local function random_blocks_for_cells(cells, d)
  local empty_cells = {}
  local filled_cells = {}
  for x = 1, HALF_W do
    for y = 1, GRID_H do
      if not cells[x][y] then
        empty_cells[#empty_cells + 1] = {x = x, y = y}
      else
        filled_cells[#filled_cells + 1] = {x = x, y = y}
      end
    end
  end

  local count = math.ceil(2 ^ math.abs(d) - 1)
  if d > 0 then
    count = math.min(count, #empty_cells)
    for i = 1, count do
      local idx = random(1, #empty_cells)
      local cell = empty_cells[idx]
      cells[cell.x][cell.y] = true
      table.remove(empty_cells, idx)
    end
  elseif d < 0 then
    count = math.min(count, #filled_cells)
    for i = 1, count do
      local idx = random(1, #filled_cells)
      local cell = filled_cells[idx]
      cells[cell.x][cell.y] = false
      table.remove(filled_cells, idx)
    end
  end
end

------------------------------------------------------------
-- ENCODERS
------------------------------------------------------------

function enc(n, d)
  if n == 1 then
    random_blocks_for_cells(cells_left, d)
    random_blocks_for_cells(cells_right, d)
    gridredraw()

  elseif n == 2 then
    if key1_held then
      random_speed_left = clamp(random_speed_left + d * 0.2, 0, 20)
    elseif key2_held then
      local v = clamp(params:get("dp_pitch_factor_left") + d * 0.05, 0.25, 4)
      params:set("dp_pitch_factor_left", v)
    elseif key3_held then
      local v = clamp(params:get("dp_pitch_factor_right") + d * 0.05, 0.25, 4)
      params:set("dp_pitch_factor_right", v)
    else
      speed_left = clamp(speed_left + d * 0.05, 0.1, 3)
    end

  elseif n == 3 then
    if key1_held then
      random_speed_right = clamp(random_speed_right + d * 0.2, 0, 20)
    elseif key2_held then
      local v = clamp(params:get("dp_release_left") + d * 0.05, 0.01, 2)
      params:set("dp_release_left", v)
    elseif key3_held then
      local v = clamp(params:get("dp_release_right") + d * 0.05, 0.01, 2)
      params:set("dp_release_right", v)
    else
      speed_right = clamp(speed_right + d * 0.05, 0.1, 3)
    end
  end
end

------------------------------------------------------------
-- CLEAR AREAS
------------------------------------------------------------

local function clear_left()
  for x = 1, HALF_W do
    for y = 1, GRID_H do
      cells_left[x][y] = false
    end
  end
  gridredraw()
end

local function clear_right()
  for x = 1, HALF_W do
    for y = 1, GRID_H do
      cells_right[x][y] = false
    end
  end
  gridredraw()
end

------------------------------------------------------------
-- KEYS
------------------------------------------------------------

function key(n, z)
  if n == 1 then
    key1_held = (z > 0)

    if not key1_held then
      if clear_left_clock then clock.cancel(clear_left_clock) end
      if clear_right_clock then clock.cancel(clear_right_clock) end
      clear_left_clock = nil
      clear_right_clock = nil
    end

  elseif n == 2 then
    key2_held = (z > 0)

    if key1_held and key2_held and z > 0 then
      clear_left_clock = clock.run(function()
        clock.sleep(1.0)
        if key1_held and key2_held then clear_left() end
      end)
    elseif z == 0 and clear_left_clock then
      clock.cancel(clear_left_clock)
      clear_left_clock = nil
    end

  elseif n == 3 then
    key3_held = (z > 0)

    if key1_held and key3_held and z > 0 then
      clear_right_clock = clock.run(function()
        clock.sleep(1.0)
        if key1_held and key3_held then clear_right() end
      end)
    elseif z == 0 and clear_right_clock then
      clock.cancel(clear_right_clock)
      clear_right_clock = nil
    end
  end
end
