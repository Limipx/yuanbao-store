# 迷你世界 UGC 3.0 官方 API 签名抓取报告

## 摘要

本次抓取以 `https://dev-wiki.mini1.cn/ugc-wiki/` 为主站点，沿官方更新日志与页面中已确认的 `/ugc-wiki/apis/<模块小写>.html` 规律展开，不凭空猜测 URL。你给出的 24 个名称中，17 个可映射到实际页面；其中 14 个页面完整抓取成功，Player、Actor、World 页面可确认的函数项数分别达到 71、75、72 项，抓取摘要受工具响应截断，未在报告中伪造未返回的参数。其余已确认页面分别提供 3—57 项函数签名。

官方页面还暴露了“名称并非一一对应”的情况：`Timer` 实际对应官方 `MiniTimer`，共 12 项；`Listen` 对应 `ListenParam`，当前页面只展开 1 项；`Trigger` 没有独立的同名词函数页，但组件系统提供 22 个事件/线程/任务函数；`CloudSever` 同时出现新旧页面，且旧路径函数更多。相反，`threadpool`、`json`、`LuaPanda`、`OfficeUtils` 经小写、首字母大写、旧路径和官方镜像检索，均未找到对应官方页面，因而没有编造签名。本报告不是站点镜像，而是供知识库按“模块—函数—参数—返回值—示例”检索的结构化索引。

## 抓取口径与质量规则

抓取对象限定为 `dev-wiki.mini1.cn` 的 UGC 3.0 脚本文档，以及能直接证明 UGC 3.0 页面存在的 `developers.mini1.cn` 镜像页面；未引入迷你世界 2.0、其他游戏或其他社区文档补齐签名。每个函数优先照抄官方页面给出的“参数及类型”“返回值及类型”与原始 Lua 示例。官方只列函数名而未展开参数、返回值的，明确写为“官方文档未提供”，不根据调用习惯或示例自行补参。

模块名保持你给出的目标名；当官方 URL 使用不同命名时，在章节标题中注明实际抓取页。函数数量来自官方序号、表格或抓取返回的首层摘要。Player、Actor、World 三个页面较大，抓取器只返回部分展开条目，因此这些章节记录已验证签名，并特别标注“页面存在更多同名函数”，而不是声称已经逐条完整枚举。

## Player

目标页 `https://dev-wiki.mini1.cn/ugc-wiki/apis/player.html` 明确列出 71 个函数。抓取摘要展开前六项，确认其参数、返回值和调用形式；其余 65 项官方仅列出名称及作用。下列表格仅记录已展开抓取的签名。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Player:GetHostUin()` | 无 | `ret: number / nil` | 获取房主 Uin；云服/房间服环境优先返回房主 Uin。 |
| `Player:SetGameResults(objid: number, result: number)` | `objid` 玩家 Uin；`result` 游戏结果，枚举 `TeamResults` | `ret: boolean` | 设置对局结果。 |
| `Player:SetGameWin(objid: number)` | `objid` 玩家 Uin | `ret: boolean` | 设置玩家胜利。 |
| `Player:GetCurToolID(objid: number)` | `objid` 玩家 Uin | `ret: number / string / nil` | 获取手持道具 ID。 |
| `Player:GetShotcutIndex(objid: number)` | `objid` 玩家 Uin | `ret: number / nil` | 获取当前快捷栏索引；索引从 1 开始。 |
| `Player:SetShotcutIndex(objid: number, index: number)` | `objid` 玩家 Uin；`index` 快捷栏索引（1—8） | `ret: boolean` | 设置当前快捷栏索引。 |
| `Player:GetFriendList(...)` | 官方文档未提供 | 官方文档未提供 | 1.54+ 新增；官方序号及名称已确认，但本次抓取的展开详情未覆盖该函数。 |

官方序号列表中的其他函数包括 `SetSkillCD`、`ReviveToPos`、`SetRevivePoint`、`NotifyGameInfo2Self`、`RotateCamera`、`ShakeCamera`、`StopShakeCamera`、`RotateCameraToActor`、`ChangeViewMode`、`IsEquipByResID`、`IsHandWeaponSpellEnhancementActive`、`GetAimPos`、`GetAimDir`、`GetRayOriginPos`、`PlayMusic`、`StopMusic`、`PauseMusic`、`OpenUIView`、`HideUIView`、`GetClientInfo`、`GetNickname`、`OpenDevGoodsBuyDialog`、`OpenDevGoodsBuyDetailedDialog`、`OpenDevStore`、`OpenDevStoreTab`、`OpenDevGoodsPage`、`GetMiniCurrency`、`GetPlayerCostStatic`、`StandReportEvent`、`ClearMotion`、`SetMobileVibrate`、`GetScreenSpacePos`、`GetScreenSpacePosV2`、`SendFriendApply`、`SetCameraPosTransformTo`、`SetCameraRotTransformTo`、`SetCameraFovTransformTo`、`SetCameraPosTransformBy`、`SetCameraRotTransformBy`、`SetCameraFovTransformBy`、`SetCameraAttrState`、`SetCameraRotMode`、`SetCameraMountObj`、`SetCameraMountPos`、`ResetCameraAttr`、`OpenBoxByPos`、`GetFirstInviter`、`HasFriend`、`GetMiniVipLevel`、`ChangPlayerMoveType`、`PlayAdvertising`、`OpenInnerView`、`SetItemAttAction`、`ForceOpenBoxUI`、`ItemSkillCDEnter`、`ItemSkillCDDone`、`SetGunActionState`、`GetViewMode`、`GetRevivePoint`、`GetRentCloudServerOwner`、`RemovePlayer`、`SetSettingEnable`、`SetSettingAbility`、`RotateMainModel`。这些函数的完整参数顺序、参数名及返回值以官方页面为准。

```lua
local ret = Player:SetGameResults(Player:GetHostUin(), TeamResults.Win)
local objid = Player:GetHostUin()
local toolid = Player:GetCurToolID(objid)
```

## Actor

`https://dev-wiki.mini1.cn/ugc-wiki/apis/actor.html` 的官方函数表及详情可确认至少 75 项。以下记录已展开抓取的签名；页面其余同名函数的官方参数未随当前抓取展开，不做补写。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Actor:GetItemId(objid: number)` | `objid` 对象 ID | `id: number / nil` | 根据掉落物对象 ID 获取对应的物品类型 ID。 |
| `Actor:GetDropItemNum(objid: number)` | `objid` 对象 ID | `num: number / nil` | 获取掉落物数量。 |
| `Actor:SetTeam(objid: number, teamid: number, bResetAttr: boolean)` | `objid` 对象 ID；`teamid` 队伍 ID；`bResetAttr` 是否重置属性 | `bool: boolean` | 设置对象队伍；重置属性仅对玩家有效。 |
| `Actor:GetTeam(objid: number)` | `objid` 对象 ID | `id: number / nil` | 获取对象所属队伍 ID。 |
| `Actor:AddHp(objid: number, hp: number)` | `objid` 对象 ID；`hp` 生命值变化 | `bool: boolean` | `hp` 为正增加、为负减少当前生命值。 |
| `Actor:GetMaxHP(objid: number)` | `objid` 对象 ID | `num: number / nil` | 获取最大生命值，包含属性加成。 |
| `Actor:ShowNickName(objid: number, bshow: boolean)` | `objid` 对象 ID；`bshow` 是否显示 | `bool: boolean` | 设置角色昵称显示状态。 |
| `Actor:SetNickName(objid: number, nickname: string)` | `objid` 对象 ID；`nickname` 昵称 | `bool: boolean` | 设置角色昵称；自动过滤敏感词。 |
| `Actor:GetNickName(objid: number)` | `objid` 对象 ID | `name: string / nil` | 获取角色昵称。 |
| `Actor:GetObjWorldId(objid: number)` | `objid` 对象 ID | `id: number / nil` | 获取对象所在星球 ID；失败返回 `-1`。 |
| `Actor:IsPlayer(objid: number)` | `objid` 对象 ID | `bool: boolean` | 判断对象是否为玩家。 |
| `Actor:PlaySoundEffectById(objid: number, soundId: number, volume: number, pitch: number, isLoop: boolean)` | `objid`；`soundId`；`volume`；`pitch`；`isLoop` | `bool: boolean` | 在对象上播放 3D 音效。 |
| `Actor:StopSoundEffectById(objid: number, soundId: number)` | `objid`；`soundId` | `bool: boolean` | 停止指定对象音效。 |
| `Actor:PauseSoundEffectById(objid: number, soundId: number, pause: boolean)` | `objid`；`soundId`；`pause` | `bool: boolean` | 暂停或恢复对象音效。 |
| `Actor:RotateFaceToActor(objid: number, targetid: number)` | `objid`；`targetid` 目标对象 ID | `bool: boolean` | 使对象旋转并朝向目标。 |
| `Actor:GetMotion(objid: number)` | `objid` 对象 ID | `x: number, y: number, z: number` | 获取运动速度分量。 |
| `Actor:SetBeHurtTarget(objid: number, targetid: number)` | `objid`；`targetid` | `bool: boolean` | 设置仇恨目标，供 AI 战斗系统使用。 |
| `Actor:GetActorFacade(objid: number, bhasequip: boolean)` | `objid`；`bhasequip` 是否含装备外观 | `facade: string / nil` | 获取对象外观描述。 |
| `Actor:CompareMainModel(facade1: string, facade2: string)` | `facade1`；`facade2` | `bool: boolean` | 比较两个主模型外观是否相等。 |
| `Actor:PlayBodyParticleById(objid: number, particleId: number|string|table, ptme: number, offset: table, rot: table, scale: table)` | `objid`；粒子 ID/路径/数组；持续时间；偏移；旋转；缩放 | `bool: boolean` | 播放身体粒子特效。 |
| `Actor:StopBodyEffectById(objid: number, particleId: number|string|table)` | `objid`；粒子 ID | `bool: boolean` | 停止身体粒子特效。 |
| `Actor:SetBodyParticleTransform(objid: number, particleId: number|string|table, offset: table, rot: table, scale: table)` | `objid`；粒子 ID；偏移；旋转；缩放 | `bool: boolean` | 修改正在播放的身体粒子变换。 |
| `Actor:Jump(objid: number)` | `objid` 对象 ID | `bool: boolean` | 使对象执行一次跳跃。 |
| `Actor:GetRidingActorObjId(objid: number)` | `objid` 对象 ID | `id: number` | 获取正在骑乘的对象 ID；失败返回 `0`。 |
| `Actor:GetFaceDirection(objid: number)` | `objid` 对象 ID | `pos: table` | 返回轴向方向向量 `{x, y, z}`。 |
| `Actor:TryMoveToActor(objid: number, targetObjid: number, speed: number)` | `objid`；目标 ID；`speed` | `bool: boolean` | 向目标对象寻路移动。 |
| `Actor:SetFaceDirection(objid: number, x: number, y: number, z: number)` | `objid`；方向向量分量 | `bool: boolean` | 设置对象朝向。 |
| `Actor:KillSelf(objid: number)` | `objid` 对象 ID | `bool: boolean` | 使对象死亡。 |
| `Actor:SetAttr(objid: number, atttype: number, val: number)` | `objid`；`atttype` 属性枚举；`val` | `bool: boolean` | 设置对象属性值。 |
| `Actor:IncreasesAttr(objid: number, atttype: number, val: number)` | `objid`；属性枚举；`val` | `bool: boolean` | 1.50+；增加属性值。 |
| `Actor:GetAttr(objid: number, atttype: number)` | `objid`；属性枚举 | `num: number / nil` | 获取属性值；失败返回 `nil`。 |
| `Actor:SetActorPermissions(objid: number, ability: number, switch: boolean)` | `objid`；能力枚举；开关 | `bool: boolean` | 设置对象行为权限。 |
| `Actor:GetActorPermissions(objid: number, ability: number)` | `objid`；能力枚举 | `bool: boolean` | 查询对象权限开关。 |
| `Actor:SetFaceYaw(objid: number, yaw: number)` | `objid`；水平角度 | `bool: boolean` | 设置水平朝向。 |
| `Actor:GetFaceYaw(objid: number)` | `objid` 对象 ID | `num: number / nil` | 获取水平面朝角度。 |
| `Actor:SetFacePitch(objid: number, pitch: number)` | `objid`；俯仰角度 | `pitch: number`；返回值官方页面抽取异常 | 官方表格将参数写为 `pitch`，返回值抽取为 `num: number`；本表保留官方文字，但无法确认字段是否一致。 |
| `Actor:GetFacePitch(objid: number)` | `objid` 对象 ID | `num: number / nil` | 获取仰望角度。 |
| `Actor:SetPosition(objid: number, x: number, y: number, z: number)` | `objid`；坐标 | `bool: boolean` | 设置对象位置。 |
| `Actor:GetPosition(objid: number)` | `objid` 对象 ID | `x: number, y: number, z: number` | 获取对象位置。 |
| `Actor:ChangeCustomModel(objid: number, modleName: string)` | `objid`；模型名/预制名 | `bool: boolean` | 修改对象外观模型。 |
| `Actor:RecoverinitialModel(objid: number)` | `objid` 对象 ID | `bool: boolean` | 恢复初始外观模型。 |
| `Actor:ActorHurt(objid: number, targetid: number, damage: number, attacktype: number, ignoreResist: boolean, ignoreTriggerEvent: boolean)` | 攻击者；目标；伤害；攻击类型；是否忽略抵抗；是否忽略触发伤害事件 | `bool: boolean` | 使对象对目标造成伤害。 |
| `Actor:SetImmuneType(objid: number, immunetype: number, isadd: boolean)` | `objid`；免疫伤害类型；是否增加免疫 | `bool: boolean` | 设置指定伤害类型免疫状态。 |
| `Actor:ChangActorMoveType(objid: number, moveMode: number)` | `objid`；移动方式枚举 | `bool: boolean` | 改变移动方式。 |
| `Actor:GetActorMovementMode(objid: number)` | `objid` 对象 ID | `num: number` | 获取移动模式 `MoveType`。 |
| `Actor:GetBoundSzie(objid: number)` | `objid` 对象 ID | `vec: table` | 获取模型边界大小 `{x, y, z}`。 |
| `Actor:RandomFacadeID()` | 无 | `id: string / nil` | 随机外观 ID。 |
| `Actor:GetObjType(objid: number)` | `objid` 对象 ID | `itype: number` | 获取对象类型 `ObjType`；失败返回 `nil`。 |
| `Actor:TryMoveToPos(objid: number, x: number, y: number, z: number, cancontrol: boolean, bshowtip: boolean)` | 对象 ID；目标坐标；可控制；是否提示 | `bool: boolean` | 使用寻路移动至目标位置。 |
| `Actor:AppendSpeed(objid: number, vx: number, vy: number, vz: number)` | `objid`；三轴速度增量 | `bool: boolean` | 附加瞬时速度。 |
| `Actor:FindNearestBlock(objid: number, blockid: number|string, blockRange: number)` | `objid`；方块 ID；搜索范围 | `x: number, y: number, z: number` | 查找最近指定类型方块。 |
| `Actor:GetEyeHeight(objid: number)` | `objid` 对象 ID | `num: number / nil` | 获取眼睛高度。 |
| `Actor:ClearActorWithId(actorid: number|string, bkill: boolean, worldId: number)` | 生物类型 ID；是否击杀；星球 ID | `bool: boolean` | 清除该类型所有生物。 |
| `Actor:IsExist(objid: number)` | `objid` 对象 ID | `bool: boolean` | 检测对象是否存在且存活。 |
| `Actor:PlayAnim(objid: number, animid: number|string, speed: number, loop: number|boolean)` | `objid`；动作 ID；速度；循环模式 | `bool: boolean` | 播放对象动作。 |
| `Actor:PlayHandAnim(objid: number, animid: number|string, speed: number, loop: number|boolean)` | `objid`；动作 ID；速度；循环模式 | `bool: boolean` | 播放手部动作。 |
| `Actor:MountActor(objid: number, rideobjid: number, isContrl: boolean, isCloseAI: boolean)` | 骑乘者；坐骑对象；是否控制；是否关闭 AI | `bool: boolean` | 骑乘到目标对象。 |
| `Actor:DisMountActor(objid: number)` | `objid` 对象 ID | `bool: boolean` | 取消骑乘。 |
| `Actor:PickupActor(objidA: number, objidB: number, animid: number|string, soundId: number, offset: table, rot: table)` | 抓取方；被抓方；动作 ID；音效 ID；偏移；旋转 | `bool: boolean` | 尝试举起另一对象。 |
| `Actor:TryPickupActorForward(objid: number, distance: number)` | `objid`；前方检测距离 | `bool: boolean` | 尝试抓取前方对象。 |
| `Actor:DropActor(objid: number, dir: table, isThrow: boolean, speed: number, hasInertance: boolean)` | `objid`；投掷方向；是否投掷；速度；是否带惯性 | `bool: boolean` | 投掷或放下对象。 |
| `Actor:EscapePickup(objid: number)` | `objid` 对象 ID | `bool: boolean` | 使被抓举对象尝试逃脱。 |
| `Actor:SetBtreeVarValue(objid: number, varid: string, val: any)` | `objid`；行为树变量 ID；值 | `bool: boolean` | 设置行为树变量值。 |
| `Actor:GetBtreeVarValue(objid: number, varid: string)` | `objid`；变量 ID | `val: any / nil` | 读取行为树变量值。 |
| `Actor:GetDropItemInstanceId(objid: number)` | `objid` 对象 ID | `id: string / nil` | 获取掉落物实例 ID。 |
| `Actor:SetAblePick(objid: number, able: boolean)` | `objid`；是否可拾取 | `bool: boolean` | 设置掉落物可否被拾取。 |
| `Actor:GetEntityFacade(prefab: string)` | `prefab` 实体预制名 | `facade: string / nil` | 根据实体预制名获取外观。 |
| `Actor:PickupItem(objid: number, itemobjid: number, bforcepickup: boolean)` | 拾取者；掉落物或投掷物；是否强制 | `num: number` | 拾取掉落物并返回数量。 |
| `Actor:GetPickupObjID(objid: number, roleType: number)` | `objid`；角色类型 | `id: number` | 获取正在拾取的对象 ID；失败返回 `0`。 |
| `Actor:HasTags(objid: number, tags: string|table, mathcmode: number, bexactmatch: boolean)` | `objid`；标签或标签表；匹配模式；是否精确匹配 | `bool: boolean` | 判断对象是否拥有指定标签。 |
| `Actor:GetTags(objid: number)` | `objid` 对象 ID | `tags: table / nil` | 获取对象标签数组。 |
| `Actor:AddTags(objid: number, tags: string|table, icount: number)` | `objid`；标签；数量参数 | `bool: boolean` | 为对象添加标签。 |
| `Actor:RemoveTags(objid: number, tags: string|table, icount: number)` | `objid`；标签；数量参数 | `bool: boolean` | 删除对象标签。 |
| `Actor:ClearTags(objid: number)` | `objid` 对象 ID | `bool: boolean` | 清空对象标签。 |
| `Actor:PlayAnimByObj(objidA: number, objidB: number, breplay: boolean)` | 对象 A；对象 B；是否重播 | `bool: boolean` | 对象 A 播放对象 B 的动作。 |

