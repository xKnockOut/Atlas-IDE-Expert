unit Atlas.Core.Tests.UnitScans.Tests;

// Tests der gelesenen Units des Fensters „Atlas-Tests“ mit gestellter Änderungszeit: unverändert heißt nicht neu
// gelesen, geändert oder gespeichert heißt neu gelesen, keine Testunit heißt kein Text behalten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tests.UnitScans;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestUnitScansTests = class
  private
    FScans: TAtlasTestUnitScans;
    FAge: TDateTime;
    FReads: Integer;
    FText: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UnchangedIsNotReadAgain;
    [Test]
    procedure ChangedAgeIsReadAgain;
    [Test]
    procedure ForgottenIsReadAgain;
    [Test]
    procedure OtherUnitKeepsNoText;
    [Test]
    procedure WithoutAgeFunctionUsesDisk;
  end;

implementation

const
  cTestUnit: array[0..9] of string = ('unit T;', 'interface', 'uses', '  DUnitX.TestFramework;', 'type',
    '  [TestFixture]', '  TFoo = class', '  public', '    [Test] procedure A;', '  end;');

procedure TAtlasTestUnitScansTests.Setup;
var
  mIndex: Integer;
begin
  FAge := 1;
  FReads := 0;
  SetLength(FText, Length(cTestUnit));
  for mIndex := 0 to High(cTestUnit) do
  begin
    FText[mIndex] := cTestUnit[mIndex];
  end;
  FScans := TAtlasTestUnitScans.Create(
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      Inc(FReads);
      ALines := Copy(FText);
      Result := True;
    end,
    function(const AFileName: string): TDateTime
    begin
      Result := FAge;
    end);
end;

procedure TAtlasTestUnitScansTests.TearDown;
begin
  FScans.Free;
  FScans := nil;
  FText := nil;
end;

procedure TAtlasTestUnitScansTests.UnchangedIsNotReadAgain;
var
  mScan: TAtlasTestUnitScan;
begin
  mScan := FScans.Scan('C:\P\T.pas');
  Assert.IsTrue(mScan.IsTest);
  Assert.AreEqual(Integer(Length(cTestUnit)), Integer(Length(mScan.Lines)));
  mScan := FScans.Scan('c:\p\t.pas');
  Assert.AreEqual(1, FReads, 'gleiche Änderungszeit, Schreibweise egal');
  Assert.IsTrue(mScan.IsTest);
end;

procedure TAtlasTestUnitScansTests.ChangedAgeIsReadAgain;
begin
  FScans.Scan('C:\P\T.pas');
  FAge := 2;
  FScans.Scan('C:\P\T.pas');
  Assert.AreEqual(2, FReads);
end;

procedure TAtlasTestUnitScansTests.ForgottenIsReadAgain;
begin
  Assert.IsFalse(FScans.Forget('C:\P\T.pas'), 'noch nicht gelesen');
  FScans.Scan('C:\P\T.pas');
  Assert.IsTrue(FScans.Forget('C:\P\T.pas'));
  FScans.Scan('C:\P\T.pas');
  Assert.AreEqual(2, FReads, 'gespeichert');
  FScans.Clear;
  FScans.Scan('C:\P\T.pas');
  Assert.AreEqual(3, FReads, 'neu einlesen');
end;

procedure TAtlasTestUnitScansTests.OtherUnitKeepsNoText;
var
  mScan: TAtlasTestUnitScan;
begin
  FText := TArray<string>.Create('unit U;', 'interface', 'implementation', 'end.');
  mScan := FScans.Scan('C:\P\U.pas');
  Assert.IsFalse(mScan.IsTest);
  Assert.AreEqual(0, Integer(Length(mScan.Lines)));
  Assert.AreEqual(1.0, Double(mScan.Age), 0);
end;

procedure TAtlasTestUnitScansTests.WithoutAgeFunctionUsesDisk;
var
  mScans: TAtlasTestUnitScans;
begin
  mScans := TAtlasTestUnitScans.Create(
    function(const AFileName: string; out ALines: TArray<string>): Boolean
    begin
      ALines := nil;
      Result := True;
    end, nil);
  try
    // Datei gibt es nicht: Änderungszeit 0.
    Assert.AreEqual(0.0, Double(mScans.Scan('Z:\Fehlt\Gibt.Es.Nicht.pas').Age), 0);
  finally
    mScans.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTestUnitScansTests);

end.
