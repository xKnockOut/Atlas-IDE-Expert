unit Atlas.Core.Assistants.DebugInbox;

// Debuggen für KI-Assistenten über die IDE (#1874, MCP-Werkzeuge debug_start … debug_evaluate), ohne Open Tools API.
// Der MCP-Server legt je Aufruf einen Auftrag in den Eingang des Plugins:
//   %LOCALAPPDATA%\Atlas\ide-debug\<pid>\<id>.json
//   {"command": Werkzeugname, "client": clientInfo.name, …Argumente}
// Das Plugin übernimmt ihn durch Umbenennen in <id>.taken (TAtlasFileInbox, im Eingang Atlas.IDE.Assistants.DebugInbox)
// und antwortet mit <id>.result.json:
//   {"ok": true, "result": {…}}  bzw.  {"ok": false, "reason": "…"}
// "result" je Befehl: Zustand der Sitzung (debug_start, debug_stop, debug_continue, debug_step, debug_state), der
// gesetzte Haltepunkt (set_breakpoint), die Zahl der entfernten (remove_breakpoint) bzw. Wert und Typ
// (debug_evaluate); Aufbau in docs/MCP.md. Zeilen sind 1-basiert. Die Argumente hat der MCP-Server schon geprüft
// (Atlas.Common.Mcp.IdeDebug); hier zählt nur, was das Plugin braucht. Gründe kommen in der Sprache der Oberfläche
// als TAtlasDebugInboxTexts herein (Core kennt die Texttabellen nicht).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.DebugControl.Types;

type
  TAtlasDebugCommand = (Start, Stop, SetBreakpoint, RemoveBreakpoint, Resume, Step, State, Evaluate);

  /// <summary>Ein Debug-Auftrag; welche Felder gelten, hängt von Command ab.</summary>
  TAtlasDebugRequest = record
    Id: string;
    Command: TAtlasDebugCommand;
    /// <summary>clientInfo.name des MCP-Clients; '' unbekannt.</summary>
    Client: string;
    Launch: TAtlasDebugControlLaunch;
    FileName: string;
    Line: Integer;
    Condition: string;
    PassCount: Integer;
    /// <summary>remove_breakpoint: Kennung oder alle.</summary>
    BreakpointId: Integer;
    All: Boolean;
    StepKind: TAtlasDebugControlStep;
    WaitSeconds: Integer;
    Frames: Integer;
    Locals: Boolean;
    Expression: string;
    SideEffects: Boolean;
  end;

  /// <summary>Gründe, aus denen ein Auftrag nicht lesbar ist, in der Sprache der Oberfläche.</summary>
  TAtlasDebugInboxTexts = record
    Unreadable: string;
    /// <summary>Format mit %s für den Befehl.</summary>
    UnknownCommand: string;
  end;

  TAtlasDebugInbox = class
  public const
    cCommandNames: array[TAtlasDebugCommand] of string = ('debug_start', 'debug_stop', 'set_breakpoint',
      'remove_breakpoint', 'debug_continue', 'debug_step', 'debug_state', 'debug_evaluate');
    cStepNames: array[TAtlasDebugControlStep] of string = ('into', 'over', 'out', 'toLine');
    cPhaseNames: array[TAtlasDebugControlPhase] of string = ('none', 'running', 'stopped');
    cTerminated = 'terminated';
    cDefaultWaitSeconds = 10;
    cDefaultFrames = 20;
  public
    /// <summary>Eingang des Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string; APid: Cardinal): string; static;
    class function CommandOf(const AName: string; out ACommand: TAtlasDebugCommand): Boolean; static;
    class function StepOf(const AName: string; out AKind: TAtlasDebugControlStep): Boolean; static;
    /// <summary>Liest einen Auftrag; False mit Grund in AReason.</summary>
    class function ParseRequest(const AText: string; const ATexts: TAtlasDebugInboxTexts;
      out ARequest: TAtlasDebugRequest; out AReason: string): Boolean; static;
    /// <summary>Zustand als Objekt "result": ASession, AStateName ('none', 'running', 'stopped', 'terminated') und
    /// bei einem Halt Grund, Stelle, Rahmen, Variablen und Threads aus AState. Der Aufrufer gibt es frei.</summary>
    class function StateJson(const ASession, AStateName: string; const AState: TAtlasDebugControlState):
      TJSONObject; static;
    class function BreakpointJson(const ABreakpoint: TAtlasDebugControlBreakpoint): TJSONObject; static;
    class function EvaluationJson(const AExpression, AValue, ATypeName: string): TJSONObject; static;
    class function RemovedJson(ACount: Integer): TJSONObject; static;
    /// <summary>{"ok": true, "result": AResult}; gibt AResult frei.</summary>
    class function SuccessText(AResult: TJSONObject): string; static;
    /// <summary>{"ok": false, "reason": …}.</summary>
    class function RefusalText(const AReason: string): string; static;
  end;

