// 3MF 解析。
//
// 3MF（3D Manufacturing Format）是现代切片软件实际使用的格式——PrusaSlicer、
// Bambu Studio、Cura 导出的都是它，定位上就是 STL 的正式替代品。
//
// 它和 STL 有两处根本不同：
//
//   1. **它是个 ZIP 包**（OPC 容器），模型数据装在里面一个 XML 部件里，
//      通常叫 3D/3dmodel.model。
//   2. **顶点是共享的**。三角形存的是顶点表下标，和 OBJ 一样，
//      而不是像 STL 那样每个三角形把自己的三个顶点重写一遍。
//
// 第二点对「能不能打印」这个问题特别重要：**拓扑关系是现成的**。
// STL 里「哪些三角形共用同一个顶点」得靠容差焊接去猜（差 1e-9 的算不算同一个点？），
// 输入文件可明确共享身份，但本库统一展开到 Triangle 列表；
// 下游仍按坐标容差重建拓扑，不保留原始顶点身份。
//
// 代价是格式复杂得多：要解 ZIP、要解 XML，对象还能互相引用拼成装配体。

///|
/// 一个 3MF 对象。
///
/// 两种形态二选一：要么自带网格（顶点表 + 三角形索引），要么是一组组件
/// （引用别的对象，各带一个变换矩阵）。用两个数组共存来表示，
/// 比套一层枚举少绕几下——解析时本来就是一个一个往里塞。
priv struct MfObject {
  /// 共享顶点表
  vertices : Array[Vec3]
  /// 三角形，存的是顶点表下标
  triangles : Array[(Int, Int, Int)]
  /// 组件：引用的对象 id + 变换矩阵
  components : Array[(Int, FixedArray[Double]?)]
}

///|
/// 3MF 是个 ZIP 包。只看魔数，真正的校验在 `parse_3mf` 里做——
/// 「打开才知道」的检查不该塞进一个只看开头的判断函数。
pub fn is_3mf(data : Bytes) -> Bool {
  data.length() >= 4 &&
  data[0] == b'P' &&
  data[1] == b'K' &&
  // 空 ZIP 的开头是 PK\x05\x06，这里要的是有内容的那种
  data[2] == b'\x03' &&
  data[3] == b'\x04'
}

///|
/// 默认严格校验 OPC 关系和内容类型，再按 Core 几何子集读取。
/// compatibility=true 显式启用旧包定位回退；不放宽 XML/几何检查。
pub fn parse_3mf(
  data : Bytes,
  compatibility? : Bool = false,
) -> Result[Mesh, String] {
  // 解 ZIP。fzip 自带 zip bomb 防护（解压比超过 1000 倍直接拒绝）
  // 和不安全路径拒绝（绝对路径、`..` 一律不收）——解析用户传上来的文件，
  // 这两道防线是必须的，自己写很容易漏。
  let entries = @fzip.unzip_sync(data.to_fixedarray()) catch {
    @fzip.FzipError(message~, ..) =>
      return Err("这不是一个合法的 3MF：ZIP 解不开——\{message}")
  }
  let located = if compatibility {
    find_model_part(entries)
  } else {
    mf_strict_model_part(entries)
  }
  let xml = match located {
    Ok(text) => text
    Err(msg) => return Err(msg)
  }
  parse_model_xml(xml)
}

///|
/// 从压缩包里找出模型部件。
///
/// 正规做法是读 `_rels/.rels`，里面记着哪个部件是模型。绝大多数文件确实就叫
/// `3D/3dmodel.model`。两条路都走：先按规范查关系表，查不到再退化成
/// 「找唯一一个 .model 文件」——有些导出器写的关系表不规范，但文件名是对的。
fn find_model_part(
  entries : Array[(String, FixedArray[Byte])],
) -> Result[String, String] {
  let target = match find_entry(entries, "_rels/.rels") {
    Some(raw) => rels_model_target(@utf8.decode_lossy(Bytes::from_array(raw)))
    None => None
  }
  match target {
    Some(path) =>
      match find_entry(entries, path) {
        Some(raw) => mf_xml_text(raw)
        None =>
          Err(
            "3MF 的关系表指向「\{path}」，但包里没有这个部件",
          )
      }
    None => {
      // 退路：找 .model 文件
      let models : Array[String] = []
      for entry in entries {
        let (name, _) = entry
        if name.to_lower().has_suffix(".model") {
          models.push(name)
        }
      }
      if models.length() == 0 {
        Err(
          "这个 ZIP 里没有 3D 模型部件（找不到 .model 文件），不是 3MF 文件",
        )
      } else if models.length() > 1 {
        Err(
          "这个 3MF 里有 \{models.length()} 个 .model 部件，关系表也没说是哪个，认不出来",
        )
      } else {
        match find_entry(entries, models[0]) {
          Some(raw) => mf_xml_text(raw)
          None => Err("读不到模型部件「\{models[0]}」")
        }
      }
    }
  }
}

