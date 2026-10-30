unit Atlas.Common.Query.Language.Tests;

// Tests der Abfragesprache (#1351): Lexer, Parser, Vorrang von and/or, das
// Doppelleben von "uses", Katalog und deutsche Fehlermeldungen mit Spalte und
// Vorschlag.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TQueryLanguageTests = class
  public
    [Test]
    procedure TokenizesNamesNumbersTextsAndOperators;
    [Test]
    procedure ParsesWhereOrderByAndLimit;
    [Test]
    procedure AndBindsStrongerThanOr;
    [Test]
    procedure ParsesNotLikeAndParentheses;
    [Test]
    procedure UsesIsFieldOrPredicate;
    [Test]
    procedure ParsesAllPredicates;
    [Test]
    procedure UnknownFieldSuggestsWithColumn;
    [Test]
    procedure UnknownEntitySuggests;
    [Test]
    procedure FieldOfOtherEntityIsRejected;
    [Test]
    procedure ValueMustMatchFieldType;
    [Test]
    procedure RejectsTrailingAndOpenText;
    [Test]
    procedure PredicateOnlyOnItsEntities;
    [Test]
    procedure UsedFieldsInOrder;
    [Test]
    procedure CatalogNamesEveryEntityAndField;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Catalog,
  Atlas.Common.Query.Language;

function ErrorOf(const AQuery: string; out AColumn: Integer; out ASuggestion: string): string;
var
  mAst: TQueryAst;
begin
  if TQueryParser.TryParse(AQuery, mAst, Result, AColumn, ASuggestion) then
  begin
    mAst.Free;
    Result := '';
  end;
end;

{ TQueryLanguageTests }

procedure TQueryLanguageTests.TokenizesNamesNumbersTextsAndOperators;
var
  mTokens: TArray<TQueryToken>;
