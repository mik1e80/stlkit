// SPDX-License-Identifier: Apache-2.0

///|
fn cli_limit(
  matches : @argparse.Matches,
  name : String,
  fallback : Int32,
) -> Result[Int32, String] {
  match matches.values.get(name) {
    Some([raw, ..]) => {
      let value = @string.parse_int(raw) catch {
        _ => return Err("--\{name} 必须是非负 Int32 整数")
      }
      if value < 0 {
        return Err("--\{name} 必须是非负 Int32 整数")
      }
      Ok(value)
    }
    _ => Ok(fallback)
  }
}

///|
fn cli_limits(
  matches : @argparse.Matches,
) -> Result[@stlkit.ParseLimits, String] {
  let defaults = @stlkit.ParseLimits::default()
  let input = match
    cli_limit(matches, "max-input-bytes", defaults.max_input_bytes) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let triangles = match
    cli_limit(matches, "max-triangles", defaults.max_triangles) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let vertices = match
    cli_limit(matches, "max-vertices", defaults.max_vertices) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let uncompressed = match
    cli_limit(
      matches,
      "max-uncompressed-bytes",
      defaults.max_uncompressed_bytes,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if triangles > 715827882 {
    return Err("--max-triangles 不能超过 715827882")
  }
  Ok({
    ..defaults,
    max_input_bytes: input,
    max_triangles: triangles,
    max_vertices: vertices,
    max_uncompressed_bytes: uncompressed,
  })
}

///|
// File size is checked before allocating/reading the full input. The file can
// change concurrently: reject size changes and premature EOF instead of padding.
async fn read_input(
  path : String,
  limits : @stlkit.ParseLimits,
) -> Result[Bytes, String] {
  let file = @asyncfs.open(path, mode=@asyncfs.Mode::ReadOnly) catch {
    err => return Err("读不了文件「\{path}」：\{err}")
  }
  let result = try {
    let size = file.size()
    if size < 0L || size > limits.max_input_bytes.to_int64() {
      Err("resource_limit: max_input_bytes (max=\{limits.max_input_bytes})")
    } else {
      let length = size.to_int()
      let bytes = FixedArray::make(length, b'\x00')
      let mut offset = 0
      let mut failed = false
      while offset < length {
        let n = file.read_at(
          bytes,
          position=offset.to_int64(),
          offset~,
          len=(length - offset).min(262144),
        )
        if n <= 0 {
          failed = true
          break
        }
        offset += n
      }
      if failed || file.size() != size {
        Err("读取时文件长度发生变化或文件被截断")
      } else {
        Ok(Bytes::from_array(bytes))
      }
    }
  } catch {
    err => Err("读不了文件「\{path}」：\{err}")
  }
  let _ = file.close()
  result
}
