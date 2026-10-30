unit Atlas.Common.Rules.Builtin.Assembler;

// Inline-Assembler (#1375, Gruppe „Compiler vorab“):
//   asm-invalid   Anweisungen in asm-Blöcken, die dcc nicht übersetzt. Die
//                 Anweisungen zerlegt Pascal.AsmStatements. Gemeldet werden
//                 nur Formen, die dcc 13 im Testprojekt Tests/Compilermeldungen
//                 meldet (#1361), je Anweisung höchstens ein Befund:
//                   E2105  Operand fehlt (mov eax, ), esp als Indexregister
//                          mit Faktor ([eax + esp * 2]; dcc meldet hier E2105,
//                          nicht E2112)
//                   E2113  Zahl über 64 Bit
//                   E2118  Division durch null (/ 0, mod 0)
//                   E2111  OFFSET a + OFFSET b
//                   E2114  Stringkonstante über 4 Zeichen an einem
//                          32-Bit-Register (mov eax, 'abcdefgh')
//                   E2107  zwei Register verschiedener Größe (mov al, ebx),
//                          lea mit einer Zahl (lea eax, 5; dcc: E2107 statt
//                          E2108), Zahl als Ziel von mov (mov 5, eax; dcc:
//                          E2107 statt E2116)
//                   E2109  db mit einer lokalen Variablen der Routine
//                 Nur Token, die immer mit dem asm übersetzt werden (bei
//                 {$IFDEF X} asm … {$ELSE} … begin … {$ENDIF} end; gehört der
//                 Pascal-Zweig nicht zum Block).
//                 Nicht gemeldet: Anweisungen mit Direktive (bedingte Teile)
//                 oder { }-Kommentar (ARM-Registerlisten bei Free Pascal),
//                 Datenbefehle außer db mit Variable, Register von Win64 (rax,
//                 r8 …, unter Win32 mögliche Variablennamen) und Dateien für
//                 Free Pascal ({$MODE …}, {$ASMMODE …}).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  AsmInvalidRuleId = 'asm-invalid';

type
  TAsmInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterAssemblerRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.AsmStatements;

const
  // Befehle, deren zwei Operanden gleich groß sein müssen.
  cSameSizeMnemonics: array[0..12] of string = ('mov', 'add', 'adc', 'sub', 'sbb', 'and', 'or', 'xor', 'cmp',
    'test', 'xchg', 'cmpxchg', 'xadd');
  cMaxUInt64 = '18446744073709551615';

/// <summary>Ziffern ohne führende Nullen ('0' bleibt '').</summary>
function WithoutLeadingZeros(const ADigits: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(ADigits)) and (ADigits[mIndex] = '0') do
    Inc(mIndex);
  Result := Copy(ADigits, mIndex, MaxInt);
end;

/// <summary>Nur Zeichen aus AAllowed und mindestens eines?</summary>
function OnlyOf(const AText: string; const AAllowed: TSysCharSet): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
    if not CharInSet(mChar, AAllowed) then
      Exit(False);
end;

/// <summary>Ganze Zahl ohne Nachsilbe: dezimal oder $-Hex. AHex = Ziffern zur Basis 16.</summary>
function PlainInteger(const AText: string; out ADigits: string; out AHex: Boolean): Boolean;
begin
  AHex := AText.StartsWith('$');
  if AHex then
    ADigits := Copy(AText, 2, MaxInt)
  else
    ADigits := AText;
  if AHex then
    Result := OnlyOf(ADigits, ['0'..'9', 'A'..'F', 'a'..'f'])
  else
    Result := OnlyOf(ADigits, ['0'..'9']);
end;

{ TAsmInvalidRule }

function TAsmInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AsmInvalidRuleId, TRuleSeverity.Error, 'Ungültige Anweisung im Inline-Assembler');
end;

