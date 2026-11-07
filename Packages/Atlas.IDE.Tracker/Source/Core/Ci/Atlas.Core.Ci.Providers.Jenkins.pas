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
    cProviderName = 'jenkins';
    /// <summary>Höchstens so viele Zeichen einer Fehlermeldung werden gespeichert.</summary>
    cMaxMessage = 300;
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
  cBuildTree = 'tree=number,result,timestamp,duration';
  // [ und ] kodiert: manche Proxys lehnen sie in der Adresse ab.
  cCaseTree = 'suites%5Bcases%5BclassName,name,status,errorDetails%5D%5D';
  cReportTree = 'tree=passCount,failCount,skipCount,' + cCaseTree +
    ',childReports%5Bresult%5BpassCount,failCount,skipCount,' + cCaseTree + '%5D%5D';

/// <summary>Zeichen, die in einer Adresse unverändert bleiben (RFC 3986, „unreserved“).</summary>
function IsUnreserved(AValue: Byte): Boolean;
begin
  Result := CharInSet(Char(AValue), ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~']);
end;

{ TAtlasJenkinsProvider }

class function TAtlasJenkinsProvider.Encode(const AText: string): string;
var
  mBytes: TBytes;
  mValue: Byte;
begin
  Result := '';
  mBytes := TEncoding.UTF8.GetBytes(AText);
  for mValue in mBytes do
  begin
    if IsUnreserved(mValue) then
    begin
      Result := Result + Char(mValue);
    end
    else
    begin
      Result := Result + '%' + IntToHex(mValue, 2);
    end;
  end;
end;

class function TAtlasJenkinsProvider.JobUrl(const AJob: TAtlasCiJob): string;
var
  mParts: TArray<string>;
  mPart: string;
begin
  Result := '';
  if (AJob.Server = '') or (AJob.Job = '') then
  begin
    Exit;
  end;
  Result := AJob.Url;
  mParts := AJob.Job.Split(['/']);
  for mPart in mParts do
  begin
    if Trim(mPart) <> '' then
    begin
      Result := Result + '/job/' + Encode(Trim(mPart));
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
    Result := Result + '/lastCompletedBuild/api/json?' + cBuildTree;
  end;
end;

class function TAtlasJenkinsProvider.TestReportApiUrl(const AJob: TAtlasCiJob; ANumber: Integer): string;
begin
  Result := JobUrl(AJob);
  if (Result <> '') and (ANumber > 0) then
  begin
    Result := Result + '/' + IntToStr(ANumber) + '/testReport/api/json?' + cReportTree;
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
  mValue: TJSONValue;
begin
  AValue := 0;
  mValue := AObject.Values[AName];
  Result := mValue is TJSONNumber;
  // Über den Text: Zeitstempel in ms passen nicht in 32 Bit, Zähler können als 12.0 kommen.
  if Result and not TryStrToInt64(TJSONNumber(mValue).Value, AValue) then
  begin
    AValue := Trunc(TJSONNumber(mValue).AsDouble);
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

/// <summary>Erste nicht leere Zeile, gekürzt.</summary>
function FirstLine(const AText: string): string;
var
  mLines: TArray<string>;
  mLine: string;
begin
  Result := '';
  mLines := AText.Replace(#13, #10).Split([#10]);
  for mLine in mLines do
  begin
    if Trim(mLine) <> '' then
    begin
      Result := Trim(mLine);
      Break;
    end;
  end;
  if Length(Result) > TAtlasJenkinsProvider.cMaxMessage then
  begin
    Result := Copy(Result, 1, TAtlasJenkinsProvider.cMaxMessage - 1) + '…';
  end;
end;

class function TAtlasJenkinsProvider.ParseBuild(const AJson: string; out ABuild: TAtlasCiBuild): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mNumber, mStamp, mDuration: Int64;
begin
  ABuild := TAtlasCiBuild.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if not NumberOf(mRoot, 'number', mNumber) or (mNumber <= 0) or (mNumber > MaxInt) then
    begin
      Exit;
    end;
    ABuild.Number := Integer(mNumber);
    ABuild.Outcome := OutcomeOfResult(TextOf(mRoot, 'result'));
    // Millisekunden seit 1970 in UTC.
    if NumberOf(mRoot, 'timestamp', mStamp) and (mStamp > 0) then
    begin
      ABuild.StartedUtc := IncMilliSecond(UnixToDateTime(mStamp div 1000), mStamp mod 1000);
    end;
    if NumberOf(mRoot, 'duration', mDuration) and (mDuration > 0) then
    begin
      ABuild.DurationMs := mDuration;
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

/// <summary>Zähler eines Berichts zu ABuild addieren.</summary>
procedure ReadCounts(AReport: TJSONObject; var ABuild: TAtlasCiBuild);
var
  mCount: Int64;
begin
  if NumberOf(AReport, 'passCount', mCount) then
  begin
    Inc(ABuild.Passed, Integer(mCount));
  end;
  if NumberOf(AReport, 'failCount', mCount) then
  begin
    Inc(ABuild.Failed, Integer(mCount));
  end;
  if NumberOf(AReport, 'skipCount', mCount) then
  begin
    Inc(ABuild.Skipped, Integer(mCount));
  end;
end;

/// <summary>Fehlgeschlagener Fall aus AItem; False bei anderem Status oder ohne Namen.</summary>
function FailureOf(AItem: TJSONValue; out AFailure: TAtlasCiFailure): Boolean;
var
  mStatus, mClassName, mCaseName: string;
begin
  AFailure := Default(TAtlasCiFailure);
  Result := False;
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mStatus := TextOf(TJSONObject(AItem), 'status');
  if not (SameText(mStatus, 'FAILED') or SameText(mStatus, 'REGRESSION')) then
  begin
    Exit;
  end;
  mClassName := Trim(TextOf(TJSONObject(AItem), 'className'));
  mCaseName := Trim(TextOf(TJSONObject(AItem), 'name'));
  AFailure.Test := mCaseName;
  if mClassName <> '' then
  begin
    AFailure.Test := mClassName + '.' + mCaseName;
  end;
  AFailure.Message := FirstLine(TextOf(TJSONObject(AItem), 'errorDetails'));
  Result := AFailure.Test <> '';
end;

/// <summary>Fehlschläge der Fälle einer Suite sammeln, höchstens MaxFailures.</summary>
procedure ReadCases(ASuite: TJSONValue; var ABuild: TAtlasCiBuild);
var
  mCases, mItem: TJSONValue;
  mFailure: TAtlasCiFailure;
begin
  if not (ASuite is TJSONObject) then
  begin
    Exit;
  end;
  mCases := TJSONObject(ASuite).Values['cases'];
  if not (mCases is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mCases) do
  begin
    if (Length(ABuild.Failures) < TAtlasCiBuild.MaxFailures) and FailureOf(mItem, mFailure) then
    begin
      ABuild.Failures := ABuild.Failures + [mFailure];
    end;
  end;
end;

/// <summary>Fälle eines Berichts (oder eines Teilberichts) zählen und Fehlschläge sammeln.</summary>
procedure ReadReport(AReport: TJSONObject; var ABuild: TAtlasCiBuild);
var
  mSuites, mSuite: TJSONValue;
begin
  ReadCounts(AReport, ABuild);
  mSuites := AReport.Values['suites'];
  if mSuites is TJSONArray then
  begin
    for mSuite in TJSONArray(mSuites) do
    begin
      ReadCases(mSuite, ABuild);
    end;
  end;
end;

/// <summary>Teilberichte (Matrix, Pipeline) aus AChildren zählen.</summary>
procedure ReadChildReports(AChildren: TJSONArray; var ABuild: TAtlasCiBuild);
var
  mChild, mInner: TJSONValue;
begin
  for mChild in AChildren do
  begin
    if mChild is TJSONObject then
    begin
      mInner := TJSONObject(mChild).Values['result'];
      if mInner is TJSONObject then
      begin
        ReadReport(TJSONObject(mInner), ABuild);
      end;
    end;
  end;
end;

class function TAtlasJenkinsProvider.ParseTestReport(const AJson: string; var ABuild: TAtlasCiBuild): Boolean;
var
  mValue, mChildren: TJSONValue;
  mRoot: TJSONObject;
  mSum: TAtlasCiBuild;
begin
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    mSum := TAtlasCiBuild.Empty;
    mChildren := mRoot.Values['childReports'];
    if (mChildren is TJSONArray) and (TJSONArray(mChildren).Count > 0) then
    begin
      // Zusammengefasster Bericht (Matrix, Pipeline mit Teilberichten): Teilberichte zählen.
      ReadChildReports(TJSONArray(mChildren), mSum);
    end
    else
    begin
      ReadReport(mRoot, mSum);
    end;
    ABuild.TestsKnown := True;
    ABuild.Passed := mSum.Passed;
    ABuild.Failed := mSum.Failed;
    ABuild.Skipped := mSum.Skipped;
    ABuild.Failures := mSum.Failures;
    // Weniger Zähler als gelesene Fehlschläge (alte Plugins zählen nicht): die gelesenen gelten.
    if ABuild.Failed < Length(ABuild.Failures) then
    begin
      ABuild.Failed := Length(ABuild.Failures);
    end;
    Result := True;
  finally
    mValue.Free;
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
  Result := cProviderName;
end;

function TAtlasJenkinsProvider.Fetch(const AJob: TAtlasCiJob; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
var
  mWatch: TStopwatch;
  mStatus: Integer;
  mText: string;
  mRest: Int64;
begin
  ABuild := TAtlasCiBuild.Empty;
  AError := TAtlasCiFetchError.None;
  Result := False;
  if not AJob.Configured or (ATransport = nil) then
  begin
    AError := TAtlasCiFetchError.NotConfigured;
    Exit;
  end;
  mWatch := TStopwatch.StartNew;
  if not ATransport.Get(BuildApiUrl(AJob), ATimeoutMs, mStatus, mText, AError) then
  begin
    Exit;
  end;
  if mStatus <> 200 then
  begin
    AError := ErrorOfStatus(mStatus);
  end
  else if not ParseBuild(mText, ABuild) then
  begin
    AError := TAtlasCiFetchError.Invalid;
  end
  else
  begin
    Result := True;
  end;
  // Testbericht in der restlichen Zeit; fehlt er oder reicht die Zeit nicht, bleiben die Tests unbekannt.
  mRest := ATimeoutMs - mWatch.ElapsedMilliseconds;
  if not Result or (mRest <= 0) then
  begin
    Exit;
  end;
  if ATransport.Get(TestReportApiUrl(AJob, ABuild.Number), Integer(mRest), mStatus, mText, AError) and
    (mStatus = 200) then
  begin
    ParseTestReport(mText, ABuild);
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
