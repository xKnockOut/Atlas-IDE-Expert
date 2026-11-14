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
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    [Test]
    procedure ShowsConditionUnlessSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.UI.Strings,
  Atlas.UI.Outline.Strings,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model;

const
  cFormCode =
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
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cFormCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cFormCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function Names(AFrame: TAtlasOutlineFrame): string;
var
  mRow: TAtlasOutlineRow;
begin
  Result := '';
  for mRow in AFrame.Rows do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + AFrame.Nodes[mRow.Node].Name;
  end;
end;

function RowOf(AFrame: TAtlasOutlineFrame; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFrame.Rows) do
  begin
    if AFrame.Nodes[AFrame.Rows[mIndex].Node].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function MenuItem(AMenu: TPopupMenu; const ACaption: string): TMenuItem;
var
  mItem: TMenuItem;
begin
  for mItem in AMenu.Items do
  begin
    if mItem.Caption = ACaption then
    begin
      Exit(mItem);
    end;
  end;
  Result := nil;
end;

procedure TAtlasOutlineFrameTests.WarmUpFirstUse;
begin
  SetUp;
  try
    ShowsRowsWithMarks;
  finally
    TearDown;
  end;
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
  Assert.AreEqual('interface,TForm1,Button1,Button1Click,FCount,Missing,Make', Names(FFrame));
  Assert.AreEqual(Integer(Length(FFrame.Rows)), FFrame.List.Count);
  Assert.AreEqual('◆ Button1', FFrame.RowText(RowOf(FFrame, 'Button1')));
  Assert.AreEqual('− Missing · ' + TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineUnimplemented),
    FFrame.RowText(RowOf(FFrame, 'Missing')));
  Assert.AreEqual('+ Make · class', FFrame.RowText(RowOf(FFrame, 'Make')));
  Assert.IsTrue(FFrame.List.Visible);
  Assert.IsFalse(FFrame.MessageLabel.Visible);
end;

procedure TAtlasOutlineFrameTests.PublishedMenuShowsFormFieldsAndHandlers;
var
  mItem: TMenuItem;
begin
  // Aus „alle“ heraus wählt der Klick genau diese Sichtbarkeit.
  mItem := MenuItem(FFrame.VisibilityMenu, 'published');
  Assert.IsNotNull(mItem);
  mItem.Click;
  Assert.AreEqual('interface,TForm1,Button1,Button1Click', Names(FFrame));
  Assert.IsTrue(mItem.Checked);
  Assert.IsFalse(MenuItem(FFrame.VisibilityMenu, 'private').Checked);
  // Art „Felder“ dazu: nur Button1.
  MenuItem(FFrame.KindMenu, TAtlasStrings.Text(TAtlasTextId.OutlineKindFields)).Click;
  Assert.AreEqual('interface,TForm1,Button1', Names(FFrame));
  // „Alle zeigen“ hebt den Filter auf.
  MenuItem(FFrame.VisibilityMenu, TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineShowAll)).Click;
  MenuItem(FFrame.KindMenu, TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineShowAll)).Click;
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
  Assert.AreEqual('interface,TForm1', Names(FFrame));
  // Neue Gliederung (nach dem Tippen): zugeklappt bleibt zugeklappt.
  FFrame.SetNodes(Nodes);
  Assert.AreEqual('interface,TForm1', Names(FFrame));
  // Mit Suchtext ist alles offen.
  FFrame.Search.Text := 'Make';
  Assert.AreEqual('interface,TForm1,Make', Names(FFrame));
  FFrame.Search.Text := '';
  FFrame.ToggleRow(RowOf(FFrame, 'TForm1'));
  Assert.AreEqual(7, Integer(Length(FFrame.Rows)));
end;

procedure TAtlasOutlineFrameTests.HighlightsEntryAtCursorWithoutOpening;
var
  mOpened: Integer;
