unit Rules.Builtin.Architecture.Tests;

// Tests für die Architekturregeln forbidden-uses (#183), architecture-role-import
// und architecture-contract-content. Die Matrix prüft
// MatrixCasesFromFile gegen Tests/Data/Architecture/role-imports.json, dieselbe
// Fallliste wie Tools/Check-PackageDependencies.ps1 -SelfTest.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForbiddenUsesRuleTests = class
  public
    [Test]
    procedure ReportsDeniedUnitByUnitName;
    [Test]
    procedure AllowOverridesDeny;
    [Test]
    procedure MatchesLayerByPath;
    [Test]
    procedure SilentWithoutLayers;
    [Test]
    procedure IgnoresInvalidLayers;
  end;

  [TestFixture]
  TArchitectureMatrixTests = class
  public
    [Test]
    procedure ClassifiesFeatureRoles;
    [Test]
    procedure ClassifiesLongestPrefix;
    [Test]
    procedure ClassifiesHostAndExternal;
    [Test]
    procedure ClassifiesHostedFeature;
    [Test]
    procedure ClassifiesRoleAfterThing;
    [Test]
    procedure ClassifiesNesting;
    [Test]
    procedure FindsCommonCarrier;
    [Test]
    procedure MatrixCasesFromFile;
    [Test]
    procedure DescribesOwnAndForeign;
    [Test]
    procedure DescribesNestedAndHostRoles;
    [Test]
    procedure ClassifiesDomainPackage;
    [Test]
    procedure ClassifiesLayerPackageAndTargets;
    [Test]
    procedure ClassifiesBaseBeforeSwitch;
    [Test]
    procedure DescribesDomainPackage;
  end;

  [TestFixture]
  TRoleImportRuleTests = class
  public
    [Test]
    procedure ReportsForbiddenImportAtUsesEntry;
    [Test]
    procedure AllowsOwnContractAndForeignRoot;
    [Test]
    procedure SilentWithoutPrefixes;
    [Test]
    procedure ApprovedExceptionIsSilent;
    [Test]
    procedure ApprovedExceptionNeverCoversInternals;
    [Test]
    procedure ChecksImplementationUses;
    [Test]
    procedure ChecksHostedFeature;
    [Test]
    procedure PackageContainsIsNoImport;
    [Test]
    procedure TestUnitIsSilent;
    [Test]
    procedure ParsesOptions;
    [Test]
    procedure ChecksDomainPackage;
  end;

  [TestFixture]
  TContractContentRuleTests = class
  public
    [Test]
    procedure ReportsClassInContract;
    [Test]
    procedure AllowsExceptionsAndInterfaces;
    [Test]
    procedure IgnoresImplementationSection;
    [Test]
    procedure IgnoresNonContractUnit;
    [Test]
    procedure IgnoresTestUnitOfContract;
    [Test]
    procedure ForwardDeclarationIsSilent;
    [Test]
    procedure ApprovedTypeIsSilent;
    [Test]
    procedure ChecksRoleAfterThingAndSubContract;
    [Test]
    procedure ChecksContractOfDomainPackage;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Rules.Builtin.Architecture,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Findings.Contract;

const
  cLayerConfig =
    '{ "rules": { "forbidden-uses": { "layers": [' +
    '{ "from": "*.Common.*", "deny": ["Vcl.*", "Winapi.*"], "allow": ["Winapi.Windows"] },' +
    '{ "from": "Source/Windows/**", "deny": ["Vcl.*"] } ] } } }';
  cLayerSource =
    'unit App.Common.Model;'#10 +
    'interface'#10 +
    'uses System.Classes, Vcl.Forms, Winapi.Windows;'#10 +
    'implementation'#10 +
    'uses Winapi.Messages;'#10 +
    'end.';

{ TForbiddenUsesRuleTests }

procedure TForbiddenUsesRuleTests.ReportsDeniedUnitByUnitName;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForbiddenUsesRule.Create, cLayerSource, cLayerConfig, 'Source/App.Common.Model.pas');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(30, mFindings[0].Range.EndPos.Character);
  Assert.IsTrue(Pos('Vcl.Forms', mFindings[0].Message) > 0);
  Assert.AreEqual(4, mFindings[1].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
end;

procedure TForbiddenUsesRuleTests.AllowOverridesDeny;
var
  mFinding: TRuleFinding;
begin
  for mFinding in TRuleAssert.Findings(TForbiddenUsesRule.Create, cLayerSource, cLayerConfig, 'Source/App.Common.Model.pas') do
  begin
    Assert.AreEqual(0, Pos('Winapi.Windows', mFinding.Message));
  end;
end;

procedure TForbiddenUsesRuleTests.MatchesLayerByPath;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForbiddenUsesRule.Create,
    'unit Fenster;'#10'interface'#10'uses Vcl.Controls, Winapi.Windows;'#10'implementation'#10'end.', cLayerConfig,
    'Source/Windows/Fenster.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Character);
end;

procedure TForbiddenUsesRuleTests.SilentWithoutLayers;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForbiddenUsesRule.Create, cLayerSource, '',
    'Source/App.Common.Model.pas'))));
