//  Mesh builder "process"
//
//    Both server & client are customers of this process

#include <stdlib.h>

#include <math.h>
#include <assert.h>

#include "u_noise.h"

#include "stb_voxel_render.h"

#define stb_min(a,b)   ((a) < (b) ? (a) : (b))
#define stb_max(a,b)   ((a) > (b) ? (a) : (b))

#define stb_lerp(t,a,b)               ( (a) + (t) * (float) ((b)-(a)) )
#define stb_unlerp(t,a,b)             ( ((t) - (a)) / (float) ((b) - (a)) )
#define stb_clamp(x,xmin,xmax)  ((x) < (xmin) ? (xmin) : (x) > (xmax) ? (xmax) : (x))

typedef int Bool;
#define True   1
#define False  0

typedef unsigned char  uint8 ;
typedef   signed char   int8 ;
typedef unsigned short uint16;
typedef   signed short  int16;
typedef unsigned int   uint32;
typedef   signed int    int32;


#define CHUNK_SIZE 64
#define NUM_Z_SEGMENTS   16
#define Z_SEGMENT_SIZE   16

#define MAX_BUILT_MESHES   256

#define AVG_GROUND 32

typedef struct
{
   int x,y,z;
} vec3i;

typedef struct
{
   int x0,y0,x1,y1;
} recti;

// block types
enum
{
   BT_empty,
   BT_grass,
   BT_stone,
   BT_sand,
   BT_wood,
   BT_leaves,
   BT_gravel,
   BT_asphalt,
   BT_marble,
};

typedef struct
{
   int chunk_x, chunk_y;

   size_t vbuf_size, fbuf_size;
   size_t total_size;

   float transform[3][3];
   float bounds[2][3];

   unsigned int vbuf;
   unsigned int fbuf, fbuf_tex;
   int num_quads;
} mesh_chunk;

typedef struct
{
   uint8 block   [CHUNK_SIZE][CHUNK_SIZE][Z_SEGMENT_SIZE];
   uint8 lighting[CHUNK_SIZE][CHUNK_SIZE][Z_SEGMENT_SIZE];
   uint8 overlay [CHUNK_SIZE][CHUNK_SIZE][Z_SEGMENT_SIZE];
   uint8 rotate  [CHUNK_SIZE][CHUNK_SIZE][Z_SEGMENT_SIZE];
} gen_chunk_partial;

typedef struct
{
   gen_chunk_partial partial  [NUM_Z_SEGMENTS];
   int highest_z;
   int lowest_z;
} gen_chunk;

typedef struct
{
   gen_chunk *chunk[4][4];
} chunk_set;

typedef struct
{
   int x,y;
   int state;

   mesh_chunk *mc;
   uint8 *vertex_build_buffer; // malloc/free
   uint8 *face_buffer;  // malloc/free

   chunk_set chunks;
} mesh;

double stb_linear_remap(double x, double x_min, double x_max,
                                  double out_min, double out_max)
{
   return stb_lerp(stb_unlerp(x,x_min,x_max),out_min,out_max);
}

int world_to_chunk(int n) {
  return n / CHUNK_SIZE;
}

float octave_multiplier[8] =
{
   1.01f,
   1.03f,
   1.052f,
   1.021f,
   1.0057f,
   1.111f,
   1.089f,
   1.157f,
};

float compute_height_field_octave(float ns, int o, float weight)
{
   float scale,heavier,sign;
   scale = (float) (1 << o) * octave_multiplier[o];
   sign = (ns < 0 ? -1.0f : 1.0f);
   ns = (float) fabs(ns);
   heavier = ns*ns*ns*ns*4*sign;
   return scale/2 * stb_lerp(weight, ns, heavier) / 2;
}

float compute_height_field(int x, int y, float weight)
{
   int o;
   float ht = AVG_GROUND;
   for (o=3; o < 8; ++o) {
      float scale = (float) (1 << o) * octave_multiplier[o];
      float ns = stb_perlin_noise3(x/scale, y/scale, o*2.0f, 256,256,256);
      ht += compute_height_field_octave(ns, o, weight);
   }
   return ht;
}

