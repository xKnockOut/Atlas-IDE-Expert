unit Atlas.UI.Welcome.Setup;

// Bereich „<Projekt> für Atlas einrichten“ der Willkommensseite (#759), ohne
// Open Tools API. Nach dem Mockup (#ws7):
//   ✓ Projekt gefunden, keine atlas.json
//   ☐ atlas.json anlegen          [Bestehendes Projekt ▾] [Anlegen …]
//   ☐ Baseline erzeugen (#97)     [Starten]
//   ☐ Suchpfade und Defines prüfen [Prüfen]
//       Unit „Xml.Helpers“ nicht gefunden – Src\Main.pas, Zeile 12
//       [Projektoptionen …]
//   Für dieses Projekt nicht mehr fragen
//   Neu mit Atlas:  [Unit] [Formular] [Testklasse]
// Erledigte Schritte stehen grün mit ✓ und ohne Knöpfe. Ein laufender Schritt
// zeigt die Sekunden („läuft … 12 s“); ist das Projekt nicht geöffnet, heißen
// die Knöpfe von Baseline und Prüfung „Projekt öffnen“. Ein Klick auf einen
// Fund öffnet die Projektoptionen. Jeder Schritt läuft nur auf Klick; die
// Knöpfe rufen die Quelle (IAtlasSetupSource) über die Nachrichtenschleife
// auf, damit Dialoge nicht im Klick des Knopfs laufen. Ohne Karte stehen nur
// die Knöpfe „Neu mit Atlas“ da.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Generate.FileTemplates,
  Atlas.Core.Welcome.Setup,
  Atlas.UI.Welcome.Frame;

type
  IAtlasSetupSource = interface
    ['{8C2D4E61-7A3B-4F95-B1C0-2E9D6A4F7B13}']
    /// <summary>Stand der Karte für das Ziel.</summary>
    function Card: TAtlasSetupCard;
    /// <summary>„Anlegen …“: Inhalt zeigen, nach Bestätigung atlas.json neben die Projektdatei schreiben.
    /// </summary>
    procedure CreateConfig(ATemplate: TAtlasSetupTemplate);
    /// <summary>„Starten“: Baseline erzeugen (#97).</summary>
    procedure StartBaseline;
    /// <summary>„Prüfen“: Suchpfade und Defines prüfen.</summary>
    procedure CheckPaths;
    /// <summary>Projektoptionen des Ziels öffnen.</summary>
    procedure OpenOptions;
    /// <summary>Ziel in der IDE öffnen.</summary>
    procedure OpenProject;
    /// <summary>„Für dieses Projekt nicht mehr fragen“.</summary>
    procedure Dismiss;
    /// <summary>„Neu mit Atlas“: Erzeugen-Menü mit den Dateivorlagen der Art AKind.</summary>
    procedure NewFile(AKind: TAtlasNewFileKind);
  end;

