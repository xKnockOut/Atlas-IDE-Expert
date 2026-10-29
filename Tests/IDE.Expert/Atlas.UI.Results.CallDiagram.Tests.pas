unit Atlas.UI.Results.CallDiagram.Tests;

// Tests für die Diagrammansicht der Aufrufhierarchie (#1122): erste Ebene beim
// Zeigen, Klick lädt bzw. klappt die nächste, „+ N …“ zeigt alle, Öffnen der
// gewählten Stelle; im Ergebnisfenster Umschalter nur mit DiagramAllowed und
// nur für Aufrufhierarchien, Richtungswechsel mit denselben Wurzeln,
// HTML-Ausgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCallDiagramViewTests = class
  public
    [Test]
    procedure ShowsFirstLevelAndLoadsOnClick;
    [Test]
    procedure MoreBoxShowsAllChildren;
    [Test]
    procedure ProjectOnlyHidesLibraryCalls;
    [Test]
    procedure FrameToggleOnlyWhenAllowed;
    [Test]
    procedure FrameSwitchesDirectionAndSavesHtml;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Results.CallDiagram,
  Atlas.UI.Results.CallDiagram,
  Atlas.UI.Results.Frame;

function Item(const AName, AFileName: string; ALine: Integer): TAtlasHierarchyItem;
begin
  Result := Default(TAtlasHierarchyItem);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

/// <summary>Drei Ebenen: Start → Laden, Speichern → Lesen; 'Viele' hat zehn Aufgerufene; 'System.pas' ist RTL.
/// </summary>
function Children(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
var
  Index: Integer;
begin
  Result := nil;
  if AItem.Name = 'Start' then
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Laden', 'C:\P\Daten.pas', 10),
      Item('Speichern', 'C:\P\Daten.pas', 20), Item('IntToStr', 'C:\RTL\System.pas', 5))
  else if AItem.Name = 'Laden' then
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Lesen', 'C:\P\Datei.pas', 3))
  else if AItem.Name = 'Viele' then
    for Index := 1 to 10 do
      Result := Result + [Item('Teil' + IntToStr(Index), 'C:\P\Teile.pas', Index)];
  if ADirection = TAtlasHierarchyDirection.Incoming then
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Aufrufer', 'C:\P\Haupt.pas', 1));
end;

function IsProject(AFileName: string): Boolean;
begin
  Result := Pos('C:\P\', AFileName) = 1;
end;

function NewView(AHost: TForm): TAtlasCallDiagramView;
begin
  Result := TAtlasCallDiagramView.Create(AHost);
  Result.Parent := AHost;
  Result.SetBounds(0, 0, 800, 600);
  Result.IsProjectFile := IsProject;
  Result.OnLoad := Children;
end;

procedure TAtlasCallDiagramViewTests.ShowsFirstLevelAndLoadsOnClick;
var
  Host: TForm;
  View: TAtlasCallDiagramView;
  Loads: Integer;
  Opened: string;
  Box: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    View := NewView(Host);
    Loads := 0;
    View.OnLoad :=
      function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
      begin
        Inc(Loads);
        Result := Children(ADirection, AItem);
      end;
    Opened := '';
    View.OnOpen :=
      procedure(const AItem: TAtlasHierarchyItem)
      begin
        Opened := AItem.Name;
      end;
    View.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas',
      1)));
    // Wurzel und erste Ebene (ohne RTL): Start, Laden, Speichern.
    Assert.AreEqual(1, Loads, 'erste Ebene gleich geladen');
    Assert.AreEqual(3, Integer(Length(View.Layout.Boxes)));
    Box := View.Layout.BoxOf(1);
    Assert.AreEqual('Laden', View.Diagram[View.Layout.Boxes[Box].Node].Item.Name);
    View.ClickBox(Box);
    Assert.AreEqual(2, Loads, 'Klick lädt die nächste Ebene');
    Assert.AreEqual(4, Integer(Length(View.Layout.Boxes)), 'Lesen dazu');
    Assert.AreEqual(1, View.Selected);
    View.ClickBox(View.Layout.BoxOf(1));
    Assert.AreEqual(2, Loads, 'Zuklappen lädt nicht neu');
    Assert.AreEqual(3, Integer(Length(View.Layout.Boxes)));
    View.ClickBox(View.Layout.BoxOf(1));
    Assert.AreEqual(2, Loads, 'Aufklappen nutzt die geladene Ebene');
    Assert.AreEqual(4, Integer(Length(View.Layout.Boxes)));
    // Doppelklick bzw. Enter öffnet die gewählte Stelle.
    View.OpenSelected;
    Assert.AreEqual('Laden', Opened);
    Assert.IsTrue(View.Html('Aufrufe von Start').Contains('Lesen'), 'HTML enthält die geladenen Ebenen');
  finally
    Host.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.MoreBoxShowsAllChildren;
