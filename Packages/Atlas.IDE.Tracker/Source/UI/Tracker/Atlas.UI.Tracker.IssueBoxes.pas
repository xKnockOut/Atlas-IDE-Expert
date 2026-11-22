unit Atlas.UI.Tracker.IssueBoxes;

// Bausteine des Fensters „Atlas-Issue“ (#1264), reine VCL ohne Open Tools API:
// Bild in Fensterbreite (Klick vergrößert in einem eigenen Fenster), Felder
// als Abzeichen mit Tooltip und die Texte des Verknüpfungsbaums (#1279).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Plugin.Style.Color,
  Atlas.Plugin.Style.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Links,
  Atlas.Vcl.Forms.Dialog;

type
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

  /// <summary>Überschrift eines Abschnitts (Beschreibung, Kommentare, Anhänge …): gedämpfter Text, dahinter
  /// eine Linie bis zum rechten Rand.</summary>
  TAtlasIssueSectionHead = class(TCustomControl)
  public const
    /// <summary>Höhe bei 96 dpi und Abstand des Texts zur Linie.</summary>
    cHeight = 26;
    cLineGap = 8;
  private
    FColors: TAtlasColors;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetColors(const AColors: TAtlasColors);
    property Caption;
  end;

  /// <summary>Teile untereinander in voller Breite, in der Reihenfolge, in der sie eingehängt werden (Parent);
  /// die Höhe folgt dem Inhalt. Ersetzt alTop: Das ordnet nach Top und verliert Höhenänderungen, die ein Teil
  /// während des Ausrichtens macht (Doku, Abzeichen, Bilder und umbrechende Texte rechnen ihre Höhe in Resize
  /// bzw. CreateWnd aus der Breite). Hier bekommt jedes Teil zuerst seine Breite, erst danach zählt seine Höhe;
  /// ändert sie sich später, richtet die Fläche über RequestAlign neu aus. Margins zählen bei AlignWithMargins.
  /// </summary>
  TAtlasIssueStack = class(TCustomControl)
  private
    /// <summary>Teile in der Reihenfolge des Einhängens; nil im Destruktor.</summary>
    FItems: TList<TControl>;
    procedure CMControlListChange(var AMessage: TCMControlListChange); message CM_CONTROLLISTCHANGE;
  protected
    procedure AlignControls(AControl: TControl; var Rect: TRect); override;
    procedure CreateWnd; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Jetzt ablegen, auch ohne Fenster (die VCL richtet erst mit Fenster aus).</summary>
    procedure Arrange;
  end;

  /// <summary>Abgesetzte Fläche mit Rahmen (Kopf des Issues, ein Kommentar); wächst mit ihrem Inhalt.
  /// Die Kinder erben die Füllfarbe über Color.</summary>
  TAtlasIssueCard = class(TAtlasIssueStack)
  public const
    /// <summary>Innenabstand bei 96 dpi: seitlich und oben/unten.</summary>
    cPadSide = 6;
    cPadEnd = 4;
  private
    FFill: TAtlasColor;
    FBorder: TAtlasColor;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetColors(AFill, ABorder: TAtlasColor);
    property Fill: TAtlasColor read FFill;
  end;

  /// <summary>Vergrößertes Bild; gibt sich beim Schließen selbst frei.</summary>
  TAtlasIssueImageWindow = class(TAtlasDialog)
  protected
    procedure DoClose(var Action: TCloseAction); override;
  public
    /// <summary>Bild von ASource in eigenem Fenster zeigen; ohne Bild nichts.</summary>
    class procedure Enlarge(ASource: TAtlasIssueImageBox); static;
  end;

  /// <summary>Texte des Verknüpfungsbaums (#1279).</summary>
  TAtlasIssueLinkText = class
  public
    /// <summary>Zeile des Baums: Symbol, Kennung, Titel, Zustand.</summary>
    class function Row(const ALink: TAtlasTrackerLink): string; static;
    /// <summary>Überschrift einer Gruppe, bei Unteraufgaben mit Fortschritt „2/3“.</summary>
    class function Group(const AGroup: TAtlasTrackerLinkGroup): string; static;
    /// <summary>ALinks ergeben mindestens eine Gruppe des Baums.</summary>
    class function HasGroups(const ALinks: TArray<TAtlasTrackerLink>): Boolean; static;
    /// <summary>Baum aus den Gruppen von ALinks füllen: Gruppen mit Node.Data = nil, Verknüpfungen mit
    /// Node.Data = Index + 1 in ATreeLinks (dort angehängt). Duplikate, „bezieht sich auf“ und Erwähnungen bleiben
    /// eingeklappt.</summary>
    class procedure FillTree(ATree: TTreeView; const ALinks: TArray<TAtlasTrackerLink>;
      var ATreeLinks: TArray<TAtlasTrackerLink>); static;
  end;

  /// <summary>Zeiten im Fenster: relativ im Text, absolut im Tooltip.</summary>
  TAtlasIssueTimeText = class
  public
    /// <summary>Alter von ATime (UTC) gegenüber ANow (UTC), z. B. „vor 3 Tg.“.</summary>
    class function Age(ATime, ANow: TDateTime): string; static;
    /// <summary>ATime (UTC) als Ortszeit „dd.mm.yyyy hh:nn“; '' ohne Zeit.</summary>
    class function Absolute(ATime: TDateTime): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.DateUtils,
  Vcl.ExtCtrls,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.IssueTip;

