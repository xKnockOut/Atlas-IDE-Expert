unit Atlas.UI.Problems.Frame;

// Inhalt des Fensters „Atlas-Prüfung“ (#909), reine VCL. Oben die
// Werkzeugleiste: Bereich (aktuelle Datei, aktuelles Projekt, Projektgruppe,
// bei offener Gruppe darunter die einzelnen Projekte, #1843), je Art ein
// Umschalter mit Anzahl, Kategorie, Gruppierung, Textfilter und rechts die
// Anzeige „Live“ bzw. „Angehalten“. Darunter die Liste (virtuell, ohne
// Flackern) mit den Spalten aus TAtlasFindingColumn: Icon (rotes Kreuz,
// gelb-oranges Dreieck, blauer Kreis), Art, Kategorie, Meldung, Zeile (gekürzt,
// Tooltip mit ganzer Zeile), Stelle, Regel und Compiler (#1024: Code, bei
// bestätigten Befunden „Atlas + dcc“). Reihenfolge (Spaltenkopf ziehen),
// Breite und Sichtbarkeit (Kontextmenü „Spalten“, nur Meldung, Regel und
// Compiler) liefert ColumnsText für problems.window.columns. Mit
// ShowCompilerCode aus (problems.showCompilerCode) fehlt die Spalte Compiler,
// und die Meldungen stehen ohne „(wie E2035)“. Klick auf den
// Spaltenkopf sortiert, ein zweiter kehrt um. Gruppenzeilen (▾/▸ Name, Anzahl)
// klappen per Klick, Leertaste oder ←/→. Unten die Statuszeile.
// Bedienung: Doppelklick oder Enter springt (OnOpen), Alt+Enter wendet die
// Schnellkorrektur an (OnFix), Strg+C kopiert die Auswahl. Kontextmenü:
// Gehe zu, Schnellkorrektur, „Alle sicheren Treffer von <Regel> korrigieren …“
// (#1352, OnFixAll; nur mit CanFixAll, fix.bulk), „Für diese Zeile
// unterdrücken“, „Regel einstellen…“, „Regel abschalten“, „Regel erklären“, Kopieren, Spalten,
// Sortierung zurücksetzen. Neue Einträge werden kurz hervorgehoben.
// Den Inhalt (SetFindings) und die Statuszeile setzt die IDE-Schicht; Auswahl,
// Aufklappzustand und Bildlauf bleiben dabei erhalten (TAtlasFindingsView).
// Offene Units zuerst (#1108): Umschaltknopf „Offene zuerst“ (Nadel) neben
// der Gruppierung; die Gruppe bzw. die Zeilen der aktiven Unit hinterlegt in
// Akzentfarbe mit Nadel und „aktiver Editor“, Trennzeilen „Geöffnet“ und
// „Nicht geöffnet“ über die ganze Zeile, nicht geöffnete Units ausgegraut
// (Text mit mindestens 4,5 : 1, Symbole aufgehellt in gleicher Form) und
// voll bedienbar. Trennzeilen lassen sich nicht wählen; ↑/↓ springen über sie.
// Wechselt die aktive Unit, bleibt die Auswahl sichtbar, ohne Auswahl steht
// die oberste Zeile oben.
// Fehler der IDE (#1819, problems.ideErrors): Mit ShowIdeErrors gibt es die
// Spalte „Quelle“ (Atlas, Atlas + IDE, IDE) und rechts neben dem Textfilter
// die Auswahl „Atlas und IDE“, „nur Atlas“, „nur IDE“; ohne fehlen beide.
// Ereignisse, Steuerelemente und die virtuelle Liste mit Spalten und Zellen stehen in
// Atlas.UI.Problems.Frame.List; hier Aufbau, Leiste, Tasten und Kontextmenü.
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.ImgList,
  Vcl.Forms,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.ScopeProjects,
  Atlas.Core.Settings.ProblemsUpdate,
  Atlas.UI.Problems.ScopeBox,
  Atlas.UI.Problems.Frame.List;