{$SCOPEDENUMS ON}
  /// <summary>Knöpfe des Bereichs (für Tests und ClickButton).</summary>
  TAtlasSetupButton = (CreateConfig, Baseline, Paths, Options, Dismiss, NewUnit, NewForm, NewTest);
{$SCOPEDENUMS OFF}

  /// <summary>Texte des Bereichs „Einrichten“, ohne Steuerelement.</summary>
  TAtlasSetupTexts = class
  public
    /// <summary>„XmlInspector für Atlas einrichten“ bzw. „Neu mit Atlas“ ohne Karte.</summary>
    class function TitleText(const ACard: TAtlasSetupCard): string; static;
    class function TemplateCaption(ATemplate: TAtlasSetupTemplate): string; static;
    class function ButtonCaption(AButton: TAtlasSetupButton): string; static;
    /// <summary>Text des Schritts ohne Knöpfe; ANow für die Sekunden eines laufenden Schritts.</summary>
    class function StepCaption(AStep: TAtlasSetupStep; const ACard: TAtlasSetupCard; ANow: UInt64): string; static;
    /// <summary>Zeile eines Funds der Pfadprüfung.</summary>
    class function FindingCaption(const ALine: TAtlasSetupLine): string; static;
    /// <summary>Zeilen unter „Suchpfade und Defines prüfen“: Fehler, Stand der Gruppe, Zahlen, unsichere Funde.
    /// </summary>
    class function PathsCaption(const ACard: TAtlasSetupCard): string; static;
  end;

  /// <summary>Beschriftungen des Bereichs: Marke und Text je Schritt, Zeilen unter Baseline und Prüfung, Links.
  /// </summary>
  TAtlasSetupLabels = record
    Marks: array[TAtlasSetupStep] of TLabel;
    Texts: array[TAtlasSetupStep] of TLabel;
    BaselineInfo: TLabel;
    PathsInfo: TLabel;
    Findings: array[0..TAtlasWelcomeSetup.cMaxLines - 1] of TLabel;
    More: TLabel;
    /// <summary>Hinweis zur Edition der IDE (#1822) über „Nicht mehr fragen“.</summary>
    Edition: TLabel;
    Dismiss: TLabel;
    NewRow: TLabel;
  end;

  TAtlasWelcomeSetupFrame = class(TAtlasWelcomeSectionFrame)
  public const
    cIndent = 8;
    cGap = 6;
    cMarkWidth = 18;
    cButtonHeight = 24;
    cButtonPadding = 16;
    cComboWidth = 170;
    /// <summary>Grün wie die Marken der Projekte (#592), lesbar im hellen und im dunklen Thema.</summary>
    cDoneColor = TColor($0043A02E);
  private
    FSource: IAtlasSetupSource;
    FCard: TAtlasSetupCard;
    FLabels: TAtlasSetupLabels;
    FTemplate: TComboBox;
    FButtons: array[TAtlasSetupButton] of TButton;
    FTimer: TTimer;
    FContentHeight: Integer;
    FArranging: Boolean;
    FTemplateIndex: Integer;
    procedure SetSource(const AValue: IAtlasSetupSource);
    function NewLabel: TLabel;
    function NewButton(AButton: TAtlasSetupButton): TButton;
    procedure FillTemplates;
    procedure Arrange;
    procedure BodyResize(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
    procedure DismissClick(Sender: TObject);
    procedure FindingClick(Sender: TObject);
    procedure TemplateChange(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    function Running: Boolean;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Klick auf einen Knopf wie mit der Maus (auch für Tests).</summary>
    procedure ClickButton(AButton: TAtlasSetupButton);
    function Button(AButton: TAtlasSetupButton): TButton;
    function StepMark(AStep: TAtlasSetupStep): TLabel;
    function StepText(AStep: TAtlasSetupStep): TLabel;
    function Finding(AIndex: Integer): TLabel;
    /// <summary>Gewählte Vorlage (Vorgabe: Bestehendes Projekt).</summary>
    function SelectedTemplate: TAtlasSetupTemplate;
    procedure SelectTemplate(ATemplate: TAtlasSetupTemplate);
    /// <summary>Ist der Knopf sichtbar und bereit (bei „Nicht mehr fragen“ der Link)?</summary>
    function Clickable(AButton: TAtlasSetupButton): Boolean;
    property Source: IAtlasSetupSource read FSource write SetSource;
    property BaselineInfo: TLabel read FLabels.BaselineInfo;
    property PathsInfo: TLabel read FLabels.PathsInfo;
    property MoreLabel: TLabel read FLabels.More;
    property DismissLabel: TLabel read FLabels.Dismiss;
    property NewRowLabel: TLabel read FLabels.NewRow;
    property TemplateBox: TComboBox read FTemplate;
  end;

implementation

uses
  System.Math,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.UI.Welcome.Strings;

const
  cCheckMark = #$2713;
  cOpenBox = #$2610;

type
  /// <summary>Überträgt die Karte auf die Steuerelemente: Farben, Schritte, Knöpfe, Ergebnisse, Funde.</summary>
  TSetupCardView = record
  private
    FFrame: TAtlasWelcomeSetupFrame;
    FShow: Boolean;
    function Themed(AColor: TColor): TColor;
    procedure ApplyColors;
    procedure ApplySteps;
    procedure ApplyButtons;
    procedure ApplyInfos;
    procedure ApplyFindings;
    procedure ApplyNew;
  public
    constructor Create(AFrame: TAtlasWelcomeSetupFrame);
    procedure Apply;
  end;

  /// <summary>Ordnet die Steuerelemente in Reihen an; zu breite Reihen brechen um.</summary>
  TSetupLayout = record
  private
    FFrame: TAtlasWelcomeSetupFrame;
    FMeasure: TBitmap;
    FLeft: Integer;
    FTextLeft: Integer;
    FRight: Integer;
    FTop: Integer;
    FX: Integer;
    FRowHeight: Integer;
    function Scaled(AValue: Integer): Integer;
    function ButtonWidth(AButton: TButton): Integer;
    /// <summary>Setzt AControl rechts neben FX in die Reihe, bei zu wenig Platz in eine neue Reihe ab FTextLeft.
    /// </summary>
    procedure Place(AControl: TControl; AWidth, AHeight: Integer);
    /// <summary>Den Knopf in die Reihe setzen, wenn er sichtbar ist.</summary>
    procedure PlaceButton(AButton: TAtlasSetupButton);
    procedure NextRow;
    procedure PlaceLine(ALabel: TLabel);
    procedure PlaceStep(AStep: TAtlasSetupStep);
    procedure PlaceStepExtras(AStep: TAtlasSetupStep);
    procedure PlaceCard;
    procedure PlaceNew;
  public
    constructor Create(AFrame: TAtlasWelcomeSetupFrame);
    /// <summary>Gibt die Messfläche frei.</summary>
    procedure Release;
    /// <summary>Ordnet alles an und liefert die Höhe des Inhalts.</summary>
    function Run: Integer;
  end;

/// <summary>Führt die Aktion des Knopfs bei der Quelle aus; ohne geöffnetes Projekt öffnen Baseline und Prüfung es.
/// </summary>
procedure RunSetupButton(const ASource: IAtlasSetupSource; AButton: TAtlasSetupButton; AOpen: Boolean;
  ATemplate: TAtlasSetupTemplate);
begin
  case AButton of
    TAtlasSetupButton.CreateConfig:
      ASource.CreateConfig(ATemplate);
    TAtlasSetupButton.Baseline, TAtlasSetupButton.Paths:
      if not AOpen then
      begin
        ASource.OpenProject;
      end
      else if AButton = TAtlasSetupButton.Baseline then
      begin
        ASource.StartBaseline;
      end
      else
      begin
        ASource.CheckPaths;
      end;
    TAtlasSetupButton.Options:
      ASource.OpenOptions;
    TAtlasSetupButton.Dismiss:
      ASource.Dismiss;
    TAtlasSetupButton.NewUnit:
      ASource.NewFile(TAtlasNewFileKind.UnitFile);
    TAtlasSetupButton.NewForm:
      ASource.NewFile(TAtlasNewFileKind.FormFile);
  else
    ASource.NewFile(TAtlasNewFileKind.TestFile);
  end;
end;

{ TSetupCardView }

constructor TSetupCardView.Create(AFrame: TAtlasWelcomeSetupFrame);
begin
  FFrame := AFrame;
  FShow := AFrame.FCard.ShowCard;
end;

function TSetupCardView.Themed(AColor: TColor): TColor;
begin
  // Farbe des IDE-Themas (hell oder dunkel).
  Result := StyleServices(FFrame).GetSystemColor(AColor);
end;

procedure TSetupCardView.Apply;
begin
  ApplyColors;
  ApplySteps;
  ApplyButtons;
  ApplyInfos;
  ApplyFindings;
  ApplyNew;
  FFrame.FTimer.Enabled := FFrame.Running;
end;

procedure TSetupCardView.ApplyColors;
var
  mIndex: Integer;
begin
  FFrame.FLabels.BaselineInfo.Font.Color := Themed(clGrayText);
  FFrame.FLabels.Edition.Font.Color := Themed(clGrayText);
  FFrame.FLabels.PathsInfo.Font.Color := Themed(clGrayText);
  FFrame.FLabels.More.Font.Color := Themed(clGrayText);
  FFrame.FLabels.NewRow.Font.Color := Themed(clWindowText);
  FFrame.FLabels.Dismiss.Font.Color := Themed(clHotLight);
  for mIndex := Low(FFrame.FLabels.Findings) to High(FFrame.FLabels.Findings) do
  begin
    FFrame.FLabels.Findings[mIndex].Font.Color := Themed(clWindowText);
  end;
end;

procedure TSetupCardView.ApplySteps;
var
  mStep: TAtlasSetupStep;
  mMark, mText: TLabel;
begin
  for mStep := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
  begin
    mMark := FFrame.FLabels.Marks[mStep];
    mText := FFrame.FLabels.Texts[mStep];
    mMark.Visible := FShow;
    mText.Visible := FShow;
    if FFrame.FCard.StepDone(mStep) then
    begin
      mMark.Caption := cCheckMark;
      mMark.Font.Color := TAtlasWelcomeSetupFrame.cDoneColor;
    end
    else
    begin
      mMark.Caption := cOpenBox;
      mMark.Font.Color := Themed(clWindowText);
    end;
    mText.Font.Color := mMark.Font.Color;
    mText.Caption := TAtlasSetupTexts.StepCaption(mStep, FFrame.FCard, TThread.GetTickCount64);
  end;
end;

procedure TSetupCardView.ApplyButtons;
var
  mCard: TAtlasSetupCard;
  mHasSource: Boolean;
begin
  mCard := FFrame.FCard;
  mHasSource := FFrame.FSource <> nil;
  // Schritt 2: Auswahl und „Anlegen …“, solange keine Datei da ist.
  FFrame.FTemplate.Visible := FShow and not mCard.StepDone(TAtlasSetupStep.Config);
  FFrame.FButtons[TAtlasSetupButton.CreateConfig].Visible := FFrame.FTemplate.Visible;
  FFrame.FButtons[TAtlasSetupButton.CreateConfig].Enabled := mHasSource;
  // Schritt 3 und 4: Knopf, solange offen; ohne geöffnetes Projekt „Projekt öffnen“.
  FFrame.FButtons[TAtlasSetupButton.Baseline].Visible := FShow and not mCard.StepDone(TAtlasSetupStep.Baseline);
  FFrame.FButtons[TAtlasSetupButton.Paths].Visible := FShow and not mCard.StepDone(TAtlasSetupStep.Paths);
  if mCard.ProjectOpen then
  begin
    FFrame.FButtons[TAtlasSetupButton.Baseline].Caption := TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Baseline);
    FFrame.FButtons[TAtlasSetupButton.Paths].Caption := TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Paths);
  end
  else
  begin
    FFrame.FButtons[TAtlasSetupButton.Baseline].Caption := TAtlasWelcomeStrings.Text(
      TAtlasWelcomeTextId.WelcomeSetupOpenProject);
    FFrame.FButtons[TAtlasSetupButton.Paths].Caption := TAtlasWelcomeStrings.Text(
      TAtlasWelcomeTextId.WelcomeSetupOpenProject);
  end;
  FFrame.FButtons[TAtlasSetupButton.Baseline].Enabled := mHasSource and (mCard.Baseline <> TAtlasSetupRun.Running);
  FFrame.FButtons[TAtlasSetupButton.Paths].Enabled := mHasSource and (mCard.Paths <> TAtlasSetupRun.Running);
  FFrame.FLabels.Dismiss.Visible := FShow;
