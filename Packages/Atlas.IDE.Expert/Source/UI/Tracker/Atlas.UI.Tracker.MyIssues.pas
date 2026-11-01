unit Atlas.UI.Tracker.MyIssues;

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
// Abfragen (#1262): rechts in der ersten Zeile die Klappliste „Mir zugewiesen
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
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Style.Canvas,
  Atlas.UI.Tracker.TileView;

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
    /// <summary>Filter der Sprint-Kachel aufheben (#1277): wieder alle meine Issues.</summary>
    procedure ClearFilter;
  end;

{$SCOPEDENUMS ON}
  TAtlasIssuesHitKind = (None, Row, Key, PullRequest, Start, Assign, Filter);
{$SCOPEDENUMS OFF}

  TAtlasIssuesHit = record
    Kind: TAtlasIssuesHitKind;
    /// <summary>Zeile; -1 sonst.</summary>
    Index: Integer;
    class function Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit; static;
  end;

  TAtlasTrackerIssuesView = class(TAtlasTrackerTileView)
  public const
    cIndent = 8;
    cKeyWidth = 76;
    cLineHeight = 20;
    cChipLineHeight = 22;
    cRowPadding = 5;
    cStatusHeight = 22;
    cFooterHeight = 24;
    cButtonHeight = 26;
    cButtonPadding = 12;
    cChipHeight = 18;
    cChipPadding = 6;
    cChipGap = 4;
    cChipRadius = 8;
    /// <summary>Durchmesser des Punkts vor der Kennung eines Issues mit neuen Änderungen (#1271).</summary>
    cUnseenDot = 6;
    /// <summary>Vor dem Titel des Bereichs, solange ein Issue einen Punkt trägt.</summary>
    cUnseenMark = '● ';
    cMonoFont = 'Consolas';
  private
    FSource: IAtlasIssuesSource;
    FBox: TAtlasStyledCanvas;
    FView: TAtlasIssuesView;
    FKeyRects: TArray<TRect>;
    FPullRects: TArray<TRect>;
    FStartRects: TArray<TRect>;
    /// <summary>Link „zuordnen …“ in der Fußzeile; leer ohne.</summary>
    FAssignRect: TRect;
    /// <summary>Zeile „Gefiltert: … · alle zeigen“ (#1277); leer ohne Filter.</summary>
    FFilterRect: TRect;
    FMenu: TPopupMenu;
    FPreviewItem: TMenuItem;
    FBrowseItem: TMenuItem;
    FBrowsePullItem: TMenuItem;
    FStartBranchItem: TMenuItem;
    FStartRememberItem: TMenuItem;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FEndItem: TMenuItem;
    /// <summary>Klappliste der Abfragen (#1262) rechts in der ersten Zeile; die Titelzeile gehört der Seite.</summary>
    FQueryBar: TPanel;
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
    function RowTop(AIndex: Integer): Integer;
    function RowHeight(AIndex: Integer): Integer;
    function FooterTop: Integer;
    function SourceTop: Integer;
    function ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
    procedure PaintChip(ACanvas: TCanvas; var ALeft: Integer; ATop, ALimit: Integer; const AText: string;
      AColor: TColor; AFilled: Boolean; out ARect: TRect);
    procedure PaintRow(ACanvas: TCanvas; AIndex: Integer);
    procedure PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    function BodyHeight: Integer; override;
    procedure UpdateContent; override;
    function HitTest(AX, AY: Integer): TAtlasIssuesHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): Kennung und Pull Request öffnen den Browser, „Beginnen“
    /// beginnt mit der Einstellung issues.start.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit); overload;
    /// <summary>ABrowse: Strg+Klick, öffnet den Browser auch mit issues.preview.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean); overload;
    /// <summary>„Beginnen“ nutzbar: Quelle da, keine laufende Aktion.</summary>
    function CanStart: Boolean;
    /// <summary>Zeile über der Liste: Stand, Fehler, „Stand vom …“; '' bei frischem Stand.</summary>
    class function StatusText(const AView: TAtlasIssuesView): string; static;
    /// <summary>„Gefiltert: „Sprint 12“, meine offen · alle zeigen“; '' ohne Filter (#1277).</summary>
    class function FilterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Oberkante der Filterzeile bzw. der Liste (unter Stand- und Filterzeile).</summary>
    function FilterTop: Integer;
    function ListTop: Integer;
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
    class function TitleText(const AProjectName: string): string; overload; static;
    /// <summary>Wie oben, mit Punkt davor, wenn AUnseen (#1271: neue Änderungen an einem Issue).</summary>
    class function TitleText(const AProjectName: string; AUnseen: Boolean): string; overload; static;
    class function NowUtc: TDateTime; static;
    property Source: IAtlasIssuesSource read FSource write SetSource;
    property View: TAtlasIssuesView read FView;
    property PaintBox: TAtlasStyledCanvas read FBox;
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
  cSeparator = ' · ';
  // Dieselben Töne wie „Testergebnisse“ und „Projekte“: lesbar im hellen und im dunklen Thema.
  cGreenColor = TColor($0043A02E);
  cYellowColor = TColor($001A8CC9);
  cRedColor = TColor($002E22CF);
  cGrayColor = TColor($00817666);

