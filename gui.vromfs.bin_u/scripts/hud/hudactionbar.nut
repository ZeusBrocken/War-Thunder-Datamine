local { isFakeBullet, getBulletsSetData } = require("scripts/weaponry/bulletsInfo.nut")
local { getBulletsIconView } = require("scripts/weaponry/bulletsVisual.nut")
local { MODIFICATION } = require("scripts/weaponry/weaponryTooltips.nut")
local { LONG_ACTIONBAR_TEXT_LEN, getActionItemAmountText, getActionItemModificationName
} = require("scripts/hud/hudActionBarInfo.nut")
local { toggleShortcut } = require("globalScripts/controls/shortcutActions.nut")
local { getActionBarItems, getWheelBarItems, activateActionBarAction,
  getActionBarUnitName } = ::require_native("hudActionBar")
local { EII_BULLET, EII_ARTILLERY_TARGET, EII_EXTINGUISHER, EII_ROCKET, EII_FORCED_GUN
} = ::require_native("hudActionBarConst")
local { arrangeStreakWheelActions } = require("scripts/hud/hudActionBarStreakWheel.nut")

local sectorAngle1PID = ::dagui_propid.add_name_id("sector-angle-1")

::ActionBar <- class
{
  actionItems             = null
  guiScene                = null
  scene                   = null

  canControl              = true
  useWheelmenu            = false
  killStreaksActions      = null
  killStreaksActionsOrdered = null
  weaponActions           = null

  artillery_target_mode = false

  curActionBarUnit = null

  __action_id_prefix = "action_bar_item_"

  isFootballMission = false

  constructor(_nestObj) {
    if (!::checkObj(_nestObj))
      return
    scene     = _nestObj
    guiScene  = _nestObj.getScene()
    killStreaksActions = []
    weaponActions = []

    canControl = !::isPlayerDedicatedSpectator() && !::is_replay_playing()

    isFootballMission = (::get_game_type() & ::GT_FOOTBALL) != 0

    updateVisibility()

    ::g_hud_event_manager.subscribe("ToggleKillStreakWheel", function (eventData) {
      if ("open" in eventData)
        toggleKillStreakWheel(eventData.open)
    }, this)
    ::g_hud_event_manager.subscribe("ToggleSelectWeaponWheel", function (eventData) {
      if ("open" in eventData)
        toggleSelectWeaponWheel(eventData.open)
    }, this)
    ::g_hud_event_manager.subscribe("LiveStatsVisibilityToggled", function (eventData) {
      updateVisibility()
    }, this)
    ::g_hud_event_manager.subscribe("LocalPlayerAlive", function (data) {
      fill() //the same unit can change bullets order.
    }, this)

    updateParams()
    fill()
  }

  function reinit(forceUpdate = false)
  {
    updateParams()
    if (forceUpdate || getActionBarUnit() != curActionBarUnit)
      fill()
    else
      onUpdate()
  }

  function updateParams()
  {
    useWheelmenu = ::is_xinput_device()
  }

  function isValid()
  {
    return ::checkObj(scene)
  }

  function getActionBarUnit()
  {
    return ::getAircraftByName(getActionBarUnitName())
  }

  function fill()
  {
    if (!::checkObj(scene))
      return

    curActionBarUnit = getActionBarUnit()
    actionItems = getActionBar()

    local view = {
      items = ::u.map(actionItems, (@(a) buildItemView(a, true)).bindenv(this))
    }

    local partails = {
      items           = ::load_template_text("gui/hud/actionBarItem")
      textShortcut    = canControl ? ::load_template_text("gui/hud/actionBarItemTextShortcut")    : ""
      gamepadShortcut = canControl ? ::load_template_text("gui/hud/actionBarItemGamepadShortcut") : ""
    }
    local blk = ::handyman.renderCached(("gui/hud/actionBar"), view, partails)
    guiScene.replaceContentFromText(scene, blk, blk.len(), this)
    scene.findObject("action_bar").setUserData(this)

    ::broadcastEvent("HudActionbarInited", { actionBarItemsAmount = actionItems.len() })
  }

  //creates view for handyman by one actionBar item
  function buildItemView(item, needShortcuts = false)
  {
    local unit = getActionBarUnit()
    local actionBarType = ::g_hud_action_bar_type.getByActionItem(item)
    local isReady = isActionReady(item)

    local shortcutText = ""
    local isXinput = false
    local shortcutId = ""
    local showShortcut = false
    if (needShortcuts && actionBarType.getShortcut(item, unit))
    {
      shortcutId = actionBarType.getVisualShortcut(item, unit)

      if (isFootballMission)
        shortcutId = item?.modificationName == "152mm_football" ? "ID_FIRE_GM"
          : item?.modificationName == "152mm_football_jump" ? "ID_FIRE_GM_MACHINE_GUN"
          : shortcutId

      local shType = ::g_shortcut_type.getShortcutTypeByShortcutId(shortcutId)
      local scInput = shType.getFirstInput(shortcutId)
      shortcutText = scInput.getText()
      isXinput = scInput.hasImage() && scInput.getDeviceId() != ::STD_KEYBOARD_DEVICE_ID
      showShortcut = isXinput || shortcutText !=""
    }

    local viewItem = {
      id               = __action_id_prefix + item.id
      selected         = item.selected ? "yes" : "no"
      active           = item.active ? "yes" : "no"
      enable           = isReady ? "yes" : "no"
      wheelmenuEnabled = isReady || actionBarType.canSwitchAutomaticMode()
      shortcutText     = shortcutText
      isLongScText     = ::utf8_strlen(shortcutText) >= LONG_ACTIONBAR_TEXT_LEN
      mainShortcutId   = shortcutId
      cancelShortcutId = shortcutId
      isXinput         = showShortcut && isXinput
      showShortcut     = showShortcut
      amount           = getActionItemAmountText(item)
      cooldown         = getWaitGaugeDegree(item.cooldown)
    }

    local modifName = getActionItemModificationName(item, unit)
    if (modifName)
    {
      viewItem.bullets <- ::handyman.renderNested(::load_template_text("gui/weaponry/bullets"),
        function (text) {
          // if fake bullets are not generated yet, generate them
          if (isFakeBullet(modifName) && !(modifName in unit.bulletsSets))
            getBulletsSetData(unit, ::fakeBullets_prefix, {})
          local data = getBulletsSetData(unit, modifName)
          return getBulletsIconView(data)
        }
      )
      viewItem.tooltipId <- MODIFICATION.getTooltipId(unit.name, modifName, { isInHudActionBar = true })
      viewItem.tooltipDelayed <- !canControl
    }
    else if (item.type == EII_ARTILLERY_TARGET)
    {
      viewItem.activatedShortcutId <- "ID_SHOOT_ARTILLERY"
    }

    if (!modifName && item.type != EII_BULLET && item.type != EII_FORCED_GUN)
    {
      local killStreakTag = ::getTblValue("killStreakTag", item)
      local killStreakUnitTag = ::getTblValue("killStreakUnitTag", item)
      viewItem.icon <- actionBarType.getIcon(killStreakUnitTag)
      viewItem.name <- actionBarType.getTitle(killStreakTag)
      viewItem.tooltipText <- actionBarType.getTooltipText(item)
    }

    return viewItem
  }

  function isActionReady(action)
  {
    return action.cooldown <= 0
  }

  function getWaitGaugeDegree(val)
  {
    return (360 - (::clamp(val, 0.0, 1.0) * 360)).tointeger()
  }

  function updateWaitGaugeDegree(obj, val) {
    local degree = getWaitGaugeDegree(val)
    if (degree == (obj.getFinalProp(sectorAngle1PID) ?? -1).tointeger())
      return
    obj.set_prop_latent(sectorAngle1PID, degree)
    obj.updateRendElem()
  }

  function onUpdate(obj = null, dt = 0.0)
  {
    local prevCount = typeof actionItems == "array" ? actionItems.len() : 0
    local prevKillStreaksActions = killStreaksActions

    local prevActionItems = actionItems
    actionItems = getActionBar()

    if (useWheelmenu)
      updateKillStreakWheel(prevKillStreaksActions)

    local fullUpdate = prevCount != actionItems.len()
    if (!fullUpdate)
    {
      foreach (id, item in actionItems)
        if (item.id != prevActionItems[id].id
          || (item?.isStreakEx && item.count < 0 && prevActionItems[id].count >= 0)
          || ((item.type == EII_BULLET || item.type == EII_FORCED_GUN)
            && item?.modificationName != prevActionItems[id]?.modificationName)
          || ((item.type == EII_ROCKET)
            && item?.bulletName != prevActionItems[id]?.bulletName))
        {
          fullUpdate = true
          break
        }
    }

    if (fullUpdate)
    {
      fill()
      ::broadcastEvent("HudActionbarResized", { size = actionItems.len() })
      return
    }

    local ship = getActionBarUnit()?.isShipOrBoat()
    foreach(item in actionItems)
    {
      local itemObj = scene.findObject(__action_id_prefix + item.id)
      if (!::checkObj(itemObj))
        continue

      local amountObj = itemObj.findObject("amount_text")
      if (::check_obj(amountObj))
        amountObj.setValue(getActionItemAmountText(item))

      local automaticObj = itemObj.findObject("automatic_text")
      if (::check_obj(automaticObj))
        automaticObj.show(ship && item?.automatic)

      if (item.type != EII_BULLET && !itemObj.isEnabled() && isActionReady(item))
        blink(itemObj)

      handleIncrementCount(item, prevActionItems, itemObj)

      itemObj.selected = item.selected ? "yes" : "no"
      itemObj.active = item.active ? "yes" : "no"
      itemObj.enable(isActionReady(item))

      local mainActionButtonObj = itemObj.findObject("mainActionButton")
      local activatedActionButtonObj = itemObj.findObject("activatedActionButton")
      local cancelButtonObj = itemObj.findObject("cancelButton")
      if (::checkObj(mainActionButtonObj) &&
          ::checkObj(activatedActionButtonObj) &&
          ::checkObj(cancelButtonObj))
      {
          mainActionButtonObj.show(!item.active)
          activatedActionButtonObj.show(item.active)
          cancelButtonObj.show(item.active)
      }

      local actionBarType = ::g_hud_action_bar_type.getByActionItem(item)
      local backgroundImage = actionBarType.getIcon()
      local iconObj = itemObj.findObject("action_icon")
      if (::checkObj(iconObj))
      {
        if (backgroundImage.len() > 0)
          iconObj["background-image"] = backgroundImage
      }
      if (item.type == EII_EXTINGUISHER && ::checkObj(mainActionButtonObj))
        mainActionButtonObj.show(item.cooldown == 0)
      if (item.type == EII_ARTILLERY_TARGET && item.active != artillery_target_mode)
      {
        artillery_target_mode = item.active
        ::broadcastEvent("ArtilleryTarget", { active = artillery_target_mode })
      }

      updateWaitGaugeDegree(itemObj.findObject("cooldown"), item.cooldown)
      updateWaitGaugeDegree(itemObj.findObject("blockedCooldown"), item?.blockedCooldown ?? 0.0)
    }
  }

  /**
   * Function checks increase count and shows it in view.
   * It needed for display rearming process.
   */
  function handleIncrementCount(currentItem, prewItemsArray, itemObj)
  {
    local actionBarType = ::g_hud_action_bar_type.getByActionItem(currentItem)
     if (!actionBarType.needAnimOnIncrementCount)
       return

    local prewItem = ::u.search(prewItemsArray, (@(currentItem) function (searchItem) {
      return currentItem.id == searchItem.id
    })(currentItem))

    if (prewItem == null)
      return

    local hasAmmoLost = "ammoLost" in prewItem && "ammoLost" in currentItem // compatibility 1.71
    if ((prewItem.countEx == currentItem.countEx && prewItem.count < currentItem.count)
      || (prewItem.countEx < currentItem.countEx)
      || (hasAmmoLost && prewItem.ammoLost < currentItem.ammoLost))
    {
      local delta = currentItem.countEx - prewItem.countEx || currentItem.count - prewItem.count
      if (hasAmmoLost && prewItem.ammoLost < currentItem.ammoLost)
        ::g_hud_event_manager.onHudEvent("hint:ammoDestroyed:show")
      local blk = ::handyman.renderCached("gui/hud/actionBarIncrement", {is_increment = delta > 0, delta_amount = delta})
      guiScene.appendWithBlk(itemObj, blk, this)
    }
  }

  function blink(obj)
  {
    local blinkObj = obj.findObject("availability")
    if (::checkObj(blinkObj))
      blinkObj["_blink"] = "yes"
  }

  function updateVisibility()
  {
    if (::checkObj(scene))
      scene.show(!::g_hud_live_stats.isVisible())
  }

  /* *
   * Wrapper for getActionBarItems().
   * Need to separate killstreak reward form other
   * action bar items.
   * Works only with gamepad controls.
   * */
  function getActionBar()
  {
    local isUnitValid = ::get_es_unit_type(getActionBarUnit()) != ::ES_UNIT_TYPE_INVALID
    local rawActionBarItem = isUnitValid ? getActionBarItems() : []
    if (!useWheelmenu)
      return rawActionBarItem

    local rawWheelItem = isUnitValid ? (getWheelBarItems() ?? []) : []
    killStreaksActions = []
    weaponActions = []
    for (local i = rawActionBarItem.len() - 1; i >= 0; i--)
    {
      local actionBarType = ::g_hud_action_bar_type.getByActionItem(rawActionBarItem[i])
      if (actionBarType.isForWheelMenu())
        killStreaksActions.append(rawActionBarItem[i])
    }
    for (local i = rawWheelItem.len() - 1; i >= 0; i--)
    {
      local actionBarType = ::g_hud_action_bar_type.getByActionItem(rawWheelItem[i])
      if (actionBarType.isForSelectWeaponMenu())
        weaponActions.insert(0, rawWheelItem[i])
    }

    return rawActionBarItem
  }

  function activateAction(obj)
  {
    local action = getActionByObj(obj)
    if (action)
    {
      local shortcut = ::g_hud_action_bar_type.getByActionItem(action).getShortcut(action, getActionBarUnit())
      if (shortcut)
        toggleShortcut(shortcut)
    }
  }

  //Only for streak wheel menu
  function activateStreak(streakId)
  {
    local action = killStreaksActionsOrdered?[streakId]
    if (action)
      return activateActionBarAction(action.shortcutIdx)

    if (streakId >= 0) //something goes wrong; -1 is valid situation = player does not choose smthng
    {
      debugTableData(killStreaksActionsOrdered)
      callstack()
      ::dagor.assertf(false, "Error: killStreak id out of range.")
    }
  }

  function activateWeapon(streakId)
  {
    local action = ::getTblValue(streakId, weaponActions)
    if (action)
    {
      local shortcut = ::g_hud_action_bar_type.getByActionItem(action).getShortcut(action, getActionBarUnit())
      toggleShortcut(shortcut)
    }
  }


  function getActionByObj(obj)
  {
    local actionItemNum = obj.id.slice(-(obj.id.len() - __action_id_prefix.len())).tointeger()
    foreach (item in actionItems)
      if (item.id == actionItemNum)
        return item
    return null
  }

  function toggleKillStreakWheel(open)
  {
    if (!::checkObj(scene))
      return

    if (open)
    {
      if (killStreaksActions.len() == 1)
      {
        activateStreak(0)
        ::close_cur_wheelmenu()
      }
      else
        openKillStreakWheel()
    }
    else
      ::close_cur_wheelmenu()
  }

  function openKillStreakWheel()
  {
    if (!killStreaksActions || killStreaksActions.len() == 0)
      return

    ::close_cur_voicemenu()

    fillKillStreakWheel()
  }

  function fillKillStreakWheel(isUpdate = false)
  {
    killStreaksActionsOrdered = arrangeStreakWheelActions(getActionBarUnit(), killStreaksActions)

    local menu = []
    foreach(action in killStreaksActionsOrdered)
      menu.append(action != null ? buildItemView(action) : null)

    local params = {
      menu            = menu
      callbackFunc    = activateStreak
      contentTemplate = "gui/hud/actionBarItemStreakWheel"
      owner           = this
    }

    ::gui_start_wheelmenu(params, isUpdate)
  }

  function updateKillStreakWheel(prevActions)
  {
    local handler = ::handlersManager.findHandlerClassInScene(::gui_handlers.wheelMenuHandler)
    if (!handler || !handler.isActive)
      return

    local update = false
    if (killStreaksActions.len() != prevActions.len())
      update = true
    else
    {
      for (local i = killStreaksActions.len() - 1; i >= 0; i--)
        if (killStreaksActions[i].active != prevActions[i].active ||
          isActionReady(killStreaksActions[i]) != isActionReady(prevActions[i]) ||
          killStreaksActions[i].count != prevActions[i].count ||
          killStreaksActions[i].countEx != prevActions[i].countEx)
        {
          update = true
          break
        }
    }

    if (update)
      fillKillStreakWheel(true)
  }

  function toggleSelectWeaponWheel(open)
  {
    if (!::checkObj(scene))
      return

    if (open)
      fillSelectWaponWheel()
    else
      ::close_cur_wheelmenu()
  }

  function fillSelectWaponWheel()
  {
    local menu = []
    foreach(action in weaponActions)
      menu.append(buildItemView(action))
    local params = {
      menu            = menu
      callbackFunc    = activateWeapon
      contentTemplate = "gui/hud/actionBarItemStreakWheel"
      owner           = this
    }
    ::gui_start_wheelmenu(params)
  }
  function onTooltipObjClose(obj)
  {
    ::g_tooltip.close.call(this, obj)
  }

  function onGenericTooltipOpen(obj)
  {
    ::g_tooltip.open(obj, this)
  }
}
