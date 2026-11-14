unit Atlas.Core.Debug.Evaluate.Tests;

// Fenster „Auswerten“ (#784) ohne IDE: Ergebnis-Strings des Debuggers in
// Baumknoten zerlegen (Objekte, Records, Arrays, verschachtelt, Strings mit
// ; und Klammern), Stringliterale, Ansichten Text, Zeilen, JSON und Hex,
// Feldausdrücke, Ausdruck unter dem Cursor (Strg+F7), Felder vom Server, Baum mit Markierung geänderter
// Werte über Halte, Teile ohne Server, offene Knoten in Anzeigereihenfolge, festgeheftete Ausdrücke,
// Suche über den Schlüsselpfad, Eingabe der Ansicht unten (unverändert:
// nichts neu berechnen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
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
    [Test]
    procedure FindFollowsKeyPath;
    [Test]
    procedure DetailInputSame;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.Evaluate;

{ TAtlasDebugEvaluateTests }

procedure TAtlasDebugEvaluateTests.PartsOfObject;
var
  mParts: TAtlasEvalParts;
begin
  mParts := TAtlasEvalText.Parts('(FName: ''Meier; (GmbH)''; FCount: 3; FList: $01234567)');
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual('FName', mParts[0].Name);
  Assert.AreEqual('''Meier; (GmbH)''', mParts[0].Value, '; und Klammern im String');
  Assert.AreEqual('FCount', mParts[1].Name);
  Assert.AreEqual('3', mParts[1].Value);
  Assert.AreEqual('$01234567', mParts[2].Value);
  mParts := TAtlasEvalText.Parts('(X = 1, Y = 2)');
  Assert.AreEqual('Y', mParts[1].Name, 'mit Gleichheitszeichen');
  Assert.AreEqual('2', mParts[1].Value);
end;

procedure TAtlasDebugEvaluateTests.PartsOfArrayAndNested;
var
  mParts, mInner: TAtlasEvalParts;
begin
  mParts := TAtlasEvalText.Parts('(1, 2, 3)');
  Assert.AreEqual(3, Integer(Length(mParts)));
  Assert.AreEqual('[0]', mParts[0].Name);
  Assert.IsTrue(mParts[2].Indexed);
  Assert.AreEqual('3', mParts[2].Value);
  mParts := TAtlasEvalText.Parts('(Kopf: (X: 1; Y: (A: ''a'')); Liste: (5, 6))');
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual('(X: 1; Y: (A: ''a''))', mParts[0].Value);
  mInner := TAtlasEvalText.Parts(mParts[0].Value);
  Assert.AreEqual('Y', mInner[1].Name);
  Assert.AreEqual('(A: ''a'')', mInner[1].Value);
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
  mText: string;
begin
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''Zeile 1''#13#10''Zeile 2''', mText));
  Assert.AreEqual('Zeile 1'#13#10'Zeile 2', mText);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''O''''Neil''', mText));
  Assert.AreEqual('O''Neil', mText);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('#$41#66''''', mText));
  Assert.AreEqual('AB', mText);
  Assert.IsTrue(TAtlasEvalText.TryDecodeString('''''', mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''offen', mText));
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''ab''''', mText), 'endet mit Verdopplung');
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('42', mText));
  Assert.IsFalse(TAtlasEvalText.TryDecodeString('''a'' + ''b''', mText));
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
  // ",r" für Feldnamen; eigene Formatangabe und Kommas in Klammern bzw. Strings.
  Assert.AreEqual('GFeatures[N],r', TAtlasEvalText.WithFieldNames('GFeatures[N]'));
  Assert.AreEqual('Format(''%d,%d'', [A, B]),r', TAtlasEvalText.WithFieldNames('Format(''%d,%d'', [A, B])'));
  Assert.AreEqual('X,h', TAtlasEvalText.WithFieldNames('X,h'));
  Assert.AreEqual('', TAtlasEvalText.WithFieldNames(''));
  // Feldnamen landen als Namen der Teile im Baum.
  Assert.AreEqual('Id', TAtlasEvalText.Parts('(FeatureClass: TSchemaFeature; Id: ''schema''; Order: 10)')[1].Name);
end;

procedure TAtlasDebugEvaluateTests.ExpressionUnderCursor;
const
  cLine = '  Summe := Kunde.Adresse.Ort + P^.X;';
begin
  Assert.AreEqual('Kunde.Adresse', TAtlasEvalText.ExpressionAt(cLine, 17), 'bis zum Wortende');
  Assert.AreEqual('Kunde.Adresse.Ort', TAtlasEvalText.ExpressionAt(cLine, 28), 'hinter dem Wort');
  Assert.AreEqual('Summe', TAtlasEvalText.ExpressionAt(cLine, 2), 'Wortanfang');
  Assert.AreEqual('P^.X', TAtlasEvalText.ExpressionAt(cLine, 35));
  Assert.AreEqual('', TAtlasEvalText.ExpressionAt(cLine, 0), 'Einrückung');
  Assert.AreEqual('', TAtlasEvalText.ExpressionAt('', 0));
  Assert.AreEqual('x', TAtlasEvalText.ExpressionAt('3.x', 3), 'Zahl vorn gehört nicht dazu');
