unit Atlas.Common.Rules.Builtin.Ownership.Interfaces.Tests;

// Tests von interface-object-mixed und interface-cycle-without-weak (#1876): doppelte Freigabe, Benutzung nach
// vorübergehender Interface-Weitergabe, eigene Referenzzählung, Kreis zweier Klassen und Baum mit Rückverweis,
// [weak]-Korrektur, Experimentell-Status.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInterfaceObjectMixedTests = class
  public
    [Test]
    procedure FreedAfterInterfaceAssignment;
    [Test]
    procedure UsedAfterTemporaryInterface;
    [Test]
    procedure SilentCases;
  end;

  [TestFixture]
  TInterfaceCycleWithoutWeakTests = class
  public
    [Test]
    procedure TwoClassesWithFix;
    [Test]
    procedure TreeWithBackReference;
    [Test]
    procedure WeakFieldIsSilent;
    [Test]
    procedure ExperimentalOnlyInStrictProfile;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Builtin.Ownership.Interfaces,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

/// <summary>Unit mit TZaehler (TInterfacedObject, IZaehler) und der Routine Lauf.</summary>
function Source(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  IZaehler = interface'#10'    procedure Plus;'#10'  end;'#10 +
    '  TZaehler = class(TInterfacedObject, IZaehler)'#10'    procedure Plus;'#10'  end;'#10 +
    'procedure Nimm(const AZaehler: IZaehler);'#10'implementation'#10'procedure TZaehler.Plus;'#10'begin'#10 +
    'end;'#10'procedure Nimm(const AZaehler: IZaehler);'#10'begin'#10'end;'#10'procedure Lauf;'#10'var'#10 +
    AVars + 'begin'#10 + ABody + 'end;'#10'end.';
end;

{ TInterfaceObjectMixedTests }

procedure TInterfaceObjectMixedTests.FreedAfterInterfaceAssignment;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10'  I: IZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  I := Z;'#10'  I.Plus;'#10'  Z.Free;'#10));
  Assert.AreEqual('25: Z (TZaehler mit Referenzzählung) wird als Interface weitergegeben und zusätzlich ' +
    'freigegeben: Der letzte Interface-Verweis gibt das Objekt ein zweites Mal frei.|', Messages(mFound));
  Assert.AreEqual(cInterfaceObjectMixedRuleId, mFound[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  TRuleAssert.Reports(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  Nimm(Z as IZaehler);'#10'  FreeAndNil(Z);'#10));
  // Eine Methode eines anderen Objekts behält den Verweis meist; Freigeben ist dann doppelt.
  TRuleAssert.Reports(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10'  L: TInterfaceList;'#10,
    '  Z := TZaehler.Create;'#10'  L.Add(Z as IZaehler);'#10'  Z.Free;'#10));
end;

procedure TInterfaceObjectMixedTests.UsedAfterTemporaryInterface;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  Nimm(IZaehler(Z));'#10'  Z.Plus;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(23, mFound[0].Range.StartPos.Line);
  Assert.Contains(mFound[0].Message, 'in Zeile 23 nur vorübergehend als Interface');
end;

procedure TInterfaceObjectMixedTests.SilentCases;
begin
  // Interface-Variable hält das Objekt; nur Objekt mit Free; eigene Zählung (_AddRef) in der Kette.
  TRuleAssert.Silent(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10'  I: IZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  I := Z;'#10'  Nimm(Z as IZaehler);'#10'  Z.Plus;'#10));
  TRuleAssert.Silent(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  Z.Plus;'#10'  Z.Free;'#10));
  // Methode eines anderen Objekts (behält den Verweis), neues Objekt nach der Weitergabe.
  TRuleAssert.Silent(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10'  L: TInterfaceList;'#10,
    '  Z := TZaehler.Create;'#10'  L.Add(Z as IZaehler);'#10'  Z.Plus;'#10));
  TRuleAssert.Silent(TInterfaceObjectMixedRule.Create, Source('  Z: TZaehler;'#10,
    '  Z := TZaehler.Create;'#10'  Nimm(IZaehler(Z));'#10'  Z := TZaehler.Create;'#10'  Z.Plus;'#10));
  TRuleAssert.Silent(TInterfaceObjectMixedRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TOhneZaehlung = class(TInterfacedObject, IInterface)'#10 +
    '    function _AddRef: Integer; stdcall;'#10'    function _Release: Integer; stdcall;'#10'  end;'#10 +
    'implementation'#10'function TOhneZaehlung._AddRef: Integer;'#10'begin'#10'  Result := -1;'#10'end;'#10 +
    'function TOhneZaehlung._Release: Integer;'#10'begin'#10'  Result := -1;'#10'end;'#10'procedure Lauf;'#10 +
    'var'#10'  O: TOhneZaehlung;'#10'  I: IInterface;'#10'begin'#10'  O := TOhneZaehlung.Create;'#10 +
    '  I := O;'#10'  I := nil;'#10'  O.Free;'#10'end;'#10'end.');
end;

{ TInterfaceCycleWithoutWeakTests }

const
  cKnoten = 'unit U;'#10'interface'#10'uses'#10'  System.Generics.Collections;'#10'type'#10 +
    '  IKnoten = interface'#10'  end;'#10'  IBaum = interface'#10'  end;'#10;

function Pair(const AParentField: string): string;
begin
  Result := cKnoten + '  TBaum = class(TInterfacedObject, IBaum)'#10'  private'#10 +
    '    FKnoten: TList<IKnoten>;'#10'  end;'#10'  TKnoten = class(TInterfacedObject, IKnoten)'#10'  private'#10 +
    AParentField + '  end;'#10'implementation'#10'end.';
end;

procedure TInterfaceCycleWithoutWeakTests.TwoClassesWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Pair('    FBaum: IBaum;'#10);
  mFound := TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create, mSource,
    '{"rules": {"interface-cycle-without-weak": "hint"}}');
  Assert.AreEqual('11: TBaum.FKnoten und TKnoten.FBaum halten sich über Interfaces gegenseitig fest; ohne [weak] ' +
    'auf einer Seite wird keines der Objekte freigegeben.|15: TKnoten.FBaum und TBaum.FKnoten halten sich über ' +
    'Interfaces gegenseitig fest; ohne [weak] auf einer Seite wird keines der Objekte freigegeben.|',
    Messages(mFound));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFound[0].Severity));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('[weak] an FBaum setzen', mFound[1].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[1].Fixes[0].Edits);
  Assert.AreEqual(Pair('    [weak] FBaum: IBaum;'#10), mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create, mFixed,
    '{"rules": {"interface-cycle-without-weak": "hint"}}'))));
end;

procedure TInterfaceCycleWithoutWeakTests.TreeWithBackReference;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create, cKnoten +
    '  TKnoten = class(TInterfacedObject, IKnoten)'#10'  private'#10'    FEltern: IKnoten;'#10 +
    '    FKinder: TArray<IKnoten>;'#10'  end;'#10'implementation'#10'end.',
    '{"rules": {"interface-cycle-without-weak": "hint"}}');
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  // Nur einzelne Felder derselben Klasse (verkettete Liste) sind kein sicherer Kreis.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create, cKnoten +
    '  TKnoten = class(TInterfacedObject, IKnoten)'#10'  private'#10'    FNaechster: IKnoten;'#10'  end;'#10 +
    'implementation'#10'end.', '{"rules": {"interface-cycle-without-weak": "hint"}}'))));
end;

procedure TInterfaceCycleWithoutWeakTests.WeakFieldIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create,
    Pair('    [unsafe] FBaum: IBaum;'#10), '{"rules": {"interface-cycle-without-weak": "hint"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceCycleWithoutWeakRule.Create,
    Pair('    FBaum: TObject;'#10), '{"rules": {"interface-cycle-without-weak": "hint"}}'))));
end;

procedure TInterfaceCycleWithoutWeakTests.ExperimentalOnlyInStrictProfile;
var
  mEntry: TRuleCatalogEntry;
begin
  Assert.IsTrue(TRuleCatalog.Shared.TryFind(cInterfaceCycleWithoutWeakRuleId, mEntry));
  Assert.AreEqual(1, Integer(Length(mEntry.Profiles)));
  Assert.AreEqual('strict', mEntry.Profiles[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TInterfaceObjectMixedTests);
  TDUnitX.RegisterTestFixture(TInterfaceCycleWithoutWeakTests);

end.