///|
/// 从 `_rels/.rels` 里找出模型部件路径。
///
/// 关系表长这样：
///
/// ```xml
/// <Relationship Target="/3D/3dmodel.model" Id="rel0"
///   Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
/// ```
///
/// 认的是 Type 后缀而不是 Id——Id 是随便起的。
fn rels_model_target(xml : String) -> String? {
  let reader = @xml.Reader::from_string(xml)
  let mut found : String? = None
  while found is None {
    let event = reader.read_event() catch {
      // 关系表坏了不该让整个解析失败，退回去按文件名找就行
      _ => break
    }
    let element = match event.kind {
      @xml.EventKind::Start(e) | @xml.EventKind::Empty(e) => e
      // **必须在这里停下来。**
      //
      // 读到文件末尾之后，`read_event` 会一直返回 `Eof` 而不会抛错。
      // 少了这个分支，一个「关系表是合法 XML、但里面没有 3dmodel 关系」的包
      // 就会在这里无限空转——CPU 跑满，命令行和网页都卡死，而且永远等不到报错。
      // 现实中把 .docx 改名成 .3mf 就是这个样子。
      @xml.EventKind::Eof => break
      _ => continue
    }
    if local_name(element.name) != "Relationship" {
      continue
    }
    let kind = match element.get("Type") {
      Some(t) => t
      None => continue
    }
    if kind != "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" {
      continue
    }
    // 关系对上了但没有 Target——文件不规范，不算数，继续往后找
    match element.get("Target") {
      Some(t) => found = Some(normalize_part_path(t))
      None => ()
    }
  }
  found
}

///|
/// OPC 里的路径可能写成 `/3D/3dmodel.model` 这种带前导斜杠的，
/// 而压缩包里存的是 `3D/3dmodel.model`。统一去掉前导斜杠。
fn normalize_part_path(path : String) -> String {
  if path.has_prefix("/") {
    path[1:].to_owned()
  } else {
    path
  }
}

///|
/// 按名字找一个部件。
///
/// 大小写不敏感——OPC 的部件名在规范里不区分大小写，
/// 实际文件里 `3D/3dmodel.model` 和 `3d/3DModel.model` 都出现过。
fn find_entry(
  entries : Array[(String, FixedArray[Byte])],
  name : String,
) -> FixedArray[Byte]? {
  let want = normalize_entry_name(name)
  for entry in entries {
    let (entry_name, bytes) = entry
    if normalize_entry_name(entry_name) == want {
      return Some(bytes)
    }
  }
  None
}

///|
/// 把压缩包里的条目名规范化，好用来比对。
///
/// 两件事：
///
/// 1. **转小写**——OPC 的部件名不区分大小写。
/// 2. **反斜杠换成正斜杠**——ZIP 规范要求条目名用正斜杠，但 Windows 上一些
///    打包工具（比如 PowerShell 的 `Compress-Archive`）会写成反斜杠。
///    不归一化的话，一个结构完好的包会因为 `3D\3dmodel.model` 匹配不上
///    `3D/3dmodel.model` 而被判成「没有模型部件」——报错完全指错了方向。
fn normalize_entry_name(name : String) -> String {
  let lower = name.to_lower()
  if lower.contains("\\") {
    lower.replace_all(old="\\", new="/")
  } else {
    lower
  }
}

