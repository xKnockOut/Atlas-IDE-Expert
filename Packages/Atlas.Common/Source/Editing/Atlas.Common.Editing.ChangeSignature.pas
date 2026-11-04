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

  /// <summary>Änderung der Argumente eines Aufrufs: alte Parameter (für Standardwerte ausgelassener Argumente),
  /// die neue Signatur und je neuem Parameter der Wert (Index wie Changes, '' = Value der Änderung).</summary>
  TCallChange = record
    Old: TArray<TSignatureParameter>;
    Changes: TArray<TParameterChange>;
    Values: TArray<string>;
    class function Create(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
      const AValues: TArray<string>): TCallChange; static;
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
    /// <summary>Neue Argumente des Aufrufs an ANameToken nach AChange. False, wenn sich nichts ändert.</summary>
    class function CallEdit(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      const AChange: TCallChange; out AEdit: TTextEdit): Boolean; static;
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

{ TCallChange }

class function TCallChange.Create(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
  const AValues: TArray<string>): TCallChange;
begin
  Result.Old := AOld;
  Result.Changes := AChanges;
  Result.Values := AValues;
end;

{ TChangeSignature }

/// <summary>Löst Attribute wie [ref] und einen Modifizierer (const, var …) vom Anfang von ARest; sie gehören zum
/// Modifizierer von AParameter.</summary>
procedure ReadModifiers(var ARest: string; var AParameter: TSignatureParameter);
var
  mSpace: Integer;
  mWord: string;
begin
  while StartsStr('[', ARest) and (Pos(']', ARest) > 0) do
  begin
    AParameter.Modifier := Trim(AParameter.Modifier + ' ' + Copy(ARest, 1, Pos(']', ARest)));
    ARest := Trim(Copy(ARest, Pos(']', ARest) + 1, MaxInt));
  end;
  mSpace := Pos(' ', ARest);
  mWord := Copy(ARest, 1, mSpace - 1);
  if (mSpace > 0) and (IndexText(mWord, ModifierWords) >= 0) then
  begin
    AParameter.Modifier := Trim(AParameter.Modifier + ' ' + LowerCase(mWord));
    ARest := Trim(Copy(ARest, mSpace + 1, MaxInt));
  end;
end;

/// <summary>Löst Standardwert und Typ vom Ende von ARest; liefert die Namen davor ("A, B").</summary>
function ReadTypeAndDefault(const ARest: string; var AParameter: TSignatureParameter): string;
var
  mEquals, mColon: Integer;
begin
  Result := ARest;
  mEquals := TopLevelPos(Result, '=');
  if mEquals > 0 then
  begin
    AParameter.DefaultValue := Trim(Copy(Result, mEquals + 1, MaxInt));
    Result := Trim(Copy(Result, 1, mEquals - 1));
  end;
  mColon := TopLevelPos(Result, ':');
  if mColon > 0 then
  begin
    AParameter.TypeName := Trim(Copy(Result, mColon + 1, MaxInt));
    Result := Copy(Result, 1, mColon - 1);
  end;
end;

class function TChangeSignature.ParseParameters(const AText: string): TArray<TSignatureParameter>;
var
  mGroup, mRest, mName: string;
  mGroupIndex: Integer;
  mParameter: TSignatureParameter;
begin
  Result := nil;
  mGroupIndex := 0;
  for mGroup in SplitTopLevel(AText, ';') do
  begin
    mRest := Collapse(mGroup);
    if mRest = '' then
    begin
      Continue;
    end;
    mParameter := Default(TSignatureParameter);
    mParameter.Group := mGroupIndex;
    Inc(mGroupIndex);
    ReadModifiers(mRest, mParameter);
    for mName in SplitTopLevel(ReadTypeAndDefault(mRest, mParameter), ',') do
    begin
      mParameter.Name := Trim(mName);
      if mParameter.Name <> '' then
      begin
        Result := Result + [mParameter];
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

/// <summary>Liest die Parameterliste ab ACurrent, falls dort "(" steht, und setzt ACurrent dahinter; False, wenn
/// die Klammer offen bleibt.</summary>
function ReadParameterList(const AText: string; const ATokens: TArray<TPascalToken>; var ACurrent: Integer;
  var AHeader: TSignatureHeader): Boolean;
