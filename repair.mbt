// 网格修复。
//
// 校验负责指出问题，这里负责修。修完的网格会重新跑一遍校验，报告里
// 能直接看到「修之前 3 条边界边，修之后 0 条」。
//
// 四件事，从简单到麻烦：
//   1. 删退化面        三个点粘在一起、没有面积的面，删掉
//   2. 删重复面        同一个三角形出现两次，删掉后面的
//   3. 补洞            校验简单平面边界环后用耳切三角化补面
//   4. 重算法线        按顶点顺序重算，把文件里写错的法线覆盖掉
//
// 补洞是最有价值的一项，也是最容易出错的：新补的三角形绕向必须和原来
// 的面一致，否则补完还是水密不了（甚至更糟）。

///|
/// 修复选项。
pub(all) struct RepairOptions {
  /// 顶点焊接容差。判断「两个点是不是同一个」用的，和校验用同一个值
  tolerance : Double
  /// 删除退化面
  drop_degenerate : Bool
  /// 删除重复面
  drop_duplicates : Bool
  /// 补洞
  fill_holes : Bool
  /// 重算法线
  recompute_normals : Bool
  /// 统一相邻绕向，并将包围盒互不重叠的独立闭合分量调整为正体积方向。
  unify_winding : Bool
}

///|
/// 默认修复：什么都做。
pub fn RepairOptions::default() -> RepairOptions {
  {
    tolerance: default_weld_tolerance(),
    drop_degenerate: true,
    drop_duplicates: true,
    fill_holes: true,
    recompute_normals: true,
    unify_winding: true,
  }
}

///|
/// 只修法线，不动拓扑。适合「模型本来是好的，只是法线写错了」的情况。
pub fn RepairOptions::normals_only() -> RepairOptions {
  {
    tolerance: default_weld_tolerance(),
    drop_degenerate: false,
    drop_duplicates: false,
    fill_holes: false,
    recompute_normals: true,
    // 「只修法线」不该动拓扑，绕向也属于拓扑，一起关掉
    unify_winding: false,
  }
}

///|
/// 修复结果。除了修好的网格，还报告每一项具体做了多少。
///
/// 报告做了什么很重要：如果跑了修复但边界边从 3 变成 3，用户需要知道
/// 是「补洞没生效」还是「补了三处又破了三处」。光给一个网格说不清楚。
pub(all) struct RepairResult {
  /// 修好的网格
  mesh : Mesh
  /// 删掉的退化面数量
  removed_degenerate : Int32
  /// 删掉的重复面数量
  removed_duplicates : Int32
  /// 补上的洞的数量（按边界环计）
  filled_holes : Int32
  /// 为了补洞新增的三角形数量
  added_triangles : Int32
  /// 重算过法线的三角形数量
  recomputed_normals : Int32
  /// 相邻绕向一致性调整的面数，不含分量整体翻转。
  flipped_faces : Int32
  /// Isolated closed components whose entire direction was reversed.
  reoriented_components : Int32
}

///|
/// 做了什么修改。
pub fn RepairResult::changed(self : RepairResult) -> Bool {
  self.removed_degenerate > 0 ||
  self.removed_duplicates > 0 ||
  self.filled_holes > 0 ||
  self.recomputed_normals > 0 ||
  self.flipped_faces > 0 ||
  self.reoriented_components > 0
}

///|
/// 修复一个网格。
fn repair_inner(
  mesh : Mesh,
  options : RepairOptions,
  limits : RepairLimits,
) -> Result[RepairResult, String] {
  let mut removed_degenerate = 0
  let mut removed_duplicates = 0

  // 先用焊接编号把每个三角形转成三个整数下标。后面删退化面、找重复面、
  // 找边界边都要用这个，算一次就够了。
  let weld = weld_vertices(mesh, options.tolerance)
  let kept : Array[Triangle] = []
  let kept_ids : Array[(Int32, Int32, Int32)] = []
  let seen : Map[String, Unit] = Map([])

  for i, triangle in mesh.triangles {
    let ia = weld.ids[i * 3]
    let ib = weld.ids[i * 3 + 1]
    let ic = weld.ids[i * 3 + 2]

    // 退化面：焊接后有两个顶点是同一个点，这个面没有面积
    if options.drop_degenerate &&
      (ia == ib || ib == ic || ia == ic || triangle_is_degenerate(triangle)) {
      removed_degenerate = removed_degenerate + 1
      continue
    }

    // 重复面：三个顶点下标排序后相同的，就是同一个面。
    // 排序是为了让 (1,2,3) 和 (2,3,1) 被认成同一个——它们顶点顺序不同
    // 但是同一个三角形。绕向相反的 (1,3,2) 也会被认出来，那种是「同一块
    // 面贴了两遍，一片朝外一片朝里」，同样该删。
    if options.drop_duplicates {
      let key = canonical_key(ia, ib, ic)
      if seen.contains(key) {
        removed_duplicates = removed_duplicates + 1
        continue
      }
      seen.set(key, ())
    }

    kept.push(triangle)
    kept_ids.push((ia, ib, ic))
  }

  // 补洞。用「删完之后」的网格来找边界，不然会去补一个马上要删掉的面
  // 留下的洞。
  let mut filled_holes = 0
  let mut added_triangles = 0
  let mut result = kept
  if options.fill_holes {
    let before = result.length()
    let (patched, count) = match fill_holes_safe(result, kept_ids, limits) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    result = patched
    added_triangles = result.length() - before
    filled_holes = count
  }

  // 统一绕向。必须排在重算法线**之前**：绕向一变，法线跟着变，
  // 反过来做的话刚算好的法线会被绕向翻转作废。
  //
  // 这一步是「重算法线」修不了的那部分：顶点顺序写反的面，按它自己
  // 的顺序重算法线是**自洽的**（法线和绕向一致），但几何还是错的——
  // 体积求和时它的贡献符号反了。
  let mut flipped_faces = 0
  let mut reoriented_components = 0
  if options.unify_winding {
    let before = check_winding(Mesh::new(result), options.tolerance)
    flipped_faces = before.flipped_faces
    // 分量整体翻转单独计数；可能嵌套/重叠的壳层保留符号。
    let (aligned, count) = unify_winding_details(
      Mesh::new(result),
      options.tolerance,
    )
    result = aligned.triangles
    reoriented_components = count
  }

  // 重算法线。放在最后——删面、补洞、翻转绕向都会改变法线，先算就白算了。
  let mut recomputed = 0
  let final_triangles : Array[Triangle] = []
  for triangle in result {
    let computed = triangle.computed_normal()
    if options.recompute_normals {
      let changed = !same_vec(triangle.normal, computed)
      if changed {
        recomputed = recomputed + 1
      }
      final_triangles.push({ ..triangle, normal: computed, })
    } else {
      final_triangles.push(triangle)
    }
  }

  Ok({
    mesh: Mesh::new(final_triangles),
    removed_degenerate,
    removed_duplicates,
    filled_holes,
    added_triangles,
    recomputed_normals: recomputed,
    flipped_faces,
    reoriented_components,
  })
}

///|
/// 三个下标排序后拼成字符串。用来判断两个面是不是同一个。
fn canonical_key(a : Int32, b : Int32, c : Int32) -> String {
  let (x, y, z) = if a <= b && a <= c {
    if b <= c {
      (a, b, c)
    } else {
      (a, c, b)
    }
  } else if b <= a && b <= c {
    if a <= c {
      (b, a, c)
    } else {
      (b, c, a)
    }
  } else if a <= b {
    (c, a, b)
  } else {
    (c, b, a)
  }
  "\{x},\{y},\{z}"
}
