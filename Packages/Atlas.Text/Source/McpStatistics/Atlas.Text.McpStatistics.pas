unit Atlas.Text.McpStatistics;

// Aufrufstatistik einer MCP-Sitzung (#2611), gemeinsam für Server und Plugin: die Zahlen je Werkzeug, Ressource
// und Prompt (Aufrufe, Fehler, Median und Höchstwert von Dauer und Antwortgröße, letzter fehlgeschlagener Aufruf),
// ihre Form im Abschnitt mcp der Statusdatei (ToJson/FromJson) und die Zellen einer Tabelle ohne Sprachtexte
// (Dauer, Größe, Fehler mit Quote). Der MCP-Server zählt (Atlas.Common.Mcp.Statistics); AtlasMonitor und das
// Fenster „Atlas-Server“ der IDE lesen die Statusdateien und zeigen die Zahlen mit denselben Zellen.
// Argumente und Meldung fehlgeschlagener Aufrufe stehen gekennzeichnet (Atlas.Text.LogMarks); Anzeigen nehmen
// TLogMarks.Plain.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Werkzeug (tools/call), Ressource (resources/read) oder Prompt (prompts/get).</summary>
  TMcpCallKind = (Tool, Resource, Prompt);
  /// <summary>Spalten einer Tabelle der Aufrufe (Cells).</summary>
  TMcpCallColumn = (Name, Calls, Errors, MedianMs, MaxMs, MedianBytes, MaxBytes, LastFailed);
  {$SCOPEDENUMS OFF}

  /// <summary>Letzter fehlgeschlagener Aufruf; At = 0 ohne. Arguments als „name=wert …“ mit gekennzeichneten
  /// Werten, Message gekennzeichnet als fremder Text.</summary>
  TMcpFailedCall = record
    At: TDateTime;
    Arguments: string;
    Message: string;
  end;

  /// <summary>Zahlen eines Werkzeugs, einer Ressource oder eines Prompts.</summary>
  TMcpCallSummary = record
  public const
    /// <summary>Ab so vielen Aufrufen …</summary>
    cConspicuousCalls = 5;
    /// <summary>… gilt eine Fehlerquote über diesem Wert als auffällig.</summary>
    cConspicuousPercent = 20;
  public
    Kind: TMcpCallKind;
    Name: string;
    Calls: Integer;
    Errors: Integer;
    MedianMs: Int64;
    MaxMs: Int64;
    MedianBytes: Int64;
    MaxBytes: Int64;
    LastFailed: TMcpFailedCall;
    /// <summary>Anteil der Fehler in Prozent, gerundet; 0 ohne Aufruf.</summary>
    function ErrorPercent: Integer;
    /// <summary>Fehlerquote über cConspicuousPercent bei mindestens cConspicuousCalls Aufrufen.</summary>
    function Conspicuous: Boolean;
    /// <summary>Letzter fehlgeschlagener Aufruf im Klartext, z. B. „09:40 file="…": Meldung“; '' ohne.</summary>
    function LastFailedText: string;
    /// <summary>Zellen der Tabelle in der Reihenfolge von TMcpCallColumn; ADecimal trennt Nachkommastellen, ANone
    /// steht in Zahlenspalten ohne Aufruf.</summary>
    function Cells(ADecimal: Char; const ANone: string): TArray<string>;
    function ToJson: TJSONObject;
    class function FromJson(AObject: TJSONObject): TMcpCallSummary; static;
  end;

  /// <summary>Stand einer Sitzung: Client, Projekt, Beginn und die Zahlen je Name.</summary>
  TMcpSessionStatistics = record
    /// <summary>clientInfo.name aus initialize; '' solange unbekannt.</summary>
    Client: string;
    Project: string;
    Started: TDateTime;
    /// <summary>Nach Art, dann Aufrufen absteigend, dann Name.</summary>
    Calls: TArray<TMcpCallSummary>;
    function TotalCalls: Integer;
    function TotalErrors: Integer;
    /// <summary>Kopie mit Argumenten und Meldungen im Klartext (ohne Kennzeichen), für Antworten an den Client.
    /// </summary>
    function Plain: TMcpSessionStatistics;
    function ToJson: TJSONObject;
    /// <summary>Liest einen Stand aus ToJson; leerer Stand bei nil.</summary>
    class function FromJson(AObject: TJSONObject): TMcpSessionStatistics; static;
    /// <summary>Wie FromJson aus einem JSON-Text (Abschnitt mcp einer Statusdatei); leerer Stand bei ungültigem.
    /// </summary>
    class function FromText(const AJson: string): TMcpSessionStatistics; static;
  end;

  TMcpStatisticsFormat = record
  public
    /// <summary>Kennwort der Art in JSON und Verlauf (tool, resource, prompt).</summary>
    class function KindCode(AKind: TMcpCallKind): string; static;
    /// <summary>Art zu KindCode; Tool bei Unbekanntem.</summary>
    class function KindOf(const ACode: string): TMcpCallKind; static;
    /// <summary>Dauer wie „40 ms“ oder „1,2 s“.</summary>
    class function DurationText(AMs: Int64; ADecimal: Char): string; static;
    /// <summary>Größe wie „512 B“, „2,0 KB“, „120 KB“ oder „1,5 MB“.</summary>
    class function SizeText(ABytes: Int64; ADecimal: Char): string; static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  Atlas.Text.Json,
  Atlas.Text.LogMarks,
  Atlas.Text.TestResults;

