unit Atlas.UI.Tracker.SettingsWorkflow;

// Zustand im Tracker (#1266) auf der Seite Issue-Tracker: Schalter, Felder
// und Zustände mit Werten vom Tracker (Klapplisten), Vorlagen der Kommentare
// beim Beginnen und Beenden und „Werte vom Tracker laden“. Die Klapplisten
// liest Load und schreibt Save selbst; die Kommentare bleiben ungekürzt, die
// Zielzustände werden geordnet. Dazu die Prüfzustände (#2126,
// issues.reviewStates), „Prüfen“ mit Build und Tests und die Vorlage seines
// Kommentars (#2126, issues.reviewBuild, issues.reviewComment) und der
// Schalter für wieder geöffnete Issues (#2127, issues.reopened).

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente des Zustands im Tracker.</summary>
  TAtlasTrackerWorkflowView = record
    SyncState: TCheckBox;
    StateField: TAtlasValueBox;
    AssigneeField: TAtlasValueBox;
    StartState: TAtlasValueBox;
    AssignOnStart: TCheckBox;
    StartComment: TEdit;
    EndStates: TEdit;
    EndComment: TEdit;
    ReviewStates: TEdit;
    ReviewBuild: TCheckBox;
    ReviewComment: TEdit;
    Reopened: TCheckBox;
    LoadValues: TButton;
    ValuesNote: TLabel;
  end;

  TAtlasTrackerWorkflowPart = class
  public const
    cStateFieldKey = 'issues.stateField';
    cAssigneeFieldKey = 'issues.assigneeField';
    cStartStateKey = 'issues.startState';
    cStartCommentKey = 'issues.startComment';
    cEndStatesKey = 'issues.endStates';
    cEndCommentKey = 'issues.endComment';
    cReviewStatesKey = 'issues.reviewStates';
    cReviewCommentKey = 'issues.reviewComment';
  private
    FRows: TAtlasTrackerSettingsRows;
    FHooks: TAtlasTrackerSettingsHooks;
    FTables: TAtlasTrackerSettingsTables;
    FView: TAtlasTrackerWorkflowView;
    procedure BuildFields;
    procedure BuildLoad;
    procedure LoadValuesClick(Sender: TObject);
  public
    constructor Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
      ATables: TAtlasTrackerSettingsTables);
    procedure Build;
    /// <summary>Die Klapplisten (gebundene Felder lädt die Seite).</summary>
    procedure Load(const AValues: IAtlasSettingsValues);
    /// <summary>Klapplisten, Kommentare ungekürzt, Zielzustände geordnet.</summary>
    procedure Save(const AValues: IAtlasSettingsValues);
    /// <summary>Antwort auf „Werte vom Tracker laden“; AError leer bei Erfolg.</summary>
    procedure ValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
    property View: TAtlasTrackerWorkflowView read FView;
  end;

implementation

uses
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Review,
  Vcl.Graphics,
  Atlas.UI.Tracker.Strings;

const
  cValueLeft = 280;
  cLoadRow = 30;
  cLoadWidth = 180;
  cNoteLeft = 190;
  cNoteTop = 7;

{ TAtlasTrackerWorkflowPart }

constructor TAtlasTrackerWorkflowPart.Create(ARows: TAtlasTrackerSettingsRows; AHooks: TAtlasTrackerSettingsHooks;
  ATables: TAtlasTrackerSettingsTables);
begin
  inherited Create;
  FRows := ARows;
  FHooks := AHooks;
  FTables := ATables;
end;

procedure TAtlasTrackerWorkflowPart.Build;
begin
  FRows.AddTitle(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesWorkflowTitle));
  BuildFields;
  BuildLoad;
end;

procedure TAtlasTrackerWorkflowPart.BuildFields;
begin
  FView.SyncState := FRows.AddCheck('issues.syncState',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesSyncState));
  FView.StateField := FRows.AddValueBox(cStateFieldKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStateField), cValueLeft);
  FView.AssigneeField := FRows.AddValueBox(cAssigneeFieldKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAssigneeField), cValueLeft);
  FView.StartState := FRows.AddValueBox(cStartStateKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartState), cValueLeft);
  FView.AssignOnStart := FRows.AddCheck('issues.assignOnStart',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesAssignOnStart));
  FView.StartComment := FRows.AddText(cStartCommentKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesStartComment));
  FView.EndStates := FRows.AddText(cEndStatesKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesEndStates));
  FView.EndComment := FRows.AddText(cEndCommentKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesEndComment));
  FView.ReviewStates := FRows.AddText(cReviewStatesKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesReviewStates));
  FView.ReviewBuild := FRows.AddCheck('issues.reviewBuild',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesReviewBuild));
  FView.ReviewComment := FRows.AddText(cReviewCommentKey,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesReviewComment));
  FView.Reopened := FRows.AddCheck('issues.reopened',
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesReopened));
end;

