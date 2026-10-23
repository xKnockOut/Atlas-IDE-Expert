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

  TAtlasWelcomeSetupFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    Gap = 6;
    MarkWidth = 18;
    ButtonHeight = 24;
    ButtonPadding = 16;
    ComboWidth = 170;
    /// <summary>Grün wie die Marken der Projekte (#592), lesbar im hellen und im dunklen Thema.</summary>
    DoneColor = TColor($0043A02E);
  private
    FSource: IAtlasSetupSource;
    FCard: TAtlasSetupCard;
    FMarks: array[TAtlasSetupStep] of TLabel;
    FTexts: array[TAtlasSetupStep] of TLabel;
    FTemplate: TComboBox;
    FButtons: array[TAtlasSetupButton] of TButton;
    FBaselineInfo: TLabel;
    FPathsInfo: TLabel;
    FFindings: array[0..TAtlasWelcomeSetup.MaxLines - 1] of TLabel;
    FMore: TLabel;
    FDismiss: TLabel;
    FNewLabel: TLabel;
    FTimer: TTimer;
    FContentHeight: Integer;
    FArranging: Boolean;
    FTemplateIndex: Integer;
    procedure SetSource(const AValue: IAtlasSetupSource);
    function NewLabel: TLabel;
    /// <summary>Farbe des IDE-Themas (hell oder dunkel).</summary>
    function Themed(AColor: TColor): TColor;
    function NewButton(AButton: TAtlasSetupButton): TButton;
    procedure FillTemplates;
    procedure ApplyCard;
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
    property Source: IAtlasSetupSource read FSource write SetSource;
    property Card: TAtlasSetupCard read FCard;
    property BaselineInfo: TLabel read FBaselineInfo;
    property PathsInfo: TLabel read FPathsInfo;
    property MoreLabel: TLabel read FMore;
    property DismissLabel: TLabel read FDismiss;
    property NewRowLabel: TLabel read FNewLabel;
    property TemplateBox: TComboBox read FTemplate;
  end;

implementation

uses
  System.Math,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.UI.Strings;

const
  CheckMark = #$2713;
  OpenBox = #$2610;

{ TAtlasWelcomeSetupFrame }

constructor TAtlasWelcomeSetupFrame.Create(AOwner: TComponent);
var
  Step: TAtlasSetupStep;
  Kind: TAtlasSetupButton;
  Index: Integer;
begin
  inherited Create(AOwner);
  FCard := TAtlasSetupCard.Empty;
  for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
  begin
    FMarks[Step] := NewLabel;
    FMarks[Step].Font.Style := [fsBold];
    FTexts[Step] := NewLabel;
  end;
  FTemplate := TComboBox.Create(Self);
  FTemplate.Parent := Body;
  FTemplate.Style := csDropDownList;
  FTemplate.OnChange := TemplateChange;
  FTemplateIndex := Ord(TAtlasSetupTemplate.Existing);
  for Kind := Low(TAtlasSetupButton) to High(TAtlasSetupButton) do
    if Kind <> TAtlasSetupButton.Dismiss then
      FButtons[Kind] := NewButton(Kind);
  FBaselineInfo := NewLabel;
  FPathsInfo := NewLabel;
  for Index := Low(FFindings) to High(FFindings) do
  begin
    FFindings[Index] := NewLabel;
    FFindings[Index].Cursor := crHandPoint;
    FFindings[Index].OnClick := FindingClick;
  end;
  FMore := NewLabel;
  FDismiss := NewLabel;
  FDismiss.Font.Style := [fsUnderline];
  FDismiss.Cursor := crHandPoint;
  FDismiss.Caption := ButtonCaption(TAtlasSetupButton.Dismiss);
  FDismiss.OnClick := DismissClick;
  FNewLabel := NewLabel;
  FNewLabel.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewRow);
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

function TAtlasWelcomeSetupFrame.Themed(AColor: TColor): TColor;
begin
  Result := StyleServices(Self).GetSystemColor(AColor);
end;

