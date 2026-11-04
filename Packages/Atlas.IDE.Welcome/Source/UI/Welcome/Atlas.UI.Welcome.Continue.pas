unit Atlas.UI.Welcome.Continue;

// Bereich „Weiterarbeiten“ der Willkommensseite (#755), ohne Open Tools API.
// Zwei Reiter (der zweite nur mit welcomePage.saved):
// - „Zuletzt“: je Arbeitsstand eine Zeile, neueste zuerst, selbst gezeichnet:
//     Atlas · 7 Reiter                              vor 2 Std.  [Fortsetzen]
//     Kunde.pas › TKunde.Laden
//   Darunter für den obersten Eintrag „Neu seit deinem letzten Öffnen
//   (origin/main)“ mit je Commit Kurz-Hash, Betreff, Autor und betroffener
//   Datei; Klick zeigt die Dateien des Commits. Ohne Arbeitskopie oder
//   verfolgten Branch fehlt der Abschnitt. Ganz unten ein Hinweis der Quelle
//   (z. B. übersprungene Dateien nach „Fortsetzen“).
// - „Gemerkt“: Filterfeld und Liste mit Art, Text bzw. Name, Datei und Zeile,
//   Projekt; Doppelklick oder Enter springt hin.
// Schnellaktionen (#764, Atlas.UI.Welcome.QuickActions): In der Zeile unter
// der Maus bzw. in der mit der Tastatur gewählten Zeile (hinterlegt) stehen
// links von „Fortsetzen“ die Knöpfe „Öffnen und bauen“, „Tests“,
// „Startprofil ▾“, „Pull“, „Ordner“, „Konsole“ statt des Zeitpunkts; ein
// laufender oder beendeter Lauf steht dort als Marke („baut … 12 s“).
// Tastatur: ↑/↓ Zeile, ←/→ Knopf, Enter führt aus bzw. setzt fort, Strg+B
// baut, Strg+T testet; Kontextmenütaste öffnet das Menü der Zeile.
// Daten und Aktionen kommen über IAtlasContinueSource aus der IDE-Schicht;
// Klicks gehen über die Nachrichtenschleife, weil die Quelle den Bereich
// daraufhin neu füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.QuickActions;

