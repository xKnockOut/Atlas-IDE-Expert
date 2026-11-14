unit Atlas.Common.Rules.Builtin.Architecture.Tests;

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
    procedure MatrixCasesFromFile;
    [Test]
    procedure DescribesOwnAndForeign;
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
    procedure ChecksImplementationUses;
    [Test]
    procedure PackageContainsIsNoImport;
    [Test]
    procedure TestUnitIsSilent;
    [Test]
    procedure ParsesOptions;
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
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Architecture,
  Atlas.Tests.RuleAssert;

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
  cPrefixes: array[0..5] of string = ('Atlas.Text', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core', 'Atlas.UI',
    'Atlas.IDE');

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
  Result := TArchitectureMatrix.Classify(AName, PrefixList, TArchitectureMatrix.DefaultHostRoles);
end;

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
  U := TArchitectureMatrix.Classify('Atlas.Core.Lsp.Session', ['Atlas', 'Atlas.Core'], nil);
  Assert.AreEqual('Atlas.Core', U.Artefact);
  Assert.AreEqual('Lsp', U.Feature);
  // Präfix nur an Segmentgrenzen: Atlas.Common ist nicht Atlas.Co + mmon.
  U := TArchitectureMatrix.Classify('Atlas.Common.Lsp.Hover', ['Atlas.Co'], nil);
  Assert.IsFalse(U.Known);
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

function JsonStrings(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  for mItem in AObject.GetValue<TJSONArray>(AName) do
  begin
    Result := Result + [mItem.Value];
  end;
end;

procedure TArchitectureMatrixTests.MatrixCasesFromFile;
var
  mFileName: string;
  mRoot: TJSONValue;
  mData: TJSONObject;
  mItem: TJSONValue;
  mCase_: TJSONObject;
  mCasePrefixes, mCaseHosts: TArray<string>;
  mSource, mTarget: TArchitectureUnit;
  mCount: Integer;
begin
  mFileName := RoleImportsFile;
  Assert.AreNotEqual('', mFileName, 'Tests\Data\Architecture\role-imports.json nicht gefunden');
  mRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(mFileName, TEncoding.UTF8));
  try
    Assert.IsTrue(mRoot is TJSONObject);
    mData := TJSONObject(mRoot);
    mCasePrefixes := JsonStrings(mData, 'prefixes');
    mCaseHosts := JsonStrings(mData, 'hostRoles');
    mCount := 0;
    for mItem in mData.GetValue<TJSONArray>('cases') do
    begin
      mCase_ := mItem as TJSONObject;
      mSource := TArchitectureMatrix.Classify(mCase_.GetValue<string>('from'), mCasePrefixes, mCaseHosts);
      mTarget := TArchitectureMatrix.Classify(mCase_.GetValue<string>('to'), mCasePrefixes, mCaseHosts);
      Assert.AreEqual(mCase_.GetValue<Boolean>('allowed'), TArchitectureMatrix.Allowed(mSource, mTarget),
        mCase_.GetValue<string>('from') + ' -> ' + mCase_.GetValue<string>('to'));
      Inc(mCount);
    end;
    Assert.IsTrue(mCount > 100, 'Fallliste unvollständig');
  finally
    mRoot.Free;
  end;
end;

procedure TArchitectureMatrixTests.DescribesOwnAndForeign;
begin
  Assert.AreEqual('fremde Adapters aus Root', TArchitectureMatrix.Describe(Classify('Atlas.IDE.Undo.Changes'),
    Classify('Atlas.Core.Undo.Adapters.FileStore')));
  Assert.AreEqual('eigene Providers aus Contract', TArchitectureMatrix.Describe(
    Classify('Atlas.Common.Logging.Contract'), Classify('Atlas.Common.Logging.Providers.Logger')));
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

procedure TRoleImportRuleTests.TestUnitIsSilent;
begin
  // Die Testunit trägt den Namen der getesteten Contract-Unit, gehört aber zu keiner Rolle.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Logging.Contract.Tests;'#10'interface'#10'uses DUnitX.TestFramework;'#10 +
    'implementation'#10'uses Atlas.Common.Logging.Providers.Logger;'#10'end.', cRoleConfig, 'Tests/x.pas'))));
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
    'Atlas.Core.Undo.Adapters.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['Atlas.IDE.* -> Atlas.Core.*'], 'Atlas.UI.Undo.Changes',
    'Atlas.Core.Undo.Adapters.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['ohne Pfeil'], 'A', 'B'));
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

procedure TRoleImportRuleTests.ParsesOptions;
var
  mOptions: TRoleImportOptions;
begin
  mOptions := TRoleImportRule.ParseOptions('{ "prefixes": ["A"], "allow": ["x -> y"], "other": 1 }');
  Assert.AreEqual(1, Integer(Length(mOptions.Prefixes)));
  Assert.AreEqual(1, Integer(Length(mOptions.Allow)));
  Assert.AreEqual(5, Integer(Length(mOptions.HostRoles)), 'Vorgabe der Host-Rollen');
  mOptions := TRoleImportRule.ParseOptions('{ "hostRoles": ["App"] }');
  Assert.AreEqual(1, Integer(Length(mOptions.HostRoles)));
  Assert.AreEqual(0, Integer(Length(TRoleImportRule.ParseOptions('kein json').Prefixes)));
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

procedure TContractContentRuleTests.IgnoresTestUnitOfContract;
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract.Tests;'#10'interface'#10 +
    'uses DUnitX.TestFramework;'#10'type'#10'  [TestFixture]'#10'  TOrderTests = class'#10'  end;'#10 +
    'implementation'#10'end.'))));
end;

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

initialization
  TDUnitX.RegisterTestFixture(TForbiddenUsesRuleTests);
  TDUnitX.RegisterTestFixture(TArchitectureMatrixTests);
  TDUnitX.RegisterTestFixture(TRoleImportRuleTests);
  TDUnitX.RegisterTestFixture(TContractContentRuleTests);

end.
