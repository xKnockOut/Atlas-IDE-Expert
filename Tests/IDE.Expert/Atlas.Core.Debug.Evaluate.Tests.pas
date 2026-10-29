unit Atlas.Core.Debug.Evaluate.Tests;

// Fenster „Auswerten“ (#784) ohne IDE: Ergebnis-Strings des Debuggers in
// Baumknoten zerlegen (Objekte, Records, Arrays, verschachtelt, Strings mit
// ; und Klammern), Stringliterale, Ansichten Text, Zeilen, JSON und Hex,
// Feldausdrücke, Ausdruck unter dem Cursor (Strg+F7), Felder vom Server, Baum mit Markierung geänderter Werte über Halte, Teile ohne
// Server, offene Knoten in Anzeigereihenfolge, festgeheftete Ausdrücke.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDebugEvaluateTests = class
  public
    [Test]
    procedure PartsOfObject;
    [Test]
    procedure PartsOfArrayAndNested;
    [Test]
    procedure NotStructured;
    [Test]
    procedure DecodesStrings;
    [Test]
    procedure SimpleValues;
    [Test]
    procedure FieldExpressions;
    [Test]
    procedure ExpressionUnderCursor;
    [Test]
    procedure FieldsFromServer;
    [Test]
    procedure ViewsTextAndLines;
    [Test]
    procedure ViewsJsonAndHex;
    [Test]
    procedure MarksChangedAcrossStops;
    [Test]
    procedure FieldsAreEvaluatedWhenExpanded;
    [Test]
    procedure PartsWithoutServer;
    [Test]
    procedure PinnedAndDuplicates;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.Evaluate;

{ TAtlasDebugEvaluateTests }

procedure TAtlasDebugEvaluateTests.PartsOfObject;
var
  Parts: TAtlasEvalParts;
begin
  Parts := TAtlasEvalText.Parts('(FName: ''Meier; (GmbH)''; FCount: 3; FList: $01234567)');
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual('FName', Parts[0].Name);
  Assert.AreEqual('''Meier; (GmbH)''', Parts[0].Value, '; und Klammern im String');
  Assert.AreEqual('FCount', Parts[1].Name);
  Assert.AreEqual('3', Parts[1].Value);
  Assert.AreEqual('$01234567', Parts[2].Value);
  Parts := TAtlasEvalText.Parts('(X = 1, Y = 2)');
  Assert.AreEqual('Y', Parts[1].Name, 'mit Gleichheitszeichen');
  Assert.AreEqual('2', Parts[1].Value);
end;

procedure TAtlasDebugEvaluateTests.PartsOfArrayAndNested;
var
  Parts, Inner: TAtlasEvalParts;
begin
  Parts := TAtlasEvalText.Parts('(1, 2, 3)');
  Assert.AreEqual(3, Integer(Length(Parts)));
  Assert.AreEqual('[0]', Parts[0].Name);
  Assert.IsTrue(Parts[2].Indexed);
  Assert.AreEqual('3', Parts[2].Value);
  Parts := TAtlasEvalText.Parts('(Kopf: (X: 1; Y: (A: ''a'')); Liste: (5, 6))');
  Assert.AreEqual(2, Integer(Length(Parts)));
  Assert.AreEqual('(X: 1; Y: (A: ''a''))', Parts[0].Value);
  Inner := TAtlasEvalText.Parts(Parts[0].Value);
  Assert.AreEqual('Y', Inner[1].Name);
  Assert.AreEqual('(A: ''a'')', Inner[1].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasEvalText.Parts('()'))), 'leer');
end;

procedure TAtlasDebugEvaluateTests.NotStructured;
begin
  Assert.IsFalse(TAtlasEvalText.IsStructured('(1) + (2)'));
  Assert.IsFalse(TAtlasEvalText.IsStructured('''(nur Text)'''));
  Assert.IsFalse(TAtlasEvalText.IsStructured('(offen'));
  Assert.IsFalse(TAtlasEvalText.IsStructured('(''offen)'));
  Assert.IsTrue(TAtlasEvalText.IsStructured(' (A: '')'') '));
end;

procedure TAtlasDebugEvaluateTests.DecodesStrings;
var
  Text: string;
begin
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''Zeile 1''#13#10''Zeile 2''', Text));
  Assert.AreEqual('Zeile 1'#13#10'Zeile 2', Text);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''O''''Neil''', Text));
  Assert.AreEqual('O''Neil', Text);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('#$41#66''''', Text));
  Assert.AreEqual('AB', Text);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''''', Text));
  Assert.AreEqual('', Text);
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''offen', Text));
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''ab''''', Text), 'endet mit Verdopplung');
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('42', Text));
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''a'' + ''b''', Text));
end;

