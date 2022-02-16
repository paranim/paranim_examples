{.compile: "stb_voxel_render.c".}

from nimgl/opengl import GLfloat

const
  STBVOX_MAX_MESHES = 2
  STBVOX_MAX_MESH_SLOTS = 3

type
  stbvox_block_type* = uint8

type
  stbvox_rgb* {.bycopy.} = object
    r*: uint8
    g*: uint8
    b*: uint8
  stbvox_input_description* {.bycopy.} = object
    lighting_at_vertices*: uint8 ##  The default is lighting values (i.e. ambient occlusion) are at block
                                ##  center, and the vertex light is gathered from those adjacent block
                                ##  centers that the vertex is facing. This makes smooth lighting
                                ##  consistent across adjacent faces with the same orientation.
                                ##
                                ##  Setting this flag to non-zero gives you explicit control
                                ##  of light at each vertex, but now the lighting/ao will be
                                ##  shared by all vertices at the same point, even if they
                                ##  have different normals.
                                ##  these are mostly 3D maps you use to define your voxel world, using x_stride and y_stride
                                ##  note that for cache efficiency, you want to use the block_foo palettes as much as possible instead
    rgb*: ptr stbvox_rgb        ##  Indexed by 3D coordinate.
                      ##  24-bit voxel color for STBVOX_CONFIG_MODE = 20 or 21 only
    lighting*: ptr uint8 ##  Indexed by 3D coordinate. The lighting value / ambient occlusion
                       ##  value that is used to define the vertex lighting values.
                       ##  The raw lighting values are defined at the center of blocks
                       ##  (or at vertex if 'lighting_at_vertices' is true).
                       ##
                       ##  If the macro STBVOX_CONFIG_ROTATION_IN_LIGHTING is defined,
                       ##  then an additional 2-bit block rotation value is stored
                       ##  in this field as well.
                       ##
                       ##  Encode with STBVOX_MAKE_LIGHTING_EXT(lighting,rot)--here
                       ##  'lighting' should still be 8 bits, as the macro will
                       ##  discard the bottom bits automatically. Similarly, if
                       ##  using STBVOX_CONFIG_VHEIGHT_IN_LIGHTING, encode with
                       ##  STBVOX_MAKE_LIGHTING_EXT(lighting,vheight).
                       ##
                       ##  (Rationale: rotation needs to be independent of blocktype,
                       ##  but is only 2 bits so doesn't want to be its own array.
                       ##  Lighting is the one thing that was likely to already be
                       ##  in use and that I could easily steal 2 bits from.)
    blocktype*: ptr stbvox_block_type ##  Indexed by 3D coordinate. This is a core "block type" value, which is used
                                   ##  to index into other arrays; essentially a "palette". This is much more
                                   ##  memory-efficient and performance-friendly than storing the values explicitly,
                                   ##  but only makes sense if the values are always synchronized.
                                   ##
                                   ##  If a voxel's blocktype is 0, it is assumed to be empty (STBVOX_GEOM_empty),
                                   ##  and no other blocktypes should be STBVOX_GEOM_empty. (Only if you do not
                                   ##  have blocktypes should STBVOX_GEOM_empty ever used.)
                                   ##
                                   ##  Normally it is an unsigned byte, but you can override it to be
                                   ##  a short if you have too many blocktypes.
    geometry*: ptr uint8 ##  Indexed by 3D coordinate. Contains the geometry type for the block.
                       ##  Also contains a 2-bit rotation for how the whole block is rotated.
                       ##  Also includes a 2-bit vheight value when using shared vheight values.
                       ##  See the separate vheight documentation.
                       ##  Encode with STBVOX_MAKE_GEOMETRY(geom, rot, vheight)
    block_geometry*: ptr uint8 ##  Array indexed by blocktype containing the geometry for this block, plus
                             ##  a 2-bit "simple rotation". Note rotation has limited use since it's not
                             ##  independent of blocktype.
                             ##
                             ##  Encode with STBVOX_MAKE_GEOMETRY(geom,simple_rot,0)
    block_tex1*: ptr uint8     ##  Array indexed by blocktype containing the texture id for texture #1.
    block_tex1_face*: array[6, uint8] ##  Array indexed by blocktype and face containing the texture id for texture #1.
                                    ##  The N/E/S/W face choices can be rotated by one of the rotation selectors;
                                    ##  The top & bottom face textures will rotate to match.
                                    ##  Note that it only makes sense to use one of block_tex1 or block_tex1_face;
                                    ##  this pattern repeats throughout and this notice is not repeated.
    tex2*: ptr uint8 ##  Indexed by 3D coordinate. Contains the texture id for texture #2
                   ##  to use on all faces of the block.
    block_tex2*: ptr uint8     ##  Array indexed by blocktype containing the texture id for texture #2.
    block_tex2_face*: array[6, uint8] ##  Array indexed by blocktype and face containing the texture id for texture #2.
                                    ##  The N/E/S/W face choices can be rotated by one of the rotation selectors;
                                    ##  The top & bottom face textures will rotate to match.
    color*: ptr uint8 ##  Indexed by 3D coordinate. Contains the color for all faces of the block.
                    ##  The core color value is 0..63.
                    ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    block_color*: ptr uint8 ##  Array indexed by blocktype containing the color value to apply to the faces.
                          ##  The core color value is 0..63.
                          ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    block_color_face*: array[6, uint8] ##  Array indexed by blocktype and face containing the color value to apply to that face.
                                     ##  The core color value is 0..63.
                                     ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    block_texlerp*: ptr uint8 ##  Array indexed by blocktype containing 3-bit scalar for texture #2 alpha
                            ##  (known throughout as 'texlerp'). This is constant over every face even
                            ##  though the property is potentially per-vertex.
    block_texlerp_face*: array[6, uint8] ##  Array indexed by blocktype and face containing 3-bit scalar for texture #2 alpha.
                                       ##  This is constant over the face even though the property is potentially per-vertex.
    block_vheight*: ptr uint8 ##  Array indexed by blocktype containing the vheight values for the
                            ##  top or bottom face of this block. These will rotate properly if the
                            ##  block is rotated. See discussion of vheight.
                            ##  Encode with STBVOX_MAKE_VHEIGHT(sw_height, se_height, nw_height, ne_height)
    selector*: ptr uint8       ##  Array indexed by 3D coordinates indicating which output mesh to select.
    block_selector*: ptr uint8 ##  Array indexed by blocktype indicating which output mesh to select.
    side_texrot*: ptr uint8 ##  Array indexed by 3D coordinates encoding 2-bit texture rotations for the
                          ##  faces on the E/N/W/S sides of the block.
                          ##  Encode with STBVOX_MAKE_SIDE_TEXROT(rot_e, rot_n, rot_w, rot_s)
    block_side_texrot*: ptr uint8 ##  Array indexed by blocktype encoding 2-bit texture rotations for the faces
                                ##  on the E/N/W/S sides of the block.
                                ##  Encode with STBVOX_MAKE_SIDE_TEXROT(rot_e, rot_n, rot_w, rot_s)
    overlay*: ptr uint8 ##  index into palettes listed below
                      ##  Indexed by 3D coordinate. If 0, there is no overlay. If non-zero,
                      ##  it indexes into to the below arrays and overrides the values
                      ##  defined by the blocktype.
    overlay_tex1*: array[6, uint8] ##  Array indexed by overlay value and face, containing an override value
                                 ##  for the texture id for texture #1. If 0, the value defined by blocktype
                                 ##  is used.
    overlay_tex2*: array[6, uint8] ##  Array indexed by overlay value and face, containing an override value
                                 ##  for the texture id for texture #2. If 0, the value defined by blocktype
                                 ##  is used.
    overlay_color*: array[6, uint8] ##  Array indexed by overlay value and face, containing an override value
                                  ##  for the face color. If 0, the value defined by blocktype is used.
    overlay_side_texrot*: ptr uint8 ##  Array indexed by overlay value, encoding 2-bit texture rotations for the faces
                                  ##  on the E/N/W/S sides of the block.
                                  ##  Encode with STBVOX_MAKE_SIDE_TEXROT(rot_e, rot_n, rot_w, rot_s)
    rotate*: ptr uint8 ##  Indexed by 3D coordinate. Allows independent rotation of several
                     ##  parts of the voxel, where by rotation I mean swapping textures
                     ##  and colors between E/N/S/W faces.
                     ##     Block: rotates anything indexed by blocktype
                     ##     Overlay: rotates anything indexed by overlay
                     ##     EColor: rotates faces defined in ecolor_facemask
                     ##  Encode with STBVOX_MAKE_MATROT(block,overlay,ecolor)
    tex2_for_tex1*: ptr uint8 ##  Array indexed by tex1 containing the texture id for texture #2.
                            ##  You can use this if the two are always/almost-always strictly
                            ##  correlated (e.g. if tex2 is a detail texture for tex1), as it
                            ##  will be more efficient (touching fewer cache lines) than using
                            ##  e.g. block_tex2_face.
    tex2_replace*: ptr uint8 ##  Indexed by 3D coordinate. Specifies the texture id for texture #2
                           ##  to use on a single face of the voxel, which must be E/N/W/S (not U/D).
                           ##  The texture id is limited to 6 bits unless tex2_facemask is also
                           ##  defined (see below).
                           ##  Encode with STBVOX_MAKE_TEX2_REPLACE(tex2, face)
    tex2_facemask*: ptr uint8 ##  Indexed by 3D coordinate. Specifies which of the six faces should
                            ##  have their tex2 replaced by the value of tex2_replace. In this
                            ##  case, all 8 bits of tex2_replace are used as the texture id.
                            ##  Encode with STBVOX_MAKE_FACE_MASK(east,north,west,south,up,down)
    extended_color*: ptr uint8 ##  Indexed by 3D coordinate. Specifies a value that indexes into
                             ##  the ecolor arrays below (both of which must be defined).
    ecolor_color*: ptr uint8 ##  Indexed by extended_color value, specifies an optional override
                           ##  for the color value on some faces.
                           ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    ecolor_facemask*: ptr uint8 ##  Indexed by extended_color value, this specifies which faces the
                              ##  color in ecolor_color should be applied to. The faces can be
                              ##  independently rotated by the ecolor value of 'rotate', if it exists.
                              ##  Encode with STBVOX_MAKE_FACE_MASK(e,n,w,s,u,d)
    color2*: ptr uint8 ##  Indexed by 3D coordinates, specifies an alternative color to apply
                     ##  to some of the faces of the block.
                     ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    color2_facemask*: ptr uint8 ##  Indexed by 3D coordinates, specifies which faces should use the
                              ##  color defined in color2. No rotation value is applied.
                              ##  Encode with STBVOX_MAKE_FACE_MASK(e,n,w,s,u,d)
    color3*: ptr uint8 ##  Indexed by 3D coordinates, specifies an alternative color to apply
                     ##  to some of the faces of the block.
                     ##  Encode with STBVOX_MAKE_COLOR(color_number, tex1_enable, tex2_enable)
    color3_facemask*: ptr uint8 ##  Indexed by 3D coordinates, specifies which faces should use the
                              ##  color defined in color3. No rotation value is applied.
                              ##  Encode with STBVOX_MAKE_FACE_MASK(e,n,w,s,u,d)
    texlerp_simple*: ptr uint8 ##  Indexed by 3D coordinates, this is the smallest texlerp encoding
                             ##  that can do useful work. It consits of three values: baselerp,
                             ##  vertlerp, and face_vertlerp. Baselerp defines the value
                             ##  to use on all of the faces but one, from the STBVOX_TEXLERP_BASE
                             ##  values. face_vertlerp is one of the 6 face values (or STBVOX_FACE_NONE)
                             ##  which specifies the face should use the vertlerp values.
                             ##  Vertlerp defines a lerp value at every vertex of the mesh.
                             ##  Thus, one face can have per-vertex texlerp values, and those
                             ##  values are encoded in the space so that they will be shared
                             ##  by adjacent faces that also use vertlerp, allowing continuity
                             ##  (this is used for the "texture crossfade" bit of the release video).
                             ##  Encode with STBVOX_MAKE_TEXLERP_SIMPLE(baselerp, vertlerp, face_vertlerp)
                             ##  The following texlerp encodings are experimental and maybe not
                             ##  that useful.
    texlerp*: ptr uint8 ##  Indexed by 3D coordinates, this defines four values:
                      ##    vertlerp is a lerp value at every vertex of the mesh (using STBVOX_TEXLERP_BASE values).
                      ##    ud is the value to use on up and down faces, from STBVOX_TEXLERP_FACE values
                      ##    ew is the value to use on east and west faces, from STBVOX_TEXLERP_FACE values
                      ##    ns is the value to use on north and south faces, from STBVOX_TEXLERP_FACE values
                      ##  If any of ud, ew, or ns is STBVOX_TEXLERP_FACE_use_vert, then the
                      ##  vertlerp values for the vertices are gathered and used for those faces.
                      ##  Encode with STBVOX_MAKE_TEXLERP(vertlerp,ud,ew,sw)
    texlerp_vert3*: ptr cushort ##  Indexed by 3D coordinates, this works with texlerp and
                             ##  provides a unique texlerp value for every direction at
                             ##  every vertex. The same rules of whether faces share values
                             ##  applies. The STBVOX_TEXLERP_FACE vertlerp value defined in
                             ##  texlerp is only used for the down direction. The values at
                             ##  each vertex in other directions are defined in this array,
                             ##  and each uses the STBVOX_TEXLERP3 values (i.e. full precision
                             ##  3-bit texlerp values).
                             ##  Encode with STBVOX_MAKE_VERT3(vertlerp_e,vertlerp_n,vertlerp_w,vertlerp_s,vertlerp_u)
    texlerp_face3*: ptr cushort ##  e:3,n:3,w:3,s:3,u:2,d:2
                             ##  Indexed by 3D coordinates, this provides a compact way to
                             ##  fully specify the texlerp value indepenendly for every face,
                             ##  but doesn't allow per-vertex variation. E/N/W/S values are
                             ##  encoded using STBVOX_TEXLERP3 values, whereas up and down
                             ##  use STBVOX_TEXLERP_SIMPLE values.
                             ##  Encode with STBVOX_MAKE_FACE3(face_e,face_n,face_w,face_s,face_u,face_d)
    vheight*: ptr uint8 ##  STBVOX_MAKE_VHEIGHT   -- sw:2, se:2, nw:2, ne:2, doesn't rotate
                      ##  Indexed by 3D coordinates, this defines the four
                      ##  vheight values to use if the geometry is STBVOX_GEOM_vheight*.
                      ##  See the vheight discussion.
    packed_compact*: ptr uint8 ##  Stores block rotation, vheight, and texlerp values:
                             ##     block rotation: 2 bits
                             ##     vertex vheight: 2 bits
                             ##     use_texlerp   : 1 bit
                             ##     vertex texlerp: 3 bits
                             ##  If STBVOX_CONFIG_UP_TEXLERP_PACKED is defined, then 'vertex texlerp' is
                             ##  used for up faces if use_texlerp is 1. If STBVOX_CONFIG_DOWN_TEXLERP_PACKED
                             ##  is defined, then 'vertex texlerp' is used for down faces if use_texlerp is 1.
                             ##  Note if those symbols are defined but packed_compact is NULL, the normal
                             ##  texlerp default will be used.
                             ##  Encode with STBVOX_MAKE_PACKED_COMPACT(rot, vheight, texlerp, use_texlerp)
  stbvox_mesh_maker* {.bycopy.} = object
    input*: stbvox_input_description
    cur_x*: cint
    cur_y*: cint
    cur_z*: cint               ##  last unprocessed voxel if it splits into multiple buffers
    x0*: cint
    y0*: cint
    z0*: cint
    x1*: cint
    y1*: cint
    z1*: cint
    x_stride_in_bytes*: cint
    y_stride_in_bytes*: cint
    config_dirty*: cint
    default_mesh*: cint
    tags*: cuint
    cube_vertex_offset*: array[6, array[4, cint]] ##  this allows access per-vertex data stored block-centered (like texlerp, ambient)
    vertex_gather_offset*: array[6, array[4, cint]]
    pos_x*: cint
    pos_y*: cint
    pos_z*: cint
    full*: cint                ##  computed from user input
    output_cur*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cstring]]
    output_end*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cstring]]
    output_buffer*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cstring]]
    output_len*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cint]] ##  computed from config
    output_size*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cint]] ##  per quad
    output_step*: array[STBVOX_MAX_MESHES, array[STBVOX_MAX_MESH_SLOTS, cint]] ##  per vertex or per face, depending
    num_mesh_slots*: cint
    default_tex_scale*: array[128, array[2, GLfloat]]
  stbvox_uniform_info* {.bycopy.} = object
    `type`*: cint              ##  which type of uniform
    bytes_per_element*: cint   ##  the size of each uniform array element (e.g. vec3 = 12 bytes)
    array_length*: cint        ##  length of the uniform array
    name*: cstring             ##  name in the shader @TODO use numeric binding
    default_value*: ptr GLfloat  ##  if not NULL, you can use this as the uniform pointer
    use_tex_buffer*: cint      ##  if true, then the uniform is a sampler but the data can come from default_value

