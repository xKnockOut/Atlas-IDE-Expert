unit Atlas.Common.Editing.ChangeSignature;

// Textbausteine für „Signatur ändern“ (#100) ohne Index und Protokoll:
//   - Kopf einer Routine aus den Token lesen: Schlüsselwort, Name, Parameter
//     (Modifizierer, Name, Typ, Standardwert), Ergebnistyp, Direktiven,
//   - neue Parameterliste für Deklaration (mit den vorhandenen Standardwerten)
//     und Rumpf (ohne) aus der Liste der Änderungen bilden,
//   - Argumente eines Aufrufs umstellen, ergänzen oder entfernen,
//   - Verwendungen eines Parameters im Rumpf finden und umbenennen,
//   - die alte Signatur als Überladung, die an die neue weiterreicht.
// Neue Parameter bekommen nie einen Standardwert; vorhandene bleiben, wo sie
// stehen. Was zur Routine gehört (Vorfahren, Nachfahren, Interfaces,
// Aufrufer), sammelt Atlas.Common.Lsp.ChangeSignature.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TSignatureParameter = record
    /// <summary>const, var, out, constref, auch mit Attribut wie "[ref] const"; '' ohne.</summary>
    Modifier: string;
    Name: string;
    /// <summary>'' bei untypisierten Parametern (var Buffer).</summary>
    TypeName: string;
    /// <summary>Standardwert als Quelltext; '' ohne.</summary>
    DefaultValue: string;
    /// <summary>Gruppe in der alten Liste (A, B: Integer ist eine Gruppe); -1 bei neuen Parametern. Nur
    /// Parameter derselben Gruppe werden wieder zusammengefasst.</summary>
    Group: Integer;
    /// <summary>Wie in der Deklaration: "const A: Integer = 0"; AWithDefault False ohne Standardwert.</summary>
    function Text(AWithDefault: Boolean): string;
  end;

  /// <summary>Kopf einer Routine; Token-Indizes in der Tokenliste der Datei, -1 = fehlt.</summary>
  TSignatureHeader = record
    /// <summary>Erstes Token: class bzw. procedure, function, constructor, destructor.</summary>
    StartToken: Integer;
    NameToken: Integer;
    OpenToken: Integer;
    CloseToken: Integer;
    /// <summary>";" hinter Parametern und Ergebnistyp.</summary>
    EndToken: Integer;
    /// <summary>";" hinter der letzten Direktive (= EndToken ohne Direktiven).</summary>
    LastToken: Integer;
    /// <summary>procedure, function, constructor oder destructor in Kleinschreibung.</summary>
    Keyword: string;
    IsClass: Boolean;
    /// <summary>Name wie im Kopf, beim Rumpf mit Typ (TFoo.Bar).</summary>
    QualifiedName: string;
    ResultType: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Direktiven in Kleinschreibung samt Argument ("message wm_paint").</summary>
    Directives: TArray<string>;
    function IsFunction: Boolean;
    function HasDirective(const ADirective: string): Boolean;
    /// <summary>Typen der Parameter in Reihenfolge.</summary>
    function ParamTypes: TArray<string>;
  end;

  /// <summary>Ein Parameter der neuen Signatur.</summary>
  TParameterChange = record
    /// <summary>Stelle in der alten Liste; -1 = neuer Parameter.</summary>
    Origin: Integer;
    Name: string;
    /// <summary>Nur bei neuen Parametern; vorhandene behalten Typ und Modifizierer.</summary>
    TypeName: string;
    Modifier: string;
    /// <summary>Neue Parameter: Wert, den bisherige Aufrufer übergeben.</summary>
    Value: string;
    class function Kept(AOrigin: Integer; const AName: string): TParameterChange; static;
    class function Added(const AName, ATypeName, AModifier, AValue: string): TParameterChange; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Wie ein Verweis auf die Routine verwendet wird.</summary>
  TSignatureUse = (Call, Pointer_, Accessor);
  {$SCOPEDENUMS OFF}

  TChangeSignature = class
  public
    /// <summary>Parameter aus dem Text zwischen den Klammern.</summary>
    class function ParseParameters(const AText: string): TArray<TSignatureParameter>; static;
    /// <summary>Index des Bezeichners an APosition; -1 ohne.</summary>
    class function NameTokenAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer; static;
    /// <summary>Kopf zur Routine, deren Name bei ANameToken steht; False, wenn dort keine beginnt.</summary>
    class function ReadHeader(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      out AHeader: TSignatureHeader): Boolean; static;
    /// <summary>Kopf eines prozeduralen Typs (TFooEvent = procedure(...) of object); ANameToken ist der Typname.</summary>
    class function ReadProcedureType(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      out AHeader: TSignatureHeader): Boolean; static;
    /// <summary>Fehlertext oder '': Neue Parameter brauchen Namen, Typ und Wert; Namen eindeutig; kein neuer
    /// Parameter hinter einem mit Standardwert; jede alte Stelle höchstens einmal.</summary>
    class function Validate(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>): string;
      static;
    /// <summary>Parameter der neuen Signatur zu AOld (den Parametern dieses Kopfes). Umbenannt wird nur, wo
    /// der neue Name vom Namen in ARootNames abweicht; sonst bleibt der eigene Name.</summary>
    class function NewParameters(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
      const ARootNames: TArray<string>; AWithDefaults: Boolean): TArray<TSignatureParameter>; static;
    /// <summary>"(A: Integer; const B: string)" bzw. '' ohne Parameter; Parameter, die schon vorher
    /// zusammenstanden (A, B: Integer), bleiben zusammen.</summary>
    class function ParameterList(const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string;
      static;
    /// <summary>Ersetzt die Klammern samt Inhalt (oder fügt sie hinter dem Namen ein).</summary>
    class function HeaderEdit(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader;
      const AList: string): TTextEdit; static;
    /// <summary>Art der Verwendung des Bezeichners ANameToken. AHasRequired: Die alte Signatur hat Parameter
    /// ohne Standardwert (ohne Klammern ist es dann kein Aufruf).</summary>
    class function UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer; AHasRequired: Boolean): TSignatureUse;
      static;
    /// <summary>Neue Argumente eines Aufrufs. AOld: alte Parameter (für Standardwerte ausgelassener Argumente);
    /// AValues: Wert je neuem Parameter (Index wie AChanges, '' = Value der Änderung). False, wenn sich
    /// nichts ändert.</summary>
    class function CallEdit(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
      const AValues: TArray<string>; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Verwendungen des Namens AName (ohne Punkt davor) in Token AFirst bis ALast.</summary>
    class function Uses_(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const AName: string): TArray<Integer>; static;
    /// <summary>Letztes Token der Routine (";" hinter end), deren Kopf bei AHeader steht; -1 ohne Rumpf.</summary>
    class function BodyEnd(ATree: TSyntaxTree; const AHeader: TSignatureHeader): Integer; static;
    /// <summary>Kopf als Text mit neuer Parameterliste, ohne Direktiven, mit ";".</summary>
    class function HeaderText(const AHeader: TSignatureHeader; const AQualifiedName: string;
      const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string; static;
    /// <summary>Aufruf der neuen Signatur aus der alten Überladung: alte Parameter nach Namen, neue mit Value.
    /// Mit "Result := " bei Funktionen.</summary>
    class function ForwardCall(const AHeader: TSignatureHeader; const AOld: TArray<TSignatureParameter>;
      const AChanges: TArray<TParameterChange>): string; static;
    /// <summary>Direktiven, die die alte Überladung übernimmt (Aufrufkonvention, static, inline …), je mit
    /// " name;"; virtual nur mit AVirtual.</summary>
    class function OverloadDirectives(const AHeader: TSignatureHeader; AVirtual: Boolean): string; static;
    /// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
    class function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Lexer,
  Atlas.Text.Lines;

const
  RoutineWords: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  ModifierWords: array[0..3] of string = ('const', 'var', 'out', 'constref');
  DirectiveWords: array[0..26] of string = ('overload', 'override', 'virtual', 'dynamic', 'abstract', 'reintroduce',
    'static', 'inline', 'final', 'cdecl', 'stdcall', 'register', 'pascal', 'safecall', 'winapi', 'message',
    'deprecated', 'platform', 'library', 'experimental', 'assembler', 'forward', 'external', 'varargs', 'dispid',
    'unsafe', 'export');
  // Diese Direktiven gehören zur virtuellen Kette bzw. zur Deklaration und gehen nicht auf die alte Überladung über.
  ChainWords: array[0..7] of string = ('overload', 'override', 'virtual', 'dynamic', 'abstract', 'reintroduce',
    'message', 'final');

function IsWord(const AToken: TPascalToken; const AWords: array of string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (IndexText(AToken.Text, AWords) >= 0);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function IsSymbolAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; const ASymbol: string): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(ATokens)) and ATokens[AIndex].IsSymbol(ASymbol);
end;

/// <summary>Passende schließende Klammer zu AOpen ("(" oder "[" oder "&lt;"); -1 ohne.</summary>
function Matching(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  Depth: Integer;
  Opening, Closing: string;
begin
  Opening := ATokens[AOpen].Text;
  if Opening = '(' then
  begin
    Closing := ')';
  end
  else if Opening = '[' then
  begin
    Closing := ']';
  end
  else
  begin
    Closing := '>';
  end;
  Depth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(Opening) then
    begin
      Inc(Depth);
    end
    else if ATokens[Result].IsSymbol(Closing) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Exit;
      end;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Text von Token AFirst bis einschließlich ALast.</summary>
function SliceText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
begin
  if (AFirst < 0) or (ALast < AFirst) then
  begin
    Exit('');
  end;
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

/// <summary>Leerraum zusammenfassen (Zeilenumbrüche in Typen und Standardwerten).</summary>
function Collapse(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
  begin
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
    begin
      Space := True;
    end
    else
    begin
      if Space and (Result <> '') then
      begin
        Result := Result + ' ';
      end;
      Space := False;
      Result := Result + AText[Index];
    end;
  end;
end;

/// <summary>Teile von AText an ADelimiter außerhalb von Klammern und Zeichenketten.</summary>
function SplitTopLevel(const AText: string; ADelimiter: Char): TArray<string>;
var
  Index, Depth, Start: Integer;
  Quoted: Boolean;
begin
  Result := nil;
  Depth := 0;
  Quoted := False;
  Start := 1;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = '''' then
    begin
      Quoted := not Quoted;
    end
    else if not Quoted then
      case AText[Index] of
        '(', '[', '<':
          Inc(Depth);
        ')', ']', '>':
          Dec(Depth);
      else
        if (AText[Index] = ADelimiter) and (Depth = 0) then
        begin
          Result := Result + [Copy(AText, Start, Index - Start)];
          Start := Index + 1;
        end;
      end;
  end;
  Result := Result + [Copy(AText, Start, MaxInt)];
end;

/// <summary>Stelle von ADelimiter außerhalb von Klammern und Zeichenketten; 0 ohne.</summary>
function TopLevelPos(const AText: string; ADelimiter: Char): Integer;
var
  Index, Depth: Integer;
  Quoted: Boolean;
begin
  Depth := 0;
  Quoted := False;
  for Index := 1 to Length(AText) do
  begin
    if AText[Index] = '''' then
    begin
      Quoted := not Quoted;
    end
    else if not Quoted then
      case AText[Index] of
        '(', '[', '<':
          Inc(Depth);
        ')', ']', '>':
          Dec(Depth);
      else
        if (AText[Index] = ADelimiter) and (Depth = 0) then
        begin
          Exit(Index);
        end;
      end;
  end;
  Result := 0;
end;

/// <summary>Ein Bezeichner, kein reserviertes Wort, ohne &amp;.</summary>
function IsIdentifier(const AName: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(AName);
  Result := (Length(Tokens) = 1) and (Tokens[0].Kind = TPascalTokenKind.Identifier) and (Tokens[0].Text = AName) and
    (AName[1] <> '&');
end;

{ TSignatureParameter }

function TSignatureParameter.Text(AWithDefault: Boolean): string;
begin
  Result := Name;
  if Modifier <> '' then
  begin
    Result := Modifier + ' ' + Result;
  end;
  if TypeName <> '' then
  begin
    Result := Result + ': ' + TypeName;
  end;
  if AWithDefault and (DefaultValue <> '') then
  begin
    Result := Result + ' = ' + DefaultValue;
  end;
end;

{ TSignatureHeader }

function TSignatureHeader.IsFunction: Boolean;
begin
  Result := Keyword = 'function';
end;

function TSignatureHeader.HasDirective(const ADirective: string): Boolean;
var
  Directive: string;
begin
  for Directive in Directives do
  begin
    if SameText(Directive, ADirective) or StartsText(ADirective + ' ', Directive) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureHeader.ParamTypes: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Parameters));
  for Index := 0 to High(Parameters) do
  begin
    Result[Index] := Parameters[Index].TypeName;
  end;
end;

{ TParameterChange }

class function TParameterChange.Kept(AOrigin: Integer; const AName: string): TParameterChange;
begin
  Result := Default(TParameterChange);
  Result.Origin := AOrigin;
  Result.Name := AName;
end;

class function TParameterChange.Added(const AName, ATypeName, AModifier, AValue: string): TParameterChange;
begin
  Result := Default(TParameterChange);
  Result.Origin := -1;
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Modifier := AModifier;
  Result.Value := AValue;
end;

{ TChangeSignature }

class function TChangeSignature.ParseParameters(const AText: string): TArray<TSignatureParameter>;
var
  Group, Rest, Names, Word, Name: string;
  Colon, Equals, Space, GroupIndex: Integer;
  Parameter: TSignatureParameter;
begin
  Result := nil;
  GroupIndex := 0;
  for Group in SplitTopLevel(AText, ';') do
  begin
    Rest := Collapse(Group);
    if Rest = '' then
    begin
      Continue;
    end;
    Parameter := Default(TSignatureParameter);
    Parameter.Group := GroupIndex;
    Inc(GroupIndex);
    // Attribute wie [ref] gehören zum Modifizierer.
    while StartsStr('[', Rest) and (Pos(']', Rest) > 0) do
    begin
      Parameter.Modifier := Trim(Parameter.Modifier + ' ' + Copy(Rest, 1, Pos(']', Rest)));
      Rest := Trim(Copy(Rest, Pos(']', Rest) + 1, MaxInt));
    end;
    Space := Pos(' ', Rest);
    if Space > 0 then
    begin
      Word := Copy(Rest, 1, Space - 1);
      if IndexText(Word, ModifierWords) >= 0 then
      begin
        Parameter.Modifier := Trim(Parameter.Modifier + ' ' + LowerCase(Word));
        Rest := Trim(Copy(Rest, Space + 1, MaxInt));
      end;
    end;
    Equals := TopLevelPos(Rest, '=');
    if Equals > 0 then
    begin
      Parameter.DefaultValue := Trim(Copy(Rest, Equals + 1, MaxInt));
      Rest := Trim(Copy(Rest, 1, Equals - 1));
    end;
    Colon := TopLevelPos(Rest, ':');
    if Colon > 0 then
    begin
      Parameter.TypeName := Trim(Copy(Rest, Colon + 1, MaxInt));
      Names := Copy(Rest, 1, Colon - 1);
    end
    else
    begin
      Names := Rest;
    end;
    for Name in SplitTopLevel(Names, ',') do
    begin
      Parameter.Name := Trim(Name);
      if Parameter.Name <> '' then
      begin
        Result := Result + [Parameter];
      end;
    end;
  end;
end;

class function TChangeSignature.NameTokenAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): Integer;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    if (Token.StartPos.Line > APosition.Line) or
      ((Token.StartPos.Line = APosition.Line) and (Token.StartPos.Character > APosition.Character)) then
    begin
      Break;
    end;
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

/// <summary>Liest Klammern, Ergebnistyp, ";" und Direktiven ab dem Token hinter dem Namen.</summary>
function ReadTail(const AText: string; const ATokens: TArray<TPascalToken>; AAfterName: Integer;
  var AHeader: TSignatureHeader; ADirectives: Boolean): Boolean;
var
  Current, Close, Next, Last: Integer;
  Directive: string;
begin
  Result := False;
  AHeader.OpenToken := -1;
  AHeader.CloseToken := -1;
  Current := AAfterName;
  if IsSymbolAt(ATokens, Current, '(') then
  begin
    Close := Matching(ATokens, Current);
    if Close < 0 then
    begin
      Exit;
    end;
    AHeader.OpenToken := Current;
    AHeader.CloseToken := Close;
    if Close > NextToken(ATokens, Current) then
    begin
      AHeader.Parameters := TChangeSignature.ParseParameters(SliceText(AText, ATokens, Current + 1, Close - 1));
    end;
    Current := NextToken(ATokens, Close);
  end;
  if IsSymbolAt(ATokens, Current, ':') then
  begin
    Next := Current;
    while (Next >= 0) and (Next <= High(ATokens)) and not ATokens[Next].IsSymbol(';') and
      not ATokens[Next].IsKeyword('of') do
    begin
      Next := NextToken(ATokens, Next);
    end;
    if Next < 0 then
    begin
      Exit;
    end;
    AHeader.ResultType := Collapse(SliceText(AText, ATokens, NextToken(ATokens, Current), PreviousToken(ATokens, Next)));
    Current := Next;
  end;
  // Prozedurale Typen: "of object" bzw. "reference to" gehören vor das ";".
  while (Current >= 0) and (ATokens[Current].IsKeyword('of') or SameText(ATokens[Current].Text, 'object')) do
  begin
    Current := NextToken(ATokens, Current);
  end;
  if not IsSymbolAt(ATokens, Current, ';') then
  begin
    // Kopf ohne ";" am Ende eines prozeduralen Typs in einer Parameterliste o. Ä.
    if not ADirectives then
    begin
      AHeader.EndToken := PreviousToken(ATokens, Current);
      AHeader.LastToken := AHeader.EndToken;
      Exit(True);
    end;
    Exit;
  end;
  AHeader.EndToken := Current;
  AHeader.LastToken := Current;
  if not ADirectives then
  begin
    Exit(True);
  end;
  AHeader.Directives := nil;
  Next := NextToken(ATokens, Current);
  while (Next >= 0) and IsWord(ATokens[Next], DirectiveWords) do
  begin
    Last := Next;
    while (Last >= 0) and not ATokens[Last].IsSymbol(';') do
    begin
      Last := NextToken(ATokens, Last);
    end;
    if Last < 0 then
    begin
      Break;
    end;
    Directive := LowerCase(Collapse(SliceText(AText, ATokens, Next, PreviousToken(ATokens, Last))));
    AHeader.Directives := AHeader.Directives + [Directive];
    AHeader.LastToken := Last;
    Next := NextToken(ATokens, Last);
  end;
  Result := True;
end;

class function TChangeSignature.ReadHeader(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; out AHeader: TSignatureHeader): Boolean;
var
  Current, Next: Integer;
begin
  AHeader := Default(TSignatureHeader);
  Result := False;
  if (ANameToken < 0) or (ANameToken > High(ATokens)) then
  begin
    Exit;
  end;
  AHeader.NameToken := ANameToken;
  // Rückwärts über "TFoo." bzw. "TAussen.TInnen." bis zum Schlüsselwort.
  Current := PreviousToken(ATokens, ANameToken);
  while IsSymbolAt(ATokens, Current, '.') do
  begin
    Current := PreviousToken(ATokens, Current);
    if (Current >= 0) and ATokens[Current].IsSymbol('>') then
    begin
      // Generischer Typ TFoo<T>.Bar
      while (Current >= 0) and not ATokens[Current].IsSymbol('<') do
      begin
        Dec(Current);
      end;
      Current := PreviousToken(ATokens, Current);
    end;
    if (Current < 0) or (ATokens[Current].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    Current := PreviousToken(ATokens, Current);
  end;
  if (Current < 0) or not IsWord(ATokens[Current], RoutineWords) then
  begin
    Exit;
  end;
  AHeader.Keyword := LowerCase(ATokens[Current].Text);
  AHeader.StartToken := Current;
  Next := PreviousToken(ATokens, Current);
  // "class procedure", aber nicht "TFoo = class" direkt vor der ersten Methode.
  if (Next >= 0) and ATokens[Next].IsKeyword('class') and not IsSymbolAt(ATokens, PreviousToken(ATokens, Next), '=') and
    not ((PreviousToken(ATokens, Next) >= 0) and SameText(ATokens[PreviousToken(ATokens, Next)].Text, 'packed')) then
  begin
    AHeader.IsClass := True;
    AHeader.StartToken := Next;
  end;
  AHeader.QualifiedName := StringReplace(Collapse(SliceText(AText, ATokens, NextToken(ATokens, Current),
    ANameToken)), ' ', '', [rfReplaceAll]);
  Next := NextToken(ATokens, ANameToken);
  // Generische Methode Bar<T>(...)
  if IsSymbolAt(ATokens, Next, '<') then
  begin
    Next := Matching(ATokens, Next);
    if Next < 0 then
    begin
      Exit;
    end;
    Next := NextToken(ATokens, Next);
  end;
  Result := ReadTail(AText, ATokens, Next, AHeader, True);
end;

class function TChangeSignature.ReadProcedureType(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; out AHeader: TSignatureHeader): Boolean;
var
  Current: Integer;
begin
  AHeader := Default(TSignatureHeader);
  Result := False;
  if (ANameToken < 0) or (ANameToken > High(ATokens)) then
  begin
    Exit;
  end;
  // TFooEvent = [reference to] procedure(...)
  Current := NextToken(ATokens, ANameToken);
  if not IsSymbolAt(ATokens, Current, '=') then
  begin
    Exit;
  end;
  Current := NextToken(ATokens, Current);
  if (Current >= 0) and SameText(ATokens[Current].Text, 'reference') then
  begin
    Current := NextToken(ATokens, Current);
    if (Current >= 0) and SameText(ATokens[Current].Text, 'to') then
    begin
      Current := NextToken(ATokens, Current);
    end;
  end;
  if (Current < 0) or not IsWord(ATokens[Current], ['procedure', 'function']) then
  begin
    Exit;
  end;
  AHeader.Keyword := LowerCase(ATokens[Current].Text);
  AHeader.StartToken := Current;
  // Der "Name" ist das Schlüsselwort: die Klammern folgen direkt.
  AHeader.NameToken := Current;
  AHeader.QualifiedName := ATokens[ANameToken].Text;
  Result := ReadTail(AText, ATokens, NextToken(ATokens, Current), AHeader, False);
end;

class function TChangeSignature.Validate(const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  Index, Other: Integer;
  Change: TParameterChange;
  Used: TArray<Boolean>;
  SeenDefault: Boolean;
begin
  Result := '';
  SetLength(Used, Length(AOld));
  SeenDefault := False;
  for Index := 0 to High(AChanges) do
  begin
    Change := AChanges[Index];
    if not IsIdentifier(Change.Name) then
    begin
      Exit(Format('"%s" ist kein gültiger Parametername.', [Change.Name]));
    end;
    for Other := 0 to Index - 1 do
    begin
      if SameText(AChanges[Other].Name, Change.Name) then
      begin
        Exit(Format('Der Parameter "%s" steht zweimal in der Liste.', [Change.Name]));
      end;
    end;
    if Change.Origin >= 0 then
    begin
      if Change.Origin > High(AOld) then
      begin
        Exit(Format('Der Parameter "%s" gehört nicht zur alten Signatur.', [Change.Name]));
      end;
      if Used[Change.Origin] then
      begin
        Exit(Format('Der Parameter "%s" steht zweimal in der Liste.', [AOld[Change.Origin].Name]));
      end;
      Used[Change.Origin] := True;
      if AOld[Change.Origin].DefaultValue <> '' then
      begin
        SeenDefault := True;
      end;
    end
    else
    begin
      if Trim(Change.TypeName) = '' then
      begin
        Exit(Format('Für den neuen Parameter "%s" fehlt der Typ.', [Change.Name]));
      end;
      if Trim(Change.Value) = '' then
      begin
        Exit(Format('Für den neuen Parameter "%s" fehlt der Wert, den die bisherigen Aufrufer übergeben.',
          [Change.Name]));
      end;
      // Atlas erzeugt keine Standardwerte; hinter einem Parameter mit Standardwert ginge es nur mit einem.
      if SeenDefault then
      begin
        Exit(Format('Der neue Parameter "%s" stünde hinter einem Parameter mit Standardwert. Bitte weiter vorn ' +
          'einfügen.', [Change.Name]));
      end;
    end;
  end;
end;

class function TChangeSignature.NewParameters(const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>; const ARootNames: TArray<string>;
  AWithDefaults: Boolean): TArray<TSignatureParameter>;
var
  Change: TParameterChange;
  Parameter: TSignatureParameter;
  Renamed: Boolean;
begin
  Result := nil;
  for Change in AChanges do
  begin
    if Change.Origin >= 0 then
    begin
      if Change.Origin > High(AOld) then
      begin
        Continue;
      end;
      Parameter := AOld[Change.Origin];
      Renamed := (Change.Origin <= High(ARootNames)) and not SameText(Change.Name, ARootNames[Change.Origin]);
      if Renamed or (Change.Origin > High(ARootNames)) then
      begin
        Parameter.Name := Change.Name;
      end;
      if not AWithDefaults then
      begin
        Parameter.DefaultValue := '';
      end;
    end
    else
    begin
      Parameter := Default(TSignatureParameter);
      Parameter.Group := -1;
      Parameter.Name := Change.Name;
      Parameter.TypeName := Trim(Change.TypeName);
      Parameter.Modifier := LowerCase(Trim(Change.Modifier));
    end;
    Result := Result + [Parameter];
  end;
end;

class function TChangeSignature.ParameterList(const AParameters: TArray<TSignatureParameter>;
  AWithDefaults: Boolean): string;
var
  Index: Integer;
  Group: string;
  Current, Next: TSignatureParameter;

  function Groupable(const A, B: TSignatureParameter): Boolean;
  begin
    Result := (A.Group >= 0) and (A.Group = B.Group) and SameText(A.Modifier, B.Modifier) and
      (A.TypeName = B.TypeName) and
      ((not AWithDefaults) or ((A.DefaultValue = '') and (B.DefaultValue = '')));
  end;

begin
  Result := '';
  Index := 0;
  while Index <= High(AParameters) do
  begin
    Current := AParameters[Index];
    Group := Current.Name;
    while (Index < High(AParameters)) and Groupable(Current, AParameters[Index + 1]) do
    begin
      Inc(Index);
      Next := AParameters[Index];
      Group := Group + ', ' + Next.Name;
    end;
    Current.Name := Group;
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + Current.Text(AWithDefaults);
    Inc(Index);
  end;
  if Result <> '' then
  begin
    Result := '(' + Result + ')';
  end;
end;

class function TChangeSignature.HeaderEdit(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader;
  const AList: string): TTextEdit;
begin
  if AHeader.OpenToken >= 0 then
  begin
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.OpenToken].StartPos,
      ATokens[AHeader.CloseToken].EndPos), AList);
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.NameToken].EndPos,
      ATokens[AHeader.NameToken].EndPos), AList);
  end;
