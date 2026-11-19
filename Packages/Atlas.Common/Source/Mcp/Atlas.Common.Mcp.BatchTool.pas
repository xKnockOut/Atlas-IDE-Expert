unit Atlas.Common.Mcp.BatchTool;

// MCP-Werkzeug batch (#2638): mehrere lesende Werkzeugaufrufe in einem Aufruf, auf einem Indexstand. Den
// Abgleich der Dateien mit dem Index (OnBeforeToolCall) macht tools/call einmal für batch; die Teilaufrufe
// laufen über TMcpServer.InvokeTool ohne weiteren Abgleich, nacheinander (nicht alle lesenden Werkzeuge sind
// sicher nebenläufig), mit den Regeln eines einzelnen Aufrufs (mcp.disabledTools, eingeschränkter Modus,
// Protokoll). Schreibende und Prozess-Werkzeuge sowie batch selbst werden je Abschnitt abgelehnt; ein Fehler
// betrifft nur seinen Abschnitt. Zeitlimit (requestTimeoutMs) und Abbruch (notifications/cancelled) gelten für
// das Ganze: Fertige Abschnitte bleiben, der Rest ist gekennzeichnet. Über cMaxTotal Zeichen wird jeder zu lange
// Abschnitt gekürzt und gekennzeichnet.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server;

