// CLI 与网页共用的打印前检查结论。检查通过不代表制造过程保证。

///|
pub(all) struct PrintabilityReport {
  validation : ValidationReport
  winding : WindingReport
  thickness : ThicknessReport?
  /// 用户指定的参考壁厚，毫米；0 表示不设薄壁阈值。
  min_thickness : Double
}

///|
pub fn check_printability(
  mesh : Mesh,
  min_thickness : Double,
  samples? : Int = DEFAULT_THICKNESS_SAMPLES,
) -> PrintabilityReport {
  let validation = validate_default(mesh)
  let winding = check_winding_default(mesh)
  let thickness = if mesh.is_empty() ||
    !validation.is_watertight() ||
    validation.degenerate_count > 0 ||
    winding.flipped_faces > 0 ||
    !winding.orientation_reliable() {
    None
  } else {
    Some(check_thickness(mesh, samples))
  }
  { validation, winding, thickness, min_thickness, }
}

///|
/// 确定为负体积的闭合分量数；负号也可能对应合法内腔，需要复核。
/// 从分量明细计算，避免与 winding.components 保存重复且可能不一致的计数。
pub fn PrintabilityReport::inward_component_count(
  self : PrintabilityReport,
) -> Int {
  self.winding.negative_components()
}

///|
pub fn PrintabilityReport::inward(self : PrintabilityReport) -> Bool {
  self.inward_component_count() > 0
}

///|
pub fn PrintabilityReport::thin_wall(self : PrintabilityReport) -> Bool {
  match self.thickness {
    Some(r) =>
      r.hits > 0 &&
      self.min_thickness > 0.0 &&
      r.min_thickness < self.min_thickness
    None => false
  }
}

///|
pub fn PrintabilityReport::thickness_unavailable(
  self : PrintabilityReport,
) -> Bool {
  match self.thickness {
    Some(r) => r.hits == 0
    None => true
  }
}

///|
pub fn PrintabilityReport::needs_review(self : PrintabilityReport) -> Bool {
  self.min_thickness.is_nan() ||
  self.min_thickness.is_inf() ||
  self.min_thickness < 0.0 ||
  self.validation.triangle_count == 0 ||
  !self.validation.is_watertight() ||
  self.validation.degenerate_count > 0 ||
  self.validation.wrong_normal_count > 0 ||
  self.winding.flipped_faces > 0 ||
  self.inward() ||
  !self.winding.orientation_reliable() ||
  self.thin_wall() ||
  self.thickness_unavailable()
}

///|
pub fn PrintabilityReport::verdict(self : PrintabilityReport) -> String {
  if self.needs_review() {
    "本次网格检查发现需要复核的问题；不构成可打印结论。"
  } else {
    "本次网格检查未发现已覆盖的问题；不构成可打印结论，仍需确认单位、材料、设备和切片设置。"
  }
}

///|
pub fn review_scope() -> String {
  "工艺未评估：喷嘴、支撑、材料、摆放方向和切片参数；射线样本不保证全局最小壁厚。"
}
