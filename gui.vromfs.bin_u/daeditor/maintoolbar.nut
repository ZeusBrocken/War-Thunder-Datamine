from "%darg/ui_imports.nut" import *
from "%darg/laconic.nut" import *
local {showEntitySelect, propPanelVisible, showHelp, de4editMode, showUIinEditor} = require("state.nut")
local pictureButton = require("components/pictureButton.nut")
local cursors =  require("components/cursors.nut")
local daEditor4 = require("daEditor4")
local {DE4_MODE_CREATE_ENTITY, get_instance} = require("entity_editor")
local {DE4_MODE_MOVE, DE4_MODE_ROTATE, DE4_MODE_SCALE, DE4_MODE_SELECT, getEditMode, setEditMode} = daEditor4

local function toolbarButton(image, action, tooltip_text, checked=null) {
  local function onHover(on) {
    cursors.setTooltip(on ? tooltip_text : null)
  }
  local defParams = {
    imageMargin = fsh(0.5)
    action = action
    checked = checked
    onHover = onHover
  }
  local params = (type(image)=="table") ? defParams.__merge(image) : defParams.__merge({image=image})
  return pictureButton(params)
}

local function modeButton(image, mode, tooltip_text, next_action=null) {
  local params = (type(image)=="table") ? image : {image}
  params = params.__merge({
    checked = mode==getEditMode()
    imageMargin = fsh(0.5)
    function onHover(on) {
      cursors.setTooltip(on ? tooltip_text : null)
    }
    function action() {
      showEntitySelect.update(false)
      daEditor4.setEditMode(mode)
      if (next_action)
        next_action()
    }
  })
  return pictureButton(params)
}


local separator = {
  rendObj = ROBJ_SOLID
  color = Color(100, 100, 100, 100)
  size = [1, fsh(3)]
  margin = [0, fsh(0.5)]
}

local svg = @(name) {image = $"!%daeditor/images/{name}.svg"} //Atlas is not working %daeditor/editor#
local function mainToolbar() {
  local function toggleEntitySelect() {
    if (getEditMode() == DE4_MODE_CREATE_ENTITY)
      setEditMode(DE4_MODE_SELECT)
    showEntitySelect.update(!showEntitySelect.value);
  }
  local togglePropPanel = @() propPanelVisible.update(!propPanelVisible.value)
  local toggleHelp = @() showHelp.update(!showHelp.value)

  return {
    size = [sw(100), SIZE_TO_CONTENT]
    flow = FLOW_HORIZONTAL
    rendObj = ROBJ_WORLD_BLUR
    color = Color(150, 150, 150, 255)
    watch = de4editMode
    valign = ALIGN_CENTER
    padding =hdpx(4)

    children = [
//      comp(Watch(scenePath), txt(scenePath.value, {color = Color(170,170,170), padding=[0, hdpx(10)], maxWidth = sw(15)}), ClipChildren)
      toolbarButton(svg("select_by_name"), toggleEntitySelect, "Select by name", showEntitySelect.value)
      separator
      modeButton(svg("select"), DE4_MODE_SELECT, "Select")
      modeButton(svg("move"), DE4_MODE_MOVE, "Move")
      modeButton(svg("rotate"), DE4_MODE_ROTATE, "Rotate") //rotate or mirror, make blue
      modeButton(svg("scale"), DE4_MODE_SCALE, "Scale")
      modeButton(svg("create"), DE4_MODE_CREATE_ENTITY, "Create entity")
      separator
      toolbarButton(svg("properties"), togglePropPanel, "Property panel", propPanelVisible.value)
      toolbarButton(svg("hide"), @() get_instance().hideSelectedTemplate(), "Hide")
      toolbarButton(svg("show"), @() get_instance().unhideAll(), "Unhide all")
      separator
      toolbarButton(svg("gui_toggle"), @() showUIinEditor(!showUIinEditor.value), "Switch UI visibility")
      separator
      toolbarButton(svg("save"), @() get_instance().saveObjects(""), "Save")
      toolbarButton(svg("help"), toggleHelp, "Help", showHelp.value)
    ]

    hotkeys = [
      ["L.Alt H", toggleEntitySelect],
      ["F1", toggleHelp],
    ]
  }
}


return mainToolbar