const
  // Maße in logischen Pixeln (96 dpi).
  /// <summary>Höhe eines Bildes, solange es lädt, und Mindesthöhe danach.</summary>
  cImageLoadingHeight = 24;
  cMinImageHeight = 8;
  /// <summary>Höhe der Plakettenleiste ohne Plaketten.</summary>
  cEmptyBadgeHeight = 4;
  cBadgeRadius = 8;
  cBadgePadding = 6;
  cBadgeGap = 4;
  /// <summary>Zusätzliche Höhe einer Plakette über der Texthöhe.</summary>
  cBadgeExtraHeight = 4;
  /// <summary>Rand um das Bild im Bildfenster und Abstand des Fensters zum Rand des Arbeitsbereichs.</summary>
  cImageWindowExtraWidth = 40;
  cImageWindowExtraHeight = 60;
  cImageWindowScreenMargin = 80;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueImageBox }

constructor TAtlasIssueImageBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := ScaleValue(cImageLoadingHeight);
  Cursor := crHandPoint;
end;

destructor TAtlasIssueImageBox.Destroy;
begin
  FGraphic.Free;
  inherited;
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
    mText := TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssuePreviewImageLink, [FAlt]);
    Canvas.TextOut(0, ScaleValue(2), mText);
    Exit;
  end;
  mWidth := Min(FGraphic.Width, ClientWidth);
  mRect := Rect(0, 0, mWidth, ClientHeight);
  Canvas.StretchDraw(mRect, FGraphic);
end;

procedure TAtlasIssueImageBox.Resize;
begin
  inherited;
  Fit;
end;

procedure TAtlasIssueImageBox.Click;
begin
  inherited;
  if (FGraphic <> nil) and Assigned(FOnEnlarge) then
  begin
    FOnEnlarge(Self);
  end;
end;

procedure TAtlasIssueImageBox.Fit;
var
  mHeight: Integer;
begin
  if (FGraphic = nil) or (FGraphic.Width <= 0) or (ClientWidth <= 0) then
  begin
    Exit;
  end;
  // Höchstens Originalgröße, sonst Fensterbreite.
  mHeight := FGraphic.Height;
  if FGraphic.Width > ClientWidth then
  begin
    mHeight := MulDiv(FGraphic.Height, ClientWidth, FGraphic.Width);
  end;
  mHeight := Max(mHeight, ScaleValue(cMinImageHeight));
  if Height <> mHeight then
  begin
    Height := mHeight;
  end;
end;

procedure TAtlasIssueImageBox.SetGraphic(AGraphic: TGraphic);
begin
  FreeAndNil(FGraphic);
  FGraphic := AGraphic;
  Hint := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewImageHint);
  ShowHint := True;
  Fit;
  Invalidate;
end;

{ TAtlasIssueBadgeBar }

constructor TAtlasIssueBadgeBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FHintIndex := -1;
  ShowHint := True;
  Height := ScaleValue(cEmptyBadgeHeight);
end;

procedure TAtlasIssueBadgeBar.Paint;
var
  mIndex, mRadius: Integer;
  mRect: TRect;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  if Length(FRects) <> Length(FTexts) then
  begin
    Arrange;
  end;
  Canvas.Font := Font;
  mRadius := ScaleValue(cBadgeRadius);
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