end;

procedure TForbiddenUsesRuleTests.IgnoresInvalidLayers;
var
  mLayers: TArray<TArchitectureLayer>;
begin
  mLayers := TForbiddenUsesRule.ParseLayers('{ "layers": [ { "deny": ["X"] }, { "from": "A", "deny": [] }, ' +
    '{ "from": "B", "deny": ["Y", 3] } ] }');
  Assert.AreEqual(1, Integer(Length(mLayers)));
  Assert.AreEqual('B', mLayers[0].From);
  Assert.AreEqual(1, Integer(Length(mLayers[0].Deny)));
  Assert.AreEqual(0, Integer(Length(TForbiddenUsesRule.ParseLayers('kein json'))));
end;

{ TArchitectureMatrixTests }

const
  cPrefixes: array[0..7] of string = ('Atlas.Text', 'Atlas.WinBase', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Linux',
    'Atlas.Core', 'Atlas.UI', 'Atlas.IDE');

function PrefixList: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cPrefixes));
  for mIndex := 0 to High(cPrefixes) do
  begin
    Result[mIndex] := cPrefixes[mIndex];
  end;
end;

function Classify(const AName: string): TArchitectureUnit;
begin
  Result := TArchitectureMatrix.Classify(AName, PrefixList, TArchitectureMatrix.DefaultHostRoles, ['Gamma']);
end;

{ TArchitectureMatrixTests }

procedure TArchitectureMatrixTests.ClassifiesFeatureRoles;
var
  U: TArchitectureUnit;
begin
  U := Classify('Atlas.Common.Logging.Providers.StreamSink');
  Assert.AreEqual('Atlas.Common', U.Artefact);
  Assert.AreEqual('Logging', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(U.Role));
  Assert.AreEqual(Ord(TArchitectureRole.Contract), Ord(Classify('Atlas.Common.Logging.Contract').Role));
  U := Classify('Atlas.Common.Rules.Builtin.Architecture');
  Assert.AreEqual('Rules', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Root), Ord(U.Role));
  Assert.AreEqual(Ord(TArchitectureRole.Internals), Ord(Classify('Atlas.Core.Completion.Internals.Async').Role));
  U := Classify('Atlas.Text.Lines');
  Assert.AreEqual('Lines', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Root), Ord(U.Role));
end;

procedure TArchitectureMatrixTests.ClassifiesLongestPrefix;
var
  U: TArchitectureUnit;
begin
  U := TArchitectureMatrix.Classify('Atlas.Core.Lsp.Session', ['Atlas', 'Atlas.Core'], nil, nil);
  Assert.AreEqual('Atlas.Core', U.Artefact);
  Assert.AreEqual('Lsp', U.Feature);
  // Präfix nur an Segmentgrenzen: Atlas.Common ist nicht Atlas.Co + mmon.
  U := TArchitectureMatrix.Classify('Atlas.Common.Lsp.Hover', ['Atlas.Co'], nil, nil);
  Assert.IsFalse(U.Known);
end;

procedure TArchitectureMatrixTests.ClassifiesHostedFeature;
var
  U: TArchitectureUnit;
begin
  // Hosted-Feature der Anwendung: kein Präfix, das erste Segment ist das Feature (Konzept 6.3).
  U := Classify('Gamma.Providers.Cache.Contract');
  Assert.IsTrue(U.Hosted);
  Assert.AreEqual('', U.Artefact);
  Assert.AreEqual('Gamma', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(U.Role));
  Assert.IsTrue(U.IsContract, 'Sub-Contract');
  Assert.AreEqual(Ord(TArchitectureRole.Root), Ord(Classify('Gamma.Session').Role));
  Assert.IsFalse(Classify('Gamma').Known, 'ohne Punkt keine Unit eines Features');
  Assert.IsFalse(Classify('Shell.Composition').Hosted);
  Assert.IsFalse(Classify('Atlas.Common.Logging.Contract').Hosted);
end;

procedure TArchitectureMatrixTests.ClassifiesHostAndExternal;
var
  U: TArchitectureUnit;
begin
  U := Classify('Shell.Composition');
  Assert.AreEqual(Ord(TArchitectureRole.Host), Ord(U.Role));
  Assert.AreEqual('Shell', U.Feature);
  Assert.IsFalse(Classify('System.SysUtils').Known);
  Assert.IsFalse(Classify('Vcl.Forms').Known);
  Assert.IsFalse(Classify('Setup.Core.Plan').Known);
  Assert.IsFalse(Classify('Shell').Known, 'ohne Punkt keine Host-Unit');
end;

procedure TArchitectureMatrixTests.ClassifiesRoleAfterThing;
var
  U: TArchitectureUnit;