type
  /// <summary>Ergebnis eines Teilaufrufs.</summary>
  TMcpBatchPart = record
    Tool: string;
    Ok: Boolean;
    /// <summary>Antwort des Werkzeugs bzw. Fehlertext.</summary>
    Text: string;
    /// <summary>Nicht ausgeführt (Zeitlimit oder Abbruch).</summary>
    Skipped: Boolean;
    /// <summary>Zeichen vor dem Kürzen; 0 = nicht gekürzt.</summary>
    OriginalLength: Integer;
  end;

  /// <summary>Wann ein Lauf abbricht: Zeitlimit in ms (0 = ohne) und Abbruch des Clients.</summary>
  TMcpBatchLimits = record
    TimeoutMs: Integer;
    Cancelled: TFunc<Boolean>;
  end;

  TMcpBatchTool = class
  public const
    cName = 'batch';
    cMaxCalls = 10;
    /// <summary>Höchstgröße der Antwort in Zeichen (etwa 200 KB).</summary>
    cMaxTotal = 200000;
  private
    FServer: TMcpServer;
    FLimitsFor: TFunc<TMcpBatchLimits>;
    function RunPart(const ACall: TJSONValue): TMcpBatchPart;
    function Limits: TMcpBatchLimits;
    class function StopReason(const ALimits: TMcpBatchLimits; AElapsedMs: Int64): string; static;
    class function SkippedPart(const ACall: TJSONValue; const AReason: string): TMcpBatchPart; static;
  public
    constructor Create(AServer: TMcpServer);
    /// <summary>Führt die Aufrufe in ACalls aus (Liste aus {tool, args}); EMcpToolError bei leerer oder zu langer
    /// Liste.</summary>
    function Run(const ACalls: TJSONArray; out AElapsedMs: Int64): TArray<TMcpBatchPart>;
    /// <summary>Antwort als Text: Kopfzeile, dann je Teilaufruf "## n werkzeug".</summary>
    class function Markdown(const AParts: TArray<TMcpBatchPart>; const AIndexTime: TDateTime;
      AElapsedMs: Int64): string; static;
    /// <summary>Antwort als JSON: {format, indexTime, elapsedMs, calls: [{tool, ok, result | error}]}.</summary>
    class function Json(const AParts: TArray<TMcpBatchPart>; const AIndexTime: TDateTime;
      AElapsedMs: Int64): string; static;
    /// <summary>Kürzt zu lange Abschnitte, bis die Summe höchstens AMaxTotal Zeichen hat.</summary>
    class procedure Shorten(var AParts: TArray<TMcpBatchPart>; AMaxTotal: Integer); static;
    /// <summary>Meldet batch an AServer an; ALimits liefert Zeitlimit und Abbruch je Aufruf.</summary>
    class procedure Register(AServer: TMcpServer; const ALimits: TFunc<TMcpBatchLimits>); static;
    property LimitsFor: TFunc<TMcpBatchLimits> read FLimitsFor write FLimitsFor;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBatchText = (Tool, Calls, CallsItem, CallsTool, CallsArgs, Format, CallsMissing, TooManyCalls, CallInvalid,
    NotRead, NotInBatch, Header, Error, TimeLimit, Cancelled, ShortenedText, FormatInvalid);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TBatchText] of TAtlasText = (
    (De: 'Mehrere lesende Werkzeugaufrufe in einem Aufruf (#2638), auf einem Indexstand mit einem einzigen ' +
     'Abgleich der Dateien. Nur lesende Werkzeuge (find_symbol, get_unit_outline, find_references, ' +
     'get_diagnostics …); schreibende und Prozess-Werkzeuge und batch selbst werden je Abschnitt abgelehnt, ein ' +
     'Fehler betrifft nur seinen Abschnitt. Antwort: Kopfzeile mit Indexstand, dann je Aufruf "## n werkzeug" mit ' +
     'der unveränderten Antwort des Werkzeugs. Höchstens 10 Aufrufe, Antwort höchstens etwa 200 KB.';
     En: 'Several read-only tool calls in one call (#2638), on one index state with a single comparison of the ' +
     'files. Read-only tools only (find_symbol, get_unit_outline, find_references, get_diagnostics …); writing ' +
     'and process tools and batch itself are refused per section, an error affects only its section. Answer: ' +
     'header line with the index state, then per call "## n tool" with the unchanged answer of the tool. At ' +
     'most 10 calls, answer at most about 200 KB.'),
    (De: 'Aufrufe in Reihenfolge, höchstens 10'; En: 'Calls in order, at most 10'),
    (De: 'Ein Werkzeugaufruf'; En: 'One tool call'),
    (De: 'Name des lesenden Werkzeugs, z. B. find_references'; En: 'Name of the read-only tool, e.g. find_references'),
    (De: 'Argumente wie beim einzelnen Aufruf, z. B. {"name": "TFoo.Bar"}';
     En: 'Arguments as for the single call, e.g. {"name": "TFoo.Bar"}'),
    (De: 'markdown (Vorgabe) oder json'; En: 'markdown (default) or json'),
    (De: '"calls" fehlt oder ist leer: Liste aus {"tool": …, "args": {…}}';
     En: '"calls" is missing or empty: list of {"tool": …, "args": {…}}'),
    (De: 'Höchstens %d Aufrufe in einem batch, angegeben sind %d.'; En: 'At most %d calls in one batch, %d given.'),
    (De: 'Aufruf ohne "tool": erwartet {"tool": …, "args": {…}}.';
     En: 'Call without "tool": expected {"tool": …, "args": {…}}.'),
    (De: 'Werkzeug "%s" ist nicht lesend und läuft nicht in batch; einzeln aufrufen.';
     En: 'Tool "%s" is not read-only and does not run in batch; call it on its own.'),
    (De: 'batch lässt sich nicht verschachteln.'; En: 'batch cannot be nested.'),
    (De: 'Indexstand %s · %d Aufrufe · %d ms'; En: 'Index state %s · %d calls · %d ms'),
    (De: 'Fehler: %s'; En: 'Error: %s'),
    (De: 'nicht ausgeführt: Zeitlimit von %d ms erreicht'; En: 'not run: time limit of %d ms reached'),
    (De: 'nicht ausgeführt: abgebrochen'; En: 'not run: cancelled'),
    (De: '… gekürzt auf %d von %d Zeichen (batch höchstens %d Zeichen)';
     En: '… shortened to %d of %d characters (batch at most %d characters)'),
    (De: '"format" ist markdown oder json'; En: '"format" is markdown or json'));

  cIndexTimeFormat = 'hh:nn:ss';

