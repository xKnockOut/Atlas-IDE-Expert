unit Atlas.Core.Tests.Stale.Tests;

// Tests der veralteten Testergebnisse (#1770) ohne IDE: Stand eines Laufs
// merken, Änderung im Rumpf, nur Leerraum oder Kommentar, verwendete Units
// (tests.stale.units) und die Namen für „Veraltete Tests ausführen“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestStampsTests = class
  private
    FTest: TArray<string>;
    FHelper: TArray<string>;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChangedBodyIsStale;
    [Test]
    procedure WhitespaceAndCommentsAreNotStale;
    [Test]
    procedure OnlyTestsThatRanAreStamped;
    [Test]
    procedure ChangedUsedUnitIsStaleWithOption;
    [Test]
    procedure StaleRunsPerProject;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tests.Stale,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults;

const
  cTestFile = 'C:\Projekt\Tests\Rechner.Tests.pas';
  cHelperFile = 'C:\Projekt\Src\Rechner.pas';
  cProject = 'C:\Projekt\Tests\RechnerTests.dproj';

function Source: TArray<string>;
begin
  Result := TArray<string>.Create(
    'unit Rechner.Tests;',                         // 0
    'interface',                                   // 1
    'uses DUnitX.TestFramework, Rechner;',         // 2
    'type',                                        // 3
    '  [TestFixture]',                             // 4
    '  TRechnerTests = class',                     // 5
    '  public',                                    // 6
    '    [Test]',                                  // 7
    '    procedure Addiert;',                      // 8
    '    [TestCase(''Gross'', ''10,20,30'')]',     // 9
    '    procedure Summe(A, B, C: Integer);',      // 10
    '  end;',                                      // 11
    'implementation',                              // 12
    'procedure TRechnerTests.Addiert;',            // 13
    'begin',                                       // 14
    '  Assert.AreEqual(4, Add(2, 2));',            // 15
    'end;',                                        // 16
    'procedure TRechnerTests.Summe(A, B, C: Integer);', // 17
    'begin',                                       // 18
    '  Assert.AreEqual(C, Add(A, B));',            // 19
    'end;',                                        // 20
    'end.');
end;

function Cases(const ANames: array of string): TArray<TTestCaseResult>;
var
  mXml, mName: string;
begin
  mXml := '<test-results><test-suite type="Assembly" name="R.exe"><results>' +
    '<test-suite type="TestFixture" name="TRechnerTests"><results>';
  for mName in ANames do
  begin
    mXml := mXml + '<test-case name="Rechner.Tests.TRechnerTests.' + mName +
      '" executed="True" result="Success" time="0.01"/>';
  end;
  mXml := mXml + '</results></test-suite></results></test-suite></test-results>';
  Result := TTestResults.Parse(mXml).Cases;
end;

{ TAtlasTestStampsTests }

procedure TAtlasTestStampsTests.TearDown;
begin
  FTest := nil;
  FHelper := nil;
end;

function UnitFile(const AUnitName: string): string;
begin
  Result := '';
  if SameText(AUnitName, 'Rechner') then
  begin
    Result := cHelperFile;
  end
  else if SameText(AUnitName, 'Rechner.Tests') then
  begin
    Result := cTestFile;
  end;
end;

/// <summary>Neue Stände nach einem Lauf der Tests ARan über den Text ALines.</summary>
function Stamped(const ALines: TArray<string>; const ARan: array of string; const AReadLines: TAtlasTestReadLines;
  AWithUnits: Boolean): TAtlasTestStamps;
var
  mUnits: TArray<TAtlasUnitStamp>;
begin
  Result := TAtlasTestStamps.Create;
  mUnits := nil;
  if AWithUnits then
  begin
    mUnits := TAtlasTestStamps.UnitStamps(ALines, UnitFile, AReadLines);
  end;
  Result.Remember(cProject, cTestFile, TDUnitXSource.Scan(ALines), ALines, Cases(ARan), mUnits);
end;

/// <summary>Liest die Testunit und die getestete Unit aus den Feldern des Tests.</summary>
function Reader(ATests: TAtlasTestStampsTests): TAtlasTestReadLines;
var
  mTests: TAtlasTestStampsTests;
begin
  mTests := ATests;
  Result :=
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      ALines := nil;
      if SameText(AFileName, cTestFile) then
      begin
        ALines := mTests.FTest;
      end
      else if SameText(AFileName, cHelperFile) then
      begin
        ALines := mTests.FHelper;
      end;
      Result := Length(ALines) > 0;
    end;
end;

