unit Atlas.Common.Rules.Builtin.Recursion;

// Property-Falle (#623):
//   recursive-property-accessor   Getter liest bzw. Setter schreibt die eigene
//                                 Property (Result := Name in GetName) und
//                                 ruft sich damit endlos selbst auf.
// Die Analyse liefert TRecursionAnalysis.AccessorTraps. Hat die Klasse das
// Feld F<Name>, nennt die Meldung es und die Korrektur setzt es ein.
// Geerbte Properties und Accessoren in anderen Units sieht die Analyse nicht.

interface

uses
  Atlas.Common.Semantics.Recursion,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  RecursivePropertyAccessorRuleId = 'recursive-property-accessor';

type
  TRecursivePropertyAccessorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Meldungstext eines Treffers.</summary>
    class function Message(const ATrap: TAccessorTrap): string; static;
  end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract;

{ TRecursivePropertyAccessorRule }

function TRecursivePropertyAccessorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(RecursivePropertyAccessorRuleId, TRuleSeverity.Warning,
    'Getter liest oder Setter schreibt die eigene Property (endlose Rekursion)');
end;

class function TRecursivePropertyAccessorRule.Message(const ATrap: TAccessorTrap): string;
begin
  if ATrap.IsSetter then
    Result := Format('Setter %s schreibt die eigene Property %s und ruft sich damit endlos selbst auf',
      [ATrap.Accessor, ATrap.PropertyName])
  else
    Result := Format('Getter %s liest die eigene Property %s und ruft sich damit endlos selbst auf',
      [ATrap.Accessor, ATrap.PropertyName]);
  if ATrap.Field <> '' then
    Result := Result + Format('; das Feld %s verwenden', [ATrap.Field]);
end;

procedure TRecursivePropertyAccessorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Trap: TAccessorTrap;
begin
  if AContext.Tree = nil then
    Exit;
  for Trap in TRecursionAnalysis.AccessorTraps(AContext.Tree) do
    if Trap.Field <> '' then
      AReport.Add(Trap.Range, Message(Trap), [TRuleFix.Create(Format('Feld %s verwenden', [Trap.Field]),
        [TRuleEdit.Create(Trap.Range, Trap.Field)])])
    else
      AReport.Add(Trap.Range, Message(Trap));
end;

procedure RegisterRecursionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TRecursivePropertyAccessorRule.Create);
end;

end.
