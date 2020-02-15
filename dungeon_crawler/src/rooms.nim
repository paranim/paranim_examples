import sets, random

type
  XYTuple = tuple[x: int, y: int]
  Rooms = HashSet[XYTuple]
  Tiles = HashSet[XYTuple]

const
  cols = 4
  rows = 4
  size = 10

proc getSpawnPoints*(): seq[XYTuple] =
  for row in 0 ..< rows:
    for col in 0 ..< cols:
      result.add((row * size, col * size))

proc getRandomNeighbor(rooms: Rooms, room: XYTuple): XYTuple =
  let (x, y) = room
  let possibleRooms = [
    (x, y+1),
    (x, y-1),
    (x+1, y),
    (x-1, y)
  ]
  var neighbors: seq[XYTuple]
  for pr in possibleRooms:
    if rooms.contains(pr):
      neighbors.add(pr)
  if neighbors.len > 0:
    neighbors[rand(neighbors.len-1)]
  else:
    (-1, -1)

proc connectRoom(tiles: var Tiles, room1: XYTuple, room2: XYTuple) =
  let
    randSpot = rand(size - 4) + 1
    xDiff = room2.x - room1.x
    yDiff = room2.y - room1.y
  for i in 0 ..< size:
    let
      x = (room1.x * size) + randSpot + (xDiff * i)
      y = (room1.y * size) + randSpot + (yDiff * i)
    tiles.incl((x, y))
    tiles.incl((x+1, y))
    tiles.incl((x, y+1))
    tiles.incl((x+1, y+1))

proc connectRooms(tiles: var Tiles, rooms: var Rooms, room: XYTuple): XYTuple =
  rooms.excl(room)
  result = getRandomNeighbor(rooms, room)
  if result == (-1, -1):
    return

  connectRoom(tiles, room, result)

proc connectRooms*(room: XYTuple): Tiles =
  var rooms: Rooms
  for row in 0 ..< rows:
    for col in 0 ..< cols:
      rooms.incl((row, col))
  var nextRoom = room
  while true:
    nextRoom = connectRooms(result, rooms, nextRoom)
    if nextRoom == (-1, -1):
      break
