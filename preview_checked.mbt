// SPDX-License-Identifier: Apache-2.0

///|
fn safe_svg_paint(value : String) -> Bool {
  if [
      "none", "transparent", "black", "white", "red", "green", "blue", "gray", "grey",
      "currentColor",
    ].contains(value) {
    return true
  }
  if !value.has_prefix("#") || ![4, 5, 7, 9].contains(value.length()) {
    return false
  }
  value[1:]
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  })
}

///|
fn svg_attribute(value : String) -> String {
  let parts : Array[String] = []
  for c in value {
    parts.push(
      match c {
        '&' => "&amp;"
        '<' => "&lt;"
        '>' => "&gt;"
        '"' => "&quot;"
        '\'' => "&apos;"
        _ => c.to_string()
      },
    )
  }
  parts.join("")
}

///|
/// Bounded approximate SVG preview. Validates drawing options, escapes string
/// attributes and deterministically samples at most max_faces (up to 20000).
/// A desc element identifies downsampling. It is not a complete mesh rendering.
pub fn render_svg_checked(
  mesh : Mesh,
  options : PreviewOptions,
  max_faces~ : Int32 = 20000,
  max_output_bytes~ : Int32 = 8000000,
) -> Result[String, String] {
  if options.width < 1 ||
    options.height < 1 ||
    options.width > 16384 ||
    options.height > 16384 ||
    not_finite(options.yaw) ||
    not_finite(options.pitch) ||
    not_finite(options.stroke_width) ||
    options.stroke_width < 0.0 ||
    options.stroke_width > 256.0 ||
    !safe_svg_paint(options.stroke) ||
    options.stroke.iter().any(c => c < ' ') {
    return Err("invalid SVG preview options")
  }
  if max_faces < 1 ||
    max_faces > 20000 ||
    max_output_bytes < 1 ||
    max_output_bytes > 16000000 {
    return Err("invalid SVG preview limits")
  }
  if mesh.is_empty() {
    return Ok("<!-- 空网格 -->")
  }
  let count = mesh.triangle_count()
  let selected : Array[Triangle] = []
  let budget = count.min(max_faces)
  for i in 0..<budget {
    let triangle = mesh.triangles[(i.to_int64() *
      count.to_int64() /
      budget.to_int64()).to_int()]
    if !finite_vertex(triangle.a) ||
      !finite_vertex(triangle.b) ||
      !finite_vertex(triangle.c) {
      return Err("non-finite preview coordinates")
    }
    selected.push(triangle)
  }
  let selected_mesh = Mesh::new(selected)
  let box = selected_mesh.bounding_box().unwrap()
  let origin = Vec3::new(
    box.min.x / 2.0 + box.max.x / 2.0,
    box.min.y / 2.0 + box.max.y / 2.0,
    box.min.z / 2.0 + box.max.z / 2.0,
  )
  let size = box.size()
  let scale = size.x.max(size.y).max(size.z)
  if not_finite(scale) {
    return Err("preview coordinate span is not representable")
  }
  let scale = if scale > 0.0 { scale } else { 1.0 }
  let to_local = fn(v : Vec3) {
    let d = v.sub(origin)
    Vec3::new(d.x / scale, d.y / scale, d.z / scale)
  }
  let local_mesh = Mesh::new(
    selected.map(t => {
      Triangle::from_vertices(to_local(t.a), to_local(t.b), to_local(t.c))
    }),
  )
  let mut svg = render_svg_inner(local_mesh, options)
  if count > budget {
    svg = svg.replace(
      old="<rect",
      new="<desc>Approximate preview: sampled \{budget} of \{count} faces.</desc><rect",
    )
  }
  if @utf8.encode(svg).length() > max_output_bytes {
    return Err("resource_limit: max_preview_output_bytes")
  }
  Ok(svg)
}

///|
/// Compatibility preview API; unavailable previews return a safe constant
/// comment. Use render_svg_checked() to obtain the refusal reason.
pub fn render_svg(mesh : Mesh, options : PreviewOptions) -> String {
  match render_svg_checked(mesh, options) {
    Ok(svg) => svg
    Err(_) =>
      "<!-- SVG preview unavailable: invalid input or resource limit -->"
  }
}
