// OBJ 解析。
//
// OBJ 跟 STL 有两个根本区别，决定了这个解析器长得完全不一样：
//
// **一、OBJ 有共享顶点表。** 文件开头先把所有顶点列一遍（`v x y z`），
// 后面的面只写编号（`f 1 2 3`）。一个立方体是 8 行 v + 6 行 f，
// 而 STL 要写 36 遍顶点。所以这里得先建表再查表。
//
// **二、OBJ 的面可以是多边形。** `f 1 2 3 4` 是个四边形，甚至可以是
// 十七边形。而我们的 Mesh 只装三角形，所以要在这里做三角化——
// 凸多边形用扇形法，凹多边形用耳切法；自相交或非平面多边形明确报错。
//
// 另外 OBJ 的编号从 1 开始，而且可以是负数（表示从末尾往前数）。

///|
/// 解析 OBJ 文本。
///
/// 只认几何相关的关键字：`v`（顶点）、`f`（面）、`vn`（法线）会读，
/// `vt` 读取并检查面引用，纹理值不保存在 Mesh；其余（`g`、`o`、`s`、`mtllib`、`usemtl`、注释）跳过——
/// 这些语义不进入 Mesh；跳过不表示已验证材质或工艺。
pub fn parse_obj(
  text : String,
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Mesh, String] {
  if text_limit_error(text, limits) is Some(error) {
    return Err(error)
  }
  // 顶点表。OBJ 的编号是 1 基的，为了少一次减法，这里在下标 0 处
  // 塞一个占位，让 vertices[1] 就是文件里的第 1 号顶点。
  let vertices : Array[Vec3] = [Vec3::zero()]
  // 法线表，同样是 1 基
  let normals : Array[Vec3] = [Vec3::zero()]
  let textures : Array[Vec3] = [Vec3::zero()]
  let triangles : Array[Triangle] = []
  let mut line_no = 0
  let mut list_items = 0L

  for raw_line in text.split("\n") {
    line_no = line_no + 1
    let tokens : Array[StringView] = []
    for raw_token in obj_words(raw_line) {
      let token = strip_cr(raw_token)
      if token.length() > 0 {
        if token.has_prefix("#") {
          break
        }
        tokens.push(token)
      }
    }
    if tokens is [head, ..] && (head == "v" || head == "vn" || head == "vt") {
      if vertices.length().to_int64() +
        normals.length().to_int64() +
        textures.length().to_int64() -
        3L >=
        limits.max_vertices.to_int64() {
        return Err(resource_error("max_vertices", limits.max_vertices))
      }
    }
    if tokens is ["f", .. refs] {
      if refs.length() > limits.max_polygon_vertices {
        return Err(
          resource_error("max_polygon_vertices", limits.max_polygon_vertices),
        )
      }
      list_items += refs.length().to_int64()
      if list_items > limits.max_list_items.to_int64() {
        return Err(resource_error("max_list_items", limits.max_list_items))
      }
      if refs.length() >= 3 &&
        refs.length() - 2 > limits.max_triangles - triangles.length() {
        return Err(resource_error("max_triangles", limits.max_triangles))
      }
    }
    match tokens {
      ["v", x, y, z] =>
        match parse_vec3(x, y, z, line_no) {
          Ok(v) => vertices.push(v)
          Err(msg) => return Err(msg)
        }
      ["vn", x, y, z] =>
        match parse_vec3(x, y, z, line_no) {
          Ok(v) => normals.push(v)
          Err(msg) => return Err(msg)
        }
      ["v", x, y, z, w] => {
        let weight = @string.parse_double(w) catch {
          _ => return Err("第 \{line_no} 行：OBJ v 的 w 不是有限数字")
        }
        if weight != 1.0 {
          return Err(
            "第 \{line_no} 行：当前 OBJ 多边形读取子集只接受省略 w 或 w=1",
          )
        }
        match parse_vec3(x, y, z, line_no) {
          Ok(v) => vertices.push(v)
          Err(msg) => return Err(msg)
        }
      }
      ["v", ..] | ["vn", ..] =>
        return Err(
          "第 \{line_no} 行：OBJ v/vn 字段数量不符合当前几何读取子集",
        )
      ["vt", .. values] => {
        let uvw = match values {
          [u] => parse_vec3(u, "0", "0", line_no)
          [u, v] => parse_vec3(u, v, "0", line_no)
          [u, v, w] => parse_vec3(u, v, w, line_no)
          _ =>
            return Err(
              "第 \{line_no} 行：OBJ vt 必须有 1..3 个有限坐标",
            )
        }
        match uvw {
          Ok(v) => textures.push(v)
          Err(msg) => return Err(msg)
        }
      }
      ["f", .. rest] =>
        match parse_face(rest, vertices, normals, textures, line_no) {
          Ok(new_triangles) =>
            for t in new_triangles {
              triangles.push(t)
            }
          Err(msg) => return Err(msg)
        }
      _ => ()
    }
  }

  if triangles.length() == 0 {
    return Err("这个 OBJ 里一个面都没有，可能不是 OBJ 文件")
  }
  Ok(Mesh::new(triangles))
}

