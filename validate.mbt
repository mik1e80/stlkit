// 网格校验：发现边界边、非流形边、退化面和已保留声明面法线的反向。
// 这些检查只覆盖部分几何问题，不能保证打印成功。
//
// 各项检查的原理都不复杂，难的是「两个顶点算不算同一个点」这个前置问题，
// 见下面 weld_vertices 的注释。

///|
/// 网格校验报告。
pub(all) struct ValidationReport {
  /// 三角形总数
  triangle_count : Int32
  /// 文件里写了多少个顶点（等于三角形数 × 3，STL 每个面都重写一遍自己的顶点）
  raw_vertex_count : Int32
  /// 焊接之后剩下多少个不同的顶点
  unique_vertex_count : Int32
  /// 只被一个面用到的边。数量大于零说明网格有破洞
  boundary_edge_count : Int32
  /// 被三个及以上面共用的边。这种边在真实物体上不该出现
  non_manifold_edge_count : Int32
  /// 退化三角形（三个点共线，面积为零）的数量
  degenerate_count : Int32
  /// 已保留声明面法线与几何法线点积 < 0 的数量；近零向量跳过。
  /// 不检查单位长度、垂直性或精确一致性；0 不代表完整法线验证。
  wrong_normal_count : Int32
  /// 不同边的条数（去重后）。和顶点数、三角形数一起能算出欧拉示性数
  unique_edge_count : Int32
}

///|
/// 欧拉示性数 χ = V − E + F。
///
/// 对应 trimesh 的 `mesh.euler_number`。和 `count_parts` 一样，
/// 是看了 trimesh 的设计之后补的，详细对比见 `COMPARISON.md`。
///
/// 对闭合、可定向的流形表面，这个数具有以下含义：
///
/// - 单个实体、没有洞（topologically 一个球面）：**χ = 2**
/// - 有一个穿透的洞（比如甜甜圈）：**χ = 0**
/// - 有两个穿透的洞：**χ = −2**
///
/// 有 k 个独立表面时，χ = 2k − 2Σg，g 为各表面的亏格。
/// 边闭合不证明网格无自相交或非流形顶点；解释前需要核实这些前提。
pub fn ValidationReport::euler_number(self : ValidationReport) -> Int32 {
  self.unique_vertex_count - self.unique_edge_count + self.triangle_count
}

///|
/// 网格是不是水密的。
///
/// 判据：每条边都恰好被两个面共用；不检查非流形顶点、自相交或朝向。
/// 空网格也满足这项边计数判据，调用方应另行检查三角形数。
pub fn ValidationReport::is_watertight(self : ValidationReport) -> Bool {
  self.boundary_edge_count == 0 && self.non_manifold_edge_count == 0
}

///|
/// 默认的顶点焊接容差。
///
/// 默认 1e-6 毫米是坐标格子宽度，不保证覆盖所有 float32 舍入误差。
/// 物理尺度与文件精度不同的模型，应由调用方选择合适容差。
pub fn default_weld_tolerance() -> Double {
  1.0e-6
}

///|
/// 用 Double 保存取整后的格子坐标，避免固定宽度整数截断。
/// 量化按格子相等判定，并非距离搜索；格子边界两侧的近点仍可能分开。
priv enum CoordinateKey {
  Grid(Double)
  Exact(Double)
} derive(Eq, Hash)

///|
fn quantize(value : Double, tolerance : Double) -> CoordinateKey {
  let scaled = value / tolerance
  // 不截成 Int，也不截低位。极端尺度除法溢出时，用独立的精确键。
  if scaled.is_inf() || scaled.is_nan() {
    return Exact(if value == 0.0 { 0.0 } else { value })
  }
  let q = scaled.round()
  Grid(if q == 0.0 { 0.0 } else { q })
}

///|
/// 三个完整的量化分量作为键，哈希冲突仍由逐分量相等判定区分。
priv struct PositionKey {
  x : CoordinateKey
  y : CoordinateKey
  z : CoordinateKey
} derive(Eq, Hash)

///|
fn position_key(v : Vec3, tolerance : Double) -> PositionKey {
  {
    x: quantize(v.x, tolerance),
    y: quantize(v.y, tolerance),
    z: quantize(v.z, tolerance),
  }
}

