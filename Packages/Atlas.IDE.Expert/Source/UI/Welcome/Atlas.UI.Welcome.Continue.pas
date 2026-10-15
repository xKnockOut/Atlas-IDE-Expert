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
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Frame;

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
    FBox: TPaintBox;
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
    procedure SetSource(const AValue: IAtlasContinueSource);
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
    function TabsShown: Boolean;
  protected
    function BodyHeight: Integer; override;
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
    class function HintFor(const AEntry: TAtlasContinueEntry; ANowUtc: TDateTime): string; static;
    /// <summary>Spalten einer Zeile der Liste „Gemerkt“: Art, Text, Datei und Zeile, Projekt.</summary>
    class function SavedCells(const AItem: TAtlasSavedItem): TArray<string>; static;
    class function KindText(AKind: TAtlasSavedKind): string; static;
    class function NowUtc: TDateTime; static;
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasContinueSource read FSource write SetSource;
    property Entries: TAtlasContinueEntries read FEntries;
    property IncomingView: TAtlasContinueIncoming read FIncoming;
    property PaintBox: TPaintBox read FBox;
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
  Winapi.Windows,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

const
  Separator = ' · ';
  Arrow = ' ' + #$203A + ' ';
  Dash = ' ' + #$2014 + ' ';

{ TAtlasWelcomeContinueFrame }

constructor TAtlasWelcomeContinueFrame.Create(AOwner: TComponent);
var
  Column: TListColumn;
begin
  inherited Create(AOwner);
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Body;
  FTabs.Align := alTop;
  FTabs.Height := ScaleValue(TabHeight);
  FTabs.Tabs.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueTabRecent));
  FTabs.Tabs.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueTabSaved));
  FTabs.TabIndex := PageRecent;
  FTabs.OnChange := TabsChange;

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;

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
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedFilter);
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
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedColKind);
  Column.Width := ScaleValue(80);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedColText);
  Column.Width := ScaleValue(220);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedColPlace);
  Column.Width := ScaleValue(140);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedColProject);
  Column.Width := ScaleValue(120);
end;

procedure TAtlasWelcomeContinueFrame.SetSource(const AValue: IAtlasContinueSource);
begin
  FSource := AValue;
  FSavedLoaded := False;
  UpdateContent;
  if FSource <> nil then
    FSource.Shown;
end;

function TAtlasWelcomeContinueFrame.TabsShown: Boolean;
begin
  Result := (FSource <> nil) and FSource.SavedEnabled;
end;

function TAtlasWelcomeContinueFrame.GetPage: Integer;
begin
  Result := PageRecent;
  if TabsShown and (FTabs.TabIndex = PageSaved) then
    Result := PageSaved;
end;

procedure TAtlasWelcomeContinueFrame.SetPage(AValue: Integer);
begin
  if (AValue = PageSaved) and TabsShown then
    FTabs.TabIndex := PageSaved
  else
    FTabs.TabIndex := PageRecent;
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
    LoadSaved;
  FSavedPanel.Visible := Saved;
  FBox.Visible := not Saved;
  HeightChanged;
end;

procedure TAtlasWelcomeContinueFrame.UpdateContent;
var
  Count, Lines: Integer;
begin
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
  FTabs.Visible := TabsShown;
  // „Gemerkt“ neu lesen, wenn der Reiter offen ist; sonst erst beim Wechsel dorthin.
  FSavedLoaded := False;
  if Page = PageSaved then
    LoadSaved;
  FSavedPanel.Visible := Page = PageSaved;
  FBox.Visible := Page = PageRecent;
  FBox.Invalidate;
  inherited;
  // Andere Höhe: Der Frame „Atlas“ ordnet die Spalten neu.
  if (Count <> Length(FEntries)) or (Lines <> IncomingLines) then
    HeightChanged;
end;

procedure TAtlasWelcomeContinueFrame.LoadSaved;
begin
  FSaved := nil;
  if FSource <> nil then
    FSaved := FSource.Saved;
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
        Row.SubItems.Add(Cells[Index]);
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
    FSavedEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedEmpty)
  else
    FSavedEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedNoMatch);
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
  Source: IAtlasContinueSource;
  Item: TAtlasSavedItem;
  Index: Integer;
