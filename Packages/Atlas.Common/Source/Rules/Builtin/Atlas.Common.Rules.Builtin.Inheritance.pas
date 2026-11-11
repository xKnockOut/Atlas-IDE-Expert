unit Atlas.Common.Rules.Builtin.Inheritance;

// Klassische Deklarationsfehler bei der Vererbung (#125), alles Varianten von
// W1010, aber schon beim Tippen und mit Korrektur:
//   destroy-without-override            destructor Destroy ohne override
//   component-create-without-override   constructor Create(AOwner: TComponent)
//                                       ohne override in TComponent-Nachfahren
//   hides-virtual                       Methode verdeckt eine virtuelle des Vorfahren
//   virtual-instead-of-override         virtual statt override bei gleicher Signatur; die Meldung nennt den
//                                       Vorfahren mit der virtuellen Methode (Destroy ohne Index: TObject)
//   shadowed-name                       Parameter oder lokale Variable heißt wie ein Feld, eine
//                                       Property (auch geerbt) oder eine globale Variable der Unit (#934)
//   override-target-missing             override ohne passende virtuelle Methode im Vorfahren (E2137),
//                                       auf eine statische (E2170) oder finale (E2352), Ableiten von
//                                       einer sealed-Klasse (E2353) (#997)
//   abstract-class-instantiated         Create auf einer Klasse mit offenen abstrakten Methoden (W1020)
//                                       (#999); "class abstract" allein erzwingt dcc nicht (E2402 gibt es
//                                       nur unter .NET, #1383)
//   inherited-abstract-call             inherited Name(…) auf eine im Vorfahren abstrakte Methode (#1026):
//                                       läuft in EAbstractError; Delphi 13 übersetzt das ohne E2373
//                                       (#1383). Die Methode löst TNameResolver samt Überladungen auf
//   class-reference-nonvirtual-constructor  Create über eine Klassenreferenz (class of TBasis), deren
//                                       Konstruktor nicht virtuell ist (E2391, #1032); läuft immer der
//                                       Konstruktor der Basisklasse
//   member-hides-ancestor               Property heißt wie ein Feld des Vorfahren (W1009), Feld wie ein
//                                       Feld oder eine Property, nicht virtuelle Methode wie eine gleich
//                                       aufgebaute nicht virtuelle des Vorfahren (#1003, ohne Code: dcc
//                                       schweigt dort, #1383); strict private des Vorfahren nur mit
//                                       ignoreStrictPrivate = false
//   override-case-mismatch              Schreibweise oder Sichtbarkeit weicht ab (#1021, aus): override
//                                       anders geschrieben als der Vorfahr (H2365) oder weniger sichtbar
//                                       (H2269, nur Klassen im interface-Teil), Getter/Setter Get<Name>
//                                       bzw. Set<Name> anders geschrieben, inline-Methode greift auf ein
//                                       weniger sichtbares Mitglied zu (beide ohne Code: H2367 und H2440
//                                       meldet Delphi 13 dort nicht, #1383)
//   override-only-inherited             override, dessen Rumpf nur inherited mit unveränderten Parametern
//                                       aufruft (#1143); still bei geänderter Sichtbarkeit, Attributen,
//                                       Kommentaren oder Direktiven im Rumpf, final, deprecated, Standardwerten
//                                       und lokalen Deklarationen. Korrektur entfernt Deklaration und Rumpf
//                                       samt XMLDoc
//   inherited-without-ancestor          bloßes inherited; in einer neuen Methode, die kein Vorfahr kennt
//                                       (#1144): tut nichts, meist fehlt override. Nicht in Konstruktoren,
//                                       Destruktoren und Message-Handlern; unbekannter Vorfahr: still.
//                                       Korrektur entfernt das inherited
//
// Vorfahren werden zuerst in der Datei, dann im Symbolindex gesucht (auch RTL
// und VCL, soweit eingelesen). Ist ein Vorfahr nicht auflösbar oder mehrdeutig,
// endet die Suche ohne Treffer. Mit reintroduce oder override schweigen alle
// Regeln; eine Überladung (overload) mit anderer Signatur ebenso.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Rules.Builtin.Inheritance.Shadowing,
  Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets,
  Atlas.Common.Rules.Builtin.Inheritance.OverrideCase,
  Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls,
  Atlas.Common.Rules.Builtin.Inheritance.Abstract,
  Atlas.Common.Rules.Builtin.Inheritance.ClassReferences,
  Atlas.Common.Rules.Builtin.Inheritance.MemberHides;

