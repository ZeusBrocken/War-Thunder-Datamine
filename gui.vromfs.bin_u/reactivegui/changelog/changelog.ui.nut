local scrollbar = require("reactiveGui/components/scrollbar.nut")
local {formatText} = require("reactiveGui/components/formatText.nut")
local {curPatchnote, curPatchnoteIdx, choosePatchnote, nextPatchNote,
  prevPatchNote, patchnotesReceived, versions, chosenPatchnoteContent,
  chosenPatchnoteLoaded} = require("changeLogState.nut")
local colors = require("reactiveGui/style/colors.nut")
local { commonTextButton } = require("reactiveGui/components/textButton.nut")
local modalWindow = require("reactiveGui/components/modalWindow.nut")
local fontsState = require("reactiveGui/style/fontsState.nut")
local JB = require("reactiveGui/control/gui_buttons.nut")
local { mkImageCompByDargKey } = require("reactiveGui/components/gamepadImgByKey.nut")
local { showConsoleButtons } = require("reactiveGui/ctrlsState.nut")
local focusBorder = require("reactiveGui/components/focusBorder.nut")
local blurPanel = require("reactiveGui/components/blurPanel.nut")
local spinner = require("reactiveGui/components/spinner.nut")

local tabStyle = {
  fillColor = {
    normal   = colors.transparent
    hover    = colors.menu.menuButtonColorHover
    active   = colors.menu.frameBackgroundColor
    current  = colors.menu.higlightFrameBgColor
  }
  textColor = {
    normal   = colors.menu.commonTextColor
    hover    = colors.menu.menuButtonTextColorHover
    active   = colors.menu.activeTextColor
    current  = colors.menu.activeTextColor
  }
}

local blockInterval = ::fpx(6)
local borderWidth = ::dp(1)

local scrollHandler = ::ScrollHandler()
local scrollStep = ::fpx(75)
local maxPatchnoteWidth = ::fpx(300)

local function getTabColorCtor(sf, style, isCurrent) {
  if (isCurrent)        return style.current
  if (sf & S_ACTIVE)    return style.active
  if (sf & S_HOVER)     return style.hover
  return style.normal
}

local function patchnote(v) {
  local stateFlags = Watched(0)
  local isCurrent = @() curPatchnote.value.id == v.id
  return function() {
    local children = [{
      size = [flex(), ::ph(100)]
      maxWidth = maxPatchnoteWidth - 2 * ::scrn_tgt(0.01)
      behavior = Behaviors.TextArea
      rendObj = ROBJ_TEXTAREA
      halign = ALIGN_CENTER
      valign = ALIGN_CENTER
      color = getTabColorCtor(stateFlags.value, tabStyle.textColor, isCurrent())
      font = fontsState.get("small")
      text = v?.titleshort ?? v?.title ?? v.tVersion
    }]
    if ((stateFlags.value & S_HOVER) != 0)
      children.append(focusBorder({ maxWidth = maxPatchnoteWidth }))
    return {
      watch = [stateFlags, curPatchnote]
      rendObj = ROBJ_BOX
      fillColor = isCurrent() ? Color(58, 71, 79)
        : Color(0, 0, 0)
      borderColor = Color(178, 57, 29)
      borderWidth = isCurrent()
        ? [0, 0, 2*borderWidth, 0]
        : 0
      size = [flex(1), ::ph(100)]
      maxWidth = maxPatchnoteWidth
      behavior = Behaviors.Button
      halign = ALIGN_CENTER
      onClick = @() choosePatchnote(v)
        onElemState = @(sf) stateFlags(sf)
      children
    }
  }
}

local topBorder = @(params = {}) {
  size = [::dp(1), flex()]
  valign = ALIGN_CENTER
}.__merge(params)

local patchnoteSelectorGamepadButton = @(hotkey, actionFunc) topBorder({
  size = [SIZE_TO_CONTENT, flex()]
  behavior = Behaviors.Button
  children = mkImageCompByDargKey(hotkey)
  onClick = actionFunc
  skipDirPadNav = true
})

local isVersionsExists = ::Computed(@() (versions.value?.len() ?? 0) > 0)
local function getPatchoteSelectorChildren() {
  if (!isVersionsExists.value)
    return null

  local children = patchnotesReceived.value && isVersionsExists.value
    ? versions.value.map(patchnote) : []
  if (!showConsoleButtons.value)
    return children

  return [patchnoteSelectorGamepadButton("J:LB", nextPatchNote)]
    .extend(children)
    .append(patchnoteSelectorGamepadButton("J:RB", prevPatchNote))
}

local patchnoteSelector = @() {
  size = [flex(), ::ph(100)]
  flow = FLOW_HORIZONTAL
  gap = topBorder()
  padding = [blockInterval, 0, 0, 0]
  children = getPatchoteSelectorChildren()
  watch = [versions, curPatchnote, patchnotesReceived, isVersionsExists]
}

