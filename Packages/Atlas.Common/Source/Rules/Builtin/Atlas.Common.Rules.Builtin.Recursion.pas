unit Atlas.Common.Rules.Builtin.Recursion;

// Property-Falle (#623, #910):
//   setter-recursion   Setter schreibt bzw. Getter liest die eigene Property
//                      (Name := Value in SetName) und ruft sich damit endlos
//                      selbst auf. Fehler mit hoher Konfidenz; bis #910 hieß
//                      die Regel recursive-property-accessor (TRuleIdAliases).
// Die Analyse liefert TRecursionAnalysis.AccessorTraps. Die Korrektur setzt
// das Feld ein: aus read/write der Property, sonst F<Name>, wenn die Klasse
// es hat. Geerbte Properties und Accessoren in anderen Units sieht die
// Analyse nicht.

interface

uses
  Atlas.Common.Semantics.Recursion,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  SetterRecursionRuleId = 'setter-recursion';

type
  TSetterRecursionRule = class(TInterfacedObject, IRule)
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

{ TSetterRecursionRule }

function TSetterRecursionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(SetterRecursionRuleId, TRuleSeverity.Error,
    'Setter oder Getter ruft sich selbst auf (Endlosrekursion)');
end;

class function TSetterRecursionRule.Message(const ATrap: TAccessorTrap): string;
begin
  if ATrap.IsSetter then
    Result := Format('Zuweisung an die Property %s im eigenen Setter: Endlosrekursion.', [ATrap.PropertyName])
  else
    Result := Format('Lesen der Property %s im eigenen Getter: Endlosrekursion.', [ATrap.PropertyName]);
end;

procedure TSetterRecursionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
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
  ARegistry.Register(TSetterRecursionRule.Create);
end;

end.