procedure TAsmInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mPaths: TArray<string>;

  function TokenText(AIndex: Integer): string;
  begin
    Result := mTokens[AIndex].Text;
  end;

  /// <summary>Folgt dem Token direkt (ohne Leerraum) ein Bezeichner wie bei 0FFh? Dann ist die Zahl nur ein Teil.
  /// </summary>
  function HasSuffix(AIndex: Integer): Boolean;
  begin
    Result := (AIndex < High(mTokens)) and (mTokens[AIndex + 1].Kind = TPascalTokenKind.Identifier) and
      (mTokens[AIndex + 1].StartPos.Line = mTokens[AIndex].EndPos.Line) and
      (mTokens[AIndex + 1].StartPos.Character = mTokens[AIndex].EndPos.Character);
  end;

  /// <summary>Größe des Registers, das allein den Operanden bildet; 0 sonst.</summary>
  function OperandRegister(const AOperand: TAsmOperand): Integer;
  begin
    Result := 0;
    if (Length(AOperand.Tokens) = 1) and (mTokens[AOperand.Tokens[0]].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword]) then
      Result := TAsmStatements.RegisterSize(TokenText(AOperand.Tokens[0]));
  end;

  /// <summary>Besteht der Operand aus genau einer Zahl ohne Nachsilbe?</summary>
  function IsNumber(const AOperand: TAsmOperand): Boolean;
  begin
    Result := (Length(AOperand.Tokens) = 1) and (mTokens[AOperand.Tokens[0]].Kind = TPascalTokenKind.Number) and
      not HasSuffix(AOperand.Tokens[0]);
  end;

  function IsZero(AIndex: Integer): Boolean;
  var
    mDigits: string;
    mHex: Boolean;
  begin
    Result := (mTokens[AIndex].Kind = TPascalTokenKind.Number) and not HasSuffix(AIndex) and
      PlainInteger(TokenText(AIndex), mDigits, mHex) and (WithoutLeadingZeros(mDigits) = '');
  end;

  function TooLarge(AIndex: Integer): Boolean;
  var
    mDigits: string;
    mHex: Boolean;
  begin
    Result := False;
    if (mTokens[AIndex].Kind <> TPascalTokenKind.Number) or HasSuffix(AIndex) or
      not PlainInteger(TokenText(AIndex), mDigits, mHex) then
      Exit;
    mDigits := WithoutLeadingZeros(mDigits);
    if mHex then
      Result := Length(mDigits) > 16
    else
      Result := (Length(mDigits) > Length(cMaxUInt64)) or
        (Length(mDigits) = Length(cMaxUInt64)) and (mDigits > cMaxUInt64);
  end;

  function Range(const AStatement: TAsmStatement): TTextRange;
  begin
    Result := TTextRange.Create(mTokens[AStatement.FirstToken].StartPos, mTokens[AStatement.LastToken].EndPos);
  end;

  /// <summary>Lokale Variablen der Routine um ANode (ohne gleichnamige Konstanten und Typen der Routine).</summary>
  function LocalVariables(ANode: TSyntaxNode): TDictionary<string, Boolean>;
  var
    mRoutine, mSection, mDecl: TSyntaxNode;
    mIndex, mInner: Integer;
    mName: string;
    mHidden: TList<string>;
  begin
    Result := TDictionary<string, Boolean>.Create;
    mRoutine := ANode.Parent;
    while (mRoutine <> nil) and (mRoutine.Kind <> TSyntaxKind.RoutineDecl) do
      mRoutine := mRoutine.Parent;
    if mRoutine = nil then
      Exit;
    mHidden := TList<string>.Create;
    try
      for mIndex := 0 to mRoutine.ChildCount - 1 do
      begin
        mSection := mRoutine[mIndex];
        for mInner := 0 to mSection.ChildCount - 1 do
        begin
          mDecl := mSection[mInner];
          if (mSection.Kind = TSyntaxKind.VarSection) and (mDecl.Kind = TSyntaxKind.VarDecl) then
          begin
            for mName in mDecl.Name.Split([',']) do
              Result.AddOrSetValue(LowerCase(Trim(mName)), True);
          end
          else if mDecl.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl] then
            mHidden.Add(LowerCase(mDecl.Name));
        end;
      end;
      for mName in mHidden do
        Result.Remove(mName);
    finally
      mHidden.Free;
    end;
  end;

  /// <summary>Befund der Anweisung als Meldung ohne Code-Zusatz und Code; '' ohne Befund.</summary>
  function Problem(ANode: TSyntaxNode; const AStatement: TAsmStatement; out ACode: string): string;
  var
    mOperand: TAsmOperand;
    mOperands: TArray<TAsmOperand>;
    mPosition, mToken, mLeft, mRight: Integer;
    mLocals: TDictionary<string, Boolean>;
    mLiteral: string;
  begin
    Result := '';
    ACode := '';
    mOperands := AStatement.Operands;
    if TAsmStatements.IsDataDirective(AStatement.Mnemonic) then
    begin
      if AStatement.Mnemonic <> 'db' then
        Exit;
      mLocals := LocalVariables(ANode);
      try
        for mOperand in mOperands do
          if (Length(mOperand.Tokens) = 1) and (mTokens[mOperand.Tokens[0]].Kind = TPascalTokenKind.Identifier) and
            mLocals.ContainsKey(LowerCase(TokenText(mOperand.Tokens[0]))) then
          begin
            ACode := 'E2109';
            Exit(Format('%s ist eine lokale Variable; db braucht eine Konstante', [TokenText(mOperand.Tokens[0])]));
          end;
      finally
        mLocals.Free;
      end;
      Exit;
    end;
    if AStatement.Mnemonic.StartsWith('.') then
      Exit;
    // E2105: fehlender Operand, esp mit Faktor
    if Length(mOperands) >= 2 then
      for mOperand in mOperands do
        if mOperand.Tokens = nil then
        begin
          ACode := 'E2105';
          Exit(Format('Hinter %s fehlt ein Operand', [AStatement.Mnemonic]));
        end;
    for mOperand in mOperands do
      for mPosition := 0 to High(mOperand.Tokens) do
      begin
        mToken := mOperand.Tokens[mPosition];
        if SameText(TokenText(mToken), 'esp') then
        begin
          mLeft := -1;
          mRight := -1;
          if (mPosition >= 2) and mTokens[mOperand.Tokens[mPosition - 1]].IsSymbol('*') then
            mLeft := mOperand.Tokens[mPosition - 2];
          if (mPosition + 2 <= High(mOperand.Tokens)) and mTokens[mOperand.Tokens[mPosition + 1]].IsSymbol('*') then
            mRight := mOperand.Tokens[mPosition + 2];
          if ((mLeft >= 0) and (mTokens[mLeft].Kind = TPascalTokenKind.Number) and (TokenText(mLeft) <> '1')) or
            ((mRight >= 0) and (mTokens[mRight].Kind = TPascalTokenKind.Number) and (TokenText(mRight) <> '1')) then
          begin
            ACode := 'E2105';
            Exit('esp kann nicht Indexregister mit Faktor sein');
          end;
        end;
      end;
    // E2113, E2118, E2111 in den Ausdrücken der Operanden
    for mOperand in mOperands do
      for mPosition := 0 to High(mOperand.Tokens) do
      begin
        mToken := mOperand.Tokens[mPosition];
        if TooLarge(mToken) then
        begin
          ACode := 'E2113';
          Exit(Format('Die Zahl %s passt nicht in 64 Bit', [TokenText(mToken)]));
        end;
        if (mTokens[mToken].IsSymbol('/') or mTokens[mToken].IsKeyword('mod')) and
          (mPosition < High(mOperand.Tokens)) and IsZero(mOperand.Tokens[mPosition + 1]) then
        begin
          ACode := 'E2118';
          Exit('Division durch null');
        end;
        if mTokens[mToken].IsSymbol('+') and (mPosition < High(mOperand.Tokens)) and
          SameText(TokenText(mOperand.Tokens[mPosition + 1]), 'offset') then
        begin
          // Links vom + ein OFFSET mit Namen (OFFSET Fall, OFFSET TFoo.Bar).
          mLeft := mPosition - 1;
          while (mLeft >= 0) and ((mTokens[mOperand.Tokens[mLeft]].Kind = TPascalTokenKind.Identifier) and
            not SameText(TokenText(mOperand.Tokens[mLeft]), 'offset') or mTokens[mOperand.Tokens[mLeft]].IsSymbol('.')) do
            Dec(mLeft);
          if (mLeft >= 0) and (mLeft < mPosition - 1) and SameText(TokenText(mOperand.Tokens[mLeft]), 'offset') then
          begin
            ACode := 'E2111';
            Exit('Zwei relozierbare Adressen lassen sich nicht addieren');
          end;
        end;
      end;
    if Length(mOperands) <> 2 then
      Exit;
    // E2114: Stringkonstante an einem 32-Bit-Register
    if (OperandRegister(mOperands[0]) = 4) and (Length(mOperands[1].Tokens) = 1) and
      (mTokens[mOperands[1].Tokens[0]].Kind = TPascalTokenKind.StringLiteral) then
    begin
      mLiteral := AnsiDequotedStr(TokenText(mOperands[1].Tokens[0]), '''');
      if Length(mLiteral) > 4 then
      begin
        ACode := 'E2114';
        Exit(Format('Die Stringkonstante hat %d Zeichen, %s fasst 4', [Length(mLiteral),
          TokenText(mOperands[0].Tokens[0])]));
      end;
    end;
    // E2107: Operandengröße
    if MatchStr(AStatement.Mnemonic, cSameSizeMnemonics) and (OperandRegister(mOperands[0]) > 0) and
      (OperandRegister(mOperands[1]) > 0) and (OperandRegister(mOperands[0]) <> OperandRegister(mOperands[1])) then
    begin
      ACode := 'E2107';
      Exit(Format('Operandengröße stimmt nicht überein: %s hat %d Byte, %s %d Byte', [TokenText(mOperands[0].Tokens[0]),
        OperandRegister(mOperands[0]), TokenText(mOperands[1].Tokens[0]), OperandRegister(mOperands[1])]));
    end;
    if (AStatement.Mnemonic = 'lea') and IsNumber(mOperands[1]) then
    begin
      ACode := 'E2107';
      Exit('lea braucht eine Speicheradresse, keine Zahl');
    end;
    if (AStatement.Mnemonic = 'mov') and IsNumber(mOperands[0]) then
    begin
      ACode := 'E2107';
      Exit('Eine Zahl kann nicht Ziel von mov sein');
    end;
  end;

  procedure CheckBlock(ANode: TSyntaxNode);
  var
    mFirst, mLast: Integer;
    mStatement: TAsmStatement;
    mMessage, mCode: string;
  begin
    mFirst := AContext.Tree.FirstTokenFrom(ANode.StartOffset);
    mLast := AContext.Tree.FirstTokenFrom(ANode.EndOffset) - 1;
    // Unvollständiger Block (ohne end): nichts sagen.
    if (mFirst > High(mTokens)) or (mLast <= mFirst) or not mTokens[mFirst].IsKeyword('asm') or
      not mTokens[mLast].IsKeyword('end') then
      Exit;
    for mStatement in TAsmStatements.Split(mTokens, mPaths, mFirst, mFirst + 1, mLast - 1) do
    begin
      if mStatement.Uncertain or (mStatement.Mnemonic = '') then
        Continue;
      mMessage := Problem(ANode, mStatement, mCode);
      if mMessage <> '' then
        AReport.Add(Range(mStatement), Format('%s (wie %s).', [mMessage, mCode]), TRuleConfidence.High);
    end;
  end;

var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
  mName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  mTokens := AContext.Tree.Tokens;
  // Quelltext für Free Pascal: dessen Assembler-Modi übersetzt dcc nie.
  for mIndex := 0 to High(mTokens) do
    if mTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      mName := TPascalLexer.DirectiveName(mTokens[mIndex].Text);
      if (mName = 'MODE') or (mName = 'ASMMODE') then
        Exit;
    end;
  mPaths := TConditionalBranches.Paths(mTokens);
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AsmBlock then
        CheckBlock(mNode)
      else
        for mIndex := mNode.ChildCount - 1 downto 0 do
          mPending.Push(mNode[mIndex]);
    end;
  finally
    mPending.Free;
  end;
end;

procedure RegisterAssemblerRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAsmInvalidRule.Create);
end;

end.
