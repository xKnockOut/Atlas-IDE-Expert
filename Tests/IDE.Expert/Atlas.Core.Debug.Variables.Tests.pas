unit Atlas.Core.Debug.Variables.Tests;

// Tests für das Fenster „Variablen“ (#853) ohne IDE: Antwort des Servers lesen,
// Zeilen für Autos und Lokal abgleichen (Markierung geänderter Werte bleibt),
// Suche nach Name und Wert, in Unterelementen mit Tiefe und Abbruch.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasVariablesTests = class
  private
    FList: TAtlasEvalList;
    FSearch: TAtlasVariableSearch;
    /// <summary>Werte je Ausdruck; ohne Eintrag zerlegt Open den Wert in Teile.</summary>
    FValues: TDictionary<string, string>;
    /// <summary>Felder je Ausdruck, durch Komma getrennt.</summary>
    FFields: TDictionary<string, string>;
    procedure Put(ANode: TAtlasEvalNode);
    procedure OpenNode(ANode: TAtlasEvalNode);
    /// <summary>Suche bis zum Ende laufen lassen wie die IDE-Schicht; Anzahl der geöffneten Knoten.</summary>
    function RunSearch: Integer;
    function Shown: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAnswerAndArguments;
    [Test]
    procedure ReplaceKeepsNodesAndChangedMarks;
    [Test]
    procedure NameSearchFiltersWithoutOpening;
    [Test]
    procedure DeepValueSearchFindsFieldAndOpensPath;
    [Test]
    procedure DepthLimitsOpening;
    [Test]
    procedure LimitStopsSearch;
    [Test]
    procedure StructuredParentIsNoValueHit;
    [Test]
    procedure EmptySearchShowsAll;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

{ TAtlasVariablesTests }

procedure TAtlasVariablesTests.Setup;
begin
  FList := TAtlasEvalList.Create;
  FSearch := TAtlasVariableSearch.Create;
  FValues := TDictionary<string, string>.Create;
  FFields := TDictionary<string, string>.Create;
end;

procedure TAtlasVariablesTests.TearDown;
begin
  FreeAndNil(FFields);
  FreeAndNil(FValues);
  FreeAndNil(FSearch);
  FreeAndNil(FList);
end;

procedure TAtlasVariablesTests.Put(ANode: TAtlasEvalNode);
var
  mValue: string;
  mIndex: Integer;
begin
  if (ANode.Expression <> '') and (ANode.State = TAtlasEvalState.Pending) and
    FValues.TryGetValue(ANode.Expression, mValue) then
  begin
    FList.SetResult(ANode, True, mValue);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Put(ANode.Children[mIndex]);
  end;
end;

procedure TAtlasVariablesTests.OpenNode(ANode: TAtlasEvalNode);
var
  mFields: string;
begin
  // Wie die IDE-Schicht: Felder aus dem Index, sonst Teile des Werts; danach die Felder auswerten.
  if FFields.TryGetValue(ANode.Expression, mFields) then
  begin
    FList.SetFields(ANode, mFields.Split([',']));
  end
  else
  begin
    FList.SetParts(ANode);
  end;
  FSearch.Loaded(ANode);
  Put(ANode);
end;

function TAtlasVariablesTests.RunSearch: Integer;
var
  mNode: TAtlasEvalNode;
begin
  Result := 0;
  mNode := FSearch.NextToOpen(FList);
  while mNode <> nil do
  begin
    Inc(Result);
    FSearch.Opened(mNode);
    if not mNode.ChildrenLoaded then
    begin
      OpenNode(mNode);
    end;
    mNode := FSearch.NextToOpen(FList);
  end;
  FSearch.Apply(FList);
end;

