require daslib/media
require daslib/decs
require daslib/decs_boost
require daslib/debug
options indenting = 2
options debugger

let WORLD_SIZE = 2048.0
let HERO_MOVE_SPEED = 128.0
let HERO_SCALE = 2.0
let CENTER_SAFE_ZONE = 50.0

let DEBUG_COLLISION = false

/***** Globals *****/

let world_center = float2(WORLD_SIZE / 2.0, WORLD_SIZE / 2.0)
var rand_seed : int4
let hero_action_offset = float2(7, -11)
let hero_action_dist = float2(8, 6)

var g_images : array<Image>

var ecs_dt : float
var ecs_time : float

enum WorldObjectId : int
  hero_stand = 0
  hero_stand_flip = 1
  hero_walk = 2
  hero_walk_flip = 3
  hero_action = 4
  hero_action_flip = 5
  fir = 6
  oak = 7
  bush = 8

struct WorldObject
  image_path : string
  image_transparent : bool
  image_flip : bool
  image_idx : int
  collision_size : int2

var g_world_objects = [[WorldObject[]
  [[WorldObject image_path="assets/hero_stand.png", image_transparent=true, collision_size=int2(4, 8)]];
  [[WorldObject image_path="assets/hero_stand.png", image_transparent=true, collision_size=int2(4, 8), image_flip=true]];
  [[WorldObject image_path="assets/hero_walk.png", image_transparent=true, collision_size=int2(4, 8)]];
  [[WorldObject image_path="assets/hero_walk.png", image_transparent=true, collision_size=int2(4, 8), image_flip=true]];
  [[WorldObject image_path="assets/hero_action.png", image_transparent=true, collision_size=int2(4, 8)]];
  [[WorldObject image_path="assets/hero_action.png", image_transparent=true, collision_size=int2(4, 8), image_flip=true]];
  [[WorldObject image_path="assets/tree1.png", image_transparent=true, collision_size=int2(20, 14)]];
  [[WorldObject image_path="assets/tree2.png", image_transparent=true, collision_size=int2(4, 8)]];
  [[WorldObject image_path="assets/bush1.png", image_transparent=true, collision_size=int2(11, 8)]]
]]


/***** Templates *****/

[decs_template]
struct Input
  up : bool
  down : bool
  left : bool
  right : bool
  space : bool

[decs_template]
struct Phys
  lastUpdate : float
  updateInterval : float
  moveSpeed : float
  isMoving : bool

[decs_template]
struct Rect
  min, max : float2


/***** Utils *****/

def random_int(min, max : int) : int
  return min + random_int(rand_seed) % (max - min + 1)


def random_float(min, max : float) : float
  return min + random_float(rand_seed) * (max - min)


def load_image(path : string; transparent, flip_x : bool = false) : int
  var img <- create_image(path)
  if transparent
    img |> make_image_color_transparent(get_pixel(img, 0, 0))
  if flip_x
    img |> flip_image_x()
  g_images |> emplace(img)
  return length(g_images) - 1


def load_resources()
  for obj in g_world_objects
    obj.image_idx = load_image(obj.image_path, obj.image_transparent, obj.image_flip)


def draw_resource(image : Image; size : float2; pos : float2)
  draw_image(image, pos.x - size.x / 2.0, pos.y - size.y, 0xFFFFFFFFu, size)


def calc_collision(pos : float2; local_collision : int2; scale : float) : Rect
  var ret : Rect
  let scaled = float2(local_collision) * scale
  ret.min = float2(pos.x - scaled.x, pos.y - scaled.y)
  ret.max = float2(pos.x + scaled.x, pos.y)
  return ret


def check_overlap(r1, r2 : Rect)
  return !((r2.max.x <= r1.min.x) || (r2.min.x >= r1.max.x) || (r2.max.y <= r1.min.y) || (r2.min.y >= r1.max.y))


def is_in_world(pos : float2)
  return pos.x >= 0.0 && pos.x < WORLD_SIZE && pos.y >= 0.0 && pos.y < WORLD_SIZE


def is_in_world(collision : Rect)
  return is_in_world(collision.min) && is_in_world(collision.max)


def is_free_pos(coll : Rect; ignore_eid : EntityId implicit) : bool
  if !is_in_world(coll)
    return false
  var ret = true
  find_query() <| $ (eid : EntityId; collision : Rect)
    if eid != ignore_eid && check_overlap(coll, [[Rect min=collision.min, max=collision.max]])
      ret = false
      return true
  return ret


def gen_world_object(obj_id : int; scale, hp : float; wood_count : int; region : Rect)
  var pos : float2
  var coll : Rect
  for i in range (0, 5)
    pos = float2(random_float(region.min.x, region.max.x), random_float(region.min.y, region.max.y))
    coll = calc_collision(pos, g_world_objects[obj_id].collision_size, scale)
    if abs(world_center.x - pos.x) < CENTER_SAFE_ZONE || abs(world_center.y - pos.y) < CENTER_SAFE_ZONE
      continue 
    if is_free_pos(coll, INVALID_ENTITY_ID)
      break

  create_entity <| @ (eid, cmp)
    cmp |> set("pos", pos)
    cmp |> set("image_idx", g_world_objects[obj_id].image_idx)
    cmp |> set("scale", scale)
    cmp |> set("hp", hp)
    cmp |> set("wood_count", wood_count)
    apply_decs_template(cmp, [[Rect coll]])

  commit()


