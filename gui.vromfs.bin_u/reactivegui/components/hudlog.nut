local colors = require("reactiveGui/style/colors.nut")
local scrollbar = require("scrollbar.nut")
local { cursorVisible } = require("reactiveGui/ctrlsState.nut")

local logContainer = @() {
  size = [flex(), SIZE_TO_CONTENT]
  gap = ::fpx(3)
  padding = [::scrn_tgt(0.005) , ::scrn_tgt(0.005)]
  flow = FLOW_VERTICAL
}

local hudLog = function (params) {
  local messageComponent = params.messageComponent
  local logComponent = params.logComponent
  local content = scrollbar.makeSideScroll(
    logComponent.data(@() logContainer, messageComponent),
    {
      scrollHandler = logComponent.scrollHandler
      barStyle = @(has_scroll) scrollbar.styling.Bar(has_scroll && cursorVisible.value)
      scrollAlign = ALIGN_LEFT
    }
  )

  return @() {
    watch = cursorVisible
    rendObj = ROBJ_SOLID
    size = [flex(), ::scrn_tgt(0.135)]
    clipChildren = true
    valign = ALIGN_BOTTOM
    color = colors.hud.hudLogBgColor
    children = content
    onAttach = @(_) logComponent.scrollHandler.scrollToY(1e10)
  }
}

return hudLog
