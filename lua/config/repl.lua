-- Steel Scheme REPL Integration
local repl = require("steel_repl")
repl.setup({
  position = "right", -- "right" (垂直在右侧打开，经典Lisp布局) 或 "bottom" (在底部打开)
  size = 65,          -- 宽度 (字符列数，若为 right) 或高度 (行数，若为 bottom)
})

-- Global user commands for easy REPL management
vim.api.nvim_create_user_command("SteelRepl", repl.toggle, { desc = "Toggle Steel REPL" })
vim.api.nvim_create_user_command("SteelClose", repl.close, { desc = "Close Steel REPL window" })
vim.api.nvim_create_user_command("SteelKill", repl.kill, { desc = "Kill Steel REPL process" })
vim.api.nvim_create_user_command("SteelSendBuffer", repl.eval_buffer, { desc = "Send entire buffer to Steel REPL" })

-- -------------------------------------------------------------------------
-- 全局快捷键 (Global Shortcuts)
-- 遵循 docs/strict_paredit_guide.md 单发理念：Alt + R (Mac: ⌥ R) 一键秒开/秒关
-- -------------------------------------------------------------------------
-- 1. 普通模式按 Alt + R：切换展开/收起 REPL
vim.keymap.set("n", "<M-r>", repl.toggle, { silent = true, desc = "Toggle Steel REPL (One-Shot Alt+R)" })
-- 2. 终端模式内按 Alt + R：直接收起 REPL 并光标回到代码编辑器
vim.keymap.set("t", "<M-r>", repl.close, { silent = true, desc = "Close Steel REPL from terminal (Alt+R)" })

-- 全局 Leader 快捷键支持 (Space + s + ...)
vim.keymap.set("n", "<leader>so", repl.toggle, { silent = true, desc = "Toggle (open/hide) Steel REPL" })
vim.keymap.set("n", "<leader>sc", repl.close, { silent = true, desc = "Close (hide) Steel REPL window" })
vim.keymap.set("n", "<leader>sq", repl.kill, { silent = true, desc = "Kill & Quit Steel REPL process" })

-- -------------------------------------------------------------------------
-- 求值与发射快捷键 (Eval Keymaps)
-- 委托至 strict_paredit.eval_repl (具备视觉闪烁、多表达式 begin 事务包裹)
-- -------------------------------------------------------------------------
local function register_eval_keys(bufnr)
  local key_opts = bufnr and { buffer = bufnr, silent = true } or { silent = true }
  local eval_fn = function()
    require("strict_paredit").eval_repl()
  end

  -- 可视与普通模式统一发射
  vim.keymap.set({ "n", "v" }, "<M-CR>", eval_fn, vim.tbl_extend("force", key_opts, { desc = "Eval in Steel REPL (Alt+Enter)" }))
  vim.keymap.set({ "n", "v" }, "<C-CR>", eval_fn, vim.tbl_extend("force", key_opts, { desc = "Eval in Steel REPL (Ctrl+Enter)" }))
  vim.keymap.set({ "n", "v" }, "<M-e>", eval_fn, vim.tbl_extend("force", key_opts, { desc = "Eval in Steel REPL (Alt+E)" }))
  vim.keymap.set({ "n", "v" }, "<leader>se", eval_fn, vim.tbl_extend("force", key_opts, { desc = "Eval in Steel REPL" }))
  vim.keymap.set({ "n", "v" }, "<leader><CR>", eval_fn, vim.tbl_extend("force", key_opts, { desc = "Eval in Steel REPL" }))

  -- 发送整个缓冲区文件求值
  vim.keymap.set("n", "<leader>sb", repl.eval_buffer, vim.tbl_extend("force", key_opts, { desc = "Eval Buffer in Steel REPL" }))
end

-- 全局注册（无名缓冲、草稿页开箱即可求值）
register_eval_keys(nil)

-- Scheme 专属缓冲覆盖注册
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "scheme" },
  callback = function(ev)
    register_eval_keys(ev.buf)
  end,
})
