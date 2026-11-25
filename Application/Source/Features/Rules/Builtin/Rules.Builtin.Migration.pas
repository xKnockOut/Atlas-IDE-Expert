unit Rules.Builtin.Migration;

// Anmeldung der Migrationsregeln (Gruppe „Migration“, "group:migration"):
//   Win64 (#112)          pointer-integer-cast, handle-as-integer, window-long-ptr, asm-without-win64
//                         (Rules.Builtin.Migration.Win64)
//   Unicode/ANSI (#117)   char-count-as-bytes, ansi-api-call (Rules.Builtin.Migration.Unicode)
// Gemeinsames (inaktive Zweige, Plattformzweige, Typlisten) in Rules.Builtin.Migration.Shared.

interface

uses
  Rules.Registry;

/// <summary>Meldet die Migrationsregeln in ARegistry an.</summary>
procedure RegisterMigrationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.Migration.Win64,
  Rules.Builtin.Migration.Unicode;

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