implementation

uses
  // Inline-Funktionen von TJSONObject (H2443).
  System.Generics.Collections,
  System.IOUtils;

{ TAtlasDebugInbox }

class function TAtlasDebugInbox.Folder(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-debug'), IntToStr(APid));
end;

class function TAtlasDebugInbox.CommandOf(const AName: string; out ACommand: TAtlasDebugCommand): Boolean;
var
  mCommand: TAtlasDebugCommand;
begin
  ACommand := TAtlasDebugCommand.State;
  for mCommand := Low(TAtlasDebugCommand) to High(TAtlasDebugCommand) do
  begin
    if SameText(cCommandNames[mCommand], AName) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugInbox.StepOf(const AName: string; out AKind: TAtlasDebugControlStep): Boolean;
var
  mKind: TAtlasDebugControlStep;
begin
  AKind := TAtlasDebugControlStep.Over;
  if AName = '' then
  begin
    Exit(True);
  end;
  for mKind := Low(TAtlasDebugControlStep) to High(TAtlasDebugControlStep) do
  begin
    if SameText(cStepNames[mKind], AName) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Felder für Start, Haltepunkte und Schritte aus ARoot.</summary>
procedure ReadPlaces(ARoot: TJSONObject; var ARequest: TAtlasDebugRequest);
begin
  ARequest.Launch.Project := ARoot.GetValue<string>('project', '');
  ARequest.Launch.Configuration := ARoot.GetValue<string>('configuration', '');
  ARequest.Launch.Platform := ARoot.GetValue<string>('platform', '');
  ARequest.Launch.Test := ARoot.GetValue<string>('test', '');
  ARequest.Launch.Arguments := ARoot.GetValue<string>('arguments', '');
  ARequest.FileName := ARoot.GetValue<string>('file', '');
  ARequest.Line := ARoot.GetValue<Integer>('line', 0);
  ARequest.Condition := ARoot.GetValue<string>('condition', '');
  ARequest.PassCount := ARoot.GetValue<Integer>('passCount', 0);
  ARequest.BreakpointId := ARoot.GetValue<Integer>('id', 0);
  ARequest.All := ARoot.GetValue<Boolean>('all', False);
end;

/// <summary>Felder für Warten, Zustand und Auswerten aus ARoot; False bei unbekannter Schrittart.</summary>
function ReadOptions(ARoot: TJSONObject; var ARequest: TAtlasDebugRequest): Boolean;
begin
  ARequest.WaitSeconds := ARoot.GetValue<Integer>('waitSeconds', TAtlasDebugInbox.cDefaultWaitSeconds);
  ARequest.Frames := ARoot.GetValue<Integer>('frames', TAtlasDebugInbox.cDefaultFrames);
  ARequest.Locals := ARoot.GetValue<Boolean>('locals', True);
  ARequest.Expression := ARoot.GetValue<string>('expression', '');
  ARequest.SideEffects := ARoot.GetValue<Boolean>('sideEffects', False);
  Result := TAtlasDebugInbox.StepOf(ARoot.GetValue<string>('kind', ''), ARequest.StepKind);
end;

class function TAtlasDebugInbox.ParseRequest(const AText: string; const ATexts: TAtlasDebugInboxTexts;
  out ARequest: TAtlasDebugRequest; out AReason: string): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mCommand: string;
begin
  ARequest := Default(TAtlasDebugRequest);
  AReason := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if not (mValue is TJSONObject) then
    begin
      AReason := ATexts.Unreadable;
      Exit(False);
    end;
    mRoot := TJSONObject(mValue);
    mCommand := mRoot.GetValue<string>('command', '');
    if not CommandOf(mCommand, ARequest.Command) then
    begin
      AReason := Format(ATexts.UnknownCommand, [mCommand]);
      Exit(False);
    end;
    ARequest.Client := mRoot.GetValue<string>('client', '');
    ReadPlaces(mRoot, ARequest);
    if not ReadOptions(mRoot, ARequest) then
    begin
      AReason := Format(ATexts.UnknownCommand, [mCommand + ' ' + mRoot.GetValue<string>('kind', '')]);
      Exit(False);
    end;
  finally
    mValue.Free;
  end;
  Result := True;
end;

function FramesJson(const AFrames: TArray<TAtlasDebugControlFrame>): TJSONArray;
var
  mFrame: TAtlasDebugControlFrame;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mFrame in AFrames do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mFrame.FileName);
    mItem.AddPair('line', TJSONNumber.Create(mFrame.Line));
    mItem.AddPair('header', mFrame.Header);
    mItem.AddPair('own', TJSONBool.Create(mFrame.Own));
    Result.AddElement(mItem);
  end;