type
  /// <summary>Kontextmenü und Aktionen auf markierten Befunden.</summary>
  TAtlasProblemsFrameMenu = class(TAtlasProblemsFrameList)
  private
    FOpenItem: TMenuItem;
    FFixItem: TMenuItem;
    FFixAllItem: TMenuItem;
    FSuppressItem: TMenuItem;
    FConfigureItem: TMenuItem;
    FDisableItem: TMenuItem;
    FExplainItem: TMenuItem;
    FIssueItem: TMenuItem;
    FCopyItem: TMenuItem;
    FResetSortItem: TMenuItem;
    function SelectedRows: TArray<Integer>;
    function Current(out AFinding: TAtlasFinding): Boolean;
    function IsRule(const AFinding: TAtlasFinding): Boolean;
    /// <summary>Einträge der Regel-Aktionen nach CanRuleActions zeigen und freigeben.</summary>
    procedure ShowRuleActions(ACanSuppress, ARule: Boolean);
    procedure Fire(const AEvent: TAtlasFindingEvent);
    procedure MenuPopup(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure FixClick(Sender: TObject);
    procedure FixAllClick(Sender: TObject);
    procedure SuppressClick(Sender: TObject);
    procedure ConfigureClick(Sender: TObject);
    procedure DisableClick(Sender: TObject);
    procedure ExplainClick(Sender: TObject);
    procedure IssueClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ResetSortClick(Sender: TObject);
    /// <summary>Kontextmenü der Liste anlegen.</summary>
    procedure BuildMenu;
  public
    procedure CopySelection;
    /// <summary>Markierte Befunde ohne Gruppen- und Trennzeilen, in Anzeigereihenfolge.</summary>
    function SelectedFindings: TArray<TAtlasFinding>;
  end;

  TAtlasProblemsFrame = class(TAtlasProblemsFrameMenu)
  private
    /// <summary>Leiste mit Bereich, Arten, Kategorie, Gruppierung, „Offene zuerst“ und Filter.</summary>
    procedure BuildBar;
    /// <summary>Rechter Teil der Leiste: „Offene zuerst“, Filter und „Live“.</summary>
    procedure BuildTools;
    /// <summary>Statuszeile, Symbole, Kontextmenü, Liste und Hinweis ohne Befunde.</summary>
    procedure BuildList;
    function FilterFromControls: TAtlasFindingFilter;
    /// <summary>Nach neuen Befunden: Hervorhebung neu starten, Liste neu füllen.</summary>
    procedure FindingsChanged;
    /// <summary>Hat die aktive Unit seit ABefore gewechselt: Auswahl bzw. oberste Zeile sichtbar halten.</summary>
    procedure KeepInView(const ABefore: string);
    procedure ControlsChanged(Sender: TObject);
    procedure ScopeChange(Sender: TObject);
    procedure GroupingChange(Sender: TObject);
    procedure OpenFirstClick(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    /// <summary>↑/↓ über Trennzeilen hinweg; True, wenn die Taste verarbeitet ist.</summary>
    function MoveKey(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Enter, Leertaste, Links/Rechts und Strg+C; True, wenn die Taste verarbeitet ist.</summary>
    function ActionKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure NewTimerTick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Einstellungen übernehmen: Bereich, Gruppierung, Spalten (problems.window.columns) und
    /// Compilermeldungen.</summary>
    procedure ApplySettings(AScope: TAtlasFindingScope; AGrouping: TAtlasFindingGrouping; const AColumns: string;
      ACompiler: Boolean);
    /// <summary>Einzelprojekte in der Bereichsliste (#1843): problems.window.scopeProjects und das gespeicherte
    /// Projekt (problems.window.scopeProject; gilt nur bei Bereich „Projekt“).</summary>
    procedure ApplyScopeSettings(AShowProjects: Boolean; const AProject: string);
    /// <summary>Projekte der offenen Gruppe (#1843). Fehlt das gewählte Einzelprojekt, gilt das aktive Projekt und
    /// OnLayout speichert das.</summary>
    procedure SetScopeProjects(const AProjects: TArray<TAtlasScopeProject>);
    /// <summary>Offene Units zuerst (#1108): problems.window.openFirst, .closedUnits, .showCleanActive.</summary>
    procedure ApplyTierSettings(AOpenFirst: Boolean; AClosedUnits: TAtlasClosedUnits; AShowCleanActive: Boolean);
    /// <summary>Aktive und geöffnete Dateien (#1108); AActiveChecked: der Server hat die aktive Datei geliefert.
    /// Hält die Auswahl sichtbar bzw. ohne Auswahl die oberste Zeile oben, wenn die aktive Unit wechselt.</summary>
    procedure SetOpenFiles(const AActive: string; const AOpen: TArray<string>; AActiveChecked: Boolean);
    /// <summary>Neuer Stand; ACurrentFile und AFiles bestimmen den Bereich (siehe TAtlasFindingFilter).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
      const AFiles: TArray<string>); overload;
    /// <summary>Neuer Stand samt aktiver und geöffneter Dateien in einem Schritt: ein Neuaufbau der Liste statt
    /// drei. Wirkt wie SetFindings und danach SetOpenFiles(ACurrentFile, AOpen, AActiveChecked).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
      const AFiles, AOpen: TArray<string>; AActiveChecked: Boolean); overload;
    procedure SetStatus(const AText: string);
    /// <summary>Anzeige nach problems.update: „Live“, „Beim Speichern“ oder „Manuell“; ohne Live-Prüfung mit dem
    /// Knopf „Datei jetzt prüfen“.</summary>
    procedure SetUpdate(AMode: TAtlasProblemsUpdate);
    /// <summary>Markierung folgt dem Cursor (problems.window.followCursor).</summary>
    procedure FollowCursor(const AFileName: string; ALine: Integer);
    /// <summary>F8/Umschalt+F8 aus dem Editor: nächster bzw. vorheriger Befund der gefilterten Liste.</summary>
    function Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
  end;

implementation

uses
  Atlas.Core.Problems.FindingsView,
  System.Math,
  Winapi.CommCtrl,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Problems.Explanation,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings;

{$R *.dfm}

const
  /// <summary>Breite der Bereichsliste bei 96 dpi; die Klappliste wird so breit wie der längste Eintrag (#1843).
  /// </summary>
  cScopeWidth = 130;
  /// <summary>Filter „Quelle“ (#1819): Breite und Abstand zum Textfilter bei 96 dpi.</summary>
  cOriginWidth = 110;
  cOriginGap = 4;
  /// <summary>Abstand oben der Live-Anzeige in der Leiste bei 96 dpi.</summary>
  cLiveTop = 6;
  /// <summary>Hervorhebung neuer Einträge.</summary>
  cNewMs = 1500;
  cIconSize = 16;

{ TAtlasProblemsFrame }

procedure TAtlasProblemsFrameMenu.BuildMenu;
begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuOpen), OpenClick);
  FOpenItem.Default := True;
  FFixItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuFixNone), FixClick);
  FFixItem.ShortCut := ShortCut(VK_RETURN, [ssAlt]);
  FFixAllItem := AddMenuItem(nil, TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, ['…']),
    FixAllClick);
  FFixAllItem.Visible := False;
  FSuppressItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuSuppress), SuppressClick);
  FMenu.Items.Add(NewLine);
  FConfigureItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuConfigure), ConfigureClick);
  FDisableItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuDisable), DisableClick);
  FExplainItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplain), ExplainClick);
  FIssueItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCreateIssue), IssueClick);
  FIssueItem.Visible := False;
  FMenu.Items.Add(NewLine);
  FCopyItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCopy), CopyClick);
  FCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  FColumnsItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuColumns), nil);
  FResetSortItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuResetSort),
    ResetSortClick);
