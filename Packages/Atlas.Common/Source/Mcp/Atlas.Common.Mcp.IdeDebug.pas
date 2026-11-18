unit Atlas.Common.Mcp.IdeDebug;

// Debuggen für KI-Assistenten (MCP) in der laufenden IDE (#1874): Werkzeuge debug_start, debug_stop,
// set_breakpoint, remove_breakpoint, debug_continue, debug_step, debug_state und debug_evaluate. Der MCP-Server
// prüft die Argumente, legt je Aufruf einen Auftrag in den Eingang des Plugins und wartet auf die Antwort
// (Austausch wie bei build_project, Atlas.Common.Mcp.IdeInbox):
//   %LOCALAPPDATA%\Atlas\ide-debug\<pid>\<id>.json
//   {"command": Werkzeugname, "client": clientInfo.name, …Argumente}
// Argumente je Befehl (Zeilen ab 1, Dateien mit vollem Pfad):
//   debug_start        project, configuration, platform, test, arguments, waitSeconds
//   debug_stop         –
//   set_breakpoint     file, line, condition, passCount
//   remove_breakpoint  id oder all
//   debug_continue     waitSeconds
//   debug_step         kind (into, over, out, toLine), file und line bei toLine, waitSeconds
//   debug_state        frames, locals
//   debug_evaluate     expression, sideEffects
// Antwort des Plugins: {"ok": true, "result": {…}} bzw. {"ok": false, "reason": "…"}. "result" geht unverändert an
// den MCP-Client; seinen Aufbau beschreibt docs/MCP.md. Nimmt das Plugin nicht binnen cTakeMs an (abgeschaltet,
// andere Sitzung, Pause für KI), nennt das Werkzeug den Grund.
// Gegenstück im Plugin: Atlas.Core.Assistants.DebugInbox.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.IdeInbox;

type
  TMcpIdeDebugOutcome = (Done, NotTaken, Refused, TimedOut);

  /// <summary>Löst einen Dateinamen aus den Argumenten in einen vollen Pfad unter dem Arbeitsordner auf; wirft bei
  /// Pfaden außerhalb.</summary>
  TMcpIdeDebugResolve = TFunc<string, string>;

  /// <summary>Ein Aufruf: Werkzeug, clientInfo.name und das Projekt, das der Aufrufer für debug_start gewählt hat.
  /// </summary>
  TMcpIdeDebugCall = record
    Tool: string;
    Client: string;
    Project: string;
    class function Make(const ATool, AClient, AProject: string): TMcpIdeDebugCall; static;
  end;

  TMcpIdeDebug = class
  public const
    /// <summary>So lange darf das Plugin bis zur Übernahme brauchen.</summary>
    cTakeMs = 5000;
    /// <summary>Frist für die Antwort nach der Übernahme, zusätzlich zu waitSeconds.</summary>
    cAnswerMs = 30 * 1000;
    cPollMs = 100;
    /// <summary>Vorgabe und Höchstwert für waitSeconds (Warten auf den nächsten Halt).</summary>
    cWaitDefault = 10;
    cWaitMax = 300;
    /// <summary>Vorgabe und Höchstwert für frames in debug_state.</summary>
    cFramesDefault = 20;
    cFramesMax = 200;
    cStart = 'debug_start';
    cStop = 'debug_stop';
    cSetBreakpoint = 'set_breakpoint';
    cRemoveBreakpoint = 'remove_breakpoint';
    cContinue = 'debug_continue';
    cStep = 'debug_step';
    cState = 'debug_state';
    cEvaluate = 'debug_evaluate';
  public
    /// <summary>Eingang des IDE-Prozesses APid unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function InboxOf(const ABase: string; APid: Cardinal): string; static;
    /// <summary>Die acht Werkzeuge in der Reihenfolge von tools/list.</summary>
    class function Tools: TArray<string>; static;
    /// <summary>Prüft die Argumente von ACall.Tool und baut den Auftrag. AResolve macht aus "file" einen vollen
    /// Pfad. "project" von debug_start kommt aus ACall.Project (nach der Wahl der IDE). False mit Grund.</summary>
    class function RequestText(const ACall: TMcpIdeDebugCall; const AArguments: TJSONObject;
      const AResolve: TMcpIdeDebugResolve; out AText, AReason: string): Boolean; static;
    /// <summary>Grund, wenn keine IDE mit Atlas-Plugin läuft.</summary>
    class function NoIdeReason: string; static;
    /// <summary>Frist für die Antwort nach der Übernahme: cAnswerMs plus waitSeconds.</summary>
    class function AnswerMs(const AArguments: TJSONObject): Int64; static;
    /// <summary>Liest die Antwort des Plugins; AResultText = Objekt "result" als JSON-Text.</summary>
    class function ParseAnswer(const AText: string; out AOk: Boolean; out AResultText, AReason: string): Boolean;
      static;
    /// <summary>Legt den Auftrag in AInbox und wartet auf das Plugin. Done: AResultText enthält das Ergebnis.
    /// Sonst Grund in AReason.</summary>
    class function Send(const AInbox, ARequestText: string; const AWaiting: TMcpIdeWaiting;
      out AResultText, AReason: string): TMcpIdeDebugOutcome; static;
  end;

