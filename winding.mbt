// Shared-edge components, local consistency, and signed shell orientation.

///|
pub(all) enum WindingOrientation {
  PositiveVolume
  NegativeVolume
  Indeterminate
} derive(Eq)

///|
pub extend WindingOrientation with Eq::{not_equal, equal}

///|
pub fn WindingOrientation::label(self : WindingOrientation) -> String {
  match self {
    PositiveVolume => "正体积方向"
    NegativeVolume => "负体积方向"
    Indeterminate => "朝向未确定"
  }
}

///|
pub(all) struct WindingComponent {
  index : Int
  /// Original face indices, for locating the component in the input mesh.
  faces : Array[Int]
  flipped_faces : Int
  closed : Bool
  consistent : Bool
  signed_volume : Double
  orientation : WindingOrientation
  bounds : Aabb
  /// A conservative AABB overlap test, not a shell nesting classification.
  potentially_nested : Bool
}

///|
pub(all) struct WindingReport {
  flipped_faces : Int
  consistent : Bool
  /// Aggregate diagnostic only: signs of different components may cancel.
  signed_volume : Double
  components : Array[WindingComponent]
}

///|
pub fn WindingReport::negative_components(self : WindingReport) -> Int {
  self.components.filter(c => c.orientation == NegativeVolume).length()
}

///|
pub fn WindingReport::orientation_reliable(self : WindingReport) -> Bool {
  !self.components.is_empty() &&
  !self.components.any(c => {
    c.orientation != PositiveVolume || c.potentially_nested
  })
}

///|
priv struct WindingPartition {
  flags : Array[Bool]
  faces : Array[Array[Int]]
  closed : Array[Bool]
  orientable : Array[Bool]
}

///|
fn winding_edge_key(a : Int, b : Int) -> String {
  if a < b {
    "\{a},\{b}"
  } else {
    "\{b},\{a}"
  }
}

///|
fn winding_partition(mesh : Mesh, tolerance : Double) -> WindingPartition {
  let n = mesh.triangle_count()
  let flags = Array::make(n, false)
  let labels = Array::make(n, -1)
  let weld = weld_vertices(mesh, tolerance)
  let ids = Array::makei(n, i => {
    (weld.ids[i * 3], weld.ids[i * 3 + 1], weld.ids[i * 3 + 2])
  })
  let edges : Map[String, Array[(Int, Int)]] = Map([])
  for i, (a, b, c) in ids {
    for (u, v) in [(a, b), (b, c), (c, a)] {
      let key = winding_edge_key(u, v)
      let list = match edges.get(key) {
        Some(list) => list
        None => {
          let list = []
          edges.set(key, list)
          list
        }
      }
      list.push((i, if u < v { 1 } else { -1 }))
    }
  }
  let faces = []
  let closed = []
  let orientable = []
  for seed = 0; seed < n; seed = seed + 1 {
    if labels[seed] >= 0 {
      continue
    }
    let component = faces.length()
    let group = []
    let stack = [seed]
    let mut is_closed = true
    let mut is_orientable = true
    labels[seed] = component
    while !stack.is_empty() {
      let cur = stack.pop().unwrap()
      group.push(cur)
      let (a, b, c) = ids[cur]
      for (u, v) in [(a, b), (b, c), (c, a)] {
        let list = edges.get(winding_edge_key(u, v)).unwrap()
        if list.length() != 2 || u == v {
          is_closed = false
        }
        let dir = if u < v { 1 } else { -1 }
        for (j, other_dir) in list {
          if j == cur {
            continue
          }
          let expected = if dir == other_dir { !flags[cur] } else { flags[cur] }
          if labels[j] < 0 {
            labels[j] = component
            flags[j] = expected
            stack.push(j)
          } else if flags[j] != expected {
            is_orientable = false
          }
        }
      }
    }
    faces.push(group)
    closed.push(is_closed)
    orientable.push(is_orientable)
  }
  { flags, faces, closed, orientable, }
}

///|
fn winding_bounds_overlap(a : Aabb, b : Aabb) -> Bool {
  a.min.x <= b.max.x &&
  b.min.x <= a.max.x &&
  a.min.y <= b.max.y &&
  b.min.y <= a.max.y &&
  a.min.z <= b.max.z &&
  b.min.z <= a.max.z
}

