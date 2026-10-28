unit Atlas.UI.Tracker.IssueFrame;

// Inhalt des andockbaren Fensters „Atlas-Issue“ (#1264), reine VCL ohne Open
// Tools API:
//   [◀] [▶]  [Beginnen] [Im Browser öffnen] [Kennung kopieren] [Aktualisieren]
//   ───────────────── dünne Leiste beim Laden ─────────────────
//   (Stand vom …  bzw. Fehler mit Knopf zum Beheben)
//   ATL-123
//   Titel des Issues (Klick öffnet den Tracker)
//   (In Arbeit) (Hoch) (Bug) (M. Muster) (Sprint 12) (ui) (erstellt vor 3 Tg.)
//   Beschreibung: Markdown gesetzt wie die XMLDoc im Hover (TAtlasDocView):
//   Überschriften, Listen, fett/kursiv, Links, Tabellen, Zitate, Codeblöcke
//   (Delphi eingefärbt); alleinstehende Bilder als Vorschau in Fensterbreite,
//   Klick vergrößert.
//   KOMMENTARE (n): neueste unten, ältere hinter „12 ältere Kommentare“.
//   ANHÄNGE (n): Name und Größe; Doppelklick öffnet.
//   VERKNÜPFTE ISSUES (n): Kennung, Titel, Art; Klick öffnet im Fenster.
// Ein Fenster, der Inhalt wechselt; Verlauf über Zurück/Vor (Alt+Links,
// Alt+Rechts). Schließen des Fensters (OnHidden) bricht das Laden ab. Laden, Netz, Verlauf und Zwischenspeicher liegen in der
// IDE-Schicht; der Frame meldet nur Wünsche (On…). Text in der Beschreibung
// und den Kommentaren lässt sich markieren und mit Strg+C kopieren. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.ActnList,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Documentation.View;

const
  /// <summary>Nachricht an den Frame: Inhalt neu bzw. verknüpftes Issue öffnen, nach dem auslösenden Klick (das
  /// Steuerelement des Klicks wird dabei freigegeben). Mit dem Fenster verfällt sie.</summary>
  WM_ATLAS_ISSUE_DEFERRED = WM_APP + 1264;

