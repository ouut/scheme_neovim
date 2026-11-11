-- Steel Scheme REPL Plugin Integration
return {
  name = "steel-repl",
  dir = "/workspace/scheme_neovim",
  config = function()
    local repl = require("steel_repl")

    -- Set filetype-specific keymaps for Scheme
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "scheme" },
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }

        -- Shortcut 2: Alt + Enter / Ctrl + Enter (发射求值 / Eval REPL)
        vim.keymap.set("v", "<M-CR>", repl.eval_visual, vim.tbl_extend("force", opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("v", "<C-CR>", repl.eval_visual, vim.tbl_extend("force", opts, { desc = "Eval Selection in Steel REPL" }))
        vim.keymap.set("n", "<M-CR>", repl.eval_current_form, vim.tbl_extend("force", opts, { desc = "Eval Form in Steel REPL" }))
        vim.keymap.set("n", "<C-CR>", repl.eval_current_form, vim.tbl_extend("force", opts, { desc = "Eval Form in Steel REPL" }))

        -- Convenience REPL leader commands
        vim.keymap.set("n", "<leader>so", repl.toggle, vim.tbl_extend("force", opts, { desc = "Toggle Steel REPL" }))
        vim.keymap.set("n", "<leader>sb", repl.eval_buffer, vim.tbl_extend("force", opts, { desc = "Eval Buffer in Steel REPL" }))
      end,
    })
  end,
}