end;

procedure TAtlasProblemsFrame.BuildBar;
var
  mKind: TAtlasFindingKind;
  mButton: TSpeedButton;
  mLeft: Integer;
begin
  // Fließende Leiste: Ist das Fenster schmal, brechen die Bedienelemente in weitere Zeilen um, statt
  // abgeschnitten zu werden (vorher feste Left-Positionen in einem Panel fester Höhe).
  FBar := TFlowPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.AutoWrap := True;
  FBar.AutoSize := True;
  FBar.ParentBackground := True;

  FScope := AddCombo(cScopeWidth);
  FScope.OnChange := ScopeChange;
  FScopeBox := TAtlasProblemsScopeBox.Create(Self, FScope, TArray<string>.Create(
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)));
  mLeft := FScope.Left + FScope.Width + MulDiv(6, CurrentPPI, 96);
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    mButton := TSpeedButton.Create(Self);
    mButton.Parent := FBar;
    mButton.AlignWithMargins := True;
    mButton.Top := MulDiv(2, CurrentPPI, 96);
    mButton.Height := MulDiv(22, CurrentPPI, 96);
    mButton.Width := MulDiv(78, CurrentPPI, 96);
    mButton.Left := mLeft;
    mButton.Flat := True;
    // Je Umschalter eine eigene Gruppe: unabhängig an und aus.
    mButton.GroupIndex := Ord(mKind) + 1;
    mButton.AllowAllUp := True;
    mButton.Down := True;
    mButton.OnClick := ControlsChanged;
    FKinds[mKind] := mButton;
    Inc(mLeft, mButton.Width + MulDiv(2, CurrentPPI, 96));
  end;
  FCategoryTexts := [TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryAll),
    CategoryText(TAtlasFindingCategory.Bug), CategoryText(TAtlasFindingCategory.Vulnerability),
    CategoryText(TAtlasFindingCategory.CodeSmell), CategoryText(TAtlasFindingCategory.SecurityHotspot),
    CategoryText(TAtlasFindingCategory.Compiler), CategoryText(TAtlasFindingCategory.Other)];
  FCategory := AddCombo(130);
  FCategory.Left := mLeft + MulDiv(4, CurrentPPI, 96);
  FCategory.OnChange := ControlsChanged;
  FGroupingTexts := [TAtlasStrings.Text(TAtlasTextId.ProblemsGroupNone),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupFile), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupRule),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupCategory)];
  FGrouping := AddCombo(120);
  FGrouping.Left := FCategory.Left + FCategory.Width + MulDiv(4, CurrentPPI, 96);
  FGrouping.OnChange := GroupingChange;