def game_start()
  // Hero
  create_entity <| @ (eid, cmp)
    cmp |> set("pos", world_center)
    cmp |> set("image_idx", -1)
    cmp |> set("scale", HERO_SCALE)
    cmp |> set("damage", 5.0)
    cmp |> set("hero_flipped", false)
    cmp |> set("hero_state", WorldObjectId hero_stand)
    cmp |> set("hero_interacting", false)
    cmp |> set("inventory_wood", 0)
    apply_decs_template(cmp, [[Input]])
    apply_decs_template(cmp, [[Phys
      updateInterval = 0.03,
      moveSpeed = HERO_MOVE_SPEED
    ]])
    apply_decs_template(cmp, [[Rect
      calc_collision(world_center, g_world_objects[int(WorldObjectId hero_stand)].collision_size, HERO_SCALE)
    ]])

  // Camera
  create_entity <| @ (eid, cmp)
    cmp |> set("pos", world_center)
    cmp |> set("camera_active", true)
    cmp |> set("camera_scale", 1.25)
    cmp |> set("camera_scale_min", 0.75)
    cmp |> set("camera_scale_max", 2.5)
    cmp |> set("camera_scale_mult", 8.0)
    cmp |> set("camera_hero_padding", 128.0)

  let worldRect = [[Rect min=float2(), max=float2(WORLD_SIZE, WORLD_SIZE)]]

  // Generate trees
  for i in range(0, 200)
    let treeType = (random_int(rand_seed) % 2) != 0 ? int(WorldObjectId fir) : int(WorldObjectId oak)
    let scale = 1.4 + 0.75 * random_float(rand_seed)
    gen_world_object(treeType, scale, 12.0, 5, worldRect)

  // Generate bushes
  for i in range(0, 100)
    let scale = 1.4 + 0.5 * random_float(rand_seed)
    gen_world_object(int(WorldObjectId bush), scale, 5.0, 2, worldRect)


/***** Export *****/

[export]
def initialize
  set_window_title("Survival")
  randomize_seed(rand_seed)
  load_resources()
  game_start()


[export]
def act(dt : float)
  if get_key(VK_ESCAPE)
    schedule_quit_game()

  ecs_dt = dt
  ecs_time += dt

  decs_stage("input")
  decs_stage("update")


[export]
def draw
  decs_stage("draw")


/***** Entity systems *****/

[decs (stage=input)]
def hero_input_es(var input : Input)
  input.up = get_key(VK_UP) || get_key(VK_W)
  input.down = get_key(VK_DOWN) || get_key(VK_S)
  input.left = get_key(VK_LEFT) || get_key(VK_A)
  input.right = get_key(VK_RIGHT) || get_key(VK_D)
  input.space = get_key(VK_SPACE)


[decs (stage=input)]
def camera_input_es(var camera_scale : float&; camera_scale_min : float = 1.0; camera_scale_max : float = 2.0; camera_scale_mult : float = 8.0)
  camera_scale += get_mouse_scroll_delta() * camera_scale_mult * ecs_dt
  camera_scale = clamp(camera_scale, camera_scale_min, camera_scale_max)


[decs (stage=update)]
def hero_anim_es(input : Input; var image_idx : int&; var hero_flipped : bool&; var hero_state : WorldObjectId&)
  var moving_anim = false
  var action_anim = false
  let anim_rnd = (int(ecs_time * 7.0) & 1) != 0
  if input.left
    hero_flipped = true
  if input.right
    hero_flipped = false
  if (input.up ^^ input.down) || (input.left ^^ input.right)
    moving_anim = anim_rnd
  elif input.space
    action_anim = anim_rnd

  if moving_anim
    hero_state = hero_flipped ? WorldObjectId hero_walk_flip : WorldObjectId hero_walk
  elif action_anim
    hero_state = hero_flipped ? WorldObjectId hero_action_flip : WorldObjectId hero_action
  else
    hero_state = hero_flipped ? WorldObjectId hero_stand_flip : WorldObjectId hero_stand
  image_idx = g_world_objects[int(hero_state)].image_idx


[decs (stage=update)]
def hero_phys_es(eid : EntityId;
             var phys : Phys;
             var pos : float2&;
             var collision : Rect&;
                 scale : float;
                 input : Input)
  let dt = ecs_time - phys.lastUpdate
  if dt < phys.updateInterval
    return
  phys.lastUpdate = ecs_time

  let moveDir = float2((input.left ? -1.0 : 0.0) + (input.right ? 1.0 : 0.0),
                       (input.up ? -1.0 : 0.0) + (input.down ? 1.0 : 0.0))
  var moveSpeed = phys.moveSpeed
  if moveDir.x != 0.0 && moveDir.y != 0.0
    moveSpeed /= sqrt(2.0)
  let moveOffset = moveDir * moveSpeed * dt
  let stepsCount = int(max(abs(moveOffset.x), abs(moveOffset.y)))
  if stepsCount > 0
    let step = moveOffset / float(stepsCount)
    for i in range(0, stepsCount)
      let newPos = pos + step
      let newColl <- [[Rect min=collision.min + step, max=collision.max + step]]
      if is_free_pos(newColl, eid)
        pos = newPos
        collision.min = newColl.min
        collision.max = newColl.max


