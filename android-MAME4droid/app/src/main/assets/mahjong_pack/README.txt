# 麻将按键包资源目录（assets/mahjong_pack）

许可证：见同目录 `LICENSE.txt`（与本仓库相同，GPL-2.0-or-later）。  
源码仓库：https://github.com/zffffff/MAME4droid-Mahjong

结构会安装到 App files 根目录：
  artwork/{rom}/...
  master_lamps.lua
  fei_mj_lamps/
  ini/mame.ini
  mame.lst / arcade.lst  ← 按键包系中文游戏名（含克隆；内容相同）
  （并同步一份 mame.ini 到 files 根目录）

更新步骤（推荐）：打包前先检查是否落后于仓库 A：

  python android-MAME4droid/scripts/sync-mahjong-pack.py --check

落后再同步（合并手机横竖屏桥接，勿裸拷 Mods 的 master_lamps.lua）：

  python android-MAME4droid/scripts/sync-mahjong-pack.py

脚本不改 mame.lst / arcade.lst / ini；详见 docs/知识库.md §2.1、docs/整合勿丢内容.md。
手动覆盖时：勿整目录盖 fei_mj_lamps（会丢灯控或透视）；勿裸拷 Mods 的 master_lamps.lua（会丢 .device_orientation 切 View）；bump VERSION.txt 后重打 APK。
补中文名：编辑 mame.lst（UTF-8，romset 与中文名用 Tab 分隔），同步 arcade.lst，bump VERSION.txt。
