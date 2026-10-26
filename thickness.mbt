// 确定性表面采样与内法线射线距离估计。
// 样本最小值可能漏掉局部薄处，不能视为全局最小壁厚或可打印结论。
// 每条射线遍历所有面，时间约 O(samples*faces)。

///|
/// 壁厚检查的结果。
pub(all) struct ThicknessReport {
  /// 一共打了多少条射线
  samples : Int32
  /// 有多少条打到了对面的表面。
  /// 明显偏少说明模型有开放面，或者朝向不一致，结论不可信
  hits : Int32
  /// 采到的最薄处有多厚（打到对面的那些里最小的）
  min_thickness : Double
  /// 最薄处的位置
  min_at : Vec3?
  /// 平均厚度（只统计打到对面的）
  mean_thickness : Double
}

///|
/// 默认样本预算，不保证覆盖全部面或薄处。
/// 每条射线遍历所有面，运行成本取决于输入规模。
const DEFAULT_THICKNESS_SAMPLES : Int32 = 1000

///|
/// 用默认采样数检查壁厚。
pub fn check_thickness_default(mesh : Mesh) -> ThicknessReport {
  check_thickness(mesh, DEFAULT_THICKNESS_SAMPLES)
}

///|
/// 检查壁厚。
///
/// 采样是**确定性**的：同一个模型每次跑出来的数一样。
/// 用黄金比之类的低差异序列把采样点铺开，而不是伪随机数——
/// 「上次跑 0.42，这次跑 0.38」这种报告没法用来对比修复前后的变化。
pub fn check_thickness(mesh : Mesh, samples : Int32) -> ThicknessReport {
  let n = mesh.triangle_count()
  if n == 0 || samples <= 0 {
    return {
      samples: 0,
      hits: 0,
      min_thickness: 0.0,
      min_at: None,
      mean_thickness: 0.0,
    }
  }

  // 射线起点往里挪一点点，免得打中自己所在的那个三角形。
  // 挪的量按模型尺度取，别用固定值——微米级的模型和米级的模型差着六个数量级
  let inset = probe_inset(mesh)

  let mut hits = 0
  let mut min_d = 1.0e300
  let mut min_at : Vec3? = None
  let mut total = 0.0

  for i = 0; i < samples; i = i + 1 {
    // 三角形编号：乘一个大奇数再取模，把相邻的采样打散到整个模型上。
    // 顺序扫的话前一半采样全落在模型的同一片区域
    let idx = (i.to_uint64() * 2654435761UL % n.to_uint64()).to_int()
    let tri = mesh.triangles[idx]

    // 三角形内的均匀采样点
    let r1 = frac(i.to_double() * 0.6180339887498949).sqrt()
    let r2 = frac(i.to_double() * 0.7548776662466927)
    let p = Vec3::new(
      tri.a.x * (1.0 - r1) + tri.b.x * (r1 * (1.0 - r2)) + tri.c.x * (r1 * r2),
      tri.a.y * (1.0 - r1) + tri.b.y * (r1 * (1.0 - r2)) + tri.c.y * (r1 * r2),
      tri.a.z * (1.0 - r1) + tri.b.z * (r1 * (1.0 - r2)) + tri.c.z * (r1 * r2),
    )

    // 往**里面**打。法线朝外，所以方向取反。
    // 退化面没有法线，跳过
    let normal = tri.computed_normal()
    if normal.is_zero(1.0e-12) {
      continue
    }
    let dir = Vec3::new(-normal.x, -normal.y, -normal.z)
    let origin = Vec3::new(
      p.x + dir.x * inset,
      p.y + dir.y * inset,
      p.z + dir.z * inset,
    )

    match mesh.ray_cast(origin, dir) {
      Some(hit) => {
        hits = hits + 1
        total = total + hit.distance
        if hit.distance < min_d {
          min_d = hit.distance
          min_at = Some(hit.point)
        }
      }
      None => ()
    }
  }

  if hits == 0 {
    // 一条都没打到对面。开放曲面（比如一张纸）就是这样，
    // 报「厚度 0」会误导——那根本不是「薄」，是没法用这个办法量
    return {
      samples,
      hits: 0,
      min_thickness: 0.0,
      min_at: None,
      mean_thickness: 0.0,
    }
  }
  {
    samples,
    hits,
    min_thickness: min_d,
    min_at,
    mean_thickness: total / hits.to_double(),
  }
}

///|
/// 取小数部分。
fn frac(v : Double) -> Double {
  v - v.floor()
}

///|
/// 射线起点往里挪多少。
///
/// 取包围盒对角线的一亿分之一：足够大到能躲开自己那个三角形，
/// 又小到不影响测出来的厚度。模型尺度差几个数量级也能自适应
fn probe_inset(mesh : Mesh) -> Double {
  match mesh.bounding_box() {
    Some(b) => {
      let s = b.size()
      let diag = (s.x * s.x + s.y * s.y + s.z * s.z).sqrt()
      if diag > 0.0 {
        diag * 1.0e-8
      } else {
        1.0e-9
      }
    }
    None => 1.0e-9
  }
}