///|
/// 空格、制表符和 CR 都是分隔符；不依赖只替换第一处的 String::replace。
fn obj_words(line : StringView) -> Array[StringView] {
  let words : Array[StringView] = []
  let mut i = 0
  while i < line.length() {
    while i < line.length() && is_ascii_space(line.code_unit_at(i).to_int()) {
      i = i + 1
    }
    let start = i
    while i < line.length() && !is_ascii_space(line.code_unit_at(i).to_int()) {
      i = i + 1
    }
    if i > start {
      words.push(line[start:i])
    }
  }
  words
}

///|
/// 解析一个面，返回它三角化之后的三角形。
///
/// 每个顶点记号可能是 `3`、`3/5`、`3//7`、`3/5/7` 四种形式之一，
/// 分别表示「只有顶点」「顶点/纹理」「顶点//法线」「顶点/纹理/法线」。
/// 纹理坐标仅用于合法性和索引范围检查，不进入 Mesh。
fn parse_face(
  refs : ArrayView[StringView],
  vertices : Array[Vec3],
  normals : Array[Vec3],
  textures : Array[Vec3],
  line_no : Int32,
) -> Result[Array[Triangle], String] {
  if refs.length() < 3 {
    return Err(
      "第 \{line_no} 行：一个面至少要有 3 个顶点，这里只有 \{refs.length()} 个",
    )
  }

  // 先把这个面的所有顶点解出来
  let mut reference_shape : Int32? = None
  let face_vertices : Array[Vec3] = []
  let face_normals : Array[Vec3] = []
  for vref in refs {
    let fields = vref.split("/").to_array()
    let shape = fields.length() * 2 +
      (if fields.length() > 1 && fields[1].length() == 0 { 1 } else { 0 })
    match reference_shape {
      Some(old) =>
        if old != shape {
          return Err(
            "第 \{line_no} 行：OBJ 同一面的引用形式必须一致",
          )
        }
      None => reference_shape = Some(shape)
    }
    match parse_face_ref(vref, vertices, normals, textures, line_no) {
      Ok(pair) => {
        face_vertices.push(pair.0)
        face_normals.push(pair.1)
      }
      Err(msg) => return Err(msg)
    }
  }

  let faces = match triangulate_polygon(face_vertices) {
    Ok(faces) => faces
    Err(msg) => return Err("第 \{line_no} 行：\{msg}")
  }
  let result : Array[Triangle] = []
  for face in faces {
    let (a, b, c) = face
    // 法线优先用文件里写的。一个平面的三个顶点法线一样时直接用
    // （3D 打印模型里绝大多数面都是平的），不一样就留零，
    // 零向量随后跳过声明面法线反向检查；不验证不同的平滑顶点法线。
    let normal = if same_vec(face_normals[a], face_normals[b]) &&
      same_vec(face_normals[b], face_normals[c]) {
      face_normals[a]
    } else {
      Vec3::zero()
    }
    result.push({
      normal,
      a: face_vertices[a],
      b: face_vertices[b],
      c: face_vertices[c],
    })
  }
  Ok(result)
}