procedure TAtlasIssueBadgeBar.Resize;
begin
  inherited;
  Arrange;
end;

procedure TAtlasIssueBadgeBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mIndex, mHit: Integer;
begin
  inherited;
  mHit := -1;
  for mIndex := 0 to High(FRects) do
  begin
    if FRects[mIndex].Contains(Point(X, Y)) then
    begin
      mHit := mIndex;
    end;
  end;
  if mHit = FHintIndex then
  begin
    Exit;
  end;
  FHintIndex := mHit;
  if (mHit >= 0) and (mHit <= High(FHints)) then
  begin
    Hint := FHints[mHit];
  end
  else
  begin
    Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasIssueBadgeBar.Arrange;
var
  mIndex, mX, mY, mWidth, mHeight, mPad, mGap: Integer;
begin
  FRects := nil;
  if not HandleAllocated then
  begin
    Height := ScaleValue(cEmptyBadgeHeight);
    Exit;
  end;
  Canvas.Font := Font;
  mPad := ScaleValue(cBadgePadding);
  mGap := ScaleValue(cBadgeGap);
  mHeight := Canvas.TextHeight('Wg') + ScaleValue(cBadgeExtraHeight);
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
  begin
    Height := ScaleValue(cEmptyBadgeHeight);
  end
  else if Height <> mY + mHeight + mGap then
  begin
    Height := mY + mHeight + mGap;
  end;
end;

procedure TAtlasIssueBadgeBar.SetBadges(const ATexts, AHints: TArray<string>; const AColors: TAtlasColors);
begin
  FTexts := ATexts;
  FHints := AHints;
  FColors := AColors;
  Arrange;
  Invalidate;
end;

{ TAtlasIssueSectionHead }

constructor TAtlasIssueSectionHead.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := ScaleValue(cHeight);
end;

procedure TAtlasIssueSectionHead.Paint;
var
  mRect: TRect;
  mText: string;
  mLineY: Integer;
begin
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Muted);
  mText := Caption;
  mRect := ClientRect;
  // Text unten bündig, damit der Abstand zum Abschnitt davor größer ist als zum eigenen Inhalt.
  mRect.Top := mRect.Bottom - Canvas.TextHeight('Wg') - MulDiv(2, CurrentPPI, 96);
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS or DT_CALCRECT);
  mRect.Right := Min(mRect.Right, ClientWidth);
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(mText), Length(mText), mRect,
    DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  mLineY := (mRect.Top + mRect.Bottom) div 2;
  if mRect.Right + MulDiv(cLineGap, CurrentPPI, 96) < ClientWidth then
  begin
    Canvas.Pen.Color := ToColor(FColors.Line);
    Canvas.Pen.Width := 1;
    Canvas.MoveTo(mRect.Right + MulDiv(cLineGap, CurrentPPI, 96), mLineY);
    Canvas.LineTo(ClientWidth, mLineY);
  end;
end;

procedure TAtlasIssueSectionHead.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

{ TAtlasIssueStack }

/// <summary>Abstand von AControl zu seinen Nachbarn: Margins nur mit AlignWithMargins.</summary>
function ItemMargins(AControl: TControl): TRect;
begin
  Result := TRect.Empty;
  if AControl.AlignWithMargins then
  begin
    Result := TRect.Create(AControl.Margins.Left, AControl.Margins.Top, AControl.Margins.Right,
      AControl.Margins.Bottom);
  end;
end;

constructor TAtlasIssueStack.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList<TControl>.Create;
  ControlStyle := ControlStyle + [csAcceptsControls];
  Height := 0;
end;

destructor TAtlasIssueStack.Destroy;
begin
  // Die VCL hängt die Teile in inherited aus: dann nichts mehr merken.
  FreeAndNil(FItems);
  inherited;
end;

procedure TAtlasIssueStack.CMControlListChange(var AMessage: TCMControlListChange);
begin
  inherited;
  if FItems = nil then
  begin
    Exit;
  end;
  if AMessage.Inserting then
  begin
    FItems.Add(AMessage.Control);
  end
  else
  begin
    FItems.Remove(AMessage.Control);
  end;
end;

procedure TAtlasIssueStack.AlignControls(AControl: TControl; var Rect: TRect);
var
  mItem: TControl;
  mMargins: TRect;
  mTop, mHeight: Integer;