function TAtlasWelcomeSetupFrame.NewButton(AButton: TAtlasSetupButton): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Body;
  Result.Caption := ButtonCaption(AButton);
  Result.Tag := Ord(AButton);
  Result.OnClick := ButtonClick;
end;

class function TAtlasWelcomeSetupFrame.TitleText(const ACard: TAtlasSetupCard): string;
begin
  if ACard.ShowCard and (ACard.ProjectName <> '') then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupTitle, [ACard.ProjectName])
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewTitle);
end;

class function TAtlasWelcomeSetupFrame.TemplateCaption(ATemplate: TAtlasSetupTemplate): string;
begin
  case ATemplate of
    TAtlasSetupTemplate.NewStrict:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupTemplateStrict);
    TAtlasSetupTemplate.Legacy:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupTemplateLegacy);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupTemplateExisting);
  end;
end;

class function TAtlasWelcomeSetupFrame.ButtonCaption(AButton: TAtlasSetupButton): string;
begin
  case AButton of
    TAtlasSetupButton.CreateConfig:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupConfigCreate);
    TAtlasSetupButton.Baseline:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupStart);
    TAtlasSetupButton.Paths:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupCheck);
    TAtlasSetupButton.Options:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupOptions);
    TAtlasSetupButton.Dismiss:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupDismiss);
    TAtlasSetupButton.NewUnit:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewUnit);
    TAtlasSetupButton.NewForm:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewForm);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupNewTest);
  end;
end;

class function TAtlasWelcomeSetupFrame.StepCaption(AStep: TAtlasSetupStep; const ACard: TAtlasSetupCard;
  ANow: UInt64): string;
begin
  case AStep of
    TAtlasSetupStep.Found:
      if ACard.Facts.ConfigExists then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupFound)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupFoundNoConfig);
    TAtlasSetupStep.Config:
      if ACard.StepDone(AStep) then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupConfigDone, [ACard.ConfigName])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupConfig);
    TAtlasSetupStep.Baseline:
      if ACard.Baseline = TAtlasSetupRun.Running then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupBaselineRunning,
          [TAtlasWelcomeSetup.Elapsed(ACard.BaselineStarted, ANow)])
      else if ACard.StepDone(AStep) then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupBaselineDone)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupBaseline);
  else
    if ACard.Paths = TAtlasSetupRun.Running then
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsRunning,
        [TAtlasWelcomeSetup.Elapsed(ACard.PathsStarted, ANow)])
    else if ACard.StepDone(AStep) then
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupPathsDone)
    else
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupPaths);
  end;
end;

class function TAtlasWelcomeSetupFrame.FindingCaption(const ALine: TAtlasSetupLine): string;
begin
  // Hinweis zu einem requires-Package (#759): kein Fehler.
  if (ALine.Kind = TAtlasSetupFindingKind.Hint) and (ALine.Note <> '') then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupRequiresInSearchPath, [ALine.Note, ALine.Name,
      ALine.FileName, ALine.Line])
  else if ALine.Kind = TAtlasSetupFindingKind.Hint then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupRequiresNoSource, [ALine.Name, ALine.FileName, ALine.Line])
  // Unsicher (Suchpfad mit unbekanntem Makro übersprungen): mit den Makros, damit es nicht wie ein Fehler wirkt.
  else if ALine.Uncertain and (ALine.Kind = TAtlasSetupFindingKind.MissingUnit) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupMissingUnitUncertain, [ALine.Name, ALine.Macros,
      ALine.FileName, ALine.Line])
  else if ALine.Uncertain then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupUndefinedDefineUncertain, [ALine.Name, ALine.Macros,
      ALine.FileName, ALine.Line])
  else if ALine.Kind = TAtlasSetupFindingKind.MissingUnit then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupMissingUnit, [ALine.Name, ALine.FileName, ALine.Line])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupUndefinedDefine, [ALine.Name, ALine.FileName, ALine.Line]);
  if ALine.Count > 1 then
    Result := Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupTimes, [ALine.Count]);
  // Tippfehler? Ähnliches bekanntes Symbol.
  if (ALine.Kind = TAtlasSetupFindingKind.UndefinedDefine) and (ALine.Note <> '') then
    Result := Result + ' – ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupSuggestion, [ALine.Note]);
  // Projektgruppe: Projekt vorn.
  if ALine.Project <> '' then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupFindingInProject, [ALine.Project, Result]);