begin
  if (FSource = nil) or (FList.Selected = nil) then
    Exit;
  Index := FList.Selected.Index;
  if (Index < 0) or (Index > High(FShownSaved)) then
    Exit;
  Source := FSource;
  Item := FShownSaved[Index];
  // Die Quelle öffnet Projekt und Datei: nicht im eigenen Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.OpenSaved(Item);
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
    Exit;
  // Überschrift und je Commit eine Zeile; ohne Commits eine Zeile „Keine …“ bzw. „wird abgefragt …“.
  Result := 1 + Length(FIncoming.Commits);
  if Length(FIncoming.Commits) = 0 then
    Inc(Result);
  if FIncoming.More then
    Inc(Result);
  if FIncoming.FetchFailed then
    Inc(Result);
end;

function TAtlasWelcomeContinueFrame.BodyHeight: Integer;
var
  Rows, Lines: Integer;
begin
  Result := 0;
  if TabsShown then
    Inc(Result, ScaleValue(TabHeight));
  if Page = PageSaved then
  begin
    Inc(Result, ScaleValue(FilterHeight) + (SavedRows + 1) * ScaleValue(LineHeight) + ScaleValue(Indent));
    Exit;
  end;
  Rows := Length(FEntries);
  if Rows < 1 then
    Rows := 1;
  Lines := IncomingLines;
  if FNotice <> '' then
    Inc(Lines);
  Inc(Result, Rows * ScaleValue(RowHeight) + Lines * ScaleValue(LineHeight) + ScaleValue(Indent));
  if Lines > 0 then
    Inc(Result, ScaleValue(Indent));
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
    Rows := 1;
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
    Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

class function TAtlasWelcomeContinueFrame.TabsText(ACount: Integer): string;
begin
  if ACount = 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueTabsOne)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueTabs, [ACount]);
end;

class function TAtlasWelcomeContinueFrame.AgeText(AAtUtc, ANowUtc: TDateTime): string;
var
  AtLocal: TDateTime;
  Value: Integer;
begin
  Result := '';
  if AAtUtc <= 0 then
    Exit;
  AtLocal := TTimeZone.Local.ToLocalTime(AAtUtc);
  case TAtlasWelcomeContinue.Age(AtLocal, TTimeZone.Local.ToLocalTime(ANowUtc), Value) of
    TAtlasContinueAge.JustNow:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueJustNow);
    TAtlasContinueAge.Minutes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueMinutes, [Value]);
    TAtlasContinueAge.Hours:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueHours, [Value]);
    TAtlasContinueAge.Yesterday:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueYesterday, [FormatDateTime('t', AtLocal)]);
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
    Result := Result + Arrow + Tab.Method;
end;

class function TAtlasWelcomeContinueFrame.CommitText(const ACommit: TAtlasContinueCommit): string;
var
  Names: TArray<string>;
  FileName: string;
begin
  Names := nil;
  for FileName in ACommit.Files do
    Names := Names + [TAtlasWelcomeContinue.FileNameOf(FileName)];
  Result := ACommit.Commit.ShortHash + '  ' + ACommit.Commit.Summary + Dash + ACommit.Commit.Author;
  if Length(Names) > 0 then
    Result := Result + Separator + string.Join(', ', Names);
end;

class function TAtlasWelcomeContinueFrame.CommitHint(const ACommit: TAtlasContinueCommit): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(ACommit.Commit.ShortHash + ' ' + ACommit.Commit.Summary);
    Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitAuthor, [ACommit.Commit.Author]));
    Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitDate, [LocalText(ACommit.Commit.Date)]));
    Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueCommitAffects, [string.Join(', ', ACommit.Files)]));
    Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueCommitClick));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasWelcomeContinueFrame.HintFor(const AEntry: TAtlasContinueEntry; ANowUtc: TDateTime): string;
var
  Lines: TStringList;
  Tab: TAtlasWorkTab;
  Place: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(AEntry.Project);
    Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueHintSaved, [TabsText(AEntry.State.TabCount),
      LocalText(AEntry.State.At)]));
    Tab := AEntry.LastTab;
    if Tab.FileName <> '' then
    begin
      Place := Tab.FileName;
      if Tab.Line > 0 then
        Place := Place + ':' + IntToStr(Tab.Line);
      if Tab.Method <> '' then
        Place := Place + Arrow + Tab.Method;
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueHintLast, [Place]));
    end;
    Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeContinueHintResume));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasWelcomeContinueFrame.KindText(AKind: TAtlasSavedKind): string;
begin
  case AKind of
    TAtlasSavedKind.Note:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedNote);
    TAtlasSavedKind.Bookmark:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedBookmark);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedFavorite);
  end;
end;

class function TAtlasWelcomeContinueFrame.SavedCells(const AItem: TAtlasSavedItem): TArray<string>;
var
  Text, Project: string;
