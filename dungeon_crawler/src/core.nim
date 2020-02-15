import nimgl/opengl
from nimgl/glfw import GLFWKey
import stb_image/read as stbi
import paranim/gl, paranim/gl/entities
import pararules
from tiles import nil
import sets, tables
from math import `mod`
from glm import nil
import paranim/math as pmath
import rooms

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float
  Id = enum
    Global, Player
  Attr = enum
    DeltaTime, TotalTime, WindowWidth, WindowHeight,
    WorldWidth, WorldHeight,
    PressedKeys, MouseClick, MouseX, MouseY,
    X, Y, Width, Height,
    XVelocity, YVelocity, XChange, YChange,
    ImageIndex, Direction,
  DirectionName = enum
    West, NorthWest, North, NorthEast,
    East, SouthEast, South, SouthWest,
  IntSet = HashSet[int]

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  WindowWidth: int
  WindowHeight: int
  WorldWidth: float
  WorldHeight: float
  PressedKeys: IntSet
  MouseClick: int
  MouseX: float
  MouseY: float
  X: float
  Y: float
  Width: float
  Height: float
  XVelocity: float
  YVelocity: float
  XChange: float
  YChange: float
  ImageIndex: int
  Direction: DirectionName

const
  charTileCount = 8 # number of rows and columns in a character's spritesheet
  charTileSize = 256 # the width and height of a given tile in a character's spritesheet
  verticalTiles = 7 # number of tiles that span the height of the screen
  rawPlayerImage = staticRead("assets/characters/male_light.png")
  tiledMap = tiles.loadTiledMap("assets/level1.tmx")
  deceleration = 0.9
  damping = 0.5
  maxVelocity = 4f
  animationSecs = 0.2
  velocities = {(-1, 0): West, (-1, -1): NorthWest,
                (0, -1): North, (1, -1): NorthEast,
                (1, 0): East, (1, 1): SouthEast,
                (0, 1): South, (-1, 1): SouthWest}.toTable

var
  imageEntities: array[5, ImageEntity]
  tiledMapEntity: InstancedImageEntity
  orderedTiles: seq[tuple[layerName: string, x: int, y: int]]
  wallLayer = tiledMap.layers["walls"]
  playerImages: array[charTileCount, array[charTileCount, ImageEntity]]

proc decelerate(velocity: float): float =
  let v = velocity * deceleration
  if abs(v) < damping: 0f else: v

proc hitTile(x: int, y: int) =
  # make a blank image
  var e = initImageEntity([], 0, 0)
  e.crop(0f, 0f, 0f, 0f)
  # make the correct tile disappear
  let tile = orderedTiles.find((layerName: "walls", x: x, y: y))
  tiledMapEntity[tile] = e
  # remove the tile from hit detection
  wallLayer[x][y] = -1

# http://clintbellanger.net/articles/isometric_math/

const
  tileWidthHalf = 1 / 2
  tileHeightHalf = 1 / 4

proc isometricToScreen(x: float, y: float): tuple[x: float, y: float] =
  (x: (x - y) * tileWidthHalf,
   y: (x + y) * tileHeightHalf)

proc screenToIsometric(x: float, y: float): tuple[x: float, y: float] =
  (x: ((x / tileWidthHalf) + (y / tileHeightHalf)) / 2,
   y: ((y / tileHeightHalf) - (x / tileWidthHalf)) / 2)

