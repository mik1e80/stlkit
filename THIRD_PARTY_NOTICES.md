# 第三方内容声明

本项目自己的代码是 Apache-2.0（见 [LICENSE](LICENSE)）。下面这些内容来自别处，
按各自的许可证使用。

---

## 1. 3MF 官方样例文件

**位置**：`examples/*.3mf`（4 个）和 `examples/conformance/*.3mf`（13 个）

**来源**：[3MF Consortium 的 3mf-samples](https://github.com/3MFConsortium/3mf-samples) 仓库，
分别是 `examples/core/` 下的示例模型和 `validation tests/3mf-Verify/MUSTPASS/` 下的一致性测试文件。

**改动**：无。原样收录。

**许可证**：BSD 2-Clause。完整文本见下。

```
BSD 2-Clause License

Copyright (c) 2018, 3MF Consortium
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

---

## 2. trimesh（设计参考，未使用代码）

**来源**：[trimesh](https://trimesh.org/) —— Python 的通用三角网格库，
[MIT 许可证](https://github.com/mikedh/trimesh/blob/main/LICENSE.md)。

**使用方式**：**只参考了 API 设计，没有复制任何代码。** 本项目是 MoonBit 实现，
和它的 Python 实现语言、数据结构都不同。逐项对应关系见
[接口文档](README.mbt.md#许可与参考) 和 [COMPARISON.md](COMPARISON.md#参考关系)。

这里列出 API 设计参考来源；本项目代码及随附样例分别按上述许可证说明。

---

## 3. 第三方依赖

`moon.mod` 里声明的依赖，各自的许可证以它们自己的仓库为准：

| 依赖 | 用途 | 许可证 |
| --- | --- | --- |
| `hustcer/fzip` | 解 ZIP（3MF 用） | Apache-2.0 |
| `Milky2018/xml` | 解 XML（3MF 用） | Apache-2.0 |
| `moonbitlang/x` | 读文件、设退出码（命令行用） | Apache-2.0 |
| `moonbitlang/async` | 分块读文件（只有 `--bench` 用） | Apache-2.0 |

分块读取现也用于 `--stream-only`。网页分发的 MoonBit core、fzip、XML 完整许可，以及本项目许可和此来源说明，保存在 `web/licenses/` 并随 Pages 部署。`examples/review/` 的模型及报告由本项目生成，未引入外部样例。`scripts/review-cases.cjs` 记录确定性构造方法和实际 CLI 输出。


## 浏览器分发补充

网页包含 MoonBit core 编译代码；完整上游许可及附带声明保存在 web/licenses/moonbit-core.LICENSE 和 web/licenses/moonbit-core.NOTICE，构建时随站点复制，保留其中第三方来源及免责声明。网页界面和示例模型由本项目编写。


## 模型实测语料补充（2026-10-21）

`examples/corpus/` 的解析模型由本项目独立构造，采用 Apache-2.0，生成脚本为 `scripts/model-builders.cjs`。这不覆盖下面的第三方内容。

`examples/external/` 收录 Ghostkeeper / SlicerTestModels contributors 的 CC0-1.0 CAD 源码、从这些源码导出的 STL / OBJ，以及 Cura 4.2 / 4.5 工程和分组 3MF。固定上游提交为 `e1bbc8eec047c2fb604b71f7e4793c3e0189fd6d`。完整 CC0 法律文本（含权利放弃、后备许可、限制和免责声明）随附于 [SlicerTestModels.CC0-1.0.txt](examples/external/licenses/SlicerTestModels.CC0-1.0.txt)，上游 README 许可说明也保留。导出及重组凹多边形面等改动逐文件注明，不把所有文件一概标成“原样收录”。

`examples/external/kinect-scan.3mf` 来自 3MF Consortium，固定上游提交 `665e20dc4d7777fd4c9702bca86a2d4028440337`，原样收录，BSD-2-Clause，Copyright (c) 2018, 3MF Consortium。完整版权、两条条件及免责声明见 [3MFConsortium.BSD-2-Clause.txt](examples/external/licenses/3MFConsortium.BSD-2-Clause.txt)。独立转换的 PLY 仅提取几何并写入忽略目录 `_build/corpus/`，原 BSD 声明保留在 PLY header 和来源记录中。

逐文件作者、来源 URL、许可证、SHA-256 和修改说明见 [manifest.json](examples/external/manifest.json)，实测及边界统一见 [COMPARISON.md](COMPARISON.md)。OpenSCAD 2021.01 仅作为本地 GPL-2.0 导出工具执行，不分发其程序或代码。未收录上游库中许可来源难以逐项核实的其他模型。
