fs = require 'fs-plus'
_ = require 'underscore-plus'
_path = require 'path'
nsync = require 'nsync-fs'
remote = require 'remote'
{dialog} = require('electron').remote
atomHelper = require './atom-helper'
executeCustomCommand = require './custom-commands'
{name} = require '../../package.json'
{CompositeDisposable} = require 'event-kit'

convertEOL = (text) ->
  text.replace(/\r\n|\n|\r/g, '\n')

didAddOpener = false

unimplemented = ({type}) ->
  command = type.replace(/^learn-ide:/, '').replace(/-/g, ' ')
  atomHelper.warn 'Learn IDE: coming soon!', {detail: "Sorry, '#{command}' isn't available yet."}

onRefresh = ->
  atomHelper.resetPackage()

onSave = ->
  editor = atomHelper.findActiveTextEditor()
  path = editor?.getPath()

  if not path
    # TODO: untitled editor is saved
    return console.warn 'Cannot save file without path'

  text = convertEOL(editor.getText())

  if process.platform is 'win32'
    buffer = editor.getBuffer()
    buffer.setPreferredLineEnding('\n')
    buffer.setText(text)

  content = new Buffer(text).toString('base64')
  nsync.save(path, content)

onImport = ->
  dialog.showOpenDialog
    title: 'Import Files',
    properties: ['openFile', 'multiSelections']
  , (paths) ->
    importLocalPaths(paths)

importLocalPaths = (localPaths) ->
  localPaths = [localPaths] if typeof localPaths is 'string'
  targetPath = atomHelper.selectedPath()
  targetNode = nsync.getNode(targetPath)

  localPaths.forEach (path) ->
    fs.readFile path, 'base64', (err, data) ->
      if err?
        return console.error 'Unable to import file:', path, err

      base = _path.basename(path)
      newPath = _path.posix.join(targetNode.path, base)

      if nsync.hasPath(newPath)
        atomHelper.warn 'Learn IDE: cannot save file',
          detail: "There is already an existing remote file with path: #{newPath}"
        return

      nsync.save(newPath, data)

onEditorSave = ({path}) ->
  node = nsync.getNode(path)

  node.determineSync().then (shouldSync) ->
    if shouldSync
      atomHelper.findOrCreateBuffer(path).then (textBuffer) ->
        text = convertEOL(textBuffer.getText())
        content = new Buffer(text).toString('base64')
        nsync.save(node.path, content)

onFindAndReplace = (path) ->
  fs.readFile path, 'utf8', (err, data) ->
    if err
      return console.error 'Project Replace Error', err

    text = convertEOL(data)
    content = new Buffer(text).toString('base64')
    nsync.save(path, content)

waitForFile = (localPath, seconds) ->
  setTimeout ->
    fs.stat localPath, (err, stats) ->
      if err? and nsync.hasPath(localPath)
        waitForFile(localPath, seconds * 2)
      else
        atomHelper.resolveOpen(localPath)
  , seconds * 1000

onResetConnection = ->
  atomHelper.onResetConnection()

module.exports = helper = (activationState) ->
  composite = new CompositeDisposable

  disposables = [
    atomHelper.addCommands
      'learn-ide:save': onSave
      'learn-ide:reset-connection': onResetConnection
      'learn-ide:save-as': unimplemented
      'learn-ide:save-all': unimplemented
      'learn-ide:import': onImport
      'learn-ide:file-open': unimplemented
      'learn-ide:add-project': unimplemented
      'learn-ide-tree:refresh': onRefresh

    nsync.onDidConfigure ->
      if not didAddOpener
        didAddOpener = true
        atomHelper.addOpener (uri) ->
          fs.stat uri, (err, stats) ->
            if err? and nsync.hasPath(uri)
              atomHelper.loadingFile(uri)
              nsync.open(uri)
              waitForFile(uri, 1)

    nsync.onDidOpen ({localPath}) ->
      atomHelper.resolveOpen(localPath)

    nsync.onDidSetPrimary ({localPath, expansionState}) ->
      atomHelper.updateProject(localPath, expansionState)

    nsync.onWillLoad ->
      secondsTillNotifying = 2

      setTimeout ->
        unless nsync.hasPrimaryNode()
          atomHelper.loading()
      , secondsTillNotifying * 1000

    nsync.onDidDisconnect ->
      atomHelper.disconnected()

    nsync.onDidSendWhileDisconnected (msg) ->
        atomHelper.error 'Learn IDE: you are not connected!',
          detail: "The operation cannot be performed while disconnected {command: #{msg.command}}"

    nsync.onDidConnect ->
      atomHelper.connected()

    nsync.onDidReceiveCustomCommand (payload) ->
      executeCustomCommand(payload)

    nsync.onDidChange (path) ->
      parent = _path.dirname(path)
      atomHelper.reloadTreeView(parent, path)
      atomHelper.updateTitle()

    nsync.onDidUpdate (path) ->
      atomHelper.saveEditor(path)

    atomHelper.observeTextEditors (editor) ->
      composite.add editor.onDidSave (e) ->
        onEditorSave(e)

    atomHelper.on 'learn-ide:logout', ->
      pkg = atom.packages.loadPackage(name)

    atomHelper.onDidActivatePackage (pkg) ->
      if pkg.name is 'find-and-replace'
        projectFindView = pkg.mainModule.projectFindView
        resultModel = projectFindView.model

        composite.add resultModel.onDidReplacePath ({filePath}) ->
          onFindAndReplace(filePath)

    atomHelper.observeConnection (channel) ->
      nsync.configure
        expansionState: activationState.directoryExpansionStates
        localRoot: _path.join(atom.configDirPath, '.learn-ide')
        channel: channel

    atom.emitter.on 'learn-ide:connection-error', ->
      atomHelper.disconnected()
  ]

  disposables.forEach (disposable) -> composite.add(disposable)


  return composite

