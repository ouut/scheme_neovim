-- Steel Scheme REPL Engine for Neovim
local M = {}

M.config = {
  position = "right", -- "right" (垂直右侧分屏) 或 "bottom" (水平底部底栏)
  size = 65,          -- 宽度 (字符列数，若为 right) 或 高度 (行数，若为 bottom)
}

local state = {
  buf = nil,
  win = nil,
  job_id = nil,
}

---Configure REPL engine options
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

---Internal helper: Open the REPL split window at configured position
local function open_split()
  if M.config.position == "right" then
    local width = M.config.size or 65
    vim.cmd(string.format("botright vertical %dsplit", width))
  else
    local height = M.config.size or 12
    vim.cmd(string.format("botright %dsplit", height))
  end
end

---Ensure Steel REPL terminal buffer and window are open and ready
---@return number|nil job_id
function M.ensure_repl()
  -- If buffer is valid and job is alive
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.job_id then
    -- Check if window exists
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
      open_split()
      state.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(state.win, state.buf)
      -- Return focus to previous window
      vim.cmd("wincmd p")
    end
    return state.job_id
  end

  -- Save current window
  local prev_win = vim.api.nvim_get_current_win()

  -- Open split window according to configuration
  open_split()
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)

  -- Resolve steel executable path robustly
  local function get_steel_cmd()
    if vim.fn.executable("steel") == 1 then
      return "steel"
    end
    if vim.fn.executable("steel.exe") == 1 then
      return "steel.exe"
    end
    local steel_ide_dir = vim.env.STEEL_IDE_DIR
    if steel_ide_dir then
      local win_bin = steel_ide_dir .. "/bin/steel.exe"
      if vim.fn.executable(win_bin) == 1 then
        return win_bin
      end
      local unix_bin = steel_ide_dir .. "/bin/steel"
      if vim.fn.executable(unix_bin) == 1 then
        return unix_bin
      end
    end
    return "steel"
  end

  -- Start steel terminal
  state.job_id = vim.fn.termopen(get_steel_cmd(), {
    on_exit = function()
      state.job_id = nil
      state.buf = nil
      state.win = nil
    end,
  })

  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].bufhidden = "hide"

  -- Restore focus to editor window
  vim.api.nvim_set_current_win(prev_win)
  return state.job_id
end

---Close/Hide Steel REPL window (keeps background process alive)
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

---Toggle Steel REPL window visibility
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.ensure_repl()
  end
end

---Kill Steel REPL process and close window
function M.kill()
  if state.job_id then
    pcall(vim.fn.jobstop, state.job_id)
    state.job_id = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
    state.buf = nil
  end
  vim.notify("Steel REPL terminated", vim.log.levels.INFO)
end

---Send raw text string to the Steel REPL
---@param text string
function M.send_text(text)
  local job = M.ensure_repl()
  if not job then
    vim.notify("Failed to start Steel REPL", vim.log.levels.ERROR)
    return
  end

  -- Clean trailing whitespace
  text = vim.trim(text)
  if text == "" then
    return
  end

  local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  if is_win then
    text = text:gsub("\r?\n", "\r\n")
    if not text:match("\r\n$") then
      text = text .. "\r\n"
    end
  else
    text = text:gsub("\r\n", "\n")
    if not text:match("\n$") then
      text = text .. "\n"
    end
  end

  vim.fn.jobsend(job, text)

  -- Auto scroll terminal window to bottom
  if state.win and vim.api.nvim_win_is_valid(state.win) and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local line_count = vim.api.nvim_buf_line_count(state.buf)
    vim.api.nvim_win_set_cursor(state.win, { line_count, 0 })
  end
end

---Send visually selected code to Steel REPL
function M.eval_visual()
  -- Exit visual mode to set '< and '> marks
  vim.cmd([[execute "normal! \<ESC>"]])
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = math.abs(s_end[2] - s_start[2]) + 1
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
  if #lines == 0 then
    return
  end

  if n_lines == 1 then
    lines[1] = string.sub(lines[1], s_start[3], s_end[3])
  else
    lines[1] = string.sub(lines[1], s_start[3])
    lines[#lines] = string.sub(lines[#lines], 1, s_end[3])
  end

  local code = table.concat(lines, "\n")
  M.send_text(code)
end

---Get text of Treesitter node at cursor (or enclosing form)
function M.eval_current_form()
  local ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
  local text = nil

  if ok then
    local node = ts_utils.get_node_at_cursor()
    while node do
      local type = node:type()
      if type == "list" or type == "vector" or type == "program" or type:match("form") then
        break
      end
      local parent = node:parent()
      if not parent or parent:type() == "program" then
        break
      end
      node = parent
    end

    if node and node:type() ~= "program" then
      local start_row, start_col, end_row, end_col = node:range()
      local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
      text = table.concat(lines, "\n")
    end
  end

  -- Fallback to current line if Treesitter node not found
  if not text or text == "" then
    text = vim.api.nvim_get_current_line()
  end

  M.send_text(text)
end

---Send entire buffer to Steel REPL
function M.eval_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local code = table.concat(lines, "\n")
  M.send_text(code)
  vim.notify("Sent entire buffer to Steel REPL", vim.log.levels.INFO)
end

return M
