nsync = require 'nsync-fs'
shell = require 'shell'
atomHelper = require './atom-helper'
WebWindow = require './web-window'
{ipcRenderer} = require 'electron'

commandStrategies = {
  browser_open: ({url}) ->
    shell.openExternal(url)

  atom_open: ({path}) ->
    node = nsync.getNode(path)
    if node?
      atomHelper.open(node.localPath()).then ->
        atomHelper.termFocus()

  open_lab: ({lab_name}) ->
    localStorage.setItem('learnOpenLabOnActivation', lab_name)
    ipcRenderer.send('command', 'application:new-window')

  learn_submit: ({url}) ->
    new WebWindow(url, {resizable: false})
}

module.exports = executeCustomCommand = (data) ->
  {command} = data
  strategy = commandStrategies[command]

  if not strategy?
    console.warn 'No strategy for custom command:', command, data
  else
    strategy(data)

