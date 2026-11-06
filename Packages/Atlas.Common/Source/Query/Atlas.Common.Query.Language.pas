unit Atlas.Common.Query.Language;

// Lexer und Parser der Abfragesprache (#1351), bewusst klein und kein SQL:
//
//   abfrage    = menge [where ausdruck] [order by feld [asc|desc]] [limit zahl]
//   ausdruck   = glied {or glied}
//   glied      = faktor {and faktor}
//   faktor     = not faktor | "(" ausdruck ")" | prädikat | vergleich
//   prädikat   = inherits wert | implements wert | uses wert | calls wert
//              | has attribute wert
//   vergleich  = feld ("=" | "<>" | "<" | ">" | "<=" | ">=") wert
//              | feld [not] like wert
//   wert       = zahl | 'text' | "text" | name | true | false
//
// Schlüsselwörter ohne Groß-/Kleinschreibung. Namen dürfen Punkte, * und ?
// enthalten (Vcl.Forms, Get*). "uses" ist bei Units auch ein Feld: Folgt ein
// Vergleich, ist es das Feld, sonst das Prädikat.
//
// Der Parser prüft gegen den Katalog: Menge, Felder je Menge, Art des Werts
// und Prädikate je Menge. Fehler kommen als EQueryError mit Spalte (ab 1)
// und, wo möglich, einem Vorschlag („meintest du methods?“).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Catalog;

{$SCOPEDENUMS ON}

type
  EQueryError = class(Exception)
  private
    FColumn: Integer;
    FSuggestion: string;
  public
    constructor Create(const AMessage: string; AColumn: Integer; const ASuggestion: string);
    /// <summary>Spalte in der Abfrage ab 1.</summary>
    property Column: Integer read FColumn;
    property Suggestion: string read FSuggestion;
  end;

  TQueryTokenKind = (Name, Number, Text, Symbol, OpenParen, CloseParen, EndOfQuery);

  TQueryToken = record
    Kind: TQueryTokenKind;
    Text: string;
    /// <summary>Spalte ab 1.</summary>
    Column: Integer;
    /// <summary>Name, der ein Schlüsselwort ist (ohne Groß-/Kleinschreibung)?</summary>
    function Is_(const AKeyword: string): Boolean;
  end;

  TQueryOperator = (Equal, NotEqual, Less, Greater, LessEqual, GreaterEqual, Like, NotLike);

  TQueryLogic = (And_, Or_);

  /// <summary>Knoten der Bedingung.</summary>
  TQueryNode = class
  public
    Column: Integer;
  end;

  /// <summary>Verknüpfung mehrerer Glieder mit and bzw. or.</summary>
  TQueryLogicNode = class(TQueryNode)
  private
    FItems: TObjectList<TQueryNode>;
  public
    Logic: TQueryLogic;
    constructor Create(ALogic: TQueryLogic);
    destructor Destroy; override;
    property Items: TObjectList<TQueryNode> read FItems;
  end;

  TQueryNotNode = class(TQueryNode)
  public
    Inner: TQueryNode;
    destructor Destroy; override;
  end;

  TQueryCompareNode = class(TQueryNode)
  public
    Field: TQueryFieldInfo;
    Comparison: TQueryOperator;
    Value: TQueryValue;
  end;

  TQueryPredicateNode = class(TQueryNode)
  public
    Kind: TQueryPredicateKind;
    Argument: string;
  end;

  /// <summary>Eine geparste Abfrage. Besitzt die Bedingung.</summary>
  TQueryAst = class
  public
    Text: string;
    Entity: TQueryEntity;
    /// <summary>nil = alle Elemente der Menge.</summary>
    Condition: TQueryNode;
    HasOrder: Boolean;
    OrderField: TQueryFieldInfo;
    Descending: Boolean;
    /// <summary>-1 = ohne limit.</summary>
    Limit: Integer;
    destructor Destroy; override;
    /// <summary>Felder aus Bedingung und Sortierung, ohne Doppelte, in Reihenfolge des Auftretens.</summary>
    function UsedFields: TArray<string>;
  end;

  TQueryLexer = class
  public
    /// <summary>Token der Abfrage samt EndOfQuery; EQueryError bei offenem Text oder unbekanntem Zeichen.</summary>
    class function Tokenize(const AText: string): TArray<TQueryToken>; static;
  end;

  TQueryParser = class
  private
    FTokens: TArray<TQueryToken>;
    FPosition: Integer;
    FEntity: TQueryEntity;
    function Current: TQueryToken;
    function Next: TQueryToken;
    procedure Fail(const AMessage: string; AColumn: Integer); overload;
    procedure Fail(const AMessage: string; AColumn: Integer; const ASuggestion: string); overload;
    function ParseExpression: TQueryNode;
    function ParseTerm: TQueryNode;
    function ParseFactor: TQueryNode;
    function ParsePredicate(AKind: TQueryPredicateKind; AColumn: Integer): TQueryNode;
    function ParseComparison: TQueryNode;
    function ParseValue(const AField: TQueryFieldInfo; ALike: Boolean): TQueryValue;
    function FieldFor(const AToken: TQueryToken): TQueryFieldInfo;
    function IsComparisonStart(const AToken: TQueryToken): Boolean;
    function ParseNot: TQueryNode;
    function ParseGroup: TQueryNode;
    /// <summary>Beginnt mit AToken ein Prädikat (inherits, implements, calls, has attribute, uses)?</summary>
    function IsPredicateStart(const AToken: TQueryToken; out AKind: TQueryPredicateKind): Boolean;
    function ParseKeywordPredicate(AKind: TQueryPredicateKind): TQueryNode;
    function ParseEntity: TQueryEntity;
    procedure ParseOrder(AAst: TQueryAst);
    procedure ParseLimit(AAst: TQueryAst);
    /// <summary>Meldet, was nach der Abfrage noch steht.</summary>
    procedure CheckEnd(AAst: TQueryAst);
  public
    /// <summary>Parst und prüft AText; EQueryError mit Spalte und Vorschlag. Der Aufrufer gibt das Ergebnis frei.
    /// </summary>
    class function Parse(const AText: string): TQueryAst; static;
    /// <summary>Wie Parse, liefert aber False mit Meldung, Spalte und Vorschlag statt einer Ausnahme.</summary>
    class function TryParse(const AText: string; out AAst: TQueryAst; out AError: string; out AColumn: Integer;
      out ASuggestion: string): Boolean; static;
    /// <summary>Fehlertext mit Vorschlag: "Unbekanntes Feld `methode`, meintest du `methods`?".</summary>
    class function UnknownText(const AWhat, AName, ASuggestion: string): string; static;
    /// <summary>Fehler der gespeicherten Abfragen (queries in atlas.json) an der Stelle in der Datei; leer, wenn
    /// alle parsen.</summary>
    class function ConfigurationIssues(const AQueries: TArray<TSavedQuery>): TArray<TConfigurationIssue>; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Fuzzy,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLanguageText = (TextWithoutClosingQuotationMark, IsNotANumber, DoesNotExistForNegation, EndOfTheQuery,
    ExpectedFieldPredicateNotOr, FieldDoesNotExistFor, ExpectedValueAfterFound, LikeOnlyExistsForText, IsANumberIsNot,
    IsATruthValueTrue, ExpectedComparisonOrLikeAfter, IsATruthValueAllowed, DoesNotExistFor, ExpectedNameAfterFound,
    ExpectedForInColumnFound, ExpectedAttributeAfterHasFound, ExpectedSetFound, ExpectedByAfterOrderFound,
    ExpectedCountAfterLimitFound, ExpectedWhereOrderByOr, UnexpectedConditionsAreJoinedWith, UnknownField, FieldsOf,
    QueryColumn, UnexpectedCharacter, DidYouMean, UnknownSet, EmptyQueryExampleClassesWhere);