proc initMeshMaker*(meshMaker: ptr stbvox_mesh_maker) {.cdecl, importc: "stbvox_init_mesh_maker".}
proc getVertexShader*(): cstring {.cdecl, importc: "stbvox_get_vertex_shader".}
proc getFragmentShader*(): cstring {.cdecl, importc: "stbvox_get_fragment_shader".}
proc getBufferCount*(meshMaker: ptr stbvox_mesh_maker): int {.cdecl, importc: "stbvox_get_buffer_count".}
proc setBuffer*(mm: ptr stbvox_mesh_maker, mesh: cint, slot: cint, buffer: pointer, len: csize) {.cdecl, importc: "stbvox_set_buffer".}

const
  STBVOX_GEOM_empty* = 0
  STBVOX_GEOM_knockout* = 1     ##  creates a hole in the mesh
  STBVOX_GEOM_solid* = 2
  STBVOX_GEOM_transp* = 3 ##  solid geometry, but transparent contents so neighbors generate normally, unless same blocktype
                       ##  following 4 can be represented by vheight as well
  STBVOX_GEOM_slab_upper* = 4
  STBVOX_GEOM_slab_lower* = 5
  STBVOX_GEOM_floor_slope_north_is_top* = 6
  STBVOX_GEOM_ceil_slope_north_is_bottom* = 7
  STBVOX_GEOM_floor_slope_north_is_top_as_wall_UNIMPLEMENTED* = 8 ##  same as floor_slope above, but uses wall's texture & texture projection
  STBVOX_GEOM_ceil_slope_north_is_bottom_as_wall_UNIMPLEMENTED* = 9
  STBVOX_GEOM_crossed_pair* = 10 ##  corner-to-corner pairs, with normal vector bumped upwards
  STBVOX_GEOM_force* = 11 ##  like GEOM_transp, but faces visible even if neighbor is same type, e.g. minecraft fancy leaves
                       ##  these access vheight input
  STBVOX_GEOM_floor_vheight_03* = 12 ##  diagonal is SW-NE
  STBVOX_GEOM_floor_vheight_12* = 13 ##  diagonal is SE-NW
  STBVOX_GEOM_ceil_vheight_03* = 14
  STBVOX_GEOM_ceil_vheight_12* = 15
  STBVOX_GEOM_count* = 16       ##  number of geom cases

