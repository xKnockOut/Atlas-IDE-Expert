unit Atlas.Core.Results.Plan.Tests;

// Befehle des Ergebnisfensters (#400, #1967): Bezeichner am Cursor, Wirkung
// gefundener Implementierungen, Zeilen der Symbolsuche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasResultsPlanTests = class
  public
    [Test]
    procedure SpotFindsWordAtCursor;
    [Test]
    procedure SpotExpandsTabs;
    [Test]
    procedure SpotFailsOutsideText;
    [Test]
    procedure FoundByCount;
    [Test]
    procedure SymbolCommandsWithContainer;
  end;

implementation

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Results.Plan;

{ TAtlasResultsPlanTests }

procedure TAtlasResultsPlanTests.SpotFindsWordAtCursor;
var
  mSpot: TAtlasResultsSpot;
begin
  Assert.IsTrue(TAtlasResultsPlan.Spot('unit A;'#13#10'  Foo.Bar(1);', 2, 9, 8, mSpot));
  Assert.AreEqual(1, mSpot.Line);
  Assert.AreEqual(8, mSpot.Character);
  Assert.AreEqual('Bar', mSpot.Name);
  Assert.IsTrue(TAtlasResultsPlan.Spot('x := Wert;'#10'y', 1, 1, 8, mSpot));
  Assert.AreEqual(0, mSpot.Line);
  Assert.AreEqual('x', mSpot.Name);
end;

procedure TAtlasResultsPlanTests.SpotExpandsTabs;
var
  mSpot: TAtlasResultsSpot;
begin
  // Spalte 9 liegt hinter dem Tab (Breite 8) auf dem ersten Zeichen von Name.
  Assert.IsTrue(TAtlasResultsPlan.Spot(#9'Name := 1;', 1, 9, 8, mSpot));
  Assert.AreEqual(1, mSpot.Character);
  Assert.AreEqual('Name', mSpot.Name);
end;

procedure TAtlasResultsPlanTests.SpotFailsOutsideText;
var
  mSpot: TAtlasResultsSpot;
begin
  Assert.IsFalse(TAtlasResultsPlan.Spot('a'#13#10'b', 3, 1, 8, mSpot));
  Assert.IsFalse(TAtlasResultsPlan.Spot('a', 0, 1, 8, mSpot));
  Assert.AreEqual('', mSpot.Name);
end;

procedure TAtlasResultsPlanTests.FoundByCount;
begin
  Assert.AreEqual<TAtlasResultsFound>(TAtlasResultsFound.Nothing, TAtlasResultsPlan.Found(0));
  Assert.AreEqual<TAtlasResultsFound>(TAtlasResultsFound.Jump, TAtlasResultsPlan.Found(1));
  Assert.AreEqual<TAtlasResultsFound>(TAtlasResultsFound.List, TAtlasResultsPlan.Found(2));
end;

procedure TAtlasResultsPlanTests.SymbolCommandsWithContainer;
var
  mSymbols: TArray<TAtlasSymbol>;
  mCommands: TArray<TAtlasCommand>;
begin
  SetLength(mSymbols, 2);
  mSymbols[0] := Default(TAtlasSymbol);
  mSymbols[0].Name := 'Add';
  mSymbols[0].Container := 'TBar';
  mSymbols[0].FileName := 'Bar.pas';
  mSymbols[0].Kind := 6;
  mSymbols[1] := Default(TAtlasSymbol);
  mSymbols[1].Name := 'TBar';
  mSymbols[1].FileName := 'Bar.pas';
  mSymbols[1].Kind := 5;
  mCommands := TAtlasResultsPlan.SymbolCommands(mSymbols);
  Assert.AreEqual(2, Integer(Length(mCommands)));
  Assert.AreEqual('0', mCommands[0].Id);
  Assert.AreEqual('Add', mCommands[0].Caption);
  Assert.AreEqual('TBar' + TAtlasResultsPlan.cContainerSeparator + 'Bar.pas', mCommands[0].Path);
  Assert.AreEqual('fn', mCommands[0].ShortCut);
  Assert.AreEqual('1', mCommands[1].Id);
  Assert.AreEqual('Bar.pas', mCommands[1].Path);
  Assert.AreEqual('ty', mCommands[1].ShortCut);
  mSymbols := nil;
  mCommands := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResultsPlanTests);

end.