{ TMcpBatchTool }

constructor TMcpBatchTool.Create(AServer: TMcpServer);
begin
  inherited Create;
  FServer := AServer;
end;

function TMcpBatchTool.Limits: TMcpBatchLimits;
begin
  Result := Default(TMcpBatchLimits);
  if Assigned(FLimitsFor) then
  begin
    Result := FLimitsFor();
  end;
end;

function TMcpBatchTool.RunPart(const ACall: TJSONValue): TMcpBatchPart;
var
  mTool: TMcpTool;
  mArguments: TJSONObject;
  mValue: TJSONValue;
begin
  Result := Default(TMcpBatchPart);
  if not ((ACall is TJSONObject) and (TJSONObject(ACall).GetValue('tool') is TJSONString)) then
  begin
    Result.Text := cTexts[TBatchText.CallInvalid].Text;
    Exit;
  end;
  Result.Tool := TJSONObject(ACall).GetValue('tool').Value;
  if SameText(Result.Tool, cName) then
  begin
    Result.Text := cTexts[TBatchText.NotInBatch].Text;
    Exit;
  end;
  if FServer.FindTool(Result.Tool, mTool) and (mTool.Kind <> TMcpToolKind.Read) then
  begin
    Result.Text := cTexts[TBatchText.NotRead].Fmt([Result.Tool]);
    Exit;
  end;
  mArguments := nil;
  mValue := TJSONObject(ACall).GetValue('args');
  if mValue is TJSONObject then
  begin
    mArguments := TJSONObject(mValue);
  end;
  // Ein Fehler betrifft nur seinen Abschnitt, auch einer, der bei einem einzelnen Aufruf zum JSON-RPC-Fehler würde.
  try
    Result.Ok := FServer.InvokeTool(Result.Tool, mArguments, Result.Text);
  except
    on EAbort do
      raise;
    // lsp-ignore: catch-all-without-raise -- der Fehler steht als Antwort in seinem Abschnitt
    on E: Exception do
    begin
      Result.Ok := False;
      Result.Text := E.Message;
    end;
  end;
end;

/// <summary>Grund, den Rest nicht mehr auszuführen: Abbruch des Clients oder Zeitlimit; '' = weiter.</summary>
class function TMcpBatchTool.StopReason(const ALimits: TMcpBatchLimits; AElapsedMs: Int64): string;
begin
  Result := '';
  if Assigned(ALimits.Cancelled) and ALimits.Cancelled() then
  begin
    Result := cTexts[TBatchText.Cancelled].Text;
  end
  else if (ALimits.TimeoutMs > 0) and (AElapsedMs >= ALimits.TimeoutMs) then
  begin
    Result := cTexts[TBatchText.TimeLimit].Fmt([ALimits.TimeoutMs]);
  end;
end;

class function TMcpBatchTool.SkippedPart(const ACall: TJSONValue; const AReason: string): TMcpBatchPart;
begin
  Result := Default(TMcpBatchPart);
  if (ACall is TJSONObject) and (TJSONObject(ACall).GetValue('tool') <> nil) then
  begin
    Result.Tool := TJSONObject(ACall).GetValue('tool').Value;
  end;
  Result.Skipped := True;
  Result.Text := AReason;
end;

function TMcpBatchTool.Run(const ACalls: TJSONArray; out AElapsedMs: Int64): TArray<TMcpBatchPart>;
var
  mWatch: TStopwatch;
  mLimits: TMcpBatchLimits;
  mIndex: Integer;
  mStop: string;