function TAtlasVariablesTests.Shown: string;

  procedure Add(ANode: TAtlasEvalNode; var AText: string);
  var
    mIndex: Integer;
    mMark: string;
  begin
    if not FSearch.IsShown(ANode) then
    begin
      Exit;
    end;
    mMark := '';
    if FSearch.IsHit(ANode) then
    begin
      mMark := '*';
    end;
    if ANode.Expanded then
    begin
      mMark := mMark + '+';
    end;
    AText := AText + ANode.Name + mMark + ' ';
    if ANode.Expanded then
    begin
      for mIndex := 0 to ANode.ChildCount - 1 do
      begin
        Add(ANode.Children[mIndex], AText);
      end;
    end;
  end;

var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to FList.Count - 1 do
  begin
    Add(FList.Roots[mIndex], Result);
  end;
  Result := Trim(Result);
end;

procedure TAtlasVariablesTests.ReadsAnswerAndArguments;
var
  mAnswer: TAtlasVariablesAnswer;
begin
  Assert.IsTrue(TAtlasVariables.ReadAnswerText('{"format":1,"autos":["Betrag","S"],"locals":["Self","S"]}', mAnswer));
  Assert.AreEqual('Betrag,S', string.Join(',', mAnswer.Autos));
  Assert.AreEqual('Self,S', string.Join(',', mAnswer.Locals));
  Assert.IsFalse(TAtlasVariables.ReadAnswerText('', mAnswer), 'leer');
  Assert.IsFalse(TAtlasVariables.ReadAnswerText('{kaputt', mAnswer), 'kaputt');
  Assert.IsFalse(TAtlasVariables.ReadAnswerText('{"format":1,"autos":[]}', mAnswer), 'ohne locals');
  Assert.AreEqual(Integer(0), Integer(Length(mAnswer.Autos)));
  Assert.AreEqual('["file:///c:/a.pas",12,-1]', TAtlasVariables.Arguments('file:///c:/a.pas', 12, -1));
end;

procedure TAtlasVariablesTests.ReplaceKeepsNodesAndChangedMarks;
var
  mKept: TAtlasEvalNode;
begin
  FList.Replace(['Betrag', 'S', 'Betrag', ' ']);
  Assert.AreEqual(Integer(2), FList.Count, 'ohne Doppelte und Leere');
  mKept := FList.Roots[0];
  FList.SetResult(mKept, True, '1');
  mKept.Expanded := True;
  FList.BeginStop;
  // Nach F8: neue Ausdrücke vorn, Betrag bleibt derselbe Knoten.
  FList.Replace(['Summe', 'Betrag']);
  Assert.AreEqual('Summe', FList.Roots[0].Name);
  Assert.AreSame(mKept, FList.Roots[1], 'Knoten bleibt');
  Assert.IsTrue(mKept.Expanded, 'aufgeklappt bleibt');
  FList.SetResult(mKept, True, '2');
  Assert.IsTrue(mKept.Changed, 'geändert seit dem letzten Schritt');
  Assert.AreEqual(Integer(TAtlasEvalState.Pending), Integer(FList.Roots[0].State), 'neu ist offen');
end;

procedure TAtlasVariablesTests.NameSearchFiltersWithoutOpening;
begin
  FList.Replace(['Betrag', 'Summe', 'Kunde.Betrag']);
  FList.SetResult(FList.Roots[2], True, '(Ort: ''Berlin'')');
  FSearch.Start('betrag', TAtlasVariableSearchMode.Name, False, 3, 500);
  Assert.AreEqual(Integer(0), RunSearch, 'ohne Unterelemente wird nichts geöffnet');
  Assert.AreEqual(Integer(2), FSearch.HitCount);
  Assert.AreEqual('Betrag* Kunde.Betrag*', Shown);
end;