begin
  Text := AItem.Text;
  if AItem.Lost then
    Text := Text + ' ' + TAtlasStrings.Text(TAtlasTextId.WelcomeSavedLost);
  Project := AItem.ProjectName;
  if AItem.Kind = TAtlasSavedKind.Favorite then
    Project := TAtlasStrings.Text(TAtlasTextId.WelcomeSavedAllProjects);
  Result := [KindText(AItem.Kind), Text, AItem.Place, Project];
end;

procedure TAtlasWelcomeContinueFrame.LayoutButtons;
var
  Row, Width, Top, Right: Integer;
  Canvas: TCanvas;
  Text: string;
begin
  // „Fortsetzen“ rechts, mittig in der Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FButtonRects, Length(FEntries));
  Canvas := FBox.Canvas;
  Canvas.Font.Assign(Font);
  Text := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueResume);
  Right := FBox.Width - ScaleValue(Indent);
  for Row := 0 to High(FEntries) do
  begin
    Width := Canvas.TextWidth(Text) + 2 * ScaleValue(ButtonPadding);
    Top := RowTop(Row) + (ScaleValue(RowHeight) - ScaleValue(ButtonHeight)) div 2;
    FButtonRects[Row] := Rect(Right - Width, Top, Right, Top + ScaleValue(ButtonHeight));
  end;
end;

procedure TAtlasWelcomeContinueFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Row, Left, Top, Limit, Index, Line: Integer;
  Entry: TAtlasContinueEntry;
  Text, Age: string;
  TextColor, MutedColor, LineColor, LinkColor: TColor;
  Button: TRect;
  Stamp: TDateTime;
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
    Canvas.TextOut(ScaleValue(Indent), RowTop(0) + ScaleValue(4), TAtlasStrings.Text(TAtlasTextId.WelcomeContinueEmpty));
  end;
  LayoutButtons;
  Stamp := NowUtc;
  for Row := 0 to High(FEntries) do
  begin
    Entry := FEntries[Row];
    Top := RowTop(Row);
    Left := ScaleValue(Indent);
    Button := FButtonRects[Row];
    Limit := Button.Left - ScaleValue(Indent);
    // Zeitpunkt rechts vor der Schaltfläche.
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := MutedColor;
    Age := AgeText(Entry.State.At, Stamp);
    if Age <> '' then
    begin
      Canvas.TextOut(Limit - Canvas.TextWidth(Age), Top + ScaleValue(3), Age);
      Limit := Limit - Canvas.TextWidth(Age) - ScaleValue(Indent);
    end;
    Canvas.Font.Color := TextColor;
    Canvas.Font.Style := [fsBold];
    Canvas.TextRect(Rect(Left, Top + ScaleValue(3), Limit, Top + ScaleValue(21)), Left, Top + ScaleValue(3),
      Entry.Name);
    Inc(Left, Canvas.TextWidth(Entry.Name));
    Canvas.Font.Style := [];
    if Left < Limit then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextRect(Rect(Left, Top + ScaleValue(3), Limit, Top + ScaleValue(21)), Left, Top + ScaleValue(3),
        Separator + TabsText(Entry.State.TabCount));
    end;
    // Zweite Zeile: Datei und Methode.
    Left := ScaleValue(Indent);
    Canvas.Font.Color := MutedColor;
    Canvas.TextRect(Rect(Left, Top + ScaleValue(23), Button.Left - ScaleValue(Indent), Top + ScaleValue(41)), Left,
      Top + ScaleValue(23), DetailText(Entry));
    // Schaltfläche.
    Canvas.Pen.Color := LineColor;
    Canvas.Brush.Style := bsClear;
    Canvas.RoundRect(Button.Left, Button.Top, Button.Right, Button.Bottom, ScaleValue(6), ScaleValue(6));
    Canvas.Font.Color := TextColor;
    Text := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueResume);
    Canvas.TextOut(Button.Left + (Button.Width - Canvas.TextWidth(Text)) div 2,
      Button.Top + (Button.Height - Canvas.TextHeight(Text)) div 2, Text);
  end;
  // Neu seit deinem letzten Öffnen (für den obersten Eintrag).
  Line := 0;
  Top := IncomingTop;
  Left := ScaleValue(Indent);
  Limit := FBox.Width - ScaleValue(Indent);
  if ShowsIncoming then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := TextColor;
    if FIncoming.Upstream <> '' then
      Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueIncomingTitle, [FIncoming.Upstream])
    else
      Text := TAtlasStrings.Fmt(TAtlasTextId.WelcomeContinueIncomingTitle, ['…']);
    Canvas.TextRect(Rect(Left, Top, Limit, Top + ScaleValue(LineHeight)), Left, Top, Text);
    Inc(Line);
    Canvas.Font.Style := [];
    for Index := 0 to High(FIncoming.Commits) do
    begin
      Canvas.Font.Color := LinkColor;
      Canvas.TextRect(Rect(Left, Top + Line * ScaleValue(LineHeight), Limit, Top + (Line + 1) * ScaleValue(LineHeight)),
        Left + ScaleValue(Indent), Top + Line * ScaleValue(LineHeight), CommitText(FIncoming.Commits[Index]));
      Inc(Line);
    end;
    Canvas.Font.Color := MutedColor;
    if Length(FIncoming.Commits) = 0 then
    begin
      if FQuerying then
        Text := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueIncomingQuerying)
      else
        Text := TAtlasStrings.Text(TAtlasTextId.WelcomeContinueIncomingNone);
      Canvas.TextRect(Rect(Left, Top + Line * ScaleValue(LineHeight), Limit, Top + (Line + 1) * ScaleValue(LineHeight)),
        Left + ScaleValue(Indent), Top + Line * ScaleValue(LineHeight), Text);
      Inc(Line);
    end;
    if FIncoming.More then
    begin
      Canvas.TextOut(Left + ScaleValue(Indent), Top + Line * ScaleValue(LineHeight),
        TAtlasStrings.Text(TAtlasTextId.WelcomeContinueIncomingMore));
      Inc(Line);
    end;
    if FIncoming.FetchFailed then
    begin
      Canvas.TextOut(Left + ScaleValue(Indent), Top + Line * ScaleValue(LineHeight),
        TAtlasStrings.Text(TAtlasTextId.WelcomeContinueIncomingFetchFailed));
      Inc(Line);
    end;
  end;
  // Hinweis der Quelle (z. B. übersprungene Dateien).
  if FNotice <> '' then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := TColor($001A8CC9);
    Canvas.TextRect(Rect(Left, Top + Line * ScaleValue(LineHeight), Limit, Top + (Line + 1) * ScaleValue(LineHeight)),
      Left, Top + Line * ScaleValue(LineHeight), FNotice);
  end;