begin
  if (ACalls = nil) or (ACalls.Count = 0) then
  begin
    raise EMcpToolError.Create(cTexts[TBatchText.CallsMissing].Text);
  end;
  if ACalls.Count > cMaxCalls then
  begin
    raise EMcpToolError.Create(cTexts[TBatchText.TooManyCalls].Fmt([cMaxCalls, ACalls.Count]));
  end;
  mLimits := Limits;
  mWatch := TStopwatch.StartNew;
  SetLength(Result, ACalls.Count);
  mStop := '';
  for mIndex := 0 to ACalls.Count - 1 do
  begin
    if mStop = '' then
    begin
      mStop := StopReason(mLimits, mWatch.ElapsedMilliseconds);
    end;
    if mStop <> '' then
    begin
      Result[mIndex] := SkippedPart(ACalls.Items[mIndex], mStop);
    end
    else
    begin
      Result[mIndex] := RunPart(ACalls.Items[mIndex]);
    end;
  end;
  AElapsedMs := mWatch.ElapsedMilliseconds;
  Shorten(Result, cMaxTotal);
end;

class procedure TMcpBatchTool.Shorten(var AParts: TArray<TMcpBatchPart>; AMaxTotal: Integer);
var
  mTotal, mShare, mIndex, mLong, mFixed: Integer;
begin
  mTotal := 0;
  for mIndex := 0 to High(AParts) do
  begin
    Inc(mTotal, Length(AParts[mIndex].Text));
  end;
  if (mTotal <= AMaxTotal) or (Length(AParts) = 0) then
  begin
    Exit;
  end;
  // Kurze Abschnitte bleiben ganz; den Rest teilen sich die langen gleichmäßig.
  mShare := AMaxTotal div Length(AParts);
  mFixed := 0;
  mLong := 0;
  for mIndex := 0 to High(AParts) do
  begin
    if Length(AParts[mIndex].Text) <= mShare then
    begin
      Inc(mFixed, Length(AParts[mIndex].Text));
    end
    else
    begin
      Inc(mLong);
    end;
  end;
  if mLong > 0 then
  begin
    mShare := (AMaxTotal - mFixed) div mLong;
  end;
  for mIndex := 0 to High(AParts) do
  begin
    if Length(AParts[mIndex].Text) > mShare then
    begin
      AParts[mIndex].OriginalLength := Length(AParts[mIndex].Text);
      AParts[mIndex].Text := Copy(AParts[mIndex].Text, 1, mShare) + #10 +
        cTexts[TBatchText.ShortenedText].Fmt([mShare, AParts[mIndex].OriginalLength, AMaxTotal]);
    end;
  end;
end;

class function TMcpBatchTool.Markdown(const AParts: TArray<TMcpBatchPart>; const AIndexTime: TDateTime;
  AElapsedMs: Int64): string;
var
  mLines: TStringList;
  mIndex: Integer;
  mPart: TMcpBatchPart;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(cTexts[TBatchText.Header].Fmt([FormatDateTime(cIndexTimeFormat, AIndexTime,
      TFormatSettings.Invariant), Length(AParts), AElapsedMs]));
    for mIndex := 0 to High(AParts) do
    begin
      mPart := AParts[mIndex];
      mLines.Add('');
      mLines.Add(Format('## %d %s', [mIndex + 1, mPart.Tool]));
      if mPart.Ok or mPart.Skipped then
      begin
        mLines.Add(mPart.Text);
      end
      else
      begin
        mLines.Add(cTexts[TBatchText.Error].Fmt([mPart.Text]));
      end;
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

class function TMcpBatchTool.Json(const AParts: TArray<TMcpBatchPart>; const AIndexTime: TDateTime;
  AElapsedMs: Int64): string;