/// <summary>Teile mit „ · “ verbunden; leere fallen weg.</summary>
function JoinParts(const AParts: TArray<string>): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    if mPart = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + cSeparator;
    end;
    Result := Result + mPart;
  end;
end;

{ TAtlasIssuesHit }

class function TAtlasIssuesHit.Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasTrackerIssuesView }

constructor TAtlasTrackerIssuesView.Create(AOwner: TComponent);

  function AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    FMenu.Items.Add(Result);
  end;

var
  mLine: TMenuItem;
begin
  inherited Create(AOwner);
  FMenuRow := -1;
  FView := Default(TAtlasIssuesView);
  // Klappliste der Abfragen (#1262) über der Liste, nur bei Bedarf sichtbar.
  FQueryBar := TPanel.Create(Self);
  FQueryBar.Parent := Self;
  FQueryBar.Align := alTop;
  FQueryBar.BevelOuter := bvNone;
  FQueryBar.ShowCaption := False;
  FQueryBar.ParentBackground := True;
  FQueryBar.Height := ScaleValue(cStatusHeight);
  FQueryBar.Visible := False;
  FBox := TAtlasStyledCanvas.Create(Self);
  FBox.Parent := Self;
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
  mLine := TMenuItem.Create(Self);
  mLine.Caption := '-';
  FMenu.Items.Add(mLine);
  FQueryItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryNow), QueryClick);
  FCredentialsItem := AddItem(TAtlasStrings.Text(TAtlasTextId.TrackerLoginCommand), CredentialsClick);
  FEndItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEnd), EndClick);
  FBox.PopupMenu := FMenu;
  FQueryMenu := TPopupMenu.Create(Self);
  FQueryLabel := TLabel.Create(Self);
  FQueryLabel.Parent := FQueryBar;
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

procedure TAtlasTrackerIssuesView.SetSource(const AValue: IAtlasIssuesSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasTrackerIssuesView.UpdateContent;
var
  mOldHeight: Integer;
begin
  mOldHeight := BodyHeight;
  FView := Default(TAtlasIssuesView);
  if FSource <> nil then
  begin
    FView := FSource.View;
  end;
  FKeyRects := nil;
  FPullRects := nil;
  FStartRects := nil;
  FAssignRect := TRect.Empty;
  FFilterRect := TRect.Empty;
  SetLength(FKeyRects, Length(FView.Items));
  SetLength(FPullRects, Length(FView.Items));
  SetLength(FStartRects, Length(FView.Items));
  FHintKey := '';
  UpdateQueryPicker;
  FBox.Invalidate;
  inherited;
  if mOldHeight <> BodyHeight then
  begin
    HeightChanged;
  end;
end;

class function TAtlasTrackerIssuesView.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasTrackerIssuesView.TitleText(const AProjectName: string): string;
begin
  if AProjectName = '' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesTitleProject, [AProjectName]);
  end;
end;

class function TAtlasTrackerIssuesView.TitleText(const AProjectName: string; AUnseen: Boolean): string;
begin
  Result := TitleText(AProjectName);
  if AUnseen then
  begin
    Result := cUnseenMark + Result;
  end;
end;

class function TAtlasTrackerIssuesView.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesUnauthorized);
    TAtlasCiFetchError.NoCredentials:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNoToken);
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

class function TAtlasTrackerIssuesView.StatusText(const AView: TAtlasIssuesView): string;
var
  mParts: TArray<string>;
