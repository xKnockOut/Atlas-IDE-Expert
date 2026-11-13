unit Atlas.UI.Tracker.SettingsQueries;

// Tabelle Abfragen der Seite Issue-Tracker (#1262, Mockup IT3): benannte
// Abfragen mit Verbindung und Tracker-Projekt, „Bearbeiten …“ öffnet den
// Dialog mit Vorlagen und „Testen“ (#1263, Atlas.UI.Tracker.QueryDialog).
// Darunter die Schalter der Klappliste und von „Issue anlegen …“ (#1268).
// Die Zeilen und alle Prüfungen hält TAtlasTrackerQueryTable.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente der Tabelle Abfragen und der Schalter darunter.</summary>
  TAtlasTrackerQueriesView = record
    List: TListView;
    Name: TEdit;
    Text: TEdit;
    Connection: TAtlasChoiceBox;
    Project: TEdit;
    Note: TLabel;
    Add: TButton;
    Remove: TButton;
    Edit: TButton;
    Picker: TCheckBox;
    /// <summary>Klappliste „Tracker-Projekt“ (#1927), „Alle“ (#1928) mit Zeilen je Gruppe.</summary>
    ProjectPicker: TCheckBox;
    AllProjects: TCheckBox;
    AllProjectsPerGroup: TEdit;
    CreateIssue: TCheckBox;
    CreateIncludeCode: TCheckBox;
    /// <summary>GitHub-Issue-Vorlagen im Dialog (#2137).</summary>
    CreateTemplates: TCheckBox;
    TemplateFields: TEdit;
  end;

  TAtlasTrackerQueriesPart = class
  private
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FTables: TAtlasTrackerSettingsTables;
    FView: TAtlasTrackerQueriesView;
    FAnchor: TWinControl;
    FFilling: Boolean;
    function Table: TAtlasTrackerQueryTable;
    procedure BuildList;
    procedure BuildFields;
    procedure BuildButtons;
    procedure BuildSwitches;
    function NoteText(const AQuery: TAtlasTrackerQuery): string;
    procedure FillList;
    procedure FillFields;
    procedure RowChanged;
    procedure SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure NameChange(Sender: TObject);
    procedure TextChange(Sender: TObject);
    procedure ConnectionChange(Sender: TObject);
    procedure ProjectChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
      ATables: TAtlasTrackerSettingsTables);
    procedure Build;
    /// <summary>Auswahl der Verbindungen, Tabelle und Felder neu.</summary>
    procedure Refresh;
    property View: TAtlasTrackerQueriesView read FView;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Settings.Strings,
  Atlas.UI.Tracker.QueryDialog;

const
  cNameColumn = 130;
  cQueryColumn = 230;
  cConnectionColumn = 100;
  cProjectColumn = 100;
  cQueriesRow = 96;
  cAddWidth = 110;
  cEditWidth = 110;
  cQuerySubItem = 0;
  cConnectionSubItem = 1;
  cProjectSubItem = 2;

type
  TRows = TAtlasTrackerSettingsRows;

{ TAtlasTrackerQueriesPart }

constructor TAtlasTrackerQueriesPart.Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
  ATables: TAtlasTrackerSettingsTables);
begin
  inherited Create;
  FRows := ARows;
  FHooks := AHooks;
  FTables := ATables;
end;

function TAtlasTrackerQueriesPart.Table: TAtlasTrackerQueryTable;
begin
  Result := FTables.Queries;
end;

procedure TAtlasTrackerQueriesPart.Build;
begin
  BuildList;
  BuildFields;
  BuildButtons;
  BuildSwitches;
end;

procedure TAtlasTrackerQueriesPart.BuildList;
begin
  FRows.AddTitle(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueries));
  FAnchor := FRows.AddKeyedPanel(cQueriesRow, TAtlasTrackerSettingsTables.cQueriesKey);
  // Wie die Verbindungen: die Zeilen erst mit Fenster (Refresh, auch aus WindowReady).
  FView.List := FRows.AddList(FAnchor, SelectItem);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryName), cNameColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQuery), cQueryColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectConnection),
    cConnectionColumn);
  FRows.AddColumn(FView.List, TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectProject),
    cProjectColumn);
end;