var
  Host: TForm;
  View: TAtlasCallDiagramView;
  Index, More: Integer;
begin
  Host := TForm.CreateNew(nil);
  try
    View := NewView(Host);
    View.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Viele', 'C:\P\Haupt.pas',
      1)));
    More := -1;
    for Index := 0 to High(View.Layout.Boxes) do
      if View.Layout.Boxes[Index].Kind = TAtlasCallBoxKind.More then
        More := Index;
    Assert.IsTrue(More >= 0, '„+ N …“ bei zehn Kindern');
    Assert.AreEqual(2, View.Layout.Boxes[More].Hidden);
    Assert.AreEqual(1 + TAtlasCallDiagram.MaxChildren + 1, Integer(Length(View.Layout.Boxes)));
    View.ClickBox(More);
    Assert.AreEqual(11, Integer(Length(View.Layout.Boxes)), 'Klick zeigt alle');
  finally
    Host.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.ProjectOnlyHidesLibraryCalls;
var
  Host: TForm;
  View: TAtlasCallDiagramView;
begin
  Host := TForm.CreateNew(nil);
  try
    View := NewView(Host);
    View.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas',
      1)));
    Assert.IsTrue(View.ProjectOnly, 'Vorgabe: nur Projekt-Units');
    Assert.AreEqual(3, Integer(Length(View.Layout.Boxes)));
    View.ProjectOnly := False;
    Assert.AreEqual(4, Integer(Length(View.Layout.Boxes)), 'IntToStr aus der RTL wieder da');
  finally
    Host.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.FrameToggleOnlyWhenAllowed;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Roots: TArray<TAtlasHierarchyItem>;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnExpand := Children;
    // Wie in NewView: ohne Projektfilter stünde IntToStr aus der RTL als vierte Box da.
    Frame.IsProjectFile := IsProject;
    Roots := TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas', 1));
    // Ohne callHierarchy.diagram: kein Umschalter, auch nicht auf Wunsch.
    Frame.DiagramAllowed := False;
    Frame.ShowHierarchy('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing, Roots, True);
    Assert.IsFalse(Frame.DiagramToggle.Visible);
    Assert.IsFalse(Frame.ShowsDiagram);
    Assert.IsTrue(Frame.Tree.Visible);
    // Erlaubt: Umschalter bei Aufrufhierarchien, nicht bei Typhierarchien.
    Frame.DiagramAllowed := True;
    Frame.ShowHierarchy('Vorfahren', TAtlasHierarchyDirection.Supertypes, Roots);
    Assert.IsFalse(Frame.DiagramToggle.Visible, 'Typhierarchie ohne Diagramm');
    Frame.ShowHierarchy('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing, Roots);
    Assert.IsTrue(Frame.DiagramToggle.Visible);
    Assert.IsFalse(Frame.ShowsDiagram, 'Vorgabe: Liste');
    Frame.DiagramToggle.Checked := True;
    Assert.IsTrue(Frame.ShowsDiagram);
    Assert.IsTrue(Frame.DiagramBar.Visible);
    Assert.IsFalse(Frame.Tree.Visible);
    Assert.AreEqual(3, Integer(Length(Frame.Diagram.Layout.Boxes)));
    // Abschalten der Einstellung nimmt das Diagramm weg.
    Frame.DiagramAllowed := False;
    Assert.IsFalse(Frame.ShowsDiagram);
    Assert.IsFalse(Frame.DiagramToggle.Visible);
    Assert.IsTrue(Frame.Tree.Visible);
  finally
    Host.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.FrameSwitchesDirectionAndSavesHtml;
var
  Host: TForm;
  Frame: TAtlasResultsFrame;
  Html: string;
begin
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.OnExpand := Children;
    Frame.DiagramAllowed := True;
    Frame.ShowHierarchy('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing,
      TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas', 1)), True);
    Assert.IsTrue(Frame.ShowsDiagram, 'gleich als Diagramm');
    Assert.IsTrue(Frame.OutgoingButton.Checked);
    Frame.IncomingButton.Checked := True;
    Assert.AreEqual(Ord(TAtlasHierarchyDirection.Incoming), Ord(Frame.Direction));
    Assert.IsTrue(Frame.ShowsDiagram, 'bleibt Diagramm');
    Assert.AreEqual('Aufrufer', Frame.Diagram.Diagram[1].Item.Name, 'dieselbe Wurzel, eingehend geladen');
    Html := Frame.DiagramHtml;
    Assert.IsTrue(Html.StartsWith('<!DOCTYPE html>', True));
    Assert.IsTrue(Html.Contains('Aufrufer'));
    Assert.IsFalse(Html.Contains('src="http'), 'keine externen Verweise');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallDiagramViewTests);

end.