procedure TAtlasDebugEvaluateTests.SimpleValues;
begin
  Assert.IsTrue(TAtlasEvalText.IsSimple('42'));
  Assert.IsTrue(TAtlasEvalText.IsSimple('-3.5'));
  Assert.IsTrue(TAtlasEvalText.IsSimple('''Text'''));
  Assert.IsTrue(TAtlasEvalText.IsSimple('nil'));
  Assert.IsTrue(TAtlasEvalText.IsSimple('True'));
  Assert.IsTrue(TAtlasEvalText.IsSimple('alClient'), 'Aufzählungswert');
  Assert.IsFalse(TAtlasEvalText.IsSimple('(A: 1)'));
  Assert.IsFalse(TAtlasEvalText.IsSimple('$0040A0B0'), 'Zeiger lässt sich aufklappen');
end;

procedure TAtlasDebugEvaluateTests.FieldExpressions;
begin
  Assert.AreEqual('Self.FName', TAtlasEvalText.FieldExpression('Self', 'FName'));
  Assert.AreEqual('Liste[0].Name', TAtlasEvalText.FieldExpression('Liste[0]', 'Name'));
  Assert.AreEqual('P^.X', TAtlasEvalText.FieldExpression('P^', 'X'));
  Assert.AreEqual('(TKunde(Sender)).Name', TAtlasEvalText.FieldExpression('TKunde(Sender)', 'Name'));
end;

procedure TAtlasDebugEvaluateTests.ExpressionUnderCursor;
const
  Line = '  Summe := Kunde.Adresse.Ort + P^.X;';
begin
  Assert.AreEqual('Kunde.Adresse', TAtlasEvalText.ExpressionAt(Line, 17), 'bis zum Wortende');
  Assert.AreEqual('Kunde.Adresse.Ort', TAtlasEvalText.ExpressionAt(Line, 28), 'hinter dem Wort');
  Assert.AreEqual('Summe', TAtlasEvalText.ExpressionAt(Line, 2), 'Wortanfang');
  Assert.AreEqual('P^.X', TAtlasEvalText.ExpressionAt(Line, 35));
  Assert.AreEqual('', TAtlasEvalText.ExpressionAt(Line, 0), 'Einrückung');
  Assert.AreEqual('', TAtlasEvalText.ExpressionAt('', 0));
  Assert.AreEqual('x', TAtlasEvalText.ExpressionAt('3.x', 3), 'Zahl vorn gehört nicht dazu');
end;

procedure TAtlasDebugEvaluateTests.FieldsFromServer;
var
  Response: TJSONValue;
  Fields: TArray<string>;
begin
  Response := TJSONObject.ParseJSONValue('{"prefix":"","items":[{"label":"FName","kind":5},' +
    '{"label":"Count","kind":10},{"label":"Free","kind":2},{"label":"fname","kind":5},{"kind":5},' +
    '{"label":"FList","kind":5}]}');
  try
    Fields := TAtlasEvalText.FieldsOf(Response, False);
    Assert.AreEqual(2, Integer(Length(Fields)), 'ohne Eigenschaft, Methode und Doppelte');
    Assert.AreEqual('FName', Fields[0]);
    Assert.AreEqual('FList', Fields[1]);
    Fields := TAtlasEvalText.FieldsOf(Response, True);
    Assert.AreEqual(3, Integer(Length(Fields)), 'mit Nebenwirkungen auch Eigenschaften');
    Assert.AreEqual('Count', Fields[1]);
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasEvalText.FieldsOf(nil, True))));
end;

procedure TAtlasDebugEvaluateTests.ViewsTextAndLines;
var
  Text: string;
