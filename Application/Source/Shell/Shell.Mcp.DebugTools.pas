unit Shell.Mcp.DebugTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeuge zum Debuggen in der laufenden IDE für KI-Assistenten
// (#1874): debug_start, debug_stop, set_breakpoint, remove_breakpoint, debug_continue, debug_step, debug_state und
// debug_evaluate. Argumente prüft Atlas.Common.Mcp.IdeDebug, den Austausch mit dem Plugin Shell.Mcp.Ide.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet die acht Debug-Werkzeuge an.</summary>
procedure RegisterDebugTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.IdeDebug,
  Shell.Mcp.Ide,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpDebugText = (StartTool, StartProject, StartConfiguration, StartPlatform, StartTest, StartArguments, WaitSeconds,
    StopTool, SetBreakpointTool, BreakpointFile, BreakpointLine, BreakpointCondition, BreakpointPassCount,
    RemoveBreakpointTool, RemoveId, RemoveAll, ContinueTool, StepTool, StepKind, StepFile, StepLine, StateTool,
    StateFrames, StateLocals, EvaluateTool, EvaluateExpression, EvaluateSideEffects);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpDebugText] of TAtlasText = (
    (De: 'Startet ein Projekt im Debugger der laufenden RAD-Studio-IDE über das Atlas-Plugin (#1874) und wartet ' +
      'bis zum ersten Halt (Haltepunkt, Exception), zum Ende oder bis waitSeconds. Liefert Sitzung und Zustand ' +
      '(running, stopped, terminated) wie debug_state. Das Projekt muss in der IDE offen sein; der Benutzer muss ' +
      '„Debuggen durch KI-Assistenten (MCP)“ eingeschaltet haben. Haltepunkte vorher mit set_breakpoint setzen.';
     En: 'Starts a project in the debugger of the running RAD Studio IDE through the Atlas plugin (#1874) and ' +
      'waits for the first stop (breakpoint, exception), the end or waitSeconds. Returns session and state ' +
      '(running, stopped, terminated) like debug_state. The project must be open in the IDE; the user must have ' +
      'switched on "Debugging by AI assistants (MCP)". Set breakpoints with set_breakpoint first.'),
    (De: 'Projekt (.dproj mit Pfad, Dateiname oder Name); leer = aktives Projekt der IDE';
     En: 'Project (.dproj with path, file name or name); empty = active project of the IDE'),
    (De: 'z. B. Debug; leer = aktive Konfiguration'; En: 'e.g. Debug; empty = active configuration'),
    (De: 'z. B. Win32 oder Win64; leer = aktive Plattform'; En: 'e.g. Win32 or Win64; empty = active platform'),
    (De: 'Nur diesen DUnitX-Test starten: Unit.Fixture.Methode (oder Unit.Fixture)';
     En: 'Start only this DUnitX test: Unit.Fixture.Method (or Unit.Fixture)'),
    (De: 'Kommandozeilenparameter des Programms'; En: 'Command line parameters of the program'),
    (De: 'So lange auf den nächsten Halt warten (Sekunden, 0 bis 300, Vorgabe 10); danach Zustand running';
     En: 'Wait this long for the next stop (seconds, 0 to 300, default 10); after that state running'),
    (De: 'Beendet das vom KI-Assistenten gestartete Programm und entfernt seine Haltepunkte (Gruppe Atlas-KI). ' +
      'Haltepunkte des Benutzers bleiben.';
     En: 'Ends the program started by the AI assistant and removes its breakpoints (group Atlas-KI). Breakpoints ' +
      'of the user stay.'),
    (De: 'Setzt einen Haltepunkt (Gruppe Atlas-KI) und meldet Kennung und ob er gültig ist (Zeile mit Code). ' +
      'Optional mit Bedingung und Durchlaufzahl.';
     En: 'Sets a breakpoint (group Atlas-KI) and reports its id and whether it is valid (line with code). ' +
      'Optionally with condition and pass count.'),
    (De: 'Datei unter dem Arbeitsordner'; En: 'File below the working folder'),
    (De: 'Zeile ab 1'; En: 'Line from 1'),
    (De: 'Bedingung in Delphi-Syntax, z. B. I > 10'; En: 'Condition in Delphi syntax, e.g. I > 10'),
    (De: 'Erst beim n-ten Durchlauf halten; 0 = immer'; En: 'Stop only on the n-th pass; 0 = always'),
    (De: 'Entfernt einen Haltepunkt des KI-Assistenten (id) oder alle (all). Haltepunkte des Benutzers bleiben.';
     En: 'Removes one breakpoint of the AI assistant (id) or all (all). Breakpoints of the user stay.'),
    (De: 'Kennung aus set_breakpoint'; En: 'Id from set_breakpoint'),
    (De: 'Alle Haltepunkte des KI-Assistenten'; En: 'All breakpoints of the AI assistant'),
    (De: 'Lässt das angehaltene Programm weiterlaufen und wartet bis zum nächsten Halt, zum Ende oder bis ' +
      'waitSeconds. Liefert den Zustand wie debug_state.';
     En: 'Lets the stopped program run on and waits for the next stop, the end or waitSeconds. Returns the state ' +
      'like debug_state.'),
    (De: 'Ein Schritt im angehaltenen Programm: into (in Aufrufe hinein), over (Zeile), out (bis zum Rücksprung) ' +
      'oder toLine (bis file/line). Wartet bis zum Halt und liefert den Zustand wie debug_state.';
     En: 'One step in the stopped program: into (into calls), over (line), out (until return) or toLine (to ' +
      'file/line). Waits for the stop and returns the state like debug_state.'),
    (De: 'into, over (Vorgabe), out oder toLine'; En: 'into, over (default), out or toLine'),
    (De: 'Datei für toLine'; En: 'File for toLine'),
    (De: 'Zeile für toLine, ab 1'; En: 'Line for toLine, from 1'),
    (De: 'Zustand der Debug-Sitzung: running, stopped oder terminated; bei stopped Grund (Haltepunkt, Schritt, ' +
      'Exception mit Klasse und Text), aktuelle Stelle, Aufrufstapel mit Dateien und Zeilen (eigener Code ' +
      'markiert), lokale Variablen und Threads. Lesend.';
     En: 'State of the debug session: running, stopped or terminated; when stopped the reason (breakpoint, step, ' +
      'exception with class and text), current location, call stack with files and lines (own code marked), ' +
      'local variables and threads. Read-only.'),
    (De: 'Anzahl Rahmen des Aufrufstapels (1 bis 200, Vorgabe 20)';
     En: 'Number of call stack frames (1 to 200, default 20)'),
    (De: 'Lokale Variablen des aktuellen Rahmens mitliefern (Vorgabe true)';
     En: 'Include local variables of the current frame (default true)'),
    (De: 'Wertet einen Ausdruck im aktuellen Rahmen des angehaltenen Programms aus und liefert Wert und Typ. Ohne ' +
      'sideEffects nur Felder und Variablen; Ausdrücke mit Aufrufen oder Zuweisungen lehnt das Plugin mit ' +
      'Begründung ab, solange der Benutzer sie nicht erlaubt hat.';
     En: 'Evaluates an expression in the current frame of the stopped program and returns value and type. ' +
      'Without sideEffects only fields and variables; the plugin refuses expressions with calls or assignments ' +
      'with a reason as long as the user has not allowed them.'),
    (De: 'Ausdruck in Delphi-Syntax'; En: 'Expression in Delphi syntax'),
    (De: 'Aufrufe (Getter, Funktionen) erlauben; Vorgabe false. Braucht die Einstellung des Benutzers.';
     En: 'Allow calls (getters, functions); default false. Needs the user''s setting.'));

  cWaitProperty = '"waitSeconds":{"type":"integer","minimum":0,"maximum":300,"description":%s}';