begin
  Result := '';
  mParts := nil;
  case AView.Status of
    TAtlasIssuesStatus.NotConfigured:
      Exit;
    TAtlasIssuesStatus.Waiting:
      if AView.Querying then
      begin
        mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
      end
      else
      begin
        mParts := [AView.Tracker, TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried)];
      end;
    TAtlasIssuesStatus.Failed:
      mParts := [AView.Tracker, ErrorText(AView.Error)];
    TAtlasIssuesStatus.Stale:
      mParts := [AView.Tracker, ErrorText(AView.Error), TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsStale,
        [FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AView.At))])];
  else
    if AView.Querying then
    begin
      mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
    end
    else if Length(AView.Items) = 0 then
    begin
      mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEmpty)];
    end;
  end;
  if AView.Querying and (AView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale]) then
  begin
    mParts := mParts + [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
  end;
  Result := JoinParts(mParts);
end;

class function TAtlasTrackerIssuesView.FooterText(const AView: TAtlasIssuesView): string;
var
  mItem: TAtlasTrackerIssue;
  mListed: Boolean;
begin
  if AView.Notice <> '' then
  begin
    Exit(AView.Notice);
  end;
  if AView.Status = TAtlasIssuesStatus.NotConfigured then
  begin
    if AView.Project = '' then
    begin
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNoProject));
    end;
    // Weder .atlas noch persönliche Zuordnung: gleich zuordnen lassen (#1261).
    if FooterIsAssign(AView) then
    begin
      Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesAssign));
    end;
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNotConfigured));
  end;
  // Aktuelles Issue, das die Liste nicht zeigt (z. B. schon geschlossen oder anderer Bearbeiter).
  if AView.Active.Active then
  begin
    mListed := False;
    for mItem in AView.Items do
    begin
      if SameText(mItem.Key, AView.Active.Key) then
      begin
        mListed := True;
      end;
    end;
    if not mListed then
    begin
      Exit(TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesActiveFooter,
        [Trim(AView.Active.Key + ' ' + AView.Active.Title)]));
    end;
  end;
  if Length(AView.Items) = 0 then
  begin
    Exit('');
  end;
  if (AView.Options.Start = TAtlasIssueStart.Remember) or
    ((AView.VcsKind <> TAtlasVcsKind.Git) and (AView.VcsKind <> TAtlasVcsKind.Svn)) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooterRemember);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooter);
  end;
end;

class function TAtlasTrackerIssuesView.FooterIsAssign(const AView: TAtlasIssuesView): Boolean;
begin
  Result := (AView.Notice = '') and (AView.Status = TAtlasIssuesStatus.NotConfigured) and (AView.Project <> '') and
    AView.CanAssign;
end;

class function TAtlasTrackerIssuesView.SourceText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if (AView.Status = TAtlasIssuesStatus.NotConfigured) or (AView.QueryText = '') then
  begin
    Exit;
  end;
  Result := JoinParts([AView.Connection, AView.TrackerProject,
    TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSource, [AView.QueryText])]);
end;

class function TAtlasTrackerIssuesView.QueryCaption(const AName: string; ACount: Integer): string;
begin
  if ACount < 0 then
  begin
    Result := AName;
  end
  else if ACount >= TAtlasMyIssues.cMaxItems then
  begin
    Result := Format('%s (%d+)', [AName, TAtlasMyIssues.cMaxItems]);
  end
  else
  begin
    Result := Format('%s (%d)', [AName, ACount]);
  end;
end;

class function TAtlasTrackerIssuesView.ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean;
begin
  Result := AView.Picker and (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryIndex >= 0) and
    (AView.QueryIndex <= High(AView.Queries));
end;

procedure TAtlasTrackerIssuesView.UpdateQueryPicker;
var
  mCount: Integer;
begin
  FQueryLabel.Visible := ShowsQueryPicker(FView);
  FQueryBar.Visible := FQueryLabel.Visible;
  // Die Beschriftung misst ihren Text: erst mit Fenster (CreateWnd holt UpdateContent nach).
  if not FQueryLabel.Visible or not HasWindow then
  begin
    Exit;
  end;
  mCount := -1;
  if FView.QueryIndex <= High(FView.QueryCounts) then
  begin
    mCount := FView.QueryCounts[FView.QueryIndex];
  end;
  FQueryLabel.Caption := QueryCaption(FView.Queries[FView.QueryIndex].Name, mCount) + ' ' + #$25BE;
end;

procedure TAtlasTrackerIssuesView.FillQueryMenu;
var
  mIndex, mCount: Integer;
  mItem: TMenuItem;
begin
  FQueryMenu.Items.Clear;
  for mIndex := 0 to High(FView.Queries) do
  begin
    mCount := -1;
    if mIndex <= High(FView.QueryCounts) then
    begin
      mCount := FView.QueryCounts[mIndex];
    end;
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

procedure TAtlasTrackerIssuesView.QueryLabelClick(Sender: TObject);
var
  mPoint: TPoint;