begin
  mTokens := TQueryLexer.Tokenize('classes where name like ''O''''B*'' and lines >= -3 or x != "a b"');
  Assert.AreEqual(Integer(14), Integer(Length(mTokens)));
  Assert.AreEqual('classes', mTokens[0].Text);
  Assert.AreEqual(1, mTokens[0].Column);
  Assert.IsTrue(mTokens[4].Kind = TQueryTokenKind.Text);
  Assert.AreEqual('O''B*', mTokens[4].Text);
  Assert.AreEqual('>=', mTokens[7].Text);
  Assert.IsTrue(mTokens[8].Kind = TQueryTokenKind.Number);
  Assert.AreEqual('-3', mTokens[8].Text);
  // != gilt als <>.
  Assert.AreEqual('<>', mTokens[11].Text);
  Assert.AreEqual('a b', mTokens[12].Text);
  Assert.IsTrue(mTokens[High(mTokens)].Kind = TQueryTokenKind.EndOfQuery);
end;

procedure TQueryLanguageTests.ParsesWhereOrderByAndLimit;
var
  mAst: TQueryAst;
begin
  mAst := TQueryParser.Parse('classes where inherits TForm and methods > 40 order by methods desc limit 5');
  try
    Assert.IsTrue(mAst.Entity = TQueryEntity.Classes);
    Assert.IsTrue(mAst.Condition is TQueryLogicNode);
    Assert.IsTrue(mAst.HasOrder);
    Assert.AreEqual('methods', mAst.OrderField.Name);
    Assert.IsTrue(mAst.Descending);
    Assert.AreEqual(5, mAst.Limit);
  finally
    mAst.Free;
  end;
  mAst := TQueryParser.Parse('UNITS');
  try
    Assert.IsTrue(mAst.Entity = TQueryEntity.Units);
    Assert.IsNull(mAst.Condition);
    Assert.AreEqual(-1, mAst.Limit);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.AndBindsStrongerThanOr;
var
  mAst: TQueryAst;
  mOr: TQueryLogicNode;
begin
  mAst := TQueryParser.Parse('methods where params > 3 or complexity > 10 and callers = 0');
  try
    Assert.IsTrue(mAst.Condition is TQueryLogicNode);
    mOr := TQueryLogicNode(mAst.Condition);
    Assert.IsTrue(mOr.Logic = TQueryLogic.Or_);
    Assert.AreEqual(Integer(2), Integer(mOr.Items.Count));
    Assert.IsTrue(mOr.Items[0] is TQueryCompareNode);
    Assert.IsTrue(mOr.Items[1] is TQueryLogicNode);
    Assert.IsTrue(TQueryLogicNode(mOr.Items[1]).Logic = TQueryLogic.And_);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.ParsesNotLikeAndParentheses;
var
  mAst: TQueryAst;
  mCompare: TQueryCompareNode;
begin
  mAst := TQueryParser.Parse('methods where not (name not like Get* or virtual = true)');
  try
    Assert.IsTrue(mAst.Condition is TQueryNotNode);
    Assert.IsTrue(TQueryNotNode(mAst.Condition).Inner is TQueryLogicNode);
    mCompare := TQueryLogicNode(TQueryNotNode(mAst.Condition).Inner).Items[0] as TQueryCompareNode;
    Assert.IsTrue(mCompare.Comparison = TQueryOperator.NotLike);
    Assert.AreEqual('Get*', mCompare.Value.Text);
    mCompare := TQueryLogicNode(TQueryNotNode(mAst.Condition).Inner).Items[1] as TQueryCompareNode;
    Assert.IsTrue(mCompare.Value.Kind = TQueryValueKind.Flag);
    Assert.AreEqual(Int64(1), mCompare.Value.Number);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.UsesIsFieldOrPredicate;
var
  mAst: TQueryAst;
begin
  mAst := TQueryParser.Parse('units where uses > 30');
  try
    Assert.IsTrue(mAst.Condition is TQueryCompareNode);
    Assert.AreEqual('uses', TQueryCompareNode(mAst.Condition).Field.Name);
  finally
    mAst.Free;
  end;
  mAst := TQueryParser.Parse('units where uses System.SysUtils');
  try
    Assert.IsTrue(mAst.Condition is TQueryPredicateNode);
    Assert.IsTrue(TQueryPredicateNode(mAst.Condition).Kind = TQueryPredicateKind.Uses_);
    Assert.AreEqual('System.SysUtils', TQueryPredicateNode(mAst.Condition).Argument);
  finally
    mAst.Free;
  end;
  // Bei Klassen ist uses nur das Prädikat (die Unit der Deklaration).
  mAst := TQueryParser.Parse('classes where uses Vcl.Forms');
  try
    Assert.IsTrue(mAst.Condition is TQueryPredicateNode);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.ParsesAllPredicates;
var
  mAst: TQueryAst;
  mItems: TQueryLogicNode;
begin
  mAst := TQueryParser.Parse('methods where inherits TBasis and implements IFoo and uses Data and calls TFoo.Bar ' +
    'and has attribute Test');
  try
    mItems := mAst.Condition as TQueryLogicNode;
    Assert.AreEqual(Integer(5), Integer(mItems.Items.Count));
    Assert.IsTrue((mItems.Items[0] as TQueryPredicateNode).Kind = TQueryPredicateKind.Inherits);
    Assert.IsTrue((mItems.Items[1] as TQueryPredicateNode).Kind = TQueryPredicateKind.Implements);
    Assert.IsTrue((mItems.Items[2] as TQueryPredicateNode).Kind = TQueryPredicateKind.Uses_);
    Assert.IsTrue((mItems.Items[3] as TQueryPredicateNode).Kind = TQueryPredicateKind.Calls);
    Assert.AreEqual('TFoo.Bar', (mItems.Items[3] as TQueryPredicateNode).Argument);
    Assert.IsTrue((mItems.Items[4] as TQueryPredicateNode).Kind = TQueryPredicateKind.HasAttribute);
    Assert.AreEqual('Test', (mItems.Items[4] as TQueryPredicateNode).Argument);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.UnknownFieldSuggestsWithColumn;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('classes where methode > 40', mColumn, mSuggestion);
  Assert.AreEqual('Unbekanntes Feld `methode`, meintest du `methods`?', mError);
  Assert.AreEqual(15, mColumn);
  Assert.AreEqual('methods', mSuggestion);
end;

procedure TQueryLanguageTests.UnknownEntitySuggests;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('clases where methods > 40', mColumn, mSuggestion);
  Assert.AreEqual('Unbekannte Menge `clases`, meintest du `classes`?', mError);
  Assert.AreEqual(1, mColumn);
  mError := ErrorOf('', mColumn, mSuggestion);
  Assert.StartsWith('Leere Abfrage', mError);
end;

procedure TQueryLanguageTests.FieldOfOtherEntityIsRejected;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('units where complexity > 3', mColumn, mSuggestion);
  Assert.StartsWith('Feld `complexity` gibt es bei `units` nicht', mError);
  Assert.AreEqual(13, mColumn);
end;

procedure TQueryLanguageTests.ValueMustMatchFieldType;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('classes where methods > viele', mColumn, mSuggestion);
  Assert.AreEqual('`methods` ist eine Zahl; `viele` ist keine', mError);
  Assert.AreEqual(25, mColumn);
  mError := ErrorOf('methods where virtual > true', mColumn, mSuggestion);
  Assert.StartsWith('`virtual` ist ein Wahrheitswert', mError);
  mError := ErrorOf('classes where methods like ''x*''', mColumn, mSuggestion);
  Assert.StartsWith('like gibt es nur für Textfelder', mError);
  mError := ErrorOf('classes where methods 40', mColumn, mSuggestion);
  Assert.StartsWith('Erwartet: Vergleich', mError);
