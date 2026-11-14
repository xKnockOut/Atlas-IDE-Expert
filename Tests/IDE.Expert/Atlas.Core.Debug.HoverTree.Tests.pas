unit Atlas.Core.Debug.HoverTree.Tests;

// Tests für den aufklappbaren Debug-Hover (#895) ohne IDE: Kind-Ausdrücke aus Feldern, Indizes und Zeigern,
// Eigenschaften als Getter, Begrenzung je Ebene, Vergleich mit dem vorigen Halt und die Schalter.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.HoverTree;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasHoverTreeTests = class
  private
    FChanges: TAtlasValueChanges;
    FTree: TAtlasHoverTree;
    /// <summary>Nächste Anfrage beantworten: Ausdruck AExpected, Ergebnis AText.</summary>
    procedure Answer(const AExpected, AText: string);
    /// <summary>Anstehende Anfragen nach Eigenschaften ohne Eigenschaften beantworten.</summary>
    procedure NoProperties;
    /// <summary>Zeilen als „Tiefe:Name=Text“, durch | getrennt.</summary>
    function RowsText: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RootExpandsWithFieldNames;
    [Test]
    procedure ChildExpressionsForFieldsIndicesAndPointers;
    [Test]
    procedure PropertiesAreLazyGetters;
    [Test]
    procedure LimitsChildrenPerLevel;
    [Test]
    procedure LongArrayEvaluatesVisibleElements;
    [Test]
    procedure MarksChangesSincePreviousStop;
    [Test]
    procedure ChangesOnlyInSameContext;
    [Test]
    procedure ExpandedSurvivesStopsUntilClear;
    [Test]
    procedure SwitchesOffChangesAndLeaves;
    [Test]
    procedure ServerParamsAndProperties;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Hover.DebugValue;

procedure TAtlasHoverTreeTests.Setup;
var
  mTexts: TAtlasHoverTreeTexts;
begin
  FChanges := TAtlasValueChanges.Create;
  FTree := TAtlasHoverTree.Create(FChanges);
  mTexts := Default(TAtlasHoverTreeTexts);
  mTexts.Evaluate := 'auswerten';
  mTexts.Pending := '…';
  mTexts.More := 'weitere %d …';
  FTree.Texts := mTexts;
end;

procedure TAtlasHoverTreeTests.TearDown;
begin
  FTree.Free;
  FChanges.Free;
end;

procedure TAtlasHoverTreeTests.Answer(const AExpected, AText: string);
var
  mRequest: TAtlasHoverTreeRequest;
begin
  Assert.IsTrue(FTree.NextRequest(mRequest), 'Anfrage für ' + AExpected);
  Assert.AreEqual(AExpected, mRequest.Expression);
  Assert.IsFalse(mRequest.Properties);
  FTree.SetResult(mRequest.Key, True, AText);
end;

procedure TAtlasHoverTreeTests.NoProperties;
var
  mRequest: TAtlasHoverTreeRequest;
begin
  while FTree.NextRequest(mRequest) and mRequest.Properties do
  begin
    FTree.SetProperties(mRequest.Key, nil);
  end;
end;

function TAtlasHoverTreeTests.RowsText: string;
var
  mRow: TAtlasDebugValueRow;
begin
  Result := '';
  for mRow in FTree.Rows do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + IntToStr(mRow.Depth) + ':' + mRow.Name + '=' + mRow.Text;
  end;
end;

procedure TAtlasHoverTreeTests.RootExpandsWithFieldNames;
var
  mValue: TAtlasDebugValue;
  mRequest: TAtlasHoverTreeRequest;
begin
  FTree.Bind('Kunde', '(''Meier'', 3)');
  mValue := FTree.Decorate(TAtlasDebugValue.Evaluated('Kunde', '(''Meier'', 3)'));
  Assert.IsTrue(mValue.Expandable);
  Assert.IsFalse(mValue.Expanded);
  Assert.AreEqual(0, Integer(Length(mValue.Rows)));
  Assert.IsFalse(FTree.NextRequest(mRequest), 'zugeklappt wird nichts ausgewertet');
  // Aufklappen: „…“, bis die Auswertung mit Feldnamen da ist.
  Assert.IsTrue(FTree.Click(-1));
  Assert.AreEqual('0:=…', RowsText);
  Answer('Kunde,r', '(Name: ''Meier''; Anzahl: 3)');
  Assert.AreEqual('0:Name=''Meier''|0:Anzahl=3', RowsText);
  Assert.IsTrue(FTree.Decorate(TAtlasDebugValue.Evaluated('Kunde', '')).Expanded);
  // Zuklappen.
  Assert.IsTrue(FTree.Click(-1));
  Assert.AreEqual('', RowsText);
  // Blätter lassen sich nicht aufklappen.
  FTree.Bind('Anzahl', '3');
  Assert.IsFalse(FTree.Click(-1));
  Assert.IsFalse(FTree.Decorate(TAtlasDebugValue.Evaluated('Anzahl', '3')).Expandable);
