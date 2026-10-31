// SPDX-License-Identifier: Apache-2.0

///|
fn valid_weld_tolerance(value : Double) -> Bool {
  !not_finite(value) && value >= 0.0
}

///|
fn mesh_option_error(mesh : Mesh, tolerance : Double) -> String? {
  if !valid_weld_tolerance(tolerance) {
    return Some(
      "tolerance must be finite and nonnegative; zero selects exact coordinates",
    )
  }
  for triangle in mesh.triangles {
    if !finite_vertex(triangle.a) ||
      !finite_vertex(triangle.b) ||
      !finite_vertex(triangle.c) {
      return Some("mesh coordinates must be finite")
    }
  }
  None
}

///|
/// Validate finite coordinates using a finite nonnegative weld tolerance.
/// Zero selects exact coordinate equality. Invalid inputs return an error;
/// this does not certify absence of self-intersections or printability.
pub fn validate_checked(
  mesh : Mesh,
  tolerance : Double,
) -> Result[ValidationReport, String] {
  match mesh_option_error(mesh, tolerance) {
    Some(error) => Err(error)
    None => Ok(validate(mesh, tolerance))
  }
}
