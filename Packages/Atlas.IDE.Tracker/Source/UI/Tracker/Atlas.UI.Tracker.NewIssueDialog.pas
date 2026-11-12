unit Atlas.UI.Tracker.NewIssueDialog;

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
  Atlas.Core.Tracker.NewIssue,
  Atlas.UI.Foundation.Dialog;

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
  private
    FDialog: TAtlasNewIssueDialog;
  public
    property Dialog: TAtlasNewIssueDialog read FDialog write FDialog;
  end;

  /// <summary>Steuerelemente des Dialogs und ihr Aufbau (Zeilen mit Beschriftung, Häkchen, Stand, Knöpfe).
  /// </summary>
  TAtlasNewIssueParts = class
  private
    FForm: TForm;
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
    function Scaled(AValue: Integer): Integer;
    function AddRow(const ACaption: string; AControl: TWinControl; AHeight: Integer): TPanel;
    function AddBox(const ACaption: string; AStyle: TComboBoxStyle): TAtlasNewIssueBox;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
    procedure CreateRows;
    procedure CreateOptions;
    procedure CreateStatus;
    procedure CreateButtons;
  public
    /// <summary>Baut alle Steuerelemente in AForm (Besitzer und Eltern ist AForm).</summary>
    constructor Create(AForm: TForm);
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
  end;

  TAtlasNewIssueDialog = class(TAtlasDialog)
  private
    FParts: TAtlasNewIssueParts;
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
    /// <summary>Vorbelegung aus FSetup in die Felder und Ereignisse verbinden.</summary>
    procedure ApplySetup;
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
    property Parts: TAtlasNewIssueParts read FParts;
    property Sending: Boolean read FSending;
    property IssueResult: TAtlasNewIssueResult read FResult;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Tracker.Strings;

const
  cGap = 8;
  cLabelWidth = 110;
  cDialogWidth = 640;
  cRowHeight = 30;
  cCodeFontName = 'Consolas';
  cMemoHeight = 120;
  cCheckHeight = 26;
  cOptionsHeight = 28;
  cControlTop = 4;
  cAssignToMeWidth = 180;
  cStartNowWidth = 200;
  cBottomHeight = 44;
  cStatusSpace = 40;
  cButtonExtra = 32;
  cButtonMinWidth = 90;
  cButtonHeight = 28;

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
  begin
    Exit;
  end;
  mText := Text;
  Items.BeginUpdate;
  try
    Items.Clear;
    for mValue in FValues do
    begin
      Items.Add(mValue);
    end;
  finally
    Items.EndUpdate;
  end;
  if Style = csDropDownList then
  begin
    ItemIndex := FChoice;
  end
  else
  begin
    Text := mText;
  end;
end;

procedure TAtlasNewIssueBox.CreateWnd;
var
  mText, mValue: string;
begin
  mText := Text;
  inherited CreateWnd;
  if Items.Count = 0 then
  begin
    for mValue in FValues do
    begin
      Items.Add(mValue);
    end;
  end;
  if Style = csDropDownList then
  begin
    ItemIndex := FChoice;
  end
  else
  begin
    Text := mText;
  end;
end;

procedure TAtlasNewIssueBox.DestroyWnd;
begin
  if Style = csDropDownList then
  begin
    FChoice := ItemIndex;
  end;
  inherited DestroyWnd;
end;

function TAtlasNewIssueBox.GetChoice: Integer;
begin
  if HandleAllocated then
  begin
    Result := ItemIndex;
  end
  else
  begin
    Result := FChoice;
  end;
end;

procedure TAtlasNewIssueBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
  begin
    ItemIndex := AValue;
  end;
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

{ TAtlasNewIssueParts }

constructor TAtlasNewIssueParts.Create(AForm: TForm);
begin
  inherited Create;
  FForm := AForm;
  CreateRows;
  CreateOptions;
  CreateStatus;
  CreateButtons;
end;

function TAtlasNewIssueParts.Scaled(AValue: Integer): Integer;
begin
  Result := FForm.ScaleValue(AValue);
end;

function TAtlasNewIssueParts.AddBox(const ACaption: string; AStyle: TComboBoxStyle): TAtlasNewIssueBox;
begin
  Result := TAtlasNewIssueBox.Create(FForm);
  Result.Style := AStyle;
  AddRow(ACaption, Result, cRowHeight);
end;

