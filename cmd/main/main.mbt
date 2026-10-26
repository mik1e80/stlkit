// 命令行入口。
//
// 参数解析交给官方库 moonbitlang/core/argparse，文件读取交给
// moonbitlang/x/fs，退出码用 moonbitlang/x/sys。
//
// 给一个 STL / OBJ / 3MF / PLY 文件，打印它的体检报告：几何数据加四项校验结论。
// 可选 --svg 导出等轴测预览图，--fix 修复并存到指定文件。

///|
/// 命令行定义。
///
/// 和上个项目一样特意关掉 argparse 自带的 `--help`：它内部直接调 wasi 的
/// proc_exit 结束进程，退出码和输出都不受我们控制。换成一枚普通 flag
/// 自己处理，这样还能在参数表后面接一段中文示例。
fn command() -> @argparse.Command {
  @argparse.Command(
    "stlkit",
    about="STL / OBJ / 3MF / PLY 三维网格工具链——解析、校验、分析 3D 打印模型",
    positionals=[
      @argparse.PositionArg(
        "file",
        about="要处理的模型文件路径（STL / OBJ / 3MF / PLY）",
        num_args=@argparse.ValueRange(lower=0, upper=1),
      ),
    ],
    options=[
      @argparse.OptionArg(
        "nozzle",
        about="喷嘴直径（毫米），仅记录，不参与工艺判定",
      ),
      @argparse.OptionArg(
        "supports",
        about="支撑设置 on/off/unknown，仅记录，不计算支撑需求",
      ),
      @argparse.OptionArg(
        "samples",
        about="壁厚射线样本数，1..100000，默认1000",
      ),
      @argparse.OptionArg(
        "min-thickness",
        about="参考最小壁厚（毫米），默认0.8；0不设阈值",
      ),
      @argparse.OptionArg(
        "svg",
        about="导出等轴测 SVG 预览；与 --fix 同用时预览修复后的网格",
      ),
      @argparse.OptionArg(
        "fix",
        about="修复网格并存到指定文件（按后缀选格式：.stl / .obj / .ply）",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "stream-only",
        about="只分块统计二进制 STL；顶点和边记录仍增长",
      ),
      @argparse.FlagArg(
        "strict",
        about="模型有问题时以退出码 1 结束（给 CI 用）",
      ),
      @argparse.FlagArg(
        "bench",
        about="跑基准测试，对比耗时并估算主要数据字段量",
      ),
      @argparse.FlagArg("help", short='h', about="显示这份帮助"),
    ],
    disable_help_flag=true,
  )
}

// ── 基准测试 ────────────────────────────────────────────────────────────
//
// 回答一个问题：处理超大模型时，**不保留网格**能省多少。
//
// 仅估算文件及主要数据字段，不包含哈希索引、对象头、分配器和运行时开销。
// 各路径还会分配额外分析数据；这些数字不能用来计算实际内存节省比例。

///|
/// 文件与三角形坐标数据量（字节），不是完整内存占用。
///
/// - 文件字节：读进来之后一直在内存里
/// - 每个三角形是 4 个 Vec3 = 12 个 Double = 96 字节
/// 不计容器、对象头、顶点焊接与绕向分析的附加存储。
fn full_memory(file_size : Int32, triangles : Int32) -> Int64 {
  file_size.to_int64() + triangles.to_int64() * 96L
}

///|
/// 文件、顶点字段与全部边记录的数据量（字节）。
///
/// - 文件字节：整块扫描入口的输入
/// - 顶点字段：三个 Double 坐标与一个 Int 编号，28 字节/项
/// - 边记录：每个三角形存三条 UInt64，24 字节/三角形，含重复边
/// 不计坐标键标签、哈希索引、对象头、容器与分配器开销。
fn stream_memory(
  file_size : Int32,
  vertices : Int32,
  triangles : Int32,
) -> Int64 {
  file_size.to_int64() + vertices.to_int64() * 28L + triangles.to_int64() * 24L
}

///|
/// 把字节数格式化成好读的样子。
fn fmt_bytes(n : Int64) -> String {
  let mb = 1024.0 * 1024.0
  let kb = 1024.0
  let d = n.to_double()
  if d >= mb {
    "\{fmt(d / mb, 2)} MB"
  } else if d >= kb {
    "\{fmt(d / kb, 2)} KB"
  } else {
    "\{n} 字节"
  }
}

