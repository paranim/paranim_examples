import xmlparser, xmltree, streams, tables
from strutils import nil
from os import nil
from base64 import nil

type
  TiledMap* = object
    width*: int
    height*: int
    tileset*: tuple[tileWidth: int, tileHeight: int, data: string]
    layers*: Table[string, seq[seq[int]]]

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
    image = tileset.findAll("image")[0]
    imagePath = os.joinPath(os.parentDir(path), image.attr("source"))
    imageData = staticRead(imagePath)
    layers = map.findAll("layer")
  result.width = mapWidth
  result.height = mapHeight
  result.tileset = (tileWidth, tileHeight, imageData)
  for layer in layers:
    let
      name = layer.attr("name")
      width = layer.attrInt("width")
      height = layer.attrInt("height")
      dataNode = layer.findAll("data")[0]
      encoding = dataNode.attr("encoding")
      compression = dataNode.attr("compression")
    var data = newSeq[seq[int]](width)
    if compression != "":
      raise newException(Exception, "Compression not supported")
    if encoding == "base64":
      let
        binary = base64.decode(dataNode.innerText)
        size = sizeof(uint32)
      for i in 0 ..< int(binary.len / size):
        let
          x = i mod width
          y = int(i / width)
          imageId =
            int(
              (uint8(binary[i*size+3]) shl 24) or
              (uint8(binary[i*size+2]) shl 16) or
              (uint8(binary[i*size+1]) shl 8) or
              uint8(binary[i*size])
            ) - 1 # tile ids are 1-based, so we need to decrement
        if data[x].len == 0:
          data[x] = newSeq[int](height)
        data[x][y] = imageId
    else:
      raise newException(Exception, "Encoding not supported")
    result.layers[name] = data