begin
  AdjustClientRect(Rect);
  mTop := Rect.Top;
  for mItem in FItems do
  begin
    if not mItem.Visible then
    begin
      Continue;
    end;
    mMargins := ItemMargins(mItem);
    mItem.SetBounds(Rect.Left + mMargins.Left, mTop + mMargins.Top,
      Max(0, Rect.Width - mMargins.Left - mMargins.Right), mItem.Height);
    // Ohne Fenster richtet eine Karte bei neuer Breite nicht selbst aus.
    if (mItem is TAtlasIssueStack) and not TAtlasIssueStack(mItem).HandleAllocated then
    begin
      TAtlasIssueStack(mItem).Arrange;
    end;
    // Die Höhe erst nach der Breite lesen: Das Teil rechnet sie in Resize aus der Breite.
    mTop := mItem.Top + mItem.Height + mMargins.Bottom;
  end;
  mHeight := mTop + Padding.Bottom + Height - ClientHeight;
  if Height <> mHeight then
  begin
    Height := mHeight;
  end;
end;

procedure TAtlasIssueStack.Arrange;
var
  mRect: TRect;
begin
  DisableAlign;
  try
    mRect := ClientRect;
    AlignControls(nil, mRect);
  finally
    EnableAlign;
  end;
end;

procedure TAtlasIssueStack.CreateWnd;
begin
  inherited;
  // Teile, die ohne Fenster eingehängt wurden, stehen noch alle oben.
  Realign;
end;

procedure TAtlasIssueStack.Paint;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
end;

{ TAtlasIssueCard }

constructor TAtlasIssueCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFill := TAtlasColors.Light.Surface;
  FBorder := TAtlasColors.Light.Line;
  ParentColor := False;
  ParentBackground := False;
  Padding.SetBounds(ScaleValue(cPadSide), ScaleValue(cPadEnd), ScaleValue(cPadSide), ScaleValue(cPadEnd));
end;

procedure TAtlasIssueCard.Paint;
begin
  // Fläche in Color (= Füllfarbe, SetColors), darüber der Rahmen.
  inherited;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FBorder);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasIssueCard.SetColors(AFill, ABorder: TAtlasColor);
begin
  FFill := AFill;
  FBorder := ABorder;
  Color := ToColor(AFill);
  Invalidate;
end;

{ TAtlasIssueImageWindow }

procedure TAtlasIssueImageWindow.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action := caFree;
end;

class procedure TAtlasIssueImageWindow.Enlarge(ASource: TAtlasIssueImageBox);
var
  mForm: TAtlasIssueImageWindow;
  mBox: TScrollBox;
  mImage: TImage;
  mSource: TAtlasIssueImageBox;
begin
  mSource := ASource;
  if (mSource = nil) or (mSource.Graphic = nil) then
  begin
    Exit;
  end;
  // TAtlasDialog: IDE-Thema; die Größe setzt das Fenster unten nach dem Bild.
  mForm := TAtlasIssueImageWindow.CreateDialog(nil, mSource.Alt, 0);
  mForm.BorderStyle := bsSizeable;
  mForm.Position := poScreenCenter;
  mForm.Width := Min(mSource.Graphic.Width + mForm.ScaleValue(cImageWindowExtraWidth),
    Screen.WorkAreaWidth - mForm.ScaleValue(cImageWindowScreenMargin));
  mForm.Height := Min(mSource.Graphic.Height + mForm.ScaleValue(cImageWindowExtraHeight),
    Screen.WorkAreaHeight - mForm.ScaleValue(cImageWindowScreenMargin));
  mBox := TScrollBox.Create(mForm);
  mBox.Parent := mForm;
  mBox.Align := alClient;
  mImage := TImage.Create(mForm);
  mImage.Parent := mBox;
  mImage.AutoSize := True;
  mImage.Picture.Assign(mSource.Graphic);
  mForm.Show;
end;

{ TAtlasIssueLinkText }

class function TAtlasIssueLinkText.Row(const ALink: TAtlasTrackerLink): string;
var
  mSymbol, mState: string;