end;

procedure TAtlasProblemsFrame.BuildTools;
begin
  // Offene Units zuerst (#1108): gedrückt = an; eigene Gruppe, damit er allein an und aus geht.
  FOpenFirst := TSpeedButton.Create(Self);
  FOpenFirst.Parent := FBar;
  FOpenFirst.AlignWithMargins := True;
  FOpenFirst.Top := MulDiv(2, CurrentPPI, 96);
  FOpenFirst.Height := MulDiv(22, CurrentPPI, 96);
  FOpenFirst.Width := MulDiv(110, CurrentPPI, 96);
  FOpenFirst.Left := FGrouping.Left + FGrouping.Width + MulDiv(4, CurrentPPI, 96);
  FOpenFirst.Flat := True;
  FOpenFirst.GroupIndex := Ord(High(TAtlasFindingKind)) + 2;
  FOpenFirst.AllowAllUp := True;
  FOpenFirst.Caption := cPinMark + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOpenFirst);
  FOpenFirst.Hint := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOpenFirstHint);
  FOpenFirst.ShowHint := True;
  FOpenFirst.OnClick := OpenFirstClick;
  FFilter := TEdit.Create(Self);
  FFilter.Parent := FBar;
  FFilter.AlignWithMargins := True;
  FFilter.Top := MulDiv(3, CurrentPPI, 96);
  FFilter.Left := FOpenFirst.Left + FOpenFirst.Width + MulDiv(4, CurrentPPI, 96);
  FFilter.Width := MulDiv(200, CurrentPPI, 96);
  FFilter.TextHint := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsFilterHint);
  FFilter.OnChange := ControlsChanged;
  FFilter.OnKeyDown := FilterKeyDown;
  // Filter „Quelle“ (#1819): erst mit ShowIdeErrors sichtbar.
  FOriginTexts := [TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginAll),
    TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginAtlas),
    TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginIde)];
  FOrigin := AddCombo(cOriginWidth);
  FOrigin.Left := FFilter.Left + FFilter.Width + MulDiv(cOriginGap, CurrentPPI, 96);
  FOrigin.Visible := False;
  FOrigin.OnChange := ControlsChanged;
  FLive := TLabel.Create(Self);
  FLive.Parent := FBar;
  FLive.AlignWithMargins := True;
  // Breite nach dem Text (live, beim Speichern, manuell): AutoSize, in der Leiste vertikal etwas abgesetzt.
  FLive.AutoSize := True;
  FLive.Margins.Top := MulDiv(cLiveTop, CurrentPPI, 96);
  FLive.ShowAccelChar := False;
  FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsLive);
end;

procedure TAtlasProblemsFrame.BuildList;
begin
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.Font.Color := clGrayText;
  FStatus.Caption := '';

  FImages := TImageList.Create(Self);
  FImages.Width := MulDiv(cIconSize, CurrentPPI, 96);
  FImages.Height := FImages.Width;

  BuildMenu;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := True;
  FList.ColumnClick := True;
  // Spaltenköpfe lassen sich ziehen (Reihenfolge).
  FList.FullDrag := True;
  FList.ShowHint := True;
  FList.SmallImages := FImages;
  FList.PopupMenu := FMenu;
  FList.OnData := ListData;
  FList.OnSelectItem := ListSelectItem;
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnColumnClick := ListColumnClick;
  FList.OnInfoTip := ListInfoTip;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnMouseUp := ListMouseUp;

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsEmpty);
  FEmpty.Visible := False;

  FNewTimer := TTimer.Create(Self);
  FNewTimer.Enabled := False;
  FNewTimer.Interval := cNewMs;
  FNewTimer.OnTimer := NewTimerTick;
end;

constructor TAtlasProblemsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FView := TAtlasFindingsView.Create;
  BuildBar;
  BuildTools;
  // Statuszeile, Symbole, Kontextmenü, Liste: in dieser Reihenfolge, die Ausrichtung hängt daran.
  BuildList;
  FColumns := TAtlasFindings.ParseColumns('');
  FShowCompilerCode := True;
  BuildImages;
  BuildColumns;
  UpdateKindCaptions;
end;

destructor TAtlasProblemsFrame.Destroy;
begin
  FreeAndNil(FView);
  FreeAndNil(FScopeBox);
  inherited Destroy;
end;

procedure TAtlasProblemsFrame.CreateWnd;
var
  mCategory: Integer;