end;

class function TChangeSignature.UseOf(const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  AHasRequired: Boolean): TSignatureUse;
var
  Before, After: Integer;
begin
  Before := PreviousToken(ATokens, ANameToken);
  // Über "Self." bzw. "Liste." hinweg nach vorn schauen.
  while IsSymbolAt(ATokens, Before, '.') do
  begin
    Before := PreviousToken(ATokens, Before);
    if Before >= 0 then
    begin
      Before := PreviousToken(ATokens, Before);
    end;
  end;
  if (Before >= 0) and IsWord(ATokens[Before], ['read', 'write', 'stored', 'add', 'remove']) then
  begin
    Exit(TSignatureUse.Accessor);
  end;
  if IsSymbolAt(ATokens, Before, '@') then
  begin
    Exit(TSignatureUse.Pointer_);
  end;
  After := NextToken(ATokens, ANameToken);
  if IsSymbolAt(ATokens, After, '<') then
  begin
    After := Matching(ATokens, After);
    if After >= 0 then
    begin
      After := NextToken(ATokens, After);
    end;
  end;
  if IsSymbolAt(ATokens, After, '(') then
  begin
    Exit(TSignatureUse.Call);
  end;
  // Ohne Klammern: Aufruf nur, wenn die Routine ohne Argumente aufrufbar ist und nicht zugewiesen wird.
  if AHasRequired or IsSymbolAt(ATokens, Before, ':=') then
  begin
    Result := TSignatureUse.Pointer_;
  end
  else
  begin
    Result := TSignatureUse.Call;
  end;
