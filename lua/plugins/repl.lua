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

    -- Scheme filetype specific keymaps
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "scheme" },
      callback = function(ev)
        local key_opts = { buffer = ev.buf, silent = true }

        -- Shortcut 2: Alt + Enter / Ctrl + Enter (发射求值 / Eval REPL)
        vim.keymap.set("v", "<M-CR>", repl.eval_visual, vim.tbl_extend("force", key_opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("v", "<C-CR>", repl.eval_visual, vim.tbl_extend("force", key_opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("n", "<M-CR>", repl.eval_current_form, vim.tbl_extend("force", key_opts, { desc = "Eval Form in Steel REPL" }))
        vim.keymap.set("n", "<C-CR>", repl.eval_current_form, vim.tbl_extend("force", key_opts, { desc = "Eval Form in Steel REPL" }))

        -- REPL Window Management Keymaps
        vim.keymap.set("n", "<leader>so", repl.toggle, vim.tbl_extend("force", key_opts, { desc = "Toggle (open/hide) Steel REPL" }))
        vim.keymap.set("n", "<leader>sc", repl.close, vim.tbl_extend("force", key_opts, { desc = "Close (hide) Steel REPL window" }))
        vim.keymap.set("n", "<leader>sq", repl.kill, vim.tbl_extend("force", key_opts, { desc = "Kill & Quit Steel REPL process" }))
        vim.keymap.set("n", "<leader>sb", repl.eval_buffer, vim.tbl_extend("force", key_opts, { desc = "Eval Buffer in Steel REPL" }))
      end,
    })
  end,
}