end;

procedure TAtlasHoverTreeTests.ChildExpressionsForFieldsIndicesAndPointers;
var
  mRows: TArray<TAtlasDebugValueRow>;
begin
  FTree.Bind('Kunde', '($1A2B)');
  FTree.Click(-1);
  Answer('Kunde,r', '(Adresse: (Ort: ''Köln''); Liste: (1, 2); Next: $1A2C; Name: ''X'')');
  mRows := FTree.Rows;
  Assert.AreEqual('Kunde.Adresse', mRows[0].Expression);
  Assert.IsTrue(mRows[0].Expandable);
  Assert.IsTrue(mRows[2].Expandable, 'Zeiger klappt über eine Auswertung auf');
  Assert.IsFalse(mRows[3].Expandable);
  // Record aus seinen Teilen, ohne Auswertung.
  Assert.IsTrue(FTree.Click(0));
  Assert.AreEqual('Kunde.Adresse.Ort', FTree.Rows[1].Expression);
  Assert.AreEqual(1, FTree.Rows[1].Depth);
  // Array: Elemente mit Index.
  Assert.IsTrue(FTree.Click(2));
  mRows := FTree.Rows;
  Assert.AreEqual('Kunde.Liste[0]', mRows[3].Expression);
  Assert.AreEqual('[1]', mRows[4].Name);
  // Zeiger: eigene Auswertung mit Feldnamen (nach den Eigenschaften der Wurzel und der Adresse).
  NoProperties;
  Assert.IsTrue(FTree.Click(5));
  Answer('Kunde.Next,r', '(Name: ''Y'')');
  Assert.AreEqual('Kunde.Next.Name', FTree.Rows[6].Expression);
  // Zusammengesetzter Ausdruck bekommt Klammern.
  FTree.Bind('A + B', '(X: 1)');
  FTree.Click(-1);
  Answer('A + B,r', '(X: 1)');
  Assert.AreEqual('(A + B).X', FTree.Rows[0].Expression);
end;

procedure TAtlasHoverTreeTests.PropertiesAreLazyGetters;
var
  mRequest: TAtlasHoverTreeRequest;
  mRows: TArray<TAtlasDebugValueRow>;
begin
  FTree.Bind('Kunde', '($1A2B)');
  FTree.Click(-1);
  Answer('Kunde,r', '(FName: ''Meier''; FUmsatz: 980)');
  Assert.IsTrue(FTree.NextRequest(mRequest));
  Assert.IsTrue(mRequest.Properties);
  Assert.AreEqual('Kunde.', mRequest.Expression);
  FTree.SetProperties(mRequest.Key, ['FName', 'Umsatz']);
  Assert.IsFalse(FTree.NextRequest(mRequest), 'Getter erst auf Klick');
  mRows := FTree.Rows;
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.IsTrue(mRows[2].Lazy);
  Assert.AreEqual('auswerten', mRows[2].Text);
  // Klick: mit Nebenwirkungen auswerten.
  Assert.IsTrue(FTree.Click(2));
  Assert.IsTrue(FTree.Rows[2].Pending);
  Assert.IsTrue(FTree.NextRequest(mRequest));
  Assert.AreEqual('Kunde.Umsatz', mRequest.Expression);
  Assert.IsTrue(mRequest.SideEffects);
  FTree.SetResult(mRequest.Key, True, '980');
  Assert.AreEqual('0:FName=''Meier''|0:FUmsatz=980|0:Umsatz=980', RowsText);
  // Array: keine Eigenschaften.
  FTree.Bind('Liste', '(1, 2)');
  FTree.Click(-1);
  Answer('Liste,r', '(1, 2)');
  Assert.IsFalse(FTree.NextRequest(mRequest));
end;

procedure TAtlasHoverTreeTests.LimitsChildrenPerLevel;
var
  mItems: string;
  mIndex: Integer;
  mRows: TArray<TAtlasDebugValueRow>;