type
  /// <summary>Eine gesetzte Doku in voller Höhe (Beschreibung bzw. Kommentar).</summary>
  TAtlasIssueDocBox = class(TCustomControl)
  private
    FView: TAtlasDocView;
    FDoc: TAtlasDoc;
    FColors: TAtlasColors;
    FMono: TFont;
    FBuiltWidth: Integer;
    FOnLink: TProc<string>;
    procedure Rebuild;
    procedure WMGetDlgCode(var AMessage: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure CreateWnd; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetDoc(const ADoc: TAtlasDoc; const AColors: TAtlasColors; AMono: TFont);
    function SelectedText: string;
    property View: TAtlasDocView read FView;
    property OnLink: TProc<string> read FOnLink write FOnLink;
  end;

  /// <summary>Bild in Fensterbreite (höchstens Originalgröße); Klick vergrößert.</summary>
  TAtlasIssueImageBox = class(TCustomControl)
  private
    FUrl: string;
    FAlt: string;
    FGraphic: TGraphic;
    FColors: TAtlasColors;
    FOnEnlarge: TNotifyEvent;
    procedure Fit;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Übernimmt AGraphic (gibt es frei).</summary>
    procedure SetGraphic(AGraphic: TGraphic);
    property Url: string read FUrl write FUrl;
    property Alt: string read FAlt write FAlt;
    property Graphic: TGraphic read FGraphic;
    property Colors: TAtlasColors read FColors write FColors;
    property OnEnlarge: TNotifyEvent read FOnEnlarge write FOnEnlarge;
  end;

  /// <summary>Felder als Abzeichen, umgebrochen auf die Breite; Tooltip je Abzeichen.</summary>
  TAtlasIssueBadgeBar = class(TCustomControl)
  private
    FTexts: TArray<string>;
    FHints: TArray<string>;
    FRects: TArray<TRect>;
    FColors: TAtlasColors;
    FHintIndex: Integer;
    procedure Arrange;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetBadges(const ATexts, AHints: TArray<string>; const AColors: TAtlasColors);
    property Texts: TArray<string> read FTexts;
    property Hints: TArray<string> read FHints;
  end;

  TAtlasIssueFrame = class(TFrame)
  private
    FTools: TPanel;
    FBack: TButton;
    FForward: TButton;
    FStart: TButton;
    FBrowse: TButton;
    FCopyKey: TButton;
    FRefresh: TButton;
    FProgress: TProgressBar;
    FStatus: TPanel;
    FStatusText: TLabel;
    FFix: TButton;
    FScroll: TScrollBox;
    FEmpty: TLabel;
    FKey: TLabel;
    FTitle: TLabel;
    FBadges: TAtlasIssueBadgeBar;
    FParts: TList<TControl>;
    FImages: TList<TAtlasIssueImageBox>;
    FDocs: TList<TAtlasIssueDocBox>;
    FAttachments: TListView;
    FLinks: TListView;
    FOlder: TLabel;
    FActions: TActionList;
    FBackAction: TAction;
    FForwardAction: TAction;
    FDetails: TAtlasTrackerDetails;
    FHasDetails: Boolean;
    FNow: TDateTime;
    FCommentsExpanded: Boolean;
    FCommentsOff: Boolean;
    FLoading: Boolean;
    FFixKind: TAtlasIssueFix;
    FColors: TAtlasColors;
    FMono: TFont;
    FCanStart: Boolean;
    FNextTop: Integer;
    FPendingRebuild: Boolean;
    FPendingLink: TAtlasTrackerLink;
    FHasPendingLink: Boolean;
    FOnBack: TProc;
    FOnForward: TProc;
    FOnStart: TProc;
    FOnBrowse: TProc;
    FOnCopyKey: TProc;
    FOnRefresh: TProc;
    FOnCancel: TProc;
    FOnFix: TProc<TAtlasIssueFix>;
    FOnOpenLink: TProc<TAtlasTrackerLink>;
    FOnOpenAttachment: TProc<TAtlasTrackerAttachment>;
    FOnOpenUrl: TProc<string>;
    FOnImages: TProc<TArray<string>>;
    FOnHidden: TProc;
    function AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabel(const ACaption: string; ABold: Boolean): TLabel;
    function AddDoc(const ADoc: TAtlasDoc): TAtlasIssueDocBox;
    function AddList(const AColumns: TArray<string>): TListView;
    procedure AddMarkdown(const AText: string);
    procedure ClearContent;
    procedure Rebuild;
    procedure UpdateButtons;
    function AgeText(ATime: TDateTime): string;
    function AbsoluteText(ATime: TDateTime): string;
    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure CopyKeyClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure FixClick(Sender: TObject);
    procedure TitleClick(Sender: TObject);
    procedure OlderClick(Sender: TObject);
    procedure ImageEnlarge(Sender: TObject);
    procedure AttachmentsDblClick(Sender: TObject);
    procedure AttachmentsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LinksClick(Sender: TObject);
    procedure LinkOpened(const AUrl: string);
    procedure ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    procedure SetMonoFont(AValue: TFont);
    procedure Place(AControl: TControl);
    procedure Defer;
    procedure WMDeferred(var AMessage: TMessage); message WM_ATLAS_ISSUE_DEFERRED;
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Noch kein Issue (Fenster aus dem Desktop der IDE).</summary>
    procedure ShowEmpty;
    /// <summary>Laden läuft (Leiste, „Aktualisieren“ wird „Abbrechen“); der bisherige Inhalt bleibt.</summary>
    procedure SetLoading(AValue: Boolean);
    /// <summary>Issue zeigen. ANow (UTC) für relative Zeiten; AStale: Text der Zeile über dem Inhalt ('' ohne);
    /// ACommentsOff: issues.preview.comments aus.</summary>
    procedure ShowDetails(const ADetails: TAtlasTrackerDetails; ANow: TDateTime; const AStale: string;
      ACommentsOff: Boolean);
    /// <summary>Fehler über dem Inhalt mit Knopf zum Beheben; ohne bisherigen Inhalt nur die Meldung.</summary>
    procedure ShowError(const AText: string; AFix: TAtlasIssueFix);
    /// <summary>Bild zu AUrl ist geladen (übernimmt AGraphic); nil = bleibt als Link.</summary>
    procedure SetImage(const AUrl: string; AGraphic: TGraphic);
    procedure SetHistory(ACanBack, ACanForward: Boolean);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Für Tests: Text der Statuszeile, Abzeichen, Bildadressen, Zahl der Doku-Flächen.</summary>
    function StatusText: string;
    function ImageUrls: TArray<string>;
    function DocCount: Integer;
    property Details: TAtlasTrackerDetails read FDetails;
    property HasDetails: Boolean read FHasDetails;
    property Loading: Boolean read FLoading;
    property CanStart: Boolean read FCanStart write FCanStart;
    property CommentsExpanded: Boolean read FCommentsExpanded;
    property BackButton: TButton read FBack;
    property ForwardButton: TButton read FForward;
    property StartButton: TButton read FStart;
    property BrowseButton: TButton read FBrowse;
    property CopyKeyButton: TButton read FCopyKey;
    property RefreshButton: TButton read FRefresh;
    property FixButton: TButton read FFix;
    property BackAction: TAction read FBackAction;
    property ForwardAction: TAction read FForwardAction;
    property KeyLabel: TLabel read FKey;
    property TitleLabel: TLabel read FTitle;
    property EmptyLabel: TLabel read FEmpty;
    property Badges: TAtlasIssueBadgeBar read FBadges;
    property Attachments: TListView read FAttachments;
    property Links: TListView read FLinks;
    property OlderLabel: TLabel read FOlder;
    property Progress: TProgressBar read FProgress;
    /// <summary>Editorschrift für Code (Vorgabe Consolas).</summary>
    property MonoFont: TFont read FMono write SetMonoFont;
    property OnBack: TProc read FOnBack write FOnBack;
    property OnForward: TProc read FOnForward write FOnForward;
    property OnStart: TProc read FOnStart write FOnStart;
    property OnBrowse: TProc read FOnBrowse write FOnBrowse;
    property OnCopyKey: TProc read FOnCopyKey write FOnCopyKey;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
    property OnCancel: TProc read FOnCancel write FOnCancel;
    property OnFix: TProc<TAtlasIssueFix> read FOnFix write FOnFix;
    property OnOpenLink: TProc<TAtlasTrackerLink> read FOnOpenLink write FOnOpenLink;
    property OnOpenAttachment: TProc<TAtlasTrackerAttachment> read FOnOpenAttachment write FOnOpenAttachment;
    /// <summary>Link aus Beschreibung oder Kommentar bzw. Titel; die IDE-Schicht prüft und öffnet.</summary>
    property OnOpenUrl: TProc<string> read FOnOpenUrl write FOnOpenUrl;
    /// <summary>Adressen der Bilder, die geladen werden sollen (nach ShowDetails).</summary>
    property OnImages: TProc<TArray<string>> read FOnImages write FOnImages;
    /// <summary>Fenster geschlossen bzw. Frame freigegeben: laufendes Laden abbrechen.</summary>
    property OnHidden: TProc read FOnHidden write FOnHidden;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  System.UITypes,
  Vcl.Clipbrd,
  Atlas.Core.Style.Color,
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Strings;

{$R *.dfm}

type
  /// <summary>Vergrößertes Bild; gibt sich beim Schließen selbst frei.</summary>
  TImageWindow = class(TForm)
  protected
    procedure DoClose(var Action: TCloseAction); override;
  end;

procedure TImageWindow.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action := caFree;
end;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueDocBox }

