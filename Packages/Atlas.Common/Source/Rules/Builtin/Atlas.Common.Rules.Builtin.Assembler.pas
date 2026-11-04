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
  begin
    Inc(mIndex);
  end;
  Result := Copy(ADigits, mIndex, MaxInt);
end;

/// <summary>Nur Zeichen aus AAllowed und mindestens eines?</summary>
function OnlyOf(const AText: string; const AAllowed: TSysCharSet): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, AAllowed) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Ganze Zahl ohne Nachsilbe: dezimal oder $-Hex. AHex = Ziffern zur Basis 16.</summary>
function PlainInteger(const AText: string; out ADigits: string; out AHex: Boolean): Boolean;
begin
  AHex := AText.StartsWith('$');
  if AHex then
  begin
    ADigits := Copy(AText, 2, MaxInt);
  end
  else
  begin
    ADigits := AText;
  end;
  if AHex then
  begin
    Result := OnlyOf(ADigits, ['0'..'9', 'A'..'F', 'a'..'f']);
  end
  else
  begin
    Result := OnlyOf(ADigits, ['0'..'9']);
  end;
end;

type
  /// <summary>Prüft die asm-Blöcke einer Unit; hält die Token und Übersetzungspfade der Datei.</summary>
  TAsmChecker = class
  private
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FTree: TSyntaxTree;
    FReport: IRuleReport;
    function TokenText(AIndex: Integer): string;
    /// <summary>Folgt dem Token direkt (ohne Leerraum) ein Bezeichner wie bei 0FFh? Dann ist die Zahl nur ein
    /// Teil.</summary>
    function HasSuffix(AIndex: Integer): Boolean;
    /// <summary>Größe des Registers, das allein den Operanden bildet; 0 sonst.</summary>
    function OperandRegister(const AOperand: TAsmOperand): Integer;
    /// <summary>Besteht der Operand aus genau einer Zahl ohne Nachsilbe?</summary>
    function IsNumber(const AOperand: TAsmOperand): Boolean;
    function IsZero(AIndex: Integer): Boolean;
    function TooLarge(AIndex: Integer): Boolean;
    /// <summary>Ist der Faktor neben esp (Token AIndex, -1 ohne) eine Zahl außer 1?</summary>
    function IsScale(AIndex: Integer): Boolean;
    function Range(const AStatement: TAsmStatement): TTextRange;
    /// <summary>Lokale Variablen der Routine um ANode (ohne gleichnamige Konstanten und Typen der Routine).
    /// </summary>
    function LocalVariables(ANode: TSyntaxNode): TDictionary<string, Boolean>;
    /// <summary>E2109: db mit einer lokalen Variablen.</summary>
    function DataProblem(ANode: TSyntaxNode; const AStatement: TAsmStatement; out ACode: string): string;
    /// <summary>E2105: fehlender Operand.</summary>
    function MissingOperand(const AStatement: TAsmStatement; out ACode: string): string;
    /// <summary>E2105: esp mit Faktor an Stelle APosition des Operanden.</summary>
    function EspWithScale(const AOperand: TAsmOperand; APosition: Integer): Boolean;
    /// <summary>E2111: links vom + an Stelle APosition steht OFFSET mit Namen.</summary>
    function OffsetSum(const AOperand: TAsmOperand; APosition: Integer): Boolean;
    /// <summary>E2105, E2113, E2118, E2111 am Token APosition des Operanden.</summary>
    function TokenProblem(const AOperand: TAsmOperand; APosition: Integer; out ACode: string): string;
    /// <summary>Befunde in den Ausdrücken der Operanden.</summary>
    function ExpressionProblem(const AStatement: TAsmStatement; out ACode: string): string;
    /// <summary>E2114 und E2107 bei Befehlen mit zwei Operanden.</summary>
    function TwoOperandProblem(const AStatement: TAsmStatement; out ACode: string): string;
    /// <summary>E2107 bei lea und mov mit einer Zahl.</summary>
    function NumberOperandProblem(const AStatement: TAsmStatement; out ACode: string): string;
    /// <summary>Befund der Anweisung als Meldung ohne Code-Zusatz und Code; '' ohne Befund.</summary>
    function Problem(ANode: TSyntaxNode; const AStatement: TAsmStatement; out ACode: string): string;
    procedure CheckBlock(ANode: TSyntaxNode);
  public
    constructor Create(const ATree: TSyntaxTree; const AReport: IRuleReport);
    /// <summary>Quelltext für Free Pascal: dessen Assembler-Modi übersetzt dcc nie.</summary>
    function ForFreePascal: Boolean;
    procedure Run;
  end;

