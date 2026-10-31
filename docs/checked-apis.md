# 0.2.1 受检接口与迁移

安装 `moon add mik1e80/stlkit@0.2.2`，在包的 moon.pkg 中导入 `mik1e80/stlkit`。完整签名以 [生成接口](../pkg.generated.mbti) 为准；[最小可执行调用](../README.mbt.md#最小库调用) 与独立 consumer 会检查真实发布包。

| 接口 | 参数及返回 | 失败与边界 |
| --- | --- | --- |
| `validate_checked(mesh, tolerance)` | `Result[ValidationReport, String]`；容差单位 mm，0 为精确坐标 | 负值、NaN、Infinity 或非有限顶点拒绝；正值仍为坐标格子量化，不是距离邻域搜索 |
| `repair_checked(mesh, options, limits=RepairLimits::default())` | `Result[RepairResult, String]`；成功结果含网格与修改计数 | 不修改原输入；非法参数、分支/非流形边界、非简单/非平面环及超预算拒绝，不返回部分修复 |
| `write_stl_binary_checked(mesh)` | `Result[Bytes, String]` | 拒绝非有限坐标、Float32 溢出及量化新增退化/反向面；不保证全部拓扑保真，仍须重读检查 |
| `render_svg_checked(mesh, options, max_faces=20000, max_output_bytes=8000000)` | `Result[String, String]`；属性转义；超出面数采用确定性预览抽样并标注 | 校验绘图参数及选中顶点；最多允许 20000 面、16 MB 输出限额，输出限额在有界构造后检查，不等于进程内存上限 |
| `check_thickness_area_weighted(mesh, samples, seed=0)` | `ThicknessReport`；面积加权的确定性表面采样 | 从表面排除来源面查询；samples ≤ 0 或空网格不命中。命中为 0 表示不可评估，不表示真实厚度为 0 |

RepairLimits 默认 `max_faces=2000000`、`max_boundary_edges=10000`、`max_hole_vertices=512`、`max_holes=128`。面数包含补洞新增面；每洞顶点上限最多可设 4096。它是工作预算，不提供运行时间或内存硬保证。

PreviewOptions 要求宽高 1–16384、有限 yaw/pitch、有限且 0–256 的 stroke_width；stroke 长度最多 128 且无控制字符。已验证的字符串属性会转义 XML 特殊字符。

旧函数签名保留：`repair` 遇到拒绝条件时返回未修改快照与零修改计数；需要知道原因应迁移到 `repair_checked`。旧 `render_svg` 失败返回安全常量注释，需要知道原因使用 `render_svg_checked`。底层 `write_stl_binary` / `write_ply_binary` 仍为未受检编码器，应用优先采用受检导出。

兼容性变化包括：OBJ 不支持的点/线/曲面几何明确拒绝；PLY 重复属性/索引别名及超过 65536 字节 header 拒绝；3MF 要求唯一有序 mesh 容器，镜像调整绕向并保持源体积符号，奇异或方向不可可靠判定的变换拒绝。非法容差和不安全补洞不再被当作成功操作。ray_cast 返回归一化方向下的真实几何距离。详见 [格式边界](format-compatibility.md) 与 [发布说明](releases/0.2.1.md)。

质量属性需要非空、闭合、无退化面、绕向及分量方向可靠，并通过必要数值检查；不是无自交证明。厚度是首命中采样距离，不是全局壁厚保证。BVH、自相交、非流形顶点、完整材质与属性保留仍未实现。
