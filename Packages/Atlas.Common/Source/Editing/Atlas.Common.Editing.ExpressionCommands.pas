unit Atlas.Common.Editing.ExpressionCommands;

// Schnellbefehle für Strings und Ausdrücke (#303) im Rahmen aus #293. Alle
// wirken auf die Anweisung bzw. das Literal in der Zeile unter dem Befehl:
//   /format       'Kunde ' + Name + ' hat ' + IntToStr(N) wird zu
//                 Format('Kunde %s hat %d', [Name, N]); Platzhalter nach dem
//                 deklarierten Typ, bei unbekanntem Typ %s mit Hinweis
//   /multiline    verkettetes Literal mit Zeilenumbrüchen wird zu ''' (ab Delphi 12)
//   /multiline!   umgekehrt: ''' wird zur Verkettung mit sLineBreak
//   /iif          if B then X := A else X := C; wird zu X := if B then A else C;
//                 (ab Delphi 13)
//   /inc          X := X + 1 wird zu Inc(X), X := X - N zu Dec(X, N)
//   /modern       moderne Schreibweisen in der umgebenden Routine (for-in, Inline-Variablen,
//                 FreeAndNil); mit -for, -inline bzw. -free einzeln abschaltbar

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Befehle über ARegister ein.</summary>
procedure RegisterExpressionCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.Modernizer,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TExpressionCommandsText = (IncOnlyConvertsASingle, IncAndDecOnlyApply, BelowIncThereIsNo,
    IifNeedsConditionalExpressionsWhich, BelowIifThereIsNo, TheLiteralContainsMoreThan, TheLiteralIsAlreadyMulti,
    TheLiteralIsNotMulti, TheLiteralContainsNoLine, BelowTheCommandThereIs, IncompleteConcatenation,
    FormatOnlyConvertsConcatenationsWith, BelowFormatThereIsNo, FormatTypeOfUnknownAssumed,
    FormatAppliesToAConcatenation, InTheLineBelowFormat, ExpectedIsModernForInline, ModernOnlyAppliesInThe,
    ThereIsNothingToModernize, ModernizeTheEnclosingRoutineFor, ConvertTheStringConcatenationBelow,
    WriteTheConcatenatedLiteralBelow, WriteTheMultiLineString, IfElseAssignmentBelowAs, XXNBelowAs,
    IifNeedsTheSameTarget, MultiLineStringsExistOnly, ExpectedIsXXN, ExpectedIsIfBThen);

