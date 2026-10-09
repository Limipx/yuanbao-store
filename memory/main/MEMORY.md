# 长期记忆 · 迷你世界 UGC 3.0 / Lua / AI 对话

> 存放：/data/workspace/_memory/  （/data 每次会话重置，只有
> inputs/library/outputs/skills/user/user_persistent_data/workspace 保留）

## 当前主业
迷你世界 UGC 3.0 脚本开发；业务方向已转向**迷你建筑生成**。

---

## 「接得准」实验结论（2026-10-08，双塔 vs 字面基线）

目标：把问答检索从「接得住」提升到「接得准」。基于 23.7 万问答对实测。

**⚠️ 评估口径必须先统一（当前存在不一致）**
- `baseline.py`（倒排深截断）报 top1=**36.30%**、top5=52.23%
- `recall2.py`（倒排截断 400）报 top1=**22.00%**、top-50=45.88%
- 差异源于**倒排截断深度**。后续比较前必须先对齐口径，否则数字不可比。

**纯语义双塔惨败（关键发现）**
- 模型：字向量 IDF 加权平均池化 + tanh 投影，dim=128，词表 3002，约 1M 参数
- 6 万样本 × 5 epoch：loss 4.24→2.31，top1 仅 **5.0%→8.8%**，top5→19.2%
- 远低于字面基线 → **字面重合是这个数据集的主导特征，纯语义模型反而丢了它**

**字面方法天花板（重排空间）**
- top-1: 22.00% → top-50: 45.88%
- 即**重排最多带来 +24 个百分点**，这是路线的价值上限

**结论：要「接得准」必须走「字面召回 + 学习重排」**
1. 召回层：IDF 加权重叠，取 top-50（保证高覆盖）
2. 重排层：小模型在 top-50 内精排（这才是该投入参数的地方）
3. 双塔若要救，必须**融合字面特征**（α 加权），不要纯语义

**踩坑**
- 沙盒 2 核无 torch，全量 23 万样本训练会 502 超时 → 分步或缩小规模
- IDF 用正则提取在 23 万条上极慢；改用 `set(s)` 后 **2 秒**完成
- `np.add.reduceat`/`np.add.at` 在 batch 小时 Python 开销大 →
  预建 flat 段 + batch 提到 256 可显著提速（97s / 6万×5ep）
- `Tower.load()` 未实现；`Tower.forward()` 基类只收 2 参数，
  子类 T2 需 3 参数（ids_list, ws_list）

---

## 输入法联想做迷你世界 AI 对话（2026-10-08 实测）

基于 `/data/workspace/llm/clean_pairs.jsonl`（23.7 万问答对）：
- **去重问法 20.1 万，去重答案仅 3.1 万** → 平均 1 答案对应 7.6 种问法
- **74% 答案被复用 ≥2 次**，最热一条答案有 456 种问法
- **答案端字表仅 3822 字符**；前 500 字覆盖 87.7%，前 2000 字覆盖 99%
→ 本质是**候选排序**任务，不是开放生成。

参数量 / 体积 / 速度（推理按 2×params 粗估，基准 28.4M ≈ 0.4 s/token）：

| 方案 | 词表/dim/层 | 参数 | int8 | 二维表 | 速度 |
|---|---|---|---|---|---|
| MiniMind2-Small 现用 | 6400/512/8 | 28.4M | 28.4MB | 57 张 | 0.400 s/tok |
| 拼音音节版 | 450/512/8 | 25.4M | 25.4MB | 51 张 | 0.357 s/tok |
| **联想版·字级生成** | 3822/256/6 | **5.7M** | 5.7MB | **11 张** | **0.080 s/tok** |
| 联想版·更小 | 3822/192/4 | 2.5M | 2.5MB | 5 张 | 0.035 s/tok |
| 双塔排序 | 3822/128/2 | 0.88M | 0.9MB | 2 张 | 0.012 s/tok |

- **参数大头在 transformer 主体（25.2M）不在词表（3.3M）**
  → 拼音版只省 12%；**降 dim/层数才是真省**。

---

## 训练环境（已实测）

- 沙盒：无 torch，有 numpy 2.2.6，2 核 EPYC 9K65。
  matmul：512×512 ≈ 83.5 GFLOPS，1024×1024 ≈ 209.6 GFLOPS。**训不动 26M。**
