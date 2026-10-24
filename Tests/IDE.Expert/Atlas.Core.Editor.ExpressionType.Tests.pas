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
  System.JSON,
  Atlas.Core.Lsp.TextChanges;

const
  Answer =
    '{"range": {"start": {"line": 11, "character": 11}, "end": {"line": 11, "character": 24}},' +
    ' "expression": "Price * Count", "type": "TPreis", "base": "Currency",' +
    ' "location": {"file": "C:\\P\\Preise.pas", "line": 3, "character": 2},' +
    ' "conversions": [{"expression": "Count", "from": "Integer", "to": "Currency", "kind": "widen"},' +
    ' {"expression": "V", "from": "Variant", "to": "string", "kind": "convert"}],' +
    ' "overload": "function Max(A, B: Double): Double;", "value": 48}';

function Parse(const AJson: string): TAtlasExpressionTypeInfo;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsTrue(TAtlasExpressionType.Read(Value, Result), AJson);
  finally
    Value.Free;
  end;
end;

function RowsText(const ARows: TArray<TAtlasExpressionTypeRow>): string;
var
  Row: TAtlasExpressionTypeRow;
begin
  Result := '';
  for Row in ARows do
    Result := Result + Row.Text + '|';
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
  Value: TJSONValue;
  List: TJSONArray;
  Options: TJSONObject;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasExpressionType.Arguments('file:///C:/P/A.pas',
    TLspRange.Create(4, 2, 4, 9), True, False, True));
  try
    Assert.IsTrue(Value is TJSONArray);
    List := TJSONArray(Value);
    Assert.AreEqual(3, List.Count);
    Assert.AreEqual('file:///C:/P/A.pas', List.Items[0].Value);
    Assert.AreEqual('9', ((List.Items[1] as TJSONObject).GetValue('end') as TJSONObject).GetValue('character').Value);
    Options := List.Items[2] as TJSONObject;
    Assert.AreEqual('true', Options.GetValue('expand').ToJSON);
    Assert.AreEqual('false', Options.GetValue('conversions').ToJSON);
    Assert.AreEqual('true', Options.GetValue('constValue').ToJSON);
  finally
    Value.Free;
  end;
end;

procedure TAtlasExpressionTypeTests.ReadsFullAnswer;
var
  Info: TAtlasExpressionTypeInfo;
begin
  Info := Parse(Answer);
  Assert.AreEqual(11, Info.Range.StartPos.Line);
  Assert.AreEqual(24, Info.Range.EndPos.Character);
  Assert.AreEqual('Price * Count', Info.Expression);
  Assert.AreEqual('TPreis', Info.TypeName);
  Assert.AreEqual('Currency', Info.BaseName);
  Assert.IsTrue(Info.HasLocation);
  Assert.AreEqual('C:\P\Preise.pas', Info.FileName);
  Assert.AreEqual(3, Info.Line);
  Assert.AreEqual(2, Info.Character);
  Assert.AreEqual(2, Integer(Length(Info.Conversions)));
  Assert.IsFalse(Info.Conversions[0].Convert);
  Assert.IsTrue(Info.Conversions[1].Convert);
  Assert.AreEqual('Variant', Info.Conversions[1].FromType);
  Assert.AreEqual('function Max(A, B: Double): Double;', Info.Overload);
  Assert.IsTrue(Info.HasValue);
  Assert.AreEqual(Int64(48), Info.Value);
  Assert.AreEqual('', Info.Error);
end;

procedure TAtlasExpressionTypeTests.ReadsErrorAndRejectsForeignAnswers;
var
  Info: TAtlasExpressionTypeInfo;
  Value: TJSONValue;
begin
  Info := Parse('{"expression": "Count + Nichts", "type": "", "base": "", "conversions": [],' +
    ' "overload": "", "error": {"kind": "unknownName", "detail": "Nichts"}}');
  Assert.AreEqual('unknownName', Info.Error);
  Assert.AreEqual('Nichts', Info.ErrorDetail);
  Assert.IsFalse(Info.HasValue);
  Assert.IsFalse(Info.HasLocation);
  // Weder Typ noch Fehler bzw. kein Objekt: nicht verwertbar.
  Value := TJSONObject.ParseJSONValue('{"expression": "X"}');
  try
    Assert.IsFalse(TAtlasExpressionType.Read(Value, Info));
    Assert.IsFalse(Info.Usable);
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue('[1]');
  try
    Assert.IsFalse(TAtlasExpressionType.Read(Value, Info));
  finally
    Value.Free;
  end;
  Assert.IsFalse(TAtlasExpressionType.Read(nil, Info));
end;

procedure TAtlasExpressionTypeTests.RowsForTypeValueConversionsAndOverload;
var
  Rows: TArray<TAtlasExpressionTypeRow>;
  Info: TAtlasExpressionTypeInfo;
  Plain: TAtlasExpressionTypeTexts;
begin
  Rows := TAtlasExpressionType.Rows(Parse(Answer), Texts);
  Assert.AreEqual('Price * Count|TPreis = Currency|= 48|Count: Integer widen Currency|V: Variant convert string|' +
    'overload function Max(A, B: Double): Double;|again|', RowsText(Rows));
  Assert.IsTrue(Rows[1].Kind = TAtlasExpressionTypeRowKind.TypeName);
  Assert.IsTrue(Rows[1].Link, 'mit Fundort anklickbar');
  Assert.IsFalse(Rows[0].Link);
  Assert.IsTrue(Rows[High(Rows)].Kind = TAtlasExpressionTypeRowKind.Hint);
  // Ohne Fundort, ohne Alias und ohne Erweitern-Text.
  Info := Default(TAtlasExpressionTypeInfo);
  Info.Expression := 'I';
  Info.TypeName := 'Integer';
  Info.BaseName := 'Integer';
  Plain := Texts;
  Plain.Expand := '';
  Rows := TAtlasExpressionType.Rows(Info, Plain);
  Assert.AreEqual('I|Integer|', RowsText(Rows));
  Assert.IsFalse(Rows[1].Link);
