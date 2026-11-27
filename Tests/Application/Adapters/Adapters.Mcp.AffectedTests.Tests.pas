unit Adapters.Mcp.AffectedTests.Tests;

// Tests für den Host-Adapter zwischen get_affected_tests und dem Host: Mit tests.affected = false, unbekanntem
// Format und ohne Arbeitskopie kommt der Grund statt eines Berichts.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract;

type
  [TestFixture]
  TMcpAffectedTestsAdapterTests = class
  private
    FFolder: string;
    function Report(const ASettings: TServerSettings; const AFormat: string; out AError: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OffGivesReason;
    [Test]
    procedure UnknownFormatGivesChoice;
    [Test]
    procedure WithoutWorkingCopyGivesReason;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Semantics.Impact,
  Mcp.Contract.AffectedTests,
  Mcp.Contract.Workspace,
  Adapters.Mcp.AffectedTests,
  Core.AffectedTests,
  Core.VersionControlChanges,
  Atlas.Tests.TempFolder,
  Shell.Composition.Platform;

type
  /// <summary>Arbeitsbereich ohne Projekt: nur Einstellungen und ein leerer Index.</summary>
  TFakeWorkspace = class(TInterfacedObject, IMcpWorkspace)
  private
    FSettings: TServerSettings;
    FIndex: ISymbolIndex;
  public
    constructor Create(const ASettings: TServerSettings);
    function Settings: TServerSettings;
    function SettingsOf(const AFileName: string): TServerSettings;
    function SettingsFile: string;
    function GlobalSettingsFile: string;
    function Namespaces: TArray<string>;
    function ProjectFiles: TArray<string>;
    function AllFiles: TArray<string>;
    function Ready(out AReason: string): Boolean;
    function Client: string;
    function Session: string;
    function Index: ISymbolIndex;
    function EnsureUnit(const AUnitName: string): Boolean;
    function UnitLoader: TEnsureUnitFunc;
    function CheckSource(const AFileName: string): TPascalSource;
    function Queries: ICodeQueries;
  end;

constructor TFakeWorkspace.Create(const ASettings: TServerSettings);
begin
  inherited Create;
  FSettings := ASettings;
  FIndex := TSymbolIndex.Create;
end;

function TFakeWorkspace.Settings: TServerSettings;
begin
  Result := FSettings;
end;

function TFakeWorkspace.SettingsOf(const AFileName: string): TServerSettings;
begin
  Result := FSettings;
end;

function TFakeWorkspace.SettingsFile: string;
begin
  Result := '';
end;

function TFakeWorkspace.GlobalSettingsFile: string;
begin
  Result := '';
end;

function TFakeWorkspace.Namespaces: TArray<string>;
begin
  Result := nil;
end;

function TFakeWorkspace.ProjectFiles: TArray<string>;
begin
  Result := nil;
end;

function TFakeWorkspace.AllFiles: TArray<string>;
begin
  Result := nil;
end;

function TFakeWorkspace.Ready(out AReason: string): Boolean;
begin
  AReason := '';
  Result := True;
end;

function TFakeWorkspace.Client: string;
begin
  Result := '';
end;

function TFakeWorkspace.Session: string;
begin
  Result := '';
end;

function TFakeWorkspace.Index: ISymbolIndex;
begin
  Result := FIndex;
end;

function TFakeWorkspace.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := False;
end;

function TFakeWorkspace.UnitLoader: TEnsureUnitFunc;
begin
  Result := nil;
end;

function TFakeWorkspace.CheckSource(const AFileName: string): TPascalSource;
begin
  Result := Default(TPascalSource);
end;

function TFakeWorkspace.Queries: ICodeQueries;
begin
  Result := nil;
end;

function PlatformAccess: TCoreVcsAccess;
begin
  Result := TShellPlatformAdapters.VcsAccess;
end;

function DefaultImpactOptions(const AUri: string): TImpactOptions;
begin
  Result := TImpactOptions.Default;
end;

{ TMcpAffectedTestsAdapterTests }

procedure TMcpAffectedTestsAdapterTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-McpAffected-' + IntToStr(Random(MaxInt)));
  TDirectory.CreateDirectory(FFolder);
end;

procedure TMcpAffectedTestsAdapterTests.TearDown;
begin
  TTestTempFolder.Remove(FFolder);
end;

function TMcpAffectedTestsAdapterTests.Report(const ASettings: TServerSettings; const AFormat: string;
  out AError: string): Boolean;
var
  mWorkspace: IMcpWorkspace;
  mTests: IMcpAffectedTests;
  mQuery: TMcpAffectedQuery;
  mText: string;
begin
  mWorkspace := TFakeWorkspace.Create(ASettings);
  mTests := TMcpAffectedTestsAdapter.New(mWorkspace, PlatformAccess, DefaultImpactOptions);
  mQuery := Default(TMcpAffectedQuery);
  mQuery.Root := FFolder;
  mQuery.IncludeUncommitted := True;
  mQuery.Format := AFormat;
  Result := mTests.Report(mQuery, mText, AError);
  Assert.AreEqual('', mText, 'kein Bericht');
end;

procedure TMcpAffectedTestsAdapterTests.OffGivesReason;
var
  mSettings: TServerSettings;
  mError: string;
begin
  mSettings := TServerSettings.Default;
  mSettings.Tests.Affected := False;
  Assert.IsFalse(Report(mSettings, '', mError));
  Assert.AreEqual(TCoreAffectedTests.OffMessage, mError);
end;

procedure TMcpAffectedTestsAdapterTests.UnknownFormatGivesChoice;
var
  mSettings: TServerSettings;
  mError: string;
begin
  mSettings := TServerSettings.Default;
  mSettings.Tests.Affected := True;
  Assert.IsFalse(Report(mSettings, 'xml', mError));
  Assert.Contains(mError, 'dunitx');
end;

procedure TMcpAffectedTestsAdapterTests.WithoutWorkingCopyGivesReason;
var
  mSettings: TServerSettings;
  mError: string;
begin
  mSettings := TServerSettings.Default;
  mSettings.Tests.Affected := True;
  Assert.IsFalse(Report(mSettings, 'json', mError));
  Assert.Contains(mError, 'SVN');
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpAffectedTestsAdapterTests);

end.