///|
/// 分块读取文件并流式扫描。
///
/// 不将完整文件读入内存；读取缓冲区固定，顶点表和边记录仍随规模增长。
///
/// 走 `moonbitlang/async/fs` 是因为 `moonbitlang/x/fs` 只有
/// `read_file_to_bytes`（一次读完），没有带偏移量的读取。
async fn scan_chunked_storage(
  path : String,
) -> Result[(@stlkit.StreamReport, @stlkit.ScanStorage), String] {
  let file = @asyncfs.open(path, mode=@asyncfs.Mode::ReadOnly) catch {
    err => return Err("打不开文件「\{path}」：\{err}")
  }
  let size = file.size() catch {
    err => {
      let _ = file.close()
      return Err("读不了文件大小：\{err}")
    }
  }
  let scanner = @stlkit.StlScanner::new()
  // 256 KB 一块。这是权衡：太小了系统调用次数多，太大了缓冲区本身占内存。
  // 关键是它**固定**——文件再大也不会变大
  let chunk = 262144
  let buf : FixedArray[Byte] = FixedArray::make(chunk, b'\x00')
  let mut pos = 0L
  let mut failure : String? = None
  while pos < size && failure is None {
    let remain = size - pos
    let want = if remain < chunk.to_int64() { remain.to_int() } else { chunk }
    let n = file.read_at(buf, position=pos, offset=0, len=want) catch {
      err => {
        failure = Some("读文件失败：\{err}")
        0
      }
    }
    if n <= 0 {
      break
    }
    // 把这一块读到的部分交给扫描器
    let part : Array[Byte] = []
    for i = 0; i < n; i = i + 1 {
      part.push(buf[i])
    }
    scanner.feed(Bytes::from_array(part))
    pos = pos + n.to_int64()
  }
  let _ = file.close()
  match failure {
    Some(msg) => Err(msg)
    None =>
      match scanner.finish() {
        Ok(report) => Ok((report, scanner.storage()))
        Err(msg) => Err(msg)
      }
  }
}

///|
async fn scan_chunked(path : String) -> Result[@stlkit.StreamReport, String] {
  match scan_chunked_storage(path) {
    Ok((report, _)) => Ok(report)
    Err(msg) => Err(msg)
  }
}

///|
async fn stream_only(path : String) -> Result[Bool, String] {
  match scan_chunked_storage(path) {
    Err(msg) => Err("分块入口只支持二进制 STL：\{msg}")
    Ok((report, storage)) => {
      println("二进制 STL 分块统计；不构造完整 Mesh")
      println(
        "三角形 \{report.triangle_count}；顶点表 \{storage.unique_vertices} 项；边记录 \{storage.edge_records} 项",
      )
      println(
        "扫描器单次缓冲峰值 \{storage.peak_buffered_bytes} 字节；残留 \{storage.pending_bytes} 字节（不是进程内存实测）",
      )
      println(
        "总存储 O(V+F+chunk)：保存全部三角形边记录，排序前包含重复边；并非固定总内存。",
      )
      println(
        "此入口未检查绕向、壁厚或工艺，不能产生可打印结论。",
      )
      Ok(false)
    }
  }
}