const
  cTexts: array[TLanguageText] of TAtlasText = (
    (De: 'Text ohne schließendes Anführungszeichen'; En: 'Text without closing quotation mark'),
    (De: '"%s…" ist keine Zahl'; En: '"%s…" is not a number'),
    (De: '"!" gibt es nicht; für Verneinung "not", für ungleich "<>"';
     En: '"!" does not exist; for negation use "not", for unequal "<>"'),
    (De: 'Ende der Abfrage'; En: 'End of the query'),
    (De: 'Erwartet: Feld, Prädikat, not oder "(", gefunden %s';
     En: 'Expected: field, predicate, not or "(", found %s'),
    (De: 'Feld `%s` gibt es bei `%s` nicht; Felder: %s'; En: 'Field `%s` does not exist for `%s`; fields: %s'),
    (De: 'Erwartet: Wert nach `%s`, gefunden %s'; En: 'Expected: value after `%s`, found %s'),
    (De: 'like gibt es nur für Textfelder; `%s` ist %s'; En: 'like only exists for text fields; `%s` is %s'),
    (De: '`%s` ist eine Zahl; %s ist keine'; En: '`%s` is a number; %s is not'),
    (De: '`%s` ist ein Wahrheitswert (true oder false); %s ist keiner';
     En: '`%s` is a truth value (true or false); %s is not'),
    (De: 'Erwartet: Vergleich (=, <>, <, >, <=, >=) oder like nach `%s`, gefunden %s';
     En: 'Expected: comparison (=, <>, <, >, <=, >=) or like after `%s`, found %s'),
    (De: '`%s` ist ein Wahrheitswert; erlaubt sind = und <>'; En: '`%s` is a truth value; allowed are = and <>'),
    (De: '`%s` gibt es bei `%s` nicht'; En: '`%s` does not exist for `%s`'),
    (De: 'Erwartet: Name nach `%s`, gefunden %s'; En: 'Expected: name after `%s`, found %s'),
    (De: 'Erwartet: ")" zu "(" in Spalte %d, gefunden %s'; En: 'Expected: ")" for "(" in column %d, found %s'),
    (De: 'Erwartet: `attribute` nach `has`, gefunden %s'; En: 'Expected: `attribute` after `has`, found %s'),
    (De: 'Erwartet: Menge (%s), gefunden %s'; En: 'Expected: set (%s), found %s'),
    (De: 'Erwartet: `by` nach `order`, gefunden %s'; En: 'Expected: `by` after `order`, found %s'),
    (De: 'Erwartet: Anzahl nach `limit`, gefunden %s'; En: 'Expected: count after `limit`, found %s'),
    (De: 'Erwartet: where, order by oder limit, gefunden %s'; En: 'Expected: where, order by or limit, found %s'),
    (De: 'Unerwartet: %s; Bedingungen verbinden and und or';
     En: 'Unexpected: %s; conditions are joined with and and or'),
    (De: 'Unbekanntes Feld'; En: 'Unknown field'),
    (De: '%s; Felder von %s: %s'; En: '%s; fields of %s: %s'),
    (De: 'Abfrage "%s", Spalte %d: %s'; En: 'Query "%s", column %d: %s'),
    (De: 'Unerwartetes Zeichen "%s"'; En: 'Unexpected character "%s"'),
    (De: '%s `%s`, meintest du `%s`?'; En: '%s `%s`, did you mean `%s`?'),
    (De: 'Unbekannte Menge'; En: 'Unknown set'),
    (De: 'Leere Abfrage; Beispiel: classes where methods > 40';
     En: 'Empty query; example: classes where methods > 40'));

