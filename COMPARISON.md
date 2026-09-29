# stlkit 与现有网格库的对比

## 定位

trimesh 是 **Python** 生态的通用三角网格库，需要 Python 解释器和 numpy。

stlkit 是用 **MoonBit** 写的 3D 打印前置检查工具链，编译成原生代码 / wasm / JS，
不依赖任何运行时，回答一个问题：**这个模型能不能 3D 打印。**

两者面向的场景不同，下面逐项说清楚。

---

## 一、trimesh 是什么

按它自己的 README 原话：

> Trimesh is a pure Python 3.10+ library for loading and using triangular meshes
> with an emphasis on watertight surfaces.

- 唯一硬依赖是 numpy；scipy / networkx / lxml / pyglet 等是「装了才有更多功能」的软依赖
- 支持导入 STL、OBJ、OFF、PLY、GLTF/GLB、3MF、XAML、3DXML 等
- 支持导出 GLB/GLTF、STL、PLY、OFF、OBJ、COLLADA 等
- 还做 DXF/SVG 矢量路径、OpenGL 预览、Jupyter 内嵌 three.js 预览

能力包括：凸包、截面与切片、质量属性（体积 / 质心 / 转动惯量 / 惯性主轴）、
布尔运算（Manifold3D 或 Blender）、体素化、拉普拉斯平滑、细分、
射线求交、有向包围盒 / 包围球 / 包围柱、最近点与有符号距离、
按连通块拆分（`mesh.split()`）、欧拉数（`mesh.euler_number`）、
绕向与法线修复、四边/三角洞修补。

这是一套通用网格处理工具集，而 stlkit 只做「打印前检查」这一段。

---

## 二、逐项对比

|  | trimesh | stlkit |
| --- | --- | --- |
| 语言 / 运行时 | Python 3.10+，要 numpy | MoonBit，编译成原生代码 / wasm / JS |
| 编译产物 | 不适用（解释执行） | native 可执行文件 / wasm / 一个 js 文件 |
| 输入格式 | STL、OBJ、OFF、PLY、GLTF/GLB、3MF、XAML、3DXML… | STL（ASCII + 二进制）、OBJ、3MF |
| 输出格式 | GLB/GLTF、STL、PLY、OFF、OBJ、COLLADA | 二进制 / ASCII STL、OBJ |
| 布尔运算、体素化、平滑、细分 | 有 | 没有 |
| 射线求交、最近点、有符号距离 | 有 | 没有 |
| 质量属性 | 体积、质心、转动惯量、惯性主轴 | 体积、表面积、包围盒、零件数、欧拉数 |
| 修复 | 绕向、法线、四边/三角洞 | 补洞、删退化面、删重复面、统一绕向、重算法线 |
| 校验 | 水密、凸性、绕向一致、欧拉数 | 水密、非流形边、退化面、法线朝向、绕向一致、零件数、欧拉数 |
| 大文件 | 整个网格进 numpy 数组 | 分块流式扫描，内存不随文件增长 |
| 网页版 | 需要 Jupyter 或 pyglet 窗口（要显示环境） | 纯浏览器，双击 html 就能用，文件不上传 |
| 形态 | 库 | 库 + 命令行 + 网页 |

---

## 三、三条实质区别

### 1. 能跑的地方不同

trimesh 需要 Python 解释器和 numpy。它进不了浏览器，也编不进一个没有解释器的
独立二进制。这不是「谁更好」的问题，是「能不能用」的问题：

- 一个**纯前端页面**（用户上传模型、当场出结论、文件不出本机）
- 一个**独立的单文件可执行程序**（发给同事，他不用装 Python）
- **另一个 MoonBit 项目里的一个依赖**

这三处 trimesh 都进不去。stlkit 的网页版就是第一种的实现——浏览器里跑的是
MoonBit 编译成的 wasm/JS，不是 JavaScript 重写的，也不是后端服务。

### 2. 内存模型不同

trimesh 的设计是把整个网格装进 numpy 数组再做分析——它要做的布尔运算、
射线求交本来就要求完整的拓扑和几何索引，这是它的功能决定的。

stlkit 的流式扫描针对的是另一个场景：**只看统计量，不保留网格**。
体积、表面积、包围盒都能一边读一边累加；水密性靠两张紧凑表
（顶点去重表 + 打包成 64 位整数的边表）排序后扫一遍得出。
实测 95.37 MB、200 万三角形的模型：

| 方式 | 耗时 | 内存 |
| --- | --- | --- |
| 全量解析（保留网格，能校验能修复） | 18088 ms | 293.73 MB |
| 流式扫描（文件整块读） | 2048 ms | 141.22 MB |
| 流式扫描（**分块读**） | 3334 ms | **46.1 MB** |

分块模式下文件完全不进内存，只有一个 256 KB 的缓冲区循环复用。
省 84.3%，每个三角形从 154 字节降到 24 字节。

「3D 扫描仪导出的几百 MB 文件，我只想知道有没有破洞」这个场景，
可以不用把整个网格装进来。

### 3. 输出形态不同

trimesh 是**库**：`mesh.is_watertight` 返回 `True` / `False`，判断留给你。

stlkit 是**工具链**：报告里不写「有 3 条边界边」，而是写
「切片软件分不清哪里是实心哪里是空的，直接打印会失败」。
加 `--strict` 时退出码反映结论，可以直接挂进 CI。

对「我要不要把这个文件发给打印店」这个具体决定，给结论和给数字是两回事。

---

## 四、为什么用 MoonBit 重写是有意义的

