import paranim/opengl
import paranim/gl, paranim/gl/[uniforms, attributes]
import paranim/glm
import stb_voxel_render
from algorithm import nil
from mesh_builder import nil
import re

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

proc setMesh*[T](entity: var T, mesh: mesh_builder.Mesh) =
  # set attr_vertex
  entity.attributes.attr_vertex.disable = false
  let vbuf = cast[ptr UncheckedArray[uint32]](mesh.vertex_build_buffer)
  for i in 0 ..< int(mesh.mc.vbuf_size / 4):
    entity.attributes.attr_vertex.data[].add(vbuf[i])
  # set texture
  entity.attributes.texture.disable = false
  let fbuf = cast[ptr UncheckedArray[uint8]](mesh.face_buffer)
  for i in 0 ..< mesh.mc.fbuf_size:
    entity.attributes.texture.data[].add(fbuf[i])
  # set indexes (this allows us to draw with GL_TRIANGLES instead of the obsolete GL_QUADS)
  entity.attributes.indexes.disable = false
  entity.attributes.indexes.data[].add(quadsToTris[GLuint](entity.attributes.attr_vertex.data[].len, 1))
  # set transform uniform
  entity.uniforms.transform.disable = false
  entity.uniforms.transform.data = block:
    var vecs = newSeq[Vec3[GLfloat]]()
    for row in mesh.mc.transform:
      vecs.add(vec3(row[0], row[1], row[2]))
    vecs

proc initVoxelEntity*(faceUnit: GLint, voxelUnit: GLint): UncompiledVoxelEntity =
  result.vertexSource = $ getVertexShader()
  result.fragmentSource = $ getFragmentShader()
  when defined(emscripten):
    result.vertexSource = result.vertexSource.replace(re"#version.*", "#version 300 es\n")
    result.fragmentSource = result.fragmentSource.replace(re"#version.*", "#version 300 es\n")
  # attr_vertex
  result.attributes.attr_vertex = Attribute[GLuint](disable: true, size: 1, iter: 1)
  new(result.attributes.attr_vertex.data)
  # texture
  result.attributes.texture = TextureBuffer[GLubyte](disable: true, unit: faceUnit, internalFmt: GL_RGBA8UI)
  new(result.attributes.texture.data)
  # indexes
  result.attributes.indexes = IndexBuffer[GLuint](disable: true)
  new(result.attributes.indexes.data)
  # set uniforms
  result.uniforms = (
    facearray: Uniform[GLint](data: faceUnit),
    transform: Uniform[seq[Vec3[GLfloat]]](disable: true),
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

