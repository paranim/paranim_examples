import glm

type
  Frustum = array[6, Vec4[float]]

proc computeFrustum(matrix: Mat4x4[float]): Frustum =
  let m = matrix.transpose()
  result[0] = m[3] + m[0]
  result[1] = m[3] - m[0]
  result[2] = m[3] + m[1]
  result[3] = m[3] - m[1]
  result[4] = m[3] + m[2]
  result[5] = m[3] - m[2]

proc test*() =
  var m = mat4x4(
    vec4(-0.973834, 0.227259, 0.000000, 0.000000),
    vec4(-0.118801, -0.509078, 1.550617, -116.296250),
    vec4(0.215360, 0.922843, 0.319475, -30.835937),
    vec4(-0.215351, -0.922804, -0.319462, 30.959648),
  )
  m = m.transpose()
  let f = computeFrustum(m)
  for plane in f:
    echo plane