begin
  U := Classify('Atlas.Common.Testing.AffectedTests.Contract');
  Assert.AreEqual('Testing', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Contract), Ord(U.Role));
  Assert.IsTrue(U.IsContract);
  U := Classify('Atlas.UI.Tracker.IssueFrame.Contract');
  Assert.AreEqual('Tracker', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Contract), Ord(U.Role));
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(Classify('Atlas.Common.Lsp.Group.Providers.Store').Role));
  Assert.IsFalse(Classify('Atlas.Common.Lsp.Group.Providers.Store').IsContract);
  U := Classify('Atlas.WinBase.Files.Internals.Handles');
  Assert.AreEqual('Atlas.WinBase', U.Artefact, 'Atlas.WinBase hat eigene Rollen');
  Assert.AreEqual(Ord(TArchitectureRole.Internals), Ord(U.Role));
  Assert.AreEqual('Atlas.Linux', Classify('Atlas.Linux.Console.Adapters.Stream').Artefact);
end;

procedure TArchitectureMatrixTests.ClassifiesNesting;
var
  U: TArchitectureUnit;
begin
  U := Classify('Atlas.Common.Server.Providers.Cache.Internals.Store');
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(U.Role));
  Assert.AreEqual(2, Integer(Length(U.Positions)));
  Assert.AreEqual(1, U.Positions[0]);
  Assert.AreEqual(3, U.Positions[1]);
  Assert.AreEqual(Ord(TArchitectureRole.Internals), Ord(U.Roles[1]));
  U := Classify('Atlas.Common.Server.Providers.Cache.Contract');
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(U.Role));
  Assert.IsTrue(U.IsContract, 'Sub-Contract');
  // Keine Wiederholung: Providers.Cache.Providers.Store ist Providers.Cache.Store.
  Assert.AreEqual(1, Integer(Length(Classify('Atlas.Common.Server.Providers.Cache.Providers.Store').Positions)));
  // Zwei Rollenbezeichner hintereinander: Träger ist Feature.Composition.
  U := Classify('Atlas.IDE.Tracker.Composition.Adapters');
  Assert.AreEqual(Ord(TArchitectureRole.Composition), Ord(U.Role));
  Assert.AreEqual(2, U.Positions[1]);
end;

procedure TArchitectureMatrixTests.FindsCommonCarrier;
var
  mCache: TArchitectureUnit;
begin
  mCache := Classify('Atlas.Common.Server.Providers.Cache');
  Assert.AreEqual(3, TArchitectureMatrix.CarrierLength(mCache, Classify('Atlas.Common.Server.Providers.Cache.Store')));
  Assert.AreEqual(3, TArchitectureMatrix.CarrierLength(Classify('Atlas.Common.Server.Providers.Cache.Contract'),
    Classify('Atlas.Common.Server.Providers.Cache.Internals.Store')));
  Assert.AreEqual(1, TArchitectureMatrix.CarrierLength(mCache, mCache), 'ein Name ist nicht sein eigener Träger');
  Assert.AreEqual(1, TArchitectureMatrix.CarrierLength(Classify('Atlas.Common.Server.Providers.User'),
    Classify('Atlas.Common.Server.Providers.Cache.Internals.Store')));
  Assert.AreEqual(Ord(TArchitectureRole.Providers), Ord(TArchitectureMatrix.SourceRights(
    Classify('Atlas.Common.Server.Providers.Cache.Internals.Store'), 1)), 'Struktur erbt die Rechte des Trägers');
  Assert.AreEqual(Ord(TArchitectureRole.Contract), Ord(TArchitectureMatrix.SourceRights(
    Classify('Atlas.Common.Server.Providers.Cache.Contract'), 1)), 'Sub-Contract nur mit Contract-Rechten');
  Assert.AreEqual(Ord(TArchitectureViewKind.SubContract), Ord(TArchitectureMatrix.TargetView(
    Classify('Atlas.Common.Server.Providers.Cache.Contract'), 1).Kind));
end;

function RoleImportsFile: string;
var
  mDirectory: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    Result := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Architecture', 'role-imports.json'))));
    if TFile.Exists(Result) then
    begin
      Exit;
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  Result := '';
end;

procedure TArchitectureMatrixTests.MatrixCasesFromFile;
var
  mFileName, mText: string;
  mRoot: TJSONValue;
  mData: TJSONObject;
  mItem: TJSONValue;
  mCase_: TJSONObject;
  mOptions: TRoleImportOptions;
  mSource, mTarget: TArchitectureUnit;
  mCount: Integer;