///|
/// 跑三种解析方式，记录耗时与主要字段数据量估算。
///
/// 估算公式见 `full_memory` / `stream_memory`，不是进程内存实测。
async fn bench(path : String) -> Result[Bool, String] {
  // ── 先做分块流式：这一步不碰整个文件，测出来的才是真流式 ──
  //
  // 分块扫描目前只支持**二进制** STL——那边每个三角形固定 50 字节，
  // 切块就是数数；ASCII 格式的记录是变长的文本行，得另写一套按行的缓冲。
  // 所以先试一下，不是二进制就跳过这一档，并在报告里说明原因，
  // 而不是让整个基准测试失败。
  let t2 = @bench.monotonic_clock_start()
  let chunked : @stlkit.StreamReport? = match scan_chunked(path) {
    Ok(r) => Some(r)
    Err(_) => None
  }
  let chunked_us = @bench.monotonic_clock_end(t2)

  // ── 后面两种都要整个文件在内存里 ──
  let data = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(msg) => return Err("读不了文件「\{path}」：\{msg}")
  }
  let file_size = data.length()

  // 本工具的流式实现仅针对 STL，不将其他格式送入 STL 扫描器。
  let format = @stlkit.detect_format(data)
  if !(format is @stlkit.Ascii) && !(format is @stlkit.Binary) {
    return Err(
      "--bench 目前只支持 STL；其他格式请不带 --bench 查看报告",
    )
  }

  // 全量：解析出完整网格，能校验、能修复
  let t0 = @bench.monotonic_clock_start()
  let mesh = match @stlkit.parse_mesh(data) {
    Ok(mesh) => mesh
    Err(msg) => return Err(msg)
  }
  let check = @stlkit.validate_default(mesh)
  let winding = @stlkit.check_winding_default(mesh)
  let full_us = @bench.monotonic_clock_end(t0)

  // 流式：不保留网格，但文件还在内存里
  let t1 = @bench.monotonic_clock_start()
  let stream = match @stlkit.detect_format(data) {
    @stlkit.Ascii =>
      match @stlkit.stream_stl_ascii(@utf8.decode_lossy(data)) {
        Ok(r) => r
        Err(msg) => return Err(msg)
      }
    _ =>
      match @stlkit.stream_stl_binary(data) {
        Ok(r) => r
        Err(msg) => return Err(msg)
      }
  }
  let stream_us = @bench.monotonic_clock_end(t1)

  // 结论必须一致，不然快也没意义
  if check.triangle_count != stream.triangle_count ||
    check.unique_vertex_count != stream.unique_vertex_count ||
    check.boundary_edge_count != stream.boundary_edge_count ||
    check.non_manifold_edge_count != stream.non_manifold_edge_count {
    return Err("全量和流式的结论对不上，不能作为基准")
  }
  match chunked {
    Some(c) =>
      if c.triangle_count != stream.triangle_count ||
        c.unique_vertex_count != stream.unique_vertex_count ||
        c.boundary_edge_count != stream.boundary_edge_count ||
        c.non_manifold_edge_count != stream.non_manifold_edge_count {
        return Err(
          "分块流式和整块流式的结论对不上，不能作为基准",
        )
      }
    None => ()
  }

  let triangles = mesh.triangle_count()
  // 分块输入缓冲加保留的字段，不含完整文件。
  let chunk_bytes = 262144L
  let full_mem = full_memory(file_size, triangles)
  let stream_fields = stream_memory(0, stream.unique_vertex_count, triangles)
  let stream_mem = stream_memory(
    file_size,
    stream.unique_vertex_count,
    triangles,
  )
  let chunked_mem = match chunked {
    Some(c) =>
      chunk_bytes + stream_memory(0, c.unique_vertex_count, c.triangle_count)
    None => 0L
  }

  println(path)
  println("  文件大小    \{fmt_bytes(file_size.to_int64())}")
  println("  三角形      \{triangles}")
  println("")
  println("  全量解析（保留网格，能校验能修复）")
  println("    耗时      \{fmt(full_us / 1000.0, 1)} ms")
  println(
    "    数据量估算 文件 \{fmt_bytes(file_size.to_int64())} + 三角形字段 \{fmt_bytes(triangles.to_int64() * 96L)} = \{fmt_bytes(full_mem)}",
  )
  println("")
  println("  流式扫描（不保留网格，文件整块读）")
  println("    耗时      \{fmt(stream_us / 1000.0, 1)} ms")
  println(
    "    数据量估算 文件 \{fmt_bytes(file_size.to_int64())} + 顶点边字段 \{fmt_bytes(stream_fields)} = \{fmt_bytes(stream_mem)}",
  )
  println("")
  println("  流式扫描（不保留网格，文件分块读）")
  match chunked {
    Some(_) => {
      println("    耗时      \{fmt(chunked_us / 1000.0, 1)} ms")
      println(
        "    数据量估算 缓冲 \{fmt_bytes(chunk_bytes)} + 顶点边字段 \{fmt_bytes(chunked_mem - chunk_bytes)} = \{fmt_bytes(chunked_mem)}",
      )
    }
    None =>
      println(
        "    跳过      分块扫描目前只支持二进制 STL，这个文件是 ASCII 格式",
      )
  }
  println("")

  println(
    "  交叉验证    三角形、顶点、边界边和非流形边计数一致（通过）",
  )
  println(
    "              绕向一致性：全量查出 \{winding.flipped_faces} 个反向面（流式做不到这项）",
  )
  println("")
  println(
    "  说明        以上是主要数据字段量的粗略估算，不是进程内存实测；",
  )
  println(
    "              耗时对比对流式有利，因为全量还多做了绕向分析。",
  )
  let best_us = if chunked_mem > 0L { chunked_us } else { stream_us }
  if full_us > 0.0 && best_us > 0.0 {
    println(
      "  本次耗时比  全量 / 流式 = \{fmt(full_us / best_us, 1)}（包含的分析步骤不同）",
    )
  }
  Ok(false)
}

