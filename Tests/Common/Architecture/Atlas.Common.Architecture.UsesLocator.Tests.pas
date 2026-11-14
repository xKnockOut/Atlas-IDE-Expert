unit Atlas.Common.Architecture.UsesLocator.Tests;

// Tests der Fundstellen im Uses-Graphen (#268): Zeile und Spalte des
// uses-Eintrags, Abschnitt, aktive {$IFDEF}-Zweige, fehlende Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesLocatorTests = class
  public
    [Test]
    procedure LocatesEntryInItsSection;
    [Test]
    procedure PrefersActiveBranch;
    [Test]
    procedure MissingFileOrEntryFails;
    [Test]
    procedure ReadsEachFileOnce;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesGraph.Tests;

const
  cMainText = 'unit Main;'#10 +
    'interface'#10 +
    'uses Kern;'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Daten,'#10 +
    '  Kern.Hilfe;'#10 +
    'end.';
  cBranchText = 'unit Main;'#10 +
    'interface'#10 +
    'uses'#10 +
    '{$IFDEF ALT}'#10 +
    '  Kern,'#10 +
    '{$ELSE}'#10 +
    '  Daten, Kern,'#10 +
    '{$ENDIF}'#10 +
    '  Ende;'#10 +
    'implementation'#10 +
    'end.';

function Reader(const AFiles: TDictionary<string, string>; const ACounter: TList<string>): TUsesTextReader;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      ACounter.Add(AFileName);
      Result := AFiles.TryGetValue(AFileName, AText);
    end;
end;

function NoDefines: TUsesDefinesFunc;
begin
  Result :=
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end;
end;

function EdgeTo(AGraph: TUsesGraph; const ASource, ATarget: string): TUsesEdge;
var
  mEdge: TUsesEdge;
begin
  for mEdge in AGraph.Node(AGraph.IndexOf(ASource)).Outgoing do
  begin
    if SameText(AGraph.Node(mEdge.Target).UnitName, ATarget) then
    begin
      Exit(mEdge);
    end;
  end;
  raise Exception.Create('Kante fehlt: ' + ASource + ' → ' + ATarget);
end;

{ TUsesLocatorTests }

procedure TUsesLocatorTests.LocatesEntryInItsSection;
var
  mFiles: TDictionary<string, string>;
  mReads: TList<string>;
  mGraph: TUsesGraph;
  mLocator: TUsesLocator;
  mLocation: TUsesLocation;
  mMain: TUnitIndex;
begin
  mFiles := TDictionary<string, string>.Create;
  mReads := TList<string>.Create;
  mMain := UsesUnit('Main', ['Kern'], ['Daten', 'Kern.Hilfe']);
  mFiles.Add(mMain.FileName, cMainText);
  mGraph := TUsesGraph.Create([mMain, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Kern.Hilfe', nil, nil)], TUsesGraphOptions.Default);
  mLocator := TUsesLocator.Create(Reader(mFiles, mReads), NoDefines());
  try
    Assert.IsTrue(mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Kern'), mLocation));
    Assert.AreEqual(mMain.FileName, mLocation.FileName);
    Assert.AreEqual(2, mLocation.Range.StartPos.Line);
    Assert.AreEqual(5, mLocation.Range.StartPos.Character);
    Assert.IsTrue(mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Kern.Hilfe'), mLocation));
    Assert.AreEqual(6, mLocation.Range.StartPos.Line);
    Assert.AreEqual(2, mLocation.Range.StartPos.Character);
    Assert.AreEqual(12, mLocation.Range.EndPos.Character);
  finally
    mLocator.Free;
    mGraph.Free;
    mReads.Free;
    mFiles.Free;
  end;
end;

procedure TUsesLocatorTests.PrefersActiveBranch;
var
  mFiles: TDictionary<string, string>;
  mReads: TList<string>;
  mGraph: TUsesGraph;
  mLocator: TUsesLocator;
  mLocation: TUsesLocation;
  mMain: TUnitIndex;
begin
  // Ohne ALT gilt der $ELSE-Zweig: Kern steht in Zeile 6 hinter Daten.
  mFiles := TDictionary<string, string>.Create;
  mReads := TList<string>.Create;
  mMain := UsesUnit('Main', ['Daten', 'Kern', 'Ende'], nil);
  mFiles.Add(mMain.FileName, cBranchText);
  mGraph := TUsesGraph.Create([mMain, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Ende', nil, nil)], TUsesGraphOptions.Default);
  mLocator := TUsesLocator.Create(Reader(mFiles, mReads), NoDefines());
  try
    Assert.IsTrue(mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Kern'), mLocation));
    Assert.AreEqual(6, mLocation.Range.StartPos.Line);
    Assert.AreEqual(9, mLocation.Range.StartPos.Character);
  finally
    mLocator.Free;
    mGraph.Free;
    mReads.Free;
    mFiles.Free;
  end;
end;

procedure TUsesLocatorTests.MissingFileOrEntryFails;
var
  mFiles: TDictionary<string, string>;
  mReads: TList<string>;
  mGraph: TUsesGraph;
  mLocator: TUsesLocator;
  mLocation: TUsesLocation;
  mMain, mOther: TUnitIndex;
begin
  mFiles := TDictionary<string, string>.Create;
  mReads := TList<string>.Create;
  mMain := UsesUnit('Main', ['Kern'], nil);
  mOther := UsesUnit('Other', ['Kern'], nil);
  // Datei von Main ohne den Eintrag (veralteter Index), Datei von Other fehlt.
  mFiles.Add(mMain.FileName, 'unit Main; interface implementation end.');
  mGraph := TUsesGraph.Create([mMain, mOther, UsesUnit('Kern', nil, nil)], TUsesGraphOptions.Default);
  mLocator := TUsesLocator.Create(Reader(mFiles, mReads), NoDefines());
  try
    Assert.IsFalse(mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Kern'), mLocation));
    Assert.IsFalse(mLocator.Locate(mGraph, EdgeTo(mGraph, 'Other', 'Kern'), mLocation));
    Assert.AreEqual(mOther.FileName, mLocation.FileName, 'Datei bleibt für die Anzeige');
  finally
    mLocator.Free;
    mGraph.Free;
    mReads.Free;
    mFiles.Free;
  end;
end;

procedure TUsesLocatorTests.ReadsEachFileOnce;
var
  mFiles: TDictionary<string, string>;
  mReads: TList<string>;
  mGraph: TUsesGraph;
  mLocator: TUsesLocator;
  mLocation: TUsesLocation;
  mMain: TUnitIndex;
begin
  mFiles := TDictionary<string, string>.Create;
  mReads := TList<string>.Create;
  mMain := UsesUnit('Main', ['Kern'], ['Daten', 'Kern.Hilfe']);
  mFiles.Add(mMain.FileName, cMainText);
  mGraph := TUsesGraph.Create([mMain, UsesUnit('Kern', nil, nil), UsesUnit('Daten', nil, nil),
    UsesUnit('Kern.Hilfe', nil, nil)], TUsesGraphOptions.Default);
  mLocator := TUsesLocator.Create(Reader(mFiles, mReads), NoDefines());
  try
    mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Kern'), mLocation);
    mLocator.Locate(mGraph, EdgeTo(mGraph, 'Main', 'Daten'), mLocation);
    Assert.AreEqual(1, Integer(mReads.Count));
  finally
    mLocator.Free;
    mGraph.Free;
    mReads.Free;
    mFiles.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesLocatorTests);

end.
