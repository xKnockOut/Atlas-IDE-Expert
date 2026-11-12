unit Atlas.UI.Tracker.SettingsConnections;

// Tabelle Verbindungen der Seite Issue-Tracker (#1260, Mockup IT1): Name,
// Anbieter, Adresse und Zustand des Tokens, darunter die gewählte Zeile mit
// Zustand und Zuständigkeit je Verbindung (#1266) und die Knöpfe. Die Zeilen
// und alle Prüfungen hält TAtlasTrackerConnectionTable; hier steht nur, was
// die Oberfläche zeigt. Nach jeder Änderung der Verbindungen meldet OnChanged,
// damit Projekte und Abfragen ihre Auswahl neu aufbauen.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente der Tabelle Verbindungen.</summary>
  TAtlasTrackerConnectionsView = record
    List: TListView;
    Name: TEdit;
    Provider: TAtlasChoiceBox;
    Url: TEdit;
    Note: TLabel;
    StateField: TAtlasValueBox;
    AssigneeField: TAtlasValueBox;
    StartState: TAtlasValueBox;
    EndStates: TEdit;
    EndFields: TEdit;
    /// <summary>Zeilen von Zustandsfeld und Benutzerfeld: nur bei Anbietern mit Feldern sichtbar.</summary>
    StateRow: TWinControl;
    AssigneeRow: TWinControl;
    Add: TButton;
    Remove: TButton;
    Token: TButton;
    Check: TButton;
  end;

  TAtlasTrackerConnectionsPart = class
  private
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FTables: TAtlasTrackerSettingsTables;
    FView: TAtlasTrackerConnectionsView;
    /// <summary>Zeile mit der Tabelle; an ihr hängen Felder und Knöpfe darunter.</summary>
    FAnchor: TWinControl;
    /// <summary>Der Teil füllt die Felder selbst: OnChange übernimmt nichts.</summary>
    FFilling: Boolean;
    FOnChanged: TAtlasTrackerTableChanged;
    function Table: TAtlasTrackerConnectionTable;
    procedure BuildList;
    procedure BuildFields;
    procedure BuildWorkflow;
    procedure BuildButtons;
    function StateText(const AConnection: TAtlasTrackerConnection): string;
    class function RowCaption(const AConnection: TAtlasTrackerConnection): string; static;
    procedure FillList;
    procedure FillFields;
    procedure ShowValues(const AConnection: TAtlasTrackerConnection);
    procedure AllowFields;
    procedure ShowFields;
    function ItemReady: Boolean;
    procedure SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure NameChange(Sender: TObject);
    procedure ProviderChange(Sender: TObject);
    procedure UrlChange(Sender: TObject);
    procedure WorkflowChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure TokenClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
      ATables: TAtlasTrackerSettingsTables; AOnChanged: TAtlasTrackerTableChanged);
    procedure Build;
    /// <summary>Verbindungen aus der .atlas holen, Tabelle und Felder neu; meldet OnChanged.</summary>
    procedure Refresh;
    /// <summary>Anbieter der Auswahl haben sich geändert.</summary>
    procedure ProvidersChanged;
    /// <summary>Vorschläge für Zustandsfeld, Benutzerfeld und Startzustand (#1266).</summary>
    procedure ValuesLoaded(const AValues: TAtlasTrackerValueSet);
    property View: TAtlasTrackerConnectionsView read FView;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  cNameColumn = 110;
  cProviderColumn = 80;
  cUrlColumn = 200;
  cTokenColumn = 170;
  cProviderSubItem = 0;
  cUrlSubItem = 1;
  cStateSubItem = 2;
  cTimeFormat = 'hh:nn';

type
  TRows = TAtlasTrackerSettingsRows;

{ TAtlasTrackerConnectionsPart }

constructor TAtlasTrackerConnectionsPart.Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
  ATables: TAtlasTrackerSettingsTables; AOnChanged: TAtlasTrackerTableChanged);
