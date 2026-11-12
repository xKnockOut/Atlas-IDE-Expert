unit Atlas.Common.Rules.Builtin.Migration.Unicode.Tests;

// Tests der Unicode-Migrationsregeln (#117):
// char-count-as-bytes: Beispiel aus dem Issue mit Korrektur, Verschiebung um eine Zahl, Stream-Methoden, GetMem
// eines PChar, StrLen, Puffer aus einem anderen String, AnsiString und TBytes still, {$H-}, alte Delphi-Versionen,
// inaktive Zweige, Abschalten.
// ansi-api-call: Beispiel mit Korrektur, ohne Korrektur bei einem Ansi-Argument, stille Fälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCharCountAsBytesTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ShiftedCountAndStreams;
    [Test]
    procedure GetMemOfCharPointer;
    [Test]
    procedure OtherBuffersAndTypesAreSilent;
    [Test]
    procedure ShortStringsAndOldDelphiAreSilent;
    [Test]
    procedure InactiveBranchAndOff;
    [Test]
    procedure CountArguments;
  end;

  [TestFixture]
  TAnsiApiCallTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure AnsiArgumentPreventsFix;
    [Test]
    procedure UnconvertedAndOtherNamesAreSilent;
    [Test]
    procedure NeutralNames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Rules.Builtin.Migration.Unicode,
  Atlas.Tests.RuleAssert;

/// <summary>Routine Pruefen mit den Deklarationen ADecls (var-Abschnitt) und den Anweisungen ABody.</summary>
function Routine(const ADecls, ABody: string): string;
begin
  Result := 'unit Texte;'#10'interface'#10'implementation'#10'procedure Pruefen;'#10'var'#10 + ADecls + 'begin'#10 +
    ABody + 'end;'#10'end.';
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

