local { isPlatformXboxOne } = require("scripts/clientState/platform.nut")

local cachedMultiplayerPrivilege = persist("cachedMultiplayerPrivilege", @() ::Watched(true))
local multiplayerPrivelegeCallback = null

local function checkMultiplayerPrivilege(showMarket = true, cb = null)
{
  multiplayerPrivelegeCallback = cb
  ::check_multiplayer_sessions_privilege(showMarket)
}

::check_multiplayer_sessions_privilege_callback <- function(isAllowed)
{
  cachedMultiplayerPrivilege(isAllowed)

  if (isAllowed)
    multiplayerPrivelegeCallback?()

  multiplayerPrivelegeCallback = null

  if (!::g_login.isLoggedIn())
    return

  ::broadcastEvent("XboxMultiplayerPrivilegeUpdated")
}

return isPlatformXboxOne? {
  checkAndShowMultiplayerPrivilegeWarning = @() true
  isMultiplayerPrivilegeAvailable = @() cachedMultiplayerPrivilege.value
  resetMultiplayerPrivilege = @() cachedMultiplayerPrivilege(true)
  updateMultiplayerPrivilege = function() {
    if (!::g_login.isLoggedIn())
      return

    checkMultiplayerPrivilege(false)
  }
}
: {
  checkAndShowMultiplayerPrivilegeWarning = @() true
  isMultiplayerPrivilegeAvailable = @() true
  resetMultiplayerPrivilege = @() null
  updateMultiplayerPrivilege = @() null
}