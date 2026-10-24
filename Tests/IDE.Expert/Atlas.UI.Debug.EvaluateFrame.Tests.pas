unit Atlas.UI.Debug.EvaluateFrame.Tests;

// Fenster „Auswerten“ (#784), Oberfläche: Text im Baum je Zustand (gekürzt,
// einzeilig, grau der alte Wert bis zum neuen), Ansichten unten (Text mit
// sichtbaren Steuerzeichen, Zeilen aus „.Text“, JSON, Hex, Hinweis bei
// unpassender Ansicht), Baum mit Platzhalter zum Aufklappen und Kindern aus
// Teilen, Enter/Strg+Enter im Eingabefeld, Entf auf einem Feld entfernt die
// ganze Zeile, Knopf „Festheften“ bzw. „Lösen“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasDebugEvaluateFrameTests = class
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
    procedure DetailViews;
    [Test]
    procedure TreeWithPlaceholderAndParts;
    [Test]
    procedure InputKeys;
    [Test]
    procedure DeleteRemovesWholeRow;
    [Test]
    procedure PinCaption;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateFrame;

{ TAtlasDebugEvaluateFrameTests }

procedure TAtlasDebugEvaluateFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugEvaluateFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugEvaluateFrameTests.NodeTexts;
var
  List: TAtlasEvalList;
  Node: TAtlasEvalNode;
begin
  List := TAtlasEvalList.Create;
  try
    Node := List.Add(' Summe ');
    Assert.AreEqual('Summe = wird ausgewertet …', TAtlasDebugEvaluateFrame.NodeText(Node));
    List.SetResult(Node, True, '42');
    Assert.AreEqual('Summe = 42', TAtlasDebugEvaluateFrame.NodeText(Node));
    List.BeginStop;
    Assert.AreEqual('Summe = 42', TAtlasDebugEvaluateFrame.NodeText(Node), 'alter Wert bis zum neuen');
    List.SetResult(Node, False, 'Undeclared identifier');
    Assert.AreEqual('Summe = Undeclared identifier', TAtlasDebugEvaluateFrame.NodeText(Node));
    List.Unavailable;
    Assert.AreEqual('Summe = ‹Programm nicht angehalten›', TAtlasDebugEvaluateFrame.NodeText(Node));
    List.BeginStop;
    List.SetResult(Node, True, '''a''#13#10''b''' + StringOfChar('x', 300));
    Assert.IsFalse(TAtlasDebugEvaluateFrame.NodeText(Node).Contains(#13), 'einzeilig');
    Assert.AreEqual(Integer(Length('Summe = ') + TAtlasDebugEvaluateFrame.MaxTreeValue + 1),
      Integer(Length(TAtlasDebugEvaluateFrame.NodeText(Node))), 'gekürzt mit …');
  finally
    List.Free;
  end;
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
    Frame.OnExpand :=
      procedure(ANode: TAtlasEvalNode)
      begin
        Expanded := ANode.Key;
      end;
    Node := List.Add('Self');
    List.SetResult(Node, True, '(FName: ''Meier''; FCount: 3)');
    List.SetResult(List.Add('Zahl'), True, '7');
    Frame.SetList(List);
    Assert.AreEqual(3, Integer(Frame.Tree.Items.Count), 'Self, Platzhalter, Zahl');
    Assert.AreEqual('Self = (FName: ''Meier''; FCount: 3)', Frame.Tree.Items[0].Text);
    Frame.Tree.Items[0].Expand(False);
    Assert.AreEqual('Self', Expanded, 'Felder holt die IDE-Schicht');
    Assert.IsTrue(Node.Expanded);
    List.SetParts(Node);
    Frame.Refresh;
    Assert.AreEqual(4, Integer(Frame.Tree.Items.Count));
    Assert.AreEqual('FName = ''Meier''', Frame.Tree.Items[1].Text);
    Assert.IsTrue(Frame.Tree.Items[0].Expanded);
    Frame.Tree.Items[1].Selected := True;
    Assert.AreEqual('Meier', Frame.Detail.Text);
    Assert.IsFalse(Frame.ModifyButton.Enabled, 'Teil ohne Ausdruck');
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
    Frame.OnAdd :=
      procedure(AExpression: string)
      begin
        Added := AExpression;
      end;
    Frame.OnPinExpression :=
      procedure(AExpression: string)
      begin
        Pinned := AExpression;
      end;
    Frame.Input.Text := ' Kunde.Name ';
    Key := VK_RETURN;
    Frame.Input.OnKeyDown(Frame.Input, Key, []);
    Assert.AreEqual('Kunde.Name', Added);
    Assert.AreEqual('', Frame.Input.Text, 'Feld leer für den nächsten');
    Frame.Input.Text := 'Liste.Count';
    Key := VK_RETURN;
    Frame.Input.OnKeyDown(Frame.Input, Key, [ssCtrl]);
    Assert.AreEqual('Liste.Count', Pinned);
    Added := '';
    Key := VK_RETURN;
    Frame.Input.OnKeyDown(Frame.Input, Key, []);
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
    Frame.OnDelete :=
      procedure(ANode: TAtlasEvalNode)
      begin
        Deleted := ANode.Key;
      end;
    Node := List.Add('P');
    List.SetResult(Node, True, '(X: 1; Y: 2)');
    Node.Expanded := True;
    List.SetParts(Node);
    Frame.SetList(List);
    Frame.Tree.Items[2].Selected := True;
    Key := VK_DELETE;
    Frame.Tree.OnKeyDown(Frame.Tree, Key, []);
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
    Frame.Tree.Items[0].Selected := True;
    Assert.AreEqual('Lösen', Frame.PinButton.Caption);
    Frame.Tree.Items[1].Selected := True;
    Assert.AreEqual('Festheften', Frame.PinButton.Caption);
    Frame.SetList(nil);
  finally
    Host.Free;
    List.Free;
  end;
end;

end.