implementation

uses
  // Inline-Funktionen von TJSONObject (H2443).
  System.Generics.Collections,
  System.IOUtils,
  Atlas.Text.Json,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIdeDebugText = (UnknownTool, LineMissing, ExpressionMissing, KindInvalid, ToLineNeedsPlace, IdOrAll,
    NumberRange, NotTaken, TimedOut, NoResult, Unreadable, NoIde);

const
  cTexts: array[TIdeDebugText] of TAtlasText = (
    (De: 'Unbekanntes Debug-Werkzeug "%s".'; En: 'Unknown debug tool "%s".'),
    (De: 'Argument "line": ganze Zahl ab 1 erwartet.'; En: 'Argument "line": integer from 1 expected.'),
    (De: 'Argument "expression" fehlt.'; En: 'Argument "expression" is missing.'),
    (De: 'Argument "kind": erlaubt sind into, over, out und toLine.';
     En: 'Argument "kind": allowed are into, over, out and toLine.'),
    (De: 'kind "toLine" braucht "file" und "line".'; En: 'kind "toLine" needs "file" and "line".'),
    (De: 'Entweder "id" (ab 1) oder "all": true angeben.'; En: 'Give either "id" (from 1) or "all": true.'),
    (De: 'Argument "%s": ganze Zahl von %d bis %d erwartet.'; En: 'Argument "%s": integer from %d to %d expected.'),
    (De: 'Die IDE hat den Debug-Auftrag nicht angenommen. In den Einstellungen unter „KI-Assistenten“ ' +
      '„Debuggen durch KI-Assistenten (MCP)“ einschalten; vielleicht hat der Benutzer auch „Pause für KI“ gedrückt ' +
      'oder das Plugin ist zu alt.';
     En: 'The IDE did not accept the debug request. Switch on "Debugging by AI assistants (MCP)" under "AI ' +
      'assistants" in the settings; maybe the user also pressed "Pause for AI" or the plugin is too old.'),
    (De: 'Die IDE hat den Debug-Auftrag angenommen, aber nicht rechtzeitig geantwortet.';
     En: 'The IDE accepted the debug request but did not answer in time.'),
    (De: 'Die IDE hat kein Ergebnis geliefert.'; En: 'The IDE delivered no result.'),
    (De: 'Antwort der IDE nicht lesbar.'; En: 'Answer of the IDE not readable.'),
    (De: 'Keine RAD-Studio-IDE mit Atlas-Plugin läuft. Debuggen geht nur über die IDE: das Projekt dort öffnen und ' +
      'erneut aufrufen.';
     En: 'No RAD Studio IDE with the Atlas plugin is running. Debugging works only through the IDE: open the ' +
      'project there and call again.'));

type
  /// <summary>Erlaubte ganze Zahlen eines Arguments und die Vorgabe ohne Angabe.</summary>
  TNumberRange = record
    Min: Integer;
    Max: Integer;
    Default: Integer;
  end;

