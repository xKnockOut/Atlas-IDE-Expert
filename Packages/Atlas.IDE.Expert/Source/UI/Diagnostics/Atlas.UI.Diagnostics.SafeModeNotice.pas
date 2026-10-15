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
  private
    FKind: TAtlasSafeNoticeKind;
    FText: TLabel;
    FSuggestion: TLabel;
    FButtons: TFlowPanel;
    FPrimaryButton: TButton;
    FSecondaryButton: TButton;
    FRestoreButton: TButton;
    FDetailsButton: TButton;
    FDetailsPanel: TPanel;
    FDetails: TMemo;
    FExportButton: TButton;
    FBugButton: TButton;
    FDone: Boolean;
    FOnSafe: TProc;
    FOnNormal: TProc;
    FOnToggles: TProc;
    FOnRestore: TProc;
    FOnExportLog: TProc;
    FOnBugReport: TProc;
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
    property TextLabel: TLabel read FText;
    property SuggestionLabel: TLabel read FSuggestion;
    property PrimaryButton: TButton read FPrimaryButton;
    property SecondaryButton: TButton read FSecondaryButton;
    property RestoreButton: TButton read FRestoreButton;
    property DetailsButton: TButton read FDetailsButton;
    property ExportButton: TButton read FExportButton;
    property BugButton: TButton read FBugButton;
    property Details: TMemo read FDetails;
    /// <summary>Rückfrage: „Abgesichert starten“.</summary>
    property OnSafe: TProc read FOnSafe write FOnSafe;
    /// <summary>„Normal starten“ bzw. „Normal weiterarbeiten“.</summary>
    property OnNormal: TProc read FOnNormal write FOnNormal;
    property OnToggles: TProc read FOnToggles write FOnToggles;
    property OnRestore: TProc read FOnRestore write FOnRestore;
    property OnExportLog: TProc read FOnExportLog write FOnExportLog;
    /// <summary>Fehlerbericht (#108); ohne Zuweisung kein Knopf.</summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

const
  Gap = 8;
  NoticeWidth = 460;
  DetailsHeight = 220;

{ TAtlasSafeModeNotice }

constructor TAtlasSafeModeNotice.CreateNotice(AOwner: TComponent; AKind: TAtlasSafeNoticeKind; const AText,
  ASuggestion, ARestore: string; const ADetails: TArray<string>);
var
  Line: string;
begin
  inherited CreateNew(AOwner);
  FKind := AKind;
  Caption := TAtlasStrings.Text(TAtlasTextId.SafeTitle);
  BorderStyle := bsToolWindow;
  BorderIcons := [biSystemMenu];
  Position := poDesigned;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := NoticeWidth;
  OnClose := FormClose;

  FText := TLabel.Create(Self);
  FText.Parent := Self;
  FText.Align := alTop;
  FText.AlignWithMargins := True;
  FText.Margins.SetBounds(Gap, Gap, Gap, 0);
  FText.WordWrap := True;
  FText.Caption := AText;

  FSuggestion := TLabel.Create(Self);
  FSuggestion.Parent := Self;
  FSuggestion.Align := alTop;
  FSuggestion.AlignWithMargins := True;
  FSuggestion.Margins.SetBounds(Gap, Gap, Gap, 0);
  FSuggestion.WordWrap := True;
  FSuggestion.Caption := ASuggestion;
  FSuggestion.Visible := ASuggestion <> '';
  FSuggestion.Top := FText.Top + FText.Height + 1;

  FButtons := TFlowPanel.Create(Self);
  FButtons.Parent := Self;
  FButtons.Align := alTop;
  FButtons.AutoSize := True;
  FButtons.BevelOuter := bvNone;
  FButtons.AlignWithMargins := True;
  FButtons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  FButtons.Top := FSuggestion.Top + FSuggestion.Height + 1;

  if AKind = TAtlasSafeNoticeKind.Ask then
  begin
    FPrimaryButton := AddButton(FButtons, TAtlasStrings.Text(TAtlasTextId.SafeAskSafe), PrimaryClick);
    FSecondaryButton := AddButton(FButtons, TAtlasStrings.Text(TAtlasTextId.SafeAskNormal), SecondaryClick);
  end
  else
  begin
    FPrimaryButton := AddButton(FButtons, TAtlasStrings.Text(TAtlasTextId.SafeContinueNormal), PrimaryClick);
    FSecondaryButton := AddButton(FButtons, TAtlasStrings.Text(TAtlasTextId.SafeOpenToggles), SecondaryClick);
  end;
  FRestoreButton := AddButton(FButtons, ARestore, RestoreClick);
  FRestoreButton.Visible := (AKind = TAtlasSafeNoticeKind.Safe) and (ARestore <> '');
  FDetailsButton := AddButton(FButtons, TAtlasStrings.Text(TAtlasTextId.SafeDetails), DetailsClick);
  FDetailsButton.Visible := Length(ADetails) > 0;

  FDetailsPanel := TPanel.Create(Self);
  FDetailsPanel.Parent := Self;
  FDetailsPanel.Align := alClient;
  FDetailsPanel.BevelOuter := bvNone;
  FDetailsPanel.Visible := False;

  FDetails := TMemo.Create(Self);
  FDetails.Parent := FDetailsPanel;
  FDetails.Align := alClient;
  FDetails.AlignWithMargins := True;
  FDetails.Margins.SetBounds(Gap, 0, Gap, 0);
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssBoth;
  FDetails.WordWrap := False;
  FDetails.Font.Name := 'Consolas';
  for Line in ADetails do
    FDetails.Lines.Add(Line);

  FExportButton := AddButton(FDetailsPanel, TAtlasStrings.Text(TAtlasTextId.DiagExportMenu), ExportClick);
  FExportButton.Align := alBottom;
  FExportButton.AlignWithMargins := True;
  FExportButton.Margins.SetBounds(Gap, Gap, Gap, Gap);
  FBugButton := AddButton(FDetailsPanel, TAtlasStrings.Text(TAtlasTextId.SafeBugReport), BugClick);
  FBugButton.Align := alBottom;
  FBugButton.AlignWithMargins := True;
  FBugButton.Margins.SetBounds(Gap, 0, Gap, 0);
  FBugButton.Visible := False;

  ClientHeight := FButtons.Top + FButtons.Height + Gap;
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
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