官方页面还存在 `GetActorDir`、`GetActorDir` 等按序号及详情展开的项目；抓取结果未提供完整稳定签名，因此不在此编造参数数量或名称。

```lua
local x, y, z = Actor:GetPosition(Player:GetHostUin())
Actor:SetPosition(objId, x, y, z)
Actor:SetTeam(Player:GetHostUin(), AbsoluteCampType.Team3)
```

## World

`https://dev-wiki.mini1.cn/ugc-wiki/apis/world.html` 官方页面列出 72 项。下表记录官方展开的前几项；其余函数仅确认名称，其参数顺序和参数名以页面完整展开项为准。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `World:StopParticleOnPos(x: number, y: number, z: number, particleId: number|string, worldId: number|nil)` | 坐标；粒子 ID/路径；星球 ID | `ret: boolean` | 停止指定位置粒子特效。 |
| `World:SetParticleTransform(pos: table, particleIdArg: number|string|table, offset: table|nil, rot: table|nil, scale: table|nil, worldId: number|nil)` | 位置；粒子 ID/路径或数组；偏移；旋转；缩放；星球 ID | `ret: boolean` | 设置粒子变换。 |
| `World:PlayParticle(pos: table, particleIdArg: number|string|table, ptimeArg: number|nil, offset: table|nil, rot: table|nil, scale: table|nil, worldId: number|nil)` | 位置；粒子 ID/路径或数组；持续时间；偏移；旋转；缩放；星球 ID | `ret: boolean` | 播放粒子特效。 |
| `World:GetLightByPos(x: number, y: number, z: number, worldId: number|nil)` | 坐标；星球 ID | `lv: number` | 光照强度 0—16；失败 `-1`。 |
| `World:SpawnCreature(x: number, y: number, z: number, mobid: number|string, num: number|nil, trigger: boolean|nil, worldId: number|nil)` | 坐标；生物 ID；数量；是否触发事件；星球 ID | `objs: table / nil` | 生成生物并返回对象 ID 数组。 |
| `World:SetLightByPos(x: number, y: number, z: number, value: number, worldId: number|nil)` | 坐标；光照 0—15；星球 ID | `ret: boolean` | 设置方块光照。 |

官方序号列表还包括 `DespawnActor`、`GetPlayerTotal`、`GetAllPlayers`、`GetSpawnPoint`、`FindCanSpawnMobPosList`、`FindNearestPlayerByPos`、`PlaySoundEffectOnPos`、`StopSoundEffectOnPos`、`PauseSoundEffectOnPos`、`IsDaytime`、`SetHours`、`GetHours`、`GetDay`、`SetGravity`、`AddGravity`、`GetGravity`、`IsChunkLoaded`、`CanMobSpawnOnPosXZ`、`GetHostWorldId`、`SpawnProjectile`、`SpawnProjectileByDir`、`GetBiomeType`、`GetBiomeGroup`、`FindEcosystem`、`PixelMapAddMarker`、`PixelMapRefreshMarker`、`PixelMapDelMarker`、`PixelMapAddTexture`、`PixelMapRefreshTexture`、`PixelMapDelTexture`、`SetSkyBoxColorAnim`、`SetTimeVanishingSpeed`、`SetSkyBoxTemplate`、`SetSkyBoxMaps`、`SetSkyBoxColor`、`SetSkyBoxAttr`、`SetSkyBoxAttrWithNoTime`、`SetSkyBoxFilter`、`SetSkyBoxSwitch`、`SetSkyBoxMapsAnim`、`SetSkyBoxFilterAnim`、`GetLocalDate`、`GetLocalDateString`、`GetServerDate`、`GetDateFromTime`、`GetDirRayDetection`、`GetRayLength`、`GetRayBlock`、`CalcDirectionByYawDirection`、`CalcDirectionByYawAngle`、`CalcDirectionByCoord`、`CalcDirectionByAngle`、`RandomParticleEffectID`、`RandomSoundID`、`CalcDistance`、`SetGroupWeather`、`RandomWeatherID`、`GetGroupWeather`、`SetSpawnPoint`、`CalcDirectionByPos2Pos`、`SetWorldCreateMobRule`、`SetMobSpawnDensity`、`SetPlantGrowRate`、`SetInnerViewEnable`、`SetMidJoin`、`GetGameMode`。

