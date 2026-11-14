unit Atlas.Common.Architecture.Snapshot.Tests;

// Tests des gespeicherten Architekturstands (#1121): stabile, sortierte Datei
// ohne Zeit und Index-Stand, Lesen von Format 2 und 1, klare Meldungen bei
// fremden Formaten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.Overview;

type
  [TestFixture]
  TArchitectureSnapshotTests = class
  public
    [Test]
    procedure WritesSortedNamesWithFormat;
    [Test]
    procedure SameStateSameBytes;
    [Test]
    procedure ReadsWhatItWrites;
    [Test]
    procedure ReadsFormatOne;
    [Test]
    procedure RejectsOtherFormats;
    [Test]
    procedure SavesAndLoadsFile;
    [Test]
    procedure CycleKeyIgnoresStart;
    /// <summary>Feinheit γ (#1366) im Stand; Stände ohne "grouping" gelten als 1,0.</summary>
    [Test]
    procedure KeepsGroupingAndReadsOlderStates;
    [Test]
    procedure KeepsParentOfSplitSubsystem;
  end;

/// <summary>Units der Berichtstests: drei Namensräume, ein Zyklus über implementation in Data.</summary>
function ArchitectureSampleUnits: TArray<TUnitIndex>;
/// <summary>Übersicht zu AUnits ohne Fundstellen, Titel "Beispiel", Root C:\Projekt.</summary>
function ArchitectureOverviewOf(const AUnits: TArray<TUnitIndex>): TArchitectureOverview;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.Layout,
  Atlas.Common.Architecture.Report,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.UsesGraph.Tests;

function ArchitectureSampleUnits: TArray<TUnitIndex>;
begin
  Result := nil;
  Result := Result + [UsesUnit('App.Core.Base', nil, nil), UsesUnit('App.Core.Types', ['App.Core.Base'], nil),
    UsesUnit('App.Core.Log', ['App.Core.Base', 'App.Core.Types'], nil),
    UsesUnit('App.Core.Util', ['App.Core.Base', 'App.Core.Types'], nil)];
  Result := Result + [UsesUnit('App.Data.Db', nil, ['App.Core.Base', 'App.Data.Cache']), UsesUnit('App.Data.Model',
    ['App.Data.Db'], nil), UsesUnit('App.Data.Query', ['App.Data.Db', 'App.Data.Model'], nil),
    UsesUnit('App.Data.Cache', ['App.Data.Query', 'App.Data.Model'], nil)];
  Result := Result + [UsesUnit('App.Ui.Theme', nil, nil), UsesUnit('App.Ui.Grid', ['App.Ui.Theme'], nil),
    UsesUnit('App.Ui.Form', ['App.Ui.Theme', 'App.Ui.Grid'], nil),
    UsesUnit('App.Ui.Main', ['App.Ui.Form', 'App.Ui.Grid'], ['App.Data.Model'])];
end;

function ArchitectureOverviewOf(const AUnits: TArray<TUnitIndex>): TArchitectureOverview;
var
  mGraph: TUsesGraph;
begin
  mGraph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(mGraph, nil, 5);
  finally
    mGraph.Free;
  end;
  Result.Title := 'Beispiel';
  Result.Root := 'C:\Projekt';
  Result.Scope := 'projectGroup';
end;

{ TArchitectureSnapshotTests }

procedure TArchitectureSnapshotTests.WritesSortedNamesWithFormat;
var
  mText: string;
  mRoot: TJSONValue;
  mData: TJSONObject;
  mUnits: TJSONArray;
  mIndex: Integer;
