unit Atlas.UI.UnitSearch.Window;

// Fenster „Units suchen“ (#777) im Stil der Atlas-Popups (#410, #411):
// Akzentrahmen, runde Ecken, Farben aus TAtlasColors (hell oder dunkel nach
// dem IDE-Thema). Nicht modal, frei verschieb- und vergrößerbar; Lage, Größe
// und Breite der Vorschau merkt sich TAtlasUnitSearchState.
//   Kopf:    Suchfeld mit Filterchips aus der Tippsyntax, rechts Projekt /
//            Ordner / Flach.
//   Chips:   Herkunft (Aktives Projekt, Projektgruppe, Suchpfad, Bibliothek)
//            und Art (Formular, Frame, Datenmodul, Unit, Test, Include).
//   Liste:   selbst gezeichnet und virtuell (nur sichtbare Zeilen), zwei
//            Zeilen je Unit, Gruppenköpfe mit Trefferzahl und Pfeil.
//   Vorschau rechts (F4), Aktionsleiste, Fußzeile mit Tasten und „n von m“.
// Alles, was die IDE braucht (Öffnen, uses, Projektmanager, Testunits,
// Vorschau beim Server), kommt über Ereignisse von der IDE-Schicht.
// Modi (#786, TAtlasUnitSearchOptions.Mode):
//   Unit verwenden (Alt+F11): Zeile unter dem Kopf mit „Unit verwenden in
//            <Unit>“ und dem Umschalter interface / implementation (Strg+I,
//            Vorgabe implementation). Units aus den uses der Unit sind
//            ausgegraut („schon in uses“); ein Kreis zeigt „Kreis über X“,
//            als Warnung nur, wenn ihn der Compiler im gewählten Abschnitt
//            ablehnt, den Weg in der Fußzeile. Enter fügt die markierten
//            (sonst die aktuelle) über OnUse ein und schließt.
//   Formulare suchen (Umschalt+F12): Filter t:form|frame|dm (ohne
//            Tippsyntax fest die Arten); Enter öffnet den Designer,
//            Umschalt+Enter den Quelltext.
//
// Aufgeteilt (#777): Zustand und Filter in Atlas.UI.UnitSearch.Data,
// Zeichnen in Atlas.UI.UnitSearch.Painter; das Fenster verarbeitet Tasten
// und Maus und meldet die Aktionen.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.State,
  Atlas.Core.UnitSearch.UseUnit,
  Atlas.UI.UnitSearch.Data,
  Atlas.UI.UnitSearch.Painter;

type
  TAtlasUnitSearchWindow = class(TForm)
  private
    FData: TAtlasUnitSearchData;
    FPainter: TAtlasUnitSearchPainter;
    FEvents: TAtlasUnitSearchEvents;
    FPreviewTimer: TTimer;
    FActionMenu: TPopupMenu;
    FClosing: Boolean;
    FDragSplitter: Boolean;
    /// <summary>Nach einer Änderung der Liste: Vorschau nachziehen, neu zeichnen.</summary>
    procedure Changed;
    procedure Refilter(AKeepSelection: Boolean);
    procedure Run(AAction: TAtlasUnitSearchAction);
    procedure RunUse;
    procedure SchedulePreview;
    procedure PreviewTick(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure ClickArea(const AArea: TAtlasUnitSearchHitArea; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer);
    /// <summary>Taste außer Navigation verarbeiten; False, wenn sie nichts tut.</summary>
    function KeyCommand(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Strg+Buchstabe; False, wenn er nichts tut.</summary>
    function CtrlCommand(AKey: Word): Boolean;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>AState gehört weiter dem Aufrufer; das Fenster schreibt Lage und Wahl hinein.</summary>
    constructor CreateSearch(AOwner: TComponent; const AOptions: TAtlasUnitSearchOptions;
      AState: TAtlasUnitSearchState; const AColors: TAtlasColors);
    destructor Destroy; override;
    /// <summary>Einträge setzen (nach dem Laden beim Server); bis dahin zeigt das Fenster „wird geladen“.</summary>
    procedure SetEntries(const AEntries: TAtlasUnitEntries);
    /// <summary>„schon in uses“ und Kreise der Zielunit (#786, nach atlas.useUnitInfo).</summary>
    procedure SetUseInfo(const AInfo: TAtlasUseUnitInfo);
    /// <summary>Zeigen: gemerkte Lage oder mittig über AArea.</summary>
    procedure ShowOver(const AArea: TRect);
    property OnAction: TAtlasUnitSearchActionEvent read FEvents.OnAction write FEvents.OnAction;
    property OnPreview: TAtlasUnitSearchPreviewFunc read FEvents.OnPreview write FEvents.OnPreview;
    /// <summary>„Unit verwenden“: einfügbare Units und Abschnitt (#786).</summary>
    property OnUse: TAtlasUnitSearchUseEvent read FEvents.OnUse write FEvents.OnUse;
    /// <summary>Nach dem Schließen (Zustand ist dann gespeichert); das Fenster gibt sich selbst frei.</summary>
    property OnClosed: TProc read FEvents.OnClosed write FEvents.OnClosed;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Winapi.Dwmapi,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Atlas.Core.UnitSearch.Sections,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings;

const
  // Ab Windows 11; ältere Systeme ignorieren die Attribute.
  cCornerPreference = 33;
  cRoundCorners = 2;
  cBorderColorAttribute = 34;

function WindowCaption(const AOptions: TAtlasUnitSearchOptions): string;
begin
  case AOptions.Mode of
    TAtlasUnitSearchMode.UseUnit:
      if AOptions.TargetUnit <> '' then
      begin
        Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UseUnitTitle, [AOptions.TargetUnit]);
      end
      else
      begin
        Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitTitleNone);
      end;
    TAtlasUnitSearchMode.Forms:
      Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.FormsTitle);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle);
  end;
