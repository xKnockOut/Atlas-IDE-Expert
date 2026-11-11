unit Atlas.Text.TestResults;

// Ergebnisse eines DUnitX-Laufs lesen, gemeinsam für Server und Plugin
// (#69): die XML-Berichte der DUnitX-Logger.
// - NUnit 2 (TDUnitXXMLNUnitFileLogger, Vorgabe der Vorlage von RAD Studio):
//   <test-results> mit verschachtelten <test-suite type="Namespace|TestFixture|…">
//   und <test-case name="Unit.Fixture.Methode" result="Success|Failure|Error|
//   Ignored|…" time="0.012"> samt <failure><message>…</message>
//   <stack-trace>…</stack-trace></failure> bzw. <reason><message>.
// - NUnit 3: <test-run> mit <test-case fullname="…" result="Passed|Failed|
//   Skipped" label="Error" duration="…">.
// - JUnit (TDUnitXXMLJUnitFileLogger): <testsuite> mit <testcase
//   classname="Unit.Fixture" name="Methode" time="…"> und <failure>, <error>
//   bzw. <skipped>.
// Der volle Name wird in Unit, Fixture, Methode und Testfall zerlegt; die
// Fixture kommt aus der umgebenden test-suite (NUnit) bzw. aus classname
// (JUnit), weil Unit-Namen selbst Punkte enthalten. Aus Meldungen wie
// „Expected 3 but got 4“ (DUnitX) und „Expected: 3 But was: 4“ (NUnit)
// werden erwarteter und tatsächlicher Wert gelesen.
// Zeiten: Sekunden mit Punkt oder Komma (DUnitX schreibt je nach Fassung im
// Format des Gebietsschemas).

interface

{$SCOPEDENUMS ON}

type
  TTestOutcome = (Passed, Failed, Error, Skipped);

  TTestCaseResult = record
    /// <summary>Name wie im Bericht, z. B. Rechner.Tests.TRechnerTests.Addiert bzw. …Addiert.Fall1.</summary>
    FullName: string;
    /// <summary>Unit (Namensraum der Fixture); '' unbekannt.</summary>
    UnitName: string;
    Fixture: string;
    Method: string;
    /// <summary>Name des Testfalls bei [TestCase]; sonst ''.</summary>
    CaseName: string;
    Outcome: TTestOutcome;
    DurationMs: Int64;
    /// <summary>Meldung des Fehlschlags bzw. Grund des Überspringens.</summary>
    Message: string;
    /// <summary>Erwarteter und tatsächlicher Wert aus Message, wenn HasValues.</summary>
    Expected: string;
    Actual: string;
    HasValues: Boolean;
    StackTrace: string;
    /// <summary>Fehlgeschlagen oder mit Ausnahme abgebrochen.</summary>
    function IsFailure: Boolean;
  end;

  TTestRunResult = record
    /// <summary>Bericht gelesen; sonst Grund in Error.</summary>
    Valid: Boolean;
    Error: string;
    /// <summary>"nunit2", "nunit3" oder "junit".</summary>
    Format: string;
    /// <summary>Dauer des Laufs laut Bericht, sonst Summe der Tests.</summary>
    DurationMs: Int64;
    Cases: TArray<TTestCaseResult>;
    function Count(AOutcome: TTestOutcome): Integer;
    function Total: Integer;
    /// <summary>Fehlgeschlagene und abgebrochene Tests in Berichtsreihenfolge.</summary>
    function Failures: TArray<TTestCaseResult>;
    /// <summary>Gelesen, mindestens ein Test, keiner fehlgeschlagen.</summary>
    function AllPassed: Boolean;
  end;

  TTestResults = class
  public
    /// <summary>Liest einen XML-Bericht (Format wird erkannt).</summary>
    class function Parse(const AXml: string): TTestRunResult; static;
    /// <summary>Erwarteter und tatsächlicher Wert aus einer Meldung; False, wenn sie keine nennt.</summary>
    class function SplitValues(const AMessage: string; out AExpected, AActual: string): Boolean; static;
    /// <summary>Zerlegt AFullName mit der bekannten Fixture AFixture ('' = unbekannt: die letzten beiden Teile
    /// gelten als Fixture und Methode).</summary>
    class procedure SplitName(const AFullName, AFixture: string; out AUnitName, AFixtureName, AMethod,
      ACaseName: string); static;
    /// <summary>Sekunden ("0.012", "0,012") in Millisekunden; 0 bei ungültigem Text.</summary>
    class function SecondsToMs(const AText: string): Int64; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Entities;