begin
  mItems := '0';
  for mIndex := 1 to 249 do
  begin
    mItems := mItems + ', ' + IntToStr(mIndex);
  end;
  FTree.Bind('Liste', '(' + mItems + ')');
  FTree.Click(-1);
  Answer('Liste,r', '(' + mItems + ')');
  mRows := FTree.Rows;
  Assert.AreEqual(101, Integer(Length(mRows)));
  Assert.IsTrue(mRows[100].More);
  Assert.AreEqual('weitere 100 …', mRows[100].Text);
  Assert.IsTrue(FTree.Click(100));
  mRows := FTree.Rows;
  Assert.AreEqual(201, Integer(Length(mRows)));
  Assert.AreEqual('weitere 50 …', mRows[200].Text);
  Assert.IsTrue(FTree.Click(200));
  Assert.AreEqual(250, Integer(Length(FTree.Rows)));
  // Eigene Grenze.
  FTree.MaxChildren := 10;
  FTree.Bind('Liste', '(' + mItems + ', 250)');
  // Bleibt aufgeklappt (gleicher Ausdruck).
  Answer('Liste,r', '(' + mItems + ')');
  Assert.AreEqual(11, Integer(Length(FTree.Rows)));
end;

procedure TAtlasHoverTreeTests.LongArrayEvaluatesVisibleElements;
var
  mRequest: TAtlasHoverTreeRequest;
  mIndex: Integer;
begin
  FTree.Bind('Werte', '(1, 2, 3, …');
  FTree.Click(-1);
  // Gekürzte Antwort des Debuggers: Anzahl erfragen, dann die sichtbaren Elemente einzeln.
  Answer('Werte,r', '(1, 2, 3, …');
  Assert.AreEqual('0:=…', RowsText);
  Answer('Length(Werte)', '1000');
  Assert.AreEqual(101, Integer(Length(FTree.Rows)));
  Assert.IsTrue(FTree.Rows[0].Pending);
  for mIndex := 0 to 99 do
  begin
    Assert.IsTrue(FTree.NextRequest(mRequest));
    Assert.AreEqual('Werte[' + IntToStr(mIndex) + ']', mRequest.Expression);
    Assert.IsFalse(mRequest.SideEffects, 'Elemente ohne Nebenwirkungen');
    FTree.SetResult(mRequest.Key, True, IntToStr(mIndex * 2));
  end;
  Assert.IsFalse(FTree.NextRequest(mRequest), 'Elemente hinter „weitere …“ warten');
  Assert.AreEqual('198', FTree.Rows[99].Text);
  Assert.AreEqual('weitere 100 …', FTree.Rows[100].Text);
  Assert.IsTrue(FTree.Click(100));
  Answer('Werte[100]', '200');
  // Keine Zahl: ein Blatt.
  FTree.Bind('Text', '(''a'', …');
  FTree.Click(-1);
  Answer('Text,r', '(''a'', …');
  Answer('Length(Text)', 'E2010 Incompatible types');
  Assert.IsFalse(FTree.Decorate(TAtlasDebugValue.Evaluated('Text', '')).Expandable);
end;

procedure TAtlasHoverTreeTests.MarksChangesSincePreviousStop;
var
  mValue: TAtlasDebugValue;
begin
  FChanges.BeginStop('1:Rechne');
  FTree.Bind('Summe', '980');
  Assert.AreEqual('', FTree.Decorate(TAtlasDebugValue.Evaluated('Summe', '980')).OldText);
  // F8: Summe := Summe + X.
  FChanges.BeginStop('1:Rechne');
  FTree.Reset;
  FTree.Bind('Summe', '1250');
  mValue := FTree.Decorate(TAtlasDebugValue.Evaluated('Summe', '1250'));
  Assert.AreEqual('980', mValue.OldText);
  // Unverändert im nächsten Halt: keine Markierung.
  FChanges.BeginStop('1:Rechne');
  FTree.Reset;
  FTree.Bind('Summe', '1250');
  Assert.AreEqual('', FTree.Decorate(TAtlasDebugValue.Evaluated('Summe', '1250')).OldText);
  // Auch aufgeklappte Kinder.
  FTree.Bind('K', '(1)');
  FTree.Click(-1);
  Answer('K,r', '(Umsatz: 980)');
  FChanges.BeginStop('1:Rechne');
  FTree.Reset;
  FTree.Bind('K', '(2)');
  Answer('K,r', '(Umsatz: 1250)');
  Assert.AreEqual('980', FTree.Rows[0].OldText);