constructor TAtlasIssueDocBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := TAtlasDocView.Create;
  FMono := TFont.Create;
  FColors := TAtlasColors.Light;
  TabStop := True;
  DoubleBuffered := True;
  Height := 16;
end;

destructor TAtlasIssueDocBox.Destroy;
begin
  FView.Free;
  FMono.Free;
  inherited;
end;

procedure TAtlasIssueDocBox.WMGetDlgCode(var AMessage: TWMGetDlgCode);
begin
  inherited;
  AMessage.Result := AMessage.Result or DLGC_WANTARROWS;
end;

procedure TAtlasIssueDocBox.SetDoc(const ADoc: TAtlasDoc; const AColors: TAtlasColors; AMono: TFont);
begin
  FDoc := ADoc;
  FColors := AColors;
  if AMono <> nil then
    FMono.Assign(AMono);
  FBuiltWidth := -1;
  Rebuild;
end;

procedure TAtlasIssueDocBox.CreateWnd;
begin
  inherited;
  // Messen braucht ein Fenster.
  FBuiltWidth := -1;
  Rebuild;
end;

procedure TAtlasIssueDocBox.Rebuild;
var
  mHeight: Integer;
begin
  if not HandleAllocated or (ClientWidth <= 0) or (ClientWidth = FBuiltWidth) then
    Exit;
  FBuiltWidth := ClientWidth;
  Canvas.Font := Font;
  FView.Build(Canvas, FDoc, ClientWidth, FMono, Font, CurrentPPI, TAtlasDocLabels.German,
    Default(TAtlasDocSignature), True);
  mHeight := Max(FView.Height, 1);
  if Height <> mHeight then
    Height := mHeight;
  Invalidate;
end;

procedure TAtlasIssueDocBox.Resize;
begin
  inherited;
  Rebuild;
end;

procedure TAtlasIssueDocBox.Paint;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  FView.Paint(Canvas, FColors, 0, 0);
end;

procedure TAtlasIssueDocBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mLink: Integer;
  mUrl: string;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if CanFocus then
    SetFocus;
  mLink := FView.LinkAt(X, Y);
  if mLink >= 0 then
  begin
    if FView.Link(mLink).Kind = TAtlasDocLinkKind.Url then
    begin
      mUrl := FView.Link(mLink).Url;
      if Assigned(FOnLink) then
        FOnLink(mUrl);
    end;
    Exit;
  end;
  FView.StartSelection(Canvas, X, Y);
  Invalidate;
end;

procedure TAtlasIssueDocBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mLink: Integer;
begin
  inherited;
  if FView.Selecting then
  begin
    FView.ExtendSelection(Canvas, X, Y);
    Invalidate;
    Exit;
  end;
  mLink := FView.LinkAt(X, Y);
  if mLink >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crIBeam;
  if mLink <> FView.HotLink then
  begin
    FView.HotLink := mLink;
    Invalidate;
  end;
end;

procedure TAtlasIssueDocBox.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FView.Selecting then
  begin
    FView.EndSelection;
    Invalidate;
  end;
end;

procedure TAtlasIssueDocBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (ssCtrl in Shift) and ((Key = Ord('C')) or (Key = VK_INSERT)) and FView.HasSelection then
  begin
    Clipboard.AsText := FView.SelectedText;
    Key := 0;
  end;
end;

function TAtlasIssueDocBox.SelectedText: string;
begin
  Result := FView.SelectedText;
end;

{ TAtlasIssueImageBox }

constructor TAtlasIssueImageBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := 24;
  Cursor := crHandPoint;
end;

destructor TAtlasIssueImageBox.Destroy;
begin
  FGraphic.Free;
  inherited;
end;

procedure TAtlasIssueImageBox.SetGraphic(AGraphic: TGraphic);
begin
  FreeAndNil(FGraphic);
  FGraphic := AGraphic;
  Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewImageHint);
  ShowHint := True;
  Fit;
  Invalidate;
end;

procedure TAtlasIssueImageBox.Fit;
var
  mHeight: Integer;
begin
  if (FGraphic = nil) or (FGraphic.Width <= 0) or (ClientWidth <= 0) then
    Exit;
  // Höchstens Originalgröße, sonst Fensterbreite.
  mHeight := FGraphic.Height;
  if FGraphic.Width > ClientWidth then
    mHeight := MulDiv(FGraphic.Height, ClientWidth, FGraphic.Width);
  mHeight := Max(mHeight, 8);
  if Height <> mHeight then
    Height := mHeight;
