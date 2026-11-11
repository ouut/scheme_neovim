# Neovim + Steel Scheme (Rust) 结构化开发环境

本项目是一套专为 **Rust Steel Scheme** 量身定制的 Neovim 开发环境配置，完美复刻并实现了 [`docs/strict_paredit_guide.md`](docs/strict_paredit_guide.md) 中的设计哲学与 **17 个单发核心快捷键**，提供**严格 Paredit 模式**与**极速交互式 REPL 工作流**。

---

## 🌟 核心特性

1. **彻底废除 Leader 两阶段（One-Shot 单发）**：
   - 遵循 `docs/strict_paredit_guide.md`，全套快捷键以 **Alt（macOS: ⌥ Option）** 为基准锚定，右手依托 `H-J-K-L` 四轴八态主键矩阵，纯单发直接生效，绝不搞两阶段模态等待。
2. **严格 Paredit 模式（Strict Mode）**：
   - 引入 `sundbp/strict-paredit.nvim`，以 Tree-sitter 为底层，实现类似于 Emacs `smartparens-strict-mode` 的严苛括号平衡校验：
     - 输入 `(`、`[`、`{` 自动成对补全；
     - 遇到对应闭括号直接跳过，绝不产生失衡孤儿括号；
     - 按 `<BS>`、`<Del>`、`x` 删除括号时**强制成对删除**；任何破坏平衡的删除操作会被自动拦截。
3. **AST 结构化几何编辑（Structural Editing）**：
   - 借助 `julienvincent/nvim-paredit`，精准支持吞噬（Slurp）、吐出（Barf）、圆/方括号包裹（Wrap）、脱壳解包（Splice）、相邻参数对调（Transpose）与列表切分（Split）。
4. **零摩擦 Steel REPL 工作流**：
   - 内置纯 Lua 极速 REPL 引擎（`lua/steel_repl.lua`），按下 **`Alt + Enter`**（或 `Ctrl + Enter`）：
     - **普通模式**：自动通过 Tree-sitter 提取光标所在的当前 S 表达式（或顶级函数），立即送入 Steel REPL 求值并输出结果。
     - **可视模式**：将选中的代码块原样送入 REPL 求值。
     - 未启动时自动在底部开辟终端 Split 窗口，启动即用，自动平滑滚屏。

---

## 📂 目录结构与架构

```text
~/.config/nvim/ (软链接至 /workspace/scheme_neovim)
├── init.lua                   # 配置总入口（设置 Leader，载入核心与插件）
├── docs/
│   └── strict_paredit_guide.md# 快捷键设计哲学与 17 个键位规范
├── example.scm                # 实战测试用例（包含所有快捷键的试验田）
└── lua/
    ├── steel_repl.lua         # 交互式 Steel REPL 引擎
    ├── config/
    │   ├── options.lua        # Neovim 基础选项（行号、Lisp 缩进、外观等）
    │   ├── autocmds.lua       # 文件类型识别 (.scm, .ss, .steel) 及 Lisp 关键字缩进
    │   ├── keymaps.lua        # 全局通用快捷键（窗口跳转、Buffer 切换等）
    │   └── lazy.lua           # lazy.nvim 插件管理器自举与加载
    └── plugins/
        ├── treesitter.lua     # Tree-sitter 语法高亮与 AST 增量扩选/收缩
        ├── paredit.lua        # 严格 Paredit 与 17 个核心快捷键实现
        ├── repl.lua           # Steel REPL 快捷键绑定与自动命令
        └── ui.lua             # 主题配色（TokyoNight Storm）
```

---

## 🚀 搭建与使用步骤

### 1. 安装依赖

- **Neovim (>= 0.10.0)**：
  ```bash
  # Linux (Ubuntu 24.04+ 或通过官方 Release Tarball)
  curl -LO https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-arm64.tar.gz # 或 x86_64
  sudo tar -C /opt -xzf nvim-linux-arm64.tar.gz
  sudo ln -s /opt/nvim-linux-arm64/bin/nvim /usr/local/bin/nvim

  # macOS
  brew install neovim
  ```

- **Rust Steel Scheme**：
  ```bash
  cargo install steel-lang
  # 验证安装
  steel --version
  ```

### 2. 部署配置

将本仓库克隆或软链接到 `~/.config/nvim`：
```bash
ln -s /workspace/scheme_neovim ~/.config/nvim
```

首次启动 `nvim` 时，`lazy.nvim` 会自动下载并安装所有插件，Tree-sitter 会自动编译并加载 `scheme` 语法解析器。

---

## 🎯 17 个快捷键完整映射表（来自 docs/strict_paredit_guide.md）

