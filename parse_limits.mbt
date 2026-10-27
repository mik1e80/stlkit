// SPDX-License-Identifier: Apache-2.0

///|
/// Allocation/work budgets, not a process RSS or wall-clock guarantee.
/// All fields must be nonnegative; component/XML depth is capped at 128.
/// Defaults cover the checked-in corpus and the 1m-triangle STL benchmark.
pub(all) struct ParseLimits {
  max_input_bytes : Int32
  max_vertices : Int32
  max_triangles : Int32
  max_list_items : Int32
  max_polygon_vertices : Int32
  max_uncompressed_bytes : Int32
  max_zip_entries : Int32
  max_component_depth : Int32
  max_component_instances : Int32
  max_records : Int32
  max_line_bytes : Int32
  max_xml_depth : Int32
}

///|
/// Default budgets. Override only the fields needed by the caller; increasing
/// a budget does not relax format validation or bound process RSS.
///
/// ```moonbit nocheck
/// let limits = { ..@stlkit.ParseLimits::default(), max_triangles: 100000, }
///
/// let result = @stlkit.parse_mesh(data, limits~)
/// ```
pub fn ParseLimits::default() -> ParseLimits {
  {
    max_input_bytes: 67108864,
    max_vertices: 6000000,
    max_triangles: 2000000,
    max_list_items: 8000000,
    max_polygon_vertices: 1024,
    max_uncompressed_bytes: 104857600,
    max_zip_entries: 4096,
    max_component_depth: 32,
    max_component_instances: 100000,
    max_records: 4000000,
    max_line_bytes: 1048576,
    max_xml_depth: 128,
  }
}

///|
fn resource_error(field : String, maximum : Int32) -> String {
  "resource_limit: \{field} (max=\{maximum})"
}

///|
fn parse_limits_error(limits : ParseLimits) -> String? {
  for
    value in [
      limits.max_input_bytes,
      limits.max_vertices,
      limits.max_triangles,
      limits.max_list_items,
      limits.max_polygon_vertices,
      limits.max_uncompressed_bytes,
      limits.max_zip_entries,
      limits.max_component_depth,
      limits.max_component_instances,
      limits.max_records,
      limits.max_line_bytes,
      limits.max_xml_depth,
    ] {
    if value < 0 {
      return Some("invalid_limits: ParseLimits fields must be nonnegative")
    }
  }
  if limits.max_component_depth > 128 || limits.max_xml_depth > 128 {
    return Some("invalid_limits: depth limits must be <=128")
  }
  if limits.max_triangles > 715827882 {
    return Some("invalid_limits: max_triangles must fit three Int32 corners")
  }
  None
}

///|
fn input_limit_error(data : Bytes, limits : ParseLimits) -> String? {
  if parse_limits_error(limits) is Some(error) {
    return Some(error)
  }
  if data.length() > limits.max_input_bytes {
    return Some(resource_error("max_input_bytes", limits.max_input_bytes))
  }
  None
}

///|
// Scan before splitting into lines/tokens, including empty-line floods.
// Count UTF-8 bytes of String input without creating a second encoded buffer.
fn text_limit_error(text : String, limits : ParseLimits) -> String? {
  if parse_limits_error(limits) is Some(error) {
    return Some(error)
  }
  let mut bytes = 0L
  let mut line_bytes = 0L
  let mut lines = 0
  let mut tokens = 0
  let mut in_token = false
  for c in text {
    let code = c.to_int()
    let width = if code < 128 {
      1L
    } else if code < 2048 {
      2L
    } else if code < 65536 {
      3L
    } else {
      4L
    }
    bytes += width
    if bytes > limits.max_input_bytes.to_int64() {
      return Some(resource_error("max_input_bytes", limits.max_input_bytes))
    }
    if c == '\n' || c == '\r' {
      line_bytes = 0L
      lines += 1
      if lines > limits.max_records {
        return Some(resource_error("max_records", limits.max_records))
      }
    } else {
      line_bytes += width
      if line_bytes > limits.max_line_bytes.to_int64() {
        return Some(resource_error("max_line_bytes", limits.max_line_bytes))
      }
    }
    if is_ascii_space(code) {
      in_token = false
    } else if !in_token {
      in_token = true
      tokens += 1
      if tokens > limits.max_records {
        return Some(resource_error("max_records", limits.max_records))
      }
    }
  }
  None
}

///|
fn triangle_limit_error(count : Int32, limits : ParseLimits) -> String? {
  if count > limits.max_triangles {
    Some(resource_error("max_triangles", limits.max_triangles))
  } else if count.to_int64() * 3L > limits.max_vertices.to_int64() {
    Some(resource_error("max_vertices", limits.max_vertices))
  } else {
    None
  }
}
