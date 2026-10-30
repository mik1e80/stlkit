// 给网页用的导出层。
//
// 这一层不做任何网格处理，只负责把库的 `Result` 翻译成 JavaScript 接得住
// 的形状，再把结果排成好解析的文本。转换逻辑全在 mik1e80/stlkit 里。
//
// 文件字节用 base64 传：JS 那边把 FileReader 读到的 ArrayBuffer 编成
// base64 字符串，这边解回字节。走字符串是因为 MoonBit 的 Bytes 过不了
// JS 边界（它是编译器的内部表示），而字符串两边都认。

///|
priv struct WebLimits {
  mut input_bytes : Int32
  mut triangles : Int32
}

///|
let settings : WebLimits = { input_bytes: 67108864, triangles: 2000000, }

///|
/// Configure the next local analysis. Empty means success; rejected settings
/// leave the previous valid configuration intact. Other library budgets apply.
pub fn configure_limits(
  max_input_bytes : Int32,
  max_triangles : Int32,
) -> String {
  if max_input_bytes < 1 || max_triangles < 1 || max_triangles > 715827882 {
    return "资源上限必须为正整数，三角形上限不能超过 715827882"
  }
  settings.input_bytes = max_input_bytes
  settings.triangles = max_triangles
  ""
}

///|
fn web_limits() -> @stlkit.ParseLimits {
  {
    ..@stlkit.ParseLimits::default(),
    max_input_bytes: settings.input_bytes,
    max_triangles: settings.triangles,
  }
}

///|
/// 分析一个模型文件，返回一份「每行一个 `字段|值`」的报告。
///
/// 为什么不用 JSON：库这边没有公开的 JSON 造值构造器（core/json 只有
/// as_xxx 取值的），手拼 JSON 还要处理转义。而这个报告只有数字和几个
/// 固定的中文标签，用竖线分隔足够，JS 那边 split 两下就解开了。
///
/// 失败时返回空串，具体原因问 `analyze_error`。
pub fn analyze(file_base64 : String) -> String {
  analyze_with_threshold(file_base64, 0.8)
}

///|
pub fn analyze_with_threshold(
  file_base64 : String,
  min_thickness : Double,
) -> String {
  match analyze_inner(file_base64, min_thickness) {
    Ok(lines) => lines.join("\n")
    Err(_) => ""
  }
}

///|
/// 同样的输入会产生的错误信息；分析成功时返回空串。
///
/// 和 `analyze` 拆成两个函数是因为 `Result` 过不了 JavaScript 边界——
/// 调用方看到 `analyze` 返回空串时再来问一次原因即可。
pub fn analyze_error(file_base64 : String) -> String {
  match analyze_inner(file_base64, 0.8) {
    Ok(_) => ""
    Err(msg) => msg
  }
}

///|
/// 把模型渲染成一张 SVG 图。出错时返回空串。
///
/// 特意**不**把错误信息拼进返回值里。解析错误的文案里可能带上文件里的
/// 原文（比如 OBJ 报「『xxx』不是合法的编号」），那是不受信任的内容，
/// 拼成 HTML 塞进页面就等于开了个注入口子。错误信息交给调用方用
/// textContent 显示。
pub fn preview(file_base64 : String) -> String {
  match analyze_mesh(file_base64) {
    Ok(mesh) => @stlkit.render_svg(mesh, preview_options())
    Err(_) => ""
  }
}

///|
/// 网页用的渲染尺寸。比库的默认值大一些，因为页面上展示得比较宽。
fn preview_options() -> @stlkit.PreviewOptions {
  { ..@stlkit.PreviewOptions::default(), width: 640, height: 480, }
}

///|
/// 解码 + 解析，返回网格。
fn analyze_mesh(file_base64 : String) -> Result[@stlkit.Mesh, String] {
  let data = decode(file_base64)
  match data {
    Err(msg) => Err(msg)
    Ok(data) => @stlkit.parse_mesh(data, limits=web_limits())
  }
}

///|
// Keep the existing 1000 samples for small models; explicitly report reduced
// budgets on larger models. This limits ray/face work, not total running time.
fn web_samples(mesh : @stlkit.Mesh) -> Int32 {
  (20000000 / mesh.triangle_count().max(1)).min(1000).max(1)
}

