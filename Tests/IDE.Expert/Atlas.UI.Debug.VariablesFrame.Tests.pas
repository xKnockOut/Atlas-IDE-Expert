unit Atlas.UI.Debug.VariablesFrame.Tests;

// Fenster „Variablen“ (#853), Oberfläche: Suche blendet aus und hebt Treffer
// hervor, Reiter Überwachung mit Eingabefeld (Enter fügt an), Entf entfernt
// nur im Reiter Überwachung, Wert kopieren nur mit Wert, F2 ändert den Wert
// nur, wenn „Werte ändern“ bereitsteht (#868), Text unten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugVariablesFrameTests = class
  public
    [Test]
    procedure SearchFiltersAndHighlights;
    [Test]
    procedure WatchTab;
    [Test]
    procedure ValueTextOnlyWithValue;
    [Test]
    procedure EditValueWithF2;
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
  Atlas.UI.Debug.VariablesParts,
  Atlas.UI.Debug.VariablesFrame;

{ TAtlasDebugVariablesFrameTests }

procedure TAtlasDebugVariablesFrameTests.SearchFiltersAndHighlights;
var
  mHost: TForm;
  mFrame: TAtlasDebugVariablesFrame;
  mList: TAtlasEvalList;
  mSearch: TAtlasVariableSearch;
  mNode: TAtlasEvalNode;
begin
  mList := nil;
  mSearch := nil;
  mHost := nil;
  try
    mList := TAtlasEvalList.Create;
    mSearch := TAtlasVariableSearch.Create;
    mHost := TForm.CreateNew(nil);
    mFrame := TAtlasDebugVariablesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mNode := mList.Add('Kunde');
    mNode.Expanded := True;
    mList.SetResult(mNode, True, '(Name: ''Meier''; Ort: ''Berlin'')');
    mList.SetResult(mList.Add('Summe'), True, '42');
    mFrame.SetList(mList, mSearch);
    Assert.AreEqual(4, Integer(mFrame.Tree.Items.Count), 'ohne Suche alles');
    mSearch.Start('berlin', TAtlasVariableSearchMode.Value, False, 3, 500);
    Assert.AreEqual(1, mSearch.Apply(mList));
    mFrame.Refresh;
    Assert.AreEqual(2, Integer(mFrame.Tree.Items.Count), 'Kunde und Ort');
    Assert.AreEqual('Ort = ''Berlin''', mFrame.Tree.Items[1].Text);
    mFrame.SetStatus('1 Treffer');
    Assert.AreEqual('1 Treffer', mFrame.Status.Caption);
    mFrame.SetList(nil, nil);
    Assert.AreEqual(0, Integer(mFrame.Tree.Items.Count));
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
    mFrame.Hooks.AddWatch :=
      procedure(AExpression: string)
      begin
        mAdded := AExpression;
      end;
    mFrame.Hooks.RemoveWatch :=
      procedure(ANode: TAtlasEvalNode)
      begin
        mRemoved := ANode.Key;
      end;
    Assert.IsFalse(mFrame.WatchBar.Visible, 'Autos ohne Eingabefeld');
    mList.SetResult(mList.Add('Liste.Count'), True, '3');
    mFrame.SetList(mList, nil);
    mFrame.Tree.Items[0].Selected := True;
    mKey := VK_DELETE;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('', mRemoved, 'Entf nur im Reiter Überwachung');
    mFrame.SetTab(TAtlasVariablesTab.Watch);
    Assert.IsTrue(mFrame.WatchBar.Visible);
    mKey := VK_DELETE;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('Liste.Count', mRemoved);
    mFrame.WatchEdit.Text := ' Kunde.Name ';
    mKey := VK_RETURN;
    mFrame.WatchEdit.OnKeyDown(mFrame.WatchEdit, mKey, []);
    Assert.AreEqual('Kunde.Name', mAdded);
    Assert.AreEqual('', mFrame.WatchEdit.Text, 'Feld leer für den nächsten');
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
    Assert.AreEqual('', TAtlasVariablesRowActions.ValueText(mNode), 'noch offen');
    mList.SetResult(mNode, True, '''abc''');
    Assert.AreEqual('''abc''', TAtlasVariablesRowActions.ValueText(mNode));
    mList.SetResult(mNode, False, 'E2003');
    Assert.AreEqual('', TAtlasVariablesRowActions.ValueText(mNode), 'Fehler ist kein Wert');
    Assert.AreEqual('', TAtlasVariablesRowActions.ValueText(nil));
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugVariablesFrameTests.EditValueWithF2;
var
  mHost: TForm;
  mFrame: TAtlasDebugVariablesFrame;
  mList: TAtlasEvalList;
  mEdited: string;
  mCanEdit: Boolean;
  mKey: Word;
begin
  mEdited := '';
  mCanEdit := False;
  mList := TAtlasEvalList.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugVariablesFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Hooks.EditValue :=
      procedure(ANode: TAtlasEvalNode)
      begin
        mEdited := ANode.Expression;
      end;
    mFrame.Hooks.CanEditValue :=
      function: Boolean
      begin
        Result := mCanEdit;
      end;
    mList.SetResult(mList.Add('Betrag'), True, '125');
    mList.Add('Offen');
    mFrame.SetList(mList, nil);
    mFrame.Tree.Items[0].Selected := True;
    mKey := VK_F2;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('', mEdited, 'ohne „Werte ändern“ nichts');
    mCanEdit := True;
    mKey := VK_F2;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('Betrag', mEdited);
    mEdited := '';
    mFrame.Tree.Items[1].Selected := True;
    mKey := VK_F2;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual('', mEdited, 'ohne Wert nichts zu ändern');
    mFrame.SetList(nil, nil);
  finally
    mHost.Free;
    mList.Free;
  end;
  mEdited := '';
end;

end.
