module common shared
require ecs
require DagorMathUtils
require strings
require daslib/strings_boost
require daslib/instance_function


[generic]
def get_string(obj; name: string; name_hash: uint; orDefault : string)
  let str = get_ecs_string(obj, name, name_hash)
  return str != null ? string(*str) : orDefault

[generic]
def get_string(obj; orDefault : string)
  let str = get_ecs_string(obj)
  return str != null ? string(*str) : orDefault

[generic]
def find_index(arr : ecs::Array; eid : EntityId) : int
  return find_index_if(each(arr)) <| $ (elem) : bool
    let tryEid = get_Eid(elem)
    assert(tryEid != null, "ecs::Array child type != ecs::EntityId")
    return tryEid != null && *tryEid == eid

[generic]
def find_index(arr : ecs::Array; str : string) : int
  return find_index_if(each(arr)) <| $ (elem) : bool
    let tryStr = get_ecs_string(elem)
    assert(tryStr != null, "ecs::Array child type != ecs::string")
    return tryStr != null && string(*tryStr) == str

[generic]
def has_value(arr : ecs::Array; eid : EntityId) : bool
  return find_index(arr, eid) >= 0

[generic]
def has_value(arr : ecs::Array; str : string) : bool
  return find_index(arr, str) >= 0

[generic]
def find_index(arr, val) : int
  return find_index(each(arr), val)

[generic]
def find_index(arr: StringList; val: string) : int
  for i in iter_range(arr)
    if arr[i] == val
      return i
  return -1


[generic, export]
def list_safe_at(t: VecT implicit; idx: int): ChildT const?#
  if uint(idx) < uint(length(t))
    unsafe
      return reinterpret<ChildT const?#> addr(t.[idx])
  unsafe
    return reinterpret<ChildT const?#> null


[instance_function(list_safe_at, VecT = IntList, ChildT = "int")]
def operator ?[] (t: IntList implicit; idx: int): int const?#
  unsafe
    return reinterpret<int const?#> null

[instance_function(list_safe_at, VecT = FloatList, ChildT = "float")]
def operator ?[] (t: FloatList implicit; idx: int): float const?#
  unsafe
    return reinterpret<float const?#> null

[instance_function(list_safe_at, VecT = BoolList, ChildT = "bool")]
def operator ?[] (t: BoolList implicit; idx: int): bool const?#
  unsafe
    return reinterpret<bool const?#> null

[generic]
def is_point_in_poly(pt : float2; points : ecs::Point2List)
  unsafe
    return is_point_in_poly(pt, data_ptr(points), length(points))

// Returns random float in range [0..1) based on eid value
[generic]
def eid_frnd(eid : EntityId)
  var x = uint(eid)
  // Magic consts taken from https://github.com/skeeto/hash-prospector#discovered-hash-functions
  x ^= x >> 15u
  x *= 0xd168aaadu
  x ^= x >> 15u
  x *= 0xaf723597u
  x ^= x >> 15u
  return float(x & 16777215u) / 16777216.f // float values are int uniform only within low 24 bits


def push_to_array(var ecs_array:Array; b:block<(var data: auto(Type)#):void>)
  using() <| $(var data: Type#)
    invoke(b, data)
    push(ecs_array, data)


def push_to_object(var main_obj:Object implicit; name : string; b:block<(var obj:auto(Type)#):void>)
  using() <| $(var data: Type#)
    invoke(b, data)
    set(main_obj, name, data)


def push_to_initializer(var init: ComponentsInitializer; name : string; b: block<(var obj: auto(Type)#):void>)
  using() <| $(var data: Type#)
    invoke(b, data)
    set(init, name, data)

def split_template(name : string) : array<string>
  return <- split(name, "+")