procedure TAtlasVariablesTests.DeepValueSearchFindsFieldAndOpensPath;
begin
  // Abnahme: Suche nach „Berlin“ im Wert findet Kunde.Adressen[1].Ort und klappt den Pfad auf.
  FFields.Add('Kunde', 'Name,Adressen');
  FValues.Add('Kunde', '(Name: ''Meier''; Adressen: ((Ort: ''Hamburg''), (Ort: ''Berlin'')))');
  FValues.Add('Kunde.Name', '''Meier''');
  FValues.Add('Kunde.Adressen', '((Ort: ''Hamburg''), (Ort: ''Berlin''))');
  FValues.Add('Summe', '42');
  FList.Replace(['Kunde', 'Summe']);
  Put(FList.Roots[0]);
  Put(FList.Roots[1]);
  FSearch.Start('Berlin', TAtlasVariableSearchMode.Value, True, 3, 500);
  Assert.AreEqual(Integer(4), RunSearch, 'Kunde, Adressen, [0], [1]');
  Assert.AreEqual(Integer(1), FSearch.HitCount);
  Assert.AreEqual('Kunde+ Adressen+ [1]+ Ort*', Shown, '[0] ohne Treffer wieder zu und ausgeblendet');
  Assert.AreEqual(Integer(2), FSearch.Evaluations, 'nur die Felder aus dem Index kosten Auswertungen');
  Assert.IsFalse(FSearch.Truncated);
end;

procedure TAtlasVariablesTests.DepthLimitsOpening;
begin
  FFields.Add('Kunde', 'Name,Adressen');
  FValues.Add('Kunde', '(Name: ''Meier''; Adressen: ((Ort: ''Hamburg''), (Ort: ''Berlin'')))');
  FValues.Add('Kunde.Name', '''Meier''');
  FValues.Add('Kunde.Adressen', '((Ort: ''Hamburg''), (Ort: ''Berlin''))');
  FList.Replace(['Kunde']);
  Put(FList.Roots[0]);
  FSearch.Start('Berlin', TAtlasVariableSearchMode.Value, True, 2, 500);
  Assert.AreEqual(Integer(2), RunSearch, 'Tiefe 2: Kunde und Adressen');
  Assert.AreEqual(Integer(0), FSearch.HitCount, 'Ort liegt auf Tiefe 3');
  Assert.AreEqual('', Shown);
  Assert.IsFalse(FList.Roots[0].Expanded, 'ohne Treffer wieder zu');
end;

procedure TAtlasVariablesTests.LimitStopsSearch;
begin
  FFields.Add('A', 'X,Y,Z');
  FValues.Add('A', '(X: (P: 1); Y: (P: 2); Z: (P: 3))');
  FValues.Add('A.X', '(P: 1)');
  FValues.Add('A.Y', '(P: 2)');
  FValues.Add('A.Z', '(P: 3)');
  FList.Replace(['A']);
  Put(FList.Roots[0]);
  FSearch.Start('7', TAtlasVariableSearchMode.Value, True, 3, 2);
  Assert.AreEqual(Integer(1), RunSearch, 'nach A sind 3 von 2 Auswertungen verbraucht');
  Assert.IsTrue(FSearch.Truncated, 'tiefer läge noch etwas');
  Assert.AreEqual(Integer(3), FSearch.Evaluations);
end;

procedure TAtlasVariablesTests.StructuredParentIsNoValueHit;
begin
  FList.Replace(['Kunde']);
  FList.SetResult(FList.Roots[0], True, '(Ort: ''Berlin'')');
  FSearch.Start('Berlin', TAtlasVariableSearchMode.Value, False, 3, 500);
  RunSearch;
  Assert.AreEqual(Integer(0), FSearch.HitCount, 'der Treffer gehört dem Feld');
  FSearch.Start('Berlin', TAtlasVariableSearchMode.Value, True, 3, 500);
  RunSearch;
  Assert.AreEqual('Kunde+ Ort*', Shown);
end;

procedure TAtlasVariablesTests.EmptySearchShowsAll;
begin
  FList.Replace(['A', 'B']);
  FSearch.Start('  ', TAtlasVariableSearchMode.Name, True, 3, 500);
  Assert.IsFalse(FSearch.Active);
  Assert.IsNull(FSearch.NextToOpen(FList));
  Assert.AreEqual(Integer(0), FSearch.Apply(FList));
  Assert.AreEqual('A B', Shown);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVariablesTests);

end.