end;

function LocalsJson(const ALocals: TArray<TAtlasDebugControlVariable>): TJSONArray;
var
  mVariable: TAtlasDebugControlVariable;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mVariable in ALocals do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mVariable.Name);
    mItem.AddPair('type', mVariable.TypeName);
    mItem.AddPair('value', mVariable.Value);
    Result.AddElement(mItem);
  end;
end;

function ThreadsJson(const AThreads: TArray<TAtlasDebugControlThread>): TJSONArray;
var
  mThread: TAtlasDebugControlThread;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mThread in AThreads do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('id', TJSONNumber.Create(mThread.Id));
    mItem.AddPair('name', mThread.Name);
    mItem.AddPair('current', TJSONBool.Create(mThread.Current));
    Result.AddElement(mItem);
  end;
end;

/// <summary>Grund des Halts samt Exception.</summary>
function StopJson(const AState: TAtlasDebugControlState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('reason', AState.StopReason);
  if AState.ExceptionClass <> '' then
  begin
    Result.AddPair('exceptionClass', AState.ExceptionClass);
    Result.AddPair('exceptionMessage', AState.ExceptionMessage);
  end;
end;

class function TAtlasDebugInbox.StateJson(const ASession, AStateName: string;
  const AState: TAtlasDebugControlState): TJSONObject;
var
  mLocation: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('session', ASession);
  Result.AddPair('state', AStateName);
  if AState.Phase <> TAtlasDebugControlPhase.Stopped then
  begin
    Exit;
  end;
  Result.AddPair('stop', StopJson(AState));
  if AState.FileName <> '' then
  begin
    mLocation := TJSONObject.Create;
    mLocation.AddPair('file', AState.FileName);
    mLocation.AddPair('line', TJSONNumber.Create(AState.Line));
    Result.AddPair('location', mLocation);
  end;
  Result.AddPair('frames', FramesJson(AState.Frames));
  Result.AddPair('locals', LocalsJson(AState.Locals));
  Result.AddPair('threads', ThreadsJson(AState.Threads));
end;

class function TAtlasDebugInbox.BreakpointJson(const ABreakpoint: TAtlasDebugControlBreakpoint): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ABreakpoint.Id));
  Result.AddPair('file', ABreakpoint.FileName);
  Result.AddPair('line', TJSONNumber.Create(ABreakpoint.Line));
  Result.AddPair('valid', TJSONBool.Create(ABreakpoint.Valid));
  Result.AddPair('group', cAtlasDebugControlGroup);
end;

class function TAtlasDebugInbox.EvaluationJson(const AExpression, AValue, ATypeName: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('expression', AExpression);
  Result.AddPair('value', AValue);
  Result.AddPair('type', ATypeName);
end;

class function TAtlasDebugInbox.RemovedJson(ACount: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('removed', TJSONNumber.Create(ACount));
end;

class function TAtlasDebugInbox.SuccessText(AResult: TJSONObject): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('ok', TJSONBool.Create(True));
    mRoot.AddPair('result', AResult);
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasDebugInbox.RefusalText(const AReason: string): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('ok', TJSONBool.Create(False));
    mRoot.AddPair('reason', AReason);
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

end.
