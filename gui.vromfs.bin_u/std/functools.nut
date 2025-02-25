local abs = @(v) v> 0 ? v.tointeger() : -v.tointeger()

local callableTypes = ["function","table","instance"]
local function isCallable(v) {
  return callableTypes.indexof(type(v)) != null && (v.getfuncinfos() != null)
}
/*
+ partial:
  partial(f(x,y,z), 1) == @(y,z) f(1,y,z)
  partial(f(x,y,z), 1, 2) == @(z) f(1,2,z)
  partial(f(x,y,z), 1, 2, 3) == @() f(1,2,3) or f(1,2,3)
*/
local function partial(func, ...){
  assert(isCallable(func), "partial can be applied only to functions as first arguments")
  local infos = func.getfuncinfos()
  local argsnum = infos.parameters.len()-1
  local isvargved = infos.varargs==1
  local pargs = vargv
  local pargslen = pargs.len()
  if ( (pargslen == argsnum) && !isvargved) {
    return function(){
      return func.acall([null].extend(pargs))
    }
  }
  if ( (pargslen <= argsnum) || isvargved) {
    return function(...){
      return func.acall([null].extend(pargs).extend(vargv))
    }
  }
  assert(false, @() $"function '{infos.name}' cannot be partial with more arguments({pargslen}) that it accepts({argsnum})")
  return func
}

/*
 kwarg function:
  foo(x,y,z)
  kwarg(foo)==@(p) (foo(p?.x, p?.y, p?.z))
  foo(x,y,z=2)
  kwarg(foo)==@(p) (foo(p?.x, p?.y, p?.z ?? 2))
*/
local allowedKwargTypes = { table = true, ["class"] = true, instance = true }
local function kwarg(func){
  assert(isCallable(func), "kwarg can be applied only to functions as first arguments")
  local infos = func.getfuncinfos()
  local funcargs = infos.parameters.slice(1)
  local defargs = infos.defparams
  local argsnum = funcargs.len()
  local isvargved = infos.varargs==1
  local kfuncargs = {}
  local mandatoryparams = []
  local defparamsStartFrom = argsnum-defargs.len()
  foreach (idx, arg in funcargs) {
    if (idx >= defparamsStartFrom) {
      kfuncargs[arg] <- defargs[idx-defparamsStartFrom]
    }
    else{
      kfuncargs[arg] <-null
      mandatoryparams.append(arg)
    }
  }
  return isvargved ? function(params, ...) {
        if (type(params) not in allowedKwargTypes)
          assert(false, @() $"param of function can be only hashable (table, class, instance), found:'{type(params)}'")
        local nonManP = mandatoryparams.filter(@(p) p not in params)
        if (nonManP.len() > 0)
          assert(false, @() "not all mandatory parameters provided: {0}".subst(nonManP.len()==1 ? $"'{nonManP[0]}'" : nonManP.reduce(@(a,b) $"{a},'{b}'")))
        local posarguments = funcargs.map(@(kv) params[kv])
        posarguments.insert(0, this)
        return func.acall(posarguments.extend(vargv))
      }
    : function(params=kfuncargs) {
        if (type(params) not in allowedKwargTypes)
          assert(false, @() $"param of function can be only hashable (table, class, instance), found:'{type(params)}'")
        local nonManP = mandatoryparams.filter(@(p) p not in params)
        if (nonManP.len() > 0)
          assert(false, "not all mandatory parameters provided: {0}".subst(nonManP.len()==1 ? $"'{nonManP[0]}'" : nonManP.reduce(@(a,b) $"{a},'{b}'")))
        local posarguments = funcargs.map(@(kv) kv in params ? params[kv] : kfuncargs[kv])
        posarguments.insert(0, this)
        return func.acall(posarguments)
      }
}

