unit Atlas.UI.Diagnostics.SafeModeNotice;

// Hinweis des abgesicherten Starts (#722): ein kleines, nicht modales Fenster
// unten rechts im Hauptfenster, das den Start der IDE nie blockiert.
// - Rückfrage nach einem Absturz: „Abgesichert starten“, „Normal starten“,
//   „Details“.
// - Abgesichert gestartet: „Normal weiterarbeiten“, „Schnellschalter…“,
//   „Einstellungen auf den Stand vor … zurücksetzen“ (nur mit gemerktem
//   Stand), „Details“.
// „Details“ klappt die Angaben zur abgestürzten Sitzung und ihr anonymes
// Protokoll auf, dazu „Diagnoselog exportieren…“ und „Fehlerbericht…“ (nur,
// wenn der Aufrufer OnBugReport setzt). Die Knöpfe außer „Details“ schließen
// das Fenster und führen die Aktion danach aus. Das Fenster kennt weder
// Einstellungen noch Dateien: Text, Vorschlag und Details kommen vom Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
{$SCOPEDENUMS ON}
  TAtlasSafeNoticeKind = (Ask, Safe);
{$SCOPEDENUMS OFF}

  TAtlasSafeModeNotice = class(TForm)
  private type
    /// <summary>Steuerelemente des Fensters.</summary>
    TParts = record
      Text: TLabel;
      Suggestion: TLabel;
      Buttons: TFlowPanel;
      PrimaryButton: TButton;
      SecondaryButton: TButton;
      RestoreButton: TButton;
      DetailsButton: TButton;
      DetailsPanel: TPanel;
      Details: TMemo;
      ExportButton: TButton;
      BugButton: TButton;
    end;

    /// <summary>Aktionen der Knöpfe, gesetzt vom Aufrufer.</summary>
    THandlers = record
      OnSafe: TProc;
      OnNormal: TProc;
      OnToggles: TProc;
      OnRestore: TProc;
      OnExportLog: TProc;
      OnBugReport: TProc;
    end;
  private
    FKind: TAtlasSafeNoticeKind;
    FParts: TParts;
    FHandlers: THandlers;
    FDone: Boolean;
    /// <summary>Text und Vorschlag oben.</summary>
    procedure CreateTexts(const AText, ASuggestion: string);
    /// <summary>Knopfreihe je nach Art; ARestore = '' blendet „Zurücksetzen“ aus.</summary>
    procedure CreateButtons(const ARestore: string; AHasDetails: Boolean);
    /// <summary>Aufklappbare Details mit Export und Fehlerbericht.</summary>
    procedure CreateDetails(const ADetails: TArray<string>);
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure Run(const AProc: TProc);
    procedure PrimaryClick(Sender: TObject);
    procedure SecondaryClick(Sender: TObject);
    procedure RestoreClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure BugClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    /// <summary>Höhe nach dem tatsächlichen Umbruch von Text und Knöpfen (erst mit Fenster bekannt).</summary>
    procedure FitHeight;
  public
    /// <summary>ARestore: Beschriftung von „Einstellungen auf den Stand vor … zurücksetzen“; '' blendet den Knopf
    /// aus (nur im abgesicherten Fenster). ADetails: Zeilen für „Details“.</summary>
    constructor CreateNotice(AOwner: TComponent; AKind: TAtlasSafeNoticeKind; const AText, ASuggestion,
      ARestore: string; const ADetails: TArray<string>);
    /// <summary>Unten rechts in AArea (Bildschirm) zeigen, nicht modal.</summary>
    procedure ShowIn(const AArea: TRect);
    /// <summary>Details auf- bzw. zuklappen.</summary>
    procedure ToggleDetails;
    function DetailsVisible: Boolean;
    property Kind: TAtlasSafeNoticeKind read FKind;
    property TextLabel: TLabel read FParts.Text;
    property SuggestionLabel: TLabel read FParts.Suggestion;
    property PrimaryButton: TButton read FParts.PrimaryButton;
    property SecondaryButton: TButton read FParts.SecondaryButton;
    property RestoreButton: TButton read FParts.RestoreButton;
    property DetailsButton: TButton read FParts.DetailsButton;
    property ExportButton: TButton read FParts.ExportButton;
    property BugButton: TButton read FParts.BugButton;
    property Details: TMemo read FParts.Details;
    /// <summary>Rückfrage: „Abgesichert starten“.</summary>
    property OnSafe: TProc read FHandlers.OnSafe write FHandlers.OnSafe;
    /// <summary>„Normal starten“ bzw. „Normal weiterarbeiten“.</summary>
    property OnNormal: TProc read FHandlers.OnNormal write FHandlers.OnNormal;
    property OnToggles: TProc read FHandlers.OnToggles write FHandlers.OnToggles;
    property OnRestore: TProc read FHandlers.OnRestore write FHandlers.OnRestore;
    property OnExportLog: TProc read FHandlers.OnExportLog write FHandlers.OnExportLog;
    /// <summary>Fehlerbericht (#108); ohne Zuweisung kein Knopf.</summary>
    property OnBugReport: TProc read FHandlers.OnBugReport write FHandlers.OnBugReport;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Diagnostics.Strings;