///|
/// 帮助文本：argparse 渲染的参数表，加上中文示例。
fn help_text(cmd : @argparse.Command) -> String {
  cmd.render_help() +
  "\n示例：\n" +
  "  stlkit model.stl                  读一个模型，出体检报告\n" +
  "  stlkit model.stl --fix fixed.stl  修复并存到 fixed.stl\n" +
  "  stlkit model.stl --svg a.svg      顺便导出等轴测预览图\n" +
  "  stlkit model.stl --strict         模型有问题时退出码为 1（给 CI 用）\n" +
  "  stlkit model.stl --bench          跑基准测试，记录耗时与数据量估算\n" +
  "  stlkit                            不带参数时打印这份帮助\n" +
  "\n" +
  "格式：二进制 STL、ASCII STL、OBJ、3MF、PLY 五种都能认，按文件内容判断，\n" +
  "不看扩展名——从别处拷来的文件经常带着错的扩展名。\n"
}

///|
/// 把浮点数格式化成固定小数位。
///
/// 直接用 Double 的默认输出会得到 0.9999999999999999 这种，对看报告的
/// 人没有意义——网格数据本身就带浮点误差，显示上保留几位就够。
fn fmt(value : Double, digits : Int32) -> String {
  let mut scale = 1.0
  for _i = 0; _i < digits; _i = _i + 1 {
    scale = scale * 10.0
  }
  let rounded = (value * scale).round() / scale
  rounded.to_string()
}

