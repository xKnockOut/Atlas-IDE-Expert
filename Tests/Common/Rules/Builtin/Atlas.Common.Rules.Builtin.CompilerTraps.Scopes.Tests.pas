unit Atlas.Common.Rules.Builtin.CompilerTraps.Scopes.Tests;

// Tests der Namensfallen aus #2095: Konstante einer anderen Klasse ohne Klassennamen, geerbte Konstante in der
// Klassendeklaration, Aufzählungswerte wie Continue ohne {$SCOPEDENUMS ON} und reference to ohne benannten Typ,
// Mitglieder eines Vorfahren, die einen Namen der Unit verdecken, jeweils mit stillen Fällen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerTrapsScopesTests = class
  public
    /// <summary>Fall aus Atlas.IDE.Tracker.WorkingCopies: cHeadCacheMs aus TWorkingCopies in TWorkingHeads.</summary>
    [Test]
    procedure ForeignClassConstant;
    /// <summary>cRows = 2 * cGap in der Deklaration der abgeleiteten Klasse.</summary>
    [Test]
    procedure InheritedConstantInDeclaration;
    [Test]
    procedure ClassConstantSilentCases;
    /// <summary>Unbekannter Vorfahr: still, wenn der Index den Namen anderswo kennt.</summary>
    [Test]
    procedure UnknownAncestorWithIndex;
    /// <summary>Fall aus Atlas.IDE.Tracker.Reopened: (Continue, Dismiss, Reason).</summary>
    [Test]
    procedure EnumHidesKeyword;
    [Test]
    procedure EnumWithScopedEnumsIsSilent;
    /// <summary>Fall aus Atlas.IDE.Tracker.Reopened: Peek: reference to function(…): Boolean im Record.</summary>
    [Test]
    procedure InlineReferenceType;
    [Test]
    procedure NamedReferenceTypeIsSilent;
    /// <summary>Freie Routine AddLabel neben der geerbten Methode TDialog.AddLabel.</summary>
    [Test]
    procedure MemberHidesUnitRoutine;
    /// <summary>Scaled aus TCustomForm über den Index (Vorfahr außerhalb der Datei).</summary>
    [Test]
    procedure MemberFromIndexHidesUnitRoutine;
    [Test]
    procedure MemberHidesSilentCases;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.CompilerTraps.Scopes,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ':' + IntToStr(mFinding.Range.StartPos.Character) +
      ' ' + mFinding.Message + '|';
  end;
end;

const
  cKopien =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TWorkingCopies = class'#10 +
    '  public const'#10 +
    '    cHeadCacheMs = 500;'#10 +
    '  end;'#10 +
    '  TWorkingHeads = class'#10 +
    '  private'#10 +
    '    FAge: Integer;'#10 +
    '  public'#10 +
    '    function Fresh: Boolean;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TWorkingHeads.Fresh: Boolean;'#10 +
    'begin'#10 +
    '  Result := FAge < cHeadCacheMs;'#10 +
    'end;'#10 +
    'end.';

{ TCompilerTrapsScopesTests }

