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
    Inc(Result);
  if Result > High(ATokens) then
    Result := -1;
end;

function PreviousToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
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
    Closing := ')'
  else if Opening = '[' then
    Closing := ']'
  else
    Closing := '>';
  Depth := 0;
  Result := AOpen;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(Opening) then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(Closing) then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Text von Token AFirst bis einschließlich ALast.</summary>
function SliceText(const AText: string; const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): string;
begin
  if (AFirst < 0) or (ALast < AFirst) then
    Exit('');
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
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Space := True
    else
    begin
      if Space and (Result <> '') then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
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
    if AText[Index] = '''' then
      Quoted := not Quoted
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
    if AText[Index] = '''' then
      Quoted := not Quoted
    else if not Quoted then
      case AText[Index] of
        '(', '[', '<':
          Inc(Depth);
        ')', ']', '>':
          Dec(Depth);
      else
        if (AText[Index] = ADelimiter) and (Depth = 0) then
          Exit(Index);
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
    Result := Modifier + ' ' + Result;
  if TypeName <> '' then
    Result := Result + ': ' + TypeName;
  if AWithDefault and (DefaultValue <> '') then
    Result := Result + ' = ' + DefaultValue;
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
    if SameText(Directive, ADirective) or StartsText(ADirective + ' ', Directive) then
      Exit(True);
  Result := False;
end;

function TSignatureHeader.ParamTypes: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(Parameters));
  for Index := 0 to High(Parameters) do
    Result[Index] := Parameters[Index].TypeName;
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
      Continue;
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
      Names := Rest;
    for Name in SplitTopLevel(Names, ',') do
    begin
      Parameter.Name := Trim(Name);
      if Parameter.Name <> '' then
        Result := Result + [Parameter];
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
      Break;
    if (Token.Kind = TPascalTokenKind.Identifier) and (Token.EndPos.Line = APosition.Line) and
      (APosition.Character <= Token.EndPos.Character) then
      Exit(Index);
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
      Exit;
    AHeader.OpenToken := Current;
    AHeader.CloseToken := Close;
    if Close > NextToken(ATokens, Current) then
      AHeader.Parameters := TChangeSignature.ParseParameters(SliceText(AText, ATokens, Current + 1, Close - 1));
    Current := NextToken(ATokens, Close);
  end;
  if IsSymbolAt(ATokens, Current, ':') then
  begin
    Next := Current;
    while (Next >= 0) and (Next <= High(ATokens)) and not ATokens[Next].IsSymbol(';') and
      not ATokens[Next].IsKeyword('of') do
      Next := NextToken(ATokens, Next);
    if Next < 0 then
      Exit;
    AHeader.ResultType := Collapse(SliceText(AText, ATokens, NextToken(ATokens, Current), PreviousToken(ATokens, Next)));
    Current := Next;
  end;
  // Prozedurale Typen: "of object" bzw. "reference to" gehören vor das ";".
  while (Current >= 0) and (ATokens[Current].IsKeyword('of') or SameText(ATokens[Current].Text, 'object')) do
    Current := NextToken(ATokens, Current);
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
    Exit(True);
  AHeader.Directives := nil;
  Next := NextToken(ATokens, Current);
  while (Next >= 0) and IsWord(ATokens[Next], DirectiveWords) do
  begin
    Last := Next;
    while (Last >= 0) and not ATokens[Last].IsSymbol(';') do
      Last := NextToken(ATokens, Last);
    if Last < 0 then
      Break;
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
    Exit;
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
        Dec(Current);
      Current := PreviousToken(ATokens, Current);
    end;
    if (Current < 0) or (ATokens[Current].Kind <> TPascalTokenKind.Identifier) then
      Exit;
    Current := PreviousToken(ATokens, Current);
  end;
  if (Current < 0) or not IsWord(ATokens[Current], RoutineWords) then
    Exit;
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
      Exit;
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
    Exit;
  // TFooEvent = [reference to] procedure(...)
  Current := NextToken(ATokens, ANameToken);
  if not IsSymbolAt(ATokens, Current, '=') then
    Exit;
  Current := NextToken(ATokens, Current);
  if (Current >= 0) and SameText(ATokens[Current].Text, 'reference') then
  begin
    Current := NextToken(ATokens, Current);
    if (Current >= 0) and SameText(ATokens[Current].Text, 'to') then
      Current := NextToken(ATokens, Current);
  end;
  if (Current < 0) or not IsWord(ATokens[Current], ['procedure', 'function']) then
    Exit;
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
      Exit(Format('"%s" ist kein gültiger Parametername.', [Change.Name]));
    for Other := 0 to Index - 1 do
      if SameText(AChanges[Other].Name, Change.Name) then
        Exit(Format('Der Parameter "%s" steht zweimal in der Liste.', [Change.Name]));
    if Change.Origin >= 0 then
    begin
      if Change.Origin > High(AOld) then
        Exit(Format('Der Parameter "%s" gehört nicht zur alten Signatur.', [Change.Name]));
      if Used[Change.Origin] then
        Exit(Format('Der Parameter "%s" steht zweimal in der Liste.', [AOld[Change.Origin].Name]));
      Used[Change.Origin] := True;
      if AOld[Change.Origin].DefaultValue <> '' then
        SeenDefault := True;
    end
    else
    begin
      if Trim(Change.TypeName) = '' then
        Exit(Format('Für den neuen Parameter "%s" fehlt der Typ.', [Change.Name]));
      if Trim(Change.Value) = '' then
        Exit(Format('Für den neuen Parameter "%s" fehlt der Wert, den die bisherigen Aufrufer übergeben.',
          [Change.Name]));
      // Atlas erzeugt keine Standardwerte; hinter einem Parameter mit Standardwert ginge es nur mit einem.
      if SeenDefault then
        Exit(Format('Der neue Parameter "%s" stünde hinter einem Parameter mit Standardwert. Bitte weiter vorn ' +
          'einfügen.', [Change.Name]));
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
        Continue;
      Parameter := AOld[Change.Origin];
      Renamed := (Change.Origin <= High(ARootNames)) and not SameText(Change.Name, ARootNames[Change.Origin]);
      if Renamed or (Change.Origin > High(ARootNames)) then
        Parameter.Name := Change.Name;
      if not AWithDefaults then
        Parameter.DefaultValue := '';
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
      Result := Result + '; ';
    Result := Result + Current.Text(AWithDefaults);
    Inc(Index);
  end;
  if Result <> '' then
    Result := '(' + Result + ')';
