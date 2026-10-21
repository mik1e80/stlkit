// STL 解析。
//
// STL 是 3D 打印的事实标准格式，有两种形态，内容完全一样，只是写法不同：
//
// ASCII：纯文本，一个三角形写成一坨 facet/vertex 关键字。
//        文件大（是二进制版的好几倍），但人眼能读。
//
// 二进制：80 字节文件头（内容随意，很多导出器塞一段说明文字）
//        + 4 字节小端三角形数量
//        + 每个三角形 50 字节：12 个 float32（法线 3 + 三个顶点 9）+ 2 字节属性
//
// 属性那 2 字节没有标准含义，多数导出器填 0，直接丢掉。

///|
/// 自动读取 STL；格式探测只是路由提示，几何仍由解析器验证。
pub fn parse_stl(data : Bytes) -> Result[Mesh, String] {
  match detect_format(data) {
    Binary => parse_stl_binary(data)
    Ascii | Unknown =>
      match parse_stl_ascii(@utf8.decode_lossy(data)) {
        Ok(mesh) => Ok(mesh)
        Err(message) => Err("认不出或无法解析 STL：\{message}")
      }
    Obj =>
      Err(
        "这是一个 OBJ 文件，不是 STL——请用 parse_mesh 或 parse_obj",
      )
    ThreeMF =>
      Err(
        "这是一个 3MF 文件，不是 STL——请用 parse_mesh 或 parse_3mf",
      )
    Ply =>
      Err(
        "这是一个 PLY 文件，不是 STL——请用 parse_mesh 或 parse_ply",
      )
  }
}

///|
/// 按内容提示选择 STL / OBJ / 3MF / PLY 解析器，不使用文件扩展名。
/// 无提示的文本依次尝试 ASCII STL 和 OBJ，均失败时返回组合诊断。
pub fn parse_mesh(data : Bytes) -> Result[Mesh, String] {
  match detect_format(data) {
    ThreeMF => parse_3mf(data)
    Ply => parse_ply(data)
    Binary => parse_stl_binary(data)
    Ascii => parse_stl_ascii(@utf8.decode_lossy(data))
    Obj => parse_obj(@utf8.decode_lossy(data))
    Unknown => {
      let text = @utf8.decode_lossy(data)
      match parse_stl_ascii(text) {
        Ok(mesh) => Ok(mesh)
        Err(stl_error) =>
          match parse_obj(text) {
            Ok(mesh) => Ok(mesh)
            Err(obj_error) =>
              Err(
                "无法识别网格格式；ASCII STL：\{stl_error}；OBJ：\{obj_error}",
              )
          }
      }
    }
  }
}

///|
/// 格式探测结果；不是文件有效性或完整格式兼容性的证明。
pub(all) enum MeshFormat {
  Ascii
  Binary
  Obj
  ThreeMF
  Ply
  /// 未发现支持格式的提示；不再表示 OBJ。
  Unknown
}

///|
/// 先识别 ZIP/3MF 和 PLY，再检查二进制 STL 长度。
/// 其余文本按行首记录探测，直到找到几何记录或读完，不设 512 字节上限。
/// 关键字在注释、对象名称或 solid 名称中出现时不作为几何记录。
pub fn detect_format(data : Bytes) -> MeshFormat {
  if is_3mf(data) {
    return ThreeMF
  }
  if is_ply(data) {
    return Ply
  }
  if data.length() >= 84 {
    let count = read_u32_le(data, 80)
    let expected = 84UL + count.to_uint64() * 50UL
    if expected == data.length().to_uint64() {
      return Binary
    }
  }
  let text = @utf8.decode_lossy(data)
  let mut stl_header = false
  for line in text.split("\n") {
    let mut start = 0
    while start < line.length() &&
          is_ascii_space(line.code_unit_at(start).to_int()) {
      start = start + 1
    }
    let mut end = start
    while end < line.length() &&
          !is_ascii_space(line.code_unit_at(end).to_int()) {
      end = end + 1
    }
    match line[start:end] {
      "facet" | "vertex" | "endfacet" => return Ascii
      "v" | "vn" | "f" => return Obj
      "solid" | "endsolid" => stl_header = true
      _ => ()
    }
  }
  if stl_header {
    Ascii
  } else {
    Unknown
  }
}

///|
/// 去掉结尾的 `\r`。
///
/// Windows 的换行是 `\r\n`，按 `\n` 切完每行末尾会剩一个 `\r`。
/// 不处理的话，行尾那个数字会变成 `-1\r` 这种没法解析的东西——
/// 而 Windows 上导出的 STL 几乎全是 CRLF，真实文件一读就挂。
fn strip_cr(s : StringView) -> StringView {
  let n = s.length()
  if n > 0 && s.code_unit_at(n - 1) == 0x0D {
    s[:n - 1]
  } else {
    s
  }
}

