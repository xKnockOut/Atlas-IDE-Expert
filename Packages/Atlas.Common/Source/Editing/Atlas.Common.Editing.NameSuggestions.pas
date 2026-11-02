unit Atlas.Common.Editing.NameSuggestions;

// Namensvorschläge für Variablen (#452, ARG-054), Teil ohne Namensauflösung:
//   - Site: Namensposition einer Deklaration, deren Typ rechts vom Caret
//     schon dasteht ("|: TCustomerList;", auch mit angefangenem Namen):
//     var-Abschnitt (lokal oder global), Inline-var, Feld in Klasse oder
//     Record (auch nach private … und in class var) und Parameter.
//   - Bases: Namen aus dem Typ ohne T/I-Präfix und Unit: Mehrzahl bei Listen-
//     und Array-Typen (Customers), vollständig (CustomerList) und letzter
//     Wortteil (List); reservierte Wörter (Array, Set) entfallen.
//   - Präfix F, A bzw. L nur, wenn mindestens 60 % der Deklarationen dieser
//     Art im Projekt es tragen (UsesPrefix) oder die Projektdatei es vorgibt;
//     vergebene Namen bekommen eine Ziffer (Unique).
// Vergebene Namen und die Zählung des Projekts bringt
// Atlas.Common.Lsp.Completion über Namensauflösung und Index mit.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TNameSite = record
    /// <summary>Art der Deklaration; bei Global ohne Bedeutung.</summary>
    Kind: TNamingKind;
    /// <summary>Globale Variable (Unit-Ebene): nie mit Präfix.</summary>
    Global: Boolean;
    /// <summary>Bereich des schon getippten Namens; leer am Cursor, wenn noch nichts dasteht.</summary>
    NameRange: TTextRange;
    /// <summary>Getippter Name bis zum Cursor.</summary>
    Typed: string;
    /// <summary>Typ rechts vom Caret, wie er dasteht: "TCustomerList", "TList&lt;TCustomer&gt;", "array of TCustomer".
    /// </summary>
    TypeText: string;
    /// <summary>Offset des Namens im Text (für den Gültigkeitsbereich).</summary>
    Offset: Integer;
  end;

  TNameSuggestions = class
  public const
    /// <summary>Mindestanteil in Prozent der Deklarationen mit Präfix, ab dem das Präfix gilt.</summary>
    PrefixShare = 60;
  public
    /// <summary>Namensposition am Cursor (siehe Kopf); False ohne Deklaration mit bekanntem Typ.</summary>
    class function Site(ATree: TSyntaxTree; const APosition: TTextPosition; out ASite: TNameSite): Boolean; static;
    /// <summary>Listen- oder Array-Typ: array of, TArray&lt;T&gt;, TList&lt;T&gt; und Namen auf List, Array,
    /// Collection, Queue, Stack, Set.</summary>
    class function IsListType(const ATypeText: string): Boolean; static;
    /// <summary>Namen ohne Präfix in dieser Reihenfolge: Mehrzahl (nur Listen), vollständig, letzter Wortteil.
    /// </summary>
    class function Bases(const ATypeText: string): TArray<string>; static;
    /// <summary>Englische Mehrzahl: Category → Categories, Box → Boxes, Customer → Customers.</summary>
    class function Plural(const AWord: string): string; static;
    /// <summary>Letzter Wortteil nach Großbuchstaben: CustomerList → List, HTTPClient → Client.</summary>
    class function LastWord(const AName: string): string; static;
    /// <summary>Tragen mindestens PrefixShare % der gezählten Deklarationen das Präfix?</summary>
    class function UsesPrefix(const ACount: TNamingCount): Boolean; static;
    /// <summary>AName mit APrefix davor, wenn er es noch nicht trägt; APrefix = '' lässt AName.</summary>
    class function Prefixed(const AName, APrefix: string): string; static;
    /// <summary>AName oder mit Ziffer (Name2, Name3 …), wenn er in ATaken steht (ohne Groß-/Kleinschreibung).
    /// </summary>
    class function Unique(const AName: string; const ATaken: TArray<string>): string; static;
    /// <summary>Vorschläge für ATypeText mit APrefix, eindeutig gegenüber ATaken und untereinander.</summary>
    class function Suggest(const ATypeText, APrefix: string; const ATaken: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.CreateMethod;

type
  TSyntaxKindSet = set of TSyntaxKind;

const
  ListWords: array[0..5] of string = ('List', 'Array', 'Collection', 'Queue', 'Stack', 'Set');
  VisibilityWords: array[0..6] of string = ('private', 'protected', 'public', 'published', 'strict', 'automated',
    'class');
  RoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');

function Compare(const A, B: TTextPosition): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Character - B.Character;
  end;
end;

function IsWord(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword];
end;

function IsWordIn(const AToken: TPascalToken; const AWords: array of string): Boolean;
begin
  Result := IsWord(AToken) and MatchText(AToken.Text, AWords);
end;

/// <summary>Typ ab ATokens[AFirst] bis vor ";", ")", "=", ":=" oder "absolute" außerhalb von Klammern.</summary>
function TypeTextFrom(const ATokens: TArray<TPascalToken>; AFirst: Integer): string;
var
  Index, Depth: Integer;
  Token: TPascalToken;
  Glued: Boolean;
begin
  Result := '';
  Depth := 0;
  Glued := False;
  Index := AFirst;
  while Index <= High(ATokens) do
  begin
    Token := ATokens[Index];
    if Token.IsSymbol('<') or Token.IsSymbol('(') or Token.IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if Token.IsSymbol('>') or Token.IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if Token.IsSymbol('>>') then
    begin
      Dec(Depth, 2);
    end
    else if Token.IsSymbol(')') then
    begin
      if Depth = 0 then
      begin
        Break;
      end;
      Dec(Depth);
    end
    else if (Depth = 0) and (Token.IsSymbol(';') or Token.IsSymbol('=') or Token.IsSymbol(':=') or
      Token.IsSymbol(',') or IsWordIn(Token, ['absolute', 'read', 'write', 'begin', 'end', 'var', 'const'])) then
    begin
      Break;
    end;
    if Depth < 0 then
    begin
      Break;
    end;
    // Leerzeichen vor Wörtern, außer direkt nach "<", "(", "[" und ".".
    if (Result <> '') and IsWord(Token) and not Glued then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Token.Text;
    Glued := Token.IsSymbol('<') or Token.IsSymbol('(') or Token.IsSymbol('[') or Token.IsSymbol('.');
    Index := TRoutineBody.NextToken(ATokens, Index);
  end;
end;

/// <summary>Innerster Knoten, der AOffset enthält; nil außerhalb.</summary>
function NodeAt(ARoot: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Found: Boolean;
begin
  Result := ARoot;
  if Result = nil then
  begin
    Exit;
  end;
  repeat
    Found := False;
    for Index := 0 to Result.ChildCount - 1 do
    begin
      if (Result[Index].StartOffset <= AOffset) and (AOffset <= Result[Index].EndOffset) then
      begin
        Result := Result[Index];
        Found := True;
        Break;
      end;
    end;
  until not Found;
end;

/// <summary>Nächster umgebender Knoten einer der Arten AKinds; nil ohne.</summary>
function Enclosing(ANode: TSyntaxNode; const AKinds: TSyntaxKindSet): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and not (Result.Kind in AKinds) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Steht ATokens[AIndex] in der Parameterliste eines Routinenkopfs?</summary>
function InParameters(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index, Depth: Integer;
begin
  Result := False;
  Depth := 0;
  Index := AIndex;
  while Index >= 0 do
  begin
    if ATokens[Index].IsSymbol(')') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol('(') then
    begin
      if Depth = 0 then
      begin
        Break;
      end;
      Dec(Depth);
    end
    else if IsWordIn(ATokens[Index], ['begin', 'end', 'type', 'implementation', 'interface', 'uses']) then
    begin
      Exit;
    end;
    Index := TRoutineBody.PreviousToken(ATokens, Index);
  end;
  if Index < 0 then
  begin
    Exit;
  end;
  // Name der Routine, auch qualifiziert (TFoo.Bar), davor das Schlüsselwort.
  Index := TRoutineBody.PreviousToken(ATokens, Index);
  while (Index >= 0) and (ATokens[Index].Kind = TPascalTokenKind.Identifier) do
  begin
    Index := TRoutineBody.PreviousToken(ATokens, Index);
    if (Index >= 0) and ATokens[Index].IsSymbol('.') then
    begin
      Index := TRoutineBody.PreviousToken(ATokens, Index);
    end
    else
    begin
      Break;
    end;
  end;
  Result := (Index >= 0) and IsWordIn(ATokens[Index], RoutineWords);
end;

/// <summary>Abschnitt vor ATokens[AIndex] (über vorige Deklarationen zurück): 'var' für var und threadvar,
/// 'type' für den Rumpf einer Klasse oder eines Records (Sichtbarkeit, class, record), sonst ''. AAt ist das
/// Token, das den Abschnitt eröffnet.</summary>
function SectionBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AAt: Integer): string;
var
  Index, Depth: Integer;
begin
  Result := '';
  AAt := -1;
  Depth := 0;
  Index := AIndex;
  while Index >= 0 do
  begin
    if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol('>') or ATokens[Index].IsSymbol(']') then
    begin
      Inc(Depth);
    end
    else if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('<') or ATokens[Index].IsSymbol('[') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and IsWord(ATokens[Index]) then
    begin
      AAt := Index;
      if IsWordIn(ATokens[Index], ['var', 'threadvar']) then
      begin
        Exit('var');
      end;
      if IsWordIn(ATokens[Index], VisibilityWords) or IsWordIn(ATokens[Index], ['record', 'object']) then
      begin
        Exit('type');
      end;
      // Schlüsselwörter in Typen vorheriger Deklarationen (A: string; B: array of set of T).
      if (ATokens[Index].Kind = TPascalTokenKind.Keyword) and
        not IsWordIn(ATokens[Index], ['string', 'array', 'of', 'set', 'file', 'packed']) then
      begin
        Exit;
      end;
    end;
    Index := TRoutineBody.PreviousToken(ATokens, Index);
  end;
end;

class function TNameSuggestions.Site(ATree: TSyntaxTree; const APosition: TTextPosition;
  out ASite: TNameSite): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Name, Next, Prev, Colon: Integer;
  Node: TSyntaxNode;
  Section: string;
  At: Integer;
begin
  ASite := Default(TNameSite);
  Result := False;
  if ATree = nil then
  begin
    Exit;
  end;
  Tokens := ATree.Tokens;
  // Erstes Token, das am Cursor oder dahinter endet.
  Index := 0;
  while (Index <= High(Tokens)) and (Compare(Tokens[Index].EndPos, APosition) < 0) do
  begin
    Inc(Index);
  end;
  Name := -1;
  if (Index <= High(Tokens)) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
    (Compare(Tokens[Index].StartPos, APosition) <= 0) then
  begin
    Name := Index;
  end;
  if Name >= 0 then
  begin
    ASite.NameRange := TTextRange.Create(Tokens[Name].StartPos, Tokens[Name].EndPos);
    ASite.Typed := Copy(Tokens[Name].Text, 1, APosition.Character - Tokens[Name].StartPos.Character);
    ASite.Offset := Tokens[Name].Offset;
    Next := TRoutineBody.NextToken(Tokens, Name);
    Prev := TRoutineBody.PreviousToken(Tokens, Name);
  end
  else
  begin
    ASite.NameRange := TTextRange.Create(APosition, APosition);
    Next := Index;
    while (Next <= High(Tokens)) and ((Compare(Tokens[Next].StartPos, APosition) < 0) or
      (Tokens[Next].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive])) do
    begin
      Inc(Next);
    end;
    Prev := TRoutineBody.PreviousToken(Tokens, Next);
    if Next <= High(Tokens) then
    begin
      ASite.Offset := Tokens[Next].Offset;
    end;
  end;
  // Weitere Namen der Liste (A, |, B: T) bis zum Doppelpunkt.
  Colon := Next;
  while (Colon <= High(Tokens)) and Tokens[Colon].IsSymbol(',') do
  begin
    Colon := TRoutineBody.NextToken(Tokens, Colon);
    if (Colon > High(Tokens)) or (Tokens[Colon].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    Colon := TRoutineBody.NextToken(Tokens, Colon);
  end;
  if (Colon > High(Tokens)) or not Tokens[Colon].IsSymbol(':') or (Prev < 0) then
  begin
    Exit;
  end;
  ASite.TypeText := TypeTextFrom(Tokens, TRoutineBody.NextToken(Tokens, Colon));
  if ASite.TypeText = '' then
  begin
    Exit;
  end;
  // Vor dem Namen: Abschnitt, Trenner, Modifizierer oder Attribut.
  if not (Tokens[Prev].IsSymbol(';') or Tokens[Prev].IsSymbol(',') or Tokens[Prev].IsSymbol('(') or
    Tokens[Prev].IsSymbol(']') or IsWordIn(Tokens[Prev], ['var', 'threadvar', 'const', 'out', 'constref']) or
    IsWordIn(Tokens[Prev], VisibilityWords) or IsWordIn(Tokens[Prev], ['record', 'object'])) then
  begin
    Exit;
  end;
  if InParameters(Tokens, Prev) then
  begin
    ASite.Kind := TNamingKind.Parameter;
    Exit(True);
  end;
  Node := NodeAt(ATree.Root, ASite.Offset);
  if Tokens[Prev].IsKeyword('var') and (Enclosing(Node, [TSyntaxKind.Block .. TSyntaxKind.EmptyStatement]) <> nil) then
  begin
    // Inline-Variable in einer Anweisung.
    ASite.Kind := TNamingKind.Local;
    Exit(True);
  end;
  if Tokens[Prev].IsKeyword('const') or IsWordIn(Tokens[Prev], ['out', 'constref']) then
  begin
    Exit;
  end;
  Section := SectionBefore(Tokens, Prev, At);
  if Section = '' then
  begin
    Exit;
  end;
  // Der Abschnitt steht auch bei unfertigem Code an seinem Platz im Baum.
  Node := NodeAt(ATree.Root, Tokens[At].Offset);
  if (Section = 'type') or (Enclosing(Node, [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.HelperType]) <> nil) then
  begin
    ASite.Kind := TNamingKind.Field;
  end
  else if Enclosing(Node, [TSyntaxKind.RoutineDecl]) <> nil then
  begin
    ASite.Kind := TNamingKind.Local;
  end
  else
  begin
    ASite.Global := True;
  end;
  Result := True;
end;

class function TNameSuggestions.LastWord(const AName: string): string;
var
  Index: Integer;
begin
  Index := Length(AName);
  // Endet der Name groß (FileIO), gilt die ganze Folge von Großbuchstaben.
  if (Index > 0) and CharInSet(AName[Index], ['A'..'Z']) then
  begin
    while (Index > 1) and CharInSet(AName[Index - 1], ['A'..'Z']) do
    begin
      Dec(Index);
    end;
    Exit(Copy(AName, Index, MaxInt));
  end;
  // HTTPClient: das Wort beginnt am letzten Großbuchstaben vor Kleinbuchstaben.
  while (Index > 1) and not (CharInSet(AName[Index], ['A'..'Z']) and
    ((Index = Length(AName)) or not CharInSet(AName[Index + 1], ['A'..'Z']))) do
  begin
    Dec(Index);
  end;
  Result := Copy(AName, Index, MaxInt);
end;

class function TNameSuggestions.Plural(const AWord: string): string;
var
  Last: Char;
begin
  Result := AWord;
  if AWord = '' then
  begin
    Exit;
  end;
  Last := AWord[Length(AWord)];
  if (Last = 'y') and (Length(AWord) > 1) and not CharInSet(AWord[Length(AWord) - 1], ['a', 'e', 'i', 'o', 'u']) then
  begin
    Result := Copy(AWord, 1, Length(AWord) - 1) + 'ies';
  end
  else if CharInSet(Last, ['s', 'x', 'z']) or EndsStr('ch', AWord) or EndsStr('sh', AWord) then
  begin
    Result := AWord + 'es';
  end
  else
  begin
    Result := AWord + 's';
  end;
end;

/// <summary>Elementtyp eines Listen- oder Array-Typs ('' ohne): array of T, TArray&lt;T&gt;, TList&lt;T&gt;.</summary>
function ElementType(const ATypeText: string; out AContainer: string): string;
var
  Open, Close: Integer;
begin
  Result := '';
  AContainer := '';
  if StartsText('array', ATypeText) and (Pos(' of ', LowerCase(ATypeText)) > 0) then
  begin
    AContainer := 'Array';
    Exit(Trim(Copy(ATypeText, Pos(' of ', LowerCase(ATypeText)) + 4, MaxInt)));
  end;
  Open := Pos('<', ATypeText);
  Close := LastDelimiter('>', ATypeText);
  if (Open = 0) or (Close < Open) then
  begin
    Exit;
  end;
  AContainer := TCreateMethod.NameFromType(Copy(ATypeText, 1, Open - 1));
  if not MatchText(TNameSuggestions.LastWord(AContainer), ListWords) then
  begin
    Exit;
  end;
  Result := Trim(Copy(ATypeText, Open + 1, Close - Open - 1));
  // Nur ein Typargument (TDictionary<K, V> ist keine Liste).
  if Pos(',', Result) > 0 then
  begin
    Result := '';
  end;
end;

class function TNameSuggestions.IsListType(const ATypeText: string): Boolean;
var
  Container, Base: string;
begin
  if ElementType(ATypeText, Container) <> '' then
  begin
    Exit(True);
  end;
  Base := TCreateMethod.NameFromType(ATypeText);
  Result := (Pos('<', ATypeText) = 0) and MatchText(LastWord(Base), ListWords) and (LastWord(Base) <> Base);
end;

class function TNameSuggestions.Bases(const ATypeText: string): TArray<string>;
var
  Names: TArray<string>;
  Container, Element, Base, Item: string;

  procedure Add(const AName: string);
  var
    Known: string;
  begin
    if (AName = '') or not CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_']) or TPascalLexer.IsReservedWord(AName) then
    begin
      Exit;
    end;
    for Known in Names do
    begin
      if SameText(Known, AName) then
      begin
        Exit;
      end;
    end;
    Names := Names + [AName];
  end;

begin
  Names := nil;
  Element := ElementType(ATypeText, Container);
  if Element <> '' then
  begin
    Element := TCreateMethod.NameFromType(Element);
    Add(Plural(Element));
    Add(Element + LastWord(Container));
    Add(LastWord(Container));
  end
  else
  begin
    Base := TCreateMethod.NameFromType(ATypeText);
    if IsListType(ATypeText) then
    begin
      Add(Plural(Copy(Base, 1, Length(Base) - Length(LastWord(Base)))));
    end;
    Add(Base);
    Add(LastWord(Base));
  end;
  Result := nil;
  for Item in Names do
  begin
    Result := Result + [Item];
  end;
end;

class function TNameSuggestions.UsesPrefix(const ACount: TNamingCount): Boolean;
begin
  Result := (ACount.Total > 0) and (ACount.Prefixed * 100 >= ACount.Total * PrefixShare);
end;

class function TNameSuggestions.Prefixed(const AName, APrefix: string): string;
begin
  Result := AName;
  if (APrefix = '') or (AName = '') or TIndexExtractor.HasNamePrefix(AName, APrefix) then
  begin
    Exit;
  end;
  Result := APrefix + UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
end;

class function TNameSuggestions.Unique(const AName: string; const ATaken: TArray<string>): string;
var
  Number: Integer;
  Taken: Boolean;
  Known: string;
begin
  Result := AName;
  Number := 1;
  repeat
    Taken := False;
    for Known in ATaken do
    begin
      if SameText(Known, Result) then
      begin
        Taken := True;
      end;
    end;
    if Taken then
    begin
      Inc(Number);
      Result := AName + IntToStr(Number);
    end;
  until not Taken;
end;

class function TNameSuggestions.Suggest(const ATypeText, APrefix: string;
  const ATaken: TArray<string>): TArray<string>;
var
  Base, Name: string;
  Taken: TArray<string>;
begin
  Result := nil;
  Taken := ATaken;
  for Base in Bases(ATypeText) do
  begin
    Name := Unique(Prefixed(Base, APrefix), Taken);
    Result := Result + [Name];
    Taken := Taken + [Name];
  end;
end;

end.
