unit Atlas.UI.Welcome.Issues;

// Bereich „Meine Issues“ der Willkommensseite (#765, Mockup #ws12), ohne
// Open Tools API. Selbst gezeichnet, je Issue zwei Zeilen im Raster:
//   #753     Atlas-Bereiche und Layout der Willkommens…   [Beginnen]
//            (plugin) (welcome) (PR #760 · CI grün)
//   ─────────────────────────────────────────────────────────────────
//   ATL-123  Tracker im Bereich                           [Beginnen]
//            (In Arbeit) (Hoch) (Sprint 12) (aktuell)
//   „Beginnen“ legt den Branch an und öffnet das Projekt.
// Kennung grau in Festbreitenschrift (Klick öffnet das Issue im Browser; mit
// issues.preview zeigt ein Klick auf Zeile oder Kennung das Issue im Fenster
// „Atlas-Issue“ und Strg+Klick öffnet den Browser, #1264),
// Titel abgeschnitten, darunter Felder als Chips mit Rahmen (GitHub: Labels
// und der Pull Request mit CI-Ampel, Klick öffnet ihn; YouTrack: Zustand,
// Priorität, Sprint). Rechts „Beginnen“ über beide Zeilen. Über der Liste nur
// bei Bedarf eine Zeile zum Stand (wird abgefragt, Fehler, „Stand vom …“),
// darunter die Fußzeile bzw. der Hinweis nach „Beginnen“. Kontextmenü: Im
// Browser öffnen, Pull-Request im Browser, Beginnen, Nur merken, Tracker jetzt
// abfragen, Zugang hinterlegen, Aktuelles Issue beenden.
// Ohne Tracker (weder .atlas noch Zuordnung, #1261) ist die Fußzeile der Link
// „Kein Tracker für dieses Projekt – zuordnen …“ (AssignProject).
// Abfragen (#1262): rechts in der Titelzeile die Klappliste „Mir zugewiesen
// (3) ▾“ mit den passenden Abfragen samt Trefferzahl der letzten Abfrage und
// „Abfragen bearbeiten …“ (issues.queryPicker aus: keine Klappliste). Unter
// der Fußzeile eine Zeile mit Verbindung, Tracker-Projekt und der gesendeten
// Abfrage.
// Daten und Aktionen kommen über IAtlasIssuesSource aus der IDE-Schicht;
// Aktionen gehen über die Nachrichtenschleife, weil die Quelle den Bereich
// daraufhin neu füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Welcome.Issues,
  Atlas.UI.Welcome.Frame;

type
  IAtlasIssuesSource = interface
    ['{8D3F6A21-5C4B-4E97-A1D8-2B7E9C05F364}']
    function View: TAtlasIssuesView;
    /// <summary>Der Bereich wird gezeigt: bei Bedarf den Tracker im Hintergrund fragen.</summary>
    procedure Shown;
    /// <summary>„Beginnen“ mit AMode (Branch anlegen oder nur merken).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    /// <summary>Issue im Fenster „Atlas-Issue“ zeigen (#1264).</summary>
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    /// <summary>Tracker jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow;
    /// <summary>„Zugang zum Issue-Tracker hinterlegen …“.</summary>
    procedure Credentials;
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung TrackerLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Aktuelles Issue beenden (mit Rückfrage).</summary>
    procedure EndActive;
    /// <summary>„zuordnen …“ (#1261): Seite Issue-Tracker mit einer Zeile für das Projekt öffnen.</summary>
    procedure AssignProject;
    /// <summary>Abfrage AName für das Projekt wählen und gleich abfragen (#1262).</summary>
    procedure SelectQuery(const AName: string);
    /// <summary>„Abfragen bearbeiten …“: Seite Issue-Tracker öffnen.</summary>
    procedure EditQueries;
  end;