function ContextFindings(ARule: IRule; const ASource, AVersion: string;
  const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.Text := ASource;
  mContext.RelativePath := 'Texte.pas';
  mContext.DelphiVersion := AVersion;
  mContext.InactiveRanges := AInactive;
  Result := TRuleAssert.ContextFindings(ARule, mContext, '');
end;

{ TCharCountAsBytesTests }

procedure TCharCountAsBytesTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  S: string;'#10'  Puffer: array[0..255] of Byte;'#10, '  Move(S[1], Puffer, Length(S));'#10);
  mFound := TRuleAssert.Findings(TCharCountAsBytesRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cCharCountAsBytesRuleId, mFound[0].RuleId);
  Assert.AreEqual('Length(S) zählt Zeichen, Move erwartet Bytes; seit Delphi 2009 hat ein Char 2 Byte, es wird nur ' +
    'die Hälfte verarbeitet. Ist das Ziel ein AnsiChar-Puffer, braucht es eine Umwandlung statt der doppelten ' +
    'Größe.', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(21, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(30, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Mit SizeOf(Char) malnehmen', mFound[0].Fixes[0].Title);
  Assert.IsFalse(mFound[0].Fixes[0].Safe);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  Move(S[1], Puffer, Length(S) * SizeOf(Char));'#10, mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCharCountAsBytesRule.Create, mFixed))));
end;

procedure TCharCountAsBytesTests.ShiftedCountAndStreams;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  S: string;'#10'  W: WideString;'#10'  P: PChar;'#10,
    '  Move(Pointer(S)^, Ziel^, Length(S) + 1);'#10'  Strom.WriteBuffer(PChar(W)^, Length(W));'#10 +
    '  Strom.Read(S[1], (Length(S)));'#10'  FillChar(P^, StrLen(P), 0);'#10 +
    '  CopyMemory(Ziel, @S[1], 1 + Length(S));'#10);
  mFound := TRuleAssert.Findings(TCharCountAsBytesRule.Create, mSource);
  Assert.AreEqual(5, Integer(Length(mFound)), Messages(mFound));
  Assert.IsTrue(Pos('  Move(Pointer(S)^, Ziel^, (Length(S) + 1) * SizeOf(Char));'#10,
    Applied(mSource, mFound[0].Fixes[0])) > 0);
  Assert.AreEqual('Length(W) zählt Zeichen, WriteBuffer erwartet Bytes; seit Delphi 2009 hat ein Char 2 Byte, es ' +
    'wird nur die Hälfte verarbeitet. Ist das Ziel ein AnsiChar-Puffer, braucht es eine Umwandlung statt der ' +
    'doppelten Größe.', mFound[1].Message);
  Assert.IsTrue(Pos('  Strom.Read(S[1], (Length(S)) * SizeOf(Char));'#10, Applied(mSource, mFound[2].Fixes[0])) > 0);
  Assert.IsTrue(Pos('  FillChar(P^, StrLen(P) * SizeOf(Char), 0);'#10, Applied(mSource, mFound[3].Fixes[0])) > 0);
  Assert.IsTrue(Pos('  CopyMemory(Ziel, @S[1], (1 + Length(S)) * SizeOf(Char));'#10,
    Applied(mSource, mFound[4].Fixes[0])) > 0);
end;

procedure TCharCountAsBytesTests.GetMemOfCharPointer;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TCharCountAsBytesRule.Create, Routine(
    '  S: string;'#10'  P: PChar;'#10'  Q: Pointer;'#10'  A: PAnsiChar;'#10,
    '  GetMem(P, Length(S) + 1);'#10'  ReallocMem(P, Length(S));'#10'  GetMem(Q, Length(S));'#10 +
    '  GetMem(A, Length(S) + 1);'#10));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Length(S) zählt Zeichen, GetMem legt Bytes an; für P (PChar) ist der Speicher halb so groß wie ' +
    'nötig.', mFound[0].Message);
end;

procedure TCharCountAsBytesTests.OtherBuffersAndTypesAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TCharCountAsBytesRule.Create, Routine(
    '  S, T: string;'#10'  A: AnsiString;'#10'  Bytes: TBytes;'#10'  Puffer: array[0..9] of Byte;'#10,
    '  Move(A[1], Puffer, Length(A));'#10'  Move(Bytes[0], Puffer, Length(Bytes));'#10 +
    '  Move(T[1], Puffer, Length(S));'#10'  Move(S[1], Puffer, Length(S) * SizeOf(Char));'#10 +
    '  Move(S[1], Puffer, ByteLength(S));'#10'  Move(S[1], Puffer, Length(S) * 2);'#10 +
    '  Liste.Add(S[1], Length(S));'#10'  Move(U[1], Puffer, Length(U));'#10))));
end;

procedure TCharCountAsBytesTests.ShortStringsAndOldDelphiAreSilent;
var
  mSource: string;
begin
  mSource := Routine('  S: string;'#10'  Puffer: array[0..9] of Byte;'#10, '  Move(S[1], Puffer, Length(S));'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCharCountAsBytesRule.Create,
    StringReplace(mSource, 'interface', '{$H-}'#10'interface', [])))));
  Assert.AreEqual(0, Integer(Length(ContextFindings(TCharCountAsBytesRule.Create, mSource, '5.0', nil))));
  Assert.AreEqual(1, Integer(Length(ContextFindings(TCharCountAsBytesRule.Create, mSource, '6.0', nil))));
end;

procedure TCharCountAsBytesTests.InactiveBranchAndOff;
var
  mSource: string;
begin
  mSource := Routine('  S: string;'#10'  Puffer: array[0..9] of Byte;'#10, '  Move(S[1], Puffer, Length(S));'#10);
  Assert.AreEqual(0, Integer(Length(ContextFindings(TCharCountAsBytesRule.Create, mSource, '',
    [TTextRange.Create(8, 0, 9, 0)]))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCharCountAsBytesRule.Create, mSource,
    '{"rules": {"char-count-as-bytes": "off"}}', 'Source/Texte.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCharCountAsBytesRule.Create, mSource,
    '{"rules": {"group:migration": "off"}}', 'Source/Texte.pas'))));
end;

procedure TCharCountAsBytesTests.CountArguments;
var
  mBuffers: TArray<Integer>;
begin
  Assert.AreEqual(2, TCharCountAsBytesRule.CountArgument('move', False, mBuffers));
  Assert.AreEqual(2, Integer(Length(mBuffers)));
  Assert.AreEqual(1, TCharCountAsBytesRule.CountArgument('WriteBuffer', True, mBuffers));
  Assert.AreEqual(-1, TCharCountAsBytesRule.CountArgument('WriteBuffer', False, mBuffers));
  Assert.AreEqual(1, TCharCountAsBytesRule.CountArgument('GetMem', False, mBuffers));
  Assert.AreEqual(0, Integer(Length(mBuffers)));
  Assert.AreEqual(-1, TCharCountAsBytesRule.CountArgument('Copy', False, mBuffers));
end;

{ TAnsiApiCallTests }

procedure TAnsiApiCallTests.IssueExampleWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Routine('  Text: string;'#10,
    '  MessageBoxA(0, PAnsiChar(AnsiString(Text)), PAnsiChar(AnsiString(Text)), MB_OK);'#10);
  mFound := TRuleAssert.Findings(TAnsiApiCallRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cAnsiApiCallRuleId, mFound[0].RuleId);
  Assert.AreEqual('MessageBoxA bekommt Text als AnsiString; Zeichen außerhalb der ANSI-Codepage gehen verloren. ' +
    'MessageBox nimmt den string unverändert.', mFound[0].Message);
  Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(13, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('MessageBox mit PChar verwenden', mFound[0].Fixes[0].Title);
  mFixed := Applied(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  MessageBox(0, PChar(Text), PChar(Text), MB_OK);'#10, mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAnsiApiCallRule.Create, mFixed))));
end;

procedure TAnsiApiCallTests.AnsiArgumentPreventsFix;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TAnsiApiCallRule.Create, Routine('  Text: string;'#10'  Titel: PAnsiChar;'#10,
    '  MessageBoxA(0, PAnsiChar(AnsiString(Text)), Titel, MB_OK);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TAnsiApiCallTests.UnconvertedAndOtherNamesAreSilent;
begin
  Assert.AreEqual('', Messages(TRuleAssert.Findings(TAnsiApiCallRule.Create, Routine(
    '  Text: string;'#10'  A: AnsiString;'#10'  Titel: PAnsiChar;'#10,
    '  MessageBoxA(0, Titel, Titel, MB_OK);'#10'  MessageBoxA(0, PAnsiChar(A), nil, MB_OK);'#10 +
    '  MessageBox(0, PChar(Text), nil, MB_OK);'#10'  LeseDATA(PAnsiChar(AnsiString(Text)));'#10 +
    '  MessageBoxA(0, PAnsiChar(AnsiString(Unbekannt)), nil, MB_OK);'#10 +
    '  MessageBoxA(0, PAnsiChar(UTF8String(Text)), nil, MB_OK);'#10))));
end;

procedure TAnsiApiCallTests.NeutralNames;
begin
  Assert.AreEqual('MessageBox', TAnsiApiCallRule.NeutralName('MessageBoxA'));
  Assert.AreEqual('lstrlen', TAnsiApiCallRule.NeutralName('lstrlenA'));
  Assert.AreEqual('RegOpenKeyEx', TAnsiApiCallRule.NeutralName('RegOpenKeyExA'));
  Assert.AreEqual('', TAnsiApiCallRule.NeutralName('DATA'));
  Assert.AreEqual('', TAnsiApiCallRule.NeutralName('ExtractW'));
  Assert.AreEqual('', TAnsiApiCallRule.NeutralName('A'));
end;

initialization
  TDUnitX.RegisterTestFixture(TCharCountAsBytesTests);
  TDUnitX.RegisterTestFixture(TAnsiApiCallTests);

end.
