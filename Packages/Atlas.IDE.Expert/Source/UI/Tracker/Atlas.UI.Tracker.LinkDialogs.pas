unit Atlas.UI.Tracker.LinkDialogs;

// Dialoge zu Abhängigkeiten und Unteraufgaben (#1279), reine VCL ohne Open
// Tools API:
// - TAtlasSubtaskDialog „Unteraufgabe zu ATL-12 anlegen“: Projekt
//   (vorbelegt, das des übergeordneten Issues), Titel, Beschreibung als
//   Markdown; „Anlegen“ erst mit Titel. Gesendet wird vom Aufrufer.
// - TAtlasIssueLinkDialog „ATL-12 verknüpfen“: Art („ATL-12 hängt ab von …“
//   bzw. „ATL-12 blockiert …“) und Kennung des anderen Issues; „Verknüpfen“
//   erst mit gültiger Kennung, die nicht das Issue selbst ist.
// - TAtlasBlockedPrompt: Rückfrage beim Beginnen „ATL-129 blockiert dieses
//   Issue und ist noch offen“ mit „Trotzdem beginnen“, „ATL-129 ansehen“ und
//   Abbrechen.
// Die Suche nach Issues (#1270) ersetzt später das Kennungsfeld; bis dahin
// nimmt es Kennung oder Adresse wie „Issue anzeigen …“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Tracker.Contract;