begin
  inherited CreateWnd;
  // Die Einträge der Auswahllisten brauchen ein Fenster: erst jetzt füllen, Auswahl aus dem Modell.
  mCategory := 0;
  if FView.Filter.OneCategory then
  begin
    mCategory := Ord(FView.Filter.Category) + 1;
  end;
  FUpdating := True;
  try
    FScopeBox.Fill;
    FillCombo(FCategory, FCategoryTexts, mCategory);
    FillCombo(FGrouping, FGroupingTexts, Ord(FView.Grouping));
    FillCombo(FOrigin, FOriginTexts, Ord(FView.Filter.Origin));
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasProblemsFrame.ApplySettings(AScope: TAtlasFindingScope; AGrouping: TAtlasFindingGrouping;
  const AColumns: string; ACompiler: Boolean);
var
  mFilter: TAtlasFindingFilter;
begin
  FUpdating := True;
  try
    FScopeBox.Select(TAtlasScopeChoice.Create(AScope, FScopeBox.Choice.Project));
    if FGrouping.Items.Count > Ord(AGrouping) then
    begin
      FGrouping.ItemIndex := Ord(AGrouping);
    end;
  finally
    FUpdating := False;
  end;
  mFilter := FView.Filter;
  mFilter.Scope := AScope;
  mFilter.Compiler := ACompiler;
  FView.Filter := mFilter;
  FView.Grouping := AGrouping;
  FColumns := TAtlasFindings.ParseColumns(AColumns);
  BuildColumns;
  Refill;
end;

procedure TAtlasProblemsFrame.ApplyScopeSettings(AShowProjects: Boolean; const AProject: string);
begin
  FUpdating := True;
  try
    FScopeBox.SetShowProjects(AShowProjects);
    FScopeBox.Select(TAtlasScopeChoice.Create(FScopeBox.Choice.Scope, AProject));
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasProblemsFrame.SetScopeProjects(const AProjects: TArray<TAtlasScopeProject>);
var
  mFellBack: Boolean;
begin
  FUpdating := True;
  try
    mFellBack := FScopeBox.SetProjects(AProjects);
  finally
    FUpdating := False;
  end;
  if mFellBack and Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrame.ApplyTierSettings(AOpenFirst: Boolean; AClosedUnits: TAtlasClosedUnits;
  AShowCleanActive: Boolean);
begin
  FOpenFirst.Down := AOpenFirst;
  FView.ClosedUnits := AClosedUnits;
  FView.ShowCleanActive := AShowCleanActive;
  FView.OpenFirst := AOpenFirst;
  Refill;
end;

procedure TAtlasProblemsFrame.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  mBefore: string;
begin
  mBefore := FView.ActiveFile;
  FView.SetOpenFiles(AActive, AOpen, AActiveChecked);
  Refill;
  KeepInView(mBefore);
end;

procedure TAtlasProblemsFrame.KeepInView(const ABefore: string);
var
  mSelected: Integer;
begin
  if SameText(ABefore, FView.ActiveFile) or (FList.Items.Count = 0) then
  begin
    Exit;
  end;
  // Editorwechsel: Die ausgewählte Zeile bleibt sichtbar; ohne Auswahl steht die angepinnte Unit oben.
  mSelected := FView.SelectedRow;
  if (mSelected >= 0) and (FList.Items[mSelected] <> nil) then
  begin
    FList.Items[mSelected].MakeVisible(False);
  end
  else if FList.Items[0] <> nil then
  begin
    FList.Items[0].MakeVisible(False);
  end;
end;

procedure TAtlasProblemsFrame.OpenFirstClick(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  FView.OpenFirst := FOpenFirst.Down;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

function TAtlasProblemsFrame.FilterFromControls: TAtlasFindingFilter;
var
  mKind: TAtlasFindingKind;
begin
  Result := FView.Filter;
  Result.Kinds := [];
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    if FKinds[mKind].Down then
    begin
      Include(Result.Kinds, mKind);
    end;
  end;
  Result.OneCategory := FCategory.ItemIndex > 0;
  if Result.OneCategory then
  begin
    Result.Category := TAtlasFindingCategory(FCategory.ItemIndex - 1);
  end;
  Result.Text := Trim(FFilter.Text);
  Result.Origin := TAtlasFindingOrigin.All;
  if FShowIdeErrors and (FOrigin.ItemIndex > 0) then
  begin
    Result.Origin := TAtlasFindingOrigin(FOrigin.ItemIndex);
  end;
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles: TArray<string>);
var
  mFilter: TAtlasFindingFilter;
begin
  FView.BeginUpdate;
  try
    mFilter := FView.Filter;
    mFilter.CurrentFile := ACurrentFile;
    mFilter.Files := AFiles;
    FView.Filter := mFilter;
    FView.SetFindings(AFindings);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles, AOpen: TArray<string>; AActiveChecked: Boolean);
var
  mFilter: TAtlasFindingFilter;
  mBefore: string;
