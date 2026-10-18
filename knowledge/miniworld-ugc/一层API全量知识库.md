# 迷你世界 UGC 3.0 —— 一层模块全量 API 知识库

> 数据来源：①真机探针导出的一层反射结果（`一层测试.csv`，3112 条 / 275 模块）②官方 Wiki `dev-wiki.mini1.cn/ugc-wiki/apis/*.html` ③标准 Lua 5.1 + 引擎扩展（真机探针确认）

> 口径：**签名以官方文档为准；官方没有的按字面意思 + 同类函数 + 标准库记忆推测，来源列明确标注**。推测项未经真机验证，调用前先 `type(模块.函数)` 判存在。

## 覆盖统计

| 来源 | 条数 | 说明 |
|---|---|---|
| 官方 Wiki | 505 | 参数/返回值照抄官方页面 |
| 标准库/真机 | 84 | math/string/table/bit/os/coroutine/debug，真机探针已确认存在 |
| 推测 | 160 | 依命名与同类推断，**待验证** |
| **合计** | **749** | 一层全部函数 |

另：一层还有 244 个**纯枚举模块**（number/table/string 常量），见文末附录。

## 调用形式

```lua
-- 冒号调用（模块为引擎全局表）
local x,y,z = Actor:GetPosition(objid)
local ok = Block:PlaceBlock(452, x, y, z, 0)

-- 事件监听（官方写法）
ScriptSupportEvent:registerEvent([=[PlayerClickBlock]=], self.Player_Click)
function Script:Player_Click(e)  -- e.eventobjid, e.blockid, e.x, e.y, e.z
end
```

游戏每 50ms 推进一 tick；所有按时间推进的调度一律用 `os.timeMs()` 绝对时间戳，不要逐帧累加。

---

## Player（98 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Player:AddMagazine` | `objid:number, itemid:number\|string, num:number` | `boolean` | 给枪械装填弹匣；同类 GunGetMagazine 为读取 | 推测 |
| `Player:ChangPlayerMoveType` | `uin:number,moveType:number` | `boolean` | chang player move type | 官方 |
| `Player:ChangeViewMode` | `objid:number,viewmode:number,islock:boolean` | `boolean` | change view mode | 官方 |
| `Player:ChangeViewModeForMod` | `objid:number, viewmode:number, islock:boolean` | `boolean` | MOD 专用视角切换 | 推测 |
| `Player:CheckActionAttrState` | `objid:number, atttype:number` | `boolean` | 查询动作属性状态；与 SetCameraAttrState 同族 | 推测 |
| `Player:ClearMotion` | `uin:number` | `boolean` | 移除 motion | 官方 |
| `Player:EnterGunState` | `objid:number, state:number` | `boolean` | 进入枪械状态；LevelGunState 应为同级退出/升级接口 | 推测 |
| `Player:ForceOpenBoxUI` | `objid:number, x:number\|table, y:number, z:number` | `boolean` | 强制打开容器 UI；与 OpenBoxByPos 同族 | 推测 |
| `Player:GetAimDir` | `objid:number` | `table` | 读取 aim dir | 官方 |
| `Player:GetAimPos` | `objid:number` | `table` | 读取 aim pos | 官方 |
| `Player:GetBlockAtlasInfo` | `objid:number` | `table` | 取方块图集信息 | 推测 |
| `Player:GetClientInfo` | `uin:number` | `number` | 读取 client info | 官方 |
| `Player:GetCurShotcut` | `objid:number` | `number` | 当前快捷栏索引；与 GetShotcutIndex 同义的另一版 | 推测 |
| `Player:GetCurToolID` | `objid:number` | `number\|string` | 读取 cur tool i d | 官方 |
| `Player:GetFirstInviter` | `callback:function,objid:number` | `number` | 读取 first inviter | 官方 |
| `Player:GetFriendList` | `uin:number,index:number,size:number` | `table` | 读取 friend list | 官方 |
| `Player:GetHorseRealID` | `objid:number` | `number` | 取坐骑真实 ID | 推测 |
| `Player:GetHostUin` | `（无）` | `number` | 读取 host uin | 官方 |
| `Player:GetMiniCurrency` | `objid:number,itype:number` | `number` | 读取 mini currency | 官方 |
| `Player:GetMiniVipLevel` | `playerid:number` | `boolean` | 读取 mini vip level | 官方 |
| `Player:GetNickname` | `objid:number` | `string` | 读取 nickname | 官方 |
| `Player:GetPersonInfo` | `objid:number` | `table` | 拉取玩家个人信息聚合表（昵称/等级/VIP 等） | 推测 |
| `Player:GetPlayerCostStatic` | `callback:function,playerid:number,tbegin:number,tend:number,costtype:number` | `number` | 读取 player cost static | 官方 |
| `Player:GetRayOriginPos` | `objid:number` | `table` | 读取 ray origin pos | 官方 |
| `Player:GetRentCloudServerOwner` | `（无）` | `number` | 读取 rent cloud server owner | 官方 |
| `Player:GetRevivePoint` | `uin:number,worldId:number` | `table` | 读取 revive point | 官方 |
| `Player:GetScreenSpacePos` | `playerid:number,x:number,y:number,z:number` | `table` | 读取 screen space pos | 官方 |
| `Player:GetScreenSpacePosV2` | `playerid:number,x:number,y:number,z:number` | `table` | 读取 screen space pos v2 | 官方 |
| `Player:GetShotcutIndex` | `objid:number` | `number` | 读取 shotcut index | 官方 |
| `Player:GetSkinSeatInfos` | `objid:number` | `table` | 取皮肤席位信息 | 推测 |
| `Player:GetSkinlist` | `objid:number` | `table` | 取玩家皮肤列表 | 推测 |
| `Player:GetViewMode` | `uin:number` | `number` | 读取 view mode | 官方 |
| `Player:GetVisibleRange` | `objid:number` | `number` | 读取可见范围；与 SetVisibleRange 成对 | 推测 |
| `Player:GunGetMagazine` | `objid:number, itemid:number\|string` | `number` | 读取枪械弹匣剩余；与 AddMagazine 成对 | 推测 |
| `Player:HasFriend` | `playerid:number,friendid:number` | `boolean` | 判定 friend | 官方 |
| `Player:HasHandheldGun` | `objid:number` | `boolean` | 是否手持枪械 | 推测 |
| `Player:HideUIView` | `objid:number,uiname:number,effectid:number,time:number` | `boolean` | 界面显隐：hide u i view | 官方 |
| `Player:IsEquipByResID` | `objid:number,itemid:number\|string` | `boolean` | 判定 equip by res i d | 官方 |
| `Player:IsHandWeaponSpellEnhancementActive` | `objid:number` | `boolean` | 手持武器法术强化是否生效 | 推测 |
| `Player:ItemSkillCDDone` | `objid:number, itemid:number\|string` | `boolean` | 道具技能冷却结束 | 推测 |
| `Player:ItemSkillCDEnter` | `objid:number, itemid:number\|string` | `boolean` | 道具技能进入冷却 | 推测 |
| `Player:LevelGunState` | `objid:number, state:number` | `boolean` | 退出或升级枪械状态；与 EnterGunState 成对 | 推测 |
| `Player:MountActor` | `objid:number, rideobjid:number` | `boolean` | 骑乘；Actor:MountActor 有 4 参版本，玩家侧可能简化 | 推测 |
| `Player:NotifyGameInfo2Self` | `objid:number,info:string` | `boolean` | notify game info2 self | 官方 |
| `Player:OpenActView` | `objid:number, actid:number\|string` | `boolean` | 打开活动界面 | 推测 |
| `Player:OpenBoxByPos` | `objid:number,x:number\|table,y:number,z:number` | `boolean` | 界面显隐：open box by pos | 官方 |
| `Player:OpenDevGoodsBuyDetailedDialog` | `objid:number, goodsid:string` | `boolean` | 打开开发者商品详情弹窗 | 推测 |
| `Player:OpenDevGoodsBuyDialog` | `objid:number, goodsid:string` | `boolean` | 打开开发者商品购买弹窗 | 推测 |
| `Player:OpenDevGoodsPage` | `objid:number, goodsid:string` | `boolean` | 打开开发者商品页 | 推测 |
| `Player:OpenDevStore` | `objid:number` | `boolean` | 打开开发者商店 | 推测 |
| `Player:OpenDevStoreTab` | `objid:number, tab:number` | `boolean` | 打开开发者商店指定页签 | 推测 |
| `Player:OpenFriendChatPage` | `objid:number, frienduin:number` | `boolean` | 打开好友聊天页 | 推测 |
| `Player:OpenInnerView` | `uin:number,iview:number,bopen:boolean,data:any` | `boolean` | 界面显隐：open inner view | 官方 |
| `Player:OpenMiniShopItemPage` | `objid:number, itemid:string` | `boolean` | 打开迷你商店商品页 | 推测 |
| `Player:OpenMiniShopPage` | `objid:number, pageid:string` | `boolean` | 打开迷你商店页 | 推测 |
| `Player:OpenMiniShopWarehousePage` | `objid:number` | `boolean` | 打开迷你商店仓库页 | 推测 |
| `Player:OpenShopGiveGiftView` | `objid:number, targetuin:number` | `boolean` | 打开赠礼界面 | 推测 |
| `Player:OpenShopSkinBuyDialog` | `objid:number, skinid:string` | `boolean` | 打开皮肤购买弹窗 | 推测 |
| `Player:OpenShopTryOnView` | `objid:number, skinid:string` | `boolean` | 打开皮肤试穿界面 | 推测 |
| `Player:OpenUIView` | `objid:number,uiname:number,effectid:number,time:number` | `boolean` | 界面显隐：open u i view | 官方 |
| `Player:PauseMusic` | `objid:number,musicId:string,pause:boolean` | `boolean` | 播放/停止类：pause music | 官方 |
| `Player:PlayAdvertising` | `objid:number,adname:string` | `number` | 播放/停止类：play advertising | 官方 |
| `Player:PlayMusic` | `objid:number,musicId:string,volume:number,pitch:number,isLoop:boolean` | `boolean` | 播放/停止类：play music | 官方 |
| `Player:RemovePlayer` | `objid:number` | `boolean` | 移除 player | 官方 |
| `Player:ResetCameraAttr` | `playerid:number` | `boolean` | reset camera attr | 官方 |
| `Player:ReviveToPos` | `objid:number,x:number\|table,y:number,z:number,worldId:number` | `boolean` | revive to pos | 官方 |
| `Player:RotateCamera` | `objid:number,yaw:number,pitch:number` | `boolean` | rotate camera | 官方 |
| `Player:RotateCameraToActor` | `objid:number,targetid:number` | `boolean` | rotate camera to actor | 官方 |
| `Player:RotateMainModel` | `uin:number,yaw:number,pitch:number` | `boolean` | rotate main model | 官方 |
| `Player:SendFriendApply` | `playerid:number,uin2:number` | `boolean` | send friend apply | 官方 |
| `Player:SetCameraAttrState` | `playerid:number,attr:number,enable:boolean` | `boolean` | 设置 camera attr state | 官方 |
| `Player:SetCameraFovTransformBy` | `playerid:number,fov:number,animid:number,time:number` | `boolean` | 设置 camera fov transform by | 官方 |
| `Player:SetCameraFovTransformTo` | `playerid:number,fov:number,animid:number,time:number` | `boolean` | 设置 camera fov transform to | 官方 |
| `Player:SetCameraMountObj` | `playerid:number,objid:number` | `boolean` | 设置 camera mount obj | 官方 |
| `Player:SetCameraMountPos` | `playerid:number,pos:table` | `boolean` | 设置 camera mount pos | 官方 |
| `Player:SetCameraPosTransformBy` | `playerid:number,vec:table,animid:number,time:number` | `boolean` | 设置 camera pos transform by | 官方 |
| `Player:SetCameraPosTransformTo` | `playerid:number,vec:table,animid:number,time:number` | `boolean` | 设置 camera pos transform to | 官方 |
| `Player:SetCameraRotMode` | `playerid:number,attr:number` | `boolean` | 设置 camera rot mode | 官方 |
| `Player:SetCameraRotTransformBy` | `playerid:number,vec:table,animid:number,time:number` | `boolean` | 设置 camera rot transform by | 官方 |
| `Player:SetCameraRotTransformTo` | `playerid:number,vec:table,animid:number,time:number` | `boolean` | 设置 camera rot transform to | 官方 |
| `Player:SetCameraShake` | `playerid:number, duration:number, power:number` | `boolean` | 镜头抖动；与 ShakeCamera 同义 | 推测 |
| `Player:SetCrawl` | `objid:number, enable:boolean` | `boolean` | 设置是否匍匐 | 推测 |
| `Player:SetGameResults` | `objid:number,result:number` | `boolean` | 设置 game results | 官方 |
| `Player:SetGameWin` | `objid:number` | `boolean` | 设置 game win | 官方 |
| `Player:SetGunActionState` | `objid:number,action:number,switch:boolean` | `boolean` | 设置 gun action state | 官方 |
| `Player:SetItemAttAction` | `objid:number,itemid:number\|string,atttype:number,switch:boolean` | `boolean` | 设置 item att action | 官方 |
| `Player:SetMobileVibrate` | `playerid:number,time:number,amplitude:number` | `boolean` | 设置 mobile vibrate | 官方 |
| `Player:SetRevivePoint` | `objid:number,x:number\|table,y:number,z:number,worldId:number` | `boolean` | 设置 revive point | 官方 |
| `Player:SetSettingAbility` | `playerid:number,itype:number,enable:boolean` | `boolean` | 设置 setting ability | 官方 |
| `Player:SetSettingEnable` | `playerid:number,itype:number,enable:boolean` | `boolean` | 设置 setting enable | 官方 |
| `Player:SetShotcutIndex` | `objid:number,index:number` | `boolean` | 设置 shotcut index | 官方 |
| `Player:SetSkillCD` | `objid:number,itemid:number\|string,cd:number` | `boolean` | 设置 skill c d | 官方 |
| `Player:SetVisibleRange` | `objid:number, range:number` | `boolean` | 设置可见范围 | 推测 |
| `Player:ShakeCamera` | `objid:number,duration:number,power:number` | `boolean` | shake camera | 官方 |
| `Player:StandReportEvent` | `playerid:number,eventstr:string` | `boolean` | stand report event | 官方 |
| `Player:StopMusic` | `objid:number,musicId:string` | `boolean` | 播放/停止类：stop music | 官方 |
| `Player:StopShakeCamera` | `objid:number` | `boolean` | 播放/停止类：stop shake camera | 官方 |
| `Player:UseItem` | `objid:number, itemid:number\|string` | `boolean` | 使用道具 | 推测 |