type
  TXmlNodeKind = (StartTag, EndTag, Text, Done);
  // Ergebnis von SkipDeclaration: nichts übersprungen, übersprungen, ohne Ende.
  TXmlSkip = (None, Skipped, Unclosed);

  /// <summary>Kleiner Leser für die Berichte; nur innerhalb von Parse benutzt.</summary>
  TXmlCursor = record
    Source: string;
    Position: Integer;
    Kind: TXmlNodeKind;
    Name: string;
    /// <summary>Text eines Textknotens (entschlüsselt, CDATA wörtlich).</summary>
    Value: string;
    SelfClosing: Boolean;
    AttributeNames: TArray<string>;
    AttributeValues: TArray<string>;
    procedure Init(const AText: string);
    function Next: Boolean;
    function Attribute(const AName: string): string;
    /// <summary>Steht an Position ein Zeichen aus AChars?</summary>
    function CharIs(const AChars: TSysCharSet): Boolean;
    procedure SkipWhile(const AChars: TSysCharSet);
    /// <summary>Text ab Position bis vor das erste Zeichen aus AStops (oder bis zum Ende).</summary>
    function TakeUntil(const AStops: TSysCharSet): string;
    function SkipPast(const AClose: string; AFrom: Integer): TXmlSkip;
    /// <summary>Kommentar, Verarbeitungsanweisung oder Deklaration ab Position überspringen.</summary>
    function SkipDeclaration: TXmlSkip;
    procedure ReadCData;
    procedure ReadAttribute;
    procedure ReadTag;
  end;