end;

procedure TSetupCardView.ApplyInfos;
var
  mCard: TAtlasSetupCard;
  mInfo: TLabel;
begin
  mCard := FFrame.FCard;
  // Ergebnis bzw. Fehler unter Baseline und Prüfung.
  mInfo := FFrame.FLabels.BaselineInfo;
  mInfo.Caption := '';
  // Nach dem Erzeugen in dieser Sitzung: Treffer der Baseline und neue Treffer (dann 0).
  if (mCard.Baseline = TAtlasSetupRun.Done) and (mCard.BaselineNewHits >= 0) then
  begin
    mInfo.Caption := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupBaselineResult,
      [mCard.BaselineTotal, mCard.BaselineFiles, mCard.BaselineNewHits]);
  end
  else if mCard.Baseline = TAtlasSetupRun.Failed then
  begin
    mInfo.Caption := mCard.BaselineError;
  end;
  mInfo.Visible := FShow and (mInfo.Caption <> '');
  mInfo := FFrame.FLabels.PathsInfo;
  mInfo.Caption := TAtlasSetupTexts.PathsCaption(mCard);
  mInfo.Visible := FShow and (mInfo.Caption <> '');
  mInfo := FFrame.FLabels.Edition;
  mInfo.Caption := mCard.Edition;
  mInfo.Visible := FShow and (mInfo.Caption <> '');
