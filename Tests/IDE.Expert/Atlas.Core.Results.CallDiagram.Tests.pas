unit Atlas.Core.Results.CallDiagram.Tests;

// Aufrufdiagramm (#1122), Kern: Ebenen laden und aufklappen, Rekursion als
// Pfeil zurück, „+ N …“ ab neun Kindern, „nur Projekt-Units“, gestrichelte
// Aufrufe über Interface und virtual, Kastentexte, Umrechnung der Ansicht und
// die HTML-Datei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCallDiagramTests = class
  public
    [Test]
    procedure LoadsLevelByLevel;
    [Test]
    procedure RecursionBecomesBackArrow;
    [Test]
    procedure MoreThanEightChildrenAreSummarized;
    [Test]
    procedure ProjectOnlyHidesLibraryUnits;
    [Test]
    procedure DispatchedCallsAreDashed;
    [Test]
    procedure DuplicateChildrenAreMerged;
    [Test]
    procedure TitleAndLocation;
    [Test]
    procedure ViewFitsZoomsAndHits;
    [Test]
    procedure JsonHoldsLoadedLevels;
    [Test]
    procedure HtmlIsSelfContained;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Results.CallDiagram;

function Item(const AName, AFileName: string; ALine: Integer): TAtlasHierarchyItem;
begin
  Result := Default(TAtlasHierarchyItem);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