const
  cTexts: array[TExpressionCommandsText] of TAtlasText = (
    (De: '/inc wandelt nur einen einzelnen Summanden um'; En: '/inc only converts a single summand'),
    (De: 'Inc und Dec gelten nur für ganze Zahlen'; En: 'Inc and Dec only apply to integers'),
    (De: 'Unter /inc steht keine Zuweisung in einer Routine'; En: 'Below /inc there is no assignment in a routine'),
    (De: '/iif braucht Bedingungsausdrücke, die es erst ab Delphi 13 gibt (eingestellt: %s)';
     En: '/iif needs conditional expressions, which exist only from Delphi 13 on (set: %s)'),
    (De: 'Unter /iif steht keine if-Anweisung in einer Routine';
     En: 'Below /iif there is no if statement in a routine'),
    (De: 'Das Literal enthält mehr als Strings, sLineBreak und +';
     En: 'The literal contains more than strings, sLineBreak and +'),
    (De: 'Das Literal ist schon mehrzeilig'; En: 'The literal is already multi-line'),
    (De: 'Das Literal ist nicht mehrzeilig'; En: 'The literal is not multi-line'),
    (De: 'Das Literal enthält keinen Zeilenumbruch'; En: 'The literal contains no line break'),
    (De: 'Unter dem Befehl steht kein String-Literal'; En: 'Below the command there is no string literal'),
    (De: 'Unvollständige Verkettung'; En: 'Incomplete concatenation'),
    (De: '/format wandelt nur Verkettungen mit + um'; En: '/format only converts concatenations with +'),
    (De: 'Unter /format steht keine Verkettung aus Text und Werten';
     En: 'Below /format there is no concatenation of text and values'),
    (De: ' // /format: Typ von %s unbekannt, %%s angenommen'; En: ' // /format: type of %s unknown, %%s assumed'),
    (De: '/format gilt für eine Verkettung in der Zeile darunter, im Rumpf einer Routine';
     En: '/format applies to a concatenation in the line below, in the body of a routine'),
    (De: 'In der Zeile unter /format steht kein String-Literal';
     En: 'In the line below /format there is no string literal'),
    (De: 'Erwartet wird /modern [-for] [-inline] [-free]'; En: 'Expected is /modern [-for] [-inline] [-free]'),
    (De: '/modern gilt nur im Rumpf einer Routine'; En: '/modern only applies in the body of a routine'),
    (De: 'In dieser Routine gibt es nichts zu modernisieren'; En: 'There is nothing to modernize in this routine'),
    (De: 'Umgebende Routine modernisieren (for-in, Inline-Variablen, FreeAndNil)';
     En: 'Modernize the enclosing routine (for-in, inline variables, FreeAndNil)'),
    (De: 'String-Verkettung darunter in Format(…) umwandeln';
     En: 'Convert the string concatenation below into Format(…)'),
    (De: 'Verkettetes Literal darunter als mehrzeiligen String schreiben';
     En: 'Write the concatenated literal below as a multi-line string'),
    (De: 'Mehrzeiligen String darunter als Verkettung schreiben';
     En: 'Write the multi-line string below as a concatenation'),
    (De: 'if/else-Zuweisung darunter als Bedingungsausdruck';
     En: 'if/else assignment below as conditional expression'),
    (De: 'X := X + N darunter als Inc bzw. Dec'; En: 'X := X + N below as Inc or Dec'),
    (De: '/iif braucht in beiden Zweigen dieselbe Zielvariable';
     En: '/iif needs the same target variable in both branches'),
    (De: 'Mehrzeilige Strings gibt es erst ab Delphi 12 (eingestellt: %s)';
     En: 'Multi-line strings exist only from Delphi 12 (set: %s)'),
    (De: 'Erwartet wird X := X + N bzw. X := X - N'; En: 'Expected is X := X + N or X := X - N'),
    (De: 'Erwartet wird if B then X := A else X := C;'; En: 'Expected is if B then X := A else X := C;'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

/// <summary>Code-Tokens von AText ohne Kommentare.</summary>
function CodeTokens(const AText: string): TTokens;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + [mToken];
    end;
  end;
end;

/// <summary>Text der Tokens AFirst bis ALast aus AText.</summary>
function Slice(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

function Opens(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

function Closes(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']');
end;

/// <summary>Anweisung ab der Zeile unter dem Befehl bis zum ersten ";" am Zeilenende (höchstens 20 Zeilen).
/// ALast ist ihre letzte Zeile; der Text ist zu einer Zeile zusammengefasst.</summary>
function StatementBelow(ASource: TCommandSource; out ALast: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  AText := '';
  ALast := -1;
  for mIndex := ASource.Line + 1 to Min(High(ASource.Lines), ASource.Line + 20) do
  begin
    if AText <> '' then
    begin
      AText := AText + ' ';
    end;
    AText := AText + Trim(ASource.Lines[mIndex]);
    if EndsStr(';', TrimRight(ASource.Lines[mIndex])) then
    begin
      ALast := mIndex;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ersetzt Befehlszeile und Anweisung (Zeilen bis ALast) durch ANewText mit der Einrückung
/// der Anweisung.</summary>
function ReplaceStatement(ASource: TCommandSource; ALast: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ALast, Length(ASource.Lines[ALast])),
    ASource.Indent(ASource.Line + 1) + ANewText);
end;

/// <summary>Zählt die Klammerebene ADepth an AToken weiter; True, wenn AToken eine Klammer ist.</summary>
function StepDepth(const AToken: TPascalToken; var ADepth: Integer): Boolean;
begin
  Result := True;
  if Opens(AToken) then
  begin
    Inc(ADepth);
  end
  else if Closes(AToken) then
  begin
    Dec(ADepth);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Index des ersten Tokens AText ab AFrom auf Klammerebene 0; -1 ohne.</summary>
function FindTop(const ATokens: TTokens; AFrom: Integer; const AText: string): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := -1;
  mDepth := 0;
  mIndex := AFrom;
  while (Result < 0) and (mIndex <= High(ATokens)) do
  begin
    if (mDepth = 0) and SameText(ATokens[mIndex].Text, AText) then
    begin
      Result := mIndex;
    end;
    StepDepth(ATokens[mIndex], mDepth);
    Inc(mIndex);
  end;
end;

/// <summary>Letzter Token-Index vor einem abschließenden ";".</summary>
function StopBeforeSemicolon(const ATokens: TTokens): Integer;
begin
  Result := High(ATokens);
  if (Result >= 0) and ATokens[Result].IsSymbol(';') then
  begin
    Dec(Result);
  end;
end;

{ /inc }


type
  /// <summary>Zerlegung von X := X + N bzw. X := X - N für /inc.</summary>
  TIncStatement = record
    Text: string;
    Tokens: TTokens;
    Assign: Integer;
    Operator_: Integer;
    Stop: Integer;
    /// <summary>Zerlegt Text; '' wenn die Anweisung passt, sonst der Grund.</summary>
    function Parse: string;
    /// <summary>Rechts vom := stehen zuerst dieselben Tokens wie links.</summary>
    function SidesMatch: Boolean;
    /// <summary>Grund, warum der Summand nicht zu Inc/Dec passt; '' wenn er passt.</summary>
    function AmountProblem: string;
    function Replacement: string;
  end;

/// <summary>Plus, Minus, or oder xor: Mit einem weiteren davon wäre Inc/Dec nicht gleichwertig.</summary>
function IsAdditive(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('+') or AToken.IsSymbol('-') or AToken.IsKeyword('or') or AToken.IsKeyword('xor');
end;

function IsFloatNumber(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Number) and (LastDelimiter('.eE', AToken.Text) > 0) and
    not StartsStr('$', AToken.Text);
end;

function TIncStatement.SidesMatch: Boolean;
var
  mIndex: Integer;
begin
  Result := (Assign > 0) and (2 * Assign + 2 <= High(Tokens));
  mIndex := 0;
  while Result and (mIndex < Assign) do
  begin
    Result := SameText(Tokens[mIndex].Text, Tokens[Assign + 1 + mIndex].Text);
    Inc(mIndex);
  end;
end;

function TIncStatement.Parse: string;
begin
  Result := cTexts[TExpressionCommandsText.ExpectedIsXXN].Text;
  Tokens := CodeTokens(Text);
  Assign := FindTop(Tokens, 0, ':=');
  if not SidesMatch then
  begin
    Exit;
  end;
  Operator_ := 2 * Assign + 1;
  Stop := StopBeforeSemicolon(Tokens);
  if (Tokens[Operator_].IsSymbol('+') or Tokens[Operator_].IsSymbol('-')) and (Stop > Operator_) then
  begin
    Result := AmountProblem;
  end;
end;

function TIncStatement.AmountProblem: string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  mDepth := 0;
  mIndex := Operator_ + 1;
  while (Result = '') and (mIndex <= Stop) do
  begin
    if not StepDepth(Tokens[mIndex], mDepth) and (mDepth = 0) and IsAdditive(Tokens[mIndex]) then
    begin
      Result := cTexts[TExpressionCommandsText.IncOnlyConvertsASingle].Text;
    end
    else if IsFloatNumber(Tokens[mIndex]) then
    begin
      Result := cTexts[TExpressionCommandsText.IncAndDecOnlyApply].Text;
    end;
    Inc(mIndex);
  end;
end;

function TIncStatement.Replacement: string;
var
  mAmount: string;
begin
  mAmount := Slice(Text, Tokens, Operator_ + 1, Stop);
  Result := IfThen(Tokens[Operator_].IsSymbol('+'), 'Inc', 'Dec') + '(' + Slice(Text, Tokens, 0, Assign - 1);
  if mAmount <> '1' then
  begin
    Result := Result + ', ' + mAmount;
  end;
  Result := Result + ');';
end;

function ExecuteInc(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mStatement: TIncStatement;
  mLast: Integer;
begin
  AEdits := nil;
  mStatement := Default(TIncStatement);
  mSource := TCommandSource.Create(AContext);
  try
    if (mSource.RoutineAt = nil) or not StatementBelow(mSource, mLast, mStatement.Text) then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.BelowIncThereIsNo].Text, AReason));
    end;
    AReason := mStatement.Parse;
    Result := AReason = '';
    if Result then
    begin
      AEdits := [ReplaceStatement(mSource, mLast, mStatement.Replacement)];
    end;
  finally
    mSource.Free;
  end;
end;

{ /iif }


type
  /// <summary>Zerlegung von if B then X := A else X := C; für /iif.</summary>
  TIifStatement = record
    Text: string;
    Tokens: TTokens;
    ThenAt: Integer;
    ElseAt: Integer;
    FirstAssign: Integer;
    SecondAssign: Integer;
    Stop: Integer;
    /// <summary>Zerlegt Text; '' wenn die Anweisung passt, sonst der Grund.</summary>
    function Parse: string;
    /// <summary>Findet then, else und beide Zuweisungen.</summary>
    function FindParts: Boolean;
    /// <summary>Die Zweige enthalten keine weiteren Anweisungen.</summary>
    function BranchesSimple: Boolean;
    function Replacement: string;
  end;

function TIifStatement.FindParts: Boolean;
begin
  Tokens := CodeTokens(Text);
  Result := (Length(Tokens) >= 10) and Tokens[0].IsKeyword('if');
  if Result then
  begin
    ThenAt := FindTop(Tokens, 1, 'then');
    FirstAssign := FindTop(Tokens, ThenAt + 1, ':=');
    ElseAt := FindTop(Tokens, ThenAt + 1, 'else');
    Result := (ThenAt >= 0) and (FirstAssign >= 0) and (ElseAt >= FirstAssign);
  end;
  if Result then
  begin
    SecondAssign := FindTop(Tokens, ElseAt + 1, ':=');
    Stop := StopBeforeSemicolon(Tokens);
    Result := (SecondAssign >= 0) and (SecondAssign < Stop);
  end;
end;

function TIifStatement.BranchesSimple: Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  mIndex := ThenAt + 1;
  while Result and (mIndex <= Stop) do
  begin
    Result := not (Tokens[mIndex].IsKeyword('begin') or Tokens[mIndex].IsKeyword('if') or
      Tokens[mIndex].IsSymbol(';'));
    Inc(mIndex);
  end;
end;

function TIifStatement.Parse: string;
begin
  Result := cTexts[TExpressionCommandsText.ExpectedIsIfBThen].Text;
  if not FindParts then
  begin
    Exit;
  end;
  // Beide Zweige weisen demselben Ziel zu und enthalten keine weiteren Anweisungen.
  if not SameText(Slice(Text, Tokens, ThenAt + 1, FirstAssign - 1),
    Slice(Text, Tokens, ElseAt + 1, SecondAssign - 1)) then
  begin
    Exit(cTexts[TExpressionCommandsText.IifNeedsTheSameTarget].Text);
  end;
  if BranchesSimple then
  begin
    Result := '';
  end;
end;

function TIifStatement.Replacement: string;
begin
  Result := Format('%s := if %s then %s else %s;', [Slice(Text, Tokens, ThenAt + 1, FirstAssign - 1),
    Slice(Text, Tokens, 1, ThenAt - 1), Slice(Text, Tokens, FirstAssign + 1, ElseAt - 1),
    Slice(Text, Tokens, SecondAssign + 1, Stop)]);
end;

function ExecuteIif(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mStatement: TIifStatement;
  mLast: Integer;
begin
  AEdits := nil;
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, AContext.DelphiVersion) then
  begin
    Exit(Fail(cTexts[TExpressionCommandsText.IifNeedsConditionalExpressionsWhich].Fmt([AContext.DelphiVersion]),
      AReason));
  end;
  mStatement := Default(TIifStatement);
  mSource := TCommandSource.Create(AContext);
  try
    if (mSource.RoutineAt = nil) or not StatementBelow(mSource, mLast, mStatement.Text) then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.BelowIifThereIsNo].Text, AReason));
    end;
    AReason := mStatement.Parse;
    Result := AReason = '';
    if Result then
    begin
      AEdits := [ReplaceStatement(mSource, mLast, mStatement.Replacement)];
    end;
  finally
    mSource.Free;
  end;