///|
/// 去掉命名空间前缀，只留本地名。
///
/// 3MF 的 XML 用默认命名空间，正常情况下标签就是 `<vertex>`。
/// 但规范允许写前缀形式 `<m:vertex xmlns:m="...">`，
/// 那就得把 `m:` 切掉才能按名字匹配。
fn local_name(name : String) -> String {
  let mut last : StringView = name[:]
  for part in name.split(":") {
    last = part
  }
  last.to_owned()
}

///|
/// 取命名空间前缀。没有冒号就是空串（默认命名空间）。
fn prefix_of(name : String) -> String {
  match name.find(":") {
    Some(i) => name[:i].to_owned()
    None => ""
  }
}

///|
const MF_CORE_NS : String = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"

///|
priv struct MfXmlScope {
  name : String
  tag : String
  bindings : Map[String, String]
}

///|
fn mf_bindings(
  element : @xml.XmlElement,
  inherited : Map[String, String],
) -> Map[String, String] {
  if !element.attributes.any(a => {
      a.name == "xmlns" || a.name.has_prefix("xmlns:")
    }) {
    return inherited
  }
  let bindings : Map[String, String] = Map([])
  for key, value in inherited {
    bindings.set(key, value)
  }
  for attr in element.attributes {
    if attr.name == "xmlns" {
      bindings.set("", attr.value)
    } else if attr.name.has_prefix("xmlns:") {
      bindings.set(attr.name[6:].to_owned(), attr.value)
    }
  }
  bindings
}

///|
fn mf_parent_of(tag : String) -> String? {
  match tag {
    "resources" | "build" => Some("model")
    "object" => Some("resources")
    "mesh" | "components" => Some("object")
    "vertices" | "triangles" => Some("mesh")
    "vertex" => Some("vertices")
    "triangle" => Some("triangles")
    "component" => Some("components")
    "item" => Some("build")
    _ => None
  }
}