end;

procedure TAtlasIssueImageBox.Resize;
begin
  inherited;
  Fit;
end;

procedure TAtlasIssueImageBox.Paint;
var
  mRect: TRect;
  mWidth: Integer;
  mText: string;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if (FGraphic = nil) or (FGraphic.Width <= 0) then
  begin
    // Noch nicht geladen bzw. nicht ladbar: Alternativtext gedämpft.
    Canvas.Font := Font;
    Canvas.Font.Color := ToColor(FColors.Muted);
    mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewImageLink, [FAlt]);
    Canvas.TextOut(0, 2, mText);
    Exit;
  end;
  mWidth := Min(FGraphic.Width, ClientWidth);
  mRect := Rect(0, 0, mWidth, ClientHeight);
  Canvas.StretchDraw(mRect, FGraphic);
end;

procedure TAtlasIssueImageBox.Click;
begin
  inherited;
  if (FGraphic <> nil) and Assigned(FOnEnlarge) then
    FOnEnlarge(Self);
end;

{ TAtlasIssueBadgeBar }

constructor TAtlasIssueBadgeBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FHintIndex := -1;
  ShowHint := True;
  Height := 4;
end;

procedure TAtlasIssueBadgeBar.SetBadges(const ATexts, AHints: TArray<string>; const AColors: TAtlasColors);
begin
  FTexts := ATexts;
  FHints := AHints;
  FColors := AColors;
  Arrange;
  Invalidate;
end;

procedure TAtlasIssueBadgeBar.Arrange;
var
  mIndex, mX, mY, mWidth, mHeight, mPad, mGap: Integer;
begin
  FRects := nil;
  if not HandleAllocated then
  begin
    Height := 4;
    Exit;
  end;
  Canvas.Font := Font;
  mPad := MulDiv(6, CurrentPPI, 96);
  mGap := MulDiv(4, CurrentPPI, 96);
  mHeight := Canvas.TextHeight('Wg') + MulDiv(4, CurrentPPI, 96);
  mX := 0;
  mY := 0;
  for mIndex := 0 to High(FTexts) do
  begin
    mWidth := Canvas.TextWidth(FTexts[mIndex]) + 2 * mPad;
    if (mX > 0) and (mX + mWidth > ClientWidth) then
    begin
      mX := 0;
      Inc(mY, mHeight + mGap);
    end;
    FRects := FRects + [Rect(mX, mY, mX + mWidth, mY + mHeight)];
    Inc(mX, mWidth + mGap);
  end;
  if Length(FTexts) = 0 then
    Height := 4
  else if Height <> mY + mHeight + mGap then
    Height := mY + mHeight + mGap;
end;

procedure TAtlasIssueBadgeBar.Resize;
begin
  inherited;
  Arrange;
end;

procedure TAtlasIssueBadgeBar.Paint;
var
  mIndex, mRadius: Integer;
  mRect: TRect;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if Length(FRects) <> Length(FTexts) then
    Arrange;
  Canvas.Font := Font;
  mRadius := MulDiv(8, CurrentPPI, 96);
  for mIndex := 0 to High(FRects) do
  begin
    mRect := FRects[mIndex];
    Canvas.Brush.Color := ToColor(FColors.Gutter);
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, mRadius, mRadius);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ToColor(FColors.Text);
    DrawText(Canvas.Handle, PChar(FTexts[mIndex]), Length(FTexts[mIndex]), mRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TAtlasIssueBadgeBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex, mHit: Integer;
begin
  inherited;
  mHit := -1;
  for mIndex := 0 to High(FRects) do
    if FRects[mIndex].Contains(Point(X, Y)) then
      mHit := mIndex;
  if mHit = FHintIndex then
    Exit;
  FHintIndex := mHit;
  if (mHit >= 0) and (mHit <= High(FHints)) then
    Hint := FHints[mHit]
  else
    Hint := '';
  Application.CancelHint;
end;

{ TAtlasIssueFrame }

constructor TAtlasIssueFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FColors := TAtlasColors.Light;
  FMono := TFont.Create;
  FMono.Name := 'Consolas';
  FMono.Size := 10;
  FParts := TList<TControl>.Create;
  FImages := TList<TAtlasIssueImageBox>.Create;
  FDocs := TList<TAtlasIssueDocBox>.Create;
  FDetails := TAtlasTrackerDetails.Empty;

  FTools := TPanel.Create(Self);
  FTools.Parent := Self;
  FTools.Align := alTop;
  FTools.BevelOuter := bvNone;
  FTools.Height := 32;
  FTools.ShowCaption := False;
  FBack := AddButton('◀', BackClick);
  FBack.Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewBack);
  FBack.Width := 32;
  FForward := AddButton('▶', ForwardClick);
  FForward.Hint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewForward);
  FForward.Width := 32;
  FStart := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewStart), StartClick);
  FBrowse := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewBrowse), BrowseClick);
  FCopyKey := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCopyKey), CopyKeyClick);
  FRefresh := AddButton(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRefresh), RefreshClick);

  FProgress := TProgressBar.Create(Self);
  FProgress.Parent := Self;
  FProgress.Align := alTop;
  FProgress.Top := FTools.Height;
  FProgress.Height := 3;
  FProgress.Style := pbstMarquee;
  FProgress.Visible := False;

  FStatus := TPanel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.Top := FTools.Height + 10;
  FStatus.BevelOuter := bvNone;
  FStatus.Height := 30;
  FStatus.ShowCaption := False;
  FStatus.Visible := False;
  FFix := TButton.Create(Self);
  FFix.Parent := FStatus;
  FFix.Align := alRight;
  FFix.AlignWithMargins := True;
  FFix.Width := 150;
  FFix.OnClick := FixClick;
  FStatusText := TLabel.Create(Self);
  FStatusText.Parent := FStatus;
  FStatusText.Align := alClient;
  FStatusText.AlignWithMargins := True;
  FStatusText.Layout := tlCenter;
  FStatusText.ShowAccelChar := False;
  FStatusText.EllipsisPosition := epEndEllipsis;

  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.HorzScrollBar.Visible := False;
  FScroll.Padding.SetBounds(8, 4, 8, 8);
  FScroll.OnMouseWheel := ScrollWheel;

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := FScroll;
  FEmpty.Align := alTop;
  FEmpty.AlignWithMargins := True;
  FEmpty.WordWrap := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewEmpty);

  FActions := TActionList.Create(Self);
  FBackAction := TAction.Create(Self);
  FBackAction.ActionList := FActions;
  FBackAction.ShortCut := ShortCut(VK_LEFT, [ssAlt]);
  FBackAction.OnExecute := BackClick;
  FForwardAction := TAction.Create(Self);
  FForwardAction.ActionList := FActions;
  FForwardAction.ShortCut := ShortCut(VK_RIGHT, [ssAlt]);
  FForwardAction.OnExecute := ForwardClick;
  UpdateButtons;
