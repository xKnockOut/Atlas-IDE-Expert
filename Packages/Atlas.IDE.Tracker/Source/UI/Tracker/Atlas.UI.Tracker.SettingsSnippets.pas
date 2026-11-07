unit Atlas.UI.Tracker.SettingsSnippets;

// Textbausteine des Kommentar-Editors (#1278) auf der Seite Issue-Tracker:
// Tabelle mit Name und Text, darunter die gewählte Zeile und die Knöpfe
// „Hinzufügen“, „Entfernen“ und „Vorgaben“. Die Zeilen und alle Grenzen hält
// TAtlasTrackerSnippetTable.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente der Textbausteine.</summary>
  TAtlasTrackerSnippetsView = record
    List: TListView;
    Name: TEdit;
    Text: TMemo;
    Add: TButton;
    Remove: TButton;
    Defaults: TButton;
  end;

  TAtlasTrackerSnippetsPart = class
  private
    FRows: TAtlasTrackerSettingsRows;
    FTables: TAtlasTrackerSettingsTables;
    FView: TAtlasTrackerSnippetsView;
    FAnchor: TWinControl;
    FFilling: Boolean;
    function Table: TAtlasTrackerSnippetTable;
    procedure BuildList;
    procedure BuildFields;
    procedure BuildButtons;
    procedure FillList;
    procedure FillFields;
    function ItemReady: Boolean;
    procedure SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure NameChange(Sender: TObject);
    procedure TextChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure DefaultsClick(Sender: TObject);
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; ATables: TAtlasTrackerSettingsTables);
    procedure Build;
    /// <summary>Tabelle (mit Fenster) und Felder neu.</summary>
    procedure Refresh;
    property View: TAtlasTrackerSnippetsView read FView;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.UI.Tracker.Strings;

const
  cSnippetsRow = 100;
  cNameColumn = 200;
  cTextColumn = 330;
  cTextRow = 64;
  cTextSubItem = 0;

type
  TRows = TAtlasTrackerSettingsRows;

{ TAtlasTrackerSnippetsPart }

constructor TAtlasTrackerSnippetsPart.Create(ARows: TAtlasTrackerSettingsRows; ATables: TAtlasTrackerSettingsTables);
begin
  inherited Create;
  FRows := ARows;
  FTables := ATables;
end;

function TAtlasTrackerSnippetsPart.Table: TAtlasTrackerSnippetTable;
begin
  Result := FTables.Snippets;
end;

procedure TAtlasTrackerSnippetsPart.Build;
begin
  BuildList;
  BuildFields;
  BuildButtons;
end;

procedure TAtlasTrackerSnippetsPart.BuildList;
begin
  FRows.AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetsTitle));
  FAnchor := FRows.AddKeyedPanel(cSnippetsRow, TAtlasTrackerSettingsTables.cSnippetsKey);
  // Die Zeilen brauchen ein Fenster: Refresh füllt sie (auch aus WindowReady).
  FView.List := FRows.AddList(FAnchor, SelectItem);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetName), cNameColumn);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetText), cTextColumn);
end;

procedure TAtlasTrackerSnippetsPart.BuildFields;
begin
  FView.Name := FRows.NewEdit(NameChange);
  FView.Name.MaxLength := TAtlasCommentSnippets.cMaxName;
  FRows.Attach(FRows.AddTallLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetName),
    FView.Name, TRows.cRowHeight), FAnchor);
  FView.Text := TMemo.Create(FRows.Owner);
  FView.Text.MaxLength := TAtlasCommentSnippets.cMaxText;
  FView.Text.ScrollBars := ssVertical;
  FView.Text.WantReturns := True;
  FView.Text.OnChange := TextChange;
  FRows.Attach(FRows.AddTallLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetText),
    FView.Text, cTextRow), FAnchor);
end;

procedure TAtlasTrackerSnippetsPart.BuildButtons;
var
  mPanel: TWinControl;
  mLeft: Integer;