end;

{ /multiline }

/// <summary>Bereich des Literals in der Zeile unter dem Befehl.</summary>
function LiteralBelow(ASource: TCommandSource; const AContext: TSlashContext; out ARange: TTextRange): Boolean;
var
  mColumn: Integer;
begin
  Result := False;
  if ASource.Line + 1 > High(ASource.Lines) then
  begin
    Exit;
  end;
  mColumn := Pos('''', ASource.Lines[ASource.Line + 1]);
  if mColumn = 0 then
  begin
    Exit;
  end;
  Result := TStringLiterals.LiteralAt(AContext.Text, TTextPosition.Create(ASource.Line + 1, mColumn - 1), ARange);
end;

/// <summary>Grund, warum AExpression nicht umgeschrieben werden kann; '' wenn es geht. APlain ist der Klartext.
/// </summary>
function MultilineProblem(const AExpression: string; AToMultiline: Boolean; out APlain: string): string;
begin
  Result := '';
  if not TStringLiterals.PlainText(AExpression, APlain) then
  begin
    Result := cTexts[TExpressionCommandsText.TheLiteralContainsMoreThan].Text;
  end
  else if StartsStr('''''''', Trim(AExpression)) = AToMultiline then
  begin
    Result := IfThen(AToMultiline, cTexts[TExpressionCommandsText.TheLiteralIsAlreadyMulti].Text,
      cTexts[TExpressionCommandsText.TheLiteralIsNotMulti].Text);
  end
  else if AToMultiline and (Pos(#10, APlain) = 0) then
  begin
    Result := cTexts[TExpressionCommandsText.TheLiteralContainsNoLine].Text;
  end;
end;

function ExecuteMultiline(const AContext: TSlashContext; AToMultiline: Boolean; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRange: TTextRange;
  mPlain, mLiteral: string;
begin
  AEdits := nil;
  if AToMultiline and not TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AContext.DelphiVersion) then
  begin
    Exit(Fail(cTexts[TExpressionCommandsText.MultiLineStringsExistOnly].Fmt([AContext.DelphiVersion]),
      AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if not LiteralBelow(mSource, AContext, mRange) then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.BelowTheCommandThereIs].Text, AReason));
    end;
    AReason := MultilineProblem(TStringLiterals.TextOf(AContext.Text, mRange), AToMultiline, mPlain);
    Result := AReason = '';
    if Result then
    begin
      mLiteral := TStringLiterals.ToLiteral(mPlain, mSource.Indent(mSource.Line + 1), False, AToMultiline,
        TStringLiteralSettings.Default, mSource.LineBreak);
      AEdits := [mSource.RemoveCommand, TTextEdit.Create(mRange, mLiteral)];
    end;
  finally
    mSource.Free;
  end;
end;

{ /format }

/// <summary>True bei AFunction(X) mit einem Argument; AInner ist X.</summary>
function UnwrapCall(const AOperand, AFunction: string; out AInner: string): Boolean;
begin
  Result := StartsText(AFunction + '(', AOperand) and EndsStr(')', AOperand);
  if Result then
  begin
    AInner := Copy(AOperand, Length(AFunction) + 2, Length(AOperand) - Length(AFunction) - 2);
    Result := Pos(',', AInner) = 0;
  end;
end;

/// <summary>Platzhalter zum deklarierten Typ; '' bei unbekanntem Typ.</summary>
function TypePlaceholder(const ATypeName: string): string;
begin
  Result := '';
  if TDeclaredTypes.IsInt32(ATypeName) or TDeclaredTypes.IsInt64(ATypeName) then
  begin
    Result := '%d';
  end
  else if TDeclaredTypes.IsFloat(ATypeName) then
  begin
    Result := '%g';
  end
  else if TDeclaredTypes.IsChar(ATypeName) or MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString',
    'WideString', 'ShortString', 'UTF8String', 'RawByteString']) then
  begin
    Result := '%s';
  end;
end;

/// <summary>Platzhalter für AOperand; AArgument ist das Argument, AKnown False bei unbekanntem Typ.</summary>
function Placeholder(ATypes: TDeclaredTypes; const AOperand: string; const APosition: TTextPosition;
  out AArgument: string; out AKnown: Boolean): string;
begin
  Result := '';
  // IntToStr(X) und FloatToStr(X) entfallen.
  if UnwrapCall(AOperand, 'IntToStr', AArgument) then
  begin
    Result := '%d';
  end
  else if UnwrapCall(AOperand, 'FloatToStr', AArgument) then
  begin
    Result := '%g';
  end
  else
  begin
    AArgument := AOperand;
    if IsValidIdent(AOperand) then
    begin
      Result := TypePlaceholder(ATypes.DeclaredType(AOperand, APosition));
    end;
  end;
  AKnown := Result <> '';
  if not AKnown then
  begin
    Result := '%s';
  end;
end;

/// <summary>Index des ersten String-Literals; -1 ohne.</summary>
function FirstLiteral(const ATokens: TTokens): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(ATokens)) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.StringLiteral then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

function IsSeparator(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(',') or AToken.IsSymbol(':=') or AToken.IsSymbol(';') or AToken.IsSymbol('=') or
    AToken.IsSymbol('<>');
end;

/// <summary>Grenze des Ausdrucks um das Literal: Komma, Zuweisung, Vergleich oder Schlüsselwort außer nil.
/// </summary>
function Stops(const AToken: TPascalToken): Boolean;
begin
  Result := IsSeparator(AToken) or (AToken.Kind = TPascalTokenKind.Keyword) and not AToken.IsKeyword('nil');
end;

/// <summary>True, wenn der Ausdruck vor AToken endet. ALeft: Suche nach links; ADepth ist die Klammerebene.
/// </summary>
function ReachesBoundary(const AToken: TPascalToken; ALeft: Boolean; var ADepth: Integer): Boolean;
var
  mEnters, mLeaves: Boolean;
begin
  mEnters := Opens(AToken);
  mLeaves := Closes(AToken);
  if ALeft then
  begin
    mEnters := Closes(AToken);
    mLeaves := Opens(AToken);
  end;
  Result := False;
  if mEnters then
  begin
    Inc(ADepth);
  end
  else if mLeaves then
  begin
    Result := ADepth = 0;
    Dec(ADepth);
  end
  else
  begin
    Result := (ADepth = 0) and Stops(AToken);
  end;
end;

/// <summary>Erster (ALeft) bzw. letzter Token des Ausdrucks um AHit.</summary>
function ExpressionEdge(const ATokens: TTokens; AHit: Integer; ALeft: Boolean): Integer;
var
  mDepth, mStep: Integer;
begin
  Result := AHit;
  mDepth := 0;
  mStep := 1;
  if ALeft then
  begin
    mStep := -1;
  end;
  while (Result + mStep >= 0) and (Result + mStep <= High(ATokens)) and
    not ReachesBoundary(ATokens[Result + mStep], ALeft, mDepth) do
  begin
    Inc(Result, mStep);
  end;
end;

type
  /// <summary>Wandelt eine Verkettung in der Zeile unter /format in Format(…) um.</summary>
  TConcatenation = class
  private
    FLine: string;
    FTokens: TTokens;
    FTypes: TDeclaredTypes;
    FPosition: TTextPosition;
    FFirst: Integer;
    FLast: Integer;
    FMask: string;
    FArguments: string;
    FUnknown: string;
    FLiterals: Integer;
    FOthers: Integer;
    procedure AddOperand(AFirst, ALast: Integer);
    procedure AddArgument(const AOperand: string);
    /// <summary>Behandelt den Token AIndex auf oberster Ebene; '' oder der Grund des Abbruchs.</summary>
    function TopLevel(AIndex: Integer; var AStart: Integer): string;
    function Split: string;
  public
    constructor Create(ASource: TCommandSource; const ATokens: TTokens; AHit: Integer);
    destructor Destroy; override;
    /// <summary>Zerlegt die Verkettung; '' wenn sie passt, sonst der Grund.</summary>
    function Convert: string;
    /// <summary>Neue Zeile mit Format(…).</summary>
    function Replacement: string;
  end;

constructor TConcatenation.Create(ASource: TCommandSource; const ATokens: TTokens; AHit: Integer);
begin
  inherited Create;
  FLine := ASource.Lines[ASource.Line + 1];
  FTokens := ATokens;
  // Ausdruck um das Literal: nach links und rechts bis zu Komma, Zuweisung, Klammer oder Schlüsselwort.
  FFirst := ExpressionEdge(ATokens, AHit, True);
  FLast := ExpressionEdge(ATokens, AHit, False);
  FPosition := TTextPosition.Create(ASource.Line + 1, ATokens[FFirst].StartPos.Character);
  FTypes := TDeclaredTypes.Create(ASource.Tree, ASource.Text);
end;

destructor TConcatenation.Destroy;
begin
  FTypes.Free;
  inherited;
end;

procedure TConcatenation.AddArgument(const AOperand: string);
var
  mArgument: string;
  mKnown: Boolean;
begin
  FMask := FMask + Placeholder(FTypes, AOperand, FPosition, mArgument, mKnown);
  if FArguments <> '' then
  begin
    FArguments := FArguments + ', ';
  end;
  FArguments := FArguments + mArgument;
  if not mKnown then
  begin
    FUnknown := FUnknown + IfThen(FUnknown <> '', ', ', '') + AOperand;
  end;
  Inc(FOthers);
end;

procedure TConcatenation.AddOperand(AFirst, ALast: Integer);
var
  mOperand, mPlain: string;
begin
  mOperand := Slice(FLine, FTokens, AFirst, ALast);
  // Nur Zeichenkonstanten: als Literal lesen.
  if TStringLiterals.PlainText(mOperand, mPlain) or TStringLiterals.PlainText(''''' + ' + mOperand, mPlain) then
  begin
    FMask := FMask + StringReplace(mPlain, '%', '%%', [rfReplaceAll]);
    Inc(FLiterals);
  end
  else
  begin
    AddArgument(mOperand);
  end;
end;

function TConcatenation.TopLevel(AIndex: Integer; var AStart: Integer): string;
begin
  Result := '';
  if FTokens[AIndex].IsSymbol('+') then
  begin
    if AIndex = AStart then
    begin
      Result := cTexts[TExpressionCommandsText.IncompleteConcatenation].Text;
    end
    else
    begin
      AddOperand(AStart, AIndex - 1);
      AStart := AIndex + 1;
    end;
  end
  else if (FTokens[AIndex].Kind = TPascalTokenKind.Symbol) and (FTokens[AIndex].Text <> '.') then
  begin
    Result := cTexts[TExpressionCommandsText.FormatOnlyConvertsConcatenationsWith].Text;
  end;
end;

function TConcatenation.Split: string;
var
  mIndex, mStart, mDepth: Integer;
begin
  // An "+" auf oberster Ebene zerlegen; andere Operatoren dort lassen keine Umwandlung zu.
  Result := '';
  mStart := FFirst;
  mDepth := 0;
  mIndex := FFirst;
  while (Result = '') and (mIndex <= FLast) do
  begin
    if not StepDepth(FTokens[mIndex], mDepth) and (mDepth = 0) then
    begin
      Result := TopLevel(mIndex, mStart);
    end;
    Inc(mIndex);
  end;
  if (Result = '') and (mStart > FLast) then
  begin
    Result := cTexts[TExpressionCommandsText.IncompleteConcatenation].Text;
  end;
  if Result = '' then
  begin
    AddOperand(mStart, FLast);
  end;
end;

function TConcatenation.Convert: string;
begin
  Result := Split;
  if (Result = '') and ((FLiterals = 0) or (FOthers = 0)) then
  begin
    Result := cTexts[TExpressionCommandsText.BelowFormatThereIsNo].Text;
  end;
end;

function TConcatenation.Replacement: string;
begin
  Result := Copy(FLine, 1, FTokens[FFirst].Offset) + Format('Format(%s, [%s])', [TStringLiterals.Quote(FMask),
    FArguments]) + Copy(FLine, FTokens[FLast].Offset + Length(FTokens[FLast].Text) + 1, MaxInt);
  if FUnknown <> '' then
  begin
    Result := Result + cTexts[TExpressionCommandsText.FormatTypeOfUnknownAssumed].Fmt([FUnknown]);
  end;
end;

function ExecuteFormat(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mConcatenation: TConcatenation;
  mTokens: TTokens;
  mHit: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if (mSource.RoutineAt = nil) or (mSource.Line + 1 > High(mSource.Lines)) then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.FormatAppliesToAConcatenation].Text, AReason));
    end;
    mTokens := CodeTokens(mSource.Lines[mSource.Line + 1]);
    mHit := FirstLiteral(mTokens);
    if mHit < 0 then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.InTheLineBelowFormat].Text, AReason));
    end;
    mConcatenation := TConcatenation.Create(mSource, mTokens, mHit);
    try
      AReason := mConcatenation.Convert;
      Result := AReason = '';
      if Result then
      begin
        AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1,
          Length(mSource.Lines[mSource.Line + 1])), mConcatenation.Replacement)];
        AddUses(mSource, AContext, mSource.Line, ['System.SysUtils'], AEdits);
      end;
    finally
      mConcatenation.Free;
    end;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

