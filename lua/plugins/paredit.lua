-- Strict Paredit & Structural Editing for Scheme
return {
  -- 1. Strict Delimiter Balance Enforcement (Emacs smartparens-strict-mode style)
  {
    "sundbp/strict-paredit.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "scheme" },
    opts = {
      filetypes = { "scheme" },
      notify = true,
    },
  },

  -- 2. Treesitter-based Structural Transformations (Slurp, Barf, Wrap, Splice, Transpose)
  {
    "julienvincent/nvim-paredit",
    ft = { "scheme" },
    config = function()
      local paredit = require("nvim-paredit")

      paredit.setup({
        use_default_keys = false, -- We use the strict 17-key ergonomic mapping from docs
        filetypes = { "scheme" },
        cursor_behavior = "auto",
        indent = {
          enabled = true,
        },
      })

      -- Helper: Wrap visual selection
      local function wrap_selection(prefix, suffix)
        vim.cmd([[execute "normal! \<ESC>"]])
        local s_start = vim.fn.getpos("'<")
        local s_end = vim.fn.getpos("'>")
        local buf = 0
        -- Insert suffix first so start position isn't shifted
        vim.api.nvim_buf_set_text(buf, s_end[2] - 1, s_end[3], s_end[2] - 1, s_end[3], { suffix })
        vim.api.nvim_buf_set_text(buf, s_start[2] - 1, s_start[3] - 1, s_start[2] - 1, s_start[3] - 1, { prefix })
      end

      -- Helper: Step Into (钻入当前括号内部最左侧元素)
      local function step_into()
        local ok, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
        if not ok then return end
        local node = ts_utils.get_node_at_cursor()
        while node and node:type() ~= "list" and node:type() ~= "vector" do
          node = node:parent()
        end
        if node then
          local first_child = node:named_child(0)
          if first_child then
            local r, c = first_child:range()
            vim.api.nvim_win_set_cursor(0, { r + 1, c })
          else
            local r, c = node:range()
            vim.api.nvim_win_set_cursor(0, { r + 1, c + 1 })
          end
        end
      end

      -- Helper: Split Form (光标处列表一分为二)
      local function split_form()
        local cursor = vim.api.nvim_win_get_cursor(0)
        local row, col = cursor[1], cursor[2]
        local line = vim.api.nvim_get_current_line()
        local open_delim, close_delim = "(", ")"

        for i = col, 1, -1 do
          local ch = line:sub(i, i)
          if ch == "[" then
            open_delim, close_delim = "[", "]"
            break
          elseif ch == "(" then
            open_delim, close_delim = "(", ")"
            break
          end
        end

        local curr_char = line:sub(col + 1, col + 1)
        local end_col = col
        if curr_char == " " then
          end_col = col + 1
        end

        local split_str = close_delim .. " " .. open_delim
        vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, end_col, { split_str })
        vim.api.nvim_win_set_cursor(0, { row, col + #split_str })
      end

      -- Helper: Indent current form
      local function indent_form()
        paredit.api.select_around_form()
        vim.cmd("normal! =")
      end

      -- Bind the 17 keymaps on Scheme buffer load
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "scheme" },
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }

          -- ⭐⭐⭐⭐⭐ (45%) 1. Alt + K: 向外扩选 (Expand) - TS Incremental Selection handles this

          -- ⭐⭐⭐⭐ (25%) 3. Alt + H: 圆括号包裹 (Wrap Parens)
          vim.keymap.set("n", "<M-h>", function() paredit.api.wrap_element_under_cursor("(", ")") end,
            vim.tbl_extend("force", opts, { desc = "Wrap with ( )" }))
          vim.keymap.set("v", "<M-h>", function() wrap_selection("(", ")") end,
            vim.tbl_extend("force", opts, { desc = "Wrap selection with ( )" }))

          -- ⭐⭐⭐⭐ (25%) 4. Alt + Shift + H: 方括号包裹 (Wrap Square)
          vim.keymap.set("n", "<M-H>", function() paredit.api.wrap_element_under_cursor("[", "]") end,
            vim.tbl_extend("force", opts, { desc = "Wrap with [ ]" }))
          vim.keymap.set("v", "<M-H>", function() wrap_selection("[", "]") end,
            vim.tbl_extend("force", opts, { desc = "Wrap selection with [ ]" }))

          -- ⭐⭐⭐⭐ (20%) 5. Alt + L: 向右吞噬 (Slurp)
          vim.keymap.set("n", "<M-l>", paredit.api.slurp_forwards,
            vim.tbl_extend("force", opts, { desc = "Slurp forward" }))

          -- ⭐⭐⭐⭐ (20%) 6. Alt + J: 向左吐出 (Barf)
          vim.keymap.set("n", "<M-j>", paredit.api.barf_forwards,
            vim.tbl_extend("force", opts, { desc = "Barf forward" }))

          -- ⭐⭐⭐ (15%) 7. Alt + Shift + K: 向内收缩 (Contract) - TS Incremental Selection handles this

          -- ⭐⭐⭐ (10%) 8. Alt + 3: 选中顶级函数 (Defun)
          vim.keymap.set({ "n", "v" }, "<M-3>", paredit.api.select_around_top_level_form,
            vim.tbl_extend("force", opts, { desc = "Select top-level form (Defun)" }))

          -- ⭐⭐⭐ (10%) 9. Alt + O: 脱壳解包 (Splice)
          vim.keymap.set("n", "<M-o>", paredit.api.unwrap_form_under_cursor,
            vim.tbl_extend("force", opts, { desc = "Splice / Unwrap form" }))

          -- ⭐⭐⭐ (10%) 10. Alt + 2: 大步前进 (Forward)
          vim.keymap.set("n", "<M-2>", paredit.api.move_to_next_element_head,
            vim.tbl_extend("force", opts, { desc = "Move to next element head" }))

          -- ⭐⭐⭐ (10%) 11. Alt + 1: 大步后退 (Backward)
          vim.keymap.set("n", "<M-1>", paredit.api.move_to_prev_element_head,
            vim.tbl_extend("force", opts, { desc = "Move to previous element head" }))

          -- ⭐⭐ (5%) 12. Alt + W: 步进深入 (Step Into)
          vim.keymap.set("n", "<M-w>", step_into,
            vim.tbl_extend("force", opts, { desc = "Step into form" }))

          -- ⭐⭐ (5%) 13. Alt + S: 步退跳出 (Step Out)
          vim.keymap.set("n", "<M-s>", paredit.api.move_to_parent_form_start,
            vim.tbl_extend("force", opts, { desc = "Step out to parent form start" }))

          -- ⭐⭐ (5%) 14. Alt + X: 向后整块删除 (Kill Sexp)
          vim.keymap.set("n", "<M-x>", paredit.api.delete_element,
            vim.tbl_extend("force", opts, { desc = "Kill element under cursor" }))

          -- ⭐⭐ (5%) 15. Alt + \\: 智能格式排版 (Indent)
          vim.keymap.set({ "n", "v" }, "<M-\\>", indent_form,
            vim.tbl_extend("force", opts, { desc = "Indent form / selection" }))

          -- ⭐ (2%) 16. Alt + Shift + L: 相邻参数对调 (Transpose)
          vim.keymap.set("n", "<M-L>", paredit.api.drag_element_forwards,
            vim.tbl_extend("force", opts, { desc = "Transpose / Drag element forwards" }))

          -- ⭐ (2%) 17. Alt + Shift + J: 列表切分 (Split)
          vim.keymap.set("n", "<M-J>", split_form,
            vim.tbl_extend("force", opts, { desc = "Split list form" }))
        end,
      })
    end,
  },
}
