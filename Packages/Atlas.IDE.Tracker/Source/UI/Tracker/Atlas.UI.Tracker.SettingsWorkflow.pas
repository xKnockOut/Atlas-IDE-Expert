unit Atlas.UI.Tracker.SettingsWorkflow;

// Zustand im Tracker (#1266) auf der Seite Issue-Tracker: Schalter, Felder
// und Zustände mit Werten vom Tracker (Klapplisten), Vorlagen der Kommentare
// beim Beginnen und Beenden und „Werte vom Tracker laden“. Die Klapplisten
// liest Load und schreibt Save selbst; die Kommentare bleiben ungekürzt, die
// Zielzustände werden geordnet. Dazu die Prüfzustände (#2126,
// issues.reviewStates), „Prüfen“ mit Build und Tests und die Vorlage seines
// Kommentars (#2126, issues.reviewBuild, issues.reviewComment) und der
// Schalter für wieder geöffnete Issues (#2127, issues.reopened). Bei GitHub
// das Ziel des Zustands, das Projekt und die Aufnahme ins Projekt (#2134,
// issues.github.*); mit Projektfeld bietet „Beginnen setzt“ die Optionen des
// Statusfeldes statt der Labels an.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.SettingsTables,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Tracker.SettingsRows;

type
  /// <summary>Steuerelemente des Zustands im Tracker.</summary>
  TAtlasTrackerWorkflowView = record
    SyncState: TCheckBox;
    StateField: TAtlasValueBox;
    AssigneeField: TAtlasValueBox;
    StateTarget: TAtlasChoiceBox;
    Project: TAtlasValueBox;
    StartState: TAtlasValueBox;
    AssignOnStart: TCheckBox;
    AddToProject: TCheckBox;
    StartComment: TEdit;
    EndStates: TEdit;
    EndComment: TEdit;
    EndFields: TEdit;
    EndTime: TCheckBox;
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
    cEndFieldsKey = 'issues.endFields';
    cReviewStatesKey = 'issues.reviewStates';
    cReviewCommentKey = 'issues.reviewComment';
    cProjectKey = 'issues.github.project';
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
    /// <summary>Vorschläge für „Beginnen setzt“ (#2134): mit Projektfeld und geladenen Optionen des Statusfeldes
    /// diese, sonst die Zustände (GitHub: Labels).</summary>
    class function StartValues(const AValues: TAtlasTrackerValueSet; AInProject: Boolean): TArray<string>; static;
    property View: TAtlasTrackerWorkflowView read FView;
  end;

implementation

uses
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Review,
  Vcl.Graphics,
  Atlas.UI.Tracker.GitHubStrings,
  Atlas.UI.Tracker.Workflow.Strings,
  Atlas.UI.Tracker.Settings.Strings;

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
  FRows.AddTitle(TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesWorkflowTitle));
  BuildFields;
  BuildLoad;
end;

procedure TAtlasTrackerWorkflowPart.BuildFields;
begin
  FView.SyncState := FRows.AddCheck('issues.syncState',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesSyncState));
  FView.StateField := FRows.AddValueBox(cStateFieldKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStateField), cValueLeft);
  FView.AssigneeField := FRows.AddValueBox(cAssigneeFieldKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesAssigneeField), cValueLeft);
  FView.StateTarget := FRows.AddChoice('issues.github.stateTarget',
    TAtlasGitHubStrings.Text(TAtlasGitHubTextId.SettingsStateTarget),
    TArray<string>.Create(TAtlasGitHubStrings.Text(TAtlasGitHubTextId.SettingsStateTargetProject),
    TAtlasGitHubStrings.Text(TAtlasGitHubTextId.SettingsStateTargetLabel)),
    TArray<string>.Create(TAtlasTrackerWorkflow.cStateTargetProject, TAtlasTrackerWorkflow.cStateTargetLabel));
  FView.Project := FRows.AddValueBox(cProjectKey, TAtlasGitHubStrings.Text(TAtlasGitHubTextId.SettingsProject),
    cValueLeft);
  FView.StartState := FRows.AddValueBox(cStartStateKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStartState), cValueLeft);
  FView.AssignOnStart := FRows.AddCheck('issues.assignOnStart',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesAssignOnStart));
  FView.AddToProject := FRows.AddCheck('issues.github.addToProject',
    TAtlasGitHubStrings.Text(TAtlasGitHubTextId.SettingsAddToProject));
  FView.StartComment := FRows.AddText(cStartCommentKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesStartComment));
  FView.EndStates := FRows.AddText(cEndStatesKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesEndStates));
  FView.EndComment := FRows.AddText(cEndCommentKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesEndComment));
  // Beenden in der Reihenfolge des Ablaufs (#2123): Felder und Zeit im Dialog.
  FView.EndFields := FRows.AddText(cEndFieldsKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesEndFields));
  FView.EndTime := FRows.AddCheck('issues.endTime',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesEndTime));
  FView.ReviewStates := FRows.AddText(cReviewStatesKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesReviewStates));
  FView.ReviewBuild := FRows.AddCheck('issues.reviewBuild',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesReviewBuild));
  FView.ReviewComment := FRows.AddText(cReviewCommentKey,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesReviewComment));
  FView.Reopened := FRows.AddCheck('issues.reopened',
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesReopened));
end;