function ProjectFile(AFileName: string): Boolean;
begin
  Result := not AFileName.StartsWith('C:\RTL\', True);
end;

function NewDiagram: TAtlasCallDiagram;
begin
  Result := TAtlasCallDiagram.Create(
    function(AFileName: string): Boolean
    begin
      Result := ProjectFile(AFileName);
    end);
end;

{ TAtlasCallDiagramTests }

procedure TAtlasCallDiagramTests.LoadsLevelByLevel;
var
  Diagram: TAtlasCallDiagram;
  Layout: TAtlasCallLayout;
begin
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Assert.IsTrue(Diagram.NeedsLoad(0));
    Assert.IsFalse(Diagram.Toggle(0), 'erst laden');
    Layout := Diagram.Layout;
    Assert.AreEqual(1, Integer(Length(Layout.Boxes)));
    // Erste Ebene: zwei Aufgerufene rechts daneben, der Start mittig davor.
    Diagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Zeigen', 'C:\P\B.pas', 20)]);
    Assert.IsFalse(Diagram.NeedsLoad(0));
    Layout := Diagram.Layout;
    Assert.AreEqual(3, Integer(Length(Layout.Boxes)));
    Assert.AreEqual(2, Integer(Length(Layout.Edges)));
    Assert.AreEqual(0, Layout.Boxes[Layout.BoxOf(0)].Column);
    Assert.AreEqual(0.5, Layout.Boxes[Layout.BoxOf(0)].Row, 0.001);
    Assert.AreEqual(1, Layout.Boxes[Layout.BoxOf(1)].Column);
    Assert.AreEqual(0.0, Layout.Boxes[Layout.BoxOf(1)].Row, 0.001);
    Assert.AreEqual(1.0, Layout.Boxes[Layout.BoxOf(2)].Row, 0.001);
    Assert.AreEqual(2, Layout.Columns);
    // Dritte Ebene erst nach Klick auf „Laden“.
    Assert.IsTrue(Diagram.NeedsLoad(1));
    Diagram.SetChildren(1, [Item('Lesen', 'C:\P\C.pas', 5)]);
    Layout := Diagram.Layout;
    Assert.AreEqual(3, Layout.Columns);
    Assert.AreEqual(2, Diagram[3].Level);
    // Zuklappen blendet die Ebenen darunter aus, Aufklappen zeigt sie ohne neues Laden.
    Assert.IsTrue(Diagram.Toggle(0));
    Assert.AreEqual(1, Integer(Length(Diagram.Layout.Boxes)));
    Assert.IsTrue(Diagram.Toggle(0));
    Assert.AreEqual(4, Integer(Length(Diagram.Layout.Boxes)));
    // Ohne Kinder lässt sich nichts aufklappen.
    Diagram.SetChildren(2, []);
    Assert.IsTrue(Diagram.Toggle(2), 'zuklappen geht');
    Assert.IsFalse(Diagram.Toggle(2), 'aufklappen ohne Kinder nicht');
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.RecursionBecomesBackArrow;
var
  Diagram: TAtlasCallDiagram;
  Layout: TAtlasCallLayout;
  Edge: TAtlasCallEdge;
  Backs: Integer;
begin
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Zaehle', 'C:\P\A.pas', 3)]);
    Diagram.SetChildren(0, [Item('Hilfe', 'C:\P\A.pas', 9)]);
    // Hilfe ruft Zaehle zurück: kein neuer Kasten, sondern ein Pfeil zurück.
    Diagram.SetChildren(1, [Item('Zaehle', 'C:\P\A.pas', 3), Item('Hilfe', 'C:\P\A.pas', 9)]);
    Assert.AreEqual(0, Diagram[2].BackTo);
    Assert.AreEqual(1, Diagram[3].BackTo, 'Selbstaufruf');
    Assert.IsFalse(Diagram.NeedsLoad(2));
    Assert.IsFalse(Diagram.Toggle(2));
    Layout := Diagram.Layout;
    Assert.AreEqual(2, Integer(Length(Layout.Boxes)));
    Backs := 0;
    for Edge in Layout.Edges do
      if Edge.Back then
      begin
        Inc(Backs);
        Assert.AreEqual(Layout.BoxOf(1), Edge.Source);
      end;
    Assert.AreEqual(2, Backs);
    // Weiteres Laden unter einer Rekursion wird ignoriert.
    Diagram.SetChildren(2, [Item('X', 'C:\P\A.pas', 1)]);
    Assert.AreEqual(0, Integer(Length(Diagram[2].Children)));
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.MoreThanEightChildrenAreSummarized;
var
  Diagram: TAtlasCallDiagram;
  Children: TArray<TAtlasHierarchyItem>;
  Index, More: Integer;
  Layout: TAtlasCallLayout;
  Box: TAtlasCallBox;
  Found: Boolean;
begin
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Speichern', 'C:\P\A.pas', 3)]);
    Children := nil;
    for Index := 1 to 11 do
      Children := Children + [Item('Aufrufer' + IntToStr(Index), 'C:\P\A.pas', 10 + Index)];
    Diagram.SetChildren(0, Children);
    Assert.AreEqual(8, Integer(Length(Diagram.VisibleChildren(0, More))));
    Assert.AreEqual(3, More);
    Layout := Diagram.Layout;
    Assert.AreEqual(10, Integer(Length(Layout.Boxes)), 'Wurzel, 8 Kinder, „+ 3 …“');
    Found := False;
    for Box in Layout.Boxes do
      if Box.Kind = TAtlasCallBoxKind.More then
      begin
        Found := True;
        Assert.AreEqual(3, Box.Hidden);
        Assert.AreEqual(0, Box.Node);
        Assert.AreEqual(1, Box.Column);
      end;
    Assert.IsTrue(Found);
    Diagram.ShowAll(0);
    Assert.AreEqual(12, Integer(Length(Diagram.Layout.Boxes)));
    // Genau acht bleiben ohne Zusammenfassung.
    Diagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Speichern', 'C:\P\A.pas', 3)]);
    Diagram.SetChildren(0, Copy(Children, 0, 8));
    Assert.AreEqual(8, Integer(Length(Diagram.VisibleChildren(0, More))));
    Assert.AreEqual(0, More);
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.ProjectOnlyHidesLibraryUnits;
var
  Diagram: TAtlasCallDiagram;
  More: Integer;
begin
  Diagram := NewDiagram;
  try
    Assert.IsTrue(Diagram.ProjectOnly, 'Vorgabe an');
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Format', 'C:\RTL\System.SysUtils.pas', 99),
      Item('Ohne', '', 0)]);
    Assert.IsTrue(Diagram[2].Library_);
    Assert.IsTrue(Diagram[3].Library_, 'ohne Datei');
    Assert.AreEqual(1, Integer(Length(Diagram.VisibleChildren(0, More))));
    Diagram.ProjectOnly := False;
    Assert.AreEqual(3, Integer(Length(Diagram.VisibleChildren(0, More))));
    Assert.AreEqual(4, Integer(Length(Diagram.Layout.Boxes)));
  finally
    Diagram.Free;
  end;
  // Ohne Entscheider gehört alles mit Datei zum Projekt.
  Diagram := TAtlasCallDiagram.Create(nil);
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Item('Format', 'C:\RTL\System.SysUtils.pas', 99)]);
    Assert.IsFalse(Diagram[1].Library_);
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.DispatchedCallsAreDashed;
var
  Diagram: TAtlasCallDiagram;
  Over, ViaVirtual, Plain: TAtlasHierarchyItem;
  Layout: TAtlasCallLayout;
  Edge: TAtlasCallEdge;