const                         ##   ------------------------------------------------
  STBVOX_UNIFORM_face_data* = 0 ##   n      the sampler with the face texture buffer
  STBVOX_UNIFORM_transform* = 1 ##   n      the transform data from stbvox_get_transform
  STBVOX_UNIFORM_tex_array* = 2 ##   n      an array of two texture samplers containing the two texture arrays
  STBVOX_UNIFORM_texscale* = 3  ##   Y      a table of texture properties, see above
  STBVOX_UNIFORM_color_table* = 4 ##   Y      64 vec4 RGBA values; a default palette is provided; if A > 1.0, fullbright
  STBVOX_UNIFORM_normals* = 5   ##   Y  Y   table of normals, internal-only
  STBVOX_UNIFORM_texgen* = 6    ##   Y  Y   table of texgen vectors, internal-only
  STBVOX_UNIFORM_ambient* = 7   ##   n      lighting & fog info, see above
  STBVOX_UNIFORM_camera_pos* = 8 ##   Y      camera position in global voxel space (for lighting & fog)
  STBVOX_UNIFORM_count* = 9

proc makeGeometry*(geom: uint8, rotate: uint8, vheight: uint8): uint8 {.cdecl, importc: "stbvox_make_geometry".}
proc makeLightingExt*(lighting: uint8, rot: uint8): uint8 {.cdecl, importc: "stbvox_make_lighting_ext".}
proc setInputStride*(mm: ptr stbvox_mesh_maker, x_stride_in_bytes: cint, y_stride_in_bytes: cint) {.cdecl, importc: "stbvox_set_input_stride".}
proc setInputRange*(mm: ptr stbvox_mesh_maker, x0: cint, y0: cint, z0: cint, x1: cint, y1: cint, z1: cint) {.cdecl, importc: "stbvox_set_input_range".}
proc setDefaultMesh*(mm: ptr stbvox_mesh_maker, mesh: cint) {.cdecl, importc: "stbvox_set_default_mesh".}
proc makeMesh*(mm: ptr stbvox_mesh_maker): cint {.cdecl, importc: "stbvox_make_mesh".}
proc setMeshCoordinates*(mm: ptr stbvox_mesh_maker; x: cint; y: cint; z: cint) {.cdecl, importc: "stbvox_set_mesh_coordinates".}
proc getTransform*(mm: ptr stbvox_mesh_maker; transform: array[3, array[3, GLfloat]]) {.cdecl, importc: "stbvox_get_transform".}
proc getBounds*(mm: ptr stbvox_mesh_maker; bounds: array[2, array[3, GLfloat]]) {.cdecl, importc: "stbvox_get_bounds".}
proc getQuadCount*(mm: ptr stbvox_mesh_maker, mesh: cint): cint {.cdecl, importc: "stbvox_get_quad_count".}
proc getUniformInfo*(info: ptr stbvox_uniform_info; uniform: cint): cint {.cdecl, importc: "stbvox_get_uniform_info".}