constructor TAsmChecker.Create(const ATree: TSyntaxTree; const AReport: IRuleReport);
begin
  inherited Create;
  FTree := ATree;
  FReport := AReport;
  FTokens := ATree.Tokens;
end;

function TAsmChecker.TokenText(AIndex: Integer): string;
begin
  Result := FTokens[AIndex].Text;
end;

function TAsmChecker.HasSuffix(AIndex: Integer): Boolean;
begin
  Result := (AIndex < High(FTokens)) and (FTokens[AIndex + 1].Kind = TPascalTokenKind.Identifier) and
    (FTokens[AIndex + 1].StartPos.Line = FTokens[AIndex].EndPos.Line) and
    (FTokens[AIndex + 1].StartPos.Character = FTokens[AIndex].EndPos.Character);
end;

function TAsmChecker.OperandRegister(const AOperand: TAsmOperand): Integer;
begin
  Result := 0;
  if (Length(AOperand.Tokens) = 1) and (FTokens[AOperand.Tokens[0]].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword]) then
  begin
    Result := TAsmStatements.RegisterSize(TokenText(AOperand.Tokens[0]));
  end;
end;

function TAsmChecker.IsNumber(const AOperand: TAsmOperand): Boolean;
begin
  Result := (Length(AOperand.Tokens) = 1) and (FTokens[AOperand.Tokens[0]].Kind = TPascalTokenKind.Number) and
    not HasSuffix(AOperand.Tokens[0]);
end;

function TAsmChecker.IsZero(AIndex: Integer): Boolean;
var
  mDigits: string;
  mHex: Boolean;
begin
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Number) and not HasSuffix(AIndex) and
    PlainInteger(TokenText(AIndex), mDigits, mHex) and (WithoutLeadingZeros(mDigits) = '');
end;

function TAsmChecker.TooLarge(AIndex: Integer): Boolean;
var
  mDigits: string;
  mHex: Boolean;
begin
  Result := False;
  if (FTokens[AIndex].Kind <> TPascalTokenKind.Number) or HasSuffix(AIndex) or
    not PlainInteger(TokenText(AIndex), mDigits, mHex) then
  begin
    Exit;
  end;
  mDigits := WithoutLeadingZeros(mDigits);
  if mHex then
  begin
    Result := Length(mDigits) > 16;
  end
  else
  begin
    Result := (Length(mDigits) > Length(cMaxUInt64)) or
      (Length(mDigits) = Length(cMaxUInt64)) and (mDigits > cMaxUInt64);
  end;
end;

function TAsmChecker.IsScale(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (FTokens[AIndex].Kind = TPascalTokenKind.Number) and (TokenText(AIndex) <> '1');
end;

function TAsmChecker.Range(const AStatement: TAsmStatement): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AStatement.FirstToken].StartPos, FTokens[AStatement.LastToken].EndPos);
end;

/// <summary>Routine, in der ANode steht; nil außerhalb einer Routine.</summary>
function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Trägt die Deklaration ADecl des Abschnitts ASection in AVariables oder AHidden ein.</summary>
procedure CollectDecl(ASection, ADecl: TSyntaxNode; const AVariables: TDictionary<string, Boolean>;
  const AHidden: TList<string>);
