unit Atlas.Common.Rules.Builtin.Migration.Win64.Tests;

// Tests der Win64-Migrationsregeln (#112):
// pointer-integer-cast: Beispiel mit Korrektur, Cardinal wird NativeUInt, @X und Pointer(…) ohne Typauflösung,
// Klasse aus Integer, stille Fälle (Integer(I), Pointer(I), unbekannte Typen, bedingte Deklaration),
// Plattformzweige, inaktive Zweige, alte Delphi-Versionen, Abschalten über Regel und Gruppe.
// handle-as-integer: Fensterprozedur mit Korrekturen, Zuweisung eines Handles samt Deklarationskorrektur, stille
// Fälle. window-long-ptr: Korrektur mit Index und LONG_PTR, …W-Variante, 32-Bit-Indizes still.
// asm-without-win64: Routine und asm-Anweisung, Plattformzweige, 64-Bit-Register, Free Pascal.
// Migration.Shared: Plattformbedingungen, Typlisten, Versionen; Anmeldung aller sechs Regeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPointerIntegerCastTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure UnsignedAndSyntacticPointers;
    [Test]
    procedure ClassFromInteger;
    [Test]
    procedure IntegersAndUnknownAreSilent;
    [Test]
    procedure PlatformBranchesAreSilent;
    [Test]
    procedure InactiveBranchIsSilent;
    [Test]
    procedure OldDelphiIsSilent;
    [Test]
    procedure OffAndGroupOff;
  end;

  [TestFixture]
  THandleAsIntegerTests = class
  public
    [Test]
    procedure WindowProcedureWithFixes;
    [Test]
    procedure HandleAssignedToInteger;
    [Test]
    procedure MatchingTypesAreSilent;
  end;

  [TestFixture]
  TWindowLongPtrTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure WideVariantAndGetter;
    [Test]
    procedure ValueIndicesAreSilent;
  end;

  [TestFixture]
  TAsmWithoutWin64Tests = class
  public
    [Test]
    procedure RoutineAndStatement;
    [Test]
    procedure GuardedAndX64AreSilent;
    [Test]
    procedure FreePascalIsSilent;
  end;

  [TestFixture]
  TMigrationSharedTests = class
  public
    [Test]
    procedure PlatformConditions;
    [Test]
    procedure TypeLists;
    [Test]
    procedure VersionsAndRegistration;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.Builtin.Migration,
  Atlas.Common.Rules.Builtin.Migration.Shared,
  Atlas.Common.Rules.Builtin.Migration.Win64,
  Atlas.Tests.RuleAssert;

/// <summary>Routine Pruefen mit den Deklarationen ADecls (var-Abschnitt) und den Anweisungen ABody.</summary>
function Routine(const ADecls, ABody: string): string;
begin
  Result := 'unit Zeiger;'#10'interface'#10'type'#10'  TKunde = class'#10'  end;'#10'  IKunde = interface'#10 +
    '  end;'#10'implementation'#10'procedure Pruefen;'#10'var'#10 + ADecls + 'begin'#10 + ABody + 'end;'#10'end.';
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

function Applied(const ASource: string; const AFix: TRuleFix): string;
begin
  Result := TTextChanges.Apply(ASource, AFix.Edits);
end;

/// <summary>Treffer von ARule mit der Delphi-Version AVersion und den inaktiven Bereichen AInactive.</summary>
function ContextFindings(ARule: IRule; const ASource, AVersion: string;
  const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.Text := ASource;
  mContext.RelativePath := 'Zeiger.pas';
  mContext.DelphiVersion := AVersion;
  mContext.InactiveRanges := AInactive;
  Result := TRuleAssert.ContextFindings(ARule, mContext, '');
end;

{ TPointerIntegerCastTests }

procedure TPointerIntegerCastTests.IssueExampleWithFix;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  P: Pointer;'#10'  Kunde: TKunde;'#10'  Zahl: Integer;'#10,
    '  Zahl := Integer(P);'#10'  Zahl := LongInt(Kunde);'#10);
  mFound := TRuleAssert.Findings(TPointerIntegerCastRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cPointerIntegerCastRuleId, mFound[0].RuleId);
  Assert.AreEqual('Integer(P): P ist Pointer; unter Win64 gehen die oberen 32 Bit verloren.', mFound[0].Message);
  Assert.AreEqual('LongInt(Kunde): Kunde ist TKunde; unter Win64 gehen die oberen 32 Bit verloren.',
    mFound[1].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('NativeInt statt Integer verwenden', mFound[0].Fixes[0].Title);
  Assert.IsTrue(Pos('  Zahl := NativeInt(P);'#10, Applied(mSource, mFound[0].Fixes[0])) > 0);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPointerIntegerCastRule.Create,
    Applied(mSource, mFound[0].Fixes[0])))));
