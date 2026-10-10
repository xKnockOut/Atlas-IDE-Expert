unit Argus.Common.Editing.ExpressionCommands;

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
  Argus.Common.Editing.SlashCommands;

/// <summary>Trägt die Befehle in ARegistry ein.</summary>
procedure RegisterExpressionCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.LanguageFeatures,
  Argus.Common.Rules.DeclaredTypes,
  Argus.Common.Editing.StringLiterals,
  Argus.Common.Editing.Modernizer,
  Argus.Common.Editing.CommandSource;

type
  TTokens = TArray<TPascalToken>;

/// <summary>Code-Tokens von AText ohne Kommentare.</summary>
function CodeTokens(const AText: string): TTokens;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in TPascalLexer.Tokenize(AText) do
    if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Result := Result + [Token];
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
  Index: Integer;
begin
  AText := '';
  ALast := -1;
  for Index := ASource.Line + 1 to Min(High(ASource.Lines), ASource.Line + 20) do
  begin
    if AText <> '' then
      AText := AText + ' ';
    AText := AText + Trim(ASource.Lines[Index]);
    if EndsStr(';', TrimRight(ASource.Lines[Index])) then
    begin
      ALast := Index;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ersetzt Befehlszeile und Anweisung (Zeilen bis ALast) durch ANewText mit der Einrückung
/// der Anweisung.</summary>
function ReplaceStatement(ASource: TCommandSource; ALast: Integer; const ANewText: string): TRuleEdit;
begin
  Result := TRuleEdit.Create(TTextRange.Create(ASource.Line, 0, ALast, Length(ASource.Lines[ALast])),
    ASource.Indent(ASource.Line + 1) + ANewText);
end;

/// <summary>Index des ersten Tokens AText ab AFrom auf Klammerebene 0; -1 ohne.</summary>
function FindTop(const ATokens: TTokens; AFrom: Integer; const AText: string): Integer;
var
  Index, Depth: Integer;
begin
  Depth := 0;
  for Index := AFrom to High(ATokens) do
  begin
    if (Depth = 0) and SameText(ATokens[Index].Text, AText) then
      Exit(Index);
    if Opens(ATokens[Index]) then
      Inc(Depth)
    else if Closes(ATokens[Index]) then
      Dec(Depth);
  end;
  Result := -1;
end;

{ /inc }