| 频级 / 占比 | Linux / Win | macOS (⌥) | 动作名称 | 对应底层实现 | 功能与效果 |
|:---:|:---:|:---:|:---|:---|:---|
| ⭐⭐⭐⭐⭐ (45%) | **`Alt + K`** | **`⌥ K`** | **向外扩选 (Expand)** | Treesitter `incremental_selection` | 自动严丝合缝选中当前 `(...)`，连按逐层外扩括号 |
| ⭐⭐⭐⭐⭐ (45%) | **`Alt + Enter`<br>`Ctrl + Enter`** | **`⌥ ↵`<br>`⌘ ↵`** | **发射求值 (Eval REPL)** | `steel_repl.eval_*` | 将当前 S 表达式或选区代码送入 Steel REPL |
| ⭐⭐⭐⭐ (25%) | **`Alt + H`** | **`⌥ H`** | **圆括号包裹 (Wrap Parens)** | `wrap_element_under_cursor("(", ")")` | `cards` $\rightarrow$ `(cards)`（支持可视选区包裹） |
| ⭐⭐⭐⭐ (25%) | **`Alt + Shift + H`** | **`⌥ ⇧ H`** | **方括号包裹 (Wrap Square)** | `wrap_element_under_cursor("[", "]")` | `x 10` $\rightarrow$ `[x 10]`（写 `let*` 必备） |
| ⭐⭐⭐⭐ (20%) | **`Alt + L`** | **`⌥ L`** | **向右吞噬 (Slurp)** | `paredit.api.slurp_forwards` | `(a b) c` $\rightarrow$ `(a b c)` |
| ⭐⭐⭐⭐ (20%) | **`Alt + J`** | **`⌥ J`** | **向左吐出 (Barf)** | `paredit.api.barf_forwards` | `(a b c)` $\rightarrow$ `(a b) c` |
| ⭐⭐⭐ (15%) | **`Alt + Shift + K`** | **`⌥ ⇧ K`** | **向内收缩 (Contract)** | Treesitter `node_decremental` | 与 `Alt+K` 镜像呼应，扩选过头随时往回收缩一级 |
| ⭐⭐⭐ (10%) | **`Alt + 3`** | **`⌥ 3`** | **选中顶级函数 (Defun)** | `select_around_top_level_form` | 无论光标藏在函数多深，一键选中最外层 `(define ...)` |
| ⭐⭐⭐ (10%) | **`Alt + O`** | **`⌥ O`** | **脱壳解包 (Splice)** | `paredit.api.unwrap_form_under_cursor` | `(let () (expr))` $\rightarrow$ `(expr)`，打碎外壳提取内部 |
| ⭐⭐⭐ (10%) | **`Alt + 2`** | **`⌥ 2`** | **大步前进 (Forward)** | `move_to_next_element_head` | 光标直接跨过右侧整组完整 S 表达式或参数 |
| ⭐⭐⭐ (10%) | **`Alt + 1`** | **`⌥ 1`** | **大步后退 (Backward)** | `move_to_prev_element_head` | 光标直接跨过左侧整组完整 S 表达式或参数 |
| ⭐⭐ (5%) | **`Alt + W`** | **`⌥ W`** | **步进深入 (Step Into)** | 钻入内部最左侧元素 | 光标直接跳入当前括号内部首个参数处 |
| ⭐⭐ (5%) | **`Alt + S`** | **`⌥ S`** | **步退跳出 (Step Out)** | `move_to_parent_form_start` | 光标跳回当前外层括号起始处 |
| ⭐⭐ (5%) | **`Alt + X`** | **`⌥ X`** | **整块删除 (Kill Sexp)** | `paredit.api.delete_element` | 删掉光标处的一整组子表达式，不破坏括号结构 |
| ⭐⭐ (5%) | **`Alt + \`** | **`⌥ \`** | **智能格式排版 (Indent)** | `select_around_form` + `=` | 重新按 Lisp 缩进规范对齐当前 S 表达式代码块 |
| ⭐ (2%) | **`Alt + Shift + L`** | **`⌥ ⇧ L`** | **相邻参数对调 (Transpose)** | `paredit.api.drag_element_forwards` | `(equal? a b)` $\rightarrow$ `(equal? b a)` |
| ⭐ (2%) | **`Alt + Shift + J`** | **`⌥ ⇧ J`** | **列表切分 (Split)** | 智能识别括号类型并切分 | `(a b \| c d)` $\rightarrow$ `(a b) (c d)` |

---

## 🧪 实战测试

打开项目内附带的测试脚本：
```bash
nvim /workspace/scheme_neovim/example.scm
```

1. 将光标置于 `(+ 10 20 30)` 处，按下 **`Alt + Enter`**：
   - 底部将自动弹出 Steel REPL 窗口，并显示 `=> 60`。
2. 光标移至 `(define my-deck cards)` 中的 `cards` 上，按下 **`Alt + H`**：
   - 单键直接将其变成 `(cards)`。
3. 选中 `x 10`，按下 **`Alt + Shift + H`**：
   - 自动包裹为局部变量形式 `[x 10]`。
4. 光标移至 `'( (1 2) 3 4 )` 的 `(1 2)` 内：
   - 按 **`Alt + L`**：吞入 `3`，变成 `(1 2 3) 4`。
   - 按 **`Alt + J`**：吐出 `3`，还原为 `(1 2) 3 4`。
5. 光标移至 `(equal? a b)` 中的 `a` 上，按 **`Alt + Shift + L`**：
   - 瞬间对调位置变为 `(equal? b a)`。
6. 光标移至 `(inner-function x)` 内，按下 **`Alt + O`**：
   - 外层括号被剥除，提取出 `inner-function x`。
7. 在任何多层嵌套的函数内部，按下 **`Alt + 3`**，接着按下 **`Alt + Enter`**：
   - 最外层函数被完整选中并发送至 Steel REPL 求值！