end;

procedure TAtlasDebugEvaluateTests.FieldsFromServer;
var
  mResponse: TJSONValue;
  mFields: TArray<string>;
begin
  mResponse := TJSONObject.ParseJSONValue('{"prefix":"","items":[{"label":"FName","kind":5},' +
    '{"label":"Count","kind":10},{"label":"Free","kind":2},{"label":"fname","kind":5},{"kind":5},' +
    '{"label":"FList","kind":5}]}');
  try
    mFields := TAtlasEvalText.FieldsOf(mResponse, False);
    Assert.AreEqual(2, Integer(Length(mFields)), 'ohne Eigenschaft, Methode und Doppelte');
    Assert.AreEqual('FName', mFields[0]);
    Assert.AreEqual('FList', mFields[1]);
    mFields := TAtlasEvalText.FieldsOf(mResponse, True);
    Assert.AreEqual(3, Integer(Length(mFields)), 'mit Nebenwirkungen auch Eigenschaften');
    Assert.AreEqual('Count', mFields[1]);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasEvalText.FieldsOf(nil, True))));
end;

procedure TAtlasDebugEvaluateTests.ViewsTextAndLines;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasEvalText.Render('''a''#9''b''#13#10''c''', TAtlasEvalView.Text, mText));
  Assert.AreEqual('a'#$2192'b'#$240D#$240A + sLineBreak + 'c', mText);
  Assert.AreEqual('x'#$2400'y', TAtlasEvalText.VisibleText('x'#0'y'));
  Assert.IsTrue(TAtlasEvalText.Render('''eins''#13#10''zwei''#13#10', TAtlasEvalView.Lines, mText));
  Assert.AreEqual('eins' + sLineBreak + 'zwei', mText, 'Umbruch am Ende ohne leere Zeile');
  Assert.AreEqual(3, Integer(Length(TAtlasEvalText.StringsLines('a'#10'b'#13'c'))));
  Assert.AreEqual(0, Integer(Length(TAtlasEvalText.StringsLines(''))));
end;

procedure TAtlasDebugEvaluateTests.ViewsJsonAndHex;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasEvalText.Render('''{"a":1,"b":[true,"x:y"]}''', TAtlasEvalView.Json, mText));
  Assert.AreEqual('{' + sLineBreak + '  "a": 1,' + sLineBreak + '  "b": [' + sLineBreak + '    true,' + sLineBreak +
    '    "x:y"' + sLineBreak + '  ]' + sLineBreak + '}', mText);
  Assert.IsFalse(TAtlasEvalText.Render('''kein JSON''', TAtlasEvalView.Json, mText));
  Assert.AreEqual('kein JSON', mText, 'Rückfall Text');
  Assert.IsTrue(TAtlasEvalText.Render('42', TAtlasEvalView.Hex, mText));
  Assert.AreEqual('$0000002A (42)', mText);
  Assert.IsTrue(TAtlasEvalText.TryHex('-1', mText));
  Assert.AreEqual('$FFFFFFFF (-1)', mText);
  Assert.IsTrue(TAtlasEvalText.TryHex('4294967296', mText));
  Assert.AreEqual('$0000000100000000 (4294967296)', mText);
  Assert.IsFalse(TAtlasEvalText.TryHex('''x''', mText));
end;

procedure TAtlasDebugEvaluateTests.MarksChangedAcrossStops;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add(' Summe ');
    Assert.AreEqual('Summe', mNode.Expression);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mNode.State);
    mList.SetResult(mNode, True, '1');
    Assert.IsFalse(mNode.Changed, 'erster Halt');
    mList.BeginStop;
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mNode.State);
    mList.SetResult(mNode, True, '2');
    Assert.IsTrue(mNode.Changed, 'geändert');
    mList.BeginStop;
    mList.SetResult(mNode, True, '2');
    Assert.IsFalse(mNode.Changed, 'gleich geblieben');
    mList.BeginStop;
    mList.SetResult(mNode, False, 'Fehler');
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Error, mNode.State);
    Assert.IsFalse(mNode.Changed);
    mList.BeginStop;
    mList.SetResult(mNode, True, '3');
    Assert.IsTrue(mNode.Changed, 'verglichen mit dem letzten gültigen Wert');
    mList.Unavailable;
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Unavailable, mNode.State);
    Assert.IsNull(mList.Add('  '));
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.FieldsAreEvaluatedWhenExpanded;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mPending: TArray<TAtlasEvalNode>;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('Self');
    mList.SetResult(mNode, True, '($00A1B2C3)');
    Assert.IsTrue(mNode.CanExpand);
    mList.SetFields(mNode, TArray<string>.Create('FName', 'FCount'));
    Assert.AreEqual(2, mNode.ChildCount);
    Assert.AreEqual('Self.FCount', mNode.Children[1].Expression);
    Assert.AreEqual(0, Integer(Length(mList.Pending)), 'zugeklappt nichts offen');
    mNode.Expanded := True;
    mPending := mList.Pending;
    Assert.AreEqual(2, Integer(Length(mPending)));
    mList.SetResult(mNode.Children[1], True, '3');
    mList.BeginStop;
    mPending := mList.Pending;
    Assert.AreEqual(3, Integer(Length(mPending)), 'Wurzel und beide Felder');
    Assert.AreSame(mNode, mPending[0]);
    mList.SetResult(mNode.Children[1], True, '4');
    Assert.IsTrue(mNode.Children[1].Changed, 'Feld bis zum nächsten Halt geändert');
    Assert.AreSame(mNode.Children[1], mList.Find(mNode.Children[1].Key));
    Assert.IsNull(mList.Find('weg'));
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.PartsWithoutServer;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('Punkt');
    mList.SetResult(mNode, True, '(X: 1; Y: 2)');
    Assert.IsTrue(mList.SetParts(mNode));
    mNode.Expanded := True;
    Assert.AreEqual(2, mNode.ChildCount);
    Assert.AreEqual('', mNode.Children[0].Expression, 'Wert steht fest');
    Assert.AreEqual('2', mNode.Children[1].Value);
    Assert.AreEqual(0, Integer(Length(mList.Pending)) - 0, 'Teile sind nicht offen');
    mList.BeginStop;
    Assert.AreEqual(0, mNode.ChildCount, 'Teile entstehen mit dem neuen Wert');
    mList.SetResult(mNode, True, '(X: 1; Y: 5)');
    Assert.AreEqual(2, mNode.ChildCount);
    Assert.IsTrue(mNode.Children[1].Changed, 'Y geändert');
    Assert.IsFalse(mNode.Children[0].Changed);
    mList.SetResult(mNode, True, '7');
    Assert.IsFalse(mList.SetParts(mNode), 'einfacher Wert');
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.PinnedAndDuplicates;
var
  mList: TAtlasEvalList;
  mFirst, mSecond: TAtlasEvalNode;
  mPinned: TArray<string>;
begin
  mList := TAtlasEvalList.Create;
  try
    mFirst := mList.Add('A');
    mSecond := mList.Add('A');
    Assert.AreNotEqual(mFirst.Key, mSecond.Key, 'eigene Markierung je Zeile');
    mList.Add('B').Pinned := True;
    mFirst.Pinned := True;
    mPinned := mList.PinnedExpressions;
    Assert.AreEqual(2, Integer(Length(mPinned)));
    Assert.AreEqual('A', mPinned[0]);
    Assert.AreEqual('B', mPinned[1]);
    mList.Delete(mList.IndexOf(mFirst));
    Assert.AreEqual(2, mList.Count);
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.FindFollowsKeyPath;
var
  mList: TAtlasEvalList;
  mShort, mLong, mChild, mDouble: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    // „A“ ist Präfix von „AB“, aber kein Elternknoten: Die Suche muss bei „AB“ weitermachen.
    mShort := mList.Add('A');
    mShort.AddChild('X', 'A.X');
    mLong := mList.Add('AB');
    mChild := mLong.AddChild('X', 'AB.X');
    mDouble := mChild.AddChild('Y', 'AB.X.Y');
    Assert.AreSame(mChild, mList.Find('AB'#1'X'), 'Kind unter AB');
    Assert.AreSame(mDouble, mList.Find('AB'#1'X'#1'Y'), 'Enkel');
    Assert.AreSame(mShort.Children[0], mList.Find('A'#1'X'), 'Kind unter A');
    Assert.AreSame(mLong, mList.Find('AB'));
    Assert.IsNull(mList.Find('A'#1'Z'));
    Assert.IsNull(mList.Find('AB'#1));
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateTests.DetailInputSame;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mFirst, mNext: TAtlasEvalDetailInput;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('S');
    mList.SetResult(mNode, True, '''eins''');
    mFirst := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Text, False, '');
    mNext := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Text, False, '');
    Assert.IsTrue(mNext.Same(mFirst), 'unverändert');
    Assert.IsFalse(mNext.Same(Default(TAtlasEvalDetailInput)), 'noch nichts gezeigt');
    mNext := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Json, False, '');
    Assert.IsFalse(mNext.Same(mFirst), 'andere Ansicht');
    mList.SetResult(mNode, True, '''zwei''');
    mNext := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Text, False, '');
    Assert.IsFalse(mNext.Same(mFirst), 'neuer Wert');
    mFirst := mNext;
    mList.BeginStop;
    mNext := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Text, False, '');
    Assert.IsFalse(mNext.Same(mFirst), 'wird ausgewertet');
    mNext := TAtlasEvalDetailInput.ForNode(nil, TAtlasEvalView.Text, False, '');
    Assert.IsTrue(mNext.Same(TAtlasEvalDetailInput.ForNode(nil, TAtlasEvalView.Text, False, '')), 'keine Auswahl');
    Assert.IsFalse(mNext.Same(mFirst));
    mFirst := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Lines, True, 'a');
    mNext := TAtlasEvalDetailInput.ForNode(mNode, TAtlasEvalView.Lines, True, 'b');
    Assert.IsFalse(mNext.Same(mFirst), 'anderer Wert von .Text');
  finally
    mList.Free;
  end;
end;

end.