begin
  mBefore := FView.ActiveFile;
  FView.BeginUpdate;
  try
    mFilter := FView.Filter;
    mFilter.CurrentFile := ACurrentFile;
    mFilter.Files := AFiles;
    FView.Filter := mFilter;
    FView.SetFindings(AFindings);
    FView.SetOpenFiles(ACurrentFile, AOpen, AActiveChecked);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
  KeepInView(mBefore);
end;

procedure TAtlasProblemsFrame.FindingsChanged;
var
  mRow: TAtlasFindingRow;
  mHasNew: Boolean;
begin
  mHasNew := False;
  for mRow in FView.Rows do
  begin
    if mRow.IsNew then
    begin
      mHasNew := True;
    end;
  end;
  if mHasNew then
  begin
    // Neu starten: die Hervorhebung dauert ab dem letzten Zugang.
    FNewTimer.Enabled := False;
    FNewTimer.Enabled := True;
  end;
  Refill;
end;

procedure TAtlasProblemsFrame.SetStatus(const AText: string);
begin
  FStatus.Caption := AText;
end;

procedure TAtlasProblemsFrame.SetUpdate(AMode: TAtlasProblemsUpdate);
begin
  case AMode of
    TAtlasProblemsUpdate.Save:
      FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOnSave);
    TAtlasProblemsUpdate.Manual:
      FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsManual);
  else
    FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsLive);
  end;
  if AMode = TAtlasProblemsUpdate.Live then
  begin
    FLive.Font.Color := $0050A030;
  end
  else
  begin
    FLive.Font.Color := clGrayText;
  end;
end;

procedure TAtlasProblemsFrame.FollowCursor(const AFileName: string; ALine: Integer);
var
  mBefore: string;
begin
  mBefore := FView.SelectedKey;
  if FView.SelectAt(AFileName, ALine) and (FView.SelectedKey <> mBefore) then
  begin
    Refill;
    if (FView.SelectedRow >= 0) and (FList.Items[FView.SelectedRow] <> nil) then
    begin
      FList.Items[FView.SelectedRow].MakeVisible(False);
    end;
  end;
end;

function TAtlasProblemsFrame.Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
begin
  Result := FView.Step(AForward, AFinding);
  if not Result then
  begin
    Exit;
  end;
  Refill;
  if (FView.SelectedRow >= 0) and (FList.Items[FView.SelectedRow] <> nil) then
  begin
    FList.Items[FView.SelectedRow].MakeVisible(False);
  end;
end;

procedure TAtlasProblemsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  mRow: TAtlasFindingRow;
begin
  if FUpdating or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  // Trennzeilen (#1108) sind nicht wählbar.
  if RowAt(Item.Index, mRow) and mRow.IsSection then
  begin
    FUpdating := True;
    try
      Item.Selected := False;
    finally
      FUpdating := False;
    end;
    Exit;
  end;
  FView.Select(Item.Index);
end;

procedure TAtlasProblemsFrame.ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mHit: TListItem;
  mRow: TAtlasFindingRow;
begin
  // Klick auf eine Gruppe klappt sie; Mehrfachauswahl mit Strg/Umschalt bleibt.
  if (Button <> mbLeft) or (Shift * [ssCtrl, ssShift] <> []) then
  begin
    Exit;
  end;
  mHit := FList.GetItemAt(X, Y);
  if (mHit <> nil) and RowAt(mHit.Index, mRow) and mRow.IsGroup and not mRow.IsSection then
  begin
    FView.Toggle(mHit.Index);
    Refill;
  end;
end;

procedure TAtlasProblemsFrame.ListClick(Sender: TObject);
begin
  if FList.ItemIndex >= 0 then
  begin
    FView.Select(FList.ItemIndex);
  end;
end;

procedure TAtlasProblemsFrame.ListDblClick(Sender: TObject);
var
  mRow: TAtlasFindingRow;
begin
  if RowAt(FList.ItemIndex, mRow) and not mRow.IsGroup and not mRow.IsSection then
  begin
    Fire(FOnOpen);
  end;
end;

function TAtlasProblemsFrame.MoveKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mNext: TAtlasFindingRow;
  mTarget, mStep: Integer;
begin
  // ↑/↓ springen über Trennzeilen (#1108); am Rand bleibt die Auswahl.
  Result := False;
  if (AKey <> VK_UP) and (AKey <> VK_DOWN) then
  begin
    Exit;
  end;
  mStep := 1;
  if AKey = VK_UP then
  begin
    mStep := -1;
  end;
  mTarget := FList.ItemIndex + mStep;
  while RowAt(mTarget, mNext) and mNext.IsSection do
  begin
    Inc(mTarget, mStep);
  end;
  Result := (mTarget <> FList.ItemIndex + mStep) and (AShift * [ssShift, ssCtrl] = []);
  if Result and RowAt(mTarget, mNext) then
  begin
    ClearListSelection;
    FList.ItemIndex := mTarget;
    FList.Items[mTarget].Focused := True;
    FList.Items[mTarget].MakeVisible(False);
    FView.Select(mTarget);
  end;
