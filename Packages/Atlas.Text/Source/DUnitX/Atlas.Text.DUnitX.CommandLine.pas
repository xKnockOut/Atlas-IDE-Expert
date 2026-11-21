unit Atlas.Text.DUnitX.CommandLine;

// Befehlszeile eines DUnitX-Testprogramms, gemeinsam für Server und Plugin (#69, #585): volle Namen für --run
// (Unit.Fixture.Methode, bei [TestCase] Unit.Fixture.Methode.Fall) und die Argumente eines Laufs. --run
// (TNameFilter von DUnitX) trifft einen Test, wenn ein Name ein Anfang des vollen Namens seiner Fixture oder genau
// sein voller Name ist; RunNames bildet darum Namen, die genau das Gewählte treffen. Fixtures und Tests liest
// Atlas.Text.DUnitX aus dem Quelltext.

interface

uses
  Atlas.Text.DUnitX;

type
  TDUnitXCommandLine = class
  public const
    /// <summary>Höchstlänge der Namen in einem --run-Argument; darüber alle Tests (Windows erlaubt 32767 Zeichen
    /// je Befehlszeile).</summary>
    cMaxRunLength = 24000;
  public
    /// <summary>Voller Name für --run: Unit.Fixture bzw. Unit.Fixture.Methode (AMethod = '').</summary>
    class function TestName(const AUnitName, AFixture, AMethod: string): string; static;
    /// <summary>Voller Name eines Testfalls wie in DUnitX: Unit.Fixture.Methode.Fall; ein Fall in Klammern
    /// ohne Punkt davor, ein leerer Fall ergibt Unit.Fixture.Methode.</summary>
    class function CaseName(const AUnitName, AFixture, AMethod, ACase: string): string; static;
    /// <summary>Für Meldungen: Fixture.Methode.Fall ohne Unit; leere Methode bzw. leerer Fall fallen weg.</summary>
    class function Caption(const AFixture, AMethod, ACase: string): string; static;
    /// <summary>Namen für --run, die genau die Fixture AFixtureIndex (ATestIndex = -1), den Test ATestIndex mit
    /// allen Fällen (ACaseIndex = -1) bzw. nur den Fall ACaseIndex treffen (#585). [TestCase]-Methoden: je Fall
    /// ein Name (Unit.Fixture.Methode allein trifft sie nicht); mit [Ignore] führt DUnitX sie als einen Test
    /// ohne Fall. Eine Fixture, deren Name der Anfang einer anderen Fixture der Unit ist, wird über ihre Tests
    /// genannt, sonst liefe die andere mit (DUnitX vergleicht den Anfang). Leer bei ungültigem Index.</summary>
    class function RunNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
      ACaseIndex: Integer): TArray<string>; static;
    /// <summary>Argumente eines Laufs: XML-Bericht nach AResultFile, ohne Warten am Ende, mit --run, wenn ATests
    /// Namen enthält (sonst alle Tests). Einträge, die mit „--“ beginnen (--include:Kat, --exclude:Kat der
    /// Testlisten, #2167), gehen als eigene Option an das Programm, nicht in --run.</summary>
    class function Arguments(const AResultFile: string; const ATests: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils;

{ TDUnitXCommandLine }

class function TDUnitXCommandLine.TestName(const AUnitName, AFixture, AMethod: string): string;
begin
  Result := AFixture;
  if AUnitName <> '' then
  begin
    Result := AUnitName + '.' + Result;
  end;
  if AMethod <> '' then
  begin
    Result := Result + '.' + AMethod;
  end;
end;

class function TDUnitXCommandLine.Caption(const AFixture, AMethod, ACase: string): string;
begin
  Result := TestName('', AFixture, AMethod);
  if ACase <> '' then
  begin
    Result := Result + '.' + ACase;
  end;
end;

class function TDUnitXCommandLine.CaseName(const AUnitName, AFixture, AMethod, ACase: string): string;
begin
  Result := TestName(AUnitName, AFixture, AMethod);
  // TDUnitXTestCase.GetName: „Methode(1,2)“ bei AutoNameTestCase, sonst „Methode.Fall“.
  if ACase = '' then
  begin
    Exit;
  end;
  if ACase[1] = '(' then
  begin
    Result := Result + ACase;
  end
  else
  begin
    Result := Result + '.' + ACase;
  end;
end;

class function TDUnitXCommandLine.RunNames(const AUnit: TDUnitXUnit; AFixtureIndex, ATestIndex,
  ACaseIndex: Integer): TArray<string>;
var
  mFixture: TDUnitXFixture;
  mTest: TDUnitXTest;
  mIndex: Integer;
  mName: string;
  mShadowed: Boolean;
  mNames: TArray<string>;

  procedure Add(const AName: string);
  var
    mKnown: string;
  begin
    for mKnown in mNames do
    begin
      if SameText(mKnown, AName) then
      begin
        Exit;
      end;
    end;
    mNames := mNames + [AName];
  end;

  procedure AddTest(const ATest: TDUnitXTest; ACase: Integer);
  var
    mCaseIndex: Integer;
  begin
    // Ohne Fälle oder mit [Ignore] (DUnitX führt sie dann als einen Test): der Name der Methode.
    if (Length(ATest.Cases) = 0) or ATest.Ignored then
    begin
      Add(TestName(AUnit.UnitName, mFixture.Name, ATest.Method));
    end
    else if (ACase >= 0) and (ACase <= High(ATest.Cases)) then
    begin
      Add(CaseName(AUnit.UnitName, mFixture.Name, ATest.Method, ATest.Cases[ACase]));
    end
    else
    begin
      for mCaseIndex := 0 to High(ATest.Cases) do
      begin
        Add(CaseName(AUnit.UnitName, mFixture.Name, ATest.Method, ATest.Cases[mCaseIndex]));
      end;
    end;
  end;

begin
  Result := nil;
  mNames := nil;
  if (AFixtureIndex < 0) or (AFixtureIndex > High(AUnit.Fixtures)) then
  begin
    Exit;
  end;
  mFixture := AUnit.Fixtures[AFixtureIndex];
  if ATestIndex >= 0 then
  begin
    if ATestIndex > High(mFixture.Tests) then
    begin
      Exit;
    end;
    mTest := mFixture.Tests[ATestIndex];
    AddTest(mTest, ACaseIndex);
    Exit(mNames);
  end;
  // Die ganze Fixture: Unit.Fixture, außer eine andere Fixture der Unit beginnt mit demselben Namen.
  mShadowed := False;
  for mIndex := 0 to High(AUnit.Fixtures) do
  begin
    mName := AUnit.Fixtures[mIndex].Name;
    if (mIndex <> AFixtureIndex) and (Length(mName) > Length(mFixture.Name)) and
      SameText(Copy(mName, 1, Length(mFixture.Name)), mFixture.Name) then
    begin
      mShadowed := True;
    end;
  end;
  if not mShadowed then
  begin
    Result := [TestName(AUnit.UnitName, mFixture.Name, '')];
    Exit;
  end;
  for mTest in mFixture.Tests do
  begin
    AddTest(mTest, -1);
  end;
  Result := mNames;
end;

class function TDUnitXCommandLine.Arguments(const AResultFile: string; const ATests: TArray<string>): TArray<string>;
var
  mRun: string;
  mTest: string;
  mRunNames: TArray<string>;
begin
  // Nur Optionen, die alle DUnitX-Fassungen seit RAD Studio 10 kennen; eine unbekannte Option lässt das
  // Testprogramm ohne Lauf enden (TDUnitX.CheckCommandLine).
  Result := ['--exitbehavior:Continue', '--xmlfile:' + AResultFile];
  mRunNames := nil;
  for mTest in ATests do
  begin
    if Copy(mTest, 1, 2) = '--' then
    begin
      Result := Result + [mTest];
    end
    else if mTest <> '' then
    begin
      mRunNames := mRunNames + [mTest];
    end;
  end;
  mRun := string.Join(',', mRunNames);
  if (mRun <> '') and (Length(mRun) <= cMaxRunLength) then
  begin
    Result := Result + ['--run:' + mRun];
  end;
end;

end.
