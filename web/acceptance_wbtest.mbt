// SPDX-License-Identifier: Apache-2.0

///|
fn acceptance_cube(offset : Double) -> String {
  let vertices = [
    (0.0, 0.0, 0.0),
    (1.0, 0.0, 0.0),
    (1.0, 1.0, 0.0),
    (0.0, 1.0, 0.0),
    (0.0, 0.0, 1.0),
    (1.0, 0.0, 1.0),
    (1.0, 1.0, 1.0),
    (0.0, 1.0, 1.0),
  ]
  let lines : Array[String] = []
  for (x, y, z) in vertices {
    lines.push("v \{x + offset} \{y + offset} \{z + offset}\n")
  }
  lines.push(
    "f 1 4 3 2\nf 5 6 7 8\nf 1 2 6 5\nf 4 8 7 3\nf 1 5 8 4\nf 2 3 7 6\n",
  )
  @base64.encode(
    @stlkit.write_mesh(@stlkit.parse_obj(lines.join("")).unwrap(), "cube.obj").unwrap(),
  )
}

///|
test "web reports translated cube inertia and the actual sampling budget" {
  let report = analyze_with_threshold(acceptance_cube(100000.0), 0.0)
  assert_true(report.contains("需复核|false"))
  assert_true(report.contains("主惯量|0.167 / 0.167 / 0.167"))
  assert_true(report.contains("采样预算|1000"))
}

///|
test "web rejects precision collapse consistently across repair outputs" {
  let source = acceptance_cube(100000000.0)
  assert_eq(fixed_stl(source), "")
  assert_eq(fixed_preview(source), "")
  assert_eq(fix_report(source), "")
  assert_true(fix_error(source).contains("Float32"))
}

///|
test "web reduces large model sampling work without calling it a time guarantee" {
  let mesh = @stlkit.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap()
  assert_eq(web_samples(mesh), 1000)
  let large = @stlkit.Mesh::new(Array::make(100000, mesh.triangles[0]))
  assert_eq(web_samples(large), 200)
}
