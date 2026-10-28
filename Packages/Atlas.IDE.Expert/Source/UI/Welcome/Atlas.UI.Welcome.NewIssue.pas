unit Atlas.UI.Welcome.NewIssue;

// Dialog „Issue anlegen“ (#1268) mit Vorschau des Textes, bevor etwas an den
// Tracker geht: Tracker (Klappliste bei mehreren Verbindungen), Projekt,
// Titel, Beschreibung (Markdown, bearbeitbar), Häkchen „Codeausschnitt
// mitsenden“ mit dem Ausschnitt darunter (Vorgabe aus
// issues.create.includeCode), Typ, Priorität und Zuständig (Listen vom
// Tracker, frei eintippbar), „mir zuweisen“ und „gleich beginnen“.
// - Gesendet wird nur mit „Anlegen“. Das Netz macht der Aufrufer im
//   Hintergrund (OnLoad für die Listen, OnSend für das Anlegen); die
//   Ergebnisse kommen im Hauptthread. Ist der Dialog dann schon zu, verfallen
//   sie (TAtlasNewIssueLink).
// - Schlägt das Anlegen fehl, bleibt der Dialog offen und nennt die Ursache;
//   der Aufrufer ändert am Code nichts. Während des Sendens lässt er sich
//   nicht schließen, damit kein Issue ohne Kennung im Code entsteht.
// Reine VCL; Kennung, TODO und Zwischenablage macht der Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.NewIssue;

