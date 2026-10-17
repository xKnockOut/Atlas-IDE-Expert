unit Atlas.UI.Outline.Frame.Tests;

// Gliederungsfenster (#537), Fensterinhalt: Zeilen aus der Gliederung,
// Filter nach Sichtbarkeit und Art über die Menüs, Auf- und Zuklappen,
// Eintrag am Cursor, Springen zu Deklaration und Implementierung, Marken
// und Hinweis ohne Gliederung.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Outline.Frame;

type
  [TestFixture]
  TAtlasOutlineFrameTests = class
  private
    FForm: TForm;
    FFrame: TAtlasOutlineFrame;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsRowsWithMarks;
    [Test]
    procedure PublishedMenuShowsFormFieldsAndHandlers;
    [Test]
    procedure CollapsesAndKeepsStateOverRefresh;
    [Test]
    procedure HighlightsEntryAtCursorWithoutOpening;
    [Test]
    procedure OpensDeclarationAndImplementation;
    [Test]
    procedure SortButtonAndMessage;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.UI.Strings,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model;

const
  FormCode =
    'unit F;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm1 = class(TForm)'#13#10 +
    '    Button1: TButton;'#13#10 +
    '    procedure Button1Click(Sender: TObject);'#13#10 +
    '  private'#13#10 +
    '    FCount: Integer;'#13#10 +
    '    procedure Missing;'#13#10 +
    '  public'#13#10 +
    '    class function Make: TForm1;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'class function TForm1.Make: TForm1; begin Result := nil; end;'#13#10 +
    'end.';

function Nodes: TAtlasOutlineNodes;
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(FormCode);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, FormCode);
  finally
    Tree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(Symbols);
  finally
    Symbols.Free;
  end;
end;

function Names(AFrame: TAtlasOutlineFrame): string;
var
  Row: TAtlasOutlineRow;
begin
  Result := '';
  for Row in AFrame.Rows do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + AFrame.Nodes[Row.Node].Name;
  end;
end;

function RowOf(AFrame: TAtlasOutlineFrame; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AFrame.Rows) do
    if AFrame.Nodes[AFrame.Rows[Index].Node].Name = AName then
      Exit(Index);
  Result := -1;
end;

function MenuItem(AMenu: TPopupMenu; const ACaption: string): TMenuItem;
var
  Item: TMenuItem;
begin
  for Item in AMenu.Items do
    if Item.Caption = ACaption then
      Exit(Item);
  Result := nil;
end;

procedure TAtlasOutlineFrameTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 400;
  FForm.Height := 600;
  FFrame := TAtlasOutlineFrame.Create(FForm);
  FFrame.Parent := FForm;
  FFrame.Align := alClient;
  FFrame.SetNodes(Nodes);
end;

procedure TAtlasOutlineFrameTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FFrame := nil;
end;

procedure TAtlasOutlineFrameTests.ShowsRowsWithMarks;
begin
  Assert.AreEqual('interface,TForm1,Button1,Button1Click,FCount,Missing,Make,implementation', Names(FFrame));
  Assert.AreEqual(Integer(Length(FFrame.Rows)), FFrame.List.Count);
  Assert.AreEqual('◆ Button1', FFrame.RowText(RowOf(FFrame, 'Button1')));
  Assert.AreEqual('− Missing · ' + TAtlasStrings.Text(TAtlasTextId.OutlineUnimplemented),
    FFrame.RowText(RowOf(FFrame, 'Missing')));
  Assert.AreEqual('+ Make · class', FFrame.RowText(RowOf(FFrame, 'Make')));
  Assert.IsTrue(FFrame.List.Visible);
  Assert.IsFalse(FFrame.MessageLabel.Visible);
end;

procedure TAtlasOutlineFrameTests.PublishedMenuShowsFormFieldsAndHandlers;
var
  Item: TMenuItem;
begin
  // Aus „alle“ heraus wählt der Klick genau diese Sichtbarkeit.
  Item := MenuItem(FFrame.VisibilityMenu, 'published');
  Assert.IsNotNull(Item);
  Item.Click;
  Assert.AreEqual('interface,TForm1,Button1,Button1Click', Names(FFrame));
  Assert.IsTrue(Item.Checked);
  Assert.IsFalse(MenuItem(FFrame.VisibilityMenu, 'private').Checked);
  // Art „Felder“ dazu: nur Button1.
  MenuItem(FFrame.KindMenu, TAtlasStrings.Text(TAtlasTextId.OutlineKindFields)).Click;
  Assert.AreEqual('interface,TForm1,Button1', Names(FFrame));
  // „Alle zeigen“ hebt den Filter auf.
  MenuItem(FFrame.VisibilityMenu, TAtlasStrings.Text(TAtlasTextId.OutlineShowAll)).Click;
  MenuItem(FFrame.KindMenu, TAtlasStrings.Text(TAtlasTextId.OutlineShowAll)).Click;
  Assert.IsTrue(FFrame.Filter.AllVisibilities);
  Assert.IsTrue(FFrame.Filter.AllCategories);
  // Suchtext.
  FFrame.Search.Text := 'Miss';
  Assert.AreEqual('interface,TForm1,Missing', Names(FFrame));
  FFrame.Search.Text := '';
