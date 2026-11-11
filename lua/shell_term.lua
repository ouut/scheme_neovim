-- Bottom Shell Terminal Manager for Neovim
local M = {}

M.config = {
  height = 12,
}

local state = {
  buf = nil,
  win = nil,
  job_id = nil,
  prev_win = nil,
}

---Ensure bottom shell terminal window is open
---@return number|nil job_id
function M.ensure_term()
  -- If buffer is already valid and process is alive
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and state.job_id then
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
      state.prev_win = vim.api.nvim_get_current_win()
      vim.cmd(string.format("botright %dsplit", M.config.height))
      state.win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(state.win, state.buf)
      vim.cmd("startinsert")
    else
      -- If already open, switch focus to it
      vim.api.nvim_set_current_win(state.win)
      vim.cmd("startinsert")
    end
    return state.job_id
  end

  -- Record previous window before opening
  state.prev_win = vim.api.nvim_get_current_win()

  -- Open bottom split
  vim.cmd(string.format("botright %dsplit", M.config.height))
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)

  -- Get default system shell (bash / zsh / pwsh)
  local shell = vim.o.shell
  if not shell or shell == "" then
    shell = os.getenv("SHELL") or (vim.fn.has("win32") == 1 and "cmd.exe" or "/bin/sh")
  end

  state.job_id = vim.fn.termopen(shell, {
    on_exit = function()
      state.job_id = nil
      state.buf = nil
      state.win = nil
    end,
  })

  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].bufhidden = "hide"

  -- Auto enter insert mode in terminal
  vim.cmd("startinsert")
  return state.job_id
end

---Close/Hide the bottom shell window (keeps running process alive)
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
  -- Return focus to previous code window if valid
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    vim.api.nvim_set_current_win(state.prev_win)
  end
end

---Toggle bottom shell terminal visibility
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.ensure_term()
  end
end

return M
