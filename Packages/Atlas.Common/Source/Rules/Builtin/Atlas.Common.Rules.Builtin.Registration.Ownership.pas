unit Atlas.Common.Rules.Builtin.Registration.Ownership;

// Anmeldung der eingebauten Prüfregeln für Besitz, Freigabe und Lecks (Felder, rohe Speicherblöcke, Objekte in
// Stringlisten, Komponenten hinter Interfaces, lokale Objekte und Fabrikergebnisse, Methodenreferenzen und
// Ereignisse, Referenzzählung von Interfaces). Atlas.Common.Rules.Builtin ruft die Registration-Units nacheinander
// auf; nach Themen aufgeteilt, damit keine Unit zu viele Units einbindet (metric-uses-count).

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Besitz, Freigabe und Lecks in ARegistry an.</summary>
procedure RegisterBuiltinOwnershipRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Common.Rules.Builtin.Ownership.RawMemory,
  Atlas.Common.Rules.Builtin.Ownership.StringListObjects,
  Atlas.Common.Rules.Builtin.Ownership.ComponentInterface,
  Atlas.Common.Rules.Builtin.Ownership.LocalObjects,
  Atlas.Common.Rules.Builtin.Ownership.MethodReferences,
  Atlas.Common.Rules.Builtin.Ownership.Interfaces;

procedure RegisterBuiltinOwnershipRules(const ARegistry: TRuleRegistry);
begin
  RegisterOwnershipRules(ARegistry);
  RegisterOwnershipRawMemoryRules(ARegistry);
  RegisterOwnershipStringListObjectsRules(ARegistry);
  RegisterOwnershipComponentInterfaceRules(ARegistry);
  RegisterOwnershipLocalObjectRules(ARegistry);
  RegisterOwnershipMethodReferenceRules(ARegistry);
  RegisterOwnershipInterfaceRules(ARegistry);
end;

end.
