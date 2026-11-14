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
    [Test]
    procedure InheritedMemberOfUnknownAncestorIsSilent;
    [Test]
    procedure PointerInDescendantIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.MethodWithoutSelf,
  Atlas.Tests.RuleAssert;

const
  cEnabled = '{ "rules": { "method-without-self": "hint" } }';
  cRechnerSource =
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
  mFound: TArray<TRuleFinding>;
  mEdit: TTextEdit;
  mInserted: string;
begin
  mFound := TRuleAssert.Findings(Rule, cRechnerSource, cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('method-without-self', mFound[0].RuleId);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('TRechner.Doppelt', mFound[0].Message) > 0, mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('In class-Methode umwandeln', mFound[0].Fixes[0].Title);
  Assert.IsFalse(mFound[0].Fixes[0].Safe);
  mInserted := '';
  for mEdit in mFound[0].Fixes[0].Edits do
  begin
    mInserted := mInserted + mEdit.NewText + '|';
  end;
  Assert.IsTrue(Pos('class ', mInserted) > 0, mInserted);
  Assert.IsTrue(Pos('static;', mInserted) > 0, mInserted);
end;

procedure TMethodWithoutSelfRuleTests.MethodWithFieldIsSilent;
var
  mFound: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  mFound := TRuleAssert.Findings(Rule, cRechnerSource, cEnabled);
  for mFinding in mFound do
  begin
    Assert.AreEqual(0, Pos('TRechner.Wert', mFinding.Message), mFinding.Message);
  end;
end;

procedure TMethodWithoutSelfRuleTests.ExperimentalAndSwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cRechnerSource))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, cRechnerSource,
    '{ "rules": { "method-without-self": "hint" }, "refactoring": { "methodKind": false } }'))));
end;

procedure TMethodWithoutSelfRuleTests.FormEventIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(Rule, cRechnerSource,
    'object Rechner: TRechner'#10'  OnClick = Doppelt'#10'end', cEnabled))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(Rule, cRechnerSource,
    'object Rechner: TRechner'#10'end', cEnabled))));
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
    'begin'#10'  OnTick := Self.Tick;'#10'  mWert := Zahl;'#10'end;'#10'end.', cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.IsTrue(Pos('TRechner.Zahl', mFound[0].Message) > 0, mFound[0].Message);
end;

/// <summary>Close in einem Formular ist TCustomForm.Close, nicht System.Close: Bei einem Vorfahren außerhalb des
/// Index (Atlas.UI.Commands.KeyMap) kann ein eingebauter Name ein geerbtes Mitglied sein. Ohne solchen Vorfahren
/// meldet die Regel weiter.</summary>
procedure TMethodWithoutSelfRuleTests.InheritedMemberOfUnknownAncestorIsSilent;
const
  cBody = 'implementation'#10'procedure TFenster.Schliessen;'#10'begin'#10'  Close;'#10'end;'#10'end.';
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(Rule, 'unit Fenster;'#10'interface'#10'type'#10 +
    '  TFenster = class(TForm)'#10'    procedure Schliessen;'#10'  end;'#10 + cBody, cEnabled))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(Rule, 'unit Fenster;'#10'interface'#10'type'#10 +
    '  TFenster = class'#10'    procedure Schliessen;'#10'  end;'#10 + cBody, cEnabled))));
end;

/// <summary>Eine abgeleitete Klasse übergibt das geerbte Ereignis ohne Self (AddButton(…, CloseClick) in
/// TAtlasKeyMapWindow): Die Methode muss eine Methode des Objekts bleiben.</summary>
procedure TMethodWithoutSelfRuleTests.PointerInDescendantIsSilent;
const
  cSource = 'unit Fenster;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '    procedure Klick(Sender: TObject);'#10'  end;'#10'  TFenster = class(TBasis)'#10 +
    '    FOnKlick: TNotifyEvent;'#10'    procedure Baue;'#10'  end;'#10'implementation'#10 +
    'procedure TBasis.Klick(Sender: TObject);'#10'begin'#10'end;'#10 +
    'procedure TFenster.Baue;'#10'begin'#10'  FOnKlick := Klick;'#10'end;'#10'end.';
var
  mFound: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  mFound := TRuleAssert.Findings(Rule, cSource, cEnabled);
  for mFinding in mFound do
  begin
    Assert.AreEqual(0, Pos('TBasis.Klick', mFinding.Message), mFinding.Message);
  end;
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
  mFound: TArray<TRuleFinding>;
begin
  // IOTAWizard und IComparer<T> kennt der Index nicht, Zeige erbt IKind von IBasis: Nur Doppelt bleibt.
  mFound := TRuleAssert.Findings(Rule, cMelder, cEnabled);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.IsTrue(Pos('TZeiger.Doppelt', mFound[0].Message) > 0, mFound[0].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TMethodWithoutSelfRuleTests);

end.
