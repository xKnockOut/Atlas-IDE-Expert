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

type
  /// <summary>Teilt die Token eines asm-Blocks Zeile für Zeile in Anweisungen (TAsmStatements.Split).</summary>
  TAsmSplitter = class
  private
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FAsmPath: string;
    FList: TList<TAsmStatement>;
    FCode: TList<Integer>;
    FUncertain: Boolean;
    FLastLine: Integer;
    /// <summary>Schließt die laufende Anweisung ab.</summary>
    procedure Flush;
    /// <summary>Kommentar: zählt nicht, macht aber eine Anweisung mit { } oder (* *) mitten darin unsicher.</summary>
    procedure VisitComment(const AToken: TPascalToken);
    /// <summary>Direktive oder Token aus einem anderen Zweig als das asm.</summary>
    procedure VisitForeign(const AToken: TPascalToken);
    procedure VisitCode(AIndex: Integer);
    /// <summary>Gehört das Token AIndex sicher zum asm-Block (keine Direktive, gleicher oder umschließender
    /// Zweig)?</summary>
    function Belongs(AIndex: Integer): Boolean;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>; AAsm: Integer);
    destructor Destroy; override;
    procedure Visit(AIndex: Integer);
    /// <summary>Alle Anweisungen; schließt die letzte ab.</summary>
    function Statements: TArray<TAsmStatement>;
  end;

/// <summary>Index in ACode hinter Sprungmarke (@@Ende:, @Ende:, Ende:) und Präfixen (lock, rep …).</summary>
function InstructionStart(const ATokens: TArray<TPascalToken>; const ACode: TArray<Integer>): Integer;
begin
  Result := 0;
  while (Result < Length(ACode)) and ATokens[ACode[Result]].IsSymbol('@') do
  begin
    Inc(Result);
  end;
  if (Result + 1 < Length(ACode)) and (ATokens[ACode[Result]].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword, TPascalTokenKind.Number]) and ATokens[ACode[Result + 1]].IsSymbol(':') then
  begin
    Inc(Result, 2);
  end
  else
  begin
    Result := 0;
  end;
  while (Result + 1 < Length(ACode)) and MatchText(ATokens[ACode[Result]].Text, cPrefixes) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Liest den Befehl ab ACode[AStart] in AStatement und rückt AStart dahinter; False, wenn dort
/// kein Befehl steht.</summary>
function ReadMnemonic(const ATokens: TArray<TPascalToken>; const ACode: TArray<Integer>; var AStart: Integer;
  var AStatement: TAsmStatement): Boolean;
var
  mToken: TPascalToken;
begin
  mToken := ATokens[ACode[AStart]];
  Result := True;
  if mToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
  begin
    AStatement.Mnemonic := LowerCase(mToken.Text);
    AStatement.MnemonicToken := ACode[AStart];
    Inc(AStart);
  end
  else if mToken.IsSymbol('.') and (AStart + 1 < Length(ACode)) and
    (ATokens[ACode[AStart + 1]].Kind = TPascalTokenKind.Identifier) then
  begin
    // Win64: .noframe, .params, .pushnv, .savenv
    AStatement.Mnemonic := '.' + LowerCase(ATokens[ACode[AStart + 1]].Text);
    AStatement.MnemonicToken := ACode[AStart];
    Inc(AStart, 2);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Ändert die Klammertiefe ADepth für AToken; True bei einem Komma auf Tiefe 0.</summary>
function IsOperandSeparator(const AToken: TPascalToken; var ADepth: Integer): Boolean;
begin
  Result := False;
  if AToken.IsSymbol('[') or AToken.IsSymbol('(') then
  begin
    Inc(ADepth);
  end
  else if (AToken.IsSymbol(']') or AToken.IsSymbol(')')) and (ADepth > 0) then
  begin
    Dec(ADepth);
  end
  else
  begin
    Result := AToken.IsSymbol(',') and (ADepth = 0);
  end;
end;

/// <summary>Operanden aus ACode ab AStart: Ein Komma außerhalb von [] und () trennt.</summary>
function SplitOperands(const ATokens: TArray<TPascalToken>; const ACode: TArray<Integer>;
  AStart: Integer): TArray<TAsmOperand>;
var
  mIndex, mDepth: Integer;
  mOperand: TAsmOperand;
begin
  Result := nil;
  mOperand.Tokens := nil;
  mDepth := 0;
  for mIndex := AStart to High(ACode) do
  begin
    if IsOperandSeparator(ATokens[ACode[mIndex]], mDepth) then
    begin
      Result := Result + [mOperand];
      mOperand.Tokens := nil;
    end
    else
    begin
      mOperand.Tokens := mOperand.Tokens + [ACode[mIndex]];
    end;
  end;
  Result := Result + [mOperand];