function Range(AMin, AMax, ADefault: Integer): TNumberRange;
begin
  Result.Min := AMin;
  Result.Max := AMax;
  Result.Default := ADefault;
end;

{ TMcpIdeDebugCall }

class function TMcpIdeDebugCall.Make(const ATool, AClient, AProject: string): TMcpIdeDebugCall;
begin
  Result.Tool := ATool;
  Result.Client := AClient;
  Result.Project := AProject;
end;

{ TMcpIdeDebug }

class function TMcpIdeDebug.InboxOf(const ABase: string; APid: Cardinal): string;
begin
  Result := TPath.Combine(TPath.Combine(ABase, 'ide-debug'), IntToStr(APid));
end;

class function TMcpIdeDebug.Tools: TArray<string>;
begin
  Result := TArray<string>.Create(cStart, cStop, cSetBreakpoint, cRemoveBreakpoint, cContinue, cStep, cState,
    cEvaluate);
end;

/// <summary>Ganzzahliges Argument AName in ARange, ohne Angabe die Vorgabe; False mit Grund bei anderem Wert.
/// </summary>
function ArgumentInRange(const AArguments: TJSONObject; const AName: string; const ARange: TNumberRange;
  out AValue: Integer; out AReason: string): Boolean;
var
  mValue: TJSONValue;
  mNumber: Int64;
begin
  AValue := ARange.Default;
  AReason := '';
  mValue := TJsonRead.Value(AArguments, AName);
  if (mValue = nil) or (mValue is TJSONNull) then
  begin
    Exit(True);
  end;
  Result := (mValue is TJSONNumber) and TJsonRead.TryInt64(AArguments, AName, mNumber) and
    (mNumber >= ARange.Min) and (mNumber <= ARange.Max);
  if Result then
  begin
    AValue := Integer(mNumber);
  end
  else
  begin
    AReason := cTexts[TIdeDebugText.NumberRange].Fmt([AName, ARange.Min, ARange.Max]);
  end;
end;

/// <summary>waitSeconds übernehmen.</summary>
function AddWait(ARequest, AArguments: TJSONObject; out AReason: string): Boolean;
var
  mWait: Integer;
begin
  Result := ArgumentInRange(AArguments, 'waitSeconds', Range(0, TMcpIdeDebug.cWaitMax, TMcpIdeDebug.cWaitDefault), mWait,
    AReason);
  ARequest.AddPair('waitSeconds', TJSONNumber.Create(mWait));
end;

/// <summary>Stelle aus file und line; beide sind Pflicht.</summary>
function AddPlace(ARequest, AArguments: TJSONObject; const AResolve: TMcpIdeDebugResolve;
  out AReason: string): Boolean;
var
  mLine: Integer;
  mFile: string;
begin
  mFile := TJsonRead.TrimmedText(AArguments, 'file');
  if not ArgumentInRange(AArguments, 'line', Range(1, MaxInt, 0), mLine, AReason) or (mLine < 1) then
  begin
    AReason := cTexts[TIdeDebugText.LineMissing].Text;
    Exit(False);
  end;
  if mFile = '' then
  begin
    AReason := cTexts[TIdeDebugText.ToLineNeedsPlace].Text;
    Exit(False);
  end;
  ARequest.AddPair('file', AResolve(mFile));
  ARequest.AddPair('line', TJSONNumber.Create(mLine));
  Result := True;
end;

function AddStart(ARequest, AArguments: TJSONObject; const AProject: string; out AReason: string): Boolean;
begin
  ARequest.AddPair('project', AProject);
  ARequest.AddPair('configuration', TJsonRead.TrimmedText(AArguments, 'configuration'));
  ARequest.AddPair('platform', TJsonRead.TrimmedText(AArguments, 'platform'));
  ARequest.AddPair('test', TJsonRead.TrimmedText(AArguments, 'test'));
  ARequest.AddPair('arguments', TJsonRead.TrimmedText(AArguments, 'arguments'));
  Result := AddWait(ARequest, AArguments, AReason);
end;

function AddBreakpoint(ARequest, AArguments: TJSONObject; const AResolve: TMcpIdeDebugResolve;
  out AReason: string): Boolean;