## Actor（91 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Actor:ActorHurt` | `objid: number, targetid: number, damage: number, attacktype: number, ignoreResist: boolean, ignoreTriggerEvent: boolean` | `bool: boolean` | 使对象对目标造成伤害。 | 官方 |
| `Actor:AddHp` | `objid: number, hp: number` | `bool: boolean` | `hp` 为正增加、为负减少当前生命值。 | 官方 |
| `Actor:AddTags` | `objid: number, tags: string\|table, icount: number` | `objid；标签；数量参数` | `bool: boolean` | 官方 |
| `Actor:AppendSpeed` | `objid: number, vx: number, vy: number, vz: number` | `bool: boolean` | 附加瞬时速度。 | 官方 |
| `Actor:ChangActorMoveType` | `objid: number, moveMode: number` | `bool: boolean` | 改变移动方式。 | 官方 |
| `Actor:ChangeCustomModel` | `objid: number, modleName: string` | `bool: boolean` | 修改对象外观模型。 | 官方 |
| `Actor:ClearActorWithId` | `actorid: number\|string, bkill: boolean, worldId: number` | `生物类型 ID；是否击杀；星球 ID` | `bool: boolean` | 官方 |
| `Actor:ClearTags` | `objid: number` | `bool: boolean` | 清空对象标签。 | 官方 |
| `Actor:CompareMainModel` | `facade1: string, facade2: string` | `bool: boolean` | 比较两个主模型外观是否相等。 | 官方 |
| `Actor:DisMountActor` | `objid: number` | `bool: boolean` | 取消骑乘。 | 官方 |
| `Actor:DropActor` | `objid: number, dir: table, isThrow: boolean, speed: number, hasInertance: boolean` | `bool: boolean` | 投掷或放下对象。 | 官方 |
| `Actor:EmitByShooter` | `objid:number, itemid:number\|string, ...` | `boolean` | 由发射者发射投掷物 | 推测 |
| `Actor:EmitByShooterTarget` | `objid:number, itemid:number\|string, targetid:number, ...` | `boolean` | 对目标发射 | 推测 |
| `Actor:EmitByShooterTargetPos` | `objid:number, itemid:number\|string, dstx:number, dsty:number, dstz:number, ...` | `boolean` | 对坐标发射 | 推测 |
| `Actor:EscapePickup` | `objid: number` | `bool: boolean` | 使被抓举对象尝试逃脱。 | 官方 |
| `Actor:FindNearestBlock` | `objid: number, blockid: number\|string, blockRange: number` | `objid；方块 ID；搜索范围` | `x: number, y: number, z: number` | 官方 |
| `Actor:GetActionAttrState` | `objid:number, atttype:number` | `boolean` | 读动作属性状态；与 SetActionAttrState 成对 | 推测 |
| `Actor:GetActorDir` | `objid:number` | `table` | 取朝向（与 GetFaceDirection 同族） | 推测 |
| `Actor:GetActorFacade` | `objid: number, bhasequip: boolean` | `facade: string / nil` | 获取对象外观描述。 | 官方 |
| `Actor:GetActorMovementMode` | `objid: number` | `num: number` | 获取移动模式 `MoveType`。 | 官方 |
| `Actor:GetActorPermissions` | `objid: number, ability: number` | `bool: boolean` | 查询对象权限开关。 | 官方 |
| `Actor:GetAttr` | `objid: number, atttype: number` | `num: number / nil` | 获取属性值；失败返回 `nil`。 | 官方 |
| `Actor:GetBoundSzie` | `objid: number` | `vec: table` | 获取模型边界大小 `{x, y, z}`。 | 官方 |
| `Actor:GetBtreeVarValue` | `objid: number, varid: string` | `val: any / nil` | 读取行为树变量值。 | 官方 |
| `Actor:GetCmpBaseState` | `objid:number, cmpid:number` | `boolean` | 读组件基础状态；与 SetCmpBaseState 成对 | 推测 |
| `Actor:GetCurMapId` | `objid:number` | `number` | 对象所在地图 ID | 推测 |
| `Actor:GetDefID` | `objid:number` | `number` | 取对象定义 ID | 推测 |
| `Actor:GetDropItemInstanceId` | `objid: number` | `id: string / nil` | 获取掉落物实例 ID。 | 官方 |
| `Actor:GetDropItemNum` | `objid: number` | `num: number / nil` | 获取掉落物数量。 | 官方 |
| `Actor:GetEntityFacade` | `prefab: string` | `facade: string / nil` | 根据实体预制名获取外观。 | 官方 |
| `Actor:GetEyeHeight` | `objid: number` | `num: number / nil` | 获取眼睛高度。 | 官方 |
| `Actor:GetFaceDirection` | `objid: number` | `pos: table` | 返回轴向方向向量 `{x, y, z}`。 | 官方 |
| `Actor:GetFacePitch` | `objid: number` | `num: number / nil` | 获取仰望角度。 | 官方 |
| `Actor:GetFaceYaw` | `objid: number` | `num: number / nil` | 获取水平面朝角度。 | 官方 |
| `Actor:GetItemId` | `objid: number` | `id: number / nil` | 根据掉落物对象 ID 获取对应的物品类型 ID。 | 官方 |
| `Actor:GetMaxHP` | `objid: number` | `num: number / nil` | 获取最大生命值，包含属性加成。 | 官方 |
| `Actor:GetMotion` | `objid: number` | `x: number, y: number, z: number` | 获取运动速度分量。 | 官方 |
| `Actor:GetNickName` | `objid: number` | `name: string / nil` | 获取角色昵称。 | 官方 |
| `Actor:GetObjType` | `objid: number` | `itype: number` | 获取对象类型 `ObjType`；失败返回 `nil`。 | 官方 |
| `Actor:GetObjWorldId` | `objid: number` | `id: number / nil` | 获取对象所在星球 ID；失败返回 `-1`。 | 官方 |
| `Actor:GetPickupObjID` | `objid: number, roleType: number` | `id: number` | 获取正在拾取的对象 ID；失败返回 `0`。 | 官方 |
| `Actor:GetPosition` | `objid: number` | `x: number, y: number, z: number` | 获取对象位置。 | 官方 |
| `Actor:GetRidingActorObjId` | `objid: number` | `id: number` | 获取正在骑乘的对象 ID；失败返回 `0`。 | 官方 |
| `Actor:GetTags` | `objid: number` | `tags: table / nil` | 获取对象标签数组。 | 官方 |
| `Actor:GetTeam` | `objid: number` | `id: number / nil` | 获取对象所属队伍 ID。 | 官方 |
| `Actor:HasActor` | `objid:number` | `boolean` | 对象是否存在（与 IsExist 同义） | 推测 |
| `Actor:HasTags` | `objid: number, tags: string\|table, mathcmode: number, bexactmatch: boolean` | `objid；标签或标签表；匹配模式；是否精确匹配` | `bool: boolean` | 官方 |
| `Actor:IncreasesAttr` | `objid: number, atttype: number, val: number` | `bool: boolean` | 1.50+；增加属性值。 | 官方 |
| `Actor:IsExist` | `objid: number` | `bool: boolean` | 检测对象是否存在且存活。 | 官方 |
| `Actor:IsPlayer` | `objid: number` | `bool: boolean` | 判断对象是否为玩家。 | 官方 |
| `Actor:Jump` | `objid: number` | `bool: boolean` | 使对象执行一次跳跃。 | 官方 |
| `Actor:KillSelf` | `objid: number` | `bool: boolean` | 使对象死亡。 | 官方 |
| `Actor:MountActor` | `objid: number, rideobjid: number, isContrl: boolean, isCloseAI: boolean` | `bool: boolean` | 骑乘到目标对象。 | 官方 |
| `Actor:PauseSoundEffectById` | `objid: number, soundId: number, pause: boolean` | `bool: boolean` | 暂停或恢复对象音效。 | 官方 |
| `Actor:PickupActor` | `objidA: number, objidB: number, animid: number\|string, soundId: number, offset: table, rot: table` | `抓取方；被抓方；动作 ID；音效 ID；偏移；旋转` | `bool: boolean` | 官方 |
| `Actor:PickupItem` | `objid: number, itemobjid: number, bforcepickup: boolean` | `num: number` | 拾取掉落物并返回数量。 | 官方 |
| `Actor:PlayAnim` | `objid: number, animid: number\|string, speed: number, loop: number\|boolean` | `boolean)` | `objid`；动作 ID；速度；循环模式 | 官方 |
| `Actor:PlayAnimByObj` | `objidA: number, objidB: number, breplay: boolean` | `bool: boolean` | 对象 A 播放对象 B 的动作。 | 官方 |
| `Actor:PlayBodyEffectById` | `objid:number, effectId:number\|string, ptime:number, offset:table, rot:table, scale:table` | `boolean` | 播放身体特效；与 PlayBodyParticleById 同族 | 推测 |
| `Actor:PlayBodyParticleById` | `objid: number, particleId: number\|string\|table, ptme: number, offset: table, rot: table, scale: table` | `table, ptme: number, offset: table, rot: table, scale: table)` | `objid`；粒子 ID/路径/数组；持续时间；偏移；旋转；缩放 | 官方 |
| `Actor:PlayHandAnim` | `objid: number, animid: number\|string, speed: number, loop: number\|boolean` | `boolean)` | `objid`；动作 ID；速度；循环模式 | 官方 |
| `Actor:PlaySoundEffectById` | `objid: number, soundId: number, volume: number, pitch: number, isLoop: boolean` | `bool: boolean` | 在对象上播放 3D 音效。 | 官方 |
| `Actor:RandomFacadeID` | `（无）` | `id: string / nil` | 随机外观 ID。 | 官方 |
| `Actor:RecoverinitialModel` | `objid: number` | `bool: boolean` | 恢复初始外观模型。 | 官方 |
| `Actor:RemoveTags` | `objid: number, tags: string\|table, icount: number` | `objid；标签；数量参数` | `bool: boolean` | 官方 |
| `Actor:RotateFaceToActor` | `objid: number, targetid: number` | `bool: boolean` | 使对象旋转并朝向目标。 | 官方 |
| `Actor:SetAblePick` | `objid: number, able: boolean` | `bool: boolean` | 设置掉落物可否被拾取。 | 官方 |
| `Actor:SetActionAttrState` | `objid:number, atttype:number, enable:boolean` | `boolean` | 设置动作属性状态 | 推测 |
| `Actor:SetActorPermissions` | `objid: number, ability: number, switch: boolean` | `bool: boolean` | 设置对象行为权限。 | 官方 |
| `Actor:SetAttr` | `objid: number, atttype: number, val: number` | `bool: boolean` | 设置对象属性值。 | 官方 |
| `Actor:SetBeHurtTarget` | `objid: number, targetid: number` | `bool: boolean` | 设置仇恨目标，供 AI 战斗系统使用。 | 官方 |
| `Actor:SetBodyEffectScale` | `objid:number, effectId:number\|string, scale:table` | `boolean` | 设置身体特效缩放 | 推测 |
| `Actor:SetBodyParticleTransform` | `objid: number, particleId: number\|string\|table, offset: table, rot: table, scale: table` | `table, offset: table, rot: table, scale: table)` | `objid`；粒子 ID；偏移；旋转；缩放 | 官方 |
| `Actor:SetBtreeVarValue` | `objid: number, varid: string, val: any` | `bool: boolean` | 设置行为树变量值。 | 官方 |
| `Actor:SetCmpBaseState` | `objid:number, cmpid:number, state:boolean` | `boolean` | 设置组件基础状态 | 推测 |
| `Actor:SetFaceDirection` | `objid: number, x: number, y: number, z: number` | `bool: boolean` | 设置对象朝向。 | 官方 |
| `Actor:SetFacePitch` | `objid: number, pitch: number` | `pitch: number；返回值官方页面抽取异常` | 官方表格将参数写为 `pitch`，返回值抽取为 `num: number`；本表保留官方文字，但无法确认字段是否一致。 | 官方 |
| `Actor:SetFaceYaw` | `objid: number, yaw: number` | `bool: boolean` | 设置水平朝向。 | 官方 |
| `Actor:SetImmuneType` | `objid: number, immunetype: number, isadd: boolean` | `bool: boolean` | 设置指定伤害类型免疫状态。 | 官方 |
| `Actor:SetMountActorAttr` | `objid:number, atttype:number, val:number` | `boolean` | 设置坐骑属性 | 推测 |
| `Actor:SetNickName` | `objid: number, nickname: string` | `bool: boolean` | 设置角色昵称；自动过滤敏感词。 | 官方 |
| `Actor:SetPosition` | `objid: number, x: number, y: number, z: number` | `bool: boolean` | 设置对象位置。 | 官方 |
| `Actor:SetTeam` | `objid: number, teamid: number, bResetAttr: boolean` | `bool: boolean` | 设置对象队伍；重置属性仅对玩家有效。 | 官方 |
| `Actor:ShowNickName` | `objid: number, bshow: boolean` | `bool: boolean` | 设置角色昵称显示状态。 | 官方 |
| `Actor:StopBodyEffectById` | `objid: number, particleId: number\|string\|table` | `table)` | `objid`；粒子 ID | 官方 |
| `Actor:StopSoundEffectById` | `objid: number, soundId: number` | `bool: boolean` | 停止指定对象音效。 | 官方 |
| `Actor:TriggerSkillCall` | `objid:number, skillid:number\|string` | `boolean` | 触发技能调用 | 推测 |
| `Actor:TryMoveToActor` | `objid: number, targetObjid: number, speed: number` | `bool: boolean` | 向目标对象寻路移动。 | 官方 |
| `Actor:TryMoveToPos` | `objid: number, x: number, y: number, z: number, cancontrol: boolean, bshowtip: boolean` | `bool: boolean` | 使用寻路移动至目标位置。 | 官方 |
| `Actor:TryPickupActorForward` | `objid: number, distance: number` | `bool: boolean` | 尝试抓取前方对象。 | 官方 |
| `Actor:WhitList_StopSkill` | `objid:number, skillid:number\|string, stop:boolean` | `boolean` | 白名单内停止技能 | 推测 |

## World（86 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `World:AddGameTimes` | `times:number` | `boolean` | 增加游戏局数计数 | 推测 |
| `World:AddGravity` | `value:number` | `boolean` | 增加 gravity | 官方 |
| `World:CalcDirectionByAngle` | `yaw:number,pitch:number` | `table` | calc direction by angle | 官方 |
| `World:CalcDirectionByCoord` | `x:number,y:number,z:number` | `table` | calc direction by coord | 官方 |
| `World:CalcDirectionByPos2Pos` | `pos1:table,pos2:table` | `table` | calc direction by pos2 pos | 官方 |
| `World:CalcDirectionByYawAngle` | `objid:number,yaw:number,pitch:number` | `table` | calc direction by yaw angle | 官方 |
| `World:CalcDirectionByYawDirection` | `objid:number,vx:number,vy:number,vz:number` | `table` | calc direction by yaw direction | 官方 |
| `World:CalcDistance` | `posSrc:table,posDst:table` | `number` | calc distance | 官方 |
| `World:CanMobSpawnOnPosXZ` | `x:number,y:number,z:number,worldId:number` | `number` | 判定 mob spawn on pos x z | 官方 |
| `World:DespawnActor` | `objid:number` | `boolean` | despawn actor | 官方 |
| `World:EmitByPosition` | `x:number, y:number, z:number, ...` | `boolean` | 在坐标点发射（与 Actor:EmitByShooter 同族） | 推测 |
| `World:EmitByPositionTarget` | `x:number, y:number, z:number, targetid:number, ...` | `boolean` | 坐标点对目标发射 | 推测 |
| `World:EmitByPositionTargetPos` | `x:number, y:number, z:number, dstx:number, dsty:number, dstz:number, ...` | `boolean` | 坐标点对坐标发射 | 推测 |
| `World:FindCanSpawnMobPosList` | `centerX:number,centerY:number,centerZ:number,radius:number,includeCenterPos:boolean,worldId:number` | `table` | find can spawn mob pos list | 官方 |
| `World:FindEcosystem` | `x:number,y:number,z:number,biomeType:number,radius:number` | `table` | find ecosystem | 官方 |
| `World:FindNearActorListByObjType` | `x:number, y:number, z:number, objtype:number, range:number` | `table` | 按类型查找附近对象 | 推测 |
| `World:FindNearestPlayerByPos` | `posX:number,posY:number,posZ:number,worldId:number` | `number` | find nearest player by pos | 官方 |
| `World:GetAllPlayers` | `alive:number` | `table` | 读取 all players | 官方 |
| `World:GetBiomeGroup` | `posX:number,posZ:number,worldId:number` | `number` | 读取 biome group | 官方 |
| `World:GetBiomeType` | `posX:number,posZ:number,worldId:number` | `number` | 读取 biome type | 官方 |
| `World:GetCurMapId` | `（无）` | `number` | 当前地图 ID | 推测 |
| `World:GetDateFromTime` | `time:number,enum:number` | `number` | 读取 date from time | 官方 |
| `World:GetDateStringFromTime` | `time:number, fmt:string` | `string` | 时间戳转字符串 | 推测 |
| `World:GetDay` | `（无）` | `number` | 读取 day | 官方 |
| `World:GetDirRayDetection` | `posbegin:table,dir:table,maxlen:number,picktype:number,worldId:number,ignoreObjs:table` | `table` | 读取 dir ray detection | 官方 |
| `World:GetGameMode` | `（无）` | `number` | 读取 game mode | 官方 |
| `World:GetGravity` | `worldId:number` | `number` | 读取 gravity | 官方 |
| `World:GetGroupWeather` | `groupid:number` | `number` | 读取 group weather | 官方 |
| `World:GetHostWorldId` | `（无）` | `number` | 读取 host world id | 官方 |
| `World:GetHours` | `（无）` | `number` | 读取 hours | 官方 |
| `World:GetLightByPos` | `x:number,y:number,z:number,worldId:number` | `number` | 读取 light by pos | 官方 |
| `World:GetLocalDate` | `enum:number` | `number` | 读取 local date | 官方 |
| `World:GetLocalDateString` | `（无）` | `string` | 读取 local date string | 官方 |
| `World:GetPlayerTotal` | `alive:number` | `number` | 读取 player total | 官方 |
| `World:GetRayBlock` | `srcx:number,srcy:number,srcz:number,face:number,distance:number,worldId:number` | `number` | 读取 ray block | 官方 |
| `World:GetRayLength` | `srcx:number,srcy:number,srcz:number,dstx:number,dsty:number,dstz:number,distance:number,worldId:number` | `number` | 读取 ray length | 官方 |
| `World:GetServerDate` | `enum:number` | `number` | 读取 server date | 官方 |
| `World:GetServerDateString` | `（无）` | `string` | 服务器时间字符串；与 GetLocalDateString 同族 | 推测 |
| `World:GetSpawnPoint` | `（无）` | `table` | 读取 spawn point | 官方 |
| `World:GetTimeFromDateString` | `str:string` | `number` | 字符串转时间戳 | 推测 |
| `World:GetWorldCreateMobRule` | `worldId:number` | `table` | 读取生物生成规则；与 SetWorldCreateMobRule 成对 | 推测 |
| `World:IsChunkLoaded` | `x:number,z:number,worldId:number` | `boolean` | 判定 chunk loaded | 官方 |
| `World:IsDaytime` | `（无）` | `boolean` | 判定 daytime | 官方 |
| `World:PauseSoundEffectOnPos` | `pos:table,soundId:number,pause:boolean,worldId:number` | `boolean` | 播放/停止类：pause sound effect on pos | 官方 |
| `World:PixelMapAddMarker` | `uin:number,id:string,params:table` | `boolean` | pixel map add marker | 官方 |
| `World:PixelMapAddTexture` | `uin:number,id:string,params:table` | `boolean` | pixel map add texture | 官方 |
| `World:PixelMapDelMarker` | `uin:number,id:string` | `boolean` | pixel map del marker | 官方 |
| `World:PixelMapDelTexture` | `uin:number,id:string` | `boolean` | pixel map del texture | 官方 |
| `World:PixelMapRefreshMarker` | `uin:number,id:string,params:table` | `boolean` | pixel map refresh marker | 官方 |
| `World:PixelMapRefreshTexture` | `uin:number,id:string,params:table` | `boolean` | pixel map refresh texture | 官方 |
| `World:PlayParticle` | `pos:table,particleIdArg:number\|string\|table,ptimeArg:number,offset:table,rot:table,scale:table,worldId:number` | `boolean` | 播放/停止类：play particle | 官方 |
| `World:PlayParticleEffect` | `pos:table, particleId:number\|string, ptime:number` | `boolean` | 播放粒子特效（PlayParticle 的另一版） | 推测 |
| `World:PlaySoundEffectOnPos` | `pos:table,soundId:number,volume:number,pitch:number,isLoop:boolean,worldId:number` | `boolean` | 播放/停止类：play sound effect on pos | 官方 |
| `World:RandomParticleEffectID` | `（无）` | `number` | random particle effect i d | 官方 |
| `World:RandomSoundID` | `（无）` | `number` | random sound i d | 官方 |
| `World:RandomWeatherID` | `（无）` | `number` | random weather i d | 官方 |
| `World:SetChunkRectAlwaysLoaded` | `x1:number, z1:number, x2:number, z2:number, enable:boolean` | `boolean` | 设置区块常驻加载 | 推测 |
| `World:SetGravity` | `value:number` | `boolean` | 设置 gravity | 官方 |
| `World:SetGroupWeather` | `groupid:number,weatherid:number` | `boolean` | 设置 group weather | 官方 |
| `World:SetHours` | `time:number` | `boolean` | 设置 hours | 官方 |
| `World:SetInnerViewEnable` | `iview:number,bopen:boolean` | `boolean` | 设置 inner view enable | 官方 |
| `World:SetLightByPos` | `x:number,y:number,z:number,value:number,worldId:number` | `boolean` | 设置 light by pos | 官方 |
| `World:SetMidJoin` | `enable:boolean` | `boolean` | 设置 mid join | 官方 |
| `World:SetMobSpawnDensity` | `mobType:number,density:number` | `boolean` | 设置 mob spawn density | 官方 |
| `World:SetParticleEffectScale` | `particleId:number\|string, scale:table` | `boolean` | 设置粒子缩放 | 推测 |
| `World:SetParticleTransform` | `pos:table,particleIdArg:number\|string\|table,offset:table,rot:table,scale:table,worldId:number` | `boolean` | 设置 particle transform | 官方 |
| `World:SetPlantGrowRate` | `rate:number` | `boolean` | 设置 plant grow rate | 官方 |
| `World:SetSkyBoxAttr` | `time:number,itype:number,value:number` | `boolean` | 设置 sky box attr | 官方 |
| `World:SetSkyBoxAttrWithNoTime` | `itype:number,value:number` | `boolean` | 设置 sky box attr with no time | 官方 |
| `World:SetSkyBoxColor` | `time:number,itype:number,color:string` | `boolean` | 设置 sky box color | 官方 |
| `World:SetSkyBoxColorAnim` | `playerid:number,itype:number,color:string,animId:number,animTime:number` | `boolean` | 设置 sky box color anim | 官方 |
| `World:SetSkyBoxFilter` | `playerid:number,itype:number,value:number\|string` | `boolean` | 设置 sky box filter | 官方 |
| `World:SetSkyBoxFilterAnim` | `playerid:number,itype:number,value:number\|string,animId:number,animTime:number` | `boolean` | 设置 sky box filter anim | 官方 |
| `World:SetSkyBoxMaps` | `itype:number,url:string` | `boolean` | 设置 sky box maps | 官方 |
| `World:SetSkyBoxMapsAnim` | `playerid:number,itype:number,url:string,animId:number,animTime:number` | `boolean` | 设置 sky box maps anim | 官方 |
| `World:SetSkyBoxSwitch` | `time:number,itype:number,value:number` | `boolean` | 设置 sky box switch | 官方 |
| `World:SetSkyBoxTemplate` | `value:number\|string` | `boolean` | 设置 sky box template | 官方 |
| `World:SetSpawnPoint` | `x:number,y:number,z:number` | `boolean` | 设置 spawn point | 官方 |
| `World:SetTimeVanishingSpeed` | `speed:number` | `boolean` | 设置 time vanishing speed | 官方 |
| `World:SetWorldCreateMobRule` | `cfgs:table,worldId:number` | `boolean` | 设置 world create mob rule | 官方 |
| `World:SpawnCreature` | `x:number,y:number,z:number,mobid:number\|string,num:number,trigger:boolean,worldId:number` | `table` | 创建 creature | 官方 |
| `World:SpawnProjectile` | `objid:number,itemid:number\|string,x:number,y:number,z:number,dstx:number,dsty:number,dstz:number,speed:number,worldId:number` | `number` | 创建 projectile | 官方 |
| `World:SpawnProjectileByDir` | `objid:number,itemid:number\|string,x:number,y:number,z:number,dirx:number,diry:number,dirz:number,speed:number,worldId:number` | `number` | 创建 projectile by dir | 官方 |
| `World:StopParticleEffectOnPos` | `x:number, y:number, z:number, particleId:number\|string` | `boolean` | 停止坐标点粒子 | 推测 |
| `World:StopParticleOnPos` | `x:number,y:number,z:number,particleId:number\|string,worldId:number` | `boolean` | 播放/停止类：stop particle on pos | 官方 |
| `World:StopSoundEffectOnPos` | `pos:table,soundId:number,worldId:number` | `boolean` | 播放/停止类：stop sound effect on pos | 官方 |

