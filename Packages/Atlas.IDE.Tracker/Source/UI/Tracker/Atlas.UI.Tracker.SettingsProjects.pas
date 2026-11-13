unit Atlas.UI.Tracker.SettingsProjects;

// Tabelle Projekte der Seite Issue-Tracker (#1261, Mockup IT2): Zuordnung
// Delphi-Projekt → Tracker-Projekt. Zeilen aus der .atlas sind
// schreibgeschützt, von ihr überdeckte persönliche Zeilen grau. „Hinzufügen …“
// fragt nach Projektdatei oder Ordner (Haken OnBrowse, sonst die Dialoge von
// Windows). Die Zeilen und alle Prüfungen hält TAtlasTrackerProjectTable.
// Spalte und Feld „Arbeitskopien“ (#1926) liefert TAtlasTrackerPathsPart.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.SettingsPaths,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente der Tabelle Projekte.</summary>
  TAtlasTrackerProjectsView = record
    List: TListView;
    Match: TEdit;
    Connection: TAtlasChoiceBox;
    Project: TEdit;
    Note: TLabel;
    AddCurrent: TButton;
    Add: TButton;
    Remove: TButton;
    AddMenu: TPopupMenu;
  end;

  TAtlasTrackerProjectsPart = class
  private
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FTables: TAtlasTrackerSettingsTables;
    FView: TAtlasTrackerProjectsView;
    FAnchor: TWinControl;
    FFilling: Boolean;
    FOnChanged: TAtlasTrackerTableChanged;
    FPaths: TAtlasTrackerPathsPart;
    function Table: TAtlasTrackerProjectTable;
    procedure PathsChanged(APaths: TArray<string>);
    procedure BuildList;
    procedure BuildFields;
    procedure BuildButtons;
    function SourceText(const AMapping: TAtlasTrackerProjectMapping): string;
    function NoteText(const AMapping: TAtlasTrackerProjectMapping): string;
    procedure FillList;
    procedure FillFields;
    function ItemReady: Boolean;
    function Browse(AFolder: Boolean; out APath: string): Boolean;
    procedure SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure DrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure MatchChange(Sender: TObject);
    procedure ConnectionChange(Sender: TObject);
    procedure ProjectChange(Sender: TObject);
    procedure AddCurrentClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure AddFileClick(Sender: TObject);
    procedure AddFolderClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
      ATables: TAtlasTrackerSettingsTables; AOnChanged: TAtlasTrackerTableChanged);
    destructor Destroy; override;
    procedure Build;
    /// <summary>Kontext der IDE holen, Auswahl der Verbindungen, Tabelle und Felder neu; meldet OnChanged.
    /// </summary>
    procedure Refresh;
    /// <summary>Zeile für AMatch anlegen bzw. wählen und das Feld Tracker-Projekt zeigen.</summary>
    procedure AddMatch(const AMatch: string);
    property View: TAtlasTrackerProjectsView read FView;
    /// <summary>Feld „Arbeitskopien“ (#1926); nil vor Build.</summary>
    property Paths: TAtlasTrackerPathsPart read FPaths;
  end;

implementation

uses
  Vcl.Themes,
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Settings.Strings;

const
  cMatchColumn = 230;
  cConnectionColumn = 100;
  cProjectColumn = 100;
  cPathsColumn = 150;
  cSourceColumn = 150;
  cAddCurrentWidth = 180;
  cAddWidth = 110;
  cConnectionSubItem = 0;
  cProjectSubItem = 1;
  cPathsSubItem = 2;
  cSourceSubItem = 3;

type
  TRows = TAtlasTrackerSettingsRows;

{ TAtlasTrackerProjectsPart }

constructor TAtlasTrackerProjectsPart.Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
  ATables: TAtlasTrackerSettingsTables; AOnChanged: TAtlasTrackerTableChanged);
begin
  inherited Create;
  FRows := ARows;
  FHooks := AHooks;
  FTables := ATables;
  FOnChanged := AOnChanged;
end;

