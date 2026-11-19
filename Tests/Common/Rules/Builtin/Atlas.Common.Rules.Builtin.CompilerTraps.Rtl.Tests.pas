unit Atlas.Common.Rules.Builtin.CompilerTraps.Rtl.Tests;

// Tests der RTL-Lücken aus #2309: Namen, die Delphis Winapi.Windows nicht kennt (OpenThread, Zugriffsrechte),
// Routinen nur aus Winapi.Windows (GetTickCount64, MulDiv) ohne die Unit in uses und Write-Überschreibungen von
// TStream ohne die NativeInt-Fassung, jeweils mit stillen Fällen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerTrapsRtlTests = class
  public
    [Test]
    procedure MissingWinapiDeclaration;
    [Test]
    procedure MissingWinapiDeclarationSilentCases;
    [Test]
    procedure WindowsOnlyRoutineWithoutUses;
    [Test]
    procedure WindowsOnlyRoutineSilentCases;
    [Test]
    procedure WindowsOnlyRoutineInInactiveBranch;
    [Test]
    procedure StreamWriteWithoutNativeInt;
    [Test]
    procedure StreamWriteSilentCases;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.CompilerTraps.Rtl,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

/// <summary>Index mit Werk.Thread (deklariert OpenThread selbst) und FPCs Windows (deklariert es auch).</summary>
function ThreadIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Werk.Thread;'#10'interface'#10 +
    'function OpenThread(A: Cardinal; B: Boolean; C: Cardinal): THandle;'#10'implementation'#10 +
    'function OpenThread(A: Cardinal; B: Boolean; C: Cardinal): THandle;'#10'begin'#10'  Result := 0;'#10'end;'#10 +
    'end.', 'C:\P\Werk.Thread.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Windows;'#10'interface'#10'const'#10 +
    '  THREAD_SUSPEND_RESUME = 2;'#10'function GetTickCount64: UInt64;'#10'implementation'#10 +
    'function GetTickCount64: UInt64;'#10'begin'#10'  Result := 0;'#10'end;'#10'end.', 'C:\Fpc\Windows.pas', nil));
end;

