# 3MF 几何读取回归样例

这 13 个文件来自 [3MFConsortium/3mf-samples](https://github.com/3MFConsortium/3mf-samples) 的 `validation tests/_archive/3mf-Verify/MUSTPASS/` 目录，原样收录，采用 **BSD-2-Clause**（Copyright © 2018, 3MF Consortium）。本批逐字节核对到上游提交 `665e20dc4d7777fd4c9702bca86a2d4028440337`；这是内容核验锚点，不冒充最初下载日期或提交。连同根目录 4 个官方样例的固定路径、Git blob 与 SHA-256 见 [17 文件清单](../third-party-manifest.json)。完整版权、许可条件与免责声明见 [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)；运行 `moon run scripts/check-third-party.mbtx` 可复核本地文件哈希、完整许可和浏览器声明链接。

本项目用它们验证已支持的**几何读取路径**，包括部件关系、命名、单位、build 引用与组件变换。读取成功不表示通过完整的 3MF 一致性认证，也不证明正确处理所有扩展、颜色、材质或制造语义。

## 运行

```bash
for f in examples/conformance/*.3mf; do
  moon run cmd/main "$f" || exit 1
 done
```

普通报告模式允许输出有网格警告的文件。要对报告中的复核问题使用非零退出码，可加 `--strict`；这与格式读取测试目的不同。

## 检查方向

| 文件 | 几何读取关注点 |
| --- | --- |
| `Chapter2.1_PartsRelationships` | 按包关系定位模型部件 |
| `Chapter2.2_PartNaming` | 模型部件命名 |
| `Chapter2.3a_IgnorableMarkup` | 含无关标记的输入 |
| `Chapter3.2b_UnitsMeasurementMM` | 声明单位 |
| `Chapter3.2c_MultipleItemsTransform` | 多个 build item 的变换 |
| `Chapter3.4.1c_MustIgnoreUndefinedMetadataName` | 含未定义 metadata 的输入 |
| `Chapter3.4.2_MetaData_Resources_Build` | metadata / resources / build 结构 |
| `Chapter3.4.3a_MustNotOutputNonReferencedObjects` | 只提取被 build 引用的对象 |
| `Chapter4.1_ExplicitSupport` | 带支撑对象的几何提取 |
| `Chapter4.2_Components` | 组件引用与变换合成 |
| `Chapter5.1a_MaterialResources_CompositeAndMultiProperties` | 带材料属性的几何 |
| `Chapter5.1b_MaterialResources_MultiObjects` | 带材料属性的多对象几何 |
| `Chapter5.1c_MaterialResources_sRGB_RGB_Colors` | 带颜色属性的几何 |

材料和颜色目前不进入 `Mesh`，支撑对象也会作为三角形提取；报告不能据此判断支撑设计或多材料打印是否正确。库支持 micron / millimeter / centimeter / inch / foot / meter 的几何单位换算，未识别的单位报错。
