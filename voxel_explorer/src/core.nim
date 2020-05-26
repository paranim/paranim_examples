import nimgl/opengl
from nimgl/glfw import GLFWKey
import paranim/gl, paranim/gl/entities
import pararules
import sets, tables
import bitops
from voxels import VoxelEntity
from mesh_builder import nil
import texture_loader
import stb_image/read as stbi
import glm
import paranim/math as pmath
from math import nil

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float
  Id = enum
    Global
  Attr = enum
    DeltaTime, TotalTime, WindowWidth, WindowHeight,
    PressedKeys, MouseClick, MouseX, MouseY,
    CameraX, CameraY, CameraTargetX, CameraTargetY,
    UpdateVoxelProc,
  IntSet = HashSet[int]
  XYProc = proc (x: int, y: int)

schema Fact(Id, Attr):
  DeltaTime: float
  TotalTime: float
  WindowWidth: int
  WindowHeight: int
  PressedKeys: IntSet
  MouseClick: int
  MouseX: float
  MouseY: float
  CameraX: float
  CameraY: float
  CameraTargetX: float
  CameraTargetY: float
  UpdateVoxelProc: XYProc

const
  rawImages = [
                staticRead("assets/png/ground/Bowling_grass_pxr128.png"),
                staticRead("assets/png/ground/Dirt_and_gravel_pxr128.png"),
                staticRead("assets/png/ground/Lawn_grass_pxr128.png"),
                staticRead("assets/png/ground/Street_asphalt_pxr128.png"),
                staticRead("assets/png/siding/Vertical_redwood_pxr128.png"),
                staticRead("assets/png/stone/Buffed_marble_pxr128.png"),
                staticRead("assets/png/stone/Gray_granite_pxr128.png"),
                staticRead("assets/png/ground/Beach_sand_pxr128.png"),
              ]

var
  faceUnit: GLint
  voxelUnit: GLint
  voxelEntities: seq[VoxelEntity]

proc updateVoxelEntities*(game: var Game) =
  for mesh in mesh_builder.meshes.mvalues:
    if mesh.state != mesh_builder.Generated or mesh.mc.num_quads == 0:
      continue
    var e = compile(game, voxels.initVoxelEntity(mesh, faceUnit, voxelUnit))
    mesh.mc.vbuf = e.attributes.attr_vertex.buffer
    mesh.mc.fbuf = e.attributes.texture.buffer
    mesh.mc.fbuf_tex = e.attributes.texture.textureNum
    mesh.state = mesh_builder.Rendered
    voxelEntities.add(e)

let rules =
  ruleset:
    # getters
    rule getWindow(Fact):
      what:
        (Global, WindowWidth, windowWidth)
        (Global, WindowHeight, windowHeight)
    rule getKeys(Fact):
      what:
        (Global, PressedKeys, keys)
    rule getCamera(Fact):
      what:
        (Global, CameraX, x)
        (Global, CameraY, y)
    # move camera target
    rule moveCameraTarget(Fact):
      what:
        (Global, UpdateVoxelProc, updateVoxels)
        (Global, CameraTargetX, x, then = false)
        (Global, CameraTargetY, y, then = false)
        (Global, PressedKeys, keys)
      then:
        updateVoxels(x.int, y.int)
        const cameraStep = 50.0
        if keys.contains(GLFWKey.Up.ord) or keys.contains(GLFWKey.W.ord):
          session.insert(Global, CameraTargetY, y + cameraStep)
        elif keys.contains(GLFWKey.Down.ord) or keys.contains(GLFWKey.S.ord):
          session.insert(Global, CameraTargetY, y - cameraStep)
        if keys.contains(GLFWKey.Right.ord) or keys.contains(GLFWKey.D.ord):
          session.insert(Global, CameraTargetX, x + cameraStep)
        elif keys.contains(GLFWKey.Left.ord) or keys.contains(GLFWKey.A.ord):
          session.insert(Global, CameraTargetX, x - cameraStep)
    # move camera (this causes the camera to move smoothly)
    rule moveCamera(Fact):
      what:
        (Global, DeltaTime, dt)
        (Global, CameraTargetX, tx)
        (Global, CameraTargetY, ty)
        (Global, CameraX, x, then = false)
        (Global, CameraY, y, then = false)
      cond:
        tx != x or ty != y
      then:
        const
          speed = 10.0
          minDiff = 0.01
        let
          xDiff = tx - x
          yDiff = ty - y
          newX = if abs(xDiff) < minDiff: tx else: x + (xDiff * dt * speed)
          newY = if abs(yDiff) < minDiff: ty else: y + (yDiff * dt * speed)
        session.insert(Global, CameraX, newX)
        session.insert(Global, CameraY, newY)