const
  cGap = 8;
  cNoticeWidth = 460;
  cDetailsHeight = 220;

{ TAtlasSafeModeNotice }

constructor TAtlasSafeModeNotice.CreateNotice(AOwner: TComponent; AKind: TAtlasSafeNoticeKind; const AText,
  ASuggestion, ARestore: string; const ADetails: TArray<string>);
begin
  inherited CreateNew(AOwner);
  FKind := AKind;
  Caption := TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeTitle);
  BorderStyle := bsToolWindow;
  BorderIcons := [biSystemMenu];
  Position := poDesigned;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := cNoticeWidth;
  OnClose := FormClose;
  CreateTexts(AText, ASuggestion);
  CreateButtons(ARestore, Length(ADetails) > 0);
  CreateDetails(ADetails);
  ClientHeight := FParts.Buttons.Top + FParts.Buttons.Height + cGap;
end;

procedure TAtlasSafeModeNotice.CreateTexts(const AText, ASuggestion: string);
begin
  FParts.Text := TLabel.Create(Self);
  FParts.Text.Parent := Self;
  FParts.Text.Align := alTop;
  FParts.Text.AlignWithMargins := True;
  FParts.Text.Margins.SetBounds(cGap, cGap, cGap, 0);
  FParts.Text.WordWrap := True;
  FParts.Text.Caption := AText;

  FParts.Suggestion := TLabel.Create(Self);
  FParts.Suggestion.Parent := Self;
  FParts.Suggestion.Align := alTop;
  FParts.Suggestion.AlignWithMargins := True;
  FParts.Suggestion.Margins.SetBounds(cGap, cGap, cGap, 0);
  FParts.Suggestion.WordWrap := True;
  FParts.Suggestion.Caption := ASuggestion;
  FParts.Suggestion.Visible := ASuggestion <> '';
  FParts.Suggestion.Top := FParts.Text.Top + FParts.Text.Height + 1;
end;

procedure TAtlasSafeModeNotice.CreateButtons(const ARestore: string; AHasDetails: Boolean);
var
  mButtons: TFlowPanel;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FParts.Suggestion.Top + FParts.Suggestion.Height + 1;
  FParts.Buttons := mButtons;
  if FKind = TAtlasSafeNoticeKind.Ask then
  begin
    FParts.PrimaryButton := AddButton(mButtons, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeAskSafe),
      PrimaryClick);
    FParts.SecondaryButton := AddButton(mButtons, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeAskNormal),
      SecondaryClick);
  end
  else
  begin
    FParts.PrimaryButton := AddButton(mButtons,
      TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeContinueNormal), PrimaryClick);
    FParts.SecondaryButton := AddButton(mButtons,
      TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeOpenToggles),
      SecondaryClick);
  end;
  FParts.RestoreButton := AddButton(mButtons, ARestore, RestoreClick);
  FParts.RestoreButton.Visible := (FKind = TAtlasSafeNoticeKind.Safe) and (ARestore <> '');
  FParts.DetailsButton := AddButton(mButtons, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeDetails),
    DetailsClick);
  FParts.DetailsButton.Visible := AHasDetails;
end;

procedure TAtlasSafeModeNotice.CreateDetails(const ADetails: TArray<string>);
var
  mLine: string;
  mPanel: TPanel;
begin
  mPanel := TPanel.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alClient;
  mPanel.BevelOuter := bvNone;
  mPanel.Visible := False;
  FParts.DetailsPanel := mPanel;

  FParts.Details := TMemo.Create(Self);
  FParts.Details.Parent := mPanel;
  FParts.Details.Align := alClient;
  FParts.Details.AlignWithMargins := True;
  FParts.Details.Margins.SetBounds(cGap, 0, cGap, 0);
  FParts.Details.ReadOnly := True;
  FParts.Details.ScrollBars := ssBoth;
  FParts.Details.WordWrap := False;
  FParts.Details.Font.Name := 'Consolas';
  FParts.Details.Lines.BeginUpdate;
  try
    for mLine in ADetails do
    begin
      FParts.Details.Lines.Add(mLine);
    end;
  finally
    FParts.Details.Lines.EndUpdate;
  end;

  FParts.ExportButton := AddButton(mPanel, TAtlasStrings.Text(TAtlasTextId.DiagExportMenu), ExportClick);
  FParts.ExportButton.Align := alBottom;
  FParts.ExportButton.AlignWithMargins := True;
  FParts.ExportButton.Margins.SetBounds(cGap, cGap, cGap, cGap);
  FParts.BugButton := AddButton(mPanel, TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SafeBugReport), BugClick);
  FParts.BugButton.Align := alBottom;
  FParts.BugButton.AlignWithMargins := True;
  FParts.BugButton.Margins.SetBounds(cGap, 0, cGap, 0);
  FParts.BugButton.Visible := False;