## CustomUI（66 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `CustomUI:ChangeParent` | `...` | `官方文档未提供` | 改变父节点。 | 官方 |
| `CustomUI:CloneElement` | `...` | `官方文档未提供` | 克隆 UI 元件。 | 官方 |
| `CustomUI:CreateElement` | `...` | `官方文档未提供` | 创建 UI 元件。 | 官方 |
| `CustomUI:DeleteElement` | `...` | `官方文档未提供` | 1.50+；删除 UI 元件。 | 官方 |
| `CustomUI:GetBlockIcon` | `blockid: number` | `code: number, iconid: number` | 获取方块图标。 | 官方 |
| `CustomUI:GetElementAttrValue` | `playerid:number, uielement:number, attr:number` | `any` | 读界面元素属性值 | 推测 |
| `CustomUI:GetItemIcon` | `itemid: number` | `code: number, icon: string` | 获取道具图标。 | 官方 |
| `CustomUI:GetMonsterIcon` | `actorid: number` | `iconid: number` | 获取生物类型图标。 | 官方 |
| `CustomUI:GetMonsterObjIcon` | `actorid: number` | `iconid: number` | 获取生物图标。 | 官方 |
| `CustomUI:GetProgressBarValue` | `...` | `官方文档未提供` | 获取进度值。 | 官方 |
| `CustomUI:GetRoleHeadIcon` | `playerid: number` | `官方文档未提供` | 获取角色头像图标。 | 官方 |
| `CustomUI:GetRoleIcon` | `playerid: number` | `iconid: number` | 获取角色图标。 | 官方 |
| `CustomUI:GetScreenSize` | `playerid: number` | `Width: number, Height: number` | 获取屏幕分辨率。 | 官方 |
| `CustomUI:GetShortcutIcon` | `...` | `官方文档未提供` | 官方序号第 20 项。 | 官方 |
| `CustomUI:GetStatusIcon` | `buffid: number` | `code: number, iconid: number` | 获取状态图标。 | 官方 |
| `CustomUI:GetUIViewAttrValue` | `playerid:number, uiview:number, attr:number` | `any` | 读界面视图属性值 | 推测 |
| `CustomUI:HideElement` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 隐藏元件。 | 官方 |
| `CustomUI:PlayElementAnim` | `...` | `官方文档未提供` | 播放元件动画。 | 官方 |
| `CustomUI:RemovePositionBandBlock` | `playerid:number, uielement:number` | `boolean` | 解绑方块位置 | 推测 |
| `CustomUI:RemovePositionBindActor` | `playerid:number, uielement:number` | `boolean` | 解绑对象位置 | 推测 |
| `CustomUI:RotateElement` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 旋转元件。 | 官方 |
| `CustomUI:SetAlpha` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 设置透明度。 | 官方 |
| `CustomUI:SetBeaconBandPos` | `...` | `官方文档未提供` | 设置信标绑定位置。 | 官方 |
| `CustomUI:SetBeaconClampType` | `...` | `官方文档未提供` | 设置信标裁切类型。 | 官方 |
| `CustomUI:SetBeaconMapType` | `playerid:number, beacontype:number` | `boolean` | 设置信标地图类型 | 推测 |
| `CustomUI:SetBeaconMargin` | `...` | `官方文档未提供` | 设置信标边距。 | 官方 |
| `CustomUI:SetBeaconObjId` | `...` | `官方文档未提供` | 设置信标绑定对象。 | 官方 |
| `CustomUI:SetBeaconOffset` | `...` | `官方文档未提供` | 设置信标偏移。 | 官方 |
| `CustomUI:SetBeaconRadius` | `...` | `官方文档未提供` | 设置信标半径。 | 官方 |
| `CustomUI:SetColor` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 官方序号第 5 项。 | 官方 |
| `CustomUI:SetFloatDamageTxt` | `...` | `官方文档未提供` | 设置飘字伤害文本。 | 官方 |
| `CustomUI:SetFontSize` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 官方序号第 4 项。 | 官方 |
| `CustomUI:SetLoaderModel` | `...` | `官方文档未提供` | 设置模型加载器模型。 | 官方 |
| `CustomUI:SetLoaderModelAct` | `...` | `官方文档未提供` | 设置模型加载器动作。 | 官方 |
| `CustomUI:SetLoaderModelDir` | `...` | `官方文档未提供` | 设置模型加载器朝向。 | 官方 |
| `CustomUI:SetLoaderModelPosition` | `...` | `官方文档未提供` | 设置模型加载器位置。 | 官方 |
| `CustomUI:SetLoaderModelScale` | `...` | `官方文档未提供` | 设置模型加载器缩放。 | 官方 |
| `CustomUI:SetPosition` | `objid: number, uiid: string, elementid: string, x: number, y: number` | `code: number` | 设置元件位置。 | 官方 |
| `CustomUI:SetPositionBandBlock` | `playerid:number, uielement:number, x:number, y:number, z:number` | `boolean` | 把界面元素绑定位置到方块 | 推测 |
| `CustomUI:SetPositionBindActor` | `playerid:number, uielement:number, objid:number` | `boolean` | 把界面元素绑定位置到对象 | 推测 |
| `CustomUI:SetProgressBarResId` | `...` | `官方文档未提供` | 设置进度条资源 ID。 | 官方 |
| `CustomUI:SetProgressBarValue` | `...` | `官方文档未提供` | 设置进度值。 | 官方 |
| `CustomUI:SetRelationPosition` | `...` | `官方文档未提供` | 设置相对位置。 | 官方 |
| `CustomUI:SetRelationSize` | `...` | `官方文档未提供` | 设置相对尺寸。 | 官方 |
| `CustomUI:SetScale` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 设置缩放。 | 官方 |
| `CustomUI:SetSize` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 官方序号第 3 项。 | 官方 |
| `CustomUI:SetSliderBarImg` | `...` | `官方文档未提供` | 设置滑动条背景。 | 官方 |
| `CustomUI:SetSliderDir` | `...` | `官方文档未提供` | 设置滑动条方向。 | 官方 |
| `CustomUI:SetSpineAnimID` | `...` | `官方文档未提供` | 设置 Spine 动画 ID。 | 官方 |
| `CustomUI:SetState` | `objid: number, uiid: string, elementid: string, pageIndex: string` | `code: number` | 设置元件状态。 | 官方 |
| `CustomUI:SetSysSettingBtnVisible` | `playerid:number, visible:boolean` | `boolean` | 系统设置按钮显隐 | 推测 |
| `CustomUI:SetText` | `objid: number, uiid: string, elementid: string, text: string, animid: number, time: number, mode: number` | `bool: boolean` | 设置文本元件内容；后三项官方文档标注为可选，但未给默认值。 | 官方 |
| `CustomUI:SetTexture` | `objid: number, uiid: string, elementid: string, url: string` | `bool: boolean` | 设置元件图案纹理。 | 官方 |
| `CustomUI:SetUrlIcon` | `playerid:number, uielement:number, url:string` | `boolean` | 用网络图片设置图标 | 推测 |
| `CustomUI:ShowElement` | `objid: number, uiid: string, elementid: string, ...` | `官方文档未提供` | 显示元件。 | 官方 |
| `CustomUI:SmoothChangeProgress` | `...` | `官方文档未提供` | 平滑改变进度。 | 官方 |
| `CustomUI:SmoothIncreaseProgress` | `...` | `官方文档未提供` | 平滑增加进度。 | 官方 |
| `CustomUI:SmoothMoveBy` | `...` | `官方文档未提供` | 平滑移动指定偏移。 | 官方 |
| `CustomUI:SmoothMoveTo` | `...` | `官方文档未提供` | 平滑动移动到目标位置。 | 官方 |
| `CustomUI:SmoothRotateBy` | `...` | `官方文档未提供` | 平滑旋转指定角度。 | 官方 |
| `CustomUI:SmoothRotateTo` | `...` | `官方文档未提供` | 平滑旋转至目标角度。 | 官方 |
| `CustomUI:SmoothScaleBy` | `...` | `官方文档未提供` | 平滑缩放指定倍数。 | 官方 |
| `CustomUI:SmoothScaleByEx` | `...` | `官方文档未提供` | 扩展版平滑缩放。 | 官方 |
| `CustomUI:SmoothScaleTo` | `...` | `官方文档未提供` | 平滑缩放至目标。 | 官方 |
| `CustomUI:StopAnim` | `...` | `官方文档未提供` | 停止元件动画。 | 官方 |
| `CustomUI:TurnSliderToPos` | `...` | `官方文档未提供` | 滑动条移动到位置。 | 官方 |

## Item（45 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Item:AddSubModelPart` | `instId:number,partName:string,boneName:string,modelStr:string,offset:table,rot:table,scale:table` | `string` | 增加 sub model part | 官方 |
| `Item:CreateBindItemInBackpack` | `playerid:number, itemid:number\|string, num:number` | `boolean` | 创建绑定道具到背包 | 推测 |
| `Item:CreateGunInWorld` | `itemid:number\|string,pos:table,worldId:number` | `number` | 创建 gun in world | 官方 |
| `Item:CreateItemInstInBackpack` | `playerid:number, itemid:number\|string, gridIndex:number` | `number` | 创建道具实例到背包格 | 推测 |
| `Item:CreateItemInstInWorld` | `itemid:number\|string,pos:table,worldId:number` | `number` | 创建 item inst in world | 官方 |
| `Item:DeleteSubModelPart` | `instId:number,partName:string` | `boolean` | 移除 sub model part | 官方 |
| `Item:EmpowerEquipOrGunForPlayer` | `playerid:number, instId:number, level:number` | `boolean` | 装备/枪械赋能 | 推测 |
| `Item:FreshPowerEquipOrGunForPlayer` | `playerid:number, instId:number` | `boolean` | 刷新装备/枪械战力 | 推测 |
| `Item:GetArrayCustomData` | `instId:number,key:string` | `table` | 读取 array custom data | 官方 |
| `Item:GetAttr` | `itemid:number\|string,attr:number` | `number` | 读取 attr | 官方 |
| `Item:GetBoolCustomData` | `instId:number,key:string` | `boolean` | 读取 bool custom data | 官方 |
| `Item:GetCraftIDNum` | `itemid:number\|string` | `number` | 读取 craft i d num | 官方 |
| `Item:GetCraftMaterialAndNum` | `itemid:number\|string,i:number` | `table` | 读取 craft material and num | 官方 |
| `Item:GetCustomGunAttr` | `itemid:number\|string,attrname:string` | `any` | 读取 custom gun attr | 官方 |
| `Item:GetEquipItemGridID` | `itemid:number\|string` | `number` | 读取 equip item grid i d | 官方 |
| `Item:GetFacade` | `itemid:number\|string` | `string` | 读取 facade | 官方 |
| `Item:GetGridAttr` | `objid:number,attr:number` | `number` | 读取 grid attr | 官方 |
| `Item:GetGunAttribute` | `instId:number,key:string` | `any` | 读取 gun attribute | 官方 |
| `Item:GetGunBaseDesc` | `itemid:number\|string` | `string` | 取枪械基础描述 | 推测 |
| `Item:GetGunPrefabAttribute` | `instId:number,key:string` | `any` | 读取 gun prefab attribute | 官方 |
| `Item:GetItemDesc` | `itemid:number\|string` | `string` | 读取 item desc | 官方 |
| `Item:GetItemIdByInstanceId` | `instId:number` | `number\|string` | 读取 item id by instance id | 官方 |
| `Item:GetItemInstFacade` | `instId:number` | `string` | 读取 item inst facade | 官方 |
| `Item:GetItemModelComp` | `instId:number, compname:string` | `table` | 取道具模型组件 | 推测 |
| `Item:GetItemName` | `itemid:number\|string` | `string` | 读取 item name | 官方 |
| `Item:GetNumberCustomData` | `instId:number,key:string` | `number` | 读取 number custom data | 官方 |
| `Item:GetObjCustomData` | `instId:number,key:string` | `table` | 读取 obj custom data | 官方 |
| `Item:GetObjData` | `instId:number, key:string` | `any` | 读道具实例自定义数据（与 SetObjData 成对） | 推测 |
| `Item:GetObjDataByGrid` | `playerid:number, gridid:number, key:string` | `any` | 按背包格读道具数据 | 推测 |
| `Item:GetResIdByInstanceId` | `instId:number` | `number\|string` | 由实例 ID 反查资源 ID | 推测 |
| `Item:GetStringCustomData` | `instId:number,key:string` | `string` | 读取 string custom data | 官方 |
| `Item:GetTags` | `itemid:number\|string` | `table` | 读取 tags | 官方 |
| `Item:IsBindItem` | `instId:number` | `boolean` | 道具是否绑定 | 推测 |
| `Item:LevelUpEquipOrGunForPlayer` | `playerid:number, instId:number` | `boolean` | 装备/枪械升级 | 推测 |
| `Item:ModifyGunAttribute` | `instId:number,key:string,value:any` | `boolean` | modify gun attribute | 官方 |
| `Item:RandomItemID` | `（无）` | `number` | random item i d | 官方 |
| `Item:RandomProjectileID` | `（无）` | `number` | random projectile i d | 官方 |
| `Item:ReplaceSubModelPart` | `instId:number,partName:string,boneName:string,modelStr:string,offset:table,rot:table,scale:table` | `boolean` | replace sub model part | 官方 |
| `Item:SetArrayCustomData` | `instId:number,key:string,value:table` | `boolean` | 设置 array custom data | 官方 |
| `Item:SetBoolCustomData` | `instId:number,key:string,value:boolean` | `boolean` | 设置 bool custom data | 官方 |
| `Item:SetNumberCustomData` | `instId:number,key:string,value:number` | `boolean` | 设置 number custom data | 官方 |
| `Item:SetObjCustomData` | `instId:number,key:string,value:table` | `boolean` | 设置 obj custom data | 官方 |
| `Item:SetObjData` | `instId:number, key:string, value:any` | `boolean` | 写道具实例自定义数据 | 推测 |
| `Item:SetObjDataByGrid` | `playerid:number, gridid:number, key:string, value:any` | `boolean` | 按背包格写道具数据 | 推测 |
| `Item:SetStringCustomData` | `instId:number,key:string,value:string` | `boolean` | 设置 string custom data | 官方 |