///|
/// 处理一个模型文件，把报告打印出来。
///
/// `svg_path` 给了的话，导出最终网格的等轴测预览图（含修复后的结果）。
/// `fix_path` 给了的话，修一遍网格存到那里，并把修复前后的校验结果对照着打出来。
///
/// 返回值里的 `Bool` 是「这个模型有没有问题」——`--strict` 模式要靠它定退出码。
/// 分开放而不是塞进错误里，是因为「模型有问题」不是**程序出错**：报告已经
/// 正常打印出来了，只是结论是负面的。
fn report(
  path : String,
  svg_path : String,
  fix_path : String,
  min_thickness : Double,
  samples : Int32,
) -> Result[Bool, String] {
  if fix_path != "" && svg_path != "" {
    // 使用宿主平台规则解析绝对路径，处理 .、..、重复分隔符与 Windows 大小写。
    let fix_output = @path.Path(fix_path).resolve()
    let svg_output = @path.Path(svg_path).resolve()
    if svg_output.relative(base=fix_output).to_string() == "" {
      return Err(
        "--fix 与 --svg 必须使用不同的输出路径（规范化后相同）",
      )
    }
  }
  let data = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(msg) => return Err("读不了文件「\{path}」：\{msg}")
  }
  let format_name = match @stlkit.detect_format(data) {
    @stlkit.Binary => "二进制 STL"
    @stlkit.Ascii => "ASCII STL"
    @stlkit.ThreeMF => "3MF"
    @stlkit.Ply => "PLY"
    // 内容提示与解析有效性分开；未知文本不再标为 OBJ。
    @stlkit.Obj => "OBJ"
    @stlkit.Unknown => "未知格式"
  }
  let mesh = match @stlkit.parse_mesh(data) {
    Ok(mesh) => mesh
    Err(msg) => return Err(msg)
  }
  let review = @stlkit.check_printability(mesh, min_thickness, samples~)
  let check = review.validation

  println(path)
  println("  格式      \{format_name}")
  println("  参考阈值  \{min_thickness} mm；样本预算 \{samples}")
  println("  三角形    \{mesh.triangle_count()} 个")
  println(
    "  顶点      \{check.raw_vertex_count} 个（去重后 \{check.unique_vertex_count} 个）",
  )
  match mesh.bounding_box() {
    Some(box) => {
      let size = box.size()
      println(
        "  包围盒    \{fmt(size.x, 3)} × \{fmt(size.y, 3)} × \{fmt(size.z, 3)} mm",
      )
    }
    None => ()
  }
  // 定向包围盒。斜着摆的模型用轴对齐的盒子量会虚胖，
  // 这个贴着模型走，能看出「它实际占多大地方」
  match mesh.oriented_bounding_box() {
    Some(obb) => {
      let size = obb.size()
      println(
        "  定向包围盒 \{fmt(size.x, 3)} × \{fmt(size.y, 3)} × \{fmt(size.z, 3)} mm",
      )
    }
    None => ()
  }
  if review.winding.orientation_reliable() {
    println("  体积      \{fmt(mesh.volume(), 3)} mm³")
  } else {
    println(
      "  有符号贡献绝对值 \{fmt(mesh.volume(), 3)} mm³（朝向未通过复核，不作可靠实体体积）",
    )
  }
  println("  表面积    \{fmt(mesh.surface_area(), 3)} mm²")
  // 零件数：几块互不相连的几何。单独一项显示，不是「错误」——
  // 分开的零件本身是合法模型，只是要知道
  let parts = @stlkit.count_parts_default(mesh)
  println("  零件      \{parts} 个")
  // 欧拉示性数只在网格水密时才有拓扑含义（2 = 一个实心块，0 = 有一个
  // 穿透的洞……）。不水密的时候它只是「顶点数减边数加面数」，
  // 报出来会让人以为读出了什么，所以不显示
  if check.is_watertight() && review.winding.orientation_reliable() {
    println(
      "  欧拉数    \{check.euler_number()}（单个闭合可定向曲面：χ = 2 − 2g）",
    )
  }
  // 质量属性使用库中统一的前提检查；边计数闭合并不足够。
  if review.mass_properties_available() {
    let c = mesh.center_mass()
    println("  重心      \{fmt(c.x, 3)}, \{fmt(c.y, 3)}, \{fmt(c.z, 3)} mm")
    let pm = mesh.principal_moments()
    // 用 3 位小数，和别的字段一致。不能只留 1 位——单位立方体的主惯量是
    // 1/6 ≈ 0.167，只留 1 位就变成「0.2」，对着公式验的人会被误导
    println(
      "  主惯量    \{fmt(pm[0], 3)} / \{fmt(pm[1], 3)} / \{fmt(pm[2], 3)}（密度取 1）",
    )
  } else {
    println("  重心      未评估")
    println("  主惯量    未评估")
    println(
      "  质量属性前提  需非空、闭合、无退化面、绕向一致且分量朝向可靠（无潜在嵌套或重叠）",
    )
  }
  match review.thickness {
    Some(thick) =>
      if thick.hits > 0 {
        println(
          "  采样最小厚度 \{fmt(thick.min_thickness, 3)} mm（命中 \{thick.hits}/\{thick.samples}）",
        )
      }
    None => ()
  }
  let has_problem = review.needs_review()
  println("")
  print_findings(review, parts)

  let (final_mesh, final_has_problem) = if fix_path != "" {
    match
      fix_and_save(
        mesh,
        check,
        review.winding,
        fix_path,
        min_thickness,
        samples,
      ) {
      Ok(result) => result
      Err(message) => return Err(message)
    }
  } else {
    (mesh, has_problem)
  }

  if svg_path != "" {
    let svg = @stlkit.render_svg(final_mesh, @stlkit.PreviewOptions::default())
    @fs.write_string_to_file(svg_path, svg) catch {
      @fs.IOError(msg) =>
        return Err("写不了预览图「\{svg_path}」：\{msg}")
    }
    println("")
    println("  预览图已导出到 \{svg_path}")
  }
  Ok(final_has_problem)
}