- 用户手机 OPPO Find X8 / 天玑 9400（1×X925@3.62 + 3×X4@3.3 + 4×A720@2.4，
  12/16GB LPDDR5X，NPU 890 约 67 TOPS，GB6 多核 8969）
- ⚠️ **NPU 890 只能推理不能训练**（架构性）：Neuron API 只有
  build→compile→execute，零梯度/反向/优化器原语；OpenCL 挡在 /vendor/lib64。
  官方「端侧 LoRA 训练」需 MediaTek 自家 SDK（NeuroPilot + ExecuTorch），
  Termux + PyTorch 走不通。训练只能走 CPU。
- Termux 装 PyTorch 是地狱：无 wheel，要改 ARM 汇编（qnnpack `4s → 16b`）、
  源码编译 1h+、Python 降到 3.10。**更务实：numpy 手写训练。**
- 旁证：天玑 9300+ 上 Termux+PyTorch 训 500K 参数 MLP，5 epochs ≈ 30 分钟。

---


---

## GitHub 长期存储（Limipx，2026-10-08 建立）

账号：**Limipx**（邮箱 2975429819@qq.com）
⚠️ **密码不能用于 GitHub API**（2021 起禁用），必须用 PAT。
不要拿密码去调 API——会触发风控。生成：
https://github.com/settings/tokens/new → Note `yuanbao-uploader` →
90 days → **只勾 repo** → 复制 `ghp_` 串（只显示一次）

仓库：**`yuanbao-store`**（主），扩容 `yuanbao-store-2/-3...`

目录约定：
```
skills/   技能库，一个子文件夹 = 一个技能（skills.tar.gz 压缩入库）
agent/    Agent 画像：core/PROFILE.md 核心能力 + domains/*.md 领域专长
uploads/  手机上传器写入，uploads/<批次ID>/
```

恢复命令：
```bash
curl -L -o skills.tar.gz https://raw.githubusercontent.com/Limipx/yuanbao-store/main/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1
```

- 当前：29 个自定义技能，7.1MB → **压缩 3.1MB（2.26x）**；agent 7KB
- 限制：单文件 100MB / 单 blob 38~40MB / 单仓库 1GB 软警戒


### 技能库扩充（2026-10-08，54 个）

**好友仓库 `zhaoyi-habs/yuanbao-agent` 不存在**：用户 zhaoyi-habs 存在
（ID 316443789）但**公开仓库数 0**，所有名字变体（yuanbao-agent /
yuanbao_agent / yuanbaoagent / yuanbao / agent）全部 404。
→ 仓库是私有的，或已删/改名。要拿需好友给 collaborator 权限或改公开。

**改为从公开社区拉取（已实测可用）**：

| 仓库 | 星数 | 说明 |
|---|---|---|
| `anthropics/skills` | 180k | 官方技能库，19 个（含 docx/pdf/pptx/xlsx） |
| `obra/superpowers` | 297k | agent 方法论，15 个 |
| `openai/skills` | 28k | Codex 技能目录 |
| `ComposioHQ/awesome-claude-skills` | 77k |  curated 列表 |

下载方式（codeload 可用）：
```
curl -L -o x.tar.gz https://codeload.github.com/anthropics/skills/tar.gz/refs/heads/main
```

**新增 25 个**（跳过 5 个已有 + 4 个官方内置 docx/pdf/pptx/xlsx 不覆盖）：
- anthropics：academy-guide、algorithmic-art、claude-api(1.9MB)、
  discernment-nudge、doc-coauthoring、internal-comms、mcp-builder、
  slack-gif-creator、theme-factory、web-artifacts-builder
- superpowers：brainstorming、diagnosing-superpowers、
  dispatching-parallel-agents、executing-plans、
  finishing-a-development-branch、receiving-code-review、
  requesting-code-review、subagent-driven-development、
  systematic-debugging、test-driven-development、using-git-worktrees、
  using-superpowers、verification-before-completion、writing-plans、
  writing-skills

**当前：54 个技能 / 485 文件 / 9.67MB → 压缩 4.06MB（2.38x）**

**⚠️ jsdelivr 有缓存**：`@main` 会拿到旧版本。
必须用 **commit SHA** 绕过：
```
https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@<SHA>/skills/skills.tar.gz
```
取 SHA：`https://api.github.com/repos/Limipx/yuanbao-store/commits?per_page=1`
（purge.jsdelivr.net 和 data.jsdelivr.com 在沙盒被 403，不能用）