var
  mPassCount: Integer;
begin
  Result := AddPlace(ARequest, AArguments, AResolve, AReason) and
    ArgumentInRange(AArguments, 'passCount', Range(0, MaxInt, 0), mPassCount, AReason);
  if Result then
  begin
    ARequest.AddPair('condition', TJsonRead.TrimmedText(AArguments, 'condition'));
    ARequest.AddPair('passCount', TJSONNumber.Create(mPassCount));
  end;
end;

function AddRemove(ARequest, AArguments: TJSONObject; out AReason: string): Boolean;
var
  mId: Integer;
  mAll: Boolean;
begin
  mAll := TJsonRead.FlagOr(AArguments, 'all', False);
  Result := ArgumentInRange(AArguments, 'id', Range(1, MaxInt, 0), mId, AReason) and (mAll <> (mId > 0));
  if not Result then
  begin
    AReason := cTexts[TIdeDebugText.IdOrAll].Text;
    Exit;
  end;
  ARequest.AddPair('id', TJSONNumber.Create(mId));
  ARequest.AddPair('all', TJSONBool.Create(mAll));
end;

function AddStep(ARequest, AArguments: TJSONObject; const AResolve: TMcpIdeDebugResolve;
  out AReason: string): Boolean;
var
  mKind: string;
begin
  mKind := TJsonRead.TrimmedText(AArguments, 'kind');
  if mKind = '' then
  begin
    mKind := 'over';
  end;
  if not (SameText(mKind, 'into') or SameText(mKind, 'over') or SameText(mKind, 'out') or
    SameText(mKind, 'toLine')) then
  begin
    AReason := cTexts[TIdeDebugText.KindInvalid].Text;
    Exit(False);
  end;
  if SameText(mKind, 'toLine') then
  begin
    ARequest.AddPair('kind', 'toLine');
    if not AddPlace(ARequest, AArguments, AResolve, AReason) then
    begin
      Exit(False);
    end;
  end
  else
  begin
    ARequest.AddPair('kind', LowerCase(mKind));
  end;
  Result := AddWait(ARequest, AArguments, AReason);
end;

function AddState(ARequest, AArguments: TJSONObject; out AReason: string): Boolean;
var
  mFrames: Integer;
begin
  Result := ArgumentInRange(AArguments, 'frames', Range(1, TMcpIdeDebug.cFramesMax, TMcpIdeDebug.cFramesDefault), mFrames,
    AReason);
  ARequest.AddPair('frames', TJSONNumber.Create(mFrames));
  ARequest.AddPair('locals', TJSONBool.Create(TJsonRead.FlagOr(AArguments, 'locals', True)));
end;

function AddEvaluate(ARequest, AArguments: TJSONObject; out AReason: string): Boolean;
var
  mExpression: string;
begin
  mExpression := TJsonRead.TrimmedText(AArguments, 'expression');
  Result := mExpression <> '';
  if not Result then
  begin
    AReason := cTexts[TIdeDebugText.ExpressionMissing].Text;
    Exit;
  end;
  ARequest.AddPair('expression', mExpression);
  ARequest.AddPair('sideEffects', TJSONBool.Create(TJsonRead.FlagOr(AArguments, 'sideEffects', False)));
end;

/// <summary>Argumente von ATool in ARequest; False mit Grund.</summary>
function AddArguments(const ATool, AProject: string; ARequest, AArguments: TJSONObject;
  const AResolve: TMcpIdeDebugResolve; out AReason: string): Boolean;