const
  cKindCodes: array[TMcpCallKind] of string = ('tool', 'resource', 'prompt');
  cPercent = 100;
  cKilo = 1024;
  cTenths = 10;

/// <summary>Zeitpunkt als ISO 8601 (Ortszeit); '' für 0.</summary>
function DateText(AValue: TDateTime): string;
begin
  Result := '';
  if AValue <> 0 then
  begin
    Result := DateToISO8601(AValue, False);
  end;
end;

/// <summary>Zeitpunkt aus ISO 8601; 0, wenn der Text fehlt oder ungültig ist.</summary>
function DateOf(const AText: string): TDateTime;
begin
  if (AText = '') or not TryISO8601ToDate(AText, Result, False) then
  begin
    Result := 0;
  end;
end;

/// <summary>AValue in Einheiten von AUnit mit einer Nachkommastelle unter 10, sonst ganz.</summary>
function UnitText(AValue, AUnit: Int64; ADecimal: Char; const ASuffix: string): string;
var
  mTenths: Int64;
begin
  mTenths := (AValue * cTenths + AUnit div 2) div AUnit;
  if mTenths < cTenths * cTenths then
  begin
    Exit(IntToStr(mTenths div cTenths) + ADecimal + IntToStr(mTenths mod cTenths) + ' ' + ASuffix);
  end;
  Result := IntToStr((mTenths + cTenths div 2) div cTenths) + ' ' + ASuffix;
end;

{ TMcpCallSummary }

function TMcpCallSummary.ErrorPercent: Integer;
begin
  Result := 0;
  if Calls > 0 then
  begin
    Result := Round(Errors * cPercent / Calls);
  end;
end;

function TMcpCallSummary.Conspicuous: Boolean;
begin
  Result := (Calls >= cConspicuousCalls) and (Errors * cPercent > cConspicuousPercent * Calls);
end;

function TMcpCallSummary.LastFailedText: string;
begin
  Result := '';
  if LastFailed.At = 0 then
  begin
    Exit;
  end;
  Result := FormatDateTime('hh":"nn', LastFailed.At);
  if LastFailed.Arguments <> '' then
  begin
    Result := Result + ' ' + TLogMarks.Plain(LastFailed.Arguments);
  end;
  if LastFailed.Message <> '' then
  begin
    Result := Result + ': ' + TLogMarks.Plain(LastFailed.Message);
  end;
end;

function TMcpCallSummary.Cells(ADecimal: Char; const ANone: string): TArray<string>;
var
  mColumn: TMcpCallColumn;
begin
  Result := nil;
  SetLength(Result, Ord(High(TMcpCallColumn)) + 1);
  for mColumn := Low(TMcpCallColumn) to High(TMcpCallColumn) do
  begin
    Result[Ord(mColumn)] := ANone;
  end;
  Result[Ord(TMcpCallColumn.Name)] := Name;
  Result[Ord(TMcpCallColumn.Calls)] := IntToStr(Calls);
  Result[Ord(TMcpCallColumn.LastFailed)] := LastFailedText;
  if Calls = 0 then
  begin
    Exit;
  end;
  Result[Ord(TMcpCallColumn.Errors)] := IntToStr(Errors);
  if Errors > 0 then
  begin
    Result[Ord(TMcpCallColumn.Errors)] := Format('%d (%d %%)', [Errors, ErrorPercent]);
  end;
  Result[Ord(TMcpCallColumn.MedianMs)] := TMcpStatisticsFormat.DurationText(MedianMs, ADecimal);
  Result[Ord(TMcpCallColumn.MaxMs)] := TMcpStatisticsFormat.DurationText(MaxMs, ADecimal);
  Result[Ord(TMcpCallColumn.MedianBytes)] := TMcpStatisticsFormat.SizeText(MedianBytes, ADecimal);
  Result[Ord(TMcpCallColumn.MaxBytes)] := TMcpStatisticsFormat.SizeText(MaxBytes, ADecimal);
end;

function TMcpCallSummary.ToJson: TJSONObject;
var
  mFailed: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', TMcpStatisticsFormat.KindCode(Kind));
  Result.AddPair('name', Name);
  Result.AddPair('calls', TJSONNumber.Create(Calls));
  Result.AddPair('errors', TJSONNumber.Create(Errors));
  Result.AddPair('medianMs', TJSONNumber.Create(MedianMs));
  Result.AddPair('maxMs', TJSONNumber.Create(MaxMs));
  Result.AddPair('medianBytes', TJSONNumber.Create(MedianBytes));
  Result.AddPair('maxBytes', TJSONNumber.Create(MaxBytes));
  if LastFailed.At <> 0 then
  begin
    mFailed := TJSONObject.Create;
    mFailed.AddPair('at', DateText(LastFailed.At));
    mFailed.AddPair('arguments', LastFailed.Arguments);
    mFailed.AddPair('message', LastFailed.Message);
    Result.AddPair('lastFailed', mFailed);
  end;