type
  IAtlasContinueSource = interface
    ['{2B7E9C41-5D3A-4E86-9F1B-C4A07D2E8B95}']
    /// <summary>Gezeigte Arbeitsstände, neueste zuerst.</summary>
    function Entries: TAtlasContinueEntries;
    /// <summary>Eingehende Commits zum obersten Eintrag; Available = False: kein Abschnitt.</summary>
    function Incoming: TAtlasContinueIncoming;
    /// <summary>Die Abfrage der eingehenden Commits läuft gerade.</summary>
    function IncomingQuerying: Boolean;
    /// <summary>Reiter „Gemerkt“ zeigen (welcomePage.saved).</summary>
    function SavedEnabled: Boolean;
    /// <summary>Notizen, Lesezeichen und Favoriten aller Projekte.</summary>
    function Saved: TAtlasSavedItems;
    /// <summary>Hinweis unter der Liste (z. B. übersprungene Dateien); '' ohne.</summary>
    function Notice: string;
    /// <summary>„Fortsetzen“: Projekt öffnen, Reiter in ihrer Reihenfolge, Cursor an die letzte Änderung.</summary>
    procedure Resume(const AProject: string);
    /// <summary>Dateien eines eingehenden Commits zeigen.</summary>
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    /// <summary>Projekt öffnen und zum gemerkten Eintrag springen.</summary>
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung für AProject öffnen.
    /// </summary>
    procedure ShowServerAccess(const AProject: string);
    /// <summary>Der Bereich wird gezeigt: eingehende Commits bei Bedarf im Hintergrund abfragen.</summary>
    procedure Shown;
  end;

  TAtlasContinueHit = record
    /// <summary>Zeile eines Arbeitsstands; -1 = keine.</summary>
    Row: Integer;
    /// <summary>Auf „Fortsetzen“ der Zeile.</summary>
    Button: Boolean;
    /// <summary>Eingehender Commit; -1 = keiner.</summary>
    Commit: Integer;
    /// <summary>Auf „Anmeldung am Server nötig – prüfen …“ (#1287).</summary>
    Login: Boolean;
  end;

  TAtlasWelcomeContinueFrame = class(TAtlasWelcomeSectionFrame)
  public const
    RowHeight = 44;
    LineHeight = 20;
    Indent = 8;
    ButtonHeight = 22;
    ButtonPadding = 10;
    TabHeight = 26;
    FilterHeight = 28;
    /// <summary>Sichtbare Zeilen der Liste „Gemerkt“ (logische Pixel je Zeile: LineHeight).</summary>
    SavedRows = 8;
    PageRecent = 0;
    PageSaved = 1;
  private
    FSource: IAtlasContinueSource;
    FTabs: TTabControl;
    FBox: TAtlasWelcomeCanvas;
    FSavedPanel: TPanel;
    FFilter: TEdit;
    FList: TListView;
    FSavedEmpty: TLabel;
    FEntries: TAtlasContinueEntries;
    FIncoming: TAtlasContinueIncoming;
    FQuerying: Boolean;
    FNotice: string;
    FSaved: TAtlasSavedItems;
    FShownSaved: TAtlasSavedItems;
    FSavedLoaded: Boolean;
    FButtonRects: TArray<TRect>;
    FHintKey: string;
    FQuick: TAtlasQuickActionsBar;
    FMenu: TPopupMenu;
    FResumeItem: TMenuItem;
    FMenuRow: Integer;
    procedure SetSource(const AValue: IAtlasContinueSource);
    function GetQuickActions: IAtlasQuickActionsSource;
    procedure SetQuickActions(const AValue: IAtlasQuickActionsSource);
    procedure QuickOpenRow(ARow: Integer);
    procedure QuickRowMenu(ARow: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure ResumeClick(Sender: TObject);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseLeave(Sender: TObject);
    function ProjectNames: TArray<string>;
    function IsUpdateRow(ARow: Integer): Boolean;
    function GetPage: Integer;
    procedure SetPage(AValue: Integer);
    procedure TabsChange(Sender: TObject);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LayoutButtons;
    procedure ShowPage;
    procedure LoadSaved;
    procedure RefillSaved;
    /// <summary>Zeilen des Abschnitts „Neu seit …“ samt Überschrift; 0 ohne Abschnitt.</summary>
    function IncomingLines: Integer;
    function ShowsIncoming: Boolean;
    /// <summary>Zeile des Hinweises „Anmeldung nötig“ unter der Überschrift (0 = erste Zeile darunter).</summary>
    function LoginLine: Integer;
    function TabsShown: Boolean;
  protected
    function BodyHeight: Integer; override;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile, Schaltfläche bzw. Commit an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasContinueHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): „Fortsetzen“ bzw. Commit.</summary>
    procedure ClickAt(const AHit: TAtlasContinueHit);
    /// <summary>Gewählten Eintrag der Liste „Gemerkt“ öffnen (Doppelklick, Enter).</summary>
    procedure OpenSelected;
    /// <summary>Oberkante der Zeile ARow (Koordinaten der Zeichenfläche).</summary>
    function RowTop(ARow: Integer): Integer;
    /// <summary>Oberkante des Abschnitts „Neu seit …“ (unter den Zeilen).</summary>
    function IncomingTop: Integer;
    /// <summary>Kopfzeile: „Name · 7 Reiter“.</summary>
    class function TitleText(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>Zweite Zeile: zuletzt bearbeitete Datei und Methode, z. B. „Kunde.pas › TKunde.Laden“.</summary>
    class function DetailText(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>„7 Reiter“ bzw. „1 Reiter“.</summary>
    class function TabsText(ACount: Integer): string; static;
    /// <summary>„gerade eben“, „vor 5 Min.“, „vor 2 Std.“, „gestern 18:40“ bzw. Datum mit Uhrzeit.</summary>
    class function AgeText(AAtUtc, ANowUtc: TDateTime): string; static;
    /// <summary>Zeile eines Commits: „abc1234 Betreff — Autor · Kunde.pas“.</summary>
    class function CommitText(const ACommit: TAtlasContinueCommit): string; static;
    class function CommitHint(const ACommit: TAtlasContinueCommit): string; static;
    class function HintFor(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>Spalten einer Zeile der Liste „Gemerkt“: Art, Text, Datei und Zeile, Projekt.</summary>
    class function SavedCells(const AItem: TAtlasSavedItem): TArray<string>; static;
    class function KindText(AKind: TAtlasSavedKind): string; static;
    class function NowUtc: TDateTime; static;
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasContinueSource read FSource write SetSource;
    /// <summary>Schnellaktionen (#764); nil = keine Knöpfe.</summary>
    property QuickActions: IAtlasQuickActionsSource read GetQuickActions write SetQuickActions;
    /// <summary>Knopfleiste, Stand und Tastatur der Schnellaktionen (auch für Tests).</summary>
    property Quick: TAtlasQuickActionsBar read FQuick;
    /// <summary>Kontextmenü der Zeilen: „Fortsetzen“ und die Schnellaktionen.</summary>
    property Menu: TPopupMenu read FMenu;
    property Entries: TAtlasContinueEntries read FEntries;
    property IncomingView: TAtlasContinueIncoming read FIncoming;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
    property Tabs: TTabControl read FTabs;
    property Filter: TEdit read FFilter;
    property List: TListView read FList;
    property SavedEmptyLabel: TLabel read FSavedEmpty;
    /// <summary>Gezeigte Einträge der Liste „Gemerkt“ in der Reihenfolge der Zeilen.</summary>
    property ShownSaved: TAtlasSavedItems read FShownSaved;
    /// <summary>PageRecent oder PageSaved.</summary>
    property Page: Integer read GetPage write SetPage;
  end;

implementation

uses
  System.DateUtils,
  System.UITypes,
  Winapi.Windows,
  Vcl.Themes,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Welcome.Strings;

const
  Separator = ' · ';
  Arrow = ' ' + #$203A + ' ';
  Dash = ' ' + #$2014 + ' ';

{ TAtlasWelcomeContinueFrame }

procedure TAtlasWelcomeContinueFrame.CreateWnd;
begin
  inherited;
  if FTabs.Tabs.Count = 0 then
  begin
    FTabs.Tabs.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabRecent));
    FTabs.Tabs.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabSaved));
    FTabs.TabIndex := PageRecent;
  end;