var
  mClose: Integer;
begin
  Result := True;
  if not IsSymbolAt(ATokens, ACurrent, '(') then
  begin
    Exit;
  end;
  mClose := Matching(ATokens, ACurrent);
  Result := mClose >= 0;
  if not Result then
  begin
    Exit;
  end;
  AHeader.OpenToken := ACurrent;
  AHeader.CloseToken := mClose;
  if mClose > NextToken(ATokens, ACurrent) then
  begin
    AHeader.Parameters := TChangeSignature.ParseParameters(SliceText(AText, ATokens, ACurrent + 1, mClose - 1));
  end;
  ACurrent := NextToken(ATokens, mClose);
end;

/// <summary>Liest den Ergebnistyp ab ACurrent, falls dort ":" steht, und setzt ACurrent auf das ";" bzw. "of"
/// dahinter; False, wenn keins folgt.</summary>
function ReadResultType(const AText: string; const ATokens: TArray<TPascalToken>; var ACurrent: Integer;
  var AHeader: TSignatureHeader): Boolean;
var
  mNext: Integer;
begin
  Result := True;
  if not IsSymbolAt(ATokens, ACurrent, ':') then
  begin
    Exit;
  end;
  mNext := ACurrent;
  while (mNext >= 0) and (mNext <= High(ATokens)) and not ATokens[mNext].IsSymbol(';') and
    not ATokens[mNext].IsKeyword('of') do
  begin
    mNext := NextToken(ATokens, mNext);
  end;
  Result := mNext >= 0;
  if Result then
  begin
    AHeader.ResultType := Collapse(SliceText(AText, ATokens, NextToken(ATokens, ACurrent),
      PreviousToken(ATokens, mNext)));
    ACurrent := mNext;
  end;
end;

/// <summary>Liest die Direktiven hinter dem ";" des Kopfes (AHeader.EndToken), je bis zu ihrem ";".</summary>
procedure ReadDirectives(const AText: string; const ATokens: TArray<TPascalToken>; var AHeader: TSignatureHeader);
var
  mNext, mLast: Integer;
begin
  AHeader.Directives := nil;
  mNext := NextToken(ATokens, AHeader.EndToken);
  while (mNext >= 0) and IsWord(ATokens[mNext], DirectiveWords) do
  begin
    mLast := mNext;
    while (mLast >= 0) and not ATokens[mLast].IsSymbol(';') do
    begin
      mLast := NextToken(ATokens, mLast);
    end;
    if mLast < 0 then
    begin
      Break;
    end;
    AHeader.Directives := AHeader.Directives + [LowerCase(Collapse(SliceText(AText, ATokens, mNext,
      PreviousToken(ATokens, mLast))))];
    AHeader.LastToken := mLast;
    mNext := NextToken(ATokens, mLast);
  end;
end;

/// <summary>Liest Klammern, Ergebnistyp, ";" und Direktiven ab dem Token hinter dem Namen.</summary>
function ReadTail(const AText: string; const ATokens: TArray<TPascalToken>; AAfterName: Integer;
  var AHeader: TSignatureHeader; ADirectives: Boolean): Boolean;
var
  mCurrent: Integer;
begin
  AHeader.OpenToken := -1;
  AHeader.CloseToken := -1;
  mCurrent := AAfterName;
  Result := ReadParameterList(AText, ATokens, mCurrent, AHeader) and
    ReadResultType(AText, ATokens, mCurrent, AHeader);
  if not Result then
  begin
    Exit;
  end;
  // Prozedurale Typen: "of object" bzw. "reference to" gehören vor das ";".
  while (mCurrent >= 0) and (ATokens[mCurrent].IsKeyword('of') or SameText(ATokens[mCurrent].Text, 'object')) do
  begin
    mCurrent := NextToken(ATokens, mCurrent);
  end;
  if IsSymbolAt(ATokens, mCurrent, ';') then
  begin
    AHeader.EndToken := mCurrent;
    AHeader.LastToken := mCurrent;
    if ADirectives then
    begin
      ReadDirectives(AText, ATokens, AHeader);
    end;
  end
  else
  begin
    // Kopf ohne ";" am Ende eines prozeduralen Typs in einer Parameterliste o. Ä.
    Result := not ADirectives;
    if Result then
    begin
      AHeader.EndToken := PreviousToken(ATokens, mCurrent);
      AHeader.LastToken := AHeader.EndToken;
    end;
  end;