{$SCOPEDENUMS ON}
  TAtlasIssuesHitKind = (None, Row, Key, PullRequest, Start, Assign);
{$SCOPEDENUMS OFF}

  TAtlasIssuesHit = record
    Kind: TAtlasIssuesHitKind;
    /// <summary>Zeile; -1 sonst.</summary>
    Index: Integer;
    class function Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit; static;
  end;

  TAtlasWelcomeIssuesFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    KeyWidth = 76;
    LineHeight = 20;
    ChipLineHeight = 22;
    RowPadding = 5;
    StatusHeight = 22;
    FooterHeight = 24;
    ButtonHeight = 26;
    ButtonPadding = 12;
    ChipHeight = 18;
    ChipPadding = 6;
    ChipGap = 4;
    ChipRadius = 8;
    MonoFont = 'Consolas';
  private
    FSource: IAtlasIssuesSource;
    FBox: TAtlasWelcomeCanvas;
    FView: TAtlasIssuesView;
    FKeyRects: TArray<TRect>;
    FPullRects: TArray<TRect>;
    FStartRects: TArray<TRect>;
    /// <summary>Link „zuordnen …“ in der Fußzeile; leer ohne.</summary>
    FAssignRect: TRect;
    FMenu: TPopupMenu;
    FPreviewItem: TMenuItem;
    FBrowseItem: TMenuItem;
    FBrowsePullItem: TMenuItem;
    FStartBranchItem: TMenuItem;
    FStartRememberItem: TMenuItem;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FEndItem: TMenuItem;
    /// <summary>Klappliste der Abfragen in der Titelzeile (#1262).</summary>
    FQueryLabel: TLabel;
    FQueryMenu: TPopupMenu;
    FMenuRow: Integer;
    FHintKey: string;
    procedure SetSource(const AValue: IAtlasIssuesSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure BrowsePullClick(Sender: TObject);
    procedure StartBranchClick(Sender: TObject);
    procedure StartRememberClick(Sender: TObject);
    procedure QueryClick(Sender: TObject);
    procedure CredentialsClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    procedure QueryLabelClick(Sender: TObject);
    procedure QueryItemClick(Sender: TObject);
    procedure QueriesEditClick(Sender: TObject);
    procedure UpdateQueryPicker;
    function MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
    procedure Post(const AAction: TThreadProcedure);
    function ListTop: Integer;
    function RowTop(AIndex: Integer): Integer;
    function RowHeight(AIndex: Integer): Integer;
    function FooterTop: Integer;
    function SourceTop: Integer;
    function ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
    procedure PaintChip(ACanvas: TCanvas; var ALeft: Integer; ATop, ALimit: Integer; const AText: string;
      AColor: TColor; AFilled: Boolean; out ARect: TRect);
    procedure PaintRow(ACanvas: TCanvas; AIndex: Integer);
    procedure PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    function HitTest(X, Y: Integer): TAtlasIssuesHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): Kennung und Pull Request öffnen den Browser, „Beginnen“
    /// beginnt mit der Einstellung issues.start.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit); overload;
    /// <summary>ABrowse: Strg+Klick, öffnet den Browser auch mit issues.preview.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean); overload;
    /// <summary>„Beginnen“ nutzbar: Quelle da, keine laufende Aktion.</summary>
    function CanStart: Boolean;
    /// <summary>Zeile über der Liste: Stand, Fehler, „Stand vom …“; '' bei frischem Stand.</summary>
    class function StatusText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Fußzeile: Hinweis, sonst aktuelles Issue außerhalb der Liste, sonst was „Beginnen“ tut.</summary>
    class function FooterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Die Fußzeile ist der Link „zuordnen …“ (#1261): Projekt ohne Tracker, Zuordnen möglich.</summary>
    class function FooterIsAssign(const AView: TAtlasIssuesView): Boolean; static;
    /// <summary>Zeile unter der Fußzeile (#1262): „Firma · KASSE · Abfrage: …“; '' ohne Tracker.</summary>
    class function SourceText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Eintrag der Klappliste: „Name (3)“, ab MaxItems „Name (10+)“, ohne Abfrage nur der Name.</summary>
    class function QueryCaption(const AName: string; ACount: Integer): string; static;
    /// <summary>Klappliste sichtbar: eingeschaltet und Tracker mit Abfragen.</summary>
    class function ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean; static;
    /// <summary>Klappliste füllen (auch für Tests): passende Abfragen, die gewählte mit Haken, dann
    /// „Abfragen bearbeiten …“.</summary>
    procedure FillQueryMenu;
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
    /// <summary>„PR #760 · CI grün“, „PR #760 (Entwurf)“; '' ohne Pull Request.</summary>
    class function PullRequestText(const APull: TAtlasTrackerPullRequest): string; static;
    class function ChecksColor(AChecks: TAtlasTrackerChecks): TColor; static;
    /// <summary>Kurztext „ATL-123 · 3 offen“ (Zustandskachel und Statusfeld); ohne aktuelles Issue „3 offen“
    /// mit dem Anbieter.</summary>
    class function TileText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Hinweis auf „Beginnen“: Branch nach Muster bzw. „Merkt … als aktuelles Issue“.</summary>
    class function StartHint(const AView: TAtlasIssuesView; const AIssue: TAtlasTrackerIssue): string; static;
    /// <summary>Titel des Bereichs: „Meine Issues · Projekt“; ohne Projekt „Meine Issues“.</summary>
    class function TitleText(const AProjectName: string): string; static;
    class function NowUtc: TDateTime; static;
    property Source: IAtlasIssuesSource read FSource write SetSource;
    property View: TAtlasIssuesView read FView;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
    property Menu: TPopupMenu read FMenu;
    property PreviewItem: TMenuItem read FPreviewItem;
    property BrowseItem: TMenuItem read FBrowseItem;
    property BrowsePullItem: TMenuItem read FBrowsePullItem;
    property StartBranchItem: TMenuItem read FStartBranchItem;
    property StartRememberItem: TMenuItem read FStartRememberItem;
    property QueryItem: TMenuItem read FQueryItem;
    property CredentialsItem: TMenuItem read FCredentialsItem;
    property EndItem: TMenuItem read FEndItem;
    property QueryLabel: TLabel read FQueryLabel;
    property QueryMenu: TPopupMenu read FQueryMenu;
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  Atlas.Core.Tracker.Queries,
  System.DateUtils,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Vcs.Contract,
  Atlas.UI.Strings;

const
  Separator = ' · ';
  // Dieselben Töne wie „Testergebnisse“ und „Projekte“: lesbar im hellen und im dunklen Thema.
  GreenColor = TColor($0043A02E);
  YellowColor = TColor($001A8CC9);
  RedColor = TColor($002E22CF);
  GrayColor = TColor($00817666);

/// <summary>Teile mit „ · “ verbunden; leere fallen weg.</summary>
function JoinParts(const AParts: TArray<string>): string;
var
  Part: string;
begin
  Result := '';
  for Part in AParts do
  begin
    if Part = '' then
      Continue;
    if Result <> '' then
      Result := Result + Separator;
    Result := Result + Part;
  end;
end;

{ TAtlasIssuesHit }

class function TAtlasIssuesHit.Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasWelcomeIssuesFrame }

