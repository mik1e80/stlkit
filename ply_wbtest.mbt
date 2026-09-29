// 白盒测试：PLY 解析。
//
// 样本全部在内存里现拼。重点盯三件事：
//
//   1. **三种编码**（ASCII / 二进制小端 / 二进制大端）必须给出同一个结果
//   2. **未知属性要跳过去但不能错位**——扫描仪导出的 PLY 常带法线和颜色，
//      跳错一个字节后面全是垃圾
//   3. **编号从 0 开始**，不是 OBJ 那套从 1 开始

// ── 造样本用的零件 ──────────────────────────────────────────────────────

///|
/// 单位立方体的去重顶点表 + 面的下标三元组。
///
/// 直接用手写死 8 个顶点容易和 unit_cube_triangles() 对不上，
/// 所以从它推出来——这样两边的三角剖分保证一致。
fn cube_ply_parts() -> (Array[(Double, Double, Double)], Array[(Int, Int, Int)]) {
  let verts : Array[(Double, Double, Double)] = []
  let faces : Array[(Int, Int, Int)] = []
  for t in unit_cube_triangles() {
    let (a, b, c) = t
    let ia = intern_vertex(verts, a)
    let ib = intern_vertex(verts, b)
    let ic = intern_vertex(verts, c)
    faces.push((ia, ib, ic))
  }
  (verts, faces)
}

///|
/// 顶点表里找这个点，没有就加进去并返回新编号。
fn intern_vertex(
  verts : Array[(Double, Double, Double)],
  v : Vec3,
) -> Int {
  for i, e in verts {
    let (x, y, z) = e
    if x == v.x && y == v.y && z == v.z {
      return i
    }
  }
  verts.push((v.x, v.y, v.z))
  verts.length() - 1
}

///|
/// 拼一个 ASCII PLY。
///
/// `vertex_extra` / `face_extra` 是额外的属性声明，用来测「未知属性要跳过」。
fn ascii_ply(
  vertex_extra : String,
  face_extra : String,
  verts : Array[(Double, Double, Double)],
  faces : Array[(Int, Int, Int)],
) -> Bytes {
  let mut s = "ply\nformat ascii 1.0\n"
  s = s + "element vertex \{verts.length()}\n"
  s = s + "property float x\nproperty float y\nproperty float z\n"
  s = s + vertex_extra
  s = s + "element face \{faces.length()}\n"
  s = s + "property list uchar int vertex_indices\n"
  s = s + face_extra
  s = s + "end_header\n"
  for v in verts {
    let (x, y, z) = v
    s = s + "\{x} \{y} \{z}\n"
  }
  for f in faces {
    let (a, b, c) = f
    s = s + "3 \{a} \{b} \{c}\n"
  }
  @utf8.encode(s)
}

///|
/// 把坐标写成 float32 的位模式。
///
/// 测试用的立方体坐标只有 0 和 1，所以直接取这两个值的 IEEE 754 位模式
/// （0.0 → 0x00000000、1.0 → 0x3F800000），省得为了 Double → 位模式
/// 的转换再翻一遍标准库。
fn f32_bits(v : Double) -> UInt {
  if v == 0.0 {
    0x00000000
  } else {
    0x3F800000
  }
}

///|
/// 把一个 UInt 按 4 字节写进数组，`big` 决定字节序。
fn ply_push_u32(out : Array[Byte], v : UInt, big : Bool) -> Unit {
  let b0 = (v & 0xFF).reinterpret_as_int()
  let b1 = ((v >> 8) & 0xFF).reinterpret_as_int()
  let b2 = ((v >> 16) & 0xFF).reinterpret_as_int()
  let b3 = ((v >> 24) & 0xFF).reinterpret_as_int()
  if big {
    // 大端：高位字节在前
    out.push(b3.to_byte())
    out.push(b2.to_byte())
    out.push(b1.to_byte())
    out.push(b0.to_byte())
  } else {
    // 小端：低位字节在前
    out.push(b0.to_byte())
    out.push(b1.to_byte())
    out.push(b2.to_byte())
    out.push(b3.to_byte())
  }
}