/// <summary>Treffer von stream-write-nativeint auf ASource für die Delphi-Version AVersion.</summary>
function StreamFindings(const ASource, AVersion: string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'U';
  mContext.Text := ASource;
  mContext.DelphiVersion := AVersion;
  Result := TRuleAssert.ContextFindings(TStreamWriteNativeIntRule.Create, mContext, '');
end;

{ TCompilerTrapsRtlTests }

procedure TCompilerTrapsRtlTests.MissingWinapiDeclaration;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  Winapi.Windows;'#10'procedure Lauf;'#10 +
    'var'#10'  H: THandle;'#10'begin'#10'  H := OpenThread(THREAD_SUSPEND_RESUME, False, 1);'#10 +
    '  H := OpenThread(THREAD_SUSPEND_RESUME, False, 2);'#10'  CloseHandle(H);'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(TWinapiDeclarationMissingRule.Create, mSource);
  Assert.AreEqual('9: OpenThread steht in Free Pascals Windows, in Delphis Winapi.Windows aber nicht (wie ' +
    'E2003). Selbst deklarieren: function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: ' +
    'DWORD): THandle; stdcall; external kernel32 name ''OpenThread'';|9: THREAD_SUSPEND_RESUME steht in Free ' +
    'Pascals Windows, in Delphis Winapi.Windows aber nicht (wie E2003). Selbst deklarieren: const ' +
    'THREAD_SUSPEND_RESUME = $0002;|', TRuleAssert.LineMessages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  // Mit Index: Die Deklaration aus FPCs Windows zählt nicht.
  mFound := TRuleAssert.IndexFindings(TWinapiDeclarationMissingRule.Create, 'unit U;'#10'interface'#10 +
    'implementation'#10'uses'#10'  Windows;'#10'procedure Lauf;'#10'begin'#10 +
    '  SuspendThread(THREAD_SUSPEND_RESUME);'#10'end;'#10'end.', ThreadIndex, '', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
end;

procedure TCompilerTrapsRtlTests.MissingWinapiDeclarationSilentCases;
begin
  // Selbst deklariert (wie Atlas.IDE.Debug.ThreadFreeze und Atlas.IDE.Debug.Leaks).
  TRuleAssert.Silent(TWinapiDeclarationMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'uses'#10 +
    '  Winapi.Windows;'#10'const'#10'  THREAD_SUSPEND_RESUME = $0002;'#10'  PROCESS_QUERY_LIMITED_INFORMATION = ' +
    '$1000;'#10'function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: DWORD): THandle; ' +
    'stdcall;'#10'  external kernel32 name ''OpenThread'';'#10'procedure Lauf;'#10'begin'#10 +
    '  CloseHandle(OpenThread(THREAD_SUSPEND_RESUME or PROCESS_QUERY_LIMITED_INFORMATION, False, 1));'#10 +
    'end;'#10'end.');
  // Ohne Winapi.Windows, hinter einem Punkt, im Kommentar und im String.
  TRuleAssert.Silent(TWinapiDeclarationMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Lauf;'#10'begin'#10'  OpenThread(1, False, 2);'#10'end;'#10'end.');
  TRuleAssert.Silent(TWinapiDeclarationMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'uses'#10'  Winapi.Windows, Werk.Thread;'#10'procedure Lauf;'#10'begin'#10 +
    '  // OpenThread'#10'  Werk.Thread.OpenThread(1, False, 2);'#10'  Writeln(''ERROR_NOT_FOUND'');'#10'end;'#10 +
    'end.');
  // Mit Index: eine Projekt-Unit deklariert OpenThread.
  Assert.AreEqual('', TRuleAssert.LineMessages(TRuleAssert.IndexFindings(TWinapiDeclarationMissingRule.Create, 'unit U;'#10 +
    'interface'#10'implementation'#10'uses'#10'  Winapi.Windows, Werk.Thread;'#10'procedure Lauf;'#10'begin'#10 +
    '  OpenThread(1, False, 2);'#10'end;'#10'end.', ThreadIndex, '', 'U.pas')));
end;

procedure TCompilerTrapsRtlTests.WindowsOnlyRoutineWithoutUses;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10'procedure Lauf;'#10 +
    'var'#10'  T: UInt64;'#10'begin'#10'  T := GetTickCount64;'#10'  T := MulDiv(T, 96, 72);'#10'end;'#10'end.';
  mFound := TRuleAssert.Findings(TWinapiUsesMissingRule.Create, mSource);
  Assert.AreEqual('9: GetTickCount64 deklariert Delphi nur in Winapi.Windows, das hier nicht in uses steht; ' +
    'Free Pascal findet es auch in SysUtils (wie E2003). Winapi.Windows einbinden.|', TRuleAssert.LineMessages(mFound));
  Assert.IsFalse(mFound[0].Fixes[0].Safe);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  System.SysUtils,'#10'  Winapi.Windows;');
  Assert.AreEqual('', TRuleAssert.LineMessages(TRuleAssert.Findings(TWinapiUsesMissingRule.Create, mFixed)));
  // Mit Index: GetTickCount64 aus FPCs Windows bzw. SysUtils zählt nicht.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TWinapiUsesMissingRule.Create, 'unit U;'#10 +
    'interface'#10'implementation'#10'procedure Lauf;'#10'begin'#10'  if GetTickCount64 > 0 then'#10'    Exit;'#10 +
    'end;'#10'end.', ThreadIndex, '', 'U.pas'))));
end;

procedure TCompilerTrapsRtlTests.WindowsOnlyRoutineInInactiveBranch;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'uses'#10'  System.Classes;'#10 +
    'function Millisekunden: UInt64;'#10'begin'#10 +
    '  {$IFDEF FPC}Result := GetTickCount64;{$ELSE}Result := TThread.GetTickCount64;{$ENDIF}'#10'end;'#10'end.';
var
  mContext: TRuleContext;
begin
  // dcc sieht den FPC-Zweig nicht (PascalCoin, UConcurrency).
  mContext := Default(TRuleContext);
  mContext.RelativePath := 'U.pas';
  mContext.UnitName := 'U';
  mContext.Text := cSource;
  mContext.InactiveRanges := TPascalPreprocessor.MainInactive(TPascalPreprocessor.Process(cSource,
    TPascalPreprocessor.EditorOptions(['MSWINDOWS', 'WIN32'])));
  Assert.AreEqual('', TRuleAssert.LineMessages(TRuleAssert.ContextFindings(TWinapiUsesMissingRule.Create, mContext, '')));
  // Im aktiven Zweig bleibt der Befund.
  mContext.Text := cSource.Replace('{$IFDEF FPC}', '{$IFNDEF FPC}');
  mContext.InactiveRanges := TPascalPreprocessor.MainInactive(TPascalPreprocessor.Process(mContext.Text,
    TPascalPreprocessor.EditorOptions(['MSWINDOWS', 'WIN32'])));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.ContextFindings(TWinapiUsesMissingRule.Create, mContext, ''))));
end;

procedure TCompilerTrapsRtlTests.WindowsOnlyRoutineSilentCases;
begin
  // Mit Winapi.Windows bzw. Windows, über TThread und mit eigener Deklaration.
  TRuleAssert.Silent(TWinapiUsesMissingRule.Create, 'unit U;'#10'interface'#10'uses'#10'  Winapi.Windows;'#10 +
    'implementation'#10'procedure Lauf;'#10'begin'#10'  MulDiv(GetTickCount, 2, 3);'#10'end;'#10'end.');
  TRuleAssert.Silent(TWinapiUsesMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'uses'#10 +
    '  System.Classes, Windows;'#10'procedure Lauf;'#10'begin'#10'  GetTickCount64;'#10'end;'#10'end.');
  TRuleAssert.Silent(TWinapiUsesMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'uses'#10 +
    '  System.Classes;'#10'function MulDiv(A, B, C: Integer): Integer;'#10'begin'#10 +
    '  Result := A * B div C;'#10'end;'#10'procedure Lauf;'#10'begin'#10'  TThread.GetTickCount64;'#10 +
    '  MulDiv(1, 2, 3);'#10'end;'#10'end.');
end;

procedure TCompilerTrapsRtlTests.StreamWriteWithoutNativeInt;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TStreamWriteNativeIntRule.Create, 'unit U;'#10'interface'#10'uses'#10 +
    '  System.Classes;'#10'type'#10'  TGrenze = class(TBytesStream)'#10'  public'#10 +
    '    function Write(const ABuffer; ACount: Longint): Longint; override;'#10'  end;'#10'implementation'#10 +
    'function TGrenze.Write(const ABuffer; ACount: Longint): Longint;'#10'begin'#10 +
    '  Result := inherited Write(ABuffer, ACount);'#10'end;'#10'end.');
  Assert.AreEqual('7: TGrenze überschreibt nur Write(...; Count: Longint). Ab Delphi 13 rufen WriteBuffer und ' +
    'CopyFrom unter Win64 Write(const Buffer; Count: NativeInt): NativeInt auf und gehen an dieser Fassung ' +
    'vorbei. Die NativeInt-Fassung ebenfalls überschreiben, in {$IF RTLVersion >= 37.0} und ' +
    '{$IF SizeOf(Longint) <> SizeOf(NativeInt)}.|', TRuleAssert.LineMessages(mFound));
  // Delphi 13 eingestellt: ebenso.
  Assert.AreEqual(1, Integer(Length(StreamFindings('unit U;'#10 +
    'interface'#10'type'#10'  TZaehler = class(TStream)'#10'  public'#10 +
    '    function Write(const Buffer; Count: Longint): Longint; overload; override;'#10'  end;'#10 +
    'implementation'#10'function TZaehler.Write(const Buffer; Count: Longint): Longint;'#10'begin'#10 +
    '  Result := Count;'#10'end;'#10'end.', '37.0'))));
end;

procedure TCompilerTrapsRtlTests.StreamWriteSilentCases;
begin
  // Beide Fassungen, die zweite in {$IF}-Zweigen wie Atlas.Core.Diagnostics.BoundedStream.
  Assert.AreEqual('', TRuleAssert.LineMessages(TRuleAssert.Findings(TStreamWriteNativeIntRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TGrenze = class(TBytesStream)'#10'  public'#10 +
    '    function Write(const ABuffer; ACount: Longint): Longint; overload; override;'#10 +
    '{$IF RTLVersion >= 37.0}'#10'  {$IF SizeOf(Longint) <> SizeOf(NativeInt)}'#10 +
    '    function Write(const ABuffer; ACount: NativeInt): NativeInt; overload; override;'#10'  {$IFEND}'#10 +
    '{$IFEND}'#10'  end;'#10'implementation'#10'end.')));
  // Ohne override, andere Signatur, Delphi 12 eingestellt.
  Assert.AreEqual('', TRuleAssert.LineMessages(TRuleAssert.Findings(TStreamWriteNativeIntRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TSchreiber = class'#10'  public'#10'    function Write(const ABuffer; ACount: Longint): Longint;'#10 +
    '  end;'#10'  TText = class(TStream)'#10'  public'#10 +
    '    function Write(const ABuffer: TBytes; AOffset, ACount: Longint): Longint; override;'#10'  end;'#10 +
    'implementation'#10'end.')));
  Assert.AreEqual(0, Integer(Length(StreamFindings('unit U;'#10 +
    'interface'#10'type'#10'  TZaehler = class(TStream)'#10'  public'#10 +
    '    function Write(const Buffer; Count: Longint): Longint; override;'#10'  end;'#10'implementation'#10 +
    'end.', '36.0'))));
end;

procedure TCompilerTrapsRtlTests.RulesAreRegistered;
var
  mRule: IRule;
  mIds: string;
begin
  mIds := '';
  for mRule in BuiltinRules do
  begin
    if (mRule.Descriptor.Id = cWinapiDeclarationMissingRuleId) or (mRule.Descriptor.Id = cWinapiUsesMissingRuleId) or
      (mRule.Descriptor.Id = cStreamWriteNativeIntRuleId) then
    begin
      mIds := mIds + mRule.Descriptor.Id + ' ';
    end;
  end;
  Assert.AreEqual('winapi-declaration-missing winapi-uses-missing stream-write-nativeint ', mIds);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerTrapsRtlTests);

end.