begin
  inherited Create;
  FRows := ARows;
  FHooks := AHooks;
  FTables := ATables;
  FOnChanged := AOnChanged;
end;

function TAtlasTrackerConnectionsPart.Table: TAtlasTrackerConnectionTable;
begin
  Result := FTables.Connections;
end;

procedure TAtlasTrackerConnectionsPart.Build;
begin
  BuildList;
  BuildFields;
  BuildWorkflow;
  BuildButtons;
end;

procedure TAtlasTrackerConnectionsPart.BuildList;
begin
  FRows.AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnections));
  FAnchor := FRows.AddKeyedPanel(TRows.cListRow, TAtlasTrackerSettingsTables.cConnectionsKey);
  // Die Zeilen brauchen ein Fenster: Refresh füllt sie (auch aus WindowReady).
  FView.List := FRows.AddList(FAnchor, SelectItem);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionName),
    cNameColumn);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionProvider),
    cProviderColumn);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrl),
    cUrlColumn);
  FRows.AddColumn(FView.List, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionToken),
    cTokenColumn);
end;

procedure TAtlasTrackerConnectionsPart.BuildFields;
begin
  FView.Name := FRows.NewEdit(NameChange);
  FRows.Attach(FRows.AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionName),
    FView.Name, TRows.cFieldWidth), FAnchor);
  FView.Provider := TAtlasChoiceBox.Create(FRows.Owner);
  FView.Provider.SetChoices(Table.ProviderCaptions);
  FView.Provider.OnChange := ProviderChange;
  FRows.Attach(FRows.AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionProvider),
    FView.Provider, TRows.cFieldWidth), FAnchor);
  FView.Url := FRows.NewEdit(UrlChange);
  FRows.Attach(FRows.AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrl),
    FView.Url, TRows.cWideWidth), FAnchor);
  // Grund, warum eine Eingabe nicht übernommen wird (nur https, Name vergeben …).
  FView.Note := FRows.AddNote(FAnchor);
end;

procedure TAtlasTrackerConnectionsPart.BuildWorkflow;

  function AddBox(AId: TAtlasTrackerTextId; out ARow: TWinControl): TAtlasValueBox;
  begin
    Result := TAtlasValueBox.Create(FRows.Owner);
    Result.OnChange := WorkflowChange;
    ARow := FRows.AddLabelled(TAtlasTrackerStrings.Text(AId), Result, TRows.cFieldWidth);
    FRows.Attach(ARow, FAnchor);
  end;

var
  mRow: TWinControl;
begin
  // Zustand und Zuständigkeit je Verbindung (#1266); leer gilt „Zustand im Tracker“ weiter unten.
  FView.StateField := AddBox(TAtlasTrackerTextId.SettingsIssuesConnectionStateField, FView.StateRow);
  FView.AssigneeField := AddBox(TAtlasTrackerTextId.SettingsIssuesConnectionAssigneeField, FView.AssigneeRow);
  FView.StartState := AddBox(TAtlasTrackerTextId.SettingsIssuesConnectionStartState, mRow);
  FView.EndStates := FRows.NewEdit(WorkflowChange);
  FRows.Attach(FRows.AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionEndStates),
    FView.EndStates, TRows.cWideWidth), FAnchor);
  // Felder im Beenden-Dialog (#2123); leer gilt issues.endFields.
  FView.EndFields := FRows.NewEdit(WorkflowChange);
  FRows.Attach(FRows.AddLabelled(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionEndFields),
    FView.EndFields, TRows.cWideWidth), FAnchor);
  FRows.AddHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionStatesHint), FAnchor);
end;

procedure TAtlasTrackerConnectionsPart.BuildButtons;
var
  mPanel: TWinControl;
  mLeft: Integer;
