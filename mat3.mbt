// Jacobi eigendecomposition for finite real symmetric 3x3 matrices.
// Use the upper triangle of a row-major array of at least nine entries.

///|
pub(all) struct SymmetricEigen {
  /// Descending eigenvalues; vectors[i] belongs to values[i].
  values : FixedArray[Double]
  vectors : Array[Vec3]
}

///|
/// Return a complete orthonormal basis, including repeated eigenvalues.
/// Directions inside a repeated eigenspace are not unique.
pub fn symmetric_eigendecomposition(m : FixedArray[Double]) -> SymmetricEigen {
  let mut scale = 0.0
  for i in [0, 1, 2, 4, 5, 8] {
    scale = scale.max(m[i].abs())
  }
  let a : FixedArray[Double] = FixedArray::make(9, 0.0)
  let v : FixedArray[Double] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
  if scale > 0.0 {
    for i = 0; i < 3; i = i + 1 {
      for j = i; j < 3; j = j + 1 {
        a[i * 3 + j] = m[i * 3 + j] / scale
        a[j * 3 + i] = a[i * 3 + j]
      }
    }
    for _iteration = 0; _iteration < 64; _iteration = _iteration + 1 {
      let mut p = 0
      let mut q = 1
      let mut largest = a[1].abs()
      for pair in [(0, 2), (1, 2)] {
        let magnitude = a[pair.0 * 3 + pair.1].abs()
        if magnitude > largest {
          largest = magnitude
          p = pair.0
          q = pair.1
        }
      }
      if largest <= 1.0e-15 {
        break
      }
      let apq = a[p * 3 + q]
      let tau = (a[q * 3 + q] - a[p * 3 + p]) / (2.0 * apq)
      let t = if tau >= 0.0 {
        1.0 / (tau + @math.hypot(1.0, tau))
      } else {
        -1.0 / (-tau + @math.hypot(1.0, tau))
      }
      let c = 1.0 / (1.0 + t * t).sqrt()
      let s = t * c
      a[p * 3 + p] = a[p * 3 + p] - t * apq
      a[q * 3 + q] = a[q * 3 + q] + t * apq
      a[p * 3 + q] = 0.0
      a[q * 3 + p] = 0.0
      for k = 0; k < 3; k = k + 1 {
        if k != p && k != q {
          let akp = a[k * 3 + p]
          let akq = a[k * 3 + q]
          a[k * 3 + p] = c * akp - s * akq
          a[p * 3 + k] = a[k * 3 + p]
          a[k * 3 + q] = s * akp + c * akq
          a[q * 3 + k] = a[k * 3 + q]
        }
        let vkp = v[k * 3 + p]
        let vkq = v[k * 3 + q]
        v[k * 3 + p] = c * vkp - s * vkq
        v[k * 3 + q] = s * vkp + c * vkq
      }
    }
  }
  let order = [0, 1, 2]
  for i = 0; i < 2; i = i + 1 {
    for j = i + 1; j < 3; j = j + 1 {
      if a[order[j] * 3 + order[j]] > a[order[i] * 3 + order[i]] {
        let tmp = order[i]
        order[i] = order[j]
        order[j] = tmp
      }
    }
  }
  let values : FixedArray[Double] = FixedArray::make(3, 0.0)
  let vectors = []
  for i = 0; i < 3; i = i + 1 {
    let k = order[i]
    values[i] = a[k * 3 + k] * scale
    vectors.push(Vec3::new(v[k], v[3 + k], v[6 + k]))
  }
  { values, vectors, }
}

///|
/// Descending eigenvalues, using the same decomposition as PCA.
pub fn symmetric_eigenvalues(m : FixedArray[Double]) -> FixedArray[Double] {
  symmetric_eigendecomposition(m).values
}

///|
/// Compatibility lookup: choose the basis vector nearest to lambda.
/// Repeating this call for the same repeated eigenvalue returns the same vector;
/// use symmetric_eigendecomposition() when a complete basis is needed.
pub fn symmetric_eigenvector(m : FixedArray[Double], lambda : Double) -> Vec3 {
  let eigen = symmetric_eigendecomposition(m)
  let mut best = 0
  for i = 1; i < 3; i = i + 1 {
    if (eigen.values[i] - lambda).abs() < (eigen.values[best] - lambda).abs() {
      best = i
    }
  }
  eigen.vectors[best]
}
