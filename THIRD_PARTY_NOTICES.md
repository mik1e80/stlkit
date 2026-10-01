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
[README](README.md#参考了-trimesh-哪些设计) 和 [COMPARISON.md](COMPARISON.md)。

因为它没有代码进入本项目，MIT 许可证的条款不触发；这里列出是为了如实说明设计来源。

---

## 3. 第三方依赖

`moon.mod` 里声明的依赖，各自的许可证以它们自己的仓库为准：

| 依赖 | 用途 | 许可证 |
| --- | --- | --- |
| `hustcer/fzip` | 解 ZIP（3MF 用） | Apache-2.0 |
| `Milky2018/xml` | 解 XML（3MF 用） | Apache-2.0 |
| `moonbitlang/x` | 读文件、设退出码（命令行用） | Apache-2.0 |
| `moonbitlang/async` | 分块读文件（只有 `--bench` 用） | Apache-2.0 |
