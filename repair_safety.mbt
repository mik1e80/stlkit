// SPDX-License-Identifier: Apache-2.0

///|
/// Work budgets for automatic repair. They do not guarantee process memory or
/// running time. Hole rings additionally need one incoming and outgoing edge,
/// a planar simple polygon and nondegenerate patch triangles.
pub(all) struct RepairLimits {
  max_faces : Int32
  max_boundary_edges : Int32
  max_hole_vertices : Int32
  max_holes : Int32
}

///|
pub fn RepairLimits::default() -> RepairLimits {
  {
    max_faces: 2000000,
    max_boundary_edges: 10000,
    max_hole_vertices: 512,
    max_holes: 128,
  }
}

///|
/// Repair finite input with checked options and bounded, simple planar holes.
/// Refused repairs return an error without modifying the input mesh. This is
/// not a general self-intersection, boolean or manufacturing repair operation.
pub fn repair_checked(
  mesh : Mesh,
  options : RepairOptions,
  limits~ : RepairLimits = RepairLimits::default(),
) -> Result[RepairResult, String] {
  if mesh_option_error(mesh, options.tolerance) is Some(message) {
    return Err(message)
  }
  if limits.max_faces < 1 ||
    limits.max_boundary_edges < 1 ||
    limits.max_hole_vertices < 3 ||
    limits.max_hole_vertices > 4096 ||
    limits.max_holes < 1 {
    return Err("invalid repair limits")
  }
  if mesh.triangle_count() > limits.max_faces {
    return Err("resource_limit: repair max_faces")
  }
  repair_inner(mesh, options, limits)
}

///|
/// Compatibility repair API. Refused/invalid input yields an unchanged
/// snapshot with zero change counts; use repair_checked() for an explanation.
pub fn repair(mesh : Mesh, options : RepairOptions) -> RepairResult {
  match repair_checked(mesh, options) {
    Ok(result) => result
    Err(_) =>
      {
        mesh: Mesh::new(mesh.triangles.copy()),
        removed_degenerate: 0,
        removed_duplicates: 0,
        filled_holes: 0,
        added_triangles: 0,
        recomputed_normals: 0,
        flipped_faces: 0,
        reoriented_components: 0,
      }
  }
}

///|
fn fill_holes_safe(
  triangles : Array[Triangle],
  ids : Array[(Int32, Int32, Int32)],
  limits : RepairLimits,
) -> Result[(Array[Triangle], Int32), String] {
  let counts : Map[(Int32, Int32), Int32] = Map([])
  let directions : Map[(Int32, Int32), (Int32, Int32)] = Map([])
  let positions : Map[Int32, Vec3] = Map([])
  for i, (a, b, c) in ids {
    let triangle = triangles[i]
    positions[a] = triangle.a
    positions[b] = triangle.b
    positions[c] = triangle.c
    for (start, finish) in [(a, b), (b, c), (c, a)] {
      let key = edge_key(start, finish)
      counts[key] = counts.get(key).unwrap_or(0) + 1
      directions[key] = (start, finish)
    }
  }
  let outgoing : Map[Int32, Int32] = Map([])
  let incoming : Map[Int32, Int32] = Map([])
  for key, count in counts {
    if count > 2 {
      return Err("unsafe hole repair: non-manifold edge")
    }
    if count != 1 {
      continue
    }
    let (a, b) = directions[key]
    if a == b || outgoing.contains(a) || incoming.contains(b) {
      return Err("unsafe hole repair: branching boundary")
    }
    outgoing[a] = b
    incoming[b] = a
    if outgoing.length() > limits.max_boundary_edges {
      return Err("resource_limit: repair max_boundary_edges")
    }
  }
  for vertex, _ in outgoing {
    if !incoming.contains(vertex) {
      return Err("unsafe hole repair: open boundary chain")
    }
  }
  let used : Map[Int32, Unit] = Map([])
  let patch : Array[Triangle] = []
  let mut holes = 0
  for start, _ in outgoing {
    if used.contains(start) {
      continue
    }
    let ring : Array[Vec3] = []
    let mut current = start
    while !used.contains(current) {
      used[current] = ()
      ring.push(positions[current])
      if ring.length() > limits.max_hole_vertices {
        return Err("resource_limit: repair max_hole_vertices")
      }
      current = match outgoing.get(current) {
        Some(next) => next
        None => return Err("unsafe hole repair: open boundary chain")
      }
    }
    if current != start || ring.length() < 3 {
      return Err("unsafe hole repair: non-simple ring")
    }
    holes += 1
    if holes > limits.max_holes {
      return Err("resource_limit: repair max_holes")
    }
    let faces = match triangulate_polygon(ring) {
      Ok(faces) => faces
      Err(message) => return Err("unsafe hole repair: " + message)
    }
    for (a, b, c) in faces {
      let triangle = Triangle::from_vertices(ring[a], ring[c], ring[b])
      if triangle_is_degenerate(triangle) {
        return Err("unsafe hole repair: degenerate patch")
      }
      if triangles.length().to_int64() + patch.length().to_int64() + 1L >
        limits.max_faces.to_int64() {
        return Err("resource_limit: repair max_faces after hole filling")
      }
      patch.push(triangle)
    }
  }
  let result = triangles.copy()
  for triangle in patch {
    result.push(triangle)
  }
  Ok((result, holes))
}
