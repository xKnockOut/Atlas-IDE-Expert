unit Atlas.Common.Mcp.StatisticsHistory;

// Verlauf der MCP-Aufrufstatistik über Sitzungen (#2611): Beim Beenden hängt ein MCP-Prozess je Werkzeug (auch
// ohne Aufruf) und je aufgerufener Ressource bzw. aufgerufenem Prompt eine Zeile an
// %LOCALAPPDATA%\Atlas\Status\mcp-stats.jsonl an. Zeilen älter als cKeepDays fallen dabei weg. So lässt sich über
// mehrere Sitzungen sagen, welche Werkzeuge nie vorkommen und welche oft scheitern. Die Zeilen enthalten nur
// Zahlen, Client und Projektordner, keine Argumente. Die Datei bleibt lokal.
// Mehrere Prozesse können gleichzeitig enden: Die Datei wird exklusiv geöffnet, bei Belegung wenige Male erneut
// versucht; gelingt es nicht, fehlt diese Sitzung im Verlauf (nur Statistik).

interface

uses
  System.SysUtils,
  Atlas.Text.McpStatistics;

type
  /// <summary>Summe eines Namens über alle Sitzungen im Verlauf.</summary>
  TMcpHistoryTotal = record
    Kind: TMcpCallKind;
    Name: string;
    /// <summary>Sitzungen, in denen der Name vorkam (auch mit 0 Aufrufen).</summary>
    Sessions: Integer;
    Calls: Integer;
    Errors: Integer;
    MaxMs: Int64;
  end;

  TMcpStatisticsHistory = record
  public const
    cFileName = 'mcp-stats.jsonl';
    cKeepDays = 30;
    cOpenAttempts = 10;
    cRetryMs = 50;
  public
    /// <summary>Datei im Ordner der Statusdateien (TServerStatusFile.FolderOf).</summary>
    class function FileIn(const AStatusFolder: string): string; static;
    /// <summary>Zeilen der Sitzung AStats (Prozess APid, beendet zu AEnded), je Name eine JSON-Zeile.</summary>
    class function Lines(const AStats: TMcpSessionStatistics; APid: Cardinal; AEnded: TDateTime):
      TArray<string>; static;
    /// <summary>AExisting ohne leere, unlesbare und zu alte Zeilen (beendet vor ANow - cKeepDays).</summary>
    class function Prune(const AExisting: TArray<string>; ANow: TDateTime): TArray<string>; static;
    /// <summary>Hängt die Zeilen von AStats an AFileName an und kürzt die Datei mit Prune; False, wenn die Datei
    /// nicht zu öffnen oder zu schreiben war.</summary>
    class function Append(const AFileName: string; const AStats: TMcpSessionStatistics; APid: Cardinal;
      ANow: TDateTime): Boolean; static;
    /// <summary>Zeilen von AFileName ohne die zu alten; leer, wenn die Datei fehlt oder belegt ist.</summary>
    class function Read(const AFileName: string; ANow: TDateTime): TArray<string>; static;
    /// <summary>Summen je Art und Name, nach Art und Name geordnet.</summary>
    class function Totals(const ALines: TArray<string>): TArray<TMcpHistoryTotal>; static;
    /// <summary>Zahl der Sitzungen (verschiedene pid und Ende) in ALines.</summary>
    class function SessionCount(const ALines: TArray<string>): Integer; static;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  System.DateUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Json,
  Atlas.Text.Lines;

/// <summary>Ende der Sitzung einer Zeile; False bei unlesbarer Zeile.</summary>
function EndedOf(const ALine: string; out AEnded: TDateTime): Boolean;
var
  mObject: TJSONObject;
begin
  AEnded := 0;
  mObject := TJsonRead.ParseObject(ALine);
  try
    Result := (mObject <> nil) and TryISO8601ToDate(TJsonRead.Text(mObject, 'ended'), AEnded, False);
  finally
    mObject.Free;
  end;
end;