end;

function TAtlasWelcomeContinueFrame.HitTest(X, Y: Integer): TAtlasContinueHit;
var
  Line: Integer;
begin
  Result.Row := -1;
  Result.Button := False;
  Result.Commit := -1;
  if Length(FEntries) = 0 then
    Exit;
  if (Y >= RowTop(0)) and (Y < RowTop(Length(FEntries))) then
  begin
    Result.Row := (Y - RowTop(0)) div ScaleValue(RowHeight);
    if (Result.Row >= 0) and (Result.Row <= High(FButtonRects)) then
      Result.Button := FButtonRects[Result.Row].Contains(Point(X, Y));
    Exit;
  end;
  if not ShowsIncoming or (Y < IncomingTop) then
    Exit;
  // Zeile 0 ist die Überschrift, danach die Commits.
  Line := (Y - IncomingTop) div ScaleValue(LineHeight) - 1;
  if (Line >= 0) and (Line <= High(FIncoming.Commits)) then
    Result.Commit := Line;
end;

procedure TAtlasWelcomeContinueFrame.ClickAt(const AHit: TAtlasContinueHit);
var
  Source: IAtlasContinueSource;
  Project: string;
  Commit: TAtlasContinueCommit;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  if AHit.Button and (AHit.Row >= 0) and (AHit.Row <= High(FEntries)) then
  begin
    Project := FEntries[AHit.Row].Project;
    // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        Source.Resume(Project);
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
        Source.ShowCommit(Project, Commit);
      end);
  end;
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasContinueHit;
  Key: string;
begin
  Hit := HitTest(X, Y);
  if Hit.Button or (Hit.Commit >= 0) then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  Key := Format('%d/%d', [Hit.Row, Hit.Commit]);
  if Key = FHintKey then
    Exit;
  FHintKey := Key;
  if Hit.Row >= 0 then
    FBox.Hint := HintFor(FEntries[Hit.Row], NowUtc)
  else if Hit.Commit >= 0 then
    FBox.Hint := CommitHint(FIncoming.Commits[Hit.Commit])
  else
    FBox.Hint := '';
  Application.CancelHint;
end;

procedure TAtlasWelcomeContinueFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y));
end;

end.