begin
  mFileName := RoleImportsFile;
  Assert.AreNotEqual('', mFileName, 'Tests\Data\Architecture\role-imports.json nicht gefunden');
  mText := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  // Dieselben Schlüssel wie die Optionen der Regel in atlas.json.
  mOptions := TRoleImportRule.ParseOptions(mText);
  mRoot := TJSONObject.ParseJSONValue(mText);
  try
    Assert.IsTrue(mRoot is TJSONObject);
    mData := TJSONObject(mRoot);
    mCount := 0;
    for mItem in mData.GetValue<TJSONArray>('cases') do
    begin
      mCase_ := mItem as TJSONObject;
      mSource := TArchitectureMatrix.ClassifySource(mCase_.GetValue<string>('from'), mOptions);
      mTarget := TArchitectureMatrix.ClassifyTarget(mSource, mCase_.GetValue<string>('to'), mOptions);
      Assert.AreEqual(mCase_.GetValue<Boolean>('allowed'), TArchitectureMatrix.Allowed(mSource, mTarget),
        mCase_.GetValue<string>('from') + ' -> ' + mCase_.GetValue<string>('to'));
      Inc(mCount);
    end;
    Assert.IsTrue(mCount > 600, 'Fallliste unvollständig');
  finally
    mRoot.Free;
  end;
end;

procedure TArchitectureMatrixTests.DescribesOwnAndForeign;
begin
  Assert.AreEqual('fremde Providers aus Root', TArchitectureMatrix.Describe(Classify('Atlas.IDE.Undo.Changes'),
    Classify('Atlas.Core.Undo.Providers.FileStore')));
  Assert.AreEqual('eigene Providers aus Contract', TArchitectureMatrix.Describe(
    Classify('Atlas.Common.Logging.Contract'), Classify('Atlas.Common.Logging.Providers.Logger')));
end;

procedure TArchitectureMatrixTests.DescribesNestedAndHostRoles;
begin
  Assert.AreEqual('eigene Sub-Contract aus Root', TArchitectureMatrix.Describe(Classify('Atlas.Common.Server.Sache'),
    Classify('Atlas.Common.Server.Providers.Cache.Contract')));
  Assert.AreEqual('eigene Internals einer Struktur aus Providers', TArchitectureMatrix.Describe(
    Classify('Atlas.Common.Server.Providers.User'), Classify('Atlas.Common.Server.Providers.Cache.Internals.X')));
  Assert.AreEqual('eigene verschachtelte Composition aus Root', TArchitectureMatrix.Describe(
    Classify('Atlas.IDE.Tracker.Sache'), Classify('Atlas.IDE.Tracker.Composition.Adapters')));
  Assert.AreEqual('eigene Adapters aus Root', TArchitectureMatrix.Describe(Classify('Atlas.IDE.Tracker.Composition'),
    Classify('Atlas.IDE.Tracker.Composition.Adapters')), 'innen relativ zum Träger Composition');
  Assert.AreEqual('fremde Providers aus Host-Core', TArchitectureMatrix.Describe(Classify('Core.Settings'),
    Classify('Atlas.Common.Logging.Providers.Logger')));
  Assert.AreEqual('fremde Host-Shell aus Host-Core', TArchitectureMatrix.Describe(Classify('Core.Settings'),
    Classify('Shell.Main')));
end;

const
  cDomainKeys = '"prefixes": ["Atlas.Plugin", "Atlas.IDE.Base", "Atlas.IDE.Modul", "Atlas.IDE.Andere", ' +
    '"Atlas.IDE.Alt"], "domainPackages": ["Atlas.IDE.Base", "Atlas.IDE.Modul", "Atlas.IDE.Andere", ' +
    '"Atlas.IDE.Alt"], "basePackage": "Atlas.IDE.Base", "layerPrefixes": ["Atlas.Core", "Atlas.IDE"], ' +
    '"layerPackages": ["Atlas.IDE.Alt"], "frameworks": ["Vcl", "ToolsAPI"]';

function DomainOptions: TRoleImportOptions;
begin
  Result := TRoleImportRule.ParseOptions('{ ' + cDomainKeys + ' }');
end;

procedure TArchitectureMatrixTests.ClassifiesDomainPackage;
var
  U: TArchitectureUnit;
begin
  // Host-Rolle im Fachcode-Package (Konzept 8.1).
  U := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Shell.Composition', DomainOptions);
  Assert.AreEqual(Ord(TArchitectureRole.Host), Ord(U.Role));
  Assert.AreEqual('Shell', U.Feature);
  Assert.AreEqual('Atlas.IDE.Modul', U.Package);
  Assert.AreEqual('Atlas.IDE.Base', U.BasePackage);
  Assert.IsFalse(U.Hosted);
  // Hosted-Feature des Packages (8.2), Rolle wie bei jedem Feature.
  U := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Topics.Hosting.Pages', DomainOptions);
  Assert.IsTrue(U.Hosted);
  Assert.AreEqual('Atlas.IDE.Modul', U.Artefact);
  Assert.AreEqual('Topics', U.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Hosting), Ord(U.Role));
  // Platform-Feature und Framework.
  U := TArchitectureMatrix.ClassifySource('Atlas.Plugin.Files.Watcher', DomainOptions);
  Assert.AreEqual('', U.Package);
  Assert.IsFalse(U.Hosted);
  U := TArchitectureMatrix.ClassifySource('ToolsAPI.Editor', DomainOptions);
  Assert.IsTrue(U.Framework);
  Assert.IsFalse(U.Known);
  Assert.IsFalse(TArchitectureMatrix.ClassifySource('VclTee.Chart', DomainOptions).Framework);