## Block（44 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Block:BluePrintSaveAsNewId` | `blueprintid:string, newid:string` | `boolean` | 蓝图另存为新 ID | 推测 |
| `Block:BluePrintSetUploadInteral` | `interval:number` | `boolean` | 设置蓝图上传间隔（官方拼写 Interal） | 推测 |
| `Block:CaptureAndUploadScreenshot` | `playerid:number` | `boolean` | 截图并上传 | 推测 |
| `Block:CreateObsBluePrint` | `x1:number, y1:number, z1:number, x2:number, y2:number, z2:number` | `string` | 创建观察蓝图并返回 id | 推测 |
| `Block:DeleteBluePrint` | `blueprintid:string` | `boolean` | 删除蓝图 | 推测 |
| `Block:DestroyBlock` | `x:number,y:number,z:number,dropitem:boolean,worldId:number,btrigger:boolean` | `boolean` | destroy block | 官方 |
| `Block:GetBlockData` | `x:number,y:number,z:number,worldId:number` | `number` | 读取 block data | 官方 |
| `Block:GetBlockDefDesc` | `blockid:number\|string` | `string` | 读取 block def desc | 官方 |
| `Block:GetBlockDefName` | `blockid:number\|string` | `string` | 读取 block def name | 官方 |
| `Block:GetBlockDir` | `x:number,y:number,z:number,worldId:number` | `number` | 读取 block dir | 官方 |
| `Block:GetBlockDropExp` | `blockid:number\|string` | `number` | 读取 block drop exp | 官方 |
| `Block:GetBlockDropItemType` | `blockid:number\|string,itype:number` | `table` | 读取 block drop item type | 官方 |
| `Block:GetBlockID` | `x:number,y:number,z:number,worldId:number` | `number` | 读取 block i d | 官方 |
| `Block:GetBlockPowerStatus` | `x:number,y:number,z:number,worldId:number` | `boolean` | 读取 block power status | 官方 |
| `Block:GetBlockSettingAttState` | `blockid:number\|string,atttype:number,worldId:number` | `boolean` | 读取 block setting att state | 官方 |
| `Block:GetBlockSwitchStatus` | `x:number,y:number,z:number,worldId:number` | `boolean` | 读取 block switch status | 官方 |
| `Block:GetBluePrintBlockInfo` | `blueprintid:string` | `table` | 取蓝图方块信息 | 推测 |
| `Block:GetFacade` | `blockid:number\|string` | `string` | 读取 facade | 官方 |
| `Block:GetObsBluePrintPos` | `blueprintid:string` | `table` | 取观察蓝图位置 | 推测 |
| `Block:GetObsBluePrintStatus` | `blueprintid:string` | `number` | 取观察蓝图状态 | 推测 |
| `Block:IsAirBlock` | `x:number,y:number,z:number,worldId:number` | `boolean` | 判定 air block | 官方 |
| `Block:IsLiquidBlock` | `x:number,y:number,z:number,worldId:number` | `boolean` | 判定 liquid block | 官方 |
| `Block:IsSolidBlock` | `x:number,y:number,z:number,worldId:number` | `boolean` | 判定 solid block | 官方 |
| `Block:LoadObsBluePrint` | `blueprintid:string` | `boolean` | 加载观察蓝图 | 推测 |
| `Block:PlaceBlock` | `blockid:number\|string,x:number,y:number,z:number,face:number,color:number,worldId:number,btrigger:boolean` | `boolean` | place block | 官方 |
| `Block:PlaceBluePrint` | `x:number, y:number, z:number, blueprintid:string, angle:number, mirror:number` | `boolean` | 放置蓝图 | 推测 |
| `Block:PlayAnim` | `pos:table,animid:number\|string,speed:number,loop:number,worldId:number` | `boolean` | 播放/停止类：play anim | 官方 |
| `Block:PlayCrackEffect` | `x:number,y:number,z:number,process:number,worldId:number` | `boolean` | 播放/停止类：play crack effect | 官方 |
| `Block:PlayDestroyEffect` | `x:number,y:number,z:number,worldId:number` | `boolean` | 播放/停止类：play destroy effect | 官方 |
| `Block:RandomBlockID` | `（无）` | `number` | random block i d | 官方 |
| `Block:ReplaceBlock` | `blockid:number\|string,x:number,y:number,z:number,face:number,color:number,worldId:number,btrigger:boolean` | `boolean` | replace block | 官方 |
| `Block:ReplaceBluePrint` | `x:number,y:number,z:number,blueprint:string,angle:number,mirror:number,placeMode:number` | `boolean` | replace blue print | 官方 |
| `Block:SaveBluePrintRegionData` | `blueprintid:string, data:table` | `boolean` | 保存蓝图区域数据 | 推测 |
| `Block:SetBlockAll` | `x:number, y:number, z:number, blockid:number\|string` | `boolean` | 整体设置方块（含附加数据） | 推测 |
| `Block:SetBlockColor` | `x:number,y:number,z:number,color:string,worldId:number` | `boolean` | 设置 block color | 官方 |
| `Block:SetBlockData` | `x:number,y:number,z:number,data:number,worldId:number` | `boolean` | 设置 block data | 官方 |
| `Block:SetBlockDir` | `x:number,y:number,z:number,dir:number,worldId:number` | `boolean` | 设置 block dir | 官方 |
| `Block:SetBlockSettingAttState` | `blockid:number\|string,atttype:number,switch:boolean,worldId:number` | `boolean` | 设置 block setting att state | 官方 |
| `Block:SetBlockSwichState` | `x:number, y:number, z:number, isactive:boolean` | `boolean` | 设置方块开关态（与 SetBlockSwitchStatus 同族，注意官方拼写 Swich） | 推测 |
| `Block:SetBlockSwitchStatus` | `x:number,y:number,z:number,isactive:boolean,worldId:number` | `boolean` | 设置 block switch status | 官方 |
| `Block:SetBlockTextureColor` | `blockid:number\|string,color:string,alpha:number,slotindex:number` | `boolean` | 设置 block texture color | 官方 |
| `Block:StopPlaceObsBluePrint` | `blueprintid:string` | `boolean` | 停止放置观察蓝图 | 推测 |
| `Block:UnbindBluePrintRegion` | `blueprintid:string` | `boolean` | 解绑蓝图区域 | 推测 |
| `Block:UnloadObsBluePrint` | `blueprintid:string` | `boolean` | 卸载观察蓝图 | 推测 |

## Backpack（43 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Backpack:ActDestructEquip` | `...` | `官方文档未提供` | 官方序号第 16 项。 | 官方 |
| `Backpack:ActEquipOffByEquipID` | `playerid: number, equipID: number` | `官方文档未提供` | 脱下装备。 | 官方 |
| `Backpack:ActEquipUpByResID` | `playerid: number, itemid: number\|string` | `玩家 ID；装备道具 ID` | 官方文档未提供 | 官方 |
| `Backpack:AddItem` | `playerid:number,itemid:number\|string,num:number,prioritytype:number` | `number` | 增加 item | 官方 |
| `Backpack:CalcSpaceNumForItem` | `playerid:number,itemid:number\|string` | `number` | calc space num for item | 官方 |
| `Backpack:ClearAllPack` | `playerid:number,bartype:number` | `boolean` | 移除 all pack | 官方 |
| `Backpack:ClearGrids` | `playerid:number,begingridId:number,endgridId:number` | `boolean` | 移除 grids | 官方 |
| `Backpack:ClearPack` | `playerid:number,bartype:number` | `boolean` | 移除 pack | 官方 |
| `Backpack:CreateGunInBackpack` | `playerid:number,itemid:number\|string,gridIndex:number` | `number` | 创建 gun in backpack | 官方 |
| `Backpack:CreateItem` | `objid:number,itemid:number\|string,itemnum:number,ipos:number` | `boolean` | 创建 item | 官方 |
| `Backpack:CreateItemInstInBackpack` | `playerid:number,itemid:number\|string,gridIndex:number` | `number` | 创建 item inst in backpack | 官方 |
| `Backpack:DecodeGridInfo` | `str:string` | `table` | decode grid info | 官方 |
| `Backpack:DiscardItem` | `playerid:number,gridid:number,num:number,ablePick:boolean` | `boolean` | discard item | 官方 |
| `Backpack:DiscardItemByID` | `playerid:number,itemid:number\|string,itemnum:number` | `boolean` | discard item by i d | 官方 |
| `Backpack:EncodeTableGridInfo` | `infos:table` | `string` | encode table grid info | 官方 |
| `Backpack:EnoughSpaceForItem` | `playerid:number,itemid:number\|string,num:number` | `boolean` | enough space for item | 官方 |
| `Backpack:GetAllBackPackInstanceIds` | `playerid:number,bartype:number` | `table` | 读取 all back pack instance ids | 官方 |
| `Backpack:GetGridAttr` | `playerid:number,gridid:number,attr:number` | `number` | 读取 grid attr | 官方 |
| `Backpack:GetGridGunInfo` | `playerid:number, gridid:number` | `table` | 取格子内枪械信息 | 推测 |
| `Backpack:GetGridInfos` | `playerid:number,begingridId:number,endgridId:number` | `string` | 读取 grid infos | 官方 |
| `Backpack:GetGridItemID` | `playerid:number,gridid:number` | `table` | 读取 grid item i d | 官方 |
| `Backpack:GetGridItemName` | `playerid:number,gridid:number` | `string` | 读取 grid item name | 官方 |
| `Backpack:GetGunInstIdInBackpack` | `playerid: number` | `ids: table` | 获取背包中所有枪械实例 ID。 | 官方 |
| `Backpack:GetInstIdByGridIndex` | `playerid:number,gridIndex:number` | `number` | 读取 inst id by grid index | 官方 |
| `Backpack:GetItemNum` | `playerid:number,itemid:number\|string,isAddEquip:boolean` | `table` | 读取 item num | 官方 |
| `Backpack:GetItemNumByBackpackBar` | `playerid:number,bartype:number,itemid:number\|string` | `table` | 读取 item num by backpack bar | 官方 |
| `Backpack:HasItemByBackpackBar` | `playerid: number, bartype: number, itemid: number\|string` | `玩家 ID；背包栏；道具 ID` | `bool: boolean, id: number` | 官方 |
| `Backpack:IsLock` | `playerid:number,gridIndex:number` | `boolean` | 判定 lock | 官方 |
| `Backpack:LoadGridInfos` | `playerid:number,gridinfo:string` | `boolean` | load grid infos | 官方 |
| `Backpack:MoveGridItem` | `playerid:number,gridsrc:number,griddst:number,num:number` | `boolean` | move grid item | 官方 |
| `Backpack:PlayShortCutItemEffect` | `playerid:number, itemid:number\|string, effectids:table` | `boolean` | 播放快捷栏道具特效 | 推测 |
| `Backpack:PlayShortCutItemParticle` | `playerid:number,itemid:number\|string,effectids:table,offset:table,rot:table,scale:table` | `boolean` | 播放/停止类：play short cut item particle | 官方 |
| `Backpack:PlayShortCutIxEffect` | `playerid:number, effectids:table` | `boolean` | 播放快捷栏槽位特效 | 推测 |
| `Backpack:PlayShortCutIxParticle` | `playerid:number,effectids:table,offset:table,rot:table,scale:table` | `boolean` | 播放/停止类：play short cut ix particle | 官方 |
| `Backpack:RemoveGridItem` | `playerid:number,gridid:number,num:number` | `boolean` | 移除 grid item | 官方 |
| `Backpack:RemoveGridItemByItemID` | `playerid: number, itemid: number\|string, num: number` | `玩家 ID；道具 ID；数量` | `num: number` | 官方 |
| `Backpack:SetBackPackNum` | `playerid:number,num:number` | `boolean` | 设置 back pack num | 官方 |
| `Backpack:SetGridAttr` | `playerid:number,gridid:number,attr:number,value:number` | `boolean` | 设置 grid attr | 官方 |
| `Backpack:SetGridItem` | `playerid:number,gridid:number,itemid:number\|string,num:number,durability:number` | `boolean` | 设置 grid item | 官方 |
| `Backpack:SetGridsLock` | `playerid:number,begingridId:number,endgridId:number,lock:boolean` | `boolean` | 设置 grids lock | 官方 |
| `Backpack:StopShortCutItemEffect` | `playerid:number,itemid:number\|string,effectids:table` | `boolean` | 播放/停止类：stop short cut item effect | 官方 |
| `Backpack:StopShortCutIxEffect` | `playerid:number,effectids:table` | `boolean` | 播放/停止类：stop short cut ix effect | 官方 |
| `Backpack:SwapGridItem` | `playerid:number,gridsrc:number,griddst:number` | `boolean` | swap grid item | 官方 |