var
  mName: string;
begin
  if (ASection.Kind = TSyntaxKind.VarSection) and (ADecl.Kind = TSyntaxKind.VarDecl) then
  begin
    for mName in ADecl.Name.Split([',']) do
    begin
      AVariables.AddOrSetValue(LowerCase(Trim(mName)), True);
    end;
  end
  else if ADecl.Kind in [TSyntaxKind.ConstDecl, TSyntaxKind.TypeDecl] then
  begin
    AHidden.Add(LowerCase(ADecl.Name));
  end;
end;

function TAsmChecker.LocalVariables(ANode: TSyntaxNode): TDictionary<string, Boolean>;
var
  mRoutine, mSection: TSyntaxNode;
  mIndex, mInner: Integer;
  mName: string;
  mHidden: TList<string>;
begin
  Result := TDictionary<string, Boolean>.Create;
  mRoutine := EnclosingRoutine(ANode);
  if mRoutine = nil then
  begin
    Exit;
  end;
  mHidden := TList<string>.Create;
  try
    for mIndex := 0 to mRoutine.ChildCount - 1 do
    begin
      mSection := mRoutine[mIndex];
      for mInner := 0 to mSection.ChildCount - 1 do
      begin
        CollectDecl(mSection, mSection[mInner], Result, mHidden);
      end;
    end;
    for mName in mHidden do
    begin
      Result.Remove(mName);
    end;
  finally
    mHidden.Free;
  end;
end;

function TAsmChecker.DataProblem(ANode: TSyntaxNode; const AStatement: TAsmStatement; out ACode: string): string;
var
  mOperand: TAsmOperand;
  mLocals: TDictionary<string, Boolean>;
begin
  Result := '';
  ACode := '';
  if AStatement.Mnemonic <> 'db' then
  begin
    Exit;
  end;
  mLocals := LocalVariables(ANode);
  try
    for mOperand in AStatement.Operands do
    begin
      if (Result = '') and (Length(mOperand.Tokens) = 1) and
        (FTokens[mOperand.Tokens[0]].Kind = TPascalTokenKind.Identifier) and
        mLocals.ContainsKey(LowerCase(TokenText(mOperand.Tokens[0]))) then
      begin
        ACode := 'E2109';
        Result := Format('%s ist eine lokale Variable; db braucht eine Konstante', [TokenText(mOperand.Tokens[0])]);
      end;
    end;
  finally
    mLocals.Free;
  end;
end;

function TAsmChecker.MissingOperand(const AStatement: TAsmStatement; out ACode: string): string;
var
  mOperand: TAsmOperand;
begin
  Result := '';
  ACode := '';
  if Length(AStatement.Operands) < 2 then
  begin
    Exit;
  end;
  for mOperand in AStatement.Operands do
  begin
    if mOperand.Tokens = nil then
    begin
      ACode := 'E2105';
      Exit(Format('Hinter %s fehlt ein Operand', [AStatement.Mnemonic]));
    end;
  end;
end;

function TAsmChecker.EspWithScale(const AOperand: TAsmOperand; APosition: Integer): Boolean;
var
  mLeft, mRight: Integer;
begin
  Result := False;
  if not SameText(TokenText(AOperand.Tokens[APosition]), 'esp') then
  begin
    Exit;
  end;
  mLeft := -1;
  mRight := -1;
  if (APosition >= 2) and FTokens[AOperand.Tokens[APosition - 1]].IsSymbol('*') then
  begin
    mLeft := AOperand.Tokens[APosition - 2];
  end;
  if (APosition + 2 <= High(AOperand.Tokens)) and FTokens[AOperand.Tokens[APosition + 1]].IsSymbol('*') then
  begin
    mRight := AOperand.Tokens[APosition + 2];
  end;
  Result := IsScale(mLeft) or IsScale(mRight);
