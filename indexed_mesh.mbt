// SPDX-License-Identifier: Apache-2.0

///|
pub(all) struct Face3 {
  a : Int32
  b : Int32
  c : Int32
}

///|
/// Owns snapshots of finite positions, valid face indices and per-face declared
/// normals. Unreferenced and coincident vertices are permitted. Attribute/UV
/// document semantics are not represented by this geometry-only type.
pub struct IndexedMesh {
  priv positions : Array[Vec3]
  priv indices : Array[Face3]
  priv normals : Array[Vec3]
}

///|
/// Copies input arrays. Empty normals mean zero declared normals; otherwise the
/// length must equal faces.length(). Degenerate faces are retained for diagnosis.
///
/// ```moonbit nocheck
/// let mesh = @stlkit.IndexedMesh::new(
///   [@stlkit.Vec3::zero(), @stlkit.Vec3::new(1, 0, 0), @stlkit.Vec3::new(0, 1, 0)],
///   [{ a: 0, b: 1, c: 2, }],
/// )
/// ```
pub fn IndexedMesh::new(
  vertices : Array[Vec3],
  faces : Array[Face3],
  normals~ : Array[Vec3] = [],
) -> Result[IndexedMesh, String] {
  if faces.length() > 715827882 {
    return Err("indexed face count overflows expanded corner count")
  }
  for i, point in vertices {
    if !finite_vertex(point) {
      return Err("indexed vertex \{i} is non-finite")
    }
  }
  if !normals.is_empty() && normals.length() != faces.length() {
    return Err("indexed declared normals must match face count")
  }
  for i, normal in normals {
    if !finite_vertex(normal) {
      return Err("indexed normal \{i} is non-finite")
    }
  }
  for i, face in faces {
    for index in [face.a, face.b, face.c] {
      if index < 0 || index >= vertices.length() {
        return Err("indexed face \{i} references invalid vertex \{index}")
      }
    }
  }
  Ok({
    positions: vertices.copy(),
    indices: faces.copy(),
    normals: if normals.is_empty() {
      Array::make(faces.length(), Vec3::zero())
    } else {
      normals.copy()
    },
  })
}

///|
pub fn IndexedMesh::vertex_count(self : IndexedMesh) -> Int32 {
  self.positions.length()
}

///|
pub fn IndexedMesh::triangle_count(self : IndexedMesh) -> Int32 {
  self.indices.length()
}

///|
/// Returns a detached copy, preserving the constructor's validation invariant.
pub fn IndexedMesh::vertices(self : IndexedMesh) -> Array[Vec3] {
  self.positions.copy()
}

///|
pub fn IndexedMesh::faces(self : IndexedMesh) -> Array[Face3] {
  self.indices.copy()
}

///|
pub fn IndexedMesh::declared_normals(self : IndexedMesh) -> Array[Vec3] {
  self.normals.copy()
}

///|
pub fn IndexedMesh::unused_vertex_count(self : IndexedMesh) -> Int32 {
  let used = FixedArray::make(self.positions.length(), false)
  for face in self.indices {
    used[face.a] = true
    used[face.b] = true
    used[face.c] = true
  }
  used.iter().filter(value => !value).count()
}

///|
pub fn IndexedMesh::to_mesh(self : IndexedMesh) -> Mesh {
  let triangles : Array[Triangle] = []
  for i, face in self.indices {
    triangles.push({
      normal: self.normals[i],
      a: self.positions[face.a],
      b: self.positions[face.b],
      c: self.positions[face.c],
    })
  }
  Mesh::new(triangles)
}

///|
fn indexed_exact_key(point : Vec3) -> PositionKey {
  {
    x: Exact(if point.x == 0.0 { 0.0 } else { point.x }),
    y: Exact(if point.y == 0.0 { 0.0 } else { point.y }),
    z: Exact(if point.z == 0.0 { 0.0 } else { point.z }),
  }
}

///|
/// Exact coordinate deduplication (including signed zero), not tolerance welding.
/// Face order, winding, degenerate faces and declared normals are preserved.
pub fn Mesh::to_indexed(self : Mesh) -> Result[IndexedMesh, String] {
  if self.triangles.length() > 715827882 {
    return Err("indexed face count overflows expanded corner count")
  }
  let positions : Array[Vec3] = []
  let indices : Array[Face3] = []
  let normals : Array[Vec3] = []
  let table : Map[PositionKey, Int32] = Map([])
  for i, triangle in self.triangles {
    if !finite_vertex(triangle.normal) {
      return Err("indexed normal \{i} is non-finite")
    }
    let ids : Array[Int32] = []
    for point in [triangle.a, triangle.b, triangle.c] {
      if !finite_vertex(point) {
        return Err("indexed vertex on face \{i} is non-finite")
      }
      let key = indexed_exact_key(point)
      let id = match table.get(key) {
        Some(id) => id
        None => {
          let id = positions.length()
          positions.push(point)
          table.set(key, id)
          id
        }
      }
      ids.push(id)
    }
    indices.push({ a: ids[0], b: ids[1], c: ids[2], })
    normals.push(triangle.normal)
  }
  Ok({ positions, indices, normals, })
}

///|
pub fn IndexedMesh::surface_area(self : IndexedMesh) -> Double {
  let mut total = 0.0
  for face in self.indices {
    total += Triangle::from_vertices(
      self.positions[face.a],
      self.positions[face.b],
      self.positions[face.c],
    ).area()
  }
  total
}

///|
/// Same conditional oriented-volume interpretation as Mesh::volume().
pub fn IndexedMesh::volume(self : IndexedMesh) -> Double {
  let mut total = 0.0
  for face in self.indices {
    total += self.positions[face.a].dot(
        self.positions[face.b].cross(self.positions[face.c]),
      ) /
      6.0
  }
  total.abs()
}

///|
/// Bounds of referenced geometry only. Unused vertices do not change the bounds;
/// a document with no faces returns None, even if it stores unused positions.
pub fn IndexedMesh::bounding_box(self : IndexedMesh) -> Aabb? {
  let mut bounds : Aabb? = None
  for face in self.indices {
    for index in [face.a, face.b, face.c] {
      let point = self.positions[index]
      bounds = Some(
        match bounds {
          None => { min: point, max: point, }
          Some(box) =>
            {
              min: Vec3::new(
                box.min.x.min(point.x),
                box.min.y.min(point.y),
                box.min.z.min(point.z),
              ),
              max: Vec3::new(
                box.max.x.max(point.x),
                box.max.y.max(point.y),
                box.max.z.max(point.z),
              ),
            }
        },
      )
    }
  }
  bounds
}

///|
/// Compatibility implementation: temporarily expands Mesh and uses the existing
/// coordinate-welding topology rules. This does not validate index identity as
/// a separate topology, nor promise reduced peak memory during validation.
pub fn IndexedMesh::validate(
  self : IndexedMesh,
  tolerance~ : Double = default_weld_tolerance(),
) -> ValidationReport {
  validate(self.to_mesh(), tolerance)
}
