// SPDX-License-Identifier: Apache-2.0

///|
// Keep direction and scale separate, including finite endpoints whose raw
// difference overflows. The two edges use separate scales, so thin triangles
// with very different edge magnitudes are not collapsed by one global scale.
fn scaled_edge(a : Vec3, b : Vec3) -> (Vec3, Double)? {
  let edge = b.sub(a)
  let scale = if finite_vertex(edge) {
    edge.x.abs().max(edge.y.abs()).max(edge.z.abs())
  } else {
    a.x
    .abs()
    .max(a.y.abs())
    .max(a.z.abs())
    .max(b.x.abs())
    .max(b.y.abs())
    .max(b.z.abs())
  }
  if scale == 0.0 {
    return Some((Vec3::zero(), 0.0))
  }
  let direction = if finite_vertex(edge) {
    Vec3::new(edge.x / scale, edge.y / scale, edge.z / scale)
  } else {
    Vec3::new(
      b.x / scale - a.x / scale,
      b.y / scale - a.y / scale,
      b.z / scale - a.z / scale,
    )
  }
  if (edge.x != 0.0 && direction.x == 0.0) ||
    (edge.y != 0.0 && direction.y == 0.0) ||
    (edge.z != 0.0 && direction.z == 0.0) {
    return None
  }
  Some((direction, scale))
}

///|
fn triangle_frame(triangle : Triangle) -> (Vec3, Double, Double)? {
  if !finite_vertex(triangle.a) ||
    !finite_vertex(triangle.b) ||
    !finite_vertex(triangle.c) {
    return None
  }
  guard scaled_edge(triangle.a, triangle.b) is Some((u, su)) else {
    return None
  }
  guard scaled_edge(triangle.a, triangle.c) is Some((v, sv)) else {
    return None
  }
  Some((u.cross(v), su, sv))
}

///|
// Represent positive finite factors as m*2^e, including subnormals. Multiplying
// mantissas before restoring the combined exponent avoids intermediate loss.
fn positive_parts(value : Double) -> (Double, Int32) {
  let raw = ((value.reinterpret_as_uint64() >> 52) & 2047UL).to_int()
  let exponent = if raw == 0 {
    ((@math.scalbn(value, 1022).reinterpret_as_uint64() >> 52) & 2047UL).to_int() -
    1023 -
    1022
  } else {
    raw - 1023
  }
  (@math.scalbn(value, -exponent), exponent)
}

///|
fn scaled_area(cross : Vec3, first : Double, second : Double) -> Double {
  let length = cross.length()
  if length == 0.0 || first == 0.0 || second == 0.0 {
    return 0.0
  }
  let (a, ea) = positive_parts(length)
  let (b, eb) = positive_parts(first)
  let (c, ec) = positive_parts(second)
  @math.scalbn(a * b * c, ea + eb + ec - 1)
}

///|
/// Area with explicit refusal when finite geometry has a positive area outside
/// Double's representable range. Degenerate triangles have area zero.
pub fn Triangle::area_checked(self : Triangle) -> Result[Double, String] {
  guard triangle_frame(self) is Some((cross, a, b)) else {
    return Err(
      "triangle coordinates are non-finite or lose precision during scaling",
    )
  }
  let area = scaled_area(cross, a, b)
  if not_finite(area) ||
    (area == 0.0 && cross.length() > 0.0 && a > 0.0 && b > 0.0) {
    return Err("triangle area is outside the representable Double range")
  }
  Ok(area)
}

///|
/// Empty meshes return Ok(None). Invalid query/vertices or detected numeric
/// loss return Err, rather than a plausible finite distance. This is a linear
/// query and does not promise a formal error bound for ill-conditioned input.
pub fn Mesh::nearest_point_checked(
  self : Mesh,
  point : Vec3,
) -> Result[(Double, Vec3)?, String] {
  if !finite_vertex(point) {
    return Err("nearest point query must be finite")
  }
  let mut best : (Double, Vec3)? = None
  for triangle in self.triangles {
    if !finite_vertex(triangle.a) ||
      !finite_vertex(triangle.b) ||
      !finite_vertex(triangle.c) {
      return Err("nearest point mesh contains non-finite vertices")
    }
    if triangle_frame(triangle) is None {
      return Err("nearest point geometry loses precision during scaling")
    }
    let ab = triangle.b.sub(triangle.a)
    let ac = triangle.c.sub(triangle.a)
    let ap = point.sub(triangle.a)
    let relative = finite_vertex(ab) && finite_vertex(ac) && finite_vertex(ap)
    let scale = if relative {
      ab.x
      .abs()
      .max(ab.y.abs())
      .max(ab.z.abs())
      .max(ac.x.abs())
      .max(ac.y.abs())
      .max(ac.z.abs())
      .max(ap.x.abs())
      .max(ap.y.abs())
      .max(ap.z.abs())
    } else {
      let mut maximum = 0.0
      for vertex in [triangle.a, triangle.b, triangle.c, point] {
        maximum = maximum
          .max(vertex.x.abs())
          .max(vertex.y.abs())
          .max(vertex.z.abs())
      }
      maximum
    }
    if scale == 0.0 {
      return Ok(Some((0.0, triangle.a)))
    }
    let to_local = fn(vertex : Vec3) {
      let value = if relative { vertex.sub(triangle.a) } else { vertex }
      Vec3::new(value.x / scale, value.y / scale, value.z / scale)
    }
    let a = to_local(triangle.a)
    let b = to_local(triangle.b)
    let c = to_local(triangle.c)
    let local_cross = b.sub(a).cross(c.sub(a))
    if !triangle_is_degenerate(triangle) &&
      (
        triangle_is_degenerate(Triangle::from_vertices(a, b, c)) ||
        local_cross.dot(local_cross) == 0.0
      ) {
      return Err("nearest point geometry lost precision during normalization")
    }
    let (distance, nearest) = point_triangle_distance(to_local(point), a, b, c)
    let restored = Vec3::new(
      nearest.x * scale + (if relative { triangle.a.x } else { 0.0 }),
      nearest.y * scale + (if relative { triangle.a.y } else { 0.0 }),
      nearest.z * scale + (if relative { triangle.a.z } else { 0.0 }),
    )
    let result = distance * scale
    if not_finite(result) ||
      !finite_vertex(restored) ||
      (result == 0.0 && distance > 0.0) {
      return Err("nearest point distance or position is not representable")
    }
    match best {
      Some((old, _)) if old <= result => ()
      _ => best = Some((result, restored))
    }
  }
  Ok(best)
}
