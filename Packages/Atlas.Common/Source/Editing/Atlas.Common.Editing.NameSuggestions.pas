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

/// <summary>Beendet AToken auf Klammerebene 0 einen Typ (";", "=", ":=", ",", absolute, read …)?</summary>
function EndsType(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsSymbol('=') or AToken.IsSymbol(':=') or AToken.IsSymbol(',') or
    IsWordIn(AToken, ['absolute', 'read', 'write', 'begin', 'end', 'var', 'const']);
end;

/// <summary>Öffnet AToken eine Klammer ("&lt;", "(", "[")?</summary>
function OpensBracket(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol('<') or AToken.IsSymbol('(') or AToken.IsSymbol('[');
end;

/// <summary>Klammerebene nach AToken; False, wenn der Typ vor AToken endet.</summary>
function TypeStep(const AToken: TPascalToken; var ADepth: Integer): Boolean;
begin
  Result := True;
  if OpensBracket(AToken) then
  begin
    Inc(ADepth);
  end
  else if AToken.IsSymbol('>') or AToken.IsSymbol(']') then
  begin
    Dec(ADepth);
  end
  else if AToken.IsSymbol('>>') then
  begin
    Dec(ADepth, 2);
  end
  else if AToken.IsSymbol(')') then
  begin
    Result := ADepth > 0;
    Dec(ADepth);
  end
  else if ADepth = 0 then
  begin
    Result := not EndsType(AToken);
  end;
  Result := Result and (ADepth >= 0);
end;

/// <summary>Typ ab ATokens[AFirst] bis vor ";", ")", "=", ":=" oder "absolute" außerhalb von Klammern.</summary>
function TypeTextFrom(const ATokens: TArray<TPascalToken>; AFirst: Integer): string;
var
  mIndex, mDepth: Integer;
  mToken: TPascalToken;
  mGlued: Boolean;
begin
  Result := '';
  mDepth := 0;
  mGlued := False;
  mIndex := AFirst;
  while (mIndex <= High(ATokens)) and TypeStep(ATokens[mIndex], mDepth) do
  begin
    mToken := ATokens[mIndex];
    // Leerzeichen vor Wörtern, außer direkt nach "<", "(", "[" und ".".
    if (Result <> '') and IsWord(mToken) and not mGlued then
    begin
      Result := Result + ' ';
    end;
    Result := Result + mToken.Text;
    mGlued := OpensBracket(mToken) or mToken.IsSymbol('.');
    mIndex := TRoutineBody.NextToken(ATokens, mIndex);
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

/// <summary>Was das Wort AToken über den Abschnitt sagt: True mit ASection 'var' bzw. 'type', True mit '' bei
/// einem anderen Schlüsselwort; False, wenn es nichts entscheidet (Name oder Teil eines Typs).</summary>
function SectionWord(const AToken: TPascalToken; out ASection: string): Boolean;
begin
  ASection := '';
  Result := True;
  if IsWordIn(AToken, ['var', 'threadvar']) then
  begin
    ASection := 'var';
  end
  else if IsWordIn(AToken, VisibilityWords) or IsWordIn(AToken, ['record', 'object']) then
  begin
    ASection := 'type';
  end
  else
  begin
    // Schlüsselwörter in Typen vorheriger Deklarationen (A: string; B: array of set of T).
    Result := (AToken.Kind = TPascalTokenKind.Keyword) and
      not IsWordIn(AToken, ['string', 'array', 'of', 'set', 'file', 'packed']);
  end;
end;

/// <summary>Abschnitt vor ATokens[AIndex] (über vorige Deklarationen zurück): 'var' für var und threadvar,
/// 'type' für den Rumpf einer Klasse oder eines Records (Sichtbarkeit, class, record), sonst ''. AAt ist das
/// Token, das den Abschnitt eröffnet.</summary>
function SectionBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AAt: Integer): string;
var
  mIndex, mDepth: Integer;
begin
  Result := '';
  AAt := -1;
  mDepth := 0;
  mIndex := AIndex;
  while mIndex >= 0 do
  begin
    if ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol('>') or ATokens[mIndex].IsSymbol(']') then
    begin
      Inc(mDepth);
    end
    else if OpensBracket(ATokens[mIndex]) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and IsWord(ATokens[mIndex]) then
    begin
      AAt := mIndex;
      if SectionWord(ATokens[mIndex], Result) then
      begin
        Exit;
      end;
    end;
    mIndex := TRoutineBody.PreviousToken(ATokens, mIndex);
  end;
end;

/// <summary>Name am Cursor (oder leere Stelle) in ASite eintragen; ANext und APrev sind die Token danach und
/// davor.</summary>
procedure LocateName(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition; var ASite: TNameSite;
  out ANext, APrev: Integer);
var
  mIndex: Integer;
begin
  // Erstes Token, das am Cursor oder dahinter endet.
  mIndex := 0;
  while (mIndex <= High(ATokens)) and (Compare(ATokens[mIndex].EndPos, APosition) < 0) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    (Compare(ATokens[mIndex].StartPos, APosition) <= 0) then
  begin
    ASite.NameRange := TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos);
    ASite.Typed := Copy(ATokens[mIndex].Text, 1, APosition.Character - ATokens[mIndex].StartPos.Character);
    ASite.Offset := ATokens[mIndex].Offset;
    ANext := TRoutineBody.NextToken(ATokens, mIndex);
    APrev := TRoutineBody.PreviousToken(ATokens, mIndex);
    Exit;
  end;
  ASite.NameRange := TTextRange.Create(APosition, APosition);
  ANext := mIndex;
  while (ANext <= High(ATokens)) and ((Compare(ATokens[ANext].StartPos, APosition) < 0) or
    (ATokens[ANext].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive])) do
  begin
    Inc(ANext);
  end;
  APrev := TRoutineBody.PreviousToken(ATokens, ANext);
  if ANext <= High(ATokens) then
  begin
    ASite.Offset := ATokens[ANext].Offset;
  end;
