unit Atlas.UI.Welcome.SetupPreview;

// Vorschau vor „atlas.json anlegen“ in der Einrichtungskarte der
// Willkommensseite (#759), ohne Open Tools API: zeigt Ziel, Vorlage und den
// vollständigen Inhalt der Datei. Geschrieben wird nur nach „Anlegen“; Esc
// und „Abbrechen“ schreiben nichts. Der Inhalt ist nur lesbar: Wer ihn ändern
// will, legt die Datei an und öffnet sie danach in den Projekteinstellungen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasSetupPreviewDialog = class(TAtlasDialog)
  public const
    cDialogWidth = 560;
    cContentHeight = 300;
  private
    FIntro: TLabel;
    FContent: TMemo;
    FCreate: TButton;
    FCancel: TButton;
    function AddButton(AParent: TWinControl; const ACaption: string): TButton;
  public
    /// <summary>AConfigName = Dateiname (atlas.json), AProjectName = Datei, neben der sie liegt, ATemplate =
    /// Name der Vorlage, AText = Inhalt.</summary>
    constructor CreateDialog(AOwner: TComponent; const AConfigName, AProjectName, ATemplate, AText: string);
    /// <summary>Modal fragen; True nur nach „Anlegen“. APrepare (darf nil sein) kann das Fenster vorher dem
    /// Thema der IDE anpassen.</summary>
    class function Confirm(const AConfigName, AProjectName, ATemplate, AText: string;
      const APrepare: TProc<TForm>): Boolean; static;
    property Intro: TLabel read FIntro;
    property Content: TMemo read FContent;
    property CreateButton: TButton read FCreate;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Atlas.UI.Welcome.Strings;

const
  cGap = 8;

{ TAtlasSetupPreviewDialog }

constructor TAtlasSetupPreviewDialog.CreateDialog(AOwner: TComponent; const AConfigName, AProjectName,
  ATemplate, AText: string);
var
  mButtons: TFlowPanel;
begin
  inherited CreateDialog(AOwner, TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPreviewTitle, [AConfigName]),
    cDialogWidth);

  FIntro := TLabel.Create(Self);
  FIntro.Parent := Self;
  FIntro.Align := alTop;
  FIntro.AlignWithMargins := True;
  FIntro.Margins.SetBounds(cGap, cGap, cGap, 0);
  FIntro.WordWrap := True;
  FIntro.ShowAccelChar := False;
  FIntro.Caption := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPreviewIntro, [AConfigName, AProjectName,
    ATemplate]);

  FContent := TMemo.Create(Self);
  FContent.Parent := Self;
  FContent.Align := alTop;
  FContent.AlignWithMargins := True;
  FContent.Margins.SetBounds(cGap, cGap, cGap, 0);
  FContent.Top := FIntro.Top + FIntro.Height + 1;
  FContent.Height := ScaleValue(cContentHeight);
  FContent.ReadOnly := True;
  FContent.ScrollBars := ssBoth;
  FContent.WordWrap := False;
  FContent.Font.Name := 'Consolas';
  FContent.Text := AText;

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FContent.Top + FContent.Height + 1;
  FCreate := AddButton(mButtons, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupPreviewCreate));
  FCreate.ModalResult := mrOk;
  FCreate.Default := True;
  FCancel := AddButton(mButtons, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupPreviewCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  ActiveControl := FCreate;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

function TAtlasSetupPreviewDialog.AddButton(AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

class function TAtlasSetupPreviewDialog.Confirm(const AConfigName, AProjectName, ATemplate, AText: string;
  const APrepare: TProc<TForm>): Boolean;
var
  mDialog: TAtlasSetupPreviewDialog;
begin
  mDialog := TAtlasSetupPreviewDialog.CreateDialog(nil, AConfigName, AProjectName, ATemplate, AText);
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
