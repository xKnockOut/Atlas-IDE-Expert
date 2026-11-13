unit Atlas.Common.Rules.Builtin.Registration.Frameworks;

// Anmeldung der eingebauten Prüfregeln für Bibliotheken und Plattform (RTL, Listen, Exceptions,
// Threads, Komponenten, Formulare, Datenbank, Dateien, Sicherheit, Open Tools API, Packages, Tests).
// Atlas.Common.Rules.Builtin ruft die Registration-Units nacheinander auf; nach Themen aufgeteilt, damit
// keine Unit zu viele Units einbindet (metric-uses-count).

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Bibliotheken und Plattform in ARegistry an.</summary>
procedure RegisterBuiltinFrameworkRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Rules.Builtin.Components,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Rules.Builtin.Security,
  Atlas.Common.Rules.Builtin.RtlPatterns,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.Exceptions,
  Atlas.Common.Rules.Builtin.PaletteIcons,
  Atlas.Common.Rules.Builtin.DataBinding,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Atlas.Common.Rules.Builtin.SlashCommands,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Common.Rules.Builtin.Packages,
  Atlas.Common.Rules.Builtin.OpenTools,
  Atlas.Common.Rules.Builtin.Testing,
  Atlas.Common.Rules.Builtin.Events,
  Atlas.Common.Rules.Builtin.Database,
  Atlas.Common.Rules.Builtin.Credentials,
  Atlas.Common.Rules.Builtin.DllExports,
  Atlas.Common.Rules.Builtin.Files,
  Atlas.Common.Rules.Builtin.Forms,
  Atlas.Common.Rules.Builtin.SharedState,
  Atlas.Common.Rules.Builtin.Platform,
  Atlas.Common.Rules.Builtin.Collections,
  Atlas.Common.Rules.Builtin.Automation,
  Atlas.Common.Rules.Builtin.ForbiddenSymbols;

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
