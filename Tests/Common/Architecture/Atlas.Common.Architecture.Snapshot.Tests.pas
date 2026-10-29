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
  Graph: TUsesGraph;
begin
  Graph := TUsesGraph.Create(AUnits, TUsesGraphOptions.Default);
  try
    Result := TArchitectureAnalyzer.Analyze(Graph, nil, 5);
  finally
    Graph.Free;
  end;
  Result.Title := 'Beispiel';
  Result.Root := 'C:\Projekt';
  Result.Scope := 'projectGroup';
end;

{ TArchitectureSnapshotTests }

procedure TArchitectureSnapshotTests.WritesSortedNamesWithFormat;
var
  Text: string;
  Root: TJSONValue;
  Data: TJSONObject;
  Units: TJSONArray;
  Index: Integer;
begin
  Text := TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(
    ArchitectureOverviewOf(ArchitectureSampleUnits)));
  Root := TJSONObject.ParseJSONValue(Text);
  try
    Assert.IsTrue(Root is TJSONObject, 'gültiges JSON');
    Data := TJSONObject(Root);
    Assert.AreEqual(2, Data.GetValue<Integer>('format'));
    Assert.AreEqual('atlas.architecture', Data.GetValue<string>('kind'));
    Units := Data.GetValue<TJSONArray>('units');
    Assert.AreEqual(12, Units.Count);
    for Index := 1 to Units.Count - 1 do
      Assert.IsTrue(CompareText((Units.Items[Index - 1] as TJSONObject).GetValue<string>('name'),
        (Units.Items[Index] as TJSONObject).GetValue<string>('name')) < 0, 'Units nach Namen');
    Assert.AreEqual('App/Core/Base.pas', (Units.Items[0] as TJSONObject).GetValue<string>('file'));
    Assert.AreEqual('Core', (Units.Items[0] as TJSONObject).GetValue<string>('subsystem'));
  finally
    Root.Free;
  end;
  // Kanten mit Namen und Abschnitt, je Zeile eine; keine Zeit, kein Index-Stand.
  Assert.Contains(Text, '["App.Data.Db", "App.Data.Cache", "implementation"]');
  Assert.Contains(Text, '["App.Core.Types", "App.Core.Base", "interface"]');
  Assert.DoesNotContain(Text, 'created');
  Assert.DoesNotContain(Text, 'generation');
  Assert.DoesNotContain(Text, 'durationMs');
  Assert.DoesNotContain(Text, #13);
end;

procedure TArchitectureSnapshotTests.SameStateSameBytes;
var
  First, Second: TArchitectureOverview;
  Units: TArray<TUnitIndex>;
  Index: Integer;
begin
  First := ArchitectureOverviewOf(ArchitectureSampleUnits);
  // Gleicher Stand in anderer Reihenfolge, zu anderer Zeit, mit anderem Index-Stand.
  Units := ArchitectureSampleUnits;
  for Index := 0 to High(Units) div 2 do
  begin
    Units := Units + [Units[0]];
    Delete(Units, 0, 1);
  end;
  Second := ArchitectureOverviewOf(Units);
  Second.Created := First.Created + 1;
  Second.Generation := First.Generation + 99;
  Second.DurationMs := First.DurationMs + 500;
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(First)),
    TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(Second)));
end;

procedure TArchitectureSnapshotTests.ReadsWhatItWrites;
var
  Snapshot, Read: TArchitectureSnapshot;
  Error: string;
begin
  Snapshot := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(ArchitectureSampleUnits));
  Assert.IsTrue(TArchitectureSnapshots.Parse(TArchitectureSnapshots.Json(Snapshot), Read, Error), Error);
  Assert.AreEqual(2, Read.FormatVersion);
  Assert.AreEqual('Beispiel', Read.Title);
  Assert.AreEqual(Integer(Length(Snapshot.Units)), Integer(Length(Read.Units)));
  Assert.AreEqual(Integer(Length(Snapshot.Edges)), Integer(Length(Read.Edges)));
  Assert.AreEqual(1, Integer(Length(Read.Cycles)));
  Assert.AreEqual(TArchitectureSnapshots.Json(Snapshot), TArchitectureSnapshots.Json(Read));
end;

procedure TArchitectureSnapshotTests.ReadsFormatOne;
var
  Source: TArchitectureOverview;
  Read: TArchitectureSnapshot;
  Error: string;
