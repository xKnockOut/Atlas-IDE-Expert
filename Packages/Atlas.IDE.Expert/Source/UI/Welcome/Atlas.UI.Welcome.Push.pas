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
    DialogWidth = 560;
    DetailsHeight = 220;
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
  Atlas.UI.Strings;

const
  Gap = 8;

{ TAtlasPushDialog }

constructor TAtlasPushDialog.CreateDialog(AOwner: TComponent; const AProjectName: string;
  const APlans: TArray<TAtlasUnsavedPush>);
var
  Buttons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushTitle, [AProjectName]);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);

  FIntro := TLabel.Create(Self);
  FIntro.Parent := Self;
  FIntro.Align := alTop;
  FIntro.AlignWithMargins := True;
  FIntro.Margins.SetBounds(Gap, Gap, Gap, 0);
  FIntro.WordWrap := True;
  FIntro.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedPushIntro);

  FDetails := TMemo.Create(Self);
  FDetails.Parent := Self;
  FDetails.Align := alTop;
  FDetails.AlignWithMargins := True;
  FDetails.Margins.SetBounds(Gap, Gap, Gap, 0);
  FDetails.Top := FIntro.Top + FIntro.Height + 1;
  FDetails.Height := ScaleValue(DetailsHeight);
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssBoth;
  FDetails.WordWrap := False;
  FDetails.Text := DetailText(APlans);

  Buttons := TFlowPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.Align := alTop;
  Buttons.AutoSize := True;
  Buttons.BevelOuter := bvNone;
  Buttons.AlignWithMargins := True;
  Buttons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  Buttons.Top := FDetails.Top + FDetails.Height + 1;
  FPush := AddButton(Buttons, TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedPushButton));
  FPush.ModalResult := mrOk;
  FCancel := AddButton(Buttons, TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedPushCancel));
  FCancel.ModalResult := mrCancel;
  // Enter und Esc brechen ab: Gepusht wird nur mit einem bewussten Klick auf „Pushen“.
  FCancel.Default := True;
  FCancel.Cancel := True;
  ActiveControl := FCancel;
  ClientHeight := Buttons.Top + Buttons.Height + Gap;
end;

function TAtlasPushDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

class function TAtlasPushDialog.DetailText(const APlans: TArray<TAtlasUnsavedPush>): string;
var
  Lines: TStringList;
  Plan: TAtlasUnsavedPush;
  Commit: TAtlasVcsCommit;
begin
  Lines := TStringList.Create;
  try
    for Plan in APlans do
    begin
      if Lines.Count > 0 then
        Lines.Add('');
      if Plan.SetUpstream then
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushTargetNew, [Plan.Branch, Plan.Target,
          Length(Plan.Commits)]))
      else
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPushTarget, [Plan.Branch, Plan.Target,
          Length(Plan.Commits)]));
      for Commit in Plan.Commits do
        Lines.Add('  ' + Commit.ShortHash + '  ' + FormatDateTime('ddddd t',
          TTimeZone.Local.ToLocalTime(Commit.Date)) + '  ' + Commit.Summary);
      if Plan.More then
        Lines.Add('  ' + TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedPushMore));
    end;
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasPushDialog.Confirm(const AProjectName: string; const APlans: TArray<TAtlasUnsavedPush>;
  const APrepare: TProc<TForm>): Boolean;
var
  Dialog: TAtlasPushDialog;
begin
  Dialog := TAtlasPushDialog.CreateDialog(nil, AProjectName, APlans);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := Dialog.ShowModal = mrOk;
  finally
    Dialog.Free;
  end;
end;

end.
