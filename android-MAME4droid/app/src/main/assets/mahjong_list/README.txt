# 选台列表资源（mahjong_list）

给「自制选台页」用的美术与约定。按键包仍在 `mahjong_pack/`。

## 你需要提供的资源

### 1. 列表背景图（按机种，可选）

| 项 | 约定 |
|----|------|
| 目录 | `android-MAME4droid/app/src/main/assets/mahjong_list/bg/` |
| 文件名 | **必须与 MAME 短名完全一致**（小写），如 `lhzb4.webp`、`lhzb4dhb.webp` |
| 格式 | 优先 **WebP**；也支持 `.png` / `.jpg` / `.jpeg` |
| 建议尺寸 | 宽 **720–1080px**，高 **160–240px**（列表会裁切铺满一行；横图更好） |
| 内容 | 该机种代表性画面/海报感；避免大块白边；重要内容靠左或居中（右侧常被渐变压暗） |

**加载优先级：**

1. `mahjong_list/bg/<rom>.*`（机种定制）
2. 安装目录 `snap/<rom>.png`（或 `.jpg`）
3. **缺省底图** `_default.*`（按基础版/进阶版分开，见下）
4. 纯色渐变（最后兜底；颜色只是按短名换皮，**与 ROM 好坏无关**）

### 缺省底图（两版各一张）

文件名都叫 **`_default.webp`**（也可用 png/jpg），放到不同目录：

| 版本 | 放这里 |
|------|--------|
| 进阶版 | `android-MAME4droid/app/src/full/assets/mahjong_list/bg/_default.webp` |
| 基础版 | `android-MAME4droid/app/src/basic/assets/mahjong_list/bg/_default.webp` |

### 2. 发布签名

见 `docs/选台资源与签名.md`（仓库已配置 CI Secrets）。

### 3. 不必提供

- ROM、全套 snap、按键包 artwork

## 当前会进选台列表的机种

以 `mahjong_pack/mame.lst` 为准（**含克隆版**）。中文名同文件。