destructor TAtlasTrackerProjectsPart.Destroy;
begin
  FreeAndNil(FPaths);
  inherited Destroy;
end;

function TAtlasTrackerProjectsPart.Table: TAtlasTrackerProjectTable;
begin
  Result := FTables.Projects;
end;

procedure TAtlasTrackerProjectsPart.Build;
begin
  BuildList;
  BuildFields;
  BuildButtons;
end;

procedure TAtlasTrackerProjectsPart.PathsChanged(APaths: TArray<string>);
begin
  Table.SetPaths(APaths);
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].SubItems[cPathsSubItem] := TAtlasTrackerPathsPart.Caption(Table.SelectedRow);
  end;
end;

procedure TAtlasTrackerProjectsPart.BuildList;
begin
  FRows.AddTitle(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjects));
  FAnchor := FRows.AddKeyedPanel(TRows.cListRow, TAtlasTrackerSettingsTables.cProjectsKey);
  // Wie die Verbindungen: die Zeilen erst mit Fenster (Refresh, auch aus WindowReady).
  FView.List := FRows.AddList(FAnchor, SelectItem);
  FView.List.OnCustomDrawItem := DrawItem;
  FRows.AddColumn(FView.List, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatch), cMatchColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectConnection),
    cConnectionColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectProject),
    cProjectColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesPaths), cPathsColumn);
  FRows.AddColumn(FView.List, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectSource), cSourceColumn);
end;

procedure TAtlasTrackerProjectsPart.BuildFields;
begin
  FView.Match := FRows.NewEdit(MatchChange);
  FRows.Attach(FRows.AddLabelled(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatch), FView.Match,
    TRows.cWideWidth), FAnchor);
  FView.Connection := TAtlasChoiceBox.Create(FRows.Owner);
  FView.Connection.OnChange := ConnectionChange;
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectConnection),
    FView.Connection, TRows.cFieldWidth), FAnchor);
  FView.Project := FRows.NewEdit(ProjectChange);
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectProject),
    FView.Project, TRows.cFieldWidth), FAnchor);
  // Arbeitskopien (#1926).
  FPaths := TAtlasTrackerPathsPart.Create(FRows, FHooks, FAnchor,
    function(out APath: string): Boolean
    begin
      Result := Browse(True, APath);
    end,
    PathsChanged);
  FPaths.Build;
  // Grund, warum eine Zeile nicht greift (Verbindung fehlt, von .atlas überdeckt …).
  FView.Note := FRows.AddNote(FAnchor);
end;

procedure TAtlasTrackerProjectsPart.BuildButtons;

  procedure AddMenuItem(const ACaption: string; AClick: TNotifyEvent);
  var
    mItem: TMenuItem;
  begin
    mItem := TMenuItem.Create(FRows.Owner);
    mItem.Caption := ACaption;
    mItem.OnClick := AClick;
    FView.AddMenu.Items.Add(mItem);
  end;

var
  mPanel: TWinControl;
  mLeft: Integer;
begin
  mPanel := FRows.AddPanel(TRows.cButtonRow);
  mLeft := 0;
  FView.AddCurrent := FRows.AddButton(mPanel, mLeft, cAddCurrentWidth,
    TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddCurrent), AddCurrentClick);
  Inc(mLeft, cAddCurrentWidth + TRows.cButtonGap);
  FView.Add := FRows.AddButton(mPanel, mLeft, cAddWidth, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAdd),
    AddClick);
  Inc(mLeft, cAddWidth + TRows.cButtonGap);
  FView.Remove := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove), RemoveClick);
  FRows.Attach(mPanel, FAnchor);
  // „Hinzufügen …“: Projektdatei oder Ordner.
  FView.AddMenu := TPopupMenu.Create(FRows.Owner);
  AddMenuItem(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddFile), AddFileClick);
  AddMenuItem(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAddFolder), AddFolderClick);
  FRows.AddHint(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectsHint), FAnchor);
end;