/// <summary>Öffnet AFileName exklusiv (bei Bedarf neu), mit wenigen Versuchen; nil, wenn es nicht gelingt.</summary>
function OpenExclusive(const AFileName: string; ACreate: Boolean): TFileStream;
var
  mAttempt: Integer;
  mMode: Word;
begin
  Result := nil;
  for mAttempt := 1 to TMcpStatisticsHistory.cOpenAttempts do
  begin
    try
      mMode := fmOpenReadWrite or fmShareExclusive;
      if not FileExists(AFileName) then
      begin
        if not ACreate then
        begin
          Exit;
        end;
        mMode := fmCreate or fmShareExclusive;
      end;
      Exit(TFileStream.Create(AFileName, mMode));
    except
      on EFOpenError do
        Sleep(TMcpStatisticsHistory.cRetryMs);
      on EFCreateError do
        Sleep(TMcpStatisticsHistory.cRetryMs);
    end;
  end;
end;

function ReadAll(AStream: TStream): string;
var
  mBytes: TBytes;
begin
  mBytes := nil;
  SetLength(mBytes, AStream.Size);
  AStream.Position := 0;
  if Length(mBytes) > 0 then
  begin
    AStream.ReadBuffer(mBytes[0], Length(mBytes));
  end;
  Result := TEncoding.UTF8.GetString(mBytes);
end;

procedure WriteAll(AStream: TStream; const ALines: TArray<string>);
var
  mBytes: TBytes;
