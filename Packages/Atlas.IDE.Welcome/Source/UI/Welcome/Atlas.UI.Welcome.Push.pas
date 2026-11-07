unit Atlas.UI.Welcome.Push;

// Rückfrage vor „Push …“ im Bereich „Nicht gesichert“ (#762), ohne Open
// Tools API: zeigt je Branch das Ziel (Remote und Branch dort, bei einem
// Branch ohne Upstream mit Hinweis „neu, wird verfolgter Branch“) und die
// Commits, die auf den Server gehen. Gepusht wird nur mit „Pushen“; Vorgabe-
// und Abbruch-Taste ist „Abbrechen“, Enter oder Esc pushen also nie.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Welcome.Unsaved;

type
  TAtlasPushDialog = class(TForm)
  public const
    cDialogWidth = 560;
    cDetailsHeight = 220;
  private
    FIntro: TLabel;
    FDetails: TMemo;
    FPush: TButton;
    FCancel: TButton;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
  public
    constructor CreateDialog(AOwner: TComponent; const AProjectName: string;
      const APlans: TArray<TAtlasUnsavedPush>);
    /// <summary>Ziel und Commits als Text, je Branch eine Kopfzeile und je Commit eine Zeile.</summary>
    class function DetailText(const APlans: TArray<TAtlasUnsavedPush>): string; static;
    /// <summary>Modal fragen; True nur nach „Pushen“. APrepare (darf nil sein) kann das Fenster vorher dem Thema
    /// der IDE anpassen.</summary>
    class function Confirm(const AProjectName: string; const APlans: TArray<TAtlasUnsavedPush>;
      const APrepare: TProc<TForm>): Boolean; static;
    property Intro: TLabel read FIntro;
    property Details: TMemo read FDetails;
    property PushButton: TButton read FPush;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Welcome.Strings;

const
  cGap = 8;

{ TAtlasPushDialog }

constructor TAtlasPushDialog.CreateDialog(AOwner: TComponent; const AProjectName: string;
  const APlans: TArray<TAtlasUnsavedPush>);
var
  mButtons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushTitle, [AProjectName]);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);

  FIntro := TLabel.Create(Self);
  FIntro.Parent := Self;
  FIntro.Align := alTop;
  FIntro.AlignWithMargins := True;
  FIntro.Margins.SetBounds(cGap, cGap, cGap, 0);
  FIntro.WordWrap := True;
  FIntro.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedPushIntro);

  FDetails := TMemo.Create(Self);
  FDetails.Parent := Self;
  FDetails.Align := alTop;
  FDetails.AlignWithMargins := True;
  FDetails.Margins.SetBounds(cGap, cGap, cGap, 0);
  FDetails.Top := FIntro.Top + FIntro.Height + 1;
  FDetails.Height := ScaleValue(cDetailsHeight);
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssBoth;
  FDetails.WordWrap := False;
  FDetails.Text := DetailText(APlans);

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FDetails.Top + FDetails.Height + 1;
  FPush := AddButton(mButtons, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedPushButton));
  FPush.ModalResult := mrOk;
  FCancel := AddButton(mButtons, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedPushCancel));
  FCancel.ModalResult := mrCancel;
  // Enter und Esc brechen ab: Gepusht wird nur mit einem bewussten Klick auf „Pushen“.
  FCancel.Default := True;
  FCancel.Cancel := True;
  ActiveControl := FCancel;
  ClientHeight := mButtons.Top + mButtons.Height + cGap;
end;

function TAtlasPushDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

class function TAtlasPushDialog.DetailText(const APlans: TArray<TAtlasUnsavedPush>): string;
var
  mLines: TStringList;
  mPlan: TAtlasUnsavedPush;
  mCommit: TAtlasVcsCommit;
begin
  mLines := TStringList.Create;
  try
    for mPlan in APlans do
    begin
      if mLines.Count > 0 then
      begin
        mLines.Add('');
      end;
      if mPlan.SetUpstream then
      begin
        mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushTargetNew,
          [mPlan.Branch, mPlan.Target,
          Length(mPlan.Commits)]));
      end
      else
      begin
        mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPushTarget, [mPlan.Branch, mPlan.Target,
          Length(mPlan.Commits)]));
      end;
      for mCommit in mPlan.Commits do
      begin
        mLines.Add('  ' + mCommit.ShortHash + '  ' + FormatDateTime('ddddd t',
          TTimeZone.Local.ToLocalTime(mCommit.Date)) + '  ' + mCommit.Summary);
      end;
      if mPlan.More then
      begin
        mLines.Add('  ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedPushMore));
      end;
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

class function TAtlasPushDialog.Confirm(const AProjectName: string; const APlans: TArray<TAtlasUnsavedPush>;
  const APrepare: TProc<TForm>): Boolean;
var
  mDialog: TAtlasPushDialog;
begin
  mDialog := TAtlasPushDialog.CreateDialog(nil, AProjectName, APlans);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

end.