type
  /// <summary>Ein Eintrag der Klappliste „Tracker“.</summary>
  TAtlasNewIssueTracker = record
    /// <summary>"YouTrack Firma", "GitHub · github.com".</summary>
    Caption: string;
    /// <summary>Anbieter, Adresse, Projekt und Sprache.</summary>
    Target: TAtlasTrackerTarget;
    class function Create(const ACaption: string; const ATarget: TAtlasTrackerTarget): TAtlasNewIssueTracker;
      static;
  end;

  /// <summary>Vorbelegung des Dialogs.</summary>
  TAtlasNewIssueSetup = record
    Trackers: TArray<TAtlasNewIssueTracker>;
    /// <summary>Vorgewählter Eintrag in Trackers (Zuordnung bzw. .atlas).</summary>
    TrackerIndex: Integer;
    Title: string;
    /// <summary>Beschreibung ohne Codeausschnitt.</summary>
    Description: string;
    Code: string;
    /// <summary>Häkchen „Codeausschnitt mitsenden“ (issues.create.includeCode).</summary>
    IncludeCode: Boolean;
    /// <summary>„gleich beginnen“ möglich (Bereich „Meine Issues“ an).</summary>
    CanStart: Boolean;
    class function Empty: TAtlasNewIssueSetup; static;
  end;

  TAtlasNewIssueFieldsDone = reference to procedure(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
  /// <summary>Listen des Trackers im Hintergrund laden; ADone im Hauptthread.</summary>
  TAtlasNewIssueLoadEvent = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const ADone: TAtlasNewIssueFieldsDone);
  TAtlasNewIssueSendDone = reference to procedure(const AResult: TAtlasNewIssueResult);
  /// <summary>Issue im Hintergrund anlegen; ADone im Hauptthread.</summary>
  TAtlasNewIssueSendEvent = reference to procedure(const ATarget: TAtlasTrackerTarget;
    const ADraft: TAtlasNewIssueDraft; const ADone: TAtlasNewIssueSendDone);

  TAtlasNewIssueDialog = class;

  /// <summary>Klappliste, deren Einträge erst mit Fenster in die Liste kommen (CreateWnd); Values und Choice gelten
  /// auch ohne Fenster.</summary>
  TAtlasNewIssueBox = class(TComboBox)
  private
    FValues: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Einträge setzen; ein eingetippter Text bleibt.</summary>
    procedure SetValues(const AValues: TArray<string>);
    property Values: TArray<string> read FValues;
    /// <summary>Gewählter Eintrag (csDropDownList), -1 = keiner.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

  /// <summary>Verbindung von laufenden Anfragen zum Dialog; nil, sobald der Dialog weg ist.</summary>
  TAtlasNewIssueLink = class(TInterfacedObject)
  public
    Dialog: TAtlasNewIssueDialog;
  end;

  TAtlasNewIssueDialog = class(TForm)
  private
    FTracker: TAtlasNewIssueBox;
    FProject: TEdit;
    FTitle: TEdit;
    FDescription: TMemo;
    FIncludeCode: TCheckBox;
    FCode: TMemo;
    FType: TAtlasNewIssueBox;
    FPriority: TAtlasNewIssueBox;
    FAssignee: TAtlasNewIssueBox;
    FAssignToMe: TCheckBox;
    FStartNow: TCheckBox;
    FStatus: TLabel;
    FCreate: TButton;
    FCancel: TButton;
    FSetup: TAtlasNewIssueSetup;
    FFields: TAtlasNewIssueFields;
    FResult: TAtlasNewIssueResult;
    FOnLoad: TAtlasNewIssueLoadEvent;
    FOnSend: TAtlasNewIssueSendEvent;
    FLink: TAtlasNewIssueLink;
    FLinkRef: IInterface;
    FSending: Boolean;
    /// <summary>Zählt Ladevorgänge; ein älteres Ergebnis nach einem Wechsel des Trackers verfällt.</summary>
    FLoadTicket: Integer;
    function AddRow(const ACaption: string; AControl: TWinControl; AHeight: Integer): TPanel;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure Changed(Sender: TObject);
    procedure TrackerChange(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ClearFields;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ASetup: TAtlasNewIssueSetup;
      const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent);
    destructor Destroy; override;
    /// <summary>Gewählter Tracker mit dem Projekt aus dem Feld; False ohne Tracker.</summary>
    function Target(out ATarget: TAtlasTrackerTarget): Boolean;
    /// <summary>Was „Anlegen“ sendet: Titel, Beschreibung (mit Codeausschnitt nur bei Häkchen), Felder.</summary>
    function Draft: TAtlasNewIssueDraft;
    /// <summary>Listen des Trackers für den gewählten Tracker laden (beim Anzeigen und nach einem Wechsel).
    /// </summary>
    procedure LoadFields;
    /// <summary>Listen übernehmen; was schon eingetippt ist, bleibt.</summary>
    procedure ShowFields(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
    /// <summary>Ergebnis von „Anlegen“: bei Erfolg schließt der Dialog mit mrOk, sonst bleibt er mit der Ursache.
    /// </summary>
    procedure ShowResult(const AResult: TAtlasNewIssueResult);
    /// <summary>Text zum Ergebnis; AProject für „Projekt unbekannt“, AServer für „kein Token“.</summary>
    class function ResultText(const AResult: TAtlasNewIssueResult; const AProject, AServer: string): string; static;
    /// <summary>Modal; True mit dem angelegten Issue in AResult, AStartNow für „gleich beginnen“.</summary>
    class function Execute(const ASetup: TAtlasNewIssueSetup; const AOnLoad: TAtlasNewIssueLoadEvent;
      const AOnSend: TAtlasNewIssueSendEvent; out AResult: TAtlasNewIssueResult; out AStartNow: Boolean): Boolean;
      static;
    property TrackerBox: TAtlasNewIssueBox read FTracker;
    property ProjectEdit: TEdit read FProject;
    property TitleEdit: TEdit read FTitle;
    property DescriptionMemo: TMemo read FDescription;
    property IncludeCodeBox: TCheckBox read FIncludeCode;
    property CodeMemo: TMemo read FCode;
    property TypeBox: TAtlasNewIssueBox read FType;
    property PriorityBox: TAtlasNewIssueBox read FPriority;
    property AssigneeBox: TAtlasNewIssueBox read FAssignee;
    property AssignToMeBox: TCheckBox read FAssignToMe;
    property StartNowBox: TCheckBox read FStartNow;
    property StatusLabel: TLabel read FStatus;
    property CreateButton: TButton read FCreate;
    property CancelButton: TButton read FCancel;
    property Sending: Boolean read FSending;
    property IssueResult: TAtlasNewIssueResult read FResult;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cGap = 8;
  cLabelWidth = 110;
  cDialogWidth = 640;
  cRowHeight = 30;

{ TAtlasNewIssueBox }

constructor TAtlasNewIssueBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChoice := -1;
end;

destructor TAtlasNewIssueBox.Destroy;
begin
  FValues := nil;
  inherited Destroy;
end;

procedure TAtlasNewIssueBox.SetValues(const AValues: TArray<string>);
var
  mText, mValue: string;
begin
  FValues := AValues;
  if not HandleAllocated then
    Exit;
  mText := Text;
  Items.BeginUpdate;
  try
    Items.Clear;
    for mValue in FValues do
      Items.Add(mValue);
  finally
    Items.EndUpdate;
  end;
  if Style = csDropDownList then
    ItemIndex := FChoice
  else
    Text := mText;
end;

procedure TAtlasNewIssueBox.CreateWnd;
var
  mText, mValue: string;
begin
  mText := Text;
  inherited CreateWnd;
  if Items.Count = 0 then
    for mValue in FValues do
      Items.Add(mValue);
  if Style = csDropDownList then
    ItemIndex := FChoice
  else
    Text := mText;
end;

procedure TAtlasNewIssueBox.DestroyWnd;
begin
  if Style = csDropDownList then
    FChoice := ItemIndex;
  inherited DestroyWnd;
end;

function TAtlasNewIssueBox.GetChoice: Integer;
begin
  if HandleAllocated then
    Result := ItemIndex
  else
    Result := FChoice;
end;

procedure TAtlasNewIssueBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
    ItemIndex := AValue;
end;

{ TAtlasNewIssueTracker }

class function TAtlasNewIssueTracker.Create(const ACaption: string;
  const ATarget: TAtlasTrackerTarget): TAtlasNewIssueTracker;
begin
  Result.Caption := ACaption;
  Result.Target := ATarget;
end;

{ TAtlasNewIssueSetup }

class function TAtlasNewIssueSetup.Empty: TAtlasNewIssueSetup;
begin
  Result := Default(TAtlasNewIssueSetup);
  Result.Trackers := nil;
  Result.IncludeCode := True;
end;

{ TAtlasNewIssueDialog }

constructor TAtlasNewIssueDialog.CreateDialog(AOwner: TComponent; const ASetup: TAtlasNewIssueSetup;
  const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent);
var
  mBottom, mOptions: TPanel;
  mTracker: TAtlasNewIssueTracker;
  mCaptions: TArray<string>;
begin
  inherited CreateNew(AOwner);
  FSetup := ASetup;
  FOnLoad := AOnLoad;
  FOnSend := AOnSend;
  FFields := TAtlasNewIssueFields.Empty;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  FLink := TAtlasNewIssueLink.Create;
  FLink.Dialog := Self;
  FLinkRef := FLink;
  Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueDialogTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  OnCloseQuery := FormCloseQuery;

  FTracker := TAtlasNewIssueBox.Create(Self);
  FTracker.Style := csDropDownList;
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueTracker), FTracker, cRowHeight);
  FProject := TEdit.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueProject), FProject, cRowHeight);
  FTitle := TEdit.Create(Self);
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueSummary), FTitle, cRowHeight);
  FDescription := TMemo.Create(Self);
  FDescription.ScrollBars := ssVertical;
  FDescription.WantReturns := True;
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueDescription), FDescription, 120);
  FIncludeCode := TCheckBox.Create(Self);
  FIncludeCode.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueIncludeCode);
  AddRow('', FIncludeCode, 26);
  FCode := TMemo.Create(Self);
  FCode.ScrollBars := ssBoth;
  FCode.WordWrap := False;
  FCode.WantReturns := True;
  FCode.Font.Name := 'Consolas';
  AddRow('', FCode, 120);
  FType := TAtlasNewIssueBox.Create(Self);
  FType.Style := csDropDown;
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueType), FType, cRowHeight);
  FPriority := TAtlasNewIssueBox.Create(Self);
  FPriority.Style := csDropDown;
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssuePriority), FPriority, cRowHeight);
  FAssignee := TAtlasNewIssueBox.Create(Self);
  FAssignee.Style := csDropDown;
  AddRow(TAtlasStrings.Text(TAtlasTextId.NewIssueAssignee), FAssignee, cRowHeight);

  mOptions := TPanel.Create(Self);
  mOptions.Parent := Self;
  mOptions.Align := alTop;
  mOptions.Top := ClientHeight;
  mOptions.Height := ScaleValue(28);
  mOptions.BevelOuter := bvNone;
  FAssignToMe := TCheckBox.Create(Self);
  FAssignToMe.Parent := mOptions;
  FAssignToMe.Left := ScaleValue(cGap + cLabelWidth);
  FAssignToMe.Top := ScaleValue(4);
  FAssignToMe.Width := ScaleValue(180);
  FAssignToMe.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueAssignToMe);
  FStartNow := TCheckBox.Create(Self);
  FStartNow.Parent := mOptions;
  FStartNow.Left := FAssignToMe.Left + FAssignToMe.Width + ScaleValue(cGap);
  FStartNow.Top := ScaleValue(4);
  FStartNow.Width := ScaleValue(200);
  FStartNow.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueStartNow);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.Top := ClientHeight;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(ScaleValue(cGap + cLabelWidth), ScaleValue(4), ScaleValue(cGap), ScaleValue(4));
  FStatus.WordWrap := True;
  FStatus.ShowAccelChar := False;
  FStatus.Caption := '';

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  FCancel := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.NewIssueCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FCreate := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.NewIssueCreate), CreateClick);
  FCreate.Left := FCancel.Left - FCreate.Width - ScaleValue(cGap);
  // Kein Default-Knopf: Enter in der Beschreibung ist ein Zeilenumbruch, nie ein Senden.
  ClientHeight := FStatus.Top + ScaleValue(40) + mBottom.Height;
  Constraints.MinWidth := Width;
  Constraints.MinHeight := Height;

  mCaptions := nil;
  for mTracker in FSetup.Trackers do
    mCaptions := mCaptions + [mTracker.Caption];
  FTracker.SetValues(mCaptions);
  if (FSetup.TrackerIndex >= 0) and (FSetup.TrackerIndex <= High(FSetup.Trackers)) then
    FTracker.Choice := FSetup.TrackerIndex
  else if Length(FSetup.Trackers) > 0 then
    FTracker.Choice := 0;
  if FTracker.Choice >= 0 then
    FProject.Text := FSetup.Trackers[FTracker.Choice].Target.Project;
  FTitle.Text := FSetup.Title;
  FDescription.Text := StringReplace(FSetup.Description, #10, sLineBreak, [rfReplaceAll]);
  FCode.Text := StringReplace(FSetup.Code, #10, sLineBreak, [rfReplaceAll]);
  FIncludeCode.Checked := FSetup.IncludeCode and (Trim(FSetup.Code) <> '');
  FIncludeCode.Enabled := Trim(FSetup.Code) <> '';
  FStartNow.Enabled := FSetup.CanStart;
  FTracker.OnChange := TrackerChange;
  FTitle.OnChange := Changed;
  FProject.OnChange := Changed;
  FIncludeCode.OnClick := Changed;
  FAssignToMe.OnClick := Changed;
  if FSetup.Title = '' then
    ActiveControl := FTitle
  else
    ActiveControl := FDescription;
  Changed(nil);
end;

destructor TAtlasNewIssueDialog.Destroy;
begin
  // Antworten, die danach kommen, finden keinen Dialog mehr.
  if FLink <> nil then
    FLink.Dialog := nil;
  FLinkRef := nil;
  ClearFields;
  inherited Destroy;
end;

procedure TAtlasNewIssueDialog.ClearFields;
begin
  FSetup := TAtlasNewIssueSetup.Empty;
  FFields := TAtlasNewIssueFields.Empty;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
end;

function TAtlasNewIssueDialog.AddRow(const ACaption: string; AControl: TWinControl; AHeight: Integer): TPanel;
var
  mLabel: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.Top := ClientHeight;
  Result.Height := ScaleValue(AHeight);
  Result.BevelOuter := bvNone;
  AControl.Parent := Result;
  AControl.Left := ScaleValue(cGap + cLabelWidth);
  AControl.Top := ScaleValue(4);
  AControl.Width := Result.ClientWidth - AControl.Left - ScaleValue(cGap);
  if AHeight > cRowHeight then
  begin
    AControl.Height := Result.ClientHeight - ScaleValue(8);
    AControl.Anchors := [akLeft, akTop, akRight, akBottom];
  end
  else
    AControl.Anchors := [akLeft, akTop, akRight];
  if ACaption = '' then
    Exit;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Result;
  mLabel.Left := ScaleValue(cGap);
  mLabel.Top := ScaleValue(cGap);
  mLabel.Caption := ACaption;
  mLabel.ShowAccelChar := False;
  mLabel.FocusControl := AControl;
end;

function TAtlasNewIssueDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  if Result.Width < ScaleValue(90) then
    Result.Width := ScaleValue(90);
  Result.Top := ScaleValue(cGap div 2);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

procedure TAtlasNewIssueDialog.DoShow;
begin
  inherited DoShow;
  LoadFields;
end;

function TAtlasNewIssueDialog.Target(out ATarget: TAtlasTrackerTarget): Boolean;
var
  mIndex: Integer;
  mLanguage: string;
begin
  mIndex := FTracker.Choice;
  Result := (mIndex >= 0) and (mIndex <= High(FSetup.Trackers));
  if not Result then
  begin
    ATarget := TAtlasTrackerTarget.Create('', '', '', '');
    Exit;
  end;
  ATarget := FSetup.Trackers[mIndex].Target;
  // Projekt aus dem Feld; Create normiert (GitHub owner/repo, Schrägstriche).
  mLanguage := ATarget.Language;
  ATarget := TAtlasTrackerTarget.Create(ATarget.Provider, ATarget.Url, FProject.Text, ATarget.Query);
  ATarget.Language := mLanguage;
end;

function TAtlasNewIssueDialog.Draft: TAtlasNewIssueDraft;
begin
  Result := TAtlasNewIssueDraft.Empty;
  Result.Title := Trim(FTitle.Text);
  Result.Description := TAtlasNewIssues.Compose(FDescription.Text, FCode.Text, FIncludeCode.Checked);
  Result.IssueType := Trim(FType.Text);
  Result.Priority := Trim(FPriority.Text);
  Result.Assignee := Trim(FAssignee.Text);
  Result.AssignToMe := FAssignToMe.Checked;
  Result.TypeField := FFields.TypeField;
  Result.PriorityField := FFields.PriorityField;
  Result.AssigneeField := FFields.AssigneeField;
end;

procedure TAtlasNewIssueDialog.Changed(Sender: TObject);
var
  mTarget: TAtlasTrackerTarget;
  mHasTarget: Boolean;
begin
  mHasTarget := Target(mTarget) and mTarget.Configured;
  FCreate.Enabled := not FSending and mHasTarget and (Trim(FTitle.Text) <> '') and Assigned(FOnSend);
  FCancel.Enabled := not FSending;
  FCode.Enabled := FIncludeCode.Checked;
  FAssignee.Enabled := not FAssignToMe.Checked;
  if not FSending and (Length(FSetup.Trackers) = 0) then
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueNoTracker);
end;

procedure TAtlasNewIssueDialog.TrackerChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FTracker.Choice;
  if (mIndex >= 0) and (mIndex <= High(FSetup.Trackers)) then
    FProject.Text := FSetup.Trackers[mIndex].Target.Project;
  Changed(Sender);
  LoadFields;
end;

procedure TAtlasNewIssueDialog.LoadFields;
var
  mTarget: TAtlasTrackerTarget;
  mLinkRef: IInterface;
  mLink: TAtlasNewIssueLink;
  mTicket: Integer;
begin
  if not Assigned(FOnLoad) or not Target(mTarget) or not mTarget.Configured then
    Exit;
  Inc(FLoadTicket);
  mTicket := FLoadTicket;
  mLinkRef := FLinkRef;
  mLink := FLink;
  FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueLoading);
  FOnLoad(mTarget,
    procedure(const AFields: TAtlasNewIssueFields; ALoaded: Boolean)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) and (mLink.Dialog.FLoadTicket = mTicket) then
        mLink.Dialog.ShowFields(AFields, ALoaded);
    end);