begin
  AStream.Size := 0;
  AStream.Position := 0;
  if Length(ALines) = 0 then
  begin
    Exit;
  end;
  mBytes := TEncoding.UTF8.GetBytes(string.Join(#10, ALines) + #10);
  AStream.WriteBuffer(mBytes[0], Length(mBytes));
end;

{ TMcpStatisticsHistory }

class function TMcpStatisticsHistory.FileIn(const AStatusFolder: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AStatusFolder) + cFileName;
end;

class function TMcpStatisticsHistory.Lines(const AStats: TMcpSessionStatistics; APid: Cardinal; AEnded: TDateTime):
  TArray<string>;
var
  mCall: TMcpCallSummary;
  mLine: TJSONObject;
begin
  Result := nil;
  for mCall in AStats.Calls do
  begin
    if (mCall.Kind <> TMcpCallKind.Tool) and (mCall.Calls = 0) then
    begin
      Continue;
    end;
    mLine := TJSONObject.Create;
    try
      mLine.AddPair('ended', DateToISO8601(AEnded, False));
      mLine.AddPair('pid', TJSONNumber.Create(APid));
      mLine.AddPair('client', AStats.Client);
      mLine.AddPair('project', AStats.Project);
      mLine.AddPair('kind', TMcpStatisticsFormat.KindCode(mCall.Kind));
      mLine.AddPair('name', mCall.Name);
      mLine.AddPair('calls', TJSONNumber.Create(mCall.Calls));
      mLine.AddPair('errors', TJSONNumber.Create(mCall.Errors));
      mLine.AddPair('medianMs', TJSONNumber.Create(mCall.MedianMs));
      mLine.AddPair('maxMs', TJSONNumber.Create(mCall.MaxMs));
      mLine.AddPair('medianBytes', TJSONNumber.Create(mCall.MedianBytes));
      mLine.AddPair('maxBytes', TJSONNumber.Create(mCall.MaxBytes));
      Result := Result + [mLine.ToJSON([])];
    finally
      mLine.Free;
    end;
  end;
end;

class function TMcpStatisticsHistory.Prune(const AExisting: TArray<string>; ANow: TDateTime): TArray<string>;
var
  mLine: string;
  mEnded, mOldest: TDateTime;
begin
  Result := nil;
  mOldest := IncDay(ANow, -cKeepDays);
  for mLine in AExisting do
  begin
    if EndedOf(mLine, mEnded) and (mEnded >= mOldest) then
    begin
      Result := Result + [mLine];
    end;
  end;
end;

class function TMcpStatisticsHistory.Append(const AFileName: string; const AStats: TMcpSessionStatistics;
  APid: Cardinal; ANow: TDateTime): Boolean;
var
  mStream: TFileStream;
begin
  Result := False;
  try
    ForceDirectories(ExtractFileDir(AFileName));
    mStream := OpenExclusive(AFileName, True);
    if mStream = nil then
    begin
      Exit;
    end;
    try
      WriteAll(mStream, Prune(TTextLines.SplitLines(ReadAll(mStream)), ANow) + Lines(AStats, APid, ANow));
      Result := True;
    finally
      mStream.Free;
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Verlauf nach Kräften; der Prozess endet ohnehin
    on Exception do
      Result := False;
  end;
end;

class function TMcpStatisticsHistory.Read(const AFileName: string; ANow: TDateTime): TArray<string>;
var
  mStream: TFileStream;
begin
  Result := nil;
  try
    mStream := OpenExclusive(AFileName, False);
    if mStream = nil then
    begin
      Exit;
    end;
    try
      Result := Prune(TTextLines.SplitLines(ReadAll(mStream)), ANow);
    finally
      mStream.Free;
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Verlauf nach Kräften; nur Anzeige
    on Exception do
      Result := nil;
  end;
end;

function CompareTotals(const ALeft, ARight: TMcpHistoryTotal): Integer;
begin
  Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Name, ARight.Name);
  end;
end;

/// <summary>Zählt die Zeile AObject in ATotals ein.</summary>
procedure AddLine(AObject: TJSONObject; ATotals: TDictionary<string, TMcpHistoryTotal>);
var
  mKey: string;
  mTotal: TMcpHistoryTotal;
begin
  mKey := TJsonRead.Text(AObject, 'kind') + ':' + TJsonRead.Text(AObject, 'name');
  if not ATotals.TryGetValue(mKey, mTotal) then
  begin
    mTotal := Default(TMcpHistoryTotal);
    mTotal.Kind := TMcpStatisticsFormat.KindOf(TJsonRead.Text(AObject, 'kind'));
    mTotal.Name := TJsonRead.Text(AObject, 'name');
  end;
  Inc(mTotal.Sessions);
  Inc(mTotal.Calls, TJsonRead.Int(AObject, 'calls'));
  Inc(mTotal.Errors, TJsonRead.Int(AObject, 'errors'));
  mTotal.MaxMs := Max(mTotal.MaxMs, TJsonRead.Int64Or(AObject, 'maxMs', 0));
  ATotals.AddOrSetValue(mKey, mTotal);
end;

class function TMcpStatisticsHistory.Totals(const ALines: TArray<string>): TArray<TMcpHistoryTotal>;
var
  mTotals: TDictionary<string, TMcpHistoryTotal>;
  mLine: string;
  mObject: TJSONObject;
begin
  mTotals := TDictionary<string, TMcpHistoryTotal>.Create;
  try
    for mLine in ALines do
    begin
      mObject := TJsonRead.ParseObject(mLine);
      try
        if (mObject <> nil) and (TJsonRead.Text(mObject, 'name') <> '') then
        begin
          AddLine(mObject, mTotals);
        end;
      finally
        mObject.Free;
      end;
    end;
    Result := mTotals.Values.ToArray;
  finally
    mTotals.Free;
  end;
  TArray.Sort<TMcpHistoryTotal>(Result, TComparer<TMcpHistoryTotal>.Construct(CompareTotals));
end;

class function TMcpStatisticsHistory.SessionCount(const ALines: TArray<string>): Integer;
var
  mSessions: TDictionary<string, Boolean>;
  mLine: string;
  mObject: TJSONObject;
begin
  mSessions := TDictionary<string, Boolean>.Create;
  try
    for mLine in ALines do
    begin
      mObject := TJsonRead.ParseObject(mLine);
      try
        if mObject <> nil then
        begin
          mSessions.AddOrSetValue(IntToStr(TJsonRead.Int64Or(mObject, 'pid', 0)) + '@' + TJsonRead.Text(mObject, 'ended'), True);
        end;
      finally
        mObject.Free;
      end;
    end;
    Result := mSessions.Count;
  finally
    mSessions.Free;
  end;
end;

end.