end;

constructor TAtlasWelcomeContinueFrame.Create(AOwner: TComponent);
var
  Column: TListColumn;
begin
  inherited Create(AOwner);
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Body;
  FTabs.Align := alTop;
  FTabs.Height := ScaleValue(TabHeight);
  // Reiter erst in CreateWnd: TTabControl braucht dafür ein Fenster („kein übergeordnetes Fenster“).
  FTabs.OnChange := TabsChange;

  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseLeave := BoxMouseLeave;

  FSavedPanel := TPanel.Create(Self);
  FSavedPanel.Parent := Body;
  FSavedPanel.Align := alClient;
  FSavedPanel.BevelOuter := bvNone;
  FSavedPanel.ParentBackground := True;
  FSavedPanel.Visible := False;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FSavedPanel;
  FFilter.Align := alTop;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedFilter);
  FFilter.OnChange := FilterChange;
  FFilter.OnKeyDown := FilterKeyDown;

  FSavedEmpty := TLabel.Create(Self);
  FSavedEmpty.Parent := FSavedPanel;
  FSavedEmpty.Align := alTop;
  FSavedEmpty.AlignWithMargins := True;
  FSavedEmpty.ShowAccelChar := False;
  FSavedEmpty.WordWrap := True;
  FSavedEmpty.Font.Color := clGrayText;
  FSavedEmpty.Visible := False;

  FList := TListView.Create(Self);
  FList.Parent := FSavedPanel;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.ShowHint := True;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedColKind);
  Column.Width := ScaleValue(80);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedColText);
  Column.Width := ScaleValue(220);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedColPlace);
  Column.Width := ScaleValue(140);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedColProject);
  Column.Width := ScaleValue(120);

  // Schnellaktionen (#764): Knopfleiste, Tastatur und Kontextmenü der Zeilen.
  FMenuRow := -1;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FResumeItem := TMenuItem.Create(Self);
  FResumeItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  FResumeItem.Default := True;
  FResumeItem.OnClick := ResumeClick;
  FMenu.Items.Add(FResumeItem);
  FBox.PopupMenu := FMenu;
  FQuick := TAtlasQuickActionsBar.Create(Self, FBox, Body);
  FQuick.OnScale :=
    function(AValue: Integer): Integer
    begin
      Result := ScaleValue(AValue);
    end;
  FQuick.OnOpenRow := QuickOpenRow;
  FQuick.OnRowMenu := QuickRowMenu;
  FQuick.AttachMenu(FMenu);
end;

function TAtlasWelcomeContinueFrame.GetQuickActions: IAtlasQuickActionsSource;
begin
  Result := FQuick.Source;
end;

procedure TAtlasWelcomeContinueFrame.SetQuickActions(const AValue: IAtlasQuickActionsSource);
begin
  FQuick.Source := AValue;
  UpdateContent;
end;

function TAtlasWelcomeContinueFrame.ProjectNames: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(FEntries));
  for Index := 0 to High(FEntries) do
  begin
    Result[Index] := FEntries[Index].Project;
  end;
end;

function TAtlasWelcomeContinueFrame.IsUpdateRow(ARow: Integer): Boolean;
var
  Button: TAtlasQuickActionButton;
begin
  // SVN: „aktualisiert …“ statt „holt …“.
  Result := False;
  for Button in FQuick.ButtonsOf(ARow) do
  begin
    if Button.Action = TAtlasQuickAction.Pull then
    begin
      Result := Button.Update;
    end;
  end;
end;

procedure TAtlasWelcomeContinueFrame.QuickOpenRow(ARow: Integer);
var
  Hit: TAtlasContinueHit;
begin
  // Enter ohne Knopf setzt fort (wie „Fortsetzen“).
  Hit.Row := ARow;
  Hit.Button := True;
  Hit.Commit := -1;
  ClickAt(Hit);
end;

procedure TAtlasWelcomeContinueFrame.QuickRowMenu(ARow: Integer);
var
  Position: TPoint;
begin
  if (ARow < 0) or (ARow > High(FEntries)) then
  begin
    Exit;
  end;
  Position := FBox.ClientToScreen(Point(ScaleValue(Indent), RowTop(ARow) + ScaleValue(RowHeight) div 2));
  FMenu.PopupComponent := FBox;
  FMenu.Popup(Position.X, Position.Y);
end;

procedure TAtlasWelcomeContinueFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(Position.X, Position.Y).Row;
  FResumeItem.Enabled := FMenuRow >= 0;
  // Schnellaktionen der Zeile: nur eingestellte Knöpfe, gesperrte grau.
  FQuick.PrepareMenu(FMenuRow);
end;