procedure TCompilerTrapsScopesTests.ForeignClassConstant;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TClassConstantUnqualifiedRule.Create, cKopien);
  Assert.AreEqual('16:19 cHeadCacheMs ist eine Konstante von TWorkingCopies; in TWorkingHeads sieht Delphi sie ohne ' +
    'Klassennamen nicht (wie E2003). TWorkingCopies.cHeadCacheMs schreiben.|', Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  Assert.AreEqual('TWorkingCopies.', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(19, mFound[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TCompilerTrapsScopesTests.InheritedConstantInDeclaration;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '  public const'#10 +
    '    cGap = 4;'#10 +
    '  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10 +
    '  public const'#10 +
    '    cRows = 2 * cGap;'#10 +
    '    cCols = 2 * TBasis.cGap;'#10 +
    '  public'#10 +
    '    function Hoehe: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TAbgeleitet.Hoehe: Integer;'#10 +
    'begin'#10 +
    '  Result := cRows * cGap;'#10 +
    'end;'#10 +
    'end.';
begin
  // Im Rumpf sieht Delphi die geerbte Konstante, in der Deklaration noch nicht.
  Assert.AreEqual('9:16 cGap ist eine Konstante des Vorfahren TBasis; in der Deklaration von TAbgeleitet sieht ' +
    'Delphi geerbte Konstanten noch nicht (wie E2003). TBasis.cGap schreiben.|',
    Messages(TRuleAssert.Findings(TClassConstantUnqualifiedRule.Create, cSource)));
end;

procedure TCompilerTrapsScopesTests.ClassConstantSilentCases;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TQuelle = class'#10 +
    '  public const'#10 +
    '    cGrenze = 5;'#10 +
    '    cEigen = 1;'#10 +
    '  public type'#10 +
    '    TInnen = class'#10 +
    '      function Wert: Integer;'#10 +
    '    end;'#10 +
    '  end;'#10 +
    '  TNutzer = class'#10 +
    '  public const'#10 +
    '    cEigen = 2;'#10 +
    '  public'#10 +
    '    function Lokal: Integer;'#10 +
    '    function Qualifiziert: Integer;'#10 +
    '    function MitWith(A: TQuelle): Integer;'#10 +
    '  end;'#10 +
    'const'#10 +
    '  cGlobal = 3;'#10 +
    'implementation'#10 +
    'function TQuelle.TInnen.Wert: Integer;'#10 +
    'begin'#10 +
    '  Result := cGrenze;'#10 +
    'end;'#10 +
    'function TNutzer.Lokal: Integer;'#10 +
    'const'#10 +
    '  cGrenze = 7;'#10 +
    'begin'#10 +
    '  Result := cGrenze + cEigen + cGlobal;'#10 +
    'end;'#10 +
    'function TNutzer.Qualifiziert: Integer;'#10 +
    'begin'#10 +
    '  Result := TQuelle.cGrenze;'#10 +
    'end;'#10 +
    'function TNutzer.MitWith(A: TQuelle): Integer;'#10 +
    'begin'#10 +
    '  with A do'#10 +
    '    Result := cGrenze;'#10 +
    'end;'#10 +
    'procedure Frei;'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := cGlobal;'#10 +
    'end;'#10 +
    'end.';
begin
  // Umgebende Klasse, lokale Konstante, eigene Konstante, Unit-Ebene, qualifiziert, with, freie Routine.
  TRuleAssert.Silent(TClassConstantUnqualifiedRule.Create, cSource);
end;

procedure TCompilerTrapsScopesTests.UnknownAncestorWithIndex;
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  mSource := StringReplace(cKopien, 'TWorkingHeads = class', 'TWorkingHeads = class(TBasis)', []);
  // Ohne Index: Der Vorfahr ist unbekannt, deklariert aber kaum eine gleichnamige Konstante.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TClassConstantUnqualifiedRule.Create, mSource))));
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  TBasis = class'#10 +
    '  public const'#10'    cHeadCacheMs = 100;'#10'  end;'#10'implementation'#10'end.', 'C:\P\Basis.pas', nil));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TClassConstantUnqualifiedRule.Create,
    StringReplace(mSource, 'interface', 'interface'#10'uses Basis;', []), mIndex, '', 'U.pas'))));
end;

procedure TCompilerTrapsScopesTests.EnumHidesKeyword;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAtlasIssueReopenedAction = (Continue, Dismiss, Reason);'#10 +
    '  TSprung = (Weiter, Exit);'#10 +
    'implementation'#10 +
    'end.';
begin
  Assert.AreEqual('3:31 Der Wert Continue von TAtlasIssueReopenedAction verdeckt ohne {$SCOPEDENUMS ON} die ' +
    'Standardprozedur Continue in jeder Unit, die den Typ sieht; Continue; wird dort zum Ausdruck (wie E2014). ' +
    '{$SCOPEDENUMS ON} vor den Typ setzen oder den Wert umbenennen.|4:21 Der Wert Exit von TSprung verdeckt ohne ' +
    '{$SCOPEDENUMS ON} die Standardprozedur Exit in jeder Unit, die den Typ sieht; Exit; wird dort zum Ausdruck ' +
    '(wie E2014). {$SCOPEDENUMS ON} vor den Typ setzen oder den Wert umbenennen.|',
    Messages(TRuleAssert.Findings(TEnumHidesKeywordRule.Create, cSource)));
end;

procedure TCompilerTrapsScopesTests.EnumWithScopedEnumsIsSilent;
begin
  TRuleAssert.Silent(TEnumHidesKeywordRule.Create, 'unit U;'#10'interface'#10'{$SCOPEDENUMS ON}'#10'type'#10 +
    '  TAktion = (Continue, Dismiss);'#10'{$SCOPEDENUMS OFF}'#10'  TFarbe = (Rot, Gruen);'#10'implementation'#10 +
    'end.');
  // Nach {$SCOPEDENUMS OFF} gilt die Regel wieder.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEnumHidesKeywordRule.Create, 'unit U;'#10'interface'#10 +
    '{$SCOPEDENUMS ON}'#10'{$SCOPEDENUMS OFF}'#10'type'#10'  TAktion = (Break, Dismiss);'#10'implementation'#10 +
    'end.'))));
end;

procedure TCompilerTrapsScopesTests.InlineReferenceType;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TReopened = record'#10 +
    '    Peek: reference to function(const A: string): Boolean;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Nimm;'#10 +
    'var'#10 +
    '  mProc: reference to procedure;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TInlineReferenceTypeRule.Create, cSource);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('4:10 Peek hat den Typ reference to … direkt; Delphi kennt Methodenreferenzen nur als benannten ' +
    'Typ (wie E2003 ''reference''). Typ im type-Abschnitt deklarieren und hier verwenden.|',
    Messages(Copy(mFound, 0, 1)));
  Assert.AreEqual(9, mFound[1].Range.StartPos.Line);
end;