end;

function TAsmChecker.OffsetSum(const AOperand: TAsmOperand; APosition: Integer): Boolean;
var
  mLeft: Integer;
  mToken: TPascalToken;
begin
  Result := FTokens[AOperand.Tokens[APosition]].IsSymbol('+') and (APosition < High(AOperand.Tokens)) and
    SameText(TokenText(AOperand.Tokens[APosition + 1]), 'offset');
  if not Result then
  begin
    Exit;
  end;
  // Links vom + ein OFFSET mit Namen (OFFSET Fall, OFFSET TFoo.Bar).
  mLeft := APosition - 1;
  while mLeft >= 0 do
  begin
    mToken := FTokens[AOperand.Tokens[mLeft]];
    if not ((mToken.Kind = TPascalTokenKind.Identifier) and not SameText(mToken.Text, 'offset') or
      mToken.IsSymbol('.')) then
    begin
      Break;
    end;
    Dec(mLeft);
  end;
  Result := (mLeft >= 0) and (mLeft < APosition - 1) and SameText(TokenText(AOperand.Tokens[mLeft]), 'offset');
end;

function TAsmChecker.TokenProblem(const AOperand: TAsmOperand; APosition: Integer; out ACode: string): string;
var
  mToken: Integer;
begin
  Result := '';
  ACode := '';
  mToken := AOperand.Tokens[APosition];
  if TooLarge(mToken) then
  begin
    ACode := 'E2113';
    Result := Format('Die Zahl %s passt nicht in 64 Bit', [TokenText(mToken)]);
  end
  else if (FTokens[mToken].IsSymbol('/') or FTokens[mToken].IsKeyword('mod')) and
    (APosition < High(AOperand.Tokens)) and IsZero(AOperand.Tokens[APosition + 1]) then
  begin
    ACode := 'E2118';
    Result := 'Division durch null';
  end
  else if OffsetSum(AOperand, APosition) then
  begin
    ACode := 'E2111';
    Result := 'Zwei relozierbare Adressen lassen sich nicht addieren';
  end;
end;

function TAsmChecker.ExpressionProblem(const AStatement: TAsmStatement; out ACode: string): string;
var
  mOperand: TAsmOperand;
  mPosition: Integer;
begin
  Result := '';
  ACode := '';
  // E2105 (esp mit Faktor) geht den Ausdrücken vor.
  for mOperand in AStatement.Operands do
  begin
    for mPosition := 0 to High(mOperand.Tokens) do
    begin
      if EspWithScale(mOperand, mPosition) then
      begin
        ACode := 'E2105';
        Exit('esp kann nicht Indexregister mit Faktor sein');
      end;
    end;
  end;
  // E2113, E2118, E2111 in den Ausdrücken der Operanden
  for mOperand in AStatement.Operands do
  begin
    mPosition := 0;
    while (Result = '') and (mPosition <= High(mOperand.Tokens)) do
    begin
      Result := TokenProblem(mOperand, mPosition, ACode);
      Inc(mPosition);
    end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
end;

function TAsmChecker.TwoOperandProblem(const AStatement: TAsmStatement; out ACode: string): string;
var
  mOperands: TArray<TAsmOperand>;
  mLiteral: string;
  mLeft, mRight: Integer;
begin
  Result := '';
  ACode := '';
  mOperands := AStatement.Operands;
  mLeft := OperandRegister(mOperands[0]);
  mRight := OperandRegister(mOperands[1]);
  // E2114: Stringkonstante an einem 32-Bit-Register
  if (mLeft = 4) and (Length(mOperands[1].Tokens) = 1) and
    (FTokens[mOperands[1].Tokens[0]].Kind = TPascalTokenKind.StringLiteral) then
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
  if MatchStr(AStatement.Mnemonic, cSameSizeMnemonics) and (mLeft > 0) and (mRight > 0) and (mLeft <> mRight) then
  begin
    ACode := 'E2107';
    Exit(Format('Operandengröße stimmt nicht überein: %s hat %d Byte, %s %d Byte',
      [TokenText(mOperands[0].Tokens[0]), mLeft, TokenText(mOperands[1].Tokens[0]), mRight]));
  end;
  Result := NumberOperandProblem(AStatement, ACode);