type
  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Ancestry.</summary>
  TMethodDecl = Atlas.Common.Rules.Builtin.Inheritance.Ancestry.TMethodDecl;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Ancestry.</summary>
  TInherited = Atlas.Common.Rules.Builtin.Inheritance.Ancestry.TInherited;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Ancestry.</summary>
  TAncestry = Atlas.Common.Rules.Builtin.Inheritance.Ancestry.TAncestry;

  TDestroyWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComponentCreateWithoutOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THidesVirtualRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TVirtualInsteadOfOverrideRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Shadowing.</summary>
  TShadowedNameRule = Atlas.Common.Rules.Builtin.Inheritance.Shadowing.TShadowedNameRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets.</summary>
  TOverrideTargetMissingRule = Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets.TOverrideTargetMissingRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Abstract.</summary>
  TAbstractClassInstantiatedRule = Atlas.Common.Rules.Builtin.Inheritance.Abstract.TAbstractClassInstantiatedRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.Abstract.</summary>
  TInheritedAbstractCallRule = Atlas.Common.Rules.Builtin.Inheritance.Abstract.TInheritedAbstractCallRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.ClassReferences.</summary>
  TClassReferenceNonvirtualConstructorRule =
    Atlas.Common.Rules.Builtin.Inheritance.ClassReferences.TClassReferenceNonvirtualConstructorRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.MemberHides.</summary>
  TMemberHidesAncestorRule = Atlas.Common.Rules.Builtin.Inheritance.MemberHides.TMemberHidesAncestorRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.OverrideCase.</summary>
  TOverrideCaseMismatchRule = Atlas.Common.Rules.Builtin.Inheritance.OverrideCase.TOverrideCaseMismatchRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls.</summary>
  TOverrideOnlyInheritedRule = Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls.TOverrideOnlyInheritedRule;

  /// <summary>Liegt in Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls.</summary>
  TInheritedWithoutAncestorRule = Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls.TInheritedWithoutAncestorRule;

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceText = (DestroyTitle, DestroyNoOverride, CreateTitle, CreateNoOverride, HidesTitle, Hides, VirtualTitle,
    Virtual, ReplaceByOverride);

const
  cTexts: array[TInheritanceText] of TAtlasText = (
    (De: 'destructor Destroy ohne override'; En: 'destructor Destroy without override'),
    (De: 'Destroy ohne override: Free ruft diesen Destruktor nicht auf';
     En: 'Destroy without override: Free does not call this destructor'),
    (De: 'constructor Create(AOwner: TComponent) ohne override in einer Komponente';
     En: 'constructor Create(AOwner: TComponent) without override in a component'),
    (De: 'Create(AOwner: TComponent) ohne override: beim Laden aus der DFM wird dieser Konstruktor nicht aufgerufen';
     En: 'Create(AOwner: TComponent) without override: loading from the DFM does not call this constructor'),
    (De: 'Methode verdeckt eine virtuelle Methode des Vorfahren'; En: 'Method hides a virtual method of the ancestor'),
    (De: '"%s" verdeckt die virtuelle Methode %s.%s; override oder reintroduce angeben';
     En: '"%s" hides the virtual method %s.%s; specify override or reintroduce'),
    (De: 'virtual im Nachfahren statt override'; En: 'virtual in the descendant instead of override'),
    (De: '"%s" ist im Vorfahren %s schon virtuell; override statt %s verwenden';
     En: '"%s" is already virtual in the ancestor %s; use override instead of %s'),
    (De: '%s durch override ersetzen'; En: 'Replace %s with override'));

{$SCOPEDENUMS OFF}

{ TDestroyWithoutOverrideRule }

function TDestroyWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('destroy-without-override', TRuleSeverity.Warning,
    cTexts[TInheritanceText.DestroyTitle].Text);
end;

procedure TDestroyWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAncestry: TAncestry;
  mMethods: TArray<TMethodDecl>;
  mMethod: TMethodDecl;
  mFix: TRuleFix;
begin
  if not Prepare(AContext, mAncestry, mMethods) then
  begin
    Exit;
  end;
  try
    for mMethod in mMethods do
    begin
      // Mit virtual meldet virtual-instead-of-override.
      if not IsDestroy(mMethod) or mMethod.Has('virtual') or mMethod.Has('dynamic') then
      begin
        Continue;
      end;
      if AppendDirective(AContext, mMethod, 'override', mFix) then
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TInheritanceText.DestroyNoOverride].Text, [mFix]);
      end
      else
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TInheritanceText.DestroyNoOverride].Text);
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

{ TComponentCreateWithoutOverrideRule }

function TComponentCreateWithoutOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-create-without-override', TRuleSeverity.Warning,
    cTexts[TInheritanceText.CreateTitle].Text);
end;

procedure TComponentCreateWithoutOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAncestry: TAncestry;
  mMethods: TArray<TMethodDecl>;
  mMethod: TMethodDecl;
  mFix: TRuleFix;
begin
  if not Prepare(AContext, mAncestry, mMethods) then
  begin
    Exit;
  end;
  try
    for mMethod in mMethods do
    begin
      if not IsComponentCreate(mMethod) or mMethod.Has('virtual') or mMethod.Has('dynamic') or
        not mAncestry.DescendsFrom(mMethod.ClassName, 'TComponent') then
      begin
        Continue;
      end;
      if AppendDirective(AContext, mMethod, 'override', mFix) then
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TInheritanceText.CreateNoOverride].Text, [mFix]);
      end
      else
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, cTexts[TInheritanceText.CreateNoOverride].Text);
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

{ THidesVirtualRule }

function THidesVirtualRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hides-virtual', TRuleSeverity.Warning,
    cTexts[TInheritanceText.HidesTitle].Text);
end;

/// <summary>AMethod verdeckt die virtuelle Methode AFound: virtual bei gleicher Signatur prüft
/// virtual-instead-of-override; eine Überladung mit anderer Signatur verdeckt nichts.</summary>
function HidesVirtual(const AMethod: TMethodDecl; const AFound: TInherited): Boolean;
var
  mIsVirtual: Boolean;
begin
  mIsVirtual := AMethod.Has('virtual') or AMethod.Has('dynamic');
  Result := AFound.Found and not (mIsVirtual and AFound.SameSignature);
  Result := Result and not (AMethod.Has('overload') and not AFound.SameSignature);
end;

/// <summary>Meldet hides-virtual mit override (nur bei gleicher Signatur) und reintroduce als Korrekturen.</summary>
procedure ReportHidesVirtual(const AContext: TRuleContext; const AReport: IRuleReport; const AMethod: TMethodDecl;
  const AFound: TInherited);
var
  mFixes: TArray<TRuleFix>;
  mFix: TRuleFix;
  mConfidence: TRuleConfidence;
begin
  mFixes := nil;
  if AFound.SameSignature and AppendDirective(AContext, AMethod, 'override', mFix) then
  begin
    mFix.Alternative := True;
    mFixes := mFixes + [mFix];
  end;
  if AppendDirective(AContext, AMethod, 'reintroduce', mFix) then
  begin
    mFix.Alternative := True;
    mFixes := mFixes + [mFix];
  end;
  mConfidence := TRuleConfidence.Medium;
  if AFound.SameSignature then
  begin
    mConfidence := TRuleConfidence.High;
  end;
  AReport.Add(AMethod.Symbol.SelectionRange, cTexts[TInheritanceText.Hides].Fmt([AMethod.Symbol.Name, AFound.TypeName,
    AFound.Symbol.Name]), mConfidence, mFixes);
end;

procedure THidesVirtualRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAncestry: TAncestry;
  mMethods: TArray<TMethodDecl>;
  mMethod: TMethodDecl;
  mFound: TInherited;