procedure TAtlasTrackerWorkflowPart.BuildLoad;
var
  mPanel: TWinControl;
begin
  mPanel := FRows.AddPanel(cLoadRow);
  FView.LoadValues := FRows.AddButton(mPanel, 0, cLoadWidth,
    TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesLoadValues), LoadValuesClick);
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
  FView.Project.Value := AValues.ReadString(cProjectKey);
  // Die unveränderte Vorgabe in der Sprache der Oberfläche (#1458); die Seite hat den gespeicherten Text geladen.
  FView.EndComment.Text := TAtlasTrackerWorkflow.EndCommentFor(AValues.ReadString(cEndCommentKey),
    TAtlasWorkflowStrings.English);
  FView.ReviewComment.Text := TAtlasTrackerReview.CommentFor(AValues.ReadString(cReviewCommentKey),
    TAtlasWorkflowStrings.English);
end;

procedure TAtlasTrackerWorkflowPart.Save(const AValues: IAtlasSettingsValues);
begin
  // Die Kommentare bleiben, wie eingegeben (die Seite kürzt gebundene Textzeilen).
  AValues.WriteString(cStartCommentKey, FView.StartComment.Text);
  AValues.WriteString(cEndCommentKey, FView.EndComment.Text);
  AValues.WriteString(cReviewCommentKey, FView.ReviewComment.Text);
  AValues.WriteString(cEndStatesKey,
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FView.EndStates.Text)));
  AValues.WriteString(cEndFieldsKey,
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FView.EndFields.Text)));
  AValues.WriteString(cReviewStatesKey,
    TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FView.ReviewStates.Text)));
  AValues.WriteString(cStateFieldKey, FView.StateField.Value);
  AValues.WriteString(cAssigneeFieldKey, FView.AssigneeField.Value);
  AValues.WriteString(cStartStateKey, FView.StartState.Value);
  AValues.WriteString(cProjectKey, Trim(FView.Project.Value));
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
    FView.ValuesNote.Caption := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesValuesNoConnection);
    Exit;
  end;
  // Zustände zum Feld der Verbindung, sonst zum globalen Feld.
  mField := mConnection.StateField;
  if mField = '' then
  begin
    mField := FView.StateField.Value;
  end;
  // Optionen des Statusfeldes zum Projekt der Verbindung, sonst zum globalen (#2134).
  if mConnection.GitHubProject = '' then
  begin
    mConnection.GitHubProject := Trim(FView.Project.Value);
  end;
  FView.ValuesNote.Caption := TAtlasOptionsStrings.Text(TAtlasOptionsTextId.SettingsIssuesValuesLoading);
  FView.LoadValues.Enabled := False;
  FHooks.OnValues(mConnection, mField);
end;

class function TAtlasTrackerWorkflowPart.StartValues(const AValues: TAtlasTrackerValueSet;
  AInProject: Boolean): TArray<string>;
begin
  Result := AValues.States;
  if AInProject and (Length(AValues.ProjectStates) > 0) then
  begin
    Result := AValues.ProjectStates;
  end;
end;

procedure TAtlasTrackerWorkflowPart.ValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
begin
  FView.LoadValues.Enabled := True;
  if AError <> '' then
  begin
    FView.ValuesNote.Caption := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesValuesFailed, [AError]);
    Exit;
  end;
  // Vorschläge für die globalen Felder; eingegebene Texte bleiben.
  FView.StateField.SetValues(AValues.StateFields);
  FView.AssigneeField.SetValues(AValues.UserFields);
  FView.Project.SetValues(AValues.Projects);
  FView.StartState.SetValues(StartValues(AValues, FView.StateTarget.Choice = 0));
  FView.ValuesNote.Caption := TAtlasOptionsStrings.Fmt(TAtlasOptionsTextId.SettingsIssuesValuesLoaded,
    [Length(AValues.States), Length(AValues.StateFields) + Length(AValues.UserFields)]);
end;

end.