///|
pub fn check_winding(mesh : Mesh, tolerance : Double) -> WindingReport {
  let part = winding_partition(mesh, tolerance)
  let components = []
  let mut total_flips = 0
  let mut total_signed = 0.0
  let mut all_consistent = true
  for index, group in part.faces {
    let origin = mesh.triangles[group[0]].a
    let mut lo = origin
    let mut hi = origin
    let mut signed = 0.0
    let mut compensation = 0.0
    let mut flips = 0
    for face in group {
      if part.flags[face] {
        flips = flips + 1
      }
      let t = mesh.triangles[face]
      // Local origin and compensated summation reduce cancellation under translation.
      let contribution = t.a
        .sub(origin)
        .dot(t.b.sub(origin).cross(t.c.sub(origin))) /
        6.0
      let corrected = contribution - compensation
      let sum = signed + corrected
      compensation = sum - signed - corrected
      signed = sum
      for v in [t.a, t.b, t.c] {
        lo = Vec3::new(lo.x.min(v.x), lo.y.min(v.y), lo.z.min(v.z))
        hi = Vec3::new(hi.x.max(v.x), hi.y.max(v.y), hi.z.max(v.z))
      }
    }
    let consistent = flips == 0 && part.orientable[index]
    let orientation = if !part.closed[index] ||
      !consistent ||
      signed.is_nan() ||
      signed.is_inf() ||
      signed == 0.0 {
      Indeterminate
    } else if signed < 0.0 {
      NegativeVolume
    } else {
      PositiveVolume
    }
    components.push({
      index,
      faces: group,
      flipped_faces: flips,
      closed: part.closed[index],
      consistent,
      signed_volume: signed,
      orientation,
      bounds: { min: lo, max: hi, },
      potentially_nested: false,
    })
    total_flips = total_flips + flips
    total_signed = total_signed + signed
    if !consistent {
      all_consistent = false
    }
  }
  let order = Array::makei(components.length(), i => i)
  order.sort_by((i, j) => {
    components[i].bounds.min.x.compare(components[j].bounds.min.x)
  })
  for a = 0; a < order.length(); a = a + 1 {
    let i = order[a]
    for b = a + 1; b < order.length(); b = b + 1 {
      let j = order[b]
      if components[j].bounds.min.x > components[i].bounds.max.x {
        break
      }
      if winding_bounds_overlap(components[i].bounds, components[j].bounds) {
        components[i] = { ..components[i], potentially_nested: true, }
        components[j] = { ..components[j], potentially_nested: true, }
      }
    }
  }
  {
    flipped_faces: total_flips,
    consistent: all_consistent,
    signed_volume: total_signed,
    components,
  }
}

///|
fn flip_winding(t : Triangle) -> Triangle {
  { ..t, b: t.c, c: t.b, }
}

///|
/// Make adjacent faces consistent, then orient isolated closed components positive.
/// Potentially nested/overlapping shells retain their sign for manual review.
fn unify_winding_details(mesh : Mesh, tolerance : Double) -> (Mesh, Int) {
  let part = winding_partition(mesh, tolerance)
  let triangles = mesh.triangles.copy()
  for i, group in part.faces {
    if !part.orientable[i] {
      continue
    }
    for face in group {
      if part.flags[face] {
        triangles[face] = flip_winding(triangles[face])
      }
    }
  }
  let report = check_winding(Mesh::new(triangles), tolerance)
  let mut reoriented = 0
  for component in report.components {
    if component.orientation == NegativeVolume && !component.potentially_nested {
      for face in component.faces {
        triangles[face] = flip_winding(triangles[face])
      }
      reoriented = reoriented + 1
    }
  }
  (Mesh::new(triangles), reoriented)
}

///|
pub fn unify_winding(mesh : Mesh, tolerance : Double) -> Mesh {
  let (result, _) = unify_winding_details(mesh, tolerance)
  result
}

///|
pub fn check_winding_default(mesh : Mesh) -> WindingReport {
  check_winding(mesh, default_weld_tolerance())
}
