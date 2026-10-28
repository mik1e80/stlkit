# IndexedMesh 初版：设计与边界

0.2.0 新增独立 `IndexedMesh`，现有 `Mesh` 和解析器保留。内部保存顶点表、`Face3 {a,b,c}` 和逐面声明法线；字段私有。构造函数和 getters 都复制数组，外部修改原始数组或返回数组不会破坏已验证的实例。Vec3 / Face3 自身字段不可变。

```moonbit
let indexed = mesh.to_indexed().unwrap()
let vertices = indexed.vertices()
let restored = indexed.to_mesh()
let report = indexed.validate()
```

`IndexedMesh::new(vertices, faces, normals=[])` 检查全部坐标和法线有限、每个面索引非负且在范围内、非空 normals 长度等于面数；空 normals 按逐面零法线处理。保留空网格、未引用顶点、重复坐标、重复面和退化面，不将构造有效性包装为几何正确性。面数不超过 715827882，避免展开后角数超出 Int32；构造函数不是独立进程内存限制。

`Mesh::to_indexed()` 精确去重坐标（+0/-0 统一作为键），不按默认焊接容差合并近点；返回新数组。面序、绕向和声明面法线保留。`to_mesh()` 只展开被面引用的坐标，不保留未引用顶点；因此 IndexedMesh → Mesh → IndexedMesh 不保证保留所有顶点身份或多余顶点。UV、材质、颜色、对象语义不进入此类型。

直接计算 `surface_area()`、条件 `volume()`、`bounding_box()`；包围盒只包含被面引用的几何，没有面时为 None。`unused_vertex_count()` 明确报告未引用顶点。

拓扑 `validate(tolerance=1e-6)` **暂时展开 Mesh，复用现有坐标焊接规则**；不会把不同索引身份当成互不连接的拓扑，也没有宣称校验峰值内存已下降。后续可在接口稳定后迁移原生索引算法。构造快照和后续空间索引的失效策略分开，不缓存可变 Mesh。

## 验收与实测

测试覆盖单位立方体的面积 6 / 体积 1 / 8 顶点 / 12 面、边界边 0 / 欧拉数 2；以及非法索引/坐标/法线、数组快照、未引用顶点、精确与近坐标、重复和退化证据、面绕向与法线往返。使用公开 API 的黑盒测试和发布包 consumer 也覆盖转换。

[100k 网格内存对照](benchmarks/indexed-20261028.md) 同时报告逻辑字段和 OS 实测：转换路径的实际峰值比单独 Mesh 高，因为会临时同时持有原网格、哈希表和索引结构。初版提供数据表示基础，不能宣传为现有全流程内存优化。