**这场黑客松里已经通过初审的项目，全都是「把别的语言里已经成熟的东西用 MoonBit 重写一遍」：**

| 项目 | 它实现的规范 | 其他语言里的成熟实现 |
| --- | --- | --- |
| `moon-robots` | RFC 9309 robots.txt | Python 标准库 `urllib.robotparser` |
| `moon-sfv` | RFC 9651 结构化字段值 | PyPI `http-sfv` |
| `dbc-toolkit` | CAN DBC | PyPI `cantools` |
| `nmea-toolkit` | NMEA 0183 | PyPI `pynmea2` |

（上面四个 Python 实现都实际查过，确实存在。）

「别的语言里已经有成熟实现」这件事，对上面每一个项目同样成立。
它们的价值不在于世界首创，而在于 **MoonBit 生态里从零到一**——
用 MoonBit 的项目没法直接调用 `pip install trimesh`。

而 3D 网格处理这一块，**MoonBit 生态目前是空的**：

- 检索了 mooncakes 全部 2439 个包，逐个检查 15 个 3D 相关候选
- 它们**全是渲染方向**：`mizchi/three` 是 three.js 的 FFI 绑定（模型解析是
  `extern "js"` 交给浏览器里的 three.js 做的，MoonBit 侧没有解析代码）；
  `mizchi/mesh3d` 是渲染原语，OBJ 解析器逐面展开顶点、不留拓扑
- **没有任何一个包做三角网格质量验证**

trimesh 是 Python 的。它进不了 MoonBit。

---

## 五、从 trimesh 借鉴的部分

下面几项是看了 trimesh 的设计之后补的：

**零件数**（对应 trimesh 的 `mesh.split()`）。一个「看起来是一个模型」的文件
里如果有 5 块互不相连的几何，打出来就是 5 个零散的东西。这类问题从预览图上
看不出来，模型画出来是完整的。实现上按**面的邻接**数连通块——
只有共用边才算连接，两个零件只碰一个角不算，因为那种接触在切片时是断的。

**欧拉示性数**（对应 trimesh 的 `mesh.euler_number`）。χ = V − E + F。
水密网格上它是有拓扑含义的：2 = 一个实心块，0 = 有一个穿透的洞，
−2 = 有两个。`examples/torus.3mf` 是个圆环，算出来正好是 **0**。
实现上只在结论是水密时才报——不水密的时候这个数只是一堆计数的组合，
报出来会让人以为读出了什么。

**单位换算和装配体**：3MF 里写 `inch` 而不换算，体积会差 25.4³ ≈ 16387 倍；
对象可以由别的对象拼出来，各带一个 4×3 的行向量变换矩阵。

**拓扑判据本身**也是同一套：水密性 = 每条边恰好被两个面共用，
绕向一致性 = 相邻两面必须以相反方向使用共用边。

---

## 六、能力边界

这些能力 trimesh 有、stlkit 没有：

- 布尔运算（交 / 并 / 差）
- 体素化、拉普拉斯平滑、细分
- 射线求交、最近点查询、有符号距离
- 有向包围盒 / 包围球 / 包围柱
- 质心、转动惯量、惯性主轴
- 导入 OFF / PLY / GLTF / XAML / 3DXML
- 导出 GLB / PLY / COLLADA / DXF / SVG
- 交互式 3D 预览窗口（stlkit 只出静态 SVG 等轴测图）

它们服务的是「对网格做变换和运算」，stlkit 服务的是「判断这个网格能不能打印」。
两条线要回答的问题不同，功能的取舍自然也不同。

---

## 七、MoonBit 生态内部对比

MoonBit 生态里已有的两个 3D 相关包：

|  | `mizchi/three`（three-mbt） | `mizchi/mesh3d` | stlkit |
| --- | --- | --- | --- |
| 本质 | three.js 的类型化 FFI 绑定 | 渲染用网格原语（从 kagura 抽出） | 文件格式与质量工具链 |
| 解析在哪 | **JS**（`extern "js"` 里调 three.js 的 `self.parse()`） | 纯 MoonBit，但只到顶点/格式原语 | 纯 MoonBit |
| 跑在哪 | 只有 JS 后端，要 npm 工具链 | JS（kagura 渲染管线的一部分） | native / wasm / js 三端 |
| 保留拓扑 | 否（输出 `BufferGeometry`，给 GPU 的） | **否**（逐面展开顶点，注释原文 "Emit vertices for this face"） | 是 |
| 出错怎么办 | 抛 JS 异常 | 索引越界静默按 `0.0`，返回 `Mesh3D` 而非 `Result` | `Result`，错误带行号或字节偏移 |
| 回答的问题 | 它长什么样 | 它长什么样 | **它能不能被 3D 打印** |

`mizchi/mesh3d` 的注册表描述原文就是 "Mesh / vertex-format primitives for
**3D rendering** (extracted from kagura)"。它们是渲染方向的。

---

## 八、一句话总结

| | |
| --- | --- |
| trimesh | Python 生态的通用三角网格库，需要 Python + numpy，提供网格操作的完整工具集 |
| 其它 MoonBit 3D 包 | 渲染方向，输出给 GPU 的几何，不做质量验证 |
| **stlkit** | 回答「这个模型能不能 3D 打印」。纯 MoonBit，无 FFI，三端可跑；库 + 命令行 + 网页三种形态；能流式扫描几百 MB 的扫描件 |

**它们回答「模型长什么样」，stlkit 回答「模型能不能打印」。**
