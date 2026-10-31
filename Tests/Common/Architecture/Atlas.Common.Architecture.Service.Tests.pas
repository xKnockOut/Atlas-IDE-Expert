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
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview,
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
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
  Overview: TArchitectureOverview;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('A', ['B'], nil));
  Index.AddUnit(UsesUnit('B', nil, nil));
  Service := NewService(Index);
  try
    Request := Default(TArchitectureRequest);
    Request.Title := 'Projekt';
    Request.CentralUnits := 15;
    Overview := Service.Overview(Request);
    Assert.AreEqual(2, Integer(Length(Overview.Units)));
    Assert.AreEqual('Projekt', Overview.Title);
    Assert.AreEqual(Integer(Index.Generation), Integer(Overview.Generation));
    Service.Overview(Request);
    Assert.AreEqual(1, Service.Computations, 'gleicher Stand: aus dem Zwischenspeicher');
    Request.Title := 'Anders';
    Service.Overview(Request);
    Assert.AreEqual(2, Service.Computations, 'andere Anfrage');
    Request.Grouping.Resolution := 2;
    Overview := Service.Overview(Request);
    Assert.AreEqual(3, Service.Computations, 'andere Feinheit (#1366)');
    Request.Grouping.MaxShare := 0.5;
    Service.Overview(Request);
    Assert.AreEqual(4, Service.Computations, 'andere Nachteilung (#1364)');
    Assert.AreEqual(Double(2), Overview.Grouping.Resolution, 1E-9);
    Index.AddUnit(UsesUnit('C', ['A'], nil));
    Overview := Service.Overview(Request);
    Assert.AreEqual(5, Service.Computations, 'neue Index-Generation');
    Assert.AreEqual(3, Integer(Length(Overview.Units)));
  finally
    Service.Free;
  end;
end;

procedure TArchitectureServiceTests.ScopeFilesAndLibrary;
var
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
  Overview: TArchitectureOverview;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Main', ['App.Data', 'System.SysUtils'], nil));
  Index.AddUnit(UsesUnit('App.Data', nil, nil));
  Index.AddUnit(UsesUnit('Other.Tool', ['App.Data'], nil));
  Index.AddUnit(LibraryUnit('System.SysUtils'));
  Service := NewService(Index);
  try
    Request := Default(TArchitectureRequest);
    Request.Files := [UsesUnit('App.Main', nil, nil).FileName, UsesUnit('App.Data', nil, nil).FileName];
    Overview := Service.Overview(Request);
    Assert.AreEqual(2, Integer(Length(Overview.Units)), 'nur Dateien des Projekts, keine Bibliothek');
    Assert.AreEqual(-1, Overview.IndexOf('Other.Tool'));
    Request.IncludeLibrary := True;
    Overview := Service.Overview(Request);
    Assert.AreEqual(3, Integer(Length(Overview.Units)));
    Assert.IsTrue(Overview.Units[Overview.IndexOf('System.SysUtils')].Library_);
    Request.Files := nil;
    Request.IncludeLibrary := False;
    Overview := Service.Overview(Request);
    Assert.AreEqual(3, Integer(Length(Overview.Units)), 'ohne Dateiliste: alle Projekt-Units');
  finally
    Service.Free;
  end;
end;

procedure TArchitectureServiceTests.ExcludesByPattern;
var
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Request: TArchitectureRequest;
  Overview: TArchitectureOverview;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Main', ['App.Data'], nil));
  Index.AddUnit(UsesUnit('App.Data', nil, nil));
  Index.AddUnit(UsesUnit('App.Data.Tests', ['App.Data'], nil));
  Service := NewService(Index);
  try
    Request := Default(TArchitectureRequest);
    Request.Root := 'C:\Projekt';
    Request.Exclude := ['*.Tests'];
    Overview := Service.Overview(Request);
    Assert.AreEqual(2, Integer(Length(Overview.Units)));
    Assert.AreEqual(-1, Overview.IndexOf('App.Data.Tests'));
    Assert.AreEqual('*.Tests', string.Join(',', Overview.Excludes));
  finally
    Service.Free;
  end;
end;

procedure TArchitectureServiceTests.RequestFromSettings;
var
  Settings: TServerSettings;
  Request: TArchitectureRequest;
