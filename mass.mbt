// 质量属性：重心和转动惯量。
//
// 对应 trimesh 的 `mesh.center_mass` 和 `mesh.moment_inertia`。
//
// 算法和体积用的是同一套：把网格拆成一堆「原点 + 三角形」的四面体，
// 用散度定理把体积分变成面积分。体积是零阶矩，重心是一阶矩，
// 转动惯量是二阶矩——同一个套路往下走而已：
//
//     体积   = Σ 有符号四面体体积
//     一阶矩 = Σ 体积 × 四面体重心
//     二阶矩 = Σ 体积 × (四面体的二阶矩公式)
//
// 为什么值得单独做：**重心偏了的模型打印时容易倒**。这不是几何上「坏」，
// 水密性检查一个字都不会说，但它是个实打实的打印问题。
//
// 前提：**网格要水密，而且朝向一致**。有破洞的话正负抵消不干净，
// 算出来的数没有意义——这一点报告里会说明，不装作没这回事。

///|
/// 一个四面体（原点 + 三角形 a b c）的有符号体积。
fn tet_volume(a : Vec3, b : Vec3, c : Vec3) -> Double {
  a.dot(b.cross(c)) / 6.0
}

///|
/// 网格的重心（质心）。假设材料密度均匀。
///
/// 返回的是绝对坐标。网格不水密时这个数不可信——一阶矩和体积一样，
/// 靠各面的正负抵消算出来，有破洞就抵消不干净。
pub fn Mesh::center_mass(self : Mesh) -> Vec3 {
  let mut volume = 0.0
  let mut mx = 0.0
  let mut my = 0.0
  let mut mz = 0.0
  for t in self.triangles {
    let (a, b, c) = (t.a, t.b, t.c)
    let vol = tet_volume(a, b, c)
    volume = volume + vol
    // 四面体的重心是四个顶点的平均，原点是 (0,0,0)，
    // 所以是 (a+b+c)/4。乘上体积就是这个四面体的一阶矩
    mx = mx + vol * (a.x + b.x + c.x) / 4.0
    my = my + vol * (a.y + b.y + c.y) / 4.0
    mz = mz + vol * (a.z + b.z + c.z) / 4.0
  }
  // 朝向整体反了的话（体积为负），三个分量一起是负的，
  // 相除仍然得到正确的位置——这里不用特殊处理
  if volume == 0.0 {
    return Vec3::zero()
  }
  Vec3::new(mx / volume, my / volume, mz / volume)
}

///|
/// 网格关于**重心**的转动惯量张量，假设密度为 1。
///
/// 返回 9 个数，按行排列：
///
/// ```text
/// [0] [1] [2]      Ixx Ixy Ixz
/// [3] [4] [5]  =   Iyx Iyy Iyz
/// [6] [7] [8]      Izx Izy Izz
/// ```
///
/// 张量是对称的（Ixy = Iyx），所以实际只有 6 个独立分量，
/// 另外 3 个是重复的——保留完整 3×3 是为了和 trimesh 的 `moment_inertia`
/// 对得上，用起来不用想「哪个下标是哪个」。
///
/// 对应 trimesh 的 `mesh.moment_inertia`（`density=1` 时的结果）。
pub fn Mesh::moment_inertia(self : Mesh) -> FixedArray[Double] {
  // 关于原点的二阶矩。四个顶点是「原点 + a + b + c」
  let mut volume = 0.0
  let mut s_xx = 0.0
  let mut s_yy = 0.0
  let mut s_zz = 0.0
  let mut s_xy = 0.0
  let mut s_yz = 0.0
  let mut s_zx = 0.0

  for t in self.triangles {
    let (a, b, c) = (t.a, t.b, t.c)
    let vol = tet_volume(a, b, c)
    volume = volume + vol
    // 四个顶点各分量之和。原点是 0，所以只要 a+b+c
    let sx = a.x + b.x + c.x
    let sy = a.y + b.y + c.y
    let sz = a.z + b.z + c.z
    // 平方和与两两乘积：原点是 (0,0,0)，所以这四项都只算 a/b/c 三个顶点
    let sq_x = a.x * a.x + b.x * b.x + c.x * c.x
    let sq_y = a.y * a.y + b.y * b.y + c.y * c.y
    let sq_z = a.z * a.z + b.z * b.z + c.z * c.z
    let sq_xy = a.x * a.y + b.x * b.y + c.x * c.y
    let sq_yz = a.y * a.z + b.y * b.z + c.y * c.z
    let sq_zx = a.z * a.x + b.z * b.x + c.z * c.x

    // 单纯形上的多项式积分（四面体是 n=3 的单纯形）：
    //
    //   ∫ x_i x_j dV = V/20 · [ Σ_k v_{k,i}·v_{k,j} + (Σ_k v_{k,i})(Σ_k v_{k,j}) ]
    //
    // **两项都要**。第二项是两个和的乘积、不是小数，漏掉的话结果会明显偏小；
    // 而且它对角和非对角一视同仁，不用分情况。
    //
    // （一开始我推错了，写成「对角 V/10、非对角 V/20」，那只有在
    //  「原点 + 坐标轴上的三个点」这种特殊四面体上才凑巧对得上。
    //   用长方体一测就露馅了：算出来 12/60，正确答案是 20/60）
    s_xx = s_xx + vol * (sq_x + sx * sx) / 20.0
    s_yy = s_yy + vol * (sq_y + sy * sy) / 20.0
    s_zz = s_zz + vol * (sq_z + sz * sz) / 20.0
    s_xy = s_xy + vol * (sq_xy + sx * sy) / 20.0
    s_yz = s_yz + vol * (sq_yz + sy * sz) / 20.0
    s_zx = s_zx + vol * (sq_zx + sz * sx) / 20.0
  }

  // 朝向整体反了的话，所有矩都是负的。翻转过来，
  // 这样「顶点顺序写反了的模型」也能算出正确的物理量
  if volume < 0.0 {
    s_xx = -s_xx
    s_yy = -s_yy
    s_zz = -s_zz
    s_xy = -s_xy
    s_yz = -s_yz
    s_zx = -s_zx
  }

  // 关于原点的惯性张量：I = 迹(二阶矩)·单位阵 − 二阶矩
  let trace = s_xx + s_yy + s_zz
  let i_xx = trace - s_xx
  let i_yy = trace - s_yy
  let i_zz = trace - s_zz
  let i_xy = -s_xy
  let i_yz = -s_yz
  let i_zx = -s_zx

  // 平移到重心：平行轴定理。m = |V|（密度取 1）
  let center = self.center_mass()
  let mass = if volume < 0.0 { -volume } else { volume }
  let cc = center.dot(center)
  let i_xx_c = i_xx - mass * (cc - center.x * center.x)
  let i_yy_c = i_yy - mass * (cc - center.y * center.y)
  let i_zz_c = i_zz - mass * (cc - center.z * center.z)
  let i_xy_c = i_xy - mass * (0.0 - center.x * center.y)
  let i_yz_c = i_yz - mass * (0.0 - center.y * center.z)
  let i_zx_c = i_zx - mass * (0.0 - center.z * center.x)

  [
    i_xx_c, i_xy_c, i_zx_c,
    i_xy_c, i_yy_c, i_yz_c,
    i_zx_c, i_yz_c, i_zz_c,
  ]
}