end;

procedure TArchitectureMatrixTests.ClassifiesLayerPackageAndTargets;
var
  mSource, mTarget: TArchitectureUnit;
begin
  // Ein Package aus "layerPackages" heißt noch nach Schichten: Atlas.IDE ist das Präfix, Alt das Feature.
  mSource := TArchitectureMatrix.ClassifySource('Atlas.IDE.Alt.Composition', DomainOptions);
  Assert.IsTrue(mSource.Layer);
  Assert.AreEqual('Atlas.IDE', mSource.Artefact);
  Assert.AreEqual('Alt', mSource.Feature);
  Assert.AreEqual(Ord(TArchitectureRole.Composition), Ord(mSource.Role));
  // Seine Ziele ebenso, auch mit dem Präfix eines umgestellten Packages.
  mTarget := TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.IDE.Base.Foundation.Probe', DomainOptions);
  Assert.IsTrue(mTarget.Layer);
  Assert.AreEqual('Base', mTarget.Feature);
  // Aus einem Fachcode-Package: ein Schichtname ist ein Hosted-Feature von Base, auch mit dem Präfix eines
  // Packages aus "layerPackages" (Atlas.IDE.Editor.* in Base vor dem Modul Editor).
  mSource := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Topics.Links', DomainOptions);
  mTarget := TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.IDE.Alt.Foundation.Sache', DomainOptions);
  Assert.IsTrue(mTarget.Layer);
  Assert.AreEqual('Atlas.IDE.Base', mTarget.Package);
  Assert.IsTrue(mTarget.Hosted);
  Assert.AreEqual('Alt', mTarget.Feature);
  mTarget := TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.Core.Settings.Contract', DomainOptions);
  Assert.AreEqual('Atlas.IDE.Base', mTarget.Package);
  Assert.IsTrue(mTarget.Hosted);
  Assert.AreEqual(Ord(TArchitectureRole.Contract), Ord(mTarget.Role));
  // Aus einem Platform-Feature: umgestellte Fachcode-Packages nach ihrem Präfix, die übrigen nach Schichtnamen.
  mSource := TArchitectureMatrix.ClassifySource('Atlas.Plugin.Files.Watcher', DomainOptions);
  Assert.AreEqual('Atlas.IDE.Modul', TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.IDE.Modul.Sache',
    DomainOptions).Package);
  Assert.AreEqual('', TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.IDE.Alt.Sache', DomainOptions).Package);
end;

procedure TArchitectureMatrixTests.ClassifiesBaseBeforeSwitch;
var
  mOptions: TRoleImportOptions;
  mSource, mTarget: TArchitectureUnit;
begin
  // Base steht noch in "layerPackages", hat aber schon Units mit seinem Namen (Foundation): Als Ziel aus einem
  // umgestellten Modul gilt sein Präfix, als Quelle noch der Schichtname.
  mOptions := TRoleImportRule.ParseOptions('{ "prefixes": ["Atlas.IDE.Base", "Atlas.IDE.Modul"], ' +
    '"domainPackages": ["Atlas.IDE.Base", "Atlas.IDE.Modul"], "basePackage": "Atlas.IDE.Base", ' +
    '"layerPrefixes": ["Atlas.IDE"], "layerPackages": ["Atlas.IDE.Base"] }');
  mSource := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Topics.Links', mOptions);
  mTarget := TArchitectureMatrix.ClassifyTarget(mSource, 'Atlas.IDE.Base.Foundation.Probe', mOptions);
  Assert.AreEqual('Atlas.IDE.Base', mTarget.Package);
  Assert.AreEqual(Ord(TArchitectureRole.Host), Ord(mTarget.Role));
  Assert.IsTrue(TArchitectureMatrix.Allowed(mSource, mTarget));
  Assert.IsTrue(TArchitectureMatrix.ClassifySource('Atlas.IDE.Base.Foundation.Probe', mOptions).Layer);
end;

procedure TArchitectureMatrixTests.DescribesDomainPackage;
var
  mSource: TArchitectureUnit;

  function DescribeTarget(const ATarget: string): string;
  begin
    Result := TArchitectureMatrix.Describe(mSource, TArchitectureMatrix.ClassifyTarget(mSource, ATarget,
      DomainOptions));
  end;

begin
  mSource := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Topics.Links', DomainOptions);
  Assert.AreEqual('Framework aus Root; nur Hosting und Host-Rollen binden es ein', DescribeTarget('Vcl.Forms'));
  Assert.AreEqual('Fachcode-Package Atlas.IDE.Andere aus Root', DescribeTarget('Atlas.IDE.Andere.Topics.Contract'));
  Assert.AreEqual('fremdes Hosted-Feature Atlas.Core.Settings aus Root', DescribeTarget('Atlas.Core.Settings.Contract'));
  Assert.AreEqual('fremdes Hosted-Feature Atlas.IDE.Modul.Pages aus Root', DescribeTarget('Atlas.IDE.Modul.Pages.Contract'));
  Assert.AreEqual('fremde Host-Core aus Root', DescribeTarget('Atlas.IDE.Base.Core.Probe'));
  mSource := TArchitectureMatrix.ClassifySource('Atlas.IDE.Modul.Core.Run', DomainOptions);
  Assert.AreEqual('fremde Host-Shell aus Host-Core', DescribeTarget('Atlas.IDE.Base.Shell.Register'));
  mSource := TArchitectureMatrix.ClassifySource('Atlas.Plugin.Files.Watcher', DomainOptions);
  Assert.AreEqual('Fachcode-Package Atlas.IDE.Base aus Root', DescribeTarget('Atlas.IDE.Base.Foundation.Probe'));
end;

{ TRoleImportRuleTests }

const
  cRoleConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", "prefixes": ["Atlas.Common"] } } }';
  cRoleSource =
    'unit Atlas.Common.Logging.Contract;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Atlas.Common.Logging.Providers.Logger;'#10 +
    'implementation'#10 +
    'end.';

{ TRoleImportRuleTests }

procedure TRoleImportRuleTests.ReportsForbiddenImportAtUsesEntry;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TRoleImportRule.Create, cRoleSource, cRoleConfig,
    'Source/Atlas.Common.Logging.Contract.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(22, mFindings[0].Range.StartPos.Character);
  Assert.IsTrue(Pos('eigene Providers aus Contract', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
end;

procedure TRoleImportRuleTests.AllowsOwnContractAndForeignRoot;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Logging.Providers.Logger;'#10'interface'#10 +
    'uses Atlas.Common.Logging.Contract, Atlas.Common.Index.Files, Atlas.Common.Index.Contract;'#10 +
    'implementation'#10'end.', cRoleConfig, 'Source/x.pas'))));
end;

procedure TRoleImportRuleTests.SilentWithoutPrefixes;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, cRoleSource,
    '{ "rules": { "architecture-role-import": "warning" } }', 'Source/x.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, cRoleSource, '', 'Source/x.pas'))),
    'experimentell: ohne Konfiguration aus');
end;

procedure TRoleImportRuleTests.ApprovedExceptionIsSilent;
const
  cConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", "prefixes": ["Atlas.Common"], ' +
    '"allow": ["Atlas.Common.Rules.Contract -> Atlas.Common.Pascal.SyntaxTree"] } } }';
  cSource = 'unit Atlas.Common.Rules.Contract;'#10'interface'#10'uses Atlas.Common.Pascal.SyntaxTree;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, cSource, cConfig, 'Source/x.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, cSource, cRoleConfig,
    'Source/x.pas'))));
  Assert.IsTrue(TRoleImportRule.Approved(['Atlas.IDE.* -> Atlas.Core.*'], 'Atlas.IDE.Undo.Changes',
    'Atlas.Core.Undo.Providers.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['Atlas.IDE.* -> Atlas.Core.*'], 'Atlas.UI.Undo.Changes',
    'Atlas.Core.Undo.Providers.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['ohne Pfeil'], 'A', 'B'));
end;

procedure TRoleImportRuleTests.ApprovedExceptionNeverCoversInternals;
const
  cConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", ' +
    '"prefixes": ["Atlas.Core", "Atlas.IDE"], "allow": ["Atlas.IDE.Alpha.Composition -> Atlas.Core.*"] } } }';
  cSource = 'unit Atlas.IDE.Alpha.Composition;'#10'interface'#10 +
    'uses Atlas.Core.Beta.Providers.Store, Atlas.Core.Beta.Internals.Cache, Atlas.Core.Beta.Providers.Cache.Internals.X;'#10 +
    'implementation'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Der Platzhalter trifft alle drei; frei wird nur der Provider.
  Assert.IsTrue(TRoleImportRule.Approved(['Atlas.IDE.Alpha.Composition -> Atlas.Core.*'],
    'Atlas.IDE.Alpha.Composition', 'Atlas.Core.Beta.Internals.Cache'));
  mFindings := TRuleAssert.Findings(TRoleImportRule.Create, cSource, cConfig, 'Source/x.pas');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('Atlas.Core.Beta.Internals.Cache', mFindings[0].Message) > 0);
  Assert.IsTrue(Pos('Atlas.Core.Beta.Providers.Cache.Internals.X', mFindings[1].Message) > 0);
end;

procedure TRoleImportRuleTests.ChecksImplementationUses;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Lsp.Hover;'#10'interface'#10'implementation'#10 +
    'uses Atlas.Common.Index.Internals.Table;'#10'end.', cRoleConfig, 'Source/x.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('fremde Internals aus Root', mFindings[0].Message) > 0, mFindings[0].Message);
end;

procedure TRoleImportRuleTests.ChecksHostedFeature;
const
  cConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", ' +
    '"prefixes": ["Atlas.Common"], "hostedFeatures": ["Gamma", "Delta"] } } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Nach außen nur Foundation und Platform-Features; nie Host-Core oder ein anderes Hosted-Feature (8.2).
  mFindings := TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Gamma.Session;'#10'interface'#10 +
    'uses Foundation.Values, Atlas.Common.Logging.Contract, Gamma.Internals.Table, Core.Workspace, ' +
    'Delta.Contract;'#10'implementation'#10'end.', cConfig, 'Source/x.pas');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('Core.Workspace', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.IsTrue(Pos('Delta.Contract', mFindings[1].Message) > 0, mFindings[1].Message);
  // Host-Core sieht kein Hosted-Feature, die Shell schon.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Core.Workspace;'#10'interface'#10'uses Gamma.Contract;'#10'implementation'#10'end.', cConfig,
    'Source/x.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Shell.Composition;'#10'interface'#10'uses Gamma.Providers.Store;'#10'implementation'#10'end.', cConfig,
    'Source/x.pas'))));