begin
  if not Prepare(AContext, mAncestry, mMethods) then
  begin
    Exit;
  end;
  try
    for mMethod in mMethods do
    begin
      // Destroy und Create(TComponent) haben eigene Regeln.
      if IsDestroy(mMethod) or IsComponentCreate(mMethod) then
      begin
        Continue;
      end;
      mFound := mAncestry.InheritedVirtual(mMethod);
      if HidesVirtual(mMethod, mFound) then
      begin
        ReportHidesVirtual(AContext, AReport, mMethod, mFound);
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

{ TVirtualInsteadOfOverrideRule }

function TVirtualInsteadOfOverrideRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('virtual-instead-of-override', TRuleSeverity.Warning,
    cTexts[TInheritanceText.VirtualTitle].Text);
end;

/// <summary>Token der Direktive virtual bzw. dynamic im Kopf.</summary>
function VirtualToken(const AContext: TRuleContext; const AMethod: TMethodDecl; out AToken: TPascalToken): Boolean;
var
  mIndex: Integer;
  mDirective: TSyntaxNode;
begin
  for mIndex := 0 to AMethod.Header.ChildCount - 1 do
  begin
    mDirective := AMethod.Header[mIndex];
    if (mDirective.Kind = TSyntaxKind.Directive) and MatchText(mDirective.Name, ['virtual', 'dynamic']) and
      TokenAt(AContext, mDirective.StartOffset, AToken) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TVirtualInsteadOfOverrideRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mAncestry: TAncestry;
  mMethods: TArray<TMethodDecl>;
  mMethod: TMethodDecl;
  mFound: TInherited;
  mToken: TPascalToken;
  mMessage, mAncestor: string;
begin
  if not Prepare(AContext, mAncestry, mMethods) then
  begin
    Exit;
  end;
  try
    for mMethod in mMethods do
    begin
      if not mMethod.Has('virtual') and not mMethod.Has('dynamic') then
      begin
        Continue;
      end;
      mFound := mAncestry.InheritedVirtual(mMethod);
      if mFound.Found and mFound.SameSignature then
      begin
        mAncestor := mFound.TypeName;
      end
      else if IsDestroy(mMethod) then
      begin
        // TObject.Destroy ist immer virtuell, auch wenn TObject nicht im Index steht.
        mAncestor := 'TObject';
      end
      else
      begin
        Continue;
      end;
      mMessage := cTexts[TInheritanceText.Virtual].Fmt(
        [mMethod.Symbol.Name, mAncestor, IfThen(mMethod.Has('virtual'), 'virtual', 'dynamic')]);
      if VirtualToken(AContext, mMethod, mToken) then
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, mMessage,
          [TRuleFix.Create(cTexts[TInheritanceText.ReplaceByOverride].Fmt(
          [mToken.Text]), [TRuleEdit.Create(TTextRange.Create(mToken.StartPos, mToken.EndPos), 'override')])]);
      end
      else
      begin
        AReport.Add(mMethod.Symbol.SelectionRange, mMessage);
      end;
    end;
  finally
    mAncestry.Free;
  end;
end;

procedure RegisterInheritanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDestroyWithoutOverrideRule.Create);
  ARegistry.Register(TComponentCreateWithoutOverrideRule.Create);
  ARegistry.Register(THidesVirtualRule.Create);
  ARegistry.Register(TVirtualInsteadOfOverrideRule.Create);
  ARegistry.Register(TShadowedNameRule.Create);
  ARegistry.Register(TOverrideTargetMissingRule.Create);
  ARegistry.Register(TAbstractClassInstantiatedRule.Create);
  ARegistry.Register(TInheritedAbstractCallRule.Create);
  ARegistry.Register(TClassReferenceNonvirtualConstructorRule.Create);
  ARegistry.Register(TMemberHidesAncestorRule.Create);
  ARegistry.Register(TOverrideCaseMismatchRule.Create);
  ARegistry.Register(TOverrideOnlyInheritedRule.Create);
  ARegistry.Register(TInheritedWithoutAncestorRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance', cTexts);

end.