constructor TAtlasWelcomeIssuesFrame.Create(AOwner: TComponent);

  function AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    FMenu.Items.Add(Result);
  end;

var
  Line: TMenuItem;
begin
  inherited Create(AOwner);
  FMenuRow := -1;
  FView := Default(TAtlasIssuesView);
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FPreviewItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesPreview), PreviewClick);
  FBrowseItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesBrowse), BrowseClick);
  FBrowsePullItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesBrowsePullRequest), BrowsePullClick);
  FStartBranchItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStartBranch), StartBranchClick);
  FStartRememberItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStartRemember), StartRememberClick);
  Line := TMenuItem.Create(Self);
  Line.Caption := '-';
  FMenu.Items.Add(Line);
  FQueryItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryNow), QueryClick);
  FCredentialsItem := AddItem(TAtlasStrings.Text(TAtlasTextId.TrackerLoginCommand), CredentialsClick);
  FEndItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEnd), EndClick);
  FBox.PopupMenu := FMenu;
  // Klappliste der Abfragen rechts in der Titelzeile (#1262).
  FQueryMenu := TPopupMenu.Create(Self);
  FQueryLabel := TLabel.Create(Self);
  FQueryLabel.Parent := TitleBar;
  FQueryLabel.Align := alRight;
  FQueryLabel.AlignWithMargins := True;
  FQueryLabel.Margins.SetBounds(4, 4, 6, 0);
  FQueryLabel.Cursor := crHandPoint;
  FQueryLabel.ShowHint := True;
  FQueryLabel.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryHint);
  FQueryLabel.Font.Color := clHotLight;
  FQueryLabel.Visible := False;
  FQueryLabel.OnClick := QueryLabelClick;
end;

procedure TAtlasWelcomeIssuesFrame.SetSource(const AValue: IAtlasIssuesSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
    FSource.Shown;
end;

procedure TAtlasWelcomeIssuesFrame.UpdateContent;
var
  OldHeight: Integer;
begin
  OldHeight := BodyHeight;
  FView := Default(TAtlasIssuesView);
  if FSource <> nil then
    FView := FSource.View;
  FKeyRects := nil;
  FPullRects := nil;
  FStartRects := nil;
  FAssignRect := TRect.Empty;
  SetLength(FKeyRects, Length(FView.Items));
  SetLength(FPullRects, Length(FView.Items));
  SetLength(FStartRects, Length(FView.Items));
  FHintKey := '';
  UpdateQueryPicker;
  FBox.Invalidate;
  inherited;
  if OldHeight <> BodyHeight then
    HeightChanged;
end;

class function TAtlasWelcomeIssuesFrame.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasWelcomeIssuesFrame.TitleText(const AProjectName: string): string;
begin
  if AProjectName = '' then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesTitleProject, [AProjectName]);
end;

class function TAtlasWelcomeIssuesFrame.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesUnauthorized);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNotFound);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesInvalid);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiTimeout);
    TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiServerError);
    TAtlasCiFetchError.UnknownProvider, TAtlasCiFetchError.NotConfigured:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnknownProvider);
    TAtlasCiFetchError.None:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnreachable);
  end;
end;

class function TAtlasWelcomeIssuesFrame.StatusText(const AView: TAtlasIssuesView): string;
var
  Parts: TArray<string>;
