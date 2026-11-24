# 战役改造验收

## 五关节奏

每关每个难度使用 16 个固定种子。表中的时长从首波开始计到通关，采用普通难度双 AI 的通关中位数。平衡模拟步长为 0.05 秒，实机战斗步长为 1/60 秒。

| 关卡 | 普通通关中位数 | 休闲胜场 | 普通胜场 | 困难胜场 |
| --- | ---: | ---: | ---: | ---: |
| 翡翠双桥 | 5:09 | 16/16 | 16/16 | 16/16 |
| 裂谷交叉 | 7:05 | 16/16 | 16/16 | 6/16 |
| 王城终局 | 7:49 | 16/16 | 16/16 | 6/16 |
| 霜原雪径 | 7:51 | 16/16 | 16/16 | 7/16 |
| 深渊回廊 | 10:22 | 16/16 | 16/16 | 11/16 |

普通难度空守和单 AI 对照各五局全败。建议开局塔位在每关首批敌人的所有地面分线上均能于约 4–8 秒建立箭塔射程覆盖。实战首击还取决于建造选择和英雄站位。

## 回归与局域网

- `godot --headless --path . --script res://tests/run_tests.gd` 验证地图合法性、波次流转、裂隙开启、弹体命中、受击时序、存档和界面。864 项通过。
- `godot --headless --path . --script res://tests/balance_sim.gd -- seeds=16` 运行 240 场双 AI 对局及空守、单 AI 对照。可用 `stage=<id>` 分关运行。
- 将下面两条命令放在两个终端运行。测试覆盖房主选关、席位归属、开波就绪、密集单位同步、暂停、倍速、结算、重开和掉线。

```powershell
godot --headless --path . --script res://tests/lan_smoke.gd -- role=host port=24635
godot --headless --path . --script res://tests/lan_smoke.gd -- role=client port=24635
```

同屏和局域网的双真人实玩，以及实体手柄操作仍待验证。基线和更新后的无头测试均有退出时的 Godot 资源释放告警。

## Windows 表现

导出文件为 `dist/TwinBastionTD.exe`，五关实机片段为 `dist/TwinBastionTD-Campaign.mp4`。帧时间以 Ryzen 7 7800X3D、Radeon RX 9070 XT 和 1440×810 为参考，在五关密集交战中分 1×、2×、3× 采样。每关加载后加入 120 个普通单位和一名特殊敌人。

最终导出运行中，15 组场景的最高 P95 为 **9.58 ms**，采样最高单帧 **14.89 ms**，均低于 60 FPS 对应的 16.67 ms。该项采样从关卡载入后开始。

```powershell
.\build_windows.ps1
.\dist\TwinBastionTD.exe --resolution 1440x810 -- --battle-review --profile
godot --path . --resolution 1440x810 --fixed-fps 30 --write-movie tools/out/twin-bastion-campaign.avi -- --battle-review
```

帧时间日志由导出版本写到 `user://_twin_battle_profile.log`。表现测试和录像使用独立存档。
