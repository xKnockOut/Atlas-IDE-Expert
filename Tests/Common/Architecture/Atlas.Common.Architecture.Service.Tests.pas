unit Atlas.Common.Architecture.Service.Tests;

// Tests des Architekturdienstes (#1118): Umfang über Dateien, Bibliothek,
// Ausschlüsse, Zwischenspeicher je Index-Generation und Anfrage.

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
  end;

function NoReader(const AFileName: string; out AText: string): Boolean;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Service,
  Atlas.Common.Architecture.UsesGraph.Tests;

function NoReader(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function NewService(const AIndex: ISymbolIndex): TArchitectureService;
begin
  Result := TArchitectureService.Create(AIndex,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := NoReader(AFileName, AText);
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