begin
  Result := '';
  Parts := nil;
  case AView.Status of
    TAtlasIssuesStatus.NotConfigured:
      Exit;
    TAtlasIssuesStatus.Waiting:
      if AView.Querying then
        Parts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)]
      else
        Parts := [AView.Tracker, TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried)];
    TAtlasIssuesStatus.Failed:
      Parts := [AView.Tracker, ErrorText(AView.Error)];
    TAtlasIssuesStatus.Stale:
      Parts := [AView.Tracker, ErrorText(AView.Error), TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsStale,
        [FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AView.At))])];
  else
    if AView.Querying then
      Parts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)]
    else if Length(AView.Items) = 0 then
      Parts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEmpty)];
  end;
  if AView.Querying and (AView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale]) then
    Parts := Parts + [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
  Result := JoinParts(Parts);
end;

class function TAtlasWelcomeIssuesFrame.FooterText(const AView: TAtlasIssuesView): string;
var
  Item: TAtlasTrackerIssue;
  Listed: Boolean;
begin
  if AView.Notice <> '' then
    Exit(AView.Notice);
  if AView.Status = TAtlasIssuesStatus.NotConfigured then
  begin
    if AView.Project = '' then
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNoProject));
    // Weder .atlas noch persönliche Zuordnung: gleich zuordnen lassen (#1261).
    if FooterIsAssign(AView) then
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesAssign));
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNotConfigured));
  end;
  // Aktuelles Issue, das die Liste nicht zeigt (z. B. schon geschlossen oder anderer Bearbeiter).
  if AView.Active.Active then
  begin
    Listed := False;
    for Item in AView.Items do
      if SameText(Item.Key, AView.Active.Key) then
        Listed := True;
    if not Listed then
      Exit(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesActiveFooter,
        [Trim(AView.Active.Key + ' ' + AView.Active.Title)]));
  end;
  if Length(AView.Items) = 0 then
    Exit('');
  if (AView.Options.Start = TAtlasIssueStart.Remember) or
    ((AView.VcsKind <> TAtlasVcsKind.Git) and (AView.VcsKind <> TAtlasVcsKind.Svn)) then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooterRemember)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooter);
end;

class function TAtlasWelcomeIssuesFrame.FooterIsAssign(const AView: TAtlasIssuesView): Boolean;
begin
  Result := (AView.Notice = '') and (AView.Status = TAtlasIssuesStatus.NotConfigured) and (AView.Project <> '') and
    AView.CanAssign;
end;

class function TAtlasWelcomeIssuesFrame.SourceText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if (AView.Status = TAtlasIssuesStatus.NotConfigured) or (AView.QueryText = '') then
    Exit;
  Result := JoinParts([AView.Connection, AView.TrackerProject,
    TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSource, [AView.QueryText])]);
end;

class function TAtlasWelcomeIssuesFrame.QueryCaption(const AName: string; ACount: Integer): string;
begin
  if ACount < 0 then
    Result := AName
  else if ACount >= TAtlasWelcomeIssues.MaxItems then
    Result := Format('%s (%d+)', [AName, TAtlasWelcomeIssues.MaxItems])
  else
    Result := Format('%s (%d)', [AName, ACount]);
end;

class function TAtlasWelcomeIssuesFrame.ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean;
begin
  Result := AView.Picker and (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryIndex >= 0) and
    (AView.QueryIndex <= High(AView.Queries));
end;

procedure TAtlasWelcomeIssuesFrame.UpdateQueryPicker;
var
  mCount: Integer;
begin
  FQueryLabel.Visible := ShowsQueryPicker(FView);
  // Die Beschriftung misst ihren Text: erst mit Fenster (CreateWnd holt UpdateContent nach).
  if not FQueryLabel.Visible or not HasWindow then
    Exit;
  mCount := -1;
  if FView.QueryIndex <= High(FView.QueryCounts) then
    mCount := FView.QueryCounts[FView.QueryIndex];
  FQueryLabel.Caption := QueryCaption(FView.Queries[FView.QueryIndex].Name, mCount) + ' ' + #$25BE;
end;

procedure TAtlasWelcomeIssuesFrame.FillQueryMenu;
var
  mIndex, mCount: Integer;
  mItem: TMenuItem;
begin
  FQueryMenu.Items.Clear;
  for mIndex := 0 to High(FView.Queries) do
  begin
    mCount := -1;
    if mIndex <= High(FView.QueryCounts) then
      mCount := FView.QueryCounts[mIndex];
    mItem := TMenuItem.Create(FQueryMenu);
    mItem.Caption := QueryCaption(FView.Queries[mIndex].Name, mCount);
    mItem.RadioItem := True;
    mItem.Checked := mIndex = FView.QueryIndex;
    mItem.Tag := mIndex;
    mItem.OnClick := QueryItemClick;
    FQueryMenu.Items.Add(mItem);
  end;
  mItem := TMenuItem.Create(FQueryMenu);
  mItem.Caption := '-';
  FQueryMenu.Items.Add(mItem);
  mItem := TMenuItem.Create(FQueryMenu);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueriesEdit);
  mItem.OnClick := QueriesEditClick;
  FQueryMenu.Items.Add(mItem);