procedure TAtlasWelcomeContinueFrame.ResumeClick(Sender: TObject);
begin
  QuickOpenRow(FMenuRow);
end;

procedure TAtlasWelcomeContinueFrame.SetSource(const AValue: IAtlasContinueSource);
begin
  FSource := AValue;
  FSavedLoaded := False;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

function TAtlasWelcomeContinueFrame.TabsShown: Boolean;
begin
  Result := (FSource <> nil) and FSource.SavedEnabled;
end;

function TAtlasWelcomeContinueFrame.GetPage: Integer;
begin
  Result := PageRecent;
  if TabsShown and (FTabs.TabIndex = PageSaved) then
  begin
    Result := PageSaved;
  end;
end;

procedure TAtlasWelcomeContinueFrame.SetPage(AValue: Integer);
begin
  if (AValue = PageSaved) and TabsShown then
  begin
    FTabs.TabIndex := PageSaved;
  end
  else
  begin
    FTabs.TabIndex := PageRecent;
  end;
  ShowPage;
end;

procedure TAtlasWelcomeContinueFrame.TabsChange(Sender: TObject);
begin
  ShowPage;
end;

procedure TAtlasWelcomeContinueFrame.ShowPage;
var
  Saved: Boolean;
begin
  FTabs.Visible := TabsShown;
  Saved := Page = PageSaved;
  if Saved and not FSavedLoaded then
  begin
    LoadSaved;
  end;
  FSavedPanel.Visible := Saved;
  FBox.Visible := not Saved;
  // Die Tastatur der Schnellaktionen gilt nur für „Zuletzt“.
  FQuick.Sink.Visible := not Saved;
  HeightChanged;
end;

procedure TAtlasWelcomeContinueFrame.UpdateContent;
var
  Count, Lines: Integer;
begin
  // Ohne Fenster später: CreateWnd bzw. die Tafel ruft UpdateContent nach dem Einhängen.
  if not HasWindow then
  begin
    Exit;
  end;
  Count := Length(FEntries);
  Lines := IncomingLines;
  FEntries := nil;
  FIncoming := Default(TAtlasContinueIncoming);
  FQuerying := False;
  FNotice := '';
  if FSource <> nil then
  begin
    FEntries := FSource.Entries;
    FIncoming := FSource.Incoming;
    FQuerying := FSource.IncomingQuerying;
    FNotice := FSource.Notice;
  end;
  // Die Rechtecke der Schaltflächen entstehen beim Zeichnen.
  FButtonRects := nil;
  FHintKey := '';
  FQuick.SetRows(ProjectNames);
  FTabs.Visible := TabsShown;
  // „Gemerkt“ neu lesen, wenn der Reiter offen ist; sonst erst beim Wechsel dorthin.
  FSavedLoaded := False;
  if Page = PageSaved then
  begin
    LoadSaved;
  end;
  FSavedPanel.Visible := Page = PageSaved;
  FBox.Visible := Page = PageRecent;
  FQuick.Sink.Visible := Page = PageRecent;
  FBox.Invalidate;
  inherited;
  // Andere Höhe: Der Frame „Atlas“ ordnet die Spalten neu.
  if (Count <> Length(FEntries)) or (Lines <> IncomingLines) then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeContinueFrame.LoadSaved;
begin
  FSaved := nil;
  if FSource <> nil then
  begin
    FSaved := FSource.Saved;
  end;
  FSavedLoaded := True;
  RefillSaved;
end;

procedure TAtlasWelcomeContinueFrame.RefillSaved;
var
  Item: TAtlasSavedItem;
  Row: TListItem;
  Cells: TArray<string>;
  Index: Integer;
begin
  FShownSaved := TAtlasWelcomeSaved.Filter(FSaved, FFilter.Text);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Item in FShownSaved do
    begin
      Cells := SavedCells(Item);
      Row := FList.Items.Add;
      Row.Caption := Cells[0];
      for Index := 1 to High(Cells) do
      begin
        Row.SubItems.Add(Cells[Index]);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    FList.Items[0].Focused := True;
  end;
  FSavedEmpty.Visible := Length(FShownSaved) = 0;
  if Length(FSaved) = 0 then
  begin
    FSavedEmpty.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedEmpty);
  end
  else
  begin
    FSavedEmpty.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedNoMatch);
  end;
  FList.Visible := not FSavedEmpty.Visible;
end;

procedure TAtlasWelcomeContinueFrame.FilterChange(Sender: TObject);
begin
  RefillSaved;
end;

procedure TAtlasWelcomeContinueFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and FList.Visible and (FList.Items.Count > 0) then
  begin
    FList.SetFocus;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

procedure TAtlasWelcomeContinueFrame.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasWelcomeContinueFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

procedure TAtlasWelcomeContinueFrame.OpenSelected;
var
  mSource: IAtlasContinueSource;
  Item: TAtlasSavedItem;
  Index: Integer;
begin
  if (FSource = nil) or (FList.Selected = nil) then
  begin
    Exit;
  end;
  Index := FList.Selected.Index;
  if (Index < 0) or (Index > High(FShownSaved)) then
  begin
    Exit;
  end;
  mSource := FSource;
  Item := FShownSaved[Index];
  // Die Quelle öffnet Projekt und Datei: nicht im eigenen Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.OpenSaved(Item);
    end);