procedure TAtlasNewIssueParts.CreateRows;
begin
  FTracker := AddBox(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueTracker), csDropDownList);
  FProject := TEdit.Create(FForm);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueProject), FProject, cRowHeight);
  FTitle := TEdit.Create(FForm);
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueSummary), FTitle, cRowHeight);
  FDescription := TMemo.Create(FForm);
  FDescription.ScrollBars := ssVertical;
  FDescription.WantReturns := True;
  AddRow(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueDescription), FDescription, cMemoHeight);
  FIncludeCode := TCheckBox.Create(FForm);
  FIncludeCode.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueIncludeCode);
  AddRow('', FIncludeCode, cCheckHeight);
  FCode := TMemo.Create(FForm);
  FCode.ScrollBars := ssBoth;
  FCode.WordWrap := False;
  FCode.WantReturns := True;
  FCode.Font.Name := cCodeFontName;
  AddRow('', FCode, cMemoHeight);
  FType := AddBox(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueType), csDropDown);
  FPriority := AddBox(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssuePriority), csDropDown);
  FAssignee := AddBox(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueAssignee), csDropDown);
end;

procedure TAtlasNewIssueParts.CreateOptions;
var
  mOptions: TPanel;
begin
  mOptions := TPanel.Create(FForm);
  mOptions.Parent := FForm;
  mOptions.Align := alTop;
  mOptions.Top := FForm.ClientHeight;
  mOptions.Height := Scaled(cOptionsHeight);
  mOptions.BevelOuter := bvNone;
  FAssignToMe := TCheckBox.Create(FForm);
  FAssignToMe.Parent := mOptions;
  FAssignToMe.Left := Scaled(cGap + cLabelWidth);
  FAssignToMe.Top := Scaled(cControlTop);
  FAssignToMe.Width := Scaled(cAssignToMeWidth);
  FAssignToMe.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueAssignToMe);
  FStartNow := TCheckBox.Create(FForm);
  FStartNow.Parent := mOptions;
  FStartNow.Left := FAssignToMe.Left + FAssignToMe.Width + Scaled(cGap);
  FStartNow.Top := Scaled(cControlTop);
  FStartNow.Width := Scaled(cStartNowWidth);
  FStartNow.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueStartNow);
end;

procedure TAtlasNewIssueParts.CreateStatus;
begin
  FStatus := TLabel.Create(FForm);
  FStatus.Parent := FForm;
  FStatus.Align := alTop;
  FStatus.Top := FForm.ClientHeight;
  FStatus.AlignWithMargins := True;
  FStatus.Margins.SetBounds(Scaled(cGap + cLabelWidth), Scaled(cControlTop), Scaled(cGap), Scaled(cControlTop));
  FStatus.WordWrap := True;
  FStatus.ShowAccelChar := False;
  FStatus.Caption := '';
end;

procedure TAtlasNewIssueParts.CreateButtons;
var
  mBottom: TPanel;
begin
  mBottom := TPanel.Create(FForm);
  mBottom.Parent := FForm;
  mBottom.Align := alBottom;
  mBottom.Height := Scaled(cBottomHeight);
  mBottom.BevelOuter := bvNone;
  FCancel := AddButton(mBottom, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueCancel));
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - Scaled(cGap);
  FCreate := AddButton(mBottom, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueCreate));
  FCreate.Left := FCancel.Left - FCreate.Width - Scaled(cGap);
  // Kein Default-Knopf: Enter in der Beschreibung ist ein Zeilenumbruch, nie ein Senden.
  FForm.ClientHeight := FStatus.Top + Scaled(cStatusSpace) + mBottom.Height;
  FForm.Constraints.MinWidth := FForm.Width;
  FForm.Constraints.MinHeight := FForm.Height;
end;

function TAtlasNewIssueParts.AddRow(const ACaption: string; AControl: TWinControl; AHeight: Integer): TPanel;
var
  mLabel: TLabel;
begin
  Result := TPanel.Create(FForm);
  Result.Parent := FForm;
  Result.Align := alTop;
  Result.Top := FForm.ClientHeight;
  Result.Height := Scaled(AHeight);
  Result.BevelOuter := bvNone;
  AControl.Parent := Result;
  AControl.Left := Scaled(cGap + cLabelWidth);
  AControl.Top := Scaled(cControlTop);
  AControl.Width := Result.ClientWidth - AControl.Left - Scaled(cGap);
  if AHeight > cRowHeight then
  begin
    AControl.Height := Result.ClientHeight - Scaled(cGap);
    AControl.Anchors := [akLeft, akTop, akRight, akBottom];
  end
  else
  begin
    AControl.Anchors := [akLeft, akTop, akRight];
  end;
  if ACaption <> '' then
  begin
    mLabel := TLabel.Create(FForm);
    mLabel.Parent := Result;
    mLabel.Left := Scaled(cGap);
    mLabel.Top := Scaled(cGap);
    mLabel.Caption := ACaption;
    mLabel.ShowAccelChar := False;
    mLabel.FocusControl := AControl;
  end;
end;

