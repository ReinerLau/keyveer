# Keyveer 配置说明

配置文件位置：`~/Library/Application Support/Keyveer/config.json`

这是严格的 JSON 文件，不支持 `//` 或 `/* ... */` 注释。字段说明放在本文档中；可在状态栏菜单选择 **Show Configuration in Finder** 打开配置目录并选中文件，修改并保存后选择 **Reload Configuration**。

## 完整示例

下面是 schema v3 的完整示例。可以只保留或修改自己需要的字段；`visual`、`marker`、`trail` 及其中字段都可以省略，省略时使用默认值。

```json
{
  "schemaVersion": 3,
  "bindings": {
    "activation": "leftOption",
    "moveUp": "i",
    "moveDown": "k",
    "moveLeft": "j",
    "moveRight": "l",
    "leftClick": "space",
    "rightClick": "r",
    "middleClick": "e",
    "backClick": "q",
    "forwardClick": "w",
    "scrollUp": "m",
    "scrollDown": "comma",
    "scrollLeft": "period",
    "scrollRight": "slash",
    "precision": "a",
    "speedOne": "s",
    "speedTwo": "d",
    "speedThree": "f"
  },
  "movement": {
    "baseSpeed": 300,
    "precisionMultiplier": 0.3333333333,
    "fastMultiplier": 3,
    "smoothingMilliseconds": 75
  },
  "scrolling": {
    "baseSpeed": 960,
    "precisionMultiplier": 0.25,
    "fastMultiplier": 4,
    "smoothingMilliseconds": 47
  },
  "optionTapMilliseconds": 250,
  "visual": {
    "marker": {
      "coreDiameter": 7,
      "glowRadius": 9,
      "coreColor": "#FFFFFF",
      "outerGlowColor": "#008FEF",
      "outerGlowOpacity": 0.60,
      "glowStrength": 1.0
    },
    "trail": {
      "coreWidth": 3.5,
      "blurRadius": 16,
      "coreColor": "#FFFFFF",
      "outerGlowColor": "#008FEF",
      "outerGlowOpacity": 1.0,
      "glowStrength": 1.0,
      "trunkFlickerIntervalMin": 0.12,
      "trunkFlickerIntervalMax": 0.30,
      "trunkFlickerFramesMin": 1,
      "trunkFlickerFramesMax": 2
    }
  }
}
```

## 字段含义

### `bindings`：按键

`activation` 是进入/退出自由模式的按键，必须是 `leftOption` 或 `rightOption`。其余字段是对应动作的按键名称：

| 字段 | 默认值 | 作用 |
| --- | --- | --- |
| `moveUp` / `moveDown` / `moveLeft` / `moveRight` | `i` / `k` / `j` / `l` | 指针移动 |
| `leftClick` / `rightClick` / `middleClick` | `space` / `r` / `e` | 鼠标按键 |
| `backClick` / `forwardClick` | `q` / `w` | 鼠标后退/前进 |
| `scrollUp` / `scrollDown` / `scrollLeft` / `scrollRight` | `m` / `comma` / `period` / `slash` | 滚动 |
| `precision` | `a` | 精细速度 |
| `speedOne` / `speedTwo` / `speedThree` | `s` / `d` / `f` | 速度档位 |

### `movement`：指针移动

| 字段 | 默认值 | 含义 |
| --- | ---: | --- |
| `baseSpeed` | `300` | 基础移动速度（pt/s） |
| `precisionMultiplier` | `0.3333` | 按住精细键时的速度倍率 |
| `fastMultiplier` | `3` | 快速档位的速度倍率 |
| `smoothingMilliseconds` | `75` | 移动平滑时间（ms） |

### `scrolling`：滚动

字段与 `movement` 相同，但作用于滚动：默认值分别为 `960`、`0.25`、`4`、`47`。

### `optionTapMilliseconds`

左右 Option 单击/长按判定时间，单位为毫秒，默认 `250`。

### `visual.marker`：右下角圆点

| 字段 | 默认值 | 含义 |
| --- | ---: | --- |
| `coreDiameter` | `7` | 白芯直径（pt） |
| `glowRadius` | `9` | 外层辉光的高斯模糊半径（pt）；数值越大，扩散越宽 |
| `coreColor` | `#FFFFFF` | 白芯颜色 |
| `outerGlowColor` | `#008FEF` | 外层蓝色辉光及模糊扩散 |
| `outerGlowOpacity` | `0.60` | 外层辉光透明度（`0` 到 `1`） |
| `glowStrength` | `1` | 高斯辉光叠加强度（`0` 到 `3`）；不改变扩散半径 |

### `visual.trail`：闪电轨迹