function DebugTool(const AContext: TMcpToolContext; const ATool: string; const AArguments: TJSONObject): string;
var
  mGuard: TMcpPathGuard;
begin
  mGuard := AContext.Guard;
  Result := DebugInIde(AContext.Root, ATool, AContext.Group.ProcessIdentity.Client, TMcpArgs.OptionalString(AArguments, 'project'),
    AArguments,
    function(AFile: string): string
    begin
      Result := mGuard.Resolve(AFile);
    end);
end;

function ToolStart(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cStart, AArguments);
end;

function ToolStop(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cStop, AArguments);
end;

function ToolSetBreakpoint(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cSetBreakpoint, AArguments);
end;

function ToolRemoveBreakpoint(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cRemoveBreakpoint, AArguments);
end;

function ToolContinue(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cContinue, AArguments);
end;

function ToolStep(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cStep, AArguments);
end;

function ToolState(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cState, AArguments);
end;

function ToolEvaluate(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := DebugTool(AContext, TMcpIdeDebug.cEvaluate, AArguments);
end;

function Text(AId: TMcpDebugText): string;
begin
  Result := cTexts[AId].Text;
end;

procedure AddStartAndStop(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpIdeDebug.cStart, Text(TMcpDebugText.StartTool),
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"configuration":{"type":"string","description":%s},' +
      '"platform":{"type":"string","description":%s},' +
      '"test":{"type":"string","description":%s},' +
      '"arguments":{"type":"string","description":%s},' + cWaitProperty + '}}',
      [Text(TMcpDebugText.StartProject), Text(TMcpDebugText.StartConfiguration), Text(TMcpDebugText.StartPlatform),
      Text(TMcpDebugText.StartTest), Text(TMcpDebugText.StartArguments), Text(TMcpDebugText.WaitSeconds)]),
    ContextTool(AContext, ToolStart), TMcpToolKind.Process);
  AContext.Server.AddTool(TMcpIdeDebug.cStop, Text(TMcpDebugText.StopTool), '{"type":"object","properties":{}}',
    ContextTool(AContext, ToolStop), TMcpToolKind.Process);
