# 选台列表资源（mahjong_list）

给「自制选台页」用的美术与约定。按键包仍在 `mahjong_pack/`。

## 列表背景加载顺序

1. `mahjong_list/bg/<rom>.*`（机种定制）
2. `snap/<rom>.png` **或** `snap/<rom>/0000.png`（文件夹封面）
3. 缺省底图 `_default.*`（可半透明，底下仍有按短名区分的深色渐变）
4. 文字遮罩：横屏约 2/3 渐隐；竖屏左 1/5 实底、中 3/5 渐隐、右 1/5 全透

缺省底图（两版各一张，文件名相同）：

| 版本 | 路径 |
|------|------|
| 进阶版 | `app/src/full/assets/mahjong_list/bg/_default.webp` |
| 基础版 | `app/src/basic/assets/mahjong_list/bg/_default.webp` |

机种定制图仍放：`app/src/main/assets/mahjong_list/bg/<短名>.webp`

## 列表条目

- 中文名：`mahjong_pack/mame.lst`（两列，勿加第三列，MAME 会读）
- 主档/克隆：`mahjong_list/groups.txt`（`短名<TAB>主档短名`，主档填自己）
- 克隆：缩进 + 浅灰标题