end;

/// <summary>Doppelpunkt hinter weiteren Namen der Liste (A, |, B: T) ab ANext; -1 ohne.</summary>
function ColonAfter(const ATokens: TArray<TPascalToken>; ANext: Integer): Integer;
begin
  Result := ANext;
  while (Result <= High(ATokens)) and ATokens[Result].IsSymbol(',') do
  begin
    Result := TRoutineBody.NextToken(ATokens, Result);
    if (Result > High(ATokens)) or (ATokens[Result].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit(-1);
    end;
    Result := TRoutineBody.NextToken(ATokens, Result);
  end;
  if (Result > High(ATokens)) or not ATokens[Result].IsSymbol(':') then
  begin
    Result := -1;
  end;
end;

/// <summary>Darf vor einem Namen stehen: Abschnitt, Trenner, Modifizierer oder Attribut?</summary>
function PrecedesName(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsSymbol(',') or AToken.IsSymbol('(') or AToken.IsSymbol(']') or
    IsWordIn(AToken, ['var', 'threadvar', 'const', 'out', 'constref', 'record', 'object']) or
    IsWordIn(AToken, VisibilityWords);
end;

/// <summary>Art der Deklaration nach dem Token APrev vor dem Namen; False, wenn es keine passende ist.</summary>
function ClassifySite(ATree: TSyntaxTree; const ATokens: TArray<TPascalToken>; APrev: Integer;
  var ASite: TNameSite): Boolean;
var
  mNode: TSyntaxNode;
  mSection: string;
  mAt: Integer;
begin
  Result := True;
  if InParameters(ATokens, APrev) then
  begin
    ASite.Kind := TNamingKind.Parameter;
    Exit;
  end;
  if ATokens[APrev].IsKeyword('var') and (Enclosing(NodeAt(ATree.Root, ASite.Offset),
    [TSyntaxKind.Block .. TSyntaxKind.EmptyStatement]) <> nil) then
  begin
    // Inline-Variable in einer Anweisung.
    ASite.Kind := TNamingKind.Local;
    Exit;
  end;
  mSection := '';
  if not IsWordIn(ATokens[APrev], ['const', 'out', 'constref']) then
  begin
    mSection := SectionBefore(ATokens, APrev, mAt);
  end;
  if mSection = '' then
  begin
    Exit(False);
  end;
  // Der Abschnitt steht auch bei unfertigem Code an seinem Platz im Baum.
  mNode := NodeAt(ATree.Root, ATokens[mAt].Offset);
  if (mSection = 'type') or (Enclosing(mNode, [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
    TSyntaxKind.RecordType, TSyntaxKind.HelperType]) <> nil) then
  begin
    ASite.Kind := TNamingKind.Field;
  end
  else if Enclosing(mNode, [TSyntaxKind.RoutineDecl]) <> nil then
  begin
    ASite.Kind := TNamingKind.Local;
  end
  else
  begin
    ASite.Global := True;
  end;
end;

class function TNameSuggestions.Site(ATree: TSyntaxTree; const APosition: TTextPosition;
  out ASite: TNameSite): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mNext, mPrev, mColon: Integer;
begin
  ASite := Default(TNameSite);
  Result := False;
  if ATree = nil then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  LocateName(mTokens, APosition, ASite, mNext, mPrev);
  mColon := ColonAfter(mTokens, mNext);
  if (mColon < 0) or (mPrev < 0) then
  begin
    Exit;
  end;
  ASite.TypeText := TypeTextFrom(mTokens, TRoutineBody.NextToken(mTokens, mColon));
  if (ASite.TypeText = '') or not PrecedesName(mTokens[mPrev]) then
  begin
    Exit;
  end;
  Result := ClassifySite(ATree, mTokens, mPrev, ASite);
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