let rules =
  ruleset:
    # getters
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
      then:
        let tileSize = windowHeight / verticalTiles
        session.insert(Global, WorldWidth, float(windowWidth) / tileSize)
        session.insert(Global, WorldHeight, float(windowHeight) / tileSize)
    rule getWorld(Fact):
      what:
        (Global, WorldWidth, worldWidth)
        (Global, WorldHeight, worldHeight)
    rule getKeys(Fact):
      what:
        (Global, PressedKeys, keys)
    rule getPlayer(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
        (Player, Width, width)
        (Player, Height, height)
        (Player, Direction, direction)
        (Player, ImageIndex, imageIndex)
    # move the player's x,y position and animate
    rule movePlayer(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, PressedKeys, keys, then = false)
        (Player, X, x, then = false)
        (Player, Y, y, then = false)
        (Player, XVelocity, xv, then = false)
        (Player, YVelocity, yv, then = false)
      then:
        xv =
          if keys.contains(int(GLFWKey.Left)):
            -1 * maxVelocity
          elif keys.contains(int(GLFWKey.Right)):
            maxVelocity
          else:
            xv
        yv =
          if keys.contains(int(GLFWKey.Up)):
            -1 * maxVelocity
          elif keys.contains(int(GLFWKey.Down)):
            maxVelocity
          else:
            yv
        let xChange = xv * dt
        let yChange = yv * dt
        session.insert(Player, XVelocity, decelerate(xv))
        session.insert(Player, YVelocity, decelerate(yv))
        session.insert(Player, XChange, xChange)
        session.insert(Player, YChange, yChange)
        session.insert(Player, X, x + xChange)
        session.insert(Player, Y, y + yChange)
    rule animate(Fact):
      what:
        (Global, TotalTime, tt)
        (Player, XVelocity, xv)
        (Player, YVelocity, yv)
      cond:
        xv != 0 or yv != 0
      then:
        let
          cycleTime = tt mod (animationSecs * 4)
          index = int(cycleTime / animationSecs)
        session.insert(Player, ImageIndex, index)
    rule updateDirection(Fact):
      what:
        (Player, XVelocity, xv)
        (Player, YVelocity, yv)
      cond:
        xv != 0 or yv != 0
      then:
        let v = (math.sgn(xv), math.sgn(yv))
        session.insert(Player, Direction, velocities[v])
    # prevent going through walls
    rule preventMoveX(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
        (Player, Width, width)
        (Player, Height, height)
        (Player, XChange, xChange, then = false)
        (Player, YChange, yChange, then = false)
      cond:
        xChange != 0
      then:
        let
          oldX = x - xChange
          oldY = y - yChange
          (horizX, horizY) = screenToIsometric(x, oldY)
          horizTile = tiles.touchingTile(wallLayer, horizX, horizY, width, height)
        if horizTile != (-1, -1):
          session.insert(Player, X, oldX)
          session.insert(Player, XChange, 0f)
          session.insert(Player, XVelocity, 0f)
    rule preventMoveY(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
        (Player, Width, width)
        (Player, Height, height)
        (Player, XChange, xChange, then = false)
        (Player, YChange, yChange, then = false)
      cond:
        yChange != 0
      then:
        let
          oldX = x - xChange
          oldY = y - yChange
          (vertX, vertY) = screenToIsometric(oldX, y)
          vertTile = tiles.touchingTile(wallLayer, vertX, vertY, width, height)
        if vertTile != (-1, -1):
          session.insert(Player, Y, oldY)
          session.insert(Player, YChange, 0f)
          session.insert(Player, YVelocity, 0f)

var session = initSession(Fact)

for r in rules.fields:
  session.add(r)

proc keyPressed*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)

proc keyReleased*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)

proc mouseClicked*(button: int) =
  session.insert(Global, MouseClick, button)

proc mouseMoved*(xpos: float, ypos: float) =
  session.insert(Global, MouseX, xpos)
  session.insert(Global, MouseY, ypos)

proc windowResized*(width: int, height: int) =
  if width == 0 or height == 0:
    return
  session.insert(Global, WindowWidth, width)
  session.insert(Global, WindowHeight, height)

proc createGrid(image: ImageEntity, count: static[int], tileSize: int, maskSize: int): array[count, array[count, ImageEntity]] =
  let offset = (tileSize - maskSize) / 2
  for y in 0 ..< count:
    for x in 0 ..< count:
      result[x][y] = image
      result[x][y].crop(float(x * tileSize) + offset, float(y * tileSize) + offset, maskSize.float, maskSize.float)

proc init*(game: var Game) =
  # opengl
  doAssert glInit()
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # load image
  var playerImage: ImageEntity
  block:
    var
      width, height, channels: int
      data: seq[uint8]
    data = stbi.loadFromMemory(cast[seq[uint8]](rawPlayerImage), width, height, channels, stbi.RGBA)
    let uncompiledImage = initImageEntity(data, width, height)
    playerImage = compile(game, uncompiledImage)

  # load tiled map
  block:
    # load tileset image
    var
      width, height, channels: int
      data: seq[uint8]
    data = stbi.loadFromMemory(cast[seq[uint8]](tiledMap.tileset.data), width, height, channels, stbi.RGBA)
    # create an entity for each tile
    let
      uncompiledImage = initImageEntity(data, width, height)
      tileWidth = tiledMap.tileset.tileWidth
      tileHeight = tiledMap.tileset.tileHeight
    var images = newSeq[UncompiledImageEntity]()
    for y in 0 ..< int(height / tileHeight):
      for x in 0 ..< int(width / tileWidth):
        var imageEntity = uncompiledImage
        imageEntity.crop(float(x * tileWidth), float(y * tileHeight), float(tileWidth), float(tileHeight))
        images.add(imageEntity)
    # create an instanced entity containing all the tiles
    var uncompiledTiledMap = initInstancedEntity(uncompiledImage)
    for layerName in ["walls"]:
      let layerData = tiledMap.layers[layerName]
      for x in 0 ..< layerData.len:
        for y in 0 ..< layerData[x].len:
          let imageId = layerData[x][y]
          if imageId >= 0:
            var image = images[imageId]
            let (screenX, screenY) = isometricToScreen(float(x), float(y))
            image.translate(screenX, screenY)
            uncompiledTiledMap.add(image)
            orderedTiles.add((layerName: layerName, x: x, y: y))
    tiledMapEntity = compile(game, uncompiledTiledMap)

  # connect rooms in the tiled map
  let tilesToHit = connectRooms((0, 0))
  for tile in tilesToHit:
    if wallLayer[tile.x][tile.y] != -1:
      hitTile(tile.x, tile.y)

  # init global values
  session.insert(Global, PressedKeys, initHashSet[int]())

  # init player
  let maskSize = 128
  playerImages = createGrid(playerImage, charTileCount, charTileSize, maskSize)
  let (x, y) = isometricToScreen(5, 5)
  session.insert(Player, X, x)
  session.insert(Player, Y, y)
  session.insert(Player, Width, maskSize / charTileSize)
  session.insert(Player, Height, maskSize / charTileSize)
  session.insert(Player, XVelocity, 0f)
  session.insert(Player, YVelocity, 0f)
  session.insert(Player, ImageIndex, 0)
  session.insert(Player, Direction, South)

proc tick*(game: Game) =
  # update and query the session
  session.insert(Global, DeltaTime, game.deltaTime)
  session.insert(Global, TotalTime, game.totalTime)
  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (worldWidth, worldHeight) = session.query(rules.getWorld)
  let player = session.query(rules.getPlayer)

  # clear the frame
  glClearColor(150/255, 150/255, 150/255, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))

  # make the camera follow the player
  var camera = glm.mat3f(1)
  camera.translate(player.x - worldWidth / 2, player.y - worldHeight / 2)

  # render the tiled map
  var tiledMapEntity = tiledMapEntity
  tiledMapEntity.project(worldWidth, worldHeight)
  tiledMapEntity.invert(camera)
  render(game, tiledMapEntity)

  # render the player
  var image = playerImages[player.imageIndex.ord][player.direction.ord]
  image.project(worldWidth, worldHeight)
  image.invert(camera)
  image.translate(player.x, player.y)
  image.scale(player.width, player.height)
  render(game, image)