end;

procedure TAtlasHoverTreeTests.ChangesOnlyInSameContext;
begin
  FChanges.BeginStop('1:Rechne');
  Assert.AreEqual('', FChanges.Observe('I', '1'));
  // Andere Methode: kein Vergleich.
  FChanges.BeginStop('1:Andere');
  Assert.AreEqual('', FChanges.Observe('I', '5'));
  // Anderer Thread.
  FChanges.BeginStop('2:Rechne');
  Assert.AreEqual('', FChanges.Observe('I', '7'));
  // Zurück in derselben Methode und demselben Thread: Vergleich mit dem letzten Wert dort.
  FChanges.BeginStop('1:Rechne');
  Assert.AreEqual('1', FChanges.Observe('I', '2'));
  // Mehrmals im selben Halt: der alte bleibt der des vorigen Halts.
  Assert.AreEqual('1', FChanges.Observe('I', '2'));
  // Ende der Sitzung.
  FChanges.Clear;
  FChanges.BeginStop('1:Rechne');
  Assert.AreEqual('', FChanges.Observe('I', '3'));
end;

procedure TAtlasHoverTreeTests.ExpandedSurvivesStopsUntilClear;
var
  mRequest: TAtlasHoverTreeRequest;
begin
  FTree.Bind('K', '(1)');
  FTree.Click(-1);
  Answer('K,r', '(A: (X: 1))');
  // Klicks gelten den zuletzt gelieferten Zeilen.
  Assert.AreEqual('0:A=(X: 1)', RowsText);
  Assert.IsTrue(FTree.Click(0));
  FTree.Reset;
  FTree.Bind('K', '(1)');
  Assert.IsTrue(FTree.Decorate(TAtlasDebugValue.Evaluated('K', '(1)')).Expanded);
  Answer('K,r', '(A: (X: 2))');
  Assert.AreEqual('0:A=(X: 2)|1:X=2', RowsText);
  FTree.Clear;
  FTree.Bind('K', '(1)');
  Assert.IsFalse(FTree.NextRequest(mRequest));
  Assert.IsFalse(FTree.Decorate(TAtlasDebugValue.Evaluated('K', '(1)')).Expanded);
end;

procedure TAtlasHoverTreeTests.SwitchesOffChangesAndLeaves;
var
  mValue: TAtlasDebugValue;
begin
  // debug.hoverChanges aus: kein alter Wert.
  FTree.ShowChanges := False;
  FChanges.BeginStop('1:R');
  FTree.Bind('I', '1');
  FChanges.BeginStop('1:R');
  FTree.Reset;
  FTree.Bind('I', '2');
  Assert.AreEqual('', FTree.Decorate(TAtlasDebugValue.Evaluated('I', '2')).OldText);
  // Anderer Ausdruck im Hover: Wert unverändert, nichts aufklappbar.
  mValue := FTree.Decorate(TAtlasDebugValue.Evaluated('J', '(1)'));
  Assert.IsFalse(mValue.Expandable);
  Assert.AreEqual(0, Integer(Length(mValue.Rows)));
  // Gescheiterte Auswertung beim Aufklappen: ein Blatt.
  FTree.Bind('K', '($1)');
  FTree.Click(-1);
  FTree.SetResult('K', False, 'Inaccessible value');
  Assert.IsFalse(FTree.Decorate(TAtlasDebugValue.Evaluated('K', '($1)')).Expandable);
end;

procedure TAtlasHoverTreeTests.ServerParamsAndProperties;
var
  mNames: TArray<string>;
begin
  Assert.AreEqual('{"textDocument":{"uri":"file:///c:/a.pas"},"position":{"line":11,"character":0},' +
    '"expression":"Kunde.","character":6}', TAtlasHoverTree.CompletionParams('file:///c:/a.pas', 11, 'Kunde.'));
  // Nur Eigenschaften (10), keine Felder (5) oder Methoden.
  mNames := TAtlasHoverTree.PropertiesOf('{"items":[{"label":"FName","kind":5},{"label":"Umsatz","kind":10},' +
    '{"label":"Rechne","kind":2},{"label":"Name","kind":10}]}');
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('Umsatz', mNames[0]);
  Assert.AreEqual('Name', mNames[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasHoverTree.PropertiesOf(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasHoverTree.PropertiesOf('null'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHoverTreeTests);

end.
