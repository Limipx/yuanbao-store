# 变更记录 —— 2026-10-13 清理

主管（元宝）执行。单次原子提交。

## 一、清理原则

按 `_system/SCHEMA.md` 通用规则 5「不删历史：用 archive/ 而非删除」：

| 类别 | 处置 | 理由 |
|---|---|---|
| **被取代的版本历史**（MiniMind2 v8~v23） | **归档** → `projects/miniworld/archive/` | 唯一历史，有追溯价值 |
| **完全重复的文件**（顶层 `miniworld-ugc/`） | **删除** | 8 组 md5 完全相同，另 2 个为旧版；零信息损失，git 历史仍完整保留 |

## 二、归档（13 个，重指向 blob，未重传）

```
projects/minimind/MiniMind2_增强版v8.lua
projects/miniworld/MiniMind2_增强版v9.txt
projects/miniworld/MiniMind2_增强版v10.txt
projects/miniworld/MiniMind2_增强版v11.txt
projects/miniworld/MiniMind2_增强版v12.txt
projects/miniworld/MiniMind2_增强版v13_流式输出.txt
projects/miniworld/MiniMind2_增强版v14_流式分帧.txt
projects/miniworld/MiniMind2_增强版v16_修复版.txt
projects/miniworld/MiniMind2_增强版v17_计时器泵.txt
projects/miniworld/MiniMind2_增强版v18_跑飞拦截.txt
projects/miniworld/MiniMind2_增强版v19_跑飞拦截生效.txt
projects/miniworld/MiniMind2_增强版v20_重复拦截与加载进度.txt
projects/miniworld/MiniMind2_增强版v23_加载分帧.txt
```

**保留**：`MiniMind2_增强版v24_收尾决策器.txt`（用户指定保留）。

**弃用**：`v24Acc`（matvec 加速 3.65x）。经用户确认不再需要，未入库。
（如需恢复：同目录下 v24 打 32 行并行 × 4 列展开补丁即可，逐位精确。）

## 三、删除（10 个，纯重复）

顶层 `miniworld-ugc/`（不在 SCHEMA 顶层清单内）是 `knowledge/miniworld-ugc/` 的旧快照：

| 文件 | 与 knowledge/ 同名文件比对 |
|---|---|
| MiniBus组件.lua | md5 相同 |
| arrayWrapper.md | md5 相同 |
| 两套脚本上下文.md | md5 相同 |
| 引擎元数据铁律.md | md5 相同 |
| 探针_隐藏接口.lua | md5 相同 |
| 环境全景_1.54.0.md | md5 相同 |
| 环境能力.md | md5 相同 |
| 组件属性补全.md | md5 相同 |
| 广播通信体系.md | 不同（旧版 5802 < 新版 6227） |
| INDEX.md | 不同（旧版 3699 < 新版 6485） |

正统位置统一为 `knowledge/miniworld-ugc/`（13 个文件，为前者的超集）。

## 四、新增（8 个）

| 文件 | 说明 |
|---|---|
| `MiniMind2_增强版v28_指纹绑定版.txt` | v26 混淆主体 + RSA 非对称 License 激活，绑定脚本指纹/玩家/变体，抗注入与转卖 |
| `KV文件系统_云服版v3.lua` | 云服 KV 表文件夹系统，带令牌桶限流 |
| `KV文件系统_房间个人版v3.lua` | 同上，按 playerId 区分，无云服限流 |
| `KV文件系统_使用与原理.md` | 34 个开放函数签名 + Merkle/SimHash 鸽巢/CTR+MAC/令牌桶原理 + 18 条文献 |
| `KV文件系统_探针v2.lua` | 枚举并实测引擎真实可用 KV 接口 |
| `MiniMind2_权重解包规格.txt` | 70 张二维表 base85 → int8 权重完整布局与 74 条偏移表 |
| `全服去中心化文件夹系统.lua` | 不用 KV 表，全服广播 + 房间数组最终一致复制，抗房间关闭 |
| `全服去中心化文件夹系统_设计原理.md` | 原子广播 ≈ 共识、Lamport 排序、Merkle 根校验、16 条文献 |

## 五、更新

- `projects/miniworld/INDEX.md` —— 模组清单从「暂无」补齐为 7 条 + 2 篇配套文档 + 归档区说明

## 六、同步清理沙盒本地

```
791 MB → 649 MB
```

- 删：MiniMind2 v8/v9/v22/v23/v25/v26/v27/v24Acc、加速补丁及构建脚本
- 删：KV 文件系统 v1/v2（与 v3 md5 完全相同）、混淆工具三个旧版、License 模块 v1、MLKEM768 旧版
- 删：重复权重 bin（`e2da62b2` 同一份）、82.9MB 权重转储 txt（保留 zip 版）、旧 GitHub 备份
- 留：v24、v28、所有 zip 成品包

## 七、环境事实（本轮确认，供后续复用）

1. **沙盒无法 git clone**：出口代理只放行 `api.github.com`，`github.com` / `codeload.github.com` 直连返回 403。
   → 所有仓库操作须走 **Git Data API**（blobs → trees → commits → refs）。
2. **归档零上传**：Git Data API 建树时可直接引用已有 blob sha，移动文件不需要重新上传内容。
3. **删除写法**：tree entry 里 `{"path": ..., "sha": null}` 即删除。
4. **jsDelivr 本轮不可用**（返回 0 字节 / 352 字节错误页）；`raw.githubusercontent.com` 未测通；
   `api.github.com` 稳定，读公开仓库匿名即可（HTTP 200）。
