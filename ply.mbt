// PLY 解析。
//
// PLY（Polygon File Format，也叫 Stanford Triangle Format）是**三维扫描仪**
// 常见输出格式。本库对 PLY 全量读取；分块扫描入口只针对二进制 STL。
//
// 格式结构很简单，一个纯文本头 + 一段数据：
//
//     ply
//     format binary_little_endian 1.0
//     element vertex 8
//     property float x
//     property float y
//     property float z
//     element face 12
//     property list uchar int vertex_indices
//     end_header
//     <按上面声明的顺序排列的数据>
//
// 和 STL / OBJ / 3MF 都不一样的地方在于：**头部是自描述的**。
// 有哪些元素、每个元素有哪些属性、属性是什么类型，全写在头里。
// 所以解析器不能写死「顶点就是三个 float」——得先读头，再按头里说的读数据。
//
// 这也意味着**未知属性必须能正确跳过**。扫描仪导出的 PLY 常带
// nx/ny/nz（法线）、red/green/blue（颜色）、甚至纹理坐标，
// 跳不过去后面全乱。

///|
/// PLY 的一个属性：要么是一个标量，要么是一个列表。
///
/// 列表在 PLY 里就用在面上——`property list uchar int vertex_indices`
/// 意思是「先读一个 uchar 表示有几个顶点，再读那么多个 int」。
/// 所以多边形面在 PLY 里天生就是变长的，不像 STL 那样固定三个。
priv enum PlyProp {
  /// 标量：属性名 + 类型
  Scalar(String, String)
  /// 列表：属性名 + 计数类型 + 元素类型
  List(String, String, String)
}

///|
/// 头里声明的一个元素。
priv struct PlyElement {
  /// 元素名：`vertex` / `face` / 其它
  name : String
  /// 有多少个
  count : Int32
  /// 每个元素有哪些属性，**顺序就是数据里的顺序**
  props : Array[PlyProp]
}

///|
/// 解析出来的文件头。
priv struct PlyHeader {
  /// true = 二进制，false = ASCII
  binary : Bool
  /// 二进制时才有意义：true = 大端
  big_endian : Bool
  /// 元素按声明顺序排列
  elements : Array[PlyElement]
}

///|
/// 是不是 PLY。
///
/// 规范里第一行必须是 `ply`，所以要求后面跟换行——只比三个字母的话，
/// 万一有个二进制 STL 的文件头恰好以 "ply" 开头就会误判
/// （STL 那 80 字节头是自由的，写什么都合法）。
pub fn is_ply(data : Bytes) -> Bool {
  data.length() >= 4 &&
  data[0] == b'p' &&
  data[1] == b'l' &&
  data[2] == b'y' &&
  (data[3] == b'\n' || data[3] == b'\r')
}

///|
/// 解析 PLY。ASCII 和二进制（小端 / 大端）三种都支持。
/// ASCII 默认连续消费空白分隔 token，不丢弃行尾，拒绝声明外的尾随数据。
/// lenient_ascii=true 仅用于每条记录占一行、行尾有未声明值的异常 ASCII 文件。
pub fn parse_ply(
  data : Bytes,
  lenient_ascii~ : Bool = false,
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Mesh, String] {
  if input_limit_error(data, limits) is Some(error) {
    return Err(error)
  }
  if !is_ply(data) {
    return Err("这不是 PLY 文件（开头不是 ply）")
  }
  let body_at = match find_header_end(data) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let header = match parse_header(@utf8.decode_lossy(data[:body_at])) {
    Ok(h) => h
    Err(msg) => return Err(msg)
  }
  match validate_ply_vertex_schema(header) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  let mut records = 0L
  let mut vertices = 0L
  let mut faces = 0L
  for element in header.elements {
    let names : Map[String, Unit] = Map([])
    let mut indices = 0
    for property in element.props {
      let name = match property {
        Scalar(name, _) | List(name, _, _) => name
      }
      if names.contains(name) {
        return Err("PLY element 重复声明属性：\{name}")
      }
      names[name] = ()
      if element.name == "face" &&
        (name == "vertex_indices" || name == "vertex_index") {
        indices += 1
        match property {
          Scalar(_, _) => return Err("PLY face 顶点索引必须为 list")
          List(_, _, _) => ()
        }
      }
    }
    if element.name == "face" && indices != 1 {
      return Err(
        "PLY face 必须恰好声明一个 vertex_indices / vertex_index 列表，不能缺少或重复",
      )
    }
    records += element.count.to_int64()
    if element.name == "vertex" {
      vertices += element.count.to_int64()
    }
    if element.name == "face" {
      faces += element.count.to_int64()
    }
  }
  if records > limits.max_records.to_int64() {
    return Err(resource_error("max_records", limits.max_records))
  }
  if vertices > limits.max_vertices.to_int64() {
    return Err(resource_error("max_vertices", limits.max_vertices))
  }
  if faces > limits.max_triangles.to_int64() {
    return Err(resource_error("max_triangles", limits.max_triangles))
  }
  if !header.binary {
    if text_limit_error(@utf8.decode_lossy(data), limits) is Some(error) {
      return Err(error)
    }
  }
  let cursor = match
    PlyCursor::new(
      data,
      body_at,
      header.binary,
      header.big_endian,
      lenient_ascii,
    ) {
    Ok(c) => c
    Err(msg) => return Err(msg)
  }
  read_body(cursor, header, limits~)
}