function TAtlasNewIssueParts.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(FForm);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  FForm.Canvas.Font := FForm.Font;
  Result.Width := Max(FForm.Canvas.TextWidth(ACaption) + Scaled(cButtonExtra), Scaled(cButtonMinWidth));
  Result.Top := Scaled(cGap div 2);
  Result.Height := Scaled(cButtonHeight);
  Result.Anchors := [akTop, akRight];
end;

{ TAtlasNewIssueDialog }

constructor TAtlasNewIssueDialog.CreateDialog(AOwner: TComponent; const ASetup: TAtlasNewIssueSetup;
  const AOnLoad: TAtlasNewIssueLoadEvent; const AOnSend: TAtlasNewIssueSendEvent);
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FSetup := ASetup;
  FOnLoad := AOnLoad;
  FOnSend := AOnSend;
  FFields := TAtlasNewIssueFields.Empty;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
  FLink := TAtlasNewIssueLink.Create;
  FLink.Dialog := Self;
  FLinkRef := FLink;
  Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueDialogTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  OnCloseQuery := FormCloseQuery;
  FParts := TAtlasNewIssueParts.Create(Self);
  FParts.CancelButton.OnClick := CancelClick;
  FParts.CreateButton.OnClick := CreateClick;
  ApplySetup;
  Changed(nil);
end;

procedure TAtlasNewIssueDialog.ApplySetup;
var
  mTracker: TAtlasNewIssueTracker;
  mCaptions: TArray<string>;
begin
  mCaptions := nil;
  for mTracker in FSetup.Trackers do
  begin
    mCaptions := mCaptions + [mTracker.Caption];
  end;
  FParts.TrackerBox.SetValues(mCaptions);
  if (FSetup.TrackerIndex >= 0) and (FSetup.TrackerIndex <= High(FSetup.Trackers)) then
  begin
    FParts.TrackerBox.Choice := FSetup.TrackerIndex;
  end
  else if Length(FSetup.Trackers) > 0 then
  begin
    FParts.TrackerBox.Choice := 0;
  end;
  if FParts.TrackerBox.Choice >= 0 then
  begin
    FParts.ProjectEdit.Text := FSetup.Trackers[FParts.TrackerBox.Choice].Target.Project;
  end;
  FParts.TitleEdit.Text := FSetup.Title;
  FParts.DescriptionMemo.Text := StringReplace(FSetup.Description, #10, sLineBreak, [rfReplaceAll]);
  FParts.CodeMemo.Text := StringReplace(FSetup.Code, #10, sLineBreak, [rfReplaceAll]);
  FParts.IncludeCodeBox.Checked := FSetup.IncludeCode and (Trim(FSetup.Code) <> '');
  FParts.IncludeCodeBox.Enabled := Trim(FSetup.Code) <> '';
  FParts.StartNowBox.Enabled := FSetup.CanStart;
  FParts.TrackerBox.OnChange := TrackerChange;
  FParts.TitleEdit.OnChange := Changed;
  FParts.ProjectEdit.OnChange := Changed;
  FParts.IncludeCodeBox.OnClick := Changed;
  FParts.AssignToMeBox.OnClick := Changed;
  if FSetup.Title = '' then
  begin
    ActiveControl := FParts.TitleEdit;
  end
  else
  begin
    ActiveControl := FParts.DescriptionMemo;
  end;
end;

destructor TAtlasNewIssueDialog.Destroy;
begin
  // Antworten, die danach kommen, finden keinen Dialog mehr.
  if FLink <> nil then
  begin
    FLink.Dialog := nil;
  end;
  FLinkRef := nil;
  ClearFields;
  // Die Steuerelemente gehören dem Formular; hier geht nur die Hülle.
  FreeAndNil(FParts);
  inherited Destroy;
end;

procedure TAtlasNewIssueDialog.ClearFields;
begin
  FSetup := TAtlasNewIssueSetup.Empty;
  FFields := TAtlasNewIssueFields.Empty;
  FResult := TAtlasNewIssueResult.Create(TAtlasNewIssueOutcome.NotConfigured);
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
  mIndex := FParts.TrackerBox.Choice;
  Result := (mIndex >= 0) and (mIndex <= High(FSetup.Trackers));
  if not Result then
  begin
    ATarget := TAtlasTrackerTarget.Create('', '', '', '');
    Exit;
  end;
  ATarget := FSetup.Trackers[mIndex].Target;
  // Projekt aus dem Feld; Create normiert (GitHub owner/repo, Schrägstriche).
  mLanguage := ATarget.Language;
  ATarget := TAtlasTrackerTarget.Create(ATarget.Provider, ATarget.Url, FParts.ProjectEdit.Text, ATarget.Query);
  ATarget.Language := mLanguage;
end;

function TAtlasNewIssueDialog.Draft: TAtlasNewIssueDraft;
begin
  Result := TAtlasNewIssueDraft.Empty;
  Result.Title := Trim(FParts.TitleEdit.Text);
  Result.Description := TAtlasNewIssues.Compose(FParts.DescriptionMemo.Text, FParts.CodeMemo.Text,
    FParts.IncludeCodeBox.Checked);
  Result.IssueType := Trim(FParts.TypeBox.Text);
  Result.Priority := Trim(FParts.PriorityBox.Text);
  Result.Assignee := Trim(FParts.AssigneeBox.Text);
  Result.AssignToMe := FParts.AssignToMeBox.Checked;
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
  FParts.CreateButton.Enabled := not FSending and mHasTarget and (Trim(FParts.TitleEdit.Text) <> '') and
    Assigned(FOnSend);
  FParts.CancelButton.Enabled := not FSending;
  FParts.CodeMemo.Enabled := FParts.IncludeCodeBox.Checked;
  FParts.AssigneeBox.Enabled := not FParts.AssignToMeBox.Checked;
  if not FSending and (Length(FSetup.Trackers) = 0) then
  begin
    FParts.StatusLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueNoTracker);
  end;
end;

procedure TAtlasNewIssueDialog.TrackerChange(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FParts.TrackerBox.Choice;
  if (mIndex >= 0) and (mIndex <= High(FSetup.Trackers)) then
  begin
    FParts.ProjectEdit.Text := FSetup.Trackers[mIndex].Target.Project;
  end;
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
  begin
    Exit;
  end;
  Inc(FLoadTicket);
  mTicket := FLoadTicket;
  mLinkRef := FLinkRef;
  mLink := FLink;
  FParts.StatusLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueLoading);
  FOnLoad(mTarget,
    procedure(const AFields: TAtlasNewIssueFields; ALoaded: Boolean)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) and (mLink.Dialog.FLoadTicket = mTicket) then
      begin
        mLink.Dialog.ShowFields(AFields, ALoaded);
      end;
    end);