procedure TAtlasTrackerWorkflowPart.BuildLoad;
var
  mPanel: TWinControl;
begin
  mPanel := FRows.AddPanel(cLoadRow);
  FView.LoadValues := FRows.AddButton(mPanel, 0, cLoadWidth,
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesLoadValues), LoadValuesClick);
  FView.ValuesNote := TLabel.Create(FRows.Owner);
  FView.ValuesNote.Parent := mPanel;
  FView.ValuesNote.Left := FView.ValuesNote.ScaleValue(cNoteLeft);
  FView.ValuesNote.Top := FView.ValuesNote.ScaleValue(cNoteTop);
  FView.ValuesNote.Font.Color := clGrayText;
  FView.ValuesNote.Caption := '';
end;

procedure TAtlasTrackerWorkflowPart.Load(const AValues: IAtlasSettingsValues);
begin
  FView.StateField.Value := AValues.ReadString(cStateFieldKey);
  FView.AssigneeField.Value := AValues.ReadString(cAssigneeFieldKey);
  FView.StartState.Value := AValues.ReadString(cStartStateKey);
  // Die unveränderte Vorgabe in der Sprache der Oberfläche (#1458); die Seite hat den gespeicherten Text geladen.
  FView.EndComment.Text := TAtlasTrackerWorkflow.EndCommentFor(AValues.ReadString(cEndCommentKey),
    TAtlasTrackerStrings.English);
  FView.ReviewComment.Text := TAtlasTrackerReview.CommentFor(AValues.ReadString(cReviewCommentKey),
    TAtlasTrackerStrings.English);
end;

procedure TAtlasTrackerWorkflowPart.Save(const AValues: IAtlasSettingsValues);
begin
  // Die Kommentare bleiben, wie eingegeben (die Seite kürzt gebundene Textzeilen).
  AValues.WriteString(cStartCommentKey, FView.StartComment.Text);
  AValues.WriteString(cEndCommentKey, FView.EndComment.Text);
  AValues.WriteString(cReviewCommentKey, FView.ReviewComment.Text);
  AValues.WriteString(cEndStatesKey,
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FView.EndStates.Text)));
  AValues.WriteString(cReviewStatesKey,
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FView.ReviewStates.Text)));
  AValues.WriteString(cStateFieldKey, FView.StateField.Value);
  AValues.WriteString(cAssigneeFieldKey, FView.AssigneeField.Value);
  AValues.WriteString(cStartStateKey, FView.StartState.Value);
end;

procedure TAtlasTrackerWorkflowPart.LoadValuesClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
  mField: string;
begin
  if not Assigned(FHooks.OnValues) then
  begin
    Exit;
  end;
  if not FTables.Connections.ValuesConnection(mConnection) then
  begin
    FView.ValuesNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesNoConnection);
    Exit;
  end;
  // Zustände zum Feld der Verbindung, sonst zum globalen Feld.
  mField := mConnection.StateField;
  if mField = '' then
  begin
    mField := FView.StateField.Value;
  end;
  FView.ValuesNote.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.SettingsIssuesValuesLoading);
  FView.LoadValues.Enabled := False;
  FHooks.OnValues(mConnection, mField);
end;

procedure TAtlasTrackerWorkflowPart.ValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
begin
  FView.LoadValues.Enabled := True;
  if AError <> '' then
  begin
    FView.ValuesNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesFailed, [AError]);
    Exit;
  end;
  // Vorschläge für die globalen Felder; eingegebene Texte bleiben.
  FView.StateField.SetValues(AValues.StateFields);
  FView.AssigneeField.SetValues(AValues.UserFields);
  FView.StartState.SetValues(AValues.States);
  FView.ValuesNote.Caption := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.SettingsIssuesValuesLoaded,
    [Length(AValues.States), Length(AValues.StateFields) + Length(AValues.UserFields)]);
end;

end.
