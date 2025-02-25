local LoginProcess = require("loginProcess.nut")

global enum LOGIN_STATE //bit mask
{
  AUTHORIZED               = 0x0001 //succesfully connected to auth
  PROFILE_RECEIVED         = 0x0002
  CONFIGS_RECEIVED         = 0x0004
  MATCHING_CONNECTED       = 0x0008
  CONFIGS_INITED           = 0x0010
  ONLINE_BINARIES_INITED   = 0x0020
  HANGAR_LOADED            = 0x0040

  //masks
  NOT_LOGGED_IN            = 0x0000
  LOGGED_IN                = 0x003F //logged in to all hosts and all configs are loaded
}

::g_login <- {
  [PERSISTENT_DATA_PARAMS] = ["curState", "curLoginProcess"]

  curState = LOGIN_STATE.NOT_LOGGED_IN
  curLoginProcess = null
  loginProcessClass = LoginProcess //this is really bad class. It has a cyclic dependency with g_login and is hard to change the order in it for other project

  onAuthorizeChanged = function() {}
  onLoggedInChanged  = function() {}
  loadLoginHandler   = function() {}
  initConfigs        = function(cb) { cb() }
  afterScriptsReload = function() {}

  function onProfileReceived()
  {
    addState(LOGIN_STATE.PROFILE_RECEIVED | LOGIN_STATE.CONFIGS_RECEIVED)

    ::broadcastEvent("ProfileReceived")
  }

  function bigQueryOnLogin()
  {
    local params = ::target_platform
    if (::getSystemConfigOption("launcher/bg_update", true))
      params += " bg_update"
    ::add_big_query_record("login", params)
  }
}

g_login.init <- function init()
{
  ::g_script_reloader.registerPersistentDataFromRoot("g_login")
  ::subscribe_handler(this, ::g_listener_priority.CONFIG_VALIDATION)
}

g_login.isAuthorized <- function isAuthorized()
{
  return (curState & LOGIN_STATE.AUTHORIZED) != 0
}

g_login.isReadyToFullLoad <- function isReadyToFullLoad()
{
  return hasState(LOGIN_STATE.AUTHORIZED | LOGIN_STATE.ONLINE_BINARIES_INITED)
}

g_login.isLoggedIn <- function isLoggedIn()
{
  return (curState & LOGIN_STATE.LOGGED_IN) == LOGIN_STATE.LOGGED_IN
}

g_login.isProfileReceived <- function isProfileReceived()
{
  return (curState & LOGIN_STATE.PROFILE_RECEIVED) != 0
}

g_login.hasState <- function hasState(state)
{
  return (curState & state) == state
}

g_login.startLoginProcess <- function startLoginProcess(shouldCheckScriptsReload = false)
{
  if (curLoginProcess && curLoginProcess.isValid())
    return
  curLoginProcess = loginProcessClass(shouldCheckScriptsReload)
}

g_login.setState <- function setState(newState)
{
  if (curState == newState)
    return

  local wasAuthorized = isAuthorized()
  local wasLoggedIn = isLoggedIn()

  curState = newState

  if (wasAuthorized != isAuthorized())
    onAuthorizeChanged()
  if (wasLoggedIn != isLoggedIn())
    onLoggedInChanged()

  ::broadcastEvent("LoginStateChanged")
}

g_login.addState <- function addState(statePart)
{
  setState(curState | statePart)
}

g_login.removeState <- function removeState(statePart)
{
  setState(curState & ~statePart)
}

g_login.destroyLoginProgress <- function destroyLoginProgress()
{
  if (curLoginProcess)
    curLoginProcess.destroy()
  curLoginProcess = null
}

g_login.reset <- function reset()
{
  destroyLoginProgress()
  setState(LOGIN_STATE.NOT_LOGGED_IN)
}

g_login.onEventScriptsReloaded <- function onEventScriptsReloaded(p)
{
  if (!isLoggedIn() && isAuthorized())
    startLoginProcess(true)
  afterScriptsReload()
}

g_login.getStateDebugStr <- function getStateDebugStr(state = null)
{
  state = state ?? curState
  return state == 0 ? "0" : ::bit_mask_to_string("LOGIN_STATE", state)
}

g_login.debugState <- function debugState(shouldShowNotSetBits = false)
{
  local debugLog = ::dlog // warning disable: -forbidden-function
  if (shouldShowNotSetBits)
    return debugLog($"not set loginState = {getStateDebugStr(LOGIN_STATE.LOGGED_IN & ~curState)}")
  return debugLog($"loginState = {getStateDebugStr()}")
}

::is_logged_in <- function is_logged_in() //used from code
{
  return ::g_login.isLoggedIn()
}

::cross_call_api.login <- ::g_login