const
  cOperatorChars = ['=', '<', '>', '!'];

{ EQueryError }

constructor EQueryError.Create(const AMessage: string; AColumn: Integer; const ASuggestion: string);
begin
  inherited Create(AMessage);
  FColumn := AColumn;
  FSuggestion := ASuggestion;
end;

{ TQueryToken }

function TQueryToken.Is_(const AKeyword: string): Boolean;
begin
  Result := (Kind = TQueryTokenKind.Name) and SameText(Text, AKeyword);
end;

{ TQueryLogicNode }

constructor TQueryLogicNode.Create(ALogic: TQueryLogic);
begin
  inherited Create;
  Logic := ALogic;
  FItems := TObjectList<TQueryNode>.Create(True);
end;

destructor TQueryLogicNode.Destroy;
begin
  FItems.Free;
  inherited;
end;

{ TQueryNotNode }

destructor TQueryNotNode.Destroy;
begin
  Inner.Free;
  inherited;
end;

{ TQueryAst }

destructor TQueryAst.Destroy;
begin
  Condition.Free;
  inherited;
end;

procedure CollectFields(ANode: TQueryNode; AList: TList<string>);
var
  mItem: TQueryNode;
  mName: string;
begin
  if ANode is TQueryLogicNode then
  begin
    for mItem in TQueryLogicNode(ANode).Items do
    begin
      CollectFields(mItem, AList);
    end;
  end
  else if ANode is TQueryNotNode then
  begin
    CollectFields(TQueryNotNode(ANode).Inner, AList);
  end
  else if ANode is TQueryCompareNode then
  begin
    mName := TQueryCompareNode(ANode).Field.Name;
    if not AList.Contains(mName) then
    begin
      AList.Add(mName);
    end;
  end;
end;

function TQueryAst.UsedFields: TArray<string>;
var
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    if Condition <> nil then
    begin
      CollectFields(Condition, mList);
    end;
    if HasOrder and not mList.Contains(OrderField.Name) then
    begin
      mList.Add(OrderField.Name);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TQueryLexer }

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '*', '?', '&']) or (Ord(AChar) > 127);
end;

/// <summary>Text in Anführungszeichen ab APosition; ein verdoppeltes Zeichen steht für sich selbst ('O''Brien').
/// </summary>
procedure ReadQuoted(const AText: string; var APosition: Integer; var AToken: TQueryToken);
var
  mQuote: Char;
  mStart: Integer;