begin
  mPanel := FRows.AddPanel(TRows.cButtonRow);
  mLeft := 0;
  FView.Add := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionAdd), AddClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  FView.Remove := FRows.AddButton(mPanel, mLeft, TRows.cButtonWidth,
    TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionRemove), RemoveClick);
  Inc(mLeft, TRows.cButtonWidth + TRows.cButtonGap);
  FView.Token := FRows.AddButton(mPanel, mLeft, TRows.cWideButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionEnterToken), TokenClick);
  Inc(mLeft, TRows.cWideButtonWidth + TRows.cButtonGap);
  FView.Check := FRows.AddButton(mPanel, mLeft, TRows.cWideButtonWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionCheck), CheckClick);
  FRows.Attach(mPanel, FAnchor);
  FRows.AddHint(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionsHint), FAnchor);
end;

function TAtlasTrackerConnectionsPart.StateText(const AConnection: TAtlasTrackerConnection): string;
var
  mStatus: TAtlasTrackerTokenStatus;
begin
  if Table.Checking(AConnection) then
  begin
    Exit(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenChecking));
  end;
  mStatus := TAtlasTrackerTokenStatus.Stored(False);
  if Assigned(FHooks.OnState) and (AConnection.Target.Server <> '') then
  begin
    mStatus := FHooks.OnState(AConnection);
  end;
  case mStatus.State of
    TAtlasTrackerTokenState.Saved:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenSaved);
    TAtlasTrackerTokenState.Verified:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenVerified,
        [FormatDateTime(cTimeFormat, mStatus.CheckedAt, FormatSettings)]);
    TAtlasTrackerTokenState.Rejected:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenRejected);
    TAtlasTrackerTokenState.Unreachable:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenUnreachable);
    TAtlasTrackerTokenState.Unexpected:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.TrackerTokenUnexpectedStatus, [mStatus.HttpStatus]);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenMissing);
  end;
  if (mStatus.State = TAtlasTrackerTokenState.Unexpected) and (mStatus.HttpStatus <= 0) then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.TrackerTokenUnexpected);
  end;
end;

class function TAtlasTrackerConnectionsPart.RowCaption(const AConnection: TAtlasTrackerConnection): string;
begin
  Result := AConnection.Name;
  if AConnection.ReadOnly then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesConnectionTeam, [AConnection.Name]);
  end;
end;

procedure TAtlasTrackerConnectionsPart.Refresh;
begin
  if FView.List = nil then
  begin
    Exit;
  end;
  if Assigned(FHooks.OnTeam) then
  begin
    Table.SetTeam(FHooks.OnTeam());
  end
  else
  begin
    Table.SetTeam(nil);
  end;
  // Wie die Liste der Favoriten: ohne Fenster folgt das in WindowReady.
  if FRows.ListReady(FView.List) then
  begin
    FillList;
  end;
  FillFields;
  FTables.ShareNames;
  FOnChanged;
end;

procedure TAtlasTrackerConnectionsPart.FillList;
var
  mRow: TAtlasTrackerConnection;
  mItem: TListItem;
begin
  FFilling := True;
  FView.List.Items.BeginUpdate;
  try
    FView.List.Items.Clear;
    for mRow in Table.Rows do
    begin
      mItem := FView.List.Items.Add;
      mItem.Caption := RowCaption(mRow);
      mItem.SubItems.Add(Table.ProviderCaption(mRow.Provider));
      mItem.SubItems.Add(mRow.Url);
      mItem.SubItems.Add(StateText(mRow));
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

procedure TAtlasTrackerConnectionsPart.ShowValues(const AConnection: TAtlasTrackerConnection);
begin
  FView.Name.Text := AConnection.Name;
  FView.Url.Text := AConnection.Url;
  FView.Provider.Choice := Table.ProviderIndex(AConnection.Provider);
  FView.StateField.Value := AConnection.StateField;
  FView.AssigneeField.Value := AConnection.AssigneeField;
  FView.StartState.Value := AConnection.StartState;
  FView.EndStates.Text := TAtlasTrackerWorkflow.ListText(AConnection.EndStates);
  FView.EndFields.Text := TAtlasTrackerWorkflow.ListText(AConnection.EndFields);
