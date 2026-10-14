unit Atlas.UI.Updates.Consent;

// Rückfrage zur Update-Prüfung beim ersten Start (#495): ein kleines, nicht
// modales Fenster unten rechts im Hauptfenster wie beim abgesicherten Start
// (#722), damit der Start der IDE nie wartet. „Ja, prüfen“ und „Nein“
// schließen das Fenster und führen die Aktion danach aus; Schließen über das
// Kreuz entscheidet nichts (der Aufrufer fragt beim nächsten Start wieder).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol;

type
  TAtlasUpdateConsent = class(TForm)
  private
    FText: TLabel;
    FSymbol: TAtlasSymbolImage;
    FYes: TButton;
    FNo: TButton;
    FDone: Boolean;
    FOnYes: TProc;
    FOnNo: TProc;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure Run(const AProc: TProc);
    procedure YesClick(Sender: TObject);
    procedure NoClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor CreateConsent(AOwner: TComponent);
    /// <summary>Unten rechts in AArea (Bildschirm) zeigen, nicht modal.</summary>
    procedure ShowIn(const AArea: TRect);
    property TextLabel: TLabel read FText;
    property Symbol: TAtlasSymbolImage read FSymbol;
    property YesButton: TButton read FYes;
    property NoButton: TButton read FNo;
    property OnYes: TProc read FOnYes write FOnYes;
    property OnNo: TProc read FOnNo write FOnNo;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  Gap = 8;
  ConsentWidth = 420;

{ TAtlasUpdateConsent }

constructor TAtlasUpdateConsent.CreateConsent(AOwner: TComponent);
var
  Buttons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Text(TAtlasTextId.UpdatesConsentTitle);
  BorderStyle := bsToolWindow;
  BorderIcons := [biSystemMenu];
  Position := poDesigned;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(ConsentWidth);
  OnClose := FormClose;

  // Atlas-Symbol (#751) links neben dem Text.
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Self;
  FSymbol.LogicalSize := TAtlasSymbol.HeaderSize;
  FSymbol.Left := Gap;
  FSymbol.Top := Gap;
  FText := TLabel.Create(Self);
  FText.Parent := Self;
  FText.Align := alTop;
  FText.AlignWithMargins := True;
  FText.Margins.SetBounds(2 * Gap + FSymbol.Width, Gap, Gap, 0);
  FText.WordWrap := True;
  FText.Caption := TAtlasStrings.Text(TAtlasTextId.UpdatesConsentText);

  Buttons := TFlowPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.Align := alTop;
  Buttons.AutoSize := True;
  Buttons.BevelOuter := bvNone;
  Buttons.AlignWithMargins := True;
  Buttons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  Buttons.Top := FText.Top + FText.Height + 1;
  FYes := AddButton(Buttons, TAtlasStrings.Text(TAtlasTextId.UpdatesConsentYes), YesClick);
  FNo := AddButton(Buttons, TAtlasStrings.Text(TAtlasTextId.UpdatesConsentNo), NoClick);
  ClientHeight := Buttons.Top + Buttons.Height + Gap;
  if ClientHeight < FSymbol.Top + FSymbol.Height + Gap then
    ClientHeight := FSymbol.Top + FSymbol.Height + Gap;
end;

function TAtlasUpdateConsent.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(24);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

procedure TAtlasUpdateConsent.ShowIn(const AArea: TRect);
begin
  Left := AArea.Right - Width - Gap;
  Top := AArea.Bottom - Height - Gap;
  // Nicht modal: Die IDE arbeitet weiter, während die Frage offen ist.
  Show;
end;

procedure TAtlasUpdateConsent.Run(const AProc: TProc);
begin
  // Nur die erste Antwort zählt; ausgeführt wird nach dem Schließen.
  if FDone then
    Exit;
  FDone := True;
  Close;
  if Assigned(AProc) then
    TThread.ForceQueue(nil,
      procedure
      begin
        AProc();
      end);
end;

procedure TAtlasUpdateConsent.YesClick(Sender: TObject);
begin
  Run(FOnYes);
end;

procedure TAtlasUpdateConsent.NoClick(Sender: TObject);
begin
  Run(FOnNo);
end;

procedure TAtlasUpdateConsent.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

end.