end;

/// <summary>Volle Pfade der Einträge, eine Zeile je Datei.</summary>
function PathsText(const AEntries: TArray<TAtlasUnitEntry>): string;
var
  mEntry: TAtlasUnitEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    Result := Result + mEntry.FileName + sLineBreak;
  end;
  Result := TrimRight(Result);
end;

/// <summary>Projekt, Ordner, Flach und wieder von vorn (Strg+G).</summary>
function NextGrouping(AGrouping: TAtlasUnitGrouping): TAtlasUnitGrouping;
begin
  case AGrouping of
    TAtlasUnitGrouping.Project: Result := TAtlasUnitGrouping.Folder;
    TAtlasUnitGrouping.Folder: Result := TAtlasUnitGrouping.None;
  else
    Result := TAtlasUnitGrouping.Project;
  end;
end;

/// <summary>Kontextmenü mit den angebotenen Aktionen und ihren Tasten.</summary>
procedure BuildActionMenu(AMenu: TPopupMenu; const AOptions: TAtlasUnitSearchOptions; AClick: TNotifyEvent);
const
  cShortCuts: array[TAtlasUnitSearchAction] of string = ('Enter', 'Shift+Enter', 'Alt+Enter', 'Ctrl+T', 'Ctrl+C',
    '', '');
var
  mAction: TAtlasUnitSearchAction;
  mItem: TMenuItem;
begin
  for mAction := Low(TAtlasUnitSearchAction) to High(TAtlasUnitSearchAction) do
  begin
    if not UnitSearchActionVisible(AOptions, mAction) then
    begin
      Continue;
    end;
    mItem := TMenuItem.Create(AMenu);
    mItem.Caption := UnitSearchActionCaption(mAction);
    if cShortCuts[mAction] <> '' then
    begin
      mItem.Caption := mItem.Caption + #9 + cShortCuts[mAction];
    end;
    mItem.Tag := Ord(mAction);
    mItem.OnClick := AClick;
    AMenu.Items.Add(mItem);
  end;
end;

/// <summary>Enter und Doppelklick: je nach Modus öffnen, einfügen oder den Designer zeigen (AShift: umgekehrt).
/// </summary>
function AcceptAction(AMode: TAtlasUnitSearchMode; AShift: Boolean): TAtlasUnitSearchAction;
begin
  if AMode = TAtlasUnitSearchMode.UseUnit then
  begin
    Exit(TAtlasUnitSearchAction.AddUses);
  end;
  // Formulare suchen: Enter zeigt den Designer, Umschalt+Enter den Quelltext; sonst umgekehrt.
  if AShift = (AMode = TAtlasUnitSearchMode.Forms) then
  begin
    Result := TAtlasUnitSearchAction.Open;
  end
  else
  begin
    Result := TAtlasUnitSearchAction.OpenForm;
  end;
end;