end;

destructor TAtlasIssueFrame.Destroy;
begin
  if Assigned(FOnHidden) then
    FOnHidden();
  FOnHidden := nil;
  FParts.Free;
  FImages.Free;
  FDocs.Free;
  FMono.Free;
  inherited;
end;

function TAtlasIssueFrame.AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FTools;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  // Reihenfolge wie angelegt: hinter den bisherigen.
  Result.Left := FTools.ControlCount * 200;
  Result.Caption := ACaption;
  Result.ShowHint := True;
  Result.Width := Max(80, Length(ACaption) * 8);
  Result.OnClick := AClick;
end;

function TAtlasIssueFrame.AddLabel(const ACaption: string; ABold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Place(Result);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Result.Font.Color := ToColor(FColors.Text);
  if ABold then
    Result.Font.Style := [fsBold];
  FParts.Add(Result);
end;

function TAtlasIssueFrame.AddDoc(const ADoc: TAtlasDoc): TAtlasIssueDocBox;
begin
  Result := TAtlasIssueDocBox.Create(Self);
  Place(Result);
  Result.SetDoc(ADoc, FColors, FMono);
  Result.OnLink := LinkOpened;
  FParts.Add(Result);
  FDocs.Add(Result);
end;

function TAtlasIssueFrame.AddList(const AColumns: TArray<string>): TListView;
var
  mCaption: string;
  mColumn: TListColumn;
begin
  Result := TListView.Create(Self);
  Place(Result);
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ShowColumnHeaders := True;
  for mCaption in AColumns do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := mCaption;
    mColumn.AutoSize := True;
  end;
  FParts.Add(Result);
end;

procedure TAtlasIssueFrame.Place(AControl: TControl);
begin
  // Untereinander in der Reihenfolge des Anlegens: alTop ordnet nach Top.
  Inc(FNextTop, 1000);
  AControl.Parent := FScroll;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
end;

procedure TAtlasIssueFrame.Defer;
begin
  if HandleAllocated then
    PostMessage(Handle, WM_ATLAS_ISSUE_DEFERRED, 0, 0);
end;

procedure TAtlasIssueFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FOnHidden) then
    FOnHidden();
end;

procedure TAtlasIssueFrame.WMDeferred(var AMessage: TMessage);
var
  mLink: TAtlasTrackerLink;
begin
  if FPendingRebuild then
  begin
    FPendingRebuild := False;
    Rebuild;
  end;
  if FHasPendingLink then
  begin
    FHasPendingLink := False;
    mLink := FPendingLink;
    if Assigned(FOnOpenLink) then
      FOnOpenLink(mLink);
  end;
end;

procedure TAtlasIssueFrame.AddMarkdown(const AText: string);
var
  mSegment: TAtlasMarkdownSegment;
  mImage: TAtlasIssueImageBox;
  mUrl: string;
begin
  for mSegment in TAtlasTrackerMarkdown.Segments(AText) do
  begin
    if mSegment.Kind = TAtlasMarkdownSegmentKind.Doc then
    begin
      AddDoc(mSegment.Doc);
      Continue;
    end;
    // Relative Namen (YouTrack) sind Anhänge.
    mUrl := TAtlasIssuePreview.ImageUrl(FDetails, mSegment.Image.Url);
    mImage := TAtlasIssueImageBox.Create(Self);
    Place(mImage);
    mImage.Url := mUrl;
    mImage.Alt := mSegment.Image.Text;
    if mImage.Alt = '' then
      mImage.Alt := mSegment.Image.Url;
    mImage.Colors := FColors;
    mImage.OnEnlarge := ImageEnlarge;
    FParts.Add(mImage);
    FImages.Add(mImage);
  end;
end;

procedure TAtlasIssueFrame.ClearContent;
var
  mPart: TControl;
