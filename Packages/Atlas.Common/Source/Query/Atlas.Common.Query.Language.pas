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
  Atlas.Text.Fuzzy;

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
      CollectFields(mItem, AList);
  end
  else if ANode is TQueryNotNode then
    CollectFields(TQueryNotNode(ANode).Inner, AList)
  else if ANode is TQueryCompareNode then
  begin
    mName := TQueryCompareNode(ANode).Field.Name;
    if not AList.Contains(mName) then
      AList.Add(mName);
  end;
end;

function TQueryAst.UsedFields: TArray<string>;
var
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    if Condition <> nil then
      CollectFields(Condition, mList);
    if HasOrder and not mList.Contains(OrderField.Name) then
      mList.Add(OrderField.Name);
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

class function TQueryLexer.Tokenize(const AText: string): TArray<TQueryToken>;
var
  mList: TList<TQueryToken>;
  mToken: TQueryToken;
  mPosition, mStart: Integer;
  mQuote: Char;
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
      mStart := mPosition;
      if CharInSet(AText[mPosition], ['''', '"']) then
      begin
        mQuote := AText[mPosition];
        Inc(mPosition);
        mToken.Kind := TQueryTokenKind.Text;
        while True do
        begin
          if mPosition > Length(AText) then
            raise EQueryError.Create('Text ohne schließendes Anführungszeichen', mStart, '');
          if AText[mPosition] = mQuote then
          begin
            // Verdoppeltes Zeichen steht für sich selbst ('O''Brien').
            if (mPosition < Length(AText)) and (AText[mPosition + 1] = mQuote) then
            begin
              mToken.Text := mToken.Text + mQuote;
              Inc(mPosition, 2);
              Continue;
            end;
            Inc(mPosition);
            Break;
          end;
          mToken.Text := mToken.Text + AText[mPosition];
          Inc(mPosition);
        end;
      end
      else if CharInSet(AText[mPosition], ['0'..'9']) or ((AText[mPosition] = '-') and (mPosition < Length(AText)) and
        CharInSet(AText[mPosition + 1], ['0'..'9'])) then
      begin
        Inc(mPosition);
        while (mPosition <= Length(AText)) and CharInSet(AText[mPosition], ['0'..'9']) do
          Inc(mPosition);
        mToken.Text := Copy(AText, mStart, mPosition - mStart);
        // 12abc ist kein Name und keine Zahl.
        if (mPosition <= Length(AText)) and IsNameChar(AText[mPosition]) then
          raise EQueryError.Create(Format('"%s…" ist keine Zahl', [mToken.Text]), mStart, '');
        mToken.Kind := TQueryTokenKind.Number;
      end
      else if CharInSet(AText[mPosition], cOperatorChars) then
      begin
        Inc(mPosition);
        if (mPosition <= Length(AText)) and CharInSet(AText[mPosition], ['=', '>']) and
          (AText[mStart] <> '=') and not ((AText[mStart] = '>') and (AText[mPosition] = '>')) then
          Inc(mPosition);
        mToken.Text := Copy(AText, mStart, mPosition - mStart);
        // != wie <> (häufige Gewohnheit aus anderen Sprachen); ! allein gibt es nicht.
        if mToken.Text = '!=' then
          mToken.Text := '<>'
        else if mToken.Text = '!' then
          raise EQueryError.Create('"!" gibt es nicht; für Verneinung "not", für ungleich "<>"', mStart, '<>');
        mToken.Kind := TQueryTokenKind.Symbol;
      end
      else if AText[mPosition] = '(' then
      begin
        Inc(mPosition);
        mToken.Kind := TQueryTokenKind.OpenParen;
        mToken.Text := '(';
      end
      else if AText[mPosition] = ')' then
      begin
        Inc(mPosition);
        mToken.Kind := TQueryTokenKind.CloseParen;
        mToken.Text := ')';
      end
      else if IsNameChar(AText[mPosition]) then
      begin
        while (mPosition <= Length(AText)) and IsNameChar(AText[mPosition]) do
          Inc(mPosition);
        mToken.Kind := TQueryTokenKind.Name;
        mToken.Text := Copy(AText, mStart, mPosition - mStart);
      end
      else
        raise EQueryError.Create(Format('Unerwartetes Zeichen "%s"', [AText[mPosition]]), mPosition, '');
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
    Result := Format('%s `%s`, meintest du `%s`?', [AWhat, AName, ASuggestion])
  else
    Result := Format('%s `%s`', [AWhat, AName]);
end;

function TQueryParser.Current: TQueryToken;
begin
  Result := FTokens[FPosition];
end;

function TQueryParser.Next: TQueryToken;
begin
  Result := FTokens[FPosition];
  if FPosition < High(FTokens) then
    Inc(FPosition);
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
    Result := 'Ende der Abfrage'
  else
    Result := Format('`%s`', [AToken.Text]);
end;

function OperatorOf(const AText: string; out AOperator: TQueryOperator): Boolean;
begin
  Result := True;
  if AText = '=' then
    AOperator := TQueryOperator.Equal
  else if AText = '<>' then
    AOperator := TQueryOperator.NotEqual
  else if AText = '<' then
    AOperator := TQueryOperator.Less
  else if AText = '>' then
    AOperator := TQueryOperator.Greater
  else if AText = '<=' then
    AOperator := TQueryOperator.LessEqual
  else if AText = '>=' then
    AOperator := TQueryOperator.GreaterEqual
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
    Fail(Format('Erwartet: Feld, Prädikat, not oder "(", gefunden %s', [Describe(AToken)]), AToken.Column);
  if not TQueryCatalog.TryField(AToken.Text, Result) then
  begin
    mSuggestion := TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames(FEntity));
    if mSuggestion = '' then
      mSuggestion := TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames);
    if mSuggestion <> '' then
      Fail(UnknownText('Unbekanntes Feld', AToken.Text, mSuggestion), AToken.Column, mSuggestion)
    else
      Fail(Format('%s; Felder von %s: %s', [UnknownText('Unbekanntes Feld', AToken.Text, ''),
        TQueryCatalog.EntityName(FEntity), string.Join(', ', TQueryCatalog.FieldNames(FEntity))]), AToken.Column);
  end;
  if not (FEntity in Result.Entities) then
    Fail(Format('Feld `%s` gibt es bei `%s` nicht; Felder: %s', [Result.Name, TQueryCatalog.EntityName(FEntity),
      string.Join(', ', TQueryCatalog.FieldNames(FEntity))]), AToken.Column,
      TTextFuzzy.Closest(AToken.Text, TQueryCatalog.FieldNames(FEntity)));
end;

function TQueryParser.ParseValue(const AField: TQueryFieldInfo; ALike: Boolean): TQueryValue;
var
  mToken: TQueryToken;
  mNumber: Int64;
begin
  mNumber := 0;
  mToken := Next;
  if not (mToken.Kind in [TQueryTokenKind.Name, TQueryTokenKind.Number, TQueryTokenKind.Text]) then
    Fail(Format('Erwartet: Wert nach `%s`, gefunden %s', [AField.Name, Describe(mToken)]), mToken.Column);
  if ALike then
  begin
    if AField.FieldType <> TQueryFieldType.Text then
      Fail(Format('like gibt es nur für Textfelder; `%s` ist %s', [AField.Name,
        LowerCase(TQueryCatalog.FieldTypeName(AField.FieldType))]), mToken.Column);
    Exit(TQueryValue.OfText(mToken.Text));
  end;
  case AField.FieldType of
    TQueryFieldType.Number:
      begin
        if (mToken.Kind <> TQueryTokenKind.Number) or not TryStrToInt64(mToken.Text, mNumber) then
          Fail(Format('`%s` ist eine Zahl; %s ist keine', [AField.Name, Describe(mToken)]), mToken.Column);
        Result := TQueryValue.OfNumber(mNumber);
      end;
    TQueryFieldType.Flag:
      begin
        if mToken.Is_('true') then
          Result := TQueryValue.OfFlag(True)
        else if mToken.Is_('false') then
          Result := TQueryValue.OfFlag(False)
        else
        begin
          Fail(Format('`%s` ist ein Wahrheitswert (true oder false); %s ist keiner', [AField.Name,
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
      mOperator := TQueryOperator.NotLike
    else
      mOperator := TQueryOperator.Like;
  end
  else if (mOperatorToken.Kind <> TQueryTokenKind.Symbol) or not OperatorOf(mOperatorToken.Text, mOperator) then
  begin
    Fail(Format('Erwartet: Vergleich (=, <>, <, >, <=, >=) oder like nach `%s`, gefunden %s',
      [mField.Name, Describe(mOperatorToken)]), mOperatorToken.Column);
    mOperator := TQueryOperator.Equal;
  end;
  if (mField.FieldType = TQueryFieldType.Flag) and not (mOperator in [TQueryOperator.Equal,
    TQueryOperator.NotEqual]) then
    Fail(Format('`%s` ist ein Wahrheitswert; erlaubt sind = und <>', [mField.Name]), mOperatorToken.Column);
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
    Fail(Format('`%s` gibt es bei `%s` nicht', [TQueryCatalog.PredicateName(AKind),
      TQueryCatalog.EntityName(FEntity)]), AColumn);
  mToken := Next;
  if not (mToken.Kind in [TQueryTokenKind.Name, TQueryTokenKind.Text]) then
    Fail(Format('Erwartet: Name nach `%s`, gefunden %s', [TQueryCatalog.PredicateName(AKind), Describe(mToken)]),
      mToken.Column);
  mNode := TQueryPredicateNode.Create;
  mNode.Column := AColumn;
  mNode.Kind := AKind;
  mNode.Argument := mToken.Text;
  Result := mNode;
end;

function TQueryParser.ParseFactor: TQueryNode;
var
  mToken: TQueryToken;
  mNot: TQueryNotNode;
  mInner: TQueryNode;
begin
  mToken := Current;
  if mToken.Is_('not') then
  begin
    Next;
    mInner := ParseFactor;
    mNot := TQueryNotNode.Create;
    mNot.Column := mToken.Column;
    mNot.Inner := mInner;
    Exit(mNot);
  end;
  if mToken.Kind = TQueryTokenKind.OpenParen then
  begin
    Next;
    Result := ParseExpression;
    if Current.Kind <> TQueryTokenKind.CloseParen then
    begin
      Result.Free;
      Fail(Format('Erwartet: ")" zu "(" in Spalte %d, gefunden %s', [mToken.Column, Describe(Current)]),
        Current.Column);
    end;
    Next;
    Exit;
  end;
  if mToken.Is_('inherits') then
  begin
    Next;
    Exit(ParsePredicate(TQueryPredicateKind.Inherits, mToken.Column));
  end;
  if mToken.Is_('implements') then
  begin
    Next;
    Exit(ParsePredicate(TQueryPredicateKind.Implements, mToken.Column));
  end;
  if mToken.Is_('calls') then
  begin
    Next;
    Exit(ParsePredicate(TQueryPredicateKind.Calls, mToken.Column));
  end;
  if mToken.Is_('has') then
  begin
    Next;
    if not Current.Is_('attribute') then
      Fail(Format('Erwartet: `attribute` nach `has`, gefunden %s', [Describe(Current)]), Current.Column,
        'attribute');
    Next;
    Exit(ParsePredicate(TQueryPredicateKind.HasAttribute, mToken.Column));
  end;
  // "uses" ist bei Units auch ein Feld: mit Vergleich das Feld, sonst das Prädikat.
  if mToken.Is_('uses') and not ((FEntity = TQueryEntity.Units) and IsComparisonStart(FTokens[FPosition + 1])) then
  begin
    Next;
    Exit(ParsePredicate(TQueryPredicateKind.Uses_, mToken.Column));
  end;
  Result := ParseComparison;
end;

function TQueryParser.ParseTerm: TQueryNode;
var
  mLogic: TQueryLogicNode;
begin
  Result := ParseFactor;
  if not Current.Is_('and') then
    Exit;
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
    Exit;
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

class function TQueryParser.Parse(const AText: string): TQueryAst;
var
  mParser: TQueryParser;
  mToken: TQueryToken;
  mSuggestion: string;
  mAst: TQueryAst;
  mLimit: Integer;
begin
  if Trim(AText) = '' then
    raise EQueryError.Create('Leere Abfrage; Beispiel: classes where methods > 40', 1, '');
  mParser := TQueryParser.Create;
  mAst := TQueryAst.Create;
  try
    mAst.Text := AText;
    mAst.Limit := -1;
    mParser.FTokens := TQueryLexer.Tokenize(AText);
    mParser.FPosition := 0;
    mToken := mParser.Next;
    if (mToken.Kind <> TQueryTokenKind.Name) or not TQueryCatalog.TryEntity(mToken.Text, mAst.Entity) then
    begin
      mSuggestion := TTextFuzzy.Closest(mToken.Text, TQueryCatalog.EntityNames);
      if mSuggestion <> '' then
        mParser.Fail(UnknownText('Unbekannte Menge', mToken.Text, mSuggestion), mToken.Column, mSuggestion)
      else
        mParser.Fail(Format('Erwartet: Menge (%s), gefunden %s', [string.Join(', ', TQueryCatalog.EntityNames),
          Describe(mToken)]), mToken.Column);
    end;
    mParser.FEntity := mAst.Entity;
    if mParser.Current.Is_('where') then
    begin
      mParser.Next;
      mAst.Condition := mParser.ParseExpression;
    end;
    if mParser.Current.Is_('order') then
    begin
      mParser.Next;
      if not mParser.Current.Is_('by') then
        mParser.Fail(Format('Erwartet: `by` nach `order`, gefunden %s', [Describe(mParser.Current)]),
          mParser.Current.Column, 'by');
      mParser.Next;
      mAst.OrderField := mParser.FieldFor(mParser.Next);
      mAst.HasOrder := True;
      if mParser.Current.Is_('desc') then
      begin
        mAst.Descending := True;
        mParser.Next;
      end
      else if mParser.Current.Is_('asc') then
        mParser.Next;
    end;
    if mParser.Current.Is_('limit') then
    begin
      mParser.Next;
      mToken := mParser.Next;
      if (mToken.Kind <> TQueryTokenKind.Number) or not TryStrToInt(mToken.Text, mLimit) or (mLimit < 0) then
        mParser.Fail(Format('Erwartet: Anzahl nach `limit`, gefunden %s', [Describe(mToken)]), mToken.Column);
      mAst.Limit := mLimit;
    end;
    mToken := mParser.Current;
    if mToken.Kind <> TQueryTokenKind.EndOfQuery then
    begin
      if (mAst.Condition = nil) and not mAst.HasOrder and (mAst.Limit < 0) then
        mParser.Fail(Format('Erwartet: where, order by oder limit, gefunden %s', [Describe(mToken)]), mToken.Column,
          TTextFuzzy.Closest(mToken.Text, TArray<string>.Create('where', 'order', 'limit')))
      else
        mParser.Fail(Format('Unerwartet: %s; Bedingungen verbinden and und or', [Describe(mToken)]), mToken.Column,
          TTextFuzzy.Closest(mToken.Text, TArray<string>.Create('and', 'or', 'order', 'limit')));
    end;
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
    mIssue.Message := Format('Abfrage "%s", Spalte %d: %s', [mQuery.Name, mColumn, mError]);
    mIssue.Range := mQuery.QueryRange;
    // Auf der Zeile des Texts steht die Stelle genau, sonst gilt der ganze Text.
    if (mColumn > 0) and (mQuery.QueryRange.StartPos.Line = mQuery.QueryRange.EndPos.Line) then
    begin
      mIssue.Range.StartPos.Character := mQuery.QueryRange.StartPos.Character + mColumn - 1;
      mIssue.Range.EndPos.Character := mIssue.Range.StartPos.Character + 1;
      if mIssue.Range.EndPos.Character > mQuery.QueryRange.EndPos.Character then
        mIssue.Range := mQuery.QueryRange;
    end;
    Result := Result + [mIssue];
  end;
end;

end.