end;

class function TAtlasWelcomeSetupFrame.PathsCaption(const ACard: TAtlasSetupCard): string;
var
  Setup: TAtlasProjectSetup;
  Parts: TArray<string>;
  Uncertain: Integer;
begin
  if ACard.Paths = TAtlasSetupRun.Failed then
    Exit(ACard.PathsError);
  Parts := nil;
  Setup := ACard.Facts.Setup;
  // Projektgruppe: noch nicht alle Projekte geprüft.
  if (ACard.GroupProjects > 0) and (ACard.GroupChecked < ACard.GroupProjects) then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsGroup, [ACard.GroupChecked,
      ACard.GroupProjects])];
  if (Setup.Checked or (ACard.GroupChecked > 0)) and (Setup.MissingUnitCount + Setup.UndefinedDefineCount > 0) then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsSummary, [Setup.MissingUnitCount,
      Setup.UndefinedDefineCount, Setup.Files])];
  Uncertain := Setup.UncertainUnitCount + Setup.UncertainDefineCount;
  if Uncertain > 0 then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupPathsUncertain, [Uncertain,
      TAtlasWelcomeSetup.MacroList(Setup.SkippedMacros)])];
  Result := string.Join(sLineBreak, Parts);
end;

function TAtlasWelcomeSetupFrame.Button(AButton: TAtlasSetupButton): TButton;
begin
  Result := FButtons[AButton];
end;

function TAtlasWelcomeSetupFrame.StepMark(AStep: TAtlasSetupStep): TLabel;
begin
  Result := FMarks[AStep];
end;

function TAtlasWelcomeSetupFrame.StepText(AStep: TAtlasSetupStep): TLabel;
begin
  Result := FTexts[AStep];
end;

function TAtlasWelcomeSetupFrame.Finding(AIndex: Integer): TLabel;
begin
  Result := FFindings[AIndex];
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
    FTemplate.ItemIndex := FTemplateIndex;
end;

procedure TAtlasWelcomeSetupFrame.TemplateChange(Sender: TObject);
begin
  if FTemplate.ItemIndex >= 0 then
    FTemplateIndex := FTemplate.ItemIndex;
end;

procedure TAtlasWelcomeSetupFrame.FillTemplates;
var
  Template: TAtlasSetupTemplate;
begin
  // Die Liste braucht ein Fenster; Arrange ruft das erst mit Fenster.
  if FTemplate.Items.Count > 0 then
    Exit;
  for Template := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
    FTemplate.Items.Add(TemplateCaption(Template));
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
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  if FSource <> nil then
    FCard := FSource.Card
  else
    FCard := TAtlasSetupCard.Empty;
  ApplyCard;
  Arrange;
  inherited;
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeSetupFrame.ApplyCard;
var
  Step: TAtlasSetupStep;
  Done, Open, Show: Boolean;
  Lines: TArray<TAtlasSetupLine>;
  More, Index: Integer;
  Kind: TAtlasNewFileKind;
  Setup: TAtlasSetupButton;
