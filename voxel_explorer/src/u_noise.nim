{.compile: "u_noise.c".}

##  perlin-style noise: s is a the number of fractional bits in x&y

proc fast_noise*(x: cint; y: cint; s: cint; seed: cint): cint {.cdecl, importc: "fast_noise".}
##  0..65535, randomness in high bits

proc big_noise*(x: cint; y: cint; s: cint; seed: cuint): cint {.cdecl, importc: "big_noise".}
##  0..65535, randomness in high bits, uses 20 bits of seed

proc stb_perlin_noise3*(x: cfloat; y: cfloat; z: cfloat; x_wrap: cint; y_wrap: cint;
                        z_wrap: cint): cfloat {.cdecl, importc: "stb_perlin_noise3".}
##  -1 to 1
##  discrete parametric noise

proc flat_noise32_weak*(x: cint; y: cint; seed: cuint): cuint {.cdecl, importc: "flat_noise32_weak".}
##  all bits random

proc flat_noise32_strong*(x: cint; y: cint; seed: cuint): cuint {.cdecl, importc: "flat_noise32_strong".}
##  all bits random

proc flat_noise8*(x: cint; y: cint; seed: cint): cint {.cdecl, importc: "flat_noise8".}
##  8 random bits

proc stb_sha256_noise*(result: array[8, cuint]; x: cuint; y: cuint; seed1: cuint;
                       seed2: cuint) {.cdecl, importc: "stb_sha256_noise".}
##  256 random bits
