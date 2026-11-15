unit Atlas.Core.Debug.BreakpointSetFlow.Tests;

// Tests für die Haltepunkt-Sätze außerhalb von Speichern und Plan (#586, #863, #1967): Satz zum Namen, Branch
// beim Überschreiben, andere Sätze beim Wechseln, Stellen für das Haltepunktfenster; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointSetFlowTests = class
  private
    function TextOf(const AFileName: string; out AText: string): Boolean;
  public
    [Test]
    procedure IndexIgnoresCase;
    [Test]
    procedure BranchKeptWithoutNewCoupling;
    [Test]
    procedure OthersOnlyWhenExclusive;
    [Test]
    procedure PlacesJoinSetNames;
    [Test]
    procedure PlacesStaleAfterMaxAge;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Debug.BreakpointSets,
  Atlas.Core.Debug.BreakpointSetFlow;

const
  cFile = 'C:\P\Kunden.pas';
  cSource =
    'unit Kunden;' + #10 +
    'interface' + #10 +
    'implementation' + #10 +
    'procedure Lade;' + #10 +
    'begin' + #10 +
    '  Lies;' + #10 +
    'end;' + #10 +
    'end.' + #10;

function SetOf(const AName, ABranch: string; const AEntries: TAtlasBreakpointSetEntries): TAtlasBreakpointSet;
begin
  Result := Default(TAtlasBreakpointSet);
  Result.Name := AName;
  Result.Branch := ABranch;
  Result.Entries := AEntries;
end;

function Entry(ALine: Integer): TAtlasBreakpointSetEntry;
begin
  Result := TAtlasBreakpointSets.Capture(cFile, cSource, ALine, TAtlasBreakpointProps.Default);
end;

{ TAtlasBreakpointSetFlowTests }

function TAtlasBreakpointSetFlowTests.TextOf(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, cFile);
  AText := cSource;
end;

procedure TAtlasBreakpointSetFlowTests.IndexIgnoresCase;
var
  mSets: TAtlasBreakpointSetList;
begin
  mSets := [SetOf('Import', '', nil), SetOf('Export', '', nil)];
  Assert.AreEqual(1, TAtlasBreakpointSetFlow.IndexOfName(mSets, 'EXPORT'));
  Assert.AreEqual(-1, TAtlasBreakpointSetFlow.IndexOfName(mSets, 'Druck'));
end;

procedure TAtlasBreakpointSetFlowTests.BranchKeptWithoutNewCoupling;
var
  mSets: TAtlasBreakpointSetList;
begin
  mSets := [SetOf('Import', 'feature/x', nil)];
  Assert.AreEqual('feature/x', TAtlasBreakpointSetFlow.KeepBranch(mSets, 'import', '', ''));
  Assert.AreEqual('main', TAtlasBreakpointSetFlow.KeepBranch(mSets, 'Import', 'main', ''));
  // Arbeitskopie hat einen Branch, der Benutzer koppelt nicht: keine alte Kopplung übernehmen.
  Assert.AreEqual('', TAtlasBreakpointSetFlow.KeepBranch(mSets, 'Import', '', 'develop'));
  Assert.AreEqual('', TAtlasBreakpointSetFlow.KeepBranch(mSets, 'Neu', '', ''));
end;

procedure TAtlasBreakpointSetFlowTests.OthersOnlyWhenExclusive;
var
  mSets: TAtlasBreakpointSetList;
begin
  mSets := [SetOf('A', '', [Entry(5)]), SetOf('B', '', [Entry(4), Entry(5)]), SetOf('C', '', [Entry(6)])];
  Assert.AreEqual(3, Integer(Length(TAtlasBreakpointSetFlow.OthersOf(mSets, 0, True))));
  Assert.AreEqual(2, Integer(Length(TAtlasBreakpointSetFlow.OthersOf(mSets, 1, True))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreakpointSetFlow.OthersOf(mSets, 1, False))));
end;

procedure TAtlasBreakpointSetFlowTests.PlacesJoinSetNames;
var
  mPlaces: TStringList;
  mNames: TArray<string>;
begin
  mPlaces := TStringList.Create;
  try
    TAtlasBreakpointSetFlow.FillPlaces(mPlaces, [SetOf('A', '', [Entry(5)]), SetOf('B', '', [Entry(5),
      Entry(4)])], TextOf);
    mNames := TAtlasBreakpointSetFlow.NamesAt(mPlaces, 'c:\p\KUNDEN.pas', 5);
    Assert.AreEqual(2, Integer(Length(mNames)));
    Assert.AreEqual('A', mNames[0]);
    Assert.AreEqual('B', mNames[1]);
    mNames := TAtlasBreakpointSetFlow.NamesAt(mPlaces, cFile, 4);
    Assert.AreEqual(1, Integer(Length(mNames)));
    Assert.AreEqual(0, Integer(Length(TAtlasBreakpointSetFlow.NamesAt(mPlaces, cFile, 6))));
  finally
    mPlaces.Free;
  end;
end;

procedure TAtlasBreakpointSetFlowTests.PlacesStaleAfterMaxAge;
begin
  Assert.IsTrue(TAtlasBreakpointSetFlow.PlacesStale(False, 10, 10, 3000));
  Assert.IsFalse(TAtlasBreakpointSetFlow.PlacesStale(True, 2999, 0, 3000));
  Assert.IsTrue(TAtlasBreakpointSetFlow.PlacesStale(True, 3000, 0, 3000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointSetFlowTests);

end.