end;

class function TChangeSignature.CallEdit(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
  const AValues: TArray<string>; out AEdit: TTextEdit): Boolean;
var
  Open, Close, Index, Last: Integer;
  OldArgs, NewArgs: TArray<string>;
  Missing: TArray<Boolean>;
  Change: TParameterChange;
  Value, Joined: string;
begin
  AEdit := Default(TTextEdit);
  Open := NextToken(ATokens, ANameToken);
  if IsSymbolAt(ATokens, Open, '<') then
  begin
    Open := Matching(ATokens, Open);
    if Open >= 0 then
    begin
      Open := NextToken(ATokens, Open);
    end;
  end;
  OldArgs := nil;
  Close := -1;
  if IsSymbolAt(ATokens, Open, '(') then
  begin
    Close := Matching(ATokens, Open);
    if Close < 0 then
    begin
      Exit(False);
    end;
    if Close > NextToken(ATokens, Open) then
    begin
      for Value in SplitTopLevel(SliceText(AText, ATokens, NextToken(ATokens, Open), PreviousToken(ATokens, Close)),
        ',') do
      begin
        OldArgs := OldArgs + [Trim(Value)];
      end;
    end;
  end
  else
  begin
    Open := -1;
  end;
  NewArgs := nil;
  Missing := nil;
  for Index := 0 to High(AChanges) do
  begin
    Change := AChanges[Index];
    if Change.Origin >= 0 then
    begin
      if Change.Origin <= High(OldArgs) then
      begin
        NewArgs := NewArgs + [OldArgs[Change.Origin]];
        Missing := Missing + [False];
      end
      else
      begin
        // Ausgelassenes Argument mit Standardwert.
        if Change.Origin <= High(AOld) then
        begin
          Value := AOld[Change.Origin].DefaultValue;
        end
        else
        begin
          Value := '';
        end;
        NewArgs := NewArgs + [Value];
        Missing := Missing + [True];
      end;
    end
    else
    begin
      Value := '';
      if Index <= High(AValues) then
      begin
        Value := AValues[Index];
      end;
      if Value = '' then
      begin
        Value := Change.Value;
      end;
      NewArgs := NewArgs + [Value];
      Missing := Missing + [False];
    end;
  end;
  // Ausgelassene Standardwerte am Ende bleiben ausgelassen.
  Last := High(NewArgs);
  while (Last >= 0) and Missing[Last] do
  begin
    Dec(Last);
  end;
  SetLength(NewArgs, Last + 1);
  Joined := string.Join(', ', NewArgs);
  if (Length(NewArgs) = Length(OldArgs)) and (Joined = string.Join(', ', OldArgs)) then
  begin
    Exit(False);
  end;
  if Open >= 0 then
  begin
    if Joined = '' then
    begin
      // Foo() wird zu Foo.
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[Close].EndPos), '');
    end
    else
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[Open].StartPos, ATokens[Close].EndPos),
        '(' + Joined + ')');
    end;
  end
  else
  begin
    if Joined = '' then
    begin
      Exit(False);
    end;
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[ANameToken].EndPos),
      '(' + Joined + ')');
  end;
  Result := True;