///|
/// 在读取任何正文前验证每个 vertex 元素，三坐标必须各有一个标量属性。
/// 未知属性仍可读取后丢弃；兼容 ASCII 模式不放宽坐标声明。
fn validate_ply_vertex_schema(header : PlyHeader) -> Result[Unit, String] {
  for element in header.elements {
    if element.name != "vertex" {
      continue
    }
    for coordinate in ["x", "y", "z"] {
      let mut count = 0
      for property in element.props {
        match property {
          Scalar(name, _) => if name == coordinate { count = count + 1 }
          List(name, _, _) =>
            if name == coordinate {
              return Err(
                "PLY vertex 的 \{coordinate} 属性必须为标量，不能声明为 list",
              )
            }
        }
      }
      if count == 0 {
        return Err("PLY vertex 缺少 \{coordinate} 标量属性")
      }
      if count > 1 {
        return Err("PLY vertex 重复声明 \{coordinate} 属性")
      }
    }
  }
  Ok(())
}

///|
/// 找 `end_header` 那一行的结尾，返回正文第一个字节的下标。
///
/// 不用「找 end_header 子串」是因为那串字也可能出现在 comment 里
/// （比如 `comment generated by end_header_tool`）。逐行比才准。
fn find_header_end(data : Bytes) -> Result[Int32, String] {
  // 头只有几百字节，但文件可能几百 MB——限制扫描范围，别为找头把整个文件过一遍
  let limit = if data.length() < 65536 { data.length() } else { 65536 }
  let mut line_start = 0
  let mut i = 0
  while i < limit {
    if data[i] == b'\n' {
      // 这一行是 [line_start, i)，去掉可能的 \r
      let mut line_end = i
      if line_end > line_start && data[line_end - 1] == b'\r' {
        line_end = line_end - 1
      }
      if line_equals_ascii(data, line_start, line_end, "end_header") {
        return Ok(i + 1)
      }
      line_start = i + 1
    }
    i = i + 1
  }
  if data.length() >= 65536 {
    Err(
      "resource_limit: PLY header exceeds fixed 65536-byte limit or lacks end_header within it",
    )
  } else {
    Err("PLY 文件里找不到 end_header，头不完整")
  }
}

///|
/// 比较 [from, to) 这段字节是不是等于给定的 ASCII 串。
fn line_equals_ascii(
  data : Bytes,
  from : Int32,
  to : Int32,
  want : String,
) -> Bool {
  if to - from != want.length() {
    return false
  }
  for k = 0; k < want.length(); k = k + 1 {
    // 刻意只支持 ASCII：PLY 的关键字都是 ASCII，
    // 而 want[k] 取的是码元，非 ASCII 字符根本不会等于单字节
    if data[from + k].to_int() != want.code_unit_at(k).to_int() {
      return false
    }
  }
  true
}

