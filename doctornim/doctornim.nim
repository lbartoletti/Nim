#
#
#            Doctor Nim
#        (c) Copyright 2020 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

when false:
  # ICON linking
  when defined(gcc) and defined(windows):
    when defined(x86):
      {.link: "../icons/nim.res".}
    else:
      {.link: "../icons/nim_icon.o".}

  when defined(amd64) and defined(windows) and defined(vcc):
    {.link: "../icons/nim-amd64-windows-vcc.res".}
  when defined(i386) and defined(windows) and defined(vcc):
    {.link: "../icons/nim-i386-windows-vcc.res".}

import std / [
  parseopt, strutils, os
]

import ".." / compiler / [
  ast, astalgo,
  commands, options, msgs,
  extccomp,
  idents, lineinfos, cmdlinehelper, modulegraphs, condsyms,
  pathutils, passes, passaux, sem, modules
]

import z3

#proc nodeToZ3(n: PNode): Z3_ast =

proc proofEngine(graph: ModuleGraph; assumptions: seq[PNode]; a, b: PNode): (bool, string) =
  # question to answer: Is 'a <= b'?
  result = (false, "needs to be implemented")
  if a.kind == nkIntLit and b.kind == nkIntLit:
    z3:
      let x = Int("x")
      let y = Int("y")

      let s = Solver()
      #for assumption in assumptions:
      #  s.assert nodeToZ3(assumption)

      s.assert x == a.intVal
      s.assert y == b.intVal
      s.assert x <= y

      result[0] = s.check() == Z3_L_TRUE
      if not result[0]:
        result[1] = $s.get_model()

proc mainCommand(graph: ModuleGraph) =
  graph.proofEngine = proofEngine

  graph.config.errorMax = high(int)  # do not stop after first error
  defineSymbol(graph.config.symbols, "nimcheck")

  registerPass graph, verbosePass
  registerPass graph, semPass
  compileProject(graph)


proc prependCurDir(f: AbsoluteFile): AbsoluteFile =
  when defined(unix):
    if os.isAbsolute(f.string): result = f
    else: result = AbsoluteFile("./" & f.string)
  else:
    result = f

proc addCmdPrefix*(result: var string, kind: CmdLineKind) =
  # consider moving this to std/parseopt
  case kind
  of cmdLongOption: result.add "--"
  of cmdShortOption: result.add "-"
  of cmdArgument, cmdEnd: discard

proc processCmdLine(pass: TCmdLinePass, cmd: string; config: ConfigRef) =
  var p = parseopt.initOptParser(cmd)
  var argsCount = 1

  config.commandLine.setLen 0
  config.command = "check"
  config.cmd = cmdCheck

  while true:
    parseopt.next(p)
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      config.commandLine.add " "
      config.commandLine.addCmdPrefix p.kind
      config.commandLine.add p.key.quoteShell # quoteShell to be future proof
      if p.val.len > 0:
        config.commandLine.add ':'
        config.commandLine.add p.val.quoteShell

      if p.key == " ":
        p.key = "-"
        if processArgument(pass, p, argsCount, config): break
      else:
        processSwitch(pass, p, config)
    of cmdArgument:
      config.commandLine.add " "
      config.commandLine.add p.key.quoteShell
      if processArgument(pass, p, argsCount, config): break
  if pass == passCmd2:
    if {optRun, optWasNimscript} * config.globalOptions == {} and
        config.arguments.len > 0 and config.command.normalize notin ["run", "e"]:
      rawMessage(config, errGenerated, errArgsNeedRunOption)

proc handleCmdLine(cache: IdentCache; conf: ConfigRef) =
  let self = NimProg(
    supportsStdinFile: true,
    processCmdLine: processCmdLine,
    mainCommand: mainCommand
  )
  self.initDefinesProg(conf, "nim_compiler")
  if paramCount() == 0:
    writeCommandLineUsage(conf)
    return

  self.processCmdLineAndProjectPath(conf)
  if not self.loadConfigsAndRunMainCommand(cache, conf): return
  if conf.hasHint(hintGCStats): echo(GC_getStatistics())

when compileOption("gc", "v2") or compileOption("gc", "refc"):
  # the new correct mark&sweet collector is too slow :-/
  GC_disableMarkAndSweep()

when not defined(selftest):
  let conf = newConfigRef()
  handleCmdLine(newIdentCache(), conf)
  when declared(GC_setMaxPause):
    echo GC_getStatistics()
  msgQuit(int8(conf.errorCounter > 0))