function TAtlasTrackerProjectsPart.SourceText(const AMapping: TAtlasTrackerProjectMapping): string;
const
  cTexts: array[TAtlasTrackerProjectSource] of TAtlasTextId = (TAtlasTextId.SettingsIssuesProjectPersonal,
    TAtlasTextId.SettingsIssuesProjectCovered, TAtlasTextId.SettingsIssuesProjectTeam);
begin
  Result := TAtlasStrings.Text(cTexts[Table.SourceOf(AMapping)]);
end;

function TAtlasTrackerProjectsPart.NoteText(const AMapping: TAtlasTrackerProjectMapping): string;
begin
  case Table.NoteOf(AMapping) of
    TAtlasTrackerProjectNote.ReadOnly:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly);
    TAtlasTrackerProjectNote.NoConnection:
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectNoConnection);
    TAtlasTrackerProjectNote.ConnectionMissing:
      Result := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesProjectConnectionMissing,
        [AMapping.Connection]);
    TAtlasTrackerProjectNote.Covered:
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectCoveredHint);
  else
    Result := '';
  end;
end;

procedure TAtlasTrackerProjectsPart.Refresh;
begin
  if FView.List = nil then
  begin
    Exit;
  end;
  if Assigned(FHooks.OnContext) then
  begin
    Table.SetContext(FHooks.OnContext());
  end
  else
  begin
    Table.SetContext(TAtlasTrackerProjectContext.Empty);
  end;
  // Auswahl der Verbindung: die persönlichen mit Namen (eine Zeile verweist per Name auf sie).
  FFilling := True;
  try
    FView.Connection.SetChoices(Table.Choices);
  finally
    FFilling := False;
  end;
  if FRows.ListReady(FView.List) then
  begin
    FillList;
  end;
  FillFields;
  FOnChanged;
end;

procedure TAtlasTrackerProjectsPart.FillList;
var
  mRow: TAtlasTrackerProjectMapping;
  mItem: TListItem;
begin
  FFilling := True;
  FView.List.Items.BeginUpdate;
  try
    FView.List.Items.Clear;
    for mRow in Table.Rows do
    begin
      mItem := FView.List.Items.Add;
      mItem.Caption := mRow.Match;
      mItem.SubItems.Add(mRow.Connection);
      mItem.SubItems.Add(mRow.Project);
      mItem.SubItems.Add(TAtlasTrackerPathsPart.Caption(mRow));
      mItem.SubItems.Add(SourceText(mRow));
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

procedure TAtlasTrackerProjectsPart.FillFields;
var
  mRow: TAtlasTrackerProjectMapping;
  mEditable: Boolean;
begin
  mRow := Table.SelectedRow;
  FFilling := True;
  try
    FView.Match.Text := mRow.Match;
    FView.Project.Text := mRow.Project;
    FView.Connection.Choice := Table.ChoiceOf(mRow.Connection);
  finally
    FFilling := False;
  end;
  FView.Note.Caption := NoteText(mRow);
  if not Table.HasSelection and (Length(Table.Choices) > 0) then
  begin
    FView.Note.Caption := '';
  end;
  mEditable := Table.Editable;
  FRows.Allow(FView.Match, mEditable);
  FRows.Allow(FView.Connection, mEditable and (Length(Table.Choices) > 0));
  FRows.Allow(FView.Project, mEditable);
  FRows.Allow(FView.Remove, mEditable);
  FRows.Allow(FView.AddCurrent, Table.Context.ProjectFile <> '');
  if FPaths <> nil then
  begin
    FPaths.Show(mRow, mEditable and not mRow.ReadOnly);
  end;
end;

function TAtlasTrackerProjectsPart.ItemReady: Boolean;
begin
  Result := FRows.ListReady(FView.List) and (Table.Selected < FView.List.Items.Count);
end;

procedure TAtlasTrackerProjectsPart.SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  Table.Select(Item.Index);
  FillFields;
end;