///|
/// 解析文件头。
fn parse_header(text : String) -> Result[PlyHeader, String] {
  let elements : Array[PlyElement] = []
  let mut binary = false
  let mut big_endian = false
  let mut cur : PlyElement? = None
  let mut done = false
  let mut format_seen = false
  let mut line_no = 0

  for raw in text.split("\n") {
    if done {
      break
    }
    line_no = line_no + 1
    let tokens = ascii_tokens(strip_cr(raw))
    if line_no == 1 {
      if !(tokens is ["ply"]) {
        return Err("PLY header 的第一行必须为 ply")
      }
      continue
    }
    // 不从默认布尔值猜测编码；format 必须紧跟魔数，先于任何元素声明。
    if !format_seen && !(tokens is ["format", ..]) {
      return Err(
        "PLY header 缺少 format 声明（必须紧跟 ply，位于 element 之前）",
      )
    }
    match tokens {
      ["end_header"] => done = true
      ["format", kind, version] => {
        if format_seen {
          return Err("PLY header 重复声明 format")
        }
        if version != "1.0" {
          return Err("当前只支持 PLY 1.0，收到版本「\{version}」")
        }
        match kind {
          "ascii" => binary = false
          "binary_little_endian" => {
            binary = true
            big_endian = false
          }
          "binary_big_endian" => {
            binary = true
            big_endian = true
          }
          _ => return Err("PLY 的 format 认不出来：「\{kind}」")
        }
        format_seen = true
      }
      ["format", ..] =>
        if format_seen {
          return Err("PLY header 重复声明 format")
        } else {
          return Err(
            "PLY format 必须完整声明为 format <编码> 1.0，不能缺少或增加字段",
          )
        }
      ["element", name, count] => {
        // 上一个元素收尾
        match cur {
          Some(e) => elements.push(e)
          None => ()
        }
        let n = match parse_count(count) {
          Ok(v) => v
          Err(msg) => return Err(msg)
        }
        cur = Some({ name: name.to_owned(), count: n, props: [], })
      }
      ["property", "list", count_ty, item_ty, name] => {
        let e = match cur {
          Some(e) => e
          None => return Err("PLY 的 property 出现在 element 之前")
        }
        if ply_integer_range(count_ty) is None {
          return Err("PLY list 的计数类型必须是整数类型")
        }
        if ply_type_size(count_ty) is None {
          return Err("PLY 里有个不认识的类型「\{count_ty}」")
        }
        if ply_type_size(item_ty) is None {
          return Err("PLY 里有个不认识的类型「\{item_ty}」")
        }
        e.props.push(
          List(name.to_owned(), count_ty.to_owned(), item_ty.to_owned()),
        )
      }
      ["property", ty, name] => {
        let e = match cur {
          Some(e) => e
          None => return Err("PLY 的 property 出现在 element 之前")
        }
        if ply_type_size(ty) is None {
          return Err("PLY 里有个不认识的类型「\{ty}」")
        }
        e.props.push(Scalar(name.to_owned(), ty.to_owned()))
      }
      ["comment", ..] | ["obj_info", ..] | [] => ()
      _ => return Err("PLY header 存在未知或不完整声明：\{raw}")
    }
  }
  if !format_seen {
    return Err("PLY header 缺少 format 声明")
  }
  if !done {
    return Err("PLY header 缺少 end_header")
  }
  match cur {
    Some(e) => elements.push(e)
    None => ()
  }

  if elements.length() == 0 {
    return Err("PLY 头里没有声明任何 element")
  }
  Ok({ binary, big_endian, elements, })
}

///|
/// 解析一个元素的数量。PLY 头里写的是十进制整数。
fn parse_count(s : StringView) -> Result[Int32, String] {
  profile_decimal_int(s, 0)
}

///|
/// PLY 里各种类型占几个字节。不认识返回 `None`。
///
/// 类型名有新旧两套写法（`uchar` 和 `uint8`、`int` 和 `int32`），
/// 规范里两套都合法，都得认。
fn ply_type_size(t : StringView) -> Int32? {
  match t {
    "char" | "int8" | "uchar" | "uint8" => Some(1)
    "short" | "int16" | "ushort" | "uint16" => Some(2)
    "int" | "int32" | "uint" | "uint32" | "float" | "float32" => Some(4)
    "double" | "float64" => Some(8)
    _ => None
  }
}

