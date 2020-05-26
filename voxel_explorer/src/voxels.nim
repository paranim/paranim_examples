import nimgl/opengl
import paranim/gl, paranim/gl/[uniforms, attributes]
import glm
import stb_voxel_render
from algorithm import nil
from mesh_builder import nil

type
  VoxelEntityUniforms = tuple[
    facearray: Uniform[GLint],
    transform: Uniform[seq[Vec3[GLfloat]]], # 3
    normal_table: Uniform[seq[Vec3[GLfloat]]], # 32
    ambient: Uniform[seq[Vec4[GLfloat]]], # 4
    model_view: Uniform[Mat4x4[GLfloat]],
    tex_array: Uniform[seq[GLint]],
    texscale: Uniform[seq[Vec4[GLfloat]]],
    color_table: Uniform[seq[Vec4[GLfloat]]],
    texgen: Uniform[seq[Vec3[GLfloat]]],
  ]
  VoxelEntityAttributes = tuple[attr_vertex: Attribute[GLuint], texture: TextureBuffer[GLubyte], indexes: IndexBuffer[GLuint]]
  VoxelEntity* = object of IndexedEntity[VoxelEntityUniforms, VoxelEntityAttributes]
  UncompiledVoxelEntity* = object of UncompiledEntity[VoxelEntity, VoxelEntityUniforms, VoxelEntityAttributes]

proc quadsToTris[T](dataLen: int, vertexSize: int): seq[T] =
  var i = 0
  while i < dataLen:
    result.add([T(i+0), T(i+1), T(i+2), T(i+0), T(i+2), T(i+3)])
    i += vertexSize * 4

proc initVoxelEntity*(mesh: mesh_builder.Mesh, faceUnit: GLint, voxelUnit: GLint): UncompiledVoxelEntity =
  result.vertexSource = $ getVertexShader()
  result.fragmentSource = $ getFragmentShader()
  # set attr_vertex
  result.attributes.attr_vertex = Attribute[GLuint](size: 1, iter: 1)
  new(result.attributes.attr_vertex.data)
  let vbuf = cast[ptr UncheckedArray[uint32]](mesh.vertex_build_buffer)
  for i in 0 ..< int(mesh.mc.vbuf_size / 4):
    result.attributes.attr_vertex.data[].add(vbuf[i])
  # set texture
  result.attributes.texture = TextureBuffer[GLubyte](unit: faceUnit, internalFmt: GL_RGBA8UI)
  new(result.attributes.texture.data)
  let fbuf = cast[ptr UncheckedArray[uint8]](mesh.face_buffer)
  for i in 0 ..< mesh.mc.fbuf_size:
    result.attributes.texture.data[].add(fbuf[i])
  # set indexes (this allows us to draw with GL_TRIANGLES instead of the obsolete GL_QUADS)
  result.attributes.indexes = IndexBuffer[GLuint]()
  new(result.attributes.indexes.data)
  result.attributes.indexes.data[].add(quadsToTris[GLuint](result.attributes.attr_vertex.data[].len, 1))
  # set uniforms
  result.uniforms = (
    facearray: Uniform[GLint](data: faceUnit),
    transform: Uniform[seq[Vec3[GLfloat]]](data: block:
      var vecs = newSeq[Vec3[GLfloat]]()
      for row in mesh.mc.transform:
        vecs.add(vec3(row[0], row[1], row[2]))
      vecs
    ),
    normal_table: Uniform[seq[Vec3[GLfloat]]](data: block:
      var vecs = newSeq[Vec3[GLfloat]](32)
      var info: stbvox_uniform_info
      discard getUniformInfo(info.addr, STBVOX_UNIFORM_normals)
      let data = cast[ptr array[32, array[3, GLfloat]]](info.default_value)
      for i in 0 ..< 32:
        vecs[i] = vec3(data[i][0], data[i][1], data[i][2])
      vecs
    ),
    ambient: Uniform[seq[Vec4[GLfloat]]](data: block:
      var vecs = newSeq[Vec4[GLfloat]](4)
      vecs[0] = vec4(0.3f, -0.5f, 0.9f, 0f)
      var amb: array[3, array[3, GLfloat]]
      amb[1] = [0.3f, 0.3f, 0.3f]
      amb[2] = [1.0f, 1.0f, 1.0f]
      for j in 0 ..< 3:
        vecs[1][j] = (amb[2][j] - amb[1][j]) / 2
        vecs[2][j] = (amb[1][j] + amb[2][j]) / 2
      vecs[1][3] = 0f
      vecs[2][3] = 0f
      vecs
    ),
    model_view: Uniform[Mat4x4[GLfloat]](disable: true, data: mat4f(1)),
    tex_array: Uniform[seq[GLint]](data: @[voxelUnit.GLint, voxelUnit.GLint]),
    texscale: Uniform[seq[Vec4[GLfloat]]](data: block:
      var vecs = newSeq[Vec4[GLfloat]](128)
      algorithm.fill(vecs, vec4(1.0f/4, 1.0f, 0f, 0f))
      vecs
    ),
    color_table: Uniform[seq[Vec4[GLfloat]]](data: block:
      var vecs = newSeq[Vec4[GLfloat]](64)
      algorithm.fill(vecs, vec4(1f, 1f, 1f, 1f))
      vecs
    ),
    texgen: Uniform[seq[Vec3[GLfloat]]](data: block:
      var vecs = newSeq[Vec3[GLfloat]](64)
      var info: stbvox_uniform_info
      discard getUniformInfo(info.addr, STBVOX_UNIFORM_texgen)
      let data = cast[ptr array[2, array[32, array[3, GLfloat]]]](info.default_value)
      for i in 0 ..< 2:
        for j in 0 ..< 32:
          vecs[i*32+j] = vec3(data[i][j][0], data[i][j][1], data[i][j][2])
      vecs
    )
  )