///|
/// 解析 3D/3dmodel.model。
///
/// 关心的标签只有几个：`model`（拿单位）、`object`（攒顶点和三角形）、
/// `component`（装配体引用）、`item`（build 里列出要打印的对象）。
/// 其余（metadata、basematerials、切片信息……）全部跳过——
/// 这些语义不进入 Mesh；忽略不代表已验证制造语义或可打印。
fn parse_model_xml(xml : String) -> Result[Mesh, String] {
  let reader = @xml.Reader::from_string(xml)
  let objects : Map[Int, MfObject] = Map([])
  // build 里列出的 (对象 id, 变换)
  let build : Array[(Int, FixedArray[Double]?)] = []

  // 单位换算到毫米。STL 没有单位概念，3MF 有，不换算的话
  // 一个以英寸建模的模型体积会差 25.4³ ≈ 16387 倍
  let mut unit_scale = 1.0

  // 按 XML 作用域解析完整 URI；不把前缀名称当作命名空间身份。
  let scopes : Array[MfXmlScope] = []
  let empty_bindings : Map[String, String] = Map([])
  let mut model_seen = false
  let mut resources_seen = false
  let mut build_seen = false
  let mut geometry_seen = false

  // 当前正在攒的对象
  let mut cur_id : Int? = None
  let mut cur_vertices : Array[Vec3] = []
  let mut cur_triangles : Array[(Int, Int, Int)] = []
  let mut cur_components : Array[(Int, FixedArray[Double]?)] = []

  while !reader.is_eof() {
    let event = reader.read_event() catch {
      err =>
        return Err(
          "3MF 的模型 XML 解析失败（第 \{reader.line()} 行）：\{err}",
        )
    }
    let element = match event.kind {
      @xml.EventKind::Start(e) | @xml.EventKind::Empty(e) => e
      @xml.EventKind::End(name) => {
        if scopes.length() == 0 {
          return Err("3MF XML 出现无对应开始标签的结束标签")
        }
        let scope = scopes.pop().unwrap()
        if scope.name != name {
          return Err("3MF XML 标签不匹配")
        }
        if scope.tag == "object" {
          flush_object(
            objects, cur_id, cur_vertices, cur_triangles, cur_components,
          )
          cur_id = None
          cur_vertices = []
          cur_triangles = []
          cur_components = []
        }
        continue
      }
      @xml.EventKind::Decl(encoding~, ..) => {
        match encoding {
          Some(e) =>
            if e.to_lower() != "utf-8" {
              return Err("3MF XML 声明必须使用 UTF-8")
            }
          None => ()
        }
        continue
      }
      @xml.EventKind::DocType(_) =>
        return Err("当前 3MF 几何读取子集不接受 DTD")
      @xml.EventKind::Text(text) | @xml.EventKind::CData(text) => {
        if scopes.length() == 0 && obj_words(text).length() > 0 {
          return Err("3MF XML 根元素外存在文本")
        }
        continue
      }
      _ => continue
    }
    let parent = if scopes.length() > 0 {
      scopes[scopes.length() - 1].tag
    } else {
      ""
    }
    let inherited = if scopes.length() > 0 {
      scopes[scopes.length() - 1].bindings
    } else {
      empty_bindings
    }
    let bindings = mf_bindings(element, inherited)
    let prefix = prefix_of(element.name)
    let uri = match bindings.get(prefix) {
      Some(value) => value
      None => ""
    }
    if prefix != "" && uri == "" {
      return Err("3MF XML 使用了未声明的命名空间前缀")
    }
    let tag_name = local_name(element.name)
    let mut tag = if uri == MF_CORE_NS { tag_name } else { "" }
    if scopes.length() == 0 {
      if model_seen || tag != "model" {
        return Err(
          "3MF XML 必须恰有一个使用 Core 2015/02 命名空间的 model 根元素",
        )
      }
      model_seen = true
    } else if parent == "" {
      // Optional foreign/unknown subtrees cannot inject Core lookalikes.
      tag = ""
    } else if tag == "model" {
      return Err("3MF model 不能嵌套")
    } else {
      match mf_parent_of(tag) {
        Some(required_parent) =>
          if parent != required_parent {
            return Err("3MF <\{tag}> 必须位于 <\{required_parent}> 中")
          }
        None => tag = ""
      }
    }
    if tag == "resources" {
      if resources_seen || build_seen {
        return Err("3MF resources 必须唯一且位于 build 之前")
      }
      resources_seen = true
    }
    if tag == "build" {
      if build_seen || !resources_seen {
        return Err("3MF build 必须唯一且位于 resources 之后")
      }
      build_seen = true
    }
    if tag == "mesh" || tag == "components" {
      if geometry_seen {
        return Err("3MF object 只能包含一个 mesh 或一个 components")
      }
      geometry_seen = true
    }
    if event.kind is @xml.EventKind::Start(_) {
      scopes.push({ name: element.name, tag, bindings, })
    }
    if tag == "" {
      continue
    }

    if tag == "model" {
      // 单位：micron / millimeter / centimeter / inch / foot / meter
      match element.get("requiredextensions") {
        Some(required) =>
          if obj_words(required).length() > 0 {
            return Err(
              "3MF 声明了本工具未实现的必需扩展 requiredextensions=\"\{required}\"；不能仅按核心三角网格解释",
            )
          }
        None => ()
      }
      match element.get("unit") {
        Some(u) =>
          unit_scale = match unit_scale_of(u) {
            Ok(v) => v
            Err(msg) => return Err(msg)
          }
        None => ()
      }
    } else if tag == "object" {
      // 自闭合的未使用空对象在下一对象处收尾；不接受坏 XML。
      flush_object(objects, cur_id, cur_vertices, cur_triangles, cur_components)
      let id = match attribute_int(element, "id", "object") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      if objects.contains(id) {
        return Err("3MF object id 重复：\{id}")
      }
      geometry_seen = false
      cur_id = Some(id)
      cur_vertices = []
      cur_triangles = []
      cur_components = []
    } else if tag == "vertex" {
      let v = match attribute_vec3(element) {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      cur_vertices.push(v)
    } else if tag == "triangle" {
      // 三角形存的是顶点表下标，不是坐标
      let a = match attribute_int(element, "v1", "triangle") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      let b = match attribute_int(element, "v2", "triangle") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      let c = match attribute_int(element, "v3", "triangle") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      cur_triangles.push((a, b, c))
    } else if tag == "component" {
      let id = match attribute_int(element, "objectid", "component") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      let tf = match attribute_transform(element) {
        Ok(t) => t
        Err(msg) => return Err(msg)
      }
      cur_components.push((id, tf))
    } else if tag == "item" {
      let id = match attribute_int(element, "objectid", "item") {
        Ok(v) => v
        Err(msg) => return Err(msg)
      }
      let tf = match attribute_transform(element) {
        Ok(t) => t
        Err(msg) => return Err(msg)
      }
      build.push((id, tf))
    }
  }
  if !model_seen || scopes.length() != 0 {
    return Err("3MF XML 缺少完整 model 根元素")
  }
  if !resources_seen || !build_seen {
    return Err("3MF 缺少 resources 或 build")
  }
  // 最后一个对象
  flush_object(objects, cur_id, cur_vertices, cur_triangles, cur_components)

  if build.length() == 0 {
    return Err(
      "这个 3MF 的 build 里没有列任何对象，没有东西可以打印",
    )
  }

  // 按 build 列出的对象拼出最终网格
  let triangles : Array[Triangle] = []
  for (id, tf) in build {
    // item 不带 transform 就是原样放进去
    let transform = match tf {
      Some(t) => t
      None => identity_transform()
    }
    let body = match build_object(objects, id, transform, 0) {
      Ok(v) => v
      Err(msg) => return Err(msg)
    }
    for tri in body {
      triangles.push(tri)
    }
  }

  if triangles.length() == 0 {
    // 措辞要说清楚两种可能，别让人以为文件坏了。
    // 3MF 的 Beam Lattice 扩展明确规定：挂了 beamlattice 的 mesh
    // **可以一个三角形都没有**（规范原话：MAY consist of no triangles），
    // 几何全写在扩展元素里。这种文件是合法的，只是本工具处理不了
    return Err(
      "这个 3MF 的 build 引用的对象里没有三角形——可能是空对象，" +
      "也可能是几何写在扩展元素里的对象（比如 beam lattice，本工具只处理三角网格）",
    )
  }
  let scaled = scale_mesh(triangles, unit_scale)
  for tri in scaled {
    if !finite_vertex(tri.a) || !finite_vertex(tri.b) || !finite_vertex(tri.c) {
      return Err("3MF 单位换算后坐标超出有限范围")
    }
  }
  Ok(Mesh::new(scaled))
}

///|
/// 把一个对象的当前状态收进对象表。
///
/// 抽成函数是因为「收尾」要在两个地方发生：遇到结束标签时，
/// 以及开始下一个对象之前。后一处是给自闭合或者结构不完整的文件兜底的。
fn flush_object(
  objects : Map[Int, MfObject],
  id : Int?,
  vertices : Array[Vec3],
  triangles : Array[(Int, Int, Int)],
  components : Array[(Int, FixedArray[Double]?)],
) -> Unit {
  match id {
    Some(i) => objects.set(i, MfObject::{ vertices, triangles, components, })
    None => ()
  }
}

///|
/// 把所有顶点乘一个系数。
///
/// 单位换算单独走一遍，而不是在解析顶点时乘——因为变换矩阵里的平移量
/// 也是同一个单位的长度，两处都得乘。统一到最后做，不会漏。
fn scale_mesh(triangles : Array[Triangle], scale : Double) -> Array[Triangle] {
  if scale == 1.0 {
    return triangles
  }
  let out : Array[Triangle] = []
  for t in triangles {
    out.push({
      normal: t.normal,
      a: t.a.scale(scale),
      b: t.b.scale(scale),
      c: t.c.scale(scale),
    })
  }
  out
}

///|
/// 把一个对象（可能是装配体）展开成三角形，顺便套上变换。
///
/// `depth` 是递归深度。3MF 允许对象互相引用，**引用成环是坏文件，
/// 但真会出现**，不设上限就会栈溢出。
fn build_object(
  objects : Map[Int, MfObject],
  id : Int,
  transform : FixedArray[Double],
  depth : Int,
) -> Result[Array[Triangle], String] {
  if depth > 32 {
    return Err(
      "3MF 的对象引用套得太深（超过 32 层），可能是循环引用",
    )
  }
  let obj = match objects.get(id) {
    Some(o) => o
    None => return Err("3MF 里引用了不存在的对象 id=\{id}")
  }
  let out : Array[Triangle] = []
  if obj.triangles.length() > 0 {
    // 共享顶点表：三角形存的是下标，到这里才真正取出坐标
    let n = obj.vertices.length()
    for (i, j, k) in obj.triangles {
      if i < 0 || j < 0 || k < 0 || i >= n || j >= n || k >= n {
        return Err(
          "3MF 对象 id=\{id} 里有三角形的顶点下标越界（顶点表只有 \{n} 个，" +
          "引用到了 \{i}/\{j}/\{k}）",
        )
      }
      let a = apply_transform(obj.vertices[i], transform)
      let b = apply_transform(obj.vertices[j], transform)
      let c = apply_transform(obj.vertices[k], transform)
      if !finite_vertex(a) || !finite_vertex(b) || !finite_vertex(c) {
        return Err("3MF 对象 id=\{id} 变换后坐标超出有限范围")
      }
      out.push(Triangle::from_vertices(a, b, c))
    }
  }
  for (child_id, child_tf) in obj.components {
    // 组件自己的变换要先做，再套外层的——顺序反了位置就错了
    let combined = match child_tf {
      Some(t) => compose_transform(t, transform)
      None => transform
    }
    for value in combined {
      if not_finite(value) {
        return Err("3MF 对象 id=\{child_id} 的嵌套变换溢出")
      }
    }
    let sub = match build_object(objects, child_id, combined, depth + 1) {
      Ok(v) => v
      Err(msg) => return Err(msg)
    }
    for tri in sub {
      out.push(tri)
    }
  }
  Ok(out)
}

///|
/// 3MF 里的长度单位换算成毫米。
///
/// STL 没有单位概念，一路按毫米处理；3MF 有，不换算的话
/// 一个以英寸建模的模型体积会差 25.4³ ≈ 16387 倍，报告里的数字全是错的。
fn unit_scale_of(unit : String) -> Result[Double, String] {
  match unit {
    "micron" => Ok(0.001)
    "millimeter" => Ok(1.0)
    "centimeter" => Ok(10.0)
    "inch" => Ok(25.4)
    "foot" => Ok(304.8)
    "meter" => Ok(1000.0)
    _ =>
      Err(
        "3MF 里写了一个不认识的单位「\{unit}」，" +
        "规范里只有 micron / millimeter / centimeter / inch / foot / meter",
      )
  }
}

///|
/// 单位矩阵。build 里的 item 和 component 都可以不带 transform，
/// 不带就是原样放。
fn identity_transform() -> FixedArray[Double] {
  [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
}

///|
/// 把一个点按 3MF 的变换矩阵变换。
///
/// 3MF 写的是 12 个数，代表一个 4×3 矩阵，按行排：
///
/// ```text
/// m00 m01 m02
/// m10 m11 m12
/// m20 m21 m22
/// m30 m31 m32      ← 平移
/// ```
///
/// 用的是**行向量**约定：点当作 1×4 的 `[x y z 1]` 去右乘矩阵：
///
/// ```text
/// x' = x·m00 + y·m10 + z·m20 + m30
/// y' = x·m01 + y·m11 + z·m21 + m31
/// z' = x·m02 + y·m12 + z·m22 + m32
/// ```
///
/// 注意平移在 m30/m31/m32，也就是数组的第 9/10/11 个——**不是前三个**。
/// 按列优先、或者把平移放前面，都会得到完全错误的位置。
fn apply_transform(v : Vec3, m : FixedArray[Double]) -> Vec3 {
  Vec3::{
    x: v.x * m[0] + v.y * m[3] + v.z * m[6] + m[9],
    y: v.x * m[1] + v.y * m[4] + v.z * m[7] + m[10],
    z: v.x * m[2] + v.y * m[5] + v.z * m[8] + m[11],
  }
}

///|
/// 先把点按 `first` 变换、再按 `second` 变换，合成一个矩阵。
///
/// 行向量约定下「先 A 后 B」就是 A×B。4×3 的矩阵要隐式补上第 4 列
/// （前三行填 0、最后一行填 1）才能相乘。
fn compose_transform(
  first : FixedArray[Double],
  second : FixedArray[Double],
) -> FixedArray[Double] {
  let out : Array[Double] = []
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      let mut sum = 0.0
      for k = 0; k < 3; k = k + 1 {
        sum = sum + first[i * 3 + k] * second[k * 3 + j]
      }
      // 第 4 行（i=3）还要加上 second 自己的平移
      if i == 3 {
        sum = sum + second[9 + j]
      }
      out.push(sum)
    }
  }
  [
    out[0],
    out[1],
    out[2],
    out[3],
    out[4],
    out[5],
    out[6],
    out[7],
    out[8],
    out[9],
    out[10],
    out[11],
  ]
}