begin
  // Format 1 sind die Daten des Berichts (Nummern statt Namen), auch als Antwort von atlas/architecture.
  Source := ArchitectureOverviewOf(ArchitectureSampleUnits);
  Assert.IsTrue(TArchitectureSnapshots.Parse(TArchitectureReport.Json(Source, TArchitectureLayouter.Compute(Source)),
    Read, Error), Error);
  Assert.AreEqual(1, Read.FormatVersion);
  Assert.AreEqual(TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(Source)),
    TArchitectureSnapshots.Json(Read));
  Assert.IsTrue(TArchitectureSnapshots.Parse('{"enabled": true, "format": "json", "data": ' +
    TArchitectureReport.Json(Source, TArchitectureLayouter.Compute(Source)) + '}', Read, Error), Error);
  Assert.AreEqual(12, Integer(Length(Read.Units)));
end;

procedure TArchitectureSnapshotTests.RejectsOtherFormats;
var
  Read: TArchitectureSnapshot;
  Error: string;
begin
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 3, "units": []}', Read, Error));
  Assert.Contains(Error, 'Format 3');
  Assert.Contains(Error, 'neu speichern');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"units": []}', Read, Error));
  Assert.Contains(Error, 'ohne Formatversion');
  Assert.IsFalse(TArchitectureSnapshots.Parse('kein JSON', Read, Error));
  Assert.Contains(Error, 'kein JSON-Objekt');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 2, "kind": "atlas.baseline", "units": []}', Read, Error));
  Assert.Contains(Error, 'kein Architekturstand');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 1, "units": [{"name": "A"}], "edges": [[0, 4, "i"]]}',
    Read, Error));
  Assert.Contains(Error, 'beschädigt');
  Assert.IsFalse(TArchitectureSnapshots.Parse('{"format": 2}', Read, Error));
  Assert.Contains(Error, '"units" fehlt');
end;

procedure TArchitectureSnapshotTests.SavesAndLoadsFile;
var
  Folder, FileName, Error: string;
  Snapshot, Read: TArchitectureSnapshot;
  Bytes: TBytes;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'AtlasSnapshot' + IntToStr(Random(1000000)));
  FileName := TPath.Combine(TPath.Combine(Folder, 'Stand'), 'architektur.json');
  try
    Snapshot := TArchitectureSnapshots.FromOverview(ArchitectureOverviewOf(ArchitectureSampleUnits));
    TArchitectureSnapshots.Save(FileName, Snapshot);
    Bytes := TFile.ReadAllBytes(FileName);
    Assert.AreEqual(Integer(Ord('{')), Integer(Bytes[0]), 'ohne BOM');
    Assert.IsTrue(TArchitectureSnapshots.Load(FileName, Read, Error), Error);
    Assert.AreEqual(TArchitectureSnapshots.Json(Snapshot), TArchitectureSnapshots.Json(Read));
    Assert.IsFalse(TArchitectureSnapshots.Load(TPath.Combine(Folder, 'fehlt.json'), Read, Error));
    Assert.Contains(Error, 'nicht gefunden');
  finally
    if TDirectory.Exists(Folder) then
      TDirectory.Delete(Folder, True);
  end;
end;

procedure TArchitectureSnapshotTests.CycleKeyIgnoresStart;
var
  First, Second: TSnapshotCycle;
begin
  First := Default(TSnapshotCycle);
  First.Units := TArray<string>.Create('B', 'c', 'A');
  Second := Default(TSnapshotCycle);
  Second.Units := TArray<string>.Create('a', 'B', 'C');
  Assert.AreEqual(First.Key, Second.Key);
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
  mName := mOverview.Subsystems[1].Name;
  mOverview.Subsystems[1].Parent := 'App';
  mText := TArchitectureSnapshots.Json(TArchitectureSnapshots.FromOverview(mOverview));
  Assert.Contains(mText, '"isolated": false, "parent": "App"}');
  Assert.IsTrue(TArchitectureSnapshots.Parse(mText, mRead, mError), mError);
  mFound := False;
  for mSubsystem in mRead.Subsystems do
    if mSubsystem.Name = mName then
    begin
      Assert.AreEqual('App', mSubsystem.Parent);
      mFound := True;
    end
    else
      Assert.AreEqual('', mSubsystem.Parent);
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureSnapshotTests);

end.