///|
/// 是不是有符号类型。二进制的有符号和无符号读法不同。
fn ply_type_signed(t : StringView) -> Bool {
  match t {
    "char" | "int8" | "short" | "int16" | "int" | "int32" => true
    _ => false
  }
}

// ── 数据读取 ────────────────────────────────────────────────────────────
//
// ASCII 和二进制只是「怎么把一个数拿出来」不同，**按头里声明的顺序走**
// 这件事是一样的。所以抽一个游标，两种格式共用同一套走法——
// 不然那套嵌套循环（元素 → 实例 → 属性 → 列表项）要写两遍，
// 改一处漏一处。

///|
/// 数据游标。ASCII 模式下吃 token，二进制模式下按字节走。
priv struct PlyCursor {
  binary : Bool
  big_endian : Bool
  /// 二进制用：原始字节
  data : Bytes
  mut at : Int32
  /// 默认跨行连续消费；保留行边界仅供显式的异常文件兼容模式使用。
  lines : Array[Array[StringView]]
  mut li : Int32
  mut ci : Int32
  lenient_ascii : Bool
}

///|
/// 建游标。ASCII 模式会先把正文切成 token——注意 PLY 的 ASCII 正文
/// 是按空白分隔的，**不是按行**，所以不能只按空格切。
fn PlyCursor::new(
  data : Bytes,
  body_at : Int32,
  binary : Bool,
  big_endian : Bool,
  lenient_ascii : Bool,
) -> Result[PlyCursor, String] {
  if binary {
    Ok({
      binary: true,
      big_endian,
      data,
      at: body_at,
      lines: [],
      li: 0,
      ci: 0,
      lenient_ascii: false,
    })
  } else {
    let text = @utf8.decode_lossy(data[body_at:])
    Ok({
      binary: false,
      big_endian: false,
      data,
      at: body_at,
      lines: ascii_lines(text),
      li: 0,
      ci: 0,
      lenient_ascii,
    })
  }
}

///|
/// 把一段文本先按行切、每行再按空白切成 token。
fn ascii_lines(text : String) -> Array[Array[StringView]] {
  let out : Array[Array[StringView]] = []
  for raw in text.split("\n") {
    out.push(ascii_tokens(raw))
  }
  out
}

///|
fn ascii_tokens(s : StringView) -> Array[StringView] {
  let tokens : Array[StringView] = []
  let mut i = 0
  while i < s.length() {
    while i < s.length() && is_ascii_space(s.code_unit_at(i).to_int()) {
      i = i + 1
    }
    let start = i
    while i < s.length() && !is_ascii_space(s.code_unit_at(i).to_int()) {
      i = i + 1
    }
    if i > start {
      tokens.push(s[start:i])
    }
  }
  tokens
}

///|
fn is_ascii_space(c : Int32) -> Bool {
  c == 0x20 || (c >= 0x09 && c <= 0x0D)
}

///|
/// 前进到下一个非空 token，但不消费；严格模式可跨越任意行边界。
fn PlyCursor::has_ascii_token(self : PlyCursor) -> Bool {
  while self.li < self.lines.length() && self.ci >= self.lines[self.li].length() {
    self.li = self.li + 1
    self.ci = 0
  }
  self.li < self.lines.length()
}

///|
fn PlyCursor::begin_element(self : PlyCursor) -> Unit {
  if !self.binary && self.lenient_ascii {
    ignore(self.has_ascii_token())
  }
}

///|
/// 不是有限数（NaN 或 ±Infinity）。
///
/// 抽出来是因为要在几个地方反复判——而且条件写一长串的话，
/// 断行位置稍有不对 MoonBit 就会报「missing `{`」。
fn not_finite(v : Double) -> Bool {
  v.is_nan() || v.is_inf()
}