[decs (stage=update, after=hero_anim_es)]
def hero_action_es(eid : EntityId; hero_state : WorldObjectId; pos : float2; scale : float; hero_flipped : bool; damage : float; var inventory_wood : int&; var hero_interacting : bool&)
  hero_interacting = false
  if hero_state != WorldObjectId hero_action && hero_state != WorldObjectId hero_action_flip
    return
  let heroEid = eid
  let actionPos = pos + hero_action_offset * scale * float2(hero_flipped ? -1.0 : 1.0, 1.0)
  find_query() <| $ (eid : EntityId; collision : Rect)
    if eid != heroEid
      let interactZone = [[Rect min=collision.min - hero_action_dist, max=collision.max + hero_action_dist]]
      if actionPos.x > interactZone.min.x && actionPos.y > interactZone.min.y && actionPos.x < interactZone.max.x && actionPos.y < interactZone.max.y
        hero_interacting = true
        query(eid) <| $ (var hp : float&; wood_count : int)
          hp -= damage * ecs_dt
          if hp < 0.0
            inventory_wood += wood_count
            delete_entity(eid)
        return true


[decs (stage=update, after=hero_phys_es)]
def hero_camera_es(var pos : float2&; camera_active : bool; camera_scale : float; camera_hero_padding : float)
  if !camera_active
    return
  var cameraPos & = pos
  find_query() <| $ [REQUIRE(Input_up)] (pos : float2)
    var offset = cameraPos - pos
    let halfScreen = float2(get_screen_width() / 2, get_screen_height() / 2)
    let maxOffset = (halfScreen - float2(camera_hero_padding)) / camera_scale
    offset = min(offset, maxOffset)
    offset = max(offset, -maxOffset)
    cameraPos = pos + offset
    return true


[decs (stage=draw)]
def draw_world_es(pos : float2; camera_active : bool; camera_scale : float)
  if !camera_active
    return

  let screenWidth = get_screen_width()
  let screenHeight = get_screen_height()
  let halfScreenWidth = float(screenWidth / 2) / camera_scale
  let halfScreenHeight = float(screenHeight / 2) / camera_scale
  let cameraPos = pos

  fill_rect(0, 0, screenWidth, screenHeight, 0xFF2778D4)
  setup_2d_camera(cameraPos, camera_scale)
  fill_rect(0.0, 0.0, WORLD_SIZE, WORLD_SIZE, 0xFF18810F)

  var screenObjects : array<tuple<pos : float2; idx : int; size : float2>>
  query() <| $ (pos : float2; image_idx : int; scale : float)
    if image_idx == -1
      return
    let image & = g_images[image_idx]
    let imageSize = float2(image.width, image.height) * scale
    let offset = cameraPos - pos
    if abs(offset.x) - imageSize.x / 2.0 > halfScreenWidth
      return
    if abs(offset.y + (offset.y < 0.0 ? imageSize.y : 0.0)) > halfScreenHeight
      return
    screenObjects |> emplace([[auto pos, image_idx, imageSize]])

  screenObjects |> sort() <| $ (lhs, rhs)
    return lhs.pos.y < rhs.pos.y

  // World
  enable_alpha_blend()

  for obj in screenObjects
    draw_resource(g_images[obj.idx], obj.size, obj.pos)

  find_query() <| $ [REQUIRE(Input_up)] (hero_interacting : bool; pos : float2; scale: float; hero_flipped : bool)
    if hero_interacting
      let actionPos = pos + hero_action_offset * scale * float2(hero_flipped ? -1.0 : 1.0, 1.0)
      circle(actionPos.x, actionPos.y, 5.5, 0xFF6E0E7A)
      circle(actionPos.x, actionPos.y, 5.0, 0xFFCFC31E)
    return true

  if DEBUG_COLLISION
    query() <| $ (pos : float2; collision : Rect)
      rect(collision.min.x, collision.min.y, collision.max.x - collision.min.x, collision.max.y - collision.min.y, 0xFFA50505)

  disable_alpha_blend()

  // UI
  transform2d_reset()

  text_out(10, 10, "cam pos {int2(pos)}", 0xF0F0F0)
  text_out(240, 10, "fps {int(1.0 / ecs_dt)}", 0xF0F0F0)

  find_query() <| $ [REQUIRE(Input_up)] (pos : float2; inventory_wood : int)
    text_out(10, 30, "hero pos {int2(pos)}", 0xF0F0F0)
    text_out(240, 30, "wood {inventory_wood}", 0xF0F0F0)
    return true
