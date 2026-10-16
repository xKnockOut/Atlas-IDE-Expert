unit Atlas.UI.Welcome.Issues;

// Bereich „Meine Issues“ der Willkommensseite (#765, Mockup #ws12), ohne
// Open Tools API. Selbst gezeichnet, je Issue zwei Zeilen im Raster:
//   #753     Atlas-Bereiche und Layout der Willkommens…   [Beginnen]
//            (plugin) (welcome) (PR #760 · CI grün)
//   ─────────────────────────────────────────────────────────────────
//   ATL-123  Tracker im Bereich                           [Beginnen]
//            (In Arbeit) (Hoch) (Sprint 12) (aktuell)
//   „Beginnen“ legt den Branch an und öffnet das Projekt.
// Kennung grau in Festbreitenschrift (Klick öffnet das Issue im Browser),
// Titel abgeschnitten, darunter Felder als Chips mit Rahmen (GitHub: Labels
// und der Pull Request mit CI-Ampel, Klick öffnet ihn; YouTrack: Zustand,
// Priorität, Sprint). Rechts „Beginnen“ über beide Zeilen. Über der Liste nur
// bei Bedarf eine Zeile zum Stand (wird abgefragt, Fehler, „Stand vom …“),
// darunter die Fußzeile bzw. der Hinweis nach „Beginnen“. Kontextmenü: Im
// Browser öffnen, Pull-Request im Browser, Beginnen, Nur merken, Tracker jetzt
// abfragen, Zugang hinterlegen, Aktuelles Issue beenden.
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
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    /// <summary>Tracker jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow;
    /// <summary>„Zugang zum Issue-Tracker hinterlegen …“.</summary>
    procedure Credentials;
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung TrackerLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Aktuelles Issue beenden (mit Rückfrage).</summary>
    procedure EndActive;
  end;

{$SCOPEDENUMS ON}
  TAtlasIssuesHitKind = (None, Row, Key, PullRequest, Start);
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
    FBox: TPaintBox;
    FView: TAtlasIssuesView;
    FKeyRects: TArray<TRect>;
    FPullRects: TArray<TRect>;
    FStartRects: TArray<TRect>;
    FMenu: TPopupMenu;
    FBrowseItem: TMenuItem;
    FBrowsePullItem: TMenuItem;
    FStartBranchItem: TMenuItem;
    FStartRememberItem: TMenuItem;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FEndItem: TMenuItem;
    FMenuRow: Integer;
    FHintKey: string;
    procedure SetSource(const AValue: IAtlasIssuesSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure BrowsePullClick(Sender: TObject);
    procedure StartBranchClick(Sender: TObject);
    procedure StartRememberClick(Sender: TObject);
    procedure QueryClick(Sender: TObject);
    procedure CredentialsClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    function MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
    procedure Post(const AAction: TThreadProcedure);
    function ListTop: Integer;
    function RowTop(AIndex: Integer): Integer;
    function RowHeight(AIndex: Integer): Integer;
    function FooterTop: Integer;
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
    /// beginnt mit der Einstellung welcomePage.issues.start.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit);
    /// <summary>„Beginnen“ nutzbar: Quelle da, keine laufende Aktion.</summary>
    function CanStart: Boolean;
    /// <summary>Zeile über der Liste: Stand, Fehler, „Stand vom …“; '' bei frischem Stand.</summary>
    class function StatusText(const AView: TAtlasIssuesView; ANowUtc: TDateTime): string; static;
    /// <summary>Fußzeile: Hinweis, sonst aktuelles Issue außerhalb der Liste, sonst was „Beginnen“ tut.</summary>
    class function FooterText(const AView: TAtlasIssuesView): string; static;
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
    property PaintBox: TPaintBox read FBox;
    property Menu: TPopupMenu read FMenu;
    property BrowseItem: TMenuItem read FBrowseItem;
    property BrowsePullItem: TMenuItem read FBrowsePullItem;
    property StartBranchItem: TMenuItem read FStartBranchItem;
    property StartRememberItem: TMenuItem read FStartRememberItem;
    property QueryItem: TMenuItem read FQueryItem;
    property CredentialsItem: TMenuItem read FCredentialsItem;
    property EndItem: TMenuItem read FEndItem;
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

implementation

uses
  System.UITypes,
  System.Math,
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
  FBox := TPaintBox.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
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
  SetLength(FKeyRects, Length(FView.Items));
  SetLength(FPullRects, Length(FView.Items));
  SetLength(FStartRects, Length(FView.Items));
  FHintKey := '';
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

class function TAtlasWelcomeIssuesFrame.StatusText(const AView: TAtlasIssuesView; ANowUtc: TDateTime): string;
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
  if StatusText(FView, NowUtc) <> '' then
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

function TAtlasWelcomeIssuesFrame.BodyHeight: Integer;
begin
  Result := FooterTop + ScaleValue(FooterHeight) + ScaleValue(Indent) div 2;
end;

function TAtlasWelcomeIssuesFrame.ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
begin
  Result := ACanvas.TextWidth(AText) + 2 * ScaleValue(ChipPadding);
end;

procedure TAtlasWelcomeIssuesFrame.PaintChip(ACanvas: TCanvas; var ALeft: Integer; ATop, ALimit: Integer;
  const AText: string; AColor: TColor; AFilled: Boolean; out ARect: TRect);
var
  Width, Radius: Integer;
begin
  ARect := TRect.Empty;
  Width := ChipWidth(ACanvas, AText);
  if ALeft + Width > ALimit then
    Exit;
  ARect := Rect(ALeft, ATop, ALeft + Width, ATop + ScaleValue(ChipHeight));
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
  Text: string;
  Area: TRect;
  Top, Width: Integer;
  Accent: TColor;
begin
  ACanvas.Font.Assign(Font);
  Text := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStart);
  Width := ACanvas.TextWidth(Text) + 2 * ScaleValue(ButtonPadding);
  // Über beide Zeilen der Zeile mittig (Mockup).
  Top := RowTop(AIndex) + (RowHeight(AIndex) - ScaleValue(ButtonHeight)) div 2;
  Area := Rect(ARight - Width, Top, ARight, Top + ScaleValue(ButtonHeight));
  FStartRects[AIndex] := Area;
  Accent := StyleServices(Self).GetSystemColor(clBtnShadow);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := Accent;
  ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, ScaleValue(6), ScaleValue(6));
  if CanStart then
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText)
  else
    ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  ACanvas.TextOut(Area.Left + (Area.Width - ACanvas.TextWidth(Text)) div 2,
    Area.Top + (Area.Height - ACanvas.TextHeight(Text)) div 2, Text);
