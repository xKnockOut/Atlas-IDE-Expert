unit Atlas.Text.TestResults;

// Ergebnisse eines DUnitX-Laufs lesen, gemeinsam für Server und Plugin
// (ADR 0012, #69): die XML-Berichte der DUnitX-Logger.
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
  end;

procedure TXmlCursor.Init(const AText: string);
begin
  Source := AText;
  Position := 1;
  Kind := TXmlNodeKind.Done;
end;

function TXmlCursor.Attribute(const AName: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(AttributeNames) do
    if SameText(AttributeNames[Index], AName) then
      Exit(AttributeValues[Index]);
  Result := '';
end;

function TXmlCursor.Next: Boolean;
var
  Start, Stop: Integer;
  Quote: Char;
  AttributeName: string;
begin
  Name := '';
  Value := '';
  SelfClosing := False;
  AttributeNames := nil;
  AttributeValues := nil;
  while Position <= Length(Source) do
  begin
    if Source[Position] <> '<' then
    begin
      Start := Position;
      while (Position <= Length(Source)) and (Source[Position] <> '<') do
        Inc(Position);
      Kind := TXmlNodeKind.Text;
      Value := TTextEntities.Decode(Copy(Source, Start, Position - Start));
      Exit(True);
    end;
    if Copy(Source, Position, 9) = '<![CDATA[' then
    begin
      Start := Position + 9;
      Stop := PosEx(']]>', Source, Start);
      if Stop = 0 then
        Stop := Length(Source) + 1;
      Kind := TXmlNodeKind.Text;
      Value := Copy(Source, Start, Stop - Start);
      Position := Stop + 3;
      Exit(True);
    end;
    if Copy(Source, Position, 4) = '<!--' then
    begin
      Stop := PosEx('-->', Source, Position + 4);
      if Stop = 0 then
        Break;
      Position := Stop + 3;
      Continue;
    end;
    if (Copy(Source, Position, 2) = '<?') or (Copy(Source, Position, 2) = '<!') then
    begin
      Stop := PosEx('>', Source, Position + 2);
      if Stop = 0 then
        Break;
      Position := Stop + 1;
      Continue;
    end;
    Inc(Position);
    Kind := TXmlNodeKind.StartTag;
    if (Position <= Length(Source)) and (Source[Position] = '/') then
    begin
      Kind := TXmlNodeKind.EndTag;
      Inc(Position);
    end;
    Start := Position;
    while (Position <= Length(Source)) and not CharInSet(Source[Position], [' ', #9, #13, #10, '/', '>']) do
      Inc(Position);
    Name := Copy(Source, Start, Position - Start);
    while Position <= Length(Source) do
    begin
      case Source[Position] of
        '>':
          begin
            Inc(Position);
            Exit(True);
          end;
        '/':
          begin
            SelfClosing := True;
            Inc(Position);
          end;
        ' ', #9, #13, #10:
          Inc(Position);
      else
        Start := Position;
        while (Position <= Length(Source)) and not CharInSet(Source[Position], ['=', ' ', #9, #13, #10, '>', '/']) do
          Inc(Position);
        AttributeName := Copy(Source, Start, Position - Start);
        while (Position <= Length(Source)) and CharInSet(Source[Position], [' ', #9, #13, #10]) do
          Inc(Position);
        if (Position <= Length(Source)) and (Source[Position] = '=') then
        begin
          Inc(Position);
          while (Position <= Length(Source)) and CharInSet(Source[Position], [' ', #9, #13, #10]) do
            Inc(Position);
          if (Position <= Length(Source)) and CharInSet(Source[Position], ['"', '''']) then
          begin
            Quote := Source[Position];
            Inc(Position);
            Start := Position;
            while (Position <= Length(Source)) and (Source[Position] <> Quote) do
              Inc(Position);
            AttributeNames := AttributeNames + [AttributeName];
            AttributeValues := AttributeValues + [TTextEntities.Decode(Copy(Source, Start, Position - Start))];
            Inc(Position);
          end;
        end;
      end;
    end;
    Exit(True);
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
  Item: TTestCaseResult;
begin
  Result := 0;
  for Item in Cases do
    if Item.Outcome = AOutcome then
      Inc(Result);
end;

function TTestRunResult.Total: Integer;
begin
  Result := Length(Cases);
end;

function TTestRunResult.Failures: TArray<TTestCaseResult>;
var
  Item: TTestCaseResult;
begin
  Result := nil;
  for Item in Cases do
    if Item.IsFailure then
      Result := Result + [Item];
end;

function TTestRunResult.AllPassed: Boolean;
begin
  Result := Valid and (Total > 0) and (Length(Failures) = 0);
end;

{ TTestResults }

class function TTestResults.SecondsToMs(const AText: string): Int64;
var
  Value: Double;
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Invariant;
  if not TryStrToFloat(StringReplace(Trim(AText), ',', '.', []), Value, Settings) or (Value < 0) then
    Exit(0);
  Result := Round(Value * 1000);
end;

class function TTestResults.SplitValues(const AMessage: string; out AExpected, AActual: string): Boolean;
var
  Text: string;
  ExpectedAt, ActualAt, LineEnd: Integer;

  function Unquote(const AValue: string): string;
  begin
    Result := Trim(AValue);
    if (Length(Result) >= 2) and CharInSet(Result[1], ['"', '''', '<']) and
      (Result[Length(Result)] = Result[1]) then
      Result := Copy(Result, 2, Length(Result) - 2)
    else if (Length(Result) >= 2) and (Result[1] = '<') and (Result[Length(Result)] = '>') then
      Result := Copy(Result, 2, Length(Result) - 2);
  end;

begin
  AExpected := '';
  AActual := '';
  Text := StringReplace(AMessage, #13, '', [rfReplaceAll]);
  // NUnit: "Expected: 3" und in der nächsten Zeile "But was: 4".
  ExpectedAt := Pos('expected:', LowerCase(Text));
  ActualAt := Pos('but was:', LowerCase(Text));
  if (ExpectedAt > 0) and (ActualAt > ExpectedAt) then
  begin
    AExpected := Unquote(Copy(Text, ExpectedAt + 9, ActualAt - ExpectedAt - 9));
    AActual := Copy(Text, ActualAt + 8, MaxInt);
    LineEnd := Pos(#10, AActual);
    if LineEnd > 0 then
      AActual := Copy(AActual, 1, LineEnd - 1);
    AActual := Unquote(AActual);
    Exit(True);
  end;
  // DUnitX: "Expected 3 but got 4" (dahinter ggf. die eigene Meldung des Tests).
  ExpectedAt := Pos('expected ', LowerCase(Text));
  if ExpectedAt > 0 then
    ActualAt := PosEx(' but got ', LowerCase(Text), ExpectedAt + 9)
  else
    ActualAt := 0;
  if (ExpectedAt > 0) and (ActualAt > 0) then
  begin
    AExpected := Unquote(Copy(Text, ExpectedAt + 9, ActualAt - ExpectedAt - 9));
    AActual := Copy(Text, ActualAt + 9, MaxInt);
    LineEnd := Pos(#10, AActual);
    if LineEnd > 0 then
      AActual := Copy(AActual, 1, LineEnd - 1);
    AActual := Unquote(AActual);
    Exit(True);
  end;
  Result := False;
end;

class procedure TTestResults.SplitName(const AFullName, AFixture: string; out AUnitName, AFixtureName, AMethod,
  ACaseName: string);
var
  Parts: TArray<string>;
  At, Index: Integer;
  Rest: string;
begin
  AUnitName := '';
  AFixtureName := AFixture;
  AMethod := '';
  ACaseName := '';
  if AFixture <> '' then
  begin
    // Die Fixture steht als eigener Teil im Namen: Unit.Fixture.Methode[.Fall].
    At := Pos(LowerCase('.' + AFixture + '.'), LowerCase('.' + AFullName));
    if At > 0 then
    begin
      AUnitName := Copy(AFullName, 1, At - 2);
      Rest := Copy(AFullName, At + Length(AFixture) + 1, MaxInt);
      AFixtureName := Copy(AFullName, At, Length(AFixture));
      Index := Pos('.', Rest);
      if Index > 0 then
      begin
        AMethod := Copy(Rest, 1, Index - 1);
        ACaseName := Copy(Rest, Index + 1, MaxInt);
      end
      else
        AMethod := Rest;
      Exit;
    end;
  end;
  Parts := AFullName.Split(['.']);
  if Length(Parts) >= 2 then
  begin
    AFixtureName := Parts[High(Parts) - 1];
    AMethod := Parts[High(Parts)];
    for Index := 0 to High(Parts) - 2 do
    begin
      if AUnitName <> '' then
        AUnitName := AUnitName + '.';
      AUnitName := AUnitName + Parts[Index];
    end;
  end
  else
    AMethod := AFullName;
end;

class function TTestResults.Parse(const AXml: string): TTestRunResult;
var
  Cursor: TXmlCursor;
  Fixtures: TArray<string>;
  Suites: TArray<Boolean>;
  Current: TTestCaseResult;
  InCase, InMessage, InStack, InFailure, RunTimeKnown: Boolean;
  Element, SuiteType, ResultText, Label_, ClassName: string;
  SumMs: Int64;

  procedure StartCase;
  var
    UnitName, SuiteFixture, FixtureName, Method, CaseName: string;
  begin
    Current := Default(TTestCaseResult);
    InCase := True;
    InFailure := False;
    if Result.Format = 'junit' then
    begin
      ClassName := Cursor.Attribute('classname');
      Current.Method := Cursor.Attribute('name');
      Current.FullName := ClassName + '.' + Current.Method;
      if LastDelimiter('.', ClassName) > 0 then
      begin
        Current.UnitName := Copy(ClassName, 1, LastDelimiter('.', ClassName) - 1);
        Current.Fixture := Copy(ClassName, LastDelimiter('.', ClassName) + 1, MaxInt);
      end
      else
        Current.Fixture := ClassName;
      // Testfall: "Methode.Fall" im Namen.
      if Pos('.', Current.Method) > 0 then
      begin
        Current.CaseName := Copy(Current.Method, Pos('.', Current.Method) + 1, MaxInt);
        Current.Method := Copy(Current.Method, 1, Pos('.', Current.Method) - 1);
      end;
      Current.DurationMs := SecondsToMs(Cursor.Attribute('time'));
      Current.Outcome := TTestOutcome.Passed;
      Exit;
    end;
    Current.FullName := Cursor.Attribute('fullname');
    if Current.FullName = '' then
      Current.FullName := Cursor.Attribute('name');
    SuiteFixture := '';
    if Length(Fixtures) > 0 then
      SuiteFixture := Fixtures[High(Fixtures)];
    SplitName(Current.FullName, SuiteFixture, UnitName, FixtureName, Method, CaseName);
    Current.UnitName := UnitName;
    Current.Fixture := FixtureName;
    Current.Method := Method;
    Current.CaseName := CaseName;
    if Cursor.Attribute('duration') <> '' then
      Current.DurationMs := SecondsToMs(Cursor.Attribute('duration'))
    else
      Current.DurationMs := SecondsToMs(Cursor.Attribute('time'));
    ResultText := LowerCase(Cursor.Attribute('result'));
    Label_ := LowerCase(Cursor.Attribute('label'));
    if (ResultText = 'success') or (ResultText = 'passed') then
      Current.Outcome := TTestOutcome.Passed
    else if (ResultText = 'failure') or (ResultText = 'failed') then
    begin
      Current.Outcome := TTestOutcome.Failed;
      if (Label_ = 'error') or (Label_ = 'cancelled') then
        Current.Outcome := TTestOutcome.Error;
    end
    else if ResultText = 'error' then
      Current.Outcome := TTestOutcome.Error
    else
      // Ignored, Skipped, Inconclusive, NotRunnable, executed="False"
      Current.Outcome := TTestOutcome.Skipped;
    if SameText(Cursor.Attribute('executed'), 'False') and (Current.Outcome = TTestOutcome.Passed) then
      Current.Outcome := TTestOutcome.Skipped;
  end;

  procedure EndCase;
  var
    Expected, Actual: string;
  begin
    Current.Message := Trim(Current.Message);
    Current.StackTrace := Trim(Current.StackTrace);
    // JUnit ohne Attribut "message": erste Zeile des Texts.
    if (Current.Message = '') and Current.IsFailure and (Current.StackTrace <> '') then
    begin
      Current.Message := Current.StackTrace;
      if Pos(#10, Current.Message) > 0 then
        Current.Message := Trim(Copy(Current.Message, 1, Pos(#10, Current.Message) - 1));
    end;
    if Current.IsFailure and SplitValues(Current.Message, Expected, Actual) then
    begin
      Current.Expected := Expected;
      Current.Actual := Actual;
      Current.HasValues := True;
    end;
    Inc(SumMs, Current.DurationMs);
    Result.Cases := Result.Cases + [Current];
    InCase := False;
    InMessage := False;
    InStack := False;
  end;

begin
  Result := Default(TTestRunResult);
  Result.Cases := nil;
  Cursor.Init(AXml);
  Fixtures := nil;
  Suites := nil;
  InCase := False;
  InMessage := False;
  InStack := False;
  InFailure := False;
  RunTimeKnown := False;
  SumMs := 0;
  while Cursor.Next do
  begin
    Element := LowerCase(Cursor.Name);
    case Cursor.Kind of
      TXmlNodeKind.StartTag:
        begin
          if Result.Format = '' then
          begin
            if Element = 'test-results' then
              Result.Format := 'nunit2'
            else if Element = 'test-run' then
              Result.Format := 'nunit3'
            else if (Element = 'testsuites') or (Element = 'testsuite') then
              Result.Format := 'junit';
            if (Result.Format <> '') and not Cursor.SelfClosing then
            begin
              // Gesamtdauer: NUnit 3 "duration", JUnit "time" an der Wurzel.
              if Cursor.Attribute('duration') <> '' then
              begin
                Result.DurationMs := SecondsToMs(Cursor.Attribute('duration'));
                RunTimeKnown := True;
              end
              else if (Result.Format = 'junit') and (Cursor.Attribute('time') <> '') then
              begin
                Result.DurationMs := SecondsToMs(Cursor.Attribute('time'));
                RunTimeKnown := True;
              end;
            end;
          end;
          if Element = 'test-suite' then
          begin
            SuiteType := LowerCase(Cursor.Attribute('type'));
            // Äußerste Suite (Assembly): Dauer des ganzen Laufs (NUnit 2).
            if not RunTimeKnown and (Cursor.Attribute('time') <> '') then
            begin
              Result.DurationMs := SecondsToMs(Cursor.Attribute('time'));
              RunTimeKnown := True;
            end;
            if not Cursor.SelfClosing then
            begin
              Suites := Suites + [Pos('fixture', SuiteType) > 0];
              if Pos('fixture', SuiteType) > 0 then
                Fixtures := Fixtures + [Cursor.Attribute('name')];
            end;
          end
          else if (Element = 'test-case') or (Element = 'testcase') then
          begin
            StartCase;
            if Cursor.SelfClosing then
              EndCase;
          end
          else if InCase and ((Element = 'failure') or (Element = 'error')) then
          begin
            InFailure := True;
            if Element = 'error' then
              Current.Outcome := TTestOutcome.Error
            else if Current.Outcome = TTestOutcome.Passed then
              Current.Outcome := TTestOutcome.Failed;
            // JUnit: Meldung im Attribut, der Text ist die Aufrufliste.
            if Cursor.Attribute('message') <> '' then
              Current.Message := Cursor.Attribute('message');
            InStack := (Result.Format = 'junit') and not Cursor.SelfClosing;
          end
          else if InCase and (Element = 'skipped') then
          begin
            Current.Outcome := TTestOutcome.Skipped;
            if Cursor.Attribute('message') <> '' then
              Current.Message := Cursor.Attribute('message');
          end
          else if InCase and (Element = 'message') and not Cursor.SelfClosing then
            InMessage := True
          else if InCase and (Element = 'stack-trace') and not Cursor.SelfClosing then
            InStack := True;
        end;
      TXmlNodeKind.EndTag:
        begin
          if Element = 'test-suite' then
          begin
            if Length(Suites) > 0 then
            begin
              if Suites[High(Suites)] and (Length(Fixtures) > 0) then
                SetLength(Fixtures, Length(Fixtures) - 1);
              SetLength(Suites, Length(Suites) - 1);
            end;
          end
          else if InCase and ((Element = 'test-case') or (Element = 'testcase')) then
            EndCase
          else if Element = 'message' then
            InMessage := False
          else if Element = 'stack-trace' then
            InStack := False
          else if (Element = 'failure') or (Element = 'error') then
          begin
            InFailure := False;
            InStack := False;
          end;
        end;
      TXmlNodeKind.Text:
        if InCase then
        begin
          if InMessage then
            Current.Message := Current.Message + Cursor.Value
          else if InStack then
            Current.StackTrace := Current.StackTrace + Cursor.Value
          else if InFailure and (Trim(Cursor.Value) <> '') and (Current.Message = '') then
            Current.Message := Cursor.Value;
        end;
      TXmlNodeKind.Done: ;
    end;
  end;
  if Result.Format = '' then
  begin
    Result.Error := 'Kein Testbericht (NUnit oder JUnit) erkannt';
    Exit;
  end;
  Result.Valid := True;
  if not RunTimeKnown then
    Result.DurationMs := SumMs;
end;

end.