/// <summary>Zielzeile der Navigationstasten (Pfeile, Bild, Strg+Pos1/Ende); False für andere Tasten.</summary>
function NavigationRow(AData: TAtlasUnitSearchData; AKey: Word; AShift: TShiftState; out ARow: Integer): Boolean;
var
  mPage: Integer;
begin
  mPage := Max(1, AData.List.Rect.Height div AData.Metrics.EntryHeight);
  Result := True;
  case AKey of
    VK_UP: ARow := AData.List.Selected - 1;
    VK_DOWN: ARow := AData.List.Selected + 1;
    VK_PRIOR: ARow := AData.List.Selected - mPage;
    VK_NEXT: ARow := AData.List.Selected + mPage;
    VK_HOME: ARow := 0;
    VK_END: ARow := High(AData.List.Rows);
  else
    ARow := -1;
    Result := False;
  end;
  // Pos1 und Ende nur mit Strg.
  if (AKey = VK_HOME) or (AKey = VK_END) then
  begin
    Result := ssCtrl in AShift;
  end;
end;

/// <summary>Zeile an der Höhe Y; -1 außerhalb der Liste.</summary>
function RowAt(AData: TAtlasUnitSearchData; AY: Integer): Integer;
var
  mOffset, mIndex: Integer;
begin
  Result := -1;
  mOffset := AY - AData.List.Rect.Top + AData.List.Scroll;
  if (AY < AData.List.Rect.Top) or (AY >= AData.List.Rect.Bottom) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AData.List.Rows) do
  begin
    if (mOffset >= AData.List.RowTops[mIndex]) and (mOffset < AData.List.RowTops[mIndex + 1]) then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Rand zum Vergrößern unter APoint (HTTOPLEFT …); HTCLIENT im Inneren.</summary>
function EdgeHit(const APoint: TPoint; AWidth, AHeight, AEdge: Integer): Integer;
const
  cEdges: array[0..2, 0..2] of Integer = ((HTTOPLEFT, HTTOP, HTTOPRIGHT), (HTLEFT, HTCLIENT, HTRIGHT),
    (HTBOTTOMLEFT, HTBOTTOM, HTBOTTOMRIGHT));
var
  mRow, mColumn: Integer;
begin
  mRow := 1;
  if APoint.Y < AEdge then
  begin
    mRow := 0;
  end
  else if APoint.Y >= AHeight - AEdge then
  begin
    mRow := 2;
  end;
  mColumn := 1;
  if APoint.X < AEdge then
  begin
    mColumn := 0;
  end
  else if APoint.X >= AWidth - AEdge then
  begin
    mColumn := 2;
  end;
  Result := cEdges[mRow, mColumn];
end;

/// <summary>Tooltip an der Fläche AArea: voller Pfad einer Zeile oder der Vorschau.</summary>
function AreaHint(AData: TAtlasUnitSearchData; const AArea: TAtlasUnitSearchHitArea): string;
begin
  Result := '';
  if (AArea.Kind = TAtlasUnitSearchHit.Row) and not AData.List.Rows[AArea.Value].IsGroup then
  begin
    Result := AData.Entries[AData.List.Rows[AArea.Value].Entry].FileName;
  end
  else if (AArea.Kind = TAtlasUnitSearchHit.Section) and
    (TAtlasPreviewSection(AArea.Value) = TAtlasPreviewSection.Path) then
  begin
    Result := AData.Preview.Data.FileName;
  end;
end;

/// <summary>Zeiger über der Fläche AArea.</summary>
function AreaCursor(const AArea: TAtlasUnitSearchHitArea): TCursor;
begin
  case AArea.Kind of
    TAtlasUnitSearchHit.Splitter: Result := crHSplit;
    TAtlasUnitSearchHit.Section, TAtlasUnitSearchHit.SectionSwitch: Result := crHandPoint;
  else
    Result := crDefault;
  end;
end;

/// <summary>Enter auf einem Gruppenkopf (ohne Markierung) klappt die Gruppe; False sonst.</summary>
function ToggleGroupOnEnter(AData: TAtlasUnitSearchData): Boolean;
var
  mRow: Integer;
begin
  mRow := AData.List.Selected;
  Result := (mRow >= 0) and (mRow <= High(AData.List.Rows)) and AData.List.Rows[mRow].IsGroup and
    (AData.Marked.Count = 0);
  if Result then
  begin
    AData.ToggleGroup(mRow, not AData.List.Rows[mRow].Collapsed);
  end;