end;

procedure TSetupCardView.ApplyFindings;
var
  mLines: TArray<TAtlasSetupLine>;
  mMore, mIndex: Integer;
  mFinding: TLabel;
begin
  mLines := nil;
  mMore := 0;
  if FShow and (FFrame.FCard.Paths <> TAtlasSetupRun.Running) then
  begin
    mLines := TAtlasWelcomeSetup.Lines(FFrame.FCard.Facts.Setup, Length(FFrame.FLabels.Findings), mMore);
  end;
  for mIndex := Low(FFrame.FLabels.Findings) to High(FFrame.FLabels.Findings) do
  begin
    mFinding := FFrame.FLabels.Findings[mIndex];
    mFinding.Visible := mIndex < Length(mLines);
    if mFinding.Visible then
    begin
      mFinding.Caption := TAtlasSetupTexts.FindingCaption(mLines[mIndex]);
    end;
  end;
  FFrame.FLabels.More.Visible := mMore > 0;
  if mMore > 0 then
  begin
    FFrame.FLabels.More.Caption := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupMore, [mMore]);
  end;
  FFrame.FButtons[TAtlasSetupButton.Options].Visible := Length(mLines) > 0;
  FFrame.FButtons[TAtlasSetupButton.Options].Enabled := FFrame.FSource <> nil;
end;

procedure TSetupCardView.ApplyNew;
var
  mKind: TAtlasNewFileKind;
  mButton: TButton;
begin
  // Neu mit Atlas.
  FFrame.FLabels.NewRow.Visible := FFrame.FCard.ShowNew;
  for mKind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
  begin
    mButton := FFrame.FButtons[TAtlasSetupButton(Ord(TAtlasSetupButton.NewUnit) + Ord(mKind))];
    mButton.Visible := FFrame.FCard.ShowNew;
    mButton.Enabled := FFrame.FSource <> nil;
  end;
end;

{ TSetupLayout }

constructor TSetupLayout.Create(AFrame: TAtlasWelcomeSetupFrame);
begin
  FFrame := AFrame;
  // Breite des Frames statt der Inhaltsfläche: Die richtet sich erst später nach dem Frame aus.
  FLeft := Scaled(TAtlasWelcomeSetupFrame.cIndent);
  FTextLeft := FLeft + Scaled(TAtlasWelcomeSetupFrame.cMarkWidth);
  FRight := AFrame.ClientWidth - Scaled(TAtlasWelcomeSetupFrame.cIndent);
  FTop := Scaled(TAtlasWelcomeSetupFrame.cGap) div 2;
  FRowHeight := 0;
  FX := FTextLeft;
  FMeasure := TBitmap.Create;
  FMeasure.Canvas.Font.Assign(AFrame.Font);
end;

procedure TSetupLayout.Release;
begin
  FreeAndNil(FMeasure);
end;

function TSetupLayout.Scaled(AValue: Integer): Integer;
begin
  Result := FFrame.ScaleValue(AValue);
end;

function TSetupLayout.ButtonWidth(AButton: TButton): Integer;
begin
  Result := FMeasure.Canvas.TextWidth(AButton.Caption) + 2 * Scaled(TAtlasWelcomeSetupFrame.cButtonPadding);