begin
  FScroll.DisableAlign;
  try
    for mPart in FParts do
      mPart.Free;
    FParts.Clear;
    FImages.Clear;
    FDocs.Clear;
    FKey := nil;
    FTitle := nil;
    FBadges := nil;
    FAttachments := nil;
    FLinks := nil;
    FOlder := nil;
    FNextTop := 0;
  finally
    FScroll.EnableAlign;
  end;
end;

function TAtlasIssueFrame.AbsoluteText(ATime: TDateTime): string;
begin
  Result := '';
  if ATime > 0 then
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime));
end;

function TAtlasIssueFrame.AgeText(ATime: TDateTime): string;
var
  mAge: TAtlasIssueAge;
begin
  mAge := TAtlasIssuePreview.Age(ATime, FNow);
  case mAge.UnitKind of
    TAtlasIssueAgeUnit.Minutes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewMinutes, [mAge.Count]);
    TAtlasIssueAgeUnit.Hours:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewHours, [mAge.Count]);
    TAtlasIssueAgeUnit.Days:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewDays, [mAge.Count]);
    TAtlasIssueAgeUnit.Months:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewMonths, [mAge.Count]);
    TAtlasIssueAgeUnit.Years:
      Result := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewYears, [mAge.Count]);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewJustNow);
  end;
end;

procedure TAtlasIssueFrame.Rebuild;
var
  mBadge: TAtlasIssueBadge;
  mTexts, mHints: TArray<string>;
  mText, mHint: string;
  mComments: TArray<TAtlasTrackerComment>;
  mIndex, mCollapsed: Integer;
  mItem: TListItem;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
  mHead: TLabel;
  mUrls: TArray<string>;
  mImage: TAtlasIssueImageBox;
begin
  FScroll.DisableAlign;
  try
    ClearContent;
    FEmpty.Visible := not FHasDetails;
    if not FHasDetails then
      Exit;
    FKey := AddLabel(FDetails.Key, False);
    FKey.Font.Name := FMono.Name;
    FKey.Font.Color := ToColor(FColors.Muted);
    FTitle := AddLabel(FDetails.Title, True);
    FTitle.Font.Height := MulDiv(Font.Height, 13, 10);
    FTitle.Cursor := crHandPoint;
    FTitle.OnClick := TitleClick;
    // Felder als Abzeichen; Zeiten relativ, Tooltip absolut.
    mTexts := nil;
    mHints := nil;
    for mBadge in TAtlasIssuePreview.Badges(FDetails) do
    begin
      case mBadge.Kind of
        TAtlasIssueBadgeKind.State:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldState);
        TAtlasIssueBadgeKind.Priority:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldPriority);
        TAtlasIssueBadgeKind.Kind:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldKind);
        TAtlasIssueBadgeKind.Assignee:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldAssignee);
        TAtlasIssueBadgeKind.Sprint:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldSprint);
        TAtlasIssueBadgeKind.LabelName:
          mHint := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFieldLabel);
      else
        mHint := '';
      end;
      mText := mBadge.Text;
      if mBadge.Kind = TAtlasIssueBadgeKind.Created then
      begin
        mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeCreated, [AgeText(mBadge.Time)]);
        mHint := AbsoluteText(mBadge.Time);
      end
      else if mBadge.Kind = TAtlasIssueBadgeKind.Updated then
      begin
        mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewBadgeUpdated, [AgeText(mBadge.Time)]);
        mHint := AbsoluteText(mBadge.Time);
      end
      else
        mHint := mHint + ': ' + mBadge.Text;
      mTexts := mTexts + [mText];
      mHints := mHints + [mHint];
    end;
    FBadges := TAtlasIssueBadgeBar.Create(Self);
    Place(FBadges);
    FParts.Add(FBadges);
    FBadges.SetBadges(mTexts, mHints, FColors);
    // Beschreibung.
    if Trim(FDetails.Description) = '' then
      AddLabel(TAtlasStrings.Text(TAtlasTextId.IssuePreviewNoDescription), False).Font.Color :=
        ToColor(FColors.Muted)
    else
      AddMarkdown(FDetails.Description);
    // Kommentare: neueste unten, ältere eingeklappt.
    if FCommentsOff then
      AddLabel(TAtlasStrings.Text(TAtlasTextId.IssuePreviewCommentsOff), False).Font.Color := ToColor(FColors.Muted)
    else if Length(FDetails.Comments) > 0 then
    begin
      AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewComments, [Length(FDetails.Comments)])),
        True).Font.Color := ToColor(FColors.Muted);
      mComments := FDetails.Comments;
      mCollapsed := TAtlasIssuePreview.CollapsedComments(Length(mComments), FCommentsExpanded);
      if mCollapsed > 0 then
      begin
        if mCollapsed = 1 then
          mText := TAtlasStrings.Text(TAtlasTextId.IssuePreviewOlderComment)
        else
          mText := TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewOlderComments, [mCollapsed]);
        FOlder := AddLabel(mText, False);
        FOlder.Font.Color := ToColor(FColors.Accent);
        FOlder.Font.Style := [fsUnderline];
        FOlder.Cursor := crHandPoint;
        FOlder.OnClick := OlderClick;
      end;
      for mIndex := mCollapsed to High(mComments) do
      begin
        mHead := AddLabel(mComments[mIndex].Author + ' · ' + AgeText(mComments[mIndex].Created), True);
        mHead.Hint := AbsoluteText(mComments[mIndex].Created);
        mHead.ShowHint := True;
        AddMarkdown(mComments[mIndex].Text);
      end;
    end;
    // Anhänge: Name und Größe; Doppelklick öffnet.
    if Length(FDetails.Attachments) > 0 then
    begin
      AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewAttachments,
        [Length(FDetails.Attachments)])), True).Font.Color := ToColor(FColors.Muted);
      FAttachments := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnName),
        TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnSize)));
      for mAttachment in FDetails.Attachments do
      begin
        mItem := FAttachments.Items.Add;
        mItem.Caption := mAttachment.Name;
        if mAttachment.Size >= 0 then
          mItem.SubItems.Add(FormatFloat('#,##0.0', mAttachment.Size / 1024) + ' KB')
        else
          mItem.SubItems.Add('–');
      end;
      FAttachments.Height := (Length(FDetails.Attachments) + 2) * MulDiv(20, CurrentPPI, 96);
      FAttachments.OnDblClick := AttachmentsDblClick;
      FAttachments.OnKeyDown := AttachmentsKeyDown;
    end;
    // Verknüpfte Issues: Klick öffnet sie im selben Fenster (bzw. im Browser).
    if Length(FDetails.Links) > 0 then
    begin
      AddLabel(AnsiUpperCase(TAtlasStrings.Fmt(TAtlasTextId.IssuePreviewLinks, [Length(FDetails.Links)])),
        True).Font.Color := ToColor(FColors.Muted);
      FLinks := AddList(TArray<string>.Create(TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnKey),
        TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnTitle),
        TAtlasStrings.Text(TAtlasTextId.IssuePreviewColumnRelation)));
      for mLink in FDetails.Links do
      begin
        mItem := FLinks.Items.Add;
        mItem.Caption := mLink.Key;
        mItem.SubItems.Add(mLink.Title);
        if mLink.Relation = 'cross-referenced' then
          mItem.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRelationMentioned))
        else if mLink.Relation = 'pull request' then
          mItem.SubItems.Add(TAtlasStrings.Text(TAtlasTextId.IssuePreviewRelationPull))
        else
          mItem.SubItems.Add(mLink.Relation);
      end;
      FLinks.Height := (Length(FDetails.Links) + 2) * MulDiv(20, CurrentPPI, 96);
      FLinks.OnClick := LinksClick;
    end;
  finally
    FScroll.EnableAlign;
  end;
  // Bilder laden lassen (nur die mit Adresse).
  mUrls := nil;
  for mImage in FImages do
    if mImage.Url <> '' then
      mUrls := mUrls + [mImage.Url];
  if (Length(mUrls) > 0) and Assigned(FOnImages) then
    FOnImages(mUrls);