end;

class function TChangeSignature.HeaderEdit(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader;
  const AList: string): TTextEdit;
begin
  if AHeader.OpenToken >= 0 then
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.OpenToken].StartPos,
      ATokens[AHeader.CloseToken].EndPos), AList)
  else
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.NameToken].EndPos,
      ATokens[AHeader.NameToken].EndPos), AList);
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
      Before := PreviousToken(ATokens, Before);
  end;
  if (Before >= 0) and IsWord(ATokens[Before], ['read', 'write', 'stored', 'add', 'remove']) then
    Exit(TSignatureUse.Accessor);
  if IsSymbolAt(ATokens, Before, '@') then
    Exit(TSignatureUse.Pointer_);
  After := NextToken(ATokens, ANameToken);
  if IsSymbolAt(ATokens, After, '<') then
  begin
    After := Matching(ATokens, After);
    if After >= 0 then
      After := NextToken(ATokens, After);
  end;
  if IsSymbolAt(ATokens, After, '(') then
    Exit(TSignatureUse.Call);
  // Ohne Klammern: Aufruf nur, wenn die Routine ohne Argumente aufrufbar ist und nicht zugewiesen wird.
  if AHasRequired or IsSymbolAt(ATokens, Before, ':=') then
    Result := TSignatureUse.Pointer_
  else
    Result := TSignatureUse.Call;
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
      Open := NextToken(ATokens, Open);
  end;
  OldArgs := nil;
  Close := -1;
  if IsSymbolAt(ATokens, Open, '(') then
  begin
    Close := Matching(ATokens, Open);
    if Close < 0 then
      Exit(False);
    if Close > NextToken(ATokens, Open) then
      for Value in SplitTopLevel(SliceText(AText, ATokens, NextToken(ATokens, Open), PreviousToken(ATokens, Close)),
        ',') do
        OldArgs := OldArgs + [Trim(Value)];
  end
  else
    Open := -1;
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
          Value := AOld[Change.Origin].DefaultValue
        else
          Value := '';
        NewArgs := NewArgs + [Value];
        Missing := Missing + [True];
      end;
    end
    else
    begin
      Value := '';
      if Index <= High(AValues) then
        Value := AValues[Index];
      if Value = '' then
        Value := Change.Value;
      NewArgs := NewArgs + [Value];
      Missing := Missing + [False];
    end;
  end;
  // Ausgelassene Standardwerte am Ende bleiben ausgelassen.
  Last := High(NewArgs);
  while (Last >= 0) and Missing[Last] do
    Dec(Last);
  SetLength(NewArgs, Last + 1);
  Joined := string.Join(', ', NewArgs);
  if (Length(NewArgs) = Length(OldArgs)) and (Joined = string.Join(', ', OldArgs)) then
    Exit(False);
  if Open >= 0 then
  begin
    if Joined = '' then
      // Foo() wird zu Foo.
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[Close].EndPos), '')
    else
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[Open].StartPos, ATokens[Close].EndPos),
        '(' + Joined + ')');
  end
  else
  begin
    if Joined = '' then
      Exit(False);
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
    Exit;
  for Index := AFirst to ALast do
  begin
    if (Index > High(ATokens)) or (ATokens[Index].Kind <> TPascalTokenKind.Identifier) then
      Continue;
    Text := ATokens[Index].Text;
    if StartsStr('&', Text) then
      Text := Copy(Text, 2, MaxInt);
    if not SameText(Text, AName) then
      Continue;
    Before := PreviousToken(ATokens, Index);
    if IsSymbolAt(ATokens, Before, '.') then
      Continue;
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
        Exit(TSyntaxSearchStep.Descend);
      if (ACandidate.StartOffset > Offset) or (Offset > ACandidate.EndOffset) then
        Exit(TSyntaxSearchStep.Skip);
      // Die äußerste Routine, deren Kopf hier steht.
      if ACandidate.Kind = TSyntaxKind.RoutineDecl then
        Exit(TSyntaxSearchStep.Found);
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
    Exit;
  Tokens := ATree.Tokens;
  Node := FindRoutine(ATree.Root, Tokens[AHeader.NameToken].Offset);
  if Node = nil then
    Exit;
  HasBegin := False;
  for Index := AHeader.LastToken + 1 to High(Tokens) do
  begin
    if Tokens[Index].Offset >= Node.EndOffset then
      Break;
    if Tokens[Index].IsKeyword('begin') or Tokens[Index].IsKeyword('asm') then
      HasBegin := True;
    Result := Index;
  end;
  if not HasBegin then
    Exit(-1);
  // Das ";" hinter end gehört dazu.
  Index := NextToken(Tokens, Result);
  if IsSymbolAt(Tokens, Index, ';') then
    Result := Index;