end;

/// <summary>F4: Vorschau ein- oder ausblenden und neu anordnen; False ohne Vorschau.</summary>
function TogglePreview(AData: TAtlasUnitSearchData; AWidth, AHeight: Integer): Boolean;
begin
  Result := AData.Options.Preview;
  if Result then
  begin
    AData.Preview.Visible := not AData.Preview.Visible;
    AData.Layout(AWidth, AHeight);
    AData.EnsureVisible;
  end;
end;

/// <summary>Leertaste: Fertig getippter Filter wird zum Chip; sonst markiert sie und geht weiter (Umschalt+Leertaste
/// tippt ein Leerzeichen für mehrere Suchwörter). True, wenn neu gefiltert werden muss.</summary>
function TypeSpace(AData: TAtlasUnitSearchData; AShift: TShiftState): Boolean;
begin
  Result := True;
  if AData.CommitTypedFilter then
  begin
    Exit;
  end;
  if AData.Options.MultiSelect and not (ssShift in AShift) then
  begin
    AData.ToggleMark(AData.List.Selected);
    AData.Select(AData.List.Selected + 1);
    Result := False;
  end
  else
  begin
    AData.Filter.Pattern := AData.Filter.Pattern + ' ';
  end;
end;

/// <summary>Linksklick auf Chip, Gruppierung, Häkchen, Abschnitt, Umschalter oder Zeile.</summary>
procedure ClickLeft(AData: TAtlasUnitSearchData; const AArea: TAtlasUnitSearchHitArea; AShift: TShiftState);
var
  mSection: TAtlasPreviewSection;
begin
  case AArea.Kind of
    TAtlasUnitSearchHit.Chip:
      begin
        AData.ChipClicked(AArea.Value);
        AData.Refilter(True);
      end;
    TAtlasUnitSearchHit.Grouping:
      if AData.SetGrouping(TAtlasUnitGrouping(AArea.Value)) then
      begin
        AData.Refilter(True);
      end;
    TAtlasUnitSearchHit.Check:
      begin
        AData.Select(AArea.Value);
        AData.ToggleMark(AArea.Value);
      end;
    TAtlasUnitSearchHit.Section:
      begin
        mSection := TAtlasPreviewSection(AArea.Value);
        AData.State.Sections[mSection] := TAtlasPreviewSections.Toggled(AData.Preview.Sections[mSection]);
      end;
    TAtlasUnitSearchHit.SectionSwitch:
      if TAtlasUseUnitSection(AArea.Value) <> AData.Use.Section then
      begin
        AData.ToggleUseSection;
      end;
    TAtlasUnitSearchHit.Row:
      if AData.List.Rows[AArea.Value].IsGroup then
      begin
        AData.ToggleGroup(AArea.Value, not AData.List.Rows[AArea.Value].Collapsed);
      end
      else if ssCtrl in AShift then
      begin
        AData.ToggleMark(AArea.Value);
      end;
  else
    // Splitter und Aktionen verarbeitet das Fenster, None trifft nichts.
  end;
end;

{ TAtlasUnitSearchWindow }