begin
  AReason := '';
  Result := True;
  if ATool = TMcpIdeDebug.cStart then
  begin
    Result := AddStart(ARequest, AArguments, AProject, AReason);
  end
  else if ATool = TMcpIdeDebug.cSetBreakpoint then
  begin
    Result := AddBreakpoint(ARequest, AArguments, AResolve, AReason);
  end
  else if ATool = TMcpIdeDebug.cRemoveBreakpoint then
  begin
    Result := AddRemove(ARequest, AArguments, AReason);
  end
  else if ATool = TMcpIdeDebug.cContinue then
  begin
    Result := AddWait(ARequest, AArguments, AReason);
  end
  else if ATool = TMcpIdeDebug.cStep then
  begin
    Result := AddStep(ARequest, AArguments, AResolve, AReason);
  end
  else if ATool = TMcpIdeDebug.cState then
  begin
    Result := AddState(ARequest, AArguments, AReason);
  end
  else if ATool = TMcpIdeDebug.cEvaluate then
  begin
    Result := AddEvaluate(ARequest, AArguments, AReason);
  end
  else if ATool <> TMcpIdeDebug.cStop then
  begin
    AReason := cTexts[TIdeDebugText.UnknownTool].Fmt([ATool]);
    Result := False;
  end;
end;

class function TMcpIdeDebug.RequestText(const ACall: TMcpIdeDebugCall; const AArguments: TJSONObject;
  const AResolve: TMcpIdeDebugResolve; out AText, AReason: string): Boolean;
var
  mRequest: TJSONObject;
begin
  AText := '';
  mRequest := TJSONObject.Create;
  try
    mRequest.AddPair('command', ACall.Tool);
    mRequest.AddPair('client', ACall.Client);
    Result := AddArguments(ACall.Tool, ACall.Project, mRequest, AArguments, AResolve, AReason);
    if Result then
    begin
      AText := mRequest.ToJSON;
    end;
  finally
    mRequest.Free;
  end;
end;

class function TMcpIdeDebug.NoIdeReason: string;
begin
  Result := cTexts[TIdeDebugText.NoIde].Text;
end;

class function TMcpIdeDebug.AnswerMs(const AArguments: TJSONObject): Int64;
var
  mWait: Integer;
  mReason: string;
begin
  if not ArgumentInRange(AArguments, 'waitSeconds', Range(0, cWaitMax, cWaitDefault), mWait, mReason) then
  begin
    mWait := cWaitDefault;
  end;
  Result := cAnswerMs + Int64(mWait) * 1000;
end;

class function TMcpIdeDebug.ParseAnswer(const AText: string; out AOk: Boolean;
  out AResultText, AReason: string): Boolean;
var
  mValue, mResult: TJSONValue;
begin
  AOk := False;
  AResultText := '';
  AReason := '';
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    AOk := TJSONObject(mValue).GetValue<Boolean>('ok', False);
    AReason := TJSONObject(mValue).GetValue<string>('reason', '');
    mResult := TJSONObject(mValue).GetValue('result');
    if mResult is TJSONObject then
    begin
      AResultText := mResult.ToJSON;
    end;
    // Ohne Ergebnis gilt der Auftrag als abgelehnt.
    if AOk and (AResultText = '') then
    begin
      AOk := False;
      if AReason = '' then
      begin
        AReason := cTexts[TIdeDebugText.NoResult].Text;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TMcpIdeDebug.Send(const AInbox, ARequestText: string; const AWaiting: TMcpIdeWaiting;
  out AResultText, AReason: string): TMcpIdeDebugOutcome;
var
  mText: string;
  mOk: Boolean;
begin
  AResultText := '';
  AReason := '';
  case TMcpIdeInbox.Exchange(AInbox, ARequestText, AWaiting, mText) of
    TMcpIdeExchangeOutcome.NotTaken:
      begin
        AReason := cTexts[TIdeDebugText.NotTaken].Text;
        Exit(TMcpIdeDebugOutcome.NotTaken);
      end;
    TMcpIdeExchangeOutcome.TimedOut:
      begin
        AReason := cTexts[TIdeDebugText.TimedOut].Text;
        Exit(TMcpIdeDebugOutcome.TimedOut);
      end;
  end;
  if not ParseAnswer(mText, mOk, AResultText, AReason) then
  begin
    AReason := cTexts[TIdeDebugText.Unreadable].Text;
    Exit(TMcpIdeDebugOutcome.Refused);
  end;
  if mOk then
  begin
    Result := TMcpIdeDebugOutcome.Done;
  end
  else
  begin
    Result := TMcpIdeDebugOutcome.Refused;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.IdeDebug', cTexts);

end.