end;

procedure TAtlasWelcomeIssuesFrame.QueryLabelClick(Sender: TObject);
var
  mPoint: TPoint;
begin
  FillQueryMenu;
  mPoint := FQueryLabel.ClientToScreen(Point(0, FQueryLabel.Height));
  FQueryMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasWelcomeIssuesFrame.QueryItemClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  mName: string;
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (FSource = nil) or (mIndex < 0) or (mIndex > High(FView.Queries)) then
    Exit;
  mSource := FSource;
  mName := FView.Queries[mIndex].Name;
  Post(
    procedure
    begin
      mSource.SelectQuery(mName);
    end);
end;

procedure TAtlasWelcomeIssuesFrame.QueriesEditClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.EditQueries;
    end);
end;

class function TAtlasWelcomeIssuesFrame.PullRequestText(const APull: TAtlasTrackerPullRequest): string;
begin
  Result := '';
  if APull.Number <= 0 then
    Exit;
  Result := 'PR #' + IntToStr(APull.Number);
  if APull.Draft then
    Result := Result + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesDraft);
  case APull.Checks of
    TAtlasTrackerChecks.Success:
      Result := Result + Separator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksSuccess);
    TAtlasTrackerChecks.Failure:
      Result := Result + Separator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksFailure);
    TAtlasTrackerChecks.Pending:
      Result := Result + Separator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksPending);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasWelcomeIssuesFrame.ChecksColor(AChecks: TAtlasTrackerChecks): TColor;
begin
  case AChecks of
    TAtlasTrackerChecks.Success:
      Result := GreenColor;
    TAtlasTrackerChecks.Failure:
      Result := RedColor;
    TAtlasTrackerChecks.Pending:
      Result := YellowColor;
  else
    Result := GrayColor;
  end;
end;

class function TAtlasWelcomeIssuesFrame.TileText(const AView: TAtlasIssuesView): string;
var
  Head: string;
begin
  Head := AView.Active.Key;
  if Head = '' then
    Head := AView.Tracker;
  if Head = '' then
    Head := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle);
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusTile, [Head, AView.OpenCount]);
end;

class function TAtlasWelcomeIssuesFrame.StartHint(const AView: TAtlasIssuesView;
  const AIssue: TAtlasTrackerIssue): string;
var
  Plan: TAtlasIssueStartPlan;
begin
  Plan := TAtlasWelcomeIssues.PlanStart(AView.VcsKind, AView.Options, AIssue);
  if (Plan.Mode = TAtlasIssueStart.Branch) and Plan.Valid then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintStart, [Plan.Branch])
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintRemember, [AIssue.Key]);
end;

function TAtlasWelcomeIssuesFrame.CanStart: Boolean;
begin
  Result := (FSource <> nil) and not FView.Starting;
end;

function TAtlasWelcomeIssuesFrame.ListTop: Integer;
begin
  Result := ScaleValue(Indent) div 2;
  if StatusText(FView) <> '' then
    Inc(Result, ScaleValue(StatusHeight));
end;

function TAtlasWelcomeIssuesFrame.RowHeight(AIndex: Integer): Integer;
begin
  Result := 2 * ScaleValue(RowPadding) + ScaleValue(LineHeight);
  if (AIndex >= 0) and (AIndex <= High(FView.Items)) and
    ((Length(TAtlasWelcomeIssues.Fields(FView.Items[AIndex])) > 0) or (FView.Items[AIndex].PullRequest.Number > 0) or
    SameText(FView.Items[AIndex].Key, FView.Active.Key)) then
    Inc(Result, ScaleValue(ChipLineHeight));
end;

function TAtlasWelcomeIssuesFrame.RowTop(AIndex: Integer): Integer;
var
  Index: Integer;
begin
  Result := ListTop;
  for Index := 0 to AIndex - 1 do
    Inc(Result, RowHeight(Index));
end;

function TAtlasWelcomeIssuesFrame.FooterTop: Integer;
begin
  Result := RowTop(Length(FView.Items));
end;

function TAtlasWelcomeIssuesFrame.SourceTop: Integer;
begin
  Result := FooterTop + ScaleValue(FooterHeight);
end;

function TAtlasWelcomeIssuesFrame.BodyHeight: Integer;
begin
  Result := SourceTop + ScaleValue(Indent) div 2;
  if SourceText(FView) <> '' then
    Inc(Result, ScaleValue(FooterHeight));
end;

function TAtlasWelcomeIssuesFrame.ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
begin
  Result := ACanvas.TextWidth(AText) + 2 * ScaleValue(ChipPadding);
end;