///|
/// 两个向量是不是逐分量完全相等。
///
/// 用精确比较而不是带容差：这里的用途是判断「同一个面里几个顶点的法线
/// 是不是同一份数据」，它们要么来自文件里同一个 `vn` 编号（那就完全一样），
/// 要么就不是同一个。引入容差反而会把「相近但不相同」误判成相同。
fn same_vec(a : Vec3, b : Vec3) -> Bool {
  a.x == b.x && a.y == b.y && a.z == b.z
}

///|
/// 解析面里的一个顶点记号，返回（顶点, 法线）。
///
/// 法线可能没有（`f 1 2 3` 或 `f 1/1 2/2 3/3`），那就返回零向量。
fn parse_face_ref(
  vref : StringView,
  vertices : Array[Vec3],
  normals : Array[Vec3],
  textures : Array[Vec3],
  line_no : Int32,
) -> Result[(Vec3, Vec3), String] {
  // 按 `/` 切开，最多三段：顶点[/纹理][/法线]
  let parts : Array[StringView] = []
  for part in vref.split("/") {
    parts.push(part)
  }
  match parts {
    [v] =>
      if v.length() == 0 {
        return Err("第 \{line_no} 行：空的顶点引用")
      }
    [v, t] =>
      if v.length() == 0 || t.length() == 0 {
        return Err("第 \{line_no} 行：OBJ v/vt 引用不完整")
      }
    [v, _, n] =>
      if v.length() == 0 || n.length() == 0 {
        return Err("第 \{line_no} 行：OBJ 法线引用不完整")
      }
    _ =>
      return Err(
        "第 \{line_no} 行：OBJ 面引用只接受 v、v/vt、v//vn、v/vt/vn",
      )
  }
  let vertex_index = match parts {
    [v, ..] => v
    [] => return Err("第 \{line_no} 行：空的顶点记号")
  }
  if parts.length() >= 2 && parts[1].length() > 0 {
    match lookup(parts[1], textures, line_no, "纹理") {
      Ok(_) => ()
      Err(msg) => return Err(msg)
    }
  }
  let vertex = match lookup(vertex_index, vertices, line_no, "顶点") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  // 第三段才是法线；第二段纹理索引已在上面验证，纹理数据不进入 Mesh。
  let normal = match parts {
    [_, _, n, ..] =>
      if n.length() == 0 {
        Vec3::zero()
      } else {
        match lookup(n, normals, line_no, "法线") {
          Ok(v) => v
          Err(msg) => return Err(msg)
        }
      }
    _ => Vec3::zero()
  }
  Ok((vertex, normal))
}

///|
/// 把 OBJ 的编号查成表里的值。
///
/// OBJ 的编号有两个规矩：
/// - **从 1 开始**，不是从 0。所以查表时要用 `index - 1`；
///   我们的表在开头塞了个占位，正好抵消。
/// - **可以是负数**，表示从当前表的末尾往前数：-1 是最后一个，
///   -2 是倒数第二个。有些导出器喜欢这么写。
fn[T] lookup(
  token : StringView,
  table : Array[T],
  line_no : Int32,
  what : String,
) -> Result[T, String] {
  let index = match parse_int(token, line_no, what) {
    Ok(i) => i
    Err(msg) => return Err(msg)
  }
  if index == 0 {
    return Err(
      "第 \{line_no} 行：\{what}编号不能是 0（OBJ 从 1 开始数）",
    )
  }
  // 表里有 n 个真实条目（下标 0 是占位），合法编号是 1..n 和 -1..-n
  let count = table.length() - 1
  let resolved = if index > 0 { index } else { count + index + 1 }
  if resolved < 1 || resolved > count {
    return Err(
      "第 \{line_no} 行：\{what}编号 \{index} 超出范围（文件里一共有 \{count} 个\{what}）",
    )
  }
  Ok(table[resolved])
}

///|
/// 解析一个整数，失败时给出中文提示。
fn parse_int(
  token : StringView,
  line_no : Int32,
  what : String,
) -> Result[Int32, String] {
  if !profile_integer_token(token) {
    return Err("第 \{line_no} 行：OBJ 编号必须为十进制整数")
  }
  Ok(@string.parse_int(token)) catch {
    _ =>
      Err(
        "第 \{line_no} 行：『\{token}』不是合法的\{what}编号（OBJ 的编号必须是整数）",
      )
  }
}
