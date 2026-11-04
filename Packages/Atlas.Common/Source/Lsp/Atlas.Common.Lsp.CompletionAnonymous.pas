unit Atlas.Common.Lsp.CompletionAnonymous;

// Anonyme Methoden (#468, ARG-069): Erwartet ein Argument oder eine Zuweisung einen Methodenreferenztyp
// ("reference to procedure/function"), bietet die Vervollständigung ganz oben ein Gerüst mit passender
// Signatur an. Hier die Teile ohne Namensauflösung; TCompletionMethods.AnonymousItem verbindet sie mit dem
// erwarteten Typ.
// - Parse liest die Deklaration aus der Signatur des Index ("TPredicate<T> = reference to function(Arg1: T):
//   Boolean;"); ein Alias ("TKundenFilter = TPredicate<TKunde>;") liefert sein Ziel.
// - Typparameter werden durch die Typargumente des erwarteten Typs ersetzt (TPredicate<TKunde> → Arg1: TKunde).
// - Fehlt die Deklaration im Index, gelten die von System.SysUtils (TProc, TProc<…>, TFunc<…>, TPredicate<T>).
// - Parameter Arg1, Arg2 … der generischen RTL-Typen heißen um (#452): allein Value, sonst nach dem Typ
//   (Kunde) bzw. Value1, Value2; dazu const und das Präfix der Parameter im Projekt. Eigene Namen bleiben.
// - Gerüst: begin/end eine Ebene tiefer als die Zeile, Caret im Rumpf, bei Funktionen "Result := ".

interface

uses
  System.SysUtils;

type
  TMethodRefParam = record
    /// <summary>const, var, out, constref oder ''.</summary>
    Modifier: string;
    Name: string;
    /// <summary>Typ wie geschrieben; '' bei untypisierten Parametern.</summary>
    TypeText: string;
  end;

  TMethodRef = record
    IsFunction: Boolean;
    Params: TArray<TMethodRefParam>;
    ResultType: string;
  end;

  TCompletionAnonymous = class
  public const
    /// <summary>Einrückung je Ebene.</summary>
    IndentUnit = '  ';
    /// <summary>Höchstzahl verfolgter Aliase.</summary>
    MaxAliasDepth = 8;
  public
    /// <summary>Deklaration "Name&lt;T&gt; = reference to …" in AMethodRef, ATypeParams die Typparameter (T). Ist
    /// sie ein Alias, steht sein Ziel in ATarget (ohne ";") und das Ergebnis ist False; ebenso bei anderen
    /// Typen (dann ATarget '').</summary>
    class function Parse(const ASignature: string; out ATypeParams: TArray<string>; out AMethodRef: TMethodRef;
      out ATarget: string): Boolean; static;
    /// <summary>"TFunc&lt;TKunde, Boolean&gt;" → ABase "TFunc", Ergebnis [TKunde, Boolean]; ohne spitze Klammern leer.
    /// </summary>
    class function TypeArgs(const ATypeText: string; out ABase: string): TArray<string>; static;
    /// <summary>Ersetzt ganze Wörter ANames[i] durch AValues[i] (ohne Groß-/Kleinschreibung).</summary>
    class function Substitute(const AText: string; const ANames, AValues: TArray<string>): string; static;
    /// <summary>Deklaration aus System.SysUtils für ABase (ohne oder mit Unit) und AArgCount Typargumente; ''
    /// ohne.</summary>
    class function RtlDeclaration(const ABase: string; AArgCount: Integer): string; static;
    /// <summary>Parameter Arg1, Arg2 … umbenennen (siehe oben); APrefix ist das Parameterpräfix des Projekts.
    /// </summary>
    class function Named(const AMethodRef: TMethodRef; const APrefix: string): TMethodRef; static;
    /// <summary>"procedure", "procedure(const Value: TKunde)", "function(const Value: TKunde): Boolean".</summary>
    class function Header(const AMethodRef: TMethodRef): string; static;
    /// <summary>LSP-Snippet mit #10, eingerückt relativ zur Zeile, $0 im Rumpf.</summary>
    class function Snippet(const AMethodRef: TMethodRef): string; static;
    /// <summary>Klartext mit AIndent (Einrückung der Zeile) und ALineBreak; ohne Platzhalter steht der Cursor
    /// danach hinter end.</summary>
    class function Plain(const AMethodRef: TMethodRef; const AIndent, ALineBreak: string): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.NameSuggestions;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Tokens ohne Kommentare und Direktiven.</summary>