procedure TAtlasWelcomeIssuesFrame.PaintChip(ACanvas: TCanvas; var ALeft: Integer; ATop, ALimit: Integer;
  const AText: string; AColor: TColor; AFilled: Boolean; out ARect: TRect);
var
  mWidth, Radius: Integer;
begin
  ARect := TRect.Empty;
  mWidth := ChipWidth(ACanvas, AText);
  if ALeft + mWidth > ALimit then
    Exit;
  ARect := Rect(ALeft, ATop, ALeft + mWidth, ATop + ScaleValue(ChipHeight));
  Radius := 2 * ScaleValue(ChipRadius);
  ACanvas.Pen.Color := AColor;
  if AFilled then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
  end
  else
    ACanvas.Brush.Style := bsClear;
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Radius, Radius);
  ACanvas.Brush.Style := bsClear;
  if AFilled then
    ACanvas.Font.Color := clWhite
  else
    ACanvas.Font.Color := AColor;
  ACanvas.TextOut(ARect.Left + ScaleValue(ChipPadding), ARect.Top + (ARect.Height - ACanvas.TextHeight(AText)) div 2,
    AText);
  ALeft := ARect.Right + ScaleValue(ChipGap);
end;

procedure TAtlasWelcomeIssuesFrame.PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
var
  mText: string;
  Area: TRect;
  mTop, mWidth: Integer;
  Accent: TColor;
begin
  ACanvas.Font.Assign(Font);
  mText := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStart);
  mWidth := ACanvas.TextWidth(mText) + 2 * ScaleValue(ButtonPadding);
  // Über beide Zeilen der Zeile mittig (Mockup).
  mTop := RowTop(AIndex) + (RowHeight(AIndex) - ScaleValue(ButtonHeight)) div 2;
  Area := Rect(ARight - mWidth, mTop, ARight, mTop + ScaleValue(ButtonHeight));
  FStartRects[AIndex] := Area;
  Accent := StyleServices(Self).GetSystemColor(clBtnShadow);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := Accent;
  ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, ScaleValue(6), ScaleValue(6));
  if CanStart then
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText)
  else
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  ACanvas.TextOut(Area.Left + (Area.Width - ACanvas.TextWidth(mText)) div 2,
    Area.Top + (Area.Height - ACanvas.TextHeight(mText)) div 2, mText);
end;

procedure TAtlasWelcomeIssuesFrame.PaintRow(ACanvas: TCanvas; AIndex: Integer);
var
  Item: TAtlasTrackerIssue;
  mTop, mLeft, Limit, Right: Integer;
  TextColor, MutedColor, LineColor: TColor;
  Field, mText: string;
  Chip: TRect;