end;

procedure TRoleImportRuleTests.PackageContainsIsNoImport;
begin
  // contains nimmt Units ins Package auf (#1109); dieselbe Unit im uses eines Programms wäre ein Import.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'package Atlas.Common.Lsp;'#10'requires rtl;'#10'contains'#10 +
    '  Atlas.Common.Index.Internals.Table in ''Table.pas'';'#10'end.', cRoleConfig, 'Atlas.Common.Lsp.dpk'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'program Atlas.Common.Lsp;'#10'uses'#10'  Atlas.Common.Index.Internals.Table in ''Table.pas'';'#10 +
    'begin'#10'end.', cRoleConfig, 'Atlas.Common.Lsp.dpr'))));
end;

procedure TRoleImportRuleTests.TestUnitIsSilent;
begin
  // Die Testunit trägt den Namen der getesteten Contract-Unit, gehört aber zu keiner Rolle.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Logging.Contract.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10 +
    'implementation'#10'uses Atlas.Common.Logging.Providers.Logger;'#10'end.', cRoleConfig, 'Tests/x.pas'))));
end;

procedure TRoleImportRuleTests.ParsesOptions;
var
  mOptions: TRoleImportOptions;
begin
  mOptions := TRoleImportRule.ParseOptions('{ "prefixes": ["A"], "allow": ["x -> y"], "other": 1 }');
  Assert.AreEqual(1, Integer(Length(mOptions.Prefixes)));
  Assert.AreEqual(1, Integer(Length(mOptions.Allow)));
  Assert.AreEqual(5, Integer(Length(mOptions.HostRoles)), 'Vorgabe der Host-Rollen');
  Assert.AreEqual(0, Integer(Length(mOptions.HostedFeatures)), 'ohne Hosted-Features');
  mOptions := TRoleImportRule.ParseOptions('{ "hostRoles": ["App"], "hostedFeatures": ["Gamma", "Delta"] }');
  Assert.AreEqual(1, Integer(Length(mOptions.HostRoles)));
  Assert.AreEqual(2, Integer(Length(mOptions.HostedFeatures)));
  Assert.AreEqual(0, Integer(Length(TRoleImportRule.ParseOptions('kein json').Prefixes)));
  mOptions := DomainOptions;
  Assert.AreEqual(4, Integer(Length(mOptions.DomainPackages)));
  Assert.AreEqual('Atlas.IDE.Base', mOptions.BasePackage);
  Assert.AreEqual(2, Integer(Length(mOptions.LayerPrefixes)));
  Assert.AreEqual(1, Integer(Length(mOptions.LayerPackages)));
  Assert.AreEqual(2, Integer(Length(mOptions.Frameworks)));
