unit Atlas.UI.Debug.VariablesFrame.Tests;

// Fenster „Variablen“ (#853), Oberfläche: Suche blendet aus und hebt Treffer
// hervor, Reiter Überwachung mit Eingabefeld (Enter fügt an), Entf entfernt
// nur im Reiter Überwachung, Wert kopieren nur mit Wert, Text unten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugVariablesFrameTests = class
  public
    /// <summary>Einmalige VCL-Puffer (Baumansicht) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure SearchFiltersAndHighlights;
    [Test]
    procedure WatchTab;
    [Test]
    procedure ValueTextOnlyWithValue;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.UI.Debug.VariablesFrame;

{ TAtlasDebugVariablesFrameTests }

procedure TAtlasDebugVariablesFrameTests.WarmUpFirstUse;
begin
  SearchFiltersAndHighlights;
end;

procedure TAtlasDebugVariablesFrameTests.SearchFiltersAndHighlights;
var
  mHost: TForm;
  mFrame: TAtlasDebugVariablesFrame;
  mList: TAtlasEvalList;
  mSearch: TAtlasVariableSearch;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  mSearch := TAtlasVariableSearch.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugVariablesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mNode := mList.Add('Kunde');
    mNode.Expanded := True;
    mList.SetResult(mNode, True, '(Name: ''Meier''; Ort: ''Berlin'')');
    mList.SetResult(mList.Add('Summe'), True, '42');
    mFrame.SetList(mList, mSearch);
    Assert.AreEqual(4, Integer(mFrame.Parts.Tree.Items.Count), 'ohne Suche alles');
    mSearch.Start('berlin', TAtlasVariableSearchMode.Value, False, 3, 500);
    Assert.AreEqual(1, mSearch.Apply(mList));
    mFrame.Refresh;
    Assert.AreEqual(2, Integer(mFrame.Parts.Tree.Items.Count), 'Kunde und Ort');
    Assert.AreEqual('Ort = ''Berlin''', mFrame.Parts.Tree.Items[1].Text);
    mFrame.SetStatus('1 Treffer');
    Assert.AreEqual('1 Treffer', mFrame.Parts.Status.Caption);
    mFrame.SetList(nil, nil);
    Assert.AreEqual(0, Integer(mFrame.Parts.Tree.Items.Count));
  finally
    mHost.Free;
    mSearch.Free;
    mList.Free;
  end;
end;

procedure TAtlasDebugVariablesFrameTests.WatchTab;
var
  mHost: TForm;
  mFrame: TAtlasDebugVariablesFrame;
  mList: TAtlasEvalList;
  mAdded, mRemoved: string;
  mKey: Word;
begin
  mAdded := '';
  mRemoved := '';
  mList := TAtlasEvalList.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugVariablesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.OnAddWatch :=
      procedure(AExpression: string)
      begin
        mAdded := AExpression;
      end;
    mFrame.OnRemoveWatch :=
      procedure(ANode: TAtlasEvalNode)
      begin
        mRemoved := ANode.Key;
      end;
    Assert.IsFalse(mFrame.Parts.WatchBar.Visible, 'Autos ohne Eingabefeld');
    mList.SetResult(mList.Add('Liste.Count'), True, '3');
    mFrame.SetList(mList, nil);
    mFrame.Parts.Tree.Items[0].Selected := True;
    mKey := VK_DELETE;
    mFrame.Parts.Tree.OnKeyDown(mFrame.Parts.Tree, mKey, []);
    Assert.AreEqual('', mRemoved, 'Entf nur im Reiter Überwachung');
    mFrame.SetTab(TAtlasVariablesTab.Watch);
    Assert.IsTrue(mFrame.Parts.WatchBar.Visible);
    mKey := VK_DELETE;
    mFrame.Parts.Tree.OnKeyDown(mFrame.Parts.Tree, mKey, []);
    Assert.AreEqual('Liste.Count', mRemoved);
    mFrame.Parts.WatchEdit.Text := ' Kunde.Name ';
    mKey := VK_RETURN;
    mFrame.Parts.WatchEdit.OnKeyDown(mFrame.Parts.WatchEdit, mKey, []);
    Assert.AreEqual('Kunde.Name', mAdded);
    Assert.AreEqual('', mFrame.Parts.WatchEdit.Text, 'Feld leer für den nächsten');
    mFrame.SetList(nil, nil);
  finally
    mHost.Free;
    mList.Free;
  end;
  mAdded := '';
  mRemoved := '';
end;

procedure TAtlasDebugVariablesFrameTests.ValueTextOnlyWithValue;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('S');
    Assert.AreEqual('', TAtlasDebugVariablesFrame.ValueText(mNode), 'noch offen');
    mList.SetResult(mNode, True, '''abc''');
    Assert.AreEqual('''abc''', TAtlasDebugVariablesFrame.ValueText(mNode));
    mList.SetResult(mNode, False, 'E2003');
    Assert.AreEqual('', TAtlasDebugVariablesFrame.ValueText(mNode), 'Fehler ist kein Wert');
    Assert.AreEqual('', TAtlasDebugVariablesFrame.ValueText(nil));
  finally
    mList.Free;
  end;
end;

end.