end;

procedure TSetupLayout.Place(AControl: TControl; AWidth, AHeight: Integer);
begin
  if (FX > FTextLeft) and (FX + AWidth > FRight) then
  begin
    FX := FTextLeft;
    Inc(FTop, FRowHeight + Scaled(TAtlasWelcomeSetupFrame.cGap) div 2);
    FRowHeight := 0;
  end;
  AControl.SetBounds(FX, FTop, AWidth, AHeight);
  Inc(FX, AWidth + Scaled(TAtlasWelcomeSetupFrame.cGap));
  FRowHeight := Max(FRowHeight, AHeight);
end;

procedure TSetupLayout.PlaceButton(AButton: TAtlasSetupButton);
var
  mButton: TButton;
begin
  mButton := FFrame.FButtons[AButton];
  if mButton.Visible then
  begin
    Place(mButton, ButtonWidth(mButton), Scaled(TAtlasWelcomeSetupFrame.cButtonHeight));
  end;
end;

procedure TSetupLayout.NextRow;
begin
  if FRowHeight > 0 then
  begin
    Inc(FTop, FRowHeight + Scaled(TAtlasWelcomeSetupFrame.cGap) div 2);
  end;
  FRowHeight := 0;
  FX := FTextLeft;
end;

procedure TSetupLayout.PlaceLine(ALabel: TLabel);
begin
  if not ALabel.Visible then
  begin
    Exit;
  end;
  FX := FTextLeft;
  Place(ALabel, FMeasure.Canvas.TextWidth(ALabel.Caption), ALabel.Height);
  NextRow;
end;

procedure TSetupLayout.PlaceStep(AStep: TAtlasSetupStep);
var
  mMark, mText: TLabel;
begin
  mMark := FFrame.FLabels.Marks[AStep];
  mText := FFrame.FLabels.Texts[AStep];
  mMark.SetBounds(FLeft, FTop + Scaled(4), Scaled(TAtlasWelcomeSetupFrame.cMarkWidth), mMark.Height);
  FX := FTextLeft;
  Place(mText, FMeasure.Canvas.TextWidth(mText.Caption), mText.Height);
  // Text etwas tiefer, damit er mittig neben den Knöpfen steht.
  mText.Top := FTop + Scaled(4);
  FRowHeight := Max(FRowHeight, Scaled(TAtlasWelcomeSetupFrame.cButtonHeight));
  case AStep of
    TAtlasSetupStep.Config:
      if FFrame.FTemplate.Visible then
      begin
        Place(FFrame.FTemplate, Scaled(TAtlasWelcomeSetupFrame.cComboWidth), FFrame.FTemplate.Height);
        PlaceButton(TAtlasSetupButton.CreateConfig);
      end;
    TAtlasSetupStep.Baseline:
      PlaceButton(TAtlasSetupButton.Baseline);
    TAtlasSetupStep.Paths:
      PlaceButton(TAtlasSetupButton.Paths);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  NextRow;
  PlaceStepExtras(AStep);
end;

procedure TSetupLayout.PlaceStepExtras(AStep: TAtlasSetupStep);
var
  mIndex: Integer;
begin
  if AStep = TAtlasSetupStep.Baseline then
  begin
    PlaceLine(FFrame.FLabels.BaselineInfo);
  end;
  if AStep <> TAtlasSetupStep.Paths then
  begin
    Exit;
  end;
  PlaceLine(FFrame.FLabels.PathsInfo);
  for mIndex := Low(FFrame.FLabels.Findings) to High(FFrame.FLabels.Findings) do
  begin
    PlaceLine(FFrame.FLabels.Findings[mIndex]);
  end;
  PlaceLine(FFrame.FLabels.More);
  if FFrame.FButtons[TAtlasSetupButton.Options].Visible then
  begin
    PlaceButton(TAtlasSetupButton.Options);
    NextRow;
  end;
end;

procedure TSetupLayout.PlaceCard;
var
  mStep: TAtlasSetupStep;
  mDismiss: TLabel;
begin
  for mStep := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
  begin
    PlaceStep(mStep);
  end;
  PlaceLine(FFrame.FLabels.Edition);
  mDismiss := FFrame.FLabels.Dismiss;
  FX := FLeft;
  Place(mDismiss, FMeasure.Canvas.TextWidth(mDismiss.Caption), mDismiss.Height);
  mDismiss.Left := FLeft;
  NextRow;
end;

procedure TSetupLayout.PlaceNew;
var
  mKind: TAtlasNewFileKind;
  mNewRow: TLabel;
begin
  mNewRow := FFrame.FLabels.NewRow;
  Inc(FTop, Scaled(TAtlasWelcomeSetupFrame.cGap) div 2);
  FX := FLeft;
  Place(mNewRow, FMeasure.Canvas.TextWidth(mNewRow.Caption), mNewRow.Height);
  mNewRow.Left := FLeft;
  mNewRow.Top := FTop + Scaled(4);
  FRowHeight := Max(FRowHeight, Scaled(TAtlasWelcomeSetupFrame.cButtonHeight));
  FX := FLeft + FMeasure.Canvas.TextWidth(mNewRow.Caption) + Scaled(TAtlasWelcomeSetupFrame.cGap);
  for mKind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
  begin
    PlaceButton(TAtlasSetupButton(Ord(TAtlasSetupButton.NewUnit) + Ord(mKind)));
  end;
  NextRow;