function ExecuteInc(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Text, Target, Amount: string;
  Tokens: TTokens;
  Last, Assign, Index, Operator_, Stop, Depth: Integer;
  Increment: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if (Source.RoutineAt = nil) or not StatementBelow(Source, Last, Text) then
      Exit(Fail('Unter /inc steht keine Zuweisung in einer Routine', AReason));
    Tokens := CodeTokens(Text);
    Assign := FindTop(Tokens, 0, ':=');
    // X := X + N: rechts zuerst dieselben Tokens wie links.
    if (Assign <= 0) or (2 * Assign + 2 > High(Tokens)) then
      Exit(Fail('Erwartet wird X := X + N bzw. X := X - N', AReason));
    for Index := 0 to Assign - 1 do
      if not SameText(Tokens[Index].Text, Tokens[Assign + 1 + Index].Text) then
        Exit(Fail('Erwartet wird X := X + N bzw. X := X - N', AReason));
    Operator_ := 2 * Assign + 1;
    Increment := Tokens[Operator_].IsSymbol('+');
    if not (Increment or Tokens[Operator_].IsSymbol('-')) then
      Exit(Fail('Erwartet wird X := X + N bzw. X := X - N', AReason));
    Stop := High(Tokens);
    if Tokens[Stop].IsSymbol(';') then
      Dec(Stop);
    if Stop <= Operator_ then
      Exit(Fail('Erwartet wird X := X + N bzw. X := X - N', AReason));
    // Weitere Plus-/Minus-Operatoren oder Gleitkommazahlen: Inc/Dec wäre nicht gleichwertig.
    Depth := 0;
    for Index := Operator_ + 1 to Stop do
    begin
      if Opens(Tokens[Index]) then
        Inc(Depth)
      else if Closes(Tokens[Index]) then
        Dec(Depth)
      else if (Depth = 0) and (Tokens[Index].IsSymbol('+') or Tokens[Index].IsSymbol('-') or
        Tokens[Index].IsKeyword('or') or Tokens[Index].IsKeyword('xor')) then
        Exit(Fail('/inc wandelt nur einen einzelnen Summanden um', AReason));
      if (Tokens[Index].Kind = TPascalTokenKind.Number) and (LastDelimiter('.eE', Tokens[Index].Text) > 0) and
        not StartsStr('$', Tokens[Index].Text) then
        Exit(Fail('Inc und Dec gelten nur für ganze Zahlen', AReason));
    end;
    Target := Slice(Text, Tokens, 0, Assign - 1);
    Amount := Slice(Text, Tokens, Operator_ + 1, Stop);
    if Amount = '1' then
      Text := IfThen(Increment, 'Inc', 'Dec') + '(' + Target + ');'
    else
      Text := IfThen(Increment, 'Inc', 'Dec') + '(' + Target + ', ' + Amount + ');';
    AEdits := [ReplaceStatement(Source, Last, Text)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /iif }

function ExecuteIif(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
const
  Expected = 'Erwartet wird if B then X := A else X := C;';
var
  Source: TCommandSource;
  Text, Target: string;
  Tokens: TTokens;
  Last, ThenAt, ElseAt, FirstAssign, SecondAssign, Stop, Index: Integer;
begin
  AEdits := nil;
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, AContext.DelphiVersion) then
    Exit(Fail(Format('/iif braucht Bedingungsausdrücke, die es erst ab Delphi 13 gibt (eingestellt: %s)',
      [AContext.DelphiVersion]), AReason));
  Source := TCommandSource.Create(AContext);
  try
    if (Source.RoutineAt = nil) or not StatementBelow(Source, Last, Text) then
      Exit(Fail('Unter /iif steht keine if-Anweisung in einer Routine', AReason));
    Tokens := CodeTokens(Text);
    if (Length(Tokens) < 10) or not Tokens[0].IsKeyword('if') then
      Exit(Fail(Expected, AReason));
    ThenAt := FindTop(Tokens, 1, 'then');
    if ThenAt < 0 then
      Exit(Fail(Expected, AReason));
    FirstAssign := FindTop(Tokens, ThenAt + 1, ':=');
    ElseAt := FindTop(Tokens, ThenAt + 1, 'else');
    if (FirstAssign < 0) or (ElseAt < FirstAssign) then
      Exit(Fail(Expected, AReason));
    SecondAssign := FindTop(Tokens, ElseAt + 1, ':=');
    Stop := High(Tokens);
    if Tokens[Stop].IsSymbol(';') then
      Dec(Stop);
    if (SecondAssign < 0) or (SecondAssign >= Stop) then
      Exit(Fail(Expected, AReason));
    // Beide Zweige weisen demselben Ziel zu und enthalten keine weiteren Anweisungen.
    Target := Slice(Text, Tokens, ThenAt + 1, FirstAssign - 1);
    if not SameText(Target, Slice(Text, Tokens, ElseAt + 1, SecondAssign - 1)) then
      Exit(Fail('/iif braucht in beiden Zweigen dieselbe Zielvariable', AReason));
    for Index := ThenAt + 1 to Stop do
      if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('if') or Tokens[Index].IsSymbol(';') then
        Exit(Fail(Expected, AReason));
    Text := Format('%s := if %s then %s else %s;', [Target, Slice(Text, Tokens, 1, ThenAt - 1),
      Slice(Text, Tokens, FirstAssign + 1, ElseAt - 1), Slice(Text, Tokens, SecondAssign + 1, Stop)]);
    AEdits := [ReplaceStatement(Source, Last, Text)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /multiline }

/// <summary>Bereich des Literals in der Zeile unter dem Befehl.</summary>
function LiteralBelow(ASource: TCommandSource; const AContext: TSlashContext; out ARange: TTextRange): Boolean;
var
  Column: Integer;
begin
  Result := False;
  if ASource.Line + 1 > High(ASource.Lines) then
    Exit;
  Column := Pos('''', ASource.Lines[ASource.Line + 1]);
  if Column = 0 then
    Exit;
  Result := TStringLiterals.LiteralAt(AContext.Text, TTextPosition.Create(ASource.Line + 1, Column - 1), ARange);
end;

function ExecuteMultiline(const AContext: TSlashContext; AToMultiline: Boolean; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Range: TTextRange;
  Expression, Plain, Literal: string;
begin
  AEdits := nil;
  if AToMultiline and not TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AContext.DelphiVersion) then
    Exit(Fail(Format('Mehrzeilige Strings gibt es erst ab Delphi 12 (eingestellt: %s)', [AContext.DelphiVersion]),
      AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not LiteralBelow(Source, AContext, Range) then
      Exit(Fail('Unter dem Befehl steht kein String-Literal', AReason));
    Expression := TStringLiterals.TextOf(AContext.Text, Range);
    if not TStringLiterals.PlainText(Expression, Plain) then
      Exit(Fail('Das Literal enthält mehr als Strings, sLineBreak und +', AReason));
    if StartsStr('''''''', Trim(Expression)) = AToMultiline then
      Exit(Fail(IfThen(AToMultiline, 'Das Literal ist schon mehrzeilig', 'Das Literal ist nicht mehrzeilig'),
        AReason));
    if AToMultiline and (Pos(#10, Plain) = 0) then
      Exit(Fail('Das Literal enthält keinen Zeilenumbruch', AReason));
    Literal := TStringLiterals.ToLiteral(Plain, Source.Indent(Source.Line + 1), False, AToMultiline,
      TStringLiteralBreak.SLineBreak, 0, Source.LineBreak);
    AEdits := [Source.RemoveCommand, TRuleEdit.Create(Range, Literal)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /format }

/// <summary>Platzhalter für AOperand; AArgument ist das Argument, AKnown False bei unbekanntem Typ.</summary>
function Placeholder(ATypes: TDeclaredTypes; const AOperand: string; const APosition: TTextPosition;
  out AArgument: string; out AKnown: Boolean): string;
var
  Inner, TypeName: string;
begin
  AKnown := True;
  AArgument := AOperand;
  Result := '%s';
  // IntToStr(X) und FloatToStr(X) entfallen.
  if StartsText('IntToStr(', AOperand) and EndsStr(')', AOperand) then
  begin
    Inner := Copy(AOperand, Length('IntToStr(') + 1, Length(AOperand) - Length('IntToStr(') - 1);
    if Pos(',', Inner) = 0 then
    begin
      AArgument := Inner;
      Exit('%d');
    end;
  end;
  if StartsText('FloatToStr(', AOperand) and EndsStr(')', AOperand) then
  begin
    Inner := Copy(AOperand, Length('FloatToStr(') + 1, Length(AOperand) - Length('FloatToStr(') - 1);
    if Pos(',', Inner) = 0 then
    begin
      AArgument := Inner;
      Exit('%g');
    end;
  end;
  if IsValidIdent(AOperand) then
  begin
    TypeName := ATypes.DeclaredType(AOperand, APosition);
    if TDeclaredTypes.IsInt32(TypeName) or TDeclaredTypes.IsInt64(TypeName) then
      Exit('%d');
    if TDeclaredTypes.IsFloat(TypeName) then
      Exit('%g');
    if TDeclaredTypes.IsChar(TypeName) or MatchText(TypeName, ['string', 'UnicodeString', 'AnsiString',
      'WideString', 'ShortString', 'UTF8String', 'RawByteString']) then
      Exit('%s');
  end;
  AKnown := False;
end;

function ExecuteFormat(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Types: TDeclaredTypes;
  Line, Mask, Arguments, Operand, Plain, Argument, Unknown: string;
  Tokens: TTokens;
  Hit, First, Last, Index, Depth, Start, Literals, Others: Integer;
  Known: Boolean;
  Position: TTextPosition;

  function Stops(const AToken: TPascalToken): Boolean;
  begin
    Result := AToken.IsSymbol(',') or AToken.IsSymbol(':=') or AToken.IsSymbol(';') or AToken.IsSymbol('=') or
      AToken.IsSymbol('<>') or (AToken.Kind = TPascalTokenKind.Keyword) and not AToken.IsKeyword('nil');
  end;

  procedure AddOperand(AFirst, ALast: Integer);
  begin
    Operand := Slice(Line, Tokens, AFirst, ALast);
    // Nur Zeichenkonstanten: als Literal lesen.
    if TStringLiterals.PlainText(Operand, Plain) or TStringLiterals.PlainText(''''' + ' + Operand, Plain) then
    begin
      Mask := Mask + StringReplace(Plain, '%', '%%', [rfReplaceAll]);
      Inc(Literals);
      Exit;
    end;
    Mask := Mask + Placeholder(Types, Operand, Position, Argument, Known);
    if Arguments <> '' then
      Arguments := Arguments + ', ';
    Arguments := Arguments + Argument;
    if not Known then
      Unknown := Unknown + IfThen(Unknown <> '', ', ', '') + Operand;
    Inc(Others);
  end;

begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  Types := nil;
  try
    if (Source.RoutineAt = nil) or (Source.Line + 1 > High(Source.Lines)) then
      Exit(Fail('/format gilt für eine Verkettung in der Zeile darunter, im Rumpf einer Routine', AReason));
    Line := Source.Lines[Source.Line + 1];
    Tokens := CodeTokens(Line);
    Hit := -1;
    for Index := 0 to High(Tokens) do
      if Tokens[Index].Kind = TPascalTokenKind.StringLiteral then
      begin
        Hit := Index;
        Break;
      end;
    if Hit < 0 then
      Exit(Fail('In der Zeile unter /format steht kein String-Literal', AReason));
    // Ausdruck um das Literal: nach links und rechts bis zu Komma, Zuweisung, Klammer oder Schlüsselwort.
    First := Hit;
    Depth := 0;
    while First > 0 do
    begin
      if Closes(Tokens[First - 1]) then
        Inc(Depth)
      else if Opens(Tokens[First - 1]) then
      begin
        if Depth = 0 then
          Break;
        Dec(Depth);
      end
      else if (Depth = 0) and Stops(Tokens[First - 1]) then
        Break;
      Dec(First);
    end;
    Last := Hit;
    Depth := 0;
    while Last < High(Tokens) do
    begin
      if Opens(Tokens[Last + 1]) then
        Inc(Depth)
      else if Closes(Tokens[Last + 1]) then
      begin
        if Depth = 0 then
          Break;
        Dec(Depth);
      end
      else if (Depth = 0) and Stops(Tokens[Last + 1]) then
        Break;
      Inc(Last);
    end;
    Types := TDeclaredTypes.Create(Source.Tree, Source.Text);
    Position := TTextPosition.Create(Source.Line + 1, Tokens[First].StartPos.Character);
    Mask := '';
    Arguments := '';
    Unknown := '';
    Literals := 0;
    Others := 0;
    // An "+" auf oberster Ebene zerlegen; andere Operatoren dort lassen keine Umwandlung zu.
    Start := First;
    Depth := 0;
    for Index := First to Last do
    begin
      if Opens(Tokens[Index]) then
        Inc(Depth)
      else if Closes(Tokens[Index]) then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsSymbol('+') then
      begin
        if Index = Start then
          Exit(Fail('Unvollständige Verkettung', AReason));
        AddOperand(Start, Index - 1);
        Start := Index + 1;
      end
      else if (Depth = 0) and (Tokens[Index].Kind = TPascalTokenKind.Symbol) and (Tokens[Index].Text <> '.') then
        Exit(Fail('/format wandelt nur Verkettungen mit + um', AReason));
    end;
    if Start > Last then
      Exit(Fail('Unvollständige Verkettung', AReason));
    AddOperand(Start, Last);
    if (Literals = 0) or (Others = 0) then
      Exit(Fail('Unter /format steht keine Verkettung aus Text und Werten', AReason));
    Line := Copy(Line, 1, Tokens[First].Offset) + Format('Format(%s, [%s])', [TStringLiterals.Quote(Mask),
      Arguments]) + Copy(Line, Tokens[Last].Offset + Length(Tokens[Last].Text) + 1, MaxInt);
    if Unknown <> '' then
      Line := Line + Format(' // /format: Typ von %s unbekannt, %%s angenommen', [Unknown]);
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1,
      Length(Source.Lines[Source.Line + 1])), Line)];
    AddUses(Source, AContext, Source.Line, ['System.SysUtils'], AEdits);
    Result := True;
  finally
    Types.Free;
    Source.Free;
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

