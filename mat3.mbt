// 对称 3×3 矩阵的特征分解。
//
// 两个地方要用：转动惯量的主惯量（质量属性）、有向包围盒的主轴（PCA）。
// 都是「对称 3×3 矩阵求特征值/特征向量」，抽出来共用，不写两遍。
//
// 对称矩阵的特征值一定是实数，所以有闭式解（Cardano 公式），不用迭代。
// 非对称的矩阵没这个性质，那就不在这个文件的职责范围里了。

///|
/// 对称 3×3 矩阵的特征值，**从大到小**。
///
/// 输入按行排列的 9 个数（[0..2] 第一行，[3..5] 第二行，[6..8] 第三行），
/// 只用得到上三角——对称矩阵的下三角是重复的。
pub fn symmetric_eigenvalues(m : FixedArray[Double]) -> FixedArray[Double] {
  let a = m[0]
  let b = m[1]
  let c = m[2]
  let d = m[4]
  let e = m[5]
  let f = m[8]

  // 特征多项式：λ³ − p λ² + q λ − r = 0
  let p = a + d + f
  let q = a * d + d * f + f * a - b * b - c * c - e * e
  let r = a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d)

  // 消掉二次项：λ = x + p/3，得到 x³ + p2·x + q2 = 0
  //
  // 常数项是 s³ − p·s² + q·s − r（s = p/3）展开的结果：
  //     p³/27 − p³/9 + pq/3 − r = −2p³/27 + pq/3 − r
  //
  // 这三个符号**都要小心**：抄反一个，特征值就全错。而且错得很有欺骗性——
  // 三个根加起来还是等于 p（迹是不变量），光检查「和等于迹」发现不了
  let shift = p / 3.0
  let p2 = q - p * p / 3.0
  let q2 = -2.0 * p * p * p / 27.0 + p * q / 3.0 - r

  let half = q2 / 2.0
  let third = p2 / 3.0
  let disc = half * half + third * third * third
  let roots : FixedArray[Double] = FixedArray::make(3, 0.0)
  if disc >= 0.0 {
    // 一个实根 + 一对复根。对称实矩阵不会出现这种情况，
    // 但浮点误差可能让重根附近算出一个极小的正数，所以这条路得留着
    let s = disc.sqrt()
    let u = @math.cbrt(-half + s)
    let v = @math.cbrt(-half - s)
    roots[0] = u + v + shift
    roots[1] = -(u + v) / 2.0 + shift
    roots[2] = roots[1]
  } else {
    // 三个不同的实根（对称矩阵的正常情况），走三角函数形式
    let radius = (-third).sqrt()
    let cos_arg = -half / (radius * radius * radius)
    // acos 的定义域是 [-1, 1]，浮点误差会让它偶尔越界一点点
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
  roots.sort()
  [roots[2], roots[1], roots[0]]
}

///|
/// 求某个特征值对应的单位特征向量。
///
/// 做法：算 B = A − λI，然后取 B 的三行两两叉乘，挑模长最大的那个。
///
/// 为什么不直接解方程组：λ 是数值算出来的，代入之后 B 通常不满秩，
/// 靠选主元解出来的向量可能全是噪声。而叉乘天然给出「垂直于两行」的方向，
/// 哪个叉乘最大就说明哪两行最独立——这也顺带躲开了「某一行恰好是零行」的情况。
pub fn symmetric_eigenvector(m : FixedArray[Double], lambda : Double) -> Vec3 {
  let rows = [
    Vec3::new(m[0] - lambda, m[1], m[2]),
    Vec3::new(m[3], m[4] - lambda, m[5]),
    Vec3::new(m[6], m[7], m[8] - lambda),
  ]
  let candidates = [
    rows[0].cross(rows[1]),
    rows[1].cross(rows[2]),
    rows[2].cross(rows[0]),
  ]
  let mut best = Vec3::zero()
  let mut best_len = -1.0
  for v in candidates {
    let len = v.length()
    if len > best_len {
      best_len = len
      best = v
    }
  }
  best.normalize()
}