begin
  Assert.IsTrue(TAtlasEvalText.Render('''a''#9''b''#13#10''c''', TAtlasEvalView.Text, Text));
  Assert.AreEqual('a'#$2192'b'#$240D#$240A + sLineBreak + 'c', Text);
  Assert.AreEqual('x'#$2400'y', TAtlasEvalText.VisibleText('x'#0'y'));
  Assert.IsTrue(TAtlasEvalText.Render('''eins''#13#10''zwei''#13#10', TAtlasEvalView.Lines, Text));
  Assert.AreEqual('eins' + sLineBreak + 'zwei', Text, 'Umbruch am Ende ohne leere Zeile');
  Assert.AreEqual(3, Integer(Length(TAtlasEvalText.StringsLines('a'#10'b'#13'c'))));
  Assert.AreEqual(0, Integer(Length(TAtlasEvalText.StringsLines(''))));
end;

procedure TAtlasDebugEvaluateTests.ViewsJsonAndHex;
var
  Text: string;
begin
  Assert.IsTrue(TAtlasEvalText.Render('''{"a":1,"b":[true,"x:y"]}''', TAtlasEvalView.Json, Text));
  Assert.AreEqual('{' + sLineBreak + '  "a": 1,' + sLineBreak + '  "b": [' + sLineBreak + '    true,' + sLineBreak +
    '    "x:y"' + sLineBreak + '  ]' + sLineBreak + '}', Text);
  Assert.IsFalse(TAtlasEvalText.Render('''kein JSON''', TAtlasEvalView.Json, Text));
  Assert.AreEqual('kein JSON', Text, 'Rückfall Text');
  Assert.IsTrue(TAtlasEvalText.Render('42', TAtlasEvalView.Hex, Text));
  Assert.AreEqual('$0000002A (42)', Text);
  Assert.IsTrue(TAtlasEvalText.TryHex('-1', Text));
  Assert.AreEqual('$FFFFFFFF (-1)', Text);
  Assert.IsTrue(TAtlasEvalText.TryHex('4294967296', Text));
  Assert.AreEqual('$0000000100000000 (4294967296)', Text);
  Assert.IsFalse(TAtlasEvalText.TryHex('''x''', Text));
end;

procedure TAtlasDebugEvaluateTests.MarksChangedAcrossStops;
var
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
begin
  List := TAtlasEvalList.Create;
  try
    Node := List.Add(' Summe ');
    Assert.AreEqual('Summe', Node.Expression);
    Assert.IsTrue(Node.State = TAtlasEvalState.Pending);
    List.SetResult(Node, True, '1');
    Assert.IsFalse(Node.Changed, 'erster Halt');
    List.BeginStop;
    Assert.IsTrue(Node.State = TAtlasEvalState.Pending);
    List.SetResult(Node, True, '2');
    Assert.IsTrue(Node.Changed, 'geändert');
    List.BeginStop;
    List.SetResult(Node, True, '2');
    Assert.IsFalse(Node.Changed, 'gleich geblieben');
    List.BeginStop;
    List.SetResult(Node, False, 'Fehler');
    Assert.IsTrue(Node.State = TAtlasEvalState.Error);
    Assert.IsFalse(Node.Changed);
    List.BeginStop;
    List.SetResult(Node, True, '3');
    Assert.IsTrue(Node.Changed, 'verglichen mit dem letzten gültigen Wert');
    List.Unavailable;
    Assert.IsTrue(Node.State = TAtlasEvalState.Unavailable);
    Assert.IsNull(List.Add('  '));
  finally
    List.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.FieldsAreEvaluatedWhenExpanded;
var
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
  Pending: TArray<TAtlasEvalNode>;
begin
  List := TAtlasEvalList.Create;
  try
    Node := List.Add('Self');
    List.SetResult(Node, True, '($00A1B2C3)');
    Assert.IsTrue(Node.CanExpand);
    List.SetFields(Node, TArray<string>.Create('FName', 'FCount'));
    Assert.AreEqual(2, Node.ChildCount);
    Assert.AreEqual('Self.FCount', Node.Children[1].Expression);
    Assert.AreEqual(0, Integer(Length(List.Pending)), 'zugeklappt nichts offen');
    Node.Expanded := True;
    Pending := List.Pending;
    Assert.AreEqual(2, Integer(Length(Pending)));
    List.SetResult(Node.Children[1], True, '3');
    List.BeginStop;
    Pending := List.Pending;
    Assert.AreEqual(3, Integer(Length(Pending)), 'Wurzel und beide Felder');
    Assert.AreSame(Node, Pending[0]);
    List.SetResult(Node.Children[1], True, '4');
    Assert.IsTrue(Node.Children[1].Changed, 'Feld bis zum nächsten Halt geändert');
    Assert.AreSame(Node.Children[1], List.Find(Node.Children[1].Key));
    Assert.IsNull(List.Find('weg'));
  finally
    List.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.PartsWithoutServer;
var
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
begin
  List := TAtlasEvalList.Create;
  try
    Node := List.Add('Punkt');
    List.SetResult(Node, True, '(X: 1; Y: 2)');
    Assert.IsTrue(List.SetParts(Node));
    Node.Expanded := True;
    Assert.AreEqual(2, Node.ChildCount);
    Assert.AreEqual('', Node.Children[0].Expression, 'Wert steht fest');
    Assert.AreEqual('2', Node.Children[1].Value);
    Assert.AreEqual(0, Integer(Length(List.Pending)) - 0, 'Teile sind nicht offen');
    List.BeginStop;
    Assert.AreEqual(0, Node.ChildCount, 'Teile entstehen mit dem neuen Wert');
    List.SetResult(Node, True, '(X: 1; Y: 5)');
    Assert.AreEqual(2, Node.ChildCount);
    Assert.IsTrue(Node.Children[1].Changed, 'Y geändert');
    Assert.IsFalse(Node.Children[0].Changed);
    List.SetResult(Node, True, '7');
    Assert.IsFalse(List.SetParts(Node), 'einfacher Wert');
  finally
    List.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.PinnedAndDuplicates;
var
  List: TAtlasEvalList;
  First, Second: TAtlasEvalNode;
  Pinned: TArray<string>;
begin
  List := TAtlasEvalList.Create;
  try
    First := List.Add('A');
    Second := List.Add('A');
    Assert.AreNotEqual(First.Key, Second.Key, 'eigene Markierung je Zeile');
    List.Add('B').Pinned := True;
    First.Pinned := True;
    Pinned := List.PinnedExpressions;
    Assert.AreEqual(2, Integer(Length(Pinned)));
    Assert.AreEqual('A', Pinned[0]);
    Assert.AreEqual('B', Pinned[1]);
    List.Delete(List.IndexOf(First));
    Assert.AreEqual(2, List.Count);
  finally
    List.Free;
  end;
end;

end.
