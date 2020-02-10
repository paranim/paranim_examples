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

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float
    imageEntities: array[5, ImageEntity]
    tiledMapEntity: InstancedImageEntity

const
  rawImage = staticRead("assets/koalio.png")
  tiledMap = tiles.loadTiledMap("assets/level1.tmx")
  wallLayer = tiledMap.layers["walls"]
  gravity = 3
  deceleration = 0.8
  damping = 0.1
  maxVelocity = 12f
  maxJumpVelocity = float(maxVelocity * 8)
  animationSecs = 0.2
  koalaWidth = 18f
  koalaHeight = 26f

type
  Id = enum
    Global, Player
  Attr = enum
    DeltaTime, TotalTime, WindowWidth, WindowHeight,
    WorldWidth, WorldHeight,
    PressedKeys, MouseClick, MousePosition,
    X, Y, Width, Height,
    XVelocity, YVelocity, XChange, YChange,
    CanJump, ImageIndex, Direction,
  DirectionName = enum
    Left, Right
  IntSet = HashSet[int]
  XYTuple = tuple[x: float, y: float]

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  WindowWidth: int
  WindowHeight: int
  WorldWidth: float
  WorldHeight: float
  PressedKeys: IntSet
  MouseClick: int
  MousePosition: XYTuple
  X: float
  Y: float
  Width: float
  Height: float
  XVelocity: float
  YVelocity: float
  XChange: float
  YChange: float
  CanJump: bool
  ImageIndex: int
  Direction: DirectionName

proc decelerate(velocity: float): float =
  let v = velocity * deceleration
  if abs(v) < damping: 0f else: v

let rules =
  ruleset:
    # getters
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
      then:
        let tileSize = windowHeight / tiledMap.height
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
        (Player, ImageIndex, imageIndex)
        (Player, Direction, direction)
    # perform jumping
    rule doJump(Fact):
      what:
        (Global, PressedKeys, keys)
        (Player, CanJump, canJump, then = false)
      cond:
        keys.contains(int(GLFWKey.Up))
        canJump
      then:
        session.insert(Player, CanJump, false)
        session.insert(Player, YVelocity, -1 * maxJumpVelocity)
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
        yv = yv + gravity
        let xChange = xv * dt
        let yChange = yv * dt
        session.insert(Player, XVelocity, decelerate(xv))
        session.insert(Player, YVelocity, decelerate(yv))
        session.insert(Player, XChange, xChange)
        session.insert(Player, YChange, yChange)
        session.insert(Player, X, x + xChange)
        session.insert(Player, Y, y + yChange)
    rule animateStanding(Fact):
      what:
        (Player, XVelocity, xv)
        (Player, YVelocity, yv)
      cond:
        xv == 0
        yv == 0
      then:
        session.insert(Player, ImageIndex, 0)
    rule animateJumping(Fact):
      what:
        (Player, YVelocity, yv)
      cond:
        yv != 0
      then:
        session.insert(Player, ImageIndex, 1)
    rule animateWalking(Fact):
      what:
        (Global, TotalTime, tt)
        (Player, XVelocity, xv)
        (Player, YVelocity, yv)
      cond:
        xv != 0
        yv == 0
      then:
        let
          cycleTime = tt mod (animationSecs * 3)
          index = int(cycleTime / animationSecs)
        session.insert(Player, ImageIndex, index + 2)
    rule updateDirection(Fact):
      what:
        (Player, XVelocity, xv)
      cond:
        xv != 0
      then:
        session.insert(Player, Direction, if xv > 0: Right else: Left)
    # prevent going through walls
    rule preventMove(Fact):
      what:
        (Player, X, x)
        (Player, Y, y)
        (Player, Width, width)
        (Player, Height, height)
        (Player, XChange, xChange, then = false)
        (Player, YChange, yChange, then = false)
      cond:
        xChange != 0 or yChange != 0
      then:
        let
          oldX = x - xChange
          oldY = y - yChange
          horizTile = tiles.touchingTile(wallLayer, x, oldY, width, height)
          vertTile = tiles.touchingTile(wallLayer, oldX, y, width, height)
        if horizTile != (-1, -1):
          session.insert(Player, X, oldX)
          session.insert(Player, XChange, 0f)
          session.insert(Player, XVelocity, 0f)
        if vertTile != (-1, -1):
          session.insert(Player, Y, oldY)
          session.insert(Player, YChange, 0f)
          session.insert(Player, YVelocity, 0f)
          session.insert(Player, CanJump, true)

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
  session.insert(Global, MousePosition, (xpos, ypos))

proc windowResized*(width: int, height: int) =
  session.insert(Global, WindowWidth, width)
  session.insert(Global, WindowHeight, height)

proc init*(game: var Game) =
  # opengl
  doAssert glInit()
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # load image
  block:
    var
      width, height, channels: int
      data: seq[uint8]
    data = stbi.loadFromMemory(cast[seq[uint8]](rawImage), width, height, channels, stbi.RGBA)
    let
      uncompiledImage = initImageEntity(data, width, height)
      image = compile(game, uncompiledImage)
    for i in 0 ..< game.imageEntities.len:
      game.imageEntities[i] = image
      game.imageEntities[i].crop(float(i) * koalaWidth, 0f, koalaWidth, koalaHeight)

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
    for layerName in ["background", "walls"]:
      let layerData = tiledMap.layers[layerName]
      for x in 0 ..< layerData.len:
        for y in 0 ..< layerData[x].len:
          let imageId = layerData[x][y]
          if imageId >= 0:
            var image = images[imageId]
            image.translate(float(x), float(y))
            uncompiledTiledMap.add(image)
    game.tiledMapEntity = compile(game, uncompiledTiledMap)

  # set initial values
  session.insert(Global, PressedKeys, initHashSet[int]())
  session.insert(Player, X, 20f)
  session.insert(Player, Y, 0f)
  session.insert(Player, Width, 1f)
  session.insert(Player, Height, koalaHeight / koalaWidth)
  session.insert(Player, XVelocity, 0f)
  session.insert(Player, YVelocity, 0f)
  session.insert(Player, CanJump, false)
  session.insert(Player, ImageIndex, 0)
  session.insert(Player, Direction, Right)

proc tick*(game: Game) =
  session.insert(Global, DeltaTime, game.deltaTime)
  session.insert(Global, TotalTime, game.totalTime)

  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (worldWidth, worldHeight) = session.query(rules.getWorld)
  let player = session.query(rules.getPlayer)

  glClearColor(173/255, 216/255, 230/255, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))

  var camera = glm.mat3f(1)
  camera.translate(player.x - worldWidth / 2, 0f)

  var tiledMapEntity = game.tiledMapEntity
  tiledMapEntity.project(worldWidth, worldHeight)
  tiledMapEntity.invert(camera)
  render(game, tiledMapEntity)

  let x =
    if player.direction == Right:
      player.x
    else:
      player.x + player.width
  let width =
    if player.direction == Right:
      player.width
    else:
      player.width * -1

  var image = game.imageEntities[player.imageIndex]
  image.project(worldWidth, worldHeight)
  image.invert(camera)
  image.translate(x, player.y)
  image.scale(width, player.height)
  render(game, image)

