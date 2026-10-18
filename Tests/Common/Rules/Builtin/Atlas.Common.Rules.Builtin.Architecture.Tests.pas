unit Atlas.Common.Rules.Builtin.Architecture.Tests;

// Tests für die Architekturregeln forbidden-uses (#183), architecture-role-import
// und architecture-contract-content (Code-Review A-12). Die Matrix prüft
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
  Config =
    '{ "rules": { "forbidden-uses": { "layers": [' +
    '{ "from": "*.Common.*", "deny": ["Vcl.*", "Winapi.*"], "allow": ["Winapi.Windows"] },' +
    '{ "from": "Source/Windows/**", "deny": ["Vcl.*"] } ] } } }';
  Source =
    'unit App.Common.Model;'#10 +
    'interface'#10 +
    'uses System.Classes, Vcl.Forms, Winapi.Windows;'#10 +
    'implementation'#10 +
    'uses Winapi.Messages;'#10 +
    'end.';

procedure TForbiddenUsesRuleTests.ReportsDeniedUnitByUnitName;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TForbiddenUsesRule.Create, Source, Config, 'Source/App.Common.Model.pas');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(2, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(21, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(30, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(Pos('Vcl.Forms', Findings[0].Message) > 0, True);
  Assert.AreEqual(4, Findings[1].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
end;

procedure TForbiddenUsesRuleTests.AllowOverridesDeny;
var
  Finding: TRuleFinding;
begin
  for Finding in TRuleAssert.Findings(TForbiddenUsesRule.Create, Source, Config, 'Source/App.Common.Model.pas') do
    Assert.AreEqual(0, Pos('Winapi.Windows', Finding.Message));
end;

procedure TForbiddenUsesRuleTests.MatchesLayerByPath;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TForbiddenUsesRule.Create,
    'unit Fenster;'#10'interface'#10'uses Vcl.Controls, Winapi.Windows;'#10'implementation'#10'end.', Config,
    'Source/Windows/Fenster.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
end;

procedure TForbiddenUsesRuleTests.SilentWithoutLayers;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForbiddenUsesRule.Create, Source, '',
    'Source/App.Common.Model.pas'))));
end;

procedure TForbiddenUsesRuleTests.IgnoresInvalidLayers;
var
  Layers: TArray<TArchitectureLayer>;
begin
  Layers := TForbiddenUsesRule.ParseLayers('{ "layers": [ { "deny": ["X"] }, { "from": "A", "deny": [] }, ' +
    '{ "from": "B", "deny": ["Y", 3] } ] }');
  Assert.AreEqual(1, Integer(Length(Layers)));
  Assert.AreEqual('B', Layers[0].From);
  Assert.AreEqual(1, Integer(Length(Layers[0].Deny)));
  Assert.AreEqual(0, Integer(Length(TForbiddenUsesRule.ParseLayers('kein json'))));
end;

{ TArchitectureMatrixTests }

const
  Prefixes: array[0..5] of string = ('Atlas.Text', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core', 'Atlas.UI',
    'Atlas.IDE');

function PrefixList: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Prefixes));
  for Index := 0 to High(Prefixes) do
    Result[Index] := Prefixes[Index];
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
  Directory: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    Result := TPath.Combine(Directory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Architecture', 'role-imports.json'))));
    if TFile.Exists(Result) then
      Exit;
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  Result := '';
end;

function JsonStrings(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  Item: TJSONValue;
begin
  Result := nil;
  for Item in AObject.GetValue<TJSONArray>(AName) do
    Result := Result + [Item.Value];
end;

procedure TArchitectureMatrixTests.MatrixCasesFromFile;
var
  FileName: string;
  Root: TJSONValue;
  Data: TJSONObject;
  Item: TJSONValue;
  Case_: TJSONObject;
  CasePrefixes, CaseHosts: TArray<string>;
  Source, Target: TArchitectureUnit;
  Count: Integer;
begin
  FileName := RoleImportsFile;
  Assert.AreNotEqual('', FileName, 'Tests\Data\Architecture\role-imports.json nicht gefunden');
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8));
  try
    Assert.IsTrue(Root is TJSONObject);
    Data := TJSONObject(Root);
    CasePrefixes := JsonStrings(Data, 'prefixes');
    CaseHosts := JsonStrings(Data, 'hostRoles');
    Count := 0;
    for Item in Data.GetValue<TJSONArray>('cases') do
    begin
      Case_ := Item as TJSONObject;
      Source := TArchitectureMatrix.Classify(Case_.GetValue<string>('from'), CasePrefixes, CaseHosts);
      Target := TArchitectureMatrix.Classify(Case_.GetValue<string>('to'), CasePrefixes, CaseHosts);
      Assert.AreEqual(Case_.GetValue<Boolean>('allowed'), TArchitectureMatrix.Allowed(Source, Target),
        Case_.GetValue<string>('from') + ' -> ' + Case_.GetValue<string>('to'));
      Inc(Count);
    end;
    Assert.IsTrue(Count > 100, 'Fallliste unvollständig');
  finally
    Root.Free;
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
  RoleConfig = '{ "rules": { "architecture-role-import": { "severity": "warning", "prefixes": ["Atlas.Common"] } } }';
  RoleSource =
    'unit Atlas.Common.Logging.Contract;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Atlas.Common.Logging.Providers.Logger;'#10 +
    'implementation'#10 +
    'end.';

