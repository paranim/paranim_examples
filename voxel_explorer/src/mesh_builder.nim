import nimgl/opengl
import stb_voxel_render, u_noise
import sets

{.compile: "mesh_builder.c".}

const
  meshRadius = 1
  chunkSize = 64
  numZSegments = 16
  zSegmentSize = 16

type
  BlockType = enum
    Empty, Grass, Stone, Sand, Wood, Leaves, Gravel, Asphalt, Marble
  GenChunkPartial {.bycopy.} = object
    `block`: array[chunkSize, array[chunkSize, array[zSegmentSize, uint8]]]
    lighting: array[chunkSize, array[chunkSize, array[zSegmentSize, uint8]]]
    overlay: array[chunkSize, array[chunkSize, array[zSegmentSize, uint8]]]
    rotate: array[chunkSize, array[chunkSize, array[zSegmentSize, uint8]]]
  GenChunk {.bycopy.} = object
    partial: array[numZSegments, GenChunkPartial]
    highest_z: cint
    lowest_z: cint
  ChunkSet {.bycopy.} = object
    chunk: array[4, array[4, ptr GenChunk]]
  MeshChunk {.bycopy.} = object
    chunk_x, chunk_y: cint
    vbuf_size*, fbuf_size*, total_size: csize
    transform*: array[3, array[3, cfloat]]
    bounds: array[2, array[3, cfloat]]
    vbuf*, fbuf*, fbuf_tex*: cuint
    num_quads*: cint
  Mesh* {.bycopy.} = object
    x, y: cint
    mc*: ptr MeshChunk
    vertex_build_buffer*, face_buffer*: pointer
    chunks: ChunkSet
  BuildData {.bycopy.} = object
    vertex_build_buffer: pointer
    face_buffer: pointer
    segment_blocktype: array[66, array[66, array[18, uint8]]]
    segment_lighting: array[66, array[66, array[18, uint8]]]

var
  builtMeshes: HashSet[tuple[x: int, y: int]]
  geomForBlocktype: array[256, cuchar]
  texForBlocktype: array[256, array[6, cuchar]]

proc build_mesh(rm: ptr Mesh, geomForBlocktype: array[256, cuchar], texForBlocktype: array[256, array[6, cuchar]]) {.cdecl, importc: "build_mesh".}

proc world_to_chunk(n: cint): cint {.cdecl importc: "world_to_chunk".}

proc free_mesh*(mesh: ptr Mesh) {.cdecl importc: "free_mesh".}

proc setBlocktypeTex(texForBlocktype: var array[256, array[6, cuchar]], bt: BlockType, tex: int) =
  for i in 0 ..< 6:
    texForBlocktype[bt.ord][i] = tex.cuchar

proc initMeshBuilding(geomForBlocktype: var array[256, cuchar], texForBlocktype: var array[256, array[6, cuchar]]) =
  for i in 1 ..< 256:
    geomForBlocktype[i] = makeGeometry(STBVOX_GEOM_solid.cuchar, 0.cuchar, 0.cuchar)
  setBlocktypeTex(texForBlocktype, Leaves, 0)
  setBlocktypeTex(texForBlocktype, Gravel, 1)
  setBlocktypeTex(texForBlocktype, Grass, 2)
  setBlocktypeTex(texForBlocktype, Asphalt, 3)
  setBlocktypeTex(texForBlocktype, Wood, 4)
  setBlocktypeTex(texForBlocktype, Marble, 5)
  setBlocktypeTex(texForBlocktype, Stone, 6)
  setBlocktypeTex(texForBlocktype, Sand, 7)

proc generateMeshes*(camX: int, camY: int): seq[Mesh] =
  let
    qchunkX = world_to_chunk(camX.cint)
    qchunkY = world_to_chunk(camY.cint)
    chunkCenterX = int(chunkSize/2)
    chunkCenterY = int(chunkSize/2)

  for j in -meshRadius .. meshRadius:
    for i in -meshRadius .. meshRadius:
      let
        cx = qchunkX + i
        cy = qchunkY + j
        t = (cx, cy)
      if not builtMeshes.contains(t):
        let
          wx = cx * chunkSize
          wy = cy * chunkSize
          distX = wx + chunkCenterX - camX
          distY = wy + chunkCenterY - camY
        var m: Mesh
        m.x = wx.cint
        m.y = wy.cint
        build_mesh(m.addr, geomForBlocktype, texForBlocktype)
        result.add(m)
        builtMeshes.incl(t)

proc init*() =
  initMeshBuilding(geomForBlocktype, texForBlocktype)
