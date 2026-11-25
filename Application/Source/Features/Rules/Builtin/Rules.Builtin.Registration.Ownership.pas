unit Rules.Builtin.Registration.Ownership;

// Anmeldung der eingebauten Prüfregeln für Besitz, Freigabe und Lecks (Felder, rohe Speicherblöcke, Objekte in
// Stringlisten, Komponenten hinter Interfaces, lokale Objekte und Fabrikergebnisse, mehrere Objekte an einem try,
// Methodenreferenzen und Ereignisse, Referenzzählung von Interfaces). Rules.Builtin ruft die Registration-Units nacheinander
// auf; nach Themen aufgeteilt, damit keine Unit zu viele Units einbindet (metric-uses-count).

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Besitz, Freigabe und Lecks in ARegistry an.</summary>
procedure RegisterBuiltinOwnershipRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.Ownership,
  Rules.Builtin.Ownership.RawMemory,
  Rules.Builtin.Ownership.StringListObjects,
  Rules.Builtin.Ownership.ComponentInterface,
  Rules.Builtin.Ownership.LocalObjects,
  Rules.Builtin.Ownership.CreateOrder,
  Rules.Builtin.Ownership.MethodReferences,
  Rules.Builtin.Ownership.Interfaces;

procedure RegisterBuiltinOwnershipRules(const ARegistry: TRuleRegistry);
begin
  RegisterOwnershipRules(ARegistry);
  RegisterOwnershipRawMemoryRules(ARegistry);
  RegisterOwnershipStringListObjectsRules(ARegistry);
  RegisterOwnershipComponentInterfaceRules(ARegistry);
  RegisterOwnershipLocalObjectRules(ARegistry);
  RegisterOwnershipCreateOrderRules(ARegistry);
  RegisterOwnershipMethodReferenceRules(ARegistry);
  RegisterOwnershipInterfaceRules(ARegistry);
end;

end.