begin
  Item := FView.Items[AIndex];
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clBtnFace);
  mTop := RowTop(AIndex);
  mLeft := ScaleValue(Indent);
  Right := FBox.Width - ScaleValue(Indent);
  // Trennlinie zwischen den Zeilen (Mockup).
  if AIndex > 0 then
  begin
    ACanvas.Pen.Color := LineColor;
    ACanvas.MoveTo(mLeft, mTop);
    ACanvas.LineTo(Right, mTop);
  end;
  PaintStart(ACanvas, AIndex, Right);
  Limit := FStartRects[AIndex].Left - ScaleValue(8);
  Inc(mTop, ScaleValue(RowPadding));
  // Kennung grau in Festbreitenschrift.
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Name := MonoFont;
  ACanvas.Font.Color := MutedColor;
  FKeyRects[AIndex] := Rect(mLeft, mTop, Min(mLeft + ACanvas.TextWidth(Item.Key), Limit), mTop + ScaleValue(LineHeight));
  ACanvas.TextRect(FKeyRects[AIndex], mLeft, mTop + ScaleValue(1), Item.Key);
  mLeft := mLeft + Max(ScaleValue(KeyWidth), ACanvas.TextWidth(Item.Key) + ScaleValue(8));
  // Titel, abgeschnitten.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := TextColor;
  if SameText(Item.Key, FView.Active.Key) then
    ACanvas.Font.Style := [fsBold];
  if mLeft < Limit then
    ACanvas.TextRect(Rect(mLeft, mTop, Limit, mTop + ScaleValue(LineHeight)), mLeft, mTop + ScaleValue(1),
      Item.Title);
  ACanvas.Font.Style := [];
  // Zweite Zeile: Felder als Chips mit Rahmen, dann der Pull Request mit CI-Ampel.
  mTop := mTop + ScaleValue(LineHeight) + (ScaleValue(ChipLineHeight) - ScaleValue(ChipHeight)) div 2;
  ACanvas.Font.Size := Font.Size - 1;
  FPullRects[AIndex] := TRect.Empty;
  if SameText(Item.Key, FView.Active.Key) then
    PaintChip(ACanvas, mLeft, mTop, Limit, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesActive),
      StyleServices(Self).GetSystemColor(clHighlight), True, Chip);
  for Field in TAtlasWelcomeIssues.Fields(Item) do
    PaintChip(ACanvas, mLeft, mTop, Limit, Field, MutedColor, False, Chip);
  mText := PullRequestText(Item.PullRequest);
  if mText <> '' then
  begin
    PaintChip(ACanvas, mLeft, mTop, Limit, mText, ChecksColor(Item.PullRequest.Checks), False, Chip);
    FPullRects[AIndex] := Chip;
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasWelcomeIssuesFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Index, mTop: Integer;
  mText: string;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  mText := StatusText(FView);
  if mText <> '' then
  begin
    Canvas.Font.Size := Font.Size - 1;
    if FView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
      Canvas.Font.Color := YellowColor
    else
      Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    Canvas.TextRect(Rect(ScaleValue(Indent), ScaleValue(Indent) div 2, FBox.Width - ScaleValue(Indent),
      ScaleValue(Indent) div 2 + ScaleValue(StatusHeight)), ScaleValue(Indent), ScaleValue(Indent) div 2 +
      ScaleValue(2), mText);
    Canvas.Font.Assign(Font);
  end;
  if Length(FStartRects) <> Length(FView.Items) then
    Exit;
  for Index := 0 to High(FView.Items) do
    PaintRow(Canvas, Index);
  // Woher die Liste kommt (#1262): Verbindung, Tracker-Projekt, gesendete Abfrage.
  mText := SourceText(FView);
  if mText <> '' then
  begin
    mTop := SourceTop + ScaleValue(4);
    Canvas.Font.Size := Font.Size - 1;
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    Canvas.TextRect(Rect(ScaleValue(Indent), mTop, FBox.Width - ScaleValue(Indent), mTop + ScaleValue(FooterHeight)),
      ScaleValue(Indent), mTop, mText);
    Canvas.Font.Assign(Font);
  end;
  mText := FooterText(FView);
  if mText = '' then
    Exit;
  mTop := FooterTop + ScaleValue(4);
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := Font.Size - 1;
  if FView.NoticeFailed then
    Canvas.Font.Color := RedColor
  else if FooterIsAssign(FView) then
  begin
    // Link „zuordnen …“: Akzentfarbe, Klickfläche nur über dem Text.
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clHotLight);
    FAssignRect := Rect(ScaleValue(Indent), mTop, Min(ScaleValue(Indent) + Canvas.TextWidth(mText),
      FBox.Width - ScaleValue(Indent)), mTop + Canvas.TextHeight(mText));
  end
  else
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  Canvas.TextRect(Rect(ScaleValue(Indent), mTop, FBox.Width - ScaleValue(Indent), mTop + ScaleValue(FooterHeight)),
    ScaleValue(Indent), mTop, mText);
  Canvas.Font.Assign(Font);
end;

function TAtlasWelcomeIssuesFrame.HitTest(X, Y: Integer): TAtlasIssuesHit;
var
  Index: Integer;
  Point_: TPoint;
begin
  Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.None, -1);
  Point_ := Point(X, Y);
  if not FAssignRect.IsEmpty and FAssignRect.Contains(Point_) then
    Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Assign, -1));
  for Index := 0 to High(FView.Items) do
  begin
    if (Y < RowTop(Index)) or (Y >= RowTop(Index) + RowHeight(Index)) then
      Continue;
    if (Index <= High(FStartRects)) and not FStartRects[Index].IsEmpty and FStartRects[Index].Contains(Point_) then
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, Index));
    if (Index <= High(FKeyRects)) and not FKeyRects[Index].IsEmpty and FKeyRects[Index].Contains(Point_) then
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, Index));
    if (Index <= High(FPullRects)) and not FPullRects[Index].IsEmpty and FPullRects[Index].Contains(Point_) then
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, Index));
    Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, Index));
  end;
end;

procedure TAtlasWelcomeIssuesFrame.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Maus- bzw. Menüereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, AAction);
end;

procedure TAtlasWelcomeIssuesFrame.ClickAt(const AHit: TAtlasIssuesHit);
begin
  ClickAt(AHit, False);
end;

procedure TAtlasWelcomeIssuesFrame.ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean);
var
  mSource: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
  Mode: TAtlasIssueStart;