function Significant(const AText: string): TArray<TPascalToken>;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if not IsTrivia(Token) then
    begin
      Result := Result + [Token];
    end;
  end;
end;

/// <summary>Text von ATokens[AFirst] bis vor ATokens[AStop] aus AText (AStop = Length: bis zum Ende).</summary>
function Slice(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, AStop: Integer): string;
var
  StopOffset: Integer;
begin
  if (AFirst < 0) or (AFirst >= AStop) or (AFirst > High(ATokens)) then
  begin
    Exit('');
  end;
  if AStop > High(ATokens) then
  begin
    StopOffset := ATokens[High(ATokens)].Offset + Length(ATokens[High(ATokens)].Text);
  end
  else
  begin
    StopOffset := ATokens[AStop].Offset;
  end;
  Result := Trim(Copy(AText, ATokens[AFirst].Offset + 1, StopOffset - ATokens[AFirst].Offset));
end;

function Opens(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('(') or AToken.IsSymbol('[') or AToken.IsSymbol('<');
end;

function Closes(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(')') or AToken.IsSymbol(']') or AToken.IsSymbol('>');
end;

/// <summary>Index der schließenden Klammer zu ATokens[AOpen]; Length(ATokens) ohne.</summary>
function Matching(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if Opens(ATokens[Result]) then
    begin
      Inc(Depth);
    end
    else if Closes(ATokens[Result]) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
end;

function IsModifier(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('const') or AToken.IsKeyword('var') or
    ((AToken.Kind = TPascalTokenKind.Identifier) and (SameText(AToken.Text, 'out') or
    SameText(AToken.Text, 'constref')));
end;

/// <summary>Parameter zwischen ATokens[AOpen] = "(" und ATokens[AClose] = ")".</summary>
function ParseParams(const AText: string; const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<TMethodRefParam>;
var
  Index, GroupStart, Colon, TypeStop, NameIndex, Depth: Integer;
  Modifier, TypeText: string;
  Param: TMethodRefParam;
begin
  Result := nil;
  GroupStart := AOpen + 1;
  Index := GroupStart;
  Depth := 0;
  while Index <= AClose do
  begin
    if (Index < AClose) and Opens(ATokens[Index]) then
    begin
      Inc(Depth);
    end
    else if (Index < AClose) and Closes(ATokens[Index]) then
    begin
      Dec(Depth);
    end
    else if (Index = AClose) or ((Depth = 0) and ATokens[Index].IsSymbol(';')) then
    begin
      // Eine Gruppe "const A, B: T = Wert".
      NameIndex := GroupStart;
      // Attribute wie [Ref] überspringen.
      while (NameIndex < Index) and ATokens[NameIndex].IsSymbol('[') do
      begin
        NameIndex := Matching(ATokens, NameIndex) + 1;
      end;
      Modifier := '';
      if (NameIndex < Index) and IsModifier(ATokens[NameIndex]) then
      begin
        Modifier := LowerCase(ATokens[NameIndex].Text);
        Inc(NameIndex);
      end;
      Colon := NameIndex;
      while (Colon < Index) and not ATokens[Colon].IsSymbol(':') do
      begin
        Inc(Colon);
      end;
      TypeText := '';
      if Colon < Index then
      begin
        TypeStop := Colon + 1;
        while (TypeStop < Index) and not ATokens[TypeStop].IsSymbol('=') do
        begin
          Inc(TypeStop);
        end;
        TypeText := Slice(AText, ATokens, Colon + 1, TypeStop);
      end;
      while NameIndex < Colon do
      begin
        if ATokens[NameIndex].Kind = TPascalTokenKind.Identifier then
        begin
          Param.Modifier := Modifier;
          Param.Name := ATokens[NameIndex].Text;
          Param.TypeText := TypeText;
          Result := Result + [Param];
        end;
        Inc(NameIndex);
      end;
      GroupStart := Index + 1;
    end;
    Inc(Index);
  end;
end;

{ TCompletionAnonymous }

class function TCompletionAnonymous.Parse(const ASignature: string; out ATypeParams: TArray<string>;
  out AMethodRef: TMethodRef; out ATarget: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Equal, Close, Stop: Integer;
  InConstraint: Boolean;
begin
  Result := False;
  ATypeParams := nil;
  AMethodRef := Default(TMethodRef);
  ATarget := '';
  Tokens := Significant(ASignature);
  // Name und Typparameter bis "=".
  Equal := -1;
  Index := 0;
  while Index <= High(Tokens) do
  begin
    if Tokens[Index].IsSymbol('=') then
    begin
      Equal := Index;
      Break;
    end;
    if Tokens[Index].IsSymbol('<') then
    begin
      Close := Matching(Tokens, Index);
      InConstraint := False;
      while Index < Close do
      begin
        Inc(Index);
        if Tokens[Index].IsSymbol(':') then
        begin
          InConstraint := True;
        end
        else if Tokens[Index].IsSymbol(',') or Tokens[Index].IsSymbol(';') then
        begin
          // "T: class; U": nach ";" beginnt ein neuer Parameter, nach "," nur ohne Constraint.
          if Tokens[Index].IsSymbol(';') then
          begin
            InConstraint := False;
          end;
        end
        else if not InConstraint and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
        begin
          ATypeParams := ATypeParams + [Tokens[Index].Text];
        end;
      end;
    end;
    Inc(Index);
  end;
  if Equal < 0 then
  begin
    Exit;
  end;
  Index := Equal + 1;
  // Ende der Deklaration: ";" oder Textende.
  Stop := Index;
  while (Stop <= High(Tokens)) and not Tokens[Stop].IsSymbol(';') do
  begin
    Inc(Stop);
  end;
  if not ((Index + 1 <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
    SameText(Tokens[Index].Text, 'reference') and Tokens[Index + 1].IsKeyword('to')) then
  begin
    // Alias auf einen benannten Typ; "procedure of object" und andere Typen zählen nicht.
    if (Index <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
    begin
      ATarget := Slice(ASignature, Tokens, Index, Stop);
    end;
    Exit;
  end;
  Inc(Index, 2);
  if Index > High(Tokens) then
  begin
    Exit;
  end;
  if Tokens[Index].IsKeyword('function') then
  begin
    AMethodRef.IsFunction := True;
  end
  else if not Tokens[Index].IsKeyword('procedure') then
  begin
    Exit;
  end;
  Inc(Index);
  if (Index < Stop) and Tokens[Index].IsSymbol('(') then
  begin
    Close := Matching(Tokens, Index);
    if Close > High(Tokens) then
    begin
      Exit;
    end;
    AMethodRef.Params := ParseParams(ASignature, Tokens, Index, Close);
    Index := Close + 1;
  end;
  if AMethodRef.IsFunction then
  begin
    if (Index >= Stop) or not Tokens[Index].IsSymbol(':') then
    begin
      Exit;
    end;
    AMethodRef.ResultType := Slice(ASignature, Tokens, Index + 1, Stop);
    if AMethodRef.ResultType = '' then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TCompletionAnonymous.TypeArgs(const ATypeText: string; out ABase: string): TArray<string>;
var
  Open, Index, Depth, Start: Integer;
  Text: string;
begin
  Result := nil;
  Text := Trim(ATypeText);
  Open := Pos('<', Text);
  if (Open = 0) or not EndsStr('>', Text) then
  begin
    ABase := Text;
    Exit;
  end;
  ABase := Trim(Copy(Text, 1, Open - 1));
  Depth := 0;
  Start := Open + 1;
  for Index := Open + 1 to Length(Text) - 1 do
    case Text[Index] of
      '<', '(', '[':
        Inc(Depth);
      '>', ')', ']':
        Dec(Depth);
      ',':
        if Depth = 0 then
        begin
          Result := Result + [Trim(Copy(Text, Start, Index - Start))];
          Start := Index + 1;
        end;
    end;
  Result := Result + [Trim(Copy(Text, Start, Length(Text) - Start))];
end;

class function TCompletionAnonymous.Substitute(const AText: string; const ANames, AValues: TArray<string>): string;
var
  Index, Start, Name: Integer;
  Word: string;
  Replaced: Boolean;
begin
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin
        Inc(Index);
      end;
      Word := Copy(AText, Start, Index - Start);
      Replaced := False;
      // Nach einem Punkt ist es ein Teil eines qualifizierten Namens, kein Typparameter.
      if (Start = 1) or (AText[Start - 1] <> '.') then
      begin
        for Name := 0 to Min(High(ANames), High(AValues)) do
        begin
          if SameText(Word, ANames[Name]) then
          begin
            Result := Result + AValues[Name];
            Replaced := True;
            Break;
          end;
        end;
      end;
      if not Replaced then
      begin
        Result := Result + Word;
      end;
    end
    else
    begin
      Result := Result + AText[Index];
      Inc(Index);
    end;
  end;
end;

class function TCompletionAnonymous.RtlDeclaration(const ABase: string; AArgCount: Integer): string;
var
  Name, Params, Generic: string;
  Index, Count: Integer;
begin
  Result := '';
  Name := ABase;
  if StartsText('System.SysUtils.', Name) then
  begin
    Name := Copy(Name, Length('System.SysUtils.') + 1, MaxInt);
  end
  else if StartsText('SysUtils.', Name) then
  begin
    Name := Copy(Name, Length('SysUtils.') + 1, MaxInt);
  end;
  if SameText(Name, 'TPredicate') then
  begin
    if AArgCount = 1 then
    begin
      Result := 'TPredicate<T> = reference to function(Arg1: T): Boolean;';
    end;
    Exit;
  end;
  if SameText(Name, 'TProc') then
  begin
    Count := AArgCount;
  end
  else if SameText(Name, 'TFunc') then
  begin
    Count := AArgCount - 1;
  end
  else
  begin
    Exit;
  end;
  if (Count < 0) or (Count > 4) then
  begin
    Exit;
  end;
  Params := '';
  Generic := '';
  for Index := 1 to Count do
  begin
    if Index > 1 then
    begin
      Params := Params + '; ';
      Generic := Generic + ', ';
    end;
    if Count = 1 then
    begin
      Params := Params + 'Arg1: T';
      Generic := Generic + 'T';
    end
    else
    begin
      Params := Params + Format('Arg%d: T%d', [Index, Index]);
      Generic := Generic + Format('T%d', [Index]);
    end;
  end;
  if Params <> '' then
  begin
    Params := '(' + Params + ')';
  end;
  if SameText(Name, 'TProc') then
  begin
    if Generic <> '' then
    begin
      Generic := '<' + Generic + '>';
    end;
    Result := 'TProc' + Generic + ' = reference to procedure' + Params + ';';
  end
  else
  begin
    if Generic <> '' then
    begin
      Generic := Generic + ', ';
    end;
    Result := 'TFunc<' + Generic + 'TResult> = reference to function' + Params + ': TResult;';
  end;
end;

/// <summary>Arg1, Arg2 … (Namen der generischen RTL-Typen).</summary>
function IsArgName(const AName: string): Boolean;
var
  Index: Integer;
begin
  Result := (Length(AName) > 3) and StartsStr('Arg', AName);
  if Result then
  begin
    for Index := 4 to Length(AName) do
    begin
      if not CharInSet(AName[Index], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

/// <summary>Benannter Typ mit Präfix T oder I (TKunde, IFoo): daraus ein Name; sonst ''.</summary>
function TypeBase(const ATypeText: string): string;
var
  Bases: TArray<string>;
  Plain: string;
begin
  Result := '';
  Plain := Copy(ATypeText, LastDelimiter('.', ATypeText) + 1, MaxInt);
  if (Length(Plain) < 2) or not CharInSet(Plain[1], ['T', 'I']) or not CharInSet(Plain[2], ['A'..'Z']) then
  begin
    Exit;
  end;
  Bases := TNameSuggestions.Bases(ATypeText);
  if Length(Bases) > 0 then
  begin
    Result := Bases[0];
  end;
end;

class function TCompletionAnonymous.Named(const AMethodRef: TMethodRef; const APrefix: string): TMethodRef;
var
  Index, Count, Number: Integer;
  Taken: TArray<string>;
  Name: string;
begin
  Result := AMethodRef;
  Count := 0;
  for Index := 0 to High(Result.Params) do
  begin
    if IsArgName(Result.Params[Index].Name) then
    begin
      Inc(Count);
    end;
  end;
  if Count = 0 then
  begin
    Exit;
  end;
  Taken := nil;
  for Index := 0 to High(Result.Params) do
  begin
    if not IsArgName(Result.Params[Index].Name) then
    begin
      Taken := Taken + [Result.Params[Index].Name];
    end;
  end;
  Number := 0;
  for Index := 0 to High(Result.Params) do
  begin
    if not IsArgName(Result.Params[Index].Name) then
    begin
      Continue;
    end;
    Inc(Number);
    if Count = 1 then
    begin
      Name := 'Value';
    end
    else
    begin
      Name := TypeBase(Result.Params[Index].TypeText);
      if Name = '' then
      begin
        Name := 'Value' + IntToStr(Number);
      end;
    end;
    Name := TNameSuggestions.Unique(TNameSuggestions.Prefixed(Name, APrefix), Taken);
    Taken := Taken + [Name];
    Result.Params[Index].Name := Name;
    if Result.Params[Index].Modifier = '' then
    begin
      Result.Params[Index].Modifier := 'const';
    end;
  end;
end;

class function TCompletionAnonymous.Header(const AMethodRef: TMethodRef): string;
var
  Param: TMethodRefParam;
  Parts: TArray<string>;
  Part: string;
begin
  if AMethodRef.IsFunction then
  begin
    Result := 'function';
  end
  else
  begin
    Result := 'procedure';
  end;
  Parts := nil;
  for Param in AMethodRef.Params do
  begin
    Part := Param.Name;
    if Param.Modifier <> '' then
    begin
      Part := Param.Modifier + ' ' + Part;
    end;
    if Param.TypeText <> '' then
    begin
      Part := Part + ': ' + Param.TypeText;
    end;
    Parts := Parts + [Part];
  end;
  if Length(Parts) > 0 then
  begin
    Result := Result + '(' + string.Join('; ', Parts) + ')';
  end;
  if AMethodRef.IsFunction then
  begin
    Result := Result + ': ' + AMethodRef.ResultType;
  end;
end;

/// <summary>Zeichen, die in einem LSP-Snippet eine Bedeutung haben, maskieren.</summary>
function EscapeSnippet(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '$', '\$', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '\}', [rfReplaceAll]);
end;

class function TCompletionAnonymous.Snippet(const AMethodRef: TMethodRef): string;
var
  Body: string;
begin
  Body := '$0';
  if AMethodRef.IsFunction then
  begin
    Body := 'Result := $0';
  end;
  Result := EscapeSnippet(Header(AMethodRef)) + #10 + IndentUnit + 'begin' + #10 + IndentUnit + IndentUnit + Body +
    #10 + IndentUnit + 'end';
end;

class function TCompletionAnonymous.Plain(const AMethodRef: TMethodRef; const AIndent, ALineBreak: string): string;
var
  Body: string;
begin
  // Leere Rumpfzeile ohne Einrückung: sonst bliebe Leerraum am Zeilenende stehen.
  Body := '';
  if AMethodRef.IsFunction then
  begin
    Body := AIndent + IndentUnit + IndentUnit + 'Result := ';
  end;
  Result := Header(AMethodRef) + ALineBreak + AIndent + IndentUnit + 'begin' + ALineBreak + Body + ALineBreak +
    AIndent + IndentUnit + 'end';
end;

end.