/*
 kwpartial
  local function foo(a,b,c){(a+b)*c}
  kwpartial(foo, {b=3})(1,5) == (1+3)*5
  kwpartial(foo, {b=3}, 2)(5) == (2+3)*5
*/
local function kwpartial(func, partparams, ...){
  assert(isCallable(func), "partial can be applied only to functions as first arguments")
  assert(["table", "class","instance"].indexof(type(partparams))!=null, "kwpartial second argument of function can be only hashable (table, class, instance)")
  local infos = func.getfuncinfos()
  local funcargs = infos.parameters.slice(1)
//  local defargs = infos.defparams
  local argsnum = funcargs.len()
  local posfuncargs = {}
  local partvargs = vargv
  foreach (p, v in partparams){
    local posidx = funcargs.indexof(p)
    if (posidx == null)
      continue
    posfuncargs[posidx] <- v
  }
  return function(...){
    local curargs = partvargs.extend(vargv)
    assert(curargs.len()+posfuncargs.len()>=argsnum, @() $"not enough arguments provided for function '{infos?.name}' to call")
    local finalargs = []
    local provArgIdx = 0
    for (local i=0; i<argsnum; i++) {
      if (i in posfuncargs) {
        finalargs.append(posfuncargs[i])
      }
      else {
        finalargs.append(curargs[provArgIdx])
        provArgIdx++
      }
    }
    return func.acall([this].extend(finalargs))
  }
}

// pipe:
//  pipe(f,g) =  @(x) f(g(x))
//it can be replaced with oneliner pipe = @(...) @(x) vargv.reduce(@(a,b) b(a), x)
local function pipe(...){
  local args = vargv.filter(isCallable)
  assert(args.len() == vargv.len() && args.len()>0, "pipe should be called with functions")
  local finfos = args[0].getfuncinfos()
  local numarg = (finfos.native ? abs(finfos.paramscheck) : finfos.parameters.len()) - 1
  local isvargved = finfos.native ? finfos.paramscheck < -2 : finfos.varargs==1
  assert(numarg==1 || (numarg==0 && isvargved), "pipe cannot be applied to multiargument function or function with no argument")
  return @(x) args.reduce(@(a,b) b(a), x)
}
// compose (reverse to pipe):
//  compose(f,g) =  @(x) g(f(x))
//it can be replaced with oneliner compose = @(...) @(x) vargv.reverse().reduce(@(a,b) b(a), x)
local function compose(...){
  local args = vargv.filter(isCallable)
  assert(args.len() == vargv.len() && args.len()>0, "compose should be called with functions")
  args.reverse()
  local finfos = args[0].getfuncinfos()
  local numarg = (finfos.native ? abs(finfos.paramscheck) : finfos.parameters.len()) - 1
  local isvargved = finfos.native ? finfos.paramscheck < -2 : finfos.varargs==1
  assert(numarg==1 || (numarg==0 && isvargved), "compose cannot be applied to multiargument function or function with no argument")
  return @(x) args.reduce(@(a,b) b(a), x)
}
/*
  tryCatch(tryer function, catcher function) return function that will operate on input safely
*/
local function tryCatch(tryer, catcher){
  return function(...) {
    try{
      return tryer.pacall([null].extend(vargv))
    }
    catch(e)
      return catcher(e)
   }
}

/*
 (un)curry:
  cf = curry(f) == @(x) @(y) @(z) f(x,y,z)
  f(x,y,z) = cf(x)(y)(z)
  cf(x) == @(y) @(z) f(x,y,z)
  local get = curry(function(property, object){ return object?[property] })
  local map = curry(function(fn, value){ return value.map(fn) })

  local objects = [{ id = 1 }, { id = 2 }, { id = 3 }]
  local getIDs = map(get("id"))

  log(objects.map(get("id"))) //= [1, 2, 3]
  log(objects.map(@(v) v?.id)) //= [1, 2, 3]
  log(getIDs(objects)) //= [1, 2, 3]

also our curry is (un)curry - so
local sum = curry(@(a,b,c) a+b+c)
sum(1)(2)(3) == sum(1)(2,3) == sum(1,2,3) == sum(1,2)(3)
unfortunately returning function are now use vargv, instead of rest of parameters (the same issue goes to partial)
*/
local function curry(fn) {
  local finfos = fn.getfuncinfos()
  assert(!finfos.native || finfos.paramscheck >= 0, "Cannot curry native function with varargs")
  local arity = (finfos.native ? finfos.paramscheck : finfos.parameters.len())-1

  return function f1(...) {
    local args = vargv
    if (args.len() >= arity) {
      return fn.acall([this].extend(args))
    } else {
      local fone = f1
      return function(...) {
        local moreArgs = vargv
        local newArgs = clone args
        newArgs.extend(moreArgs)
        return fone.acall([this].extend(newArgs))
      }
    }
  }
}