procedure TAtlasTrackerQueriesPart.BuildFields;
begin
  FView.Name := FRows.NewEdit(NameChange);
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryName), FView.Name,
    TRows.cFieldWidth), FAnchor);
  FView.Text := FRows.NewEdit(TextChange);
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQuery), FView.Text,
    TRows.cWideWidth), FAnchor);
  FView.Connection := TAtlasChoiceBox.Create(FRows.Owner);
  FView.Connection.OnChange := ConnectionChange;
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectConnection),
    FView.Connection, TRows.cFieldWidth), FAnchor);
  FView.Project := FRows.NewEdit(ProjectChange);
  FRows.Attach(FRows.AddLabelled(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectProject),
    FView.Project, TRows.cFieldWidth), FAnchor);
  // Grund, warum eine Zeile nicht gespeichert wird (Name doppelt, Abfrage fehlt), bzw. die Vorgabe ohne Zeilen;
  // in der Farbe des Textes, weil „keine Zeilen“ kein Fehler ist.
  FView.Note := FRows.AddNote(FAnchor);
  FView.Note.ParentFont := True;
end;

procedure TAtlasTrackerQueriesPart.BuildButtons;
var
  mPanel: TWinControl;
  mLeft: Integer;
begin
  mPanel := FRows.AddPanel(TRows.cButtonRow);
  mLeft := 0;
  FView.Add := FRows.AddButton(mPanel, mLeft, cAddWidth, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectAdd),
    AddClick);
  Inc(mLeft, cAddWidth + TRows.cButtonGap);
  FView.Remove := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove), RemoveClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  // Dialog mit Vorlagen und „Testen“ (#1263); auch Doppelklick auf eine Zeile.
  FView.Edit := FRows.AddButton(mPanel, mLeft, cEditWidth,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryEdit), EditClick);
  FView.List.OnDblClick := EditClick;
  FRows.Attach(mPanel, FAnchor);
  FRows.AddHint(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueriesHint), FAnchor);
end;

procedure TAtlasTrackerQueriesPart.BuildSwitches;
begin
  FView.Picker := FRows.AddCheck('issues.queryPicker',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryPicker));
  // Tracker-Projekt frei wählen (#1927) und alle zusammen (#1928).
  FView.ProjectPicker := FRows.AddCheck('issues.projectPicker',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesProjectPicker));
  FView.AllProjects := FRows.AddCheck('issues.allProjects',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesAllProjects));
  FView.AllProjectsPerGroup := FRows.AddNumber('issues.allProjects.perGroup',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesAllProjectsPerGroup));
  // „Issue anlegen …“ im Editor und bei Befunden (#1268).
  FView.CreateIssue := FRows.AddCheck('issues.create',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesCreate));
  FView.CreateIncludeCode := FRows.AddCheck('issues.create.includeCode',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesCreateIncludeCode));
  // Issue-Vorlagen von GitHub und ihre Vorbelegung (#2137).
  FView.CreateTemplates := FRows.AddCheck('issues.create.templates',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesCreateTemplates));
  FView.TemplateFields := FRows.AddText('issues.github.templateFields',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesGitHubTemplateFields));
end;

function TAtlasTrackerQueriesPart.NoteText(const AQuery: TAtlasTrackerQuery): string;
begin
  case Table.NoteOf(AQuery) of
    TAtlasTrackerQueryNote.Empty:
      Result := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryEmpty);
    TAtlasTrackerQueryNote.ConnectionMissing:
      Result := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesProjectConnectionMissing,
        [AQuery.Connection]);
  else
    Result := '';
  end;
end;

procedure TAtlasTrackerQueriesPart.Refresh;
begin
  if FView.List = nil then
  begin
    Exit;
  end;
  // Auswahl: „(alle)“, dann die Verbindungen mit Namen (wie bei den Projekten).
  FFilling := True;
  try
    FView.Connection.SetChoices(TArray<string>.Create(
      TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryAny)) + Table.Choices);
  finally
    FFilling := False;
  end;
  if FRows.ListReady(FView.List) then
  begin
    FillList;
  end;
  FillFields;
end;