///|
/// 顶点焊接的结果。
pub(all) struct WeldResult {
  /// 每个顶点焊接后的编号。第 i 个顶点的编号是 ids[i]
  ids : Array[Int32]
  /// 焊接后剩下多少个不同的顶点
  unique_count : Int32
}

///|
/// 把重复的顶点合并，给每个顶点一个编号。
///
/// STL 格式本身没有「顶点表」——每个三角形把自己的三个顶点各写一遍，
/// 一个立方体 8 个顶点会写 36 遍。要做拓扑分析（哪条边被几个面共用），
/// 必须先把这些重复的点认出来是同一个。
///
/// 用 Map 存「量化后的坐标 → 编号」，第一次见到的坐标分配一个新编号，
/// 之后见到的复用。坐标量化的细节见 quantize。
fn weld_vertices(mesh : Mesh, tolerance : Double) -> WeldResult {
  let lookup : Map[PositionKey, Int32] = Map([])
  let ids : Array[Int32] = []
  let mut next_id = 0
  for triangle in mesh.triangles {
    for v in triangle.vertices() {
      // 完整的三分量键；哈希只负责查找，相等判定不会丢弃坐标高位。
      let key = position_key(v, tolerance)
      let id = match lookup.get(key) {
        Some(id) => id
        None => {
          let id = next_id
          lookup.set(key, id)
          next_id = next_id + 1
          id
        }
      }
      ids.push(id)
    }
  }
  { ids, unique_count: next_id, }
}

///|
/// 把一条边规范化成可比较的形式。
///
/// 一条边有两个端点，但从哪个面看过来顺序可能相反（第一个面是 a→b，
/// 相邻面是 b→a）。要统计「这条边被几个面用了」，得先让两个方向
/// 表示成同一个东西：小的编号在前。
fn edge_key(a : Int32, b : Int32) -> (Int32, Int32) {
  if a < b {
    (a, b)
  } else {
    (b, a)
  }
}

///|
/// 检查边计数、退化面和已保留声明面法线反向等有限项目。
pub fn validate(mesh : Mesh, tolerance : Double) -> ValidationReport {
  let weld = weld_vertices(mesh, tolerance)

  // 统计每条边被几个三角形共用。
  // 键是「小编号,大编号」拼成的字符串，值是出现次数。
  let edge_counts : Map[String, Int32] = Map([])
  let mut degenerate = 0
  let mut wrong_normal = 0

  for i, triangle in mesh.triangles {
    let ia = weld.ids[i * 3]
    let ib = weld.ids[i * 3 + 1]
    let ic = weld.ids[i * 3 + 2]

    // 退化面：三个顶点焊接后有两个或以上是同一个点，说明这个面没有面积。
    // 用焊接后的编号判断而不是看面积是否为零——焊接后的判断和拓扑一致，
    // 不会因为浮点误差漏掉。
    if ia == ib || ib == ic || ia == ic || triangle_is_degenerate(triangle) {
      degenerate = degenerate + 1
    }

    // 法线朝向：拿文件里写的法线和按顶点顺序算出来的比。
    // 点积为负仅说明声明向量与几何法线夹角超过 90 度，不能据此断言顶点绕向错误。
    // 不校验单位长度或垂直性；正交及同半球的其他向量不会计入。
    // 文件里法线填 0 0 0 的不算——那是「没填」，不是「填错了」。
    let declared = triangle.normal
    if !declared.is_zero(1.0e-9) {
      let computed = triangle.computed_normal()
      if declared.dot(computed) < 0.0 {
        wrong_normal = wrong_normal + 1
      }
    }

    // 三个顶点里如果有重复的，说明这条边是退化的，不该计进拓扑统计
    if ia != ib {
      let k = edge_key(ia, ib)
      let key = "\{k.0},\{k.1}"
      edge_counts.set(
        key,
        match edge_counts.get(key) {
          Some(n) => n + 1
          None => 1
        },
      )
    }
    if ib != ic {
      let k = edge_key(ib, ic)
      let key = "\{k.0},\{k.1}"
      edge_counts.set(
        key,
        match edge_counts.get(key) {
          Some(n) => n + 1
          None => 1
        },
      )
    }
    if ic != ia {
      let k = edge_key(ic, ia)
      let key = "\{k.0},\{k.1}"
      edge_counts.set(
        key,
        match edge_counts.get(key) {
          Some(n) => n + 1
          None => 1
        },
      )
    }
  }

  let mut boundary = 0
  let mut non_manifold = 0
  for _, count in edge_counts {
    if count == 1 {
      boundary = boundary + 1
    } else if count > 2 {
      non_manifold = non_manifold + 1
    }
  }

  {
    triangle_count: mesh.triangle_count(),
    raw_vertex_count: mesh.triangles.length() * 3,
    unique_vertex_count: weld.unique_count,
    boundary_edge_count: boundary,
    non_manifold_edge_count: non_manifold,
    degenerate_count: degenerate,
    wrong_normal_count: wrong_normal,
    unique_edge_count: edge_counts.length(),
  }
}

