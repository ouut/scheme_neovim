-- Bottom Shell Terminal Integration
return {
  name = "shell-terminal",
  dir = "/workspace/scheme_neovim",
  config = function()
    local term = require("shell_term")

    -- User commands
    vim.api.nvim_create_user_command("Terminal", term.toggle, { desc = "Toggle bottom shell terminal" })
    vim.api.nvim_create_user_command("ShellToggle", term.toggle, { desc = "Toggle bottom shell terminal" })
    vim.api.nvim_create_user_command("ShellClose", term.close, { desc = "Close bottom shell terminal" })

    -- -------------------------------------------------------------------------
    -- 1. 单发核心快捷键: Alt + T (Mac: ⌥ T, T = Terminal)
    -- 与 Alt + R (REPL) 完美呼应，遵循 One-Shot 哲学
    -- -------------------------------------------------------------------------
    vim.keymap.set("n", "<M-t>", term.toggle, { silent = true, desc = "Toggle Bottom Shell (Alt+T)" })
    vim.keymap.set("t", "<M-t>", term.close, { silent = true, desc = "Close Bottom Shell from terminal (Alt+T)" })

    -- -------------------------------------------------------------------------
    -- 2. 常用 IDE 习惯快捷键: Ctrl + ` (反引号，类似 VS Code)
    -- -------------------------------------------------------------------------
    vim.keymap.set("n", "<C-`>", term.toggle, { silent = true, desc = "Toggle Bottom Shell (Ctrl+`)" })
    vim.keymap.set("t", "<C-`>", term.close, { silent = true, desc = "Close Bottom Shell from terminal (Ctrl+`)" })

    -- -------------------------------------------------------------------------
    -- 3. Leader 系列快捷键: Space + t + t
    -- -------------------------------------------------------------------------
    vim.keymap.set("n", "<leader>tt", term.toggle, { silent = true, desc = "Toggle Bottom Shell (Leader tt)" })
  end,
}