end;

procedure AddBreakpoints(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpIdeDebug.cSetBreakpoint, Text(TMcpDebugText.SetBreakpointTool),
    SchemaWith('{"type":"object","properties":{' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"condition":{"type":"string","description":%s},' +
      '"passCount":{"type":"integer","minimum":0,"description":%s}},"required":["file","line"]}',
      [Text(TMcpDebugText.BreakpointFile), Text(TMcpDebugText.BreakpointLine),
      Text(TMcpDebugText.BreakpointCondition), Text(TMcpDebugText.BreakpointPassCount)]),
    ContextTool(AContext, ToolSetBreakpoint), TMcpToolKind.Process);
  AContext.Server.AddTool(TMcpIdeDebug.cRemoveBreakpoint, Text(TMcpDebugText.RemoveBreakpointTool),
    SchemaWith('{"type":"object","properties":{' +
      '"id":{"type":"integer","minimum":1,"description":%s},' +
      '"all":{"type":"boolean","description":%s}}}',
      [Text(TMcpDebugText.RemoveId), Text(TMcpDebugText.RemoveAll)]),
    ContextTool(AContext, ToolRemoveBreakpoint), TMcpToolKind.Process);
end;

procedure AddRun(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpIdeDebug.cContinue, Text(TMcpDebugText.ContinueTool),
    SchemaWith('{"type":"object","properties":{' + cWaitProperty + '}}', [Text(TMcpDebugText.WaitSeconds)]),
    ContextTool(AContext, ToolContinue), TMcpToolKind.Process);
  AContext.Server.AddTool(TMcpIdeDebug.cStep, Text(TMcpDebugText.StepTool),
    SchemaWith('{"type":"object","properties":{' +
      '"kind":{"type":"string","enum":["into","over","out","toLine"],"default":"over","description":%s},' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' + cWaitProperty + '}}',
      [Text(TMcpDebugText.StepKind), Text(TMcpDebugText.StepFile), Text(TMcpDebugText.StepLine),
      Text(TMcpDebugText.WaitSeconds)]),
    ContextTool(AContext, ToolStep), TMcpToolKind.Process);
end;

procedure AddInspect(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpIdeDebug.cState, Text(TMcpDebugText.StateTool),
    SchemaWith('{"type":"object","properties":{' +
      '"frames":{"type":"integer","minimum":1,"maximum":200,"default":20,"description":%s},' +
      '"locals":{"type":"boolean","default":true,"description":%s}}}',
      [Text(TMcpDebugText.StateFrames), Text(TMcpDebugText.StateLocals)]),
    ContextTool(AContext, ToolState), TMcpToolKind.Process);
  AContext.Server.AddTool(TMcpIdeDebug.cEvaluate, Text(TMcpDebugText.EvaluateTool),
    SchemaWith('{"type":"object","properties":{' +
      '"expression":{"type":"string","description":%s},' +
      '"sideEffects":{"type":"boolean","default":false,"description":%s}},"required":["expression"]}',
      [Text(TMcpDebugText.EvaluateExpression), Text(TMcpDebugText.EvaluateSideEffects)]),
    ContextTool(AContext, ToolEvaluate), TMcpToolKind.Process);
end;

procedure RegisterDebugTools(const AContext: TMcpToolContext);
begin
  AddStartAndStop(AContext);
  AddBreakpoints(AContext);
  AddRun(AContext);
  AddInspect(AContext);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.DebugTools', cTexts);

end.