end;

procedure TAtlasTrackerConnectionsPart.FillFields;
var
  mRow: TAtlasTrackerConnection;
begin
  mRow := Table.SelectedRow;
  FFilling := True;
  try
    ShowValues(mRow);
  finally
    FFilling := False;
  end;
  FView.Note.Caption := '';
  if Table.HasSelection and not Table.Editable then
  begin
    FView.Note.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionReadOnly);
  end
  else if Table.Editable and (mRow.Url = '') then
  begin
    FView.Note.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionUrlEmpty);
  end;
  AllowFields;
  ShowFields;
end;

procedure TAtlasTrackerConnectionsPart.AllowFields;
var
  mEditable, mHasUrl: Boolean;
begin
  mEditable := Table.Editable;
  mHasUrl := Table.HasSelection and (Table.SelectedRow.Url <> '');
  FRows.Allow(FView.Name, mEditable);
  FRows.Allow(FView.Provider, mEditable);
  FRows.Allow(FView.Url, mEditable);
  FRows.Allow(FView.StateField, mEditable);
  FRows.Allow(FView.AssigneeField, mEditable);
  FRows.Allow(FView.StartState, mEditable);
  FRows.Allow(FView.EndStates, mEditable);
  FRows.Allow(FView.EndFields, mEditable);
  FRows.Allow(FView.Remove, mEditable);
  // Token und Prüfung auch für die Verbindung aus der .atlas, nicht ohne gültige Adresse.
  FRows.Allow(FView.Token, mHasUrl and Assigned(FHooks.OnToken));
  FRows.Allow(FView.Check, mHasUrl and Assigned(FHooks.OnCheck));
end;

procedure TAtlasTrackerConnectionsPart.ShowFields;
var
  mShown: Boolean;

  // alTop ordnet eine wieder gezeigte Zeile nach ihrem alten Top ein: knapp über „Beim Beginnen“ stellen, damit
  // die Reihenfolge Zustandsfeld, Benutzerfeld, Beim Beginnen bleibt.
  procedure ShowAbove(ARow: TWinControl);
  begin
    if mShown and not ARow.Visible then
    begin
      ARow.Top := FView.StartState.Parent.Top - 1;
    end;
    ARow.Visible := mShown;
  end;

begin
  mShown := True;
  if Table.HasSelection then
  begin
    mShown := TAtlasTrackerWorkflow.UsesFields(Table.SelectedRow.Provider);
  end;
  ShowAbove(FView.StateRow);
  ShowAbove(FView.AssigneeRow);
end;

function TAtlasTrackerConnectionsPart.ItemReady: Boolean;
begin
  Result := FRows.ListReady(FView.List) and (Table.Selected < FView.List.Items.Count);
end;

procedure TAtlasTrackerConnectionsPart.SelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  Table.Select(Item.Index);
  FillFields;
end;

procedure TAtlasTrackerConnectionsPart.NameChange(Sender: TObject);
var
  mName, mOld: string;
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  mName := Trim(FView.Name.Text);
  if Table.NameTaken(mName) then
  begin
    FView.Note.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNameTaken);
    Exit;
  end;
  FView.Note.Caption := '';
  // Projekte und Abfragen verweisen per Name: umbenennen statt sie ins Leere zeigen zu lassen (#1261, #1262).
  mOld := Table.Rename(mName);
  FTables.ConnectionRenamed(mOld, mName);
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].Caption := mName;
  end;
  FOnChanged;
end;

procedure TAtlasTrackerConnectionsPart.ProviderChange(Sender: TObject);
begin
  if FFilling or not Table.SetProvider(FView.Provider.Choice) then
  begin
    Exit;
  end;
  ShowFields;
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].SubItems[cProviderSubItem] := Table.ProviderCaption(Table.SelectedRow.Provider);
  end;
