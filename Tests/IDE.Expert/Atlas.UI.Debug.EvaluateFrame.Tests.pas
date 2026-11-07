unit Atlas.UI.Debug.EvaluateFrame.Tests;

// Fenster „Auswerten“ (#784), Oberfläche (Text im Baum: EvaluateTree.Tests):
// Ansichten unten (Text mit sichtbaren Steuerzeichen, Zeilen aus „.Text“,
// JSON, Hex, Hinweis bei unpassender Ansicht), Baum mit Platzhalter zum Aufklappen und Kindern aus
// Teilen, Enter/Strg+Enter im Eingabefeld, Entf auf einem Feld entfernt die
// ganze Zeile, Knopf „Festheften“ bzw. „Lösen“, Tastenhilfe passt ihre Höhe der
// Breite an (kein leerer Streifen unten, Baum wächst mit), Reihenfolge der Knöpfe.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugEvaluateFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    /// <summary>Einmalige VCL-Puffer (Baumansicht) vor dem Leckmonitor anlegen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DetailViews;
    [Test]
    procedure TreeWithPlaceholderAndParts;
    [Test]
    procedure InputKeys;
    [Test]
    procedure DeleteRemovesWholeRow;
    [Test]
    procedure PinCaption;
    [Test]
    procedure KeysFollowWidth;
    [Test]
    procedure ButtonOrder;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateFrame;

{ TAtlasDebugEvaluateFrameTests }

procedure TAtlasDebugEvaluateFrameTests.WarmUpFirstUse;
begin
  Setup;
  try
    TreeWithPlaceholderAndParts;
  finally
    TearDown;
  end;
end;

procedure TAtlasDebugEvaluateFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugEvaluateFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugEvaluateFrameTests.DetailViews;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mUnfit: Boolean;
begin
  mList := TAtlasEvalList.Create;
  try
    Assert.AreEqual('Eine Zeile wählen, um ihren Wert zu sehen.',
      TAtlasDebugEvaluateFrame.DetailText(nil, TAtlasEvalView.Text, False, '', mUnfit));
    mNode := mList.Add('S');
    mList.SetResult(mNode, True, '''a''#9''b''');
    Assert.AreEqual('a'#$2192'b', TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Text, False, '', mUnfit));
    Assert.IsFalse(mUnfit);
    TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Hex, False, '', mUnfit);
    Assert.IsTrue(mUnfit, 'String ist keine Zahl');
    Assert.AreEqual('eins' + sLineBreak + 'zwei', TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Lines,
      True, '''eins''#13#10''zwei''#13#10', mUnfit), 'Zeilen aus .Text');
    Assert.IsFalse(mUnfit);
    Assert.IsTrue(TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Lines, False, 'E2003', mUnfit)
      .StartsWith('Keine Zeilen: „S.Text“ ließ sich nicht auswerten (E2003).'));
    Assert.IsTrue(mUnfit);
    mList.SetResult(mNode, True, '''{"a":1}''');
    Assert.AreEqual('{' + sLineBreak + '  "a": 1' + sLineBreak + '}',
      TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Json, False, '', mUnfit));
    mList.SetResult(mNode, True, '255');
    Assert.AreEqual('$000000FF (255)', TAtlasDebugEvaluateFrame.DetailText(mNode, TAtlasEvalView.Hex, False, '',
      mUnfit));
  finally
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateFrameTests.TreeWithPlaceholderAndParts;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mExpanded: string;
begin
  mExpanded := '';
  mList := TAtlasEvalList.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Hooks.Expand :=
      procedure(ANode: TAtlasEvalNode)
      begin
        mExpanded := ANode.Key;
      end;
    mNode := mList.Add('Self');
    mList.SetResult(mNode, True, '(FName: ''Meier''; FCount: 3)');
    mList.SetResult(mList.Add('Zahl'), True, '7');
    mFrame.SetList(mList);
    Assert.AreEqual(3, Integer(mFrame.Parts.Tree.Items.Count), 'Self, Platzhalter, Zahl');
    Assert.AreEqual('Self = (FName: ''Meier''; FCount: 3)', mFrame.Parts.Tree.Items[0].Text);
    mFrame.Parts.Tree.Items[0].Expand(False);
    Assert.AreEqual('Self', mExpanded, 'Felder holt die IDE-Schicht');
    Assert.IsTrue(mNode.Expanded);
    mList.SetParts(mNode);
    mFrame.Refresh;
    Assert.AreEqual(4, Integer(mFrame.Parts.Tree.Items.Count));
    Assert.AreEqual('FName = ''Meier''', mFrame.Parts.Tree.Items[1].Text);
    Assert.IsTrue(mFrame.Parts.Tree.Items[0].Expanded);
    mFrame.Parts.Tree.Items[1].Selected := True;
    Assert.AreEqual('Meier', mFrame.Parts.Detail.Text);
    Assert.IsFalse(mFrame.Parts.ModifyButton.Enabled, 'Teil ohne Ausdruck');
    mFrame.SetList(nil);
  finally
    mHost.Free;
    mList.Free;
  end;
  mExpanded := '';
end;

procedure TAtlasDebugEvaluateFrameTests.InputKeys;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mAdded, mPinned: string;
  mKey: Word;
