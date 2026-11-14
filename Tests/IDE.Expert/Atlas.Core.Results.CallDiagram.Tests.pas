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
    /// <summary>Mit englischer Oberfläche: lang="en", englische Beschriftung, kein Platzhalter übrig (#1458).
    /// </summary>
    [Test]
    procedure HtmlFollowsLanguage;
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
  Atlas.Core.Localization.Language,
  Atlas.Core.Results.CallDiagram;

function Item(const AName, AFileName: string; ALine: Integer): TAtlasHierarchyItem;
begin
  Result := Default(TAtlasHierarchyItem);
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

function ProjectFile(const AFileName: string): Boolean;
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
  mDiagram: TAtlasCallDiagram;
  mLayout: TAtlasCallLayout;
begin
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    Assert.IsTrue(mDiagram.NeedsLoad(0));
    Assert.IsFalse(mDiagram.Toggle(0), 'erst laden');
    mLayout := mDiagram.Layout;
    Assert.AreEqual(1, Integer(Length(mLayout.Boxes)));
    // Erste Ebene: zwei Aufgerufene rechts daneben, der Start mittig davor.
    mDiagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Zeigen', 'C:\P\B.pas', 20)]);
    Assert.IsFalse(mDiagram.NeedsLoad(0));
    mLayout := mDiagram.Layout;
    Assert.AreEqual(3, Integer(Length(mLayout.Boxes)));
    Assert.AreEqual(2, Integer(Length(mLayout.Edges)));
    Assert.AreEqual(0, mLayout.Boxes[mLayout.BoxOf(0)].Column);
    Assert.AreEqual(0.5, mLayout.Boxes[mLayout.BoxOf(0)].Row, 0.001);
    Assert.AreEqual(1, mLayout.Boxes[mLayout.BoxOf(1)].Column);
    Assert.AreEqual(0.0, mLayout.Boxes[mLayout.BoxOf(1)].Row, 0.001);
    Assert.AreEqual(1.0, mLayout.Boxes[mLayout.BoxOf(2)].Row, 0.001);
    Assert.AreEqual(2, mLayout.Columns);
    // Dritte Ebene erst nach Klick auf „Laden“.
    Assert.IsTrue(mDiagram.NeedsLoad(1));
    mDiagram.SetChildren(1, [Item('Lesen', 'C:\P\C.pas', 5)]);
    mLayout := mDiagram.Layout;
    Assert.AreEqual(3, mLayout.Columns);
    Assert.AreEqual(2, mDiagram[3].Level);
    // Zuklappen blendet die Ebenen darunter aus, Aufklappen zeigt sie ohne neues Laden.
    Assert.IsTrue(mDiagram.Toggle(0));
    Assert.AreEqual(1, Integer(Length(mDiagram.Layout.Boxes)));
    Assert.IsTrue(mDiagram.Toggle(0));
    Assert.AreEqual(4, Integer(Length(mDiagram.Layout.Boxes)));
    // Ohne Kinder lässt sich nichts aufklappen.
    mDiagram.SetChildren(2, []);
    Assert.IsTrue(mDiagram.Toggle(2), 'zuklappen geht');
    Assert.IsFalse(mDiagram.Toggle(2), 'aufklappen ohne Kinder nicht');
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.RecursionBecomesBackArrow;
var
  mDiagram: TAtlasCallDiagram;
  mLayout: TAtlasCallLayout;
  mEdge: TAtlasCallEdge;
  mBacks: Integer;
begin
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Zaehle', 'C:\P\A.pas', 3)]);
    mDiagram.SetChildren(0, [Item('Hilfe', 'C:\P\A.pas', 9)]);
    // Hilfe ruft Zaehle zurück: kein neuer Kasten, sondern ein Pfeil zurück.
    mDiagram.SetChildren(1, [Item('Zaehle', 'C:\P\A.pas', 3), Item('Hilfe', 'C:\P\A.pas', 9)]);
    Assert.AreEqual(0, mDiagram[2].BackTo);
    Assert.AreEqual(1, mDiagram[3].BackTo, 'Selbstaufruf');
    Assert.IsFalse(mDiagram.NeedsLoad(2));
    Assert.IsFalse(mDiagram.Toggle(2));
    mLayout := mDiagram.Layout;
    Assert.AreEqual(2, Integer(Length(mLayout.Boxes)));
    mBacks := 0;
    for mEdge in mLayout.Edges do
    begin
      if mEdge.Back then
      begin
        Inc(mBacks);
        Assert.AreEqual(mLayout.BoxOf(1), mEdge.Source);
      end;
    end;
    Assert.AreEqual(2, mBacks);
    // Weiteres Laden unter einer Rekursion wird ignoriert.
    mDiagram.SetChildren(2, [Item('X', 'C:\P\A.pas', 1)]);
    Assert.AreEqual(0, Integer(Length(mDiagram[2].Children)));
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.MoreThanEightChildrenAreSummarized;
var
  mDiagram: TAtlasCallDiagram;
  mChildren: TArray<TAtlasHierarchyItem>;
  mIndex, mMore: Integer;
  mLayout: TAtlasCallLayout;
  mBox: TAtlasCallBox;
  mFound: Boolean;