end;

function TAtlasWelcomeContinueFrame.ShowsIncoming: Boolean;
begin
  Result := (Length(FEntries) > 0) and (FIncoming.Available or FQuerying);
end;

function TAtlasWelcomeContinueFrame.IncomingLines: Integer;
begin
  Result := 0;
  if not ShowsIncoming then
  begin
    Exit;
  end;
  // Überschrift und je Commit eine Zeile; ohne Commits eine Zeile „Keine …“ bzw. „wird abgefragt …“.
  Result := 1 + Length(FIncoming.Commits);
  if Length(FIncoming.Commits) = 0 then
  begin
    Inc(Result);
  end;
  if FIncoming.More then
  begin
    Inc(Result);
  end;
  if FIncoming.FetchFailed then
  begin
    Inc(Result);
  end;
end;

function TAtlasWelcomeContinueFrame.BodyHeight: Integer;
var
  Rows, Lines: Integer;
begin
  Result := 0;
  if TabsShown then
  begin
    Inc(Result, ScaleValue(TabHeight));
  end;
  if Page = PageSaved then
  begin
    Inc(Result, ScaleValue(FilterHeight) + (SavedRows + 1) * ScaleValue(LineHeight) + ScaleValue(Indent));
    Exit;
  end;
  Rows := Length(FEntries);
  if Rows < 1 then
  begin
    Rows := 1;
  end;
  Lines := IncomingLines;
  if FNotice <> '' then
  begin
    Inc(Lines);
  end;
  Inc(Result, Rows * ScaleValue(RowHeight) + Lines * ScaleValue(LineHeight) + ScaleValue(Indent));
  if Lines > 0 then
  begin
    Inc(Result, ScaleValue(Indent));
  end;
end;

function TAtlasWelcomeContinueFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(Indent) div 2 + ARow * ScaleValue(RowHeight);
end;

function TAtlasWelcomeContinueFrame.IncomingTop: Integer;
var
  Rows: Integer;
begin
  Rows := Length(FEntries);
  if Rows < 1 then
  begin
    Rows := 1;
  end;
  Result := RowTop(Rows) + ScaleValue(Indent);
end;

class function TAtlasWelcomeContinueFrame.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasWelcomeContinueFrame.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
  begin
    Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
  end;
end;

class function TAtlasWelcomeContinueFrame.TabsText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabsOne);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueTabs, [ACount]);
  end;
end;

class function TAtlasWelcomeContinueFrame.AgeText(AAtUtc, ANowUtc: TDateTime): string;
var
  AtLocal: TDateTime;
  Value: Integer;
begin
  Result := '';
  if AAtUtc <= 0 then
  begin
    Exit;
  end;
  AtLocal := TTimeZone.Local.ToLocalTime(AAtUtc);
  case TAtlasWelcomeContinue.Age(AtLocal, TTimeZone.Local.ToLocalTime(ANowUtc), Value) of
    TAtlasContinueAge.JustNow:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueJustNow);
    TAtlasContinueAge.Minutes:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMinutes, [Value]);
    TAtlasContinueAge.Hours:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHours, [Value]);
    TAtlasContinueAge.Yesterday:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueYesterday, [FormatDateTime('t', AtLocal)]);
  else
    Result := FormatDateTime('ddddd t', AtLocal);
  end;
end;

class function TAtlasWelcomeContinueFrame.TitleText(const AEntry: TAtlasContinueEntry): string;
begin
  Result := AEntry.Name + Separator + TabsText(AEntry.State.TabCount);
end;

class function TAtlasWelcomeContinueFrame.DetailText(const AEntry: TAtlasContinueEntry): string;
var
  Tab: TAtlasWorkTab;
begin
  Tab := AEntry.LastTab;
  Result := TAtlasWelcomeContinue.FileNameOf(Tab.FileName);
  if Tab.Method <> '' then
  begin
    Result := Result + Arrow + Tab.Method;
  end;
end;

class function TAtlasWelcomeContinueFrame.CommitText(const ACommit: TAtlasContinueCommit): string;
var
  Names: TArray<string>;
  FileName: string;
begin
  Names := nil;
  for FileName in ACommit.Files do
  begin
    Names := Names + [TAtlasWelcomeContinue.FileNameOf(FileName)];
  end;
  Result := ACommit.Commit.ShortHash + '  ' + ACommit.Commit.Summary + Dash + ACommit.Commit.Author;
  if Length(Names) > 0 then
  begin
    Result := Result + Separator + string.Join(', ', Names);
  end;
end;

class function TAtlasWelcomeContinueFrame.CommitHint(const ACommit: TAtlasContinueCommit): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(ACommit.Commit.ShortHash + ' ' + ACommit.Commit.Summary);
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitAuthor, [ACommit.Commit.Author]));
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitDate,
      [LocalText(ACommit.Commit.Date)]));
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitAffects,
      [string.Join(', ', ACommit.Files)]));
    Lines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueCommitClick));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasWelcomeContinueFrame.HintFor(const AEntry: TAtlasContinueEntry): string;
