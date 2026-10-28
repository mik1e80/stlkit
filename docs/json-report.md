# JSON 检查协议 v1

0.2.0 新增库接口 `inspection_json(mesh, format=Obj, min_thickness=0.8, samples=1000)` 和 CLI `--json`。库返回 `Result[Json, String]`；非法选项或手工网格中的非有限坐标/法线报错。CLI 标准输出恰好一个 JSON 文档，运行时不夹带中文报告。下面从源码克隆目录执行，完整模型语料不随 Mooncakes 库包安装。

```sh
moon run cmd/main examples/cube.obj --json --samples 32 --min-thickness 0 --strict
moon run cmd/main examples/broken.stl --json --strict
moon run scripts/json-smoke.mbtx
```

成功读取并生成报告时 `ok=true`；发现几何问题仍是成功报告，须检查 `review.needs_review`。不要用 `ok` 判断模型可打印。JSON v1 不与 `--fix`、`--svg`、`--bench`、`--stream-only` 或 `--help` 组合，组合请求在读写模型前失败。其他现有中文 CLI 行为和退出码保持原样。

## 顶层与字段

| 字段 | 类型与含义 |
| --- | --- |
| schema_version | 整数 1，成功和错误文档都有 |
| ok | 布尔值；报告 true，参数/读取/解析/执行错误 false |
| input | 成功报告对象，含 format、coordinate_units、unit_interpretation |
| geometry | 成功报告的三角形/顶点计数、面积、条件体积与包围盒 |
| validation | 成功报告的有限网格诊断计数和布尔状态 |
| mass_properties | 质量属性状态、重心和 9 个按行排列的惯量分量 |
| thickness | 采样状态、请求预算、实际样本、命中和距离 |
| review | needs_review、numeric_failure、printability_certified=false、min_thickness_mm、scope |
| path / scenario | 仅 CLI 添加；库接口没有这两个字段 |
| error | 仅错误文档添加，含 code、message、format、location |

`format` 的稳定标识为 `stl-ascii`、`stl-binary`、`obj`、`ply`、`3mf`、`unknown`；它描述路由/调用方标记，不证明完整格式符合性。坐标单位是 `mm`：3MF 已按声明换算（`converted_from_3mf_unit`），其他输入是需调用方确认的假设（`assumed_mm_confirm_scale`）。库接口不做重新缩放，format 参数需由调用方正确填写。

`geometry`：`triangles/raw_vertices/unique_vertices` 为整数；`surface_area_mm2` 为有限数或 null；`volume_mm3` 只有在已覆盖质量属性前提和数值检查通过时为有限数，否则 null；`aabb_mm` 为空网格时 null，否则 `{min:[x,y,z], max:[x,y,z]}`。

`validation`：`boundary_edges/non_manifold_edges/degenerate_faces/opposed_declared_normals/euler_number/flipped_faces/inward_components` 为整数；`winding_consistent/orientation_reliable` 为布尔值。欧拉数不是流形或无自相交证明；声明法线检查仍仅覆盖方向相反的已保留面法线。

`mass_properties.status`：`available`、`not_evaluated`、`non_finite`。不可用时 `center_of_mass_mm`、`inertia_density_one` 都为 null；可用时分别是 3 / 9 个有限数。惯量的材料密度数值固定为 1，不代表已知实际材料密度或质量单位。条件体积与这些状态一起解释。

`thickness.status`：`sample_estimate`、`not_evaluated`、`no_hits`、`non_finite`。`requested_samples/samples/hits` 为整数；有效命中时 `min_mm/mean_mm` 为有限数，否则 null。`global_minimum_certified` 恒 false。参考阈值须非负有限，样本预算 1..100000；预算不保证覆盖全部面。

`scenario` 包含 `nozzle_mm`（正有限数或 null）、`supports`（on/off/unknown）、`process_assessed=false`。仅记录用户设置，不增加工艺判定能力。

**null 表示未评估、不可用或非有限计算，0 表示实际数值零。** 不输出 NaN/Infinity；计算溢出用 null 并令 `numeric_failure=true`、`needs_review=true`。这些检查仍不证明无自相交，也不构成可打印认证。

## JSON 模式退出码

| 码 | 行为 |
| ---: | --- |
| 0 | 成功报告；普通模式即使 needs_review=true 也为 0 |
| 2 | 参数错误、缺文件参数或不支持的组合，ok=false |
| 3 | 文件读取/解析/资源限额失败，ok=false |
| 4 | `--strict` 成功生成报告但 needs_review=true，ok=true |
| 5 | 检查执行失败或意外内部错误，ok=false |

错误码包括 `invalid_arguments/input_read_error/inspection_error/internal_error` 和下述解析码。message 是供人阅读的诊断，不是稳定枚举。CLI 自身 stdout 遵守协议；使用 `moon run` 时工具链构建信息可能出现于 stderr，自动化可先编译再执行真实二进制。

## 结构化解析错误

`parse_mesh_checked(data, limits=...) -> Result[Mesh, ParseError]` 是新增接口，旧 `parse_mesh` 等 `Result[..., String]` 接口保留。四类：

- `InvalidLimits` / `invalid_limits`：配置不合法。
- `ResourceLimitExceeded` / `resource_limit`：本库 ParseLimits 预算超限；fzip 自身安全硬限制等底层拒绝仍保留为 InvalidData，暂不推测细分类别。
- `UnknownFormat` / `unknown_format`：无已知内容提示且回退解析失败，不猜测受支持格式。
- `InvalidData` / `invalid_data`：有内容提示但解析失败；error.format 给出路由格式。

`code()` 返回稳定类别，`message()` 保留诊断，`to_json()` 返回错误对象。位置目前统一为 null；不会按中文字符串猜测 InvalidIndex、InvalidHeader 或行号。资源分类只识别内部 `resource_error()` 生成的保留前缀，普通用户 token 不会直接成为该前缀。未知格式回退遇到这种预算错误时提前返回，避免掩盖超限。

协议升级：v1 可以增加字段，调用方应忽略未知字段；删除字段、改变现有字段类型/含义需提高 schema_version。API enum 使用通配分支，以便未来扩展类别。原始 message 与具体浮点小数文本不承诺逐字稳定。
