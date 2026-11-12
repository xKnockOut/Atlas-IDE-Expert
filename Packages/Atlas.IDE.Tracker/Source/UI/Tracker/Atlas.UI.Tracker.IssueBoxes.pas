unit Atlas.UI.Tracker.IssueBoxes;

// Bausteine des Fensters „Atlas-Issue“ (#1264), reine VCL ohne Open Tools API:
// Bild in Fensterbreite (Klick vergrößert in einem eigenen Fenster), Felder
// als Abzeichen mit Tooltip und die Texte des Verknüpfungsbaums (#1279).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Links;

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

  /// <summary>Abgesetzte Fläche mit Rahmen (Kopf des Issues, ein Kommentar); wächst mit ihrem Inhalt.
  /// Die Kinder erben die Füllfarbe über Color.</summary>
  TAtlasIssueCard = class(TCustomControl)
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
  TAtlasIssueImageWindow = class(TForm)
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
  Atlas.Core.Style.Color,
  Vcl.ExtCtrls,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.IssueTip;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasIssueImageBox }

constructor TAtlasIssueImageBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := ScaleValue(24);
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
  Hint := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuePreviewImageHint);
  ShowHint := True;
  Fit;
  Invalidate;
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
  mHeight := Max(mHeight, 8);
  if Height <> mHeight then
  begin
    Height := mHeight;
  end;
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
    mText := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewImageLink, [FAlt]);
    Canvas.TextOut(0, ScaleValue(2), mText);
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
  begin
    FOnEnlarge(Self);
  end;
end;

{ TAtlasIssueBadgeBar }

constructor TAtlasIssueBadgeBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FHintIndex := -1;
  ShowHint := True;
  Height := ScaleValue(4);
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
    Height := ScaleValue(4);
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
  begin
    Height := ScaleValue(4);
  end
  else if Height <> mY + mHeight + mGap then
  begin
    Height := mY + mHeight + mGap;
  end;
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
  begin
    Arrange;
  end;
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

{ TAtlasIssueSectionHead }

constructor TAtlasIssueSectionHead.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  Height := ScaleValue(cHeight);
end;

procedure TAtlasIssueSectionHead.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
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

{ TAtlasIssueCard }

constructor TAtlasIssueCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFill := TAtlasColors.Light.Surface;
  FBorder := TAtlasColors.Light.Line;
  ParentColor := False;
  ParentBackground := False;
  AutoSize := True;
  Padding.SetBounds(ScaleValue(cPadSide), ScaleValue(cPadEnd), ScaleValue(cPadSide), ScaleValue(cPadEnd));
end;

procedure TAtlasIssueCard.SetColors(AFill, ABorder: TAtlasColor);
begin
  FFill := AFill;
  FBorder := ABorder;
  Color := ToColor(AFill);
  Invalidate;
end;

procedure TAtlasIssueCard.Paint;
begin
  Canvas.Brush.Color := ToColor(FFill);
  Canvas.Pen.Color := ToColor(FBorder);
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(ClientRect);
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
  mForm := TAtlasIssueImageWindow.CreateNew(nil);
  mForm.Caption := mSource.Alt;
  mForm.Position := poScreenCenter;
  mForm.Width := Min(mSource.Graphic.Width + mForm.ScaleValue(40), Screen.WorkAreaWidth - mForm.ScaleValue(80));
  mForm.Height := Min(mSource.Graphic.Height + mForm.ScaleValue(60), Screen.WorkAreaHeight - mForm.ScaleValue(80));
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
    mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinksUnknown);
  end
  else if ALink.State <> '' then
  begin
    mState := ALink.State;
  end
  else if ALink.Resolved then
  begin
    mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinksDone);
  end
  else
  begin
    mState := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinksOpen);
  end;
  if ALink.Blocking then
  begin
    mState := mState + ' · ' + TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueLinksBlocking);
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
  mId: TAtlasTrackerTextId;
begin
  if AGroup.Kind = TAtlasTrackerLinkKind.Subtask then
  begin
    Exit(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueLinksSubtasks, [TAtlasTrackerLinks.ProgressText(AGroup.Done,
      AGroup.Total)]));
  end;
  case AGroup.Kind of
    TAtlasTrackerLinkKind.DependsOn:
      mId := TAtlasTrackerTextId.IssueLinksDependsOn;
    TAtlasTrackerLinkKind.Blocks:
      mId := TAtlasTrackerTextId.IssueLinksBlocks;
    TAtlasTrackerLinkKind.Parent:
      mId := TAtlasTrackerTextId.IssueLinksParent;
    TAtlasTrackerLinkKind.Duplicates:
      mId := TAtlasTrackerTextId.IssueLinksDuplicates;
    TAtlasTrackerLinkKind.DuplicatedBy:
      mId := TAtlasTrackerTextId.IssueLinksDuplicatedBy;
    TAtlasTrackerLinkKind.Relates:
      mId := TAtlasTrackerTextId.IssueLinksRelates;
    TAtlasTrackerLinkKind.Mentioned:
      mId := TAtlasTrackerTextId.IssueLinksMentioned;
    TAtlasTrackerLinkKind.PullRequest:
      mId := TAtlasTrackerTextId.IssueLinksPulls;
  else
    mId := TAtlasTrackerTextId.IssueLinksOther;
  end;
  Result := TAtlasTrackerStrings.Text(mId) + ' (' + IntToStr(AGroup.Total) + ')';
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