float compute_height_field_delta(int x, int y, float weight)
{
   int o;
   float ht = 0;
   for (o=0; o < 3; ++o) {
      float ns = (big_noise(x, y, o, 8348+o*23787)/32678.0f - 1.0f)/2.0f;
      ht += compute_height_field_octave(ns, o, weight);
   }
   return ht;
}

#define HEIGHT_FIELD_SPACING       8

float bilinear_interpolate(float p00, float p10, float p01, float p11, int ix, int iy)
{
   float x = (ix / (float) HEIGHT_FIELD_SPACING);
   float y = (iy / (float) HEIGHT_FIELD_SPACING);
   float p0 = stb_lerp(y, p00, p01);
   float p1 = stb_lerp(y, p10, p11);
   return stb_lerp(x, p0, p1);
}

gen_chunk *generate_chunk(int x, int y)
{
   float height_base[CHUNK_SIZE/HEIGHT_FIELD_SPACING+1+2][CHUNK_SIZE/HEIGHT_FIELD_SPACING+1+2];
   float weight_base[CHUNK_SIZE/HEIGHT_FIELD_SPACING+1+2][CHUNK_SIZE/HEIGHT_FIELD_SPACING+1+2];
   int z_seg;
   int i,j,z,ji,ii;
   int ground_top = 0, solid_bottom=255;
   gen_chunk *gc;
   float height_lerp[CHUNK_SIZE+8][CHUNK_SIZE+8];
   float height_field[CHUNK_SIZE+8][CHUNK_SIZE+8];
   unsigned short height_ore[CHUNK_SIZE+8][CHUNK_SIZE+8];
   int height_field_int[CHUNK_SIZE+8][CHUNK_SIZE+8];

   gc = malloc(sizeof(*gc));
   assert(gc);

   // @TODO: compute non_empty based on below updates
   // @OPTIMIZE: change mesh builder to check non_empty

   for (j=-HEIGHT_FIELD_SPACING,ji=0; j <= CHUNK_SIZE+HEIGHT_FIELD_SPACING; j += HEIGHT_FIELD_SPACING, ++ji)
      for (i=-HEIGHT_FIELD_SPACING,ii=0; i <= CHUNK_SIZE+HEIGHT_FIELD_SPACING; i += HEIGHT_FIELD_SPACING, ++ii) {
         float ht;
         float weight = (float) stb_linear_remap(stb_perlin_noise3((x+i)/256.0f,(y+j)/256.0f,100,256,256,256), -1.5, 1.5, -4.0f, 5.0f);
         weight_base[ji][ii] = weight;
         ht = compute_height_field(x+i,y+j, weight);
         height_base[ji][ii] = ht;
      }

   for (j=-4; j < CHUNK_SIZE+4; ++j)
      for (i=-4; i < CHUNK_SIZE+4; ++i) {
         float ht;
         float weight;
         
         ii = (i / HEIGHT_FIELD_SPACING) + 1;
         ji = (j / HEIGHT_FIELD_SPACING) + 1;
         weight = bilinear_interpolate(weight_base[ji][ii], weight_base[ji][ii+1], weight_base[ji+1][ii], weight_base[ji+1][ii+1], i&7, j&7);
         weight = stb_clamp(weight,0,1);
         ht = bilinear_interpolate(height_base[ji][ii], height_base[ji][ii+1], height_base[ji+1][ii], height_base[ji+1][ii+1], i&7, j&7);
         ht += compute_height_field_delta(x+i,y+j,weight);
         if (ht < 4) ht = 4; else if (ht > 160) ht = 160;
         height_lerp[j+4][i+4] = weight;
         height_field[j+4][i+4] = ht;
         height_field_int[j+4][i+4] = (int) height_field[j+4][i+4];
         ground_top = stb_max(ground_top, height_field_int[j+4][i+4]);
         solid_bottom = stb_min(solid_bottom, height_field_int[j+4][i+4]);
      }

   gc->highest_z = ground_top;
   gc->lowest_z = solid_bottom;
   for (z_seg=0; z_seg < NUM_Z_SEGMENTS; ++z_seg) {
      int z0 = z_seg * Z_SEGMENT_SIZE;
      int z1 = z0 + Z_SEGMENT_SIZE-1;
      gen_chunk_partial *gcp = &gc->partial[z_seg];
      if (z0 > gc->highest_z+1) {
         for (j=0; j < CHUNK_SIZE; ++j)
            for (i=0; i < CHUNK_SIZE; ++i)
               memset(gcp->block[j][i], BT_empty, Z_SEGMENT_SIZE);
      } else if (z1+1 < gc->lowest_z) {
         for (j=0; j < CHUNK_SIZE; ++j)
            for (i=0; i < CHUNK_SIZE; ++i)
               memset(gcp->block[j][i], BT_stone, Z_SEGMENT_SIZE);
      } else {
         for (j=0; j < CHUNK_SIZE; ++j) {
            for (i=0; i < CHUNK_SIZE; ++i) {
               int bt;
               int ht = height_field_int[j+4][i+4];

               int z_stone = stb_clamp(ht-2-z0, 0, Z_SEGMENT_SIZE);
               int z_limit = stb_clamp(ht-z0, 0, Z_SEGMENT_SIZE);

               if (height_lerp[j][i] < 0.5)
                  bt = BT_grass;
               else
                  bt = BT_sand;
               if (ht > AVG_GROUND+14)
                  bt = BT_gravel;

               //bt = (int) stb_lerp(height_lerp[j][i], BT_sand, BT_marble+0.99f);
               assert(z_limit >= 0 && Z_SEGMENT_SIZE - z_limit >= 0);

               memset(&gcp->rotate[j][i][0], 0, Z_SEGMENT_SIZE);
               if (z_limit > 0) {
                  memset(&gcp->block[j][i][   0   ], BT_stone, z_stone);
                  memset(&gcp->block[j][i][z_stone],  bt     , z_limit-z_stone);
               }
               memset(&gcp->block[j][i][z_limit],     BT_empty    , Z_SEGMENT_SIZE - z_limit);
            }
         }
      }
   }

   // compute lighting for every block by weighted average of neighbors

   // loop through every partial chunk separately

   for (z_seg=0; z_seg < NUM_Z_SEGMENTS; ++z_seg) {
      gen_chunk_partial *gcp = &gc->partial[z_seg];
      if (z_seg*Z_SEGMENT_SIZE > gc->highest_z+1 || (z_seg+1)*Z_SEGMENT_SIZE < gc->lowest_z) {
         unsigned char light = STBVOX_MAKE_LIGHTING_EXT(255,0);
         if ((z_seg+1)*Z_SEGMENT_SIZE < gc->lowest_z) light = STBVOX_MAKE_LIGHTING_EXT(0,0);
         #if 1
         for (j=0; j < CHUNK_SIZE; ++j) {
            memset(gcp->lighting[j][0                 ], light, Z_SEGMENT_SIZE);
            memset(gcp->lighting[j][CHUNK_SIZE-1], light, Z_SEGMENT_SIZE);
         }
         for (i=0; i < CHUNK_SIZE; ++i) {
            memset(gcp->lighting[0                 ][i], light, Z_SEGMENT_SIZE);
            memset(gcp->lighting[CHUNK_SIZE-1][i], light, Z_SEGMENT_SIZE);
         }
         #else
         memset(gcp->lighting, light, sizeof(gcp->lighting));
         #endif
      } else {
         gen_chunk_partial *gcp = &gc->partial[z_seg];
         for (j=0; j < CHUNK_SIZE; ++j)
            for (i=0; i < CHUNK_SIZE; ++i)
               for (z=0; z < Z_SEGMENT_SIZE; ++z) {
                  static uint8 convert_rot[4] = { 0,3,2,1 };
                  int type = gcp->block[j][i][z];
                  int is_solid = type != BT_empty;
                  gcp->lighting[j][i][z] = STBVOX_MAKE_LIGHTING_EXT(is_solid ? 0 : 255, convert_rot[gcp->rotate[j][i][z]]);
               }
      }
   }

   return gc;
}