begin
  mStart := APosition;
  mQuote := AText[APosition];
  Inc(APosition);
  AToken.Kind := TQueryTokenKind.Text;
  while (APosition <= Length(AText)) and
    ((AText[APosition] <> mQuote) or ((APosition < Length(AText)) and (AText[APosition + 1] = mQuote))) do
  begin
    AToken.Text := AToken.Text + AText[APosition];
    if AText[APosition] = mQuote then
    begin
      Inc(APosition);
    end;
    Inc(APosition);
  end;
  if APosition > Length(AText) then
  begin
    raise EQueryError.Create(cTexts[TLanguageText.TextWithoutClosingQuotationMark].Text, mStart, '');
  end;
  Inc(APosition);
end;

function IsNumberStart(const AText: string; APosition: Integer): Boolean;
begin
  Result := CharInSet(AText[APosition], ['0'..'9']) or ((AText[APosition] = '-') and
    (APosition < Length(AText)) and CharInSet(AText[APosition + 1], ['0'..'9']));
end;

procedure ReadNumber(const AText: string; var APosition: Integer; var AToken: TQueryToken);
var
  mStart: Integer;
begin
  mStart := APosition;
  Inc(APosition);
  while (APosition <= Length(AText)) and CharInSet(AText[APosition], ['0'..'9']) do
  begin
    Inc(APosition);
  end;
  AToken.Text := Copy(AText, mStart, APosition - mStart);
  // 12abc ist kein Name und keine Zahl.
  if (APosition <= Length(AText)) and IsNameChar(AText[APosition]) then
  begin
    raise EQueryError.Create(cTexts[TLanguageText.IsNotANumber].Fmt([AToken.Text]), mStart, '');
  end;
  AToken.Kind := TQueryTokenKind.Number;
end;

procedure ReadOperator(const AText: string; var APosition: Integer; var AToken: TQueryToken);
var
  mStart: Integer;
begin
  mStart := APosition;
  Inc(APosition);
  if (APosition <= Length(AText)) and CharInSet(AText[APosition], ['=', '>']) and
    (AText[mStart] <> '=') and not ((AText[mStart] = '>') and (AText[APosition] = '>')) then
  begin
    Inc(APosition);
  end;
  AToken.Text := Copy(AText, mStart, APosition - mStart);
  // != wie <> (häufige Gewohnheit aus anderen Sprachen); ! allein gibt es nicht.
  if AToken.Text = '!=' then
  begin
    AToken.Text := '<>';
  end
  else if AToken.Text = '!' then
  begin
    raise EQueryError.Create(cTexts[TLanguageText.DoesNotExistForNegation].Text, mStart, '<>');
  end;
  AToken.Kind := TQueryTokenKind.Symbol;
end;

procedure ReadName(const AText: string; var APosition: Integer; var AToken: TQueryToken);
var
  mStart: Integer;
begin
  mStart := APosition;
  while (APosition <= Length(AText)) and IsNameChar(AText[APosition]) do
  begin
    Inc(APosition);
  end;
  AToken.Kind := TQueryTokenKind.Name;
  AToken.Text := Copy(AText, mStart, APosition - mStart);
end;