{ /modern }

/// <summary>Arten aus den Optionen -for, -inline und -free; False bei unbekannter Option.</summary>
function ModernKinds(const AContext: TSlashContext; out AKinds: TModernizations): Boolean;
var
  mOption: string;
begin
  Result := True;
  AKinds := [TModernization.ForIn, TModernization.InlineVar, TModernization.FreeAndNilCall];
  for mOption in AContext.Arguments.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    if SameText(mOption, '-for') then
    begin
      Exclude(AKinds, TModernization.ForIn);
    end
    else if SameText(mOption, '-inline') then
    begin
      Exclude(AKinds, TModernization.InlineVar);
    end
    else if SameText(mOption, '-free') then
    begin
      Exclude(AKinds, TModernization.FreeAndNilCall);
    end
    else
    begin
      Result := False;
    end;
  end;
  // for var und Inline-Variablen gibt es erst ab Delphi 10.3.
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion) then
  begin
    AKinds := AKinds - [TModernization.ForIn, TModernization.InlineVar];
  end;
end;

/// <summary>Zeilen der Routine ohne die Befehlszeile.</summary>
function RoutineLines(ASource: TCommandSource; ARoutine: TSyntaxNode): TArray<string>;
var
  mLine: Integer;
begin
  Result := nil;
  for mLine := ARoutine.StartPos.Line to ARoutine.EndPos.Line do
  begin
    if mLine <> ASource.Line then
    begin
      Result := Result + [ASource.Lines[mLine]];
    end;
  end;