procedure TRoleImportRuleTests.ReportsForbiddenImportAtUsesEntry;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRoleImportRule.Create, RoleSource, RoleConfig,
    'Source/Atlas.Common.Logging.Contract.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(2, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(22, Findings[0].Range.StartPos.Character);
  Assert.IsTrue(Pos('eigene Providers aus Contract', Findings[0].Message) > 0, Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TRoleImportRuleTests.AllowsOwnContractAndForeignRoot;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Logging.Providers.Logger;'#10'interface'#10 +
    'uses Atlas.Common.Logging.Contract, Atlas.Common.Index.Files, Atlas.Common.Index.Contract;'#10 +
    'implementation'#10'end.', RoleConfig, 'Source/x.pas'))));
end;

procedure TRoleImportRuleTests.SilentWithoutPrefixes;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, RoleSource,
    '{ "rules": { "architecture-role-import": "warning" } }', 'Source/x.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, RoleSource, '', 'Source/x.pas'))),
    'experimentell: ohne Konfiguration aus');
end;

procedure TRoleImportRuleTests.ApprovedExceptionIsSilent;
const
  Config = '{ "rules": { "architecture-role-import": { "severity": "warning", "prefixes": ["Atlas.Common"], ' +
    '"allow": ["Atlas.Common.Rules.Contract -> Atlas.Common.Pascal.SyntaxTree"] } } }';
  Source = 'unit Atlas.Common.Rules.Contract;'#10'interface'#10'uses Atlas.Common.Pascal.SyntaxTree;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, Source, Config, 'Source/x.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRoleImportRule.Create, Source, RoleConfig,
    'Source/x.pas'))));
  Assert.IsTrue(TRoleImportRule.Approved(['Atlas.IDE.* -> Atlas.Core.*'], 'Atlas.IDE.Undo.Changes',
    'Atlas.Core.Undo.Adapters.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['Atlas.IDE.* -> Atlas.Core.*'], 'Atlas.UI.Undo.Changes',
    'Atlas.Core.Undo.Adapters.FileStore'));
  Assert.IsFalse(TRoleImportRule.Approved(['ohne Pfeil'], 'A', 'B'));
end;

procedure TRoleImportRuleTests.ChecksImplementationUses;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TRoleImportRule.Create,
    'unit Atlas.Common.Lsp.Hover;'#10'interface'#10'implementation'#10 +
    'uses Atlas.Common.Index.Internals.Table;'#10'end.', RoleConfig, 'Source/x.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('fremde Internals aus Root', Findings[0].Message) > 0, Findings[0].Message);
end;

procedure TRoleImportRuleTests.ParsesOptions;
var
  Options: TRoleImportOptions;
begin
  Options := TRoleImportRule.ParseOptions('{ "prefixes": ["A"], "allow": ["x -> y"], "other": 1 }');
  Assert.AreEqual(1, Integer(Length(Options.Prefixes)));
  Assert.AreEqual(1, Integer(Length(Options.Allow)));
  Assert.AreEqual(5, Integer(Length(Options.HostRoles)), 'Vorgabe der Host-Rollen');
  Options := TRoleImportRule.ParseOptions('{ "hostRoles": ["App"] }');
  Assert.AreEqual(1, Integer(Length(Options.HostRoles)));
  Assert.AreEqual(0, Integer(Length(TRoleImportRule.ParseOptions('kein json').Prefixes)));
end;

{ TContractContentRuleTests }

const
  ContractConfig =
    '{ "rules": { "architecture-contract-content": { "severity": "warning", "prefixes": ["App"] } } }';

function ContractFindings(const ASource: string; const AConfig: string = ContractConfig): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TContractContentRule.Create, ASource, AConfig, 'Source/x.pas');
end;

procedure TContractContentRuleTests.ReportsClassInContract;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := ContractFindings('unit App.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(12, Findings[0].Range.EndPos.Character);
  Assert.IsTrue(Pos('TOrderList', Findings[0].Message) > 0);
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
  Config = '{ "rules": { "architecture-contract-content": { "severity": "warning", "prefixes": ["App"], ' +
    '"allow": ["App.Orders.Contract.TOrder*"] } } }';
begin
  Assert.AreEqual(0, Integer(Length(ContractFindings('unit App.Orders.Contract;'#10'interface'#10'type'#10 +
    '  TOrderList = class'#10'  end;'#10'implementation'#10'end.', Config))));
end;

initialization
  TDUnitX.RegisterTestFixture(TForbiddenUsesRuleTests);
  TDUnitX.RegisterTestFixture(TArchitectureMatrixTests);
  TDUnitX.RegisterTestFixture(TRoleImportRuleTests);
  TDUnitX.RegisterTestFixture(TContractContentRuleTests);

end.
