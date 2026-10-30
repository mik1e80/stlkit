// 质量属性：重心和转动惯量。
//
// 对应 trimesh 的 `mesh.center_mass` 和 `mesh.moment_inertia`。
//
// 算法和体积用的是同一套：把网格拆成一堆「局部参考点 + 三角形」的四面体，
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
// 以下底层计算不自动校验网格。CLI / 网页先通过
// PrintabilityReport::mass_properties_available()；它仍不证明无自相交。

///|
// Neumaier compensated summation, including cancellation between signed tetrahedra.
priv struct MomentSum {
  mut sum : Double
  mut correction : Double
}

///|
fn MomentSum::new() -> MomentSum {
  { sum: 0.0, correction: 0.0, }
}

///|
fn MomentSum::add(self : MomentSum, value : Double) -> Unit {
  let next = self.sum + value
  self.correction += if self.sum.abs() >= value.abs() {
    self.sum - next + value
  } else {
    value - next + self.sum
  }
  self.sum = next
}

///|
fn MomentSum::value(self : MomentSum) -> Double {
  self.sum + self.correction
}

///|
fn mass_reference(mesh : Mesh) -> Vec3 {
  match mesh.triangles {
    [] => Vec3::zero()
    [first, ..] => first.a
  }
}

///|
/// 一个四面体（原点 + 三角形 a b c）的有符号体积。
fn tet_volume(a : Vec3, b : Vec3, c : Vec3) -> Double {
  a.dot(b.cross(c)) / 6.0
}

///|
/// 网格的重心（质心）。假设材料密度均匀。
/// 不自动验证几何前提；调用方应先检查闭合、退化性和绕向 / 分量朝向。
///
/// 返回的是绝对坐标。网格不水密时这个数不可信——一阶矩和体积一样，
/// 靠各面的正负抵消算出来，有破洞就抵消不干净。
pub fn Mesh::center_mass(self : Mesh) -> Vec3 {
  let origin = mass_reference(self)
  let volume = MomentSum::new()
  let mx = MomentSum::new()
  let my = MomentSum::new()
  let mz = MomentSum::new()
  for t in self.triangles {
    let (a, b, c) = (t.a.sub(origin), t.b.sub(origin), t.c.sub(origin))
    let vol = tet_volume(a, b, c)
    volume.add(vol)
    // 四面体的重心是四个顶点的平均，原点是 (0,0,0)，
    // 所以是 (a+b+c)/4。乘上体积就是这个四面体的一阶矩
    mx.add(vol * (a.x + b.x + c.x) / 4.0)
    my.add(vol * (a.y + b.y + c.y) / 4.0)
    mz.add(vol * (a.z + b.z + c.z) / 4.0)
  }
  // 朝向整体反了的话（体积为负），三个分量一起是负的，
  // 相除仍然得到正确的位置——这里不用特殊处理
  if volume.value() == 0.0 {
    return Vec3::zero()
  }
  Vec3::new(
    origin.x + mx.value() / volume.value(),
    origin.y + my.value() / volume.value(),
    origin.z + mz.value() / volume.value(),
  )
}

///|
/// 网格关于**重心**的转动惯量张量，假设密度为 1。
/// 不自动验证几何前提，与 center_mass() 的调用责任相同。
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
  // 直接以重心为参考积分，避免绝对坐标二阶矩减去巨大的平行轴项。
  let origin = self.center_mass()
  let volume_sum = MomentSum::new()
  let xx = MomentSum::new()
  let yy = MomentSum::new()
  let zz = MomentSum::new()
  let xy = MomentSum::new()
  let yz = MomentSum::new()
  let zx = MomentSum::new()

  for t in self.triangles {
    let (a, b, c) = (t.a.sub(origin), t.b.sub(origin), t.c.sub(origin))
    let vol = tet_volume(a, b, c)
    volume_sum.add(vol)
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
    xx.add(vol * (sq_x + sx * sx) / 20.0)
    yy.add(vol * (sq_y + sy * sy) / 20.0)
    zz.add(vol * (sq_z + sz * sz) / 20.0)
    xy.add(vol * (sq_xy + sx * sy) / 20.0)
    yz.add(vol * (sq_yz + sy * sz) / 20.0)
    zx.add(vol * (sq_zx + sz * sx) / 20.0)
  }

  let sign = if volume_sum.value() < 0.0 { -1.0 } else { 1.0 }
  let ixx = sign * (yy.value() + zz.value())
  let iyy = sign * (xx.value() + zz.value())
  let izz = sign * (xx.value() + yy.value())
  let ixy = -sign * xy.value()
  let iyz = -sign * yz.value()
  let izx = -sign * zx.value()
  [ixx, ixy, izx, ixy, iyy, iyz, izx, iyz, izz]
}

///|
fn inertia_numeric_valid(tensor : FixedArray[Double]) -> Bool {
  if tensor.any(not_finite) ||
    tensor[0] < 0.0 ||
    tensor[4] < 0.0 ||
    tensor[8] < 0.0 {
    return false
  }
  let mut scale = 0.0
  for value in tensor {
    scale = scale.max(value.abs())
  }
  if scale == 0.0 {
    return false
  }
  let normalized : FixedArray[Double] = [
    tensor[0] / scale,
    tensor[1] / scale,
    tensor[2] / scale,
    tensor[3] / scale,
    tensor[4] / scale,
    tensor[5] / scale,
    tensor[6] / scale,
    tensor[7] / scale,
    tensor[8] / scale,
  ]
  let eigenvalues = symmetric_eigenvalues(normalized)
  !eigenvalues.any(not_finite) &&
  eigenvalues[2] >= -1.0e-12 &&
  eigenvalues[0] <= eigenvalues[1] + eigenvalues[2] + 1.0e-12
}

///|
/// Necessary numeric checks for mass properties: positive finite volume,
/// finite centroid, and physically admissible inertia. This does not prove
/// geometric validity or bound the numerical error; check the report's
/// mass_properties_available() separately on the same mesh.
pub fn Mesh::mass_properties_numeric_valid(self : Mesh) -> Bool {
  let volume = self.volume()
  !not_finite(volume) &&
  volume > 0.0 &&
  finite_vertex(self.center_mass()) &&
  inertia_numeric_valid(self.moment_inertia())
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
  // 特征值用共用实现（mat3.mbt）——有向包围盒的主轴也要用同一套，
  // 写两遍迟早会改漏一处
  symmetric_eigenvalues(self.moment_inertia())
}