///|
/// 真正的分析逻辑。
fn analyze_inner(
  file_base64 : String,
  min_thickness : Double,
) -> Result[Array[String], String] {
  let data = match decode(file_base64) {
    Ok(data) => data
    Err(msg) => return Err(msg)
  }
  let mesh = match @stlkit.parse_mesh(data, limits=web_limits()) {
    Ok(mesh) => mesh
    Err(msg) => return Err(msg)
  }
  let samples = web_samples(mesh)
  let review = @stlkit.check_printability(mesh, min_thickness, samples~)
  let numeric_failure = review.mass_properties_available() &&
    !mesh.mass_properties_numeric_valid()
  let check = review.validation

  let lines : Array[String] = []
  lines.push("采样预算|\{samples}")
  lines.push("格式|\{format_name(data)}")
  lines.push("三角形|\{mesh.triangle_count()}")
  lines.push("顶点|\{check.raw_vertex_count}")
  lines.push("去重顶点|\{check.unique_vertex_count}")
  match mesh.bounding_box() {
    Some(box) => {
      let size = box.size()
      lines.push(
        "包围盒|\{round3(size.x)} × \{round3(size.y)} × \{round3(size.z)}",
      )
    }
    None => ()
  }
  // 定向包围盒：斜着摆的模型用轴对齐的盒子量会虚胖，这个贴着模型走
  match mesh.oriented_bounding_box() {
    Some(obb) => {
      let size = obb.size()
      lines.push(
        "定向包围盒|\{round3(size.x)} × \{round3(size.y)} × \{round3(size.z)}",
      )
    }
    None => ()
  }
  lines.push("体积|\{round3(mesh.volume())}")
  lines.push("体积朝向已复核|\{review.winding.orientation_reliable()}")
  lines.push("表面积|\{round3(mesh.surface_area())}")
  // 几块互不相连的几何。大于 1 说明打出来是几个独立的零件
  lines.push("零件|\{@stlkit.count_parts_default(mesh)}")
  // 欧拉数的原有显示条件；质量属性另用共享的完整前提检查。
  if check.is_watertight() && review.winding.orientation_reliable() {
    lines.push("欧拉数|\{check.euler_number()}")
  }
  if review.mass_properties_available() && !numeric_failure {
    lines.push("质量属性|已评估（满足当前检查前提）")
    let c = mesh.center_mass()
    lines.push("重心|\{round3(c.x)}, \{round3(c.y)}, \{round3(c.z)}")
    let pm = mesh.principal_moments()
    lines.push(
      "主惯量|\{round3(pm[0])} / \{round3(pm[1])} / \{round3(pm[2])}",
    )
  } else {
    // 不在数值字段中混入状态文本，调用方可继续按数值字段是否存在判断。
    lines.push("质量属性|未评估")
    lines.push(
      "质量属性前提|需非空、闭合、无退化面、绕向一致且分量朝向可靠（无潜在嵌套或重叠）",
    )
  }
  match review.thickness {
    Some(thick) =>
      if thick.hits > 0 {
        lines.push("采样最小厚度|\{round3(thick.min_thickness)}")
        lines.push("壁厚采样|\{thick.samples}")
        lines.push("壁厚命中|\{thick.hits}")
      }
    None => ()
  }
  lines.push("负体积分量|\{review.inward_component_count()}")
  lines.push("绕向分量数|\{review.winding.components.length()}")
  for component in review.winding.components {
    lines.push(
      "分量\{component.index}|\{component.faces.length()} 面；有符号体积 \{round3(component.signed_volume)} mm³；\{component.orientation.label()}；闭合 \{component.closed}；绕向一致 \{component.consistent}；可能嵌套或重叠 \{component.potentially_nested}",
    )
  }
  lines.push("薄壁|\{if review.thin_wall() { 1 } else { 0 }}")
  lines.push(
    "壁厚未评估|\{if review.thickness_unavailable() { 1 } else { 0 }}",
  )
  lines.push("壁厚阈值|\{min_thickness}")
  lines.push("需复核|\{review.needs_review() || numeric_failure}")
  lines.push(
    "结论|\{if numeric_failure { "质量属性数值异常，需要复核；不构成可打印结论。" } else { review.verdict() }}",
  )
  lines.push("工艺范围|\{@stlkit.review_scope()}")
  lines.push("水密|\{check.is_watertight()}")
  lines.push("边界边|\{check.boundary_edge_count}")
  lines.push("非流形边|\{check.non_manifold_edge_count}")
  lines.push("退化面|\{check.degenerate_count}")
  lines.push("错误法线|\{check.wrong_normal_count}")
  // 绕向和法线是两回事：法线可以按错误的绕向重算成「自洽」的，
  // 绕向才是几何本身对不对
  let winding = review.winding
  lines.push("绕向反了|\{winding.flipped_faces}")
  Ok(lines)
}

///|
/// 判断格式，给网页显示用。跟 CLI 里的逻辑一致。
fn format_name(data : Bytes) -> String {
  match @stlkit.detect_format(data) {
    @stlkit.Binary => "二进制 STL"
    @stlkit.Ascii => "ASCII STL"
    @stlkit.ThreeMF => "3MF"
    @stlkit.Ply => "PLY"
    @stlkit.Obj => "OBJ"
    @stlkit.Unknown => "未知格式"
  }
}