procedure TAtlasTrackerProjectsPart.DrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
begin
  // Von der .atlas überdeckte persönliche Zeile grau (Mockup IT2).
  mRows := Table.Rows;
  if (Item <> nil) and (Item.Index <= High(mRows)) and Table.Covered(mRows[Item.Index]) then
  begin
    // Hintergrund in der Stilfarbe, sonst zeichnet die Zeile weiß bzw. schwarz (clWindow, clWindowText ohne Stil).
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Brush.Color := StyleServices(Sender).GetSystemColor(clWindow);
      Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clWindowText);
    end;
    Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clGrayText);
  end;
  DefaultDraw := True;
end;

procedure TAtlasTrackerProjectsPart.MatchChange(Sender: TObject);
var
  mMatch: string;
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  mMatch := Trim(FView.Match.Text);
  // Ein Pfad hat höchstens eine persönliche Zeile.
  if not Table.SetMatch(mMatch) then
  begin
    FView.Note.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken);
    Exit;
  end;
  FView.Note.Caption := NoteText(Table.SelectedRow);
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].Caption := mMatch;
    FView.List.Items[Table.Selected].SubItems[cSourceSubItem] := SourceText(Table.SelectedRow);
  end;
end;

procedure TAtlasTrackerProjectsPart.ConnectionChange(Sender: TObject);
begin
  if FFilling or not Table.SetConnection(FView.Connection.Choice) then
  begin
    Exit;
  end;
  FView.Note.Caption := NoteText(Table.SelectedRow);
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].SubItems[cConnectionSubItem] := Table.SelectedRow.Connection;
  end;
end;

procedure TAtlasTrackerProjectsPart.ProjectChange(Sender: TObject);
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  Table.SetProject(Trim(FView.Project.Text));
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].SubItems[cProjectSubItem] := Table.SelectedRow.Project;
  end;
end;

procedure TAtlasTrackerProjectsPart.AddMatch(const AMatch: string);
begin
  if Table.Add(AMatch) then
  begin
    Refresh;
    TRows.Focus(FView.Project);
  end;
end;

procedure TAtlasTrackerProjectsPart.AddCurrentClick(Sender: TObject);
begin
  Refresh;
  if Table.CurrentMatch = '' then
  begin
    FView.Note.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoProject);
    Exit;
  end;
  // Die geöffnete .groupproj, sonst die aktive .dproj.
  AddMatch(Table.CurrentMatch);
end;

procedure TAtlasTrackerProjectsPart.AddClick(Sender: TObject);
begin
  // Unter dem Knopf aufklappen.
  FView.AddMenu.Popup(FView.Add.ClientOrigin.X, FView.Add.ClientOrigin.Y + FView.Add.Height);
end;

function TAtlasTrackerProjectsPart.Browse(AFolder: Boolean; out APath: string): Boolean;
var
  mFolder: TFileOpenDialog;
  mFile: TOpenDialog;
begin
  APath := '';
  if Assigned(FHooks.OnBrowse) then
  begin
    Exit(FHooks.OnBrowse(AFolder, APath));
  end;
  if AFolder then
  begin
    mFolder := TFileOpenDialog.Create(nil);
    try
      mFolder.Options := mFolder.Options + [fdoPickFolders, fdoPathMustExist];
      Result := mFolder.Execute;
      APath := mFolder.FileName;
    finally
      mFolder.Free;
    end;
    Exit;
  end;
  mFile := TOpenDialog.Create(nil);
  try
    mFile.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectFileFilter);
    mFile.Options := mFile.Options + [ofFileMustExist];
    Result := mFile.Execute;
    APath := mFile.FileName;
  finally
    mFile.Free;
  end;
end;

procedure TAtlasTrackerProjectsPart.AddFileClick(Sender: TObject);
var
  mPath: string;
begin
  if Browse(False, mPath) then
  begin
    AddMatch(mPath);
  end;
end;

procedure TAtlasTrackerProjectsPart.AddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if Browse(True, mPath) then
  begin
    AddMatch(mPath);
  end;
end;

procedure TAtlasTrackerProjectsPart.RemoveClick(Sender: TObject);
begin
  if Table.Editable then
  begin
    Table.Remove;
    Refresh;
  end;
end;

end.