procedure TCompilerTrapsScopesTests.NamedReferenceTypeIsSilent;
begin
  TRuleAssert.Silent(TInlineReferenceTypeRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TPeek = reference to function(const A: string): Boolean;'#10'  TReopened = record'#10'    Peek: TPeek;'#10 +
    '  end;'#10'implementation'#10'end.');
end;

const
  cDialog =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDialog = class'#10 +
    '  protected'#10 +
    '    procedure AddLabel(const AText: string);'#10 +
    '  end;'#10 +
    '  TFrage = class(TDialog)'#10 +
    '  public'#10 +
    '    procedure Baue;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function AddLabel(AOwner: TObject; const AText: string): Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'procedure TDialog.AddLabel(const AText: string);'#10 +
    'begin'#10 +
    '  AddLabel(Self, AText);'#10 +
    'end;'#10 +
    'procedure TFrage.Baue;'#10 +
    'begin'#10 +
    '  AddLabel(Self, ''x'');'#10 +
    'end;'#10 +
    'end.';

procedure TCompilerTrapsScopesTests.MemberHidesUnitRoutine;
var
  mFound: TArray<TRuleFinding>;
begin
  // In TDialog.AddLabel ist das eigene Mitglied gemeint (still), in TFrage.Baue das geerbte verdeckt die Routine.
  mFound := TRuleAssert.Findings(TMemberHidesUnitSymbolRule.Create, cDialog);
  Assert.AreEqual('22:2 AddLabel meint in Methoden von TFrage das Mitglied TDialog.AddLabel, nicht AddLabel der ' +
    'Unit (Zeile 13); Delphi nimmt das Mitglied (wie E2066, E2010, E2015 bzw. E2034). U.AddLabel schreiben oder ' +
    'umbenennen.|', Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.IsFalse(mFound[0].Fixes[0].Safe);
  Assert.AreEqual('U.', mFound[0].Fixes[0].Edits[0].NewText);
end;

procedure TCompilerTrapsScopesTests.MemberFromIndexHidesUnitRoutine;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  Werk.Forms;'#10 +
    'type'#10 +
    '  TFenster = class(TForm)'#10 +
    '  public'#10 +
    '    function Breite: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function Scaled(AValue: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := AValue * 2;'#10 +
    'end;'#10 +
    'function TFenster.Breite: Integer;'#10 +
    'begin'#10 +
    '  Result := Scaled(4);'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Werk.Forms;'#10'interface'#10'type'#10 +
    '  TCustomForm = class'#10'  public'#10'    property Scaled: Boolean read FScaled;'#10'  end;'#10 +
    '  TForm = class(TCustomForm)'#10'  end;'#10'implementation'#10'end.', 'C:\P\Werk.Forms.pas', nil));
  Assert.AreEqual('16:12 Scaled meint in Methoden von TFenster das Mitglied TCustomForm.Scaled, nicht Scaled der ' +
    'Unit (Zeile 11); Delphi nimmt das Mitglied (wie E2066, E2010, E2015 bzw. E2034). U.Scaled schreiben oder ' +
    'umbenennen.|', Messages(TRuleAssert.IndexFindings(TMemberHidesUnitSymbolRule.Create, cSource, mIndex, '',
    'U.pas')));
  // Ohne Index ist der Vorfahr unbekannt: still.
  TRuleAssert.Silent(TMemberHidesUnitSymbolRule.Create, cSource);
end;

procedure TCompilerTrapsScopesTests.MemberHidesSilentCases;
begin
  // Mit Unit-Namen, lokal gleich benannt, in einer freien Routine, ohne gleichnamiges Mitglied.
  TRuleAssert.Silent(TMemberHidesUnitSymbolRule.Create, StringReplace(cDialog, '  AddLabel(Self, ''x'');',
    '  U.AddLabel(Self, ''x'');', []));
  TRuleAssert.Silent(TMemberHidesUnitSymbolRule.Create, StringReplace(cDialog, 'procedure TFrage.Baue;'#10'begin',
    'procedure TFrage.Baue;'#10'var'#10'  AddLabel: Integer;'#10'begin', []));
  TRuleAssert.Silent(TMemberHidesUnitSymbolRule.Create, StringReplace(cDialog, 'procedure TFrage.Baue;',
    'procedure Baue;', []));
  TRuleAssert.Silent(TMemberHidesUnitSymbolRule.Create, StringReplace(cDialog, '  AddLabel(Self, ''x'');',
    '  Free;', []));
end;

procedure TCompilerTrapsScopesTests.RulesAreRegistered;
var
  mRule: IRule;
  mIds: string;
begin
  mIds := '';
  for mRule in BuiltinRules do
  begin
    if (mRule.Descriptor.Id = cClassConstantUnqualifiedRuleId) or (mRule.Descriptor.Id = cEnumHidesKeywordRuleId) or
      (mRule.Descriptor.Id = cInlineReferenceTypeRuleId) or (mRule.Descriptor.Id = cMemberHidesUnitSymbolRuleId) then
    begin
      mIds := mIds + mRule.Descriptor.Id + ' ';
    end;
  end;
  Assert.AreEqual('class-constant-unqualified enum-hides-keyword inline-reference-type member-hides-unit-symbol ',
    mIds);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerTrapsScopesTests);

end.
