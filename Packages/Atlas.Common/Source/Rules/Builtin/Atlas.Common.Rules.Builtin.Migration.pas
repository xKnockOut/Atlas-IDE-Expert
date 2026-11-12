unit Atlas.Common.Rules.Builtin.Migration;

// Anmeldung der Migrationsregeln (Gruppe „Migration“, "group:migration"):
//   Win64 (#112)          pointer-integer-cast, handle-as-integer, window-long-ptr, asm-without-win64
//                         (Atlas.Common.Rules.Builtin.Migration.Win64)
//   Unicode/ANSI (#117)   char-count-as-bytes, ansi-api-call (Atlas.Common.Rules.Builtin.Migration.Unicode)
// Gemeinsames (inaktive Zweige, Plattformzweige, Typlisten) in Atlas.Common.Rules.Builtin.Migration.Shared.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Migrationsregeln in ARegistry an.</summary>
procedure RegisterMigrationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Migration.Win64,
  Atlas.Common.Rules.Builtin.Migration.Unicode;

procedure RegisterMigrationRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPointerIntegerCastRule.Create);
  ARegistry.Register(THandleAsIntegerRule.Create);
  ARegistry.Register(TWindowLongPtrRule.Create);
  ARegistry.Register(TAsmWithoutWin64Rule.Create);
  ARegistry.Register(TCharCountAsBytesRule.Create);
  ARegistry.Register(TAnsiApiCallRule.Create);
end;

end.
