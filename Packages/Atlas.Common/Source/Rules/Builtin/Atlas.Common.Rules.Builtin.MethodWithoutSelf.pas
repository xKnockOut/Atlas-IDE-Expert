unit Atlas.Common.Rules.Builtin.MethodWithoutSelf;

// Methode ohne Self (#686):
//   method-without-self  Methode einer Klasse oder eines Records, die weder
//                        Self noch Instanzmitglieder braucht; Hinweis,
//                        experimentell (nur eingeschaltet in atlas.json).
//                        Korrektur „In class-Methode umwandeln“ (nicht
//                        sicher): Aufrufe über Instanzen bleiben gültig,
//                        darum ändert sie nur die Unit selbst. Die übrigen
//                        Umwandlungen (freie Routine, Record-Helper, Aufrufe
//                        über die Klasse) ändern auch andere Units und gibt
//                        es nur als Code-Aktion mit Vorschau.
//
// Erkennung und Änderungen liefert Editing über TCheckRefactorings.Methods
// (Host-Adapter Adapters.Checks.Refactorings), Mitglieder über die
// Namensauflösung. Ohne diesen Eintrag oder mit refactoring.methodKind aus
// schweigt die Regel.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TMethodWithoutSelfRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Checks.Contract.Refactorings,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodWithoutSelfText = (Title, NoSelf);

const
  cTexts: array[TMethodWithoutSelfText] of TAtlasText = (
    (De: 'Methode braucht Self nicht'; En: 'Method does not need Self'),
    (De: '%s.%s braucht Self nicht: als class-Methode, freie Routine oder Record-Helper möglich.';
     En: '%s.%s does not need Self: possible as class method, free routine or record helper.'));

{$SCOPEDENUMS OFF}

const
  cMethodWithoutSelfRuleId = 'method-without-self';

{ TMethodWithoutSelfRule }

function TMethodWithoutSelfRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cMethodWithoutSelfRuleId, TRuleSeverity.Hint,
    cTexts[TMethodWithoutSelfText.Title].Text);
end;

/// <summary>Was Editing über die geprüfte Unit wissen muss.</summary>
function ScanOf(const AContext: TRuleContext): TCheckMethodScan;
begin
  Result := Default(TCheckMethodScan);
  Result.FileName := AContext.ResolverFileName;
  Result.Text := AContext.Text;
  Result.Tree := TSyntaxTreeHandles.Wrap(AContext.Tree);
  Result.FormText := AContext.FormText;
  Result.Index := AContext.Index;
  Result.EnsureUnit := AContext.EnsureUnit;
  Result.Namespaces := AContext.Namespaces;
  Result.WithStatic := AContext.MethodKindStatic;
  Result.Style := AContext.Formatting;
end;

procedure TMethodWithoutSelfRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMethod: TCheckMethodWithoutSelf;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or AContext.NoMethodKind or
    (AContext.Refactorings.Methods = nil) then
  begin
    Exit;
  end;
  for mMethod in AContext.Refactorings.Methods.WithoutSelf(ScanOf(AContext)) do
  begin
    mFixes := nil;
    if mMethod.HasFix then
    begin
      mFixes := [TRuleFix.Create(mMethod.Fix.Title, mMethod.Fix.Edits, False)];
    end;
    // Mittel: Aufrufe über Methodenzeiger in anderen Units sieht die Regel nicht.
    AReport.Add(TTextRange.Create(mMethod.NamePosition, TTextPosition.Create(mMethod.NamePosition.Line,
      mMethod.NamePosition.Character + Length(mMethod.Name))),
      cTexts[TMethodWithoutSelfText.NoSelf].Fmt([mMethod.ClassName, mMethod.Name]),
      TRuleConfidence.Medium, mFixes);
  end;
end;

procedure RegisterMethodWithoutSelfRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TMethodWithoutSelfRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.MethodWithoutSelf', cTexts);

end.