end;

function TSetupLayout.Run: Integer;
begin
  if FFrame.FCard.ShowCard then
  begin
    PlaceCard;
  end;
  if FFrame.FCard.ShowNew then
  begin
    PlaceNew;
  end;
  Result := FTop + Scaled(TAtlasWelcomeSetupFrame.cGap) div 2;
end;

{ TAtlasWelcomeSetupFrame }

constructor TAtlasWelcomeSetupFrame.Create(AOwner: TComponent);
var
  mStep: TAtlasSetupStep;
  mKind: TAtlasSetupButton;
  mIndex: Integer;
begin
  inherited Create(AOwner);
  FCard := TAtlasSetupCard.Empty;
  for mStep := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
  begin
    FLabels.Marks[mStep] := NewLabel;
    FLabels.Marks[mStep].Font.Style := [fsBold];
    FLabels.Texts[mStep] := NewLabel;
  end;
  FTemplate := TComboBox.Create(Self);
  FTemplate.Parent := Body;
  FTemplate.Style := csDropDownList;
  FTemplate.OnChange := TemplateChange;
  FTemplateIndex := Ord(TAtlasSetupTemplate.Existing);
  for mKind := Low(TAtlasSetupButton) to High(TAtlasSetupButton) do
  begin
    if mKind <> TAtlasSetupButton.Dismiss then
    begin
      FButtons[mKind] := NewButton(mKind);
    end;
  end;
  FLabels.BaselineInfo := NewLabel;
  FLabels.PathsInfo := NewLabel;
  for mIndex := Low(FLabels.Findings) to High(FLabels.Findings) do
  begin
    FLabels.Findings[mIndex] := NewLabel;
    FLabels.Findings[mIndex].Cursor := crHandPoint;
    FLabels.Findings[mIndex].OnClick := FindingClick;
  end;
  FLabels.More := NewLabel;
  FLabels.Edition := NewLabel;
  FLabels.Dismiss := NewLabel;
  FLabels.Dismiss.Font.Style := [fsUnderline];
  FLabels.Dismiss.Cursor := crHandPoint;
  FLabels.Dismiss.Caption := TAtlasSetupTexts.ButtonCaption(TAtlasSetupButton.Dismiss);
  FLabels.Dismiss.OnClick := DismissClick;
  FLabels.NewRow := NewLabel;
  FLabels.NewRow.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNewRow);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 1000;
  FTimer.OnTimer := TimerTick;
  Body.OnResize := BodyResize;
  UpdateContent;
end;

function TAtlasWelcomeSetupFrame.NewLabel: TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Body;
  Result.ShowAccelChar := False;
  Result.AutoSize := True;
  // Eigene Farben (grün, grau, Link): Das Thema setzt die Schrift nicht, ApplyCard holt die Farben des Themas.
  Result.StyleElements := Result.StyleElements - [seFont];
end;

function TAtlasWelcomeSetupFrame.NewButton(AButton: TAtlasSetupButton): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Body;
  Result.Caption := TAtlasSetupTexts.ButtonCaption(AButton);
  Result.Tag := Ord(AButton);
  Result.OnClick := ButtonClick;
end;

class function TAtlasSetupTexts.TitleText(const ACard: TAtlasSetupCard): string;
begin
  if ACard.ShowCard and (ACard.ProjectName <> '') then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupTitle, [ACard.ProjectName]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNewTitle);
  end;
end;

class function TAtlasSetupTexts.TemplateCaption(ATemplate: TAtlasSetupTemplate): string;
begin
  case ATemplate of
    TAtlasSetupTemplate.NewStrict:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupTemplateStrict);
    TAtlasSetupTemplate.Legacy:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupTemplateLegacy);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupTemplateExisting);
  end;
end;

class function TAtlasSetupTexts.ButtonCaption(AButton: TAtlasSetupButton): string;
begin
  case AButton of
    TAtlasSetupButton.CreateConfig:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupConfigCreate);
    TAtlasSetupButton.Baseline:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupStart);
    TAtlasSetupButton.Paths:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupCheck);
    TAtlasSetupButton.Options:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupOptions);
    TAtlasSetupButton.Dismiss:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupDismiss);
    TAtlasSetupButton.NewUnit:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNewUnit);
    TAtlasSetupButton.NewForm:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNewForm);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupNewTest);
  end;
end;

class function TAtlasSetupTexts.StepCaption(AStep: TAtlasSetupStep; const ACard: TAtlasSetupCard;
  ANow: UInt64): string;
