unit Atlas.Common.Rules.Builtin.ForwardDeclarations.Tests;

// Tests für type-used-before-declaration und unneeded-forward-declaration (#685)
// sowie unsatisfied-forward (#1002).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TForwardDeclarationRulesTests = class
  public
    [Test]
    procedure UsedBeforeIsErrorWithFix;
    [Test]
    procedure ReasonWithoutFix;
    [Test]
    procedure UnneededIsHintWithSafeFix;
    [Test]
    procedure SwitchedOff;
    [Test]
    procedure UnsatisfiedIssueExample;
    [Test]
    procedure UnsatisfiedFixBeforeInitialization;
    [Test]
    procedure UnsatisfiedValidFormsAreSilent;
    [Test]
    procedure UnsatisfiedOverloadAndForward;
    [Test]
    procedure UnsatisfiedForwardTypes;
    [Test]
    procedure IncompleteTypes;
    [Test]
    procedure UnsatisfiedOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.ForwardDeclarations,
  Atlas.Tests.RuleAssert;

const
  Tree = 'unit U;'#10'interface'#10'type'#10'  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10 +
    '  TNode = class'#10'  end;'#10'implementation'#10'end.';

procedure TForwardDeclarationRulesTests.UsedBeforeIsErrorWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, Tree);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual('"TNode" wird in TTree benutzt, bevor es deklariert ist', Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Forward-Deklaration ergänzen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Assert.AreEqual('  TNode = class;'#10, Findings[0].Fixes[0].Edits[0].NewText);
  TRuleAssert.Silent(TUnneededForwardDeclarationRule.Create, Tree);
end;

procedure TForwardDeclarationRulesTests.ReasonWithoutFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TTree = class'#10'    FRoot: TNode;'#10'  end;'#10'var'#10'  Baum: TTree;'#10'type'#10'  TNode = class'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'keine Korrektur');
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TForwardDeclarationRulesTests.UnneededIsHintWithSafeFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnneededForwardDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TNode = class;'#10'  TNode = class'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.Contains(Findings[0].Message, 'TNode');
  Assert.AreEqual('Forward-Deklaration entfernen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
end;

procedure TForwardDeclarationRulesTests.SwitchedOff;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTypeUsedBeforeDeclarationRule.Create, Tree,
    '{"refactoring": {"forwardDeclaration": false}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnneededForwardDeclarationRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TNode = class;'#10'  TNode = class'#10'  end;'#10'implementation'#10'end.',
    '{"refactoring": {"forwardDeclaration": false}}'))));
end;

function Unsatisfied(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TUnsatisfiedForwardRule.Create, ASource);
end;

function Unsatisfied(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TUnsatisfiedForwardRule.Create, ASource, AConfig, APath);
end;

function OnlyUnsatisfied(const ASource: string): string;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Unsatisfied(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0].Message;
end;