///|
/// 读一个数，当成浮点用。
fn PlyCursor::next_double(
  self : PlyCursor,
  ty : String,
) -> Result[Double, String] {
  if self.binary {
    let size = match ply_type_size(ty[:]) {
      Some(s) => s
      None => return Err("PLY 里有个不认识的类型「\{ty}」")
    }
    if self.at + size > self.data.length() {
      return Err(
        "PLY 的数据在读到一半就没了——文件被截断了",
      )
    }
    let raw = read_ply_number(self.data, self.at, ty, self.big_endian)
    self.at = self.at + size
    Ok(raw)
  } else {
    if !self.lenient_ascii {
      ignore(self.has_ascii_token())
    }
    if self.li >= self.lines.length() {
      return Err(
        "PLY 的数据在读到一半就没了——文件被截断了",
      )
    }
    if self.ci >= self.lines[self.li].length() {
      return Err(
        "PLY 宽松模式要求每条记录占一行，当前行属性不足",
      )
    }
    let tok = self.lines[self.li][self.ci]
    self.ci = self.ci + 1
    let value = @string.parse_double(tok) catch {
      _ => return Err("PLY 的数据里『\{tok}』不是一个数字")
    }
    match ply_integer_range(ty[:]) {
      Some((lo, hi)) =>
        if !profile_integer_token(tok) ||
          not_finite(value) ||
          value < lo ||
          value > hi {
          return Err(
            "PLY 整数属性超出声明类型 \{ty} 的词法或数值范围：\{tok}",
          )
        }
      None => ()
    }
    Ok(value)
  }
}

///|
/// 只有显式宽松模式才丢弃该记录所在行的尾随值；默认模式不改变游标。
fn PlyCursor::finish_element(self : PlyCursor) -> Unit {
  if !self.binary && self.lenient_ascii && self.li < self.lines.length() {
    self.li = self.li + 1
    self.ci = 0
  }
}

///|
/// 读一个数，当成整数用。
///
/// 单独一个函数是因为**面的顶点编号必须精确**：拿浮点接了再转整数，
/// 一个 `nan` 或者小数会静默变成 0 或者被截断，拼出来的面就是错的。
fn PlyCursor::next_int(self : PlyCursor, ty : String) -> Result[Int32, String] {
  let value = match self.next_double(ty) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  if value.is_nan() || value.is_inf() || value != value.round() {
    return Err("PLY 的数据里有个不是整数的编号：\{value}")
  }
  if value < -2147483648.0 || value > 2147483647.0 {
    return Err(
      "PLY 索引或列表长度超出当前实现的 32 位有符号范围",
    )
  }
  Ok(value.to_int())
}

///|
/// 取一个字节，当成无符号数。
fn u8_at(data : Bytes, at : Int32) -> Int32 {
  data[at].to_int() & 0xFF
}

///|
/// 从字节里按类型读一个数。
///
/// 二进制 PLY 有大小端两种，规范里都合法——同一份模型，
/// Solaris 时代的扫描仪导出的是大端，现代的基本都是小端。
fn read_ply_number(data : Bytes, at : Int32, ty : String, big : Bool) -> Double {
  let size = ply_type_size(ty[:])
  match ty {
    "float" | "float32" => {
      let bits = if big {
        (u8_at(data, at).reinterpret_as_uint() << 24) |
        (u8_at(data, at + 1).reinterpret_as_uint() << 16) |
        (u8_at(data, at + 2).reinterpret_as_uint() << 8) |
        u8_at(data, at + 3).reinterpret_as_uint()
      } else {
        (u8_at(data, at + 3).reinterpret_as_uint() << 24) |
        (u8_at(data, at + 2).reinterpret_as_uint() << 16) |
        (u8_at(data, at + 1).reinterpret_as_uint() << 8) |
        u8_at(data, at).reinterpret_as_uint()
      }
      Float::reinterpret_from_uint(bits).to_double()
    }
    "double" | "float64" => {
      let bits = u64_at(data, at, big)
      bits.reinterpret_as_double()
    }
    _ => {
      // 整数类：先按无符号拼出来，再按有无符号决定要不要减去模
      let raw = match size {
        Some(1) => u8_at(data, at).to_uint64()
        Some(2) => u16_at(data, at, big).to_uint64()
        Some(4) => u32_at(data, at, big).to_uint64()
        _ => u64_at(data, at, big)
      }
      if ply_type_signed(ty[:]) {
        match size {
          Some(1) =>
            if raw >= 128UL {
              raw.to_double() - 256.0
            } else {
              raw.to_double()
            }
          Some(2) =>
            if raw >= 32768UL {
              raw.to_double() - 65536.0
            } else {
              raw.to_double()
            }
          Some(4) =>
            if raw >= 2147483648UL {
              raw.to_double() - 4294967296.0
            } else {
              raw.to_double()
            }
          _ => raw.to_double()
        }
      } else {
        raw.to_double()
      }
    }
  }
}