begin
  case AStep of
    TAtlasSetupStep.Found:
      if ACard.Facts.ConfigExists then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupFound);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupFoundNoConfig);
      end;
    TAtlasSetupStep.Config:
      if ACard.StepDone(AStep) then
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupConfigDone, [ACard.ConfigName]);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupConfig);
      end;
    TAtlasSetupStep.Baseline:
      if ACard.Baseline = TAtlasSetupRun.Running then
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupBaselineRunning,
          [TAtlasWelcomeSetup.Elapsed(ACard.BaselineStarted, ANow)]);
      end
      else if ACard.StepDone(AStep) then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupBaselineDone);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupBaseline);
      end;
  else
    if ACard.Paths = TAtlasSetupRun.Running then
    begin
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPathsRunning,
        [TAtlasWelcomeSetup.Elapsed(ACard.PathsStarted, ANow)]);
    end
    else if ACard.StepDone(AStep) then
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupPathsDone);
    end
    else
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSetupPaths);
    end;
  end;
end;

class function TAtlasSetupTexts.FindingCaption(const ALine: TAtlasSetupLine): string;
begin
  // Hinweis zu einem requires-Package (#759): kein Fehler.
  if (ALine.Kind = TAtlasSetupFindingKind.Hint) and (ALine.Note <> '') then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupRequiresInSearchPath, [ALine.Note, ALine.Name,
      ALine.FileName, ALine.Line]);
  end
  else if ALine.Kind = TAtlasSetupFindingKind.Hint then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupRequiresNoSource,
      [ALine.Name, ALine.FileName, ALine.Line]);
  end
  // Unsicher (Suchpfad mit unbekanntem Makro übersprungen): mit den Makros, damit es nicht wie ein Fehler wirkt.
  else if ALine.Uncertain and (ALine.Kind = TAtlasSetupFindingKind.MissingUnit) then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupMissingUnitUncertain, [ALine.Name, ALine.Macros,
      ALine.FileName, ALine.Line]);
  end
  else if ALine.Uncertain then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupUndefinedDefineUncertain,
      [ALine.Name, ALine.Macros,
      ALine.FileName, ALine.Line]);
  end
  else if ALine.Kind = TAtlasSetupFindingKind.MissingUnit then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupMissingUnit,
      [ALine.Name, ALine.FileName, ALine.Line]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupUndefinedDefine,
      [ALine.Name, ALine.FileName, ALine.Line]);
  end;
  if ALine.Count > 1 then
  begin
    Result := Result + ' ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupTimes, [ALine.Count]);
  end;
  // Tippfehler? Ähnliches bekanntes Symbol.
  if (ALine.Kind = TAtlasSetupFindingKind.UndefinedDefine) and (ALine.Note <> '') then
  begin
    Result := Result + ' – ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupSuggestion, [ALine.Note]);
  end;
  // Projektgruppe: Projekt vorn.
  if ALine.Project <> '' then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupFindingInProject, [ALine.Project, Result]);
  end;
end;

class function TAtlasSetupTexts.PathsCaption(const ACard: TAtlasSetupCard): string;
var
  mSetup: TAtlasProjectSetup;
  mParts: TArray<string>;
  mUncertain: Integer;
begin
  if ACard.Paths = TAtlasSetupRun.Failed then
  begin
    Exit(ACard.PathsError);
  end;
  mParts := nil;
  mSetup := ACard.Facts.Setup;
  // Projektgruppe: noch nicht alle Projekte geprüft.
  if (ACard.GroupProjects > 0) and (ACard.GroupChecked < ACard.GroupProjects) then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPathsGroup, [ACard.GroupChecked,
      ACard.GroupProjects])];
  end;
  if (mSetup.Checked or (ACard.GroupChecked > 0)) and (mSetup.MissingUnitCount + mSetup.UndefinedDefineCount > 0) then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPathsSummary, [mSetup.MissingUnitCount,
      mSetup.UndefinedDefineCount, mSetup.Files])];
  end;
  mUncertain := mSetup.UncertainUnitCount + mSetup.UncertainDefineCount;
  if mUncertain > 0 then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeSetupPathsUncertain, [mUncertain,
      TAtlasWelcomeSetup.MacroList(mSetup.SkippedMacros)])];
  end;
  Result := string.Join(sLineBreak, mParts);
end;

function TAtlasWelcomeSetupFrame.Button(AButton: TAtlasSetupButton): TButton;
begin
  Result := FButtons[AButton];
end;

function TAtlasWelcomeSetupFrame.StepMark(AStep: TAtlasSetupStep): TLabel;
begin
  Result := FLabels.Marks[AStep];
end;

function TAtlasWelcomeSetupFrame.StepText(AStep: TAtlasSetupStep): TLabel;
begin
  Result := FLabels.Texts[AStep];
end;

function TAtlasWelcomeSetupFrame.Finding(AIndex: Integer): TLabel;
begin
  Result := FLabels.Findings[AIndex];
end;

function TAtlasWelcomeSetupFrame.SelectedTemplate: TAtlasSetupTemplate;
begin
  Result := TAtlasSetupTemplate(EnsureRange(FTemplateIndex, Ord(Low(TAtlasSetupTemplate)),
    Ord(High(TAtlasSetupTemplate))));
end;