///|
/// 打印校验结果。
///
/// 每一条「不通过」都要说清楚**为什么这是问题**，不能只报一个数字。
/// 看到「有 3 条边界边」的人不知道这意味着什么，看到「切片软件分不清
/// 哪里是外面」才知道要修。
fn print_findings(review : @stlkit.PrintabilityReport, parts : Int32) -> Unit {
  println("  \{@stlkit.review_scope()}")
  for component in review.winding.components {
    println(
      "  分量 \{component.index}：\{component.faces.length()} 面；有符号体积 \{fmt(component.signed_volume, 6)} mm³；\{component.orientation.label()}；闭合 \{component.closed}；绕向一致 \{component.consistent}",
    )
    if component.potentially_nested {
      println(
        "    ⚠ 分量包围盒重叠，未判定内腔或壳层嵌套，不自动改变整体方向",
      )
    }
  }
  let check = review.validation
  if check.boundary_edge_count > 0 {
    println(
      "  ⚠ 有 \{check.boundary_edge_count} 条边界边，请复核开放面",
    )
  }
  if check.non_manifold_edge_count > 0 {
    println("  ⚠ 有 \{check.non_manifold_edge_count} 条非流形边")
  }
  if check.degenerate_count > 0 {
    println("  ⚠ 有 \{check.degenerate_count} 个退化面")
  }
  if check.wrong_normal_count > 0 {
    println(
      "  ⚠ 有 \{check.wrong_normal_count} 个面的已保留声明面法线方向与三角形绕向相反（不代表完整法线校验）",
    )
  }
  if review.winding.flipped_faces > 0 {
    println(
      "  ⚠ 有 \{review.winding.flipped_faces} 个面的相邻绕向不一致",
    )
  }
  if review.inward() {
    println(
      "  ⚠ 有 \{review.inward_component_count()} 个闭合分量的有符号体积为负，请复核朝向或内腔语义",
    )
  }
  if review.thin_wall() {
    println(
      "  ⚠ 采样厚度低于参考阈值 \{fmt(review.min_thickness, 3)} mm；请按材料和设备确认",
    )
  }
  if review.thickness_unavailable() {
    println("  ⚠ 当前网格无法可靠评估壁厚")
  }
  if parts > 1 {
    println("  提示：有 \{parts} 个按共享边分离的零件")
  }
  println("  结论：\{review.verdict()}")
}

