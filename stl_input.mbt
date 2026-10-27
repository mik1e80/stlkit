// STL 各入口共用的输入契约，不包含网格几何有效性判定。

///|
fn stl_binary_length_error(count : UInt32, actual : UInt64) -> String? {
  if actual < 84UL {
    return Some(
      "二进制 STL 至少要 84 字节（80 字节文件头 + 4 字节三角形数），这个文件只有 \{actual} 字节",
    )
  }
  let expected = 84UL + count.to_uint64() * 50UL
  if actual < expected {
    return Some(
      "二进制 STL 头部声称有 \{count} 个三角形（需要 \{expected} 字节），但文件只有 \{actual} 字节，文件被截断了",
    )
  }
  if actual > expected {
    return Some(
      "二进制 STL 头部声称有 \{count} 个三角形（需要 \{expected} 字节），但文件有 \{actual} 字节，含多余尾部字节",
    )
  }
  if count == 0U {
    return Some("这个二进制 STL 里一个三角形都没有")
  }
  None
}

///|
fn stl_binary_count(data : Bytes) -> Result[Int32, String] {
  let count = if data.length() >= 84 { read_u32_le(data, 80) } else { 0U }
  if stl_binary_length_error(count, data.length().to_uint64()) is Some(message) {
    return Err(message)
  }
  if count > 2147483647U {
    return Err("二进制 STL 三角形数量超出当前实现支持范围")
  }
  Ok(count.reinterpret_as_int())
}

///|
fn stl_binary_record_error(
  data : Bytes,
  base : Int32,
  index : Int32,
) -> String? {
  for offset in [0, 12, 24, 36] {
    if !finite_vertex(read_vec3_f32(data, base + offset)) {
      return Some(
        "二进制 STL 第 \{index + 1} 个三角形的坐标或法线不是有限数字",
      )
    }
  }
  None
}

///|
priv enum StlAsciiStage {
  Outside
  NeedLoop
  Vertices
  NeedEndfacet
} derive(Eq)

///|
priv struct StlAsciiReader {
  mut stage : StlAsciiStage
  mut normal : Vec3
  pending : Array[Vec3]
  mut line_no : Int32
}

///|
fn stl_ascii_tokens(line : StringView) -> Array[StringView] {
  let tokens = []
  let mut pos = 0
  while pos < line.length() {
    if is_ascii_space(line.code_unit_at(pos).to_int()) {
      pos = pos + 1
      continue
    }
    let start = pos
    while pos < line.length() &&
          !is_ascii_space(line.code_unit_at(pos).to_int()) {
      pos = pos + 1
    }
    tokens.push(line[start:pos])
  }
  tokens
}

///|
fn StlAsciiReader::read_line(
  self : StlAsciiReader,
  line : StringView,
) -> Result[Triangle?, String] {
  self.line_no = self.line_no + 1
  let tokens = stl_ascii_tokens(line)
  let error = "第 \{self.line_no} 行：ASCII STL 记录顺序或字段不合法"
  match tokens {
    [] => ()
    ["solid", ..] | ["endsolid", ..] =>
      if self.stage != Outside {
        return Err("第 \{self.line_no} 行：facet 尚未结束")
      }
    ["facet", "normal", x, y, z] => {
      if self.stage != Outside {
        return Err("第 \{self.line_no} 行：前一个 facet 尚未结束")
      }
      self.normal = match parse_vec3(x, y, z, self.line_no) {
        Ok(v) => v
        Err(message) => return Err(message)
      }
      self.pending.clear()
      self.stage = NeedLoop
    }
    ["outer", "loop"] => {
      if self.stage != NeedLoop {
        return Err(error)
      }
      self.stage = Vertices
    }
    ["vertex", x, y, z] => {
      if self.stage != Vertices {
        return Err(error)
      }
      if self.pending.length() == 3 {
        return Err(
          "第 \{self.line_no} 行：一个面超过 3 个顶点，应该是 3 个",
        )
      }
      match parse_vec3(x, y, z, self.line_no) {
        Ok(v) => self.pending.push(v)
        Err(message) => return Err(message)
      }
    }
    ["endloop"] => {
      if self.stage != Vertices {
        return Err(error)
      }
      if self.pending.length() != 3 {
        return Err(
          "第 \{self.line_no} 行：一个面里面只有 \{self.pending.length()} 个顶点，应该是 3 个",
        )
      }
      self.stage = NeedEndfacet
    }
    ["endfacet"] => {
      if self.stage != NeedEndfacet {
        return Err(error)
      }
      let t = {
        normal: self.normal,
        a: self.pending[0],
        b: self.pending[1],
        c: self.pending[2],
      }
      self.pending.clear()
      self.stage = Outside
      return Ok(Some(t))
    }
    _ => return Err(error)
  }
  Ok(None)
}

///|
// 每次只构造一个三角形；流式统计不保留完整 Mesh。
fn walk_stl_ascii(
  text : String,
  emit : (Triangle) -> Unit,
  limits~ : ParseLimits = ParseLimits::default(),
) -> Result[Int32, String] {
  if text_limit_error(text, limits) is Some(error) {
    return Err(error)
  }
  let reader : StlAsciiReader = {
    stage: Outside,
    normal: Vec3::zero(),
    pending: [],
    line_no: 0,
  }
  let mut count = 0
  for line in text.split("\n") {
    match reader.read_line(line) {
      Err(message) => return Err(message)
      Ok(Some(triangle)) => {
        if triangle_limit_error(count + 1, limits) is Some(error) {
          return Err(error)
        }
        emit(triangle)
        count = count + 1
      }
      Ok(None) => ()
    }
  }
  if reader.stage != Outside {
    return Err(
      "ASCII STL 文件结束时 facet 尚未结束（最后读取第 \{reader.line_no} 行）",
    )
  }
  if count == 0 {
    return Err(
      "这个 ASCII STL 里一个三角形都没有，可能不是 STL 文件",
    )
  }
  Ok(count)
}
