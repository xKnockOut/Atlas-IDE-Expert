unit Atlas.Common.Architecture.Service.Tests;

// Tests des Architekturdienstes (#1118): Umfang über Dateien, Bibliothek,
// Ausschlüsse, Zwischenspeicher je Index-Generation und Anfrage; Zuordnung
// erklären ohne neue Rechnung (#1368); Angleichung an den vorigen Stand
// (#1367).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArchitectureServiceTests = class
  public
    [Test]
    procedure CachesPerGenerationAndRequest;
    [Test]
    procedure ScopeFilesAndLibrary;
    [Test]
    procedure ExcludesByPattern;
    [Test]
    procedure RequestFromSettings;
    [Test]
    procedure SkipsPackagesKeepsPrograms;
    [Test]
    procedure ExplainAssignmentWithoutRecompute;
    /// <summary>Angleichung (#1367): letzter Stand im Cache, Baseline vor ihm, „neu benennen“, keepPrevious aus und
    /// ohne PreviousFile (AtlasServer --architecture) keine Datei.</summary>
    [Test]
    procedure KeepsPreviousState;
  end;

function NoReader(out AText: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Grouping,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.UsesGraph.Tests,
  Atlas.Common.Architecture.Alignment.Tests;

function NoReader(out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NewService(const AIndex: ISymbolIndex): TArchitectureService;
begin
  Result := TArchitectureService.Create(AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := NoReader(AText);
    end,
    function(const AFileName: string): TArray<string>
    begin
      Result := nil;
    end);
end;

function LibraryUnit(const AName: string): TUnitIndex;
begin
  Result := UsesUnit(AName, nil, nil);
  Result.Library_ := True;
end;

{ TArchitectureServiceTests }

procedure TArchitectureServiceTests.CachesPerGenerationAndRequest;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('A', ['B'], nil));
  mIndex.AddUnit(UsesUnit('B', nil, nil));
  mService := NewService(mIndex);
  try
    mRequest := Default(TArchitectureRequest);
    mRequest.Title := 'Projekt';
    mRequest.CentralUnits := 15;
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(2, Integer(Length(mOverview.Units)));
    Assert.AreEqual('Projekt', mOverview.Title);
    Assert.AreEqual(Integer(mIndex.Generation), Integer(mOverview.Generation));
    mService.Overview(mRequest);
    Assert.AreEqual(1, mService.Computations, 'gleicher Stand: aus dem Zwischenspeicher');
    mRequest.Title := 'Anders';
    mService.Overview(mRequest);
    Assert.AreEqual(2, mService.Computations, 'andere Anfrage');
    mRequest.Grouping.Resolution := 2;
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(3, mService.Computations, 'andere Feinheit (#1366)');
    mRequest.Grouping.MaxShare := 0.5;
    mService.Overview(mRequest);
    Assert.AreEqual(4, mService.Computations, 'andere Nachteilung (#1364)');
    Assert.AreEqual(Double(2), mOverview.Grouping.Resolution, 1E-9);
    mIndex.AddUnit(UsesUnit('C', ['A'], nil));
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(5, mService.Computations, 'neue Index-Generation');
    Assert.AreEqual(3, Integer(Length(mOverview.Units)));
  finally
    mService.Free;
  end;
end;

procedure TArchitectureServiceTests.ScopeFilesAndLibrary;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Main', ['App.Data', 'System.SysUtils'], nil));
  mIndex.AddUnit(UsesUnit('App.Data', nil, nil));
  mIndex.AddUnit(UsesUnit('Other.Tool', ['App.Data'], nil));
  mIndex.AddUnit(LibraryUnit('System.SysUtils'));
  mService := NewService(mIndex);
  try
    mRequest := Default(TArchitectureRequest);
    mRequest.Files := [UsesUnit('App.Main', nil, nil).FileName, UsesUnit('App.Data', nil, nil).FileName];
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(2, Integer(Length(mOverview.Units)), 'nur Dateien des Projekts, keine Bibliothek');
    Assert.AreEqual(-1, mOverview.IndexOf('Other.Tool'));
    mRequest.IncludeLibrary := True;
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(3, Integer(Length(mOverview.Units)));
    Assert.IsTrue(mOverview.Units[mOverview.IndexOf('System.SysUtils')].Library_);
    mRequest.Files := nil;
    mRequest.IncludeLibrary := False;
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(3, Integer(Length(mOverview.Units)), 'ohne Dateiliste: alle Projekt-Units');
  finally
    mService.Free;
  end;
end;

procedure TArchitectureServiceTests.ExcludesByPattern;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  mIndex.AddUnit(UsesUnit('App.Data', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Data.Tests', ['App.Data'], nil));
  mService := NewService(mIndex);
  try
    mRequest := Default(TArchitectureRequest);
    mRequest.Root := 'C:\Projekt';
    mRequest.Exclude := ['*.Tests'];
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(2, Integer(Length(mOverview.Units)));
    Assert.AreEqual(-1, mOverview.IndexOf('App.Data.Tests'));
    Assert.AreEqual('*.Tests', string.Join(',', mOverview.Excludes));
  finally
    mService.Free;
  end;
end;

procedure TArchitectureServiceTests.RequestFromSettings;
var
  mSettings: TServerSettings;
  mRequest: TArchitectureRequest;
begin
  mSettings := TServerSettings.Default;
  mSettings.ArchitectureScope := 'project';
  mSettings.ArchitectureIncludeLibraryUnits := True;
  mSettings.ArchitectureCentralUnits := 20;
  mSettings.ArchitectureExclude := ['Tests/**'];
  mSettings.ArchitectureGroupingResolution := 1.5;
  mSettings.ArchitectureGroupingMaxShare := 0.4;
  mSettings.ArchitectureGroupingMinCohesion := 0;
  mSettings.ArchitectureGroupingFoundations := 'attach';
  mRequest := TArchitectureRequest.FromSettings(mSettings);
  Assert.AreEqual<TArchitectureFoundations>(TArchitectureFoundations.Attach, mRequest.Grouping.Foundations);
  Assert.AreEqual<TArchitectureFoundations>(TArchitectureFoundations.Separate,
    TArchitectureRequest.FromSettings(TServerSettings.Default).Grouping.Foundations);
  Assert.AreEqual(Double(1.5), mRequest.Grouping.Resolution, 1E-9);
  Assert.AreEqual(Double(0.4), mRequest.Grouping.MaxShare, 1E-9);
  Assert.AreEqual(Double(0), mRequest.Grouping.MinCohesion, 1E-9);
  Assert.AreEqual('project', mRequest.Scope);
  Assert.IsTrue(mRequest.IncludeLibrary);
  Assert.AreEqual(20, mRequest.CentralUnits);
  Assert.AreEqual('Tests/**', mRequest.Exclude[0]);
  Assert.AreNotEqual(mRequest.Key, TArchitectureRequest.FromSettings(TServerSettings.Default).Key);
  // Zuordnung erklären (#1368): nur Ausgabe, nicht im Schlüssel.
  Assert.IsTrue(TArchitectureRequest.FromSettings(TServerSettings.Default).ExplainAssignment);
  mSettings := TServerSettings.Default;
  mSettings.ArchitectureExplainAssignment := False;
  mRequest := TArchitectureRequest.FromSettings(mSettings);
  Assert.IsFalse(mRequest.ExplainAssignment);
  Assert.AreEqual(TArchitectureRequest.FromSettings(TServerSettings.Default).Key, mRequest.Key);
  // Angleichung (#1367): an, Baseline aus den Einstellungen; im Schlüssel.
  Assert.IsTrue(TArchitectureRequest.FromSettings(TServerSettings.Default).KeepPrevious);
  mSettings := TServerSettings.Default;
  mSettings.ArchitectureGroupingKeepPrevious := False;
  mSettings.ArchitectureBaseline := 'docs/architektur.json';
  mRequest := TArchitectureRequest.FromSettings(mSettings);
  Assert.IsFalse(mRequest.KeepPrevious);
  Assert.AreEqual('docs/architektur.json', mRequest.Baseline);
  Assert.AreNotEqual(TArchitectureRequest.FromSettings(TServerSettings.Default).Key, mRequest.Key);
end;

/// <summary>Teilsystem mit der Unit AUnit.</summary>
function SubsystemOf(const AOverview: TArchitectureOverview; const AUnit: string): TOverviewSubsystem;
begin
  Result := AOverview.Subsystems[AOverview.Units[AOverview.IndexOf(AUnit)].Subsystem];
end;

/// <summary>Baseline vor dem letzten Stand; keepPrevious aus und ohne PreviousFile keine Datei.</summary>
procedure AssertBaselineBeforeLastState(AService: TArchitectureService; var ARequest: TArchitectureRequest;
  const AFolder, APrevious: string);
var
  mOverview: TArchitectureOverview;
  mBaseline: TArchitectureSnapshot;
begin
  // Baseline vor dem letzten Stand: der Stand ohne Index.B4 (Index.B* hieß dort „Index 2“).
  mBaseline := TArchitectureSnapshots.FromOverview(AlignmentOverview(False));
  TArchitectureSnapshots.Save(TPath.Combine(AFolder, 'stand.json'), mBaseline);
  ARequest.Root := AFolder;
  ARequest.Baseline := 'stand.json';
  mOverview := AService.Overview(ARequest);
  Assert.AreEqual(TArchitectureAnalyzer.cAlignedBaseline, mOverview.AlignedSource);
  Assert.AreEqual('Index 2', SubsystemOf(mOverview, 'Index.B1').Name);
  // keepPrevious aus: wie ohne Angleichung, keine Datei.
  TFile.Delete(APrevious);
  ARequest.KeepPrevious := False;
  mOverview := AService.Overview(ARequest);
  Assert.IsFalse(mOverview.IsAligned);
  Assert.AreEqual('Index', SubsystemOf(mOverview, 'Index.B1').Name);
  Assert.IsFalse(FileExists(APrevious));
  // Ohne PreviousFile (AtlasServer --architecture): nur an die Baseline, keine Datei.
  ARequest.KeepPrevious := True;
  ARequest.PreviousFile := '';
  mOverview := AService.Overview(ARequest);
  Assert.AreEqual(TArchitectureAnalyzer.cAlignedBaseline, mOverview.AlignedSource);
  Assert.IsFalse(FileExists(APrevious));
end;

procedure TArchitectureServiceTests.KeepsPreviousState;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
  mFolder, mPrevious: string;
  mItem: TUnitIndex;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasAngleichung' + IntToStr(Random(1000000)));
  mPrevious := TPath.Combine(TPath.Combine(mFolder, 'Cache'), 'architecture-last.json');
  mIndex := TSymbolIndex.Create;
  for mItem in AlignmentSample(False) do
  begin
    mIndex.AddUnit(mItem);
  end;
  mService := NewService(mIndex);
  try
    mRequest := Default(TArchitectureRequest);
    mRequest.KeepPrevious := True;
    mRequest.PreviousFile := mPrevious;
    mOverview := mService.Overview(mRequest);
    Assert.IsFalse(mOverview.IsAligned, 'noch kein voriger Stand');
    Assert.IsTrue(FileExists(mPrevious), 'Ergebnis als letzter Stand abgelegt');
    Assert.AreEqual('Index 2', SubsystemOf(mOverview, 'Index.B1').Name);
    // Eine neue Unit vertauscht die beiden Index-Gruppen; angeglichen an den letzten Stand bleiben Name und Farbe.
    mIndex.AddUnit(UsesUnit('Index.B4', ['Index.B1', 'Index.B2', 'Index.B3'], nil));
    mOverview := mService.Overview(mRequest);
    Assert.IsTrue(mOverview.IsAligned);
    Assert.AreEqual(TArchitectureAnalyzer.cAlignedLast, mOverview.AlignedSource);
    Assert.AreEqual('Index 2', SubsystemOf(mOverview, 'Index.B1').Name);
    Assert.AreEqual(1, SubsystemOf(mOverview, 'Index.B1').ColorSlot);
    // „Teilsysteme neu benennen“: einmal ohne Angleichung, auch bei gleichem Index; das Ergebnis wird der letzte
    // Stand.
    mRequest.Rename := True;
    mOverview := mService.Overview(mRequest);
    Assert.IsFalse(mOverview.IsAligned);
    Assert.AreEqual('Index', SubsystemOf(mOverview, 'Index.B1').Name);
    Assert.AreEqual(0, SubsystemOf(mOverview, 'Index.B1').ColorSlot);
    Assert.AreEqual(3, mService.Computations);
    mRequest.Rename := False;
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(3, mService.Computations, 'danach wieder aus dem Zwischenspeicher');
    Assert.AreEqual('Index', SubsystemOf(mOverview, 'Index.B1').Name);
    AssertBaselineBeforeLastState(mService, mRequest, mFolder, mPrevious);
  finally
    mService.Free;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

procedure TArchitectureServiceTests.ExplainAssignmentWithoutRecompute;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Data', nil, nil));
  mIndex.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  mService := NewService(mIndex);
  try
    mRequest := Default(TArchitectureRequest);
    mRequest.ExplainAssignment := True;
    mOverview := mService.Overview(mRequest);
    Assert.IsTrue(mOverview.ShowsAssignment);
    mRequest.ExplainAssignment := False;
    mOverview := mService.Overview(mRequest);
    Assert.IsFalse(mOverview.ShowsAssignment);
    // Die Daten bleiben (Ausreißer lesen sie), nur die Ausgabe fällt weg.
    Assert.AreEqual(2, Integer(Length(mOverview.Assignments)));
    Assert.AreEqual(1, mService.Computations);
  finally
    mService.Free;
  end;
end;

procedure TArchitectureServiceTests.SkipsPackagesKeepsPrograms;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mOverview: TArchitectureOverview;
  mPackage, mProgram_: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UsesUnit('App.Data', nil, nil));
  mProgram_ := UsesUnit('App', ['App.Data'], nil);
  mProgram_.FileName := ChangeFileExt(mProgram_.FileName, '.dpr');
  mIndex.AddUnit(mProgram_);
  mPackage := UsesUnit('AppPackage', nil, nil);
  mPackage.FileName := ChangeFileExt(mPackage.FileName, '.dpk');
  mIndex.AddUnit(mPackage);
  mService := NewService(mIndex);
  try
    mOverview := mService.Overview(Default(TArchitectureRequest));
    Assert.AreEqual(-1, mOverview.IndexOf('AppPackage'), 'Package ohne uses');
    Assert.IsTrue(mOverview.IndexOf('App') >= 0, 'Programm mit uses');
    Assert.AreEqual(2, Integer(Length(mOverview.Units)));
  finally
    mService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureServiceTests);

end.
