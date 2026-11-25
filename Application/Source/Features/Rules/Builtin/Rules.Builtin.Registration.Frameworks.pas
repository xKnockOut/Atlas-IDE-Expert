unit Rules.Builtin.Registration.Frameworks;

// Anmeldung der eingebauten Prüfregeln für Bibliotheken und Plattform (RTL, Listen, Exceptions,
// Threads, Komponenten, Formulare, Datenbank, Dateien, Sicherheit, Open Tools API, Packages, Tests).
// Rules.Builtin ruft die Registration-Units nacheinander auf; nach Themen aufgeteilt, damit
// keine Unit zu viele Units einbindet (metric-uses-count).

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Bibliotheken und Plattform in ARegistry an.</summary>
procedure RegisterBuiltinFrameworkRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.Concurrency,
  Rules.Builtin.Components,
  Rules.Builtin.FormFields,
  Rules.Builtin.Security,
  Rules.Builtin.RtlPatterns,
  Rules.Builtin.RtlTypePatterns,
  Rules.Builtin.Exceptions,
  Rules.Builtin.PaletteIcons,
  Rules.Builtin.DataBinding,
  Rules.Builtin.DfmProperties,
  Rules.Builtin.SlashCommands,
  Rules.Builtin.FreeFields,
  Rules.Builtin.Packages,
  Rules.Builtin.OpenTools,
  Rules.Builtin.Testing,
  Rules.Builtin.Events,
  Rules.Builtin.Database,
  Rules.Builtin.Credentials,
  Rules.Builtin.DllExports,
  Rules.Builtin.Files,
  Rules.Builtin.Forms,
  Rules.Builtin.SharedState,
  Rules.Builtin.Platform,
  Rules.Builtin.Collections,
  Rules.Builtin.Automation,
  Rules.Builtin.ForbiddenSymbols;

procedure RegisterBuiltinFrameworkRules(const ARegistry: TRuleRegistry);
begin
  RegisterConcurrencyRules(ARegistry);
  RegisterComponentRules(ARegistry);
  RegisterFormFieldRules(ARegistry);
  RegisterSecurityRules(ARegistry);
  RegisterCredentialRules(ARegistry);
  RegisterRtlPatternRules(ARegistry);
  RegisterRtlTypePatternRules(ARegistry);
  RegisterExceptionRules(ARegistry);
  RegisterPaletteIconRules(ARegistry);
  RegisterDataBindingRules(ARegistry);
  RegisterDfmPropertyRules(ARegistry);
  RegisterSlashCommandRules(ARegistry);
  RegisterFreeFieldRules(ARegistry);
  RegisterPackageRules(ARegistry);
  RegisterOpenToolsRules(ARegistry);
  RegisterTestingRules(ARegistry);
  RegisterEventRules(ARegistry);
  RegisterDatabaseRules(ARegistry);
  RegisterDllExportRules(ARegistry);
  RegisterFileRules(ARegistry);
  RegisterFormRules(ARegistry);
  RegisterSharedStateRules(ARegistry);
  RegisterPlatformRules(ARegistry);
  RegisterCollectionRules(ARegistry);
  RegisterAutomationRules(ARegistry);
  RegisterForbiddenSymbolRules(ARegistry);
end;

end.
