unit Atlas.Common.Editing.CreateMethod;

// Methode aus Aufruf anlegen (#472, ARG-073), Teil ohne Namensauflösung:
//   - Site: Aufruf eines Namens am Cursor (auf dem Namen oder direkt hinter
//     seiner "("), mit Qualifizierer, Argumenten und Umgebung: eigene
//     Anweisung (Prozedur), rechte Seite einer Zuweisung, Bedingung (Boolean)
//     oder sonst ein Ausdruck. Fehlt die ")" noch (Auslöser "("), zählen die
//     Argumente bis zum Ende der Zeile bzw. Anweisung.
//   - Parameternamen aus den Argumenten: Variablen ohne F-, A- bzw. L-Präfix,
//     Aufrufe ohne Get, Literale nach ihrem Wert (0.1 → Rate) bzw. Typ (#452).
//   - Literaltypen: Gleitkomma Double, ganze Zahl Integer, String string.
//   - Kopf, Deklaration in der Klasse und Rumpf bzw. freie Routine davor.
// Typen der übrigen Argumente, Rückgabetyp und Zielklasse bringt
// Atlas.Common.Lsp.Refactorings über die Namensauflösung mit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Umgebung eines Aufrufs.</summary>
  TCallContext = (
    /// <summary>Eigene Anweisung: Prozedur.</summary>
    Statement,
    /// <summary>Ganze rechte Seite einer Zuweisung: Funktion mit dem Typ des Ziels.</summary>
    Assignment,
    /// <summary>Bedingung nach if, while, until, not, and, or: Funktion mit Boolean.</summary>
    Condition,
    /// <summary>Sonst in einem Ausdruck: Funktion mit dem erwarteten Typ.</summary>
    Expression);
  {$SCOPEDENUMS OFF}

  TCallArgument = record
    /// <summary>Erstes und letztes Token des Arguments.</summary>
    First: Integer;
    Last: Integer;
    Text: string;
  end;

  TCreateCallSite = record
    Name: string;
    NameIndex: Integer;
    NameRange: TTextRange;
    /// <summary>Kette vor dem Punkt ("Kunde", "Self.Liste"); '' ohne.</summary>
    Qualifier: string;
    /// <summary>Erstes Token des Aufrufs (Qualifizierer bzw. Name).</summary>
    CallStart: Integer;
    OpenIndex: Integer;
    /// <summary>Token der schließenden Klammer; -1, wenn sie noch fehlt.</summary>
    CloseIndex: Integer;
    Arguments: TArray<TCallArgument>;
    Context: TCallContext;
    /// <summary>Ziel der Zuweisung bei Context = Assignment, sonst ''.</summary>
    Target: string;
    /// <summary>Erstes Token der Anweisung, in der der Aufruf steht (für Probetexte).</summary>
    StatementStart: Integer;
  end;

  TCreateParameter = record
    Name: string;
    TypeName: string;
    IsConst: Boolean;
  end;

  /// <summary>Was entstehen soll.</summary>
  TCreateMethodPlan = record
    Name: string;
    Parameters: TArray<TCreateParameter>;
    /// <summary>Rückgabetyp; '' = Prozedur.</summary>
    ResultType: string;
    /// <summary>Klasse der Methode (auch TAussen.TInnen); '' = freie Routine vor ARoutine.</summary>
    TypeName: string;
    /// <summary>Abschnitt der Deklaration: private, protected oder public.</summary>
    Section: string;
    /// <summary>Klassenmethode (Aufruf aus einer Klassenmethode heraus).</summary>
    IsClassMethod: Boolean;
    /// <summary>"$0" in die leere Zeile des Rumpfs (Cursor dort nach dem Anlegen).</summary>
    CaretInBody: Boolean;
    Style: TFormatStyle;
  end;

  TCreateMethod = class
  public const
    /// <summary>Rückgabetyp, wenn er sich nicht ableiten lässt; als Kommentar meldet ihn der Compiler.</summary>
    TypePlaceholder = '{Typ}';
  public
    /// <summary>Aufruf am Cursor: auf seinem Namen oder direkt hinter "Name(". False sonst, auch bei
    /// Deklarationen und Qualifizierern mit Klammern oder Indizes.</summary>
    class function Site(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
      out ASite: TCreateCallSite): Boolean; static;
    /// <summary>Typ eines Arguments, das nur ein Literal ist; '' sonst.</summary>
    class function LiteralType(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string; static;
    /// <summary>Name aus dem Argument; '' wenn es keinen hergibt (dann aus dem Typ).</summary>
    class function ArgumentName(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string; static;
    /// <summary>Name aus dem Typ (#452): ohne T- bzw. I-Präfix und Typargumente; Value, wenn nichts bleibt.</summary>
    class function NameFromType(const ATypeName: string): string; static;
    /// <summary>const für Strings, Records und Interfaces.</summary>
    class function WantsConst(const ATypeName: string; AIsRecord, AIsInterface: Boolean): Boolean; static;
    /// <summary>ANames eindeutig gemacht (Value, Value2 …), ohne Groß-/Kleinschreibung.</summary>
    class function UniqueNames(const ANames: TArray<string>): TArray<string>; static;
    /// <summary>"(Customer: TCustomer; Rate: Double)"; '' ohne Parameter.</summary>
    class function ParameterList(const AParameters: TArray<TCreateParameter>): string; static;
    /// <summary>Kopf ohne ";": "function CalcDiscount(…): Currency", mit AQualified "function TFoo.CalcDiscount…".
    /// </summary>
    class function Header(const APlan: TCreateMethodPlan; AQualified: Boolean): string; static;
    /// <summary>Deklaration und Rumpf für eine Methode von APlan.TypeName in AText; False, wenn die Klasse dort
    /// nicht passend steht.</summary>
    class function MethodEdits(const AText: string; ATree: TSyntaxTree; const APlan: TCreateMethodPlan;
      out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Freie Routine vor ARoutine (samt Kommentaren darüber).</summary>
    class function RoutineEdit(const AText: string; ARoutine: TSyntaxNode; const APlan: TCreateMethodPlan): TTextEdit;
      static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ClassCompletion;

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

function IsKeywordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  Word: string;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Keyword then
  begin
    Exit;
  end;
  for Word in AWords do
  begin
    if AToken.IsKeyword(Word) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Vor diesem Token beginnt eine Anweisung.</summary>
function StartsStatementAfter(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['begin', 'then', 'do', 'else', 'repeat', 'try',
    'finally', 'except', 'initialization', 'finalization']);
end;

/// <summary>Mit diesem Token endet eine Anweisung.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, ['end', 'else', 'until', 'except', 'finally']);
end;

function TokensText(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := AFirst to ALast do
  begin
    if not (ATokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      if (Result <> '') and (ATokens[Index].Offset > ATokens[Index - 1].Offset + Length(ATokens[Index - 1].Text)) then
      begin
        Result := Result + ' ';
      end;
      Result := Result + ATokens[Index].Text;
    end;
  end;
end;

function StripPrefix(const AName, APrefix: string): string;
begin
  Result := AName;
  if (Length(AName) > Length(APrefix)) and StartsText(APrefix, AName) and
    CharInSet(AName[Length(APrefix) + 1], ['A'..'Z']) then
  begin
    Result := Copy(AName, Length(APrefix) + 1, MaxInt);
  end;
end;

{ TCreateMethod }

class function TCreateMethod.Site(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition;
  out ASite: TCreateCallSite): Boolean;
var
  Index, Before, Scan, Depth, ArgStart, Target, Prior, Pass: Integer;
  Argument: TCallArgument;
  Stop: Boolean;
begin
  ASite := Default(TCreateCallSite);
  ASite.CloseIndex := -1;
  Result := False;
  // Letztes Token, das vor dem Cursor beginnt.
  Index := -1;
  for Scan := 0 to High(ATokens) do
  begin
    if Compare(ATokens[Scan].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    if not (ATokens[Scan].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Index := Scan;
    end;
  end;
  if Index < 0 then
  begin
    Exit;
  end;
  if ATokens[Index].IsSymbol('(') and (Compare(ATokens[Index].EndPos, APosition) = 0) then
  begin
    Index := TRoutineBody.PreviousToken(ATokens, Index);
  end
  else if Compare(ATokens[Index].EndPos, APosition) < 0 then
  begin
    Exit;
  end;
  if (Index < 0) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  ASite.NameIndex := Index;
  ASite.Name := ATokens[Index].Text;
  ASite.NameRange := TTextRange.Create(ATokens[Index].StartPos, ATokens[Index].EndPos);
  ASite.OpenIndex := TRoutineBody.NextToken(ATokens, Index);
  if (ASite.OpenIndex > High(ATokens)) or not ATokens[ASite.OpenIndex].IsSymbol('(') then
  begin
    Exit;
  end;
  // Qualifizierer: nur Bezeichner mit Punkten.
  ASite.CallStart := Index;
  Before := TRoutineBody.PreviousToken(ATokens, Index);
  while (Before >= 1) and ATokens[Before].IsSymbol('.') do
  begin
    Scan := TRoutineBody.PreviousToken(ATokens, Before);
    if (Scan < 0) or (ATokens[Scan].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    ASite.CallStart := Scan;
    Before := TRoutineBody.PreviousToken(ATokens, Scan);
  end;
  if ASite.CallStart < Index then
  begin
    ASite.Qualifier := TokensText(ATokens, ASite.CallStart, TRoutineBody.PreviousToken(ATokens, Index) - 1);
  end;
  // Keine Deklaration: kein procedure, function, constructor, destructor oder property davor.
  if (Before >= 0) and IsKeywordIn(ATokens[Before], ['procedure', 'function', 'constructor', 'destructor',
    'property', 'operator']) then
  begin
    Exit;
  end;
  // Argumente bis zur passenden ")". Fehlt sie (gerade getippt), zählt nur der Rest der Zeile: Die nächste Zeile
  // ist dann meist schon die nächste Anweisung.
  for Pass := 0 to 1 do
  begin
    ASite.Arguments := nil;
    Depth := 0;
    Scan := TRoutineBody.NextToken(ATokens, ASite.OpenIndex);
    ArgStart := Scan;
    while Scan <= High(ATokens) + 1 do
    begin
      Stop := (Scan > High(ATokens)) or ((Pass = 1) and
        (ATokens[Scan].StartPos.Line > ATokens[ASite.OpenIndex].StartPos.Line));
      if not Stop and (ATokens[Scan].IsSymbol('(') or ATokens[Scan].IsSymbol('[')) then
      begin
        Inc(Depth);
      end
      else if not Stop and (ATokens[Scan].IsSymbol(')') or ATokens[Scan].IsSymbol(']')) and (Depth > 0) then
      begin
        Dec(Depth);
      end
      else if Stop or ((Depth = 0) and (ATokens[Scan].IsSymbol(',') or ATokens[Scan].IsSymbol(')') or
        EndsStatement(ATokens[Scan]) or IsKeywordIn(ATokens[Scan], ['then', 'do', 'of', 'begin', 'to', 'downto']))) then
      begin
        if ArgStart < Scan then
        begin
          Argument.First := ArgStart;
          Argument.Last := TRoutineBody.PreviousToken(ATokens, Scan);
          Argument.Text := TokensText(ATokens, Argument.First, Argument.Last);
          ASite.Arguments := ASite.Arguments + [Argument];
        end;
        if not Stop and ATokens[Scan].IsSymbol(')') then
        begin
          ASite.CloseIndex := Scan;
          Break;
        end;
        if Stop or not ATokens[Scan].IsSymbol(',') then
        begin
          Break;
        end;
        ArgStart := TRoutineBody.NextToken(ATokens, Scan);
      end;
      Scan := TRoutineBody.NextToken(ATokens, Scan);
    end;
    if ASite.CloseIndex >= 0 then
    begin
      Break;
    end;
  end;
  // Umgebung aus dem Token vor dem Aufruf und dem nach der Klammer.
  Scan := Length(ATokens);
  if ASite.CloseIndex >= 0 then
  begin
    Scan := TRoutineBody.NextToken(ATokens, ASite.CloseIndex);
  end;
  ASite.Context := TCallContext.Expression;
  if (Before >= 0) and ATokens[Before].IsSymbol(':=') then
  begin
    if (ASite.CloseIndex < 0) or (Scan > High(ATokens)) or EndsStatement(ATokens[Scan]) then
    begin
      ASite.Context := TCallContext.Assignment;
      Target := TRoutineBody.PreviousToken(ATokens, Before);
      Prior := TRoutineBody.PreviousToken(ATokens, Target);
      while (Prior >= 0) and not StartsStatementAfter(ATokens[Prior]) do
      begin
        Target := Prior;
        Prior := TRoutineBody.PreviousToken(ATokens, Target);
      end;
      if Target >= 0 then
      begin
        ASite.Target := TokensText(ATokens, Target, TRoutineBody.PreviousToken(ATokens, Before));
      end;
    end;
  end
  else if (Before >= 0) and IsKeywordIn(ATokens[Before], ['if', 'while', 'until', 'not', 'and', 'or']) then
  begin
    ASite.Context := TCallContext.Condition;
  end
  else if ((Before < 0) or StartsStatementAfter(ATokens[Before])) and
    ((ASite.CloseIndex < 0) or (Scan > High(ATokens)) or EndsStatement(ATokens[Scan])) then
  begin
    ASite.Context := TCallContext.Statement;
  end;
  // Anfang der Anweisung: zurück bis zu ";" oder begin auf Klammertiefe 0.
  Scan := ASite.CallStart;
  Depth := 0;
  while True do
  begin
    Before := TRoutineBody.PreviousToken(ATokens, Scan);
    if Before < 0 then
    begin
      Break;
    end;
    if ATokens[Before].IsSymbol(')') or ATokens[Before].IsSymbol(']') then
    begin
      Inc(Depth);
    end
    else if (ATokens[Before].IsSymbol('(') or ATokens[Before].IsSymbol('[')) and (Depth > 0) then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and (StartsStatementAfter(ATokens[Before]) or IsKeywordIn(ATokens[Before], ['if', 'while',
      'until', 'case', 'for', 'with'])) then
    begin
      if IsKeywordIn(ATokens[Before], ['if', 'while', 'until', 'case', 'for', 'with']) then
      begin
        Scan := Before;
      end;
      Break;
    end;
    Scan := Before;
  end;
  ASite.StatementStart := Scan;
  Result := True;
end;

class function TCreateMethod.LiteralType(const ATokens: TArray<TPascalToken>; const AArgument: TCallArgument): string;
var
  Token: TPascalToken;
  First: Integer;
begin
  Result := '';
  First := AArgument.First;
  // Vorzeichen gehört zur Zahl.
  if (First < AArgument.Last) and (ATokens[First].IsSymbol('-') or ATokens[First].IsSymbol('+')) then
  begin
    First := TRoutineBody.NextToken(ATokens, First);
  end;
  if First <> AArgument.Last then
  begin
    Exit;
  end;
  Token := ATokens[First];
  case Token.Kind of
    TPascalTokenKind.Number:
      if (Token.Text[1] <> '$') and (Token.Text[1] <> '%') and
        ((Pos('.', Token.Text) > 0) or (Pos('e', LowerCase(Token.Text)) > 0)) then
      begin
        Result := 'Double';
      end
      else
      begin
        Result := 'Integer';
      end;
    TPascalTokenKind.StringLiteral:
      Result := 'string';
    TPascalTokenKind.CharLiteral:
      Result := 'Char';
    TPascalTokenKind.Identifier:
      if SameText(Token.Text, 'True') or SameText(Token.Text, 'False') then
      begin
        Result := 'Boolean';
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TCreateMethod.ArgumentName(const ATokens: TArray<TPascalToken>;
  const AArgument: TCallArgument): string;
var
  First, Last, Index, Depth: Integer;
  Value: Double;
  Settings: TFormatSettings;
  Literal: string;
begin
  Result := '';
  First := AArgument.First;
  Last := AArgument.Last;
  Literal := LiteralType(ATokens, AArgument);
  if Literal <> '' then
  begin
    if Literal = 'Double' then
    begin
      Settings := TFormatSettings.Invariant;
      // Anteil zwischen 0 und 1: ein Satz (0.1 → Rate).
      if TryStrToFloat(ATokens[Last].Text, Value, Settings) and (Value > 0) and (Value < 1) and
        not ATokens[First].IsSymbol('-') then
      begin
        Exit('Rate');
      end;
    end;
    Exit(NameFromType(Literal));
  end;
  if ATokens[First].IsSymbol('@') then
  begin
    First := TRoutineBody.NextToken(ATokens, First);
  end;
  if First > Last then
  begin
    Exit;
  end;
  // Aufruf oder Typumwandlung: Name vor der äußeren Klammer am Ende.
  if ATokens[Last].IsSymbol(')') then
  begin
    Depth := 0;
    Index := Last;
    while Index >= First do
    begin
      if ATokens[Index].IsSymbol(')') then
      begin
        Inc(Depth);
      end
      else if ATokens[Index].IsSymbol('(') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Break;
        end;
      end;
      Dec(Index);
    end;
    Last := TRoutineBody.PreviousToken(ATokens, Index);
    if (Last < First) or (ATokens[Last].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    // Typumwandlung TKunde(X): Name aus dem Typ.
    if (Last = First) and (Length(ATokens[Last].Text) > 1) and CharInSet(ATokens[Last].Text[1], ['T']) and
      CharInSet(ATokens[Last].Text[2], ['A'..'Z']) then
    begin
      Exit(NameFromType(ATokens[Last].Text));
    end;
    Exit(StripPrefix(ATokens[Last].Text, 'Get'));
  end;
  // Kette A.B.C: letzter Bezeichner.
  for Index := First to Last do
  begin
    if not ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.') or
      ATokens[Index].IsSymbol('^')) then
    begin
      Exit;
    end;
  end;
  if ATokens[Last].IsSymbol('^') then
  begin
    Last := TRoutineBody.PreviousToken(ATokens, Last);
  end;
  if (Last < First) or (ATokens[Last].Kind <> TPascalTokenKind.Identifier) or SameText(ATokens[Last].Text, 'Self') or
    SameText(ATokens[Last].Text, 'nil') or SameText(ATokens[Last].Text, 'Result') then
  begin
    Exit;
  end;
  Result := StripPrefix(ATokens[Last].Text, 'Get');
  if First = Last then
  begin
    Result := StripPrefix(Result, 'F');
    Result := StripPrefix(Result, 'A');
    Result := StripPrefix(Result, 'L');
  end;
end;

class function TCreateMethod.NameFromType(const ATypeName: string): string;
begin
  Result := ATypeName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  Result := Result.Substring(Result.LastIndexOf('.') + 1);
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 'I']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if MatchText(Result, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString', 'UTF8String',
    'ShortString']) then
  begin
    Result := 'Text';
  end
  else if MatchText(Result, ['Char', 'WideChar', 'AnsiChar']) then
  begin
    Result := 'Ch';
  end
  else if SameText(Result, 'Boolean') then
  begin
    Result := 'Flag';
  end
  else if MatchText(Result, ['Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord', 'Double', 'Single', 'Extended', 'Real', 'Currency', 'Comp',
    'Variant', 'Pointer', '']) or StartsStr('{', Result) then
  begin
    Result := 'Value';
  end;
end;

class function TCreateMethod.WantsConst(const ATypeName: string; AIsRecord, AIsInterface: Boolean): Boolean;
begin
  Result := AIsRecord or AIsInterface or MatchText(ATypeName, ['string', 'UnicodeString', 'AnsiString',
    'WideString', 'RawByteString', 'UTF8String', 'ShortString']);
end;

class function TCreateMethod.UniqueNames(const ANames: TArray<string>): TArray<string>;
var
  Index, Other, Number: Integer;
  Taken: Boolean;
begin
  SetLength(Result, Length(ANames));
  for Index := 0 to High(ANames) do
  begin
    Result[Index] := ANames[Index];
    Number := 1;
    repeat
      Taken := False;
      for Other := 0 to Index - 1 do
      begin
        if SameText(Result[Other], Result[Index]) then
        begin
          Taken := True;
        end;
      end;
      if Taken then
      begin
        Inc(Number);
        Result[Index] := ANames[Index] + IntToStr(Number);
      end;
    until not Taken;
  end;
end;

class function TCreateMethod.ParameterList(const AParameters: TArray<TCreateParameter>): string;
var
  Index: Integer;
begin
  Result := '';
  if AParameters = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(AParameters) do
  begin
    if Index > 0 then
    begin
      Result := Result + '; ';
    end;
    if AParameters[Index].IsConst then
    begin
      Result := Result + 'const ';
    end;
    Result := Result + AParameters[Index].Name + ': ' + AParameters[Index].TypeName;
  end;
  Result := '(' + Result + ')';
end;

class function TCreateMethod.Header(const APlan: TCreateMethodPlan; AQualified: Boolean): string;
begin
  if APlan.ResultType = '' then
  begin
    Result := 'procedure ';
  end
  else
  begin
    Result := 'function ';
  end;
  if APlan.IsClassMethod then
  begin
    Result := 'class ' + Result;
  end;
  if AQualified and (APlan.TypeName <> '') then
  begin
    Result := Result + APlan.TypeName + '.';
  end;
  Result := Result + APlan.Name + ParameterList(APlan.Parameters);
  if APlan.ResultType <> '' then
  begin
    Result := Result + ': ' + APlan.ResultType;
  end;
end;

function BodyText(const APlan: TCreateMethodPlan; const ALineBreak: string): string;
var
  Inner: string;
begin
  Inner := '';
  if APlan.CaretInBody then
  begin
    Inner := TRoutineBody.IndentUnit(APlan.Style) + '$0';
  end;
  Result := TCreateMethod.Header(APlan, True) + ';' + ALineBreak + 'begin' + ALineBreak + Inner + ALineBreak + 'end;';
end;

class function TCreateMethod.MethodEdits(const AText: string; ATree: TSyntaxTree; const APlan: TCreateMethodPlan;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Body: TSyntaxNode;
  Edit: TTextEdit;
  Section: string;
begin
  AEdits := nil;
  Result := False;
  Body := TRoutineBody.TypeBody(ATree.Root, APlan.TypeName.Substring(APlan.TypeName.LastIndexOf('.') + 1));
  if Body = nil then
  begin
    Exit;
  end;
  Section := APlan.Section;
  if Section = '' then
  begin
    Section := 'private';
  end;
  if not TRoutineBody.MemberDeclaration(AText, ATree, Body,
    TMemberEntry.Create(Section, TCreateMethod.Header(APlan, False) + ';'), APlan.Style, Edit) then
  begin
    Exit;
  end;
  AEdits := [Edit];
  if not TClassCompletion.BodyEdit(ATree, AText, APlan.TypeName, BodyText(APlan, TTextLines.LineBreakOf(AText)),
    Edit) then
  begin
    Exit;
  end;
  AEdits := AEdits + [Edit];
  Result := True;
end;

class function TCreateMethod.RoutineEdit(const AText: string; ARoutine: TSyntaxNode;
  const APlan: TCreateMethodPlan): TTextEdit;
var
  Line: Integer;
  LineBreak: string;
  Position: TTextPosition;
begin
  LineBreak := TTextLines.LineBreakOf(AText);
  Line := TRoutineBody.RoutineInsertLine(AText, ARoutine);
  Position := TTextPosition.Create(Line, 0);
  Result := TTextEdit.Create(TTextRange.Create(Position, Position), BodyText(APlan, LineBreak) + LineBreak +
    LineBreak);
end;

end.