// mesh building
//
// To build a mesh that is 64x64x255, we need input data 66x66x257.
// If proc gen chunks are 32x32, we need a grid of 4x4 of them:
//
//                stb_voxel_render
//    x range      x coord needed   segment-array
//   of chunk       for meshing       x coord
//   -32..-1            -1                0           1 block
//     0..31           0..31            1..32        32 blocks
//    32..63          32..63           33..64        32 blocks
//    64..95            64               65           1 block

typedef struct
{
   uint8 *vertex_build_buffer;
   uint8 *face_buffer;
   uint8 segment_blocktype[66][66][18];
   uint8 segment_lighting[66][66][18];
} build_data;

void copy_chunk_set_to_segment(chunk_set *chunks, int z_seg, build_data *bd)
{
   int j,i,x,y,a;
   for (j=0; j < 4; ++j)
      for (i=0; i < 4; ++i) {
         gen_chunk_partial *gcp;

         int x_off = (i-1) * CHUNK_SIZE + 1;
         int y_off = (j-1) * CHUNK_SIZE + 1;

         int x0,y0,x1,y1;

         x0 = 0; x1 = CHUNK_SIZE;
         y0 = 0; y1 = CHUNK_SIZE;

         if (x_off + x0 <  0) x0 = 0 - x_off;
         if (x_off + x1 > 66) x1 = 66 - x_off;
         if (y_off + y0 <  0) y0 = 0 - y_off;
         if (y_off + y1 > 66) y1 = 66 - y_off;

         gcp = &chunks->chunk[j][i]->partial[z_seg];
         for (y=y0; y < y1; ++y) {
            for (x=x0; x < x1; ++x) {
               memcpy(&bd->segment_blocktype[y+y_off][x + x_off][0], &gcp->block   [y][x][0], 16);
               memcpy(&bd->segment_lighting [y+y_off][x + x_off][0], &gcp->lighting[y][x][0], 16);
            }
         }
      }
}

