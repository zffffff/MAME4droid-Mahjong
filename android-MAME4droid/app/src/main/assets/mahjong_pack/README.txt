# 麻将按键包资源目录（assets/mahjong_pack）

来源：仓库 A 一键发布产物
  D:\Dev\MAMEmjKey\release\飞剧场-手机版怀旧街机麻将按键包-20260726

版本：20260726.1
  - 随手机横竖自动切换 Portrait_* / Landscape_* artwork View（读 .device_orientation）
  - 横屏虚拟手柄改为底部窄条（仅 Exit/Option/Coin/Start）
  - 雀斗记 jantouki 强制竖屏

结构会安装到 App files 根目录：
  artwork/{rom}/...
  master_lamps.lua
  fei_mj_lamps/
  ini/mame.ini
  （并同步一份 mame.ini 到 files 根目录）

更新步骤：替换本目录内容，修改 VERSION.txt，重新打包 APK。