/// <summary>Wendet eine Korrektur mit einem Edit an einer Einfügestelle an (Zeilen aus #10).</summary>
function Insert(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
begin
  Assert.AreEqual(1, Integer(Length(AFix.Edits)));
  Edit := AFix.Edits[0];
  Lines := AText.Split([#10]);
  Lines[Edit.Range.StartPos.Line] := Copy(Lines[Edit.Range.StartPos.Line], 1, Edit.Range.StartPos.Character) +
    Edit.NewText + Copy(Lines[Edit.Range.StartPos.Line], Edit.Range.StartPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedIssueExample;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Pruef;'#10'interface'#10#10'function Pruefsumme(const Daten: TBytes): Cardinal;'#10#10 +
    'implementation'#10#10'end.';
  Found := Unsatisfied(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Pruefsumme ist im interface deklariert, aber nicht implementiert (wie E2065).', Found[0].Message);
  Assert.AreEqual(3, Found[0].Range.StartPos.Line);
  Assert.AreEqual(9, Found[0].Range.StartPos.Character);
  Assert.AreEqual(19, Found[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Leeren Rumpf für Pruefsumme anlegen', Found[0].Fixes[0].Title);
  Fixed := Insert(Source, Found[0].Fixes[0]);
  Assert.AreEqual('unit Pruef;'#10'interface'#10#10'function Pruefsumme(const Daten: TBytes): Cardinal;'#10#10 +
    'implementation'#10#10'function Pruefsumme(const Daten: TBytes): Cardinal;'#10'begin'#10'end;'#10#10'end.', Fixed);
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, Fixed);
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedFixBeforeInitialization;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  Source := 'unit Pruef;'#10'interface'#10'procedure Melden(const AText: string = ''x'';'#10 +
    '  ACode: Integer = 0); overload;'#10'procedure Melden; overload;'#10'implementation'#10 +
    'procedure Melden;'#10'begin'#10'end;'#10'initialization'#10'  Melden;'#10'end.';
  Found := Unsatisfied(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual('procedure Melden(const AText: string; ACode: Integer); overload;'#10'begin'#10'end;'#10#10,
    Found[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(9, Found[0].Fixes[0].Edits[0].Range.StartPos.Line);
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, Insert(Source, Found[0].Fixes[0]));
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedValidFormsAreSilent;
begin
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, 'unit Pruef;'#10'interface'#10'type'#10 +
    '  TKnoten = class;'#10'  IBesucher = interface;'#10'  TKnoten = class'#10'    procedure Laufen;'#10'  end;'#10 +
    '  IBesucher = interface'#10'  end;'#10'function Summe(A, B: Integer): Integer;'#10 +
    'function Kurz(A: Integer): Integer;'#10'function Fremd: Integer; stdcall; external ''fremd.dll'';'#10 +
    'function Spaeter: Integer;'#10'procedure Zweimal(A: Integer); overload;'#10 +
    'procedure Zweimal(A, B: Integer); overload;'#10'{$IFDEF TEST}'#10'procedure NurTest;'#10'{$ENDIF}'#10 +
    'implementation'#10'function Summe(A, B: Integer): Integer;'#10'begin'#10'  Result := A + B;'#10'end;'#10 +
    'function Kurz;'#10'begin'#10'  Result := A;'#10'end;'#10'function Spaeter: Integer; external ''x.dll'';'#10 +
    'procedure Zweimal(A: Integer);'#10'begin'#10'end;'#10'procedure Zweimal(A, B: Integer);'#10'begin'#10'end;'#10 +
    'procedure Vorne; forward;'#10'procedure Hinten;'#10'begin'#10'  Vorne;'#10'end;'#10'procedure Vorne;'#10 +
    'begin'#10'end;'#10'end.');
  // Mit Include-Dateien kann der Rumpf dort stehen.
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, 'unit Pruef;'#10'interface'#10'procedure Ausgelagert;'#10 +
    'implementation'#10'{$I Ausgelagert.inc}'#10'end.');
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedOverloadAndForward;
begin
  Assert.AreEqual('Zweimal ist im interface deklariert, aber nicht implementiert (wie E2065).',
    OnlyUnsatisfied('unit Pruef;'#10'interface'#10'procedure Zweimal(A: Integer); overload;'#10 +
    'procedure Zweimal(A, B: Integer); overload;'#10'implementation'#10'procedure Zweimal(A: Integer);'#10 +
    'begin'#10'end;'#10'end.'));
  Assert.AreEqual('Vorne ist forward deklariert, aber nicht implementiert (wie E2065).',
    OnlyUnsatisfied('unit Pruef;'#10'interface'#10'implementation'#10'procedure Vorne; forward;'#10 +
    'procedure Hinten;'#10'begin'#10'  Vorne;'#10'end;'#10'end.'));
  // Lokale Routine mit forward: ohne Korrektur.
  Assert.AreEqual('Innen ist forward deklariert, aber nicht implementiert (wie E2065).',
    OnlyUnsatisfied('program P;'#10'procedure Aussen;'#10'  procedure Innen; forward;'#10'begin'#10'  Innen;'#10 +
    'end;'#10'begin'#10'end.'));
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedForwardTypes;
begin
  Assert.AreEqual('TKnoten ist nur vorwärts deklariert; die vollständige Deklaration fehlt in diesem ' +
    'type-Abschnitt (wie E2086).', OnlyUnsatisfied('unit Pruef;'#10'interface'#10'type'#10'  TKnoten = class;'#10 +
    '  TBaum = class'#10'    FWurzel: TKnoten;'#10'  end;'#10'implementation'#10'end.'));
  Assert.AreEqual('IBesucher ist nur vorwärts deklariert; die vollständige Deklaration fehlt in diesem ' +
    'type-Abschnitt (wie E2420).', OnlyUnsatisfied('unit Pruef;'#10'interface'#10'type'#10 +
    '  IBesucher = interface;'#10'implementation'#10'end.'));
  // Die vollständige Deklaration in einem späteren type-Abschnitt löst die Vorwärtsdeklaration nicht auf.
  Assert.AreEqual('TKnoten ist nur vorwärts deklariert; die vollständige Deklaration fehlt in diesem ' +
    'type-Abschnitt (wie E2086).', OnlyUnsatisfied('unit Pruef;'#10'interface'#10'type'#10'  TKnoten = class;'#10 +
    'const'#10'  Tiefe = 3;'#10'type'#10'  TKnoten = class'#10'  end;'#10'implementation'#10'end.'));
  // Kurzform mit Vorfahr ist vollständig.
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, 'unit Pruef;'#10'interface'#10'type'#10 +
    '  EPruef = class(Exception);'#10'implementation'#10'end.');
end;

procedure TForwardDeclarationRulesTests.IncompleteTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  // Cm.E2086: Record mit einem Feld seines eigenen Typs (#1380).
  mFound := Unsatisfied('unit Pruef;'#10'interface'#10'type'#10'  TKreis = record'#10'    Innen: TKreis;'#10 +
    '  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Der Record TKreis enthält sich selbst als Feld Innen; ein Typ ist erst nach seinem end ' +
    'vollständig (wie E2086).', mFound[0].Message);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Character);
  // Cm.E2420: Interface-Liste vor der vollständigen Deklaration; ebenso ein Vorfahr.
  Assert.AreEqual('IEins ist hier nur vorwärts deklariert; als Vorfahr oder in der Interface-Liste von TKlasse muss ' +
    'der Typ schon vollständig sein (wie E2086).', OnlyUnsatisfied('unit Pruef;'#10'interface'#10'type'#10 +
    '  IEins = interface;'#10'  TKlasse = class(TInterfacedObject, IEins)'#10'  end;'#10 +
    '  IEins = interface'#10'  end;'#10'implementation'#10'end.'));
  Assert.AreEqual('TBasis ist hier nur vorwärts deklariert; als Vorfahr oder in der Interface-Liste von TKind muss ' +
    'der Typ schon vollständig sein (wie E2086).', OnlyUnsatisfied('unit Pruef;'#10'interface'#10'type'#10 +
    '  TBasis = class;'#10'  TKind = class(TBasis)'#10'  end;'#10'  TBasis = class'#10'  end;'#10 +
    'implementation'#10'end.'));
  // Zeiger, Felder und Parameter dürfen den unvollständigen Typ nennen; danach ist er vollständig.
  TRuleAssert.Silent(TUnsatisfiedForwardRule.Create, 'unit Pruef;'#10'interface'#10'type'#10 +
    '  PKreis = ^TKreis;'#10'  TKreis = record'#10'    Innen: PKreis;'#10'    Weiter: ^TKreis;'#10'  end;'#10 +
    '  TBasis = class;'#10'  TNutzer = class'#10'    FBasis: TBasis;'#10'    procedure Nimm(ABasis: TBasis);'#10 +
    '  end;'#10'  TBasis = class'#10'  end;'#10'  TKind = class(TBasis)'#10'  end;'#10'implementation'#10#10 +
    'procedure TNutzer.Nimm(ABasis: TBasis);'#10'begin'#10'end;'#10#10'end.');
end;

procedure TForwardDeclarationRulesTests.UnsatisfiedOptions;
var
  Source: string;
begin
  Source := 'unit Pruef;'#10'interface'#10'procedure Fehlt;'#10'implementation'#10'end.';
  Assert.AreEqual(1, Integer(Length(Unsatisfied(Source, '', 'Source/Pruef.pas'))));
  Assert.AreEqual(0, Integer(Length(Unsatisfied(Source, '{"rules": {"unsatisfied-forward": "off"}}',
    'Source/Pruef.pas'))));
  Assert.AreEqual(0, Integer(Length(Unsatisfied(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Pruef.pas'))));
  Assert.AreEqual(0, Integer(Length(Unsatisfied(Source,
    '{"rules": {"unsatisfied-forward": {"exclude": ["Source/*.pas"]}}}', 'Source/Pruef.pas'))));
  // Anders als die beiden Forward-Regeln gilt refactoring.forwardDeclaration hier nicht.
  Assert.AreEqual(1, Integer(Length(Unsatisfied(Source, '{"refactoring": {"forwardDeclaration": false}}',
    'Source/Pruef.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TForwardDeclarationRulesTests);

end.