end;

class function TChangeSignature.HeaderText(const AHeader: TSignatureHeader; const AQualifiedName: string;
  const AParameters: TArray<TSignatureParameter>; AWithDefaults: Boolean): string;
begin
  Result := AHeader.Keyword + ' ' + AQualifiedName + ParameterList(AParameters, AWithDefaults);
  if AHeader.IsClass then
    Result := 'class ' + Result;
  if AHeader.ResultType <> '' then
    Result := Result + ': ' + AHeader.ResultType;
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
    if (Change.Origin >= 0) and (Change.Origin <= High(AOld)) then
      Arguments := Arguments + [AOld[Change.Origin].Name]
    else
      Arguments := Arguments + [Change.Value];
  Name := AHeader.QualifiedName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  Result := Name;
  if Length(Arguments) > 0 then
    Result := Result + '(' + string.Join(', ', Arguments) + ')';
  if AHeader.IsFunction then
    Result := 'Result := ' + Result;
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
      Word := Copy(Word, 1, Pos(' ', Word) - 1);
    if IndexText(Word, ChainWords) < 0 then
      Result := Result + ' ' + Directive + ';';
  end;
  if AVirtual then
    Result := Result + ' virtual;';
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
        Result := B.Range.StartPos.Line - A.Range.StartPos.Line
      else
        Result := B.Range.StartPos.Character - A.Range.StartPos.Character;
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
