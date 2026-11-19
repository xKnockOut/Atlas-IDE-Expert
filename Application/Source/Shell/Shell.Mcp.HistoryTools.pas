unit Shell.Mcp.HistoryTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Werkzeug get_symbol_history (#2641): Geschichte einer Routine oder
// eines Typs aus Git bzw. SVN (vcs.provider), über Umbenennen und Verschieben (nur Git). Zeitlimit
// requestTimeoutMs und Abbruch über notifications/cancelled; ohne Versionsverwaltung ein Hinweis.

interface

uses
  Shell.Mcp.Context;

/// <summary>get_symbol_history (#2641).</summary>
procedure RegisterSymbolHistoryTool(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.History.Contract,
  Atlas.Common.History.Service,
  Atlas.Common.Mcp.HistoryTools,
  Atlas.Common.Localization.Texts,
  Shell.SymbolHistory,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TMcpHistoryText = (Tool, Name, Limit, FollowMoves, Format, NameMissing, LimitInvalid);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpHistoryText] of TAtlasText = (
    (De: 'Geschichte einer Routine, Methode oder eines Typs (#2641): die Commits, die ihre Zeilen geändert haben ' +
    '(git log -L bzw. svn log --diff), je mit Datum, Kennung, Autor, Zeilen +n −m, erster Zeile der Nachricht ' +
    'und Issue-Kennungen. Mit Git folgt die Suche Umbenennungen und Verschiebungen in andere Units: Legt ein ' +
    'Commit das Symbol an, sucht Atlas im Stand davor einen fast gleichen Rumpf in den Dateien desselben Commits ' +
    'und geht dort weiter. Grenzen: limit, requestTimeoutMs und Abbruch; die Antwort nennt eine erreichte ' +
    'Grenze. Ergebnis je Stand gemerkt.';
    En: 'History of a routine, method or type (#2641): the commits that changed its lines (git log -L or svn log ' +
    '--diff), each with date, id, author, lines +n −m, first line of the message and issue ids. With Git the ' +
    'search follows renames and moves into other units: if a commit introduces the symbol, Atlas looks for an ' +
    'almost identical body in the files of the same commit in the state before and continues there. Limits: ' +
    'limit, requestTimeoutMs and cancellation; the answer names a limit that was reached. Result remembered ' +
    'per state.'),
    (De: 'Routine, Methode oder Typ, z. B. TFoo.Bar, Bar oder Unit.TFoo'; En: 'Routine, method or type, e.g. ' +
    'TFoo.Bar, Bar or Unit.TFoo'),
    (De: 'Höchstzahl der Einträge; Vorgabe 20, höchstens 200'; En: 'Maximum number of entries; default 20, ' +
    'at most 200'),
    (De: 'Umbenennen und Verschieben folgen (nur Git); Vorgabe true'; En: 'Follow renames and moves (Git only); ' +
    'default true'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: '"name" fehlt'; En: '"name" is missing'),
    (De: '"limit" ist eine ganze Zahl von 1 bis 200'; En: '"limit" is a whole number from 1 to 200'));

/// <summary>Argumente von get_symbol_history; EMcpToolError bei ungültigen.</summary>
function HistoryArgsOf(const AArguments: TJSONObject): TMcpHistoryArgs;
var
  mFormat: string;
begin
  Result := TMcpHistoryArgs.Default;
  Result.Name := Trim(TMcpArgs.OptionalString(AArguments, 'name'));
  if Result.Name = '' then
  begin
    raise EMcpToolError.Create(cTexts[TMcpHistoryText.NameMissing].Text);
  end;
  if (AArguments <> nil) and (AArguments.GetValue('limit') <> nil) and
    (not AArguments.TryGetValue<Integer>('limit', Result.Limit) or (Result.Limit < 1) or
    (Result.Limit > TSymbolHistoryService.cMaxLimit)) then
  begin
    raise EMcpToolError.Create(cTexts[TMcpHistoryText.LimitInvalid].Text);
  end;
  if (AArguments <> nil) and not AArguments.TryGetValue<Boolean>('followMoves', Result.FollowMoves) then
  begin
    Result.FollowMoves := True;
  end;
  mFormat := TMcpArgs.OptionalString(AArguments, 'format');
  if (mFormat <> '') and not SameText(mFormat, 'markdown') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(TShellTexts.Choice('format', ['markdown', 'json']));
  end;
  Result.Json := SameText(mFormat, 'json');
end;

/// <summary>Abbruch des laufenden Aufrufs; in eigener Routine, damit die anonyme Methode nur AToken einfängt.
/// </summary>
function CancelledOf(const AToken: IJsonRpcCancellationToken): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := (AToken <> nil) and AToken.IsCancellationRequested;
    end;
end;

function GetSymbolHistory(const AContext: TMcpToolContext; const AService: ISymbolHistoryService;
  const AArguments: TJSONObject): string;
var
  mSettings: TServerSettings;
  mArgs: TMcpHistoryArgs;
  mVcs: ISymbolHistoryVcs;
  mTools: TMcpHistoryTools;
  mError: string;
begin
  // Argumente zuerst: Ungültige Aufrufe enden, bevor Einstellungen oder Versionsverwaltung gelesen werden.
  mArgs := HistoryArgsOf(AArguments);
  mSettings := AContext.Group.Main.Configuration.Settings;
  mArgs.TimeoutMs := mSettings.RequestTimeoutMs;
  mArgs.Cancelled := CancelledOf(TJsonRpcCurrentRequest.Token);
  // Ohne Versionsverwaltung ein Hinweis statt eines Fehlers.
  if not TShellSymbolHistoryVcs.DetectHistory(AContext.Root, mSettings, mVcs, mError) then
  begin
    Exit(TMcpHistoryTools.NoVcs(mError));
  end;
  mTools := TMcpHistoryTools.Create(AContext.Index, AService, ReadSourceText);
  try
    Result := mTools.Run(mVcs, mArgs);
  finally
    mTools.Free;
  end;
end;

/// <summary>Handler mit eigenem Dienst: Der Dienst merkt Ergebnisse je Stand und lebt so lange wie der Handler.
/// In eigener Routine, damit die anonyme Methode nur Kontext und Dienst einfängt.</summary>
function SymbolHistoryHandler(const AContext: TMcpToolContext): TMcpToolHandler;
var
  mContext: TMcpToolContext;
  mService: ISymbolHistoryService;
begin
  mContext := AContext;
  mService := TSymbolHistoryService.Create;
  Result :=
    function(const AArguments: TJSONObject): string
    begin
      Result := GetSymbolHistory(mContext, mService, AArguments);
    end;
end;

procedure RegisterSymbolHistoryTool(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_symbol_history', cTexts[TMcpHistoryText.Tool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"name":{"type":"string","description":%s},' +
      '"limit":{"type":"integer","minimum":1,"maximum":200,"description":%s},' +
      '"followMoves":{"type":"boolean","default":true,"description":%s},' +
      '"format":{"type":"string","enum":["markdown","json"],"description":%s}},' +
      '"required":["name"]}',
      [cTexts[TMcpHistoryText.Name].Text,
      cTexts[TMcpHistoryText.Limit].Text,
      cTexts[TMcpHistoryText.FollowMoves].Text,
      cTexts[TMcpHistoryText.Format].Text]),
    SymbolHistoryHandler(AContext), TMcpToolKind.Process);
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.HistoryTools', cTexts);

end.
