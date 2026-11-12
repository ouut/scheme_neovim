# Neovim + Steel Scheme (Rust) 结构化开发环境

本项目是一套专为 **Rust Steel Scheme** 量身定制的现代化开发环境与独立发行版，包含两种交付形态：
1. **方案 A（推荐）：`steel-ide` 全内嵌单文件二进制（All-in-One Executable）**：将 Neovim、Steel Scheme 运行时、Tree-sitter Scheme 语法库及全套 Strict Paredit 配置封装为单一独立文件（仅 13MB），双击或命令行直接运行，**无需安装任何依赖**！
2. **纯 Neovim 配置形态**：可直接软链接至 `~/.config/nvim`，无缝嵌入既有的 Neovim 开发流。

完美复刻并实现了 [`docs/strict_paredit_guide.md`](docs/strict_paredit_guide.md) 与 [`docs/strict_paredit_algorithm_spec.md`](docs/strict_paredit_algorithm_spec.md) 中的严格括号树算法、Calva 智能包裹规则与 **17 个单发核心快捷键**。

---

## 🌟 核心特性

1. **单一文件开箱即用（方案 A 实现）**：
   - 使用 Rust 构建的独立可执行文件 `steel-ide`（已安装至系统 `/usr/local/bin/steel-ide`，文件仅 13MB）。
   - **零宿主依赖**：机器上无需提前安装 Neovim、无需安装 Rust/Cargo、无需配置 C 编译器。
   - **完全隔离运行**：利用 `NVIM_APPNAME` 与独立运行时环境，100% 不污染、不读取宿主既有的 `~/.config/nvim`。
   - **自解压与即时启动**：首次运行自动解压运行时（耗时 < 0.5s），后续运行秒级即时拉起。
2. **彻底废除 Leader 两阶段（One-Shot 单发）**：
   - 遵循 `docs/strict_paredit_guide.md`，全套快捷键以 **Alt（macOS: ⌥ Option）** 为基准锚定，右手依托 `H-J-K-L` 四轴八态主键矩阵，纯单发直接生效，绝不搞两阶段模态等待。
3. **严格 Paredit 模式（Strict Mode）**：
   - 引入 `sundbp/strict-paredit.nvim`，以 Tree-sitter 为底层，实现类似于 Emacs `smartparens-strict-mode` 的严苛括号平衡校验：
     - 输入 `(`、`[`、`{` 自动成对补全；
     - 遇到对应闭括号直接跳过，绝不产生失衡孤儿括号；
     - 按 `<BS>`、`<Del>`、`x` 删除括号时**强制成对删除**；任何破坏平衡的删除操作会被自动拦截。
4. **AST 结构化几何编辑（Structural Editing）**：
   - 借助 `julienvincent/nvim-paredit`，精准支持吞噬（Slurp）、吐出（Barf）、圆/方括号包裹（Wrap）、脱壳解包（Splice）、相邻参数对调（Transpose）与列表切分（Split）。
5. **零摩擦 Steel REPL 工作流**：
   - 内置纯 Lua 极速 REPL 引擎（`lua/steel_repl.lua`），按下 **`Alt + E`**（或 **`Space + Enter`** / `Alt + Enter`）：
     - **普通模式**：自动通过 Tree-sitter 提取光标所在的当前 S 表达式（或顶级函数），立即送入 Steel REPL 求值并输出结果。
     - **可视模式**：将选中的代码块原样送入 REPL 求值。
     - 未启动时自动在右侧开辟终端 Split 窗口，启动即用，自动平滑滚屏。
     - **Windows 提示**：由于 Windows 系统级将 `Alt + Enter` 绑定为全屏切换，请直接使用 **`Alt + E`**（E = **E**val）或 **`Space + Enter`** 一键发射求值。

---

## 🚀 单文件二进制 `steel-ide` 使用指南