///|
/// 用默认容差校验。
pub fn validate_default(mesh : Mesh) -> ValidationReport {
  validate(mesh, default_weld_tolerance())
}

///|
/// 数一数这个网格由几个互不相连的实体组成。
///
/// 对应 trimesh 的 `mesh.split()`。这个能力是看了 trimesh 的设计之后补的，
/// 详细对比见仓库根目录的 `COMPARISON.md`。
///
/// 判据是**面的邻接**：两个三角形共用一条边就算连在一起，
/// 连通块的个数就是零件数。这和水密性用的是同一套拓扑，
/// 不需要额外的几何判断。
///
/// 为什么 3D 打印要看这个：切片软件按连通块分别生成路径，
/// 一个「看起来是一个模型」的文件里如果有 5 块互不相连的几何，
/// 打出来就是 5 个零散的东西——它们可能根本没连在一起，拿起来就散了。
/// 而且这类问题从预览图上看不出来，模型画出来是完整的。
///
/// 注意**只有共用边才算连接**。两个零件刚好顶点碰着顶点不算——
/// 那种接触在切片时是断的，和分开放没有区别。
/// （这也是为什么不用「顶点相同就算连通」来判，那样会漏报。）
pub fn count_parts(mesh : Mesh, tolerance : Double) -> Int32 {
  let n = mesh.triangle_count()
  if n == 0 {
    return 0
  }
  let weld = weld_vertices(mesh, tolerance)

  // 无向边 → 用到它的面。同一条边上的面互为邻居
  let edge_faces : Map[String, Array[Int32]] = Map([])
  for i = 0; i < n; i = i + 1 {
    let ia = weld.ids[i * 3]
    let ib = weld.ids[i * 3 + 1]
    let ic = weld.ids[i * 3 + 2]
    for e in [(ia, ib), (ib, ic), (ic, ia)] {
      // 焊接后两端重合的边是退化的，不算连接
      if e.0 == e.1 {
        continue
      }
      let k = edge_key(e.0, e.1)
      let key = "\{k.0},\{k.1}"
      let list = match edge_faces.get(key) {
        Some(l) => l
        None => {
          let l : Array[Int32] = []
          edge_faces.set(key, l)
          l
        }
      }
      list.push(i)
    }
  }

  let visited : Array[Bool] = []
  for _i = 0; _i < n; _i = _i + 1 {
    visited.push(false)
  }

  let mut parts = 0
  // 每个连通块做一次广度优先。用下标当队头而不用 pop，
  // 免得每弹一个元素就挪一次数组
  let queue : Array[Int32] = []
  for seed = 0; seed < n; seed = seed + 1 {
    if visited[seed] {
      continue
    }
    parts = parts + 1
    visited[seed] = true
    queue.clear()
    queue.push(seed)
    let mut head = 0
    while head < queue.length() {
      let cur = queue[head]
      head = head + 1
      let a = weld.ids[cur * 3]
      let b = weld.ids[cur * 3 + 1]
      let c = weld.ids[cur * 3 + 2]
      for e in [(a, b), (b, c), (c, a)] {
        if e.0 == e.1 {
          continue
        }
        let k = edge_key(e.0, e.1)
        match edge_faces.get("\{k.0},\{k.1}") {
          Some(list) =>
            for other in list {
              if !visited[other] {
                visited[other] = true
                queue.push(other)
              }
            }
          None => ()
        }
      }
    }
  }
  parts
}

///|
/// 用默认容差数零件。
pub fn count_parts_default(mesh : Mesh) -> Int32 {
  count_parts(mesh, default_weld_tolerance())
}