end;

function TAtlasProblemsFrame.ActionKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mRow: TAtlasFindingRow;
begin
  Result := False;
  if not RowAt(FList.ItemIndex, mRow) or mRow.IsSection then
  begin
    Exit;
  end;
  case AKey of
    VK_RETURN, VK_SPACE:
      begin
        // Enter und Leertaste klappen Gruppen; Enter öffnet bzw. behebt (Alt) einen Befund.
        Result := mRow.IsGroup or (AKey = VK_RETURN);
        if mRow.IsGroup then
        begin
          FView.Toggle(FList.ItemIndex);
          Refill;
        end
        else if (AKey = VK_RETURN) and (ssAlt in AShift) then
        begin
          Fire(FOnFix);
        end
        else if AKey = VK_RETURN then
        begin
          Fire(FOnOpen);
        end;
      end;
    VK_LEFT, VK_RIGHT:
      begin
        Result := mRow.IsGroup and ((AKey = VK_RIGHT) <> mRow.Expanded);
        if Result then
        begin
          FView.SetExpanded(mRow.GroupKey, AKey = VK_RIGHT);
          Refill;
        end;
      end;
    Ord('C'):
      begin
        Result := ssCtrl in AShift;
        if Result then
        begin
          CopySelection;
        end;
      end;
  end;
end;

procedure TAtlasProblemsFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if MoveKey(Key, Shift) or ActionKey(Key, Shift) then
  begin
    Key := 0;
  end;
end;

procedure TAtlasProblemsFrame.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  if (Column = nil) or (Column.Index > High(FShown)) then
  begin
    Exit;
  end;
  FView.SortBy(FShown[Column.Index]);
  Refill;
end;