///|
/// 解析 ASCII STL。
///
/// 逐行扫，认三种关键字：
///   `facet normal x y z`  开一个新面，记下法线
///   `vertex x y z`        往当前面里加一个顶点
///   `endfacet`            当前面结束，凑够三个顶点就收一个三角形
///
/// 其余的行（`solid`、`outer`、`loop`、`endloop`、`endsolid`）直接跳过——
/// 它们不影响几何信息。
pub fn parse_stl_ascii(text : String) -> Result[Mesh, String] {
  let triangles : Array[Triangle] = []
  let mut normal = Vec3::zero()
  let pending : Array[Vec3] = []
  let mut line_no = 0

  for raw_line in text.split("\n") {
    line_no = line_no + 1
    // 按空格切，顺便滤掉空串（行首缩进、连续空格都会产生空 token）
    let tokens : Array[StringView] = []
    for raw_token in raw_line.split(" ") {
      let token = strip_cr(raw_token)
      if token.length() > 0 {
        tokens.push(token)
      }
    }
    match tokens {
      ["facet", "normal", x, y, z] =>
        match parse_vec3(x, y, z, line_no) {
          Ok(v) => {
            normal = v
            pending.clear()
          }
          Err(msg) => return Err(msg)
        }
      ["vertex", x, y, z] =>
        match parse_vec3(x, y, z, line_no) {
          Ok(v) => pending.push(v)
          Err(msg) => return Err(msg)
        }
      ["endfacet", ..] =>
        if pending.length() == 3 {
          triangles.push({
            normal,
            a: pending[0],
            b: pending[1],
            c: pending[2],
          })
          pending.clear()
        } else {
          return Err(
            "第 \{line_no} 行：一个面结束了，但里面只有 \{pending.length()} 个顶点，应该是 3 个",
          )
        }
      _ => ()
    }
  }

  if triangles.length() == 0 {
    return Err(
      "这个 ASCII STL 里一个三角形都没有，可能不是 STL 文件",
    )
  }
  Ok(Mesh::new(triangles))
}

///|
/// 解析二进制 STL。
pub fn parse_stl_binary(data : Bytes) -> Result[Mesh, String] {
  if data.length() < 84 {
    return Err(
      "二进制 STL 至少要 84 字节（80 字节文件头 + 4 字节三角形数），" +
      "这个文件只有 \{data.length()} 字节",
    )
  }
  let count_u = read_u32_le(data, 80)
  let expected = 84UL + count_u.to_uint64() * 50UL
  if expected > data.length().to_uint64() {
    return Err(
      "二进制 STL 头部声称有 \{count_u} 个三角形（需要 \{expected} 字节），" +
      "但文件只有 \{data.length()} 字节，文件被截断了",
    )
  }
  let count = count_u.reinterpret_as_int()
  let triangles : Array[Triangle] = []
  for i = 0; i < count; i = i + 1 {
    let base = 84 + i * 50
    for offset in [0, 12, 24, 36] {
      if !finite_vertex(read_vec3_f32(data, base + offset)) {
        return Err(
          "二进制 STL 第 \{i + 1} 个三角形的坐标或法线不是有限数字",
        )
      }
    }
    triangles.push({
      normal: read_vec3_f32(data, base),
      a: read_vec3_f32(data, base + 12),
      b: read_vec3_f32(data, base + 24),
      c: read_vec3_f32(data, base + 36),
    })
  }
  if triangles.length() == 0 {
    return Err("这个二进制 STL 里一个三角形都没有")
  }
  Ok(Mesh::new(triangles))
}

///|
/// 把三个坐标 token 解析成向量，失败时给出带行号的中文错误。
///
/// 逐个解析、出错就返回，而不是三个一起解再合并错误——后者要么写得很绕，
/// 要么丢失「是哪个坐标出的错」。
fn parse_vec3(
  x : StringView,
  y : StringView,
  z : StringView,
  line_no : Int,
) -> Result[Vec3, String] {
  let x = match parse_coord(x, line_no) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let y = match parse_coord(y, line_no) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let z = match parse_coord(z, line_no) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  Ok(Vec3::new(x, y, z))
}

///|
/// 解析一个坐标。解析器的错误是英文的，这里换成带行号的中文提示。
fn parse_coord(s : StringView, line_no : Int) -> Result[Double, String] {
  let value = @string.parse_double(s) catch {
    _ =>
      return Err("第 \{line_no} 行：『\{s}』不是一个合法的数字")
  }
  if not_finite(value) {
    return Err("第 \{line_no} 行：『\{s}』不是有限数字")
  }
  Ok(value)
}

///|
/// 从字节里读一个小端 32 位无符号整数。
fn read_u32_le(data : Bytes, offset : Int) -> UInt {
  let b0 = data[offset].to_int() & 0xFF
  let b1 = data[offset + 1].to_int() & 0xFF
  let b2 = data[offset + 2].to_int() & 0xFF
  let b3 = data[offset + 3].to_int() & 0xFF
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_uint()
}

///|
/// 从字节里读一个小端 float32，转成 Double。
///
/// 用 `Float::reinterpret_from_uint` 按位重新解释，而不是做数值转换——
/// 文件里存的就是 IEEE 754 的位模式，直接搬过来就行，不需要任何换算。
fn read_f32_le(data : Bytes, offset : Int) -> Double {
  let bits = read_u32_le(data, offset)
  Float::reinterpret_from_uint(bits).to_double()
}

///|
/// 连读三个 float32 组成一个向量。
fn read_vec3_f32(data : Bytes, offset : Int) -> Vec3 {
  Vec3::new(
    read_f32_le(data, offset),
    read_f32_le(data, offset + 4),
    read_f32_le(data, offset + 8),
  )
}