///|
fn u16_at(data : Bytes, at : Int32, big : Bool) -> UInt32 {
  let a = u8_at(data, at)
  let b = u8_at(data, at + 1)
  (if big { a * 256 + b } else { b * 256 + a }).reinterpret_as_uint()
}

///|
fn u32_at(data : Bytes, at : Int32, big : Bool) -> UInt32 {
  let b0 = u8_at(data, at).reinterpret_as_uint()
  let b1 = u8_at(data, at + 1).reinterpret_as_uint()
  let b2 = u8_at(data, at + 2).reinterpret_as_uint()
  let b3 = u8_at(data, at + 3).reinterpret_as_uint()
  if big {
    (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  } else {
    (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
  }
}

///|
fn u64_at(data : Bytes, at : Int32, big : Bool) -> UInt64 {
  let mut v = 0UL
  for k = 0; k < 8; k = k + 1 {
    let byte = u8_at(data, at + k).to_uint64()
    if big {
      v = (v << 8) | byte
    } else {
      // 小端：第 k 个字节在低位算起第 k 个 8 位
      v = v | (byte << (k * 8))
    }
  }
  v
}

// ── 按头走一遍数据 ──────────────────────────────────────────────────────

///|
/// 照着头的声明把数据走一遍。
///
/// 只认 `vertex` 和 `face` 两种元素，别的一律跳过——**但跳过也得
/// 按声明把值读出来**，不然游标会错位，后面全乱。
fn read_body(
  cursor : PlyCursor,
  header : PlyHeader,
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Mesh, String] {
  let vertices : Array[Vec3] = []
  let polygons : Array[Array[Int32]] = []
  let triangles : Array[(Int32, Int32, Int32)] = []
  let mut list_items = 0L

  for element in header.elements {
    let is_vertex = element.name == "vertex"
    let is_face = element.name == "face"
    for _i = 0; _i < element.count; _i = _i + 1 {
      if !element.props.is_empty() {
        cursor.begin_element()
      }
      let mut x = 0.0
      let mut y = 0.0
      let mut z = 0.0
      let corners : Array[Int32] = []
      for prop in element.props {
        match prop {
          Scalar(name, ty) => {
            let value = match cursor.next_double(ty) {
              Ok(v) => v
              Err(msg) => return Err(msg)
            }
            // 只认 x/y/z。nx/ny/nz、red/green/blue 这些照读不误，
            // 只是读完就丢——**不能不读**，不读游标就错位了
            match name {
              "x" => x = value
              "y" => y = value
              "z" => z = value
              _ => ()
            }
          }
          List(name, count_ty, item_ty) => {
            let n = match cursor.next_int(count_ty) {
              Ok(v) => v
              Err(msg) => return Err(msg)
            }
            if n < 0 {
              return Err("PLY 的列表长度是个负数：\{n}")
            }
            list_items += n.to_int64()
            if list_items > limits.max_list_items.to_int64() {
              return Err(
                resource_error("max_list_items", limits.max_list_items),
              )
            }
            if is_face && (name == "vertex_indices" || name == "vertex_index") {
              if n > limits.max_polygon_vertices {
                return Err(
                  resource_error(
                    "max_polygon_vertices",
                    limits.max_polygon_vertices,
                  ),
                )
              }
              if ply_integer_range(item_ty[:]) is None {
                return Err(
                  "PLY face 顶点索引的列表项必须声明为整数类型",
                )
              }
              for _k = 0; _k < n; _k = _k + 1 {
                let idx = match cursor.next_int(item_ty) {
                  Ok(v) => v
                  Err(msg) => return Err(msg)
                }
                corners.push(idx)
              }
            } else {
              // 不是顶点编号的列表（比如纹理索引），读掉就好
              for _k = 0; _k < n; _k = _k + 1 {
                match cursor.next_double(item_ty) {
                  Ok(_) => ()
                  Err(msg) => return Err(msg)
                }
              }
            }
          }
        }
      }
      if is_vertex {
        // 坐标也要查有限性：`nan` / `inf` 混进来后面全是垃圾
        if not_finite(x) || not_finite(y) || not_finite(z) {
          return Err(
            "PLY 的第 \{vertices.length() + 1} 个顶点坐标不是有限数",
          )
        }
        vertices.push(Vec3::new(x, y, z))
      } else if is_face {
        polygons.push(corners)
      }
      if !element.props.is_empty() {
        cursor.finish_element()
      }
    }
  }

  if !cursor.binary && cursor.has_ascii_token() {
    return Err("PLY 的正文含有 header 未声明的多余数据")
  }
  if cursor.binary && cursor.at != cursor.data.length() {
    return Err(
      "二进制 PLY 的正文含有 header 未声明的多余尾部字节：\{cursor.data.length() - cursor.at} 字节",
    )
  }
  // 所有元素仍按 header 顺序消费；延后解析面索引，允许 face 在 vertex 之前声明。
  for corners in polygons {
    match append_polygon(vertices, corners, triangles, limits~) {
      Ok(_) => ()
      Err(msg) => return Err(msg)
    }
  }

  if triangles.length() == 0 {
    return Err(
      "这个 PLY 里一个三角形都没有（可能只有点云，没有面）",
    )
  }

  // 到这一步才把「下标三元组」换成真正的三角形。
  // 前面append_polygon 已经校验过下标范围，这里可以直接取
  let out : Array[Triangle] = []
  for (i, j, k) in triangles {
    out.push(Triangle::from_vertices(vertices[i], vertices[j], vertices[k]))
  }
  Ok(Mesh::new(out))
}

///|
/// 把一个面的顶点编号展开成三角形。
///
/// PLY 的面天生是多边形（列表长度可变），所以这里和 OBJ 一样要三角化，
/// 共用 OBJ 的凸多边形扇形切分和凹多边形耳切，保留原顶点下标。
/// 少于三个点的面明确拒绝，不静默丢弃。
///
/// 编号是**从 0 开始**的（这和 OBJ 不一样，OBJ 从 1 开始）——
/// 按 OBJ 的习惯写就会整体错一位，得到一个完全错误的网格。
///
/// 越界在这里就报，不留到后面——编号错了的话后面每个三角形都是错的，
/// 早报能说清是哪个面的问题。
fn append_polygon(
  vertices : Array[Vec3],
  corners : Array[Int32],
  triangles : Array[(Int32, Int32, Int32)],
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Unit, String] {
  if corners.length() < 3 {
    return Err("PLY face 至少需要三个顶点，不能静默丢弃")
  }
  if corners.length() > limits.max_polygon_vertices {
    return Err(
      resource_error("max_polygon_vertices", limits.max_polygon_vertices),
    )
  }
  if corners.length() - 2 > limits.max_triangles - triangles.length() {
    return Err(resource_error("max_triangles", limits.max_triangles))
  }
  let n = vertices.length()
  for k in corners {
    if k < 0 || k >= n {
      return Err(
        "PLY 里有个面的顶点编号越界（顶点表有 \{n} 个，引用到了 \{k}）",
      )
    }
  }
  let points : Array[Vec3] = []
  for k in corners {
    points.push(vertices[k])
  }
  let faces = match triangulate_polygon(points) {
    Ok(faces) => faces
    Err(msg) => return Err("PLY 的面：\{msg}")
  }
  for face in faces {
    triangles.push((corners[face.0], corners[face.1], corners[face.2]))
  }
  Ok(())
}

// ── 导出 ────────────────────────────────────────────────────────────────
//
// 对应 trimesh 的 `mesh.export('x.ply')`。有了导出，「PLY 读写」才齐。

///|
/// 把网格拆成 PLY 需要的两个数组：去重后的顶点表 + 面的下标。
///
/// **导出前要焊接顶点。** 我们的 Mesh 是三角形列表，一个立方体存了 36 个
/// 顶点（每个面重写一遍）；PLY 是共享顶点表格式，只需要 8 个。
/// 不焊接的话文件会大三倍，而且和「PLY 就是共享顶点格式」这件事对不上。
///
/// 用完整坐标键去重，和校验、流式扫描是同一套量化——
/// 「什么算同一个点」整个项目只有一个答案。
fn ply_arrays(mesh : Mesh) -> (Array[Vec3], Array[(Int32, Int32, Int32)]) {
  let table : Map[PositionKey, Int32] = Map([])
  let verts : Array[Vec3] = []
  let faces : Array[(Int32, Int32, Int32)] = []
  for t in mesh.triangles {
    let ia = ply_intern(table, verts, t.a)
    let ib = ply_intern(table, verts, t.b)
    let ic = ply_intern(table, verts, t.c)
    faces.push((ia, ib, ic))
  }
  (verts, faces)
}

///|
/// 查表拿编号，没有就登记一个新顶点。
fn ply_intern(
  table : Map[PositionKey, Int32],
  verts : Array[Vec3],
  v : Vec3,
) -> Int32 {
  let key = position_key(v, default_weld_tolerance())
  match table.get(key) {
    Some(id) => id
    None => {
      let id = verts.length()
      table.set(key, id)
      verts.push(v)
      id
    }
  }
}

///|
/// 导出成 ASCII PLY。
///
/// ASCII 的好处是人眼能看、能直接 diff；代价是文件大好几倍
/// （一个坐标要写十几位十进制，二进制只要 4 个字节）。
/// 要存下来给别人用就选二进制的那个。
pub fn write_ply_ascii(mesh : Mesh) -> String {
  let (verts, faces) = ply_arrays(mesh)
  let mut s = "ply\nformat ascii 1.0\ncomment created by stlkit\n"
  s = s + "element vertex \{verts.length()}\n"
  s = s + "property float x\nproperty float y\nproperty float z\n"
  s = s + "element face \{faces.length()}\n"
  s = s + "property list uchar int vertex_indices\n"
  s = s + "end_header\n"
  for v in verts {
    s = s + "\{v.x} \{v.y} \{v.z}\n"
  }
  for f in faces {
    let (a, b, c) = f
    s = s + "3 \{a} \{b} \{c}\n"
  }
  s
}

///|
/// 导出成二进制 PLY（小端）。
///
/// 选小端是因为**现在的读写器基本都是小端**，大端只剩考古价值了——
/// 但读的时候两种都得认，谁知道会收到什么文件。
pub fn write_ply_binary(mesh : Mesh) -> Bytes {
  let (verts, faces) = ply_arrays(mesh)
  let out : Array[Byte] = []
  let head = "ply\nformat binary_little_endian 1.0\ncomment created by stlkit\n" +
    "element vertex \{verts.length()}\n" +
    "property float x\nproperty float y\nproperty float z\n" +
    "element face \{faces.length()}\n" +
    "property list uchar int vertex_indices\nend_header\n"
  for b in @utf8.encode(head) {
    out.push(b)
  }
  for v in verts {
    push_f32(out, v.x)
    push_f32(out, v.y)
    push_f32(out, v.z)
  }
  for f in faces {
    let (a, b, c) = f
    // 列表长度写成 uchar（规范里声明的是 uchar）
    out.push(b'\x03')
    push_u32(out, a)
    push_u32(out, b)
    push_u32(out, c)
  }
  Bytes::from_array(out)
}

///|
/// 导出成 PLY，默认走二进制——和 trimesh 的默认一致，文件也小得多。
pub fn write_ply(mesh : Mesh) -> Bytes {
  write_ply_binary(mesh)
}