begin
  FillQueryMenu;
  mPoint := FQueryLabel.ClientToScreen(Point(0, FQueryLabel.Height));
  FQueryMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasTrackerIssuesView.QueryItemClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  mName: string;
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (FSource = nil) or (mIndex < 0) or (mIndex > High(FView.Queries)) then
  begin
    Exit;
  end;
  mSource := FSource;
  mName := FView.Queries[mIndex].Name;
  Post(
    procedure
    begin
      mSource.SelectQuery(mName);
    end);
end;

procedure TAtlasTrackerIssuesView.QueriesEditClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.EditQueries;
    end);
end;

class function TAtlasTrackerIssuesView.PullRequestText(const APull: TAtlasTrackerPullRequest): string;
begin
  Result := '';
  if APull.Number <= 0 then
  begin
    Exit;
  end;
  Result := 'PR #' + IntToStr(APull.Number);
  if APull.Draft then
  begin
    Result := Result + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesDraft);
  end;
  case APull.Checks of
    TAtlasTrackerChecks.Success:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksSuccess);
    TAtlasTrackerChecks.Failure:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksFailure);
    TAtlasTrackerChecks.Pending:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksPending);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasTrackerIssuesView.ChecksColor(AChecks: TAtlasTrackerChecks): TColor;
begin
  case AChecks of
    TAtlasTrackerChecks.Success:
      Result := cGreenColor;
    TAtlasTrackerChecks.Failure:
      Result := cRedColor;
    TAtlasTrackerChecks.Pending:
      Result := cYellowColor;
  else
    Result := cGrayColor;
  end;
end;

class function TAtlasTrackerIssuesView.TileText(const AView: TAtlasIssuesView): string;
var
  mHead: string;
begin
  mHead := AView.Active.Key;
  if mHead = '' then
  begin
    mHead := AView.Tracker;
  end;
  if mHead = '' then
  begin
    mHead := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusTile, [mHead, AView.OpenCount]);
end;

class function TAtlasTrackerIssuesView.StartHint(const AView: TAtlasIssuesView;
  const AIssue: TAtlasTrackerIssue): string;
var
  mPlan: TAtlasIssueStartPlan;
begin
  mPlan := TAtlasMyIssues.PlanStart(AView.VcsKind, AView.Options, AIssue);
  if (mPlan.Mode = TAtlasIssueStart.Branch) and mPlan.Valid then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintStart, [mPlan.Branch]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintRemember, [AIssue.Key]);
  end;
end;

function TAtlasTrackerIssuesView.CanStart: Boolean;
begin
  Result := (FSource <> nil) and not FView.Starting;
end;

function TAtlasTrackerIssuesView.FilterTop: Integer;
begin
  Result := ScaleValue(cIndent) div 2;
  if StatusText(FView) <> '' then
  begin
    Inc(Result, ScaleValue(cStatusHeight));
  end;
end;

function TAtlasTrackerIssuesView.ListTop: Integer;
begin
  Result := FilterTop;
  if FilterText(FView) <> '' then
  begin
    Inc(Result, ScaleValue(cStatusHeight));
  end;
end;

class function TAtlasTrackerIssuesView.FilterText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if AView.Filter <> '' then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilter, [AView.Filter]);
  end;
end;

function TAtlasTrackerIssuesView.RowHeight(AIndex: Integer): Integer;
begin
  Result := 2 * ScaleValue(cRowPadding) + ScaleValue(cLineHeight);
  if (AIndex >= 0) and (AIndex <= High(FView.Items)) and
    ((Length(TAtlasMyIssues.Fields(FView.Items[AIndex])) > 0) or (FView.Items[AIndex].PullRequest.Number > 0) or
    SameText(FView.Items[AIndex].Key, FView.Active.Key)) then
  begin
    Inc(Result, ScaleValue(cChipLineHeight));
  end;
end;

