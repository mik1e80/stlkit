// 射线与网格求交。
//
// 对应 trimesh 的 `mesh.ray` 那一套。用 Möller–Trumbore 算法：
// 不预先算平面方程，直接解方程组，每一步都能提前退出——三角形少了很划算。
//
// 这项能力本身是为了「壁厚检查」才加的（见 thickness.mbt）：
// 从表面往模型里面打一条射线，打到的对面有多远，就是那里的壁厚。

///|
/// 一次射线命中。
pub(all) struct RayHit {
  /// 从射线起点沿方向走了多远
  distance : Double
  /// 打中的是第几个三角形
  triangle : Int
  /// 命中点的坐标
  point : Vec3
}

///|
/// 一条射线打在一个三角形上，返回距离（`None` = 没打中）。
///
/// Möller–Trumbore：把命中点表示成 `a + u·(b−a) + v·(c−a)`，
/// 直接解出 u、v 和距离 t。三个约束各自能提前退出，不用算完整。
///
/// 只有 `t > 0` 才算命中——反方向的交点是「背后的东西」，不算。
pub fn ray_triangle(
  origin : Vec3,
  dir : Vec3,
  a : Vec3,
  b : Vec3,
  c : Vec3,
) -> Double? {
  let edge1 = b.sub(a)
  let edge2 = c.sub(a)
  let h = dir.cross(edge2)
  let det = edge1.dot(h)
  // 行列式接近零 = 射线和三角形所在平面平行（或退化面）。
  // 阈值取相对量：三角形本身很小时 det 天然就小
  let scale = edge1.length() * edge2.length()
  if det.abs() <= 1.0e-12 * (if scale > 0.0 { scale } else { 1.0 }) {
    return None
  }
  let inv_det = 1.0 / det
  let s = origin.sub(a)
  let u = inv_det * s.dot(h)
  if u < 0.0 || u > 1.0 {
    return None
  }
  let q = s.cross(edge1)
  let v = inv_det * dir.dot(q)
  if v < 0.0 || u + v > 1.0 {
    return None
  }
  let t = inv_det * edge2.dot(q)
  // 浮点误差会让本该是 0 的自交算出一个极小的正数，
  // 打射线的时候要能把这些排掉
  if t <= 1.0e-12 {
    return None
  }
  Some(t)
}

///|
/// 射线穿过整个网格，返回**最近**的一次命中。
pub fn Mesh::ray_cast(self : Mesh, origin : Vec3, dir : Vec3) -> RayHit? {
  let mut best : RayHit? = None
  for i, t in self.triangles {
    match ray_triangle(origin, dir, t.a, t.b, t.c) {
      Some(d) =>
        match best {
          Some(h) =>
            if d < h.distance {
              best = Some({
                distance: d,
                triangle: i,
                point: Vec3::new(
                  origin.x + dir.x * d,
                  origin.y + dir.y * d,
                  origin.z + dir.z * d,
                ),
              })
            }
          None =>
            best = Some({
              distance: d,
              triangle: i,
              point: Vec3::new(
                origin.x + dir.x * d,
                origin.y + dir.y * d,
                origin.z + dir.z * d,
              ),
            })
        }
      None => ()
    }
  }
  best
}

///|
/// 网格上离给定点最近的位置和距离。
///
/// 对应 trimesh 的 `mesh.nearest.on_surface`。
///
/// 做法是逐三角形求「点到三角形的最短距离」：
/// 先看投影落不落在三角形内（落进去就是点到平面的垂直距离），
/// 落不进去就是到三条边的最短距离。
///
/// 这是**无符号**距离，不区分点在模型里面还是外面。
pub fn Mesh::nearest_point(self : Mesh, p : Vec3) -> (Double, Vec3) {
  let mut best_d = 1.0e300
  let mut best_p = Vec3::zero()
  for t in self.triangles {
    let (d, q) = point_triangle_distance(p, t.a, t.b, t.c)
    if d < best_d {
      best_d = d
      best_p = q
    }
  }
  (best_d, best_p)
}

///|
/// 点到三角形的最短距离，以及三角形上最近的那个点。
fn point_triangle_distance(
  p : Vec3,
  a : Vec3,
  b : Vec3,
  c : Vec3,
) -> (Double, Vec3) {
  let ab = b.sub(a)
  let ac = c.sub(a)
  let ap = p.sub(a)

  // 先把 p 投影到三角形所在平面上，看参数 (u, v) 落在哪
  let d1 = ab.dot(ap)
  let d2 = ac.dot(ap)
  // 顶点 a 附近（含 a 的外侧扇形）
  if d1 <= 0.0 && d2 <= 0.0 {
    return (ap.length(), a)
  }
  let bp = p.sub(b)
  let d3 = ab.dot(bp)
  let d4 = ac.dot(bp)
  if d3 >= 0.0 && d4 <= d3 {
    return (bp.length(), b)
  }
  let cp = p.sub(c)
  let d5 = ab.dot(cp)
  let d6 = ac.dot(cp)
  if d6 >= 0.0 && d5 <= d6 {
    return (cp.length(), c)
  }
  // 三条边的外侧区域
  let vc = d1 * d4 - d3 * d2
  if vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0 {
    let denom = d1 - d3
    let t = if denom == 0.0 { 0.0 } else { d1 / denom }
    let q = Vec3::new(
      a.x + ab.x * t,
      a.y + ab.y * t,
      a.z + ab.z * t,
    )
    return (p.sub(q).length(), q)
  }
  let vb = d5 * d2 - d1 * d6
  if vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0 {
    let denom = d2 - d6
    let t = if denom == 0.0 { 0.0 } else { d2 / denom }
    let q = Vec3::new(
      a.x + ac.x * t,
      a.y + ac.y * t,
      a.z + ac.z * t,
    )
    return (p.sub(q).length(), q)
  }
  let va = d3 * d6 - d5 * d4
  if va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0 {
    let denom = (d4 - d3) + (d5 - d6)
    let t = if denom == 0.0 { 0.0 } else { (d4 - d3) / denom }
    let bc = c.sub(b)
    let q = Vec3::new(
      b.x + bc.x * t,
      b.y + bc.y * t,
      b.z + bc.z * t,
    )
    return (p.sub(q).length(), q)
  }

  // 投影落在三角形内部：算垂直距离
  let denom = va + vb + vc
  if denom == 0.0 {
    // 退化三角形（三个点共线或重合），退回到顶点距离
    return (ap.length(), a)
  }
  let v = vb / denom
  let w = vc / denom
  let q = Vec3::new(
    a.x + ab.x * v + ac.x * w,
    a.y + ab.y * v + ac.y * w,
    a.z + ab.z * v + ac.z * w,
  )
  (p.sub(q).length(), q)
}