end;

function JoinLines(const ALines: TArray<string>; const ALineBreak: string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + ALineBreak;
  end;
end;

function ExecuteModern(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mKinds: TModernizations;
  mLines: TArray<string>;
  mCount: Integer;
begin
  AEdits := nil;
  if not ModernKinds(AContext, mKinds) then
  begin
    Exit(Fail(cTexts[TExpressionCommandsText.ExpectedIsModernForInline].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.ModernOnlyAppliesInThe].Text, AReason));
    end;
    mLines := TModernizer.Apply(RoutineLines(mSource, mRoutine), mKinds, mCount);
    if mCount = 0 then
    begin
      Exit(Fail(cTexts[TExpressionCommandsText.ThereIsNothingToModernize].Text, AReason));
    end;
    AEdits := [TTextEdit.Create(TTextRange.Create(mRoutine.StartPos.Line, 0, mRoutine.EndPos.Line + 1, 0),
      JoinLines(mLines, mSource.LineBreak))];
    if TModernization.FreeAndNilCall in mKinds then
    begin
      AddUses(mSource, AContext, mRoutine.StartPos.Line, ['System.SysUtils'], AEdits);
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

procedure RegisterExpressionCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('modern', cTexts[TExpressionCommandsText.ModernizeTheEnclosingRoutineFor].Text,
    '/modern -inline', ExecuteModern));
  ARegister(Command('format', cTexts[TExpressionCommandsText.ConvertTheStringConcatenationBelow].Text, '/format',
    ExecuteFormat));
  ARegister(Command('multiline', cTexts[TExpressionCommandsText.WriteTheConcatenatedLiteralBelow].Text,
    '/multiline',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteMultiline(AContext, True, AEdits, AReason);
    end));
  ARegister(Command('multiline!', cTexts[TExpressionCommandsText.WriteTheMultiLineString].Text, '/multiline!',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteMultiline(AContext, False, AEdits, AReason);
    end));
  ARegister(Command('iif', cTexts[TExpressionCommandsText.IfElseAssignmentBelowAs].Text, '/iif', ExecuteIif));
  ARegister(Command('inc', cTexts[TExpressionCommandsText.XXNBelowAs].Text, '/inc', ExecuteInc));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ExpressionCommands', cTexts);

end.