begin
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Speichern', 'C:\P\A.pas', 3)]);
    mChildren := nil;
    for mIndex := 1 to 11 do
    begin
      mChildren := mChildren + [Item('Aufrufer' + IntToStr(mIndex), 'C:\P\A.pas', 10 + mIndex)];
    end;
    mDiagram.SetChildren(0, mChildren);
    Assert.AreEqual(8, Integer(Length(mDiagram.VisibleChildren(0, mMore))));
    Assert.AreEqual(3, mMore);
    mLayout := mDiagram.Layout;
    Assert.AreEqual(10, Integer(Length(mLayout.Boxes)), 'Wurzel, 8 Kinder, „+ 3 …“');
    mFound := False;
    for mBox in mLayout.Boxes do
    begin
      if mBox.Kind = TAtlasCallBoxKind.More then
      begin
        mFound := True;
        Assert.AreEqual(3, mBox.Hidden);
        Assert.AreEqual(0, mBox.Node);
        Assert.AreEqual(1, mBox.Column);
      end;
    end;
    Assert.IsTrue(mFound);
    mDiagram.ShowAll(0);
    Assert.AreEqual(12, Integer(Length(mDiagram.Layout.Boxes)));
    // Genau acht bleiben ohne Zusammenfassung.
    mDiagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Speichern', 'C:\P\A.pas', 3)]);
    mDiagram.SetChildren(0, Copy(mChildren, 0, 8));
    Assert.AreEqual(8, Integer(Length(mDiagram.VisibleChildren(0, mMore))));
    Assert.AreEqual(0, mMore);
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.ProjectOnlyHidesLibraryUnits;
var
  mDiagram: TAtlasCallDiagram;
  mMore: Integer;
begin
  mDiagram := NewDiagram;
  try
    Assert.IsTrue(mDiagram.ProjectOnly, 'Vorgabe an');
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Format', 'C:\RTL\System.SysUtils.pas', 99),
      Item('Ohne', '', 0)]);
    Assert.IsTrue(mDiagram[2].Library_);
    Assert.IsTrue(mDiagram[3].Library_, 'ohne Datei');
    Assert.AreEqual(1, Integer(Length(mDiagram.VisibleChildren(0, mMore))));
    mDiagram.ProjectOnly := False;
    Assert.AreEqual(3, Integer(Length(mDiagram.VisibleChildren(0, mMore))));
    Assert.AreEqual(4, Integer(Length(mDiagram.Layout.Boxes)));
  finally
    mDiagram.Free;
  end;
  // Ohne Entscheider gehört alles mit Datei zum Projekt.
  mDiagram := TAtlasCallDiagram.Create(nil);
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [Item('Format', 'C:\RTL\System.SysUtils.pas', 99)]);
    Assert.IsFalse(mDiagram[1].Library_);
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.DispatchedCallsAreDashed;
var
  mDiagram: TAtlasCallDiagram;
  mOver, mViaVirtual, mPlain: TAtlasHierarchyItem;
  mLayout: TAtlasCallLayout;
  mEdge: TAtlasCallEdge;