## Graphics（40 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Graphics:CreateBrushByPos` | `pos: table, dim: table, color: number\|string, showuin: number, itype: number, worldId: number` | `位置；尺寸；颜色；显示对象；类型；世界 ID` | `id: number` | 官方 |
| `Graphics:CreateGraphicsArrowByActorToActor` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到对象创建箭头。 | 官方 |
| `Graphics:CreateGraphicsArrowByActorToPos` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到位置创建箭头。 | 官方 |
| `Graphics:CreateGraphicsArrowByPosToActor` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到对象创建箭头。 | 官方 |
| `Graphics:CreateGraphicsArrowByPosToPos` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到位置创建箭头。 | 官方 |
| `Graphics:CreateGraphicsImageByActor` | `objid: number, info: table, dir: table, offest: number, x2: number, y2: number` | `bool: boolean` | 在对象上创建图片。 | 官方 |
| `Graphics:CreateGraphicsImageByPos` | `x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number` | `bool: boolean` | 在位置创建图片。 | 官方 |
| `Graphics:CreateGraphicsLineByActorToActor` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到对象创建线。 | 官方 |
| `Graphics:CreateGraphicsLineByActorToPos` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到位置创建线。 | 官方 |
| `Graphics:CreateGraphicsLineByPosToActor` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到对象创建线。 | 官方 |
| `Graphics:CreateGraphicsLineByPosToPos` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到位置创建线。 | 官方 |
| `Graphics:CreateGraphicsNavPathByActorToPos` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到位置创建寻路线。 | 官方 |
| `Graphics:CreateGraphicsProgressByActor` | `objid: number, info: table, dir: table, offest: number, x2: number, y2: number` | `id: number` | 在对象上创建进度条实例。 | 官方 |
| `Graphics:CreateGraphicsProgressByPos` | `x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number` | `id: number` | 在位置创建进度条实例。 | 官方 |
| `Graphics:CreateGraphicsSurfaceByActorToActor` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到对象创建面。 | 官方 |
| `Graphics:CreateGraphicsSurfaceByActorToPos` | `objid: number, info: table, dir: table, offset: number` | `bool: boolean` | 从对象到位置创建面。 | 官方 |
| `Graphics:CreateGraphicsSurfaceByPosToActor` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到对象创建面。 | 官方 |
| `Graphics:CreateGraphicsSurfaceByPosToPos` | `pos: table, info: table, worldId: number` | `bool: boolean` | 从位置到位置创建面。 | 官方 |
| `Graphics:CreateGraphicsTxtByActor` | `objid: number, info: table, dir: table, offest: number, x2: number, y2: number` | `id: number` | 在对象上创建文字板实例。 | 官方 |
| `Graphics:CreateGraphicsTxtByPos` | `x: number, y: number, z: number, graphicInfo: table, x2: number, y2: number, worldId: number` | `id: number` | 在位置创建文字板实例。 | 官方 |
| `Graphics:CreateflotageTextByActor` | `objid: number, info: table, dir: table, offest: number, x2: number, y2: number` | `id: number` | 在对象上创建漂浮文字实例。 | 官方 |
| `Graphics:CreateflotageTextByPos` | `x: number, y: number, z: number, info: table, x2: number, y2: number, worldId: number` | `id: number` | 在位置创建漂浮文字实例。 | 官方 |
| `Graphics:GetInnerGraphicsOffset` | `tuin: number, itype: number, callback: function` | `官方文档未提供` | 通过回调返回内嵌图文偏移。 | 官方 |
| `Graphics:MakeGraphicsArrowToActor` | `objid: number, size: number, color: number\|string, itype: number` | `目标对象 ID；缩放；颜色；类型` | `obj: table` | 官方 |
| `Graphics:MakeGraphicsArrowToPos` | `x: number, y: number, z: number, size: number, color: number\|string, itype: number` | `目标坐标；缩放；颜色；类型` | `obj: table` | 官方 |
| `Graphics:MakeGraphicsImage` | `imgid: string, scale: number, apha: number, itype: number` | `obj: table` | 创建图片数据。 | 官方 |
| `Graphics:MakeGraphicsLineToActor` | `objid: number, size: number, color: number\|string, itype: number` | `目标对象 ID；缩放；颜色；类型` | `info: table` | 官方 |
| `Graphics:MakeGraphicsLineToPos` | `x: number, y: number, z: number, size: number, color: number\|string, itype: number` | `目标坐标；缩放；颜色；类型` | `obj: table` | 官方 |
| `Graphics:MakeGraphicsNavPathToPos` | `x: number, y: number, z: number, itype: number` | `obj: table` | 创建寻路路径数据。 | 官方 |
| `Graphics:MakeGraphicsProgress` | `v1: number, v2: number, color: number\|string, itype: number` | `当前值；最大值；颜色；类型` | `obj: table` | 官方 |
| `Graphics:MakeGraphicsSurfaceToActor` | `objid: number, size: number, color: number\|string, itype: number` | `目标对象 ID；缩放；颜色；类型` | `info: table` | 官方 |
| `Graphics:MakeGraphicsSurfaceToPos` | `x: number, y: number, z: number, size: number, color: number\|string, itype: number` | `目标坐标；缩放；颜色；类型` | `obj: table` | 官方 |
| `Graphics:MakeGraphicsText` | `title: string, font: number, apha: number, itype: number, autoWrap: number` | `obj: table` | 创建文字板数据。 | 官方 |
| `Graphics:MakeflotageText` | `title: string, font: number, itype: number` | `obj: table` | 创建漂浮文字数据。 | 官方 |
| `Graphics:RemoveGraphicsByGraphicsID` | `objid: number` | `bool: boolean` | 1.54+；按 ID 删除图文。 | 官方 |
| `Graphics:RemoveGraphicsByObjID` | `objid: number, itype: number, graphType: number` | `bool: boolean` | 按对象删除图文。 | 官方 |
| `Graphics:RemoveGraphicsByPos` | `x: number, y: number, z: number, itype: number, graphType: number, worldId: number` | `bool: boolean` | 按位置删除图文。 | 官方 |
| `Graphics:ReplaceAllGraphics` | `srcObjid: number, desObjid: number` | `bool: boolean` | 迁移对象上的图文。 | 官方 |
| `Graphics:UpdateGraphicsProgressById` | `graphid: number, val1: number, val2: number, isync: boolean` | `bool: boolean` | 更新进度条。 | 官方 |
| `Graphics:UpdateGraphicsTextById` | `graphid: number, title: string, fontsize: number, apha: number, isync: boolean` | `bool: boolean` | 1.50+；更新文字板。 | 官方 |

## Trigger（34 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Trigger:AllAttackType` | `（无）` | `table` | 全部攻击类型枚举表 | 推测 |
| `Trigger:AllSound` | `（无）` | `table` | 全部音效枚举表 | 推测 |
| `Trigger:AllStatus` | `（无）` | `table` | 全部状态枚举表 | 推测 |
| `Trigger:AnyValue2Str` | `v:any` | `string` | 任意值转字符串 | 推测 |
| `Trigger:DoObjOrArrayAction` | `obj:table\|any, action:string` | `boolean` | 对单个或数组执行动作 | 推测 |
| `Trigger:GetAttrVal` | `objid:number, attr:number` | `number` | 读属性值 | 推测 |
| `Trigger:GetEffectParams` | `eventobjid:number` | `table` | 取特效参数 | 推测 |
| `Trigger:GetElementID` | `uielement:number` | `number` | 取界面元素 ID | 推测 |
| `Trigger:GetLastCreateBlockId` | `（无）` | `number` | 取最近创建的方块 ID | 推测 |
| `Trigger:GetLastCreateCreatureId` | `（无）` | `number` | 取最近创建的生物 ID | 推测 |
| `Trigger:GetLastCreateCreatureObjId` | `（无）` | `number` | 取最近创建生物的对象 ID | 推测 |
| `Trigger:GetLastCreateEffectId` | `（无）` | `number` | 取最近创建的特效 ID | 推测 |
| `Trigger:GetLastCreateItemId` | `（无）` | `number` | 取最近创建的道具 ID | 推测 |
| `Trigger:GetMobId` | `eventobjid:number` | `number` | 事件参数取生物 ID | 推测 |
| `Trigger:GetPlayerId` | `eventobjid:number` | `number` | 事件参数取玩家 Uin | 推测 |
| `Trigger:GetPrefabIdStr` | `objid:number` | `string` | 取预制体 ID 字符串 | 推测 |
| `Trigger:GetPrefabInfo` | `objid:number` | `table` | 取预制体信息 | 推测 |
| `Trigger:GetRandomColor` | `（无）` | `string` | 随机颜色串 | 推测 |
| `Trigger:GetStringLength` | `str:string` | `number` | 字符串长度 | 推测 |
| `Trigger:GetUIObject` | `playerid:number, uielement:number` | `table` | 取界面对象 | 推测 |
| `Trigger:GetWorld` | `（无）` | `table` | 取世界对象 | 推测 |
| `Trigger:PrintTag` | `tag:string` | `nil` | 打印标签（调试用） | 推测 |
| `Trigger:SetLastCreateBlockId` | `blockid:number` | `boolean` | 设置最近创建的方块 ID | 推测 |
| `Trigger:SetLastCreateCreatureId` | `mobid:number` | `boolean` | 设置最近创建的生物 ID | 推测 |
| `Trigger:SetLastCreateEffectId` | `effectid:number` | `boolean` | 设置最近创建的特效 ID | 推测 |
| `Trigger:SetLastCreateItemId` | `itemid:number` | `boolean` | 设置最近创建的道具 ID | 推测 |
| `Trigger:SplitStr` | `str:string, sep:string` | `table` | 按分隔符切分 | 推测 |
| `Trigger:Str2Obj` | `str:string` | `table` | 字符串转对象 | 推测 |
| `Trigger:String2Playerid` | `str:string` | `number` | 字符串转玩家 Uin | 推测 |
| `Trigger:Substring` | `str:string, begin:number, end:number` | `string` | 截取子串 | 推测 |
| `Trigger:ToMobId` | `objid:number` | `number` | 对象 ID 转生物 ID | 推测 |
| `Trigger:ToPlayerId` | `objid:number` | `number` | 对象 ID 转玩家 Uin | 推测 |
| `Trigger:TransmitToCategoryRoom` | `uin:number, category:number\|string` | `boolean` | 传送到分类房间 | 推测 |
| `Trigger:Wait` | `time:number` | `boolean` | 等待若干时间 | 推测 |

## math（32 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `math:abs` | `x:number` | `number` | 绝对值 | 标准/真机 |
| `math:acos` | `x:number` | `number` | 反余弦 | 标准/真机 |
| `math:approximately` | `a:number, b:number` | `boolean` | 判断两个浮点数是否足够接近（引擎扩展） | 标准/真机 |
| `math:asin` | `x:number` | `number` | 反正弦 | 标准/真机 |
| `math:atan` | `x:number` | `number` | 反正切 | 标准/真机 |
| `math:atan2` | `y:number, x:number` | `number` | 带象限的反正切 | 标准/真机 |
| `math:ceil` | `x:number` | `number` | 向上取整 | 标准/真机 |
| `math:clamp` | `v:number, min:number, max:number` | `number` | 把 v 限制在 [min,max] 内（引擎扩展） | 标准/真机 |
| `math:cos` | `x:number` | `number` | 余弦 | 标准/真机 |
| `math:cosh` | `x:number` | `number` | 双曲余弦 | 标准/真机 |
| `math:deg` | `x:number` | `number` | 弧度转角度 | 标准/真机 |
| `math:exp` | `x:number` | `number` | e^x | 标准/真机 |
| `math:floor` | `x:number` | `number` | 向下取整 | 标准/真机 |
| `math:fmod` | `a:number, b:number` | `number` | 浮点取余（符号同 a） | 标准/真机 |
| `math:frexp` | `x:number` | `number, number` | 返回 m(0.5~1) 与指数 e，使 x=m*2^e | 标准/真机 |
| `math:ldexp` | `m:number, e:number` | `number` | m * 2^e | 标准/真机 |
| `math:lerp` | `a:number, b:number, t:number` | `number` | 线性插值 a+(b-a)*t（引擎扩展） | 标准/真机 |
| `math:log` | `x:number, base:number\|nil` | `number` | 对数 | 标准/真机 |
| `math:log10` | `x:number` | `number` | 常用对数 | 标准/真机 |
| `math:max` | `...` | `number` | 最大值 | 标准/真机 |
| `math:min` | `...` | `number` | 最小值 | 标准/真机 |
| `math:mod` | `a:number, b:number` | `number` | 取模（引擎扩展，标准5.1无） | 标准/真机 |
| `math:modf` | `x:number` | `number, number` | 返回整数部分与小数部分 | 标准/真机 |
| `math:pow` | `a:number, b:number` | `number` | a 的 b 次方；等价于 a^b | 标准/真机 |
| `math:rad` | `x:number` | `number` | 角度转弧度 | 标准/真机 |
| `math:random` | `m:number\|nil, n:number\|nil` | `number` | 无参=0~1；一参=1~m；两参=m~n | 标准/真机 |
| `math:randomseed` | `seed:number` | `nil` | 设置随机种子（非密码学安全） | 标准/真机 |
| `math:sin` | `x:number` | `number` | 正弦 | 标准/真机 |
| `math:sinh` | `x:number` | `number` | 双曲正弦 | 标准/真机 |
| `math:sqrt` | `x:number` | `number` | 平方根 | 标准/真机 |
| `math:tan` | `x:number` | `number` | 正切 | 标准/真机 |
| `math:tanh` | `x:number` | `number` | 双曲正切；引擎自带，无需自行实现 | 标准/真机 |

## Area（30 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Area:BlockInArea` | `areaid: number, blockid: number\|string` | `区域 ID；方块 ID` | 官方文档未提供 | 官方 |
| `Area:CheckRangeCanPlace` | `posbeg: table, posend: table, uin: number, relativing: number, actortype: number, worldId: number` | `bool: boolean` | 检查范围内能否放置方块。 | 官方 |
| `Area:ClearAllBlock` | `areaid: number` | `官方文档未提供` | 清空区域方块。 | 官方 |
| `Area:ClearAllBlockAreaRange` | `...` | `官方文档未提供` | 清空范围内方块。 | 官方 |
| `Area:CloneAreaBlock` | `areaid: number, ...` | `官方文档未提供` | 复制区域方块。 | 官方 |
| `Area:CloneAreaRange` | `...` | `官方文档未提供` | 复制范围方块。 | 官方 |
| `Area:CreateAreaPrefab` | `pos: table, size: table, worldId: number` | `obj: object` | 创建区域预制对象。 | 官方 |
| `Area:CreateAreaRectByLen` | `areaid:number, x:number, y:number, z:number, len:number` | `boolean` | 按边长创建矩形区域 | 推测 |
| `Area:CreateAreaRectByRange` | `posBeg: table, posEnd: table, btmp: boolean, worldId: number` | `areaid: number` | 按范围创建矩形区域。 | 官方 |
| `Area:DestroyAllBlock` | `areaid: number` | `官方文档未提供` | 破坏区域内方块。 | 官方 |
| `Area:DestroyArea` | `areaid: number` | `bool: boolean` | 销毁区域。 | 官方 |
| `Area:FillBlockAreaRange` | `...` | `官方文档未提供` | 用方块填充区域。 | 官方 |
| `Area:GetAllCreaturesInAreaRange` | `...` | `官方文档未提供` | 获取范围内全部生物。 | 官方 |
| `Area:GetAllObjsInAreaRange` | `...` | `官方文档未提供` | 获取范围内全部对象。 | 官方 |
| `Area:GetAllPlayersInAreaRange` | `...` | `官方文档未提供` | 获取范围内全部玩家。 | 官方 |
| `Area:GetAreaBlockTypes` | `areaid: number` | `官方文档未提供` | 获取区域内方块类型。 | 官方 |
| `Area:GetAreaCenter` | `areaid: number` | `pos: table` | 获取区域中心。 | 官方 |
| `Area:GetAreaCreatures` | `areaid: number` | `官方文档未提供` | 获取区域内生物。 | 官方 |
| `Area:GetAreaPlayers` | `areaid: number` | `官方文档未提供` | 获取区域内玩家。 | 官方 |
| `Area:GetAreaRectLength` | `areaid: number` | `lenx: number, leny: number, lenz: number` | 获取三个轴向长度。 | 官方 |
| `Area:GetAreaRectRange` | `areaid: number` | `posBeg: table, posEnd: table, worldId: number` | 获取范围及所在星球 ID。 | 官方 |
| `Area:GetAreaUuidByObjId` | `objId: number` | `id: string / nil` | 获取区域 UUID。 | 官方 |
| `Area:GetBlockNum` | `areaid: number` | `官方文档未提供` | 获取区域内方块数量。 | 官方 |
| `Area:GetRandomAirPos` | `areaid: number` | `官方文档未提供` | 获取随机空气方块位置。 | 官方 |
| `Area:GetRandomPos` | `areaid: number` | `官方文档未提供` | 获取区域内随机位置。 | 官方 |
| `Area:GetRelativeActors` | `posbeg: table, posend: table, uin: number, relativing: number, actortype: number, worldId: number` | `num: number, ids: table` | 获取范围内具有指定关系的角色。 | 官方 |
| `Area:ObjInArea` | `areaid: number, objid: number` | `官方文档未提供` | 检测对象是否在区域中。 | 官方 |
| `Area:PosInArea` | `areaid: number, x: number, y: number, z: number` | `官方文档未提供` | 检测坐标是否在区域内。 | 官方 |
| `Area:ReplaceAreaBlock` | `areaid: number, ...` | `官方文档未提供` | 替换区域方块类型。 | 官方 |
| `Area:ReplaceAreaRangeBlock` | `...` | `官方文档未提供` | 替换范围内方块。 | 官方 |

## Monster（16 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Monster:CanSee` | `objid: number, targetObjid: number` | `官方文档未提供` | 检测生物是否能看见目标。 | 官方 |
| `Monster:ChangeAI` | `objid: number, treeid: number\|string` | `生物对象 ID；行为树 ID` | 官方文档未提供 | 官方 |
| `Monster:GetActorID` | `objid: number` | `actorid: number / nil` | 获取生物类型 ID。 | 官方 |
| `Monster:GetActorName` | `objid: number` | `name: string / nil` | 获取生物类型名称。 | 官方 |
| `Monster:GetDropItemInfo` | `actorid: number\|string` | `生物类型 ID 或预制 ID` | 官方文档未提供 | 官方 |
| `Monster:GetFacade` | `monsterid: number\|string` | `生物类型 ID 或预制 ID` | 官方文档未提供 | 官方 |
| `Monster:GetMonsterDefLevelExp` | `actorid: number\|string` | `生物类型 ID 或预制 ID` | `exp: number / nil` | 官方 |
| `Monster:GetMonsterDefName` | `actorid: number\|string` | `生物类型 ID 或预制 ID` | `name: string / nil` | 官方 |
| `Monster:GetTags` | `actorid: number\|string` | `生物类型 ID 或预制 ID` | 官方文档未提供 | 官方 |
| `Monster:GetTamedOwnerID` | `objid: number` | `官方文档未提供` | 获取驯养主 ID。 | 官方 |
| `Monster:RandomActorID` | `（无）` | `官方文档未提供` | 随机获取生物类型 ID。 | 官方 |
| `Monster:ReplaceActor` | `objidSrc: number, actorid: number\|string, replacehp: boolean` | `源对象 ID；目标类型 ID；是否同步血量` | `ret: number / nil` | 官方 |
| `Monster:SetAIActive` | `objid:number, active:boolean` | `boolean` | 开关 AI | 推测 |
| `Monster:SetMonsterDefLevelExp` | `actorid: number\|string, levelExp: number` | `生物类型 ID 或预制 ID；经验` | `ret: boolean` | 官方 |
| `Monster:SetPersistance` | `objid:number, persistance:boolean` | `boolean` | 设置是否持久化 | 推测 |
| `Monster:SetTameTarget` | `objidA: number, objidB: number` | `官方文档未提供` | 使生物被目标驯服或设置驯服目标。 | 官方 |