end;

procedure TAtlasNewIssueDialog.ShowFields(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
begin
  FFields := AFields;
  FType.SetValues(AFields.Types);
  FPriority.SetValues(AFields.Priorities);
  FAssignee.SetValues(AFields.Assignees);
  if FSending then
    Exit;
  if ALoaded then
    FStatus.Caption := ''
  else
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueLoadFailed);
end;

procedure TAtlasNewIssueDialog.CreateClick(Sender: TObject);
var
  mTarget: TAtlasTrackerTarget;
  mLinkRef: IInterface;
  mLink: TAtlasNewIssueLink;
begin
  if FSending or not Assigned(FOnSend) or not Target(mTarget) then
    Exit;
  if Trim(FTitle.Text) = '' then
  begin
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueNoTitle);
    Exit;
  end;
  FSending := True;
  FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.NewIssueSending);
  Changed(Sender);
  mLinkRef := FLinkRef;
  mLink := FLink;
  FOnSend(mTarget, Draft,
    procedure(const AResult: TAtlasNewIssueResult)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) then
        mLink.Dialog.ShowResult(AResult);
    end);
end;

procedure TAtlasNewIssueDialog.ShowResult(const AResult: TAtlasNewIssueResult);
var
  mTarget: TAtlasTrackerTarget;
