local { getBattleTaskUnlocks } = require("scripts/unlocks/personalUnlocks.nut")
local { eachParam } = require("std/datablock.nut")
local { getSelectedChild } = require("sqDagui/daguiUtil.nut")

const COLLAPSED_CHAPTERS_SAVE_ID = "personal_unlocks_collapsed_chapters"

local class personalUnlocksModal extends ::gui_handlers.BaseGuiHandlerWT {
  wndType = handlerType.MODAL
  sceneBlkName = "gui/unlocks/personalUnlocksModal.blk"
  unlocksItemTpl = "gui/unlocks/battleTasksItem"

  unlocksArray = null
  unlocksConfigByChapter = null
  curChapterId = ""
  curUnlockId = ""
  showAllUnlocks = false
  isFillingUnlocksList = false

  chaptersObj = null
  unlocksObj = null
  collapsedChapters = null
  collapsibleChaptersIdx = null

  function initScreen() {
    showSceneBtn("show_all_unlocks", ::has_feature("ShowAllBattleTasks"))
    chaptersObj = scene.findObject("chapters_list")
    unlocksObj = scene.findObject("unlocks_list")
    updateWindow()
    ::move_mouse_on_child_by_value(chaptersObj)
  }

  function updateWindow() {
    updatePersonalUnlocks()
    updateNoTasksText()
    fillChapterList()
    updateButtons()
  }

  function updatePersonalUnlocks() {
    unlocksArray = getBattleTaskUnlocks()
    unlocksConfigByChapter = {}
    foreach (unlock in unlocksArray) {
      local chapter = unlock?.chapter
      local group = unlock?.group
      if (chapter == null || group == null)
        continue

      unlocksConfigByChapter[chapter] <- unlocksConfigByChapter?[chapter] ?? []
      local groupIdx = unlocksConfigByChapter[chapter].findindex(@(g) g.id == group)
      if (groupIdx == null) {
        groupIdx = unlocksConfigByChapter[chapter].len()
        unlocksConfigByChapter[chapter].append({
          id = group
          name = $"#unlocks/group/{group}"
          image = unlock?.image ?? ""
          unlocks = []
        })
      }
      if (showAllUnlocks || ::is_unlock_visible(unlock))
        unlocksConfigByChapter[chapter][groupIdx].unlocks.append(
          ::g_battle_tasks.generateUnlockConfigByTask(unlock))
    }
  }

  function updateNoTasksText() {
    local text = ""
    if (unlocksArray.len() == 0)
      text = ::loc("mainmenu/battleTasks/noPersonalUnlocks")
    scene.findObject("no_unlocks_msg").setValue(text)
  }

  function fillChapterList() {
    local view = { items = [] }
    local curChapterIdx = -1
    collapsibleChaptersIdx = {}
    local idx = 0
    foreach (chapterName, chapters in unlocksConfigByChapter) {
      collapsibleChaptersIdx[chapterName] <- idx++
      curChapterIdx = curChapterId == chapterName ? view.items.len() : curChapterIdx
      view.items.append({
        itemTag = "campaign_item"
        id = chapterName
        itemText = $"#unlocks/chapter/{chapterName}"
        isCollapsable = true
      })

      foreach (group in chapters) {
        idx++
        local isUnlockedGroup = group.unlocks.len() > 0
        local groupId = group.id
        curChapterIdx = ((curChapterId == -1 && isUnlockedGroup) ||  curChapterId == groupId)
          ? view.items.len()
          : curChapterIdx
        view.items.append({
          itemTag = isUnlockedGroup ? "mission_item_unlocked" : "mission_item_locked"
          id = groupId
          itemText = group.name
          itemIcon = isUnlockedGroup ? "" : "#ui/gameuiskin#locked"
        })
      }
    }
    local data = ::handyman.renderCached("gui/missions/missionBoxItemsList", view)
    guiScene.replaceContentFromText(chaptersObj, data, data.len(), this)

    eachParam(getCollapsedChapters(), @(_, chapterId) collapseChapter(chapterId), this)

    if (view.items.len() == 0) {
      fillUnlocksList()
      return
    }
    if (curChapterIdx == -1)
      curChapterIdx = view.items.len() > 1 ? 1 : 0
    chaptersObj.setValue(curChapterIdx)
  }

  function fillUnlocksList() {
    local currentChapterConfig = unlocksConfigByChapter?[curChapterId]
    if (currentChapterConfig == null) {
      local chapterId = curChapterId
      foreach (chapter in unlocksConfigByChapter) {
        currentChapterConfig = chapter.findvalue(@(g) g.id == chapterId)
        if (currentChapterConfig != null)
          break
      }
    }

    local unlocks = currentChapterConfig?.unlocks ?? []
    local needShowUnlocksList = unlocks.len() > 0
    local needShowChapterDescr = !needShowUnlocksList && currentChapterConfig?.name != null
    unlocksObj.show(needShowUnlocksList)
    local capterDescrObj = showSceneBtn("chapter_descr", needShowChapterDescr)
    if (needShowChapterDescr) {
      capterDescrObj.findObject("descr_name").setValue(currentChapterConfig?.name ?? "")
      capterDescrObj.findObject("descr_img")["background-image"] = currentChapterConfig?.image ?? ""
      return
    }

    local view = { items = unlocks.map(
      @(config) ::g_battle_tasks.generateItemView(config))
    }
    local data = ::handyman.renderCached(unlocksItemTpl, view)
    guiScene.replaceContentFromText(unlocksObj, data, data.len(), this)

    local unlockId = curUnlockId
    local curUnlockIdx = unlocks.findindex(@(unlock) unlock.id == unlockId) ?? 0
    isFillingUnlocksList = true
    unlocksObj.setValue(curUnlockIdx)
    isFillingUnlocksList = false
  }

  getSelectedChildId = @(obj) getSelectedChild(obj)?.id ?? ""

  function onChapterSelect(obj) {
    curChapterId = getSelectedChildId(obj)
    fillUnlocksList()
    updateButtons()
  }

  function onUnlockSelect(obj) {
    curUnlockId = getSelectedChildId(obj)
    if (::show_console_buttons && !isFillingUnlocksList) {
      guiScene.applyPendingChanges(false)
      ::move_mouse_on_child_by_value(obj)
    }
  }

  function onShowAllUnlocks(obj) {
    showAllUnlocks = obj.getValue()
    updateWindow()
  }

  function onEventUnlocksCacheInvalidate(p) {
    updateWindow()
  }

  function updateButtons() {
    local canShow = !::show_console_buttons || chaptersObj.isHovered()
    local isHeader = canShow && unlocksConfigByChapter?[curChapterId] != null
    local collapsedButtonObj = showSceneBtn("btn_collapsed_chapter", canShow && isHeader)
    if (isHeader)
      collapsedButtonObj.setValue(
        ::loc(getCollapsedChapters()?[curChapterId] != null ? "mainmenu/btnExpand" : "mainmenu/btnCollapse"))
  }

  function onCollapse(obj) {
    if (obj?.id == null)
      return
    collapseChapter(::g_string.cutPrefix(obj.id, "btn_", obj.id))
    updateButtons()
  }

  function onCollapsedChapter() {
    collapseChapter(curChapterId)
    updateButtons()
  }

  function collapseChapter(chapterId) {
    local chapterObj = chaptersObj.findObject(chapterId)
    if (!chapterObj)
      return
    local isCollapsed = chapterObj.collapsed == "yes"
    local chapterGroups = unlocksConfigByChapter?[chapterId]
    if(chapterGroups == null)
      return

    local isHiddenGroupSelected = false
    foreach (group in chapterGroups)
    {
      local groupObj = chaptersObj.findObject(group.id)
      if(!::check_obj(groupObj))
        continue

      isHiddenGroupSelected = isHiddenGroupSelected || curChapterId == group.id
      groupObj.show(isCollapsed)
      groupObj.enable(isCollapsed)
    }

    if (isHiddenGroupSelected) {
      chaptersObj.setValue(collapsibleChaptersIdx?[chapterId] ?? 0)
      ::move_mouse_on_child_by_value(chaptersObj)
    }

    chapterObj.collapsed = isCollapsed ? "no" : "yes"
    getCollapsedChapters()[chapterId] = isCollapsed ? null : true
    ::save_local_account_settings(COLLAPSED_CHAPTERS_SAVE_ID, getCollapsedChapters())
  }

  function getCollapsedChapters() {
    if(collapsedChapters == null)
      collapsedChapters = ::load_local_account_settings(COLLAPSED_CHAPTERS_SAVE_ID, ::DataBlock())
    return collapsedChapters
  }

  function onChaptersListHover(obj) {
    if (::show_console_buttons)
      updateButtons()
  }
}

::gui_handlers.personalUnlocksModal <- personalUnlocksModal

return @(params = {}) ::handlersManager.loadHandler(personalUnlocksModal, params)