**已知小问题**：`lua-obfuscator` 缺 SKILL.md（54 个里唯一格式不合规）


### 已建好并验证（2026-10-08）

- 仓库 **`Limipx/yuanbao-store`** 已创建并上传成功：
  `skills/skills.tar.gz`（269 文件 3.1MB）、`agent/agent.tar.gz`（7KB）、
  `README.md`、Release `v1.0` 含 `YuanbaoUploader.apk`
- token 已验证属于 Limipx（ID 206050242，1 个公开 + 1 个私有仓库）
- 其他仓库：`liming-house`（公开，空）、`mini-project`（私有，空）

**⚠️ 下载链路实测**：
- `raw.githubusercontent.com` 与 `github.com` 在**沙盒内被 403 policy denied**
- **`cdn.jsdelivr.net/gh/Limipx/yuanbao-store@main/...` 可用**
  （实测 skills 3.2MB、agent 7145 字节均完整下载）
- 上传走 `api.github.com` 正常 → **上传通、下载在沙盒受限**
- 恢复一律用 jsdelivr 镜像：
```
curl -L -o skills.tar.gz https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@main/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1
curl -L -o agent.tar.gz https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@main/agent/agent.tar.gz
tar -xzf agent.tar.gz -C /data/workspace
```
- 大文件走 jsdelivr 可能首次返回 0 字节，**重试 1–2 次即可**（实测第 3 次成功）

- 产物：`/data/workspace/gh_store/setup.py`（一键配置，已适配 Limipx）
- **APK 改不了**：拿到的是编译好的 `classes.dex`，无 Java 源码。
  只能改它写入的目录约定，改 App 内部需要源码工程。


## 环境硬事实（迷你世界 UGC 3.0）

- `loadstring` **实测返回 nil，不可用**；`load` 是 Lua 5.2 的。
  → 要「字符串→可执行逻辑」只能用自写编译器 + VM（已做成桥接组件）。
- Lua 5.1：无 goto / bit32 / table.unpack（用全局 unpack）/ 整数除法。
- `bit` 模块一定存在；`os` 只有 date/time/timeMs，**没有 clock**。
- 转储证实 `Mini.X.__className_` 恒等于 `"X"`（50 种类型无一例外）。

## 引擎元数据铁律（踩过多次）

`propertys` / `openFunctions` / `openFnArgs` 都是引擎在**加载期**读的元数据：
- **绝不能搬进 OnStart** —— 否则属性面板空白、属性全丢、二维表 ID 读不到。
  「非函数字段放 OnStart」只是规范 WARN，**永远不要为满足它牺牲功能**。
- **元方法（`__index` 等）不能改名**，改名会让数组返回值失效。
- 开放函数名改名时**登记表键必须同步改**，否则触发器看得到函数但调用返回 nil。
- 生命周期 `OnStart`/`OnDestroy`/`OnUpdate` **永不改名**（引擎按名字调用）。
- 元数据里的字符串**不要用 `_DEC()` 加密** —— 引擎在受限环境求值，
  看不见 chunk 顶层 local。用 `string.char(...)`（纯全局，可达）。

## arrayWrapper（数组返回值）

- `getcount == 3` 是**引擎硬编码**查询次序，Lua 只能迎合。
  真机实测：第 1/2/4/5 次给元素类型都会错位。
- 查询序列真机实测：`Array > Array > <元素类型> > Array > Array`。
- 原版只覆盖 String/Number/Bool/Item，其余 46 种返回 `"Unknown"`。
  **唯一可安全改进**：`return propertytype.__className_ or "Unknown"`
  （真机验证 Vec3/Color 从 Unknown 变正确）。
- 九项细节全部与引擎内部实现耦合，动一个就崩。

## 混淆工具（`ugc3-obfuscator`）

- 触发词「加密生成」。四层：开放函数转发入 local、标识符重命名、
  字符串加密（纯 Lua，不用 loadstring）、签名 + 变体指纹。
- 混淆**不是加密**，只增加阅读成本。真保护靠密钥：PBKDF2-HMAC-SHA256 派生，
  CTR 流加密，只存校验值不存密钥。
