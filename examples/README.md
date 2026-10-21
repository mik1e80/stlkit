# 示例模型

这些文件用于演示和回归检查。解析成功与网格检查结果是两回事；检查结果也不能保证打印成功。

## 自建模型

| 文件 | 内容 | 检查用途 |
| --- | --- | --- |
| `cube.stl` / `cube.obj` | 单位立方体 | 比较两种格式的几何统计，体积 1、表面积 6 |
| `broken.stl` | 立方体缺一个三角形 | 检查 3 条边界边及简单三角洞修复 |
| `flipped.stl` | 一个面绕向相反的立方体 | 检查局部绕向；边闭合不代表绕向正确 |
| `torus.stl` / `torus.obj` | 48×24 段的圆环，2304 个三角形 | 格式对照、曲面离散误差与 SVG 预览 |

## 3MF 官方样例

`box.3mf`、`torus.3mf`、`multiple_cylinders.3mf`、`cube_gears.3mf` 来自 [3MFConsortium/3mf-samples](https://github.com/3MFConsortium/3mf-samples)，原样收录。另有 13 个文件放在 [conformance/](conformance/README.md)。

这些 17 个文件采用 **BSD-2-Clause**（Copyright © 2018, 3MF Consortium）。完整版权声明、两条许可条件及免责声明见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。

| 文件 | 三角形数 | 检查用途 |
| --- | --- | --- |
| `box.3mf` | 12 | 10×20×30 长方体，体积约 6000 mm³ |
| `torus.3mf` | 2200 | 闭合圆环几何 |
| `multiple_cylinders.3mf` | 528 | 同一对象被 6 个 build item 引用并分别变换 |
| `cube_gears.3mf` | 25692 | 多对象模型及网格问题报告 |

`cube_gears.3mf` 在本工具的容差焊接和检查规则下会报告网格问题。仅凭这些结果，不能排除容差、解析或检查算法的影响，也不能直接断言上游文件有缺陷。

## 运行

```bash
moon run cmd/main examples/torus.stl
moon run cmd/main examples/torus.stl --svg torus.svg
moon run cmd/main examples/broken.stl --fix fixed.stl
moon run cmd/main examples/box.3mf
```

也可将文件拖入 [网页版](https://mik1e80.github.io/stlkit/)。壁厚提醒默认按 0.8 mm 参考值判断，单位立方体等演示模型并不代表实际打印尺寸。

## 如何解释数值

圆环的解析统计与连续曲面的理论值会有差别，因为输入是有限个平面三角形。两种格式的数据对照可以用于回归验证，但不能单凭几个总量相同证明所有几何算法正确。

对于单个闭合、可定向的流形表面，欧拉示性数为 `V−E+F=2−2g`。多个独立表面应相加；网格存在边界、非流形关系或焊接改变连接关系时，需要另行解释。内部网格分析按坐标容差重建顶点关系，不保留 3MF 原始顶点身份。


## 格式识别回归样例

- `long-header.stl`：自建单位立方体，solid 名称为 2048 个 x，facet 位于 512 字节后；自动读取应显示 ASCII STL、12 个三角形、体积 1。
- `obj-stl-keywords.obj`：自建立方体，在注释与对象名称中出现 solid/facet/vertex；应显示 OBJ、12 个三角形、体积 1。

二者可直接交给 CLI 或拖入网页；输入后缀不参与格式判断。


模型实测、失败反馈、外部来源与许可证、薄壁采样和 100k/500k/1m 大文件结果统一见 [COMPARISON.md](../COMPARISON.md)。完整原始输出和命令可逐项复核；解析成功不等于网格或工艺通过。
