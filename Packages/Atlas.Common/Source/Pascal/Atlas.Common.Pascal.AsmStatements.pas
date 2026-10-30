unit Atlas.Common.Pascal.AsmStatements;

// Anweisungen eines asm-Blocks (#1375): Der Parser überspringt Assembler
// (TParser.ParseAsm); diese Unit teilt die Token zwischen asm und end in
// Anweisungen mit Befehl und Operanden, für die Regel asm-invalid.
//   - Eine Anweisung endet am Zeilenende oder an ";" (wie bei dcc).
//   - Sprungmarken (@@Ende:, Marke:) und Präfixe (lock, rep …) gehören nicht
//     zum Befehl.
//   - Operanden trennt ein Komma außerhalb von [] und ().
//   - Kommentare zählen nicht. Eine Anweisung mit Compiler-Direktive oder
//     unbekanntem Zeichen gilt als unsicher (Uncertain): Welcher Teil
//     übersetzt wird, entscheidet erst der Präprozessor. Ebenso { } oder
//     (* *) mitten in der Anweisung: Andere Assembler (ARM bei Free Pascal:
//     ldmea r11, {r11, r13}) schreiben damit Registerlisten.
//   - Mit den Zweigen bedingter Übersetzung (Pascal.ConditionalBranches)
//     zählen nur Token, die nie ohne das asm übersetzt werden. Der Baum
//     enthält beide Zweige: Bei {$IFDEF X} asm … {$ELSE} var … begin …
//     {$ENDIF} end; reicht der Block bis zum gemeinsamen end, der
//     Pascal-Zweig gehört aber nicht dazu.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Ein Operand: Indizes seiner Code-Token in den Token der Datei; leer, wenn der Operand fehlt
  /// (mov eax, ).</summary>
  TAsmOperand = record
    Tokens: TArray<Integer>;
  end;

  TAsmStatement = record
    /// <summary>Befehl in Kleinbuchstaben (mov, db, .noframe …); '' ohne Befehl (nur eine Sprungmarke).</summary>
    Mnemonic: string;
    /// <summary>Index des Befehls in den Token; -1 ohne Befehl.</summary>
    MnemonicToken: Integer;
    /// <summary>Operanden in Reihenfolge; leer ohne Operanden. Ein Komma ergibt immer zwei Operanden.</summary>
    Operands: TArray<TAsmOperand>;
    /// <summary>Erstes Code-Token (hinter der Sprungmarke) und letztes Code-Token der Anweisung.</summary>
    FirstToken: Integer;
    LastToken: Integer;
    /// <summary>Direktive oder unbekanntes Zeichen in der Anweisung: nicht auswerten.</summary>
    Uncertain: Boolean;
  end;

  TAsmStatements = record
  public
    /// <summary>Anweisungen aus den Token AFirst bis ALast (beide eingeschlossen, ohne asm und end).</summary>
    class function Split(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<TAsmStatement>;
      overload; static;
    /// <summary>Wie Split, aber nur mit den Token, die immer mit dem Token AAsm (asm) übersetzt werden; APaths aus
    /// TConditionalBranches.Paths. Andere Token trennen Anweisungen wie eine Direktive.</summary>
    class function Split(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>; AAsm, AFirst,
      ALast: Integer): TArray<TAsmStatement>; overload; static;
    /// <summary>Größe eines Allzweckregisters in Byte (al → 1, ax → 2, eax → 4); 0 für andere Namen. Nur die
    /// Register, die es unter Win32 und Win64 gibt: rax, r8 … fehlen, weil sie unter Win32 Namen von Variablen
    /// sein können.</summary>
    class function RegisterSize(const AName: string): Integer; static;
    /// <summary>Datenbefehl db, dw, dd, dq oder dt (in Kleinbuchstaben)?</summary>
    class function IsDataDirective(const AMnemonic: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.ConditionalBranches;

const
  cPrefixes: array[0..5] of string = ('lock', 'rep', 'repe', 'repne', 'repz', 'repnz');
  cRegisters8: array[0..7] of string = ('al', 'ah', 'bl', 'bh', 'cl', 'ch', 'dl', 'dh');
  cRegisters16: array[0..7] of string = ('ax', 'bx', 'cx', 'dx', 'si', 'di', 'bp', 'sp');
  cRegisters32: array[0..7] of string = ('eax', 'ebx', 'ecx', 'edx', 'esi', 'edi', 'ebp', 'esp');

/// <summary>Anweisung aus den Code-Token ACode (Indizes in ATokens).</summary>
function Build(const ATokens: TArray<TPascalToken>; const ACode: TArray<Integer>; AUncertain: Boolean): TAsmStatement;
var
  mIndex, mStart, mDepth: Integer;
  mOperand: TList<Integer>;
  mToken: TPascalToken;

  function TokenAt(APosition: Integer): TPascalToken;
  begin
    Result := ATokens[ACode[APosition]];
  end;

  procedure AddOperand;
  var
    mItem: TAsmOperand;
  begin
    mItem.Tokens := mOperand.ToArray;
    Result.Operands := Result.Operands + [mItem];
    mOperand.Clear;
  end;

begin
  Result := Default(TAsmStatement);
  Result.MnemonicToken := -1;
  Result.Uncertain := AUncertain;
  Result.LastToken := ACode[High(ACode)];
  // Sprungmarke: @@Ende:, @Ende: oder Ende:
  mStart := 0;
  while (mStart < Length(ACode)) and TokenAt(mStart).IsSymbol('@') do
    Inc(mStart);
  if (mStart + 1 < Length(ACode)) and (TokenAt(mStart).Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword, TPascalTokenKind.Number]) and TokenAt(mStart + 1).IsSymbol(':') then
    Inc(mStart, 2)
  else
    mStart := 0;
  while (mStart + 1 < Length(ACode)) and MatchText(TokenAt(mStart).Text, cPrefixes) do
    Inc(mStart);
  if mStart >= Length(ACode) then
  begin
    Result.FirstToken := Result.LastToken;
    Exit;
  end;
  Result.FirstToken := ACode[mStart];
  mToken := TokenAt(mStart);
  if mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
  begin
    Result.Mnemonic := LowerCase(mToken.Text);
    Result.MnemonicToken := ACode[mStart];
    Inc(mStart);
  end
  else if mToken.IsSymbol('.') and (mStart + 1 < Length(ACode)) and
    (TokenAt(mStart + 1).Kind = TPascalTokenKind.Identifier) then
  begin
    // Win64: .noframe, .params, .pushnv, .savenv
    Result.Mnemonic := '.' + LowerCase(TokenAt(mStart + 1).Text);
    Result.MnemonicToken := ACode[mStart];
    Inc(mStart, 2);
  end
  else
  begin
    Result.Uncertain := True;
    Exit;
  end;
  if mStart >= Length(ACode) then
    Exit;
  mOperand := TList<Integer>.Create;
  try
    mDepth := 0;
    for mIndex := mStart to High(ACode) do
    begin
      mToken := TokenAt(mIndex);
      if mToken.IsSymbol('[') or mToken.IsSymbol('(') then
        Inc(mDepth)
      else if (mToken.IsSymbol(']') or mToken.IsSymbol(')')) and (mDepth > 0) then
        Dec(mDepth)
      else if mToken.IsSymbol(',') and (mDepth = 0) then
      begin
        AddOperand;
        Continue;
      end;
      mOperand.Add(ACode[mIndex]);
    end;
    AddOperand;
  finally
    mOperand.Free;
  end;
end;

{ TAsmStatements }

class function TAsmStatements.Split(const ATokens: TArray<TPascalToken>; AFirst,
  ALast: Integer): TArray<TAsmStatement>;
begin
  Result := Split(ATokens, nil, -1, AFirst, ALast);
end;

class function TAsmStatements.Split(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>; AAsm, AFirst,
  ALast: Integer): TArray<TAsmStatement>;
var
  mList: TList<TAsmStatement>;
  mCode: TList<Integer>;
  mUncertain: Boolean;
  mIndex, mLastLine: Integer;
  mToken: TPascalToken;
  mAsmPath: string;

  procedure Flush;
  begin
    if mCode.Count > 0 then
      mList.Add(Build(ATokens, mCode.ToArray, mUncertain));
    mCode.Clear;
    mUncertain := False;
  end;

begin
  mList := TList<TAsmStatement>.Create;
  mCode := TList<Integer>.Create;
  try
    mUncertain := False;
    mLastLine := -1;
    mAsmPath := TConditionalBranches.PathAt(APaths, AAsm);
    for mIndex := AFirst to ALast do
    begin
      mToken := ATokens[mIndex];
      if mToken.Kind = TPascalTokenKind.Comment then
      begin
        if (mCode.Count > 0) and (mToken.StartPos.Line <= mLastLine) and not mToken.Text.StartsWith('//') then
          mUncertain := True;
        Continue;
      end;
      if (mToken.Kind = TPascalTokenKind.Directive) or
        not TConditionalBranches.Implies(TConditionalBranches.PathAt(APaths, mIndex), mAsmPath) then
      begin
        // Steht die Direktive (oder das fremde Token) in einer eigenen Zeile, endet die Anweisung davor sauber.
        if mToken.StartPos.Line > mLastLine then
          Flush;
        mUncertain := True;
        mLastLine := mToken.EndPos.Line;
        Continue;
      end;
      if mToken.StartPos.Line > mLastLine then
        Flush;
      mLastLine := mToken.EndPos.Line;
      if mToken.IsSymbol(';') then
      begin
        Flush;
        Continue;
      end;
      if (mToken.Kind = TPascalTokenKind.Unknown) or not mToken.Terminated then
        mUncertain := True;
      mCode.Add(mIndex);
    end;
    Flush;
    Result := mList.ToArray;
  finally
    mCode.Free;
    mList.Free;
  end;
end;

class function TAsmStatements.RegisterSize(const AName: string): Integer;
begin
  if MatchText(AName, cRegisters8) then
    Result := 1
  else if MatchText(AName, cRegisters16) then
    Result := 2
  else if MatchText(AName, cRegisters32) then
    Result := 4
  else
    Result := 0;
end;

class function TAsmStatements.IsDataDirective(const AMnemonic: string): Boolean;
begin
  Result := MatchStr(AMnemonic, ['db', 'dw', 'dd', 'dq', 'dt']);
end;

end.