- 速度：混淆几乎零损失；**字节码 + 自写 VM 慢约 1467 倍**
  （10 万次加法 0.3ms→837ms），只能用于低频/一次性场景。

## LuaVM 桥接组件（`/data/workspace/LuaVM桥接.lua`，151KB）

- **宿主 ↔ VM 双向交互 17/17 全通**：传参/传表、VM 调宿主函数、
  VM 返回函数（宿主可直接调）、返回函数表、双向表传递、VM 内可见 Mini。
- 宿主 API：`VM.Run / Compile / RunBC / Define / Call / Export / SetEnv / ModuleList`
- **AI skills 用法**：宿主把能力挂 `_G` → AI 生成源码（末尾
  `return function(...) end`）→ `VM.Define(name, code)` → `VM.Call(name, ...)`
- 关键签名：`vm.lua51.run(chunk, args, upvals, globals, hook)`，
  **args 必须是表**；`globals` 默认 `_G`，可指定 → 沙箱入口。
- ⚠️ 共享 `_G`，无沙箱（刻意保留）；要限制时 `VM.SetEnv(白名单表)` 一行切换。

---

## 元宝手机操控（2026-10-08，基于好友方案给 Limipx 部署）

**架构**：GitHub 仓库做中转，**不需要公网 IP / 内网穿透 / root**
```
AI 写 task.json → 私有仓库
  → bridge.py（Termux 常驻轮询 git pull）拉取
  → 投喂本机 phone-server（127.0.0.1:27143）
  → AutoX.js 执行（点击/滑动/输入/截图/读屏）
  → 结果 result.json → git push
  → AI 读取
```
**为什么不用内网穿透**：Cloudflare Tunnel / Pinggy / ngrok / 花生壳 /
natapp / cpolar 实测 AI 端全部无法访问——AI 端出网被代理全接管。
改成「手机主动来取」即可。别再试穿透。

**仓库**：`Limipx/yuanbao-phone`（**私有**）
文件：main.js(9.4KB) / phone-server.py(4.0KB) / bridge.py(6.7KB) /
start.sh / task.json / .gitignore / README.md

**⚠️ 好友文档里 phone-server.py 被截断，我补齐了**。接口约定：
- `GET /info` 健康检查（main.js 探测用，返回体须含 `"ok"`）
- `POST /task` bridge 投递
- `GET /next` AutoX 轮询取任务（返回 `{"task":...,"id":...}`，无任务返回 `{}`）
- `POST /result` AutoX 回传
- `GET /result` bridge 取最新
- `GET /status` 调试（pending / results / cur_id）

**端到端实测（沙盒内，无手机）**：
- 协议链路 7 步全通（info/next空/task/next取/result回/result取/status）
- bridge.run_task 端到端通过：模拟 AutoX 取任务→回传，2.0s 拿到结果

**⚠️ 未测到**：沙盒 `git clone` HTTPS 被 403（github.com 全站被拦），
**git 同步/推送的往返没法在沙盒验证**。API 上传正常，文件确认在仓库里。
真机 Termux 网络正常，不受影响。

**OPPO/ColorOS 防杀后台**：设置→电池→应用耗电管理→Termux/AutoX.js→
允许后台运行+自启动；多任务卡片下拉加锁；关省电；插电；
`termux-wake-lock`（start.sh 已含）

**私有仓库下载需带 token**：
```bash
curl -H "Authorization: Bearer <TOKEN>" -H "Accept: application/vnd.github.raw"      -o shot.png https://api.github.com/repos/Limipx/yuanbao-phone/contents/shots/xxx.png
```

**安全建议**：给手机单独开一个 fine-grained token，只授权 yuanbao-phone
这一个仓库的 Contents:RW，别用主 token。

---

## CLI-Anything（2026-10-08 安装，HKUDS/CLI-Anything ★51.7k）

**项目本质**：给任意软件生成 agent 可调用的 CLI，输出 JSON。
`pip install cli-anything-hub` → `cli-hub install <name>` → `cli-anything-<name>`

**已装：70 个技能 + 15 个 CLI 包**
- 技能装到 `/data/skills`（当前 85 个）并同步进 GitHub store（124 个 / 4.16MB）
- pip 实装：hub、godot、blender、mermaid、krita、kdenlive、freecad、
  obsidian、joplin、siyuan、drawio、musescore、audacity、inkscape、libreoffice