end;

procedure TPointerIntegerCastTests.UnsignedAndSyntacticPointers;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  Kunde: IKunde;'#10'  Zahl: Cardinal;'#10,
    '  Zahl := Cardinal(Kunde);'#10'  Zahl := DWORD(@Pruefen);'#10'  Zahl := Cardinal(Pointer(Zahl));'#10 +
    '  Zahl := LongWord((PChar(''abc'')));'#10);
  mFound := TRuleAssert.Findings(TPointerIntegerCastRule.Create, mSource);
  Assert.AreEqual(4, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Cardinal(Kunde): Kunde ist IKunde; unter Win64 gehen die oberen 32 Bit verloren.',
    mFound[0].Message);
  Assert.AreEqual('DWORD(@Pruefen): @Pruefen ist Pointer; unter Win64 gehen die oberen 32 Bit verloren.',
    mFound[1].Message);
  Assert.AreEqual('NativeUInt statt Cardinal verwenden', mFound[0].Fixes[0].Title);
  Assert.IsTrue(Pos('  Zahl := NativeUInt(@Pruefen);'#10, Applied(mSource, mFound[1].Fixes[0])) > 0);
end;

procedure TPointerIntegerCastTests.ClassFromInteger;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TPointerIntegerCastRule.Create, Routine('  Zahl: Integer;'#10'  K: TKunde;'#10,
    '  K := TKunde(Zahl);'#10'  K := TKunde(Pointer(Zahl));'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('TKunde(Zahl): Zahl ist Integer und kann unter Win64 keinen Zeiger halten.', mFound[0].Message);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TPointerIntegerCastTests.IntegersAndUnknownAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TPointerIntegerCastRule.Create, Routine(
    '  Zahl: Integer;'#10'  N: NativeInt;'#10'  B: Byte;'#10'  K: TKunde;'#10 +
    '  {$IFDEF ALT}'#10'  Wechselnd: Pointer;'#10'  {$ELSE}'#10'  Wechselnd: Integer;'#10'  {$ENDIF}'#10,
    '  Zahl := Integer(Zahl);'#10'  Zahl := Integer(B);'#10'  Zahl := Integer(N);'#10 +
    '  K := TKunde(N);'#10'  Zahl := Integer(Unbekannt);'#10'  Zahl := Integer(Wechselnd);'#10 +
    '  K := TKunde(Pointer(Zahl));'#10'  Zahl := NativeInt(K);'#10))));
end;

procedure TPointerIntegerCastTests.PlatformBranchesAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TPointerIntegerCastRule.Create, Routine(
    '  P: Pointer;'#10'  Zahl: Integer;'#10,
    '  {$IFDEF CPUX86}'#10'  Zahl := Integer(P);'#10'  {$ELSE}'#10'  Zahl := Integer(P);'#10'  {$ENDIF}'#10 +
    '  {$IF SizeOf(Pointer) = 4}'#10'  Zahl := Integer(P);'#10'  {$IFEND}'#10 +
    '  {$IFNDEF WIN64}'#10'  {$IFDEF DEBUG}'#10'  Zahl := Integer(P);'#10'  {$ENDIF}'#10'  {$ENDIF}'#10))));
  // Eine Bedingung ohne Plattform schützt nicht.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPointerIntegerCastRule.Create, Routine(
    '  P: Pointer;'#10'  Zahl: Integer;'#10, '  {$IFDEF DEBUG}'#10'  Zahl := Integer(P);'#10'  {$ENDIF}'#10)))));
end;

procedure TPointerIntegerCastTests.InactiveBranchIsSilent;
var
  mSource: string;
begin
  mSource := Routine('  P: Pointer;'#10'  Zahl: Integer;'#10, '  Zahl := Integer(P);'#10);
  // Zeile 13 ist die Zuweisung.
  Assert.AreEqual(1, Integer(Length(ContextFindings(TPointerIntegerCastRule.Create, mSource, '', nil))));
  Assert.AreEqual(0, Integer(Length(ContextFindings(TPointerIntegerCastRule.Create, mSource, '',
    [TTextRange.Create(13, 0, 14, 0)]))));
end;

procedure TPointerIntegerCastTests.OldDelphiIsSilent;
var
  mSource: string;
begin
  mSource := Routine('  P: Pointer;'#10'  Zahl: Integer;'#10, '  Zahl := Integer(P);'#10);
  Assert.AreEqual(0, Integer(Length(ContextFindings(TPointerIntegerCastRule.Create, mSource, '8.0', nil))));
  Assert.AreEqual(1, Integer(Length(ContextFindings(TPointerIntegerCastRule.Create, mSource, '9.0', nil))));
  Assert.AreEqual(1, Integer(Length(ContextFindings(TPointerIntegerCastRule.Create, mSource, '37.0', nil))));
end;

procedure TPointerIntegerCastTests.OffAndGroupOff;
var
  mSource: string;
begin
  mSource := Routine('  P: Pointer;'#10'  Zahl: Integer;'#10, '  Zahl := Integer(P);'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPointerIntegerCastRule.Create, mSource, '',
    'Source/Zeiger.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPointerIntegerCastRule.Create, mSource,
    '{"rules": {"pointer-integer-cast": "off"}}', 'Source/Zeiger.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPointerIntegerCastRule.Create, mSource,
    '{"rules": {"group:migration": "off"}}', 'Source/Zeiger.pas'))));
end;

{ THandleAsIntegerTests }

procedure THandleAsIntegerTests.WindowProcedureWithFixes;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
  mEdits: TArray<TTextEdit>;
begin
  mSource := 'unit Fenster;'#10'interface'#10'implementation'#10 +
    'function FensterProc(Wnd: HWND; Msg: UINT; wParam: Longint; lParam: Longint): Longint; stdcall;'#10 +
    'begin'#10'  Result := 0;'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(THandleAsIntegerRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cHandleAsIntegerRuleId, mFound[0].RuleId);
  Assert.AreEqual('Parameter wParam ist Longint; unter Win64 ist WPARAM 64 Bit breit.', mFound[0].Message);
  Assert.AreEqual('Parameter lParam ist Longint; unter Win64 ist LPARAM 64 Bit breit.', mFound[1].Message);
  Assert.AreEqual('Ergebnis von FensterProc ist Longint; unter Win64 ist LRESULT 64 Bit breit.', mFound[2].Message);
  Assert.AreEqual('Typ WPARAM verwenden', mFound[0].Fixes[0].Title);
  mEdits := nil;
  for mFinding in mFound do
  begin
    mEdits := mEdits + mFinding.Fixes[0].Edits;
  end;
  mFixed := TTextChanges.Apply(mSource, mEdits);
  Assert.IsTrue(Pos('wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;', mFixed) > 0, mFixed);
  Assert.AreEqual('', Messages(TRuleAssert.Findings(THandleAsIntegerRule.Create, mFixed)));
  // Zwei Namen in einer Deklaration: Die Korrektur träfe beide, die Regel schweigt.
  Assert.AreEqual('', Messages(TRuleAssert.Findings(THandleAsIntegerRule.Create, 'unit Fenster;'#10'interface'#10 +
    'implementation'#10'procedure Senden(wParam, lParam: Integer);'#10'begin'#10'end;'#10'end.')));
end;

procedure THandleAsIntegerTests.HandleAssignedToInteger;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  Fenster: HWND;'#10'  Zahl: Integer;'#10'  A, B: Cardinal;'#10,
    '  Zahl := Fenster;'#10'  A := Fenster;'#10);
  mFound := TRuleAssert.Findings(THandleAsIntegerRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Zahl ist Integer, Fenster ist HWND; unter Win64 gehen die oberen 32 Bit verloren.',
    mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('Zahl als HWND deklarieren', mFound[0].Fixes[0].Title);
  Assert.IsTrue(Pos('  Zahl: HWND;'#10, Applied(mSource, mFound[0].Fixes[0])) > 0);
  // A, B: Cardinal: keine Deklarationskorrektur.
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
end;

procedure THandleAsIntegerTests.MatchingTypesAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(THandleAsIntegerRule.Create, Routine(
    '  Fenster: HWND;'#10'  H: THandle;'#10'  N: NativeInt;'#10'  Zahl: Integer;'#10'  Wert: Int64;'#10,
    '  H := Fenster;'#10'  Zahl := N;'#10'  Wert := Fenster;'#10'  Zahl := Unbekannt;'#10'  Zahl := 5;'#10))));
  Assert.AreEqual('', Messages(TRuleAssert.Findings(THandleAsIntegerRule.Create, 'unit Fenster;'#10'interface'#10 +
    'implementation'#10'function Senden: LRESULT;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'procedure Zaehlen;'#10'var'#10'  Anzahl: Integer;'#10'begin'#10'  Anzahl := Senden;'#10'end;'#10'end.')));
  Assert.AreEqual('', Messages(TRuleAssert.Findings(THandleAsIntegerRule.Create, 'unit Fenster;'#10'interface'#10 +
    'implementation'#10'function Rueckruf(AWParam: WPARAM; ALParam: LPARAM; Zahl: Integer): LRESULT;'#10 +
    'begin'#10'  Result := 0;'#10'end;'#10'function Richtung(AMessage: Cardinal; AWParam, ALParam: NativeInt): ' +
    'Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10'function Summe(Wert: Integer): Integer;'#10'begin'#10 +
    '  Result := Wert;'#10'end;'#10'end.')));
end;

{ TWindowLongPtrTests }

procedure TWindowLongPtrTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('', '  SetWindowLong(Handle, GWL_WNDPROC, Integer(@Pruefen));'#10);
  mFound := TRuleAssert.Findings(TWindowLongPtrRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cWindowLongPtrRuleId, mFound[0].RuleId);
  Assert.AreEqual('SetWindowLong mit GWL_WNDPROC liest bzw. schreibt unter Win64 nur 32 Bit eines Zeigers oder ' +
    'Handles.', mFound[0].Message);
  Assert.AreEqual('SetWindowLongPtr mit GWLP_WNDPROC verwenden', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  SetWindowLongPtr(Handle, GWLP_WNDPROC, LONG_PTR(@Pruefen));'#10, mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TWindowLongPtrRule.Create, mFixed))));
end;

procedure TWindowLongPtrTests.WideVariantAndGetter;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  P: Pointer;'#10, '  P := Pointer(GetWindowLongW(Handle, GWL_USERDATA));'#10 +
    '  SetClassLong(Handle, GCL_HICON, Symbol);'#10);
  mFound := TRuleAssert.Findings(TWindowLongPtrRule.Create, mSource);
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.IsTrue(Pos('  P := Pointer(GetWindowLongPtrW(Handle, GWLP_USERDATA));'#10,
    Applied(mSource, mFound[0].Fixes[0])) > 0);
  Assert.IsTrue(Pos('  SetClassLongPtr(Handle, GCLP_HICON, Symbol);'#10, Applied(mSource, mFound[1].Fixes[0])) > 0);
  Assert.AreEqual('GWLP_HWNDPARENT', TWindowLongPtrRule.PtrIndex('gwl_hwndparent'));
  Assert.AreEqual('', TWindowLongPtrRule.PtrRoutine('SetWindowLongPtr'));
  Assert.AreEqual('GetClassLongPtrA', TWindowLongPtrRule.PtrRoutine('GetClassLongA'));
end;

procedure TWindowLongPtrTests.ValueIndicesAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TWindowLongPtrRule.Create, Routine('',
    '  SetWindowLong(Handle, GWL_STYLE, 0);'#10'  GetWindowLong(Handle, GWL_EXSTYLE);'#10 +
    '  SetWindowLongPtr(Handle, GWLP_WNDPROC, LONG_PTR(@Pruefen));'#10'  SetWindowLong(Handle, Index, 0);'#10 +
    '  {$IFDEF WIN32}'#10'  SetWindowLong(Handle, GWL_WNDPROC, Integer(@Pruefen));'#10'  {$ENDIF}'#10))));
end;

{ TAsmWithoutWin64Tests }

procedure TAsmWithoutWin64Tests.RoutineAndStatement;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TAsmWithoutWin64Rule.Create, 'unit Schnell;'#10'interface'#10'implementation'#10 +
    'function Tausche(Wert: Cardinal): Cardinal;'#10'asm'#10'  bswap eax'#10'end;'#10 +
    'procedure Warten;'#10'begin'#10'  asm'#10'    pause'#10'  end;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cAsmWithoutWin64RuleId, mFound[0].RuleId);
  Assert.AreEqual('Routine Tausche besteht aus x86-Assembler ohne Zweig für Win64 ({$IFDEF CPUX64} bzw. ' +
    'PUREPASCAL).', mFound[0].Message);
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(0, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(3, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('asm innerhalb von begin … end übersetzt dcc64 nicht (E1025); ein Zweig nach Plattform fehlt.',
    mFound[1].Message);
  Assert.AreEqual(9, mFound[1].Range.StartPos.Line);
end;

procedure TAsmWithoutWin64Tests.GuardedAndX64AreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TAsmWithoutWin64Rule.Create, 'unit Schnell;'#10'interface'#10 +
    'implementation'#10'function Tausche(Wert: Cardinal): Cardinal;'#10'{$IFDEF CPUX86}'#10'asm'#10 +
    '  bswap eax'#10'end;'#10'{$ELSE}'#10'begin'#10'  Result := Wert;'#10'end;'#10'{$ENDIF}'#10 +
    'function Breit(Wert: Int64): Int64;'#10'asm'#10'  mov rax, rcx'#10'end;'#10 +
    'procedure Warten;'#10'begin'#10'  {$IFNDEF PUREPASCAL}'#10'  asm'#10'    pause'#10'  end;'#10 +
    '  {$ENDIF}'#10'end;'#10'end.')));
  Assert.IsTrue(TAsmWithoutWin64Rule.Is64BitRegister('R8D'));
  Assert.IsTrue(TAsmWithoutWin64Rule.Is64BitRegister('rsp'));
  Assert.IsFalse(TAsmWithoutWin64Rule.Is64BitRegister('r7'));
  Assert.IsFalse(TAsmWithoutWin64Rule.Is64BitRegister('Rest'));
end;

procedure TAsmWithoutWin64Tests.FreePascalIsSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TAsmWithoutWin64Rule.Create, 'unit Schnell;'#10 +
    '{$MODE DELPHI}'#10'interface'#10'implementation'#10'function Tausche(Wert: Cardinal): Cardinal;'#10'asm'#10 +
    '  bswap eax'#10'end;'#10'end.')));
end;

{ TMigrationSharedTests }

procedure TMigrationSharedTests.PlatformConditions;
begin
  Assert.IsTrue(TMigrationTypes.IsPlatformCondition('{$IFDEF CPUX64}'));
  Assert.IsTrue(TMigrationTypes.IsPlatformCondition('{$IF Defined(Win32) or Defined(LINUX)}'));
  Assert.IsTrue(TMigrationTypes.IsPlatformCondition('{$IFNDEF PUREPASCAL}'));
  Assert.IsTrue(TMigrationTypes.IsPlatformCondition('{$IF SizeOf(Pointer) = 8}'));
  Assert.IsTrue(TMigrationTypes.IsPlatformCondition('{$IFDEF X86ASM}'));
  Assert.IsFalse(TMigrationTypes.IsPlatformCondition('{$IFDEF DEBUG}'));
  Assert.IsFalse(TMigrationTypes.IsPlatformCondition('{$IF CompilerVersion >= 36}'));
  Assert.IsFalse(TMigrationTypes.IsPlatformCondition('{$IFDEF MSWINDOWS}'));
end;

procedure TMigrationSharedTests.TypeLists;
begin
  Assert.IsTrue(TMigrationTypes.Is32BitInteger('longint'));
  Assert.IsTrue(TMigrationTypes.Is32BitInteger('DWORD'));
  Assert.IsFalse(TMigrationTypes.Is32BitInteger('NativeInt'));
  Assert.IsTrue(TMigrationTypes.IsUnsigned32('LongWord'));
  Assert.IsFalse(TMigrationTypes.IsUnsigned32('Integer'));
  Assert.IsTrue(TMigrationTypes.IsPointerSizedAlias('lparam'));
  Assert.IsFalse(TMigrationTypes.IsPointerSizedAlias('NativeInt'));
  Assert.IsTrue(TMigrationTypes.IsUnicodeString('WideString'));
  Assert.IsFalse(TMigrationTypes.IsUnicodeString('AnsiString'));
  Assert.IsTrue(TMigrationTypes.IsWideCharPointer('PWideChar'));
  Assert.IsFalse(TMigrationTypes.IsWideCharPointer('PAnsiChar'));
end;

procedure TMigrationSharedTests.VersionsAndRegistration;
var
  mRegistry: TRuleRegistry;
  mRule: IRule;
begin
  mRegistry := TRuleRegistry.Create;
  try
    RegisterMigrationRules(mRegistry);
    Assert.AreEqual(6, Integer(Length(mRegistry.Rules)));
    Assert.IsTrue(mRegistry.Find(cAsmWithoutWin64RuleId, mRule));
  finally
    mRegistry.Free;
  end;
  Assert.IsTrue(TMigrationTypes.Win64Available(''));
  Assert.IsFalse(TMigrationTypes.Win64Available('8.0'));
  Assert.IsTrue(TMigrationTypes.Win64Available('9.0'));
  Assert.IsFalse(TMigrationTypes.UnicodeAvailable('5.0'));
  Assert.IsTrue(TMigrationTypes.UnicodeAvailable('6.0'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPointerIntegerCastTests);
  TDUnitX.RegisterTestFixture(THandleAsIntegerTests);
  TDUnitX.RegisterTestFixture(TWindowLongPtrTests);
  TDUnitX.RegisterTestFixture(TAsmWithoutWin64Tests);
  TDUnitX.RegisterTestFixture(TMigrationSharedTests);

end.