begin
  if (FSource <> nil) and (AHit.Kind = TAtlasIssuesHitKind.Assign) then
  begin
    mSource := FSource;
    Post(
      procedure
      begin
        mSource.AssignProject;
      end);
    Exit;
  end;
  if (FSource = nil) or (AHit.Index < 0) or (AHit.Index > High(FView.Items)) then
    Exit;
  mSource := FSource;
  Item := FView.Items[AHit.Index];
  if (AHit.Kind in [TAtlasIssuesHitKind.Row, TAtlasIssuesHitKind.Key]) and FView.Options.Preview and
    not ABrowse then
  begin
    Post(
      procedure
      begin
        mSource.Preview(Item);
      end);
    Exit;
  end;
  case AHit.Kind of
    // Leerraum und Zeilentext lösen ohne Vorschau nichts aus; sie zeigen nur den Hinweis (BoxMouseMove).
    TAtlasIssuesHitKind.None, TAtlasIssuesHitKind.Assign: ;
    TAtlasIssuesHitKind.Row:
      if ABrowse and FView.Options.Preview then
        Post(
          procedure
          begin
            mSource.Browse(Item);
          end);
    TAtlasIssuesHitKind.Key:
      Post(
        procedure
        begin
          mSource.Browse(Item);
        end);
    TAtlasIssuesHitKind.PullRequest:
      Post(
        procedure
        begin
          mSource.BrowsePullRequest(Item);
        end);
    TAtlasIssuesHitKind.Start:
      if CanStart then
      begin
        Mode := FView.Options.Start;
        Post(
          procedure
          begin
            mSource.Start(Item, Mode);
          end);
      end;
  end;
end;

procedure TAtlasWelcomeIssuesFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasIssuesHit;
  Key: string;
begin
  Hit := HitTest(X, Y);
  if (Hit.Kind in [TAtlasIssuesHitKind.Key, TAtlasIssuesHitKind.PullRequest, TAtlasIssuesHitKind.Start,
    TAtlasIssuesHitKind.Assign]) or ((Hit.Kind = TAtlasIssuesHitKind.Row) and FView.Options.Preview) then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  Key := IntToStr(Ord(Hit.Kind)) + ':' + IntToStr(Hit.Index);
  if Key = FHintKey then
    Exit;
  FHintKey := Key;
  case Hit.Kind of
    TAtlasIssuesHitKind.Key:
      if FView.Options.Preview then
        FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKeyPreview)
      else
        FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKey);
    TAtlasIssuesHitKind.PullRequest:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintPullRequest);
    TAtlasIssuesHitKind.Start:
      FBox.Hint := StartHint(FView, FView.Items[Hit.Index]);
    TAtlasIssuesHitKind.Row:
      FBox.Hint := FView.Items[Hit.Index].Key + ' ' + FView.Items[Hit.Index].Title;
    TAtlasIssuesHitKind.Assign:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintAssign);
  else
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeIssuesFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y), ssCtrl in Shift);
end;

procedure TAtlasWelcomeIssuesFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
  Hit: TAtlasIssuesHit;
  Item: TAtlasTrackerIssue;
  HasItem, Branching: Boolean;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  Hit := HitTest(Position.X, Position.Y);
  FMenuRow := Hit.Index;
  HasItem := MenuIssue(Item);
  Branching := (FView.VcsKind = TAtlasVcsKind.Git) or (FView.VcsKind = TAtlasVcsKind.Svn);
  FPreviewItem.Visible := HasItem and FView.Options.Preview;
  FPreviewItem.Default := FPreviewItem.Visible;
  FBrowseItem.Visible := HasItem;
  FBrowsePullItem.Visible := HasItem and (Item.PullRequest.Number > 0);
  FStartBranchItem.Visible := HasItem and Branching;
  FStartBranchItem.Enabled := CanStart;
  FStartRememberItem.Visible := HasItem;
  FStartRememberItem.Enabled := CanStart;
  FQueryItem.Visible := FView.Status <> TAtlasIssuesStatus.NotConfigured;
  FQueryItem.Enabled := not FView.Querying;
  FCredentialsItem.Visible := (FView.Status <> TAtlasIssuesStatus.NotConfigured) and (FSource <> nil) and
    FSource.CanEnterCredentials;
  FEndItem.Visible := FView.Active.Active;
end;

function TAtlasWelcomeIssuesFrame.MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  Result := (FSource <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FView.Items));
  if Result then
    AIssue := FView.Items[FMenuRow];
end;

procedure TAtlasWelcomeIssuesFrame.PreviewClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, FMenuRow), False);
end;

procedure TAtlasWelcomeIssuesFrame.BrowseClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, FMenuRow), True);
end;

procedure TAtlasWelcomeIssuesFrame.BrowsePullClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, FMenuRow));
end;

procedure TAtlasWelcomeIssuesFrame.StartBranchClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(Item) then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Start(Item, TAtlasIssueStart.Branch);
    end);
end;

procedure TAtlasWelcomeIssuesFrame.StartRememberClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(Item) then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Start(Item, TAtlasIssueStart.Remember);
    end);
end;

procedure TAtlasWelcomeIssuesFrame.QueryClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.QueryNow;
    end);
end;

procedure TAtlasWelcomeIssuesFrame.CredentialsClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Credentials;
    end);
end;

procedure TAtlasWelcomeIssuesFrame.EndClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.EndActive;
    end);
end;

end.
