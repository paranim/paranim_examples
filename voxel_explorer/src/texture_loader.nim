{.compile: "stb_image_resize.c".}

import nimgl/opengl

const
  STBIR_FLAG_ALPHA_PREMULTIPLIED = 1
  STBIR_EDGE_CLAMP   = 1
  STBIR_EDGE_REFLECT = 2
  STBIR_EDGE_WRAP    = 3
  STBIR_EDGE_ZERO    = 4

proc stbir_resize_uint8_srgb_edgemode*(input_pixels: pointer; input_w: cint;
                                       input_h: cint; input_stride_in_bytes: cint;
                                       output_pixels: pointer; output_w: cint;
                                       output_h: cint;
                                       output_stride_in_bytes: cint;
                                       num_channels: cint; alpha_channel: cint;
                                       flags: cint; edge_wrap_mode: cint): cint {.cdecl, importc: "stbir_resize_uint8_srgb_edgemode".}

proc load_bitmap_to_texture_array*(slot: cint, data: seq[uint8], width: cint, height: cint, wrap: bool, premul: bool) =
  var i: cint
  var old_data = data
  glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, slot, width, height, 1, GL_RGBA,
                  GL_UNSIGNED_BYTE, old_data[0].addr)
  i = 1
  var
    w = width
    h = height
  while i < 13 and (w > 1 or h > 1):
    var
      nw: cint = w shr 1
      nh: cint = h shr 1
    var new_data = newSeq[uint8](nw * nh * 4)
    discard stbir_resize_uint8_srgb_edgemode(old_data[0].addr, w, h, 0, new_data[0].addr, nw, nh, 0, 4, 3, if premul: STBIR_FLAG_ALPHA_PREMULTIPLIED else: 0, if wrap: STBIR_EDGE_WRAP else: STBIR_EDGE_ZERO)
    old_data = new_data
    w = nw
    h = nh
    glTexSubImage3D(GL_TEXTURE_2D_ARRAY, i, 0, 0, slot, w, h, 1, GL_RGBA,
                    GL_UNSIGNED_BYTE, old_data[0].addr)
    inc(i)