procedure TAtlasProblemsFrame.NewTimerTick(Sender: TObject);
begin
  FNewTimer.Enabled := False;
  FView.ClearNew;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrame.ControlsChanged(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  FView.Filter := FilterFromControls;
  Refill;
end;

procedure TAtlasProblemsFrame.ScopeChange(Sender: TObject);
var
  mFilter: TAtlasFindingFilter;
begin
  if FUpdating or not FScopeBox.Pick then
  begin
    Exit;
  end;
  mFilter := FilterFromControls;
  mFilter.Scope := FScopeBox.Choice.Scope;
  FView.Filter := mFilter;
  if Assigned(FOnScope) then
  begin
    FOnScope(mFilter.Scope);
  end;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrame.GroupingChange(Sender: TObject);
begin
  if FUpdating or (FGrouping.ItemIndex < 0) then
  begin
    Exit;
  end;
  FView.Grouping := TAtlasFindingGrouping(FGrouping.ItemIndex);
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and FList.Visible and FList.CanFocus then
  begin
    Key := 0;
    FList.SetFocus;
    if (FList.ItemIndex < 0) and (FList.Items.Count > 0) then
    begin
      FList.ItemIndex := 0;
    end;
  end;
end;

function TAtlasProblemsFrameMenu.SelectedRows: TArray<Integer>;
var
  mItem: TListItem;
begin
  Result := nil;
  mItem := FList.Selected;
  while mItem <> nil do
  begin
    Result := Result + [mItem.Index];
    mItem := FList.GetNextItem(mItem, sdAll, [isSelected]);
  end;
end;

function TAtlasProblemsFrameMenu.Current(out AFinding: TAtlasFinding): Boolean;
var
  mRow: TAtlasFindingRow;
begin
  Result := RowAt(FList.ItemIndex, mRow) and not mRow.IsGroup and not mRow.IsSection;
  if Result then
  begin
    AFinding := FView.Finding(mRow.Finding);
  end
  else
  begin
    AFinding := Default(TAtlasFinding);
  end;
end;

function TAtlasProblemsFrameMenu.IsRule(const AFinding: TAtlasFinding): Boolean;
begin
  // Regeln von Atlas lassen sich einstellen und unterdrücken; Compilermeldungen nicht.
  Result := (AFinding.Category <> TAtlasFindingCategory.Compiler) and (AFinding.Rule <> '');
end;

procedure TAtlasProblemsFrameMenu.ShowRuleActions(ACanSuppress, ARule: Boolean);
var
  mVisible: Boolean;
begin
  mVisible := Assigned(FCanRuleActions) and FCanRuleActions();
  FSuppressItem.Visible := mVisible and Assigned(FOnSuppress);
  FConfigureItem.Visible := mVisible and Assigned(FOnConfigure);
  FDisableItem.Visible := mVisible and Assigned(FOnDisable);
  FSuppressItem.Enabled := ACanSuppress;
  FConfigureItem.Enabled := ARule;
  FDisableItem.Enabled := ARule;
end;

procedure TAtlasProblemsFrameMenu.Fire(const AEvent: TAtlasFindingEvent);
var
  mFinding: TAtlasFinding;
begin
  if Assigned(AEvent) and Current(mFinding) then
  begin
    AEvent(mFinding);
  end;
end;

procedure TAtlasProblemsFrameMenu.CopySelection;
var
  mText: string;
begin
  mText := TAtlasFindings.AsText(FView.FindingsOfRows(SelectedRows));
  if mText <> '' then
  begin
    Clipboard.AsText := mText;
  end;
end;

procedure TAtlasProblemsFrameMenu.MenuPopup(Sender: TObject);
var
  mFinding: TAtlasFinding;
  mHas, mRule: Boolean;
  mCount: Integer;
begin
  mHas := Current(mFinding);
  mRule := mHas and IsRule(mFinding);
  FOpenItem.Enabled := mHas;
  if mHas and (mFinding.Problem.FixTitle <> '') then
  begin
    FFixItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFix, [mFinding.Problem.FixTitle]);
  end
  else
  begin
    FFixItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuFixNone);
  end;
  FFixItem.Enabled := mHas and (mFinding.Problem.FixTitle <> '');
  // Sammelkorrektur (#1352): je Regel; welche Treffer sicher sind, entscheidet der Server.
  FFixAllItem.Visible := Assigned(FOnFixAll) and Assigned(FCanFixAll) and FCanFixAll();
  FFixAllItem.Enabled := mRule;
  if mRule then
  begin
    FFixAllItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, [mFinding.Rule]);
  end
  else
  begin
    FFixAllItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, ['…']);
  end;
  // Regel-Aktionen liefert das Modul Prüfregeln (#1755); Syntaxfehler (#1022) lassen sich nicht per Kommentar
  // unterdrücken.
  ShowRuleActions(mRule and mFinding.Problem.CanSuppress, mRule);
  // Compilermeldungen mit Nummer erklärt der Katalog ebenfalls (#54).
  FExplainItem.Enabled := mRule or (mHas and (TAtlasRuleExplanation.MessageCode(mFinding.Problem) <> ''));
  if mRule or not FExplainItem.Enabled then
  begin
    FExplainItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplain);
  end
  else
  begin
    FExplainItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplainMessage);
  end;
  // Issue anlegen (#1268): auch für Compilermeldungen; mehrere markierte ergeben ein Issue mit Liste.
  mCount := Length(SelectedFindings);
  FIssueItem.Visible := Assigned(FOnCreateIssue) and Assigned(FCanCreateIssue) and FCanCreateIssue();
  FIssueItem.Enabled := mCount > 0;
  if mCount > 1 then
  begin
    FIssueItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuCreateIssueMany, [mCount]);
  end
  else
  begin
    FIssueItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCreateIssue);
  end;
  FCopyItem.Enabled := Length(SelectedRows) > 0;
  FResetSortItem.Enabled := FView.SortCustom;
end;

procedure TAtlasProblemsFrameMenu.OpenClick(Sender: TObject);
begin
  Fire(FOnOpen);
end;

procedure TAtlasProblemsFrameMenu.FixClick(Sender: TObject);
begin
  Fire(FOnFix);
end;

procedure TAtlasProblemsFrameMenu.FixAllClick(Sender: TObject);
begin
  Fire(FOnFixAll);
end;

procedure TAtlasProblemsFrameMenu.SuppressClick(Sender: TObject);
begin
  Fire(FOnSuppress);
end;

procedure TAtlasProblemsFrameMenu.ConfigureClick(Sender: TObject);
begin
  Fire(FOnConfigure);
end;

procedure TAtlasProblemsFrameMenu.DisableClick(Sender: TObject);
begin
  Fire(FOnDisable);
end;

procedure TAtlasProblemsFrameMenu.ExplainClick(Sender: TObject);
begin
  Fire(FOnExplain);
end;

function TAtlasProblemsFrameMenu.SelectedFindings: TArray<TAtlasFinding>;
begin
  Result := FView.FindingsOfRows(SelectedRows);
end;

procedure TAtlasProblemsFrameMenu.IssueClick(Sender: TObject);
var
  mFindings: TArray<TAtlasFinding>;
begin
  mFindings := SelectedFindings;
  if Assigned(FOnCreateIssue) and (Length(mFindings) > 0) then
  begin
    FOnCreateIssue(mFindings);
  end;
end;

procedure TAtlasProblemsFrameMenu.CopyClick(Sender: TObject);
begin
  CopySelection;
end;

procedure TAtlasProblemsFrameMenu.ResetSortClick(Sender: TObject);
begin
  FView.ResetSort;
  Refill;
end;

end.