begin
  mText := TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(
    ArchitectureOverviewOf(ArchitectureSampleUnits)));
  mRoot := TJSONObject.ParseJSONValue(mText);
  try
    Assert.IsTrue(mRoot is TJSONObject, 'gültiges JSON');
    mData := TJSONObject(mRoot);
    Assert.AreEqual(2, mData.GetValue<Integer>('format'));
    Assert.AreEqual('atlas.architecture', mData.GetValue<string>('kind'));
    mUnits := mData.GetValue<TJSONArray>('units');
    Assert.AreEqual(12, mUnits.Count);
    for mIndex := 1 to mUnits.Count - 1 do
    begin
      Assert.IsTrue(CompareText((mUnits.Items[mIndex - 1] as TJSONObject).GetValue<string>('name'),
        (mUnits.Items[mIndex] as TJSONObject).GetValue<string>('name')) < 0, 'Units nach Namen');
    end;
    Assert.AreEqual('App/Core/Base.pas', (mUnits.Items[0] as TJSONObject).GetValue<string>('file'));
    Assert.AreEqual('Core', (mUnits.Items[0] as TJSONObject).GetValue<string>('subsystem'));
  finally
    mRoot.Free;
  end;
  // Kanten mit Namen und Abschnitt, je Zeile eine; keine Zeit, kein Index-Stand.
  Assert.Contains(mText, '["App.Data.Db", "App.Data.Cache", "implementation"]');
  Assert.Contains(mText, '["App.Core.Types", "App.Core.Base", "interface"]');
  Assert.DoesNotContain(mText, 'created');
  Assert.DoesNotContain(mText, 'generation');
  Assert.DoesNotContain(mText, 'durationMs');
  Assert.DoesNotContain(mText, #13);
end;

procedure TArchitectureSnapshotTests.SameStateSameBytes;
var
  mFirst, mSecond: TArchitectureOverview;
  mUnits: TArray<TUnitIndex>;
  mIndex: Integer;
begin
  mFirst := ArchitectureOverviewOf(ArchitectureSampleUnits);
  // Gleicher Stand in anderer Reihenfolge, zu anderer Zeit, mit anderem Index-Stand.
  mUnits := ArchitectureSampleUnits;
  for mIndex := 0 to High(mUnits) div 2 do
  begin
    mUnits := mUnits + [mUnits[0]];
    Delete(mUnits, 0, 1);
  end;
  mSecond := ArchitectureOverviewOf(mUnits);
  mSecond.Created := mFirst.Created + 1;
  mSecond.Generation := mFirst.Generation + 99;
  mSecond.DurationMs := mFirst.DurationMs + 500;
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mFirst)),
    TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mSecond)));
end;

procedure TArchitectureSnapshotTests.ReadsWhatItWrites;
var
  mSnapshot, mRead: TArchitectureSnapshot;
  mError: string;
begin
  mSnapshot := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(ArchitectureSampleUnits));
  Assert.IsTrue(TArchitectureSnapshots.Parse(TArchitectureSnapshots.Json(mSnapshot), mRead, mError), mError);
  Assert.AreEqual(2, mRead.FormatVersion);
  Assert.AreEqual('Beispiel', mRead.Title);
  Assert.AreEqual(Integer(Length(mSnapshot.Units)), Integer(Length(mRead.Units)));
  Assert.AreEqual(Integer(Length(mSnapshot.Edges)), Integer(Length(mRead.Edges)));
  Assert.AreEqual(1, Integer(Length(mRead.Cycles)));
  Assert.AreEqual(TArchitectureSnapshots.Json(mSnapshot), TArchitectureSnapshots.Json(mRead));
end;

procedure TArchitectureSnapshotTests.ReadsFormatOne;
var
  mSource: TArchitectureOverview;
  mRead: TArchitectureSnapshot;
  mError: string;
begin
  // Format 1 sind die Daten des Berichts (Nummern statt Namen), auch als Antwort von atlas/architecture.
  mSource := ArchitectureOverviewOf(ArchitectureSampleUnits);
  Assert.IsTrue(TArchitectureSnapshots.Parse(TArchitectureReport.Json(mSource, TArchitectureLayouter.Compute(mSource)),
    mRead, mError), mError);
  Assert.AreEqual(1, mRead.FormatVersion);
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mSource)),
    TArchitectureSnapshots.Json(mRead));
  Assert.IsTrue(TArchitectureSnapshots.Parse('{"enabled": true, "format": "json", "data": ' +
    TArchitectureReport.Json(mSource, TArchitectureLayouter.Compute(mSource)) + '}', mRead, mError), mError);
  Assert.AreEqual(12, Integer(Length(mRead.Units)));
end;

procedure TArchitectureSnapshotTests.RejectsOtherFormats;
var
  mRead: TArchitectureSnapshot;
  mError: string;
begin
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 3, "units": []}', mRead, mError));
  Assert.Contains(mError, 'Format 3');
  Assert.Contains(mError, 'neu speichern');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"units": []}', mRead, mError));
  Assert.Contains(mError, 'ohne Formatversion');
  Assert.IsFalse(TArchitectureSnapshots.Parse('kein JSON', mRead, mError));
  Assert.Contains(mError, 'kein JSON-Objekt');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 2, "kind": "atlas.baseline", "units": []}', mRead, mError));
  Assert.Contains(mError, 'kein Architekturstand');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 1, "units": [{"name": "A"}], "edges": [[0, 4, "i"]]}',
    mRead, mError));
  Assert.Contains(mError, 'beschädigt');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 2}', mRead, mError));
  Assert.Contains(mError, '"units" fehlt');