function TAtlasTrackerIssuesView.RowTop(AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := ListTop;
  for mIndex := 0 to AIndex - 1 do
  begin
    Inc(Result, RowHeight(mIndex));
  end;
end;

function TAtlasTrackerIssuesView.FooterTop: Integer;
begin
  Result := RowTop(Length(FView.Items));
end;

function TAtlasTrackerIssuesView.SourceTop: Integer;
begin
  Result := FooterTop + ScaleValue(cFooterHeight);
end;

function TAtlasTrackerIssuesView.BodyHeight: Integer;
begin
  Result := SourceTop + ScaleValue(cIndent) div 2;
  if SourceText(FView) <> '' then
  begin
    Inc(Result, ScaleValue(cFooterHeight));
  end;
  if FQueryBar.Visible then
  begin
    Inc(Result, FQueryBar.Height);
  end;
end;

function TAtlasTrackerIssuesView.ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
begin
  Result := ACanvas.TextWidth(AText) + 2 * ScaleValue(cChipPadding);
end;

procedure TAtlasTrackerIssuesView.PaintChip(ACanvas: TCanvas; var ALeft: Integer; ATop, ALimit: Integer;
  const AText: string; AColor: TColor; AFilled: Boolean; out ARect: TRect);
var
  mWidth, mRadius: Integer;
begin
  ARect := TRect.Empty;
  mWidth := ChipWidth(ACanvas, AText);
  if ALeft + mWidth > ALimit then
  begin
    Exit;
  end;
  ARect := Rect(ALeft, ATop, ALeft + mWidth, ATop + ScaleValue(cChipHeight));
  mRadius := 2 * ScaleValue(cChipRadius);
  ACanvas.Pen.Color := AColor;
  if AFilled then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColor;
  end
  else
  begin
    ACanvas.Brush.Style := bsClear;
  end;
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, mRadius, mRadius);
  ACanvas.Brush.Style := bsClear;
  if AFilled then
  begin
    ACanvas.Font.Color := clWhite;
  end
  else
  begin
    ACanvas.Font.Color := AColor;
  end;
  ACanvas.TextOut(ARect.Left + ScaleValue(cChipPadding), ARect.Top + (ARect.Height - ACanvas.TextHeight(AText)) div 2,
    AText);
  ALeft := ARect.Right + ScaleValue(cChipGap);
end;

procedure TAtlasTrackerIssuesView.PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
var
  mText: string;
  mArea: TRect;
  mTop, mWidth: Integer;
  mAccent: TColor;
begin
  ACanvas.Font.Assign(Font);
  mText := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStart);
  mWidth := ACanvas.TextWidth(mText) + 2 * ScaleValue(cButtonPadding);
  // Über beide Zeilen der Zeile mittig (Mockup).
  mTop := RowTop(AIndex) + (RowHeight(AIndex) - ScaleValue(cButtonHeight)) div 2;
  mArea := Rect(ARight - mWidth, mTop, ARight, mTop + ScaleValue(cButtonHeight));
  FStartRects[AIndex] := mArea;
  mAccent := StyleServices(Self).GetSystemColor(clBtnShadow);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := mAccent;
  ACanvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, ScaleValue(6), ScaleValue(6));
  if CanStart then
  begin
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText);
  end
  else
  begin
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  end;
  ACanvas.TextOut(mArea.Left + (mArea.Width - ACanvas.TextWidth(mText)) div 2,
    mArea.Top + (mArea.Height - ACanvas.TextHeight(mText)) div 2, mText);
end;

procedure TAtlasTrackerIssuesView.PaintRow(ACanvas: TCanvas; AIndex: Integer);
var
  mItem: TAtlasTrackerIssue;
  mTop, mLeft, mLimit, mRight: Integer;
  mTextColor, mMutedColor, mLineColor: TColor;
  mField, mText: string;
  mChip: TRect;