begin
  mPanel := FRows.AddPanel(TRows.cButtonRow);
  mLeft := 0;
  FView.Add := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetAdd), AddClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  FView.Remove := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetRemove), RemoveClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  FView.Defaults := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetDefaults), DefaultsClick);
  FRows.Attach(mPanel, FAnchor);
  FRows.AddHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetsHint), FAnchor);
end;

procedure TAtlasTrackerSnippetsPart.Refresh;
begin
  if FView.List = nil then
  begin
    Exit;
  end;
  if FRows.ListReady(FView.List) then
  begin
    FillList;
  end;
  FillFields;
end;

procedure TAtlasTrackerSnippetsPart.FillList;
var
  mSnippet: TAtlasCommentSnippet;
  mItem: TListItem;
begin
  FFilling := True;
  FView.List.Items.BeginUpdate;
  try
    FView.List.Items.Clear;
    for mSnippet in Table.Items do
    begin
      mItem := FView.List.Items.Add;
      mItem.Caption := mSnippet.Name;
      mItem.SubItems.Add(TAtlasTrackerSnippetTable.Line(mSnippet.Text));
    end;
    if Table.Selected >= 0 then
    begin
      FView.List.Items[Table.Selected].Selected := True;
    end;
  finally
    FView.List.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TAtlasTrackerSnippetsPart.FillFields;
var
  mEditable: Boolean;
begin
  mEditable := Table.Editable;
  FFilling := True;
  try
    FView.Name.Text := '';
    FView.Text.Text := '';
    if mEditable then
    begin
      FView.Name.Text := Table.Items[Table.Selected].Name;
      FView.Text.Text := AdjustLineBreaks(Table.Items[Table.Selected].Text, tlbsCRLF);
    end;
  finally
    FFilling := False;
  end;
  // Über Allow: Sonst schaltet der Hauptschalter die Felder wieder frei.
  FRows.Allow(FView.Name, mEditable);
  FRows.Allow(FView.Text, mEditable);
  FRows.Allow(FView.Remove, mEditable);
  FRows.Allow(FView.Add, Table.CanAdd);
end;

function TAtlasTrackerSnippetsPart.ItemReady: Boolean;
begin
  Result := FRows.ListReady(FView.List) and (Table.Selected < FView.List.Items.Count);
end;

procedure TAtlasTrackerSnippetsPart.SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  Table.Select(Item.Index);
  FillFields;
end;

procedure TAtlasTrackerSnippetsPart.NameChange(Sender: TObject);
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  Table.SetName(FView.Name.Text);
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].Caption := FView.Name.Text;
  end;
end;

procedure TAtlasTrackerSnippetsPart.TextChange(Sender: TObject);
var
  mItem: TListItem;
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  Table.SetText(FView.Text.Text);
  if ItemReady then
  begin
    mItem := FView.List.Items[Table.Selected];
    if mItem.SubItems.Count > cTextSubItem then
    begin
      mItem.SubItems[cTextSubItem] := TAtlasTrackerSnippetTable.Line(Table.Items[Table.Selected].Text);
    end;
  end;
end;

procedure TAtlasTrackerSnippetsPart.AddClick(Sender: TObject);
begin
  if not Table.CanAdd then
  begin
    Exit;
  end;
  // Ohne Text wird der Baustein nicht gespeichert (TAtlasCommentSnippets.Parse lässt ihn fallen).
  Table.Add(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSnippetNew));
  Refresh;
  TRows.Focus(FView.Name);
end;

procedure TAtlasTrackerSnippetsPart.RemoveClick(Sender: TObject);
begin
  if Table.Editable then
  begin
    Table.Remove;
    Refresh;
  end;
end;

procedure TAtlasTrackerSnippetsPart.DefaultsClick(Sender: TObject);
begin
  Table.Defaults;
  Refresh;
end;

end.