end;

procedure TAtlasIssueFrame.UpdateButtons;
begin
  FStart.Enabled := FHasDetails and FCanStart;
  FBrowse.Enabled := FHasDetails;
  FCopyKey.Enabled := FHasDetails;
  FRefresh.Enabled := FHasDetails or FLoading;
  if FLoading then
    FRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewCancel)
  else
    FRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewRefresh);
  FBackAction.Enabled := FBack.Enabled;
  FForwardAction.Enabled := FForward.Enabled;
end;

procedure TAtlasIssueFrame.ShowEmpty;
begin
  FHasDetails := False;
  FDetails := TAtlasTrackerDetails.Empty;
  FStatus.Visible := False;
  Rebuild;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetLoading(AValue: Boolean);
begin
  FLoading := AValue;
  FProgress.Visible := AValue;
  if AValue then
  begin
    FStatusText.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewLoading);
    FFix.Visible := False;
    FStatus.Visible := not FHasDetails;
  end;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ShowDetails(const ADetails: TAtlasTrackerDetails; ANow: TDateTime;
  const AStale: string; ACommentsOff: Boolean);
begin
  // Anderes Issue: ältere Kommentare wieder eingeklappt.
  if not FHasDetails or not SameText(FDetails.Key, ADetails.Key) then
    FCommentsExpanded := False;
  FDetails := ADetails;
  FHasDetails := True;
  FNow := ANow;
  FCommentsOff := ACommentsOff;
  FStatusText.Caption := AStale;
  FFix.Visible := False;
  FStatus.Visible := AStale <> '';
  Rebuild;
  FScroll.VertScrollBar.Position := 0;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ShowError(const AText: string; AFix: TAtlasIssueFix);
begin
  FFixKind := AFix;
  FStatusText.Caption := AText;
  FFix.Visible := AFix <> TAtlasIssueFix.None;
  case AFix of
    TAtlasIssueFix.EnterToken:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixToken);
    TAtlasIssueFix.Settings:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixSettings);
    TAtlasIssueFix.Browser:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewBrowse);
    TAtlasIssueFix.Retry:
      FFix.Caption := TAtlasStrings.Text(TAtlasTextId.IssuePreviewFixRetry);
  end;
  FStatus.Visible := True;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.SetImage(const AUrl: string; AGraphic: TGraphic);
var
  mImage: TAtlasIssueImageBox;
  mOwned: Boolean;
  mCopy: TGraphic;
begin
  if AGraphic = nil then
    Exit;
  mOwned := False;
  try
    for mImage in FImages do
    begin
      if mImage.Url <> AUrl then
        Continue;
      // Dasselbe Bild mehrfach: jede Fläche bekommt ein eigenes.
      if not mOwned then
      begin
        mImage.SetGraphic(AGraphic);
        mOwned := True;
      end
      else
      begin
        mCopy := TGraphicClass(AGraphic.ClassType).Create;
        mCopy.Assign(AGraphic);
        mImage.SetGraphic(mCopy);
      end;
    end;
  finally
    if not mOwned then
      AGraphic.Free;
  end;
