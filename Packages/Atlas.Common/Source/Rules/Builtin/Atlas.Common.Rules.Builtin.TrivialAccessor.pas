unit Atlas.Common.Rules.Builtin.TrivialAccessor;

// Triviale Zugriffsmethode (#717):
//   trivial-accessor  Getter, der nur ein Feld liefert, bzw. Setter, der nur
//                     ein Feld setzt (mit refactoring.inlineAccessorEquality-
//                     Check auch mit Gleichheitsprüfung). Die Property könnte
//                     direkt auf das Feld zeigen. Hinweis, nur mit
//                     refactoring.inlineAccessorDiagnostic (Vorgabe aus) und
//                     refactoring.inlineAccessor. Keine Korrektur in der
//                     Regel: Ob die Methode anderswo aufgerufen wird, klärt
//                     erst die Code-Aktion „Zugriffsmethode durch Feld
//                     ersetzen“ an derselben Stelle über die Referenzsuche.
//
// Erkennung liefert TInlineAccessor (Editing).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TTrivialAccessorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterTrivialAccessorRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.InlineAccessor,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TTrivialAccessorText = (Title, Setter, Getter);

const
  cTexts: array[TTrivialAccessorText] of TAtlasText = (
    (De: 'Zugriffsmethode liest bzw. setzt nur ein Feld'; En: 'Access method only reads or sets a field'),
    (De: '%s setzt nur %s: Die Property kann direkt auf das Feld zeigen (Glühbirne „Zugriffsmethode durch Feld ' +
      'ersetzen“).';
     En: '%s only sets %s: the property can point directly to the field (light bulb “Replace accessor with field”).'),
    (De: '%s liefert nur %s: Die Property kann direkt auf das Feld zeigen (Glühbirne „Zugriffsmethode durch Feld ' +
      'ersetzen“).';
     En: '%s only returns %s: the property can point directly to the field (light bulb “Replace accessor with ' +
      'field”).'));

{$SCOPEDENUMS OFF}

{ TTrivialAccessorRule }

function TTrivialAccessorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('trivial-accessor', TRuleSeverity.Hint,
    cTexts[TTrivialAccessorText.Title].Text);
end;

procedure TTrivialAccessorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Options: TInlineAccessorOptions;
  Interfaces: TInterfaceDeclares;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Accessor: TTrivialAccessor;
  Verb: TTrivialAccessorText;
begin
  if (AContext.Tree = nil) or not AContext.InlineAccessorDiagnostic then
  begin
    Exit;
  end;
  Options := TInlineAccessorOptions.Default;
  Options.EqualityCheck := not AContext.NoAccessorEqualityCheck;
  Interfaces := TInlineAccessor.IndexInterfaces(AContext.Index);
  for Decl in TClassLayout.AllDecls(AContext.Tree) do
  begin
    Layout := TClassLayout.Read(AContext.Tree, AContext.Text, Decl);
    try
      for Accessor in TInlineAccessor.InClass(Layout, Options, Interfaces) do
      begin
        Verb := TTrivialAccessorText.Setter;
        if Accessor.IsGetter then
        begin
          Verb := TTrivialAccessorText.Getter;
        end;
        // Mittel: Aufrufe in anderen Units sieht die Regel nicht.
        AReport.Add(Accessor.NameRange, cTexts[Verb].Fmt([Accessor.Name, Accessor.Field]), TRuleConfidence.Medium);
      end;
    finally
      Layout.Free;
    end;
  end;
end;

procedure RegisterTrivialAccessorRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TTrivialAccessorRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TrivialAccessor', cTexts);

end.