procedure TAtlasSafeModeNotice.FitHeight;
var
  Extra: Integer;
begin
  HandleNeeded;
  // Umbrechende Beschriftungen und die Knopfreihe messen erst mit Fenster richtig;
  // im Konstruktor war die Höhe zu klein (Knöpfe abgeschnitten).
  FText.AutoSize := False;
  FText.AutoSize := True;
  FSuggestion.AutoSize := False;
  FSuggestion.AutoSize := True;
  FButtons.AutoSize := False;
  FButtons.AutoSize := True;
  Realign;
  Extra := 0;
  if FDetailsPanel.Visible then
    Extra := ScaleValue(DetailsHeight);
  ClientHeight := FButtons.Top + FButtons.Height + Gap + Extra;
end;

procedure TAtlasSafeModeNotice.ShowIn(const AArea: TRect);
begin
  FitHeight;
  Left := AArea.Right - Width - Gap;
  Top := AArea.Bottom - Height - Gap;
  // Nicht modal: Die IDE startet weiter, während der Hinweis offen ist.
  Show;
end;

procedure TAtlasSafeModeNotice.Run(const AProc: TProc);
begin
  // Nur die erste Aktion zählt; ausgeführt wird nach dem Schließen.
  if FDone then
    Exit;
  FDone := True;
  Close;
  if Assigned(AProc) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
      procedure
      begin
        AProc();
      end);
end;

procedure TAtlasSafeModeNotice.PrimaryClick(Sender: TObject);
begin
  if FKind = TAtlasSafeNoticeKind.Ask then
    Run(FOnSafe)
  else
    Run(FOnNormal);
end;

procedure TAtlasSafeModeNotice.SecondaryClick(Sender: TObject);
begin
  if FKind = TAtlasSafeNoticeKind.Ask then
    Run(FOnNormal)
  else
    Run(FOnToggles);
end;

procedure TAtlasSafeModeNotice.RestoreClick(Sender: TObject);
begin
  Run(FOnRestore);
end;

procedure TAtlasSafeModeNotice.DetailsClick(Sender: TObject);
begin
  ToggleDetails;
end;

procedure TAtlasSafeModeNotice.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExportLog) then
    FOnExportLog();
end;

procedure TAtlasSafeModeNotice.BugClick(Sender: TObject);
begin
  if Assigned(FOnBugReport) then
    FOnBugReport();
end;

function TAtlasSafeModeNotice.DetailsVisible: Boolean;
begin
  Result := FDetailsPanel.Visible;
end;

procedure TAtlasSafeModeNotice.ToggleDetails;
var
  Bottom: Integer;
begin
  Bottom := Top + Height;
  FBugButton.Visible := Assigned(FOnBugReport);
  FExportButton.Visible := Assigned(FOnExportLog);
  FDetailsPanel.Visible := not FDetailsPanel.Visible;
  FitHeight;
  // Unten bleibt unten: das Fenster wächst nach oben.
  if Visible then
    Top := Bottom - Height;
end;

procedure TAtlasSafeModeNotice.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

end.