end;

procedure TAtlasExpressionTypeTests.RowsForErrors;
var
  Info: TAtlasExpressionTypeInfo;
begin
  Info := Default(TAtlasExpressionTypeInfo);
  Info.Expression := 'Count + Nichts';
  Info.Error := 'unknownName';
  Info.ErrorDetail := 'Nichts';
  Assert.AreEqual('Count + Nichts|unknown name Nichts|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)));
  Info.Error := 'operator';
  Info.ErrorDetail := '-|string|Integer';
  Assert.AreEqual('Count + Nichts|-: string and Integer|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)));
  Info.ErrorDetail := 'not||Double';
  Assert.AreEqual('Count + Nichts|not: Double|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)));
  Info.ErrorDetail := '';
  Assert.AreEqual('Count + Nichts|unknown Count + Nichts|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)),
    'ohne Detail der Ausdruck');
  Info.Error := 'noResult';
  Info.ErrorDetail := 'Free';
  Assert.AreEqual('Count + Nichts|no result Free|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)));
  Info.Error := 'somethingNew';
  Assert.AreEqual('Count + Nichts|unknown Free|again|', RowsText(TAtlasExpressionType.Rows(Info, Texts)));
  Info := Default(TAtlasExpressionTypeInfo);
  Info.Error := 'noExpression';
  Assert.AreEqual('no expression|', RowsText(TAtlasExpressionType.Rows(Info, Texts)), 'ohne Erweitern-Zeile');
end;

procedure TAtlasExpressionTypeTests.ExpandsOnlyOnUnchangedState;
var
  Shown: TAtlasExpressionTypeShown;
  Range: TLspRange;
  Expand: Boolean;
  Info: TAtlasExpressionTypeInfo;
begin
  Shown := Default(TAtlasExpressionTypeShown);
  Shown.Active := True;
  Shown.FileName := 'C:\P\A.pas';
  Shown.Text := 'Text';
  Shown.Selection := TLspRange.Create(4, 6, 4, 6);
  Shown.Range := TLspRange.Create(4, 5, 4, 10);
  TAtlasExpressionType.NextRequest(Shown, 'c:\p\a.pas', 'Text', TLspRange.Create(4, 6, 4, 6), Range, Expand);
  Assert.IsTrue(Expand);
  Assert.IsTrue(Range.Same(Shown.Range), 'vom gezeigten Ausdruck aus');
  // Schreibmarke bewegt, Text geändert, andere Datei, Tooltip zu: von vorn.
  TAtlasExpressionType.NextRequest(Shown, 'C:\P\A.pas', 'Text', TLspRange.Create(4, 7, 4, 7), Range, Expand);
  Assert.IsFalse(Expand);
  Assert.AreEqual(7, Range.StartPos.Character);
  TAtlasExpressionType.NextRequest(Shown, 'C:\P\A.pas', 'Text!', TLspRange.Create(4, 6, 4, 6), Range, Expand);
  Assert.IsFalse(Expand);
  TAtlasExpressionType.NextRequest(Shown, 'C:\P\B.pas', 'Text', TLspRange.Create(4, 6, 4, 6), Range, Expand);
  Assert.IsFalse(Expand);
  Shown.Active := False;
  TAtlasExpressionType.NextRequest(Shown, 'C:\P\A.pas', 'Text', TLspRange.Create(4, 6, 4, 6), Range, Expand);
  Assert.IsFalse(Expand);
  // Kein größerer Ausdruck beim Erweitern: Tooltip bleibt; ohne Erweitern wird der Fehler gezeigt.
  Info := Default(TAtlasExpressionTypeInfo);
  Info.Error := 'noExpression';
  Assert.IsTrue(TAtlasExpressionType.KeepShown(True, Info));
  Assert.IsFalse(TAtlasExpressionType.KeepShown(False, Info));
  Info.Error := 'unknownName';
  Assert.IsFalse(TAtlasExpressionType.KeepShown(True, Info));
end;

procedure TAtlasExpressionTypeTests.SpanCoversExpressionLines;
var
  Span: TAtlasExpressionTypeSpan;
  Range: TLspRange;
begin
  Range := TLspRange.Create(2, 4, 4, 3);
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(Range, 1, 20, Span));
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(Range, 2, 20, Span));
  Assert.AreEqual(4, Span.Start);
  Assert.AreEqual(20, Span.Stop);
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(Range, 3, 12, Span));
  Assert.AreEqual(0, Span.Start);
  Assert.AreEqual(12, Span.Stop);
  Assert.IsTrue(TAtlasExpressionType.SpanOnLine(Range, 4, 12, Span));
  Assert.AreEqual(3, Span.Stop);
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(Range, 5, 12, Span));
  // Leerer Bereich (Cursor) und Zeile kürzer als der Anfang.
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(TLspRange.Create(2, 4, 2, 4), 2, 20, Span));
  Assert.IsFalse(TAtlasExpressionType.SpanOnLine(TLspRange.Create(2, 30, 2, 34), 2, 20, Span));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExpressionTypeTests);

end.