end;

procedure TRoleImportRuleTests.ChecksDomainPackage;
const
  cConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", ' + cDomainKeys + ' } } }';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Feature eines Moduls: von Base nur Foundation, kein anderes Feature, kein Framework außerhalb von Hosting.
  mFindings := TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.IDE.Modul.Topics.Links;'#10'interface'#10 +
    'uses Vcl.Forms, Atlas.IDE.Base.Foundation.Probe, Atlas.IDE.Base.Core.Probe, Atlas.Core.Settings.Contract, ' +
    'Atlas.IDE.Modul.Pages.Contract, Atlas.IDE.Modul.Topics.Contract, Atlas.Plugin.Files.Watcher;'#10 +
    'implementation'#10'end.', cConfig, 'Source/x.pas');
  Assert.AreEqual(4, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('Vcl.Forms', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.IsTrue(Pos('Atlas.IDE.Base.Core.Probe', mFindings[1].Message) > 0, mFindings[1].Message);
  Assert.IsTrue(Pos('Atlas.Core.Settings.Contract', mFindings[2].Message) > 0, mFindings[2].Message);
  Assert.IsTrue(Pos('Atlas.IDE.Modul.Pages.Contract', mFindings[3].Message) > 0, mFindings[3].Message);
  // Hosting kapselt das Framework; die Shell des Moduls sieht Host-Rollen und Features von Base.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.IDE.Modul.Topics.Hosting.Pages;'#10'interface'#10'uses Vcl.Forms, ToolsAPI, ' +
    'Atlas.IDE.Modul.Topics.Contract;'#10'implementation'#10'end.', cConfig, 'Source/x.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.IDE.Modul.Shell.Composition;'#10'interface'#10'uses Atlas.IDE.Base.Core.Probe, ' +
    'Atlas.Core.Settings.Store, Atlas.IDE.Modul.Topics.Providers.Store;'#10'implementation'#10'end.', cConfig,
    'Source/x.pas'))));
  // Ein Package aus "layerPackages" prüft die alte Regel.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.IDE.Alt.Composition;'#10'interface'#10'uses Vcl.Forms, Atlas.IDE.Base.Foundation.Probe;'#10 +
    'implementation'#10'end.', cConfig, 'Source/x.pas'))));