///|
/// 把 base64 解成字节，失败时给中文错误。
fn decode(file_base64 : String) -> Result[Bytes, String] {
  if file_base64.length().to_int64() >
    (settings.input_bytes.to_int64() + 2L) / 3L * 4L {
    return Err("resource_limit: max_input_bytes (max=\{settings.input_bytes})")
  }
  if file_base64.length() == 0 {
    return Err("没有收到文件内容")
  }
  let bytes = @base64.decode(file_base64) catch {
    _ => return Err("文件内容解码失败，可能上传时出错了")
  }
  if bytes.length() > settings.input_bytes {
    return Err("resource_limit: max_input_bytes (max=\{settings.input_bytes})")
  }
  Ok(bytes)
}

///|
/// 保留三位小数。网格数据本身带浮点误差，多显示的位数没有意义。
fn round3(value : Double) -> String {
  let rounded = (value * 1000.0).round() / 1000.0
  rounded.to_string()
}

// ── 修复 ────────────────────────────────────────────────────────────────
//
// 又拆成几个函数，理由和前面一样：Result 过不了 JS 边界。

///|
/// 修一遍网格，返回「每行一个 `字段|值`」的修复报告。失败返回空串。
///
/// 报告里除了「做了什么」，还带上修复前后的边界边数——只报「修复完成」
/// 没法让人判断到底修好了没有，显示「3 → 0」才叫证据。
pub fn fix_report(file_base64 : String) -> String {
  fix_report_with_threshold(file_base64, 0.8)
}

///|
pub fn fix_report_with_threshold(
  file_base64 : String,
  min_thickness : Double,
) -> String {
  match repair_of(file_base64) {
    Err(_) => ""
    Ok(result) => {
      let review = @stlkit.check_printability(
        result.mesh,
        min_thickness,
        samples=web_samples(result.mesh),
      )
      let numeric_failure = review.mass_properties_available() &&
        !result.mesh.mass_properties_numeric_valid()
      let after = review.validation
      let lines : Array[String] = []
      lines.push(
        "修复后需复核|\{review.needs_review() || numeric_failure}",
      )
      lines.push(
        "修复后结论|\{if numeric_failure { "质量属性数值异常，需要复核；不构成可打印结论。" } else { review.verdict() }}",
      )
      lines.push("可修复|\{result.changed()}")
      lines.push("删退化面|\{result.removed_degenerate}")
      lines.push("删重复面|\{result.removed_duplicates}")
      lines.push("补洞新增|\{result.added_triangles}")
      lines.push("重算法线|\{result.recomputed_normals}")
      lines.push("翻转绕向|\{result.flipped_faces}")
      lines.push("整体翻转分量|\{result.reoriented_components}")
      lines.push("修复后体积|\{round3(result.mesh.volume())}")
      lines.push("修复后水密|\{after.is_watertight()}")
      lines.push("修复后边界边|\{after.boundary_edge_count}")
      lines.push("修复后三角形|\{result.mesh.triangle_count()}")
      lines.join("\n")
    }
  }
}

///|
/// 修复后的模型导出成二进制 STL，再用 base64 编成字符串交给 JS。
///
/// 走 base64 是因为 Bytes 过不了 JS 边界；JS 那边解回字节就能做成
/// 下载链接。失败返回空串。
pub fn fixed_stl(file_base64 : String) -> String {
  match repair_of(file_base64) {
    Err(_) => ""
    Ok(result) =>
      match @stlkit.write_stl_binary_checked(result.mesh) {
        Ok(bytes) => @base64.encode(bytes)
        Err(_) => ""
      }
  }
}

///|
/// 修复后的模型的预览图。失败返回空串。
pub fn fixed_preview(file_base64 : String) -> String {
  match repair_of(file_base64) {
    Err(_) => ""
    Ok(result) => @stlkit.render_svg(result.mesh, preview_options())
  }
}

///|
/// 修复失败的原因；成功时返回空串。
pub fn fix_error(file_base64 : String) -> String {
  match repair_of(file_base64) {
    Ok(_) => ""
    Err(msg) => msg
  }
}

///|
/// 解码 + 解析 + 修复。三个修复相关的导出函数都要走这条链路，
/// 抽出来免得写三遍。
fn repair_of(file_base64 : String) -> Result[@stlkit.RepairResult, String] {
  let mesh = match analyze_mesh(file_base64) {
    Ok(mesh) => mesh
    Err(msg) => return Err(msg)
  }
  let repaired = @stlkit.repair(mesh, @stlkit.RepairOptions::default())
  let bytes = match @stlkit.write_stl_binary_checked(repaired.mesh) {
    Ok(bytes) => bytes
    Err(message) => return Err(message)
  }
  let restored = match @stlkit.parse_mesh(bytes, limits=web_limits()) {
    Ok(restored) => restored
    Err(message) => return Err("导出数据无法重读：" + message)
  }
  Ok({ ..repaired, mesh: restored, })
}
