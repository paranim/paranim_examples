# Package

version       = "0.1.0"
author        = "oakes"
description   = "FIXME"
license       = "Public Domain"
srcDir        = "src"
bin           = @["super_koalio"]

task dev, "Run dev version":
  exec "nimble -d:paravim run super_koalio"

# Dependencies

requires "nim >= 1.2.6"
requires "paranim >= 0.11.0"
requires "pararules >= 0.17.0"
requires "stb_image >= 2.5"

# Dev Dependencies

requires "paravim >= 0.18.2"