procedure TAtlasWelcomeSetupFrame.SelectTemplate(ATemplate: TAtlasSetupTemplate);
begin
  FTemplateIndex := Ord(ATemplate);
  if FTemplate.HandleAllocated and (FTemplate.Items.Count > FTemplateIndex) then
  begin
    FTemplate.ItemIndex := FTemplateIndex;
  end;
end;

procedure TAtlasWelcomeSetupFrame.TemplateChange(Sender: TObject);
begin
  if FTemplate.ItemIndex >= 0 then
  begin
    FTemplateIndex := FTemplate.ItemIndex;
  end;
end;

procedure TAtlasWelcomeSetupFrame.FillTemplates;
var
  mTemplate: TAtlasSetupTemplate;
begin
  // Die Liste braucht ein Fenster; Arrange ruft das erst mit Fenster.
  if FTemplate.Items.Count > 0 then
  begin
    Exit;
  end;
  FTemplate.Items.BeginUpdate;
  try
    for mTemplate := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
    begin
      FTemplate.Items.Add(TAtlasSetupTexts.TemplateCaption(mTemplate));
    end;
  finally
    FTemplate.Items.EndUpdate;
  end;
  FTemplate.ItemIndex := FTemplateIndex;
end;

procedure TAtlasWelcomeSetupFrame.SetSource(const AValue: IAtlasSetupSource);
begin
  FSource := AValue;
  UpdateContent;
end;

function TAtlasWelcomeSetupFrame.Running: Boolean;
begin
  Result := (FCard.Baseline = TAtlasSetupRun.Running) or (FCard.Paths = TAtlasSetupRun.Running);
end;

procedure TAtlasWelcomeSetupFrame.UpdateContent;
var
  mOldHeight: Integer;
begin
  mOldHeight := FContentHeight;
  if FSource <> nil then
  begin
    FCard := FSource.Card;
  end
  else
  begin
    FCard := TAtlasSetupCard.Empty;
  end;
  TSetupCardView.Create(Self).Apply;
  Arrange;
  inherited;
  if mOldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeSetupFrame.BodyResize(Sender: TObject);
var
  mOldHeight: Integer;
begin
  mOldHeight := FContentHeight;
  Arrange;
  // Andere Reihen bei neuer Breite: Der Frame „Atlas“ ordnet die Spalten neu.
  if mOldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeSetupFrame.Arrange;
var
  mLayout: TSetupLayout;
begin
  // Ohne Fenster lässt sich kein Text messen; CreateWnd holt UpdateContent nach.
  if FArranging or (FLabels.NewRow = nil) or not HasWindow then
  begin
    Exit;
  end;
  FArranging := True;
  try
    FillTemplates;
    mLayout := TSetupLayout.Create(Self);
    try
      FContentHeight := mLayout.Run;
    finally
      mLayout.Release;
    end;
  finally
    FArranging := False;
  end;
end;

function TAtlasWelcomeSetupFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  Arrange;
  Result := Max(FContentHeight, ScaleValue(32));
end;

procedure TAtlasWelcomeSetupFrame.TimerTick(Sender: TObject);
var
  mStep: TAtlasSetupStep;
begin
  if not Running then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  // Nur die Sekunden des laufenden Schritts; die Höhe bleibt.
  for mStep := TAtlasSetupStep.Baseline to TAtlasSetupStep.Paths do
  begin
    FLabels.Texts[mStep].Caption := TAtlasSetupTexts.StepCaption(mStep, FCard, TThread.GetTickCount64);
  end;
end;

procedure TAtlasWelcomeSetupFrame.ClickButton(AButton: TAtlasSetupButton);
var
  mSource: IAtlasSetupSource;
  mOpen: Boolean;
  mTemplate: TAtlasSetupTemplate;
begin
  if (FSource = nil) or not Clickable(AButton) then
  begin
    Exit;
  end;
  mSource := FSource;
  mOpen := FCard.ProjectOpen;
  mTemplate := SelectedTemplate;
  // Nicht im Klick des Knopfs: Vorschau und Projektoptionen sind modale Dialoge.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      RunSetupButton(mSource, AButton, mOpen, mTemplate);
    end);
end;

function TAtlasWelcomeSetupFrame.Clickable(AButton: TAtlasSetupButton): Boolean;
begin
  if AButton = TAtlasSetupButton.Dismiss then
  begin
    Result := FLabels.Dismiss.Visible;
  end
  else
  begin
    Result := FButtons[AButton].Visible and FButtons[AButton].Enabled;
  end;
end;

procedure TAtlasWelcomeSetupFrame.ButtonClick(Sender: TObject);
begin
  ClickButton(TAtlasSetupButton((Sender as TButton).Tag));
end;

procedure TAtlasWelcomeSetupFrame.DismissClick(Sender: TObject);
begin
  ClickButton(TAtlasSetupButton.Dismiss);
end;

procedure TAtlasWelcomeSetupFrame.FindingClick(Sender: TObject);
begin
  // Ein Fund führt zu den Projektoptionen (Suchpfade bzw. Defines).
  ClickButton(TAtlasSetupButton.Options);
end;

end.