begin
  Over := Item('Speichern', 'C:\P\A.pas', 4);
  Over.Dispatch := 'interface';
  Over.Implementations := 3;
  // Eingehend: erschlossen über virtual (#1119) ohne atlasDispatch eines älteren Servers.
  ViaVirtual := Item('Laden', 'C:\P\A.pas', 5);
  ViaVirtual.Confidence.Inferred := True;
  ViaVirtual.Confidence.Reason := 'virtual';
  Plain := Item('Fertig', 'C:\P\A.pas', 6);
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Over, ViaVirtual, Plain]);
    Layout := Diagram.Layout;
    for Edge in Layout.Edges do
      if Layout.Boxes[Edge.Target].Node = 1 then
      begin
        Assert.IsTrue(Edge.Dashed);
        Assert.AreEqual(3, Edge.Implementations);
      end
      else if Layout.Boxes[Edge.Target].Node = 2 then
        Assert.IsTrue(Edge.Dashed)
      else
        Assert.IsFalse(Edge.Dashed);
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.DuplicateChildrenAreMerged;
var
  Diagram: TAtlasCallDiagram;
  Inferred: TAtlasHierarchyItem;
begin
  Inferred := Item('Aufrufer', 'C:\P\A.pas', 7);
  Inferred.Confidence.Inferred := True;
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Ziel', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Item('Aufrufer', 'C:\P\A.pas', 7), Inferred]);
    Assert.AreEqual(1, Integer(Length(Diagram[0].Children)));
    Assert.AreEqual(2, Diagram.Count);
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.TitleAndLocation;
var
  Entry: TAtlasHierarchyItem;
begin
  Entry := Item('Laden', 'C:\P\Ref.Kunden.pas', 11);
  Entry.Detail := 'TKunde · Ref.Kunden';
  Assert.AreEqual('TKunde.Laden', TAtlasCallDiagram.Title(Entry));
  Entry.Detail := 'Ref.Kunden';
  Assert.AreEqual('Laden', TAtlasCallDiagram.Title(Entry));
  Entry.Detail := 'TKunde';
  Assert.AreEqual('TKunde.Laden', TAtlasCallDiagram.Title(Entry));
  Assert.AreEqual('Ref.Kunden.pas:12', TAtlasCallDiagram.Location(Entry));
  Entry.FileName := '';
  Assert.AreEqual('', TAtlasCallDiagram.Location(Entry));
end;

procedure TAtlasCallDiagramTests.ViewFitsZoomsAndHits;
var
  Diagram: TAtlasCallDiagram;
  Layout: TAtlasCallLayout;
  View: TAtlasCallView;
  Box: TAtlasCallBox;
  X, Y, BeforeX: Double;
