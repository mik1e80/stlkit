// OBJ / PLY 的平面简单多边形三角化。凸多边形保留原扇形切分，
// 凹多边形用耳切；自相交或非平面的多边形明确报错。

///|
fn polygon_turn(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
) -> Double {
  (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
}

///|
fn polygon_on_segment(
  p : (Double, Double),
  a : (Double, Double),
  b : (Double, Double),
) -> Bool {
  polygon_turn(a, b, p).abs() <= 1.0e-14 &&
  p.0 >= a.0.min(b.0) &&
  p.0 <= a.0.max(b.0) &&
  p.1 >= a.1.min(b.1) &&
  p.1 <= a.1.max(b.1)
}

///|
fn polygon_edges_cross(
  a : (Double, Double),
  b : (Double, Double),
  c : (Double, Double),
  d : (Double, Double),
) -> Bool {
  let ab_c = polygon_turn(a, b, c)
  let ab_d = polygon_turn(a, b, d)
  let cd_a = polygon_turn(c, d, a)
  let cd_b = polygon_turn(c, d, b)
  (ab_c * ab_d < 0.0 && cd_a * cd_b < 0.0) ||
  polygon_on_segment(c, a, b) ||
  polygon_on_segment(d, a, b) ||
  polygon_on_segment(a, c, d) ||
  polygon_on_segment(b, c, d)
}

///|
fn triangulate_polygon(
  vertices : Array[Vec3],
  max_work~ : Int32 = 2000000,
) -> Result[Array[(Int32, Int32, Int32)], String] {
  if max_work < 0 {
    return Err("invalid triangulation operation budget")
  }
  let mut remaining = max_work
  let n = vertices.length()
  if n < 3 {
    return Err("一个面至少要有三个顶点")
  }
  // 三角形的退化性由校验层报告，解析层不丢弃原始三点。
  if n == 3 {
    return Ok([(0, 1, 2)])
  }
  let origin = vertices[0]
  let mut scale = 0.0
  for v in vertices {
    let p = v.sub(origin)
    scale = scale.max(p.x.abs()).max(p.y.abs()).max(p.z.abs())
  }
  if scale == 0.0 || scale.is_inf() || scale.is_nan() {
    return Err("多边形没有可用的有限面积")
  }
  let normalized : Array[Vec3] = []
  for v in vertices {
    let p = v.sub(origin)
    normalized.push(Vec3::new(p.x / scale, p.y / scale, p.z / scale))
  }
  let mut nx = 0.0
  let mut ny = 0.0
  let mut nz = 0.0
  for i = 0; i < n; i = i + 1 {
    let cross = normalized[i].cross(normalized[(i + 1) % n])
    nx = nx + cross.x
    ny = ny + cross.y
    nz = nz + cross.z
  }
  let normal = Vec3::new(nx, ny, nz)
  if normal.length() == 0.0 {
    return Err("多边形零面积或自相交，无法三角化")
  }
  let unit = normal.normalize()
  for p in normalized {
    if p.dot(unit).abs() > 1.0e-8 {
      return Err("仅支持平面多边形；这个面的顶点不共面")
    }
  }
  let axis = if nx.abs() >= ny.abs() && nx.abs() >= nz.abs() {
    0
  } else if ny.abs() >= nz.abs() {
    1
  } else {
    2
  }
  let points : Array[(Double, Double)] = []
  for p in normalized {
    points.push(
      if axis == 0 {
        (p.y, p.z)
      } else if axis == 1 {
        (p.z, p.x)
      } else {
        (p.x, p.y)
      },
    )
  }
  let mut area = 0.0
  for i = 0; i < n; i = i + 1 {
    let a = points[i]
    let b = points[(i + 1) % n]
    area = area + a.0 * b.1 - a.1 * b.0
    for j = i + 1; j < n; j = j + 1 {
      if j == i + 1 || (i == 0 && j == n - 1) {
        continue
      }
      if remaining == 0 {
        return Err(
          "resource_limit: polygon triangulation work (max=\{max_work})",
        )
      }
      remaining -= 1
      if polygon_edges_cross(a, b, points[j], points[(j + 1) % n]) {
        return Err("多边形有自相交或重复边，无法三角化")
      }
    }
  }
  let sign = if area > 0.0 { 1.0 } else { -1.0 }
  let result : Array[(Int32, Int32, Int32)] = []
  let mut convex = true
  for i = 0; i < n; i = i + 1 {
    if polygon_turn(points[(i + n - 1) % n], points[i], points[(i + 1) % n]) *
      sign <
      0.0 {
      convex = false
    }
  }
  if convex {
    for i = 1; i + 1 < n; i = i + 1 {
      result.push((0, i, i + 1))
    }
    return Ok(result)
  }
  let mut live : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    live.push(i)
  }
  while live.length() > 3 {
    let count = live.length()
    let mut ear : Int32? = None
    for i = 0; i < count; i = i + 1 {
      if remaining == 0 {
        return Err(
          "resource_limit: polygon triangulation work (max=\{max_work})",
        )
      }
      remaining -= 1
      let a = live[(i + count - 1) % count]
      let b = live[i]
      let c = live[(i + 1) % count]
      if polygon_turn(points[a], points[b], points[c]) * sign <= 0.0 {
        continue
      }
      let mut blocked = false
      for j in live {
        if j == a || j == b || j == c {
          continue
        }
        if remaining == 0 {
          return Err(
            "resource_limit: polygon triangulation work (max=\{max_work})",
          )
        }
        remaining -= 1
        if polygon_turn(points[a], points[b], points[j]) * sign >= -1.0e-14 &&
          polygon_turn(points[b], points[c], points[j]) * sign >= -1.0e-14 &&
          polygon_turn(points[c], points[a], points[j]) * sign >= -1.0e-14 {
          blocked = true
          break
        }
      }
      if !blocked {
        ear = Some(i)
        break
      }
    }
    match ear {
      None =>
        return Err("多边形无法安全三角化，请先修正这个面")
      Some(i) => {
        result.push(
          (live[(i + count - 1) % count], live[i], live[(i + 1) % count]),
        )
        let next : Array[Int32] = []
        for j = 0; j < count; j = j + 1 {
          if j != i {
            next.push(live[j])
          }
        }
        live = next
      }
    }
  }
  result.push((live[0], live[1], live[2]))
  Ok(result)
}