end;

class function TChangeSignature.Uses_(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const AName: string): TArray<Integer>;
var
  Index, Before: Integer;
  Text: string;
begin
  Result := nil;
  if AFirst < 0 then
  begin
    Exit;
  end;
  for Index := AFirst to ALast do
  begin
    if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
    begin
      Continue;
    end;
    Text := ATokens[Index].Text;
    if StartsStr('&', Text) then
    begin
      Text := Copy(Text, 2, MaxInt);
    end;
    if not SameText(Text, AName) then
    begin
      Continue;
    end;
    Before := PreviousToken(ATokens, Index);
    if IsSymbolAt(ATokens, Before, '.') then
    begin
      Continue;
    end;
    Result := Result + [Index];
  end;
end;

function FindRoutine(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Root: TSyntaxNode;
  Offset: Integer;
begin
  Root := ANode;
  Offset := AOffset;
  // Search statt Rekursion (Bericht M1); unter ANode nur Knoten, die AOffset enthalten.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if ACandidate = Root then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if (ACandidate.StartOffset > Offset) or (Offset > ACandidate.EndOffset) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      // Die äußerste Routine, deren Kopf hier steht.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

class function TChangeSignature.BodyEnd(ATree: TSyntaxTree; const AHeader: TSignatureHeader): Integer;
var
  Node: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  HasBegin: Boolean;
begin
  Result := -1;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := ATree.Tokens;
  Node := FindRoutine(ATree.Root, Tokens[AHeader.NameToken].Offset);
  if Node = nil then
  begin
    Exit;
  end;
  HasBegin := False;
  for Index := AHeader.LastToken + 1 to High(Tokens) do
  begin
    if Tokens[Index].Offset >= Node.EndOffset then
    begin
      Break;
    end;
    if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('asm') then
    begin
      HasBegin := True;
    end;
    Result := Index;
  end;
  if not HasBegin then
  begin
    Exit(-1);
  end;
  // Das ";" hinter end gehört dazu.
  Index := NextToken(Tokens, Result);
  if IsSymbolAt(Tokens, Index, ';') then
  begin
    Result := Index;
  end;
end;

class function TChangeSignature.HeaderText(const AHeader: TSignatureHeader; const AQualifiedName: string;
  const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string;
begin
  Result := AHeader.Keyword + ' ' + AQualifiedName + ParameterList(AParameters, AWithDefaults);
  if AHeader.IsClass then
  begin
    Result := 'class ' + Result;
  end;
  if AHeader.ResultType <> '' then
  begin
    Result := Result + ': ' + AHeader.ResultType;
  end;
  Result := Result + ';';
end;

class function TChangeSignature.ForwardCall(const AHeader: TSignatureHeader; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  Arguments: TArray<string>;
  Change: TParameterChange;
  Name: string;
begin
  Arguments := nil;
  for Change in AChanges do
  begin
    if (Change.Origin >= 0) and (Change.Origin <= High(AOld)) then
    begin
      Arguments := Arguments + [AOld[Change.Origin].Name];
    end
    else
    begin
      Arguments := Arguments + [Change.Value];
    end;
  end;
  Name := AHeader.QualifiedName;
  if LastDelimiter('.', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  Result := Name;
  if Length(Arguments) > 0 then
  begin
    Result := Result + '(' + string.Join(', ', Arguments) + ')';
  end;
  if AHeader.IsFunction then
  begin
    Result := 'Result := ' + Result;
  end;
  Result := Result + ';';
end;

class function TChangeSignature.OverloadDirectives(const AHeader: TSignatureHeader; AVirtual: Boolean): string;
var
  Directive, Word: string;
begin
  Result := ' overload;';
  for Directive in AHeader.Directives do
  begin
    Word := Directive;
    if Pos(' ', Word) > 0 then
    begin
      Word := Copy(Word, 1, Pos(' ', Word) - 1);
    end;
    if IndexText(Word, ChainWords) < 0 then
    begin
      Result := Result + ' ' + Directive + ';';
    end;
  end;
  if AVirtual then
  begin
    Result := Result + ' virtual;';
  end;
end;

class function TChangeSignature.ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Sorted: TArray<TTextEdit>;
  Lines: TLineTable;
  Index, StartOffset, EndOffset: Integer;
begin
  Sorted := Copy(AEdits);
  TArray.Sort<TTextEdit>(Sorted, TComparer<TTextEdit>.Construct(
    function(const A, B: TTextEdit): Integer
    begin
      if A.Range.StartPos.Line <> B.Range.StartPos.Line then
      begin
        Result := B.Range.StartPos.Line - A.Range.StartPos.Line;
      end
      else
      begin
        Result := B.Range.StartPos.Character - A.Range.StartPos.Character;
      end;
    end));
  Lines := TLineTable.Build(AText);
  Result := AText;
  for Index := 0 to High(Sorted) do
  begin
    StartOffset := Lines.OffsetAt(Sorted[Index].Range.StartPos);
    EndOffset := Lines.OffsetAt(Sorted[Index].Range.EndPos);
    Result := Copy(Result, 1, StartOffset) + Sorted[Index].NewText + Copy(Result, EndOffset + 1, MaxInt);
  end;
end;

end.
