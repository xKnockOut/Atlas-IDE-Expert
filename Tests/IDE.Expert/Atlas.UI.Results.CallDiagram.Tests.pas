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
    [Test]
    procedure LateLevelArrivesAndStaleIsDropped;
    [Test]
    procedure TreeShowsPlaceholderUntilLevelArrives;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Plugin.Lsp.Contract,
  Atlas.Core.Results.CallDiagram,
  Atlas.UI.Results.CallDiagram,
  Atlas.UI.Results.Frame,
  Atlas.Core.Lsp.TestSupport;

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

/// <summary>Wie der Server, aber sofort: Children an ADone.</summary>
procedure LoadNow(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem;
  const ADone: TAtlasCallLoaded);
begin
  ADone(Children(ADirection, AItem));
end;

type
  /// <summary>Hält Anfragen fest, bis der Test sie beantwortet (wie eine Antwort aus dem Hintergrund).</summary>
  TLoadProbe = class
  public
    Items: TArray<TAtlasHierarchyItem>;
    Dones: TArray<TAtlasCallLoaded>;
    function Load: TAtlasCallLoad;
    /// <summary>Anfrage AIndex mit den Kindern ihres Eintrags beantworten.</summary>
    procedure Answer(AIndex: Integer);
  end;

function TLoadProbe.Load: TAtlasCallLoad;
begin
  Result :=
    procedure(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem; const ADone: TAtlasCallLoaded)
    begin
      Items := Items + [AItem];
      SetLength(Dones, Length(Dones) + 1);
      Dones[High(Dones)] := ADone;
    end;
end;

procedure TLoadProbe.Answer(AIndex: Integer);
begin
  Dones[AIndex](Children(TAtlasHierarchyDirection.Outgoing, Items[AIndex]));
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
  Result.OnLoad := LoadNow;
end;

{ TAtlasCallDiagramViewTests }

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
      procedure(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem; const ADone: TAtlasCallLoaded)
      begin
        Inc(mLoads);
        ADone(Children(ADirection, AItem));
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
    mFrame.Hierarchy.OnExpand := LoadNow;
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
    mFrame.Hierarchy.OnExpand := LoadNow;
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

procedure TAtlasCallDiagramViewTests.LateLevelArrivesAndStaleIsDropped;
var
  mHost: TForm;
  mView: TAtlasCallDiagramView;
  mProbe: TLoadProbe;
begin
  mProbe := nil;
  mHost := TForm.CreateNew(nil);
  try
    mProbe := TLoadProbe.Create;
    mView := NewView(mHost);
    mView.OnLoad := mProbe.Load();
    mView.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas',
      1)));
    Assert.AreEqual(1, Integer(Length(mProbe.Dones)), 'erste Ebene angefragt');
    Assert.AreEqual(1, Integer(Length(mView.Layout.Boxes)), 'bis zur Antwort nur die Wurzel');
    // Ein zweiter Klick, solange die Ebene unterwegs ist, fragt nicht erneut.
    mView.ToggleNode(0);
    Assert.AreEqual(1, Integer(Length(mProbe.Dones)));
    mProbe.Answer(0);
    Assert.AreEqual(3, Integer(Length(mView.Layout.Boxes)), 'Antwort zeichnet die Ebene');
    // Neue Wurzeln: Die Antwort für die alten verfällt.
    mView.ToggleNode(1);
    Assert.AreEqual(2, Integer(Length(mProbe.Dones)));
    mView.ShowRoots(TAtlasHierarchyDirection.Outgoing, TArray<TAtlasHierarchyItem>.Create(Item('Viele', 'C:\P\Haupt.pas',
      1)));
    mProbe.Answer(1);
    Assert.AreEqual(1, Integer(Length(mView.Layout.Boxes)), 'alte Antwort ändert nichts');
    Assert.AreEqual('Viele', mView.Diagram[0].Item.Name);
  finally
    mHost.Free;
    if mProbe <> nil then
    begin
      mProbe.Items := nil;
      mProbe.Dones := nil;
    end;
    mProbe.Free;
  end;
end;

procedure TAtlasCallDiagramViewTests.TreeShowsPlaceholderUntilLevelArrives;
var
  mHost: TForm;
  mFrame: TAtlasResultsFrame;
  mProbe: TLoadProbe;
  mRoot: TTreeNode;
begin
  mProbe := nil;
  mHost := TForm.CreateNew(nil);
  try
    mProbe := TLoadProbe.Create;
    mFrame := TAtlasResultsFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Hierarchy.OnExpand := mProbe.Load();
    mFrame.Hierarchy.IsProjectFile := IsProject;
    mFrame.Hierarchy.Show('Aufrufe von Start', TAtlasHierarchyDirection.Outgoing,
      TArray<TAtlasHierarchyItem>.Create(Item('Start', 'C:\P\Haupt.pas', 1)));
    Assert.AreEqual(1, Integer(Length(mProbe.Dones)), 'erste Ebene angefragt');
    mRoot := mFrame.Tree.Items[0];
    Assert.AreEqual(1, Integer(mRoot.Count), 'Platzhalter bis zur Antwort');
    Assert.AreEqual('…', mRoot.Item[0].Text);
    mProbe.Answer(0);
    Assert.AreEqual(3, Integer(mRoot.Count), 'Antwort ersetzt den Platzhalter');
    Assert.AreEqual('Laden', mRoot.Item[0].Text.Split([' '])[0]);
  finally
    mHost.Free;
    if mProbe <> nil then
    begin
      mProbe.Items := nil;
      mProbe.Dones := nil;
    end;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallDiagramViewTests);

end.