begin
  mOver := Item('Speichern', 'C:\P\A.pas', 4);
  mOver.Dispatch := 'interface';
  mOver.Implementations := 3;
  // Eingehend: erschlossen über virtual (#1119) ohne atlasDispatch eines älteren Servers.
  mViaVirtual := Item('Laden', 'C:\P\A.pas', 5);
  mViaVirtual.Confidence.Inferred := True;
  mViaVirtual.Confidence.Reason := 'virtual';
  mPlain := Item('Fertig', 'C:\P\A.pas', 6);
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [mOver, mViaVirtual, mPlain]);
    mLayout := mDiagram.Layout;
    for mEdge in mLayout.Edges do
    begin
      if mLayout.Boxes[mEdge.Target].Node = 1 then
      begin
        Assert.IsTrue(mEdge.Dashed);
        Assert.AreEqual(3, mEdge.Implementations);
      end
      else if mLayout.Boxes[mEdge.Target].Node = 2 then
      begin
        Assert.IsTrue(mEdge.Dashed);
      end
      else
      begin
        Assert.IsFalse(mEdge.Dashed);
      end;
    end;
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.DuplicateChildrenAreMerged;
var
  mDiagram: TAtlasCallDiagram;
  mInferred: TAtlasHierarchyItem;
begin
  mInferred := Item('Aufrufer', 'C:\P\A.pas', 7);
  mInferred.Confidence.Inferred := True;
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Ziel', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [Item('Aufrufer', 'C:\P\A.pas', 7), mInferred]);
    Assert.AreEqual(1, Integer(Length(mDiagram[0].Children)));
    Assert.AreEqual(2, mDiagram.Count);
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.TitleAndLocation;
var
  mEntry: TAtlasHierarchyItem;
begin
  mEntry := Item('Laden', 'C:\P\Ref.Kunden.pas', 11);
  mEntry.Detail := 'TKunde · Ref.Kunden';
  Assert.AreEqual('TKunde.Laden', TAtlasCallDiagram.Title(mEntry));
  mEntry.Detail := 'Ref.Kunden';
  Assert.AreEqual('Laden', TAtlasCallDiagram.Title(mEntry));
  mEntry.Detail := 'TKunde';
  Assert.AreEqual('TKunde.Laden', TAtlasCallDiagram.Title(mEntry));
  Assert.AreEqual('Ref.Kunden.pas:12', TAtlasCallDiagram.Location(mEntry));
  mEntry.FileName := '';
  Assert.AreEqual('', TAtlasCallDiagram.Location(mEntry));
end;

procedure TAtlasCallDiagramTests.ViewFitsZoomsAndHits;
var
  mDiagram: TAtlasCallDiagram;
  mLayout: TAtlasCallLayout;
  mView: TAtlasCallView;
  mBox: TAtlasCallBox;
  X, Y, mBeforeX: Double;
begin
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10), Item('Zeigen', 'C:\P\B.pas', 20)]);
    mLayout := mDiagram.Layout;
  finally
    mDiagram.Free;
  end;
  mView := Default(TAtlasCallView);
  mView.Fit(mLayout, 1000, 600);
  Assert.AreEqual(1.0, mView.Scale, 0.001, 'kleine Diagramme nicht vergrößert');
  mView.Fit(mLayout, 250, 100);
  Assert.IsTrue(mView.Scale < 1);
  mView.Fit(mLayout, 1000, 600);
  mBox := mLayout.Boxes[mLayout.BoxOf(2)];
  X := mView.ScreenX(TAtlasCallView.BoxX(mBox)) + 10;
  Y := mView.ScreenY(TAtlasCallView.BoxY(mBox)) + 10;
  Assert.AreEqual(mLayout.BoxOf(2), mView.BoxAt(mLayout, X, Y));
  Assert.AreEqual(-1, mView.BoxAt(mLayout, 1, 1));
  // Zoomen um den Punkt lässt ihn stehen.
  mBeforeX := mView.ScreenX(TAtlasCallView.BoxX(mBox));
  mView.ZoomAt(2, mBeforeX, Y);
  Assert.AreEqual(mBeforeX, mView.ScreenX(TAtlasCallView.BoxX(mBox)), 0.001);
  Assert.AreEqual(2.0, mView.Scale, 0.001);
  mView.ZoomAt(100, 0, 0);
  Assert.AreEqual(TAtlasCallView.cMaxScale, mView.Scale, 0.001);
  mView.Pan(5, -5);
  Assert.AreEqual(mLayout.BoxOf(2), mView.BoxAt(mLayout, mView.ScreenX(TAtlasCallView.BoxX(mBox)) + 1,
    mView.ScreenY(TAtlasCallView.BoxY(mBox)) + 1));
end;