end;

procedure TAtlasWelcomeIssuesFrame.PaintRow(ACanvas: TCanvas; AIndex: Integer);
var
  Item: TAtlasTrackerIssue;
  Top, Left, Limit, Right: Integer;
  TextColor, MutedColor, LineColor: TColor;
  Field, Text: string;
  Chip: TRect;
begin
  Item := FView.Items[AIndex];
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clBtnFace);
  Top := RowTop(AIndex);
  Left := ScaleValue(Indent);
  Right := FBox.Width - ScaleValue(Indent);
  // Trennlinie zwischen den Zeilen (Mockup).
  if AIndex > 0 then
  begin
    ACanvas.Pen.Color := LineColor;
    ACanvas.MoveTo(Left, Top);
    ACanvas.LineTo(Right, Top);
  end;
  PaintStart(ACanvas, AIndex, Right);
  Limit := FStartRects[AIndex].Left - ScaleValue(8);
  Inc(Top, ScaleValue(RowPadding));
  // Kennung grau in Festbreitenschrift.
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Name := MonoFont;
  ACanvas.Font.Color := MutedColor;
  FKeyRects[AIndex] := Rect(Left, Top, Min(Left + ACanvas.TextWidth(Item.Key), Limit), Top + ScaleValue(LineHeight));
  ACanvas.TextRect(FKeyRects[AIndex], Left, Top + ScaleValue(1), Item.Key);
  Left := Left + Max(ScaleValue(KeyWidth), ACanvas.TextWidth(Item.Key) + ScaleValue(8));
  // Titel, abgeschnitten.
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := TextColor;
  if SameText(Item.Key, FView.Active.Key) then
    ACanvas.Font.Style := [fsBold];
  if Left < Limit then
    ACanvas.TextRect(Rect(Left, Top, Limit, Top + ScaleValue(LineHeight)), Left, Top + ScaleValue(1),
      Item.Title);
  ACanvas.Font.Style := [];
  // Zweite Zeile: Felder als Chips mit Rahmen, dann der Pull Request mit CI-Ampel.
  Top := Top + ScaleValue(LineHeight) + (ScaleValue(ChipLineHeight) - ScaleValue(ChipHeight)) div 2;
  ACanvas.Font.Size := Font.Size - 1;
  FPullRects[AIndex] := TRect.Empty;
  if SameText(Item.Key, FView.Active.Key) then
    PaintChip(ACanvas, Left, Top, Limit, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesActive),
      StyleServices(Self).GetSystemColor(clHighlight), True, Chip);
  for Field in TAtlasWelcomeIssues.Fields(Item) do
    PaintChip(ACanvas, Left, Top, Limit, Field, MutedColor, False, Chip);
  Text := PullRequestText(Item.PullRequest);
  if Text <> '' then
  begin
    PaintChip(ACanvas, Left, Top, Limit, Text, ChecksColor(Item.PullRequest.Checks), False, Chip);
    FPullRects[AIndex] := Chip;
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasWelcomeIssuesFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Index, Top: Integer;
  Text: string;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  Text := StatusText(FView, NowUtc);
  if Text <> '' then
  begin
    Canvas.Font.Size := Font.Size - 1;
    if FView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
      Canvas.Font.Color := YellowColor
    else
      Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    Canvas.TextRect(Rect(ScaleValue(Indent), ScaleValue(Indent) div 2, FBox.Width - ScaleValue(Indent),
      ScaleValue(Indent) div 2 + ScaleValue(StatusHeight)), ScaleValue(Indent), ScaleValue(Indent) div 2 +
      ScaleValue(2), Text);
    Canvas.Font.Assign(Font);
  end;
  if Length(FStartRects) <> Length(FView.Items) then
    Exit;
  for Index := 0 to High(FView.Items) do
    PaintRow(Canvas, Index);
  Text := FooterText(FView);
  if Text = '' then
    Exit;
  Top := FooterTop + ScaleValue(4);
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := Font.Size - 1;
  if FView.NoticeFailed then
    Canvas.Font.Color := RedColor
  else
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  Canvas.TextRect(Rect(ScaleValue(Indent), Top, FBox.Width - ScaleValue(Indent), Top + ScaleValue(FooterHeight)),
    ScaleValue(Indent), Top, Text);
  Canvas.Font.Assign(Font);
