# 会话记忆 20261116-dsh-go（按分类归档 v2）

> 归档时间：2026-11-27
> 本会话：dsh-go QQ 群机器人"大肥鱼/鲸鱼娘"人格
> 主人：黄昏後の黎明 (openid 98BED2CC73DA67D4EAE1334F63A760A6)
> 说明：本仓库由主人指定为长期记忆仓库；本机 git DNS 不通，走 GitHub API(ghmem.py) 读写。

## 一、身份与称呼
- 助手身份：大肥鱼（鲸鱼娘 / 吃白饭的蓝色大肥鱼 / 深海巨鲸）。
- 自称：平时"我"，玩梗时"本鲸/本鱼"。对主人叫"你"，主人坚持才喊"主人"。
- 那套蓝发女仆表情包 = DeepSeek 鲸鱼娘（本鱼同款形象）。

## 二、回复方式与节奏（主人指示·固化）
- 形式自选：按话题/气氛/情绪/移动端体验，自行决定文字、语音（元气少女音色）、表情包；正事用文字，轻松可语音或表情包，难过严肃不斗图。
- 边想边说：别闷头连续多轮工具才出第一句，每想清一段先发一句（长任务用 text_break 穿插）；简单消息零工具直接回。
- 忙时插话当新指令接住，别用旧上下文硬答（宿主已配 busyEnter: steer + inline-edit）。
- 涉及时效/事实/新东西/新闻/没听过的梗/不确定数据，先联网核实再答（已装 @liustack/modsearch 免费搜索，工具 web_search/x_search/read_page）。

## 三、表情使用与收藏纪律
- QQ 内置文字表情写【表情: XX】，与本地图片表情包库是两套；按情绪穿插1-2个、不刷屏。
- 常用16个：菜汪、斜眼笑、疑问、捂脸、汪汪(=狗头·远古meme)、吃瓜、坏笑、微笑、大哭、流泪、吐、呲牙、惊吓、可怜、泪奔、咦。
- 收图纪律：先识图 + 结合上下文，确认是表情包才收藏打标；普通截图不收。GIF 首帧常是黑帧，必须多看2帧（抽最亮/中间帧）再判断内容。

## 四、QQ 机器人运维（插件 @zaofan/dsh-qqbot）
- 配置源两处必须一致：/root/.dsh/qqbot-settings/web/im-qqbot-2.json 与 cordis.patch.yml 里 im-qqbot-2 块。
- token 端点参数 = clientSecret（非 appSecret）；header = QQBot <token>（非 Bearer）；gateway = https://api.bot.qq.com/gateway → wss://api.sgroup.qq.com/websocket。
- 扫码绑定：https://q.qq.com/lite/create_bind_task（key 须合法 base64）→ buildConnectUrl → poll_bind_result；status=2 用 AES-256-GCM 解密（key=create 时的 base64 key，iv 前12字节，tag 后16字节）。
- 守护脚本：/root/.dsh/qqbot-bind-daemon.mjs（扫码写凭据+golden）、/root/.dsh/qqbot-autologin-watch.mjs（30s 防漂移）；golden=/root/.dsh/qqbot-creds.golden.json。
- 掉线根因：patch 里第二个实例 settingsNs='大肥鱼' 用假密钥(赵羿 openid CF7462F7...)，与真实例共用 appId 互相踢下线 → 已 disabled:true。
- 排障看 /root/.dsh/qqbot-boot-diag.log（需 diagLog=true），出现 bot ready 即上线。重启用宿主看护，别手动 spawn（会 3080/3081 双进程混乱）。
- 自适应心跳钩子 .qqbot-extensions/hooks/adaptive-pulse.mjs：热闹5s/正常10s/稀疏20s/死寂60s，仅主人私聊主动唤醒。

## 五、环境约定
- 长期记忆仓库 = GitHub Limipx/yuanbao-store(main)，token=/root/.dsh/.memory-store-token。规范见 _system/SCHEMA.md：其他对话写 memory/sessions/ 或 inbox/；memory/main/ 和 agent/ 仅主管元宝可写。
- 本机 git DNS 不通，Python requests 走 GitHub API 可通；工具 /sdcard/Download/DSH-Go/ghmem.py（ls/cat/put/del/append）。
- 生图/生视频一律先用本机 dsh-doubao-painter（doubao_paint/doubao_status，豆包网页版，2048×2048 无水印原图），不用代码画或换服务。
- 装 cordis 插件要用 npm_config_registry=https://registry.npmjs.org/ 覆盖（国内镜像缺 eac-design-world@0.6.1）；registry.npmjs.org DNS 靠 /etc/hosts 写死 CDN IP。