end;

procedure TQueryLanguageTests.RejectsTrailingAndOpenText;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('classes where name = ''offen', mColumn, mSuggestion);
  Assert.AreEqual('Text ohne schließendes Anführungszeichen', mError);
  Assert.AreEqual(22, mColumn);
  mError := ErrorOf('classes wehre methods > 3', mColumn, mSuggestion);
  Assert.AreEqual('where', mSuggestion);
  mError := ErrorOf('classes where methods > 3 anf fields > 2', mColumn, mSuggestion);
  Assert.AreEqual('and', mSuggestion);
  Assert.AreEqual(27, mColumn);
  mError := ErrorOf('classes where (methods > 3', mColumn, mSuggestion);
  Assert.StartsWith('Erwartet: ")"', mError);
  mError := ErrorOf('classes limit viele', mColumn, mSuggestion);
  Assert.StartsWith('Erwartet: Anzahl nach `limit`', mError);
end;

procedure TQueryLanguageTests.PredicateOnlyOnItsEntities;
var
  mColumn: Integer;
  mSuggestion, mError: string;
begin
  mError := ErrorOf('units where calls Foo', mColumn, mSuggestion);
  Assert.AreEqual('`calls` gibt es bei `units` nicht', mError);
  mError := ErrorOf('units where has attribute Test', mColumn, mSuggestion);
  Assert.AreEqual('`has attribute` gibt es bei `units` nicht', mError);
  mError := ErrorOf('methods where has Test', mColumn, mSuggestion);
  Assert.AreEqual('attribute', mSuggestion);
end;

procedure TQueryLanguageTests.UsedFieldsInOrder;
var
  mAst: TQueryAst;
  mFields: TArray<string>;
begin
  mAst := TQueryParser.Parse('methods where complexity > 15 and callers = 0 or complexity > 30 order by lines');
  try
    mFields := mAst.UsedFields;
    Assert.AreEqual(Integer(3), Integer(Length(mFields)));
    Assert.AreEqual('complexity', mFields[0]);
    Assert.AreEqual('callers', mFields[1]);
    Assert.AreEqual('lines', mFields[2]);
  finally
    mAst.Free;
  end;
end;

procedure TQueryLanguageTests.CatalogNamesEveryEntityAndField;
var
  mEntity: TQueryEntity;
  mFound: TQueryEntity;
  mField: TQueryFieldInfo;
begin
  for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
  begin
    Assert.IsTrue(TQueryCatalog.TryEntity(TQueryCatalog.EntityName(mEntity), mFound));
    Assert.IsTrue(mFound = mEntity);
    Assert.IsTrue(Length(TQueryCatalog.FieldNames(mEntity)) >= 4, TQueryCatalog.EntityName(mEntity));
  end;
  Assert.IsTrue(TQueryCatalog.TryField('USEDBY', mField));
  Assert.AreEqual('usedBy', mField.Name);
  Assert.IsTrue(TQueryEntity.Units in mField.Entities);
  Assert.Contains(TQueryCatalog.Help, 'has attribute');
end;

end.