constructor TAtlasUnitSearchWindow.CreateSearch(AOwner: TComponent; const AOptions: TAtlasUnitSearchOptions;
  AState: TAtlasUnitSearchState; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FData := TAtlasUnitSearchData.Create(AOptions, AState);
  FData.Metrics.PPI := CurrentPPI;
  FPainter := TAtlasUnitSearchPainter.Create(FData, AColors);
  BorderStyle := bsNone;
  KeyPreview := False;
  DoubleBuffered := True;
  Color := TColor(AColors.Surface);
  Caption := WindowCaption(AOptions);
  OnClose := FormClose;
  ShowHint := True;
  Font.Assign(FPainter.Fonts.UI);
  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Interval := 150;
  FPreviewTimer.OnTimer := PreviewTick;
  FActionMenu := TPopupMenu.Create(Self);
  BuildActionMenu(FActionMenu, AOptions, MenuClick);
  Refilter(False);
end;

destructor TAtlasUnitSearchWindow.Destroy;
begin
  FPainter.Free;
  FData.Free;
  inherited Destroy;
end;

procedure TAtlasUnitSearchWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Ohne Systemrahmen; vergrößert wird über WM_NCHITTEST. Schatten wie die Palette.
  Params.Style := (Params.Style and not (WS_CAPTION or WS_THICKFRAME)) or WS_POPUP;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasUnitSearchWindow.CreateWnd;
var
  mPreference, mBorder: DWORD;
begin
  inherited CreateWnd;
  mPreference := cRoundCorners;
  DwmSetWindowAttribute(Handle, cCornerPreference, @mPreference, SizeOf(mPreference));
  mBorder := DWORD(FPainter.Colors.Accent);
  DwmSetWindowAttribute(Handle, cBorderColorAttribute, @mBorder, SizeOf(mBorder));
end;

procedure TAtlasUnitSearchWindow.ShowOver(const AArea: TRect);
var
  mArea: TRect;
  mWidth, mHeight: Integer;
begin
  mArea := Rect(FData.State.Left, FData.State.Top, FData.State.Left + FData.State.Width,
    FData.State.Top + FData.State.Height);
  // Gemerkte Lage nur übernehmen, wenn sie noch auf einem Monitor liegt.
  if (FData.State.Width > 0) and (FData.State.Height > 0) and (Screen.MonitorFromRect(mArea, mdNull) <> nil) then
  begin
    SetBounds(mArea.Left, mArea.Top, mArea.Width, mArea.Height);
  end
  else
  begin
    mWidth := Min(ScaleValue(1000), AArea.Width - ScaleValue(40));
    mHeight := Min(ScaleValue(620), AArea.Height - ScaleValue(40));
    SetBounds(AArea.Left + (AArea.Width - mWidth) div 2, AArea.Top + Max(ScaleValue(20), (AArea.Height - mHeight) div
      3), mWidth, mHeight);
  end;
  Show;
  SetFocus;
end;

procedure TAtlasUnitSearchWindow.SetEntries(const AEntries: TAtlasUnitEntries);
begin
  FData.SetEntries(AEntries);
  Refilter(False);
end;

procedure TAtlasUnitSearchWindow.SetUseInfo(const AInfo: TAtlasUseUnitInfo);
begin
  FData.SetUseInfo(AInfo);
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.Changed;
begin
  SchedulePreview;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.Refilter(AKeepSelection: Boolean);
begin
  FData.Layout(ClientWidth, ClientHeight);
  FData.Refilter(AKeepSelection);
  Changed;
end;

procedure TAtlasUnitSearchWindow.Run(AAction: TAtlasUnitSearchAction);
var
  mEntries: TArray<TAtlasUnitEntry>;
  mHandler: TAtlasUnitSearchActionEvent;
begin
  // Unit verwenden: „In uses aufnehmen“ fügt in den gewählten Abschnitt ein (#786).
  if (AAction = TAtlasUnitSearchAction.AddUses) and (FData.Options.Mode = TAtlasUnitSearchMode.UseUnit) then
  begin
    RunUse;
    Exit;
  end;
  mEntries := FData.SelectedEntries;
  if not UnitSearchActionVisible(FData.Options, AAction) or (Length(mEntries) = 0) then
  begin
    Exit;
  end;
  if AAction = TAtlasUnitSearchAction.CopyPaths then
  begin
    Clipboard.AsText := PathsText(mEntries);
    Exit;
  end;
  mHandler := FEvents.OnAction;
  // Öffnen, Formular und Testunits schließen das Fenster wie der IDE-Dialog; die übrigen lassen es offen.
  if AAction in [TAtlasUnitSearchAction.Open, TAtlasUnitSearchAction.OpenForm,
    TAtlasUnitSearchAction.OpenTests] then
  begin
    Close;
  end;
  if Assigned(mHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.UnitSearch,
      procedure
      begin
        mHandler(AAction, mEntries);
      end);
  end;
end;

procedure TAtlasUnitSearchWindow.RunUse;
var
  mEntries: TArray<TAtlasUnitEntry>;
  mHandler: TAtlasUnitSearchUseEvent;
  mSection: TAtlasUseUnitSection;
begin
  // Ohne Duplikate: Units aus den uses, die Zielunit selbst und Include-Dateien fallen weg (#786).
  mEntries := TAtlasUseUnit.Addable(FData.Use.Info, FData.SelectedEntries);
  mHandler := FEvents.OnUse;
  mSection := FData.Use.Section;
  // Wie der Dialog der IDE: Einfügen schließt das Fenster.
  Close;
  if Assigned(mHandler) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.UnitSearch,
      procedure
      begin
        mHandler(mEntries, mSection);
      end);
  end;
