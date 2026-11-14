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
  mIndex: Integer;
begin
  Result := nil;
  if AItem.Name = 'Start' then
  begin
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Laden', 'C:\P\Daten.pas', 10),
      Item('Speichern', 'C:\P\Daten.pas', 20), Item('IntToStr', 'C:\RTL\System.pas', 5));
  end
  else if AItem.Name = 'Laden' then
  begin
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Lesen', 'C:\P\Datei.pas', 3));
  end
  else if AItem.Name = 'Viele' then
  begin
    for mIndex := 1 to 10 do
    begin
      Result := Result + [Item('Teil' + IntToStr(mIndex), 'C:\P\Teile.pas', mIndex)];
    end;
  end;
  if ADirection = TAtlasHierarchyDirection.Incoming then
  begin
    Result := TArray<TAtlasHierarchyItem>.Create(Item('Aufrufer', 'C:\P\Haupt.pas', 1));
  end;
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
  mHost: TForm;
  mView: TAtlasCallDiagramView;
  mLoads: Integer;
  mOpened: string;
  mBox: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := NewView(mHost);
    mLoads := 0;
    mView.OnLoad :=
      function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
      begin
        Inc(mLoads);
        Result := Children(ADirection, AItem);
      end;
    mOpened := '';
    mView.OnOpen :=
      procedure(const AItem: TAtlasHierarchyItem)
      begin
        mOpened := AItem.Name;
      end;
    mView.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas',
      1)));
    // Wurzel und erste Ebene (ohne RTL): Start, Laden, Speichern.
    Assert.AreEqual(1, mLoads, 'erste Ebene gleich geladen');
    Assert.AreEqual(3, Integer(Length(mView.Layout.Boxes)));
    mBox := mView.Layout.BoxOf(1);
    Assert.AreEqual('Laden', mView.Diagram[mView.Layout.Boxes[mBox].Node].Item.Name);
    mView.ClickBox(mBox);
    Assert.AreEqual(2, mLoads, 'Klick lädt die nächste Ebene');
    Assert.AreEqual(4, Integer(Length(mView.Layout.Boxes)), 'Lesen dazu');
    Assert.AreEqual(1, mView.Selected);
    mView.ClickBox(mView.Layout.BoxOf(1));
    Assert.AreEqual(2, mLoads, 'Zuklappen lädt nicht neu');
    Assert.AreEqual(3, Integer(Length(mView.Layout.Boxes)));
    mView.ClickBox(mView.Layout.BoxOf(1));
    Assert.AreEqual(2, mLoads, 'Aufklappen nutzt die geladene Ebene');
    Assert.AreEqual(4, Integer(Length(mView.Layout.Boxes)));
    // Doppelklick bzw. Enter öffnet die gewählte Stelle.
    mView.OpenSelected;
    Assert.AreEqual('Laden', mOpened);
    Assert.IsTrue(mView.Html('Aufrufe von Start').Contains('Lesen'), 'HTML enthält die geladenen Ebenen');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.MoreBoxShowsAllChildren;
var
  mHost: TForm;
  mView: TAtlasCallDiagramView;
  mIndex, mMore: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := NewView(mHost);
    mView.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Viele', 'C:\P\Haupt.pas',
      1)));
    mMore := -1;
    for mIndex := 0 to High(mView.Layout.Boxes) do
    begin
      if mView.Layout.Boxes[mIndex].Kind = TAtlasCallBoxKind.More then
      begin
        mMore := mIndex;
      end;
    end;
    Assert.IsTrue(mMore >= 0, '„+ N …“ bei zehn Kindern');
    Assert.AreEqual(2, mView.Layout.Boxes[mMore].Hidden);
    Assert.AreEqual(1 + TAtlasCallDiagram.cMaxChildren + 1, Integer(Length(mView.Layout.Boxes)));
    mView.ClickBox(mMore);
    Assert.AreEqual(11, Integer(Length(mView.Layout.Boxes)), 'Klick zeigt alle');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.ProjectOnlyHidesLibraryCalls;