end;

{ TContractContentRuleTests }

const
  cContractConfig =
    '{ "rules": { "architecture-contract-content": { "severity": "warning", "prefixes": ["App"] } } }';

function ContractFindings(const ASource: string; const AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TContractContentRule.Create, ASource, AConfig, 'Source/x.pas');
end;

function ContractFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := ContractFindings(ASource, cContractConfig);
end;

{ TContractContentRuleTests }

procedure TContractContentRuleTests.ReportsClassInContract;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := ContractFindings('unit App.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(12, mFindings[0].Range.EndPos.Character);
  Assert.IsTrue(Pos('TOrderList', mFindings[0].Message) > 0);
end;

procedure TContractContentRuleTests.AllowsExceptionsAndInterfaces;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract;'#10'interface'#10 +
    'uses System.SysUtils;'#10'type'#10 +
    '  EOrder = class(Exception);'#10 +
    '  EOrderMissing = class(EOrder);'#10 +
    '  IOrderList = interface'#10'  end;'#10 +
    '  TOrder = record'#10'    function Total: Integer;'#10'  end;'#10 +
    '  TOrderKind = (Sale, Refund);'#10 +
    '  TOrderClass = class of TObject;'#10 +
    'implementation'#10'function TOrder.Total: Integer; begin Result := 0; end;'#10'end.'))));
end;

procedure TContractContentRuleTests.IgnoresImplementationSection;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract;'#10'interface'#10 +
    'implementation'#10'type'#10'  THidden = class'#10'  end;'#10'end.'))));
end;

procedure TContractContentRuleTests.IgnoresNonContractUnit;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Store;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.'))));
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit Other.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.'))), 'ohne passendes Präfix');
end;

procedure TContractContentRuleTests.IgnoresTestUnitOfContract;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract.Tests;'#10'interface'#10 +
    'uses DUnitX.TestFramework;'#10'type'#10'  [TestFixture]'#10'  TOrderTests = class'#10'  end;'#10 +
    'implementation'#10'end.'))));
end;

procedure TContractContentRuleTests.ForwardDeclarationIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrder = class;'#10'  IOrders = interface'#10'    function First: TOrder;'#10'  end;'#10 +
    'implementation'#10'end.'))));
end;

procedure TContractContentRuleTests.ApprovedTypeIsSilent;
const
  cConfig = '{ "rules": { "architecture-contract-content": { "severity": "warning", "prefixes": ["App"], ' +
    '"allow": ["App.Orders.Contract.TOrder*"] } } }';
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.', cConfig))));
end;

procedure TContractContentRuleTests.ChecksRoleAfterThingAndSubContract;
begin
  Assert.AreEqual(1, Integer(Length(ContractFindings('unit App.Orders.Lines.Contract;'#10'interface'#10'type'#10 +
    '  TLineList = class'#10'  end;'#10'implementation'#10'end.'))), 'Rolle an dritter Stelle');
  Assert.AreEqual(1, Integer(Length(ContractFindings('unit App.Orders.Providers.Cache.Contract;'#10'interface'#10 +
    'type'#10'  TCacheList = class'#10'  end;'#10'implementation'#10'end.'))), 'Sub-Contract');
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract.Internals.Lists;'#10'interface'#10 +
    'type'#10'  TOrderList = class'#10'  end;'#10'implementation'#10'end.'))), 'Internals einer Struktur');
end;

procedure TContractContentRuleTests.ChecksContractOfDomainPackage;
const
  cConfig = '{ "rules": { "architecture-contract-content": { "severity": "warning", "prefixes": ["App.Modul"], ' +
    '"domainPackages": ["App.Modul"] } } }';
begin
  Assert.AreEqual(1, Integer(Length(ContractFindings('unit App.Modul.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.', cConfig))), 'Contract eines Hosted-Features');
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Modul.Foundation.Orders;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.', cConfig))), 'Host-Rolle, kein Contract');
end;

initialization
  TDUnitX.RegisterTestFixture(TForbiddenUsesRuleTests);
  TDUnitX.RegisterTestFixture(TArchitectureMatrixTests);
  TDUnitX.RegisterTestFixture(TRoleImportRuleTests);
  TDUnitX.RegisterTestFixture(TContractContentRuleTests);

end.
