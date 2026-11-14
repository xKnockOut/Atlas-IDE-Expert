unit Atlas.Core.Editor.ExpressionType.Tests;

// Typ des markierten Ausdrucks (#689), Kern im Plugin: Argumente, Lesen der
// Antwort, Zeilen des Tooltips, Erweitern bei erneutem Drücken und der Teil
// einer Zeile für die Hervorhebung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.ExpressionType;

type
  [TestFixture]
  TAtlasExpressionTypeTests = class
  private
    function Texts: TAtlasExpressionTypeTexts;
  public
    [Test]
    procedure ArgumentsCarryRangeAndSwitches;
    [Test]
    procedure ReadsFullAnswer;
    [Test]
    procedure ReadsErrorAndRejectsForeignAnswers;
    [Test]
    procedure RowsForTypeValueConversionsAndOverload;
    [Test]
    procedure RowsForErrors;
    [Test]
    procedure ExpandsOnlyOnUnchangedState;
    [Test]
    procedure SpanCoversExpressionLines;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.TextChanges;

const
  cAnswer =
    '{"range": {"start": {"line": 11, "character": 11}, "end": {"line": 11, "character": 24}},' +
    ' "expression": "Price * Count", "type": "TPreis", "base": "Currency",' +
    ' "location": {"file": "C:\\P\\Preise.pas", "line": 3, "character": 2},' +
    ' "conversions": [{"expression": "Count", "from": "Integer", "to": "Currency", "kind": "widen"},' +
    ' {"expression": "V", "from": "Variant", "to": "string", "kind": "convert"}],' +
    ' "overload": "function Max(A, B: Double): Double;", "value": 48}';

function Parse(const AJson: string): TAtlasExpressionTypeInfo;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsTrue(TAtlasExpressionType.Read(mValue, Result), AJson);
  finally
    mValue.Free;
  end;
end;

function RowsText(const ARows: TArray<TAtlasExpressionTypeRow>): string;
var
  mRow: TAtlasExpressionTypeRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    Result := Result + mRow.Text + '|';
  end;
end;

{ TAtlasExpressionTypeTests }

function TAtlasExpressionTypeTests.Texts: TAtlasExpressionTypeTexts;
begin
  Result := Default(TAtlasExpressionTypeTexts);
  Result.Value := '= %s';
  Result.Widen := '%s: %s widen %s';
  Result.Convert := '%s: %s convert %s';
  Result.Overload := 'overload %s';
  Result.NoExpression := 'no expression';
  Result.UnknownName := 'unknown name %s';
  Result.OperatorMismatch := '%s: %s and %s';
  Result.OperatorUnary := '%s: %s';
  Result.NoResult := 'no result %s';
  Result.Unknown := 'unknown %s';
  Result.Expand := 'again';
end;

procedure TAtlasExpressionTypeTests.ArgumentsCarryRangeAndSwitches;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mOptions: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasExpressionType.Arguments('file:///C:/P/A.pas',
    TLspRange.Create(4, 2, 4, 9), True, False, True));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mList := TJSONArray(mValue);
    Assert.AreEqual(3, mList.Count);
    Assert.AreEqual('file:///C:/P/A.pas', mList.Items[0].Value);
    Assert.AreEqual('9', ((mList.Items[1] as TJSONObject).GetValue('end') as TJSONObject).GetValue('character').Value);
    mOptions := mList.Items[2] as TJSONObject;
    Assert.AreEqual('true', mOptions.GetValue('expand').ToJSON);
    Assert.AreEqual('false', mOptions.GetValue('conversions').ToJSON);
    Assert.AreEqual('true', mOptions.GetValue('constValue').ToJSON);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasExpressionTypeTests.ReadsFullAnswer;
var
  mInfo: TAtlasExpressionTypeInfo;