## WorldContainer（16 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `WorldContainer:AddItemToContainer` | `x: number, y: number, z: number, itemid: number\|string, num: number, worldId: number\|nil` | `nil)` | 坐标；道具 ID；数量；星球 ID | 官方 |
| `WorldContainer:AddStorageItem` | `x: number, y: number, z: number, itemid: number\|string, num: number, worldId: number\|nil` | `nil)` | 坐标；道具 ID；数量；星球 ID | 官方 |
| `WorldContainer:AddWorldStorageItems` | `x: number, y: number, z: number, itemids: table, worldId: number\|nil` | `坐标；{{itemId, itemNum}}；星球 ID` | `ret: number` | 官方 |
| `WorldContainer:CheckStorage` | `x: number, y: number, z: number, worldId: number\|nil` | `坐标；星球 ID` | `ret: boolean, resIdOrBlockId: number | 官方 |
| `WorldContainer:CheckStorageEmptyGrid` | `x: number, y: number, z: number, itemid: number\|string, worldId: number\|nil` | `nil)` | 坐标；道具 ID；星球 ID | 官方 |
| `WorldContainer:ClearContainer` | `x: number, y: number, z: number, worldId: number\|nil` | `坐标；星球 ID` | `ret: boolean` | 官方 |
| `WorldContainer:ClearStorageBox` | `x: number, y: number, z: number, worldId: number\|nil` | `坐标；星球 ID` | `ret: boolean` | 官方 |
| `WorldContainer:GetAllStorageItemInstanceIds` | `x: number, y: number, z: number, worldId: number\|nil` | `坐标；星球 ID` | `ret: table | 官方 |
| `WorldContainer:GetGridAttr` | `x: number, y: number, z: number, gridid: number, attr: number, worldId: number` | `ret: number` | 获取容器格子属性。 | 官方 |
| `WorldContainer:GetStorageItem` | `x: number, y: number, z: number, offset: number, worldId: number\|nil` | `坐标；格子索引；星球 ID` | `itemid: number | 官方 |
| `WorldContainer:GetStorageItemInstanceId` | `x: number, y: number, z: number, offset: number, worldId: number\|nil` | `坐标；格子索引；星球 ID` | `ret: string | 官方 |
| `WorldContainer:RemoveContainerItemByID` | `x: number, y: number, z: number, itemid: number\|string, num: number, worldId: number\|nil` | `nil)` | 坐标；道具 ID；数量；星球 ID | 官方 |
| `WorldContainer:RemoveStorageItemByID` | `x: number, y: number, z: number, itemid: number\|string, num: number\|nil, worldId: number\|nil` | `nil, worldId: number` | nil)` | 官方 |
| `WorldContainer:RemoveStorageItemByIndex` | `x: number, y: number, z: number, offset: number, num: number\|nil, worldId: number\|nil` | `nil)` | 坐标；格子索引；数量；星球 ID | 官方 |
| `WorldContainer:SetStorageItem` | `x: number, y: number, z: number, offset: number, itemid: number\|string, num: number, worldId: number\|nil` | `nil)` | 坐标；格子索引；道具 ID；数量；星球 ID | 官方 |
| `WorldContainer:SwapContainerItem` | `x: number, y: number, z: number, grid: number, uin: number, grid2: number` | `ret: boolean` | nil` | 官方 |

## string（15 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `string:Trim` | `s:string` | `string` | 去除首尾空白（引擎扩展） | 标准/真机 |
| `string:byte` | `s:string, i:number\|nil, j:number\|nil` | `number...` | 取字符字节值 | 标准/真机 |
| `string:char` | `...` | `string` | 由字节值拼字符串 | 标准/真机 |
| `string:find` | `s:string, pattern:string, init:number\|nil, plain:boolean\|nil` | `number, number` | 查找，返回起止下标 | 标准/真机 |
| `string:format` | `fmt:string, ...` | `string` | 格式化输出 | 标准/真机 |
| `string:gmatch` | `s:string, pattern:string` | `function` | 返回迭代函数 | 标准/真机 |
| `string:gsub` | `s:string, pattern:string, repl:string\|table\|function, n:number\|nil` | `string, number` | 全局替换 | 标准/真机 |
| `string:len` | `s:string` | `number` | 字符串长度 | 标准/真机 |
| `string:lower` | `s:string` | `string` | 转小写 | 标准/真机 |
| `string:match` | `s:string, pattern:string, init:number\|nil` | `string\|nil` | 按模式捕获 | 标准/真机 |
| `string:rep` | `s:string, n:number` | `string` | 重复 n 次 | 标准/真机 |
| `string:reverse` | `s:string` | `string` | 反转 | 标准/真机 |
| `string:split` | `s:string, sep:string` | `table` | 按分隔符切分（引擎扩展） | 标准/真机 |
| `string:sub` | `s:string, i:number, j:number\|nil` | `string` | 截取子串（按字节，中文需按3字节切） | 标准/真机 |
| `string:upper` | `s:string` | `string` | 转大写 | 标准/真机 |

## Buff（12 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Buff:AddBuff` | `objid: number, buffid: number\|string, customticks: number` | `对象 ID；状态 ID；持续时间` | `bool: boolean` | 官方 |
| `Buff:ClearAllBadBuff` | `objid: number` | `bool: boolean` | 清除负面状态。 | 官方 |
| `Buff:ClearAllBuff` | `objid: number` | `bool: boolean` | 清除全部状态。 | 官方 |
| `Buff:ClearAllGoodBuff` | `objid: number` | `bool: boolean` | 清除有益状态。 | 官方 |
| `Buff:GetBuffDefDesc` | `buffid: number\|string` | `状态 ID` | `value: string` | 官方 |
| `Buff:GetBuffDefName` | `buffid: number\|string` | `状态 ID` | `name: string` | 官方 |
| `Buff:GetBuffLeftTime` | `objid: number, buffid: number\|string` | `对象 ID；状态 ID` | `num: number` | 官方 |
| `Buff:GetBuffList` | `objid: number` | `num: number, ids: table` | 获取状态数量和 ID 数组。 | 官方 |
| `Buff:GetBuffNumByBuffid` | `objid: number, buffid: number\|string` | `对象 ID；状态 ID` | `num: number` | 官方 |
| `Buff:HasBuff` | `objid: number, buffid: number\|string` | `对象 ID；状态 ID` | `bool: boolean` | 官方 |
| `Buff:RemoveBuff` | `objid: number, buffid: number\|string` | `对象 ID；状态 ID` | `bool: boolean` | 官方 |
| `Buff:ReplaceBuff` | `objid: number, buffsrc: number\|string, buffdst: number\|string, customticks: number` | `string, customticks: number)` | 对象 ID；源状态；目标状态；持续时间 | 官方 |

## Timer（12 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Timer:ChangeTimerTime` | `id:number,time:number` | `boolean` | change timer time | 官方 |
| `Timer:CreateTimer` | `name:string` | `number` | 创建 timer | 官方 |
| `Timer:DeleteTimer` | `id:number` | `boolean` | 移除 timer | 官方 |
| `Timer:GetTimerTime` | `id:number` | `number` | 读取 timer time | 官方 |
| `Timer:HideTimerWnd` | `id:number` | `boolean` | 界面显隐：hide timer wnd | 官方 |
| `Timer:IsExist` | `id:number` | `boolean` | 判定 exist | 官方 |
| `Timer:PauseTimer` | `id:number` | `boolean` | 播放/停止类：pause timer | 官方 |
| `Timer:ResumeTimer` | `id:number` | `boolean` | resume timer | 官方 |
| `Timer:ShowTimerWnd` | `id:number` | `boolean` | 界面显隐：show timer wnd | 官方 |
| `Timer:StartBackwardTimer` | `id:number,interval:number,repeated:boolean` | `boolean` | start backward timer | 官方 |
| `Timer:StartForwardTimer` | `id:number` | `boolean` | start forward timer | 官方 |
| `Timer:StopTimer` | `id:number` | `boolean` | 播放/停止类：stop timer | 官方 |

## bit（12 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `bit:arshift` | `a:number, n:number` | `number` | 算术右移 | 标准/真机 |
| `bit:band` | `a:number, ...` | `number` | 按位与（32位有符号） | 标准/真机 |
| `bit:bnot` | `a:number` | `number` | 按位取反 | 标准/真机 |
| `bit:bor` | `a:number, ...` | `number` | 按位或 | 标准/真机 |
| `bit:bswap` | `a:number` | `number` | 字节序交换 | 标准/真机 |
| `bit:bxor` | `a:number, ...` | `number` | 按位异或 | 标准/真机 |
| `bit:lshift` | `a:number, n:number` | `number` | 左移 | 标准/真机 |
| `bit:rol` | `a:number, n:number` | `number` | 循环左移 | 标准/真机 |
| `bit:ror` | `a:number, n:number` | `number` | 循环右移（引擎确实有） | 标准/真机 |
| `bit:rshift` | `a:number, n:number` | `number` | 逻辑右移 | 标准/真机 |
| `bit:tobit` | `a:number` | `number` | 截断为32位有符号整数 | 标准/真机 |
| `bit:tohex` | `a:number, n:number\|nil` | `string` | 转十六进制字符串 | 标准/真机 |

## GameObject（9 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `GameObject:CreatePrefab` | `objectType: number, prefabId: number\|string, x: number, y: number, z: number, num: number, trigger: boolean, worldId: number` | `对象类型 ObjType；预制 ID；坐标；数量；是否触发；星球 ID` | `objids: table / nil` | 官方 |
| `GameObject:CreatePrefabInst` | `prefabId: string, worldId: number, x: number, y: number, z: number, trigger: boolean` | `obj: object / nil` | 使用预制 ID 创建单个对象。 | 官方 |
| `GameObject:Destroy` | `objId: number\|string` | `对象 ID` | `bool: boolean` | 官方 |
| `GameObject:FindBlockObject` | `id: number\|string` | `方块类型 ID` | `obj: object / nil` | 官方 |
| `GameObject:FindObject` | `id: number\|string` | `游戏对象唯一标识` | `obj: object / nil` | 官方 |
| `GameObject:FindPlanet` | `planetid:number` | `table` | 查找星球对象 | 推测 |
| `GameObject:FindUIObject` | `id: number\|string` | `UI 对象唯一标识` | `obj: objectUI / nil` | 官方 |
| `GameObject:GetObjInstanceID` | `obj:table` | `number` | 取对象实例 ID | 推测 |
| `GameObject:GetObjectPrefab` | `objId: number` | `id: number` | string, num: number` | 官方 |

## CloudSever（8 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `CloudSever:GetDataListByKey` | `libvarid:string,key:string,callback:function` | `boolean` | 读取 data list by key | 官方 |
| `CloudSever:GetRoomCategory` | `（无）` | `number\|string` | 取房间分类 | 推测 |
| `CloudSever:GetRoomID` | `（无）` | `string` | 读取 room i d | 官方 |
| `CloudSever:SetDataListBykey` | `libvarid:string,key:string,value:any` | `boolean` | 设置 data list bykey | 官方 |
| `CloudSever:SetDataListValue` | `libvarid:string, key:string, value:any` | `boolean` | 设置 KV 值（与 SetDataListBykey 同族） | 推测 |
| `CloudSever:SetRoomCategory` | `category:number\|string` | `boolean` | 设置房间分类 | 推测 |
| `CloudSever:TransmitToCategoryRoom` | `uin:number, category:number\|string` | `boolean` | 传送到指定分类房间 | 推测 |
| `CloudSever:TransmitToCurMapCategoryRoom` | `uin:number` | `boolean` | 传送到当前地图同类房间 | 推测 |

## table（8 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `table:clone` | `t:table` | `table` | 深拷贝（引擎扩展） | 标准/真机 |
| `table:concat` | `t:table, sep:string\|nil, i:number\|nil, j:number\|nil` | `string` | 数组转字符串 | 标准/真机 |
| `table:equal` | `a:table, b:table` | `boolean` | 逐键逐值比较（引擎扩展） | 标准/真机 |
| `table:getn` | `t:table` | `number` | 数组长度（引擎恢复，等价 #） | 标准/真机 |
| `table:insert` | `t:table, pos:number\|nil, v:any` | `nil` | 插入元素 | 标准/真机 |
| `table:maxn` | `t:table` | `number` | 最大正数键 | 标准/真机 |
| `table:remove` | `t:table, pos:number\|nil` | `any` | 移除并返回元素 | 标准/真机 |
| `table:sort` | `t:table, comp:function\|nil` | `nil` | 排序 | 标准/真机 |

## coroutine（7 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `coroutine:create` | `f:function` | `thread` | 创建协程 | 标准/真机 |
| `coroutine:isyieldable` | `（无）` | `boolean` | 当前上下文能否 yield（引擎下放了 5.2 的函数） | 标准/真机 |
| `coroutine:resume` | `co:thread, ...` | `boolean, ...` | 恢复协程 | 标准/真机 |
| `coroutine:running` | `（无）` | `thread, boolean` | 当前协程 | 标准/真机 |
| `coroutine:status` | `co:thread` | `string` | 协程状态 | 标准/真机 |
| `coroutine:wrap` | `f:function` | `function` | 包装为函数形式 | 标准/真机 |
| `coroutine:yield` | `...` | `...` | 挂起协程 | 标准/真机 |

## OfficeUtils（6 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `OfficeUtils:GetActivateProgress` | `uin:number` | `table` | 取激活进度 | 推测 |
| `OfficeUtils:GetActivateReward` | `uin:number` | `table` | 取激活奖励 | 推测 |
| `OfficeUtils:GetShopItemInfo` | `itemid:string` | `table` | 取商店商品信息 | 推测 |
| `OfficeUtils:ReportActivateDataForUin` | `uin:number, data:table` | `boolean` | 上报指定玩家激活数据 | 推测 |
| `OfficeUtils:ReportOfficeActivateData` | `data:table` | `boolean` | 上报官方激活数据 | 推测 |
| `OfficeUtils:SendClientReportEvent` | `uin:number, eventstr:string, data:table` | `boolean` | 客户端埋点上报 | 推测 |

## Data（4 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Data:DoPackBluePrint` | `blueprintid:string` | `boolean` | 打包蓝图 | 推测 |
| `Data:GetValue` | `varId: string, playerId: number` | `value: any / nil` | 获取变量；失败或无值返回 `nil`。 | 官方 |
| `Data:IncreasesValue` | `varId: string, playerId: number, value: number` | `num: number / nil` | 数值变量增加指定量；参数错误返回 `nil`。 | 官方 |
| `Data:SetValue` | `varId: string, playerId: number, value: any` | `bool: boolean` | 设置变量；全局变量传 `nil`。 | 官方 |

## threadpool（4 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `threadpool:Wait` | `（无）` | `boolean` | 等待线程池任务完成 | 标准/真机 |
| `threadpool:Work` | `f:function, ...` | `boolean` | 提交任务到线程池 | 标准/真机 |
| `threadpool:wait` | `（无）` | `boolean` | 等待线程池任务完成 | 标准/真机 |
| `threadpool:work` | `f:function, ...` | `boolean` | 提交任务到线程池（小写版） | 标准/真机 |

## os（3 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `os:date` | `fmt:string\|nil, time:number\|nil` | `table\|string` | 格式化时间 | 标准/真机 |
| `os:time` | `t:table\|nil` | `number` | 当前时间戳（秒） | 标准/真机 |
| `os:timeMs` | `（无）` | `number` | 当前毫秒时间戳；调度一律用它，不要逐帧累加 | 标准/真机 |

## Chat（2 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Chat:SendChat` | `objid:number, content:string` | `boolean` | 发送聊天消息 | 推测 |
| `Chat:SendSystemMsg` | `content: string, playerID: number` | `ret: boolean` | 发送系统消息；`playerID` 为 `0` 时发送给所有玩家。 | 官方 |

## json（2 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `json:decode` | `s:string` | `table\|any` | JSON 字符串转表 | 标准/真机 |
| `json:encode` | `v:any` | `string` | 表/值转 JSON 字符串 | 标准/真机 |

## Listen（1 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Listen:AddGraphicsListenParam` | `graphid: number, funcs: table, param: table` | `ErrorCode.OK` | 监听图文刷新后的对象 ID、参数及回调。 | 官方 |

## LuaPanda（1 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `LuaPanda:BP` | `（无）` | `nil` | LuaPanda 调试断点入口 | 推测 |

## Mod（1 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `Mod:GetCfgIdByAssetId` | `assetId: string` | `cfgId: number` | 通过资源 ID 获取 defId。 | 官方 |

## debug（1 个函数）

| 函数 | 参数 | 返回值 | 说明 | 来源 |
|---|---|---|---|---|
| `debug:traceback` | `msg:string\|nil, level:number\|nil` | `string` | 调用栈回溯（引擎只留这一个） | 标准/真机 |

---

## 附录：一层纯枚举模块（无函数）

这些模块只提供常量，用 `模块.成员` 取值。

