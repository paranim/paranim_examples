import paranim/opengl
from paranim/glfw import GLFWKey
import stb_image/read as stbi
import paranim/gl, paranim/gl/entities
import pararules
from tiles import nil
import sets, tables
from math import `mod`
from paranim/glm import nil
import paranim/math as pmath

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
    CanJump, ImageIndex, Direction,
  DirectionName = enum
    Left, Right
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
  CanJump: bool
  ImageIndex: int
  Direction: DirectionName

const
  rawImage = staticRead("assets/koalio.png")
  tiledMap = tiles.loadTiledMap("assets/level1.tmx")
  gravity = 2.5
  deceleration = 0.9
  damping = 0.5
  maxVelocity = 14f
  maxJumpVelocity = float(maxVelocity * 4)
  animationSecs = 0.2
  koalaWidth = 18f
  koalaHeight = 26f

var
  imageEntities: array[5, ImageEntity]
  tiledMapEntity: InstancedImageEntity
  orderedTiles: seq[tuple[layerName: string, x: int, y: int]]
  wallLayer = tiledMap.layers["walls"]

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

let (initSession, rules) =
  staticRuleset(Fact, FactMatch):
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
        var xvNew =
          if keys.contains(int(GLFWKey.Left)):
            -1 * maxVelocity
          elif keys.contains(int(GLFWKey.Right)):
            maxVelocity
          else:
            xv
        var yvNew = yv + gravity
        let xChange = xvNew * dt
        let yChange = yvNew * dt
        session.insert(Player, XVelocity, decelerate(xvNew))
        session.insert(Player, YVelocity, decelerate(yvNew))
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
          horizTile = tiles.touchingTile(wallLayer, x, oldY, width, height)
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
          vertTile = tiles.touchingTile(wallLayer, oldX, y, width, height)
        if vertTile != (-1, -1):
          session.insert(Player, Y, oldY)
          session.insert(Player, YChange, 0f)
          session.insert(Player, YVelocity, 0f)
          if yChange > 0:
            session.insert(Player, CanJump, true)
          elif yChange < 0:
            hitTile(vertTile.x, vertTile.y)

var session: Session[Fact, FactMatch] = initSession(autoFire = false)
for r in rules.fields:
  session.add(r)

proc onKeyPress*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)
  session.fireRules

proc onKeyRelease*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)
  session.fireRules

proc onMouseClick*(button: int) =
  session.insert(Global, MouseClick, button)

proc onMouseMove*(xpos: float, ypos: float) =
  session.insert(Global, MouseX, xpos)
  session.insert(Global, MouseY, ypos)

proc onWindowResize*(width: int, height: int) =
  if width == 0 or height == 0:
    return
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
    for i in 0 ..< imageEntities.len:
      imageEntities[i] = image
      imageEntities[i].crop(float(i) * koalaWidth, 0f, koalaWidth, koalaHeight)

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
            orderedTiles.add((layerName: layerName, x: x, y: y))
    tiledMapEntity = compile(game, uncompiledTiledMap)

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
  # update and query the session
  session.insert(Global, DeltaTime, game.deltaTime)
  session.insert(Global, TotalTime, game.totalTime)
  session.fireRules

  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (worldWidth, worldHeight) = session.query(rules.getWorld)
  let player = session.query(rules.getPlayer)

  # clear the frame
  glClearColor(173/255, 216/255, 230/255, 1f)
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, int32(windowWidth), int32(windowHeight))

  # make the camera follow the player
  var camera = glm.mat3f(1)
  camera.translate(player.x - worldWidth / 2, 0f)

  # render the tiled map
  var tiledMapEntity = tiledMapEntity
  tiledMapEntity.project(worldWidth, worldHeight)
  tiledMapEntity.invert(camera)
  render(game, tiledMapEntity)

  # get the x and width based on the player's direction
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

  # render the player
  var image = imageEntities[player.imageIndex]
  image.project(worldWidth, worldHeight)
  image.invert(camera)
  image.translate(x, player.y)
  image.scale(width, player.height)
  render(game, image)

