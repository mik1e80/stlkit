// SPDX-License-Identifier: Apache-2.0

///|
fn number_or_null(value : Double) -> Json {
  if not_finite(value) {
    Json::null()
  } else {
    @json.to_json(value)
  }
}

///|
fn vector_or_null(value : Vec3) -> Json {
  if finite_vertex(value) {
    Json([value.x, value.y, value.z])
  } else {
    Json::null()
  }
}

///|
/// Version-1 machine report for coordinates interpreted in mm. 3MF parsers
/// already convert declared units; other formats require caller confirmation.
/// Non-finite computed quantities become null and force needs_review=true.
/// This does not certify self-intersection absence or printability.
///
/// ```moonbit nocheck
/// let report = @stlkit.inspection_json(mesh, format=@stlkit.Obj, samples=32)
/// ```
pub fn inspection_json(
  mesh : Mesh,
  format~ : MeshFormat = Unknown,
  min_thickness~ : Double = 0.8,
  samples~ : Int32 = 1000,
) -> Result[Json, String] {
  if mesh.triangle_count() > 715827882 {
    return Err("inspection face count overflows expanded corner count")
  }
  if not_finite(min_thickness) ||
    min_thickness < 0.0 ||
    samples < 1 ||
    samples > 100000 {
    return Err(
      "inspection options: finite nonnegative thickness; samples 1..100000",
    )
  }
  for triangle in mesh.triangles {
    if !finite_vertex(triangle.normal) ||
      !finite_vertex(triangle.a) ||
      !finite_vertex(triangle.b) ||
      !finite_vertex(triangle.c) {
      return Err(
        "inspection input contains non-finite coordinates or declared normals",
      )
    }
  }
  let review = check_printability(mesh, min_thickness, samples~)
  let validation = review.validation
  let area = mesh.surface_area()
  let volume = mesh.volume()
  let mass_ready = review.mass_properties_available()
  let center = if mass_ready {
    vector_or_null(mesh.center_mass())
  } else {
    Json::null()
  }
  let mut numeric_failure = not_finite(area) || not_finite(volume)
  let inertia : Json = if mass_ready {
    let tensor = mesh.moment_inertia()
    if tensor.any(not_finite) {
      numeric_failure = true
      Json::null()
    } else {
      Json::array(tensor.iter().map(value => Json(value)).collect())
    }
  } else {
    Json::null()
  }
  if mass_ready && center is Null {
    numeric_failure = true
  }
  let mass_usable = mass_ready &&
    !not_finite(volume) &&
    !(center is Null) &&
    !(inertia is Null)
  let bbox = match mesh.bounding_box() {
    Some(box) =>
      Json::object({
        "min": vector_or_null(box.min),
        "max": vector_or_null(box.max),
      })
    None => Json::null()
  }
  let thickness = match review.thickness {
    Some(result) => {
      let usable = result.hits > 0 &&
        !not_finite(result.min_thickness) &&
        !not_finite(result.mean_thickness)
      if result.hits > 0 && !usable {
        numeric_failure = true
      }
      Json::object({
        "status": Json(
          if result.hits == 0 {
            "no_hits"
          } else if usable {
            "sample_estimate"
          } else {
            "non_finite"
          },
        ),
        "requested_samples": Json(samples),
        "samples": Json(result.samples),
        "hits": Json(result.hits),
        "min_mm": if usable {
          Json(result.min_thickness)
        } else {
          Json::null()
        },
        "mean_mm": if usable {
          Json(result.mean_thickness)
        } else {
          Json::null()
        },
        "global_minimum_certified": Json(false),
      })
    }
    None =>
      Json::object({
        "status": Json("not_evaluated"),
        "requested_samples": Json(samples),
        "samples": Json(0),
        "hits": Json(0),
        "min_mm": Json::null(),
        "mean_mm": Json::null(),
        "global_minimum_certified": Json(false),
      })
  }
  Ok(
    Json::object({
      "schema_version": Json(1),
      "ok": Json(true),
      "input": Json::object({
        "format": Json(format.id()),
        "coordinate_units": Json("mm"),
        "unit_interpretation": Json(
          if format is ThreeMF {
            "converted_from_3mf_unit"
          } else {
            "assumed_mm_confirm_scale"
          },
        ),
      }),
      "geometry": Json::object({
        "triangles": Json(validation.triangle_count),
        "raw_vertices": Json(validation.raw_vertex_count),
        "unique_vertices": Json(validation.unique_vertex_count),
        "surface_area_mm2": number_or_null(area),
        "volume_mm3": if mass_usable {
          number_or_null(volume)
        } else {
          Json::null()
        },
        "aabb_mm": bbox,
      }),
      "validation": Json::object({
        "boundary_edges": Json(validation.boundary_edge_count),
        "non_manifold_edges": Json(validation.non_manifold_edge_count),
        "degenerate_faces": Json(validation.degenerate_count),
        "opposed_declared_normals": Json(validation.wrong_normal_count),
        "euler_number": Json(validation.euler_number()),
        "winding_consistent": Json(review.winding.consistent),
        "flipped_faces": Json(review.winding.flipped_faces),
        "inward_components": Json(review.inward_component_count()),
        "orientation_reliable": Json(review.winding.orientation_reliable()),
      }),
      "mass_properties": Json::object({
        "status": Json(
          if !mass_ready {
            "not_evaluated"
          } else if !mass_usable {
            "non_finite"
          } else {
            "available"
          },
        ),
        "center_of_mass_mm": if mass_usable {
          center
        } else {
          Json::null()
        },
        "inertia_density_one": if mass_usable {
          inertia
        } else {
          Json::null()
        },
      }),
      "thickness": thickness,
      "review": Json::object({
        "needs_review": Json(review.needs_review() || numeric_failure),
        "numeric_failure": Json(numeric_failure),
        "printability_certified": Json(false),
        "min_thickness_mm": Json(min_thickness),
        "scope": Json(review_scope()),
      }),
    }),
  )
}