一次连续移动只形成一道完整闪电。累计移动达到 8pt 后，闪电从准确起点补画并沿实际移动
路线持续生长；移动期间不限制最大长度，也不会删除或淡化旧段。释放最后一个键盘移动键会
立即触发停止；仅物理鼠标移动时仍以约 100ms 的无位移作为兜底。停止后主干冻结在原位置，
各处以不同顺序收细、断裂，并在约 0.45 秒内完全移除。它不会从某一端向另一端
擦除，也不产生同等粗细的分叉或飞散火花；伴随电弧是比主干更细的独立随机折线，
沿主干相同方向但不复用主干坐标，在随机路径距离触发后从当前位置开始生长。
每条电弧都有独立的随机长度和停留时间，达到长度或主干停止后停止增长，停留时间从停止增长时开始计算，
到期后单独消失；电弧数量不设上限，也不因主干消失而提前移除。

键盘控制时，默认速度和精确慢速（`precision`）隐藏醒目的主干，但保留细弱伴随电弧；按住任一速度键
（`speedOne` / `speedTwo` / `speedThree`）后重新显示主干。物理鼠标移动不受此速度档位限制。
主干和每条伴随电弧分别以约 120–300ms 的独立随机间隔短暂隐藏 1–2 个显示帧，彼此不要求同步。
停止移动后的消散阶段、以及 macOS 开启 Reduce Motion 时不会新增此类闪烁。
上述间隔和隐藏帧数可通过下方 `trunkFlicker*` 配置项调整。

`coreWidth` 是白芯的基准宽度。每个局部段生成时会取得固定的随机倍率，实际宽度为
`coreWidth × 0.45...1.6`；随机范围与轨迹位置无关，生成后不会继续变化。闪电折点也使用
位置无关的二维随机偏移：方向和距离都独立随机，但折点仍以移动路线上的采样点为中心，起点和终点不偏移。
方向范围使用相对当前路径前进方向的角度配置（0° 沿路径向前、正角度向路径左侧、负角度向路径右侧、
180° 向后），支持 `-360...360`；距离使用 pt 配置。Reload 后新生成的闪电使用新范围，已经存在的闪电保持原有几何。

| 字段 | 默认值 | 含义 |
| --- | ---: | --- |
| `coreWidth` | `3.5` | 白芯基准宽度（pt）；局部实际宽度为该值的 `0.45...1.6` 倍 |
| `bendSpacingMin` / `bendSpacingMax` | `24` / `36` | 主折点间距的随机范围（pt）；整体值越大折点越稀疏，越小越密集 |
| `bendOffsetDistanceMin` / `bendOffsetDistanceMax` | `6` / `24` | 主折点随机偏移距离范围（pt） |
| `bendOffsetDirectionMin` / `bendOffsetDirectionMax` | `-90` / `90` | 相对路径前进方向的随机偏移角度范围（度）；正角度向左、负角度向右；默认限制在前方半圆 |
| `arcLengthMin` / `arcLengthMax` | `80` / `180` | 每条伴随电弧独立抽取的生长长度范围（pt） |
| `arcGapMin` / `arcGapMax` | `24` / `72` | 新伴随电弧随机生成的路径距离间隔范围（pt） |
| `arcHoldMin` / `arcHoldMax` | `0.20` / `0.50` | 电弧停止增长后的随机停留时间范围（秒） |
| `trunkFlickerIntervalMin` / `trunkFlickerIntervalMax` | `0.12` / `0.30` | 主干随机隐藏节点之间的间隔范围（秒） |
| `trunkFlickerFramesMin` / `trunkFlickerFramesMax` | `1` / `2` | 每次主干隐藏的显示帧数范围；必须为整数 |
| `blurRadius` | `16` | 轨迹外层高斯模糊半径（pt） |
| `coreColor` / `outerGlowColor` | `#FFFFFF` / `#008FEF` | 白芯与外层辉光颜色 |
| `outerGlowOpacity` | `1` | 外层辉光透明度（`0` 到 `1`） |
| `glowStrength` | `1` | 高斯辉光叠加强度（`0` 到 `3`）；不改变扩散半径 |

颜色固定使用 `#RRGGBB`。视觉数值和宽度关系会在 Reload 时校验；非法配置会被拒绝，并继续使用上一份有效配置。

圆点窗口和定位尺寸会根据 `coreDiameter` 与 `glowRadius` 自动计算，不再需要配置 `diameter`。
旧配置中如果仍保留 `diameter`，程序会兼容读取并忽略它。

## 旧配置

schema v1/v2 配置仍可读取并自动迁移到运行时的 v3。旧文件没有 `visual` 时，会使用本文档中的视觉默认值，不需要手动补齐。

旧 schema v3 中的 `visual.trail.lengthMultiplier` 与 `visual.trail.maxLength` 仍可读取和校验，
但不再影响轨迹。`tailWidthScale` 与 `headWidthScale` 已删除；配置中仍包含它们时，Reload 会
将文件作为包含未知字段的无效配置拒绝。
