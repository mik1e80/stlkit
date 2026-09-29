// 有向包围盒（OBB）。
//
// 对应 trimesh 的 `mesh.bounding_box_oriented`。
//
// 轴对齐包围盒（AABB）好算，但对斜着摆的模型特别不准：一根斜放的长棍，
// AABB 会是一个巨大的立方体，而 OBB 能贴着棍子包上去。
//
// 做法是主成分分析（PCA）：
//
//   1. 求所有顶点的重心和协方差矩阵
//   2. 协方差矩阵的特征向量就是「顶点分布最开的三个方向」
//   3. 把顶点投影到这三个方向上，取各自的极值
//
// 严格说 PCA 求的不是**最小体积**包围盒（那个要靠旋转卡壳，很难写），
// 但对「模型实际占多大地方」这个问题，PCA 的结果通常已经很接近了。
// 这一点在文档里会说明，不装作是精确解。

///|
/// 有向包围盒。
pub(all) struct Obb {
  /// 盒子的中心
  center : Vec3
  /// 三个轴，已单位化。按对应边的长度从大到小排
  axes : Array[Vec3]
  /// 沿三个轴的半长，和 `axes` 一一对应
  half : Array[Double]
}

///|
/// 三条边的长度。
pub fn Obb::size(self : Obb) -> Vec3 {
  Vec3::new(self.half[0] * 2.0, self.half[1] * 2.0, self.half[2] * 2.0)
}

///|
/// 盒子的体积。真实体积的**上界**——模型装在里面，一般填不满。
pub fn Obb::volume(self : Obb) -> Double {
  self.half[0] * 8.0 * self.half[1] * self.half[2]
}

///|
/// 求有向包围盒。空网格返回 `None`。
pub fn Mesh::oriented_bounding_box(self : Mesh) -> Obb? {
  let pts = unique_positions(self)
  if pts.length() == 0 {
    return None
  }

  // 重心
  let mut cx = 0.0
  let mut cy = 0.0
  let mut cz = 0.0
  for p in pts {
    cx = cx + p.x
    cy = cy + p.y
    cz = cz + p.z
  }
  let n = pts.length().to_double()
  let centroid = Vec3::new(cx / n, cy / n, cz / n)

  // 协方差矩阵。对称，所以 9 个数里只有 6 个独立
  let mut xx = 0.0
  let mut yy = 0.0
  let mut zz = 0.0
  let mut xy = 0.0
  let mut yz = 0.0
  let mut zx = 0.0
  for p in pts {
    let dx = p.x - centroid.x
    let dy = p.y - centroid.y
    let dz = p.z - centroid.z
    xx = xx + dx * dx
    yy = yy + dy * dy
    zz = zz + dz * dz
    xy = xy + dx * dy
    yz = yz + dy * dz
    zx = zx + dz * dx
  }
  let cov : FixedArray[Double] = FixedArray::make(9, 0.0)
  cov[0] = xx / n
  cov[1] = xy / n
  cov[2] = zx / n
  cov[3] = xy / n
  cov[4] = yy / n
  cov[5] = yz / n
  cov[6] = zx / n
  cov[7] = yz / n
  cov[8] = zz / n

  // 特征值从大到小，对应的特征向量就是主轴
  let values = symmetric_eigenvalues(cov)
  let axes : Array[Vec3] = []
  // 三个特征值几乎相等 → 点云是**各向同性**的，主轴不唯一。
  //
  // 立方体就是典型：它的顶点关于中心完全对称，任何一组正交基都同样「正确」。
  // 这时候特征向量算出来是什么方向，完全由浮点噪声决定——盒子会歪着包上去，
  // 算出来的体积明显大于真实体积。
  //
  // PCA 本身给不出更好的答案（要精确解得上凸包 + 旋转卡壳）。
  // 这种情况退回轴对齐：方向虽然不一定最优，但至少是**紧的**
  let spread = values[0] - values[2]
  let scale = if values[0] > 0.0 { values[0] } else { 1.0 }
  if spread / scale < 1.0e-9 {
    axes.push(Vec3::new(1.0, 0.0, 0.0))
    axes.push(Vec3::new(0.0, 1.0, 0.0))
    axes.push(Vec3::new(0.0, 0.0, 1.0))
  } else {
    for k = 0; k < 3; k = k + 1 {
      axes.push(symmetric_eigenvector(cov, values[k]))
    }
  }

  // 把顶点投影到三个轴上，各取极值。
  // 投影的基准取重心——选哪里都行，取重心数值上稳一些
  let lo : Array[Double] = [0.0, 0.0, 0.0]
  let hi : Array[Double] = [0.0, 0.0, 0.0]
  for k = 0; k < 3; k = k + 1 {
    lo[k] = 1.0e300
    hi[k] = -1.0e300
  }
  for p in pts {
    for k = 0; k < 3; k = k + 1 {
      let d = p.sub(centroid).dot(axes[k])
      if d < lo[k] {
        lo[k] = d
      }
      if d > hi[k] {
        hi[k] = d
      }
    }
  }

  // 盒子中心 = 重心 + 各轴上的中点偏移
  let mut center = centroid
  let half : Array[Double] = []
  for k = 0; k < 3; k = k + 1 {
    let mid = (lo[k] + hi[k]) / 2.0
    center = Vec3::new(
      center.x + axes[k].x * mid,
      center.y + axes[k].y * mid,
      center.z + axes[k].z * mid,
    )
    half.push((hi[k] - lo[k]) / 2.0)
  }

  // 按边长从大到小排。主轴按特征值排是「分布最开的方向优先」，
  // 但用户看的是「盒子有多长多宽多高」，按长度排更直观
  let order = sort_axes_by_length(half)
  let sorted_axes : Array[Vec3] = []
  let sorted_half : Array[Double] = []
  for k in order {
    sorted_axes.push(axes[k])
    sorted_half.push(half[k])
  }
  Some({ center, axes: sorted_axes, half: sorted_half })
}

///|
/// 三个轴按半长从大到小排序，返回下标顺序。
///
/// 只有三个元素，直接手写比较比调排序省事
fn sort_axes_by_length(half : Array[Double]) -> Array[Int] {
  let idx : Array[Int] = [0, 1, 2]
  // 冒泡两轮，从大到小
  for _pass = 0; _pass < 2; _pass = _pass + 1 {
    for i = 0; i + 1 < 3; i = i + 1 {
      if half[idx[i]] < half[idx[i + 1]] {
        let t = idx[i]
        idx[i] = idx[i + 1]
        idx[i + 1] = t
      }
    }
  }
  idx
}

///|
/// 去重后的顶点位置。
///
/// 用 `pack_position` 量化去重——和校验、流式扫描、PLY 导出是同一套。
/// 「什么算同一个点」整个项目只有一个答案，不然同一条边
/// 在这个环节算共用的、到那个环节又算两个点，报告就会自相矛盾。
fn unique_positions(mesh : Mesh) -> Array[Vec3] {
  let table : Map[UInt64, Int] = Map([])
  let out : Array[Vec3] = []
  for t in mesh.triangles {
    for v in [t.a, t.b, t.c] {
      let key = pack_position(v)
      match table.get(key) {
        Some(_) => ()
        None => {
          table.set(key, out.length())
          out.push(v)
        }
      }
    }
  }
  out
}