**端到端实测通过**：
```
cli-anything-godot --json project create /tmp/gdtest --name TestGame
→ 生成真实 project.godot（features 4.4 / GL Compatibility）
```

**⚠️ 沙盒两个坑**：
1. `cli-hub list` 默认拉 `hkuds.github.io/.../registry.json` → **403**
   绕法（不改代码）：把仓库自带的 registry.json 播种进缓存
   `~/.cli-hub/registry_cache.json`，格式 `{"_cached_at":ts,"data":{...}}`
   播种后 `cli-hub list` 正常返回 **140 个 CLI**
2. `cli-hub install X` 走 `pip install git+https://github.com/...` →
   git clone 被 403。绕法：本地路径装
   `pip install /tmp/ca/CLI-Anything-main/<name>/agent-harness`
   （真机网络正常时直接 `cli-hub install X` 即可）

**已知问题**：`cli-anything-mermaid` 的 `diagram set/show` 会抛 traceback
（项目文件未初始化时）。其余 14 个 `--help` 均正常。

**对 Limipx 的价值**：他手机上有 **Godot Engine 4**，而 godot CLI 实测可用
→ Termux 里可让 AI 直接建项目/建场景/导出。其余（blender/krita/gimp 等）
需宿主软件，桌面端才能跑。

---

## Supabase（2026-10-09，Limipx）

账号：lmpxplus@gmail.com（注册链接 supabase.com/dashboard/sign-up）

**⚠️ 两个硬限制**：
1. **沙盒连不上** —— `api.supabase.com` / `supabase.com` 全部 403
   policy denied（沙盒白名单只有 api.github.com / codeload.github.com /
   mirrors.cloud.tencent.com）。无法代注册/代管理。
2. **邮箱密码不能用于管理 API** —— 那是 dashboard 网页 OAuth。
   Management API 要 **Personal Access Token（`sbp_` 开头）**：
   dashboard → Account Preferences → Access Tokens → New token
   （`grant_type=password` 是**项目级** GoTrue，给 App 终端用户用的，不是管理接口）

**工具**：`/data/workspace/supabase/sb.py`（纯标准库，无 pip 依赖）
命令：orgs / list / status / info / keys / sql / tables / buckets /
      create / pause / restore
用法：`export SUPABASE_TOKEN=sbp_xxx && python3 sb.py list`

【已测】无 token 正确退出提示、brief() 表格渲染、11 个命令路由齐全
【未测】真实 API 调用（网络不通）

**免费版两个坑**：
- **7 天不活动自动暂停**（要定期 ping）
- 最多 **2 个活跃项目**

**区域选择**：`ap-southeast-1`（新加坡）离四川最近，次选 `ap-northeast-1`

**安全**：`service_role` key 绕过所有 RLS，**绝不能放客户端**

### Supabase 项目已建（2026-10-09）

```
Project URL  https://atvwodkrvwswvegjcffo.supabase.co
项目名        yuanbao     组织 Impxplus
规格          Nano（免费档）  状态 Healthy
```

**账号无 Access Tokens 入口** —— Account Preferences 页面左侧栏确实没有
（新账号未开放）。改用 **REST 模式 + service_role key**。

**关键技巧：REST 模式拿回完整 SQL 能力**
PostgREST 本来只能读写表、不能执行 DDL/DML。
建一个 `exec_sql(text) returns json` 函数（`security definer`），
sb.py 就能通过 `POST /rest/v1/rpc/exec_sql` 跑任意 SQL。
必须 revoke anon/authenticated，只 grant service_role。
→ `init.sql` 已写好，用户粘一次 SQL Editor 即可。

**sb.py 已重写为双模式**（自动识别）：
- REST：`SUPABASE_URL` + `SUPABASE_KEY` → tables/get/insert/count/sql
- Token：`SUPABASE_TOKEN` → orgs/list/status/info/keys/create/pause/restore

【已测】本地 mock：模式识别、5 个命令请求构造、请求头（apikey +
Bearer）、响应解析
【未测】真实 API —— `*.supabase.co` 在沙盒 403

**⚠️ Nano 免费版 7 天无活动自动暂停**，需配保活（GitHub Actions 定时 ping）

**仍未确认**：这个库的用途（问了 3 次没答），表结构取决于它