end;

procedure TAtlasUnitSearchWindow.FormClose(Sender: TObject; var Action: TCloseAction);
var
  mClosed: TProc;
begin
  if FClosing then
  begin
    Exit;
  end;
  FClosing := True;
  FData.SaveState(BoundsRect);
  Action := caFree;
  mClosed := FEvents.OnClosed;
  if Assigned(mClosed) then
  begin
    mClosed();
  end;
end;

procedure TAtlasUnitSearchWindow.SchedulePreview;
begin
  if FData.Preview.Visible and Assigned(FEvents.OnPreview) then
  begin
    FPreviewTimer.Enabled := False;
    FPreviewTimer.Enabled := True;
  end;
end;

procedure TAtlasUnitSearchWindow.PreviewTick(Sender: TObject);
var
  mIndex: Integer;
begin
  FPreviewTimer.Enabled := False;
  if not FData.Preview.Visible or not Assigned(FEvents.OnPreview) then
  begin
    Exit;
  end;
  if not FData.CurrentEntry(mIndex) then
  begin
    FData.Preview.Data := Default(TAtlasUnitPreview);
    FData.Preview.FileName := '';
    Invalidate;
  end
  else if not SameText(FData.Preview.FileName, FData.Entries[mIndex].FileName) then
  begin
    FData.Preview.FileName := FData.Entries[mIndex].FileName;
    FData.Preview.Data := FEvents.OnPreview(FData.Entries[mIndex]);
    Invalidate;
  end;
end;

procedure TAtlasUnitSearchWindow.MenuClick(Sender: TObject);
begin
  Run(TAtlasUnitSearchAction(TMenuItem(Sender).Tag));
end;

procedure TAtlasUnitSearchWindow.Resize;
begin
  inherited;
  if FData = nil then
  begin
    Exit;
  end;
  FData.Metrics.PPI := CurrentPPI;
  FData.Layout(ClientWidth, ClientHeight);
  FData.EnsureVisible;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.Paint;
begin
  FData.Layout(ClientWidth, ClientHeight);
  FPainter.Paint(Canvas, ClientRect, Caption);
end;

procedure TAtlasUnitSearchWindow.WMNCHitTest(var Message: TWMNCHitTest);
var
  mPoint: TPoint;
  mArea: TAtlasUnitSearchHitArea;
  mHeader: Integer;
begin
  inherited;
  mPoint := ScreenToClient(Point(Message.XPos, Message.YPos));
  mHeader := FData.Metrics.HeaderHeight;
  Message.Result := EdgeHit(mPoint, ClientWidth, ClientHeight, ScaleValue(6));
  // Freie Stellen im Kopf verschieben das Fenster.
  if (Message.Result = HTCLIENT) and (mPoint.Y < mHeader) and not FPainter.HitAt(mPoint.X, mPoint.Y, mArea) and
    ((mPoint.Y < ScaleValue(7)) or (mPoint.Y > mHeader - ScaleValue(7))) then
  begin
    Message.Result := HTCAPTION;
  end;
end;

procedure TAtlasUnitSearchWindow.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTALLKEYS or DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTTAB;
end;

procedure TAtlasUnitSearchWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  mRow: Integer;
begin
  if NavigationRow(FData, Key, Shift, mRow) then
  begin
    if FData.Select(mRow) then
    begin
      Changed;
    end;
  end
  else if not KeyCommand(Key, Shift) then
  begin
    Exit;
  end;
  Key := 0;
end;

