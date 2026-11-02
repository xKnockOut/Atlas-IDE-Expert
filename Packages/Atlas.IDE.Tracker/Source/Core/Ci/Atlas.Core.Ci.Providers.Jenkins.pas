unit Atlas.Core.Ci.Providers.Jenkins;

// CI-Anbieter Jenkins (#763), ohne VCL und Open Tools API: Adressen der
// REST-API, Lesen der Antworten und Ablauf einer Abfrage. Das Netz kommt über
// IAtlasCiTransport von außen, damit alles hier ohne Server testbar ist.
// - Job: "kasse" → <url>/job/kasse; Ordner "team/kasse" →
//   <url>/job/team/job/kasse. Multibranch: dazu /job/<Branch>, der Branch
//   doppelt kodiert, wie Jenkins ihn führt („feature/x“ → feature%252Fx).
// - Build: <job>/lastCompletedBuild/api/json mit tree=number,result,
//   timestamp,duration (nur diese Felder kommen über das Netz).
// - Testbericht des JUnit-Plugins: <job>/<nummer>/testReport/api/json mit
//   passCount, failCount, skipCount und den Fällen (className, name, status,
//   errorDetails); bei Matrix- und Pipeline-Berichten unter childReports.
//   Status FAILED und REGRESSION gelten als fehlgeschlagen. 404 = kein
//   Testbericht: Der Build zählt, die Tests bleiben unbekannt.
// - Browser: <job>/<nummer>/ aus der eingetragenen Adresse, nicht aus der
//   Antwort des Servers.
// Die Zeitgrenze gilt für die ganze Abfrage (beide Aufrufe zusammen).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract;

type
  TAtlasJenkinsProvider = class(TInterfacedObject, IAtlasCiProvider)
  public const
    ProviderName = 'jenkins';
    /// <summary>Höchstens so viele Zeichen einer Fehlermeldung werden gespeichert.</summary>
    MaxMessage = 300;
  public
    /// <summary>Teil einer Adresse: UTF-8, alles außer A–Z, a–z, 0–9 und -._~ als %XX.</summary>
    class function Encode(const AText: string): string; static;
    /// <summary>Adresse des Jobs ohne „/“ am Ende; '' ohne Server oder Job.</summary>
    class function JobUrl(const AJob: TAtlasCiJob): string; static;
    class function BuildApiUrl(const AJob: TAtlasCiJob): string; static;
    class function TestReportApiUrl(const AJob: TAtlasCiJob; ANumber: Integer): string; static;
    /// <summary>Antwort von lastCompletedBuild/api/json; False ohne Nummer oder bei ungültigem JSON.</summary>
    class function ParseBuild(const AJson: string; out ABuild: TAtlasCiBuild): Boolean; static;
    /// <summary>Antwort von testReport/api/json in ABuild eintragen; False bei ungültigem JSON.</summary>
    class function ParseTestReport(const AJson: string; var ABuild: TAtlasCiBuild): Boolean; static;
    /// <summary>Fehler zu einem HTTP-Status außer 200.</summary>
    class function ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError; static;
    { IAtlasCiProvider }
    function Name: string;
    function Fetch(const AJob: TAtlasCiJob; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
    function BuildPage(const AJob: TAtlasCiJob; ANumber: Integer): string;
  end;

implementation

uses
  System.Generics.Collections,
  System.Classes,
  System.DateUtils,
  System.Diagnostics,
  System.JSON;

const
  BuildTree = 'tree=number,result,timestamp,duration';
  // [ und ] kodiert: manche Proxys lehnen sie in der Adresse ab.
  CaseTree = 'suites%5Bcases%5BclassName,name,status,errorDetails%5D%5D';
  ReportTree = 'tree=passCount,failCount,skipCount,' + CaseTree +
    ',childReports%5Bresult%5BpassCount,failCount,skipCount,' + CaseTree + '%5D%5D';

{ TAtlasJenkinsProvider }

class function TAtlasJenkinsProvider.Encode(const AText: string): string;
var
  Bytes: TBytes;
  Value: Byte;
begin
  Result := '';
  Bytes := TEncoding.UTF8.GetBytes(AText);
  for Value in Bytes do
  begin
    if ((Value >= Ord('A')) and (Value <= Ord('Z'))) or ((Value >= Ord('a')) and (Value <= Ord('z'))) or
      ((Value >= Ord('0')) and (Value <= Ord('9'))) or (Value = Ord('-')) or (Value = Ord('.')) or
      (Value = Ord('_')) or (Value = Ord('~')) then
    begin
      Result := Result + Char(Value);
    end
    else
    begin
      Result := Result + '%' + IntToHex(Value, 2);
    end;
  end;
end;

class function TAtlasJenkinsProvider.JobUrl(const AJob: TAtlasCiJob): string;
var
  Parts: TArray<string>;
  Part: string;
begin
  Result := '';
  if (AJob.Server = '') or (AJob.Job = '') then
  begin
    Exit;
  end;
  Result := AJob.Url;
  Parts := AJob.Job.Split(['/']);
  for Part in Parts do
  begin
    if Trim(Part) <> '' then
    begin
      Result := Result + '/job/' + Encode(Trim(Part));
    end;
  end;
  // Jenkins führt den Branch eines Multibranch-Jobs kodiert ("feature%2Fx"); in der Adresse noch einmal.
  if AJob.Multibranch and (AJob.Branch <> '') then
  begin
    Result := Result + '/job/' + Encode(Encode(AJob.Branch));
  end;
end;

class function TAtlasJenkinsProvider.BuildApiUrl(const AJob: TAtlasCiJob): string;
begin
  Result := JobUrl(AJob);
  if Result <> '' then
  begin
    Result := Result + '/lastCompletedBuild/api/json?' + BuildTree;
  end;
end;

class function TAtlasJenkinsProvider.TestReportApiUrl(const AJob: TAtlasCiJob; ANumber: Integer): string;
begin
  Result := JobUrl(AJob);
  if (Result <> '') and (ANumber > 0) then
  begin
    Result := Result + '/' + IntToStr(ANumber) + '/testReport/api/json?' + ReportTree;
  end
  else
  begin
    Result := '';
  end;
end;

function OutcomeOfResult(const AResult: string): TAtlasCiOutcome;
begin
  if SameText(AResult, 'SUCCESS') then
  begin
    Result := TAtlasCiOutcome.Success;
  end
  else if SameText(AResult, 'UNSTABLE') then
  begin
    Result := TAtlasCiOutcome.Unstable;
  end
  else if SameText(AResult, 'FAILURE') then
  begin
    Result := TAtlasCiOutcome.Failure;
  end
  else if SameText(AResult, 'ABORTED') then
  begin
    Result := TAtlasCiOutcome.Aborted;
  end
  else if SameText(AResult, 'NOT_BUILT') then
  begin
    Result := TAtlasCiOutcome.NotBuilt;
  end
  else
  begin
    Result := TAtlasCiOutcome.Unknown;
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string; out AValue: Int64): Boolean;
var
  Value: TJSONValue;