end;

function TAsmChecker.NumberOperandProblem(const AStatement: TAsmStatement; out ACode: string): string;
begin
  Result := '';
  ACode := '';
  if (AStatement.Mnemonic = 'lea') and IsNumber(AStatement.Operands[1]) then
  begin
    ACode := 'E2107';
    Result := 'lea braucht eine Speicheradresse, keine Zahl';
  end
  else if (AStatement.Mnemonic = 'mov') and IsNumber(AStatement.Operands[0]) then
  begin
    ACode := 'E2107';
    Result := 'Eine Zahl kann nicht Ziel von mov sein';
  end;
end;

function TAsmChecker.Problem(ANode: TSyntaxNode; const AStatement: TAsmStatement; out ACode: string): string;
begin
  Result := '';
  ACode := '';
  if TAsmStatements.IsDataDirective(AStatement.Mnemonic) then
  begin
    Exit(DataProblem(ANode, AStatement, ACode));
  end;
  if AStatement.Mnemonic.StartsWith('.') then
  begin
    Exit;
  end;
  Result := MissingOperand(AStatement, ACode);
  if Result = '' then
  begin
    Result := ExpressionProblem(AStatement, ACode);
  end;
  if (Result = '') and (Length(AStatement.Operands) = 2) then
  begin
    Result := TwoOperandProblem(AStatement, ACode);
  end;
end;

procedure TAsmChecker.CheckBlock(ANode: TSyntaxNode);
var
  mFirst, mLast: Integer;
  mStatement: TAsmStatement;
  mMessage, mCode: string;
begin
  mFirst := FTree.FirstTokenFrom(ANode.StartOffset);
  mLast := FTree.FirstTokenFrom(ANode.EndOffset) - 1;
  // Unvollständiger Block (ohne end): nichts sagen.
  if (mFirst > High(FTokens)) or (mLast <= mFirst) or not FTokens[mFirst].IsKeyword('asm') or
    not FTokens[mLast].IsKeyword('end') then
  begin
    Exit;
  end;
  for mStatement in TAsmStatements.Split(FTokens, FPaths, mFirst, mFirst + 1, mLast - 1) do
  begin
    if mStatement.Uncertain or (mStatement.Mnemonic = '') then
    begin
      Continue;
    end;
    mMessage := Problem(ANode, mStatement, mCode);
    if mMessage <> '' then
    begin
      FReport.Add(Range(mStatement), Format('%s (wie %s).', [mMessage, mCode]), TRuleConfidence.High);
    end;
  end;
end;

function TAsmChecker.ForFreePascal: Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  Result := False;
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      mName := TPascalLexer.DirectiveName(FTokens[mIndex].Text);
      Result := Result or (mName = 'MODE') or (mName = 'ASMMODE');
    end;
  end;
end;

procedure TAsmChecker.Run;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  FPaths := TConditionalBranches.Paths(FTokens);
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FTree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AsmBlock then
      begin
        CheckBlock(mNode);
      end
      else
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TAsmInvalidRule }

function TAsmInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AsmInvalidRuleId, TRuleSeverity.Error, 'Ungültige Anweisung im Inline-Assembler');
end;

procedure TAsmInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mChecker: TAsmChecker;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mChecker := TAsmChecker.Create(AContext.Tree, AReport);
  try
    if not mChecker.ForFreePascal then
    begin
      mChecker.Run;
    end;
  finally
    mChecker.Free;
  end;
end;

procedure RegisterAssemblerRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAsmInvalidRule.Create);
end;

end.