end;

procedure TAtlasOutlineFrameTests.CollapsesAndKeepsStateOverRefresh;
begin
  FFrame.ToggleRow(RowOf(FFrame, 'TForm1'));
  Assert.AreEqual('interface,TForm1,implementation', Names(FFrame));
  // Neue Gliederung (nach dem Tippen): zugeklappt bleibt zugeklappt.
  FFrame.SetNodes(Nodes);
  Assert.AreEqual('interface,TForm1,implementation', Names(FFrame));
  // Mit Suchtext ist alles offen.
  FFrame.Search.Text := 'Make';
  Assert.AreEqual('interface,TForm1,Make', Names(FFrame));
  FFrame.Search.Text := '';
  FFrame.ToggleRow(RowOf(FFrame, 'TForm1'));
  Assert.AreEqual(8, Integer(Length(FFrame.Rows)));
end;

procedure TAtlasOutlineFrameTests.HighlightsEntryAtCursorWithoutOpening;
var
  Opened: Integer;
begin
  Opened := 0;
  FFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      Inc(Opened);
    end;
  FFrame.ToggleRow(RowOf(FFrame, 'TForm1'));
  // Cursor im Rumpf von Button1Click (Zeile 14): Deklaration gewählt, Eltern aufgeklappt.
  Assert.IsTrue(FFrame.HighlightAt(14, 0));
  Assert.AreEqual('Button1Click', FFrame.Nodes[FFrame.SelectedNode].Name);
  Assert.AreEqual(0, Opened, 'Hervorheben springt nicht');
  // Ausgefiltert: der nächste gezeigte Elternknoten.
  FFrame.SetCategories([TAtlasOutlineCategory.Field]);
  Assert.IsTrue(FFrame.HighlightAt(8, 14));
  Assert.AreEqual('TForm1', FFrame.Nodes[FFrame.SelectedNode].Name);
  FFrame.SetCategories([]);
end;

procedure TAtlasOutlineFrameTests.OpensDeclarationAndImplementation;
var
  Node: Integer;
  Implementation_: Boolean;
begin
  Node := -1;
  Implementation_ := False;
  FFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      Node := ANode;
      Implementation_ := AImplementation;
    end;
  FFrame.SelectRow(RowOf(FFrame, 'Make'));
  FFrame.OpenSelected(False);
  Assert.AreEqual('Make', FFrame.Nodes[Node].Name);
  Assert.IsFalse(Implementation_);
  FFrame.OpenSelected(True);
  Assert.IsTrue(Implementation_);
  Assert.IsTrue(FFrame.Nodes[Node].Body >= 0, 'Make hat einen Rumpf');
  // Kontextmenü: „Zur Implementierung“ nur mit Rumpf.
  FFrame.SelectRow(RowOf(FFrame, 'Missing'));
  FFrame.ListMenu.OnPopup(FFrame.ListMenu);
  Assert.IsFalse(MenuItem(FFrame.ListMenu, TAtlasStrings.Text(TAtlasTextId.OutlineGoToImplementation)).Enabled);
end;

procedure TAtlasOutlineFrameTests.SortButtonAndMessage;
var
  Sorted: Boolean;
  Follow: Boolean;
begin
  Sorted := False;
  Follow := True;
  FFrame.OnSortChanged :=
    procedure(AValue: Boolean)
    begin
      Sorted := AValue;
    end;
  FFrame.OnFollowChanged :=
    procedure(AValue: Boolean)
    begin
      Follow := AValue;
    end;
  FFrame.Alphabetical := True;
  Assert.AreEqual('interface,TForm1,Button1,Button1Click,FCount,Make,Missing,implementation', Names(FFrame));
  MenuItem(FFrame.ListMenu, TAtlasStrings.Text(TAtlasTextId.OutlineFollowCursor)).Click;
  Assert.IsFalse(Follow);
  Assert.IsFalse(FFrame.FollowCursor);
  Assert.IsFalse(Sorted);
  FFrame.SetMessage('Keine Gliederung');
  Assert.AreEqual(0, Integer(Length(FFrame.Rows)));
  Assert.IsTrue(FFrame.MessageLabel.Visible);
  Assert.AreEqual('Keine Gliederung', FFrame.MessageLabel.Caption);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineFrameTests);

end.