end;

/// <summary>Anweisung aus den Code-Token ACode (Indizes in ATokens).</summary>
function Build(const ATokens: TArray<TPascalToken>; const ACode: TArray<Integer>; AUncertain: Boolean): TAsmStatement;
var
  mStart: Integer;
begin
  Result := Default(TAsmStatement);
  Result.MnemonicToken := -1;
  Result.Uncertain := AUncertain;
  Result.LastToken := ACode[High(ACode)];
  mStart := InstructionStart(ATokens, ACode);
  if mStart >= Length(ACode) then
  begin
    Result.FirstToken := Result.LastToken;
    Exit;
  end;
  Result.FirstToken := ACode[mStart];
  if not ReadMnemonic(ATokens, ACode, mStart, Result) then
  begin
    Result.Uncertain := True;
  end
  else if mStart < Length(ACode) then
  begin
    Result.Operands := SplitOperands(ATokens, ACode, mStart);
  end;
end;

{ TAsmSplitter }

constructor TAsmSplitter.Create(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>; AAsm: Integer);
begin
  inherited Create;
  FTokens := ATokens;
  FPaths := APaths;
  FAsmPath := TConditionalBranches.PathAt(APaths, AAsm);
  FList := TList<TAsmStatement>.Create;
  FCode := TList<Integer>.Create;
  FLastLine := -1;
end;

destructor TAsmSplitter.Destroy;
begin
  FCode.Free;
  FList.Free;
  inherited;
end;

procedure TAsmSplitter.Flush;
begin
  if FCode.Count > 0 then
  begin
    FList.Add(Build(FTokens, FCode.ToArray, FUncertain));
  end;
  FCode.Clear;
  FUncertain := False;
end;

function TAsmSplitter.Belongs(AIndex: Integer): Boolean;
begin
  Result := (FTokens[AIndex].Kind <> TPascalTokenKind.Directive) and
    TConditionalBranches.Implies(TConditionalBranches.PathAt(FPaths, AIndex), FAsmPath);
end;

procedure TAsmSplitter.VisitComment(const AToken: TPascalToken);
begin
  if (FCode.Count > 0) and (AToken.StartPos.Line <= FLastLine) and not AToken.Text.StartsWith('//') then
  begin
    FUncertain := True;
  end;
end;

procedure TAsmSplitter.VisitForeign(const AToken: TPascalToken);
begin
  // Steht die Direktive (oder das fremde Token) in einer eigenen Zeile, endet die Anweisung davor sauber.
  if AToken.StartPos.Line > FLastLine then
  begin
    Flush;
  end;
  FUncertain := True;
  FLastLine := AToken.EndPos.Line;
end;

procedure TAsmSplitter.VisitCode(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens[AIndex];
  if mToken.StartPos.Line > FLastLine then
  begin
    Flush;
  end;
  FLastLine := mToken.EndPos.Line;
  if mToken.IsSymbol(';') then
  begin
    Flush;
    Exit;
  end;
  if (mToken.Kind = TPascalTokenKind.Unknown) or not mToken.Terminated then
  begin
    FUncertain := True;
  end;
  FCode.Add(AIndex);
end;

procedure TAsmSplitter.Visit(AIndex: Integer);
begin
  if FTokens[AIndex].Kind = TPascalTokenKind.Comment then
  begin
    VisitComment(FTokens[AIndex]);
  end
  else if not Belongs(AIndex) then
  begin
    VisitForeign(FTokens[AIndex]);
  end
  else
  begin
    VisitCode(AIndex);
  end;
end;

function TAsmSplitter.Statements: TArray<TAsmStatement>;
begin
  Flush;
  Result := FList.ToArray;
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
  mSplitter: TAsmSplitter;
  mIndex: Integer;
begin
  mSplitter := TAsmSplitter.Create(ATokens, APaths, AAsm);
  try
    for mIndex := AFirst to ALast do
    begin
      mSplitter.Visit(mIndex);
    end;
    Result := mSplitter.Statements;
  finally
    mSplitter.Free;
  end;
end;

class function TAsmStatements.RegisterSize(const AName: string): Integer;
begin
  if MatchText(AName, cRegisters8) then
  begin
    Result := 1;
  end
  else if MatchText(AName, cRegisters16) then
  begin
    Result := 2;
  end
  else if MatchText(AName, cRegisters32) then
  begin
    Result := 4;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TAsmStatements.IsDataDirective(const AMnemonic: string): Boolean;
begin
  Result := MatchStr(AMnemonic, ['db', 'dw', 'dd', 'dq', 'dt']);
end;

end.