begin
  AValue := 0;
  Value := AObject.Values[AName];
  Result := Value is TJSONNumber;
  // Über den Text: Zeitstempel in ms passen nicht in 32 Bit, Zähler können als 12.0 kommen.
  if Result and not TryStrToInt64(TJSONNumber(Value).Value, AValue) then
  begin
    AValue := Trunc(TJSONNumber(Value).AsDouble);
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.Values[AName];
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end;
end;

/// <summary>Erste nicht leere Zeile, gekürzt.</summary>
function FirstLine(const AText: string): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  Result := '';
  Lines := AText.Replace(#13, #10).Split([#10]);
  for Line in Lines do
  begin
    if Trim(Line) <> '' then
    begin
      Result := Trim(Line);
      Break;
    end;
  end;
  if Length(Result) > TAtlasJenkinsProvider.MaxMessage then
  begin
    Result := Copy(Result, 1, TAtlasJenkinsProvider.MaxMessage - 1) + '…';
  end;
end;

class function TAtlasJenkinsProvider.ParseBuild(const AJson: string; out ABuild: TAtlasCiBuild): Boolean;
var
  Value: TJSONValue;
  Root: TJSONObject;
  Number, Stamp, Duration: Int64;
begin
  ABuild := TAtlasCiBuild.Empty;
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Root := TJSONObject(Value);
    if not NumberOf(Root, 'number', Number) or (Number <= 0) or (Number > MaxInt) then
    begin
      Exit;
    end;
    ABuild.Number := Integer(Number);
    ABuild.Outcome := OutcomeOfResult(TextOf(Root, 'result'));
    // Millisekunden seit 1970 in UTC.
    if NumberOf(Root, 'timestamp', Stamp) and (Stamp > 0) then
    begin
      ABuild.StartedUtc := IncMilliSecond(UnixToDateTime(Stamp div 1000), Stamp mod 1000);
    end;
    if NumberOf(Root, 'duration', Duration) and (Duration > 0) then
    begin
      ABuild.DurationMs := Duration;
    end;
    Result := True;
  finally
    Value.Free;
  end;
end;

/// <summary>Fälle eines Berichts (oder eines Teilberichts) zählen und Fehlschläge sammeln.</summary>
procedure ReadReport(AReport: TJSONObject; var ABuild: TAtlasCiBuild);
var
  Count: Int64;
  Suites, Cases: TJSONValue;
  Suite, Item: TJSONValue;
  Status, ClassName, CaseName: string;
  Failure: TAtlasCiFailure;
begin
  if NumberOf(AReport, 'passCount', Count) then
  begin
    Inc(ABuild.Passed, Integer(Count));
  end;
  if NumberOf(AReport, 'failCount', Count) then
  begin
    Inc(ABuild.Failed, Integer(Count));
  end;
  if NumberOf(AReport, 'skipCount', Count) then
  begin
    Inc(ABuild.Skipped, Integer(Count));
  end;
  Suites := AReport.Values['suites'];
  if not (Suites is TJSONArray) then
  begin
    Exit;
  end;
  for Suite in TJSONArray(Suites) do
  begin
    if not (Suite is TJSONObject) then
    begin
      Continue;
    end;
    Cases := TJSONObject(Suite).Values['cases'];
    if not (Cases is TJSONArray) then
    begin
      Continue;
    end;
    for Item in TJSONArray(Cases) do
    begin
      if not (Item is TJSONObject) then
      begin
        Continue;
      end;
      Status := TextOf(TJSONObject(Item), 'status');
      if not (SameText(Status, 'FAILED') or SameText(Status, 'REGRESSION')) then
      begin
        Continue;
      end;
      if Length(ABuild.Failures) >= TAtlasCiBuild.MaxFailures then
      begin
        Continue;
      end;
      ClassName := Trim(TextOf(TJSONObject(Item), 'className'));
      CaseName := Trim(TextOf(TJSONObject(Item), 'name'));
      Failure.Test := CaseName;
      if ClassName <> '' then
      begin
        Failure.Test := ClassName + '.' + CaseName;
      end;
      Failure.Message := FirstLine(TextOf(TJSONObject(Item), 'errorDetails'));
      if Failure.Test <> '' then
      begin
        ABuild.Failures := ABuild.Failures + [Failure];
      end;
    end;
  end;
end;

class function TAtlasJenkinsProvider.ParseTestReport(const AJson: string; var ABuild: TAtlasCiBuild): Boolean;
var
  Value, Children, Child, Inner: TJSONValue;
  Root: TJSONObject;
  Sum: TAtlasCiBuild;
begin
  Result := False;
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Root := TJSONObject(Value);
    Sum := TAtlasCiBuild.Empty;
    Children := Root.Values['childReports'];
    if (Children is TJSONArray) and (TJSONArray(Children).Count > 0) then
    begin
      // Zusammengefasster Bericht (Matrix, Pipeline mit Teilberichten): Teilberichte zählen.
      for Child in TJSONArray(Children) do
      begin
        if Child is TJSONObject then
        begin
          Inner := TJSONObject(Child).Values['result'];
          if Inner is TJSONObject then
          begin
            ReadReport(TJSONObject(Inner), Sum);
          end;
        end;
      end;
    end
    else
    begin
      ReadReport(Root, Sum);
    end;
    ABuild.TestsKnown := True;
    ABuild.Passed := Sum.Passed;
    ABuild.Failed := Sum.Failed;
    ABuild.Skipped := Sum.Skipped;
    ABuild.Failures := Sum.Failures;
    // Weniger Zähler als gelesene Fehlschläge (alte Plugins zählen nicht): die gelesenen gelten.
    if ABuild.Failed < Length(ABuild.Failures) then
    begin
      ABuild.Failed := Length(ABuild.Failures);
    end;
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasJenkinsProvider.ErrorOfStatus(AStatus: Integer): TAtlasCiFetchError;
begin
  case AStatus of
    401, 403:
      Result := TAtlasCiFetchError.Unauthorized;
    404:
      Result := TAtlasCiFetchError.NotFound;
  else
    Result := TAtlasCiFetchError.Server;
  end;
end;

function TAtlasJenkinsProvider.Name: string;
begin
  Result := ProviderName;
end;

function TAtlasJenkinsProvider.Fetch(const AJob: TAtlasCiJob; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
var
  Watch: TStopwatch;
  Status: Integer;
  Text: string;
  Rest: Int64;
begin
  ABuild := TAtlasCiBuild.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not AJob.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  Watch := TStopwatch.StartNew;
  if not ATransport.Get(BuildApiUrl(AJob), ATimeoutMs, Status, Text, AError) then
  begin
    Exit;
  end;
  if Status <> 200 then
  begin
    AError := ErrorOfStatus(Status);
    Exit;
  end;
  if not ParseBuild(Text, ABuild) then
  begin
    AError := TAtlasCiFetchError.Invalid;
    Exit;
  end;
  Result := True;
  // Testbericht in der restlichen Zeit; fehlt er oder reicht die Zeit nicht, bleiben die Tests unbekannt.
  Rest := ATimeoutMs - Watch.ElapsedMilliseconds;
  if Rest <= 0 then
  begin
    Exit;
  end;
  if ATransport.Get(TestReportApiUrl(AJob, ABuild.Number), Integer(Rest), Status, Text, AError) and
    (Status = 200) then
  begin
    ParseTestReport(Text, ABuild);
  end;
  // Ein fehlender Bericht ist kein Fehler der Abfrage.
  AError := TAtlasCiFetchError.None;
end;

function TAtlasJenkinsProvider.BuildPage(const AJob: TAtlasCiJob; ANumber: Integer): string;
begin
  Result := JobUrl(AJob);
  if (Result <> '') and (ANumber > 0) then
  begin
    Result := Result + '/' + IntToStr(ANumber) + '/';
  end
  else
  begin
    Result := '';
  end;
end;

end.