begin
  Show := FCard.ShowCard;
  Open := FCard.ProjectOpen;
  FBaselineInfo.Font.Color := Themed(clGrayText);
  FPathsInfo.Font.Color := Themed(clGrayText);
  FMore.Font.Color := Themed(clGrayText);
  FNewLabel.Font.Color := Themed(clWindowText);
  FDismiss.Font.Color := Themed(clHotLight);
  for Index := Low(FFindings) to High(FFindings) do
    FFindings[Index].Font.Color := Themed(clWindowText);
  for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
  begin
    Done := FCard.StepDone(Step);
    FMarks[Step].Visible := Show;
    FTexts[Step].Visible := Show;
    if Done then
    begin
      FMarks[Step].Caption := CheckMark;
      FMarks[Step].Font.Color := DoneColor;
      FTexts[Step].Font.Color := DoneColor;
    end
    else
    begin
      FMarks[Step].Caption := OpenBox;
      FMarks[Step].Font.Color := Themed(clWindowText);
      FTexts[Step].Font.Color := Themed(clWindowText);
    end;
    FTexts[Step].Caption := StepCaption(Step, FCard, TThread.GetTickCount64);
  end;
  // Schritt 2: Auswahl und „Anlegen …“, solange keine Datei da ist.
  FTemplate.Visible := Show and not FCard.StepDone(TAtlasSetupStep.Config);
  FButtons[TAtlasSetupButton.CreateConfig].Visible := FTemplate.Visible;
  // Schritt 3 und 4: Knopf, solange offen; ohne geöffnetes Projekt „Projekt öffnen“.
  FButtons[TAtlasSetupButton.Baseline].Visible := Show and not FCard.StepDone(TAtlasSetupStep.Baseline);
  FButtons[TAtlasSetupButton.Paths].Visible := Show and not FCard.StepDone(TAtlasSetupStep.Paths);
  if Open then
  begin
    FButtons[TAtlasSetupButton.Baseline].Caption := ButtonCaption(TAtlasSetupButton.Baseline);
    FButtons[TAtlasSetupButton.Paths].Caption := ButtonCaption(TAtlasSetupButton.Paths);
  end
  else
  begin
    FButtons[TAtlasSetupButton.Baseline].Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupOpenProject);
    FButtons[TAtlasSetupButton.Paths].Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSetupOpenProject);
  end;
  FButtons[TAtlasSetupButton.Baseline].Enabled := (FSource <> nil) and (FCard.Baseline <> TAtlasSetupRun.Running);
  FButtons[TAtlasSetupButton.Paths].Enabled := (FSource <> nil) and (FCard.Paths <> TAtlasSetupRun.Running);
  FButtons[TAtlasSetupButton.CreateConfig].Enabled := FSource <> nil;
  // Ergebnis bzw. Fehler unter Baseline und Prüfung.
  FBaselineInfo.Caption := '';
  // Nach dem Erzeugen in dieser Sitzung: Treffer der Baseline und neue Treffer (dann 0).
  if (FCard.Baseline = TAtlasSetupRun.Done) and (FCard.BaselineNewHits >= 0) then
    FBaselineInfo.Caption := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupBaselineResult, [FCard.BaselineTotal,
      FCard.BaselineFiles, FCard.BaselineNewHits])
  else if FCard.Baseline = TAtlasSetupRun.Failed then
    FBaselineInfo.Caption := FCard.BaselineError;
  FBaselineInfo.Visible := Show and (FBaselineInfo.Caption <> '');
  FPathsInfo.Caption := PathsCaption(FCard);
  FPathsInfo.Visible := Show and (FPathsInfo.Caption <> '');
  Lines := nil;
  More := 0;
  if Show and (FCard.Paths <> TAtlasSetupRun.Running) then
    Lines := TAtlasWelcomeSetup.Lines(FCard.Facts.Setup, Length(FFindings), More);
  for Index := Low(FFindings) to High(FFindings) do
  begin
    FFindings[Index].Visible := Index < Length(Lines);
    if FFindings[Index].Visible then
      FFindings[Index].Caption := FindingCaption(Lines[Index]);
  end;
  FMore.Visible := More > 0;
  if FMore.Visible then
    FMore.Caption := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSetupMore, [More]);
  FButtons[TAtlasSetupButton.Options].Visible := Length(Lines) > 0;
  FButtons[TAtlasSetupButton.Options].Enabled := FSource <> nil;
  FDismiss.Visible := Show;
  // Neu mit Atlas.
  FNewLabel.Visible := FCard.ShowNew;
  for Kind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
  begin
    Setup := TAtlasSetupButton(Ord(TAtlasSetupButton.NewUnit) + Ord(Kind));
    FButtons[Setup].Visible := FCard.ShowNew;
    FButtons[Setup].Enabled := FSource <> nil;
  end;
  FTimer.Enabled := Running;
