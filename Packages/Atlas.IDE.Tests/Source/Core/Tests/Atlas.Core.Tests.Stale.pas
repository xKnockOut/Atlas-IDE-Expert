unit Atlas.Core.Tests.Stale;

// Veraltete Testergebnisse (#1770), ohne VCL und Open Tools API:
// - Nach einem Lauf merkt sich das Modul je Test (Unit.Fixture.Methode) die
//   Prüfsumme seines Methodenrumpfs (Methodenkopf im implementation-Teil bis
//   zum abschließenden end, Atlas.Text.DUnitX, ohne Leerraum und
//   Kommentare); mit tests.stale.units zusätzlich die Prüfsummen der Units,
//   die die Testunit verwendet und die das Testprojekt kennt.
// - Weicht eine Prüfsumme vom aktuellen Text ab, ist das Ergebnis veraltet:
//   Die Code Lens zeigt den alten Stand grau mit „(veraltet)“, die Zählung
//   einer Marke über mehrere Tests nimmt es nicht als bestanden
//   (TAtlasTestTally), „Veraltete Tests ausführen“ führt genau diese aus.
// Dateien liest der Aufrufer (Puffer der IDE oder Platte) über
// TAtlasTestReadLines, Units findet er über TAtlasTestUnitFile.

interface

uses
  System.Generics.Collections,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