var
  mHost: TForm;
  mView: TAtlasCallDiagramView;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := NewView(mHost);
    mView.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas',
      1)));
    Assert.IsTrue(mView.ProjectOnly, 'Vorgabe: nur Projekt-Units');
    Assert.AreEqual(3, Integer(Length(mView.Layout.Boxes)));
    mView.ProjectOnly := False;
    Assert.AreEqual(4, Integer(Length(mView.Layout.Boxes)), 'IntToStr aus der RTL wieder da');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.FrameToggleOnlyWhenAllowed;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mRoots: TArray<TAtlasHierarchyItem>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Hierarchy.OnExpand := Children;
    // Wie in NewView: ohne Projektfilter stünde IntToStr aus der RTL als vierte Box da.
    mFrame.Hierarchy.IsProjectFile := IsProject;
    mRoots := TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas', 1));
    // Ohne callHierarchy.diagram: kein Umschalter, auch nicht auf Wunsch.
    mFrame.Hierarchy.DiagramAllowed := False;
    mFrame.Hierarchy.Show('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing, mRoots, True);
    Assert.IsFalse(mFrame.Hierarchy.Controls.Toggle.Visible);
    Assert.IsFalse(mFrame.Hierarchy.ShowsDiagram);
    Assert.IsTrue(mFrame.Tree.Visible);
    // Erlaubt: Umschalter bei Aufrufhierarchien, nicht bei Typhierarchien.
    mFrame.Hierarchy.DiagramAllowed := True;
    mFrame.Hierarchy.Show('Vorfahren', TAtlasHierarchyDirection.Supertypes, mRoots);
    Assert.IsFalse(mFrame.Hierarchy.Controls.Toggle.Visible, 'Typhierarchie ohne Diagramm');
    mFrame.Hierarchy.Show('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing, mRoots);
    Assert.IsTrue(mFrame.Hierarchy.Controls.Toggle.Visible);
    Assert.IsFalse(mFrame.Hierarchy.ShowsDiagram, 'Vorgabe: Liste');
    mFrame.Hierarchy.Controls.Toggle.Checked := True;
    Assert.IsTrue(mFrame.Hierarchy.ShowsDiagram);
    Assert.IsTrue(mFrame.Hierarchy.Controls.Bar.Visible);
    Assert.IsFalse(mFrame.Tree.Visible);
    Assert.AreEqual(3, Integer(Length(mFrame.Hierarchy.Controls.Diagram.Layout.Boxes)));
    // Abschalten der Einstellung nimmt das Diagramm weg.
    mFrame.Hierarchy.DiagramAllowed := False;
    Assert.IsFalse(mFrame.Hierarchy.ShowsDiagram);
    Assert.IsFalse(mFrame.Hierarchy.Controls.Toggle.Visible);
    Assert.IsTrue(mFrame.Tree.Visible);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.FrameSwitchesDirectionAndSavesHtml;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mHtml: string;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Hierarchy.OnExpand := Children;
    mFrame.Hierarchy.DiagramAllowed := True;
    mFrame.Hierarchy.Show('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing,
      TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas', 1)), True);
    Assert.IsTrue(mFrame.Hierarchy.ShowsDiagram, 'gleich als Diagramm');
    Assert.IsTrue(mFrame.Hierarchy.Controls.Outgoing.Checked);
    mFrame.Hierarchy.Controls.Incoming.Checked := True;
    Assert.AreEqual(Ord(TAtlasHierarchyDirection.Incoming), Ord(mFrame.Hierarchy.Direction));
    Assert.IsTrue(mFrame.Hierarchy.ShowsDiagram, 'bleibt Diagramm');
    Assert.AreEqual('Aufrufer', mFrame.Hierarchy.Controls.Diagram.Diagram[1].Item.Name, 'dieselbe Wurzel, eingehend geladen');
    mHtml := mFrame.Hierarchy.DiagramHtml;
    Assert.IsTrue(mHtml.StartsWith('<!DOCTYPE html>', True));
    Assert.IsTrue(mHtml.Contains('Aufrufer'));
    Assert.IsFalse(mHtml.Contains('src="http'), 'keine externen Verweise');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallDiagramViewTests);

end.