///|
/// 修一遍网格，存到指定文件，把修复前后的校验结果对照着打出来。
///
/// 对照着打是有意的：只报「修复完成」没法让人判断到底修好了没有。
/// 显示「边界边 3 → 0」才叫证据。
fn fix_and_save(
  mesh : @stlkit.Mesh,
  before : @stlkit.ValidationReport,
  winding : @stlkit.WindingReport,
  fix_path : String,
  min_thickness : Double,
  samples : Int32,
) -> Result[(@stlkit.Mesh, Bool), String] {
  if before.is_watertight() &&
    before.degenerate_count == 0 &&
    before.wrong_normal_count == 0 &&
    winding.flipped_faces == 0 &&
    winding.orientation_reliable() {
    println("")
    println("未发现当前自动修复能处理的网格问题。")
    match save_mesh(mesh, fix_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    return Ok(
      (
        mesh,
        @stlkit.check_printability(mesh, min_thickness, samples~).needs_review(),
      ),
    )
  }

  let fixed = @stlkit.repair(mesh, @stlkit.RepairOptions::default())
  let after_review = @stlkit.check_printability(
    fixed.mesh,
    min_thickness,
    samples~,
  )
  let after = after_review.validation

  println("")
  println("修复：")
  if fixed.removed_degenerate > 0 {
    println("  删掉 \{fixed.removed_degenerate} 个退化三角形")
  }
  if fixed.removed_duplicates > 0 {
    println("  删掉 \{fixed.removed_duplicates} 个重复三角形")
  }
  if fixed.added_triangles > 0 {
    println("  补洞：新增 \{fixed.added_triangles} 个三角形")
  }
  if fixed.recomputed_normals > 0 {
    println("  重算 \{fixed.recomputed_normals} 个三角形的法线")
  }
  if fixed.reoriented_components > 0 {
    println(
      "  按独立闭合零件假设翻转 \{fixed.reoriented_components} 个负体积分量",
    )
  }
  if fixed.flipped_faces > 0 {
    // 把体积的变化也打出来 —— 绕向反了是「看不出来的坏」，
    // 体积从错变对是它唯一的直接证据
    println(
      "  翻转 \{fixed.flipped_faces} 个绕向反了的面（体积从 \{fmt(mesh.volume(), 3)} 修正为 \{fmt(fixed.mesh.volume(), 3)}）",
    )
  }
  if !fixed.changed() {
    println(
      "  没能改动任何东西 —— 这个网格的问题修复功能处理不了",
    )
    return Err("修复没有产生任何改动")
  }

  println("")
  println(
    "  修复前 边界边 \{before.boundary_edge_count}  非流形边 \{before.non_manifold_edge_count}  退化面 \{before.degenerate_count}",
  )
  println(
    "  修复后 边界边 \{after.boundary_edge_count}  非流形边 \{after.non_manifold_edge_count}  退化面 \{after.degenerate_count}",
  )

  match save_mesh(fixed.mesh, fix_path) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  print_findings(after_review, @stlkit.count_parts_default(fixed.mesh))
  Ok((fixed.mesh, after_review.needs_review()))
}

///|
/// 按请求导出最终网格；没有可修复改动时也生成输出文件。
fn save_mesh(mesh : @stlkit.Mesh, path : String) -> Result[Unit, String] {
  let bytes = match @stlkit.write_mesh(mesh, path) {
    Ok(bytes) => bytes
    Err(msg) => return Err(msg)
  }
  @fs.write_bytes_to_file(path, bytes) catch {
    @fs.IOError(msg) => return Err("写不了文件「\{path}」：\{msg}")
  }

  println("")
  println("  已存到 \{path}（\{bytes.length()} 字节）")
  Ok(())
}

///|
/// 常规检查路径。
fn run(matches : @argparse.Matches, path : String) -> Result[Bool, String] {
  let nozzle = match matches.values.get("nozzle") {
    Some([raw, ..]) => {
      let value = @string.parse_double(raw) catch {
        _ => return Err("--nozzle 必须是正的有限数字")
      }
      if value.is_nan() || value.is_inf() || value <= 0.0 {
        return Err("--nozzle 必须是正的有限数字")
      }
      value.to_string() + " mm"
    }
    _ => "未指定"
  }
  let supports = match matches.values.get("supports") {
    Some([raw, ..]) =>
      if raw == "on" || raw == "off" || raw == "unknown" {
        raw
      } else {
        return Err("--supports 只接受 on/off/unknown")
      }
    _ => "unknown"
  }
  let samples = match matches.values.get("samples") {
    Some([raw, ..]) => {
      let value = @string.parse_int(raw) catch {
        _ => return Err("--samples 必须是 1..100000 的整数")
      }
      if value < 1 || value > 100000 {
        return Err("--samples 必须是 1..100000 的整数")
      }
      value
    }
    _ => 1000
  }
  let svg_path = match matches.values.get("svg") {
    Some([first, ..]) => first
    _ => ""
  }
  let fix_path = match matches.values.get("fix") {
    Some([first, ..]) => first
    _ => ""
  }
  let min_thickness = match matches.values.get("min-thickness") {
    Some([raw, ..]) => {
      let value = @string.parse_double(raw) catch {
        _ => return Err("--min-thickness 必须是非负有限数字")
      }
      if value.is_nan() || value.is_inf() || value < 0.0 {
        return Err("--min-thickness 必须是非负有限数字")
      }
      value
    }
    _ => 0.8
  }
  println(
    "场景记录：喷嘴 \{nozzle}；支撑 \{supports}（仅记录，不参与通过/失败判定）",
  )
  let has_problem = match
    report(path, svg_path, fix_path, min_thickness, samples) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }

  // --strict：模型有问题就以退出码 1 结束，给 CI 用。
  // 注意这里不打印「错误：」——报告已经正常打出来了，只是结论是负面的，
  // 加个错误前缀会让人以为是程序出错。
  if matches.flags.get("strict") == Some(true) && has_problem {
    @sys.exit(1)
  }
  Ok(has_problem)
}

///|
/// 命令行入口。出错时以退出码 1 结束，方便脚本判断。
///
/// 写成 `async fn main` 是因为基准测试要分块读文件，走的是
/// `moonbitlang/async/fs`。其余路径都是同步的，只是借了这个入口分派。
async fn main {
  let result = try {
    let cmd = command()
    let matches = cmd.parse()
    let path = match matches.values.get("file") {
      Some([first, ..]) => first
      _ => ""
    }
    if matches.flags.get("help") == Some(true) || path == "" {
      println(help_text(cmd))
      Ok(false)
    } else if matches.flags.get("stream-only") == Some(true) {
      if matches.flags.get("bench") == Some(true) ||
        matches.flags.get("strict") == Some(true) ||
        matches.values.length() > 1 {
        Err(
          "--stream-only 只接受文件路径，不与几何检查或基准参数组合",
        )
      } else {
        stream_only(path)
      }
    } else if matches.flags.get("bench") == Some(true) {
      bench(path)
    } else {
      run(matches, path)
    }
  } catch {
    err => Err(err.to_string())
  }
  match result {
    Ok(_) => ()
    Err(msg) => {
      println("错误：\{msg}")
      @sys.exit(1)
    }
  }
}
