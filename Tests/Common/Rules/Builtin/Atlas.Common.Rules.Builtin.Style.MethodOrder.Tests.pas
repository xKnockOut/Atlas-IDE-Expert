unit Atlas.Common.Rules.Builtin.Style.MethodOrder.Tests;

// Tests der Regel method-order (#1840): geordnete Rümpfe ohne Befund, ungeordnete mit Befund am Typnamen und
// Korrektur, die nur diesen Typ ordnet; Rümpfe in einer Region bleiben ohne Befund; fehlender Typkommentar mit
// Korrektur; classCompletion.typeComment off und placement off schweigen; Standard aus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodOrderRuleTests = class
  public
    [Test]
    procedure OrderedIsSilent;
    [Test]
    procedure DisorderedTypeIsReportedAndArranged;
    [Test]
    procedure RegionBodyIsNotWrong;
    [Test]
    procedure MissingCommentIsReportedAndInserted;
    [Test]
    procedure LineCommentIsInsertedInItsForm;
    [Test]
    procedure TypeCommentOffIsSilent;
    [Test]
    procedure PlacementOffIsSilent;
    [Test]
    procedure PlacementOptionIsUsed;
    [Test]
    procedure OffByDefault;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Style.MethodOrder,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  cEnabled = '{ "rules": { "method-order": "hint" } }';
  cKopf =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    constructor Create;'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '  end;'#10 +
    '  TBar = class'#10 +
    '    procedure X;'#10 +
    '  end;'#10 +
    'implementation'#10;
  cEnde = #10'end.';

function Rule: IRule;
begin
  Result := TMethodOrderRule.Create;
end;

function Body(const AName: string): string;
begin
  Result := #10 + AName + ';'#10'begin'#10'end;'#10;
end;

function Foo(const ANames: array of string): string;
var
  mName: string;
begin
  Result := #10'{ TFoo }'#10;
  for mName in ANames do
  begin
    Result := Result + Body(mName);
  end;
end;

function Bar: string;
begin
  Result := #10'{ TBar }'#10 + Body('procedure TBar.X');
end;

function Fixed(const ASource: string; const AFix: TRuleFix): string;
begin
  Result := TChangeSignature.ApplyEdits(ASource, AFix.Edits);
end;

{ TMethodOrderRuleTests }

procedure TMethodOrderRuleTests.OrderedIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cKopf +
    Foo(['constructor TFoo.Create', 'procedure TFoo.A', 'procedure TFoo.B']) + Bar + cEnde, cEnabled))));
end;

procedure TMethodOrderRuleTests.DisorderedTypeIsReportedAndArranged;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // TBar steht vor TFoo: zwischen den Typen ordnet die Regel nicht, nur innerhalb von TFoo.
  mSource := cKopf + Bar + Foo(['procedure TFoo.B', 'constructor TFoo.Create', 'procedure TFoo.A']) + cEnde;
  mFound := TRuleAssert.Findings(Rule, mSource, cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('method-order', mFound[0].RuleId);
  Assert.AreEqual('Methodenrümpfe von TFoo stehen nicht in der Klassenordnung (gruppiert)', mFound[0].Message);
  // Zeile 21 (ab 0): procedure TFoo.B hinter cKopf (12 Zeilen), { TBar } mit Rumpf und { TFoo }.
  Assert.AreEqual(21, mFound[0].Range.StartPos.Line, 'am Typnamen im ersten Rumpf');
  Assert.AreEqual(10, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(14, mFound[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Rümpfe von TFoo ordnen', mFound[0].Fixes[0].Title);
  Assert.AreEqual(cKopf + Bar + Foo(['constructor TFoo.Create', 'procedure TFoo.A', 'procedure TFoo.B']) + cEnde,
    Fixed(mSource, mFound[0].Fixes[0]));
end;

procedure TMethodOrderRuleTests.RegionBodyIsNotWrong;
var
  mSource: string;
begin
  // TFoo.B steht vor TFoo.A, aber in einer Region und bleibt beim Ordnen stehen; die übrigen passen.
  mSource := cKopf + Foo(['constructor TFoo.Create']) + #10'{$REGION ''Alt''}' + Body('procedure TFoo.B') +
    '{$ENDREGION}'#10 + Body('procedure TFoo.A') + Bar + cEnde;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, mSource, cEnabled))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(Rule, StringReplace(StringReplace(mSource,
    '{$REGION ''Alt''}', '', []), '{$ENDREGION}', '', []), cEnabled))), 'ohne Region: Befund');
end;

procedure TMethodOrderRuleTests.MissingCommentIsReportedAndInserted;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := cKopf + Foo(['constructor TFoo.Create', 'procedure TFoo.A', 'procedure TFoo.B']) +
    Body('procedure TBar.X') + cEnde;
  mFound := TRuleAssert.Findings(Rule, mSource, cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Kommentar { TBar } fehlt', mFound[0].Message);
  Assert.AreEqual('Kommentar { TBar } einfügen', mFound[0].Fixes[0].Title);
  Assert.AreEqual(cKopf + Foo(['constructor TFoo.Create', 'procedure TFoo.A', 'procedure TFoo.B']) + Bar + cEnde,
    Fixed(mSource, mFound[0].Fixes[0]));
end;

procedure TMethodOrderRuleTests.LineCommentIsInsertedInItsForm;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := cKopf + Foo(['constructor TFoo.Create', 'procedure TFoo.A', 'procedure TFoo.B']) +
    Body('procedure TBar.X') + cEnde;
  mFound := TRuleAssert.Findings(Rule, mSource,
    '{ "rules": { "method-order": "hint" }, "classCompletion": { "typeComment": "line" } }');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Kommentar // TBar fehlt', mFound[0].Message);
  Assert.IsTrue(Pos(#10'// TBar'#10, Fixed(mSource, mFound[0].Fixes[0])) > 0, Fixed(mSource, mFound[0].Fixes[0]));
end;

procedure TMethodOrderRuleTests.TypeCommentOffIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cKopf + Body('procedure TBar.X') + cEnde,
    '{ "rules": { "method-order": "hint" }, "classCompletion": { "typeComment": "off" } }'))));
end;

procedure TMethodOrderRuleTests.PlacementOffIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cKopf +
    Foo(['procedure TFoo.B', 'procedure TFoo.A']) + Body('procedure TBar.X') + cEnde,
    '{ "rules": { "method-order": { "severity": "hint", "placement": "off" } } }'))));
end;

procedure TMethodOrderRuleTests.PlacementOptionIsUsed;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  // Alphabetisch ohne Vorziehen des Lebenszyklus: A, B, Create.
  mSource := cKopf + Foo(['procedure TFoo.A', 'procedure TFoo.B', 'constructor TFoo.Create']) + Bar + cEnde;
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, mSource,
    '{ "rules": { "method-order": { "severity": "hint", "placement": "alphabetical" } }, ' +
    '"classCompletion": { "lifecycleFirst": false } }'))));
  mFound := TRuleAssert.Findings(Rule, mSource, cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)), 'gruppiert: Create gehört nach vorn');
end;

procedure TMethodOrderRuleTests.OffByDefault;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cKopf + Foo(['procedure TFoo.B', 'procedure TFoo.A']) +
    Body('procedure TBar.X') + cEnde))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodOrderRuleTests);

end.