type
  TAtlasSubtaskDialog = class(TForm)
  private
    FProject: TLabel;
    FTitleLabel: TLabel;
    FTitle: TEdit;
    FDescriptionLabel: TLabel;
    FDescription: TMemo;
    FOk: TButton;
    FCancel: TButton;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabel(const ACaption: string; ATop: Integer): TLabel;
    procedure TitleChange(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    /// <summary>AParentKey: übergeordnetes Issue; AProject: Projekt, in dem die Unteraufgabe entsteht.</summary>
    constructor CreateDialog(AOwner: TComponent; const AParentKey, AProject: string);
    /// <summary>Titel ohne Leerraum am Rand.</summary>
    function IssueTitle: string;
    function Description: string;
    /// <summary>Zeigt den Dialog modal; True mit Titel und Beschreibung.</summary>
    class function Execute(const AParentKey, AProject: string; out ATitle, ADescription: string): Boolean; static;
    property ProjectLabel: TLabel read FProject;
    property TitleEdit: TEdit read FTitle;
    property DescriptionMemo: TMemo read FDescription;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
  end;

  TAtlasIssueLinkDialog = class(TForm)
  private
    FKey: string;
    FProvider: string;
    FDependsOn: TRadioButton;
    FBlocks: TRadioButton;
    FOtherLabel: TLabel;
    FOther: TEdit;
    FOk: TButton;
    FCancel: TButton;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure OtherChange(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    /// <summary>AKey: das gezeigte Issue; AProvider: "github" bzw. "youtrack" (Form der Kennung).</summary>
    constructor CreateDialog(AOwner: TComponent; const AKey, AProvider: string);
    /// <summary>Kennung des anderen Issues; '' ungültig oder das Issue selbst.</summary>
    function OtherKey: string;
    /// <summary>DependsOn oder Blocks.</summary>
    function Kind: TAtlasTrackerLinkKind;
    /// <summary>Zeigt den Dialog modal; True mit Art und Kennung.</summary>
    class function Execute(const AKey, AProvider: string; out AKind: TAtlasTrackerLinkKind;
      out AOtherKey: string): Boolean; static;
    property DependsOnButton: TRadioButton read FDependsOn;
    property BlocksButton: TRadioButton read FBlocks;
    property OtherEdit: TEdit read FOther;
    property OkButton: TButton read FOk;
  end;

{$SCOPEDENUMS ON}
  TAtlasBlockedChoice = (Cancel, StartAnyway, ShowBlocker);
{$SCOPEDENUMS OFF}

  TAtlasBlockedPrompt = class
  public
    /// <summary>„ATL-129 blockiert dieses Issue und ist noch offen.“ bzw. „ATL-129 und 2 weitere blockieren …“;
    /// '' ohne Blocker.</summary>
    class function Text(const ABlockers: TArray<TAtlasTrackerLink>): string; static;
    /// <summary>Rückfrage zeigen; Cancel ohne Blocker.</summary>
    class function Ask(const ABlockers: TArray<TAtlasTrackerLink>): TAtlasBlockedChoice; static;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 520;

function Scaled(AForm: TForm; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AForm.CurrentPPI, 96);
end;

function MakeButton(AForm: TForm; AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
var
  mMeasure: TBitmap;
begin
  Result := TButton.Create(AForm);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  // Gemessen auf einer Bitmap: Das Formular hat im Konstruktor noch kein Fenster.
  mMeasure := TBitmap.Create;
  try
    mMeasure.Canvas.Font.Assign(AForm.Font);
    Result.Width := mMeasure.Canvas.TextWidth(ACaption) + Scaled(AForm, 32);
  finally
    mMeasure.Free;
  end;
  if Result.Width < Scaled(AForm, 90) then
    Result.Width := Scaled(AForm, 90);
  Result.Top := Scaled(AForm, Gap);
  Result.Height := Scaled(AForm, 28);
  Result.Anchors := [akTop, akRight];
end;

procedure SetupForm(AForm: TForm; const ACaption: string);
begin
  AForm.Caption := ACaption;
  AForm.BorderStyle := bsDialog;
  AForm.BorderIcons := [biSystemMenu];
  AForm.Position := poMainFormCenter;
  AForm.Font.Name := 'Segoe UI';
  AForm.Font.Size := 9;
  AForm.ClientWidth := Scaled(AForm, DialogWidth);
end;

function AddBottom(AForm: TForm): TPanel;
begin
  Result := TPanel.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alBottom;
  Result.Height := Scaled(AForm, 44);
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
end;

{ TAtlasSubtaskDialog }

constructor TAtlasSubtaskDialog.CreateDialog(AOwner: TComponent; const AParentKey, AProject: string);
var
  mBottom: TPanel;
begin
  inherited CreateNew(AOwner);
  SetupForm(Self, TAtlasStrings.Fmt(TAtlasTextId.IssueSubtaskTitle, [AParentKey]));
  FProject := AddLabel(TAtlasStrings.Fmt(TAtlasTextId.IssueSubtaskProject, [AProject]), 0);
  FTitleLabel := AddLabel(TAtlasStrings.Text(TAtlasTextId.IssueSubtaskSummary), 100);

  FTitle := TEdit.Create(Self);
  FTitle.Parent := Self;
  FTitle.Align := alTop;
  FTitle.AlignWithMargins := True;
  FTitle.Margins.SetBounds(Gap, 0, Gap, 0);
  FTitle.Top := 200;
  FTitle.MaxLength := TAtlasTrackerIssue.MaxTitle;
  FTitle.OnChange := TitleChange;
  FTitleLabel.FocusControl := FTitle;

  FDescriptionLabel := AddLabel(TAtlasStrings.Text(TAtlasTextId.IssueSubtaskDescription), 300);
  FDescription := TMemo.Create(Self);
  FDescription.Parent := Self;
  FDescription.Align := alTop;
  FDescription.AlignWithMargins := True;
  FDescription.Margins.SetBounds(Gap, 0, Gap, 0);
  FDescription.Top := 400;
  FDescription.Height := ScaleValue(140);
  FDescription.ScrollBars := ssVertical;
  FDescription.WantReturns := True;
  FDescriptionLabel.FocusControl := FDescription;

  mBottom := AddBottom(Self);
  FCancel := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.IssueDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.IssueSubtaskOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);

  ClientHeight := FDescription.Top + FDescription.Height + ScaleValue(Gap) + mBottom.Height;
  ActiveControl := FTitle;
  TitleChange(FTitle);
end;

function TAtlasSubtaskDialog.AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := MakeButton(Self, AParent, ACaption, AClick);
end;

function TAtlasSubtaskDialog.AddLabel(const ACaption: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap, Gap, Gap div 2);
  Result.Top := ATop;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

function TAtlasSubtaskDialog.IssueTitle: string;
begin
  Result := Trim(FTitle.Text);
end;

function TAtlasSubtaskDialog.Description: string;
begin
  Result := TrimRight(FDescription.Lines.Text);
end;

procedure TAtlasSubtaskDialog.TitleChange(Sender: TObject);
begin
  FOk.Enabled := IssueTitle <> '';
end;

procedure TAtlasSubtaskDialog.OkClick(Sender: TObject);
begin
  if IssueTitle = '' then
    Exit;
  ModalResult := mrOk;
end;

procedure TAtlasSubtaskDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasSubtaskDialog.Execute(const AParentKey, AProject: string; out ATitle,
  ADescription: string): Boolean;
var
  mDialog: TAtlasSubtaskDialog;
begin
  ATitle := '';
  ADescription := '';
  mDialog := TAtlasSubtaskDialog.CreateDialog(nil, AParentKey, AProject);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      ATitle := mDialog.IssueTitle;
      ADescription := mDialog.Description;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasIssueLinkDialog }

constructor TAtlasIssueLinkDialog.CreateDialog(AOwner: TComponent; const AKey, AProvider: string);
var
  mBottom: TPanel;
begin
  inherited CreateNew(AOwner);
  FKey := AKey;
  FProvider := AProvider;
  SetupForm(Self, TAtlasStrings.Fmt(TAtlasTextId.IssueLinkTitle, [AKey]));

  FDependsOn := TRadioButton.Create(Self);
  FDependsOn.Parent := Self;
  FDependsOn.Align := alTop;
  FDependsOn.AlignWithMargins := True;
  FDependsOn.Margins.SetBounds(Gap, Gap, Gap, 0);
  FDependsOn.Top := 0;
  FDependsOn.Caption := TAtlasStrings.Fmt(TAtlasTextId.IssueLinkDependsOn, [AKey]);
  FDependsOn.Checked := True;

  FBlocks := TRadioButton.Create(Self);
  FBlocks.Parent := Self;
  FBlocks.Align := alTop;
  FBlocks.AlignWithMargins := True;
  FBlocks.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  FBlocks.Top := 100;
  FBlocks.Caption := TAtlasStrings.Fmt(TAtlasTextId.IssueLinkBlocks, [AKey]);

  FOtherLabel := TLabel.Create(Self);
  FOtherLabel.Parent := Self;
  FOtherLabel.Align := alTop;
  FOtherLabel.AlignWithMargins := True;
  FOtherLabel.Margins.SetBounds(Gap, Gap, Gap, Gap div 2);
  FOtherLabel.Top := 200;
  FOtherLabel.ShowAccelChar := False;
  FOtherLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.IssueLinkKey, [TAtlasIssuePreview.KeyExample(AProvider)]);

  FOther := TEdit.Create(Self);
  FOther.Parent := Self;
  FOther.Align := alTop;
  FOther.AlignWithMargins := True;
  FOther.Margins.SetBounds(Gap, 0, Gap, 0);
  FOther.Top := 300;
  FOther.OnChange := OtherChange;
  FOtherLabel.FocusControl := FOther;

  mBottom := AddBottom(Self);
  FCancel := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.IssueDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(mBottom, TAtlasStrings.Text(TAtlasTextId.IssueLinkOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);

  ClientHeight := FOther.Top + FOther.Height + ScaleValue(Gap) + mBottom.Height;
  ActiveControl := FOther;
  OtherChange(FOther);
end;

function TAtlasIssueLinkDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := MakeButton(Self, AParent, ACaption, AClick);
end;

function TAtlasIssueLinkDialog.OtherKey: string;
begin
  Result := TAtlasIssuePreview.KeyOf(FProvider, FOther.Text);
  if SameText(Result, FKey) then
    Result := '';
end;

function TAtlasIssueLinkDialog.Kind: TAtlasTrackerLinkKind;
begin
  if FBlocks.Checked then
    Result := TAtlasTrackerLinkKind.Blocks
  else
    Result := TAtlasTrackerLinkKind.DependsOn;
end;

procedure TAtlasIssueLinkDialog.OtherChange(Sender: TObject);
begin
  FOk.Enabled := OtherKey <> '';
end;

procedure TAtlasIssueLinkDialog.OkClick(Sender: TObject);
begin
  if OtherKey = '' then
    Exit;
  ModalResult := mrOk;
end;

procedure TAtlasIssueLinkDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasIssueLinkDialog.Execute(const AKey, AProvider: string; out AKind: TAtlasTrackerLinkKind;
  out AOtherKey: string): Boolean;
var
  mDialog: TAtlasIssueLinkDialog;
begin
  AKind := TAtlasTrackerLinkKind.DependsOn;
  AOtherKey := '';
  mDialog := TAtlasIssueLinkDialog.CreateDialog(nil, AKey, AProvider);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AKind := mDialog.Kind;
      AOtherKey := mDialog.OtherKey;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasBlockedPrompt }

class function TAtlasBlockedPrompt.Text(const ABlockers: TArray<TAtlasTrackerLink>): string;
begin
  Result := '';
  if Length(ABlockers) = 1 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssueBlockedOne, [ABlockers[0].Key])
  else if Length(ABlockers) > 1 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.IssueBlockedMore, [ABlockers[0].Key, Length(ABlockers) - 1]);
end;

class function TAtlasBlockedPrompt.Ask(const ABlockers: TArray<TAtlasTrackerLink>): TAtlasBlockedChoice;
const
  AnswerStart = 100;
  AnswerShow = 101;
var
  mDialog: TTaskDialog;
  mButton: TTaskDialogBaseButtonItem;
begin
  Result := TAtlasBlockedChoice.Cancel;
  if Length(ABlockers) = 0 then
    Exit;
  mDialog := TTaskDialog.Create(nil);
  try
    mDialog.Caption := 'Atlas';
    mDialog.Title := TAtlasStrings.Text(TAtlasTextId.IssueBlockedCaption);
    mDialog.Text := Text(ABlockers);
    mDialog.MainIcon := tdiWarning;
    mDialog.CommonButtons := [tcbCancel];
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasStrings.Text(TAtlasTextId.IssueBlockedStart);
    mButton.ModalResult := AnswerStart;
    mButton := mDialog.Buttons.Add;
    mButton.Caption := TAtlasStrings.Fmt(TAtlasTextId.IssueBlockedShow, [ABlockers[0].Key]);
    mButton.ModalResult := AnswerShow;
    mButton.Default := True;
    if not mDialog.Execute then
      Exit;
    case mDialog.ModalResult of
      AnswerStart:
        Result := TAtlasBlockedChoice.StartAnyway;
      AnswerShow:
        Result := TAtlasBlockedChoice.ShowBlocker;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