- **ABSOLUTECAMPTYPE**（13）：ANY、ENEMY、NOTEAM、PASSIVE、TEAM_1、TEAM_2、TEAM_3、TEAM_4、TEAM_5、TEAM_6、TEAM_NPC1、TEAM_NPC2、TEAM_NPC3
- **Ability**（24）：Attack、Break、CanBePickup、CanUseItemWhenBePickup、Cube、Drop、EnableBeattacked、EnableBekilled、EnableDeathdropitem、EnableInputRotate、EnableRotatingCamera、EnableSwitchShortcut、Flying、Interaction、Item、Jumping、Movement、Pick、Place、Sneaking、Sprinting、Swimming、Use、Walking
- **AbsoluteCampType**（12）：Enemy、Noteam、Passive、Team1、Team2、Team3、Team4、Team5、Team6、TeamNpc1、TeamNpc2、TeamNpc3
- **ActorBodyEffect**（40）：Accumfire、AiAngry、AiHungry、AiNeedreeds、AiSleep、BallCharge、BallShoot、Conceal、Dance、DeadProtect、Disappear、Dizzy、DragonDie0、DragonDie1、DragonDie2、Dragonfire、Dragonsummon、EnchFall、Fear、Fire、Forbidden、Headshot、HorseBenteng、HorseFly、Hurt、Interaction、Jetpack2、MakeTrouble、Milking、Normalshot、Portal、RoleCollect、RoleJump、TameFailed、TameFood、TameNofood、TameSucceed、TrainMove、Transport、WeaponFire
- **Aggro**（2）：CampRelation、SearchRangeType
- **AliveState**（3）：Alive、All、Dead
- **AnimMode**（4）：Default、Loop、Once、OnceStop
- **AreaCloneType**（4）：ExcludeAir、ExcludeAirAndMove、IncludeAir、IncludeAirAndMove
- **AreaFillType**（2）：Delete、Destroy
- **AreaSimilarity**（2）：Cmpblock、Ignblock
- **AutoSprinklerBlock**（1）：State
- **AvtPart**（30）：BackOrnament、BgEffect、Body、EquipBreast、EquipCustom1、EquipCustom2、EquipCustom3、EquipHead、EquipLegging、EquipPifeng、EquipShoe、EquipWeapon、Face、FaceEffect、FaceOrnament、Footprint、HandEffect、HandOrnament、Head、HeadEffect、Jacket、Max、RightHand、RightShoe、Shoe、Skin、TrailingEffect、Trousers、WholeBodyEffect、WingEffect
- **BACKPACK_TYPE**（4）：EQUIP、EXTEND、INVENTORY、SHORTCUT
- **BackpackBeginIndex**（4）：Equip、ExtBackpack、Inventory、Shortcut
- **BackpackComponent**（1）：InteractMode
- **BackpackType**（4）：Equip、Extend、Inventory、Shortcut
- **BeaconClampType**（3）：Circle、None、Rectangle
- **BeaconMapType**（2）：Object、Position
- **BiomeType**（106）：AirShipFleet、AirShipPlain、Airland、AirlandAir、AirlandGround、AirlandShine、Basin、BasinBamboo、BasinEdge、BasinLake、BasinPeach、BasinRice、Beach、Canyon、CanyonEage、CatDogVillage、City、Cliff、CliffEdge、CliffGinkgo、CliffMaple、CliffPlum、CloverStream、ConiferousForest、ConiferousForestHills、ConiferousForestLake、CorruptededRuins、CrystalIsland、DarkWoods、DeepSea、Desert、DesertHills、DesertLake、DesertOasis、DesertPopulusEuphratica、Earthcore、EyedStarAirlands、EyedStarAirlandsEdge、EyedStarAirlandsSub1、EyedStarAirlandsSub2…
- **BlockAttr**（11）：BepushedDropItem、BurningProbability、BurningSpeed、EnableBeoperated、EnableBepushed、EnableDestroyed、EnableDropItem、ExplodeResistance、Glissade、Hardness、Lightness
- **BlockEdit**（19）：BlockFlowType、BuiltInType、ColliderBoxType、ColliderModeSelect、ColliderShape、ColliderState、ColliderType、CoverNeighborType、DrawType、GravityEffectType、InteractSwitch、InteractType、LodType、MineToolType、MiniColorDisplayType、PhyCollideType、PlaceDirType、PushFlagType、ToolLevel
- **BlockId**（1）：Air
- **BlockLimits**（5）：BepushedDropItem、EnableBeoperated、EnableBepushed、EnableDestroyed、EnableDropItem
- **BlockStateEdit**（3）：CustomColliderState、SubMeshDataType、TextureVariantState
- **BlockStateType**（6）：CoreBlock、CustomCollider、Occupied、SecondaryDirection、Switch、TextureVariant
- **BlockStatus**（2）：Active、Inactive
- **BoxRefresh**（2）：RefreshNumType、RefreshType
- **BtreeRangeType**（3）：Around、Behind、Front
- **CREATUREATTR**（39）：ATK_MAGIC、ATK_MELEE、ATK_PHYSICAL、ATK_REMOTE、BODY_LERP_SPEED、CUR_GRAVITY、CUR_HP、CUR_HUNGER、CUR_OXYGEN、CUR_STRENGTH、DEF_CHAOS、DEF_MAGIC、DEF_MELEE、DEF_PHYSICAL、DEF_REMOTE、DIMENSION、DODGE、ENABLE_ATTACK、ENABLE_BEATTACKED、ENABLE_BEKILLED、ENABLE_DEATHDROPITEM、ENABLE_MOVE、ENABLE_PICKUP、EXTRA_HP、HP_RECOVER、JUMP_POWER、LEVEL、MAX_HP、MAX_HUNGER、MAX_OXYGEN、MAX_STRENGTH、PACK_SIZE、RECOVER_OXYGEN、RUN_SPEED、SWIN_SPEED、TOUGHNESS、VIEW_DISTANCE、WALK_SPEED、WEIGHT
- **CameraEditState**（3）：Edit、Null、Test
- **CameraModel**（5）：Autoindent、MoveFollow、RelativeRotate、RoleTranslucent、RotateFollow
- **CameraRotate**（4）：AllDir、NoTurn、OnlyPitch、OnlyYaw
- **Chest**（1）：MaxGridCountType
- **CmpProPermission**（3）：Private、Public、Read
- **CmpUIPermission**（3）：Hide、OfficialShow、Show
- **Collider**（3）：ColliderType、NoPhyscColliderShap、PhysicColliderShape
- **CommonBlockPlace**（1）：PlaceTypeGroup
- **ComponentUIPermissions**（3）：Hide、OfficialShow、Show
- **ComponentUIStyle**（84）：AIModelArray、AIModelItem、ActionArray、ActionButton、ActionItem、AnchorMeshGroup、AnchorMeshGroupItem、ArrayAI、ArrayBiomeMonster、ArrayBlockMaterial、ArrayBuff、ArrayBurstItem、ArrayCommonItem、ArrayDropItem、ArrayEmitterId、ArrayFeedItem、ArrayForItems、ArrayForItemsOffsetPos、ArrayForTags、ArrayImportAnimation、ArrayItem、ArrayMonsterItem、ArrayParticleBrusts、ArraySkill、ArrayStatus、ArrayStatusEffect、ArrayStatusEffectInst、AvatarPart、BlockModel、BlockTemp、BossGroupArray、BossGroupArrayItem、Bullet、ColorGradient、CommonItem、Curve、CustomCommonItem、CustomDropItem、CustomFeedItem、CustomItemAI…
- **CraftingEdit**（3）：RequirementToolsEnum、SubTypeEnum、TypeEnum
- **CreatureAttr**（40）：Atk、AtkMagic、AtkMelee、AtkPhysical、AtkRemote、AttackDis、BodyLerpSpeed、CurHp、CurHunger、CurOxygen、DefChaos、DefMagic、DefMelee、DefPhysical、DefRemote、Dimension、Dodge、EnableAttack、EnableBeattacked、EnableBekilled、EnableDeathdropitem、EnableMove、EnablePickup、ExtraHp、FlySpeed、HpRecover、JumpPower、Level、MaxHp、MaxHunger、MaxOxygen、PackSize、RecoverOxygen、RunSpeed、SwinSpeed、Toughness、ViewDis、ViewDistance、WalkSpeed、Weight
- **CreatureMotion**（11）：AtkMelee、AtkRemote、Beattracted、Copulation、Follow、Idle、RunAway、SelfBomb、Standby、Stroll、Swim
- **Cropblock**（5）：AbundantType、CropState、CropType、HarvestType、WetAffectType
- **CustomModType**（10）：Actor、Biome、Block、Furnace、Item、Monster、Recipe、Rule、Status、UI
- **Data**（3）：Array、Map、Table
- **DeviceType**（4）：Android、IOS、Other、PC
- **DoExplodeStatus**（3）：DestroyBlock、ExplodeRangeType、HarmType
- **DoHarmStatus**（3）：AttackType、HarmInherit、HarmType
- **Door**（1）：ControlModeType
- **DropMode**（6）：ChangePlayMode、DefeatMob、DestroyBlock、DestroyBox、DiscardItem、SpawnItem
- **Easing**（33）：BackIn、BackInOut、BackOut、BounceIn、BounceInOut、BounceOut、CircIn、CircInOut、CircOut、CubicIn、CubicInOut、CubicOut、Custom、ElasticIn、ElasticInOut、ElasticOut、ExpoIn、ExpoInOut、ExpoOut、Linear、None、QuadIn、QuadInOut、QuadOut、QuartIn、QuartInOut、QuartOut、QuintIn、QuintInOut、QuintOut、SineIn、SineInOut、SineOut
- **ElementAttr**（20）：Angle、Color、GlobalPos、GlobalPosX、GlobalPosY、Height、Id、Name、Position、PositionX、PositionY、ScrollPosition、ScrollX、ScrollY、Size、Text、Texture、Transparency、Visibility、Width
- **ElementType**（6）：Button、InputText、Loader3D、SlidingContainer、Text、Texture
- **EquipEdit**（3）：AnchorType、PartModelType、slotType
- **EquipSlotType**（10）：Breast、Custom1、Custom2、Custom3、Head、Legging、MaxSlots、Pifeng、Shoe、Weapon
- **ErrorCode**（8）：FAILED、KV_OP_CD_LMT、KV_OP_INVALID_VAL、KV_OP_NO_VAL、KV_OP_QPM_LMT、KV_UPDATE_GET、KV_UPDATE_SET、OK
- **EventDate**（8）：Day、Dayofweek、Hour、Minute、Month、Second、Timestamp、Year
- **ExplodeDmgType**（7）：Chaos、Electric、Fire、Ice、Physical、Poison、Void
- **FaceDir**（7）：NegX、NegY、NegZ、None、PosX、PosY、PosZ
- **FaceType**（2）：Pitch、Yaw
- **Feed**（3）：BubbleType、FeedReactType、RewardItemType
- **Fight**（5）：AnimationName、AttackMode、ColliderShape、NoPhyscColliderShap、Team
- **FoodEdit**（3）：BarbecueType、FoodTIngredientsType、Time
- **FurnaceEdit**（1）：FurnaceType
- **FurnaceType**（3）：Copper、Iron、Stone
- **GRAPHICS**（12）：GRAPHICS_ARROW_ACTOR、GRAPHICS_ARROW_POS、GRAPHICS_BUBBLE、GRAPHICS_HORNBOOK、GRAPHICS_IMAGE、GRAPHICS_LINE_ACTOR、GRAPHICS_LINE_POS、GRAPHICS_NAVPATH_POS、GRAPHICS_PROGRESS、GRAPHICS_SURFACE_ACTOR、GRAPHICS_SURFACE_POS、GRAPHICS_SUSPENDBOOK
- **GSoundType**（5）：Destroy、Dig、FallGround、Place、Walk
- **GameActorType**（72）：ACTORTYPE_AQUATICMONSTER、ACTORTYPE_ARROW、ACTORTYPE_BLOCK_AWAKEN、ACTORTYPE_BLOCK_LASER、ACTORTYPE_BOAT、ACTORTYPE_BOOKEDITORTABLE、ACTORTYPE_BOSS、ACTORTYPE_BUILDBLUEPRINT、ACTORTYPE_COBBLE、ACTORTYPE_COLLIDER、ACTORTYPE_CRAB、ACTORTYPE_CREATURE、ACTORTYPE_DESERTBUSINESSMAN、ACTORTYPE_DESERTBUSINESSMANGUARD、ACTORTYPE_DESERTVILLAGER、ACTORTYPE_DRAGON、ACTORTYPE_DROPITEM、ACTORTYPE_EFFECT、ACTORTYPE_EMITTER、ACTORTYPE_ENDEREYE、ACTORTYPE_FALLSAND、ACTORTYPE_FIREBALL、ACTORTYPE_FIREWORK、ACTORTYPE_FISHERMAN、ACTORTYPE_FISHINGVILLAGER、ACTORTYPE_FLYBLOCK、ACTORTYPE_FLYMONSTER、ACTORTYPE_FLYSNAKEGOD、ACTORTYPE_FUNNEL、ACTORTYPE_GAMEOBJECT、ACTORTYPE_GAMEOBJECT_AREA、ACTORTYPE_GIANT、ACTORTYPE_HIPPOCAMPUS、ACTORTYPE_HIPPOCAMPUS_HORSE、ACTORTYPE_HOOK、ACTORTYPE_HORSE、ACTORTYPE_INTERPRETERUNIT、ACTORTYPE_ITEMEXPO、ACTORTYPE_LASER、ACTORTYPE_MECHA_DRIVER…
- **GameSetting**（4）：AutoJump、CameraShake、FixedMap、ScopeMode
- **GamemakerRule**（46）：AllowMidwayJoin、AttackPlayer、Behurt、BgMusicMode、BlockDestroy、BlockPlace、BlockUse、Camera、Countdown、Curtime、DisplayName、DisplayScore、EndScore、EndTime、EndtimeWinlose、GpoisonSafed0、GpoisonSafet0、GpoisonSwitch、GravityFactor、HurtInterval、KillNotify、LifeNum、LifenumTeamShare、MaxPlayers、MiniMapTeams、MobGen、PlayerDieDrops、ResetScore、ReviveInvulnerable、ReviveMode、RoleShadow、SaveMode、ScoreCollectStar、ScoreColorChange、ScoreKillMob、ScoreKillPlayer、ScoreResetRound、SetViewMode、SetViewType、ShowSight…
- **GenerateBlock**（3）：GenerateNumType、RandomType、SpawnMode
- **GraphicsType**（13）：ArrowActor、ArrowPos、Brush、Bubble、Hornbook、Image、LineActor、LinePos、NavPathPos、Progress、SurfaceActor、SurfacePos、Suspendbook
- **GridAttr**（3）：Durable、ItemNum、Toughness
- **GroupWeatherType**（12）：Aurora、Bad、Blizzard、MeteorShower、Rain、Sandduststorm、Shine、ShineAndRain、Snow、Tempest、Thunder、VoidFog
- **Grow**（1）：BubbleType
- **GunAction**（11）：Aim、AimFire、AimLoad、Equip、Fire、Idle、Inspect、Load、Reload、ReloadEmpty、Run
- **GunActionBan**（10）：Aim、AimFire、AimLoad、Equip、Fire、Inspect、Load、Reload、ReloadEmpty、Run
- **GunAttr**（63）：AdsMoveSpeedBonus、AdsOffsetX、AdsOffsetY、AdsOffsetZ、AdsSpreadMax、AdsSpreadMin、AdsSpreadStep、AdsSpreadType、AdsSwitchTime、AdsSwitchTimeBonus、AdsXFunction、AdsXScale、BaseDamage、BaseDamageBonus、BodyDamage、BulletConsume、BulletId、BulletShrapnel、ControlValue、DamageType、DecayFinish、DecayLiquid、DecayMin、DecayStart、EquipTime、FireType、GunLevel、HeadDamage、HipAccValue、HipMoveSpeedBonus、HipSpreadMax、HipSpreadMin、HipSpreadStep、HipSpreadType、HittedCameraAngle、JumpSpreadBonus、MaxAmmo、MoveSpreadBonus、Penetration、Range…
- **GunDamageType**（4）：Fire、Ice、Physics、Poison
- **GunEdit**（14）：AutoFireType、DamageType、FireType、GunHandSlot、GunType、PointLooksType、ReloadType、SightLooksType、SightMode、SightType、SpreadSet、SpreadType、TrajectoryType、TweenFuncName
- **GunFireType**（3）：Auto、Manual、SemiAuto
- **GunSpreadType**（3）：Circle、NoRightDown、RightUp
- **GunState**（2）：Entry、Exit
- **HURTTYPE**（20）：ANTIINJURY、ANVIL、ASPHYXIA、BOMB、BURNING、CACTUS、DROWN、FALL、FIXED、FLASH、ICE、LASER、MAGIC、MELEE、PHYSICS、REMOTE、SUFFOCATE、SUN、TOXIN、WITHER
- **HorizontalOffset**（3）：Centered、Left、Right
- **HumanBodyAnchorId**（7）：Breast、FootDown、Head、LeftFoot、LeftHand、RightFoot、RightHand
- **HurtType**（21）：All、Antiinjury、Anvil、Asphyxia、Bomb、Burning、Cactus、Drown、Fall、Fixed、Flash、Ice、Laser、Magic、Melee、Physics、Remote、Suffocate、Sun、Toxin、Wither
- **ITEMATTR**（13）：ATTACK、DURATION、EXPLODEDEFENSE、FIREDEFENSE、FIREINTERVAL、ITEMTYPE、LONGDEFENSE、MAGAZINES、POISONDEFENSE、QUALITY、SHORTDEFENSE、STACKMAX、WITHERDEFENSE
- **InnerPopUpview**（18）：AdventureHandBook、AnimView、Atlas、BackPackEra、BackPackRole、BackPackTask、BuffStatus、CollectMaps、EvaluateMaps、FollowTheAuthor、InscriptionTable、InviteFriend、ItemProcessing、ItemTips、MiniMap、MiniShop、Specialty、StorageBox
- **ItemAbility**（2）：Drop、Throw
- **ItemAttr**（13）：Attack、Duration、ExplodeDefense、FireDefense、FireInterval、ItemType、LongDefense、Magazines、PoisonDefense、Quality、ShortDefense、Stackmax、WitherDefense
- **ItemEdit**（4）：DropItemEnum、ProductType、QualityLevel、UseType
- **ItemEffectType**（8）：After_Charge、Auto_Charge、Food、Inter_Charge、Max、No_Charge、Projectile、Use
- **KeyCode**（46）：A、Alt、B、C、Ctrl、D、Down、E、F、G、H、I、J、K、L、Left、LeftButton、M、N、Number0、Number1、Number2、Number3、Number4、Number5、Number6、Number7、Number8、Number9、O、P、Q、R、Right、RightButton、S、Shift、Space、T、U…
- **LaunchProjectileStatus**（3）：LaunchDir、LaunchDirType、LaunchType
- **LightingFurniture**（1）：ControlMode
- **LinearTransformation**（33）：BackIn、BackInOut、BackOut、BounceIn、BounceInOut、BounceOut、CircIn、CircInOut、CircOut、CubicIn、CubicInOut、CubicOut、Custom、ElasticIn、ElasticInOut、ElasticOut、ExpoIn、ExpoInOut、ExpoOut、Linear、None、QuadIn、QuadInOut、QuadOut、QuartIn、QuartInOut、QuartOut、QuintIn、QuintInOut、QuintOut、SineIn、SineInOut、SineOut
- **LogLevel**（3）：Error、Print、Warn
- **MODATTRIB_TYPE**（39）：MAX_MOB_MODATTR、MAX_MOD_ATTRIB、MAX_PLAYER_MODATTR、MOBATTR_ATTACK_GUN、MOBATTR_DAMAGED_ZOMBIE、MODATTR_ACTOR_SCALE、MODATTR_ARMOR_EXPLODE、MODATTR_ARMOR_PUNCH、MODATTR_ARMOR_RANGE、MODATTR_ATTACK_ANIMAL、MODATTR_ATTACK_EXPLODE、MODATTR_ATTACK_FIRE、MODATTR_ATTACK_ICE、MODATTR_ATTACK_PLAYER、MODATTR_ATTACK_POISON、MODATTR_ATTACK_PUNCH、MODATTR_ATTACK_RANGE、MODATTR_ATTACK_UNDEAD、MODATTR_ATTACK_WITHER、MODATTR_CRITICAL_HIT、MODATTR_DAMAGED_EXPLODE、MODATTR_DAMAGED_FALLING、MODATTR_DAMAGED_FIRE、MODATTR_DAMAGED_POISON、MODATTR_DAMAGED_PUNCH、MODATTR_DAMAGED_RANGE、MODATTR_DAMAGED_WITHER、MODATTR_DAMAGE_ABSORB、MODATTR_DIG_SPEED、MODATTR_JUMP_SPEED、MODATTR_KNOCK、MODATTR_KNOCK_RESIST、MODATTR_KNOCK_RESIST_PROB、MODATTR_LUCK_DIG、MODATTR_LUCK_KILLMOB、MODATTR_MOVE_SPEED、MODATTR_OXYGEN_SUPPLY、MODATTR_SWIM_SPEED、MODATTR_VIEW_BRIGHT
- **MapMarkType**（3）：Circle、Line、Rect
- **MapShopOrder**（2）：NpcShop、WorldBluePrint
- **MatchMode**（2）：All、Any
- **Mini**（51）：Action、Area、Array、BiomeType、Block、Blueprint、Bool、Buff、CheckList、Color、ColorGrandient、ComponentType、Creature、CreatureType、CustomData、CustomMsg、DropItem、Effect、Emitter、Entity、EntityType、Enum、GroupView、Item、LineAnimation、Material、Mob、MobType、Model、ModelAction、Number、Object、PathPoint、Picture、Player、PlayerType、Prefab、Role、Rotation、Scale…
- **MiniCurrency**（4）：MiniBean、MiniCoin、MiniPoint、Star
- **MiniMapMarkType**（2）：DevMark、Player
- **MiniShopData**（4）：AllMountLevel、Avt、Mount、Skin
- **MiniShopDetail**（20）：ActionAdvanced、ActionPersonal、Advert、AuxiliaryHorse、AuxiliaryMore、AuxiliarySpray、AuxiliaryWeapon、GiftCrystalSpirit、GiftDreamBox、GiftMiniBeanJourney、MarketCollection、MarketIntegral、Member、MiniBeanStoreRoleAppearance、MiniBeanStoreSpray、MiniBeanStoreWeapon、Recharge、Recommend、RoleAppearance、Special
- **MiniShopPage**（7）：Convert、CustomCoin、Item、MiniVip、Skin、WareHouse、Welfare
- **MiniShopWarehouse**（8）：ActionAdvanced、ActionPersonal、Appearance、AuxiliaryHorse、AuxiliaryMore、AuxiliarySpray、AuxiliaryWeapon、ItemWarehouse
- **MiniViewSecondTab**（5）：Avt、FashionSeat、Mount、Skin、StarFashionSeat
- **MobType**（6）：Fly、Hostile、Passive、Rare、Trixenie、Water
- **ModAttribType**（37）：ActorScale、ArmorExplode、ArmorPunch、ArmorRange、AttackAnimal、AttackExplode、AttackFire、AttackGun、AttackIce、AttackPlayer、AttackPoison、AttackPunch、AttackRange、AttackUndead、AttackWither、CriticalHit、DamageAbsorb、DamagedExplode、DamagedFalling、DamagedFire、DamagedPoison、DamagedPunch、DamagedRange、DamagedWither、DamagedZombie、DigSpeed、JumpSpeed、Knock、KnockResist、KnockResistProb、LuckDig、LuckKillmob、MoveSpeed、OxygenSupply、SwimSpeed、ViewBright、maxAttrib
- **Model**（3）：AvatarAnchorType、GunAnchorType、PartType
- **MonsterEdit**（1）：Type
- **MoveType**（4）：Auto、Flying、Swimming、Walking
- **NPCShop**（7）：CostType、DialogScene、GoodsQuality、PayType、RefreshType、ShopType、TagMatchMode
- **ObjType**（21）：Actor、Area、BiomeEdit、Block、BlockMaterial、Crafting、DropItem、Empty、Entity、Furnace、Item、Mob、Planet、Player、Pos、Projectile、Status、StatusEffect、StatusEffectInst、UI、World
- **ObjectEvent**（183）：ActorAddBuff、ActorAreaIn、ActorAreaOut、ActorAttack、ActorAttackHit、ActorBeHurt、ActorBeat、ActorChangeAttr、ActorChangeMotion、ActorClickActor、ActorCollide、ActorCreate、ActorDamage、ActorDie、ActorEnterAOI、ActorPickupActor、ActorProjectileHit、ActorRClickUp、ActorRemoveBuff、BlockAdd、BlockBeTouched、BlockChangeColor、BlockChangeDir、BlockClicked、BlockContainerChange、BlockContainerPutIn、BlockContainerTakeOut、BlockDestroy、BlockDigBegin、BlockDigCancel、BlockDigEnd、BlockPlaceBy、BlockRemove、CanPlayerPickUpItem、CaptureAndUploadScreenshot、DeveloperBuyItem、EntityCreate、EquipItemEvent、InteractBlock2Place、ItemAddDuration…
- **ObsBluePrintStatus**（3）：Binded、Loaded、Unloaded
- **OldGunEdit**（3）：BulletType、FireType、GunType
- **PLAYERATTR**（57）：ATK_FIREARM、ATK_MAGIC、ATK_MELEE、ATK_PHYSICAL、ATK_REMOTE、CUR_ARMOR、CUR_GRAVITY、CUR_HP、CUR_HUNGER、CUR_LEVEL、CUR_LEVELEXP、CUR_OXYGEN、CUR_STRENGTH、DAMAGED_ZOMBIE、DEF_CHAOS、DEF_MAGIC、DEF_MELEE、DEF_PHYSICAL、DEF_REMOTE、DIMENSION、DODGE、ENABLE_ATTACK、ENABLE_BEATTACKED、ENABLE_BEKILLED、ENABLE_DEATHDROPITEM、ENABLE_DESTROYBLOCK、ENABLE_DISCARDITEM、ENABLE_FORBIDDODGEANIM、ENABLE_FORBIFIRE、ENABLE_MOVE、ENABLE_OPERATEBLOCK、ENABLE_PICKUP、ENABLE_PLACEBLOCK、ENABLE_ROTATINGCAMERA、ENABLE_SWITCHSHORTCUT、ENABLE_USEITEM、ENABLE_VEHICLEAUTOFORWARD、HP_RECOVER、ITEM_DISABLE_DROP、ITEM_DISABLE_THROW…
- **PackEdit**（1）：PackType
- **Physics**（3）：ColliderShape、LayerType、PhysicsType
- **PickupActionType**（4）：Drop、Pickup、Throw、Unbind
- **PixelUnits**（2）：Percentage、Value
- **PlayerAttr**（57）：AtkFirearm、AtkMagic、AtkMelee、AtkPhysical、AtkRemote、AttackDis、CurArmor、CurHp、CurHunger、CurLevel、CurLevelexp、CurOxygen、CurStrength、DamagedZombie、DefChaos、DefMagic、DefMelee、DefPhysical、DefRemote、Dimension、Dodge、EnableAttack、EnableBeAttacked、EnableBeKilled、EnableDeathDropItem、EnableDestroyBlock、EnableDiscardItem、EnableForbiFire、EnableForbidDodgeAnim、EnableMove、EnableOperateBlock、EnablePickup、EnablePlaceBlock、EnableUseItem、EnableVehicleAutoForward、FlySpeed、HpRecover、ItemDisableDrop、ItemDisableThrow、JumpPower…
- **PlayerBodyUIHight**（4）：EffEct、HpBar、Nick、Title
- **PlayerController**（7）：CrosshairType、Mode、MoveLimit、RoteLimit、ViewMove、ViewType、ZoomMode
- **PlayerMotion**（12）：Down、Fall、FallGround、Jump、JumpTwice、Run、Sneak、Static、Swim、Turnback、Up、Walk
- **PlayerNameType**（3）：EffEct、Nick、Title
- **PlayerRelations**（3）：CollectMaps、EvaluateMaps、InviteFriend
- **ProgressImg**（2）：Background、Progress
- **ProgressVal**（4）：CurAndMax、Current、Max、Min
- **Projectile**（4）：HitProcess、HitType、HurtType、TrailType
- **ProjectileEdit**（5）：AccumulatorType、AttackType、DamageType、PhysicsMaterialType、TriggerCondition
- **RandomAddStatus**（1）：triggerTimeEnumType
- **RayDetectType**（5）：Actor、ActorType、Block、LiquidBlock、Player
- **RecoverStatus**（2）：AttrType、ModifyType
- **RelativeCampType**（4）：Any、Enemy、Friendly、Neutral
- **Reproduction**（2）：LayingEggType、ReproductionType
- **Ride**（4）：RideMobType、RidingConditionType、RidingHpType、RidingItemPermissionType
- **Roadblock**（1）：ColliderType
- **RoleAttr**（31）：Amana、AmanaMax、Atk、AttackDis、AttackDis1、CurHp、CurHunger、CurOxygen、CurStrength、FlySpeed、FlySpeed1、Gravity、HpRecover、JumpPower、LevelExp、LevelExp1、MaxHp、MaxHunger、MaxOxygen、MaxStrength、PunchArmor、PunchArmor1、RangeArmor、RangeArmor1、RunSpeed、StarNum、StarNum1、SwinSpeed、ViewDis、ViewDis1、WalkSpeed
- **RoleMotion**（7）：FallGround、Jump、Run、Sneak、Stand、Swim、Walk
- **RolePickupType**（2）：Carried、Carrying
- **SkyboxAttr**（14）：AmbientLightIntensity、CloudDensity、CloudHigh、CloudSpeed、DirectionalLightIntensity、FogreMaxDis、FogreMinDis、MoonScale、StarDensity、SunScale、Template、WaterMirrorness、WaterTransparency、WindStrength
- **SkyboxAttrNoTime**（2）：Metallic、Roughness
- **SkyboxColor**（12）：AmbientLight、Bottom、Cloud、DirectionalLight、Env、Fog、Light、Middle、Moon、Sun、Top、Water
- **SkyboxFilter**（15）：Bloomthreshold、Color、Contrast、Dof、Exposure、Flood、Ftmblackclip、Ftmshoulder、Ftmslope、Ftmtoe、Gamma、Lut、Saturation、Template、Volumelight
- **SkyboxFilterSwitch**（1）：Dofenable
- **SkyboxMap**（3）：Moon、Sky、Sun
- **SkyboxParticle**（4）：Randomness、Range、Speed、Strength
- **SkyboxSwitch**（1）：Fogenable
- **SkyboxTime**（10）：Current、Time0、Time12、Time16、Time18、Time20、Time4、Time6、Time8、TimeAll
- **SortType**（2）：Down、Up
- **Sound**（2）：playModeType、startType
- **StatusEdit**（3）：priority、triggerTimeEnumType、type
- **StorageType**（3）：box、boxcol、boxrow
- **SurviveComponent**（1）：AddAttrType
- **Tame**（2）：TameMobType、TameType
- **TaskAnimType**（5）：Click、LongPress、MoveLeft、MoveRight、MoveUp
- **TaskChainType**（3）：AllMap、GuideSinglePlayer、PlayerTask
- **TaskDialogType**（2）：Base、CustomUI
- **TaskEvent**（1）：ClickRideCallBtn
- **TaskPassType**（3）：AllTask、NextTask、None
- **TaskType**（2）：Dialog、Task
- **TaskUIType**（3）：CustomUI、GameUI、OldUI
- **TeamAttr**（2）：PlayerNum、Score
- **TeamResults**（4）：Dogfall、Lose、None、Win
- **TerrainType**（2）：Flat、Normal
- **ToolEdit**（1）：ToolType
- **TouchState**（3）：Begin、Cancel、End
- **Trigger**（17）：Actor、Area、ArrayTmp、Backpack、Block、Buff、Component、CustomUI、GameObject、Graphics、Item、KvMap、Math、Monster、Player、Timeline、World
- **TriggerEvent**（259）：ActorAddBuff、ActorAreaIn、ActorAreaOut、ActorAttack、ActorAttackHit、ActorBeHurt、ActorBeat、ActorChangeAttr、ActorChangeMotion、ActorClickActor、ActorCollide、ActorCreate、ActorDamage、ActorDie、ActorPickupActor、ActorProjectileHit、ActorRemoveBuff、AreaObjAreaIn、AreaObjAreaOut、AreaObjCollideToAreaObj、AreaObjCollideToDropItem、AreaObjCollideToEntity、AreaObjCollideToMissile、AreaObjCollideToMob、AreaObjCollideToPlayer、AreaObjCreate、AtorPlayAnim、BackpackItemChange、BackpackItemPutIn、BackpackItemTakeOut、BiomeActorSpawn、BlockAdd、BlockBeTouched、BlockChangeColor、BlockChangeDir、BlockChunkExtraBuild、BlockContainerChange、BlockContainerPutIn、BlockContainerTakeOut、BlockDestroyBy…
- **TurnFaceDir**（2）：Pitch、Yaw
- **UIAttr**（3）：Id、Name、Visibility
- **UIProjectSet**（2）：bgColorEnum、systemLevelEnum
- **UIScollDir**（3）：Both、Horizontal、Vertical
- **UseEdit**（5）：ChargeType、CostType、RangeType、SkillType、TargetTeam
- **VDistanceRange**（5）：Far、Farthest、Further、Middle、Near
- **VIEWPORTTYPE**（6）：BACK2VIEW、BACKVIEW、CUSTOMVIEW、FRONTVIEW、MAINVIEW、TOPVIEW
- **VarType**（51）：AreaGroup、Areains、BlockType、BlockTypeGroup、Blueprint、Boolean、BooleanGroup、BuffType、BuffTypeGroup、Creature、CreatureGroup、CreatureType、CreatureTypeGroup、DropItem、DropItemGroup、EffectType、EffectTypeGroup、Element、ElementGroup、Entity、EntityGroup、EntityType、EntityTypeGroup、ItemType、ItemTypeGroup、ListData、Map、Model、ModelGroup、Number、NumberGroup、Object、ObjectGroup、Player、PlayerGroup、Pos、PosGroup、Projectile、ProjectileGroup、Role…
- **VerticalOffset**（3）：Bottom、Centered、Top
- **ViedoPlayMode**（2）：Once、Repeat
- **ViewPortType**（6）：Back、Back2、Custom、Front、Main、Top
- **Villager**（4）：AvatarAnchorType、GunAnchorType、PartType、ProfessionType
- **WeatherGroup**（10）：AirIsland、Coldzone、Common、Desert、Frigidzone、Global、Nunja、Ocean、Plain、Volcano
- **WeatherType**（12）：Custom、None、Rain、Sandstorm、Snow、Sunshine、UnderWater、VoidNight、Volcano、WEATHRT_NONE、ZOMBIE_WAVE、ZombieWave
- **WorkStage**（3）：Craft、Enchant、Repair
- **WorkeStage**（3）：Craft、Enchant、Repair
- **WorldRuleBaseSetting**（1）：WeatherType
- **WorldRuleCloudSetting**（1）：GameModeType
- **WorldRuleFightSetting**（2）：attackModeType、defenseFormulaType
- **WorldRuleHUDUI**（3）：MapIconClickType、MapPlayerIconType、MapPlayerShowType
- **WorldRuleRebirth**（3）：deathDropModeType、rebirthCostModeType、rebirthModeType
- **WorldRuleSceneUI**（1）：displayNameType
- **WorldRuleSound**（2）：backgroundMusicType、ratioPec
- **WorldRuleStartMode**（3）：displayNameType、levelModeTypeEnum、playerLimitTypeEnum
- **WorldType**（8）：Create、CreateToRungame、Extremity、Freemode、Gamemaker、GamemakerRun、Record、Single
- **math**（2）：huge、pi