var session = initSession(Fact)

for r in rules.fields:
  session.add(r)

proc onKeyPress*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)

proc onKeyRelease*(key: int) =
  var (keys) = session.query(rules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)

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

proc init*(game: var Game, updateVoxels: proc (x: int, y: int)) =
  doAssert glInit()

  faceUnit = game.texCount.GLint
  game.texCount += 1

  var voxelTex: GLuint
  voxelUnit = game.texCount.GLint
  game.texCount += 1

  glGenTextures(1, voxelTex.addr)
  glActiveTexture(GLenum(GL_TEXTURE0.ord + voxelUnit))
  glBindTexture(GL_TEXTURE_2D_ARRAY, voxelTex)
  glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT.ord)
  glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT.ord)
  glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR.ord)
  glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR.ord)
  for i in 0 ..< 11:
    glTexImage3D(GL_TEXTURE_2D_ARRAY, i.GLint, GL_RGBA.ord,
      (512 shr i).GLsizei, (512 shr i).GLsizei, 128.GLsizei, 0.GLint,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)
  for i in 0 ..< rawImages.len:
    var
      width, height, channels: int
      data: seq[uint8]
    data = stbi.loadFromMemory(cast[seq[uint8]](rawImages[i]), width, height, channels, stbi.RGBA)
    load_bitmap_to_texture_array(i.cint, data, width.cint, height.cint, true, false)

  mesh_builder.init()

  # set initial values
  session.insert(Global, PressedKeys, initHashSet[int]())
  session.insert(Global, CameraX, 0f)
  session.insert(Global, CameraY, 0f)
  session.insert(Global, CameraTargetX, 0f)
  session.insert(Global, CameraTargetY, 0f)
  session.insert(Global, UpdateVoxelProc, updateVoxels)

func degToRad(angle: float): float =
  (angle * math.PI) / 180.0

proc tick*(game: Game) =
  session.insert(Global, DeltaTime, game.deltaTime)
  session.insert(Global, TotalTime, game.totalTime)

  let (windowWidth, windowHeight) = session.query(rules.getWindow)
  let (cameraX, cameraY) = session.query(rules.getCamera)

  glEnable(GL_CULL_FACE)
  glDisable(GL_TEXTURE_2D)
  glDisable(GL_LIGHTING)
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_GREATER)
  glClearDepth(0)
  glDepthMask(true)
  glDisable(GL_SCISSOR_TEST)
  glClearColor(0.6f, 0.7f, 0.9f, 0.0f)
  glClear(GLbitfield(bitor(GL_COLOR_BUFFER_BIT.ord, GL_DEPTH_BUFFER_BIT.ord)))

  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glColor3f(1, 1, 1)
  glFrontFace(GL_CW)
  glEnable(GL_TEXTURE_2D)
  glDisable(GL_BLEND)
  glEnable(GL_ALPHA_TEST)
  glAlphaFunc(GL_GREATER, 0.5)

  glViewport(0, 0, int32(windowWidth), int32(windowHeight))

  var camera = mat4f(1)
  camera.translate(cameraX, cameraY, 80f)
  camera.rotateX(degToRad(45))

  for voxelEntity in voxelEntities:
    var e = voxelEntity
    e.uniforms.model_view.disable = false
    e.uniforms.model_view.data.project(degToRad(60), float(windowWidth) / float(windowHeight), 3000f, 1f/16f)
    e.uniforms.model_view.data.invert(camera)
    render(game, e)

  # for paravim
  glDisable(GL_DEPTH_TEST)
  glEnable(GL_BLEND)
  glDisable(GL_ALPHA_TEST)