begin
  mItem := FView.Items[AIndex];
  mTextColor := StyleServices(Self).GetSystemColor(clWindowText);
  mMutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mLineColor := StyleServices(Self).GetSystemColor(clBtnFace);
  mTop := RowTop(AIndex);
  mLeft := ScaleValue(cIndent);
  mRight := FBox.Width - ScaleValue(cIndent);
  // Trennlinie zwischen den Zeilen (Mockup).
  if AIndex > 0 then
  begin
    ACanvas.Pen.Color := mLineColor;
    ACanvas.MoveTo(mLeft, mTop);
    ACanvas.LineTo(mRight, mTop);
  end;
  PaintStart(ACanvas, AIndex, mRight);
  mLimit := FStartRects[AIndex].Left - ScaleValue(8);
  Inc(mTop, ScaleValue(cRowPadding));
  // Kennung grau in Festbreitenschrift.
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Name := cMonoFont;
  ACanvas.Font.Color := mMutedColor;
  FKeyRects[AIndex] := Rect(mLeft, mTop, Min(mLeft + ACanvas.TextWidth(mItem.Key), mLimit), mTop + ScaleValue(cLineHeight));
  ACanvas.TextRect(FKeyRects[AIndex], mLeft, mTop + ScaleValue(1), mItem.Key);
  // Neue Änderungen seit dem letzten Öffnen (#1271): Punkt im Rand vor der Kennung.
  if FView.IsUnseen(mItem.Key) then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := StyleServices(Self).GetSystemColor(clHighlight);
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.Ellipse(Rect((mLeft - ScaleValue(cUnseenDot)) div 2, mTop + (ScaleValue(cLineHeight) -
      ScaleValue(cUnseenDot)) div 2, (mLeft + ScaleValue(cUnseenDot)) div 2, mTop + (ScaleValue(cLineHeight) +
      ScaleValue(cUnseenDot)) div 2));
    ACanvas.Brush.Style := bsClear;
  end;
  mLeft := mLeft + Max(ScaleValue(cKeyWidth), ACanvas.TextWidth(mItem.Key) + ScaleValue(8));
  // Titel, abgeschnitten.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := mTextColor;
  if SameText(mItem.Key, FView.Active.Key) then
  begin
    ACanvas.Font.Style := [fsBold];
  end;
  if mLeft < mLimit then
  begin
    ACanvas.TextRect(Rect(mLeft, mTop, mLimit, mTop + ScaleValue(cLineHeight)), mLeft, mTop + ScaleValue(1),
      mItem.Title);
  end;
  ACanvas.Font.Style := [];
  // Zweite Zeile: Felder als Chips mit Rahmen, dann der Pull Request mit CI-Ampel.
  mTop := mTop + ScaleValue(cLineHeight) + (ScaleValue(cChipLineHeight) - ScaleValue(cChipHeight)) div 2;
  ACanvas.Font.Size := Font.Size - 1;
  FPullRects[AIndex] := TRect.Empty;
  if SameText(mItem.Key, FView.Active.Key) then
  begin
    PaintChip(ACanvas, mLeft, mTop, mLimit, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesActive),
      StyleServices(Self).GetSystemColor(clHighlight), True, mChip);
  end;
  for mField in TAtlasMyIssues.Fields(mItem) do
  begin
    PaintChip(ACanvas, mLeft, mTop, mLimit, mField, mMutedColor, False, mChip);
  end;
  mText := PullRequestText(mItem.PullRequest);
  if mText <> '' then
  begin
    PaintChip(ACanvas, mLeft, mTop, mLimit, mText, ChecksColor(mItem.PullRequest.Checks), False, mChip);
    FPullRects[AIndex] := mChip;
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasTrackerIssuesView.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mIndex, mTop: Integer;
  mText: string;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Assign(Font);
  mText := StatusText(FView);
  if mText <> '' then
  begin
    mCanvas.Font.Size := Font.Size - 1;
    if FView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
    begin
      mCanvas.Font.Color := cYellowColor;
    end
    else
    begin
      mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    end;
    mCanvas.TextRect(Rect(ScaleValue(cIndent), ScaleValue(cIndent) div 2, FBox.Width - ScaleValue(cIndent),
      ScaleValue(cIndent) div 2 + ScaleValue(cStatusHeight)), ScaleValue(cIndent), ScaleValue(cIndent) div 2 +
      ScaleValue(2), mText);
    mCanvas.Font.Assign(Font);
  end;
  // Filter der Sprint-Kachel (#1277): Link, der ihn aufhebt.
  FFilterRect := TRect.Empty;
  mText := FilterText(FView);
  if mText <> '' then
  begin
    mTop := FilterTop + ScaleValue(2);
    mCanvas.Font.Size := Font.Size - 1;
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clHotLight);
    FFilterRect := Rect(ScaleValue(cIndent), mTop, Min(ScaleValue(cIndent) + mCanvas.TextWidth(mText),
      FBox.Width - ScaleValue(cIndent)), mTop + mCanvas.TextHeight(mText));
    mCanvas.TextRect(Rect(ScaleValue(cIndent), mTop, FBox.Width - ScaleValue(cIndent), mTop + ScaleValue(cStatusHeight)),
      ScaleValue(cIndent), mTop, mText);
    mCanvas.Font.Assign(Font);
  end;
  if Length(FStartRects) <> Length(FView.Items) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FView.Items) do
  begin
    PaintRow(mCanvas, mIndex);
  end;
  // Woher die Liste kommt (#1262): Verbindung, Tracker-Projekt, gesendete Abfrage.
  mText := SourceText(FView);
  if mText <> '' then
  begin
    mTop := SourceTop + ScaleValue(4);
    mCanvas.Font.Size := Font.Size - 1;
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    mCanvas.TextRect(Rect(ScaleValue(cIndent), mTop, FBox.Width - ScaleValue(cIndent), mTop + ScaleValue(cFooterHeight)),
      ScaleValue(cIndent), mTop, mText);
    mCanvas.Font.Assign(Font);
  end;
  mText := FooterText(FView);
  if mText = '' then
  begin
    Exit;
  end;
  mTop := FooterTop + ScaleValue(4);
  mCanvas.Font.Assign(Font);
  mCanvas.Font.Size := Font.Size - 1;
  if FView.NoticeFailed then
  begin
    mCanvas.Font.Color := cRedColor;
  end
  else if FooterIsAssign(FView) then
  begin
    // Link „zuordnen …“: Akzentfarbe, Klickfläche nur über dem Text.
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clHotLight);
    FAssignRect := Rect(ScaleValue(cIndent), mTop, Min(ScaleValue(cIndent) + mCanvas.TextWidth(mText),
      FBox.Width - ScaleValue(cIndent)), mTop + mCanvas.TextHeight(mText));
  end
  else
  begin
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  end;
  mCanvas.TextRect(Rect(ScaleValue(cIndent), mTop, FBox.Width - ScaleValue(cIndent), mTop + ScaleValue(cFooterHeight)),
    ScaleValue(cIndent), mTop, mText);
  mCanvas.Font.Assign(Font);