function Key(const AMethod: string): string;
begin
  Result := TAtlasTestStamps.KeyOf('Rechner.Tests', 'TRechnerTests', AMethod);
end;

procedure TAtlasTestStampsTests.ChangedBodyIsStale;
var
  mStamps: TAtlasTestStamps;
  mStale: TArray<string>;
begin
  FTest := Source;
  mStamps := Stamped(FTest, ['Addiert', 'Summe.Gross'], Reader(Self), False);
  try
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil))),
      'unverändert');
    FTest[15] := '  Assert.AreEqual(5, Add(2, 3));';
    mStale := mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil);
    Assert.AreEqual(1, Integer(Length(mStale)));
    Assert.AreEqual(Key('Addiert'), mStale[0]);
    // Rückgängig: wieder aktuell.
    FTest[15] := '  Assert.AreEqual(4, Add(2, 2));';
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil))));
  finally
    mStamps.Free;
  end;
end;

procedure TAtlasTestStampsTests.WhitespaceAndCommentsAreNotStale;
var
  mStamps: TAtlasTestStamps;
begin
  FTest := Source;
  mStamps := Stamped(FTest, ['Addiert'], Reader(Self), False);
  try
    FTest[15] := '    Assert.AreEqual( 4,Add(2, 2) ); // Summe';
    FTest[14] := 'begin { geprüft }';
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil))));
    // Eingefügte Zeilen über dem Test verschieben ihn nur.
    FTest := TArray<string>.Create('// Kopf') + FTest;
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil))));
  finally
    mStamps.Free;
  end;
end;

procedure TAtlasTestStampsTests.OnlyTestsThatRanAreStamped;
var
  mStamps: TAtlasTestStamps;
  mStamp: TAtlasTestStamp;
begin
  FTest := Source;
  mStamps := Stamped(FTest, ['Addiert'], Reader(Self), False);
  try
    Assert.IsTrue(mStamps.TryGet(Key('Addiert'), mStamp));
    Assert.AreEqual(cProject, mStamp.Project);
    Assert.AreEqual(cTestFile, mStamp.FileName);
    Assert.IsFalse(mStamps.TryGet(Key('Summe'), mStamp), 'nicht gelaufen: kein Stand');
    // Ohne Stand ist nichts veraltet.
    FTest[19] := '  Assert.AreEqual(C, Add(B, A));';
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, nil))));
  finally
    mStamps.Free;
  end;
end;

procedure TAtlasTestStampsTests.ChangedUsedUnitIsStaleWithOption;
var
  mStamps: TAtlasTestStamps;
begin
  FTest := Source;
  FHelper := TArray<string>.Create('unit Rechner;', 'interface', 'function Add(A, B: Integer): Integer;',
    'implementation', 'function Add(A, B: Integer): Integer;', 'begin', '  Result := A + B;', 'end;', 'end.');
  mStamps := Stamped(FTest, ['Addiert', 'Summe.Gross'], Reader(Self), True);
  try
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, True, Reader(Self)))));
    FHelper[6] := '  Result := A - B;';
    Assert.AreEqual(2, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, True, Reader(Self)))),
      'geänderte getestete Unit macht beide Tests veraltet');
    Assert.AreEqual(0, Integer(Length(mStamps.StaleIn(TDUnitXSource.Scan(FTest), FTest, False, Reader(Self)))),
      'ohne tests.stale.units zählt nur der Rumpf');
  finally
    mStamps.Free;
  end;
end;

procedure TAtlasTestStampsTests.StaleRunsPerProject;
var
  mStamps: TAtlasTestStamps;
  mRuns: TArray<TAtlasStaleRun>;
begin
  FTest := Source;
  mStamps := Stamped(FTest, ['Addiert', 'Summe.Gross'], Reader(Self), False);
  try
    Assert.AreEqual(0, Integer(Length(mStamps.StaleRuns(False, Reader(Self)))), 'nichts geändert');
    FTest[19] := '  Assert.AreEqual(C, Add(B, A));';
    mRuns := mStamps.StaleRuns(False, Reader(Self));
    Assert.AreEqual(1, Integer(Length(mRuns)));
    Assert.AreEqual(cProject, mRuns[0].Project);
    Assert.AreEqual(cTestFile, mRuns[0].FileName);
    Assert.AreEqual(1, Integer(Length(mRuns[0].Names)));
    Assert.AreEqual('Rechner.Tests.TRechnerTests.Summe.Gross', mRuns[0].Names[0], 'je Fall der volle Name');
  finally
    mStamps.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestStampsTests);

end.