begin
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Zeigen', 'C:\P\B.pas', 20)]);
    Layout := Diagram.Layout;
  finally
    Diagram.Free;
  end;
  View := Default(TAtlasCallView);
  View.Fit(Layout, 1000, 600);
  Assert.AreEqual(1.0, View.Scale, 0.001, 'kleine Diagramme nicht vergrößert');
  View.Fit(Layout, 250, 100);
  Assert.IsTrue(View.Scale < 1);
  View.Fit(Layout, 1000, 600);
  Box := Layout.Boxes[Layout.BoxOf(2)];
  X := View.ScreenX(TAtlasCallView.BoxX(Box)) + 10;
  Y := View.ScreenY(TAtlasCallView.BoxY(Box)) + 10;
  Assert.AreEqual(Layout.BoxOf(2), View.BoxAt(Layout, X, Y));
  Assert.AreEqual(-1, View.BoxAt(Layout, 1, 1));
  // Zoomen um den Punkt lässt ihn stehen.
  BeforeX := View.ScreenX(TAtlasCallView.BoxX(Box));
  View.ZoomAt(2, BeforeX, Y);
  Assert.AreEqual(BeforeX, View.ScreenX(TAtlasCallView.BoxX(Box)), 0.001);
  Assert.AreEqual(2.0, View.Scale, 0.001);
  View.ZoomAt(100, 0, 0);
  Assert.AreEqual(TAtlasCallView.MaxScale, View.Scale, 0.001);
  View.Pan(5, -5);
  Assert.AreEqual(Layout.BoxOf(2), View.BoxAt(Layout, View.ScreenX(TAtlasCallView.BoxX(Box)) + 1,
    View.ScreenY(TAtlasCallView.BoxY(Box)) + 1));
end;

procedure TAtlasCallDiagramTests.JsonHoldsLoadedLevels;
var
  Diagram: TAtlasCallDiagram;
  Over: TAtlasHierarchyItem;
  Data: TJSONValue;
  Nodes: TJSONArray;
begin
  Over := Item('Speichern', 'C:\P\A.pas', 4);
  Over.Dispatch := 'interface';
  Over.Implementations := 2;
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Start', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Over, Item('Start', 'C:\P\A.pas', 1), Item('Format', 'C:\RTL\System.SysUtils.pas', 9)]);
    Data := TJSONObject.ParseJSONValue(Diagram.Json('Start'));
    try
      Assert.AreEqual(1, Data.GetValue<Integer>('format'));
      Assert.AreEqual('incoming', Data.GetValue<string>('direction'));
      Assert.IsTrue(Data.GetValue<Boolean>('projectOnly'));
      Assert.AreEqual(8, Data.GetValue<Integer>('maxChildren'));
      Nodes := Data.GetValue<TJSONArray>('nodes');
      Assert.AreEqual(4, Nodes.Count);
      Assert.AreEqual(-1.0, Nodes.Items[0].GetValue<Double>('parent'), 0.001);
      Assert.IsTrue(Nodes.Items[0].GetValue<Boolean>('expanded'));
      Assert.AreEqual('interface', Nodes.Items[1].GetValue<string>('dispatch'));
      Assert.AreEqual(2, Nodes.Items[1].GetValue<Integer>('implementations'));
      Assert.AreEqual(5, Nodes.Items[1].GetValue<Integer>('line'), 'Zeilen ab 1');
      Assert.AreEqual('A.pas:5', Nodes.Items[1].GetValue<string>('location'));
      Assert.AreEqual(0, Nodes.Items[2].GetValue<Integer>('backTo'));
      Assert.IsTrue(Nodes.Items[3].GetValue<Boolean>('library'));
    finally
      Data.Free;
    end;
  finally
    Diagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.HtmlIsSelfContained;
var
  Diagram: TAtlasCallDiagram;
  Html: string;
begin
  Diagram := NewDiagram;
  try
    Diagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start</script>', 'C:\P\A.pas', 1)]);
    Diagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10)]);
    Html := Diagram.Html('TForm1.Start & Co');
  finally
    Diagram.Free;
  end;
  Assert.StartsWith('<!doctype html>', Html);
  Assert.IsTrue(Pos('<title>Aufrufdiagramm: TForm1.Start &amp; Co</title>', Html) > 0, 'Titel maskiert');
  Assert.AreEqual(0, Pos('{{DATA}}', Html));
  Assert.AreEqual(0, Pos('{{TITLE}}', Html));
  // Nur ein schließendes script je Skript: der Name im JSON beendet das Datenelement nicht.
  Assert.AreEqual(0, Pos('Start</script>', Html));
  Assert.IsTrue(Pos('"name":"Laden"', Html) > 0);
  Assert.AreEqual(0, Pos('src="http', Html));
  Assert.AreEqual(0, Pos('href="http', Html));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallDiagramTests);

end.
