// SPDX-License-Identifier: Apache-2.0

///|
// Private counters make parse/repair/export/review work observable to regression
// tests. Only per-request deltas enter the technical JSON envelope; the page
// does not render them. No meshes or input bytes are cached here.
priv struct WebWork {
  mut parses : Int32
  mut repairs : Int32
  mut exports : Int32
  mut reviews : Int32
}

///|
let web_work : WebWork = { parses: 0, repairs: 0, exports: 0, reviews: 0, }

///|
fn work_snapshot() -> (Int32, Int32, Int32, Int32) {
  (web_work.parses, web_work.repairs, web_work.exports, web_work.reviews)
}

///|
fn work_delta(before : (Int32, Int32, Int32, Int32)) -> Json {
  Json::object({
    "parses": Json(web_work.parses - before.0),
    "repairs": Json(web_work.repairs - before.1),
    "exports": Json(web_work.exports - before.2),
    "reviews": Json(web_work.reviews - before.3),
  })
}

///|
fn web_parse(data : Bytes) -> Result[@stlkit.Mesh, String] {
  web_work.parses += 1
  @stlkit.parse_mesh(data, limits=web_limits())
}

///|
fn web_repair(mesh : @stlkit.Mesh) -> Result[@stlkit.RepairResult, String] {
  web_work.repairs += 1
  @stlkit.repair_checked(mesh, @stlkit.RepairOptions::default())
}

///|
fn web_export(mesh : @stlkit.Mesh) -> Result[Bytes, String] {
  web_work.exports += 1
  @stlkit.write_stl_binary_checked(mesh)
}

///|
fn web_review(
  mesh : @stlkit.Mesh,
  threshold : Double,
) -> @stlkit.PrintabilityReport {
  web_work.reviews += 1
  @stlkit.check_printability(mesh, threshold, samples=web_samples(mesh))
}

///|
fn bundle_error(error : String) -> String {
  Json::object({
    "schema_version": Json(1),
    "ok": Json(false),
    "error": Json(error),
  }).stringify()
}

///|
fn bundle_preview(mesh : @stlkit.Mesh) -> (String, String) {
  match @stlkit.render_svg_checked(mesh, preview_options()) {
    Ok(svg) => (svg, "")
    Err(error) => ("", error)
  }
}

///|
/// JSON envelope containing the report and preview from a single parse.
/// A preview refusal keeps the analysis report and supplies preview_error.
pub fn analyze_bundle(file_base64 : String, threshold : Double) -> String {
  let before = work_snapshot()
  if threshold.is_nan() || threshold.is_inf() || threshold < 0.0 {
    return bundle_error("参考壁厚必须为非负有限数")
  }
  let bytes = match decode(file_base64) {
    Ok(bytes) => bytes
    Err(error) => return bundle_error(error)
  }
  let mesh = match web_parse(bytes) {
    Ok(mesh) => mesh
    Err(error) => return bundle_error(error)
  }
  let review = web_review(mesh, threshold)
  let report = analyze_loaded(bytes, mesh, review, threshold).join("\n")
  let (svg, preview_error) = bundle_preview(mesh)
  Json::object({
    "schema_version": Json(1),
    "ok": Json(true),
    "report": Json(report),
    "svg": Json(svg),
    "preview_error": Json(preview_error),
    "work": work_delta(before),
  }).stringify()
}

///|
/// One source parse, repair and checked STL export, followed by one required
/// export reparse. The report, preview and download share that actual output.
pub fn fix_bundle(file_base64 : String, threshold : Double) -> String {
  let before = work_snapshot()
  if threshold.is_nan() || threshold.is_inf() || threshold < 0.0 {
    return bundle_error("参考壁厚必须为非负有限数")
  }
  let (result, bytes) = match repair_once(file_base64) {
    Ok(value) => value
    Err(error) => return bundle_error(error)
  }
  let review = web_review(result.mesh, threshold)
  let report = analyze_loaded(bytes, result.mesh, review, threshold).join("\n")
  let repair_report = repair_report_loaded(result, review)
  let (svg, preview_error) = bundle_preview(result.mesh)
  Json::object({
    "schema_version": Json(1),
    "ok": Json(true),
    "report": Json(report),
    "repair_report": Json(repair_report),
    "stl_base64": Json(@base64.encode(bytes)),
    "svg": Json(svg),
    "preview_error": Json(preview_error),
    "work": work_delta(before),
  }).stringify()
}