begin
  FSending := False;
  FResult := AResult;
  if AResult.Outcome = TAtlasNewIssueOutcome.Created then
  begin
    ModalResult := mrOk;
    Exit;
  end;
  Target(mTarget);
  FStatus.Caption := ResultText(AResult, mTarget.Project, mTarget.Server);
  Changed(nil);
end;

class function TAtlasNewIssueDialog.ResultText(const AResult: TAtlasNewIssueResult;
  const AProject, AServer: string): string;
begin
  case AResult.Outcome of
    TAtlasNewIssueOutcome.Created:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueCreated, [AResult.Key]);
    TAtlasNewIssueOutcome.NoToken:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueNoToken, [AServer]);
    TAtlasNewIssueOutcome.NotConfigured:
      Result := TAtlasStrings.Text(TAtlasTextId.NewIssueNotConfigured);
    TAtlasNewIssueOutcome.Rejected:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueRejected, [AResult.HttpStatus]);
    TAtlasNewIssueOutcome.ProjectUnknown:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueProjectUnknown, [AProject]);
    TAtlasNewIssueOutcome.Invalid:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueInvalid, [AResult.TrackerMessage]);
    TAtlasNewIssueOutcome.Unreadable:
      Result := TAtlasStrings.Text(TAtlasTextId.NewIssueUnreadable);
    TAtlasNewIssueOutcome.ServerError:
      Result := TAtlasStrings.Fmt(TAtlasTextId.NewIssueServerError, [AResult.HttpStatus]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.NewIssueUnreachable);
  end;
end;

procedure TAtlasNewIssueDialog.CancelClick(Sender: TObject);
begin
  if FSending then
    Exit;
  ModalResult := mrCancel;
end;

procedure TAtlasNewIssueDialog.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // Während des Sendens nicht schließen: Sonst entstünde ein Issue, dessen Kennung nicht in den Code kommt.
  CanClose := not FSending;
end;

class function TAtlasNewIssueDialog.Execute(const ASetup: TAtlasNewIssueSetup;
  const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent; out AResult: TAtlasNewIssueResult;
  out AStartNow: Boolean): Boolean;
var
  mDialog: TAtlasNewIssueDialog;
begin
  AResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  AStartNow := False;
  mDialog := TAtlasNewIssueDialog.CreateDialog(nil, ASetup, AOnLoad, AOnSend);
  try
    Result := (mDialog.ShowModal = mrOk) and (mDialog.IssueResult.Outcome = TAtlasNewIssueOutcome.Created);
    if Result then
    begin
      AResult := mDialog.IssueResult;
      AStartNow := mDialog.StartNowBox.Checked and mDialog.StartNowBox.Enabled;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