end;

function TAtlasSafeModeNotice.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(24);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

procedure TAtlasSafeModeNotice.FitHeight;
var
  mIndex, mBottom, mExtra: Integer;
  mControl: TControl;
begin
  HandleNeeded;
  // Umbrechende Beschriftungen messen erst mit Fenster richtig.
  FParts.Text.AutoSize := False;
  FParts.Text.AutoSize := True;
  FParts.Suggestion.AutoSize := False;
  FParts.Suggestion.AutoSize := True;
  // Knopfreihe: AutoSize des TFlowPanel rechnet umgebrochene Reihen nicht zuverlässig mit;
  // die Höhe ergibt sich aus dem untersten sichtbaren Knopf.
  FParts.Buttons.AutoSize := False;
  FParts.Buttons.Height := ScaleValue(200);
  FParts.Buttons.Realign;
  mBottom := 0;
  for mIndex := 0 to FParts.Buttons.ControlCount - 1 do
  begin
    mControl := FParts.Buttons.Controls[mIndex];
    if mControl.Visible then
    begin
      mBottom := Max(mBottom, mControl.Top + mControl.Height + mControl.Margins.Bottom);
    end;
  end;
  FParts.Buttons.Height := mBottom;
  Realign;
  mExtra := 0;
  if FParts.DetailsPanel.Visible then
  begin
    mExtra := ScaleValue(cDetailsHeight);
  end;
  ClientHeight := FParts.Buttons.Top + FParts.Buttons.Height + cGap + mExtra;
end;

procedure TAtlasSafeModeNotice.ShowIn(const AArea: TRect);
begin
  FitHeight;
  Left := AArea.Right - Width - cGap;
  Top := AArea.Bottom - Height - cGap;
  // Nicht modal: Die IDE startet weiter, während der Hinweis offen ist.
  Show;
  // Beim Zeigen kann das Fenster auf die Skalierung des Bildschirms umgerechnet werden: neu messen,
  // unten bleibt unten.
  FitHeight;
  Top := AArea.Bottom - Height - cGap;
end;

procedure TAtlasSafeModeNotice.Run(const AProc: TProc);
begin
  // Nur die erste Aktion zählt; ausgeführt wird nach dem Schließen.
  if FDone then
  begin
    Exit;
  end;
  FDone := True;
  Close;
  if Assigned(AProc) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
      procedure
      begin
        AProc();
      end);
  end;
end;

procedure TAtlasSafeModeNotice.PrimaryClick(Sender: TObject);
begin
  if FKind = TAtlasSafeNoticeKind.Ask then
  begin
    Run(FHandlers.OnSafe);
  end
  else
  begin
    Run(FHandlers.OnNormal);
  end;
end;

procedure TAtlasSafeModeNotice.SecondaryClick(Sender: TObject);
begin
  if FKind = TAtlasSafeNoticeKind.Ask then
  begin
    Run(FHandlers.OnNormal);
  end
  else
  begin
    Run(FHandlers.OnToggles);
  end;
end;

procedure TAtlasSafeModeNotice.RestoreClick(Sender: TObject);
begin
  Run(FHandlers.OnRestore);
end;

procedure TAtlasSafeModeNotice.DetailsClick(Sender: TObject);
begin
  ToggleDetails;
end;

procedure TAtlasSafeModeNotice.ExportClick(Sender: TObject);
begin
  if Assigned(FHandlers.OnExportLog) then
  begin
    FHandlers.OnExportLog();
  end;
end;

procedure TAtlasSafeModeNotice.BugClick(Sender: TObject);
begin
  if Assigned(FHandlers.OnBugReport) then
  begin
    FHandlers.OnBugReport();
  end;
end;

function TAtlasSafeModeNotice.DetailsVisible: Boolean;
begin
  Result := FParts.DetailsPanel.Visible;
end;

procedure TAtlasSafeModeNotice.ToggleDetails;
var
  mBottom: Integer;
begin
  mBottom := Top + Height;
  FParts.BugButton.Visible := Assigned(FHandlers.OnBugReport);
  FParts.ExportButton.Visible := Assigned(FHandlers.OnExportLog);
  FParts.DetailsPanel.Visible := not FParts.DetailsPanel.Visible;
  FitHeight;
  // Unten bleibt unten: das Fenster wächst nach oben.
  if Visible then
  begin
    Top := mBottom - Height;
  end;
end;

procedure TAtlasSafeModeNotice.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

end.