type
  /// <summary>Ist das Ergebnis des Tests AMethod (der Fixture einer Marke) veraltet?</summary>
  TAtlasTestStaleFunc = reference to function(const AMethod: string): Boolean;
  /// <summary>Schlüssel (TAtlasTestStamps.KeyOf) der Tests von AUnit, deren Ergebnis im Text ALines veraltet ist.
  /// </summary>
  TAtlasTestStaleKeys = reference to function(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<string>;
  /// <summary>Datei der Unit AUnitName im Testprojekt; '' ohne (auch TAtlasTestRun.Failures).</summary>
  TAtlasTestUnitFile = reference to function(const AUnitName: string): string;
  /// <summary>Zeilen einer Datei (ohne Zeilenende); False, wenn sie nicht lesbar ist (auch
  /// TAtlasTestRun.Failures).</summary>
  TAtlasTestReadLines = reference to function(const AFileName: string; out ALines: TArray<string>): Boolean;

  /// <summary>Datei und Prüfsumme einer verwendeten Unit beim Lauf.</summary>
  TAtlasUnitStamp = record
    FileName: string;
    Fingerprint: string;
  end;

  /// <summary>Stand eines Tests beim Lauf.</summary>
  TAtlasTestStamp = record
    /// <summary>.dproj des Testprojekts.</summary>
    Project: string;
    /// <summary>Datei der Testunit.</summary>
    FileName: string;
    /// <summary>Prüfsumme des Methodenrumpfs.</summary>
    Body: string;
    /// <summary>Verwendete Units (nur mit tests.stale.units, sonst leer).</summary>
    Units: TArray<TAtlasUnitStamp>;
    /// <summary>Volle Namen der gelaufenen Fälle für --run (Unit.Fixture.Methode[.Fall]).</summary>
    Names: TArray<string>;
  end;

  /// <summary>Veraltete Tests eines Testprojekts für „Veraltete Tests ausführen“.</summary>
  TAtlasStaleRun = record
    Project: string;
    /// <summary>Eine Testunit des Projekts (zum Auflösen des Testprojekts).</summary>
    FileName: string;
    /// <summary>Namen für --run.</summary>
    Names: TArray<string>;
  end;

  TAtlasTestStamps = class
  private
    FStamps: TDictionary<string, TAtlasTestStamp>;
    /// <summary>Hat sich eine der Units AUnits geändert? Liest jede Datei höchstens einmal je ACache.</summary>
    class function UnitsChanged(const AUnits: TArray<TAtlasUnitStamp>; const AReadLines: TAtlasTestReadLines;
      ACache: TDictionary<string, string>): Boolean; static;
    function StaleKeys(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AWithUnits: Boolean;
      const AReadLines: TAtlasTestReadLines; ACache: TDictionary<string, string>): TArray<string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Schlüssel eines Tests: Unit.Fixture.Methode in Kleinbuchstaben (alle Fälle eines [TestCase]
    /// teilen sich den Rumpf).</summary>
    class function KeyOf(const AUnitName, AFixture, AMethod: string): string; static;
    /// <summary>Prüfsumme des Rumpfs von Test ATestIndex der Fixture AFixtureIndex; '' ohne Rumpf.</summary>
    class function BodyOf(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AFixtureIndex,
      ATestIndex: Integer): string; static;
    /// <summary>Prüfsumme einer ganzen Datei; '' wenn sie nicht lesbar ist.</summary>
    class function FileFingerprint(const AFileName: string; const AReadLines: TAtlasTestReadLines): string; static;
    /// <summary>Units der uses-Klauseln von ALines, die AUnitFile im Testprojekt findet, mit ihren Prüfsummen.
    /// </summary>
    class function UnitStamps(const ALines: TArray<string>; const AUnitFile: TAtlasTestUnitFile;
      const AReadLines: TAtlasTestReadLines): TArray<TAtlasUnitStamp>; static;
    /// <summary>Lauf merken: jeder Test der Unit AUnit (Text ALines, Datei AFileName), zu dem ACases ein Ergebnis
    /// hat, bekommt den Stand von jetzt.</summary>
    procedure Remember(const AProject, AFileName: string; const AUnit: TDUnitXUnit; const ALines: TArray<string>;
      const ACases: TArray<TTestCaseResult>; const AUnits: TArray<TAtlasUnitStamp>);
    function TryGet(const AKey: string; out AStamp: TAtlasTestStamp): Boolean;
    /// <summary>Schlüssel (KeyOf) der Tests von AUnit, deren Ergebnis im Text ALines veraltet ist; mit AWithUnits
    /// auch wegen geänderter verwendeter Units (gelesen über AReadLines).</summary>
    function StaleIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AWithUnits: Boolean;
      const AReadLines: TAtlasTestReadLines): TArray<string>;
    /// <summary>Veraltete Tests je Testprojekt mit ihren Namen für --run; liest jede Testunit einmal.</summary>
    function StaleRuns(AWithUnits: Boolean; const AReadLines: TAtlasTestReadLines): TArray<TAtlasStaleRun>;
    /// <summary>Steht AValue in AValues?</summary>
    class function Listed(const AValues: TArray<string>; const AValue: string): Boolean; static;
    /// <summary>Gibt es Stände?</summary>
    function Count: Integer;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Steht AValue in AValues?</summary>
function InList(const AValues: TArray<string>; const AValue: string): Boolean;
var
  mValue: string;
begin
  Result := False;
  for mValue in AValues do
  begin
    if mValue = AValue then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Volle Namen der Fälle in ACases zum Test AKey.</summary>
function NamesOf(const ACases: TArray<TTestCaseResult>; const AKey: string): TArray<string>;
var
  mCase: TTestCaseResult;
begin
  Result := nil;
  for mCase in ACases do
  begin
    if (mCase.FullName <> '') and (TAtlasTestStamps.KeyOf(mCase.UnitName, mCase.Fixture, mCase.Method) = AKey) then
    begin
      Result := Result + [mCase.FullName];
    end;
  end;
end;

{ TAtlasTestStamps }

constructor TAtlasTestStamps.Create;
begin
  inherited Create;
  FStamps := TDictionary<string, TAtlasTestStamp>.Create;
end;

destructor TAtlasTestStamps.Destroy;
begin
  FStamps.Free;
  inherited Destroy;
end;

class function TAtlasTestStamps.KeyOf(const AUnitName, AFixture, AMethod: string): string;
begin
  Result := AnsiLowerCase(AUnitName + '.' + AFixture + '.' + AMethod);
end;

class function TAtlasTestStamps.BodyOf(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AFixtureIndex,
  ATestIndex: Integer): string;
var
  mTest: TDUnitXTest;
begin
  Result := '';
  if (AFixtureIndex < 0) or (AFixtureIndex > High(AUnit.Fixtures)) or (ATestIndex < 0) or
    (ATestIndex > High(AUnit.Fixtures[AFixtureIndex].Tests)) then
  begin
    Exit;
  end;
  mTest := AUnit.Fixtures[AFixtureIndex].Tests[ATestIndex];
  if (mTest.BodyLine >= 0) and (mTest.EndLine >= mTest.BodyLine) then
  begin
    Result := TDUnitXSource.Fingerprint(ALines, mTest.BodyLine, mTest.EndLine);
  end;
end;

class function TAtlasTestStamps.FileFingerprint(const AFileName: string;
  const AReadLines: TAtlasTestReadLines): string;
var
  mLines: TArray<string>;
begin
  Result := '';
  if Assigned(AReadLines) and AReadLines(AFileName, mLines) then
  begin
    Result := TDUnitXSource.Fingerprint(mLines, 0, High(mLines));
  end;
end;

class function TAtlasTestStamps.UnitStamps(const ALines: TArray<string>; const AUnitFile: TAtlasTestUnitFile;
  const AReadLines: TAtlasTestReadLines): TArray<TAtlasUnitStamp>;
var
  mName: string;
  mStamp: TAtlasUnitStamp;
begin
  Result := nil;
  if not Assigned(AUnitFile) then
  begin
    Exit;
  end;
  for mName in TDUnitXSource.UsedUnits(ALines) do
  begin
    mStamp := Default(TAtlasUnitStamp);
    mStamp.FileName := AUnitFile(mName);
    // Nur Units des Testprojekts: RTL, VCL und DUnitX ändern sich nicht im Editor.
    if mStamp.FileName = '' then
    begin
      Continue;
    end;
    mStamp.Fingerprint := FileFingerprint(mStamp.FileName, AReadLines);
    if mStamp.Fingerprint <> '' then
    begin
      Result := Result + [mStamp];
    end;
  end;
end;

procedure TAtlasTestStamps.Remember(const AProject, AFileName: string; const AUnit: TDUnitXUnit;
  const ALines: TArray<string>; const ACases: TArray<TTestCaseResult>; const AUnits: TArray<TAtlasUnitStamp>);
var
  mRan: TArray<string>;
  mCase: TTestCaseResult;
  mFixture, mTest: Integer;
  mKey: string;
  mStamp: TAtlasTestStamp;
begin
  mRan := nil;
  for mCase in ACases do
  begin
    mRan := mRan + [KeyOf(mCase.UnitName, mCase.Fixture, mCase.Method)];
  end;
  for mFixture := 0 to High(AUnit.Fixtures) do
  begin
    for mTest := 0 to High(AUnit.Fixtures[mFixture].Tests) do
    begin
      mKey := KeyOf(AUnit.UnitName, AUnit.Fixtures[mFixture].Name, AUnit.Fixtures[mFixture].Tests[mTest].Method);
      if not InList(mRan, mKey) then
      begin
        Continue;
      end;
      mStamp := Default(TAtlasTestStamp);
      mStamp.Project := AProject;
      mStamp.FileName := AFileName;
      mStamp.Body := BodyOf(AUnit, ALines, mFixture, mTest);
      mStamp.Units := AUnits;
      mStamp.Names := NamesOf(ACases, mKey);
      FStamps.AddOrSetValue(mKey, mStamp);
    end;
  end;
end;

function TAtlasTestStamps.TryGet(const AKey: string; out AStamp: TAtlasTestStamp): Boolean;
begin
  Result := FStamps.TryGetValue(AKey, AStamp);
end;

function TAtlasTestStamps.Count: Integer;
begin
  Result := FStamps.Count;
end;

class function TAtlasTestStamps.UnitsChanged(const AUnits: TArray<TAtlasUnitStamp>;
  const AReadLines: TAtlasTestReadLines; ACache: TDictionary<string, string>): Boolean;
var
  mStamp: TAtlasUnitStamp;
  mKey, mNow: string;
begin
  Result := False;
  for mStamp in AUnits do
  begin
    mKey := AnsiLowerCase(mStamp.FileName);
    if not ACache.TryGetValue(mKey, mNow) then
    begin
      mNow := FileFingerprint(mStamp.FileName, AReadLines);
      ACache.Add(mKey, mNow);
    end;
    // Nicht mehr lesbar zählt als geändert.
    if mNow <> mStamp.Fingerprint then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasTestStamps.StaleKeys(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AWithUnits: Boolean;
  const AReadLines: TAtlasTestReadLines; ACache: TDictionary<string, string>): TArray<string>;
var
  mFixture, mTest: Integer;
  mKey: string;
  mStamp: TAtlasTestStamp;
begin
  Result := nil;
  for mFixture := 0 to High(AUnit.Fixtures) do
  begin
    for mTest := 0 to High(AUnit.Fixtures[mFixture].Tests) do
    begin
      mKey := KeyOf(AUnit.UnitName, AUnit.Fixtures[mFixture].Name, AUnit.Fixtures[mFixture].Tests[mTest].Method);
      if not FStamps.TryGetValue(mKey, mStamp) then
      begin
        Continue;
      end;
      if (mStamp.Body <> BodyOf(AUnit, ALines, mFixture, mTest)) or
        (AWithUnits and UnitsChanged(mStamp.Units, AReadLines, ACache)) then
      begin
        Result := Result + [mKey];
      end;
    end;
  end;
end;

function TAtlasTestStamps.StaleIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>; AWithUnits: Boolean;
  const AReadLines: TAtlasTestReadLines): TArray<string>;