end;

procedure TAtlasNewIssueDialog.ShowFields(const AFields: TAtlasNewIssueFields; ALoaded: Boolean);
begin
  FFields := AFields;
  FParts.TypeBox.SetValues(AFields.Types);
  FParts.PriorityBox.SetValues(AFields.Priorities);
  FParts.AssigneeBox.SetValues(AFields.Assignees);
  if FSending then
  begin
    Exit;
  end;
  if ALoaded then
  begin
    FParts.StatusLabel.Caption := '';
  end
  else
  begin
    FParts.StatusLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueLoadFailed);
  end;
end;

procedure TAtlasNewIssueDialog.CreateClick(Sender: TObject);
var
  mTarget: TAtlasTrackerTarget;
  mLinkRef: IInterface;
  mLink: TAtlasNewIssueLink;
begin
  if FSending or not Assigned(FOnSend) or not Target(mTarget) then
  begin
    Exit;
  end;
  if Trim(FParts.TitleEdit.Text) = '' then
  begin
    FParts.StatusLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueNoTitle);
    Exit;
  end;
  FSending := True;
  FParts.StatusLabel.Caption := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueSending);
  Changed(Sender);
  mLinkRef := FLinkRef;
  mLink := FLink;
  FOnSend(mTarget, Draft,
    procedure(const AResult: TAtlasNewIssueResult)
    begin
      if (mLinkRef <> nil) and (mLink.Dialog <> nil) then
      begin
        mLink.Dialog.ShowResult(AResult);
      end;
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
  FParts.StatusLabel.Caption := ResultText(AResult, mTarget.Project, mTarget.Server);
  Changed(nil);
end;

class function TAtlasNewIssueDialog.ResultText(const AResult: TAtlasNewIssueResult;
  const AProject, AServer: string): string;
begin
  case AResult.Outcome of
    TAtlasNewIssueOutcome.Created:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueCreated, [AResult.Key]);
    TAtlasNewIssueOutcome.NoToken:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueNoToken, [AServer]);
    TAtlasNewIssueOutcome.NotConfigured:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueNotConfigured);
    TAtlasNewIssueOutcome.Rejected:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueRejected, [AResult.HttpStatus]);
    TAtlasNewIssueOutcome.ProjectUnknown:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueProjectUnknown, [AProject]);
    TAtlasNewIssueOutcome.Invalid:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueInvalid, [AResult.TrackerMessage]);
    TAtlasNewIssueOutcome.Unreadable:
      Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueUnreadable);
    TAtlasNewIssueOutcome.ServerError:
      Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.NewIssueServerError, [AResult.HttpStatus]);
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.NewIssueUnreachable);
  end;
end;

procedure TAtlasNewIssueDialog.CancelClick(Sender: TObject);
begin
  if FSending then
  begin
    Exit;
  end;
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
      AStartNow := mDialog.Parts.StartNowBox.Checked and mDialog.Parts.StartNowBox.Enabled;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