已经构建完毕的可执行文件位于：
- 本地二进制：[`bin/steel-ide`](file:///workspace/scheme_neovim/bin/steel-ide)（软链接至 `/usr/local/bin/steel-ide`）

### 常用命令与启动选项

```bash
# 1. 打开或创建任意 Scheme 文件
steel-ide main.scm

# 2. 一键打开内置的实战教程与试验田 (自带 17 个快捷键测试代码)
steel-ide --example

# 3. 直接进入纯交互式 Steel Scheme REPL 终端
steel-ide --repl

# 4. 查看版本与组件信息
steel-ide --version

# 5. 解压内置运行时到指定目录
steel-ide --extract /opt/steel-ide-runtime
```

---

> 💡 **查看超全分类快捷键手册**：更完整的人体工学心智模型与操作场景解析，请参阅专门的 **[`KEYMAPS.md`](KEYMAPS.md)**。

## 🎯 17 个快捷键完整映射表（来自 docs/strict_paredit_guide.md）

| 频级 / 占比 | Linux / Win | macOS (⌥) | 动作名称 | 对应底层实现 | 功能与效果 |
|:---:|:---:|:---:|:---|:---|:---|
| ⭐⭐⭐⭐⭐ (45%) | **`Alt + K`** | **`⌥ K`** | **向外扩选 (Expand)** | `strict_paredit.expand` | 自动严丝合缝选中当前 `(...)`，连按逐层外扩括号（选区历史压栈） |
| ⭐⭐⭐⭐⭐ (45%) | **`Alt + E`** (推荐)<br>**`Space + Enter`**<br>`Alt + Enter` | **`⌥ E`**<br>**`Space + ↵`**<br>`⌥ ↵` | **发射求值 (Eval REPL)** | `strict_paredit.eval_repl` | 将当前 S 表达式送入 Steel REPL（350ms 视觉闪烁，多表达式自动 begin 事务原子求值） |
| ⭐⭐⭐⭐ (25%) | **`Alt + H`** | **`⌥ H`** | **圆括号包裹 (Wrap Parens)** | `strict_paredit.wrap_parens` | `cards` $\rightarrow$ `(cards)`（Calva 智能吸附 5 态几何规则，支持 N/V/I 模式） |
| ⭐⭐⭐⭐ (25%) | **`Alt + Shift + H`** | **`⌥ ⇧ H`** | **方括号包裹 (Wrap Square)** | `strict_paredit.wrap_square` | `x 10` $\rightarrow$ `[x 10]`（写 `let*` 局部变量与 `cond` 必备） |
| ⭐⭐⭐⭐ (20%) | **`Alt + L`** | **`⌥ L`** | **向右吞噬 (Slurp)** | `strict_paredit.slurp_forward` | `(a b) c` $\rightarrow$ `(a b c)`（非破坏性局部范围替换，多行格式完好保留） |
| ⭐⭐⭐⭐ (20%) | **`Alt + J`** | **`⌥ J`** | **向左吐出 (Barf)** | `strict_paredit.barf_forward` | `(a b c)` $\rightarrow$ `(a b) c`（非破坏性局部范围替换，多行格式完好保留） |
| ⭐⭐⭐ (15%) | **`Alt + Shift + K`**<br>`Alt + I` | **`⌥ ⇧ K`**<br>`⌥ I` | **向内收缩 (Contract)** | `strict_paredit.contract` | 与 `Alt+K` 镜像呼应，基于选区历史栈精准逐层回退选区 |
| ⭐⭐⭐ (10%) | **`Alt + 3`** | **`⌥ 3`** | **选中顶级函数 (Defun)** | `strict_paredit.select_defun` | 无论光标藏在函数多深，一键选中最外层整个 `(define ...)` |
| ⭐⭐⭐ (10%) | **`Alt + O`** | **`⌥ O`** | **脱壳解包 (Splice)** | `strict_paredit.splice` | `(let () (expr))` $\rightarrow$ `(expr)`，打碎外壳提取内部代码 |
| ⭐⭐⭐ (10%) | **`Alt + 2`** | **`⌥ 2`** | **大步前进 (Forward)** | `strict_paredit.forward_sexp` | 首首跳转 Head-to-Head 跨过右侧整组完整 S 表达式或参数 |
| ⭐⭐⭐ (10%) | **`Alt + 1`** | **`⌥ 1`** | **大步后退 (Backward)** | `strict_paredit.backward_sexp` | 首首跳转 Head-to-Head 跨过左侧整组完整 S 表达式或参数 |
| ⭐⭐ (5%) | **`Alt + W`** | **`⌥ W`** | **步进深入 (Step Into)** | `strict_paredit.step_into` | 光标直接步进跳入当前括号内部最左侧首个参数前 |
| ⭐⭐ (5%) | **`Alt + S`** | **`⌥ S`** | **步退跳出 (Step Out)** | `strict_paredit.step_out` | 光标跳回当前外层括号左侧前置起始位 |
| ⭐⭐ (5%) | **`Alt + X`** | **`⌥ X`** | **整块删除 (Kill Sexp)** | `strict_paredit.kill_sexp` | 删掉当前或光标右侧的一整组完整子表达式，绝不破坏括号结构 |
| ⭐⭐ (5%) | **`Alt + \`** | **`⌥ \`** | **智能格式排版 (Indent)** | `strict_paredit.indent` | 重新按 Lisp 缩进规范对齐当前 S 表达式代码块或选区 |
| ⭐ (2%) | **`Alt + Shift + L`** | **`⌥ ⇧ L`** | **相邻参数对调 (Transpose)** | `strict_paredit.transpose` | `(equal? a b)` $\rightarrow$ `(equal? b a)`，两项位置瞬间互换 |
| ⭐ (2%) | **`Alt + Shift + J`** | **`⌥ ⇧ J`** | **列表切分 (Split)** | `strict_paredit.split` | 智能保留匹配定界符，从光标处平分列表 |

---

## 🛠️ 窗口与多标签全局漫游

无论处于普通模式还是内置终端/REPL 交互模式，无需按 `<C-\><C-n>` 繁琐逃逸，全时直通响应：

| 快捷键 | 作用区域 | 功能说明 | 逻辑细节 |
|:---|:---|:---|:---|
| **`Alt + Shift + Up`** | 全局 | **光标直达上方代码编辑器** | 自动寻找并聚焦代码窗口 |
| **`Alt + Shift + Down`** | 全局 | **光标直达下方/分屏终端或 REPL** | 自动聚焦活跃的 REPL 或系统终端 |
| **`Alt + Shift + Left`** | 全局 | **循环切换至左侧标签页 (Buffer)** | `(idx - 1) % N` 逆时针无限循环环游 |
| **`Alt + Shift + Right`** | 全局 | **循环切换至右侧标签页 (Buffer)** | `(idx + 1) % N` 顺时针无限循环环游 |

---

## 🛠️ REPL 与 Shell 终端管理

| 快捷键 | 作用区域 | 功能说明 | 助记 |
|:---|:---|:---|:---|
| **`Alt + R`** (或 `⌥ R`) | **右侧分屏** | **一键秒开 / 秒关 Steel REPL** | **R**EPL 单发开关 (终端内按直接收起返回代码) |
| **`Alt + Enter`** / **`Alt + E`** | **代码区域** | **一键发射当前 S 表达式或选区求值** | 自动在右侧拉起 REPL 并滚屏 (Win终端推荐 `Alt+E`) |
| **`Alt + T`** (或 `⌥ T`) | **底部底栏** | **一键秒开 / 秒关 系统 Shell 终端** | **T**erminal 单发开关 (保留终端执行会话) |
| **`Ctrl + \``** (反引号) | **底部底栏** | **一键秒开 / 秒关 系统 Shell 终端** | VS Code 经典终端快捷键 |
| **`Space + t + t`** | **底部底栏** | 展开 / 隐藏系统 Shell 终端 | **t**erminal **t**oggle |
| **`Space + s + o`** | **右侧分屏** | 展开 / 隐藏 Steel REPL 窗口 | **s**teel **o**pen |
| **`Space + s + c`** | **右侧分屏** | 关闭 (隐藏) Steel REPL 窗口 | **s**teel **c**lose |
| **`Space + s + q`** | **右侧分屏** | 彻底杀死并重启 Steel REPL 进程 | **s**teel **q**uit |
| **`Space + s + b`** | 当前文件 | 将当前整个文件的代码全量送入 REPL 执行 | **s**end **b**uffer |

---

## 📦 重新编译打包 Launcher

如需自行重新编译单文件二进制：
```bash
cd /workspace/scheme_neovim/launcher
cargo build --release
# 生成的单一二进制位于 launcher/target/release/steel-ide (约 13MB)
```
跨平台 GitHub Actions 自动化构建脚本已就绪于 [`.github/workflows/release.yml`](.github/workflows/release.yml)。
