# 解析资源预算（0.1.5）

未发布验收修订另对 CLI 厚度分析设置 `面数 × 样本数 ≤ 20000000`：超限时中文入口返回 1，JSON 返回 `resource_limit` / 退出 3，并提示减小 `--samples`；不会悄悄改变 CLI 的请求数。网页使用 `min(1000, floor(20000000 / 面数))` 作为样本预算并显示。它不是 `ParseLimits` 字段，不覆盖解析、拓扑或修复成本，不保证总运行时长；直接库接口仍由调用方控制分析预算。

所有解析入口默认使用 `ParseLimits::default()`。旧调用方式继续有效；大输入可能因新默认预算而失败，调用方可以显式调整 `limits`。这些是输入、分配和工作计数的上限，**不是进程内存、运行时间或恶意文件安全性的保证**。几何分析、修复、报告和导出不受解析预算统一管理；对不可信输入仍应在可终止、有限内存的独立进程中运行。

```moonbit
let limits = { ..@stlkit.ParseLimits::default(), max_triangles: 100000 }
let result = @stlkit.parse_mesh(data, limits~)
let scanner = @stlkit.StlScanner::new(limits~)
```

| 字段 | 默认值 | 计数含义 |
| --- | ---: | --- |
| max_input_bytes | 67,108,864 | 64 MiB 原始输入；String 入口按 UTF-8 编码长度计数 |
| max_vertices | 6,000,000 | STL 原始面角数（3×面数）；OBJ 的 v/vn/vt 声明总数；PLY / 3MF 的顶点声明总数 |
| max_triangles | 2,000,000 | 三角化后的面数；3MF 同时限制原始声明和实例展开后的总面数 |
| max_list_items | 8,000,000 | OBJ 面引用、PLY 所有 list（包括丢弃属性）累计项数 |
| max_polygon_vertices | 1,024 | 单个 OBJ / PLY 多边形角数，在三角化前拒绝超限 |
| max_uncompressed_bytes | 104,857,600 | 3MF ZIP 所有条目的声明解压字节数之和 |
| max_zip_entries | 4,096 | 3MF ZIP 条目数 |
| max_component_depth | 32 | 3MF 组件引用深度 |
| max_component_instances | 100,000 | 3MF 实例展开的累计对象访问数，包括空几何 |
| max_records | 4,000,000 | 文本换行数和空白分隔 token 数分别受限；PLY 另限制全部元素记录总数；XML 每个解析文档的事件数 |
| max_line_bytes | 1,048,576 | STL / OBJ / ASCII PLY 单行 UTF-8 字节数 |
| max_xml_depth | 128 | 模型及严格模式 OPC XML 层级深度，包括空元素 |

CR 和 LF 分别计入文本换行预算。OBJ 的 UV、法线虽不完整保留在 Mesh 中，也消耗声明预算。3MF 未引用对象同样消耗声明预算；反复引用小对象不能绕过输出面数和实例访问数限制。零值合法，表示不允许消费相应资源；组件和 XML 深度最多 128，三角形预算最多 715,827,882，其余字段不得为负。

STL / PLY 字节入口在解码前检查输入量，文本入口在拆行、拆 token 前扫描预算。PLY 对没有属性的未知元素也检查记录数，防止零字节记录导致长循环。3MF 先读 ZIP 元数据、核对总声明大小和条目数，再解压；解压器开启 CRC 校验。上游 fzip 0.8.7 另有 100 MiB 总解压硬上限，调高本库预算不取消上游限制。ZIP 元数据列表本身仍由上游创建，不能将预检宣传为“完全不分配内存”。

兼容选项 `lenient_ascii=true`、`compatibility=true` 仍受资源限制。调高预算不放宽格式语法、索引、非有限数或 CRC 检查。超限说明包含 `resource_limit:`，配置错误包含 `invalid_limits:`；STL 自动入口和未知格式回退可能在前面附加解析上下文。其后的说明用于诊断，旧 `Result[..., String]` API 保留，不应把整段文字作为稳定错误枚举。

## CLI

```sh
moon run cmd/main examples/cube.obj --max-input-bytes 1048576 --max-triangles 10000
moon run cmd/main examples/box.3mf --max-uncompressed-bytes 1048576
moon run cmd/main examples/review/cubes-1.stl --stream-only --max-vertices 100000
```

四个选项均接受非负 Int32。CLI 先检查文件大小，再分配整文件缓冲区；分块扫描检测到失败后停止读文件。文件在读取过程中缩短也会失败。`StlScanner::error()` 可用于尽早结束读取；仍必须调用 `finish()` 才能验证完整文件。扫描器超限后保持失败状态，不接收新的有效结果。

## 网页

界面可设置文件字节数和三角形上限，应用于下一次选文件。先检查浏览器 File.size，再读取文件；MoonBit 导出入口也在 base64 解码前检查编码长度，解码后复核实际大小。其他预算仍独立采用默认值。`configure_limits(bytes, triangles)` 成功返回空串，失败返回说明且保留原设置。网页尚未使用 Worker，资源限制不能替代取消操作或响应性保证。

## 验证

`parse_limits_wbtest.mbt` 覆盖各格式边界、重复展开、空元素、深度、CRC、配置错误及提高预算后仍拒绝非法输入；`web/limits_wbtest.mbt` 验证设置接口。真实 CLI 通过 `moon run scripts/limits-smoke.mbtx` 检查超限、参数错误及正向边界。变异测试方法见 [fuzz-testing.md](fuzz-testing.md)。

## 浏览器独立预算与三角化工作量

0.2.3 候选将浏览器默认输入设为 16 MiB，硬上限 32 MiB、500000 个三角形；设置不能放宽此上限。JS 在读取前按 File.size 检查，读取后按实际 buffer 大小再次检查，MoonBit 在 Base64 解码前后再检查。解析顶点预算最多为请求面数的三倍。Base64、字符串、网格和临时结构同时占内存；该上限是保守工作策略，没有被包装为所有浏览器/设备上的内存安全上限。实际 UI 回归覆盖乱序成功/失败、同文件重选和大小检查；未声称完成峰值 RSS 浏览器基准。大模型请使用 CLI；当前分析仍占主线程，Worker、进度与取消尚未实现。

每个大于三点的多边形共用 2000000 次几何检查预算，覆盖非相邻边对、耳候选和阻挡顶点；超限为 resource_limit，适用于 OBJ / PLY / 补洞。可调顶点上限不是执行时间保证，工作预算也不是进程级时限。