function ExecuteModern(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Kinds: TModernizations;
  Option, Text: string;
  Lines: TArray<string>;
  Line, Count: Integer;
begin
  AEdits := nil;
  Kinds := [TModernization.ForIn, TModernization.InlineVar, TModernization.FreeAndNilCall];
  for Option in AContext.Arguments.Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if SameText(Option, '-for') then
      Exclude(Kinds, TModernization.ForIn)
    else if SameText(Option, '-inline') then
      Exclude(Kinds, TModernization.InlineVar)
    else if SameText(Option, '-free') then
      Exclude(Kinds, TModernization.FreeAndNilCall)
    else
      Exit(Fail('Erwartet wird /modern [-for] [-inline] [-free]', AReason));
  // for var und Inline-Variablen gibt es erst ab Delphi 10.3.
  if not TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, AContext.DelphiVersion) then
    Kinds := Kinds - [TModernization.ForIn, TModernization.InlineVar];
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/modern gilt nur im Rumpf einer Routine', AReason));
    Lines := nil;
    for Line := Routine.StartPos.Line to Routine.EndPos.Line do
      if Line <> Source.Line then
        Lines := Lines + [Source.Lines[Line]];
    Lines := TModernizer.Apply(Lines, Kinds, Count);
    if Count = 0 then
      Exit(Fail('In dieser Routine gibt es nichts zu modernisieren', AReason));
    Text := '';
    for Line := 0 to High(Lines) do
      Text := Text + Lines[Line] + Source.LineBreak;
    AEdits := [TRuleEdit.Create(TTextRange.Create(Routine.StartPos.Line, 0, Routine.EndPos.Line + 1, 0), Text)];
    if TModernization.FreeAndNilCall in Kinds then
      AddUses(Source, AContext, Routine.StartPos.Line, ['System.SysUtils'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

procedure RegisterExpressionCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('modern', 'Umgebende Routine modernisieren (for-in, Inline-Variablen, FreeAndNil)',
    '/modern -inline', ExecuteModern));
  ARegistry.Register(Command('format', 'String-Verkettung darunter in Format(…) umwandeln', '/format',
    ExecuteFormat));
  ARegistry.Register(Command('multiline', 'Verkettetes Literal darunter als mehrzeiligen String schreiben',
    '/multiline',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteMultiline(AContext, True, AEdits, AReason);
    end));
  ARegistry.Register(Command('multiline!', 'Mehrzeiligen String darunter als Verkettung schreiben', '/multiline!',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteMultiline(AContext, False, AEdits, AReason);
    end));
  ARegistry.Register(Command('iif', 'if/else-Zuweisung darunter als Bedingungsausdruck', '/iif', ExecuteIif));
  ARegistry.Register(Command('inc', 'X := X + N darunter als Inc bzw. Dec', '/inc', ExecuteInc));
end;

end.