begin
  mInfo := Parse(cAnswer);
  Assert.AreEqual(11, mInfo.Range.StartPos.Line);
  Assert.AreEqual(24, mInfo.Range.EndPos.Character);
  Assert.AreEqual('Price * Count', mInfo.Expression);
  Assert.AreEqual('TPreis', mInfo.TypeName);
  Assert.AreEqual('Currency', mInfo.BaseName);
  Assert.IsTrue(mInfo.HasLocation);
  Assert.AreEqual('C:\P\Preise.pas', mInfo.FileName);
  Assert.AreEqual(3, mInfo.Line);
  Assert.AreEqual(2, mInfo.Character);
  Assert.AreEqual(2, Integer(Length(mInfo.Conversions)));
  Assert.IsFalse(mInfo.Conversions[0].Convert);
  Assert.IsTrue(mInfo.Conversions[1].Convert);
  Assert.AreEqual('Variant', mInfo.Conversions[1].FromType);
  Assert.AreEqual('function Max(A, B: Double): Double;', mInfo.Overload);
  Assert.IsTrue(mInfo.HasValue);
  Assert.AreEqual(Int64(48), mInfo.Value);
  Assert.AreEqual('', mInfo.Error);
end;

procedure TAtlasExpressionTypeTests.ReadsErrorAndRejectsForeignAnswers;
var
  mInfo: TAtlasExpressionTypeInfo;
  mValue: TJSONValue;
begin
  mInfo := Parse('{"expression": "Count + Nichts", "type": "", "base": "", "conversions": [],' +
    ' "overload": "", "error": {"kind": "unknownName", "detail": "Nichts"}}');
  Assert.AreEqual('unknownName', mInfo.Error);
  Assert.AreEqual('Nichts', mInfo.ErrorDetail);
  Assert.IsFalse(mInfo.HasValue);
  Assert.IsFalse(mInfo.HasLocation);
  // Weder Typ noch Fehler bzw. kein Objekt: nicht verwertbar.
  mValue := TJSONObject.ParseJSONValue('{"expression": "X"}');
  try
    Assert.IsFalse(TAtlasExpressionType.Read(mValue, mInfo));
    Assert.IsFalse(mInfo.Usable);
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue('[1]');
  try
    Assert.IsFalse(TAtlasExpressionType.Read(mValue, mInfo));
  finally
    mValue.Free;
  end;
  Assert.IsFalse(TAtlasExpressionType.Read(nil, mInfo));
end;

procedure TAtlasExpressionTypeTests.RowsForTypeValueConversionsAndOverload;
var
  mRows: TArray<TAtlasExpressionTypeRow>;
  mInfo: TAtlasExpressionTypeInfo;
  mPlain: TAtlasExpressionTypeTexts;
begin
  mRows := TAtlasExpressionType.Rows(Parse(cAnswer), Texts);
  Assert.AreEqual('Price * Count|TPreis = Currency|= 48|Count: Integer widen Currency|V: Variant convert string|' +
    'overload function Max(A, B: Double): Double;|again|', RowsText(mRows));
  Assert.AreEqual<TAtlasExpressionTypeRowKind>(TAtlasExpressionTypeRowKind.TypeName, mRows[1].Kind);
  Assert.IsTrue(mRows[1].Link, 'mit Fundort anklickbar');
  Assert.IsFalse(mRows[0].Link);
  Assert.AreEqual<TAtlasExpressionTypeRowKind>(TAtlasExpressionTypeRowKind.Hint, mRows[High(mRows)].Kind);
  // Ohne Fundort, ohne Alias und ohne Erweitern-Text.
  mInfo := Default(TAtlasExpressionTypeInfo);
  mInfo.Expression := 'I';
  mInfo.TypeName := 'Integer';
  mInfo.BaseName := 'Integer';
  mPlain := Texts;
  mPlain.Expand := '';
  mRows := TAtlasExpressionType.Rows(mInfo, mPlain);
  Assert.AreEqual('I|Integer|', RowsText(mRows));
  Assert.IsFalse(mRows[1].Link);
end;

procedure TAtlasExpressionTypeTests.RowsForErrors;
var
  mInfo: TAtlasExpressionTypeInfo;