local missedPatchnoteText = formatText([::loc("NoUpdateInfo", "Oops... No information yet :(")])

local seeMoreUrl = {
  t="url"
  url=::loc("url/news")
  v=::loc("visitGameSite", "See game website for more details")
  margin = [::fpx(50), 0, 0, 0]
}

local scrollPatchnoteWatch = Watched(0)

local function scrollPatchnote() {  //FIX ME: Remove this code, when native scroll will have opportunity to scroll by hotkeys.
  local element = scrollHandler.elem
  if (element != null)
    scrollHandler.scrollToY(element.getScrollOffsY() + scrollPatchnoteWatch.value * scrollStep)
}

scrollPatchnoteWatch.subscribe(function(value) {
  ::gui_scene.clearTimer(scrollPatchnote)
  if (value == 0)
    return

  scrollPatchnote()
  ::gui_scene.setInterval(0.1, scrollPatchnote)
})

local scrollPatchnoteBtn = @(hotkey, watchValue) {
  behavior = Behaviors.Button
  onElemState = @(sf) scrollPatchnoteWatch((sf & S_ACTIVE) ? watchValue : 0)
  hotkeys = [[hotkey]]
  onDetach = @() scrollPatchnoteWatch(0)
}

chosenPatchnoteContent.subscribe(@(value) scrollHandler.scrollToY(0))

local patchnoteLoading = freeze({
  children = [formatText([{v = ::loc("loading"), t = "h2", halign = ALIGN_CENTER}]), spinner]
  flow  = FLOW_VERTICAL
  halign = ALIGN_CENTER
  gap = ::hdpx(20)
  valign = ALIGN_CENTER size = [flex(), sh(20)]
  padding = sh(2)
})

local function selPatchnote() {
  local text = (chosenPatchnoteContent.value.text ?? "") != ""
    ? chosenPatchnoteContent.value.text : missedPatchnoteText
  if (::cross_call.hasFeature("AllowExternalLink")) {
    if (::type(text)!="array")
      text = [text, seeMoreUrl]
    else
      text = (clone text).append(seeMoreUrl)
  }
  return {
    watch = [chosenPatchnoteLoaded, chosenPatchnoteContent]
    size = flex()
    children = [
      scrollbar.makeSideScroll({
        size = [flex(), SIZE_TO_CONTENT]
        margin = [0 ,blockInterval]
        children = chosenPatchnoteLoaded.value ? formatText(text) : patchnoteLoading
      }, {
        scrollHandler = scrollHandler
        joystickScroll = false
      }),
      scrollPatchnoteBtn("^J:R.Thumb.Up | PageUp", -1),
      scrollPatchnoteBtn("^J:R.Thumb.Down | PageDown", 1)
    ]
  }
}

local function onCloseAction() {
  ::cross_call.startMainmenu()
}

local btnNext  = commonTextButton(::loc("mainmenu/btnNextItem"), nextPatchNote,
  {hotkeys=[["{0} | Tab".subst(JB.B)]], margin=0})
local btnClose = commonTextButton(::loc("mainmenu/btnClose"), onCloseAction,
  {hotkeys=[["{0}".subst(JB.B)]], margin=0})

local nextButton = @() {
  watch = [curPatchnoteIdx]
  size = SIZE_TO_CONTENT
  hplace = ALIGN_RIGHT
  vplace = ALIGN_BOTTOM
  padding = [blockInterval, 0, 0, blockInterval]
  children = curPatchnoteIdx.value != 0 ? btnNext : btnClose
}

local clicksHandler = {
  size = flex(),
  eventPassThrough = true,
  skipDirPadNav = true
  behavior = Behaviors.Button
  hotkeys = [
    ["J:LB", nextPatchNote],
    ["J:RB", prevPatchNote]
  ]
}

local changelogRoot = {
  size = flex()
  children = [
    blurPanel
    clicksHandler
    modalWindow({
      content = {
        size = flex()
        margin = blockInterval
        flow = FLOW_VERTICAL
        children = [
          {
            rendObj = ROBJ_BOX
            size = flex()
            flow = FLOW_VERTICAL
            borderColor = colors.menu.separatorBlockColor
            borderWidth = [0, 0, borderWidth, 0]
            padding = [0, 0, blockInterval, 0]
            children = selPatchnote
          }
          {
            size = [flex(), SIZE_TO_CONTENT]
            flow = FLOW_HORIZONTAL
            valign = ALIGN_CENTER
            children = [
              patchnoteSelector
              nextButton
            ]
          }
        ]
      },
      headerParams = {
        closeBtn = { onClick = onCloseAction }
        content = @() {
          watch = chosenPatchnoteContent
          rendObj = ROBJ_DTEXT
          font = fontsState.get("medium")
          color = colors.menu.activeTextColor
          text = chosenPatchnoteContent.value.title
          margin = [0, 0, 0, ::fpx(15)]
        }
      }
    })
  ]
}

return changelogRoot