begin
  mOpened := 0;
  FFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      Inc(mOpened);
    end;
  FFrame.ToggleRow(RowOf(FFrame, 'TForm1'));
  // Cursor im Rumpf von Button1Click (Zeile 14): Deklaration gewählt, Eltern aufgeklappt.
  Assert.IsTrue(FFrame.HighlightAt(14, 0));
  Assert.AreEqual('Button1Click', FFrame.Nodes[FFrame.SelectedNode].Name);
  Assert.AreEqual(0, mOpened, 'Hervorheben springt nicht');
  // Ausgefiltert: der nächste gezeigte Elternknoten.
  FFrame.SetCategories([TAtlasOutlineCategory.Field]);
  Assert.IsTrue(FFrame.HighlightAt(8, 14));
  Assert.AreEqual('TForm1', FFrame.Nodes[FFrame.SelectedNode].Name);
  FFrame.SetCategories([]);
end;

procedure TAtlasOutlineFrameTests.OpensDeclarationAndImplementation;
var
  mNode: Integer;
  mImplementation_: Boolean;
begin
  mNode := -1;
  mImplementation_ := False;
  FFrame.OnOpen :=
    procedure(ANode: Integer; AImplementation: Boolean)
    begin
      mNode := ANode;
      mImplementation_ := AImplementation;
    end;
  FFrame.SelectRow(RowOf(FFrame, 'Make'));
  FFrame.OpenSelected(False);
  Assert.AreEqual('Make', FFrame.Nodes[mNode].Name);
  Assert.IsFalse(mImplementation_);
  FFrame.OpenSelected(True);
  Assert.IsTrue(mImplementation_);
  Assert.IsTrue(FFrame.Nodes[mNode].Body >= 0, 'Make hat einen Rumpf');
  // Kontextmenü: „Zur Implementierung“ nur mit Rumpf.
  FFrame.SelectRow(RowOf(FFrame, 'Missing'));
  FFrame.ListMenu.OnPopup(FFrame.ListMenu);
  Assert.IsFalse(MenuItem(FFrame.ListMenu,
    TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineGoToImplementation)).Enabled);
end;

procedure TAtlasOutlineFrameTests.ShowsConditionUnlessSwitchedOff;
var
  mList: TAtlasOutlineNodes;
  mIndex: Integer;
begin
  // #845: Bedingung des aktiven Zweigs hinter dem Eintrag, abschaltbar.
  mList := FFrame.Nodes;
  for mIndex := 0 to High(mList) do
  begin
    if mList[mIndex].Name = 'Make' then
    begin
      mList[mIndex].Condition := 'CPUX64';
    end;
  end;
  FFrame.SetNodes(mList);
  Assert.AreEqual('+ Make · class · CPUX64', FFrame.RowText(RowOf(FFrame, 'Make')));
  FFrame.ShowConditions := False;
  Assert.AreEqual('+ Make · class', FFrame.RowText(RowOf(FFrame, 'Make')));
end;

procedure TAtlasOutlineFrameTests.SortButtonAndMessage;
var
  mSorted: Boolean;
  mFollow: Boolean;
begin
  mSorted := False;
  mFollow := True;
  FFrame.OnSortChanged :=
    procedure(AValue: Boolean)
    begin
      mSorted := AValue;
    end;
  FFrame.OnFollowChanged :=
    procedure(AValue: Boolean)
    begin
      mFollow := AValue;
    end;
  FFrame.Alphabetical := True;
  Assert.AreEqual('interface,TForm1,Button1,Button1Click,FCount,Make,Missing', Names(FFrame));
  MenuItem(FFrame.ListMenu, TAtlasOutlineStrings.Text(TAtlasOutlineTextId.OutlineFollowCursor)).Click;
  Assert.IsFalse(mFollow);
  Assert.IsFalse(FFrame.FollowCursor);
  Assert.IsFalse(mSorted);
  FFrame.SetMessage('Keine Gliederung');
  Assert.AreEqual(0, Integer(Length(FFrame.Rows)));
  Assert.IsTrue(FFrame.MessageLabel.Visible);
  Assert.AreEqual('Keine Gliederung', FFrame.MessageLabel.Caption);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOutlineFrameTests);

end.
