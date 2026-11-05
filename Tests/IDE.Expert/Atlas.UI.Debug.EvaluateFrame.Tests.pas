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
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
  Unfit: Boolean;
begin
  List := TAtlasEvalList.Create;
  try
    Assert.AreEqual('Eine Zeile wählen, um ihren Wert zu sehen.',
      TAtlasDebugEvaluateFrame.DetailText(nil, TAtlasEvalView.Text, False, '', Unfit));
    Node := List.Add('S');
    List.SetResult(Node, True, '''a''#9''b''');
    Assert.AreEqual('a'#$2192'b', TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Text, False, '', Unfit));
    Assert.IsFalse(Unfit);
    TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Hex, False, '', Unfit);
    Assert.IsTrue(Unfit, 'String ist keine Zahl');
    Assert.AreEqual('eins' + sLineBreak + 'zwei', TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Lines,
      True, '''eins''#13#10''zwei''#13#10', Unfit), 'Zeilen aus .Text');
    Assert.IsFalse(Unfit);
    Assert.IsTrue(TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Lines, False, 'E2003', Unfit)
      .StartsWith('Keine Zeilen: „S.Text“ ließ sich nicht auswerten (E2003).'));
    Assert.IsTrue(Unfit);
    List.SetResult(Node, True, '''{"a":1}''');
    Assert.AreEqual('{' + sLineBreak + '  "a": 1' + sLineBreak + '}',
      TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Json, False, '', Unfit));
    List.SetResult(Node, True, '255');
    Assert.AreEqual('$000000FF (255)', TAtlasDebugEvaluateFrame.DetailText(Node, TAtlasEvalView.Hex, False, '',
      Unfit));
  finally
    List.Free;
  end;
end;

procedure TAtlasDebugEvaluateFrameTests.TreeWithPlaceholderAndParts;
var
  Host: TForm;
  Frame: TAtlasDebugEvaluateFrame;
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
  Expanded: string;
begin
  Expanded := '';
  List := TAtlasEvalList.Create;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugEvaluateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.Hooks.Expand :=
      procedure(ANode: TAtlasEvalNode)
      begin
        Expanded := ANode.Key;
      end;
    Node := List.Add('Self');
    List.SetResult(Node, True, '(FName: ''Meier''; FCount: 3)');
    List.SetResult(List.Add('Zahl'), True, '7');
    Frame.SetList(List);
    Assert.AreEqual(3, Integer(Frame.Parts.Tree.Items.Count), 'Self, Platzhalter, Zahl');
    Assert.AreEqual('Self = (FName: ''Meier''; FCount: 3)', Frame.Parts.Tree.Items[0].Text);
    Frame.Parts.Tree.Items[0].Expand(False);
    Assert.AreEqual('Self', Expanded, 'Felder holt die IDE-Schicht');
    Assert.IsTrue(Node.Expanded);
    List.SetParts(Node);
    Frame.Refresh;
    Assert.AreEqual(4, Integer(Frame.Parts.Tree.Items.Count));
    Assert.AreEqual('FName = ''Meier''', Frame.Parts.Tree.Items[1].Text);
    Assert.IsTrue(Frame.Parts.Tree.Items[0].Expanded);
    Frame.Parts.Tree.Items[1].Selected := True;
    Assert.AreEqual('Meier', Frame.Parts.Detail.Text);
    Assert.IsFalse(Frame.Parts.ModifyButton.Enabled, 'Teil ohne Ausdruck');
    Frame.SetList(nil);
  finally
    Host.Free;
    List.Free;
  end;
  Expanded := '';
end;

procedure TAtlasDebugEvaluateFrameTests.InputKeys;
var
  Host: TForm;
  Frame: TAtlasDebugEvaluateFrame;
  Added, Pinned: string;
  Key: Word;