begin
  mAdded := '';
  mPinned := '';
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Hooks.Add :=
      procedure(AExpression: string)
      begin
        mAdded := AExpression;
      end;
    mFrame.Hooks.PinExpression :=
      procedure(AExpression: string)
      begin
        mPinned := AExpression;
      end;
    mFrame.Parts.Input.Text := ' Kunde.Name ';
    mKey := VK_RETURN;
    mFrame.Parts.Input.OnKeyDown(mFrame.Parts.Input, mKey, []);
    Assert.AreEqual('Kunde.Name', mAdded);
    Assert.AreEqual('', mFrame.Parts.Input.Text, 'Feld leer für den nächsten');
    mFrame.Parts.Input.Text := 'Liste.Count';
    mKey := VK_RETURN;
    mFrame.Parts.Input.OnKeyDown(mFrame.Parts.Input, mKey, [ssCtrl]);
    Assert.AreEqual('Liste.Count', mPinned);
    mAdded := '';
    mKey := VK_RETURN;
    mFrame.Parts.Input.OnKeyDown(mFrame.Parts.Input, mKey, []);
    Assert.AreEqual('', mAdded, 'leer fügt nichts an');
  finally
    mHost.Free;
  end;
  mAdded := '';
  mPinned := '';
end;

procedure TAtlasDebugEvaluateFrameTests.DeleteRemovesWholeRow;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
  mDeleted: string;
  mKey: Word;
begin
  mDeleted := '';
  mList := TAtlasEvalList.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.Hooks.Delete :=
      procedure(ANode: TAtlasEvalNode)
      begin
        mDeleted := ANode.Key;
      end;
    mNode := mList.Add('P');
    mList.SetResult(mNode, True, '(X: 1; Y: 2)');
    mNode.Expanded := True;
    mList.SetParts(mNode);
    mFrame.SetList(mList);
    mFrame.Parts.Tree.Items[2].Selected := True;
    mKey := VK_DELETE;
    mFrame.Parts.Tree.OnKeyDown(mFrame.Parts.Tree, mKey, []);
    Assert.AreEqual('P', mDeleted);
    mFrame.SetList(nil);
  finally
    mHost.Free;
    mList.Free;
  end;
  mDeleted := '';
end;

procedure TAtlasDebugEvaluateFrameTests.PinCaption;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mList: TAtlasEvalList;
begin
  mList := TAtlasEvalList.Create;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mList.Add('A').Pinned := True;
    mList.Add('B');
    mFrame.SetList(mList);
    mFrame.Parts.Tree.Items[0].Selected := True;
    Assert.AreEqual('Lösen', mFrame.Parts.PinButton.Caption);
    mFrame.Parts.Tree.Items[1].Selected := True;
    Assert.AreEqual('Festheften', mFrame.Parts.PinButton.Caption);
    mFrame.SetList(nil);
  finally
    mHost.Free;
    mList.Free;
  end;
end;

procedure TAtlasDebugEvaluateFrameTests.KeysFollowWidth;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mWide, mTree: Integer;
begin
  mHost := TForm.CreateNew(nil);
  try
    mHost.ClientWidth := 900;
    mHost.ClientHeight := 600;
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Align := alClient;
    mFrame.HandleNeeded;
    mWide := mFrame.Parts.Keys.Height;
    Assert.IsTrue(mWide > 0, 'Tastenhilfe sichtbar');
    mHost.ClientWidth := 200;
    Assert.IsTrue(mFrame.Parts.Keys.Height > mWide, 'schmal: mehr Zeilen');
    mHost.ClientWidth := 900;
    Assert.AreEqual(mWide, mFrame.Parts.Keys.Height, 'wieder breit: wieder eine Zeile, kein leerer Streifen');
    // Höher: Der Baum bekommt den ganzen Zuwachs.
    mTree := mFrame.Parts.Tree.Height;
    mHost.ClientHeight := 800;
    Assert.AreEqual(mTree + 200, mFrame.Parts.Tree.Height, 'Baum wächst mit');
    Assert.AreEqual(mHost.ClientHeight, mFrame.Parts.Keys.Top + mFrame.Parts.Keys.Height +
      mFrame.Parts.Keys.Margins.Bottom, 'Tastenhilfe schließt unten ab');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugEvaluateFrameTests.ButtonOrder;
var
  mHost: TForm;
  mFrame: TAtlasDebugEvaluateFrame;
  mKind: TAtlasEvalView;
begin
  mHost := TForm.CreateNew(nil);
  try
    mHost.ClientWidth := 900;
    mFrame := TAtlasDebugEvaluateFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Align := alClient;
    mFrame.HandleNeeded;
    // Ein unsichtbares Fenster legt die Leiste nicht an, dann richtet sie sich nicht neu aus.
    mFrame.Parts.Bar.HandleNeeded;
    mFrame.Parts.Bar.Realign;
    // Links Text, Zeilen, JSON, Hex; rechts Ändern, Festheften, IDE-Dialog (IDE-Dialog ganz rechts).
    for mKind := Low(TAtlasEvalView) to Pred(High(TAtlasEvalView)) do
    begin
      Assert.IsTrue(mFrame.Parts.ViewButtons[mKind].Left < mFrame.Parts.ViewButtons[Succ(mKind)].Left,
        'Ansichten in Reihenfolge');
    end;
    Assert.IsTrue(mFrame.Parts.ViewButtons[TAtlasEvalView.Text].Left < mFrame.Parts.ModifyButton.Left, 'Ansichten links von Ändern');
    Assert.IsTrue(mFrame.Parts.ModifyButton.Left < mFrame.Parts.PinButton.Left, 'Ändern vor Festheften');
    Assert.IsTrue(mFrame.Parts.PinButton.Left < mFrame.Parts.IdeDialogButton.Left, 'Festheften vor IDE-Dialog');
    Assert.IsTrue(mFrame.Parts.IdeDialogButton.Left + mFrame.Parts.IdeDialogButton.Width <=
      mFrame.Parts.Bar.ClientWidth, 'innerhalb der Leiste');
  finally
    mHost.Free;
  end;
end;

end.