procedure TAtlasTrackerQueriesPart.FillList;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  FFilling := True;
  FView.List.Items.BeginUpdate;
  try
    FView.List.Items.Clear;
    for mQuery in Table.Items do
    begin
      mItem := FView.List.Items.Add;
      mItem.Caption := mQuery.Name;
      mItem.SubItems.Add(mQuery.Query);
      mItem.SubItems.Add(mQuery.Connection);
      mItem.SubItems.Add(mQuery.Project);
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

procedure TAtlasTrackerQueriesPart.FillFields;
var
  mQuery: TAtlasTrackerQuery;
  mEditable: Boolean;
begin
  mEditable := Table.Editable;
  mQuery := Table.SelectedRow;
  FFilling := True;
  try
    FView.Name.Text := mQuery.Name;
    FView.Text.Text := mQuery.Query;
    FView.Project.Text := mQuery.Project;
    FView.Connection.Choice := Table.ChoiceOf(mQuery.Connection);
  finally
    FFilling := False;
  end;
  FView.Note.Caption := '';
  if mEditable then
  begin
    FView.Note.Caption := NoteText(mQuery);
  end
  else if Length(Table.Items) = 0 then
  begin
    // Ohne eigene Zeilen gilt die Vorgabe je Anbieter.
    FView.Note.Caption := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueriesNone);
  end;
  FRows.Allow(FView.Name, mEditable);
  FRows.Allow(FView.Text, mEditable);
  FRows.Allow(FView.Connection, mEditable);
  FRows.Allow(FView.Project, mEditable);
  FRows.Allow(FView.Remove, mEditable);
  FRows.Allow(FView.Edit, mEditable);
end;

procedure TAtlasTrackerQueriesPart.RowChanged;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  mQuery := Table.SelectedRow;
  FView.Note.Caption := NoteText(mQuery);
  if not FRows.ListReady(FView.List) or (Table.Selected >= FView.List.Items.Count) then
  begin
    Exit;
  end;
  mItem := FView.List.Items[Table.Selected];
  mItem.Caption := mQuery.Name;
  mItem.SubItems[cQuerySubItem] := mQuery.Query;
  mItem.SubItems[cConnectionSubItem] := mQuery.Connection;
  mItem.SubItems[cProjectSubItem] := mQuery.Project;
end;

procedure TAtlasTrackerQueriesPart.SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  Table.Select(Item.Index);
  FillFields;
end;

procedure TAtlasTrackerQueriesPart.NameChange(Sender: TObject);
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  // Die Klappliste unterscheidet die Abfragen am Namen.
  if not Table.SetName(Trim(FView.Name.Text)) then
  begin
    FView.Note.Caption := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryNameTaken);
    Exit;
  end;
  RowChanged;
end;

procedure TAtlasTrackerQueriesPart.TextChange(Sender: TObject);
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  Table.SetQuery(FView.Text.Text);
  RowChanged;
end;

procedure TAtlasTrackerQueriesPart.ConnectionChange(Sender: TObject);
begin
  if FFilling or not Table.SetConnection(FView.Connection.Choice) then
  begin
    Exit;
  end;
  RowChanged;
end;

procedure TAtlasTrackerQueriesPart.ProjectChange(Sender: TObject);
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  Table.SetProject(Trim(FView.Project.Text));
  RowChanged;
end;

procedure TAtlasTrackerQueriesPart.AddClick(Sender: TObject);
begin
  // Neue Zeile ohne Abfrage: gespeichert wird sie erst mit Abfrage.
  Table.Add(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesQueryNew));
  Refresh;
  TRows.Focus(FView.Text);
end;

procedure TAtlasTrackerQueriesPart.RemoveClick(Sender: TObject);
begin
  if Table.Editable then
  begin
    Table.Remove;
    Refresh;
  end;
end;

procedure TAtlasTrackerQueriesPart.EditClick(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
  mOk: Boolean;
begin
  if not Table.Editable then
  begin
    Exit;
  end;
  mQuery := Table.SelectedRow;
  if Assigned(FHooks.OnQueryEdit) then
  begin
    mOk := FHooks.OnQueryEdit(mQuery, FTables.Connections.Rows, Table.Taken);
  end
  else
  begin
    mOk := TAtlasTrackerQueryDialog.Execute(mQuery, FTables.Connections.Rows, Table.Taken, FHooks.OnQueryTest);
  end;
  if mOk then
  begin
    Table.Replace(mQuery);
    Refresh;
  end;
end;

end.