void generate_mesh_for_chunk_set(stbvox_mesh_maker *mm, mesh_chunk *mc, vec3i world_coord, chunk_set *chunks, size_t buf_size, build_data *bd, unsigned char geom_for_blocktype[256], unsigned char tex1_for_blocktype[256][6])
{
   int a,b,z;

   stbvox_input_description *map;

   mc->chunk_x = world_to_chunk(world_coord.x);
   mc->chunk_y = world_to_chunk(world_coord.y);

   stbvox_set_input_stride(mm, 18, 66*18);

   map = stbvox_get_input_description(mm);
   map->block_tex1_face = tex1_for_blocktype[0];
   map->block_geometry = geom_for_blocktype[0];
   map->block_vheight = 0;

   //stbvox_reset_buffers(mm);
   stbvox_set_buffer(mm, 0, 0, bd->vertex_build_buffer, buf_size * 16);
   stbvox_set_buffer(mm, 0, 1, bd->face_buffer , buf_size * 4);

   map->blocktype = &bd->segment_blocktype[1][1][1]; // this is (0,0,0), but we need to be able to query off the edges
   map->lighting  = &bd->segment_lighting[1][1][1];
   //map->rotate    = &bd->segment_rotate[1][1][1];

   // fill in the top two rows of the buffer
   for (b=0; b < 66; ++b) {
      for (a=0; a < 66; ++a) {
         bd->segment_blocktype[b][a][16] = 0;
         bd->segment_blocktype[b][a][17] = 0;
         bd->segment_lighting [b][a][16] = 255;
         bd->segment_lighting [b][a][17] = 255;
      }
   }

   z = 256-16;  // @TODO use MAX_Z and Z_SEGMENT_SIZE

   for (; z >= 0; z -= 16)  // @TODO use MAX_Z and Z_SEGMENT_SIZE
   {
      int z0 = z;
      int z1 = z+16;
      if (z1 == 256) z1 = 255;  // @TODO use MAX_Z and Z_SEGMENT_SIZE

      copy_chunk_set_to_segment(chunks, z >> 4, bd);   // @TODO use MAX_Z and Z_SEGMENT_SIZE

      map->blocktype = &bd->segment_blocktype[1][1][1-z];
      map->lighting  = &bd->segment_lighting[1][1][1-z];
      //map->rotate    = &bd->segment_rotate[1][1][1-z];

      stbvox_set_input_range(mm, 0,0,z0, 64,64,z1);
      stbvox_set_default_mesh(mm, 0);
      stbvox_make_mesh(mm);

      // copy the bottom two rows of data up to the top
      for (b=0; b < 66; ++b) {
         for (a=0; a < 66; ++a) {
            bd->segment_blocktype[b][a][16] = bd->segment_blocktype[b][a][0];
            bd->segment_blocktype[b][a][17] = bd->segment_blocktype[b][a][1];
            bd->segment_lighting [b][a][16] = bd->segment_lighting [b][a][0];
            bd->segment_lighting [b][a][17] = bd->segment_lighting [b][a][1];
            //bd->segment_rotate   [b][a][16] = bd->segment_rotate   [b][a][0];
            //bd->segment_rotate   [b][a][17] = bd->segment_rotate   [b][a][1];
         }
      }
   }

   stbvox_set_mesh_coordinates(mm, world_coord.x, world_coord.y, world_coord.z+1);
   stbvox_get_transform(mm, mc->transform);

   stbvox_set_input_range(mm, 0,0,0, 64,64,255);
   stbvox_get_bounds(mm, mc->bounds);

   mc->num_quads = stbvox_get_quad_count(mm, 0);
}