end;

/// <summary>Token vor einer generischen Typangabe, deren "&gt;" an AIndex steht (TFoo&lt;T&gt;.Bar).</summary>
function BeforeGenericType(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and not ATokens[Result].IsSymbol('<') do
  begin
    Dec(Result);
  end;
  Result := PreviousToken(ATokens, Result);
end;

/// <summary>Rückwärts vom Namen über "TFoo." bzw. "TAussen.TInnen." bis zum Token davor (dem Schlüsselwort);
/// -1, wenn die Kette kein Bezeichner ist.</summary>
function BeforeQualifier(const ATokens: TArray<TPascalToken>; ANameToken: Integer): Integer;
begin
  Result := PreviousToken(ATokens, ANameToken);
  while IsSymbolAt(ATokens, Result, '.') do
  begin
    Result := PreviousToken(ATokens, Result);
    if (Result >= 0) and ATokens[Result].IsSymbol('>') then
    begin
      Result := BeforeGenericType(ATokens, Result);
    end;
    if (Result < 0) or (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(-1);
    end;
    Result := PreviousToken(ATokens, Result);
  end;
end;

/// <summary>Ist AIndex das "class" von "class procedure", nicht das von "TFoo = class" oder "packed class" direkt
/// vor der ersten Methode?</summary>
function IsClassMethodPrefix(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  Result := (AIndex >= 0) and ATokens[AIndex].IsKeyword('class');
  if Result then
  begin
    mBefore := PreviousToken(ATokens, AIndex);
    Result := not IsSymbolAt(ATokens, mBefore, '=') and
      not ((mBefore >= 0) and SameText(ATokens[mBefore].Text, 'packed'));
  end;
end;

/// <summary>Token hinter generischen Argumenten bzw. Parametern ab AIndex ("&lt;…&gt;"), sonst AIndex; -1, wenn
/// die spitze Klammer offen bleibt.</summary>
function SkipGenericArguments(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  if IsSymbolAt(ATokens, Result, '<') then
  begin
    Result := Matching(ATokens, Result);
    if Result >= 0 then
    begin
      Result := NextToken(ATokens, Result);
    end;
  end;
end;

class function TChangeSignature.ReadHeader(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; out AHeader: TSignatureHeader): Boolean;
var
  mCurrent, mBefore: Integer;
begin
  AHeader := Default(TSignatureHeader);
  mCurrent := -1;
  if (ANameToken >= 0) and (ANameToken <= High(ATokens)) then
  begin
    mCurrent := BeforeQualifier(ATokens, ANameToken);
  end;
  if (mCurrent < 0) or not IsWord(ATokens[mCurrent], RoutineWords) then
  begin
    Exit(False);
  end;
  AHeader.NameToken := ANameToken;
  AHeader.Keyword := LowerCase(ATokens[mCurrent].Text);
  AHeader.StartToken := mCurrent;
  mBefore := PreviousToken(ATokens, mCurrent);
  if IsClassMethodPrefix(ATokens, mBefore) then
  begin
    AHeader.IsClass := True;
    AHeader.StartToken := mBefore;
  end;
  AHeader.QualifiedName := StringReplace(Collapse(SliceText(AText, ATokens, NextToken(ATokens, mCurrent),
    ANameToken)), ' ', '', [rfReplaceAll]);
  // Generische Methode Bar<T>(...): Bleibt die Klammer offen, scheitert ReadTail am fehlenden ";".
  Result := ReadTail(AText, ATokens, SkipGenericArguments(ATokens, NextToken(ATokens, ANameToken)), AHeader, True);
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

/// <summary>Steht der Name von AChanges[AIndex] schon weiter vorn in der Liste?</summary>
function NamedBefore(const AChanges: TArray<TParameterChange>; AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  for mOther := 0 to AIndex - 1 do
  begin
    if SameText(AChanges[mOther].Name, AChanges[AIndex].Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Fehler eines behaltenen Parameters; '' ohne. Merkt ihn in AUsed und einen Standardwert in
/// ASeenDefault.</summary>
function KeptProblem(const AOld: TArray<TSignatureParameter>; const AChange: TParameterChange;
  var AUsed: TArray<Boolean>; var ASeenDefault: Boolean): string;
begin
  Result := '';
  if AChange.Origin > High(AOld) then
  begin
    Result := Format('Der Parameter "%s" gehört nicht zur alten Signatur.', [AChange.Name]);
  end
  else if AUsed[AChange.Origin] then
  begin
    Result := Format('Der Parameter "%s" steht zweimal in der Liste.', [AOld[AChange.Origin].Name]);
  end
  else
  begin
    AUsed[AChange.Origin] := True;
    ASeenDefault := ASeenDefault or (AOld[AChange.Origin].DefaultValue <> '');
  end;
end;

/// <summary>Fehler eines neuen Parameters; '' ohne. Atlas erzeugt keine Standardwerte; hinter einem Parameter mit
/// Standardwert (ASeenDefault) ginge es nur mit einem.</summary>
function AddedProblem(const AChange: TParameterChange; ASeenDefault: Boolean): string;
begin
  Result := '';
  if Trim(AChange.TypeName) = '' then
  begin
    Result := Format('Für den neuen Parameter "%s" fehlt der Typ.', [AChange.Name]);
  end
  else if Trim(AChange.Value) = '' then
  begin
    Result := Format('Für den neuen Parameter "%s" fehlt der Wert, den die bisherigen Aufrufer übergeben.',
      [AChange.Name]);
  end
  else if ASeenDefault then
  begin
    Result := Format('Der neue Parameter "%s" stünde hinter einem Parameter mit Standardwert. Bitte weiter vorn ' +
      'einfügen.', [AChange.Name]);
  end;
end;

class function TChangeSignature.Validate(const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  mIndex: Integer;
  mUsed: TArray<Boolean>;
  mSeenDefault: Boolean;
begin
  Result := '';
  SetLength(mUsed, Length(AOld));
  mSeenDefault := False;
  mIndex := 0;
  while (Result = '') and (mIndex <= High(AChanges)) do
  begin
    if not IsIdentifier(AChanges[mIndex].Name) then
    begin
      Result := Format('"%s" ist kein gültiger Parametername.', [AChanges[mIndex].Name]);
    end
    else if NamedBefore(AChanges, mIndex) then
    begin
      Result := Format('Der Parameter "%s" steht zweimal in der Liste.', [AChanges[mIndex].Name]);
    end
    else if AChanges[mIndex].Origin >= 0 then
    begin
      Result := KeptProblem(AOld, AChanges[mIndex], mUsed, mSeenDefault);
    end
    else
    begin
      Result := AddedProblem(AChanges[mIndex], mSeenDefault);
    end;
    Inc(mIndex);
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
  mBefore: Integer;
begin
  mBefore := PreviousToken(ATokens, ANameToken);
  // Über "Self." bzw. "Liste." hinweg nach vorn schauen.
  while IsSymbolAt(ATokens, mBefore, '.') do
  begin
    mBefore := PreviousToken(ATokens, mBefore);
    if mBefore >= 0 then
    begin
      mBefore := PreviousToken(ATokens, mBefore);
    end;
  end;
  if (mBefore >= 0) and IsWord(ATokens[mBefore], ['read', 'write', 'stored', 'add', 'remove']) then
  begin
    Result := TSignatureUse.Accessor;
  end
  else if IsSymbolAt(ATokens, mBefore, '@') then
  begin
    Result := TSignatureUse.Pointer_;
  end
  else if IsSymbolAt(ATokens, SkipGenericArguments(ATokens, NextToken(ATokens, ANameToken)), '(') then
  begin
    Result := TSignatureUse.Call;
  end
  // Ohne Klammern: Aufruf nur, wenn die Routine ohne Argumente aufrufbar ist und nicht zugewiesen wird.
  else if AHasRequired or IsSymbolAt(ATokens, mBefore, ':=') then
  begin
    Result := TSignatureUse.Pointer_;
  end
  else
  begin
    Result := TSignatureUse.Call;
  end;
end;

/// <summary>Klammern eines Aufrufs hinter ANameToken (AOpen -1 ohne Klammern) und die alten Argumente; False, wenn
/// die Klammer offen bleibt.</summary>
function ReadCallArguments(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  out AOpen, AClose: Integer; out AArguments: TArray<string>): Boolean;
var
  mValue: string;
begin
  AArguments := nil;
  AClose := -1;
  AOpen := SkipGenericArguments(ATokens, NextToken(ATokens, ANameToken));
  if not IsSymbolAt(ATokens, AOpen, '(') then
  begin
    AOpen := -1;
    Exit(True);
  end;
  AClose := Matching(ATokens, AOpen);
  if AClose > NextToken(ATokens, AOpen) then
  begin
    for mValue in SplitTopLevel(SliceText(AText, ATokens, NextToken(ATokens, AOpen), PreviousToken(ATokens, AClose)),
      ',') do
    begin
      AArguments := AArguments + [Trim(mValue)];
    end;
  end;
  Result := AClose >= 0;
end;

/// <summary>Neues Argument für AChange.Changes[AIndex]: das alte Argument, bei neuen Parametern der Wert.
/// AOmitted: Das Argument war ausgelassen (Standardwert).</summary>
function NewArgument(const AChange: TCallChange; const AOldArguments: TArray<string>; AIndex: Integer;
  out AOmitted: Boolean): string;
var
  mOrigin: Integer;
begin
  mOrigin := AChange.Changes[AIndex].Origin;
  AOmitted := False;
  Result := '';
  if mOrigin < 0 then
  begin
    if AIndex <= High(AChange.Values) then
    begin
      Result := AChange.Values[AIndex];
    end;
    if Result = '' then
    begin
      Result := AChange.Changes[AIndex].Value;
    end;
  end
  else if mOrigin <= High(AOldArguments) then
  begin
    Result := AOldArguments[mOrigin];
  end
  else
  begin
    AOmitted := True;
    if mOrigin <= High(AChange.Old) then
    begin
      Result := AChange.Old[mOrigin].DefaultValue;
    end;
  end;
end;

/// <summary>Neue Argumente; ausgelassene Standardwerte am Ende bleiben ausgelassen.</summary>
function NewArguments(const AChange: TCallChange; const AOldArguments: TArray<string>): TArray<string>;
var
  mIndex, mLast: Integer;
  mOmitted: TArray<Boolean>;
begin
  SetLength(Result, Length(AChange.Changes));
  SetLength(mOmitted, Length(AChange.Changes));
  for mIndex := 0 to High(AChange.Changes) do
  begin
    Result[mIndex] := NewArgument(AChange, AOldArguments, mIndex, mOmitted[mIndex]);
  end;
  mLast := High(Result);
  while (mLast >= 0) and mOmitted[mLast] do
  begin
    Dec(mLast);
  end;
  SetLength(Result, mLast + 1);
end;

class function TChangeSignature.CallEdit(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; const AChange: TCallChange; out AEdit: TTextEdit): Boolean;
var
  mOpen, mClose: Integer;
  mOldArguments, mNewArguments: TArray<string>;
  mJoined: string;
begin
  AEdit := Default(TTextEdit);
  if not ReadCallArguments(AText, ATokens, ANameToken, mOpen, mClose, mOldArguments) then
  begin
    Exit(False);
  end;
  mNewArguments := NewArguments(AChange, mOldArguments);
  mJoined := string.Join(', ', mNewArguments);
  Result := not ((Length(mNewArguments) = Length(mOldArguments)) and (mJoined = string.Join(', ', mOldArguments))) and
    ((mOpen >= 0) or (mJoined <> ''));
  if not Result then
  begin
    Exit;
  end;
  if mOpen < 0 then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[ANameToken].EndPos),
      '(' + mJoined + ')');
  end
  else if mJoined = '' then
  begin
    // Foo() wird zu Foo.
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[mClose].EndPos), '');
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mOpen].StartPos, ATokens[mClose].EndPos),
      '(' + mJoined + ')');
  end;
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