end;

function TAtlasTrackerIssuesView.HitTest(AX, AY: Integer): TAtlasIssuesHit;
var
  mIndex: Integer;
  mPoint_: TPoint;
begin
  Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.None, -1);
  mPoint_ := Point(AX, AY);
  if not FAssignRect.IsEmpty and FAssignRect.Contains(mPoint_) then
  begin
    Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Assign, -1));
  end;
  if not FFilterRect.IsEmpty and FFilterRect.Contains(mPoint_) then
  begin
    Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Filter, -1));
  end;
  for mIndex := 0 to High(FView.Items) do
  begin
    if (AY < RowTop(mIndex)) or (AY >= RowTop(mIndex) + RowHeight(mIndex)) then
    begin
      Continue;
    end;
    if (mIndex <= High(FStartRects)) and not FStartRects[mIndex].IsEmpty and FStartRects[mIndex].Contains(mPoint_) then
    begin
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, mIndex));
    end;
    if (mIndex <= High(FKeyRects)) and not FKeyRects[mIndex].IsEmpty and FKeyRects[mIndex].Contains(mPoint_) then
    begin
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, mIndex));
    end;
    if (mIndex <= High(FPullRects)) and not FPullRects[mIndex].IsEmpty and FPullRects[mIndex].Contains(mPoint_) then
    begin
      Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, mIndex));
    end;
    Exit(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, mIndex));
  end;
end;

procedure TAtlasTrackerIssuesView.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Maus- bzw. Menüereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, AAction);
end;

procedure TAtlasTrackerIssuesView.ClickAt(const AHit: TAtlasIssuesHit);
begin
  ClickAt(AHit, False);
end;

procedure TAtlasTrackerIssuesView.ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean);
var
  mSource: IAtlasIssuesSource;
  mItem: TAtlasTrackerIssue;
  mMode: TAtlasIssueStart;
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
  if (FSource <> nil) and (AHit.Kind = TAtlasIssuesHitKind.Filter) then
  begin
    mSource := FSource;
    Post(
      procedure
      begin
        mSource.ClearFilter;
      end);
    Exit;
  end;
  if (FSource = nil) or (AHit.Index < 0) or (AHit.Index > High(FView.Items)) then
  begin
    Exit;
  end;
  mSource := FSource;
  mItem := FView.Items[AHit.Index];
  if (AHit.Kind in [TAtlasIssuesHitKind.Row, TAtlasIssuesHitKind.Key]) and FView.Options.Preview and
    not ABrowse then
  begin
    Post(
      procedure
      begin
        mSource.Preview(mItem);
      end);
    Exit;
  end;
  case AHit.Kind of
    // Leerraum und Zeilentext lösen ohne Vorschau nichts aus; sie zeigen nur den Hinweis (BoxMouseMove).
    TAtlasIssuesHitKind.None, TAtlasIssuesHitKind.Assign, TAtlasIssuesHitKind.Filter: ;
    TAtlasIssuesHitKind.Row:
      if ABrowse and FView.Options.Preview then
      begin
        Post(
          procedure
          begin
            mSource.Browse(mItem);
          end);
      end;
    TAtlasIssuesHitKind.Key:
      Post(
        procedure
        begin
          mSource.Browse(mItem);
        end);
    TAtlasIssuesHitKind.PullRequest:
      Post(
        procedure
        begin
          mSource.BrowsePullRequest(mItem);
        end);
    TAtlasIssuesHitKind.Start:
      if CanStart then
      begin
        mMode := FView.Options.Start;
        Post(
          procedure
          begin
            mSource.Start(mItem, mMode);
          end);
      end;
  end;