var
  Lines: TStringList;
  Tab: TAtlasWorkTab;
  Place: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(AEntry.Project);
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHintSaved, [TabsText(AEntry.State.TabCount),
      LocalText(AEntry.State.At)]));
    Tab := AEntry.LastTab;
    if Tab.FileName <> '' then
    begin
      Place := Tab.FileName;
      if Tab.Line > 0 then
      begin
        Place := Place + ':' + IntToStr(Tab.Line);
      end;
      if Tab.Method <> '' then
      begin
        Place := Place + Arrow + Tab.Method;
      end;
      Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHintLast, [Place]));
    end;
    Lines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueHintResume));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasWelcomeContinueFrame.KindText(AKind: TAtlasSavedKind): string;
begin
  case AKind of
    TAtlasSavedKind.Note:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedNote);
    TAtlasSavedKind.Bookmark:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedBookmark);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedFavorite);
  end;
end;

class function TAtlasWelcomeContinueFrame.SavedCells(const AItem: TAtlasSavedItem): TArray<string>;
var
  mText, Project: string;
begin
  mText := AItem.Text;
  if AItem.Lost then
  begin
    mText := mText + ' ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedLost);
  end;
  Project := AItem.ProjectName;
  if AItem.Kind = TAtlasSavedKind.Favorite then
  begin
    Project := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedAllProjects);
  end;
  Result := [KindText(AItem.Kind), mText, AItem.Place, Project];
end;

procedure TAtlasWelcomeContinueFrame.LayoutButtons;
var
  Row, mWidth, mTop, Right: Integer;
  Canvas: TCanvas;
  mText: string;
begin
  // „Fortsetzen“ rechts, mittig in der Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FButtonRects, Length(FEntries));
  Canvas := FBox.Canvas;
  Canvas.Font.Assign(Font);
  mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  Right := FBox.Width - ScaleValue(Indent);
  for Row := 0 to High(FEntries) do
  begin
    mWidth := Canvas.TextWidth(mText) + 2 * ScaleValue(ButtonPadding);
    mTop := RowTop(Row) + (ScaleValue(RowHeight) - ScaleValue(ButtonHeight)) div 2;
    FButtonRects[Row] := Rect(Right - mWidth, mTop, Right, mTop + ScaleValue(ButtonHeight));
  end;
end;

procedure TAtlasWelcomeContinueFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Row, mLeft, mTop, Limit, Index, Line, Active: Integer;
  Entry: TAtlasContinueEntry;
  mText, Age: string;
  TextColor, MutedColor, LineColor, LinkColor: TColor;
  Button, QuickRect: TRect;
  Stamp: TDateTime;
  State: TAtlasQuickActionState;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  // Farben des IDE-Themas (hell oder dunkel).
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clBtnShadow);
  LinkColor := StyleServices(Self).GetSystemColor(clHotLight);
  if Length(FEntries) = 0 then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent), RowTop(0) + ScaleValue(4),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueEmpty));
  end;
  LayoutButtons;
  Stamp := NowUtc;
  Active := FQuick.ActiveRow;
  for Row := 0 to High(FEntries) do
  begin
    Entry := FEntries[Row];
    mTop := RowTop(Row);
    mLeft := ScaleValue(Indent);
    Button := FButtonRects[Row];
    Limit := Button.Left - ScaleValue(Indent);
    // Schnellaktionen (#764): aktive Zeile hinterlegt, Knöpfe statt des Zeitpunkts links von „Fortsetzen“.
    FQuick.PaintBackground(Canvas, Row, Rect(0, mTop, FBox.Width, mTop + ScaleValue(RowHeight) - ScaleValue(2)));
    if Row = Active then
    begin
      Canvas.Font.Assign(Font);
      Canvas.Font.Size := Font.Size - 1;
      Limit := FQuick.LayoutRow(Canvas, Row, Rect(ScaleValue(Indent) + ScaleValue(80), mTop, Limit,
        mTop + ScaleValue(RowHeight) - ScaleValue(2))) - ScaleValue(Indent);
    end
    else
    begin
      // Stand der letzten Schnellaktion als Marke („baut … 12 s“), sonst der Zeitpunkt.
      Canvas.Font.Assign(Font);
      State := FQuick.StateOf(Row);
      Canvas.Font.Size := Font.Size - 1;
      mText := TAtlasQuickActionsBar.StateText(State, FQuick.NowMs, IsUpdateRow(Row));
      if mText <> '' then
      begin
        QuickRect := Rect(Limit - Canvas.TextWidth(mText) - ScaleValue(12), mTop + ScaleValue(3), Limit,
          mTop + ScaleValue(19));
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := TAtlasQuickActionsBar.StateColor(State);
        Canvas.Pen.Color := Canvas.Brush.Color;
        Canvas.RoundRect(QuickRect.Left, QuickRect.Top, QuickRect.Right, QuickRect.Bottom, ScaleValue(16),
          ScaleValue(16));
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := clWhite;
        Canvas.TextOut(QuickRect.Left + ScaleValue(6), QuickRect.Top + (QuickRect.Height - Canvas.TextHeight(mText)) div 2,
          mText);
        Limit := QuickRect.Left - ScaleValue(Indent);
      end
      else
      begin
        // Zeitpunkt rechts vor der Schaltfläche.
        Canvas.Font.Assign(Font);
        Canvas.Font.Color := MutedColor;
        Age := AgeText(Entry.State.At, Stamp);
        if Age <> '' then
        begin
          Canvas.TextOut(Limit - Canvas.TextWidth(Age), mTop + ScaleValue(3), Age);
          Limit := Limit - Canvas.TextWidth(Age) - ScaleValue(Indent);
        end;
      end;
    end;
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := TextColor;
    Canvas.Font.Style := [fsBold];
    Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), Limit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
      Entry.Name);
    Inc(mLeft, Canvas.TextWidth(Entry.Name));
    Canvas.Font.Style := [];
    if mLeft < Limit then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), Limit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
        Separator + TabsText(Entry.State.TabCount));
    end;
    // Zweite Zeile: Datei und Methode.
    mLeft := ScaleValue(Indent);
    Canvas.Font.Color := MutedColor;
    if Row = Active then
    begin
      Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(23), Limit, mTop + ScaleValue(41)), mLeft, mTop + ScaleValue(23),
        DetailText(Entry));
    end
    else
    begin
      Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(23), Button.Left - ScaleValue(Indent), mTop + ScaleValue(41)), mLeft,
        mTop + ScaleValue(23), DetailText(Entry));
    end;
    // Schaltfläche.
    Canvas.Pen.Color := LineColor;
    Canvas.Brush.Style := bsClear;
    Canvas.RoundRect(Button.Left, Button.Top, Button.Right, Button.Bottom, ScaleValue(6), ScaleValue(6));
    Canvas.Font.Color := TextColor;
    mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
    Canvas.TextOut(Button.Left + (Button.Width - Canvas.TextWidth(mText)) div 2,
      Button.Top + (Button.Height - Canvas.TextHeight(mText)) div 2, mText);
    if Row = Active then
    begin
      Canvas.Font.Assign(Font);
      Canvas.Font.Size := Font.Size - 1;
      FQuick.PaintRow(Canvas, Row);
    end;
  end;
  // Neu seit deinem letzten Öffnen (für den obersten Eintrag).
  Line := 0;
  mTop := IncomingTop;
  mLeft := ScaleValue(Indent);
  Limit := FBox.Width - ScaleValue(Indent);
  if ShowsIncoming then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := TextColor;
    if FIncoming.Upstream <> '' then
    begin
      mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueIncomingTitle, [FIncoming.Upstream]);
    end
    else
    begin
      mText := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueIncomingTitle, ['…']);
    end;
    Canvas.TextRect(Rect(mLeft, mTop, Limit, mTop + ScaleValue(LineHeight)), mLeft, mTop, mText);
    Inc(Line);
    Canvas.Font.Style := [];
    for Index := 0 to High(FIncoming.Commits) do
    begin
      Canvas.Font.Color := LinkColor;
      Canvas.TextRect(Rect(mLeft, mTop + Line * ScaleValue(LineHeight), Limit, mTop + (Line + 1) * ScaleValue(LineHeight)),
        mLeft + ScaleValue(Indent), mTop + Line * ScaleValue(LineHeight), CommitText(FIncoming.Commits[Index]));
      Inc(Line);
    end;
    Canvas.Font.Color := MutedColor;
    if Length(FIncoming.Commits) = 0 then
    begin
      if FQuerying then
      begin
        mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingQuerying);
      end
      else
      begin
        mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingNone);
      end;
      Canvas.TextRect(Rect(mLeft, mTop + Line * ScaleValue(LineHeight), Limit, mTop + (Line + 1) * ScaleValue(LineHeight)),
        mLeft + ScaleValue(Indent), mTop + Line * ScaleValue(LineHeight), mText);
      Inc(Line);
    end;
    if FIncoming.More then
    begin
      Canvas.TextOut(mLeft + ScaleValue(Indent), mTop + Line * ScaleValue(LineHeight),
        TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingMore));
      Inc(Line);
    end;
    // Fehlt die Anmeldung, die Ursache als Link statt nur „ohne Abruf“ (#1287).
    if FIncoming.LoginNeeded then
    begin
      Canvas.Font.Color := LinkColor;
      Canvas.TextOut(mLeft + ScaleValue(Indent), mTop + Line * ScaleValue(LineHeight),
        TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingLogin));
      Canvas.Font.Color := MutedColor;
      Inc(Line);
    end
    else if FIncoming.FetchFailed then
    begin
      Canvas.TextOut(mLeft + ScaleValue(Indent), mTop + Line * ScaleValue(LineHeight),
        TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingFetchFailed));
      Inc(Line);
    end;
  end;
  // Hinweis der Quelle (z. B. übersprungene Dateien).
  if FNotice <> '' then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := TColor($001A8CC9);
    Canvas.TextRect(Rect(mLeft, mTop + Line * ScaleValue(LineHeight), Limit, mTop + (Line + 1) * ScaleValue(LineHeight)),
      mLeft, mTop + Line * ScaleValue(LineHeight), FNotice);
  end;