end;

procedure TAtlasIssueFrame.SetHistory(ACanBack, ACanForward: Boolean);
begin
  FBack.Enabled := ACanBack;
  FForward.Enabled := ACanForward;
  UpdateButtons;
end;

procedure TAtlasIssueFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FScroll.Color := ToColor(AColors.Surface);
  FScroll.ParentBackground := False;
  FEmpty.Font.Color := ToColor(AColors.Muted);
  if FHasDetails then
    Rebuild;
end;

procedure TAtlasIssueFrame.SetMonoFont(AValue: TFont);
begin
  FMono.Assign(AValue);
  if FHasDetails then
    Rebuild;
end;

function TAtlasIssueFrame.StatusText: string;
begin
  Result := '';
  if FStatus.Visible then
    Result := FStatusText.Caption;
end;

function TAtlasIssueFrame.ImageUrls: TArray<string>;
var
  mImage: TAtlasIssueImageBox;
begin
  Result := nil;
  for mImage in FImages do
    Result := Result + [mImage.Url];
end;

function TAtlasIssueFrame.DocCount: Integer;
begin
  Result := FDocs.Count;
end;

procedure TAtlasIssueFrame.BackClick(Sender: TObject);
begin
  if FBack.Enabled and Assigned(FOnBack) then
    FOnBack();
end;

procedure TAtlasIssueFrame.ForwardClick(Sender: TObject);
begin
  if FForward.Enabled and Assigned(FOnForward) then
    FOnForward();
end;

procedure TAtlasIssueFrame.StartClick(Sender: TObject);
begin
  if Assigned(FOnStart) then
    FOnStart();
end;

procedure TAtlasIssueFrame.BrowseClick(Sender: TObject);
begin
  if Assigned(FOnBrowse) then
    FOnBrowse();
end;

procedure TAtlasIssueFrame.CopyKeyClick(Sender: TObject);
begin
  if Assigned(FOnCopyKey) then
    FOnCopyKey();
end;

procedure TAtlasIssueFrame.RefreshClick(Sender: TObject);
begin
  if FLoading then
  begin
    if Assigned(FOnCancel) then
      FOnCancel();
  end
  else if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TAtlasIssueFrame.FixClick(Sender: TObject);
begin
  if Assigned(FOnFix) then
    FOnFix(FFixKind);
end;

procedure TAtlasIssueFrame.TitleClick(Sender: TObject);
begin
  if Assigned(FOnBrowse) then
    FOnBrowse();
end;

procedure TAtlasIssueFrame.OlderClick(Sender: TObject);
begin
  FCommentsExpanded := True;
  // Nicht im Klick des Labels, das dabei freigegeben wird.
  FPendingRebuild := True;
  Defer;
end;

procedure TAtlasIssueFrame.ImageEnlarge(Sender: TObject);
var
  mForm: TImageWindow;
  mBox: TScrollBox;
  mImage: TImage;
  mSource: TAtlasIssueImageBox;
begin
  mSource := Sender as TAtlasIssueImageBox;
  if mSource.Graphic = nil then
    Exit;
  mForm := TImageWindow.CreateNew(nil);
  mForm.Caption := mSource.Alt;
  mForm.Position := poScreenCenter;
  mForm.Width := Min(mSource.Graphic.Width + 40, Screen.WorkAreaWidth - 80);
  mForm.Height := Min(mSource.Graphic.Height + 60, Screen.WorkAreaHeight - 80);
  mBox := TScrollBox.Create(mForm);
  mBox.Parent := mForm;
  mBox.Align := alClient;
  mImage := TImage.Create(mForm);
  mImage.Parent := mBox;
  mImage.AutoSize := True;
  mImage.Picture.Assign(mSource.Graphic);
  mForm.Show;
end;

procedure TAtlasIssueFrame.AttachmentsDblClick(Sender: TObject);
begin
  if (FAttachments = nil) or (FAttachments.Selected = nil) then
    Exit;
  if (FAttachments.Selected.Index <= High(FDetails.Attachments)) and Assigned(FOnOpenAttachment) then
    FOnOpenAttachment(FDetails.Attachments[FAttachments.Selected.Index]);
end;

procedure TAtlasIssueFrame.AttachmentsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    AttachmentsDblClick(Sender);
    Key := 0;
  end;
end;

procedure TAtlasIssueFrame.LinksClick(Sender: TObject);
var
  mLink: TAtlasTrackerLink;
begin
  if (FLinks = nil) or (FLinks.Selected = nil) or (FLinks.Selected.Index > High(FDetails.Links)) then
    Exit;
  mLink := FDetails.Links[FLinks.Selected.Index];
  // Öffnen ersetzt den Inhalt samt Liste: nicht im Klick der Liste.
  FPendingLink := mLink;
  FHasPendingLink := True;
  Defer;
end;

procedure TAtlasIssueFrame.LinkOpened(const AUrl: string);
begin
  if Assigned(FOnOpenUrl) then
    FOnOpenUrl(AUrl);
end;

procedure TAtlasIssueFrame.ScrollWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  FScroll.VertScrollBar.Position := FScroll.VertScrollBar.Position - WheelDelta div 2;
  Handled := True;
end;

end.