begin
  mInfo := Default(TAtlasExpressionTypeInfo);
  mInfo.Expression := 'Count + Nichts';
  mInfo.Error := 'unknownName';
  mInfo.ErrorDetail := 'Nichts';
  Assert.AreEqual('Count + Nichts|unknown name Nichts|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)));
  mInfo.Error := 'operator';
  mInfo.ErrorDetail := '-|string|Integer';
  Assert.AreEqual('Count + Nichts|-: string and Integer|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)));
  mInfo.ErrorDetail := 'not||Double';
  Assert.AreEqual('Count + Nichts|not: Double|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)));
  mInfo.ErrorDetail := '';
  Assert.AreEqual('Count + Nichts|unknown Count + Nichts|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)),
    'ohne Detail der Ausdruck');
  mInfo.Error := 'noResult';
  mInfo.ErrorDetail := 'Free';
  Assert.AreEqual('Count + Nichts|no result Free|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)));
  mInfo.Error := 'somethingNew';
  Assert.AreEqual('Count + Nichts|unknown Free|again|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)));
  mInfo := Default(TAtlasExpressionTypeInfo);
  mInfo.Error := 'noExpression';
  Assert.AreEqual('no expression|', RowsText(TAtlasExpressionType.Rows(mInfo, Texts)), 'ohne Erweitern-Zeile');
end;

procedure TAtlasExpressionTypeTests.ExpandsOnlyOnUnchangedState;
var
  mShown: TAtlasExpressionTypeShown;
  mRange: TLspRange;
  mExpand: Boolean;
  mInfo: TAtlasExpressionTypeInfo;
begin
  mShown := Default(TAtlasExpressionTypeShown);
  mShown.Active := True;
  mShown.FileName := 'C:\P\A.pas';
  mShown.Text := 'Text';
  mShown.Selection := TLspRange.Create(4, 6, 4, 6);
  mShown.Range := TLspRange.Create(4, 5, 4, 10);
  TAtlasExpressionType.NextRequest(mShown, 'c:\p\a.pas', 'Text', TLspRange.Create(4, 6, 4, 6), mRange, mExpand);
  Assert.IsTrue(mExpand);
  Assert.IsTrue(mRange.Same(mShown.Range), 'vom gezeigten Ausdruck aus');
  // Schreibmarke bewegt, Text geändert, andere Datei, Tooltip zu: von vorn.
  TAtlasExpressionType.NextRequest(mShown, 'C:\P\A.pas', 'Text', TLspRange.Create(4, 7, 4, 7), mRange, mExpand);
  Assert.IsFalse(mExpand);
  Assert.AreEqual(7, mRange.StartPos.Character);
  TAtlasExpressionType.NextRequest(mShown, 'C:\P\A.pas', 'Text!', TLspRange.Create(4, 6, 4, 6), mRange, mExpand);
  Assert.IsFalse(mExpand);
  TAtlasExpressionType.NextRequest(mShown, 'C:\P\B.pas', 'Text', TLspRange.Create(4, 6, 4, 6), mRange, mExpand);
  Assert.IsFalse(mExpand);
  mShown.Active := False;
  TAtlasExpressionType.NextRequest(mShown, 'C:\P\A.pas', 'Text', TLspRange.Create(4, 6, 4, 6), mRange, mExpand);
  Assert.IsFalse(mExpand);
  // Kein größerer Ausdruck beim Erweitern: Tooltip bleibt; ohne Erweitern wird der Fehler gezeigt.
  mInfo := Default(TAtlasExpressionTypeInfo);
  mInfo.Error := 'noExpression';
  Assert.IsTrue(TAtlasExpressionType.KeepShown(True, mInfo));
  Assert.IsFalse(TAtlasExpressionType.KeepShown(False, mInfo));
  mInfo.Error := 'unknownName';
  Assert.IsFalse(TAtlasExpressionType.KeepShown(True, mInfo));
end;

procedure TAtlasExpressionTypeTests.SpanCoversExpressionLines;
var
  mSpan: TAtlasExpressionTypeSpan;
  mRange: TLspRange;
begin
  mRange := TLspRange.Create(2, 4, 4, 3);
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(mRange, 1, 20, mSpan));
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(mRange, 2, 20, mSpan));
  Assert.AreEqual(4, mSpan.Start);
  Assert.AreEqual(20, mSpan.Stop);
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(mRange, 3, 12, mSpan));
  Assert.AreEqual(0, mSpan.Start);
  Assert.AreEqual(12, mSpan.Stop);
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(mRange, 4, 12, mSpan));
  Assert.AreEqual(3, mSpan.Stop);
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(mRange, 5, 12, mSpan));
  // Leerer Bereich (Cursor) und Zeile kürzer als der Anfang.
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(TLspRange.Create(2, 4, 2, 4), 2, 20, mSpan));
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(TLspRange.Create(2, 30, 2, 34), 2, 20, mSpan));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExpressionTypeTests);

end.
