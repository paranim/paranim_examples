#define STBVOX_CONFIG_MODE  1
#define STBVOX_CONFIG_DISABLE_TEX2
//#define STBVOX_CONFIG_PREFER_TEXBUFFER
//#define STBVOX_CONFIG_LIGHTING_SIMPLE
#define STBVOX_CONFIG_FOG_SMOOTHSTEP
//#define STBVOX_CONFIG_PREMULTIPLIED_ALPHA  // this doesn't work properly alpha test without next #define
//#define STBVOX_CONFIG_UNPREMULTIPLY  // slower, fixes alpha test makes windows & fancy leaves look better
#define STBVOX_CONFIG_TEXTURE_TRANSLATION
#define STBVOX_DEFAULT_COLOR  64
#define STBVOX_CONFIG_ROTATION_IN_LIGHTING

#define STB_VOXEL_RENDER_IMPLEMENTATION
#include "stb_voxel_render.h"

unsigned char stbvox_make_geometry(unsigned char geom, unsigned char rotate, unsigned char height) {
  return STBVOX_MAKE_GEOMETRY(geom, rotate, height);
}

unsigned char stbvox_make_lighting_ext(unsigned char lighting, unsigned char rot) {
  return STBVOX_MAKE_LIGHTING_EXT(lighting, rot);
}
