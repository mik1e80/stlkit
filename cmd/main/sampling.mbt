// SPDX-License-Identifier: Apache-2.0

///|
// A work estimate, not a wall-time or process-memory guarantee.
fn sampling_budget_error(faces : Int32, samples : Int32) -> String? {
  let tests = faces.to_int64() * samples.to_int64()
  if tests > 20000000L {
    let recommended = (20000000L / faces.to_int64()).to_int().max(1)
    Some(
      "resource_limit: thickness ray budget exceeds 20000000 triangle tests; use --samples \{recommended} or fewer (faces=\{faces}, samples=\{samples}); --bench / --stream-only skip thickness",
    )
  } else {
    None
  }
}