procedure TAtlasCallDiagramTests.JsonHoldsLoadedLevels;
var
  mDiagram: TAtlasCallDiagram;
  mOver: TAtlasHierarchyItem;
  mData: TJSONValue;
  mNodes: TJSONArray;
begin
  mOver := Item('Speichern', 'C:\P\A.pas', 4);
  mOver.Dispatch := 'interface';
  mOver.Implementations := 2;
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Incoming, [Item('Start', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [mOver, Item('Start', 'C:\P\A.pas', 1), Item('Format', 'C:\RTL\System.SysUtils.pas', 9)]);
    mData := TJSONObject.ParseJSONValue(mDiagram.Json('Start'));
    try
      Assert.AreEqual(1, mData.GetValue<Integer>('format'));
      Assert.AreEqual('incoming', mData.GetValue<string>('direction'));
      Assert.IsTrue(mData.GetValue<Boolean>('projectOnly'));
      Assert.AreEqual(8, mData.GetValue<Integer>('maxChildren'));
      mNodes := mData.GetValue<TJSONArray>('nodes');
      Assert.AreEqual(4, mNodes.Count);
      Assert.AreEqual(-1.0, mNodes.Items[0].GetValue<Double>('parent'), 0.001);
      Assert.IsTrue(mNodes.Items[0].GetValue<Boolean>('expanded'));
      Assert.AreEqual('interface', mNodes.Items[1].GetValue<string>('dispatch'));
      Assert.AreEqual(2, mNodes.Items[1].GetValue<Integer>('implementations'));
      Assert.AreEqual(5, mNodes.Items[1].GetValue<Integer>('line'), 'Zeilen ab 1');
      Assert.AreEqual('A.pas:5', mNodes.Items[1].GetValue<string>('location'));
      Assert.AreEqual(0, mNodes.Items[2].GetValue<Integer>('backTo'));
      Assert.IsTrue(mNodes.Items[3].GetValue<Boolean>('library'));
    finally
      mData.Free;
    end;
  finally
    mDiagram.Free;
  end;
end;

procedure TAtlasCallDiagramTests.HtmlFollowsLanguage;
var
  mDiagram: TAtlasCallDiagram;
  mHtml: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasTextLanguage.Current;
  TAtlasTextLanguage.Current := TAtlasLanguage.English;
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start', 'C:\P\A.pas', 1)]);
    mHtml := mDiagram.Html('TForm1.Start');
  finally
    mDiagram.Free;
    TAtlasTextLanguage.Current := mSaved;
  end;
  Assert.IsTrue(Pos('<html lang="en">', mHtml) > 0, 'Sprache');
  Assert.IsTrue(Pos('<title>Call diagram: TForm1.Start</title>', mHtml) > 0, 'Titel');
  Assert.IsTrue(Pos('project units only', mHtml) > 0, 'Schalter');
  Assert.AreEqual(0, Pos('{{', mHtml), 'Platzhalter');
  Assert.AreEqual(0, Pos('nur Projekt-Units', mHtml), 'deutscher Schalter');
end;

procedure TAtlasCallDiagramTests.HtmlIsSelfContained;
var
  mDiagram: TAtlasCallDiagram;
  mHtml: string;
begin
  mDiagram := NewDiagram;
  try
    mDiagram.Reset(TAtlasHierarchyDirection.Outgoing, [Item('Start</script>', 'C:\P\A.pas', 1)]);
    mDiagram.SetChildren(0, [Item('Laden', 'C:\P\A.pas', 10)]);
    mHtml := mDiagram.Html('TForm1.Start & Co');
  finally
    mDiagram.Free;
  end;
  Assert.StartsWith('<!doctype html>', mHtml);
  Assert.IsTrue(Pos('<title>Aufrufdiagramm: TForm1.Start &amp; Co</title>', mHtml) > 0, 'Titel maskiert');
  Assert.AreEqual(0, Pos('{{DATA}}', mHtml));
  Assert.AreEqual(0, Pos('{{TITLE}}', mHtml));
  // Nur ein schließendes script je Skript: der Name im JSON beendet das Datenelement nicht.
  Assert.AreEqual(0, Pos('Start</script>', mHtml));
  Assert.IsTrue(Pos('"name":"Laden"', mHtml) > 0);
  Assert.AreEqual(0, Pos('src="http', mHtml));
  Assert.AreEqual(0, Pos('href="http', mHtml));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallDiagramTests);

end.