///|
/// 读一个整数属性。
///
/// `parse_double` 收的比整数字面量宽得多：`1.5`、`1e3`、`2_0`、`nan`、`inf`
/// 它都认。所以这里必须自己把关——不把关的话 `<triangle v1="nan" .../>` 会
/// 静默变成下标 0，用户拿到一个由错顶点拼出来的网格，而且毫无提示。
///
/// 注意 `inf` 要单独判：`inf.round()` 还是 `inf`，光比 `value != value.round()`
/// 拦不住它。
fn attribute_int(
  element : @xml.XmlElement,
  name : String,
  tag : String,
) -> Result[Int, String] {
  match element.get(name) {
    Some(raw) => {
      let minimum = if name == "id" || name == "objectid" { 1 } else { 0 }
      match profile_decimal_int(raw[:], minimum) {
        Ok(i) => Ok(i)
        Err(msg) =>
          Err(
            "3MF <\{tag}> 的 \{name} 不是个整数或超出允许范围：\{msg}",
          )
      }
    }
    None => Err("3MF 的 <\{tag}> 少了一个必需的属性 \{name}")
  }
}

///|
/// 读 x / y / z 三个坐标属性。
///
/// 坐标也要查有限性：`x="inf"` 或 `x="nan"` 会让包围盒和体积算出一堆垃圾，
/// 而且从报告上看不出是文件坏了——数字就是难看点而已，不如直接报错。
fn attribute_vec3(element : @xml.XmlElement) -> Result[Vec3, String] {
  let out : Array[Double] = []
  for name in ["x", "y", "z"] {
    let raw = match element.get(name) {
      Some(v) => v
      None => return Err("3MF 的 <vertex> 少了坐标属性 \{name}")
    }
    let value = @string.parse_double(raw) catch {
      _ => return Err("3MF 的 <vertex> 里 \{name}=\"\{raw}\" 不是个数字")
    }
    if value.is_nan() || value.is_inf() {
      return Err(
        "3MF 的 <vertex> 里 \{name}=\"\{raw}\" 不是个有限的数字",
      )
    }
    out.push(value)
  }
  Ok(Vec3::new(out[0], out[1], out[2]))
}

///|
/// 读可选的位置变换属性。
///
/// 12 个数，空格分隔。个数不对就报错——少一个数会让整条装配链错位，
/// 而错位后的模型看起来「有东西」但体积完全不对，是最难查的那种错。
fn attribute_transform(
  element : @xml.XmlElement,
) -> Result[FixedArray[Double]?, String] {
  let raw = match element.get("transform") {
    Some(v) => v
    None => return Ok(None)
  }
  let out : Array[Double] = []
  for token in obj_words(raw) {
    if token.length() == 0 {
      continue
    }
    let value = @string.parse_double(token) catch {
      _ => return Err("3MF 的 transform 里『\{token}』不是个数字")
    }
    if not_finite(value) {
      return Err("3MF 的 transform 里『\{token}』不是有限数字")
    }
    out.push(value)
  }
  if out.length() != 12 {
    return Err(
      "3MF 的 transform 应该有 12 个数（4 行 3 列的矩阵），实际有 \{out.length()} 个",
    )
  }
  Ok(
    Some([
      out[0],
      out[1],
      out[2],
      out[3],
      out[4],
      out[5],
      out[6],
      out[7],
      out[8],
      out[9],
      out[10],
      out[11],
    ]),
  )
}
