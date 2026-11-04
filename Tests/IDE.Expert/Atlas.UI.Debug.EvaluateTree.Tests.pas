unit Atlas.UI.Debug.EvaluateTree.Tests;

// Baum des Fensters „Auswerten“ (#784): Text je Zustand (gekürzt, einzeilig,
// grau der alte Wert bis zum neuen, lange Werte erst gekürzt), Aufklappzeichen
// auch während der neuen Auswertung, Abgleich ohne Neuaufbau (dieselben
// Baumknoten nach neuem Wert, neuem Halt und entfernter Zeile), Darstellung je
// Knoten (geändert, grau, fett), Platzhalter ohne Schlüssel, Suche nach
// Schlüssel, Schlüssel bleiben nach vielen Abgleichen richtig.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEvalTreeSyncTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NodeTexts;
    [Test]
    procedure LongValuesCutLikeBefore;
    [Test]
    procedure ExpanderWhilePending;
    [Test]
    procedure SyncKeepsItems;
    [Test]
    procedure SyncRemovesAndAddsRows;
    [Test]
    procedure LooksAndPlaceholders;
    [Test]
    procedure KeysSurviveManyStops;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Vcl.ComCtrls,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateTree;

type
  /// <summary>Baum mit Fenster auf einem eigenen Formular.</summary>
  TTreeHost = record
    Form: TForm;
    Tree: TTreeView;
    Sync: TAtlasEvalTreeSync;
    class function Create: TTreeHost; static;
    procedure Free;
  end;

class function TTreeHost.Create: TTreeHost;
begin
  Result.Form := TForm.CreateNew(nil);
  Result.Tree := TTreeView.Create(Result.Form);
  Result.Tree.Parent := Result.Form;
  Result.Tree.HandleNeeded;
  Result.Sync := TAtlasEvalTreeSync.Create(Result.Tree);
end;

procedure TTreeHost.Free;
begin
  Form.Free;
  Sync.Free;
end;

{ TAtlasEvalTreeSyncTests }

procedure TAtlasEvalTreeSyncTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasEvalTreeSyncTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasEvalTreeSyncTests.NodeTexts;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add(' Summe ');
    Assert.AreEqual('Summe = wird ausgewertet …', TAtlasEvalTreeSync.NodeText(mNode));
    mList.SetResult(mNode, True, '42');
    Assert.AreEqual('Summe = 42', TAtlasEvalTreeSync.NodeText(mNode));
    mList.BeginStop;
    Assert.AreEqual('Summe = 42', TAtlasEvalTreeSync.NodeText(mNode), 'alter Wert bis zum neuen');
    mList.SetResult(mNode, False, 'Undeclared identifier');
    Assert.AreEqual('Summe = Undeclared identifier', TAtlasEvalTreeSync.NodeText(mNode));
    mList.Unavailable;
    Assert.AreEqual('Summe = ‹Programm nicht angehalten›', TAtlasEvalTreeSync.NodeText(mNode));
    mList.BeginStop;
    mList.SetResult(mNode, True, '''a''#13#10''b''' + StringOfChar('x', 300));
    Assert.IsFalse(TAtlasEvalTreeSync.NodeText(mNode).Contains(#13), 'einzeilig');
    Assert.AreEqual(Integer(Length('Summe = ') + TAtlasEvalTreeSync.MaxTreeValue + 1),
      Integer(Length(TAtlasEvalTreeSync.NodeText(mNode))), 'gekürzt mit …');
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalTreeSyncTests.LongValuesCutLikeBefore;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mBreaks: string;
  mIndex: Integer;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('L');
    // Nur Zeilenumbrüche: Aus 2 * MaxTreeValue + 1 Zeichen werden mindestens MaxTreeValue + 1 Leerzeichen.
    mBreaks := '';
    for mIndex := 1 to 300 do
    begin
      mBreaks := mBreaks + #13#10;
    end;
    mList.SetResult(mNode, True, mBreaks);
    Assert.AreEqual('L = ' + StringOfChar(' ', TAtlasEvalTreeSync.MaxTreeValue) + #$2026,
      TAtlasEvalTreeSync.NodeText(mNode), 'CRLF');
    mList.SetResult(mNode, True, StringOfChar(#10, 500));
    Assert.AreEqual('L = ' + StringOfChar(' ', TAtlasEvalTreeSync.MaxTreeValue) + #$2026,
      TAtlasEvalTreeSync.NodeText(mNode), 'LF');
    mList.SetResult(mNode, True, StringOfChar(' ', TAtlasEvalTreeSync.MaxTreeValue));
    Assert.AreEqual('L = ' + StringOfChar(' ', TAtlasEvalTreeSync.MaxTreeValue), TAtlasEvalTreeSync.NodeText(mNode),
      'genau die Grenze: ohne …');
  finally
    mList.Free;
  end;
  mBreaks := '';
end;

procedure TAtlasEvalTreeSyncTests.ExpanderWhilePending;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('P');
    Assert.IsFalse(TAtlasEvalTreeSync.ShowsExpander(mNode), 'noch kein Wert');
    mList.SetResult(mNode, True, '(X: 1; Y: 2)');
    Assert.IsTrue(TAtlasEvalTreeSync.ShowsExpander(mNode));
    mList.BeginStop;
    Assert.IsTrue(TAtlasEvalTreeSync.ShowsExpander(mNode), 'alter Wert war aufklappbar');
    mList.SetResult(mNode, True, '7');
    Assert.IsFalse(TAtlasEvalTreeSync.ShowsExpander(mNode));
    mList.BeginStop;
    Assert.IsFalse(TAtlasEvalTreeSync.ShowsExpander(mNode), 'alter Wert einfach');
    mList.SetResult(mNode, False, 'E2003 (Undeclared identifier)');
    Assert.IsFalse(TAtlasEvalTreeSync.ShowsExpander(mNode), 'Fehler');
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalTreeSyncTests.SyncKeepsItems;
var
  mHost: TTreeHost;
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mRoot, mField: TTreeNode;
begin
  mList := TAtlasEvalList.Create;
  mHost := TTreeHost.Create;
  try
    mNode := mList.Add('Self');
    mList.SetResult(mNode, True, '(FName: ''Meier''; FCount: 3)');
    mList.SetResult(mList.Add('Zahl'), True, '7');
    mHost.Sync.Sync(mList);
    Assert.AreEqual(3, Integer(mHost.Tree.Items.Count), 'Self, Platzhalter, Zahl');
    mRoot := mHost.Tree.Items[0];
    Assert.AreEqual('Self', mHost.Sync.KeyOf(mRoot));
    Assert.AreEqual('', mHost.Sync.KeyOf(mHost.Tree.Items[1]), 'Platzhalter ohne Schlüssel');
    // Neuer Halt: wird ausgewertet, alter Wert und Aufklappzeichen bleiben, kein neuer Baumknoten.
    mList.BeginStop;
    mHost.Sync.Sync(mList);
    Assert.AreEqual(3, Integer(mHost.Tree.Items.Count));
    Assert.IsTrue(Pointer(mHost.Tree.Items[0]) = Pointer(mRoot), 'derselbe Knoten');
    // Aufgeklappt mit Teilen: Kinder kommen dazu, die Zeile bleibt.
    mNode.Expanded := True;
    mList.SetResult(mNode, True, '(FName: ''Meier''; FCount: 4)');
    mHost.Sync.Sync(mList);
    Assert.AreEqual(4, Integer(mHost.Tree.Items.Count), 'Self, FName, FCount, Zahl');
    Assert.IsTrue(Pointer(mHost.Tree.Items[0]) = Pointer(mRoot));
    Assert.IsTrue(mRoot.Expanded);
    Assert.AreEqual('FCount = 4', mHost.Tree.Items[2].Text);
    mField := mHost.Tree.Items[1];
    // Nur ein neuer Wert für Zahl: alle Baumknoten bleiben.
    mList.SetResult(mList.Roots[1], True, '8');
    mHost.Sync.Sync(mList);
    Assert.IsTrue(Pointer(mHost.Tree.Items[1]) = Pointer(mField), 'Feld bleibt');
    Assert.AreEqual('Zahl = 8', mHost.Tree.Items[3].Text);
    Assert.IsTrue(mHost.Sync.ItemOf('Zahl') = mHost.Tree.Items[3]);
    Assert.IsNull(mHost.Sync.ItemOf('weg'));
  finally
    mHost.Free;
    mList.Free;
  end;
end;

procedure TAtlasEvalTreeSyncTests.SyncRemovesAndAddsRows;
var
  mHost: TTreeHost;
  mList: TAtlasEvalList;
  mFirst, mThird: TTreeNode;
begin
  mList := TAtlasEvalList.Create;
  mHost := TTreeHost.Create;
  try
    mList.SetResult(mList.Add('A'), True, '1');
    mList.SetResult(mList.Add('B'), True, '2');
    mList.SetResult(mList.Add('C'), True, '3');
    mHost.Sync.Sync(mList);
    mFirst := mHost.Tree.Items[0];
    mThird := mHost.Tree.Items[2];
    mList.Delete(1);
    mHost.Sync.Sync(mList);
    Assert.AreEqual(2, Integer(mHost.Tree.Items.Count));
    Assert.IsTrue(Pointer(mHost.Tree.Items[0]) = Pointer(mFirst));
    Assert.IsTrue(Pointer(mHost.Tree.Items[1]) = Pointer(mThird), 'C bleibt stehen');
    mList.Add('D');
    mHost.Sync.Sync(mList);
    Assert.AreEqual(3, Integer(mHost.Tree.Items.Count));
    Assert.AreEqual('D', mHost.Sync.KeyOf(mHost.Tree.Items[2]));
    mHost.Sync.Sync(nil);
    Assert.AreEqual(0, Integer(mHost.Tree.Items.Count), 'ohne Liste leer');
  finally
    mHost.Free;
    mList.Free;
  end;
end;

procedure TAtlasEvalTreeSyncTests.LooksAndPlaceholders;
var
  mHost: TTreeHost;
  mList: TAtlasEvalList;
  mNode, mOther: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  mHost := TTreeHost.Create;
  try
    mNode := mList.Add('A');
    mNode.Pinned := True;
    mList.SetResult(mNode, True, '1');
    mOther := mList.Add('B');
    mList.SetResult(mOther, False, 'Fehler');
    mHost.Sync.Sync(mList);
    Assert.IsTrue(mHost.Sync.InfoOf(mHost.Tree.Items[0]).Bold, 'festgeheftet fett');
    Assert.IsTrue(mHost.Sync.InfoOf(mHost.Tree.Items[0]).Look = TAtlasEvalLook.Normal);
    Assert.IsTrue(mHost.Sync.InfoOf(mHost.Tree.Items[1]).Look = TAtlasEvalLook.Gray, 'Fehler grau');
    mList.BeginStop;
    mList.SetResult(mNode, True, '2');
    mHost.Sync.Sync(mList);
    Assert.IsTrue(mHost.Sync.InfoOf(mHost.Tree.Items[0]).Look = TAtlasEvalLook.Changed, 'geändert');
    mNode.Pinned := False;
    mHost.Sync.Sync(mList);
    Assert.IsFalse(mHost.Sync.InfoOf(mHost.Tree.Items[0]).Bold);
    // Aufgeklappt ohne Felder: Platzhalter „(keine Felder)“, grau, ohne Schlüssel.
    mList.SetFields(mOther, nil);
    mHost.Sync.Sync(mList);
    Assert.AreEqual('(keine Felder)', mHost.Tree.Items[2].Text);
    Assert.IsTrue(mHost.Sync.InfoOf(mHost.Tree.Items[2]).Look = TAtlasEvalLook.Gray);
    Assert.AreEqual('', mHost.Sync.KeyOf(mHost.Tree.Items[2]));
    Assert.IsTrue(mHost.Sync.InfoOf(nil).Look = TAtlasEvalLook.Gray, 'nil');
  finally
    mHost.Free;
    mList.Free;
  end;
end;

procedure TAtlasEvalTreeSyncTests.KeysSurviveManyStops;
var
  mHost: TTreeHost;
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mStop: Integer;
begin
  mList := TAtlasEvalList.Create;
  mHost := TTreeHost.Create;
  try
    mNode := mList.Add('P');
    mNode.Expanded := True;
    mList.SetResult(mList.Add('Q'), True, '0');
    // Teile entstehen je Halt neu: Die alten Einträge der Tabelle werden zwischendurch aufgeräumt.
    for mStop := 1 to 200 do
    begin
      mList.BeginStop;
      mHost.Sync.Sync(mList);
      mList.SetResult(mNode, True, Format('(X: %d; Y: %d)', [mStop, mStop + 1]));
      mList.SetResult(mList.Roots[1], True, IntToStr(mStop));
      mHost.Sync.Sync(mList);
    end;
    Assert.AreEqual(4, Integer(mHost.Tree.Items.Count));
    Assert.AreEqual('P', mHost.Sync.KeyOf(mHost.Tree.Items[0]));
    Assert.AreEqual('P'#1'X', mHost.Sync.KeyOf(mHost.Tree.Items[1]));
    Assert.AreEqual('P'#1'Y', mHost.Sync.KeyOf(mHost.Tree.Items[2]));
    Assert.AreEqual('Q', mHost.Sync.KeyOf(mHost.Tree.Items[3]));
    Assert.AreEqual('Y = 201', mHost.Tree.Items[2].Text);
  finally
    mHost.Free;
    mList.Free;
  end;
end;

end.
