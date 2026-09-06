# Keyveer 配置说明

配置文件位置：`~/Library/Application Support/Keyveer/config.json`

这是严格的 JSON 文件，不支持 `//` 或 `/* ... */` 注释。字段说明放在本文档中；修改并保存后，在状态栏菜单选择 **Reload Configuration**。

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
      "lengthMultiplier": 1,
      "maxLength": 320,
      "coreWidth": 3.5,
      "tailWidthScale": 0.18,
      "headWidthScale": 1.6,
      "blurRadius": 16,
      "coreColor": "#FFFFFF",
      "outerGlowColor": "#008FEF",
      "outerGlowOpacity": 1.0,
      "glowStrength": 1.0
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

宽度沿轨迹从尾端逐渐过渡到标记端：尾端是远离当前自由模式指针标记的一端，标记端是
靠近标记的一端。`coreWidth` 是基准白芯宽度；两端的实际宽度都以它为基准计算：
`实际宽度 = coreWidth × 对应倍率`。因此这些倍率不是独立的 pt 数值。

| 字段 | 默认值 | 含义 |
| --- | ---: | --- |
| `lengthMultiplier` | `1` | 轨迹长度倍率 |
| `maxLength` | `320` | 轨迹最大长度（pt） |
| `coreWidth` | `3.5` | 白芯宽度（pt） |
| `tailWidthScale` | `0.18` | 尾端宽度倍率；实际宽度为 `coreWidth × tailWidthScale` |
| `headWidthScale` | `1.6` | 标记端宽度倍率；实际宽度为 `coreWidth × headWidthScale` |
| `blurRadius` | `16` | 轨迹外层高斯模糊半径（pt） |
| `coreColor` / `outerGlowColor` | `#FFFFFF` / `#008FEF` | 白芯与外层辉光颜色 |
| `outerGlowOpacity` | `1` | 外层辉光透明度（`0` 到 `1`） |
| `glowStrength` | `1` | 高斯辉光叠加强度（`0` 到 `3`）；不改变扩散半径 |

颜色固定使用 `#RRGGBB`。视觉数值和宽度关系会在 Reload 时校验；非法配置会被拒绝，并继续使用上一份有效配置。

圆点窗口和定位尺寸会根据 `coreDiameter` 与 `glowRadius` 自动计算，不再需要配置 `diameter`。
旧配置中如果仍保留 `diameter`，程序会兼容读取并忽略它。

## 旧配置

schema v1/v2 配置仍可读取并自动迁移到运行时的 v3。旧文件没有 `visual` 时，会使用本文档中的视觉默认值，不需要手动补齐。