///|
/// 拼一个二进制 PLY（float32 坐标 + uchar 计数 + int32 编号）。
fn binary_ply(
  big : Bool,
  verts : Array[(Double, Double, Double)],
  faces : Array[(Int, Int, Int)],
) -> Bytes {
  let kind = if big {
    "binary_big_endian"
  } else {
    "binary_little_endian"
  }
  let mut head = "ply\nformat " + kind + " 1.0\n"
  head = head + "element vertex \{verts.length()}\n"
  head = head + "property float x\nproperty float y\nproperty float z\n"
  head = head + "element face \{faces.length()}\n"
  head = head + "property list uchar int vertex_indices\n"
  head = head + "end_header\n"
  let out : Array[Byte] = []
  for b in @utf8.encode(head) {
    out.push(b)
  }
  for v in verts {
    let (x, y, z) = v
    ply_push_u32(out, f32_bits(x), big)
    ply_push_u32(out, f32_bits(y), big)
    ply_push_u32(out, f32_bits(z), big)
  }
  for f in faces {
    let (a, b, c) = f
    out.push(b'\x03')
    // int32 小端：编号都很小，高三个字节是 0
    for k in [a, b, c] {
      let mut byte = k & 0xFF
      if big {
        out.push(b'\x00')
        out.push(b'\x00')
        out.push(b'\x00')
        out.push(byte.to_byte())
      } else {
        out.push(byte.to_byte())
        out.push(b'\x00')
        out.push(b'\x00')
        out.push(b'\x00')
      }
      byte = 0
    }
  }
  Bytes::from_array(out)
}

// ── 三种编码 ────────────────────────────────────────────────────────────