end;

procedure TAtlasWelcomeSetupFrame.BodyResize(Sender: TObject);
var
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  Arrange;
  // Andere Reihen bei neuer Breite: Der Frame „Atlas“ ordnet die Spalten neu.
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeSetupFrame.Arrange;
var
  mLeft, TextLeft, Right, mTop, X, RowHeight, Wide: Integer;
  Measure: TBitmap;
  Step: TAtlasSetupStep;
  Index: Integer;
  Kind: TAtlasNewFileKind;
  Setup: TAtlasSetupButton;

  function ButtonWidth(AButton: TButton): Integer;
  begin
    Result := Measure.Canvas.TextWidth(AButton.Caption) + 2 * ScaleValue(ButtonPadding);
  end;

  /// <summary>Setzt AControl rechts neben X in die Reihe, bei zu wenig Platz in eine neue Reihe ab TextLeft.
  /// </summary>
  procedure Place(AControl: TControl; AWidth, AHeight: Integer);
  begin
    if (X > TextLeft) and (X + AWidth > Right) then
    begin
      X := TextLeft;
      Inc(mTop, RowHeight + ScaleValue(Gap) div 2);
      RowHeight := 0;
    end;
    AControl.SetBounds(X, mTop, AWidth, AHeight);
    Inc(X, AWidth + ScaleValue(Gap));
    RowHeight := Max(RowHeight, AHeight);
  end;

  procedure NextRow;
  begin
    if RowHeight > 0 then
      Inc(mTop, RowHeight + ScaleValue(Gap) div 2);
    RowHeight := 0;
    X := TextLeft;
  end;

  procedure PlaceLine(ALabel: TLabel);
  begin
    if not ALabel.Visible then
      Exit;
    X := TextLeft;
    Place(ALabel, Measure.Canvas.TextWidth(ALabel.Caption), ALabel.Height);
    NextRow;
  end;