var
  mCache: TDictionary<string, string>;
begin
  mCache := TDictionary<string, string>.Create;
  try
    Result := StaleKeys(AUnit, ALines, AWithUnits, AReadLines, mCache);
  finally
    mCache.Free;
  end;
end;

/// <summary>Lauf für das Testprojekt AProject in ARuns; legt ihn an, wenn es ihn noch nicht gibt.</summary>
function RunFor(var ARuns: TArray<TAtlasStaleRun>; const AStamp: TAtlasTestStamp): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARuns) do
  begin
    if SameText(ARuns[mIndex].Project, AStamp.Project) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := Length(ARuns);
  SetLength(ARuns, Result + 1);
  ARuns[Result].Project := AStamp.Project;
  ARuns[Result].FileName := AStamp.FileName;
  ARuns[Result].Names := nil;
end;

function TAtlasTestStamps.StaleRuns(AWithUnits: Boolean;
  const AReadLines: TAtlasTestReadLines): TArray<TAtlasStaleRun>;
var
  mCache: TDictionary<string, string>;
  mFiles, mStale: TArray<string>;
  mPair: TPair<string, TAtlasTestStamp>;
  mFileName: string;
  mLines: TArray<string>;
  mRun: Integer;
begin
  Result := nil;
  mFiles := nil;
  for mPair in FStamps do
  begin
    if not InList(mFiles, AnsiLowerCase(mPair.Value.FileName)) then
    begin
      mFiles := mFiles + [AnsiLowerCase(mPair.Value.FileName)];
    end;
  end;
  mStale := nil;
  mCache := TDictionary<string, string>.Create;
  try
    for mFileName in mFiles do
    begin
      if Assigned(AReadLines) and AReadLines(mFileName, mLines) then
      begin
        mStale := mStale + StaleKeys(TDUnitXSource.Scan(mLines), mLines, AWithUnits, AReadLines, mCache);
      end;
    end;
  finally
    mCache.Free;
  end;
  for mPair in FStamps do
  begin
    if InList(mStale, mPair.Key) and (Length(mPair.Value.Names) > 0) then
    begin
      mRun := RunFor(Result, mPair.Value);
      Result[mRun].Names := Result[mRun].Names + mPair.Value.Names;
    end;
  end;
end;

class function TAtlasTestStamps.Listed(const AValues: TArray<string>; const AValue: string): Boolean;
begin
  Result := InList(AValues, AValue);
end;

end.