///|
test "ASCII PLY 立方体" {
  let (verts, faces) = cube_ply_parts()
  let mesh = match parse_ply(ascii_ply("", "", verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 12)
  assert_true(close(mesh.volume(), 1.0))
  assert_true(close(mesh.surface_area(), 6.0))
}

///|
test "二进制小端 PLY 立方体" {
  let (verts, faces) = cube_ply_parts()
  let mesh = match parse_ply(binary_ply(false, verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 12)
  assert_true(close(mesh.volume(), 1.0))
}

///|
test "二进制大端 PLY 立方体" {
  let (verts, faces) = cube_ply_parts()
  let mesh = match parse_ply(binary_ply(true, verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 12)
  assert_true(close(mesh.volume(), 1.0))
}

///|
test "三种编码给出完全一样的结果" {
  // 同一份数据三种写法，只要有一种字节序读反了，这里立刻露馅
  let (verts, faces) = cube_ply_parts()
  let a = match parse_ply(ascii_ply("", "", verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("ASCII 失败：\{msg}")
  }
  let le = match parse_ply(binary_ply(false, verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("小端失败：\{msg}")
  }
  let be = match parse_ply(binary_ply(true, verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("大端失败：\{msg}")
  }
  let a_check = validate_default(a)
  let le_check = validate_default(le)
  let be_check = validate_default(be)
  assert_eq(le_check.unique_vertex_count, a_check.unique_vertex_count)
  assert_eq(be_check.unique_vertex_count, a_check.unique_vertex_count)
  assert_eq(le_check.boundary_edge_count, a_check.boundary_edge_count)
  assert_true(close(le.volume(), a.volume()))
  assert_true(close(be.volume(), a.volume()))
  // 三种都应该是水密的正方体
  assert_true(a_check.is_watertight())
  assert_true(le_check.is_watertight())
  assert_true(be_check.is_watertight())
}

// ── 编号从 0 开始 ───────────────────────────────────────────────────────

///|
test "PLY 的顶点编号从 0 开始，不是从 1" {
  // 这是最容易按 OBJ 的习惯写错的地方：OBJ 是 `f 1 2 3` 表示前三个顶点，
  // PLY 的 `3 0 1 2` 才是。搞混的话整个网格会偏移一位
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 3\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "element face 1\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n" +
    "0 0 0\n" +
    "1 0 0\n" +
    "0 1 0\n" +
    "3 0 1 2\n"
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 1)
  let t = mesh.triangles[0]
  // 三个顶点必须原样对上下标 0/1/2
  assert_true(close(t.a.x, 0.0))
  assert_true(close(t.b.x, 1.0))
  assert_true(close(t.c.y, 1.0))
  // 三角形面积 = 1/2，用这个反查坐标有没有错位
  assert_true(close(mesh.surface_area(), 0.5))
}

///|
test "行尾多出没声明的值时，不能把后面的元素带偏" {
  // 真实例子：trimesh 自带的 `fuze_ascii.ply`，头里声明每个 face 15 个值，
  // 实际数据每行有 21 个。按 token 流一路读下去的话，第一行多出来的值
  // 会让后面所有面错位，报一个莫名其妙的「编号不是整数：0.629012」。
  //
  // 处理办法是读完一个元素就跳到下一行。这条测试钉住这个行为
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 3\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "element face 1\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n" +
    "0 0 0\n1 0 0\n0 1 0\n" +
    "3 0 1 2 99 99 99 99\n"
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail("行尾多几个值不该导致失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 1)
  // 面积对得上说明三个顶点没读错位
  assert_true(close(mesh.surface_area(), 0.5))
}

///|
test "一个元素跨多行也能读" {
  // 上一版改成按行读之后，得确认没把「跨行」这条路堵死——
  // 规范里 ASCII 正文只说是空白分隔，没规定一行一个元素
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 3\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "element face 1\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n" +
    "0 0\n0\n1 0 0\n0 1\n0\n" +
    "3 0\n1 2\n"
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail("跨行的数据不该读不了：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 1)
  assert_true(close(mesh.surface_area(), 0.5))
}

///|
test "编号越界要报错" {
  let (verts, _faces) = cube_ply_parts()
  let bad : Array[(Int, Int, Int)] = [(0, 1, 99)]
  match parse_ply(ascii_ply("", "", verts, bad)) {
    Ok(_) => fail("越界的编号不该成功")
    Err(msg) => assert_true(msg.contains("越界"))
  }
}

// ── 未知属性 ────────────────────────────────────────────────────────────

///|
test "法线和颜色这些属性要跳过，但不能错位" {
  // 扫描仪导出的 PLY 基本都带 nx/ny/nz 和 red/green/blue。
  // 跳的时候少读一个字节，后面的坐标就全错位了——
  // 而且错位之后解析照样「成功」，只是网格是垃圾
  let (verts, faces) = cube_ply_parts()
  let extra = "property float nx\nproperty float ny\nproperty float nz\n" +
    "property uchar red\nproperty uchar green\nproperty uchar blue\n"
  let mut body_v = ""
  for v in verts {
    let (x, y, z) = v
    body_v = body_v + "\{x} \{y} \{z} 0.0 0.0 1.0 255 0 0\n"
  }
  let mut body_f = ""
  for f in faces {
    let (a, b, c) = f
    body_f = body_f + "3 \{a} \{b} \{c}\n"
  }
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex \{verts.length()}\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    extra +
    "element face \{faces.length()}\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n" +
    body_v +
    body_f
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  // 错位的话体积就不对了
  assert_eq(mesh.triangle_count(), 12)
  assert_true(close(mesh.volume(), 1.0))
}

///|
test "二进制里未知属性也要按字节跳对" {
  // 二进制更凶：ASCII 里错位了至少还是「一串数字」，
  // 二进制里错位就是拿 float 的字节当 uchar 读，读出来的东西毫无意义
  let (verts, faces) = cube_ply_parts()
  let head = "ply\nformat binary_little_endian 1.0\n" +
    "element vertex \{verts.length()}\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "property uchar red\nproperty uchar green\nproperty uchar blue\n" +
    "element face \{faces.length()}\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n"
  let out : Array[Byte] = []
  for b in @utf8.encode(head) {
    out.push(b)
  }
  for v in verts {
    let (x, y, z) = v
    ply_push_u32(out, f32_bits(x), false)
    ply_push_u32(out, f32_bits(y), false)
    ply_push_u32(out, f32_bits(z), false)
    out.push(b'\xFF')
    out.push(b'\x00')
    out.push(b'\x00')
  }
  for f in faces {
    let (a, b, c) = f
    out.push(b'\x03')
    for k in [a, b, c] {
      out.push(k.to_byte())
      out.push(b'\x00')
      out.push(b'\x00')
      out.push(b'\x00')
    }
  }
  let mesh = match parse_ply(Bytes::from_array(out)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 12)
  assert_true(close(mesh.volume(), 1.0))
}

// ── 多边形面 ────────────────────────────────────────────────────────────

///|
test "四边形面要三角化成两个" {
  // 正方形的底面，一个面四个点。PLY 的面天生是多边形
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 4\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "element face 1\n" +
    "property list uchar int vertex_indices\n" +
    "end_header\n" +
    "0 0 0\n1 0 0\n1 1 0\n0 1 0\n" +
    "4 0 1 2 3\n"
  let mesh = match parse_ply(@utf8.encode(text)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  // n 边形扇形三角化出 n-2 个三角形
  assert_eq(mesh.triangle_count(), 2)
  assert_true(close(mesh.surface_area(), 1.0))
}

// ── 坏文件 ──────────────────────────────────────────────────────────────

///|
test "只有点云没有面要报错" {
  // 扫描仪只扫点云不重建面的时候就是这样。文件是合法的，
  // 但没法当网格用，错误信息要说清楚
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 3\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "end_header\n" +
    "0 0 0\n1 0 0\n0 1 0\n"
  match parse_ply(@utf8.encode(text)) {
    Ok(_) => fail("没有面不该成功")
    Err(msg) => assert_true(msg.contains("点云"))
  }
}

///|
test "数据被截断要报错" {
  let (verts, faces) = cube_ply_parts()
  let full = ascii_ply("", "", verts, faces)
  // 只砍掉最后 30 字节——保证切点落在**正文里**。
  // （砍太狠会切到头部中间，那报的是「找不到 end_header」，测不到想测的那条路径）
  let cut = Bytes::from_array(full.to_fixedarray()[:full.length() - 30])
  match parse_ply(cut) {
    Ok(_) => fail("截断的文件不该成功")
    Err(msg) => assert_true(msg.contains("截断"))
  }
}

///|
test "没有 end_header 要报错" {
  match parse_ply(@utf8.encode("ply\nformat ascii 1.0\nelement vertex 3\n")) {
    Ok(_) => fail("没有 end_header 不该成功")
    Err(msg) => assert_true(msg.contains("end_header"))
  }
}

///|
test "认不出的类型要报错" {
  let text = "ply\nformat ascii 1.0\n" +
    "element vertex 1\n" +
    "property float128 x\n" +
    "end_header\n0\n"
  match parse_ply(@utf8.encode(text)) {
    Ok(_) => fail("不认识的类型不该成功")
    Err(msg) => assert_true(msg.contains("float128"))
  }
}

///|
test "不是 PLY 要报错" {
  match parse_ply(@utf8.encode("solid cube\n")) {
    Ok(_) => fail("不该成功")
    Err(msg) => assert_true(msg.contains("不是 PLY"))
  }
}

// ── 和统一入口接得上 ────────────────────────────────────────────────────

///|
test "detect_format 认得出 PLY" {
  let (verts, faces) = cube_ply_parts()
  let data = ascii_ply("", "", verts, faces)
  assert_true(detect_format(data) is Ply)
  assert_true(is_ply(data))
  // 统一入口也要走对分支
  let mesh = match parse_mesh(data) {
    Ok(m) => m
    Err(msg) => fail("parse_mesh 失败：\{msg}")
  }
  assert_eq(mesh.triangle_count(), 12)
}

///|
test "二进制 STL 的头以 ply 开头也不会被误判" {
  // is_ply 要求 `ply` 后面跟换行，就是为了防这个：
  // 二进制 STL 那 80 字节头是自由的，写什么都合法
  let header : Array[Byte] = []
  for b in @utf8.encode("plythis is a binary stl header") {
    header.push(b)
  }
  while header.length() < 80 {
    header.push(b'\x00')
  }
  let body : Array[Byte] = []
  for _i = 0; _i < 50; _i = _i + 1 {
    body.push(b'\x00')
  }
  let count = body.length() / 50
  header.push((count & 0xFF).to_byte())
  header.push(((count >> 8) & 0xFF).to_byte())
  header.push(((count >> 16) & 0xFF).to_byte())
  header.push(((count >> 24) & 0xFF).to_byte())
  for b in body {
    header.push(b)
  }
  let data = Bytes::from_array(header)
  assert_false(is_ply(data))
  // 长度正好对上，应该认成二进制 STL
  assert_true(detect_format(data) is Binary)
}

// ── 导出 ────────────────────────────────────────────────────────────────

///|
test "导出的二进制 PLY 能读回来，几何一模一样" {
  // 导出器的正确性就靠往返：写出去、读回来、和原件逐项比。
  // 只测「写出来没报错」等于没测——字节序写反了照样不报错
  let original = cube_mesh()
  let data = write_ply(original)
  let back = match parse_ply(data) {
    Ok(m) => m
    Err(msg) => fail("读不回来：\{msg}")
  }
  assert_eq(back.triangle_count(), 12)
  assert_true(close(back.volume(), 1.0))
  assert_true(close(back.surface_area(), 6.0))
  let before = validate_default(original)
  let after = validate_default(back)
  assert_eq(after.unique_vertex_count, before.unique_vertex_count)
  assert_eq(after.boundary_edge_count, before.boundary_edge_count)
  assert_eq(after.euler_number(), before.euler_number())
}

///|
test "导出的 ASCII PLY 能读回来" {
  let back = match parse_ply(@utf8.encode(write_ply_ascii(cube_mesh()))) {
    Ok(m) => m
    Err(msg) => fail("读不回来：\{msg}")
  }
  assert_eq(back.triangle_count(), 12)
  assert_true(close(back.volume(), 1.0))
}

///|
test "导出时顶点要去重" {
  // 我们的 Mesh 是三角形列表，立方体存了 36 个顶点；
  // PLY 是共享顶点表格式，只该写 8 个。
  //
  // 不去重的话文件大三倍，而且和「PLY 就是共享顶点格式」这件事对不上。
  // 这一条直接数导出的顶点数
  let text = write_ply_ascii(cube_mesh())
  assert_true(text.contains("element vertex 8\n"))
  assert_true(text.contains("element face 12\n"))
  // 8 个顶点 + 12 个面 = 20 行数据
  let mut data_lines = 0
  let mut seen_header = false
  for raw in text.split("\n") {
    if seen_header {
      if raw.length() > 0 {
        data_lines = data_lines + 1
      }
    }
    if raw == "end_header" {
      seen_header = true
    }
  }
  assert_eq(data_lines, 20)
}

///|
test "导出的三种格式互相一致" {
  // 同一个网格导出成 STL / OBJ / PLY 再读回来，几何必须一致。
  // 三个导出器各写各的，这条能把「某个导出器把坐标写错了」抓出来
  let mesh = cube_mesh()
  let from_stl = match parse_stl_binary(write_stl_binary(mesh)) {
    Ok(m) => m
    Err(msg) => fail("STL 往返失败：\{msg}")
  }
  let from_obj = match parse_obj(write_obj(mesh)) {
    Ok(m) => m
    Err(msg) => fail("OBJ 往返失败：\{msg}")
  }
  let from_ply = match parse_ply(write_ply(mesh)) {
    Ok(m) => m
    Err(msg) => fail("PLY 往返失败：\{msg}")
  }
  assert_true(close(from_stl.volume(), from_obj.volume()))
  assert_true(close(from_obj.volume(), from_ply.volume()))
  assert_true(close(from_stl.surface_area(), from_ply.surface_area()))
  // 重心也要一致——它比体积更敏感，坐标错位一点就偏
  let cs = from_stl.center_mass()
  let cp = from_ply.center_mass()
  assert_true(close(cs.x, cp.x))
  assert_true(close(cs.y, cp.y))
  assert_true(close(cs.z, cp.z))
}

///|
test "write_mesh 按后缀选 PLY" {
  let data = match write_mesh(cube_mesh(), "out.ply") {
    Ok(d) => d
    Err(msg) => fail("不该失败：\{msg}")
  }
  assert_true(is_ply(data))
  assert_true(detect_format(data) is Ply)
  // 大小写不敏感
  assert_true(write_mesh(cube_mesh(), "OUT.PLY") is Ok(_))
}

///|
test "导出的 PLY 头是合规的" {
  // 头写错了别的软件读不了，而自己的解析器可能照样能读——
  // 所以这里直接查文本内容，不靠往返
  let text = write_ply_ascii(cube_mesh())
  assert_true(text.has_prefix("ply\n"))
  assert_true(text.contains("format ascii 1.0\n"))
  assert_true(text.contains("property float x\n"))
  assert_true(text.contains("property float y\n"))
  assert_true(text.contains("property float z\n"))
  assert_true(text.contains("property list uchar int vertex_indices\n"))
  assert_true(text.contains("end_header\n"))
  let bin = write_ply_binary(cube_mesh())
  assert_true(
    @utf8
      .decode_lossy(bin[:40])
      .contains("format binary_little_endian 1.0"),
  )
}

///|
test "空网格导出不崩" {
  let text = write_ply_ascii(Mesh::empty())
  assert_true(text.contains("element vertex 0\n"))
  assert_true(text.contains("element face 0\n"))
  let bin = write_ply_binary(Mesh::empty())
  assert_true(is_ply(bin))
}

///|
test "PLY 解析出来的网格能走校验和预览" {
  let (verts, faces) = cube_ply_parts()
  let mesh = match parse_ply(ascii_ply("", "", verts, faces)) {
    Ok(m) => m
    Err(msg) => fail("解析失败：\{msg}")
  }
  let check = validate_default(mesh)
  assert_true(check.is_watertight())
  assert_eq(count_parts_default(mesh), 1)
  assert_eq(check.euler_number(), 2)
  let svg = render_svg(mesh, PreviewOptions::default())
  assert_true(svg.contains("<svg"))
}