end;

function TAtlasWelcomeContinueFrame.HitTest(X, Y: Integer): TAtlasContinueHit;
var
  Line: Integer;
begin
  Result.Row := -1;
  Result.Button := False;
  Result.Commit := -1;
  Result.Login := False;
  if Length(FEntries) = 0 then
  begin
    Exit;
  end;
  if (Y >= RowTop(0)) and (Y < RowTop(Length(FEntries))) then
  begin
    Result.Row := (Y - RowTop(0)) div ScaleValue(RowHeight);
    if (Result.Row >= 0) and (Result.Row <= High(FButtonRects)) then
    begin
      Result.Button := FButtonRects[Result.Row].Contains(Point(X, Y));
    end;
    Exit;
  end;
  if not ShowsIncoming or (Y < IncomingTop) then
  begin
    Exit;
  end;
  // Zeile 0 ist die Überschrift, danach die Commits.
  Line := (Y - IncomingTop) div ScaleValue(LineHeight) - 1;
  if (Line >= 0) and (Line <= High(FIncoming.Commits)) then
  begin
    Result.Commit := Line;
  end;
  // Hinweis „Anmeldung nötig“: nach den Commits (bzw. „Keine …“) und „… weitere“.
  if FIncoming.LoginNeeded and (Line = LoginLine) then
  begin
    Result.Login := True;
  end;
end;

function TAtlasWelcomeContinueFrame.LoginLine: Integer;
begin
  Result := Length(FIncoming.Commits);
  if Result = 0 then
  begin
    Result := 1;
  end;
  if FIncoming.More then
  begin
    Inc(Result);
  end;
end;

procedure TAtlasWelcomeContinueFrame.ClickAt(const AHit: TAtlasContinueHit);
var
  mSource: IAtlasContinueSource;
  Project: string;
  Commit: TAtlasContinueCommit;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  if AHit.Button and (AHit.Row >= 0) and (AHit.Row <= High(FEntries)) then
  begin
    Project := FEntries[AHit.Row].Project;
    // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.Resume(Project);
      end);
    Exit;
  end;
  if AHit.Login then
  begin
    Project := FIncoming.Project;
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.ShowServerAccess(Project);
      end);
    Exit;
  end;
  if (AHit.Commit >= 0) and (AHit.Commit <= High(FIncoming.Commits)) then
  begin
    Project := FIncoming.Project;
    Commit := FIncoming.Commits[AHit.Commit];
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.ShowCommit(Project, Commit);
      end);
  end;
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasContinueHit;
  Key, mHint, State: string;
  QuickRow, QuickButton: Integer;
  OnMenu: Boolean;
begin
  Hit := HitTest(X, Y);
  FQuick.MouseMove(Hit.Row, X, Y);
  if not FQuick.HitTest(X, Y, QuickRow, QuickButton, OnMenu) then
  begin
    QuickButton := -1;
  end;
  if Hit.Button or (Hit.Commit >= 0) or Hit.Login or (QuickButton >= 0) then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  Key := Format('%d/%d/%d', [Hit.Row, Hit.Commit, QuickButton]);
  if Key = FHintKey then
  begin
    Exit;
  end;
  FHintKey := Key;
  if (QuickButton >= 0) and FQuick.HintAt(X, Y, mHint) then
  begin
    FBox.Hint := mHint;
  end
  else if Hit.Row >= 0 then
  begin
    FBox.Hint := HintFor(FEntries[Hit.Row]);
    // Stand der letzten Schnellaktion samt Grund (#764).
    State := TAtlasQuickActionsBar.StateText(FQuick.StateOf(Hit.Row), FQuick.NowMs, IsUpdateRow(Hit.Row));
    if (State <> '') and (FQuick.StateOf(Hit.Row).Detail <> '') then
    begin
      State := State + ': ' + FQuick.StateOf(Hit.Row).Detail;
    end;
    if State <> '' then
    begin
      FBox.Hint := FBox.Hint + sLineBreak + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeQuickHintState,
        [State]);
    end;
    if FQuick.Active then
    begin
      FBox.Hint := FBox.Hint + sLineBreak + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickHintKeys);
    end;
  end
  else if Hit.Commit >= 0 then
  begin
    FBox.Hint := CommitHint(FIncoming.Commits[Hit.Commit]);
  end
  else
  begin
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Knöpfe der Schnellaktionen (#764) handeln selbst.
  if (Button = mbLeft) and not FQuick.ClickAt(X, Y) then
  begin
    ClickAt(HitTest(X, Y));
  end;
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Die Tastatur der Schnellaktionen übernimmt Zeile und Fokus (#764).
  FQuick.MouseDown(HitTest(X, Y).Row);
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseLeave(Sender: TObject);
begin
  FQuick.MouseLeave;
  FHintKey := '';
end;

end.