begin
  Settings := TServerSettings.Default;
  Settings.ArchitectureScope := 'project';
  Settings.ArchitectureIncludeLibraryUnits := True;
  Settings.ArchitectureCentralUnits := 20;
  Settings.ArchitectureExclude := ['Tests/**'];
  Settings.ArchitectureGroupingResolution := 1.5;
  Settings.ArchitectureGroupingMaxShare := 0.4;
  Settings.ArchitectureGroupingMinCohesion := 0;
  Settings.ArchitectureGroupingFoundations := 'attach';
  Request := TArchitectureRequest.FromSettings(Settings);
  Assert.IsTrue(Request.Grouping.Foundations = TArchitectureFoundations.Attach);
  Assert.IsTrue(TArchitectureRequest.FromSettings(TServerSettings.Default).Grouping.Foundations =
    TArchitectureFoundations.Separate);
  Assert.AreEqual(Double(1.5), Request.Grouping.Resolution, 1E-9);
  Assert.AreEqual(Double(0.4), Request.Grouping.MaxShare, 1E-9);
  Assert.AreEqual(Double(0), Request.Grouping.MinCohesion, 1E-9);
  Assert.AreEqual('project', Request.Scope);
  Assert.IsTrue(Request.IncludeLibrary);
  Assert.AreEqual(20, Request.CentralUnits);
  Assert.AreEqual('Tests/**', Request.Exclude[0]);
  Assert.AreNotEqual(Request.Key, TArchitectureRequest.FromSettings(TServerSettings.Default).Key);
  // Zuordnung erklären (#1368): nur Ausgabe, nicht im Schlüssel.
  Assert.IsTrue(TArchitectureRequest.FromSettings(TServerSettings.Default).ExplainAssignment);
  Settings := TServerSettings.Default;
  Settings.ArchitectureExplainAssignment := False;
  Request := TArchitectureRequest.FromSettings(Settings);
  Assert.IsFalse(Request.ExplainAssignment);
  Assert.AreEqual(TArchitectureRequest.FromSettings(TServerSettings.Default).Key, Request.Key);
  // Angleichung (#1367): an, Baseline aus den Einstellungen; im Schlüssel.
  Assert.IsTrue(TArchitectureRequest.FromSettings(TServerSettings.Default).KeepPrevious);
  Settings := TServerSettings.Default;
  Settings.ArchitectureGroupingKeepPrevious := False;
  Settings.ArchitectureBaseline := 'docs/architektur.json';
  Request := TArchitectureRequest.FromSettings(Settings);
  Assert.IsFalse(Request.KeepPrevious);
  Assert.AreEqual('docs/architektur.json', Request.Baseline);
  Assert.AreNotEqual(TArchitectureRequest.FromSettings(TServerSettings.Default).Key, Request.Key);
end;

/// <summary>Teilsystem mit der Unit AUnit.</summary>
function SubsystemOf(const AOverview: TArchitectureOverview; const AUnit: string): TOverviewSubsystem;
begin
  Result := AOverview.Subsystems[AOverview.Units[AOverview.IndexOf(AUnit)].Subsystem];
end;

procedure TArchitectureServiceTests.KeepsPreviousState;
var
  mIndex: ISymbolIndex;
  mService: TArchitectureService;
  mRequest: TArchitectureRequest;
  mOverview: TArchitectureOverview;
  mFolder, mPrevious: string;
  mItem: TUnitIndex;
  mBaseline: TArchitectureSnapshot;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasAngleichung' + IntToStr(Random(1000000)));
  mPrevious := TPath.Combine(TPath.Combine(mFolder, 'Cache'), 'architecture-last.json');
  mIndex := TSymbolIndex.Create;
  for mItem in AlignmentSample(False) do
    mIndex.AddUnit(mItem);
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
    Assert.AreEqual(TArchitectureAnalyzer.AlignedLast, mOverview.AlignedSource);
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
    // Baseline vor dem letzten Stand: der Stand ohne Index.B4 (Index.B* hieß dort „Index 2“).
    mBaseline := TArchitectureSnapshots.FromOverview(AlignmentOverview(False));
    TArchitectureSnapshots.Save(TPath.Combine(mFolder, 'stand.json'), mBaseline);
    mRequest.Root := mFolder;
    mRequest.Baseline := 'stand.json';
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(TArchitectureAnalyzer.AlignedBaseline, mOverview.AlignedSource);
    Assert.AreEqual('Index 2', SubsystemOf(mOverview, 'Index.B1').Name);
    // keepPrevious aus: wie ohne Angleichung, keine Datei.
    TFile.Delete(mPrevious);
    mRequest.KeepPrevious := False;
    mOverview := mService.Overview(mRequest);
    Assert.IsFalse(mOverview.IsAligned);
    Assert.AreEqual('Index', SubsystemOf(mOverview, 'Index.B1').Name);
    Assert.IsFalse(FileExists(mPrevious));
    // Ohne PreviousFile (AtlasServer --architecture): nur an die Baseline, keine Datei.
    mRequest.KeepPrevious := True;
    mRequest.PreviousFile := '';
    mOverview := mService.Overview(mRequest);
    Assert.AreEqual(TArchitectureAnalyzer.AlignedBaseline, mOverview.AlignedSource);
    Assert.IsFalse(FileExists(mPrevious));
  finally
    mService.Free;
    if TDirectory.Exists(mFolder) then
      TDirectory.Delete(mFolder, True);
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
  Index: ISymbolIndex;
  Service: TArchitectureService;
  Overview: TArchitectureOverview;
  Package, Program_: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(UsesUnit('App.Data', nil, nil));
  Program_ := UsesUnit('App', ['App.Data'], nil);
  Program_.FileName := ChangeFileExt(Program_.FileName, '.dpr');
  Index.AddUnit(Program_);
  Package := UsesUnit('AppPackage', nil, nil);
  Package.FileName := ChangeFileExt(Package.FileName, '.dpk');
  Index.AddUnit(Package);
  Service := NewService(Index);
  try
    Overview := Service.Overview(Default(TArchitectureRequest));
    Assert.AreEqual(-1, Overview.IndexOf('AppPackage'), 'Package ohne uses');
    Assert.IsTrue(Overview.IndexOf('App') >= 0, 'Programm mit uses');
    Assert.AreEqual(2, Integer(Length(Overview.Units)));
  finally
    Service.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArchitectureServiceTests);

end.