const size_t buf_size = 1024*1024;

void compute_mesh_sizes(mesh_chunk *mc)
{
   mc->vbuf_size = mc->num_quads*4*sizeof(uint32);
   mc->fbuf_size = mc->num_quads*sizeof(uint32);
   mc->total_size = mc->fbuf_size + mc->vbuf_size;
}

void build_mesh(mesh *rm, unsigned char geom_for_blocktype[256], unsigned char tex1_for_blocktype[256][6])
{
   for (int k=0; k < 4; ++k) {
      for (int j=0; j < 4; ++j) {
         int cx = rm->x + (j-1) * CHUNK_SIZE;
         int cy = rm->y + (k-1) * CHUNK_SIZE;
         rm->chunks.chunk[k][j] = generate_chunk(cx, cy);
      }
   }

   rm->state = 1;

   stbvox_mesh_maker mm;
   mesh_chunk *mc;
   vec3i wc = { rm->x, rm->y, 0 };

   mc = malloc(sizeof(*mc));

   memset(mc, 0, sizeof(*mc));

   stbvox_init_mesh_maker(&mm);

   mc->chunk_x = world_to_chunk(rm->x);
   mc->chunk_y = world_to_chunk(rm->y);

   build_data bd;
   bd.vertex_build_buffer = malloc(buf_size * 16);
   bd.face_buffer = malloc(buf_size * 4);

   generate_mesh_for_chunk_set(&mm, mc, wc, &rm->chunks, buf_size, &bd, geom_for_blocktype, tex1_for_blocktype);

   assert(mc->num_quads <= buf_size);

   rm->vertex_build_buffer = malloc(mc->num_quads * 16);
   rm->face_buffer  = malloc(mc->num_quads * 4);

   memcpy(rm->vertex_build_buffer, bd.vertex_build_buffer, mc->num_quads * 16);
   memcpy(rm->face_buffer, bd.face_buffer, mc->num_quads * 4);

   free(bd.vertex_build_buffer);
   free(bd.face_buffer);

   compute_mesh_sizes(mc);

   rm->mc = mc;
}

void free_mesh(mesh *rm)
{
   free(rm->vertex_build_buffer);
   free(rm->face_buffer);
   free(rm->mc);

   for (int k=0; k < 4; ++k) {
      for (int j=0; j < 4; ++j) {
         free(rm->chunks.chunk[k][j]);
      }
   }
}