end;

procedure TAtlasTrackerIssuesView.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasIssuesHit;
  mKey: string;
begin
  mHit := HitTest(X, Y);
  if (mHit.Kind in [TAtlasIssuesHitKind.Key, TAtlasIssuesHitKind.PullRequest, TAtlasIssuesHitKind.Start,
    TAtlasIssuesHitKind.Assign, TAtlasIssuesHitKind.Filter]) or
    ((mHit.Kind = TAtlasIssuesHitKind.Row) and FView.Options.Preview) then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  mKey := IntToStr(Ord(mHit.Kind)) + ':' + IntToStr(mHit.Index);
  if mKey = FHintKey then
  begin
    Exit;
  end;
  FHintKey := mKey;
  case mHit.Kind of
    TAtlasIssuesHitKind.Key:
      if FView.Options.Preview then
      begin
        FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKeyPreview);
      end
      else
      begin
        FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKey);
      end;
    TAtlasIssuesHitKind.PullRequest:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintPullRequest);
    TAtlasIssuesHitKind.Start:
      FBox.Hint := StartHint(FView, FView.Items[mHit.Index]);
    TAtlasIssuesHitKind.Row:
      begin
        FBox.Hint := FView.Items[mHit.Index].Key + ' ' + FView.Items[mHit.Index].Title;
        if FView.IsUnseen(FView.Items[mHit.Index].Key) then
        begin
          FBox.Hint := FBox.Hint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.IssueNotifyUnseenHint);
        end;
      end;
    TAtlasIssuesHitKind.Assign:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintAssign);
    TAtlasIssuesHitKind.Filter:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintFilter);
  else
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasTrackerIssuesView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
  begin
    ClickAt(HitTest(X, Y), ssCtrl in Shift);
  end;
end;

procedure TAtlasTrackerIssuesView.MenuPopup(Sender: TObject);
var
  mPosition: TPoint;
  mHit: TAtlasIssuesHit;
  mItem: TAtlasTrackerIssue;
  mHasItem, mBranching: Boolean;
begin
  mPosition := FBox.ScreenToClient(FMenu.PopupPoint);
  mHit := HitTest(mPosition.X, mPosition.Y);
  FMenuRow := mHit.Index;
  mHasItem := MenuIssue(mItem);
  mBranching := (FView.VcsKind = TAtlasVcsKind.Git) or (FView.VcsKind = TAtlasVcsKind.Svn);
  FPreviewItem.Visible := mHasItem and FView.Options.Preview;
  FPreviewItem.Default := FPreviewItem.Visible;
  FBrowseItem.Visible := mHasItem;
  FBrowsePullItem.Visible := mHasItem and (mItem.PullRequest.Number > 0);
  FStartBranchItem.Visible := mHasItem and mBranching;
  FStartBranchItem.Enabled := CanStart;
  FStartRememberItem.Visible := mHasItem;
  FStartRememberItem.Enabled := CanStart;
  FQueryItem.Visible := FView.Status <> TAtlasIssuesStatus.NotConfigured;
  FQueryItem.Enabled := not FView.Querying;
  FCredentialsItem.Visible := (FView.Status <> TAtlasIssuesStatus.NotConfigured) and (FSource <> nil) and
    FSource.CanEnterCredentials;
  FEndItem.Visible := FView.Active.Active;
end;

function TAtlasTrackerIssuesView.MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  Result := (FSource <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FView.Items));
  if Result then
  begin
    AIssue := FView.Items[FMenuRow];
  end;
end;

procedure TAtlasTrackerIssuesView.PreviewClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, FMenuRow), False);
end;

procedure TAtlasTrackerIssuesView.BrowseClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, FMenuRow), True);
end;

procedure TAtlasTrackerIssuesView.BrowsePullClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, FMenuRow));
end;

procedure TAtlasTrackerIssuesView.StartBranchClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  mItem: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(mItem) then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Start(mItem, TAtlasIssueStart.Branch);
    end);
end;

procedure TAtlasTrackerIssuesView.StartRememberClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
  mItem: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(mItem) then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Start(mItem, TAtlasIssueStart.Remember);
    end);
end;

procedure TAtlasTrackerIssuesView.QueryClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.QueryNow;
    end);
end;

procedure TAtlasTrackerIssuesView.CredentialsClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.Credentials;
    end);
end;

procedure TAtlasTrackerIssuesView.EndClick(Sender: TObject);
var
  mSource: IAtlasIssuesSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  Post(
    procedure
    begin
      mSource.EndActive;
    end);
end;

end.