end;

function TAtlasWelcomeIssuesFrame.HitTest(X, Y: Integer): TAtlasIssuesHit;
var
  Index: Integer;
  Point_: TPoint;
begin
  Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.None, -1);
  Point_ := Point(X, Y);
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
var
  Source: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
  Mode: TAtlasIssueStart;
begin
  if (FSource = nil) or (AHit.Index < 0) or (AHit.Index > High(FView.Items)) then
    Exit;
  Source := FSource;
  Item := FView.Items[AHit.Index];
  case AHit.Kind of
    TAtlasIssuesHitKind.Key:
      Post(
        procedure
        begin
          Source.Browse(Item);
        end);
    TAtlasIssuesHitKind.PullRequest:
      Post(
        procedure
        begin
          Source.BrowsePullRequest(Item);
        end);
    TAtlasIssuesHitKind.Start:
      if CanStart then
      begin
        Mode := FView.Options.Start;
        Post(
          procedure
          begin
            Source.Start(Item, Mode);
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
  if Hit.Kind in [TAtlasIssuesHitKind.Key, TAtlasIssuesHitKind.PullRequest, TAtlasIssuesHitKind.Start] then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  Key := IntToStr(Ord(Hit.Kind)) + ':' + IntToStr(Hit.Index);
  if Key = FHintKey then
    Exit;
  FHintKey := Key;
  case Hit.Kind of
    TAtlasIssuesHitKind.Key:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKey);
    TAtlasIssuesHitKind.PullRequest:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintPullRequest);
    TAtlasIssuesHitKind.Start:
      FBox.Hint := StartHint(FView, FView.Items[Hit.Index]);
    TAtlasIssuesHitKind.Row:
      FBox.Hint := FView.Items[Hit.Index].Key + ' ' + FView.Items[Hit.Index].Title;
  else
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeIssuesFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y));
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

procedure TAtlasWelcomeIssuesFrame.BrowseClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, FMenuRow));
end;

procedure TAtlasWelcomeIssuesFrame.BrowsePullClick(Sender: TObject);
begin
  ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, FMenuRow));
end;

procedure TAtlasWelcomeIssuesFrame.StartBranchClick(Sender: TObject);
var
  Source: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(Item) then
    Exit;
  Source := FSource;
  Post(
    procedure
    begin
      Source.Start(Item, TAtlasIssueStart.Branch);
    end);
end;

procedure TAtlasWelcomeIssuesFrame.StartRememberClick(Sender: TObject);
var
  Source: IAtlasIssuesSource;
  Item: TAtlasTrackerIssue;
begin
  if not CanStart or not MenuIssue(Item) then
    Exit;
  Source := FSource;
  Post(
    procedure
    begin
      Source.Start(Item, TAtlasIssueStart.Remember);
    end);
end;

procedure TAtlasWelcomeIssuesFrame.QueryClick(Sender: TObject);
var
  Source: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  Post(
    procedure
    begin
      Source.QueryNow;
    end);
end;

procedure TAtlasWelcomeIssuesFrame.CredentialsClick(Sender: TObject);
var
  Source: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  Post(
    procedure
    begin
      Source.Credentials;
    end);
end;

procedure TAtlasWelcomeIssuesFrame.EndClick(Sender: TObject);
var
  Source: IAtlasIssuesSource;
begin
  if FSource = nil then
    Exit;
  Source := FSource;
  Post(
    procedure
    begin
      Source.EndActive;
    end);
end;

end.