const
  cXmlSpaces = [' ', #9, #13, #10];

procedure TXmlCursor.Init(const AText: string);
begin
  Source := AText;
  Position := 1;
  Kind := TXmlNodeKind.Done;
end;

function TXmlCursor.Attribute(const AName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AttributeNames) do
  begin
    if SameText(AttributeNames[mIndex], AName) then
    begin
      Exit(AttributeValues[mIndex]);
    end;
  end;
  Result := '';
end;

function TXmlCursor.CharIs(const AChars: TSysCharSet): Boolean;
begin
  Result := (Position <= Length(Source)) and CharInSet(Source[Position], AChars);
end;

procedure TXmlCursor.SkipWhile(const AChars: TSysCharSet);
begin
  while CharIs(AChars) do
  begin
    Inc(Position);
  end;
end;

function TXmlCursor.TakeUntil(const AStops: TSysCharSet): string;
var
  mStart: Integer;
begin
  mStart := Position;
  while (Position <= Length(Source)) and not CharInSet(Source[Position], AStops) do
  begin
    Inc(Position);
  end;
  Result := Copy(Source, mStart, Position - mStart);
end;

function TXmlCursor.SkipPast(const AClose: string; AFrom: Integer): TXmlSkip;
var
  mStop: Integer;
begin
  mStop := PosEx(AClose, Source, AFrom);
  if mStop = 0 then
  begin
    Exit(TXmlSkip.Unclosed);
  end;
  Position := mStop + Length(AClose);
  Result := TXmlSkip.Skipped;
end;

function TXmlCursor.SkipDeclaration: TXmlSkip;
begin
  if Copy(Source, Position, 4) = '<!--' then
  begin
    Exit(SkipPast('-->', Position + 4));
  end;
  Result := TXmlSkip.None;
  if (Copy(Source, Position, 2) = '<?') or (Copy(Source, Position, 2) = '<!') then
  begin
    Result := SkipPast('>', Position + 2);
  end;
end;

procedure TXmlCursor.ReadCData;
var
  mStart, mStop: Integer;
begin
  mStart := Position + 9;
  mStop := PosEx(']]>', Source, mStart);
  if mStop = 0 then
  begin
    mStop := Length(Source) + 1;
  end;
  Kind := TXmlNodeKind.Text;
  Value := Copy(Source, mStart, mStop - mStart);
  Position := mStop + 3;
end;

procedure TXmlCursor.ReadAttribute;
var
  mName: string;
  mQuote: Char;
begin
  mName := TakeUntil(['=', ' ', #9, #13, #10, '>', '/']);
  SkipWhile(cXmlSpaces);
  if not CharIs(['=']) then
  begin
    Exit;
  end;
  Inc(Position);
  SkipWhile(cXmlSpaces);
  if not CharIs(['"', '''']) then
  begin
    Exit;
  end;
  mQuote := Source[Position];
  Inc(Position);
  AttributeNames := AttributeNames + [mName];
  AttributeValues := AttributeValues + [TTextEntities.Decode(TakeUntil([mQuote]))];
  Inc(Position);
end;

procedure TXmlCursor.ReadTag;
begin
  Inc(Position);
  Kind := TXmlNodeKind.StartTag;
  if CharIs(['/']) then
  begin
    Kind := TXmlNodeKind.EndTag;
    Inc(Position);
  end;
  Name := TakeUntil([' ', #9, #13, #10, '/', '>']);
  while Position <= Length(Source) do
  begin
    case Source[Position] of
      '>':
        begin
          Inc(Position);
          Exit;
        end;
      '/':
        begin
          SelfClosing := True;
          Inc(Position);
        end;
      ' ', #9, #13, #10:
        Inc(Position);
    else
      ReadAttribute;
    end;
  end;
end;

function TXmlCursor.Next: Boolean;
begin
  Name := '';
  Value := '';
  SelfClosing := False;
  AttributeNames := nil;
  AttributeValues := nil;
  Result := True;
  while Position <= Length(Source) do
  begin
    if Source[Position] <> '<' then
    begin
      Kind := TXmlNodeKind.Text;
      Value := TTextEntities.Decode(TakeUntil(['<']));
      Exit;
    end;
    if Copy(Source, Position, 9) = '<![CDATA[' then
    begin
      ReadCData;
      Exit;
    end;
    case SkipDeclaration of
      TXmlSkip.Skipped:
        Continue;
      TXmlSkip.Unclosed:
        Break;
      TXmlSkip.None: ;
    end;
    ReadTag;
    Exit;
  end;
  Kind := TXmlNodeKind.Done;
  Result := False;
end;

{ TTestCaseResult }

function TTestCaseResult.IsFailure: Boolean;
begin
  Result := Outcome in [TTestOutcome.Failed, TTestOutcome.Error];
end;

{ TTestRunResult }

function TTestRunResult.Count(AOutcome: TTestOutcome): Integer;
var
  mItem: TTestCaseResult;
begin
  Result := 0;
  for mItem in Cases do
  begin
    if mItem.Outcome = AOutcome then
    begin
      Inc(Result);
    end;
  end;
end;

function TTestRunResult.Total: Integer;
begin
  Result := Length(Cases);
end;

function TTestRunResult.Failures: TArray<TTestCaseResult>;
var
  mItem: TTestCaseResult;
begin
  Result := nil;
  for mItem in Cases do
  begin
    if mItem.IsFailure then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

function TTestRunResult.AllPassed: Boolean;
begin
  Result := Valid and (Total > 0) and (Length(Failures) = 0);
end;

{ TTestResults }

class function TTestResults.SecondsToMs(const AText: string): Int64;
var
  mValue: Double;
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  if not TryStrToFloat(StringReplace(Trim(AText), ',', '.', []), mValue, mSettings) or (mValue < 0) then
  begin
    Exit(0);
  end;
  Result := Round(mValue * 1000);
end;

class function TTestResults.SplitValues(const AMessage: string; out AExpected, AActual: string): Boolean;
var
  mText: string;
  mExpectedAt, mActualAt, mLineEnd: Integer;

  function Unquote(const AValue: string): string;
  begin
    Result := Trim(AValue);
    if (Length(Result) >= 2) and CharInSet(Result[1], ['"', '''', '<']) and
      (Result[Length(Result)] = Result[1]) then
    begin
      Result := Copy(Result, 2, Length(Result) - 2);
    end
    else if (Length(Result) >= 2) and (Result[1] = '<') and (Result[Length(Result)] = '>') then
    begin
      Result := Copy(Result, 2, Length(Result) - 2);
    end;
  end;

begin
  AExpected := '';
  AActual := '';
  mText := StringReplace(AMessage, #13, '', [rfReplaceAll]);
  // NUnit: "Expected: 3" und in der nächsten Zeile "But was: 4".
  mExpectedAt := Pos('expected:', LowerCase(mText));
  mActualAt := Pos('but was:', LowerCase(mText));
  if (mExpectedAt > 0) and (mActualAt > mExpectedAt) then
  begin
    AExpected := Unquote(Copy(mText, mExpectedAt + 9, mActualAt - mExpectedAt - 9));
    AActual := Copy(mText, mActualAt + 8, MaxInt);
    mLineEnd := Pos(#10, AActual);
    if mLineEnd > 0 then
    begin
      AActual := Copy(AActual, 1, mLineEnd - 1);
    end;
    AActual := Unquote(AActual);
    Exit(True);
  end;
  // DUnitX: "Expected 3 but got 4" (dahinter ggf. die eigene Meldung des Tests).
  mExpectedAt := Pos('expected ', LowerCase(mText));
  if mExpectedAt > 0 then
  begin
    mActualAt := PosEx(' but got ', LowerCase(mText), mExpectedAt + 9);
  end
  else
  begin
    mActualAt := 0;
  end;
  if (mExpectedAt > 0) and (mActualAt > 0) then
  begin
    AExpected := Unquote(Copy(mText, mExpectedAt + 9, mActualAt - mExpectedAt - 9));
    AActual := Copy(mText, mActualAt + 9, MaxInt);
    mLineEnd := Pos(#10, AActual);
    if mLineEnd > 0 then
    begin
      AActual := Copy(AActual, 1, mLineEnd - 1);
    end;
    AActual := Unquote(AActual);
    Exit(True);
  end;
  Result := False;
end;

class procedure TTestResults.SplitName(const AFullName, AFixture: string; out AUnitName, AFixtureName, AMethod,
  ACaseName: string);
var
  mParts: TArray<string>;
  mAt, mIndex: Integer;
  mRest: string;
begin
  AUnitName := '';
  AFixtureName := AFixture;
  AMethod := '';
  ACaseName := '';
  if AFixture <> '' then
  begin
    // Die Fixture steht als eigener Teil im Namen: Unit.Fixture.Methode[.Fall].
    mAt := Pos(LowerCase('.' + AFixture + '.'), LowerCase('.' + AFullName));
    if mAt > 0 then
    begin
      AUnitName := Copy(AFullName, 1, mAt - 2);
      mRest := Copy(AFullName, mAt + Length(AFixture) + 1, MaxInt);
      AFixtureName := Copy(AFullName, mAt, Length(AFixture));
      mIndex := Pos('.', mRest);
      if mIndex > 0 then
      begin
        AMethod := Copy(mRest, 1, mIndex - 1);
        ACaseName := Copy(mRest, mIndex + 1, MaxInt);
      end
      else
      begin
        AMethod := mRest;
      end;
      Exit;
    end;
  end;
  mParts := AFullName.Split(['.']);
  if Length(mParts) >= 2 then
  begin
    AFixtureName := mParts[High(mParts) - 1];
    AMethod := mParts[High(mParts)];
    for mIndex := 0 to High(mParts) - 2 do
    begin
      if AUnitName <> '' then
      begin
        AUnitName := AUnitName + '.';
      end;
      AUnitName := AUnitName + mParts[mIndex];
    end;
  end
  else
  begin
    AMethod := AFullName;
  end;
end;

type
  /// <summary>Liest einen Bericht Knoten für Knoten; der Zustand gilt für einen Aufruf von Read.</summary>
  TReportReader = class
  private
    FCursor: TXmlCursor;
    FResult: TTestRunResult;
    /// <summary>Fixture der umgebenden test-suite je Ebene (NUnit).</summary>
    FFixtures: TArray<string>;
    /// <summary>Je offener test-suite: ist sie eine Fixture?</summary>
    FSuites: TArray<Boolean>;
    FCurrent: TTestCaseResult;
    FInCase: Boolean;
    FInMessage: Boolean;
    FInStack: Boolean;
    FInFailure: Boolean;
    FRunTimeKnown: Boolean;
    FSumMs: Int64;
    procedure SetRunTime(const ASeconds: string);
    procedure DetectFormat(const AElement: string);
    procedure StartSuite;
    procedure EndSuite;
    procedure StartJUnitCase;
    procedure StartNUnitCase;
    procedure StartCase;
    procedure EndCase;
    procedure TakeMessageAttribute;
    procedure StartFailure(const AElement: string);
    procedure StartCaseChild(const AElement: string);
    procedure OpenElement(const AElement: string);
    procedure CloseElement(const AElement: string);
    procedure ReadTextNode;
  public
    function Read(const AXml: string): TTestRunResult;
  end;

function IsCaseElement(const AElement: string): Boolean;
begin
  Result := (AElement = 'test-case') or (AElement = 'testcase');
end;

function IsFailureElement(const AElement: string): Boolean;
begin
  Result := (AElement = 'failure') or (AElement = 'error');
end;

// Ergebnis eines NUnit-Testfalls aus den Attributen result und label (klein geschrieben).
function NUnitOutcome(const AResult, ALabel: string): TTestOutcome;
begin
  case IndexStr(AResult, ['success', 'passed', 'failure', 'failed', 'error']) of
    0, 1:
      Result := TTestOutcome.Passed;
    2, 3:
      begin
        Result := TTestOutcome.Failed;
        if (ALabel = 'error') or (ALabel = 'cancelled') then
        begin
          Result := TTestOutcome.Error;
        end;
      end;
    4:
      Result := TTestOutcome.Error;
  else
    // Ignored, Skipped, Inconclusive, NotRunnable
    Result := TTestOutcome.Skipped;
  end;
end;

procedure TReportReader.SetRunTime(const ASeconds: string);
begin
  FResult.DurationMs := TTestResults.SecondsToMs(ASeconds);
  FRunTimeKnown := True;
end;

procedure TReportReader.DetectFormat(const AElement: string);
begin
  case IndexStr(AElement, ['test-results', 'test-run', 'testsuites', 'testsuite']) of
    0:
      FResult.Format := 'nunit2';
    1:
      FResult.Format := 'nunit3';
    2, 3:
      FResult.Format := 'junit';
  else
    Exit;
  end;
  if FCursor.SelfClosing then
  begin
    Exit;
  end;
  // Gesamtdauer: NUnit 3 "duration", JUnit "time" an der Wurzel.
  if FCursor.Attribute('duration') <> '' then
  begin
    SetRunTime(FCursor.Attribute('duration'));
  end
  else if (FResult.Format = 'junit') and (FCursor.Attribute('time') <> '') then
  begin
    SetRunTime(FCursor.Attribute('time'));
  end;
end;

procedure TReportReader.StartSuite;
var
  mIsFixture: Boolean;
begin
  // Äußerste Suite (Assembly): Dauer des ganzen Laufs (NUnit 2).
  if not FRunTimeKnown and (FCursor.Attribute('time') <> '') then
  begin
    SetRunTime(FCursor.Attribute('time'));
  end;
  if FCursor.SelfClosing then
  begin
    Exit;
  end;
  mIsFixture := Pos('fixture', LowerCase(FCursor.Attribute('type'))) > 0;
  FSuites := FSuites + [mIsFixture];
  if mIsFixture then
  begin
    FFixtures := FFixtures + [FCursor.Attribute('name')];
  end;
end;

procedure TReportReader.EndSuite;
begin
  if Length(FSuites) = 0 then
  begin
    Exit;
  end;
  if FSuites[High(FSuites)] and (Length(FFixtures) > 0) then
  begin
    SetLength(FFixtures, Length(FFixtures) - 1);
  end;
  SetLength(FSuites, Length(FSuites) - 1);
end;

procedure TReportReader.StartJUnitCase;
var
  mClassName: string;
  mDot: Integer;
begin
  mClassName := FCursor.Attribute('classname');
  FCurrent.Method := FCursor.Attribute('name');
  FCurrent.FullName := mClassName + '.' + FCurrent.Method;
  mDot := LastDelimiter('.', mClassName);
  FCurrent.UnitName := Copy(mClassName, 1, mDot - 1);
  FCurrent.Fixture := Copy(mClassName, mDot + 1, MaxInt);
  // Testfall: "Methode.Fall" im Namen.
  mDot := Pos('.', FCurrent.Method);
  if mDot > 0 then
  begin
    FCurrent.CaseName := Copy(FCurrent.Method, mDot + 1, MaxInt);
    FCurrent.Method := Copy(FCurrent.Method, 1, mDot - 1);
  end;
  FCurrent.DurationMs := TTestResults.SecondsToMs(FCursor.Attribute('time'));
  FCurrent.Outcome := TTestOutcome.Passed;
end;

procedure TReportReader.StartNUnitCase;
var
  mSuiteFixture, mDuration: string;
begin
  FCurrent.FullName := FCursor.Attribute('fullname');
  if FCurrent.FullName = '' then
  begin
    FCurrent.FullName := FCursor.Attribute('name');
  end;
  mSuiteFixture := '';
  if Length(FFixtures) > 0 then
  begin
    mSuiteFixture := FFixtures[High(FFixtures)];
  end;
  TTestResults.SplitName(FCurrent.FullName, mSuiteFixture, FCurrent.UnitName, FCurrent.Fixture, FCurrent.Method,
    FCurrent.CaseName);
  mDuration := FCursor.Attribute('duration');
  if mDuration = '' then
  begin
    mDuration := FCursor.Attribute('time');
  end;
  FCurrent.DurationMs := TTestResults.SecondsToMs(mDuration);
  FCurrent.Outcome := NUnitOutcome(LowerCase(FCursor.Attribute('result')), LowerCase(FCursor.Attribute('label')));
  // executed="False"
  if SameText(FCursor.Attribute('executed'), 'False') and (FCurrent.Outcome = TTestOutcome.Passed) then
  begin
    FCurrent.Outcome := TTestOutcome.Skipped;
  end;
end;

procedure TReportReader.StartCase;
begin
  FCurrent := Default(TTestCaseResult);
  FInCase := True;
  FInFailure := False;
  if FResult.Format = 'junit' then
  begin
    StartJUnitCase;
  end
  else
  begin
    StartNUnitCase;
  end;
end;

procedure TReportReader.EndCase;
var
  mExpected, mActual: string;
begin
  FCurrent.Message := Trim(FCurrent.Message);
  FCurrent.StackTrace := Trim(FCurrent.StackTrace);
  // JUnit ohne Attribut "message": erste Zeile des Texts.
  if (FCurrent.Message = '') and FCurrent.IsFailure and (FCurrent.StackTrace <> '') then
  begin
    FCurrent.Message := FCurrent.StackTrace;
    if Pos(#10, FCurrent.Message) > 0 then
    begin
      FCurrent.Message := Trim(Copy(FCurrent.Message, 1, Pos(#10, FCurrent.Message) - 1));
    end;
  end;
  if FCurrent.IsFailure and TTestResults.SplitValues(FCurrent.Message, mExpected, mActual) then
  begin
    FCurrent.Expected := mExpected;
    FCurrent.Actual := mActual;
    FCurrent.HasValues := True;
  end;
  Inc(FSumMs, FCurrent.DurationMs);
  FResult.Cases := FResult.Cases + [FCurrent];
  FInCase := False;
  FInMessage := False;
  FInStack := False;
end;

procedure TReportReader.TakeMessageAttribute;
begin
  if FCursor.Attribute('message') <> '' then
  begin
    FCurrent.Message := FCursor.Attribute('message');
  end;
end;

procedure TReportReader.StartFailure(const AElement: string);
begin
  FInFailure := True;
  if AElement = 'error' then
  begin
    FCurrent.Outcome := TTestOutcome.Error;
  end
  else if FCurrent.Outcome = TTestOutcome.Passed then
  begin
    FCurrent.Outcome := TTestOutcome.Failed;
  end;
  // JUnit: Meldung im Attribut, der Text ist die Aufrufliste.
  TakeMessageAttribute;
  FInStack := (FResult.Format = 'junit') and not FCursor.SelfClosing;
end;

procedure TReportReader.StartCaseChild(const AElement: string);
begin
  if IsFailureElement(AElement) then
  begin
    StartFailure(AElement);
  end
  else if AElement = 'skipped' then
  begin
    FCurrent.Outcome := TTestOutcome.Skipped;
    TakeMessageAttribute;
  end
  else if not FCursor.SelfClosing then
  begin
    FInMessage := FInMessage or (AElement = 'message');
    FInStack := FInStack or (AElement = 'stack-trace');
  end;
end;

procedure TReportReader.OpenElement(const AElement: string);
begin
  if FResult.Format = '' then
  begin
    DetectFormat(AElement);
  end;
  if AElement = 'test-suite' then
  begin
    StartSuite;
  end
  else if IsCaseElement(AElement) then
  begin
    StartCase;
    if FCursor.SelfClosing then
    begin
      EndCase;
    end;
  end
  else if FInCase then
  begin
    StartCaseChild(AElement);
  end;
end;

procedure TReportReader.CloseElement(const AElement: string);
begin
  if AElement = 'test-suite' then
  begin
    EndSuite;
  end
  else if FInCase and IsCaseElement(AElement) then
  begin
    EndCase;
  end
  else if AElement = 'message' then
  begin
    FInMessage := False;
  end
  else if AElement = 'stack-trace' then
  begin
    FInStack := False;
  end
  else if IsFailureElement(AElement) then
  begin
    FInFailure := False;
    FInStack := False;
  end;
end;

procedure TReportReader.ReadTextNode;
begin
  if not FInCase then
  begin
    Exit;
  end;
  if FInMessage then
  begin
    FCurrent.Message := FCurrent.Message + FCursor.Value;
  end
  else if FInStack then
  begin
    FCurrent.StackTrace := FCurrent.StackTrace + FCursor.Value;
  end
  else if FInFailure and (Trim(FCursor.Value) <> '') and (FCurrent.Message = '') then
  begin
    FCurrent.Message := FCursor.Value;
  end;
end;

function TReportReader.Read(const AXml: string): TTestRunResult;
begin
  FResult := Default(TTestRunResult);
  FCursor.Init(AXml);
  while FCursor.Next do
  begin
    case FCursor.Kind of
      TXmlNodeKind.StartTag:
        OpenElement(LowerCase(FCursor.Name));
      TXmlNodeKind.EndTag:
        CloseElement(LowerCase(FCursor.Name));
      TXmlNodeKind.Text:
        ReadTextNode;
      TXmlNodeKind.Done: ;
    end;
  end;
  if FResult.Format = '' then
  begin
    FResult.Error := 'Kein Testbericht (NUnit oder JUnit) erkannt';
  end
  else
  begin
    FResult.Valid := True;
    if not FRunTimeKnown then
    begin
      FResult.DurationMs := FSumMs;
    end;
  end;
  Result := FResult;
end;

class function TTestResults.Parse(const AXml: string): TTestRunResult;
var
  mReader: TReportReader;
begin
  mReader := TReportReader.Create;
  try
    Result := mReader.Read(AXml);
  finally
    mReader.Free;
  end;
end;

end.