function TAtlasUnitSearchWindow.KeyCommand(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := True;
  case AKey of
    VK_ESCAPE:
      Close;
    VK_RETURN:
      if ToggleGroupOnEnter(FData) then
      begin
        Changed;
      end
      else if (ssAlt in AShift) and (FData.Options.Mode <> TAtlasUnitSearchMode.UseUnit) then
      begin
        Run(TAtlasUnitSearchAction.AddUses);
      end
      else
      begin
        Run(AcceptAction(FData.Options.Mode, ssShift in AShift));
      end;
    // Strg+Links/Rechts: Gruppe der markierten Zeile klappen.
    VK_LEFT, VK_RIGHT:
      begin
        Result := (ssCtrl in AShift) and FData.ToggleSelectedGroup(AKey = VK_LEFT);
        Invalidate;
      end;
    VK_F4:
      if TogglePreview(FData, ClientWidth, ClientHeight) then
      begin
        Changed;
      end;
    VK_SPACE:
      if TypeSpace(FData, AShift) then
      begin
        Refilter(True);
      end
      else
      begin
        Changed;
      end;
    VK_BACK:
      begin
        Result := FData.RemoveLast(ssCtrl in AShift);
        if Result then
        begin
          Refilter(False);
        end;
      end;
  else
    Result := (ssCtrl in AShift) and CtrlCommand(AKey);
  end;
end;

function TAtlasUnitSearchWindow.CtrlCommand(AKey: Word): Boolean;
begin
  Result := True;
  case AKey of
    Ord('A'):
      if FData.MarkAll then
      begin
        Invalidate;
      end;
    Ord('T'):
      Run(TAtlasUnitSearchAction.OpenTests);
    Ord('C'):
      Run(TAtlasUnitSearchAction.CopyPaths);
    Ord('G'):
      if FData.SetGrouping(NextGrouping(FData.List.Grouping)) then
      begin
        Refilter(True);
      end;
    Ord('I'):
      if FData.ToggleUseSection then
      begin
        Invalidate;
      end;
  else
    Result := False;
  end;
end;

procedure TAtlasUnitSearchWindow.KeyPress(var Key: Char);
begin
  if Key > ' ' then
  begin
    FData.Filter.Pattern := FData.Filter.Pattern + Key;
    Refilter(False);
  end;
  Key := #0;
end;

procedure TAtlasUnitSearchWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mArea: TAtlasUnitSearchHitArea;
begin
  inherited;
  if FPainter.HitAt(X, Y, mArea) then
  begin
    ClickArea(mArea, Button, Shift, X, Y);
  end;
end;

procedure TAtlasUnitSearchWindow.ClickArea(const AArea: TAtlasUnitSearchHitArea; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
var
  mPoint: TPoint;
begin
  if AArea.Kind = TAtlasUnitSearchHit.Row then
  begin
    FData.Select(AArea.Value);
    Changed;
    if (AButton = mbRight) and not FData.List.Rows[AArea.Value].IsGroup then
    begin
      mPoint := ClientToScreen(Point(AX, AY));
      FActionMenu.Popup(mPoint.X, mPoint.Y);
    end;
  end;
  if AButton <> mbLeft then
  begin
    Exit;
  end;
  case AArea.Kind of
    TAtlasUnitSearchHit.Splitter:
      begin
        FDragSplitter := True;
        MouseCapture := True;
      end;
    TAtlasUnitSearchHit.Action:
      Run(TAtlasUnitSearchAction(AArea.Value));
  else
    ClickLeft(FData, AArea, AShift);
  end;
  Changed;
end;

procedure TAtlasUnitSearchWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mArea: TAtlasUnitSearchHitArea;
  mText: string;
begin
  inherited;
  if FDragSplitter then
  begin
    FData.Preview.Width := MulDiv(ClientWidth - X, 96, CurrentPPI);
    FData.Layout(ClientWidth, ClientHeight);
    Invalidate;
    Exit;
  end;
  if not FPainter.HitAt(X, Y, mArea) then
  begin
    mArea := Default(TAtlasUnitSearchHitArea);
  end;
  Cursor := AreaCursor(mArea);
  // Voller Pfad als Tooltip.
  mText := AreaHint(FData, mArea);
  if mText <> Hint then
  begin
    Hint := mText;
    Application.CancelHint;
  end;
end;

procedure TAtlasUnitSearchWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDragSplitter then
  begin
    FDragSplitter := False;
    MouseCapture := False;
  end;
end;

procedure TAtlasUnitSearchWindow.DblClick;
var
  mPoint: TPoint;
  mRow: Integer;
begin
  inherited;
  mPoint := ScreenToClient(Mouse.CursorPos);
  mRow := RowAt(FData, mPoint.Y);
  if (mRow >= 0) and not FData.List.Rows[mRow].IsGroup and (mPoint.X < FData.List.Rect.Right) then
  begin
    FData.Select(mRow);
    FData.Marked.Clear;
    Changed;
    Run(AcceptAction(FData.Options.Mode, False));
  end;
end;

function TAtlasUnitSearchWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FData.ScrollBy(-Sign(WheelDelta) * 3 * FData.Metrics.EntryHeight);
  Invalidate;
  Result := True;
end;

end.