/**
* memoize(function, [hashFunction])
  Memoizes a given function by caching the computed result. Useful for speeding up slow-running computations.
  If passed an optional hashFunction, it will be used to compute the hash key for storing the result, based on the arguments to the original function.
  The default hashFunction just uses the first argument to the memoized function as the key.
*/
local function checkFuncArgumentsNum(func, numMinMandatoryParams){
  local funcinfos = func.getfuncinfos()
  if (funcinfos?.native) {
    local paramscheck = funcinfos.paramscheck
    if (paramscheck<0)
      paramscheck = -paramscheck
    if (paramscheck >= numMinMandatoryParams)
      return true
    return false
  }
  if ((funcinfos.parameters.len()-1) >= numMinMandatoryParams)
    return true
  if (funcinfos.varargs > 0 )
    return true
  return false
}

local function memoize(func, hashfunc=null, cacheExternal=null, nullCache=null){
  local cacheDefault = cacheExternal ?? {}
  local cacheForNull = nullCache ?? {}
  assert(checkFuncArgumentsNum(func, 1))
  hashfunc = hashfunc ?? function(...) {
    return vargv[0]
 }
  local function memoizedfunc(...){
    local args = [null].extend(vargv)
    local rawHash = hashfunc.acall(args)
    //index cannot be null. use different cache to avoid collision
    local hash = rawHash ?? 0
    local cache = rawHash != null ? cacheDefault : cacheForNull
    if (hash in cache) {
      return cache[hash]
    }
    local result = func.acall(args)
    cache[hash] <- result
    return result
  }
  return memoizedfunc
}
//the same function as in underscore.js
//Creates a version of the function that can only be called one time.
//Repeated calls to the modified function will have no effect, returning the value from the original call.
//Useful for initialization functions, instead of having to set a boolean flag and then check it later.
local function once(func){
  local result
  local called = false
  local function memoizedfunc(...){
    if (called)
      return result
    local res = func.acall([null].extend(vargv))
    result = res
    called = true
    return res
  }
  return memoizedfunc
}

//the same function as in underscore.js
//Creates a version of the function that can be called no more than count times.
//The result of the last function call is memoized and returned when count has been reached.
local function before(count, func){
  local called = 0
  local res
  return function beforeTimes(...){
    if (called >= count)
      return res
    called++
    res = func.acall([null].extend(vargv))
    return res
  }
}

//the same function as in underscore.js
//Creates a version of the function that will only be run after being called count times.
//Useful for grouping asynchronous responses, where you want to be sure that all the async calls have finished, before proceeding.
local function after(count, func){
  local called = 0
  return function beforeTimes(...){
    if (called < count) {
      called++
      return
    }
    return func.acall([null].extend(vargv))
  }
}

//generic breakable reduce. By breakable reduce most of other main functional can be implemented
// like (reduce, each, findindex, findvalue, filter, map).Each and reduce can be faster
// it can be done other way, with special type

/*
local BreakValue = class{
  result = null
  constructor(val){
    result = val
  }
}

local MemoNotInited = class{}
local function breakable_reduce(obj, func, memo=MemoNotInited()) {
  local firstInited = !(memo instanceof MemoNotInited)
  local argsnum = func.getfuncinfos().parameters.len()-1
  local nfunc
  if (argsnum==2)
    nfunc = @(prevval, curval, idx, obj_ref) func(prevval, curval)
  else if (argsnum==3)
    nfunc = @(prevval, curval, idx, obj_ref) func(prevval, curval, idx)
  else if (argsnum==4)
    nfunc = func
  else
    assert(false, "function in breakable reduce should have arguments func(prevval, curval, [idx, [obj_ref]])")
  foreach (idx, curval in obj) {
    if (!firstInited){
      memo = curval
      firstInited = true
      continue
    }
    local res = nfunc(memo, curval, idx, obj)
    if (res instanceof BreakValue)
      return res.result
    if (res == BreakValue)
      return memo
    else
      memo = res
  }
  return !firstInited ? null : memo
}
*/
local combine = @(...) @() vargv.each(@(v) v.call(null))

return {
  partial
  pipe
  compose
  kwarg
  kwpartial
  curry
  memoize
  isCallable
  once
  before
  after
//  reduce = breakable_reduce
//  BreakValue
  combine
  tryCatch
}