end;

class function TMcpCallSummary.FromJson(AObject: TJSONObject): TMcpCallSummary;
var
  mFailed: TJSONObject;
begin
  Result := Default(TMcpCallSummary);
  Result.Kind := TMcpStatisticsFormat.KindOf(TJsonRead.Text(AObject, 'kind'));
  Result.Name := TJsonRead.Text(AObject, 'name');
  Result.Calls := TJsonRead.Int(AObject, 'calls');
  Result.Errors := TJsonRead.Int(AObject, 'errors');
  Result.MedianMs := TJsonRead.Int64Or(AObject, 'medianMs', 0);
  Result.MaxMs := TJsonRead.Int64Or(AObject, 'maxMs', 0);
  Result.MedianBytes := TJsonRead.Int64Or(AObject, 'medianBytes', 0);
  Result.MaxBytes := TJsonRead.Int64Or(AObject, 'maxBytes', 0);
  mFailed := TJsonRead.Obj(AObject, 'lastFailed');
  Result.LastFailed.At := DateOf(TJsonRead.Text(mFailed, 'at'));
  Result.LastFailed.Arguments := TJsonRead.Text(mFailed, 'arguments');
  Result.LastFailed.Message := TJsonRead.Text(mFailed, 'message');
end;

{ TMcpSessionStatistics }

function TMcpSessionStatistics.TotalCalls: Integer;
var
  mCall: TMcpCallSummary;
begin
  Result := 0;
  for mCall in Calls do
  begin
    Inc(Result, mCall.Calls);
  end;
end;

function TMcpSessionStatistics.TotalErrors: Integer;
var
  mCall: TMcpCallSummary;
begin
  Result := 0;
  for mCall in Calls do
  begin
    Inc(Result, mCall.Errors);
  end;
end;

function TMcpSessionStatistics.Plain: TMcpSessionStatistics;
var
  mIndex: Integer;
begin
  Result := Self;
  Result.Calls := Copy(Calls);
  for mIndex := 0 to High(Result.Calls) do
  begin
    Result.Calls[mIndex].LastFailed.Arguments := TLogMarks.Plain(Result.Calls[mIndex].LastFailed.Arguments);
    Result.Calls[mIndex].LastFailed.Message := TLogMarks.Plain(Result.Calls[mIndex].LastFailed.Message);
  end;
end;

function TMcpSessionStatistics.ToJson: TJSONObject;
var
  mItems: TJSONArray;
  mCall: TMcpCallSummary;
begin
  Result := TJSONObject.Create;
  Result.AddPair('client', Client);
  Result.AddPair('project', Project);
  Result.AddPair('started', DateText(Started));
  mItems := TJSONArray.Create;
  for mCall in Calls do
  begin
    mItems.AddElement(mCall.ToJson);
  end;
  Result.AddPair('calls', mItems);
end;

class function TMcpSessionStatistics.FromJson(AObject: TJSONObject): TMcpSessionStatistics;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  Result := Default(TMcpSessionStatistics);
  Result.Client := TJsonRead.Text(AObject, 'client');
  Result.Project := TJsonRead.Text(AObject, 'project');
  Result.Started := DateOf(TJsonRead.Text(AObject, 'started'));
  mItems := TJsonRead.Items(AObject, 'calls');
  if mItems = nil then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if mItem is TJSONObject then
    begin
      Result.Calls := Result.Calls + [TMcpCallSummary.FromJson(TJSONObject(mItem))];
    end;
  end;
end;

class function TMcpSessionStatistics.FromText(const AJson: string): TMcpSessionStatistics;
var
  mObject: TJSONObject;
begin
  mObject := TJsonRead.ParseObject(AJson);
  try
    Result := FromJson(mObject);
  finally
    mObject.Free;
  end;
end;

{ TMcpStatisticsFormat }

class function TMcpStatisticsFormat.KindCode(AKind: TMcpCallKind): string;
begin
  Result := cKindCodes[AKind];
end;

class function TMcpStatisticsFormat.KindOf(const ACode: string): TMcpCallKind;
var
  mKind: TMcpCallKind;
begin
  for mKind := Low(TMcpCallKind) to High(TMcpCallKind) do
  begin
    if SameText(cKindCodes[mKind], ACode) then
    begin
      Exit(mKind);
    end;
  end;
  Result := TMcpCallKind.Tool;
end;

class function TMcpStatisticsFormat.DurationText(AMs: Int64; ADecimal: Char): string;
begin
  Result := TTestResults.DurationText(AMs, ADecimal);
end;

class function TMcpStatisticsFormat.SizeText(ABytes: Int64; ADecimal: Char): string;
begin
  if ABytes < cKilo then
  begin
    Exit(IntToStr(Max(ABytes, 0)) + ' B');
  end;
  if ABytes < cKilo * cKilo then
  begin
    Exit(UnitText(ABytes, cKilo, ADecimal, 'KB'));
  end;
  Result := UnitText(ABytes, cKilo * cKilo, ADecimal, 'MB');
end;

end.