var
  mRoot, mItem: TJSONObject;
  mCalls: TJSONArray;
  mPart: TMcpBatchPart;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', 'json');
    mRoot.AddPair('indexTime', FormatDateTime(cIndexTimeFormat, AIndexTime, TFormatSettings.Invariant));
    mRoot.AddPair('elapsedMs', TJSONNumber.Create(AElapsedMs));
    mCalls := TJSONArray.Create;
    mRoot.AddPair('calls', mCalls);
    for mPart in AParts do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('tool', mPart.Tool);
      mItem.AddPair('ok', TJSONBool.Create(mPart.Ok));
      if mPart.Ok then
      begin
        mItem.AddPair('result', mPart.Text);
      end
      else
      begin
        mItem.AddPair('error', mPart.Text);
      end;
      if mPart.Skipped then
      begin
        mItem.AddPair('skipped', TJSONBool.Create(True));
      end;
      if mPart.OriginalLength > 0 then
      begin
        mItem.AddPair('truncatedFrom', TJSONNumber.Create(mPart.OriginalLength));
      end;
      mCalls.AddElement(mItem);
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Handler von batch. In eigener Routine, damit die anonyme Methode nur ihre Parameter einfängt.
/// </summary>
function BatchHandler(AServer: TMcpServer; const ALimits: TFunc<TMcpBatchLimits>): TMcpToolHandler;
begin
  Result :=
    function(const AArguments: TJSONObject): string
    var
      Tool: TMcpBatchTool;
      Calls: TJSONArray;
      Parts: TArray<TMcpBatchPart>;
      Elapsed: Int64;
      FormatName: string;
      IndexTime: TDateTime;
    begin
      FormatName := TMcpArgs.OptionalString(AArguments, 'format');
      if (FormatName <> '') and not SameText(FormatName, 'markdown') and not SameText(FormatName, 'json') then
      begin
        raise EMcpToolError.Create(cTexts[TBatchText.FormatInvalid].Text);
      end;
      Calls := nil;
      if (AArguments <> nil) and (AArguments.GetValue('calls') is TJSONArray) then
      begin
        Calls := TJSONArray(AArguments.GetValue('calls'));
      end;
      // Der Abgleich mit den Dateien lief eben vor diesem Aufruf; alle Teile sehen diesen Stand.
      IndexTime := Now;
      Tool := TMcpBatchTool.Create(AServer);
      try
        Tool.LimitsFor := ALimits;
        Parts := Tool.Run(Calls, Elapsed);
      finally
        Tool.Free;
      end;
      if SameText(FormatName, 'json') then
      begin
        Result := TMcpBatchTool.Json(Parts, IndexTime, Elapsed);
      end
      else
      begin
        Result := TMcpBatchTool.Markdown(Parts, IndexTime, Elapsed);
      end;
    end;
end;

/// <summary>Eingabeschema: calls als Liste aus {tool, args}, so beschrieben, dass gängige Clients es füllen.
/// </summary>
function BatchSchema: string;
begin
  Result := '{"type":"object","properties":{' +
    '"calls":{"type":"array","minItems":1,"maxItems":' + IntToStr(TMcpBatchTool.cMaxCalls) + ',"description":' +
    TJsonText.Quote(cTexts[TBatchText.Calls].Text) + ',"items":{"type":"object","description":' +
    TJsonText.Quote(cTexts[TBatchText.CallsItem].Text) + ',"properties":{' +
    '"tool":{"type":"string","description":' + TJsonText.Quote(cTexts[TBatchText.CallsTool].Text) + '},' +
    '"args":{"type":"object","description":' + TJsonText.Quote(cTexts[TBatchText.CallsArgs].Text) + '}},' +
    '"required":["tool"]}},' +
    '"format":{"type":"string","enum":["markdown","json"],"description":' +
    TJsonText.Quote(cTexts[TBatchText.Format].Text) + '}},' +
    '"required":["calls"]}';
end;

class procedure TMcpBatchTool.Register(AServer: TMcpServer; const ALimits: TFunc<TMcpBatchLimits>);
begin
  AServer.AddTool(cName, cTexts[TBatchText.Tool].Text, BatchSchema, BatchHandler(AServer, ALimits));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.BatchTool', cTexts);

end.
