unit Atlas.Common.Rules.Builtin.MethodWithoutSelf.Tests;

// Tests der Regel method-without-self (#686): Treffer samt Korrektur „In
// class-Methode umwandeln“, Methoden mit Feldern bleiben stumm, die Regel ist
// experimentell, schweigt mit refactoring.methodKind aus, bei Ereignissen
// der Formulardatei und bei Methoden von Interfaces, auch geerbten und
// unbekannten (ToolsAPI, IComparer<T> ohne Index).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMethodWithoutSelfRuleTests = class
  public
    [Test]
    procedure ReportsWithClassMethodFix;
    [Test]
    procedure MethodWithFieldIsSilent;
    [Test]
    procedure ExperimentalAndSwitchedOff;
    [Test]
    procedure FormEventIsSilent;
    [Test]
    procedure EventAssignedInCodeIsSilent;
    [Test]
    procedure InterfaceMethodsAreSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.MethodWithoutSelf,
  Atlas.Tests.RuleAssert;

const
  Enabled = '{ "rules": { "method-without-self": "hint" } }';
  Source =
    'unit Rechner;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '  public'#10 +
    '    function Doppelt(A: Integer): Integer;'#10 +
    '    function Wert: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TRechner.Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'function TRechner.Wert: Integer;'#10 +
    'begin'#10 +
    '  Result := FWert;'#10 +
    'end;'#10 +
    'end.';

function Rule: IRule;
begin
  Result := TMethodWithoutSelfRule.Create;
end;

procedure TMethodWithoutSelfRuleTests.ReportsWithClassMethodFix;
var
  Found: TArray<TRuleFinding>;
  Edit: TTextEdit;
  Inserted: string;
begin
  Found := TRuleAssert.Findings(Rule, Source, Enabled);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('method-without-self', Found[0].RuleId);
  Assert.AreEqual(11, Found[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('TRechner.Doppelt', Found[0].Message) > 0, Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In class-Methode umwandeln', Found[0].Fixes[0].Title);
  Assert.IsFalse(Found[0].Fixes[0].Safe);
  Inserted := '';
  for Edit in Found[0].Fixes[0].Edits do
  begin
    Inserted := Inserted + Edit.NewText + '|';
  end;
  Assert.IsTrue(Pos('class ', Inserted) > 0, Inserted);
  Assert.IsTrue(Pos('static;', Inserted) > 0, Inserted);
end;

procedure TMethodWithoutSelfRuleTests.MethodWithFieldIsSilent;
var
  Found: TArray<TRuleFinding>;
  Finding: TRuleFinding;
begin
  Found := TRuleAssert.Findings(Rule, Source, Enabled);
  for Finding in Found do
  begin
    Assert.IsTrue(Pos('TRechner.Wert', Finding.Message) = 0, Finding.Message);
  end;
end;

procedure TMethodWithoutSelfRuleTests.ExperimentalAndSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, Source))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, Source,
    '{ "rules": { "method-without-self": "hint" }, "refactoring": { "methodKind": false } }'))));
end;

procedure TMethodWithoutSelfRuleTests.FormEventIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(Rule, Source,
    'object Rechner: TRechner'#10'  OnClick = Doppelt'#10'end', Enabled))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(Rule, Source,
    'object Rechner: TRechner'#10'end', Enabled))));
end;

/// <summary>Im Code einem Ereignis zugewiesen (OnClose := FormClose in Atlas.UI.Commands.KeyMap,
/// Later.OnTimer := Later_.Tick in Atlas.IDE.Foundation.Symbol): kein Treffer; eine gewöhnliche Zuweisung des
/// Ergebnisses meldet weiter.</summary>
procedure TMethodWithoutSelfRuleTests.EventAssignedInCodeIsSilent;
const
  cHead = 'unit Rechner;'#10'interface'#10'type'#10'  TRechner = class'#10'  public'#10 +
    '    OnTick: TNotifyEvent;'#10'    procedure Tick(Sender: TObject);'#10'    procedure Start;'#10 +
    '    function Zahl: Integer;'#10'  end;'#10'implementation'#10 +
    'procedure TRechner.Tick(Sender: TObject);'#10'begin'#10'end;'#10 +
    'function TRechner.Zahl: Integer;'#10'begin'#10'  Result := 2;'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(Rule, cHead + 'procedure TRechner.Start;'#10'var'#10'  mWert: Integer;'#10 +
    'begin'#10'  OnTick := Self.Tick;'#10'  mWert := Zahl;'#10'end;'#10'end.', Enabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.IsTrue(Pos('TRechner.Zahl', mFound[0].Message) > 0, mFound[0].Message);
end;

procedure TMethodWithoutSelfRuleTests.InterfaceMethodsAreSilent;
const
  cMelder =
    'unit Melder;'#10 +
    'interface'#10 +
    'uses ToolsAPI, System.Generics.Defaults;'#10 +
    'type'#10 +
    '  IBasis = interface'#10 +
    '    procedure Zeige;'#10 +
    '  end;'#10 +
    '  IKind = interface(IBasis)'#10 +
    '  end;'#10 +
    '  TMelder = class(TNotifierObject, IOTAWizard)'#10 +
    '    function GetIDString: string;'#10 +
    '  end;'#10 +
    '  TVergleich = class(TInterfacedObject, IComparer<Integer>)'#10 +
    '    function Compare(const A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    '  TZeiger = class(TInterfacedObject, IKind)'#10 +
    '    procedure Zeige;'#10 +
    '    function Doppelt(A: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TMelder.GetIDString: string;'#10 +
    'begin'#10 +
    '  Result := ''Atlas.Melder'';'#10 +
    'end;'#10 +
    'function TVergleich.Compare(const A, B: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A - B;'#10 +
    'end;'#10 +
    'procedure TZeiger.Zeige;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TZeiger.Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'end.';
var
  Found: TArray<TRuleFinding>;
begin
  // IOTAWizard und IComparer<T> kennt der Index nicht, Zeige erbt IKind von IBasis: Nur Doppelt bleibt.
  Found := TRuleAssert.Findings(Rule, cMelder, Enabled);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.IsTrue(Pos('TZeiger.Doppelt', Found[0].Message) > 0, Found[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodWithoutSelfRuleTests);

end.