/// <summary>Liest das Zeichen ab APosition (kein Leerraum) als Token.</summary>
procedure ReadToken(const AText: string; var APosition: Integer; var AToken: TQueryToken);
begin
  if CharInSet(AText[APosition], ['''', '"']) then
  begin
    ReadQuoted(AText, APosition, AToken);
  end
  else if IsNumberStart(AText, APosition) then
  begin
    ReadNumber(AText, APosition, AToken);
  end
  else if CharInSet(AText[APosition], cOperatorChars) then
  begin
    ReadOperator(AText, APosition, AToken);
  end
  else if CharInSet(AText[APosition], ['(', ')']) then
  begin
    AToken.Text := AText[APosition];
    AToken.Kind := TQueryTokenKind.OpenParen;
    if AText[APosition] = ')' then
    begin
      AToken.Kind := TQueryTokenKind.CloseParen;
    end;
    Inc(APosition);
  end
  else if IsNameChar(AText[APosition]) then
  begin
    ReadName(AText, APosition, AToken);
  end
  else
  begin
    raise EQueryError.Create(cTexts[TLanguageText.UnexpectedCharacter].Fmt([AText[APosition]]), APosition, '');
  end;
end;

class function TQueryLexer.Tokenize(const AText: string): TArray<TQueryToken>;
var
  mList: TList<TQueryToken>;
  mToken: TQueryToken;
  mPosition: Integer;
begin
  mList := TList<TQueryToken>.Create;
  try
    mPosition := 1;
    while mPosition <= Length(AText) do
    begin
      if CharInSet(AText[mPosition], [' ', #9, #10, #13]) then
      begin
        Inc(mPosition);
        Continue;
      end;
      mToken := Default(TQueryToken);
      mToken.Column := mPosition;
      ReadToken(AText, mPosition, mToken);
      mList.Add(mToken);
    end;
    mToken := Default(TQueryToken);
    mToken.Kind := TQueryTokenKind.EndOfQuery;
    mToken.Column := Length(AText) + 1;
    mList.Add(mToken);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TQueryParser }

class function TQueryParser.UnknownText(const AWhat, AName, ASuggestion: string): string;
begin
  if ASuggestion <> '' then
  begin
    Result := cTexts[TLanguageText.DidYouMean].Fmt([AWhat, AName, ASuggestion]);
  end
  else
  begin
    Result := Format('%s `%s`', [AWhat, AName]);
  end;
end;

function TQueryParser.Current: TQueryToken;
begin
  Result := FTokens[FPosition];
end;

function TQueryParser.Next: TQueryToken;
begin
  Result := FTokens[FPosition];
  if FPosition < High(FTokens) then
  begin
    Inc(FPosition);
  end;
end;

procedure TQueryParser.Fail(const AMessage: string; AColumn: Integer);
begin
  raise EQueryError.Create(AMessage, AColumn, '');
end;

procedure TQueryParser.Fail(const AMessage: string; AColumn: Integer; const ASuggestion: string);
begin
  raise EQueryError.Create(AMessage, AColumn, ASuggestion);
end;

function Describe(const AToken: TQueryToken): string;
begin
  if AToken.Kind = TQueryTokenKind.EndOfQuery then
  begin
    Result := cTexts[TLanguageText.EndOfTheQuery].Text;
  end
  else
  begin
    Result := Format('`%s`', [AToken.Text]);
  end;
end;

function OperatorOf(const AText: string; out AOperator: TQueryOperator): Boolean;
begin
  Result := True;
  if AText = '=' then
  begin
    AOperator := TQueryOperator.Equal;
  end
  else if AText = '<>' then
  begin
    AOperator := TQueryOperator.NotEqual;
  end
  else if AText = '<' then
  begin
    AOperator := TQueryOperator.Less;
  end
  else if AText = '>' then
  begin
    AOperator := TQueryOperator.Greater;
  end
  else if AText = '<=' then
  begin
    AOperator := TQueryOperator.LessEqual;
  end
  else if AText = '>=' then
  begin
    AOperator := TQueryOperator.GreaterEqual;
  end
  else
  begin
    AOperator := TQueryOperator.Equal;
    Result := False;
  end;
end;

function TQueryParser.IsComparisonStart(const AToken: TQueryToken): Boolean;
begin
  Result := (AToken.Kind = TQueryTokenKind.Symbol) or AToken.Is_('like') or AToken.Is_('not');
end;

function TQueryParser.FieldFor(const AToken: TQueryToken): TQueryFieldInfo;
var
  mSuggestion: string;
begin
  if AToken.Kind <> TQueryTokenKind.Name then
  begin
    Fail(cTexts[TLanguageText.ExpectedFieldPredicateNotOr].Fmt([Describe(AToken)]), AToken.Column);
  end;
  if not TQueryCatalog.TryField(AToken.Text, Result) then
  begin
    mSuggestion := TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames(FEntity));
    if mSuggestion = '' then
    begin
      mSuggestion := TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames);
    end;
    if mSuggestion <> '' then
    begin
      Fail(UnknownText(cTexts[TLanguageText.UnknownField].Text, AToken.Text, mSuggestion), AToken.Column, mSuggestion);
    end
    else
    begin
      Fail(cTexts[TLanguageText.FieldsOf].Fmt([UnknownText(cTexts[TLanguageText.UnknownField].Text, AToken.Text, ''),
        TQueryCatalog.EntityName(FEntity), string.Join(', ', TQueryCatalog.FieldNames(FEntity))]), AToken.Column);
    end;
  end;
  if not (FEntity in Result.Entities) then
  begin
    Fail(cTexts[TLanguageText.FieldDoesNotExistFor].Fmt([Result.Name, TQueryCatalog.EntityName(FEntity),
      string.Join(', ', TQueryCatalog.FieldNames(FEntity))]), AToken.Column,
      TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames(FEntity)));
  end;
end;

function TQueryParser.ParseValue(const AField: TQueryFieldInfo; ALike: Boolean): TQueryValue;
var
  mToken: TQueryToken;
  mNumber: Int64;
begin
  mNumber := 0;
  mToken := Next;
  if not (mToken.Kind in [TQueryTokenKind.Name, TQueryTokenKind.Number, TQueryTokenKind.Text]) then
  begin
    Fail(cTexts[TLanguageText.ExpectedValueAfterFound].Fmt([AField.Name, Describe(mToken)]), mToken.Column);
  end;
  if ALike then
  begin
    if AField.FieldType <> TQueryFieldType.Text then
    begin
      Fail(cTexts[TLanguageText.LikeOnlyExistsForText].Fmt([AField.Name,
        LowerCase(TQueryCatalog.FieldTypeName(AField.FieldType))]), mToken.Column);
    end;
    Exit(TQueryValue.OfText(mToken.Text));
  end;
  case AField.FieldType of
    TQueryFieldType.Number:
      begin
        if (mToken.Kind <> TQueryTokenKind.Number) or not TryStrToInt64(mToken.Text, mNumber) then
        begin
          Fail(cTexts[TLanguageText.IsANumberIsNot].Fmt([AField.Name, Describe(mToken)]), mToken.Column);
        end;
        Result := TQueryValue.OfNumber(mNumber);
      end;
    TQueryFieldType.Flag:
      begin
        if mToken.Is_('true') then
        begin
          Result := TQueryValue.OfFlag(True);
        end
        else if mToken.Is_('false') then
        begin
          Result := TQueryValue.OfFlag(False);
        end
        else
        begin
          Fail(cTexts[TLanguageText.IsATruthValueTrue].Fmt([AField.Name,
            Describe(mToken)]), mToken.Column);
          Result := TQueryValue.Empty;
        end;
      end;
  else
    Result := TQueryValue.OfText(mToken.Text);
  end;
end;

function TQueryParser.ParseComparison: TQueryNode;
var
  mToken, mOperatorToken: TQueryToken;
  mNode: TQueryCompareNode;
  mField: TQueryFieldInfo;
  mOperator: TQueryOperator;
  mNegated: Boolean;
begin
  mToken := Next;
  mField := FieldFor(mToken);
  mOperatorToken := Next;
  mNegated := False;
  if mOperatorToken.Is_('not') and Current.Is_('like') then
  begin
    mNegated := True;
    mOperatorToken := Next;
  end;
  if mOperatorToken.Is_('like') then
  begin
    if mNegated then
    begin
      mOperator := TQueryOperator.NotLike;
    end
    else
    begin
      mOperator := TQueryOperator.Like;
    end;
  end
  else if (mOperatorToken.Kind <> TQueryTokenKind.Symbol) or not OperatorOf(mOperatorToken.Text, mOperator) then
  begin
    Fail(cTexts[TLanguageText.ExpectedComparisonOrLikeAfter].Fmt([mField.Name, Describe(mOperatorToken)]),
      mOperatorToken.Column);
    mOperator := TQueryOperator.Equal;
  end;
  if (mField.FieldType = TQueryFieldType.Flag) and not (mOperator in [TQueryOperator.Equal,
    TQueryOperator.NotEqual]) then
  begin
    Fail(cTexts[TLanguageText.IsATruthValueAllowed].Fmt([mField.Name]), mOperatorToken.Column);
  end;
  mNode := TQueryCompareNode.Create;
  try
    mNode.Column := mToken.Column;
    mNode.Field := mField;
    mNode.Comparison := mOperator;
    mNode.Value := ParseValue(mField, mOperator in [TQueryOperator.Like, TQueryOperator.NotLike]);
  except
    mNode.Free;
    raise;
  end;
  Result := mNode;
end;

function TQueryParser.ParsePredicate(AKind: TQueryPredicateKind; AColumn: Integer): TQueryNode;
var
  mToken: TQueryToken;
  mNode: TQueryPredicateNode;
begin
  if not (FEntity in TQueryCatalog.PredicateEntities(AKind)) then
  begin
    Fail(cTexts[TLanguageText.DoesNotExistFor].Fmt([TQueryCatalog.PredicateName(AKind),
      TQueryCatalog.EntityName(FEntity)]), AColumn);
  end;
  mToken := Next;
  if not (mToken.Kind in [TQueryTokenKind.Name, TQueryTokenKind.Text]) then
  begin
    Fail(cTexts[TLanguageText.ExpectedNameAfterFound].Fmt([TQueryCatalog.PredicateName(AKind), Describe(mToken)]),
      mToken.Column);
  end;
  mNode := TQueryPredicateNode.Create;
  mNode.Column := AColumn;
  mNode.Kind := AKind;
  mNode.Argument := mToken.Text;
  Result := mNode;
end;

function TQueryParser.ParseNot: TQueryNode;
var
  mColumn: Integer;
  mNot: TQueryNotNode;
begin
  mColumn := Next.Column;
  mNot := TQueryNotNode.Create;
  mNot.Column := mColumn;
  try
    mNot.Inner := ParseFactor;
  except
    mNot.Free;
    raise;
  end;
  Result := mNot;
end;

function TQueryParser.ParseGroup: TQueryNode;
var
  mColumn: Integer;
begin
  mColumn := Next.Column;
  Result := ParseExpression;
  if Current.Kind <> TQueryTokenKind.CloseParen then
  begin
    Result.Free;
    Fail(cTexts[TLanguageText.ExpectedForInColumnFound].Fmt([mColumn, Describe(Current)]), Current.Column);
  end;
  Next;
end;

function TQueryParser.IsPredicateStart(const AToken: TQueryToken; out AKind: TQueryPredicateKind): Boolean;
begin
  Result := True;
  if AToken.Is_('inherits') then
  begin
    AKind := TQueryPredicateKind.Inherits;
  end
  else if AToken.Is_('implements') then
  begin
    AKind := TQueryPredicateKind.Implements;
  end
  else if AToken.Is_('calls') then
  begin
    AKind := TQueryPredicateKind.Calls;
  end
  else if AToken.Is_('has') then
  begin
    AKind := TQueryPredicateKind.HasAttribute;
  end
  else
  begin
    // "uses" ist bei Units auch ein Feld: mit Vergleich das Feld, sonst das Prädikat.
    AKind := TQueryPredicateKind.Uses_;
    Result := AToken.Is_('uses') and
      not ((FEntity = TQueryEntity.Units) and IsComparisonStart(FTokens[FPosition + 1]));
  end;
end;

function TQueryParser.ParseKeywordPredicate(AKind: TQueryPredicateKind): TQueryNode;
var
  mColumn: Integer;
begin
  mColumn := Next.Column;
  if AKind = TQueryPredicateKind.HasAttribute then
  begin
    if not Current.Is_('attribute') then
    begin
      Fail(cTexts[TLanguageText.ExpectedAttributeAfterHasFound].Fmt([Describe(Current)]), Current.Column,
        'attribute');
    end;
    Next;
  end;
  Result := ParsePredicate(AKind, mColumn);
end;

function TQueryParser.ParseFactor: TQueryNode;
var
  mKind: TQueryPredicateKind;
begin
  if Current.Is_('not') then
  begin
    Result := ParseNot;
  end
  else if Current.Kind = TQueryTokenKind.OpenParen then
  begin
    Result := ParseGroup;
  end
  else if IsPredicateStart(Current, mKind) then
  begin
    Result := ParseKeywordPredicate(mKind);
  end
  else
  begin
    Result := ParseComparison;
  end;
end;

function TQueryParser.ParseTerm: TQueryNode;
var
  mLogic: TQueryLogicNode;
begin
  Result := ParseFactor;
  if not Current.Is_('and') then
  begin
    Exit;
  end;
  mLogic := TQueryLogicNode.Create(TQueryLogic.And_);
  mLogic.Column := Result.Column;
  mLogic.Items.Add(Result);
  try
    while Current.Is_('and') do
    begin
      Next;
      mLogic.Items.Add(ParseFactor);
    end;
  except
    mLogic.Free;
    raise;
  end;
  Result := mLogic;
end;

function TQueryParser.ParseExpression: TQueryNode;
var
  mLogic: TQueryLogicNode;
begin
  Result := ParseTerm;
  if not Current.Is_('or') then
  begin
    Exit;
  end;
  mLogic := TQueryLogicNode.Create(TQueryLogic.Or_);
  mLogic.Column := Result.Column;
  mLogic.Items.Add(Result);
  try
    while Current.Is_('or') do
    begin
      Next;
      mLogic.Items.Add(ParseTerm);
    end;
  except
    mLogic.Free;
    raise;
  end;
  Result := mLogic;
end;

function TQueryParser.ParseEntity: TQueryEntity;
var
  mToken: TQueryToken;
  mSuggestion: string;
begin
  mToken := Next;
  if (mToken.Kind = TQueryTokenKind.Name) and TQueryCatalog.TryEntity(mToken.Text, Result) then
  begin
    Exit;
  end;
  Result := Low(TQueryEntity);
  mSuggestion := TTextFuzzy.Closest(mToken.Text, TQueryCatalog.EntityNames);
  if mSuggestion <> '' then
  begin
    Fail(UnknownText(cTexts[TLanguageText.UnknownSet].Text, mToken.Text, mSuggestion), mToken.Column, mSuggestion);
  end;
  Fail(cTexts[TLanguageText.ExpectedSetFound].Fmt([string.Join(', ', TQueryCatalog.EntityNames),
    Describe(mToken)]), mToken.Column);
end;

procedure TQueryParser.ParseOrder(AAst: TQueryAst);
begin
  Next;
  if not Current.Is_('by') then
  begin
    Fail(cTexts[TLanguageText.ExpectedByAfterOrderFound].Fmt([Describe(Current)]), Current.Column, 'by');
  end;
  Next;
  AAst.OrderField := FieldFor(Next);
  AAst.HasOrder := True;
  if Current.Is_('desc') then
  begin
    AAst.Descending := True;
    Next;
  end
  else if Current.Is_('asc') then
  begin
    Next;
  end;
end;

procedure TQueryParser.ParseLimit(AAst: TQueryAst);
var
  mToken: TQueryToken;
  mLimit: Integer;
begin
  Next;
  mToken := Next;
  if (mToken.Kind <> TQueryTokenKind.Number) or not TryStrToInt(mToken.Text, mLimit) or (mLimit < 0) then
  begin
    Fail(cTexts[TLanguageText.ExpectedCountAfterLimitFound].Fmt([Describe(mToken)]), mToken.Column);
  end;
  AAst.Limit := mLimit;
end;

procedure TQueryParser.CheckEnd(AAst: TQueryAst);
var
  mToken: TQueryToken;
begin
  mToken := Current;
  if mToken.Kind = TQueryTokenKind.EndOfQuery then
  begin
    Exit;
  end;
  if (AAst.Condition = nil) and not AAst.HasOrder and (AAst.Limit < 0) then
  begin
    Fail(cTexts[TLanguageText.ExpectedWhereOrderByOr].Fmt([Describe(mToken)]), mToken.Column,
      TTextFuzzy.Closest(mToken.Text, TArray<string>.Create('where', 'order', 'limit')));
  end;
  Fail(cTexts[TLanguageText.UnexpectedConditionsAreJoinedWith].Fmt([Describe(mToken)]), mToken.Column,
    TTextFuzzy.Closest(mToken.Text, TArray<string>.Create('and', 'or', 'order', 'limit')));
end;

class function TQueryParser.Parse(const AText: string): TQueryAst;
var
  mParser: TQueryParser;
  mAst: TQueryAst;
begin
  if Trim(AText) = '' then
  begin
    raise EQueryError.Create(cTexts[TLanguageText.EmptyQueryExampleClassesWhere].Text, 1, '');
  end;
  mParser := TQueryParser.Create;
  mAst := TQueryAst.Create;
  try
    mAst.Text := AText;
    mAst.Limit := -1;
    mParser.FTokens := TQueryLexer.Tokenize(AText);
    mParser.FPosition := 0;
    mAst.Entity := mParser.ParseEntity;
    mParser.FEntity := mAst.Entity;
    if mParser.Current.Is_('where') then
    begin
      mParser.Next;
      mAst.Condition := mParser.ParseExpression;
    end;
    if mParser.Current.Is_('order') then
    begin
      mParser.ParseOrder(mAst);
    end;
    if mParser.Current.Is_('limit') then
    begin
      mParser.ParseLimit(mAst);
    end;
    mParser.CheckEnd(mAst);
    Result := mAst;
    mAst := nil;
  finally
    mAst.Free;
    mParser.Free;
  end;
end;

class function TQueryParser.TryParse(const AText: string; out AAst: TQueryAst; out AError: string;
  out AColumn: Integer; out ASuggestion: string): Boolean;
begin
  AAst := nil;
  AError := '';
  AColumn := 0;
  ASuggestion := '';
  try
    AAst := Parse(AText);
    Result := True;
  except
    on E: EQueryError do
    begin
      AError := E.Message;
      AColumn := E.Column;
      ASuggestion := E.Suggestion;
      Result := False;
    end;
  end;
end;

class function TQueryParser.ConfigurationIssues(const AQueries: TArray<TSavedQuery>): TArray<TConfigurationIssue>;
var
  mQuery: TSavedQuery;
  mAst: TQueryAst;
  mError, mSuggestion: string;
  mColumn: Integer;
  mIssue: TConfigurationIssue;
begin
  Result := nil;
  for mQuery in AQueries do
  begin
    if TryParse(mQuery.Query, mAst, mError, mColumn, mSuggestion) then
    begin
      mAst.Free;
      Continue;
    end;
    mIssue := Default(TConfigurationIssue);
    mIssue.IsError := True;
    mIssue.Message := cTexts[TLanguageText.QueryColumn].Fmt([mQuery.Name, mColumn, mError]);
    mIssue.Range := mQuery.QueryRange;
    // Auf der Zeile des Texts steht die Stelle genau, sonst gilt der ganze Text.
    if (mColumn > 0) and (mQuery.QueryRange.StartPos.Line = mQuery.QueryRange.EndPos.Line) then
    begin
      mIssue.Range.StartPos.Character := mQuery.QueryRange.StartPos.Character + mColumn - 1;
      mIssue.Range.EndPos.Character := mIssue.Range.StartPos.Character + 1;
      if mIssue.Range.EndPos.Character > mQuery.QueryRange.EndPos.Character then
      begin
        mIssue.Range := mQuery.QueryRange;
      end;
    end;
    Result := Result + [mIssue];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Query.Language', cTexts);

end.