begin
  Added := '';
  Pinned := '';
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugEvaluateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.Hooks.Add :=
      procedure(AExpression: string)
      begin
        Added := AExpression;
      end;
    Frame.Hooks.PinExpression :=
      procedure(AExpression: string)
      begin
        Pinned := AExpression;
      end;
    Frame.Parts.Input.Text := ' Kunde.Name ';
    Key := VK_RETURN;
    Frame.Parts.Input.OnKeyDown(Frame.Parts.Input, Key, []);
    Assert.AreEqual('Kunde.Name', Added);
    Assert.AreEqual('', Frame.Parts.Input.Text, 'Feld leer für den nächsten');
    Frame.Parts.Input.Text := 'Liste.Count';
    Key := VK_RETURN;
    Frame.Parts.Input.OnKeyDown(Frame.Parts.Input, Key, [ssCtrl]);
    Assert.AreEqual('Liste.Count', Pinned);
    Added := '';
    Key := VK_RETURN;
    Frame.Parts.Input.OnKeyDown(Frame.Parts.Input, Key, []);
    Assert.AreEqual('', Added, 'leer fügt nichts an');
  finally
    Host.Free;
  end;
  Added := '';
  Pinned := '';
end;

procedure TAtlasDebugEvaluateFrameTests.DeleteRemovesWholeRow;
var
  Host: TForm;
  Frame: TAtlasDebugEvaluateFrame;
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
  Deleted: string;
  Key: Word;
begin
  Deleted := '';
  List := TAtlasEvalList.Create;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugEvaluateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    Frame.Hooks.Delete :=
      procedure(ANode: TAtlasEvalNode)
      begin
        Deleted := ANode.Key;
      end;
    Node := List.Add('P');
    List.SetResult(Node, True, '(X: 1; Y: 2)');
    Node.Expanded := True;
    List.SetParts(Node);
    Frame.SetList(List);
    Frame.Parts.Tree.Items[2].Selected := True;
    Key := VK_DELETE;
    Frame.Parts.Tree.OnKeyDown(Frame.Parts.Tree, Key, []);
    Assert.AreEqual('P', Deleted);
    Frame.SetList(nil);
  finally
    Host.Free;
    List.Free;
  end;
  Deleted := '';
end;

procedure TAtlasDebugEvaluateFrameTests.PinCaption;
var
  Host: TForm;
  Frame: TAtlasDebugEvaluateFrame;
  List: TAtlasEvalList;
begin
  List := TAtlasEvalList.Create;
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasDebugEvaluateFrame.Create(Host);
    Frame.Parent := Host;
    Frame.HandleNeeded;
    List.Add('A').Pinned := True;
    List.Add('B');
    Frame.SetList(List);
    Frame.Parts.Tree.Items[0].Selected := True;
    Assert.AreEqual('Lösen', Frame.Parts.PinButton.Caption);
    Frame.Parts.Tree.Items[1].Selected := True;
    Assert.AreEqual('Festheften', Frame.Parts.PinButton.Caption);
    Frame.SetList(nil);
  finally
    Host.Free;
    List.Free;
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
    // Links Text, Zeilen, JSON, Hex; rechts Ändern, Festheften, IDE-Dialog (IDE-Dialog ganz rechts).
    for mKind := Low(TAtlasEvalView) to Pred(High(TAtlasEvalView)) do
    begin
      Assert.IsTrue(mFrame.Parts.ViewButtons[mKind].Left < mFrame.Parts.ViewButtons[Succ(mKind)].Left,
        'Ansichten in Reihenfolge');
    end;
    Assert.IsTrue(mFrame.Parts.ViewButtons[TAtlasEvalView.Text].Left < mFrame.Parts.ModifyButton.Left);
    Assert.IsTrue(mFrame.Parts.ModifyButton.Left < mFrame.Parts.PinButton.Left);
    Assert.IsTrue(mFrame.Parts.PinButton.Left < mFrame.Parts.IdeDialogButton.Left);
    Assert.IsTrue(mFrame.Parts.IdeDialogButton.Left + mFrame.Parts.IdeDialogButton.Width <=
      mFrame.Parts.Bar.ClientWidth, 'innerhalb der Leiste');
  finally
    mHost.Free;
  end;
end;

end.