begin
  case TAtlasTrackerLinks.Mark(ALink) of
    TAtlasTrackerLinkMark.Done:
      mSymbol := '✓';
    TAtlasTrackerLinkMark.Open:
      mSymbol := '○';
    TAtlasTrackerLinkMark.Blocking:
      mSymbol := '⛔';
  else
    mSymbol := '?';
  end;
  // Zustand wie im Tracker, sonst offen bzw. erledigt; dazu, ob es dieses Issue blockiert.
  if not ALink.StateKnown then
  begin
    mState := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinksUnknown);
  end
  else if ALink.State <> '' then
  begin
    mState := ALink.State;
  end
  else if ALink.Resolved then
  begin
    mState := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinksDone);
  end
  else
  begin
    mState := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinksOpen);
  end;
  if ALink.Blocking then
  begin
    mState := mState + ' · ' + TAtlasIssueStrings.Text(TAtlasIssueTextId.IssueLinksBlocking);
  end;
  Result := mSymbol + '  ' + ALink.Key;
  if ALink.Title <> '' then
  begin
    Result := Result + '  ' + ALink.Title;
  end;
  Result := Result + '  — ' + mState;
end;

class function TAtlasIssueLinkText.Group(const AGroup: TAtlasTrackerLinkGroup): string;
var
  mId: TAtlasIssueTextId;
begin
  if AGroup.Kind = TAtlasTrackerLinkKind.Subtask then
  begin
    Exit(TAtlasIssueStrings.Fmt(TAtlasIssueTextId.IssueLinksSubtasks, [TAtlasTrackerLinks.ProgressText(AGroup.Done,
      AGroup.Total)]));
  end;
  case AGroup.Kind of
    TAtlasTrackerLinkKind.DependsOn:
      mId := TAtlasIssueTextId.IssueLinksDependsOn;
    TAtlasTrackerLinkKind.Blocks:
      mId := TAtlasIssueTextId.IssueLinksBlocks;
    TAtlasTrackerLinkKind.Parent:
      mId := TAtlasIssueTextId.IssueLinksParent;
    TAtlasTrackerLinkKind.Duplicates:
      mId := TAtlasIssueTextId.IssueLinksDuplicates;
    TAtlasTrackerLinkKind.DuplicatedBy:
      mId := TAtlasIssueTextId.IssueLinksDuplicatedBy;
    TAtlasTrackerLinkKind.Relates:
      mId := TAtlasIssueTextId.IssueLinksRelates;
    TAtlasTrackerLinkKind.Mentioned:
      mId := TAtlasIssueTextId.IssueLinksMentioned;
    TAtlasTrackerLinkKind.PullRequest:
      mId := TAtlasIssueTextId.IssueLinksPulls;
  else
    mId := TAtlasIssueTextId.IssueLinksOther;
  end;
  Result := TAtlasIssueStrings.Text(mId) + ' (' + IntToStr(AGroup.Total) + ')';
end;

class function TAtlasIssueLinkText.HasGroups(const ALinks: TArray<TAtlasTrackerLink>): Boolean;
begin
  Result := Length(TAtlasTrackerLinks.Groups(ALinks)) > 0;
end;

class procedure TAtlasIssueLinkText.FillTree(ATree: TTreeView; const ALinks: TArray<TAtlasTrackerLink>;
  var ATreeLinks: TArray<TAtlasTrackerLink>);
var
  mGroup: TAtlasTrackerLinkGroup;
  mLink: TAtlasTrackerLink;
  mNode, mChild: TTreeNode;
begin
  ATree.Items.BeginUpdate;
  try
    for mGroup in TAtlasTrackerLinks.Groups(ALinks) do
    begin
      mNode := ATree.Items.AddChild(nil, Group(mGroup));
      mNode.Data := nil;
      for mLink in mGroup.Links do
      begin
        ATreeLinks := ATreeLinks + [mLink];
        mChild := ATree.Items.AddChild(mNode, Row(mLink));
        mChild.Data := Pointer(NativeInt(Length(ATreeLinks)));
      end;
      mNode.Expanded := not mGroup.Collapsed;
    end;
  finally
    ATree.Items.EndUpdate;
  end;
end;

{ TAtlasIssueTimeText }

class function TAtlasIssueTimeText.Age(ATime, ANow: TDateTime): string;
begin
  Result := TAtlasIssueTip.AgeText(ATime, ANow);
end;

class function TAtlasIssueTimeText.Absolute(ATime: TDateTime): string;
begin
  Result := '';
  if ATime > 0 then
  begin
    Result := FormatDateTime('dd.mm.yyyy hh:nn', TTimeZone.Local.ToLocalTime(ATime), FormatSettings);
  end;
end;

end.
