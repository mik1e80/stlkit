// SPDX-License-Identifier: Apache-2.0
// Self-authored analytic grid: 250*200 cells, 100k triangles, area 50000.

///|
fn main raise {
  let args = @env.args()
  let mode = if args.length() > 1 { args[1] } else { "full" }
  guard mode == "full" || mode == "convert" else {
    fail("mode full or convert")
  }
  let triangles : Array[@stlkit.Triangle] = []
  for y in 0..<200 {
    for x in 0..<250 {
      let a = @stlkit.Vec3::new(x.to_double(), y.to_double(), 0)
      let b = @stlkit.Vec3::new((x + 1).to_double(), y.to_double(), 0)
      let c = @stlkit.Vec3::new((x + 1).to_double(), (y + 1).to_double(), 0)
      let d = @stlkit.Vec3::new(x.to_double(), (y + 1).to_double(), 0)
      triangles.push(@stlkit.Triangle::from_vertices(a, b, c))
      triangles.push(@stlkit.Triangle::from_vertices(a, c, d))
    }
  }
  let mesh = @stlkit.Mesh::new(triangles)
  let (faces, positions, area) = if mode == "convert" {
    // The benchmark intentionally includes Mesh creation + conversion, not an
    // isolated steady-state indexed heap. Both may be live during comparison.
    let indexed = mesh.to_indexed().unwrap()
    assert_eq(indexed.triangle_count(), mesh.triangle_count())
    assert_eq(indexed.surface_area(), mesh.surface_area())
    assert_eq(
      indexed.bounding_box().unwrap().max.x,
      mesh.bounding_box().unwrap().max.x,
    )
    assert_eq(indexed.vertex_count(), 50451)
    (indexed.triangle_count(), indexed.vertex_count(), indexed.surface_area())
  } else {
    (mesh.triangle_count(), mesh.triangle_count() * 3, mesh.surface_area())
  }
  assert_eq(faces, 100000)
  assert_eq(area, 50000.0)
  println(
    Json::object({
      "mode": Json(mode),
      "triangles": Json(faces),
      "position_records": Json(positions),
      "surface_area": Json(area),
      "logical_scalar_bytes": Json(
        if mode == "full" {
          faces * 96
        } else {
          positions * 24 + faces * 36
        },
      ),
    }).stringify(),
  )
}
