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

更新步骤：替换本目录内容，修改 VERSION.txt，重新打包 APK。
补中文名：编辑 mame.lst（UTF-8，romset 与中文名用 Tab 分隔），同步 arcade.lst，bump VERSION.txt。
