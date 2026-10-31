// SPDX-License-Identifier: Apache-2.0

///|
test "checked geometry APIs are callable by consumers" {
  let mesh = @stlkit.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n").unwrap()
  assert_true(@stlkit.validate_checked(mesh, 0.0) is Ok(_))
  assert_true(
    @stlkit.repair_checked(mesh, {
      ..@stlkit.RepairOptions::default(),
      fill_holes: false,
    })
    is Ok(_),
  )
  assert_true(
    @stlkit.render_svg_checked(mesh, @stlkit.PreviewOptions::default()) is Ok(_),
  )
  assert_eq(@stlkit.check_thickness_area_weighted(mesh, 4, seed=1).samples, 4)
}
