# 选台列表资源（mahjong_list）

给「自制选台页」用的美术与约定。按键包仍在 `mahjong_pack/`。

## 列表背景加载顺序

1. `mahjong_list/bg/<rom>.*`（机种定制）
2. `snap/<rom>.png` **或** `snap/<rom>/0000.png`（文件夹封面）
3. 缺省底图 `_default.*`（可半透明，底下仍有按短名区分的深色渐变）
4. 左侧约 **2/3 宽** 深色渐隐，方便读标题

缺省底图（两版各一张，文件名相同）：

| 版本 | 路径 |
|------|------|
| 进阶版 | `app/src/full/assets/mahjong_list/bg/_default.webp` |
| 基础版 | `app/src/basic/assets/mahjong_list/bg/_default.webp` |

机种定制图仍放：`app/src/main/assets/mahjong_list/bg/<短名>.webp`

## 列表条目

- 数据：`mahjong_pack/mame.lst`（含克隆）
- 分组：有 `artwork/<rom>/` 的当主档；其余挂到最长前缀匹配的主档下
- 克隆：缩进 + 浅灰标题，与主档区分

等 `_default` 图到位后再打包发版。
