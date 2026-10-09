unit Argus.Common.Rules.Builtin.Architecture.Tests;

// Tests für die Architekturregel forbidden-uses (#183).

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

implementation

uses
  System.SysUtils,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Builtin.Architecture,
  Argus.Tests.RuleAssert;

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

initialization
  TDUnitX.RegisterTestFixture(TForbiddenUsesRuleTests);

end.