end;

procedure TArchitectureSnapshotTests.SavesAndLoadsFile;
var
  mFolder, mFileName, mError: string;
  mSnapshot, mRead: TArchitectureSnapshot;
  mBytes: TBytes;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasSnapshot' + IntToStr(Random(1000000)));
  mFileName := TPath.Combine(TPath.Combine(mFolder, 'Stand'), 'architektur.json');
  try
    mSnapshot := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(ArchitectureSampleUnits));
    TArchitectureSnapshots.Save(mFileName, mSnapshot);
    mBytes := TFile.ReadAllBytes(mFileName);
    Assert.AreEqual(Integer(Ord('{')), Integer(mBytes[0]), 'ohne BOM');
    Assert.IsTrue(TArchitectureSnapshots.Load(mFileName, mRead, mError), mError);
    Assert.AreEqual(TArchitectureSnapshots.Json(mSnapshot), TArchitectureSnapshots.Json(mRead));
    Assert.IsFalse(TArchitectureSnapshots.Load(TPath.Combine(mFolder, 'fehlt.json'), mRead, mError));
    Assert.Contains(mError, 'nicht gefunden');
  finally
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TArchitectureSnapshotTests.CycleKeyIgnoresStart;
var
  mFirst, mSecond: TSnapshotCycle;
begin
  mFirst := Default(TSnapshotCycle);
  mFirst.Units := TArray<string>.Create('B', 'c', 'A');
  mSecond := Default(TSnapshotCycle);
  mSecond.Units := TArray<string>.Create('a', 'B', 'C');
  Assert.AreEqual(mFirst.Key, mSecond.Key);
end;

procedure TArchitectureSnapshotTests.KeepsGroupingAndReadsOlderStates;
var
  mOverview: TArchitectureOverview;
  mSnapshot, mRead: TArchitectureSnapshot;
  mText, mError: string;
begin
  mOverview := ArchitectureOverviewOf(ArchitectureSampleUnits);
  mOverview.Grouping.Resolution := 0.5;
  mSnapshot := TArchitectureSnapshots.FromOverview(mOverview);
  mText := TArchitectureSnapshots.Json(mSnapshot);
  Assert.Contains(mText, '"grouping": {"resolution": 0.5},');
  Assert.IsTrue(TArchitectureSnapshots.Parse(mText, mRead, mError), mError);
  Assert.AreEqual(Double(0.5), mRead.Grouping.Resolution, 1E-9);
  // Älterer Stand ohne "grouping".
  mText := StringReplace(mText, '"grouping": {"resolution": 0.5},', '', []);
  Assert.IsTrue(TArchitectureSnapshots.Parse(mText, mRead, mError), mError);
  Assert.AreEqual(Double(1), mRead.Grouping.Resolution, 1E-9);
end;

procedure TArchitectureSnapshotTests.KeepsParentOfSplitSubsystem;
var
  mOverview: TArchitectureOverview;
  mRead: TArchitectureSnapshot;
  mText, mError, mName: string;
  mSubsystem: TSnapshotSubsystem;
  mFound: Boolean;
begin
  mOverview := ArchitectureOverviewOf(ArchitectureSampleUnits);
  mText := TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mOverview));
  Assert.IsFalse(Pos('"parent"', mText) > 0, 'ohne Nachteilung wie vor #1364');
  Assert.IsFalse(Pos('"foundation": true', mText) > 0, 'ohne Fundament wie vor #1365');
  mName := mOverview.Subsystems[1].Name;
  mOverview.Subsystems[1].Parent := 'App';
  mOverview.Subsystems[1].Foundation := True;
  mText := TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mOverview));
  // Farbe dahinter (#1367).
  Assert.Contains(mText, '"isolated": false, "foundation": true, "parent": "App", "color": ' +
    IntToStr(mOverview.Subsystems[1].ColorSlot) + ', "shade": 0}');
  Assert.IsTrue(TArchitectureSnapshots.Parse(mText, mRead, mError), mError);
  mFound := False;
  for mSubsystem in mRead.Subsystems do
  begin
    if mSubsystem.Name = mName then
    begin
      Assert.AreEqual('App', mSubsystem.Parent);
      Assert.IsTrue(mSubsystem.Foundation);
      mFound := True;
    end
    else
    begin
      Assert.AreEqual('', mSubsystem.Parent);
      Assert.IsFalse(mSubsystem.Foundation);
    end;
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureSnapshotTests);

end.