begin
  // Ohne Fenster lässt sich kein Text messen; CreateWnd holt UpdateContent nach.
  if FArranging or (FNewLabel = nil) or not HasWindow then
    Exit;
  FArranging := True;
  try
    FillTemplates;
    // Breite des Frames statt der Inhaltsfläche: Die richtet sich erst später nach dem Frame aus.
    mLeft := ScaleValue(Indent);
    TextLeft := mLeft + ScaleValue(MarkWidth);
    Right := ClientWidth - ScaleValue(Indent);
    mTop := ScaleValue(Gap) div 2;
    RowHeight := 0;
    X := TextLeft;
    Measure := TBitmap.Create;
    try
      Measure.Canvas.Font.Assign(Font);
      if FCard.ShowCard then
      begin
        for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
        begin
          FMarks[Step].SetBounds(mLeft, mTop + ScaleValue(4), ScaleValue(MarkWidth), FMarks[Step].Height);
          X := TextLeft;
          Wide := Measure.Canvas.TextWidth(FTexts[Step].Caption);
          // Text etwas tiefer, damit er mittig neben den Knöpfen steht.
          Place(FTexts[Step], Wide, FTexts[Step].Height);
          FTexts[Step].Top := mTop + ScaleValue(4);
          RowHeight := Max(RowHeight, ScaleValue(ButtonHeight));
          case Step of
            TAtlasSetupStep.Config:
              if FTemplate.Visible then
              begin
                Place(FTemplate, ScaleValue(ComboWidth), FTemplate.Height);
                Place(FButtons[TAtlasSetupButton.CreateConfig],
                  ButtonWidth(FButtons[TAtlasSetupButton.CreateConfig]), ScaleValue(ButtonHeight));
              end;
            TAtlasSetupStep.Baseline:
              if FButtons[TAtlasSetupButton.Baseline].Visible then
                Place(FButtons[TAtlasSetupButton.Baseline], ButtonWidth(FButtons[TAtlasSetupButton.Baseline]),
                  ScaleValue(ButtonHeight));
            TAtlasSetupStep.Paths:
              if FButtons[TAtlasSetupButton.Paths].Visible then
                Place(FButtons[TAtlasSetupButton.Paths], ButtonWidth(FButtons[TAtlasSetupButton.Paths]),
                  ScaleValue(ButtonHeight));
          else
            // Übrige Werte bewusst ohne Wirkung.
          end;
          NextRow;
          if Step = TAtlasSetupStep.Baseline then
            PlaceLine(FBaselineInfo);
          if Step = TAtlasSetupStep.Paths then
          begin
            PlaceLine(FPathsInfo);
            for Index := Low(FFindings) to High(FFindings) do
              PlaceLine(FFindings[Index]);
            PlaceLine(FMore);
            if FButtons[TAtlasSetupButton.Options].Visible then
            begin
              Place(FButtons[TAtlasSetupButton.Options], ButtonWidth(FButtons[TAtlasSetupButton.Options]),
                ScaleValue(ButtonHeight));
              NextRow;
            end;
          end;
        end;
        X := mLeft;
        Place(FDismiss, Measure.Canvas.TextWidth(FDismiss.Caption), FDismiss.Height);
        FDismiss.Left := mLeft;
        NextRow;
      end;
      if FCard.ShowNew then
      begin
        Inc(mTop, ScaleValue(Gap) div 2);
        X := mLeft;
        Place(FNewLabel, Measure.Canvas.TextWidth(FNewLabel.Caption), FNewLabel.Height);
        FNewLabel.Left := mLeft;
        FNewLabel.Top := mTop + ScaleValue(4);
        RowHeight := Max(RowHeight, ScaleValue(ButtonHeight));
        X := mLeft + Measure.Canvas.TextWidth(FNewLabel.Caption) + ScaleValue(Gap);
        for Kind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
        begin
          Setup := TAtlasSetupButton(Ord(TAtlasSetupButton.NewUnit) + Ord(Kind));
          Place(FButtons[Setup], ButtonWidth(FButtons[Setup]), ScaleValue(ButtonHeight));
        end;
        NextRow;
      end;
    finally
      Measure.Free;
    end;
    FContentHeight := mTop + ScaleValue(Gap) div 2;
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
  Step: TAtlasSetupStep;
begin
  if not Running then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  // Nur die Sekunden des laufenden Schritts; die Höhe bleibt.
  for Step := TAtlasSetupStep.Baseline to TAtlasSetupStep.Paths do
    FTexts[Step].Caption := StepCaption(Step, FCard, TThread.GetTickCount64);
end;

procedure TAtlasWelcomeSetupFrame.ClickButton(AButton: TAtlasSetupButton);
var
  mSource: IAtlasSetupSource;
  Open: Boolean;
  Template: TAtlasSetupTemplate;
begin
  if FSource = nil then
    Exit;
  if (AButton <> TAtlasSetupButton.Dismiss) and not (FButtons[AButton].Visible and FButtons[AButton].Enabled) then
    Exit;
  if (AButton = TAtlasSetupButton.Dismiss) and not FDismiss.Visible then
    Exit;
  mSource := FSource;
  Open := FCard.ProjectOpen;
  Template := SelectedTemplate;
  // Nicht im Klick des Knopfs: Vorschau und Projektoptionen sind modale Dialoge.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      case AButton of
        TAtlasSetupButton.CreateConfig:
          mSource.CreateConfig(Template);
        TAtlasSetupButton.Baseline:
          if Open then
            mSource.StartBaseline
          else
            mSource.OpenProject;
        TAtlasSetupButton.Paths:
          if Open then
            mSource.CheckPaths
          else
            mSource.OpenProject;
        TAtlasSetupButton.Options:
          mSource.OpenOptions;
        TAtlasSetupButton.Dismiss:
          mSource.Dismiss;
        TAtlasSetupButton.NewUnit:
          mSource.NewFile(TAtlasNewFileKind.UnitFile);
        TAtlasSetupButton.NewForm:
          mSource.NewFile(TAtlasNewFileKind.FormFile);
      else
        mSource.NewFile(TAtlasNewFileKind.TestFile);
      end;
    end);
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
