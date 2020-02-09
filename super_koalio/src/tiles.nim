import xmlparser, xmltree, streams
from strutils import nil
from os import nil

type
  TiledMap* = object
    width: int
    height: int

proc attrInt(node: XmlNode, name: string): int =
  strutils.parseInt(node.attr(name))

proc loadTiledMap*(path: string): TiledMap =
  let
    rawTiledMap = staticRead(path)
    map = rawTiledMap.newStringStream().parseXml()
    mapWidth = map.attrInt("width")
    mapHeight = map.attrInt("height")
    tileset = map.findAll("tileset")[0]
    tileWidth = tileset.attrInt("tilewidth")
    tileHeight = tileset.attrInt("tileheight")
    layers = map.findAll("layer")
    image = tileset.findAll("image")[0]
    imagePath = os.joinPath(os.parentDir(path), image.attr("source"))
    imageData = staticRead(imagePath)
  TiledMap(
    width: mapWidth,
    height: mapHeight,
  )
