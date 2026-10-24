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
  Atlas.Common.Editing.InlineAccessor;

{ TTrivialAccessorRule }

function TTrivialAccessorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('trivial-accessor', TRuleSeverity.Hint,
    'Zugriffsmethode liest bzw. setzt nur ein Feld');
end;

procedure TTrivialAccessorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Options: TInlineAccessorOptions;
  Interfaces: TInterfaceDeclares;
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Accessor: TTrivialAccessor;
  Verb: string;
begin
  if (AContext.Tree = nil) or not AContext.InlineAccessorDiagnostic then
    Exit;
  Options := TInlineAccessorOptions.Default;
  Options.EqualityCheck := not AContext.NoAccessorEqualityCheck;
  Interfaces := TInlineAccessor.IndexInterfaces(AContext.Index);
  for Decl in TClassLayout.AllDecls(AContext.Tree) do
  begin
    Layout := TClassLayout.Read(AContext.Tree, AContext.Text, Decl);
    try
      for Accessor in TInlineAccessor.InClass(Layout, Options, Interfaces) do
      begin
        Verb := 'setzt';
        if Accessor.IsGetter then
          Verb := 'liefert';
        // Mittel: Aufrufe in anderen Units sieht die Regel nicht.
        AReport.Add(Accessor.NameRange, Format('%s %s nur %s: Die Property kann direkt auf das Feld zeigen ' +
          '(Glühbirne „Zugriffsmethode durch Feld ersetzen“).', [Accessor.Name, Verb, Accessor.Field]),
          TRuleConfidence.Medium);
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

end.
