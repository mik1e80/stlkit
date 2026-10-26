///|
fn assert_orthonormal_pca(axes : Array[Vec3]) -> Unit raise {
  assert_eq(axes.length(), 3)
  for i = 0; i < 3; i = i + 1 {
    assert_true((axes[i].length() - 1.0).abs() < 1.0e-10)
    for j = i + 1; j < 3; j = j + 1 {
      assert_true(axes[i].dot(axes[j]).abs() < 1.0e-10)
    }
  }
}

///|
fn pca_component(v : Vec3, i : Int32) -> Double {
  if i == 0 {
    v.x
  } else if i == 1 {
    v.y
  } else {
    v.z
  }
}

///|
test "Jacobi eigenpairs reconstruct rotated repeated and rank deficient matrices" {
  let basis = [
    Vec3::new(0.6, 0.8, 0.0),
    Vec3::new(-0.48, 0.36, 0.8),
    Vec3::new(0.64, -0.48, 0.6),
  ]
  for
    values in [
      [5.0, 2.0, 2.0],
      [5.0, 5.0, 2.0],
      [3.0, 3.0, 3.0],
      [7.0, 0.0, 0.0],
      [4.0, 1.0e-10, 0.0],
      [-1.0, -1.0, -3.0],
    ] {
    for scale in [1.0e-200, 1.0, 1.0e200] {
      let m : FixedArray[Double] = FixedArray::make(9, 0.0)
      for i = 0; i < 3; i = i + 1 {
        for j = 0; j < 3; j = j + 1 {
          for k = 0; k < 3; k = k + 1 {
            m[i * 3 + j] = m[i * 3 + j] +
              scale *
              values[k] *
              pca_component(basis[k], i) *
              pca_component(basis[k], j)
          }
        }
      }
      let eigen = symmetric_eigendecomposition(m)
      assert_orthonormal_pca(eigen.vectors)
      for k = 0; k < 3; k = k + 1 {
        assert_true((eigen.values[k] / scale - values[k]).abs() < 2.0e-13)
        for i = 0; i < 3; i = i + 1 {
          let mut av = 0.0
          let mut reconstruction = 0.0
          for j = 0; j < 3; j = j + 1 {
            av = av + m[i * 3 + j] / scale * pca_component(eigen.vectors[k], j)
            reconstruction = reconstruction +
              eigen.values[j] /
              scale *
              pca_component(eigen.vectors[j], i) *
              pca_component(eigen.vectors[j], k)
          }
          assert_true(
            (av - eigen.values[k] / scale * pca_component(eigen.vectors[k], i)).abs() <
            2.0e-13,
          )
          assert_true((reconstruction - m[i * 3 + k] / scale).abs() < 2.0e-13)
        }
      }
    }
  }
}

///|
test "zero matrix returns a complete basis" {
  let eigen = symmetric_eigendecomposition(FixedArray::make(9, 0.0))
  assert_orthonormal_pca(eigen.vectors)
  for value in eigen.values {
    assert_eq(value, 0.0)
  }
}

///|
test "PCA repeated pair: 2x2x4 square prism keeps three nonzero axes" {
  let mesh = box_mesh(2.0, 2.0, 4.0)
  let obb = mesh.oriented_bounding_box().unwrap()
  assert_orthonormal_pca(obb.axes)
  assert_true((obb.size().x - 4.0).abs() < 1.0e-10)
  assert_true((obb.size().y - 2.0).abs() < 1.0e-10)
  assert_true((obb.size().z - 2.0).abs() < 1.0e-10)
  assert_true((obb.volume() - 16.0).abs() < 1.0e-10)
}

///|
test "rotated square prism has an enclosing PCA box without a unique radial frame" {
  for angle in [0.1, 0.5, 1.1] {
    let original = rotate_z(box_mesh(2.0, 2.0, 4.0), angle)
    let triangles : Array[Triangle] = []
    for t in original.triangles {
      let rotate = fn(p : Vec3) -> Vec3 {
        Vec3::new(
          p.x * 0.6 + p.z * 0.8 + 17.0,
          p.y - 9.0,
          -p.x * 0.8 + p.z * 0.6 + 4.0,
        )
      }
      triangles.push(
        Triangle::from_vertices(rotate(t.a), rotate(t.b), rotate(t.c)),
      )
    }
    let mesh = Mesh::new(triangles)
    let obb = mesh.oriented_bounding_box().unwrap()
    assert_orthonormal_pca(obb.axes)
    assert_true(obb.volume() >= 16.0 - 1.0e-9)
    assert_true(obb.volume() <= 32.0 + 1.0e-9)
    for t in mesh.triangles {
      for v in [t.a, t.b, t.c] {
        assert_true(inside_obb(obb, v))
      }
    }
  }
}

///|
fn pca_cylinder() -> Mesh {
  let triangles : Array[Triangle] = []
  for i = 0; i < 32; i = i + 1 {
    let a = 2.0 * @math.PI * i.to_double() / 32.0
    let b = 2.0 * @math.PI * (i + 1).to_double() / 32.0
    let p = Vec3::new(@math.cos(a), @math.sin(a), -2.0)
    let q = Vec3::new(@math.cos(b), @math.sin(b), -2.0)
    let r = Vec3::new(q.x, q.y, 2.0)
    let s = Vec3::new(p.x, p.y, 2.0)
    triangles.push(Triangle::from_vertices(p, q, r))
    triangles.push(Triangle::from_vertices(p, r, s))
    triangles.push(Triangle::from_vertices(Vec3::new(0.0, 0.0, -2.0), q, p))
    triangles.push(Triangle::from_vertices(Vec3::new(0.0, 0.0, 2.0), s, r))
  }
  Mesh::new(triangles)
}

///|
test "PCA cylinder repeated radial eigenvalues retain enclosing orthogonal axes" {
  for angle in [0.0, 0.3, 0.9] {
    let mesh = rotate_z(pca_cylinder(), angle)
    let obb = mesh.oriented_bounding_box().unwrap()
    assert_orthonormal_pca(obb.axes)
    assert_true(obb.volume() > 15.0)
    for t in mesh.triangles {
      for v in [t.a, t.b, t.c] {
        assert_true(inside_obb(obb, v))
      }
    }
  }
}
