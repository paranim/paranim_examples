# Package

version       = "0.1.0"
author        = "oakes"
description   = "FIXME"
license       = "Public Domain"
srcDir        = "src"
bin           = @["voxel_explorer"]

task dev, "Run dev version":
  exec "nimble run voxel_explorer"

# Dependencies

requires "nim >= 1.0.6"
requires "paranim >= 0.9.0"
requires "pararules >= 0.5.0"
requires "stb_image >= 2.5"

# Dev Dependencies

requires "paravim >= 0.16.1"
