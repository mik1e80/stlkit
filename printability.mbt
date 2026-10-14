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
pub fn check_printability(mesh : Mesh, min_thickness : Double) -> PrintabilityReport {
  let validation = validate_default(mesh)
  let winding = check_winding_default(mesh)
  let thickness = if mesh.is_empty() || !validation.is_watertight() ||
    validation.degenerate_count > 0 || winding.flipped_faces > 0 ||
    winding.signed_volume <= 0.0 {
    None
  } else {
    Some(check_thickness_default(mesh))
  }
  { validation, winding, thickness, min_thickness }
}

///|
pub fn PrintabilityReport::inward(self : PrintabilityReport) -> Bool {
  self.validation.is_watertight() && self.winding.signed_volume < 0.0
}

///|
pub fn PrintabilityReport::thin_wall(self : PrintabilityReport) -> Bool {
  match self.thickness {
    Some(r) => r.hits > 0 && self.min_thickness > 0.0 && r.min_thickness < self.min_thickness
    None => false
  }
}

///|
pub fn PrintabilityReport::thickness_unavailable(self : PrintabilityReport) -> Bool {
  match self.thickness { Some(r) => r.hits == 0; None => true }
}

///|
pub fn PrintabilityReport::needs_review(self : PrintabilityReport) -> Bool {
  self.min_thickness.is_nan() || self.min_thickness.is_inf() || self.min_thickness < 0.0 ||
  self.validation.triangle_count == 0 || !self.validation.is_watertight() ||
  self.validation.degenerate_count > 0 || self.validation.wrong_normal_count > 0 ||
  self.winding.flipped_faces > 0 || self.inward() || self.thin_wall() ||
  self.thickness_unavailable()
}

///|
pub fn PrintabilityReport::verdict(self : PrintabilityReport) -> String {
  if self.needs_review() {
    "本次检查发现需要复核的问题；请按报告修正模型或确认加工条件。"
  } else {
    "本次网格检查未发现已覆盖的问题；仍需确认单位、材料、设备和切片设置。"
  }
}