///|
/// 惯量主轴上的三个主转动惯量（把转动惯量张量对角化之后的三个特征值）。
///
/// 对应 trimesh 的 `mesh.principal_inertia_components`。
///
/// 三个数按**从大到小**返回。物理含义是：绕着对应主轴转的时候，
/// 需要用到的力矩——最小的那个轴就是「最容易转起来的轴」。
///
/// 张量是对称的，所以特征值有闭式解（Cardano 公式），不用迭代。
pub fn Mesh::principal_moments(self : Mesh) -> FixedArray[Double] {
  let m = self.moment_inertia()
  let a = m[0]
  let b = m[1]
  let c = m[2]
  let d = m[4]
  let e = m[5]
  let f = m[8]

  // 对称 3×3 的特征多项式： λ³ − p λ² + q λ − r = 0
  let p = a + d + f
  let q = a * d + d * f + f * a - b * b - c * c - e * e
  let r = a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d)

  // 消掉二次项：λ = x + p/3，得到 x³ + p2·x + q2 = 0
  //
  // 常数项是 s³ − I₁s² + I₂s − I₃（s = I₁/3）展开的结果：
  //     I₁³/27 − I₁³/9 + I₁I₂/3 − I₃ = −2I₁³/27 + I₁I₂/3 − I₃
  //
  // 这三个符号**都要小心**：写反一个，特征值就全错。
  // 一开始我就在这里把整体符号抄反了，算出来的三个根加起来还对（迹是不变量），
  // 但每个值都偏了 33333.33——这种错光看「和等于迹」是发现不了的
  let shift = p / 3.0
  let p2 = q - p * p / 3.0
  let q2 = -2.0 * p * p * p / 27.0 + p * q / 3.0 - r

  // x³ + p2·x + q2 = 0，用 Cardano 公式
  let half = q2 / 2.0
  let third = p2 / 3.0
  let disc = half * half + third * third * third
  let roots : FixedArray[Double] = FixedArray::make(3, 0.0)
  if disc >= 0.0 {
    // 一个实根两个复根（对称实矩阵不会出现，保险起见还是写上）
    let s = disc.sqrt()
    let u = @math.cbrt(-half + s)
    let v = @math.cbrt(-half - s)
    roots[0] = u + v + shift
    roots[1] = -(u + v) / 2.0 + shift
    roots[2] = roots[1]
  } else {
    // 三个不同的实根（对称矩阵的正常情况）
    let radius = (-third).sqrt()
    let cos_arg = -half / (radius * radius * radius)
    // acos 的定义域是 [-1, 1]，浮点误差可能让它超出去一点点
    let clamped = if cos_arg > 1.0 {
      1.0
    } else if cos_arg < -1.0 {
      -1.0
    } else {
      cos_arg
    }
    let theta = @math.acos(clamped)
    for k = 0; k < 3; k = k + 1 {
      let angle = (theta - 2.0 * 3.141592653589793 * k.to_double()) / 3.0
      roots[k] = 2.0 * radius * @math.cos(angle) + shift
    }
  }
  // 从大到小
  roots.sort()
  [roots[2], roots[1], roots[0]]
}