end;

procedure TAtlasTrackerConnectionsPart.UrlChange(Sender: TObject);
const
  cUrlTexts: array[TAtlasTrackerUrlCheck] of TAtlasTrackerTextId = (TAtlasTrackerTextId.SettingsIssuesConnectionUrl,
    TAtlasTrackerTextId.SettingsIssuesConnectionUrlEmpty, TAtlasTrackerTextId.SettingsIssuesConnectionUrlHttps,
    TAtlasTrackerTextId.SettingsIssuesConnectionUrlUser, TAtlasTrackerTextId.SettingsIssuesConnectionUrlInvalid);
var
  mCheck: TAtlasTrackerUrlCheck;
begin
  if FFilling or not Table.Editable then
  begin
    Exit;
  end;
  // Nur gültige Adressen übernehmen: http oder ein Benutzer in der Adresse werden abgewiesen, mit Grund.
  mCheck := Table.SetUrl(FView.Url.Text);
  if mCheck <> TAtlasTrackerUrlCheck.Valid then
  begin
    FView.Note.Caption := TAtlasTrackerStrings.Text(cUrlTexts[mCheck]);
    Exit;
  end;
  FView.Note.Caption := '';
  if ItemReady then
  begin
    FView.List.Items[Table.Selected].SubItems[cUrlSubItem] := Table.SelectedRow.Url;
    FView.List.Items[Table.Selected].SubItems[cStateSubItem] := StateText(Table.SelectedRow);
  end;
  FRows.Allow(FView.Token, Assigned(FHooks.OnToken));
  FRows.Allow(FView.Check, Assigned(FHooks.OnCheck));
end;

procedure TAtlasTrackerConnectionsPart.WorkflowChange(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  Table.SetWorkflow(FView.StateField.Value, FView.AssigneeField.Value, FView.StartState.Value,
    FView.EndStates.Text, FView.EndFields.Text);
end;

procedure TAtlasTrackerConnectionsPart.AddClick(Sender: TObject);
begin
  // Neue Zeile ohne Adresse: gespeichert wird sie erst mit gültiger Adresse.
  Table.Add(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesConnectionNew));
  Refresh;
  TRows.Focus(FView.Name);
end;

procedure TAtlasTrackerConnectionsPart.RemoveClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if not Table.Editable then
  begin
    Exit;
  end;
  mConnection := Table.SelectedRow;
  // Die Rückfrage zum Token (Anmeldespeicher) stellt die IDE; die Zeile geht in jedem Fall.
  if Assigned(FHooks.OnRemove) and (mConnection.Target.Server <> '') then
  begin
    FHooks.OnRemove(mConnection);
  end;
  Table.Remove;
  Refresh;
end;

procedure TAtlasTrackerConnectionsPart.TokenClick(Sender: TObject);
begin
  if Assigned(FHooks.OnToken) and Table.HasSelection then
  begin
    FHooks.OnToken(Table.SelectedRow);
    Refresh;
  end;
end;

procedure TAtlasTrackerConnectionsPart.CheckClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if Assigned(FHooks.OnCheck) and Table.StartCheck(mConnection) then
  begin
    Refresh;
    FHooks.OnCheck(mConnection);
  end;
end;

procedure TAtlasTrackerConnectionsPart.ProvidersChanged;
begin
  if FView.Provider <> nil then
  begin
    FView.Provider.SetChoices(Table.ProviderCaptions);
  end;
  Refresh;
end;

procedure TAtlasTrackerConnectionsPart.ValuesLoaded(const AValues: TAtlasTrackerValueSet);
begin
  FView.StateField.SetValues(AValues.StateFields);
  FView.AssigneeField.SetValues(AValues.UserFields);
  FView.StartState.SetValues(AValues.States);
end;

end.
