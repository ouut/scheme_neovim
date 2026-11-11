-- Steel Scheme REPL Plugin Integration
return {
  name = "steel-repl",
  dir = "/workspace/scheme_neovim",
  opts = {
    position = "right", -- "right" (垂直在右侧打开，经典Lisp布局) 或 "bottom" (在底部打开)
    size = 65,          -- 宽度 (字符列数，若为 right) 或高度 (行数，若为 bottom)
  },
  config = function(_, opts)
    local repl = require("steel_repl")
    repl.setup(opts)

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
    -- Scheme 专属求值快捷键
    -- -------------------------------------------------------------------------
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "scheme" },
      callback = function(ev)
        local key_opts = { buffer = ev.buf, silent = true }

        -- Shortcut 2: Alt + Enter / Ctrl + Enter (发射求值 / Eval REPL，未打开时自动拉起)
        vim.keymap.set("v", "<M-CR>", repl.eval_visual, vim.tbl_extend("force", key_opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("v", "<C-CR>", repl.eval_visual, vim.tbl_extend("force", key_opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("n", "<M-CR>", repl.eval_current_form, vim.tbl_extend("force", key_opts, { desc = "Eval Form in Steel REPL" }))
        vim.keymap.set("n", "<C-CR>", repl.eval_current_form, vim.tbl_extend("force", key_opts, { desc = "Eval Form in Steel REPL" }))

        -- 发送整个文件求值
        vim.keymap.set("n", "<leader>sb", repl.eval_buffer, vim.tbl_extend("force", key_opts, { desc = "Eval Buffer in Steel REPL" }))
      end,
    })
  end,
}