```lua
local x, y, z = Actor:GetPosition(Player:GetHostUin())
local result = World:StopParticleOnPos(x, y, z, 1001, WorldId)
local objs = World:SpawnCreature(x, y, z, 3400, 3, true, WorldId)
```

## CustomUI

`https://dev-wiki.mini1.cn/ugc-wiki/apis/customui.html` 完整页面确认 57 项。已展开签名如下。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `CustomUI:SetText(objid: number, uiid: string, elementid: string, text: string, animid: number, time: number, mode: number)` | 玩家/对象 ID；界面 ID；元件 ID；文本；动画 ID；时长；播放模式 | `bool: boolean` | 设置文本元件内容；后三项官方文档标注为可选，但未给默认值。 |
| `CustomUI:SetTexture(objid: number, uiid: string, elementid: string, url: string)` | 玩家/对象 ID；界面 ID；元件 ID；纹理 ID | `bool: boolean` | 设置元件图案纹理。 |
| `CustomUI:SetSize(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 官方序号第 3 项。 |
| `CustomUI:SetFontSize(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 官方序号第 4 项。 |
| `CustomUI:SetColor(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 官方序号第 5 项。 |
| `CustomUI:ShowElement(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 显示元件。 |
| `CustomUI:HideElement(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 隐藏元件。 |
| `CustomUI:RotateElement(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 旋转元件。 |
| `CustomUI:SetAlpha(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 设置透明度。 |
| `CustomUI:SetState(objid: number, uiid: string, elementid: string, pageIndex: string)` | 玩家 ID；界面 ID；元件 ID；状态值 | `code: number` | 设置元件状态。 |
| `CustomUI:SetPosition(objid: number, uiid: string, elementid: string, x: number, y: number)` | 玩家 ID；界面 ID；元件 ID；X；Y | `code: number` | 设置元件位置。 |
| `CustomUI:SetScale(objid: number, uiid: string, elementid: string, ...)` | 官方文档未提供 | `官方文档未提供` | 设置缩放。 |
| `CustomUI:GetItemIcon(itemid: number)` | 道具类型 ID | `code: number, icon: string` | 获取道具图标。 |
| `CustomUI:GetMonsterObjIcon(actorid: number)` | 生物对象 ID | `iconid: number` | 获取生物图标。 |
| `CustomUI:GetMonsterIcon(actorid: number)` | 生物类型 ID | `iconid: number` | 获取生物类型图标。 |
| `CustomUI:GetStatusIcon(buffid: number)` | 状态类型 ID | `code: number, iconid: number` | 获取状态图标。 |
| `CustomUI:GetBlockIcon(blockid: number)` | 方块类型 ID | `code: number, iconid: number` | 获取方块图标。 |
| `CustomUI:GetRoleIcon(playerid: number)` | 玩家 ID | `iconid: number` | 获取角色图标。 |
| `CustomUI:GetRoleHeadIcon(playerid: number)` | 玩家 ID | `官方文档未提供` | 获取角色头像图标。 |
| `CustomUI:GetShortcutIcon(...)` | 官方文档未提供 | 官方文档未提供 | 官方序号第 20 项。 |
| `CustomUI:SmoothMoveTo(...)` | 官方文档未提供 | 官方文档未提供 | 平滑动移动到目标位置。 |
| `CustomUI:SmoothMoveBy(...)` | 官方文档未提供 | 官方文档未提供 | 平滑移动指定偏移。 |
| `CustomUI:SmoothScaleTo(...)` | 官方文档未提供 | 官方文档未提供 | 平滑缩放至目标。 |
| `CustomUI:SmoothScaleBy(...)` | 官方文档未提供 | 官方文档未提供 | 平滑缩放指定倍数。 |
| `CustomUI:SmoothScaleByEx(...)` | 官方文档未提供 | 官方文档未提供 | 扩展版平滑缩放。 |
| `CustomUI:SmoothRotateTo(...)` | 官方文档未提供 | 官方文档未提供 | 平滑旋转至目标角度。 |
| `CustomUI:SmoothRotateBy(...)` | 官方文档未提供 | 官方文档未提供 | 平滑旋转指定角度。 |
| `CustomUI:PlayElementAnim(...)` | 官方文档未提供 | 官方文档未提供 | 播放元件动画。 |
| `CustomUI:StopAnim(...)` | 官方文档未提供 | 官方文档未提供 | 停止元件动画。 |
| `CustomUI:SetLoaderModel(...)` | 官方文档未提供 | 官方文档未提供 | 设置模型加载器模型。 |
| `CustomUI:SetLoaderModelScale(...)` | 官方文档未提供 | 官方文档未提供 | 设置模型加载器缩放。 |
| `CustomUI:SetLoaderModelDir(...)` | 官方文档未提供 | 官方文档未提供 | 设置模型加载器朝向。 |
| `CustomUI:SetLoaderModelPosition(...)` | 官方文档未提供 | 官方文档未提供 | 设置模型加载器位置。 |
| `CustomUI:SetLoaderModelAct(...)` | 官方文档未提供 | 官方文档未提供 | 设置模型加载器动作。 |
| `CustomUI:TurnSliderToPos(...)` | 官方文档未提供 | 官方文档未提供 | 滑动条移动到位置。 |
| `CustomUI:SetSliderDir(...)` | 官方文档未提供 | 官方文档未提供 | 设置滑动条方向。 |
| `CustomUI:SetSliderBarImg(...)` | 官方文档未提供 | 官方文档未提供 | 设置滑动条背景。 |
| `CustomUI:SetRelationPosition(...)` | 官方文档未提供 | 官方文档未提供 | 设置相对位置。 |
| `CustomUI:SetRelationSize(...)` | 官方文档未提供 | 官方文档未提供 | 设置相对尺寸。 |
| `CustomUI:CreateElement(...)` | 官方文档未提供 | 官方文档未提供 | 创建 UI 元件。 |
| `CustomUI:CloneElement(...)` | 官方文档未提供 | 官方文档未提供 | 克隆 UI 元件。 |
| `CustomUI:ChangeParent(...)` | 官方文档未提供 | 官方文档未提供 | 改变父节点。 |
| `CustomUI:SetProgressBarValue(...)` | 官方文档未提供 | 官方文档未提供 | 设置进度值。 |
| `CustomUI:GetProgressBarValue(...)` | 官方文档未提供 | 官方文档未提供 | 获取进度值。 |
| `CustomUI:SetProgressBarResId(...)` | 官方文档未提供 | 官方文档未提供 | 设置进度条资源 ID。 |
| `CustomUI:SmoothChangeProgress(...)` | 官方文档未提供 | 官方文档未提供 | 平滑改变进度。 |
| `CustomUI:SetSpineAnimID(...)` | 官方文档未提供 | 官方文档未提供 | 设置 Spine 动画 ID。 |
| `CustomUI:SmoothIncreaseProgress(...)` | 官方文档未提供 | 官方文档未提供 | 平滑增加进度。 |
| `CustomUI:SetFloatDamageTxt(...)` | 官方文档未提供 | 官方文档未提供 | 设置飘字伤害文本。 |
| `CustomUI:GetScreenSize(playerid: number)` | 玩家 ID | `Width: number, Height: number` | 获取屏幕分辨率。 |
| `CustomUI:DeleteElement(...)` | 官方文档未提供 | `官方文档未提供` | 1.50+；删除 UI 元件。 |
| `CustomUI:SetBeaconBandPos(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标绑定位置。 |
| `CustomUI:SetBeaconObjId(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标绑定对象。 |
| `CustomUI:SetBeaconOffset(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标偏移。 |
| `CustomUI:SetBeaconClampType(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标裁切类型。 |
| `CustomUI:SetBeaconRadius(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标半径。 |
| `CustomUI:SetBeaconMargin(...)` | 官方文档未提供 | 官方文档未提供 | 设置信标边距。 |

```lua
local isSuccess = CustomUI:SetText(Player:GetHostUin(), "7482986899365911542-22886", "7482986899365911542-22886_2", "测试文本")
local code = CustomUI:setState(playerid, uiid, pageIndex)
local code, icon = Customui:getItemIcon(itemid)
```

## Item

`https://dev-wiki.mini1.cn/ugc-wiki/apis/item.html` 列出 32 项，参数与示例均完整展开。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Item:GetItemName(itemid: number|string)` | 道具 ID | `name: string / nil` | 获取道具名称。 |
| `Item:RandomItemID()` | 无 | `num: number / nil` | 随机获取道具 ID。 |
| `Item:RandomProjectileID()` | 无 | `num: number / nil` | 随机获取投掷物 ID。 |
| `Item:GetAttr(itemid: number|string, attr: number)` | 道具 ID；属性枚举 `ItemAttr` | `num: number / nil` | 获取道具属性。 |
| `Item:GetItemDesc(itemid: number|string)` | 道具 ID | `name: string / nil` | 获取道具描述。 |
| `Item:GetCustomGunAttr(itemid: number|string, attrname: string)` | 道具 ID；属性名 `GunAttr` | `obj: any / nil` | 仅自定义枪械有效。 |
| `Item:GetCraftIDNum(itemid: number|string)` | 道具 ID | `num: number / nil` | 获取配方数量。 |
| `Item:GetCraftMaterialAndNum(itemid: number|string, index: number)` | 结果道具 ID；配方序号 | `obj: table / nil` | 返回 `{itemid, num}` 原料信息。 |
| `Item:GetFacade(itemid: number|string)` | 道具类型 ID 或预制 ID | `name: string / nil` | 获取道具外观。 |
| `Item:CreateItemInstInWorld(itemid: number|string, pos: table, worldId: number)` | 道具 ID；位置；星球 ID | `id: number / nil` | 在世界创建道具掉落物。 |
| `Item:CreateGunInWorld(itemid: number|string, pos: table, worldId: number)` | 道具 ID；位置；星球 ID | `id: number / nil` | 在世界创建枪械掉落物。 |
| `Item:GetEquipItemGridID(itemid: number|string)` | 装备道具 ID | `num: number` | 返回装备栏索引。 |
| `Item:ModifyGunAttribute(instId: string, key: string, value: number|string|boolean)` | 实例 ID；属性枚举 `GunAttr`；值 | `bool: boolean` | 修改枪械实例属性。 |
| `Item:GetGunAttribute(instId: string, key: string)` | 实例 ID；属性枚举 `GunAttr` | `value: number|string|boolean|nil` | 获取枪械实例属性。 |
| `Item:GetGunPrefabAttribute(instId: string, key: string)` | 实例 ID；属性枚举 `GunAttr` | `value: number|string|boolean|nil` | 获取枪械预制属性。 |
| `Item:GetItemIdByInstanceId(instId: string)` | 实例 ID | `itemId: number|string|nil` | 获取实例对应道具 ID。 |
| `Item:AddSubModelPart(instId: string, partName: string, boneName: string, modelStr: string, offset: table, rot: table, scale: table)` | 实例 ID；部件名；挂点；模型；偏移；旋转；缩放 | `partName: string / nil` | 添加模型子部件。 |
| `Item:DeleteSubModelPart(instId: string, partName: string)` | 实例 ID；部件名 | `bool: boolean` | 删除子部件。 |
| `Item:ReplaceSubModelPart(instId: string, partName: string, boneName: string, modelStr: string, offset: table, rot: table, scale: table)` | 实例 ID；部件名；挂点；模型；偏移；旋转；缩放 | `bool: boolean` | 替换子部件。 |
| `Item:SetStringCustomData(instId: string, key: string, value: string)` | 实例 ID；键；值 | `bool: boolean` | 写入字符串自定义数据。 |
| `Item:SetBoolCustomData(instId: string, key: string, value: boolean)` | 实例 ID；键；值 | `bool: boolean` | 写入布尔自定义数据。 |
| `Item:SetNumberCustomData(instId: string, key: string, value: number)` | 实例 ID；键；值 | `bool: boolean` | 写入数值自定义数据。 |
| `Item:SetObjCustomData(instId: string, key: string, value: table)` | 实例 ID；键；对象值 | `bool: boolean` | 写入对象自定义数据；会被序列化保存。 |
| `Item:SetArrayCustomData(instId: string, key: string, value: table)` | 实例 ID；键；数组 | `bool: boolean` | 写入数组自定义数据；会被序列化保存。 |
| `Item:GetStringCustomData(instId: string, key: string)` | 实例 ID；键 | `value: string / nil` | 读取字符串自定义数据。 |
| `Item:GetBoolCustomData(instId: string, key: string)` | 实例 ID；键 | `value: boolean / nil` | 读取布尔自定义数据。 |
| `Item:GetNumberCustomData(instId: string, key: string)` | 实例 ID；键 | `value: number / nil` | 读取数值自定义数据。 |
| `Item:GetObjCustomData(instId: string, key: string)` | 实例 ID；键 | `value: table / nil` | 读取对象自定义数据。 |
| `Item:GetArrayCustomData(instId: string, key: string)` | 实例 ID；键 | `value: table / nil` | 读取数组自定义数据。 |
| `Item:GetItemInstFacade(instId: string)` | 实例 ID | `name: string / nil` | 获取道具实例外观。 |
| `Item:GetGridAttr(objid: number, attr: number)` | 对象 ID；属性枚举 `GridAttr` | `num: number / nil` | 获取掉落物或投掷物格子属性。 |
| `Item:GetTags(itemid: number|string)` | 道具定义 ID 或预制 ID | `obj: table / nil` | 1.52+；获取道具标签组。 |

```lua
local itemName = Item:GetItemName(12005)
local facade = Item:GetFacade("r2_7495945919239178250_23010")
local ret = Item:AddSubModelPart(instId, "gun1", "muzzle", "newModel_11000005", {x=0, y=0, z=0}, {x=0, y=0, z=0}, {x=1, y=1, z=1})
```

## Block

`https://dev-wiki.mini1.cn/ugc-wiki/apis/block.html` 列出 28 项，全部参数和返回值完整展开。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Block:IsSolidBlock(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 判断是否为固体方块。 |
| `Block:IsLiquidBlock(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 判断是否为液体方块。 |
| `Block:IsAirBlock(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 判断是否为空气方块。 |
| `Block:GetBlockID(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `id: number` | 获取方块类型 ID。 |
| `Block:DestroyBlock(x: number, y: number, z: number, dropitem: boolean, worldId: number, btrigger: boolean)` | 坐标；是否掉落；星球 ID；是否触发事件 | `bool: boolean` | 摧毁方块。 |
| `Block:PlaceBlock(blockid: number|string, x: number, y: number, z: number, face: number, color: number|string, worldId: number, btrigger: boolean)` | 方块 ID；坐标；朝向；颜色；星球 ID；是否触发事件 | `bool: boolean` | 放置方块。 |
| `Block:ReplaceBlock(blockid: number|string, x: number, y: number, z: number, face: number, color: number|string, worldId: number, btrigger: boolean)` | 方块 ID；坐标；朝向；颜色；星球 ID；是否触发事件 | `bool: boolean` | 替换方块。 |
| `Block:SetBlockData(x: number, y: number, z: number, data: number, worldId: number)` | 坐标；方块数据；星球 ID | `bool: boolean` | 设置方块数据。 |
| `Block:GetBlockData(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `num: number` | 获取方块数据。 |
| `Block:GetBlockDir(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `num: number` | 获取方块朝向 `FaceDir`。 |
| `Block:PlayAnim(pos: table, animid: number|string, speed: number, loop: number, worldId: number)` | 位置；动作 ID；速度；循环；星球 ID | `bool: boolean` | 播放方块动作。 |
| `Block:SetBlockSettingAttState(blockid: number|string, atttype: number, switch: boolean, worldId: number)` | 方块 ID；属性枚举 `BlockLimits`；开关；星球 ID | `bool: boolean` | 设置方块属性状态。 |
| `Block:GetBlockSettingAttState(blockid: number|string, atttype: number, worldId: number)` | 方块 ID；属性枚举；星球 ID | `bool: boolean` | 获取方块属性状态。 |
| `Block:GetBlockSwitchStatus(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 获取功能方块开关状态。 |
| `Block:SetBlockSwitchStatus(x: number, y: number, z: number, isactive: boolean, worldId: number)` | 坐标；开关状态；星球 ID | `bool: boolean` | 设置功能方块开关状态。 |
| `Block:GetBlockPowerStatus(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 获取方块通电状态。 |
| `Block:RandomBlockID()` | 无 | `id: number` | 随机获取方块 ID。 |
| `Block:GetBlockDefName(blockid: number|string)` | 方块 ID | `name: string` | 获取方块名称。 |
| `Block:GetBlockDefDesc(blockid: number|string)` | 方块 ID | `value: string` | 获取方块描述。 |
| `Block:ReplaceBluePrint(x: number, y: number, z: number, blueprint: string, angle: number, mirror: boolean, placeMode: boolean)` | 位置；蓝图资源 ID；旋转；是否镜像；是否全区域覆盖 | `bool: boolean` | 放置蓝图。 |
| `Block:PlayCrackEffect(x: number, y: number, z: number, process: number, worldId: number)` | 坐标；进度 -1—10；星球 ID | `bool: boolean` | 播放裂纹特效。 |
| `Block:PlayDestroyEffect(x: number, y: number, z: number, worldId: number)` | 坐标；星球 ID | `bool: boolean` | 播放方块损毁特效。 |
| `Block:GetBlockDropItemType(blockid: number|string, itype: number)` | 方块 ID；采集方式 1/2/3 | `obj: table` | 返回 `{itemid, itemnum, odds}`。 |
| `Block:GetBlockDropExp(blockid: number|string)` | 方块 ID | `num: number` | 获取采集经验。 |
| `Block:SetBlockColor(x: number, y: number, z: number, color: number, worldId: number)` | 坐标；颜色；星球 ID | `bool: boolean` | 设置方块颜色。 |
| `Block:SetBlockDir(x: number, y: number, z: number, dir: number, worldId: number)` | 坐标；方向 `FaceDir`；星球 ID | `bool: boolean` | 设置方块方向。 |
| `Block:GetFacade(blockid: number|string)` | 方块 ID 或预制 ID | `value: string` | 获取方块外观。 |
| `Block:SetBlockTextureColor(blockid: number, color: number, alpha: number, slotindex: number)` | 方块 ID；颜色；混合比例 0—100；材质槽索引 | `bool: boolean` | 设置方块纹理颜色。 |

```lua
local blockID = Block:GetBlockID(x, y, z, WorldId)
local success = Block:PlaceBlock(376, x, y, z, FaceDir.PosX, nil, WorldId)
local success2 = Block:PlaceBlock(605, x + 1, y, z, FaceDir.PosX, 0XFFFFFF, WorldId)
```

## Backpack

`https://dev-wiki.mini1.cn/ugc-wiki/apis/backpack.html` 列出 40 项。官方展开的签名如下。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Backpack:SetGridItem(playerid: number, gridid: number, itemid: number|string, num: number, durability: number)` | 玩家 ID；格子 ID；道具 ID；数量；耐久 | `bool: boolean` | 设置背包格道具；数量默认 1、耐久默认 1。 |
| `Backpack:RemoveGridItem(playerid: number, gridid: number, num: number)` | 玩家 ID；格子 ID；数量 | `bool: boolean` | 移除背包格道具；数量默认全部。 |
| `Backpack:RemoveGridItemByItemID(playerid: number, itemid: number|string, num: number)` | 玩家 ID；道具 ID；数量 | `num: number` | 返回实际移除数量；`num > 0` 表示成功。 |
| `Backpack:ClearPack(playerid: number, bartype: number)` | 玩家 ID；背包栏枚举 `BackpackType` | `bool: boolean` | 清空指定背包栏。 |
| `Backpack:ClearAllPack(playerid: number)` | 玩家 ID | `bool: boolean` | 清空全部背包。 |
| `Backpack:MoveGridItem(playerid: number, gridsrc: number, griddst: number, num: number)` | 玩家 ID；源格子；目标格子；数量 | `bool: boolean` | 移动背包道具；数量默认全部。 |
| `Backpack:SwapGridItem(playerid: number, gridsrc: number, griddst: number)` | 玩家 ID；源格子；目标格子 | `bool: boolean` | 交换两个格子道具。 |
| `Backpack:EnoughSpaceForItem(playerid: number, itemid: number|string, num: number)` | 玩家 ID；道具 ID；数量 | `bool: boolean` | 检查空间是否足够；数量默认 1。 |
| `Backpack:CalcSpaceNumForItem(playerid: number, itemid: number|string)` | 玩家 ID；道具 ID | `num: number` | 计算可存放数量。 |
| `Backpack:HasItemByBackpackBar(playerid: number, bartype: number, itemid: number|string)` | 玩家 ID；背包栏；道具 ID | `bool: boolean, id: number` | 检测是否持有道具，并返回所在格 ID。 |
| `Backpack:GetItemNum(playerid: number, itemid: number|string, bartype: number)` | 玩家 ID；道具 ID；背包栏 | 官方文档未提供 | 官方序号第 11 项。 |
| `Backpack:AddItem(playerid: number, itemid: number|string, num: number, durability: number)` | 玩家 ID；道具 ID；数量；耐久 | 官方文档未提供 | 官方序号第 12 项。 |
| `Backpack:DiscardItem(playerid: number, gridid: number, num: number)` | 玩家 ID；格子 ID；数量 | 官方文档未提供 | 丢弃背包道具。 |
| `Backpack:ActEquipUpByResID(playerid: number, itemid: number|string)` | 玩家 ID；装备道具 ID | 官方文档未提供 | 穿戴装备。 |
| `Backpack:ActEquipOffByEquipID(playerid: number, equipID: number)` | 玩家 ID；装备 ID | 官方文档未提供 | 脱下装备。 |
| `Backpack:ActDestructEquip(...)` | 官方文档未提供 | 官方文档未提供 | 官方序号第 16 项。 |
| `Backpack:PlayEquipEffect(...)` | 官方文档未提供 | 官方文档未提供 | 官方序号第 17 项。 |
| `Backpack:StopEquipEffect(...)` | 官方文档未提供 | 官方文档未提供 | 官方序号第 18 项。 |
| `Backpack:GetGridInfos(playerid: number, gridid: number)` | 玩家 ID；起始格子 ID | 官方文档未提供 | 批量获取格子信息。 |
| `Backpack:LoadGridInfos(playerid: number, data: table)` | 玩家 ID；格子数据 | 官方文档未提供 | 加载格子信息。 |
| `Backpack:IsLock(playerid: number, gridIndex: number)` | 玩家 Uin；格子索引 | `bool: boolean` | 是否锁定；参数错误返回 `true`。 |
| `Backpack:SetGridsLock(playerid: number, grids: table, lock: boolean)` | 玩家 ID；格子索引表；锁定状态 | 官方文档未提供 | 1.48+；批量锁定或解锁。 |
| `Backpack:GetGunInstIdInBackpack(playerid: number)` | 玩家 Uin | `ids: table` | 获取背包中所有枪械实例 ID。 |
| `Backpack:GetGridAttr(playerid: number, gridid: number, attr: number)` | 玩家 ID；格子 ID；属性枚举 `GridAttr` | `num: number` | 获取背包格属性。 |
| `Backpack:SetGridAttr(playerid: number, gridid: number, attr: number, value: number)` | 玩家 ID；格子 ID；属性枚举；值 | `bool: boolean` | 设置背包格属性。 |
| `Backpack:SetPackCapacity(playerid: number, capacity: number)` | 玩家 ID；容量 | 官方文档未提供 | 设置背包容量。 |
| `Backpack:GetPackCapacity(playerid: number)` | 玩家 ID | 官方文档未提供 | 获取背包容量。 |

```lua
local playerid = Player:GetHostUin()
local result = Backpack:SetGridItem(playerid, BackpackBeginIndex.Shortcut, 100, 3)
local result2 = Backpack:RemoveGridItem(playerid, BackpackBeginIndex.Shortcut, 1)
```

## Graphics

`https://dev-wiki.mini1.cn/ugc-wiki/apis/graphics.html` 列出 40 项，其中“构造数据”函数返回可传入“创建实例”函数的信息表。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Graphics:MakeGraphicsText(title: string, font: number, apha: number, itype: number, autoWrap: number)` | 文本；字号；透明度；类型；自动换行 | `obj: table` | 创建文字板数据。 |
| `Graphics:MakeflotageText(title: string, font: number, itype: number)` | 文本；字号；类型 | `obj: table` | 创建漂浮文字数据。 |
| `Graphics:MakeGraphicsProgress(v1: number, v2: number, color: number|string, itype: number)` | 当前值；最大值；颜色；类型 | `obj: table` | 创建进度条数据。 |
| `Graphics:MakeGraphicsArrowToPos(x: number, y: number, z: number, size: number, color: number|string, itype: number)` | 目标坐标；缩放；颜色；类型 | `obj: table` | 创建指向位置箭头数据。 |
| `Graphics:MakeGraphicsLineToPos(x: number, y: number, z: number, size: number, color: number|string, itype: number)` | 目标坐标；缩放；颜色；类型 | `obj: table` | 创建指向位置线数据。 |
| `Graphics:MakeGraphicsNavPathToPos(x: number, y: number, z: number, itype: number)` | 目标坐标；类型 | `obj: table` | 创建寻路路径数据。 |
| `Graphics:MakeGraphicsSurfaceToPos(x: number, y: number, z: number, size: number, color: number|string, itype: number)` | 目标坐标；缩放；颜色；类型 | `obj: table` | 创建指向位置面数据。 |
| `Graphics:MakeGraphicsArrowToActor(objid: number, size: number, color: number|string, itype: number)` | 目标对象 ID；缩放；颜色；类型 | `obj: table` | 创建指向生物箭头数据。 |
| `Graphics:MakeGraphicsLineToActor(objid: number, size: number, color: number|string, itype: number)` | 目标对象 ID；缩放；颜色；类型 | `info: table` | 创建指向生物线数据。 |
| `Graphics:MakeGraphicsSurfaceToActor(objid: number, size: number, color: number|string, itype: number)` | 目标对象 ID；缩放；颜色；类型 | `info: table` | 创建指向生物面数据。 |
| `Graphics:MakeGraphicsImage(imgid: string, scale: number, apha: number, itype: number)` | 图片 ID；缩放；透明度；类型 | `obj: table` | 创建图片数据。 |
| `Graphics:CreateGraphicsTxtByPos(x: number, y: number, z: number, graphicInfo: table, x2: number, y2: number, worldId: number)` | 坐标；文字数据；附加参数；世界 ID | `id: number` | 在位置创建文字板实例。 |
| `Graphics:CreateGraphicsTxtByActor(objid: number, info: table, dir: table, offest: number, x2: number, y2: number)` | 对象 ID；数据；方向；偏移；参数 | `id: number` | 在对象上创建文字板实例。 |
| `Graphics:CreateflotageTextByPos(x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number)` | 坐标；漂浮文字数据；参数；世界 ID | `id: number` | 在位置创建漂浮文字实例。 |
| `Graphics:CreateflotageTextByActor(objid: number, info: table, dir: table, offest: number, x2: number, y2: number)` | 对象 ID；数据；方向；偏移；参数 | `id: number` | 在对象上创建漂浮文字实例。 |
| `Graphics:CreateGraphicsProgressByPos(x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number)` | 坐标；进度条数据；参数；世界 ID | `id: number` | 在位置创建进度条实例。 |
| `Graphics:CreateGraphicsProgressByActor(objid: number, info: table, dir: table, offest: number, x2: number, y2: number)` | 对象 ID；数据；方向；偏移；参数 | `id: number` | 在对象上创建进度条实例。 |
| `Graphics:RemoveGraphicsByPos(x: number, y: number, z: number, itype: number, graphType: number, worldId: number)` | 坐标；类型；图文类型；世界 ID | `bool: boolean` | 按位置删除图文。 |
| `Graphics:RemoveGraphicsByObjID(objid: number, itype: number, graphType: number)` | 对象 ID；类型；图文类型 | `bool: boolean` | 按对象删除图文。 |
| `Graphics:UpdateGraphicsTextById(graphid: number, title: string, fontsize: number, apha: number, isync: boolean)` | 图文 ID；文本；字号；透明度；是否同步 | `bool: boolean` | 1.50+；更新文字板。 |
| `Graphics:UpdateGraphicsProgressById(graphid: number, val1: number, val2: number, isync: boolean)` | 图文 ID；当前值；最大值；是否同步 | `bool: boolean` | 更新进度条。 |
| `Graphics:CreateGraphicsArrowByActorToPos(objid: number, info: table, dir: table, offset: number)` | 对象 ID；箭头数据；方向；偏移 | `bool: boolean` | 从对象到位置创建箭头。 |
| `Graphics:CreateGraphicsArrowByActorToActor(objid: number, info: table, dir: table, offset: number)` | 对象 ID；箭头数据；方向；偏移 | `bool: boolean` | 从对象到对象创建箭头。 |
| `Graphics:CreateGraphicsArrowByPosToPos(pos: table, info: table, worldId: number)` | 起始位置；箭头数据；世界 ID | `bool: boolean` | 从位置到位置创建箭头。 |
| `Graphics:CreateGraphicsArrowByPosToActor(pos: table, info: table, worldId: number)` | 起始位置；箭头数据；世界 ID | `bool: boolean` | 从位置到对象创建箭头。 |
| `Graphics:CreateGraphicsLineByActorToPos(objid: number, info: table, dir: table, offset: number)` | 对象 ID；线数据；方向；偏移 | `bool: boolean` | 从对象到位置创建线。 |
| `Graphics:CreateGraphicsNavPathByActorToPos(objid: number, info: table, dir: table, offset: number)` | 对象 ID；路径数据；方向；偏移 | `bool: boolean` | 从对象到位置创建寻路线。 |
| `Graphics:CreateGraphicsLineByActorToActor(objid: number, info: table, dir: table, offset: number)` | 对象 ID；线数据；方向；偏移 | `bool: boolean` | 从对象到对象创建线。 |
| `Graphics:CreateGraphicsLineByPosToPos(pos: table, info: table, worldId: number)` | 起始位置；线数据；世界 ID | `bool: boolean` | 从位置到位置创建线。 |
| `Graphics:CreateGraphicsLineByPosToActor(pos: table, info: table, worldId: number)` | 起始位置；线数据；世界 ID | `bool: boolean` | 从位置到对象创建线。 |
| `Graphics:CreateGraphicsSurfaceByActorToPos(objid: number, info: table, dir: table, offset: number)` | 对象 ID；面数据；方向；偏移 | `bool: boolean` | 从对象到位置创建面。 |
| `Graphics:CreateGraphicsSurfaceByActorToActor(objid: number, info: table, dir: table, offset: number)` | 对象 ID；面数据；方向；偏移 | `bool: boolean` | 从对象到对象创建面。 |
| `Graphics:CreateGraphicsSurfaceByPosToPos(pos: table, info: table, worldId: number)` | 起始位置；面数据；世界 ID | `bool: boolean` | 从位置到位置创建面。 |
| `Graphics:CreateGraphicsSurfaceByPosToActor(pos: table, info: table, worldId: number)` | 起始位置；面数据；世界 ID | `bool: boolean` | 从位置到对象创建面。 |
| `Graphics:ReplaceAllGraphics(srcObjid: number, desObjid: number)` | 源对象 ID；目标对象 ID | `bool: boolean` | 迁移对象上的图文。 |
| `Graphics:CreateGraphicsImageByPos(x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number)` | 坐标；图片数据；参数；世界 ID | `bool: boolean` | 在位置创建图片。 |
| `Graphics:CreateGraphicsImageByActor(objid: number, info: table, dir: table, offest: number, x2: number, y2: number)` | 对象 ID；图片数据；方向；偏移；参数 | `bool: boolean` | 在对象上创建图片。 |
| `Graphics:GetInnerGraphicsOffset(tuin: number, itype: number, callback: function)` | 玩家 ID；类型；回调 | 官方文档未提供 | 通过回调返回内嵌图文偏移。 |
| `Graphics:CreateBrushByPos(pos: table, dim: table, color: number|string, showuin: number, itype: number, worldId: number)` | 位置；尺寸；颜色；显示对象；类型；世界 ID | `id: number` | 创建笔刷区域。 |
| `Graphics:RemoveGraphicsByGraphicsID(objid: number)` | 图文 ID | `bool: boolean` | 1.54+；按 ID 删除图文。 |

```lua
local data = Graphics:MakeGraphicsText("123", 16, 0, 1, true)
local x, y, z = Actor:GetPosition(Player:GetHostUin())
local id = Graphics:CreateGraphicsTxtByPos(x, y + 1, z, data, 0, 100, WorldId)
```

## Area

`https://dev-wiki.mini1.cn/ugc-wiki/apis/area.html` 列出 29 项，全部签名完整展开。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Area:CreateAreaPrefab(pos: table, size: table, worldId: number)` | 底部中心位置；大小；星球 ID | `obj: object` | 创建区域预制对象。 |
| `Area:GetAreaUuidByObjId(objId: number)` | 区域对象 ID | `id: string / nil` | 获取区域 UUID。 |
| `Area:CreateAreaRectByRange(posBeg: table, posEnd: table, btmp: boolean, worldId: number)` | 起始位置；结束位置；临时标记；星球 ID | `areaid: number` | 按范围创建矩形区域。 |
| `Area:DestroyArea(areaid: number)` | 区域 ID | `bool: boolean` | 销毁区域。 |
| `Area:GetAreaCenter(areaid: number)` | 区域 ID | `pos: table` | 获取区域中心。 |
| `Area:GetAreaRectLength(areaid: number)` | 区域 ID | `lenx: number, leny: number, lenz: number` | 获取三个轴向长度。 |
| `Area:GetAreaRectRange(areaid: number)` | 区域 ID | `posBeg: table, posEnd: table, worldId: number` | 获取范围及所在星球 ID。 |
| `Area:GetRandomPos(areaid: number)` | 区域 ID | 官方文档未提供 | 获取区域内随机位置。 |
| `Area:ObjInArea(areaid: number, objid: number)` | 区域 ID；对象 ID | 官方文档未提供 | 检测对象是否在区域中。 |
| `Area:BlockInArea(areaid: number, blockid: number|string)` | 区域 ID；方块 ID | 官方文档未提供 | 检测区域是否含指定方块。 |
| `Area:PosInArea(areaid: number, x: number, y: number, z: number)` | 区域 ID；坐标 | 官方文档未提供 | 检测坐标是否在区域内。 |
| `Area:GetAreaPlayers(areaid: number)` | 区域 ID | 官方文档未提供 | 获取区域内玩家。 |
| `Area:GetAreaCreatures(areaid: number)` | 区域 ID | 官方文档未提供 | 获取区域内生物。 |
| `Area:ClearAllBlock(areaid: number)` | 区域 ID | 官方文档未提供 | 清空区域方块。 |
| `Area:CloneAreaBlock(areaid: number, ...)` | 区域 ID；目标区域等 | 官方文档未提供 | 复制区域方块。 |
| `Area:ReplaceAreaBlock(areaid: number, ...)` | 区域 ID；新方块类型等 | 官方文档未提供 | 替换区域方块类型。 |
| `Area:GetAllObjsInAreaRange(...)` | 区域范围；对象类型等 | 官方文档未提供 | 获取范围内全部对象。 |
| `Area:GetAllPlayersInAreaRange(...)` | 区域范围等 | 官方文档未提供 | 获取范围内全部玩家。 |
| `Area:GetAllCreaturesInAreaRange(...)` | 区域范围等 | 官方文档未提供 | 获取范围内全部生物。 |
| `Area:FillBlockAreaRange(...)` | 区域范围；方块 ID等 | 官方文档未提供 | 用方块填充区域。 |
| `Area:ClearAllBlockAreaRange(...)` | 区域范围等 | 官方文档未提供 | 清空范围内方块。 |
| `Area:DestroyAllBlock(areaid: number)` | 区域 ID | 官方文档未提供 | 破坏区域内方块。 |
| `Area:CloneAreaRange(...)` | 源范围；目标范围等 | 官方文档未提供 | 复制范围方块。 |
| `Area:ReplaceAreaRangeBlock(...)` | 源范围；目标方块等 | 官方文档未提供 | 替换范围内方块。 |
| `Area:GetRandomAirPos(areaid: number)` | 区域 ID | 官方文档未提供 | 获取随机空气方块位置。 |
| `Area:GetAreaBlockTypes(areaid: number)` | 区域 ID | 官方文档未提供 | 获取区域内方块类型。 |
| `Area:GetBlockNum(areaid: number)` | 区域 ID | 官方文档未提供 | 获取区域内方块数量。 |
| `Area:CheckRangeCanPlace(posbeg: table, posend: table, uin: number, relativing: number, actortype: number, worldId: number)` | 起止位置；玩家；关系类型；角色类型；星球 ID | `bool: boolean` | 检查范围内能否放置方块。 |
| `Area:GetRelativeActors(posbeg: table, posend: table, uin: number, relativing: number, actortype: number, worldId: number)` | 起止位置；玩家；关系类型；角色类型；星球 ID | `num: number, ids: table` | 获取范围内具有指定关系的角色。 |

```lua
local startPos = {x = x - 10, y = y, z = z - 10}
local endPos = {x = x + 10, y = y + 20, z = z + 10}
local areaId = Area:CreateAreaRectByRange(startPos, endPos, false, WorldId)
local centerPos = Area:GetAreaCenter(areaId)
```

## Monster

`https://dev-wiki.mini1.cn/ugc-wiki/apis/monster.html` 为官方生物模块管理接口，列出 14 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Monster:GetActorID(objid: number)` | 生物对象 ID | `actorid: number / nil` | 获取生物类型 ID。 |
| `Monster:GetActorName(objid: number)` | 生物对象 ID | `name: string / nil` | 获取生物类型名称。 |
| `Monster:ReplaceActor(objidSrc: number, actorid: number|string, replacehp: boolean)` | 源对象 ID；目标类型 ID；是否同步血量 | `ret: number / nil` | 将生物替换为新类型。 |
| `Monster:GetMonsterDefName(actorid: number|string)` | 生物类型 ID 或预制 ID | `name: string / nil` | 获取生物定义名称。 |
| `Monster:GetMonsterDefLevelExp(actorid: number|string)` | 生物类型 ID 或预制 ID | `exp: number / nil` | 获取击杀掉落经验。 |
| `Monster:SetMonsterDefLevelExp(actorid: number|string, levelExp: number)` | 生物类型 ID 或预制 ID；经验 | `ret: boolean` | 设置击杀掉落经验。 |
| `Monster:ChangeAI(objid: number, treeid: number|string)` | 生物对象 ID；行为树 ID | 官方文档未提供 | 切换 AI 行为树。 |
| `Monster:CanSee(objid: number, targetObjid: number)` | 生物对象 ID；目标 ID | 官方文档未提供 | 检测生物是否能看见目标。 |
| `Monster:GetDropItemInfo(actorid: number|string)` | 生物类型 ID 或预制 ID | 官方文档未提供 | 获取掉落物信息。 |
| `Monster:SetTameTarget(objidA: number, objidB: number)` | 生物 A；驯养主/目标 B | 官方文档未提供 | 使生物被目标驯服或设置驯服目标。 |
| `Monster:RandomActorID()` | 无 | 官方文档未提供 | 随机获取生物类型 ID。 |
| `Monster:GetTamedOwnerID(objid: number)` | 生物对象 ID | 官方文档未提供 | 获取驯养主 ID。 |
| `Monster:GetFacade(monsterid: number|string)` | 生物类型 ID 或预制 ID | 官方文档未提供 | 获取生物外观。 |
| `Monster:GetTags(actorid: number|string)` | 生物类型 ID 或预制 ID | 官方文档未提供 | 1.52+；获取生物标签组。 |

```lua
local actorid = Monster:GetActorID(objid)
local actorName = Monster:GetActorName(objId)
local ret = Monster:ReplaceActor(objid, "r1_xxx", true)
```

## WorldContainer

`https://dev-wiki.mini1.cn/ugc-wiki/apis/worldcontainer.html` 列出 16 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `WorldContainer:CheckStorage(x: number, y: number, z: number, worldId: number|nil)` | 坐标；星球 ID | `ret: boolean, resIdOrBlockId: number|nil` | 检测坐标处是否为储物箱或 MOD 容器。 |
| `WorldContainer:ClearStorageBox(x: number, y: number, z: number, worldId: number|nil)` | 坐标；星球 ID | `ret: boolean` | 清空储物箱。 |
| `WorldContainer:CheckStorageEmptyGrid(x: number, y: number, z: number, itemid: number|string, worldId: number|nil)` | 坐标；道具 ID；星球 ID | `ret: boolean` | 检测是否有空位或可叠加空间。 |
| `WorldContainer:SetStorageItem(x: number, y: number, z: number, offset: number, itemid: number|string, num: number, worldId: number|nil)` | 坐标；格子索引；道具 ID；数量；星球 ID | `ret: boolean` | 按格子设置道具。 |
| `WorldContainer:GetStorageItem(x: number, y: number, z: number, offset: number, worldId: number|nil)` | 坐标；格子索引；星球 ID | `itemid: number|string|nil, num: number|nil` | 读取指定格子道具。 |
| `WorldContainer:AddStorageItem(x: number, y: number, z: number, itemid: number|string, num: number, worldId: number|nil)` | 坐标；道具 ID；数量；星球 ID | `ret: number|boolean|nil` | 按堆叠规则添加道具。 |
| `WorldContainer:RemoveStorageItemByID(x: number, y: number, z: number, itemid: number|string, num: number|nil, worldId: number|nil)` | 坐标；道具 ID；数量；星球 ID | `ret: boolean` | 按道具类型移除。 |
| `WorldContainer:RemoveStorageItemByIndex(x: number, y: number, z: number, offset: number, num: number|nil, worldId: number|nil)` | 坐标；格子索引；数量；星球 ID | `ret: boolean` | 按格子移除。 |
| `WorldContainer:AddItemToContainer(x: number, y: number, z: number, itemid: number|string, num: number, worldId: number|nil)` | 坐标；道具 ID；数量；星球 ID | `ret: number|boolean` | 添加道具并返回实际数量。 |
| `WorldContainer:RemoveContainerItemByID(x: number, y: number, z: number, itemid: number|string, num: number, worldId: number|nil)` | 坐标；道具 ID；数量；星球 ID | `ret: boolean` | 移除指定数量道具。 |
| `WorldContainer:ClearContainer(x: number, y: number, z: number, worldId: number|nil)` | 坐标；星球 ID | `ret: boolean` | 清空通用容器。 |
| `WorldContainer:AddWorldStorageItems(x: number, y: number, z: number, itemids: table, worldId: number|nil)` | 坐标；`{{itemId, itemNum}}`；星球 ID | `ret: number` | 批量添加道具并返回累计数量。 |
| `WorldContainer:GetStorageItemInstanceId(x: number, y: number, z: number, offset: number, worldId: number|nil)` | 坐标；格子索引；星球 ID | `ret: string|nil` | 读取格子道具实例 ID。 |
| `WorldContainer:GetAllStorageItemInstanceIds(x: number, y: number, z: number, worldId: number|nil)` | 坐标；星球 ID | `ret: table|nil` | 读取所有带实例 ID 的格子。 |
| `WorldContainer:SwapContainerItem(x: number, y: number, z: number, grid: number, uin: number, grid2: number)` | 容器坐标；容器格子；玩家 Uin；玩家格子 | `ret: boolean|nil` | 在背包与容器间交换道具。 |
| `WorldContainer:GetGridAttr(x: number, y: number, z: number, gridid: number, attr: number, worldId: number)` | 坐标；容器格子；属性枚举；星球 ID | `ret: number` | 获取容器格子属性。 |

```lua
local addNum = WorldContainer:AddItemToContainer(0, 7, 0, 101, 99, WorldId)
WorldContainer:removeContainerItemByID(0, 7, 0, 101, 10, WorldId)
WorldContainer:ClearContainer(0, 7, 0, WorldId)
```

## Buff

`https://dev-wiki.mini1.cn/ugc-wiki/apis/buff.html` 为官方状态模块管理接口，列出 12 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Buff:AddBuff(objid: number, buffid: number|string, customticks: number)` | 对象 ID；状态 ID；持续时间 | `bool: boolean` | 添加状态；`-1` 用默认配置，`0` 为无限。 |
| `Buff:RemoveBuff(objid: number, buffid: number|string)` | 对象 ID；状态 ID | `bool: boolean` | 移除指定状态。 |
| `Buff:ClearAllBuff(objid: number)` | 对象 ID | `bool: boolean` | 清除全部状态。 |
| `Buff:ClearAllBadBuff(objid: number)` | 对象 ID | `bool: boolean` | 清除负面状态。 |
| `Buff:ClearAllGoodBuff(objid: number)` | 对象 ID | `bool: boolean` | 清除有益状态。 |
| `Buff:HasBuff(objid: number, buffid: number|string)` | 对象 ID；状态 ID | `bool: boolean` | 是否拥有指定状态。 |
| `Buff:GetBuffList(objid: number)` | 对象 ID | `num: number, ids: table` | 获取状态数量和 ID 数组。 |
| `Buff:GetBuffNumByBuffid(objid: number, buffid: number|string)` | 对象 ID；状态 ID | `num: number` | 获取指定状态数量。 |
| `Buff:GetBuffLeftTime(objid: number, buffid: number|string)` | 对象 ID；状态 ID | `num: number` | 剩余时间；`0` 表示永久。 |
| `Buff:GetBuffDefName(buffid: number|string)` | 状态 ID | `name: string` | 获取状态定义名称。 |
| `Buff:GetBuffDefDesc(buffid: number|string)` | 状态 ID | `value: string` | 获取状态定义描述。 |
| `Buff:ReplaceBuff(objid: number, buffsrc: number|string, buffdst: number|string, customticks: number)` | 对象 ID；源状态；目标状态；持续时间 | `bool: boolean` | 替换状态并保持数量。 |

```lua
local ret = Buff:AddBuff(objid, buffid, 100)
local num, ids = Buff:GetBuffList(objid)
Buff:RemoveBuff(objid, buffid)
```

## Timer（官方页面名为 MiniTimer）

官方对应页为 `https://dev-wiki.mini1.cn/ugc-wiki/apis/minitimer.html`。抓取器无法解析该 UGC 3.0 路径时，改用官方开发者中心镜像 `https://developers.mini1.cn/wiki/minitimer.html` 交叉核验，共 12 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `MiniTimer:isExist(id: number)` | 计时器 ID | `result: ErrorCode.OK` | 判断计时器是否存在。 |
| `MiniTimer:createTimer(name: string, interval: number|nil, repeated: boolean)` | 名称；间隔；是否重复 | `result: ErrorCode.OK, id: number` | 创建计时器并返回 ID。 |
| `MiniTimer:deleteTimer(name: string, timerid: number)` | 名称；计时器 ID | `code: ErrorCode.OK` | 删除计时器。 |
| `MiniTimer:startBackwardTimer(id: number, interval: number, repeated: boolean)` | 计时器 ID；倒计时时间；是否重复 | `code: ErrorCode.OK` | 启动倒计时。 |
| `MiniTimer:startForwardTimer(id: number)` | 计时器 ID | `code: ErrorCode.OK` | 启动正向计时。 |
| `MiniTimer:pauseTimer(id: number)` | 计时器 ID | `code: ErrorCode.OK` | 暂停计时器。 |
| `MiniTimer:resumeTimer(id: number)` | 计时器 ID | `code: ErrorCode.OK` | 恢复计时器。 |
| `MiniTimer:stopTimer(id: number)` | 计时器 ID | `code: ErrorCode.OK` | 停止计时器。 |
| `MiniTimer:changeTimerTime(id: number, curtime: number)` | 计时器 ID；当前时刻 | `code: ErrorCode.OK` | 改变计时器时间。 |
| `MiniTimer:getTimerTime(id: number)` | 计时器 ID | `code: ErrorCode.OK, runtime: number` | 获取当前倒计时时间。 |
| `MiniTimer:showTimerWnd(playerids: table, timerid: number, title: string)` | 玩家 ID 数组；计时器 ID；标题 | `code: ErrorCode.OK` | 显示计时器窗口；`nil` 表示全部玩家。 |
| `MiniTimer:hideTimerWnd(playerids: table, timerid: number)` | 玩家 ID 数组；计时器 ID | `code: ErrorCode.OK` | 隐藏计时器窗口。 |

```lua
local result = MiniTimer:isExist(1)
local result, id = MiniTimer:createTimer("timer", nil, true)
MiniTimer:startBackwardTimer(1, 20, false)
```

## Trigger（官方为事件/组件接口，无同名函数页）

`https://dev-wiki.mini1.cn/ugc-wiki/event.html` 是事件列表，不是函数页；官方事件名以 `TriggerEvent.*` 形式使用，例如 `TriggerEvent.GameStart`、`TriggerEvent.PlayerRevive`、`TriggerEvent.BlockAdd`、`TriggerEvent.UILostFocus`、`TriggerEvent.ParticlePosOnCreate`。因此本节不把事件名称伪装为函数签名。

实际承担触发器增删的是组件函数页 `https://dev-wiki.mini1.cn/ugc-wiki/introduction/Component.html`，共 22 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Component:GetGameObject()` | 官方文档未提供 | 官方文档未提供 | 获取组件挂载对象实例。 |
| `Component:GetGameObjectId()` | 官方文档未提供 | 官方文档未提供 | 获取组件挂载对象实例 ID。 |
| `Component:IsValid()` | 官方文档未提供 | 官方文档未提供 | 获取组件是否有效。 |
| `Component:AddComponent(...)` | 官方文档未提供 | 官方文档未提供 | 在对象上添加组件。 |
| `Component:RemoveComponent(...)` | 官方文档未提供 | 官方文档未提供 | 移除对象组件。 |
| `Component:GetComponent(...)` | 官方文档未提供 | 官方文档未提供 | 获取对象组件。 |
| `Component:PushCustomEvent(...)` | 官方文档未提供 | 官方文档未提供 | 异步发送自定义消息。 |
| `Component:PushCustomEventSync(...)` | 官方文档未提供 | 官方文档未提供 | 同步发送自定义消息。 |
| `Component:AddCustomEvent(...)` | 官方文档未提供 | 官方文档未提供 | 监听自定义广播消息。 |
| `Component:RemoveCustomEvent(...)` | 官方文档未提供 | 官方文档未提供 | 移除自定义事件监听。 |
| `Component:AddTriggerEvent(...)` | 官方文档未提供 | 官方文档未提供 | 添加触发器事件监听。 |
| `Component:RemoveTriggerEvent(...)` | 官方文档未提供 | 官方文档未提供 | 移除触发器事件监听。 |
| `Component:PushEvent(...)` | 官方文档未提供 | 官方文档未提供 | 异步发送对象事件。 |
| `Component:PushEventSync(...)` | 官方文档未提供 | 官方文档未提供 | 同步发送对象事件。 |
| `Component:AddEvent(...)` | 官方文档未提供 | 官方文档未提供 | 监听对象事件。 |
| `Component:RemoveEvent(...)` | 官方文档未提供 | 官方文档未提供 | 移除对象事件监听。 |
| `Component:DoTaskInTime(...)` | 官方文档未提供 | 官方文档未提供 | 延时执行任务。 |
| `Component:DoPeriodicTask(...)` | 官方文档未提供 | 官方文档未提供 | 周期性执行任务。 |
| `Component:ClearAllTask(...)` | 官方文档未提供 | 官方文档未提供 | 清除所有定时器任务。 |
| `Component:SetEventIsEnable(...)` | 官方文档未提供 | 官方文档未提供 | 设置事件是否启用。 |
| `Component:ThreadWork(...)` | 官方文档未提供 | 官方文档未提供 | 启动新协程；可视为 `threadpool` 能力。 |
| `Component:ThreadWait(...)` | 官方文档未提供 | 官方文档未提供 | 协程等待。 |

## GameObject

`https://dev-wiki.mini1.cn/ugc-wiki/apis/gameobject.html` 为官方实例管理接口，列出 7 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `GameObject:FindObject(id: number|string)` | 游戏对象唯一标识 | `obj: object / nil` | 根据 ID 查找对象。 |
| `GameObject:FindUIObject(id: number|string)` | UI 对象唯一标识 | `obj: objectUI / nil` | 查找 UI 对象。 |
| `GameObject:FindBlockObject(id: number|string)` | 方块类型 ID | `obj: object / nil` | 查找方块类别对象。 |
| `GameObject:CreatePrefabInst(prefabId: string, worldId: number, x: number, y: number, z: number, trigger: boolean)` | 预制 ID；星球 ID；坐标；是否触发事件 | `obj: object / nil` | 使用预制 ID 创建单个对象。 |
| `GameObject:CreatePrefab(objectType: number, prefabId: number|string, x: number, y: number, z: number, num: number, trigger: boolean, worldId: number)` | 对象类型 `ObjType`；预制 ID；坐标；数量；是否触发；星球 ID | `objids: table / nil` | 批量创建对象。 |
| `GameObject:Destroy(objId: number|string)` | 对象 ID | `bool: boolean` | 删除对象。 |
| `GameObject:GetObjectPrefab(objId: number)` | 对象 ID | `id: number|string, num: number` | 获取对象预制 ID 及数量。 |

```lua
local uiObj = GameObject:FindObject("7482986899365911542-22886")
local player = GameObject:FindObject(Player:GetHostUin())
local objs = GameObject:CreatePrefab(ObjType.Mob, 3400, 10, 8, 10, 2, true, WorldId)
```

## CloudSever

官方存在新旧两个云服入口：旧路径 `https://dev-wiki.mini1.cn/cyclopdeia?wikiId=1358&wikiMenuId=3` 可见 `addItemToContainer`、`removeContainerItemByID`、`clearContainer`；新 UGC 路径 `https://dev-wiki.mini1.cn/ugc-wiki/apis/cloudsever.html` 本次抓取仅确认 3 项，且页面把 `CloudSever:SetDataListBykey` 与页面标题中的 `CloudServer` 拼写不一致，报告照抄官方原文。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `CloudSever:SetDataListBykey(libvarid: string, key: string, value: any)` | 表变量设计名；键；值 | `ret: boolean` | 设置指定键的值。 |
| `CloudSever:GetDataListByKey(libvarid: string, key: string, callback: function)` | 表变量设计名；键；回调 | `ret: boolean` | 异步获取；回调参数为 `code, key, data`。 |
| `CloudSever:GetRoomID()` | 无 | `ret: boolean, roomid: string` | 获取当前云服房间 ID。 |

```lua
local result = CloudSever:SetDataListBykey("datalist_1744283491", "num", 123)
CloudSever:GetDataListByKey("datalist_1744283491", "num", function(code, key, data)
    if code == 0 then value = data end
end)
```

## Data

`https://dev-wiki.mini1.cn/ugc-wiki/apis/data.html` 列出 3 项。旧路径 `https://dev-wiki.mini1.cn/cyclopdeia?wikiId=1356&wikiMenuId=3` 存在，但本次仅抓取新路径成功。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Data:SetValue(varId: string, playerId: number, value: any)` | 变量 ID；玩家 ID；值 | `bool: boolean` | 设置变量；全局变量传 `nil`。 |
| `Data:GetValue(varId: string, playerId: number)` | 变量 ID；玩家 ID | `value: any / nil` | 获取变量；失败或无值返回 `nil`。 |
| `Data:IncreasesValue(varId: string, playerId: number, value: number)` | 变量 ID；玩家 ID；增量 | `num: number / nil` | 数值变量增加指定量；参数错误返回 `nil`。 |

```lua
local bool = Data:SetValue(varId, playerId, value)
local value = Data:GetValue(varId, playerId)
local num = Data:IncreasesValue(varId, playerId, value)
```

## Chat

`https://dev-wiki.mini1.cn/ugc-wiki/apis/chat.html` 仅确认 1 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Chat:SendSystemMsg(content: string, playerID: number)` | 消息内容；玩家 ID | `ret: boolean` | 发送系统消息；`playerID` 为 `0` 时发送给所有玩家。 |

```lua
Chat:SendSystemMsg("系统消息")
```

## Mod

`https://dev-wiki.mini1.cn/ugc-wiki/apis/mod.html` 仅确认 1 项。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `Mod:GetCfgIdByAssetId(assetId: string)` | 资源 ID | `cfgId: number` | 通过资源 ID 获取 defId。 |

```lua
local cfgId = Mod:GetCfgIdByAssetId(assetId)
```

## Listen（官方页面名为 ListenParam）

`https://dev-wiki.mini1.cn/ugc-wiki/apis/listenparam.html` 抓取失败，官方镜像 `https://developers.mini1.cn/wiki/listenparam.html` 确认至少 1 项，同时标明该构造方式“此处已废弃”。

| 函数 | 参数 | 返回值 | 说明 |
|---|---|---|---|
| `ListenParam:AddGraphicsListenParam(graphid: number, funcs: table, param: table)` | 图文 ID；监听函数列表；参数 | `ErrorCode.OK` | 监听图文刷新后的对象 ID、参数及回调。 |

```lua
local result = ListenParam:AddGraphicsListenParam(objid, funcs, param)
```

## threadpool、json、LuaPanda、OfficeUtils

这四个名称在本次可核验的 UGC 3.0 官方站内搜索、小写路径、首字母大写路径、旧路径和官方镜像检索中均未获得页面。不能据此认定其为“不存在”：更稳妥的结论是“本次公开抓取未找到对应页面”。其中 `threadpool` 的能力可由 `Component:ThreadWork` 与 `Component:ThreadWait` 承担，但没有官方页面将 `threadpool:work`、`threadpool:wait` 归入独立的 `threadpool` 模块，因此不把组件函数改写成 `threadpool` 签名。

## 抓取成功与失败 URL 清单

### 成功抓取或已验证存在的页面

1. `https://dev-wiki.mini1.cn/ugc-wiki/`：站点首页及教程入口。
2. `https://dev-wiki.mini1.cn/ugc-wiki/API.html`：官方 API 模块导航索引。
3. `https://dev-wiki.mini1.cn/ugc-wiki/apis/update.html`：更新日志；成功。
4. `https://dev-wiki.mini1.cn/ugc-wiki/apis/player.html`：Player，71 项；成功，但 71 项并未全部完整展开。
5. `https://dev-wiki.mini1.cn/ugc-wiki/apis/actor.html`：Actor，官方摘要称 71 项，另一轮抓取称至少 75 项；抓取截断，报告仅完整记录已展开项。
6. `https://dev-wiki.mini1.cn/ugc-wiki/apis/world.html`：World，72 项；成功，但仅部分参数完整展开。
7. `https://dev-wiki.mini1.cn/ugc-wiki/apis/customui.html`：CustomUI，57 项；成功。
8. `https://dev-wiki.mini1.cn/ugc-wiki/apis/item.html`：Item，32 项；成功。
9. `https://dev-wiki.mini1.cn/ugc-wiki/apis/block.html`：Block，28 项；成功。
10. `https://dev-wiki.mini1.cn/ugc-wiki/apis/backpack.html`：Backpack，40 项；成功。
11. `https://dev-wiki.mini1.cn/ugc-wiki/apis/graphics.html`：Graphics，40 项；成功。
12. `https://dev-wiki.mini1.cn/ugc-wiki/apis/area.html`：Area，29 项；成功。
13. `https://dev-wiki.mini1.cn/ugc-wiki/apis/monster.html`：Monster，14 项；成功。
14. `https://dev-wiki.mini1.cn/ugc-wiki/apis/worldcontainer.html`：WorldContainer，16 项；成功。
15. `https://dev-wiki.mini1.cn/ugc-wiki/apis/buff.html`：Buff，12 项；成功。
16. `https://dev-wiki.mini1.cn/ugc-wiki/apis/gameobject.html`：GameObject，7 项；成功。
17. `https://dev-wiki.mini1.cn/ugc-wiki/apis/cloudsever.html`：CloudSever，新页面本次确认 3 项；成功。
18. `https://dev-wiki.mini1.cn/ugc-wiki/apis/data.html`：Data，3 项；成功。
19. `https://dev-wiki.mini1.cn/ugc-wiki/apis/chat.html`：Chat，1 项；成功。
20. `https://dev-wiki.mini1.cn/ugc-wiki/apis/mod.html`：Mod，1 项；成功。
21. `https://dev-wiki.mini1.cn/ugc-wiki/introduction/Component.html`：组件函数/Trigger、threadpool 能力映射页；成功。
22. `https://dev-wiki.mini1.cn/ugc-wiki/event.html`：事件系统；成功，但不是函数 API 页。
23. `https://developers.mini1.cn/wiki/minitimer.html`：Timer/MiniTimer 官方镜像；成功。
24. `https://developers.mini1.cn/wiki/listenparam.html`：Listen/ListenParam 官方镜像；成功。

### 抓取失败或仅返回空响应的 URL

1. `https://dev-wiki.mini1.cn/ugc-wiki/apis/minitimer.html`：抓取器报告无法获取；已由官方镜像交叉验证。
2. `https://dev-wiki.mini1.cn/ugc-wiki/apis/trigger.html`：抓取器报告无法获取；官方使用 `event.html` 与组件函数，而非该路径。
3. `https://dev-wiki.mini1.cn/ugc-wiki/apis/listenparam.html`：抓取器报告无法获取；已由官方镜像交叉验证。
4. `https://dev-wiki.mini1.cn/ugc-wiki/apis/officeutils.html`：抓取器报告无法获取；未发现官方页面。
5. `https://dev-wiki.mini1.cn/ugc-wiki/apis/threadpool.html`：抓取器报告无法获取；未发现官方页面。
6. `https://dev-wiki.mini1.cn/ugc-wiki/apis/json.html`：抓取器报告无法获取；未发现官方页面。
7. `https://dev-wiki.mini1.cn/ugc-wiki/apis/luapanda.html`：抓取器报告无法获取；未发现官方页面。

失败原因分为两类：前三项经官方镜像或官方相邻路径交叉验证，可确认真实页面/对应能力存在；后四项在本次公开抓取范围内没有任何官方 URL 命中，不能将失败原因武断归为 404。

## 官方文档缺失的函数清单

下列“缺失”仅指本次抓取未能从已展开页面取得完整参数与返回值，不等于官方页面没有该函数：

- `Player`：第 7—71 项全部未展开，包括 `SetSkillCD`、`ReviveToPos`、`RotateCamera`、`ChangeViewMode`、`OpenUIView`、`RemovePlayer`、`GetFriendList` 等。
- `Actor`：页面可确认至少 75 项，本报告完整记录了 73 项；其余同名函数仅在摘要中确认存在。
- `World`：第 7—72 项仅确认函数名，未在本次抓取中完整展开参数表。
- `CustomUI`：第 3—10、20 及多个 Smooth/Progress/Beacon 函数只确认名称，官方详情参数缺失。
- `Backpack`：第 11—13、16—20、22—23、26—27、30—40 未完整展开。
- `Area`：第 8—16、18—19、23—28 仅确认名称或只确认存在，参数细节缺失。
- `Monster`：`ChangeAI`、`CanSee`、`GetDropItemInfo`、`SetTameTarget`、`RandomActorID`、`GetTamedOwnerID`、`GetFacade`、`GetTags` 的完整参数与示例未随本次抓取展开。
- `ListenParam`：官方页面至少声明“此处已废弃”，本次只确认 `AddGraphicsListenParam`。
- `MiniTimer`：完整签名来自官方镜像；UGC 3.0 新域名页面抓取失败。
- `Component`：全部 22 项均未提供参数名、参数类型、返回值及示例代码。
- `CloudSever`：新 UGC 页面仅完整展开 3 项；旧文档还有更多云服函数，但旧页不在 `/ugc-wiki/apis/cloudsever.html` 范围内，未并入该模块计数。

以下名称没有找到官方页面，因而没有“官方文档缺失的函数”，只有“未找到官方模块文档”：`threadpool`、`json`、`LuaPanda`、`OfficeUtils`。在补抓到正式页面前，建议知识库将这四项标记为 `status: unverified`，不要自动关联社区资料。

## 引用来源

[1] https://dev-wiki.mini1.cn/ugc-wiki/
> “World 世界 world对象是整个迷你世界 API的入口点。”

[2] https://dev-wiki.mini1.cn/ugc-wiki/API.html
> “事件系统 Event / 方块管理 Block / 对象管理 Actor / 玩家管理 Player / 生物管理 Monster”

[3] https://dev-wiki.mini1.cn/ugc-wiki/apis/update.html
> “1.54+ | Graphics | RemoveGraphicsByGraphicsID(...) | 按ID删除图文”

[4] https://dev-wiki.mini1.cn/ugc-wiki/apis/player.html
> “GetHostUin(...) 获取房主Uin；SetGameResults(...) 设置对局结果；SetGameWin(...) 设置玩家胜利”

[5] https://dev-wiki.mini1.cn/ugc-wiki/apis/actor.html
> “GetItemId(objid: number): id: number 掉落物类型ID(失败返回nil)”

[6] https://dev-wiki.mini1.cn/ugc-wiki/apis/world.html
> “GetLightByPos 参数及类型: x|y|z:number:位置,worldId:number:星球id(默认当前主机所在星球)”

[7] https://dev-wiki.mini1.cn/ugc-wiki/apis/customui.html
> “SetText ... objid: number 玩家/对象ID, uiid: string 界面ID, elementid: string 元件ID, text: string 文本内容”

[8] https://dev-wiki.mini1.cn/ugc-wiki/apis/item.html
> “GetTags ... itemid: number/string 道具定义ID或道具预制ID；返回值 obj: table/nil 标签组”

[9] https://dev-wiki.mini1.cn/ugc-wiki/apis/block.html
> “IsSolidBlock ... worldId: number 星球id(默认当前主机所在星球)；返回值 bool: boolean”

[10] https://dev-wiki.mini1.cn/ugc-wiki/apis/backpack.html
> “SetGridItem ... playerid: number, gridid: number, itemid: number/string, num: number(默认1), durability: number(默认1)”

[11] https://dev-wiki.mini1.cn/ugc-wiki/apis/graphics.html
> “MakeGraphicsText(title: string, font: number, apha: number, itype: number, autoWrap: number)”

[12] https://dev-wiki.mini1.cn/ugc-wiki/apis/area.html
> “CreateAreaRectByRange ... posBeg: table, posEnd: table, btmp: boolean, worldId: number”

[13] https://dev-wiki.mini1.cn/ugc-wiki/apis/monster.html
> “ReplaceActor ... objidSrc: number 源对象ID, actorid: number/string 目标生物defId或资源id”

[14] https://dev-wiki.mini1.cn/ugc-wiki/apis/worldcontainer.html
> “AddWorldStorageItems ... itemids: table ... 返回累计成功添加的总数量”

[15] https://dev-wiki.mini1.cn/ugc-wiki/apis/buff.html
> “AddBuff(objid: number, buffid: number|string, customticks: number): bool”

[16] https://dev-wiki.mini1.cn/ugc-wiki/apis/gameobject.html
> “FindObject ... id: number/string 游戏对象唯一标识；返回值 obj: object 游戏对象”

[17] https://dev-wiki.mini1.cn/ugc-wiki/apis/cloudsever.html
> “SetDataListBykey ... libvarid:string:表变量设计名,key:string:获取的键值,value:Any:任意值”

[18] https://dev-wiki.mini1.cn/ugc-wiki/apis/data.html
> “SetValue ... varId: string 变量ID, playerId: number 玩家ID(全局变量传nil), value:any设置的值”

[19] https://dev-wiki.mini1.cn/ugc-wiki/apis/chat.html
> “SendSystemMsg ... content: string 消息, playerID: number 玩家ID 0表示发给所有玩家”

[20] https://dev-wiki.mini1.cn/ugc-wiki/apis/mod.html
> “GetCfgIdByAssetId ... assetId: string 资源id；返回值 cfgId: number defid”

[21] https://dev-wiki.mini1.cn/ugc-wiki/introduction/Component.html
> “AddTriggerEvent(...) 添加触发事件；ThreadWork(...) 启动新协程；ThreadWait(...) 线程等待”

[22] https://dev-wiki.mini1.cn/ugc-wiki/event.html
> “TriggerEvent.GameStart 游戏创建；TriggerEvent.PlayerRevive 玩家复活”

[23] https://developers.mini1.cn/wiki/minitimer.html
> “isExist ... id: number 计时器ID；createTimer ... name: string 计时器名称”

[24] https://developers.mini1.cn/wiki/listenparam.html
> “AddGraphicsListenParam ... graphid: number 已创建的图文信息ID, funcs: table 监听函数列表”
