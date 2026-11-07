unit Atlas.UI.Welcome.Discover;

// Karte „Atlas entdecken“ der Willkommensseite (#757), ohne Open Tools API:
//   ┌──────────────────┐
//   │       Bild       │  (schmale Spalte: Bild oben, so breit wie möglich)
//   └──────────────────┘
//   Code-Aktionen  Alt+Enter
//   Ein bis zwei Sätze, was die Funktion tut.
//   Noch nie benutzt                     Tipp 2 von 7
//   [Ausprobieren] [Nächster Tipp] [Nicht mehr zeigen]
// Breite Spalte (Platz für Bild und MinTextWidth): Bild links, Text daneben.
// Ein Tipp je IDE-Start; Bild (PNG aus dem Installationsordner, sonst ohne),
// Titel, tatsächliche Belegung des Befehls, Text und Hinweis zur Nutzung
// („Noch nie benutzt“, „Zuletzt vor 3 Wochen“; ohne Zählung keiner).
// Bildgröße: ImageWidth × ImageHeight logische Pixel, also bei 100 % genau
// die Pixel der einfachen Datei (scharf, Text im Bild lesbar). Wird das Bild
// breiter gezeigt (ab 125 %), kommt die Datei mit @2x
// (TAtlasTipCatalog.ImageFor). Weicht die Anzeigegröße von der Datei ab,
// rechnet RenderImage das Bild einmal mit HALFTONE auf die Größe um (die
// Standard-Streckung der GDI ließe helle Schrift auf dunklem Grund
// ausfallen); neu bei jedem Anordnen mit anderer Größe, also auch nach einem
// Monitorwechsel. Schmaler als das Bild: kleiner mit gleichem
// Seitenverhältnis. Ein Bild für helles und dunkles Thema (eigener dunkler
// Editor-Grund mit grauem Rahmen).
// „Nächster Tipp“ nur, wenn es mehr als einen gibt; „Ausprobieren“ nur mit
// Beispieldatei oder vorhandenem Befehl.
// Daten und Aktionen kommen über IAtlasDiscoverSource aus der IDE-Schicht.
// Klicks rufen die Quelle über die Nachrichtenschleife auf: Die Quelle baut
// die Karte daraufhin neu, und ein Knopf darf nicht in seinem eigenen Klick
// verschwinden.

interface

uses
  Winapi.Windows,
  // Vor Vcl.Graphics: sonst verdeckt Winapi.Windows.TBitmap die VCL-Klasse.
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Commands.Tips,
  Atlas.Core.Welcome.Discover,
  Atlas.UI.Welcome.Frame;

type
{$SCOPEDENUMS ON}
  TAtlasDiscoverButton = (TryIt, Next, Block);
{$SCOPEDENUMS OFF}

  IAtlasDiscoverSource = interface
    ['{3E7C9A14-5B2D-4F86-A1C0-8D6E2F4B7A93}']
    /// <summary>Der Tipp, den die Karte gerade zeigt; False ohne Tipp.</summary>
    function Card(out ACard: TAtlasDiscoverCard): Boolean;
    /// <summary>„Ausprobieren“: Befehl ausführen oder Beispieldatei öffnen.</summary>
    procedure TryTip(const AId: string);
    /// <summary>„Nächster Tipp“.</summary>
    procedure NextTip(const AId: string);
    /// <summary>„Nicht mehr zeigen“: Tipp dauerhaft sperren.</summary>
    procedure BlockTip(const AId: string);
  end;

  /// <summary>Texte der Karte „Atlas entdecken“, ohne Steuerelement.</summary>
  TAtlasDiscoverTexts = class
  public
    /// <summary>„Atlas entdecken“ in der Sprache der IDE.</summary>
    class function TitleText: string; static;
    /// <summary>„Noch nie benutzt“, „Zuletzt vor 3 Wochen“ …; '' ohne Hinweis.</summary>
    class function AgeText(const AAge: TAtlasDiscoverAge): string; static;
    /// <summary>„Tipp 2 von 7“; '' bei höchstens einem Tipp.</summary>
    class function PositionText(APosition, ACount: Integer): string; static;
    class function ButtonCaption(AButton: TAtlasDiscoverButton): string; static;
  end;

  /// <summary>Bild der Karte: hält die geladene Datei in ihrer eigenen Größe und zeigt sie in einem TImage auf die
  /// Anzeigegröße gerechnet.</summary>
  TAtlasDiscoverPicture = class
  private
    FImage: TImage;
    FFileName: string;
    FOriginal: TPicture;
    FShownWidth: Integer;
    FShownHeight: Integer;
  public
    /// <summary>AImage gehört dem Aufrufer.</summary>
    constructor Create(AImage: TImage);
    destructor Destroy; override;
    /// <summary>Datei laden, wenn sie sich geändert hat; '' oder fehlende bzw. kaputte Datei = kein Bild.</summary>
    procedure Load(const AFileName: string);
    function HasImage: Boolean;
    /// <summary>Das TImage zeigt das Bild in AWidth × AHeight Pixeln; ohne Umrechnung bei gleicher Größe.</summary>
    procedure Render(AWidth, AHeight: Integer);
  end;

  TAtlasWelcomeDiscoverFrame = class(TAtlasWelcomeSectionFrame)
  public const
    cIndent = 8;
    cGap = 8;
    cImageWidth = TAtlasTipCatalog.cImageWidth;
    cImageHeight = TAtlasTipCatalog.cImageHeight;
    /// <summary>Text neben dem Bild erst ab dieser Breite; sonst steht das Bild darüber.</summary>
    cMinTextWidth = 220;
    cButtonHeight = 24;
    cButtonPadding = 16;
  private
    FSource: IAtlasDiscoverSource;
    FCard: TAtlasDiscoverCard;
    FHasCard: Boolean;
    FImage: TImage;
    FPicture: TAtlasDiscoverPicture;
    FTitleLabel: TLabel;
    FKey: TLabel;
    FText: TLabel;
    FAge: TLabel;
    FPosition: TLabel;
    FEmpty: TLabel;
    FButtons: array[TAtlasDiscoverButton] of TButton;
    FContentHeight: Integer;
    FArranging: Boolean;
    procedure SetSource(const AValue: IAtlasDiscoverSource);
    procedure Arrange;
    /// <summary>Bild für die Spalte ALeft..ARight; setzt den Beginn des Texts und die Unterkante des Bilds.</summary>
    procedure ArrangeImage(ALeft, ARight: Integer; var ATop, ATextLeft, ABottom: Integer);
    /// <summary>Titel, Kürzel, Text, Alter und Stelle ab ATop; liefert die Unterkante.</summary>
    function ArrangeTexts(ATextLeft, ARight, ATop: Integer): Integer;
    /// <summary>Knöpfe ab ATop, bei zu wenig Breite in weiteren Reihen; liefert die Höhe des Inhalts.</summary>
    function ArrangeButtons(ALeft, ARight, ATop: Integer): Integer;
    procedure BodyResize(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure UpdateContent; override;
    /// <summary>Klick auf einen Knopf wie mit der Maus (auch für Tests).</summary>
    procedure ClickButton(AButton: TAtlasDiscoverButton);
    function Button(AButton: TAtlasDiscoverButton): TButton;
    property Source: IAtlasDiscoverSource read FSource write SetSource;
    property Card: TAtlasDiscoverCard read FCard;
    property HasCard: Boolean read FHasCard;
    property Image: TImage read FImage;
    property TipTitle: TLabel read FTitleLabel;
    property KeyLabel: TLabel read FKey;
    property TextLabel: TLabel read FText;
    property AgeLabel: TLabel read FAge;
    property PositionLabel: TLabel read FPosition;
    property EmptyLabel: TLabel read FEmpty;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Vcl.Imaging.pngimage,
  Atlas.UI.Welcome.Strings;

{ TAtlasDiscoverPicture }

constructor TAtlasDiscoverPicture.Create(AImage: TImage);
begin
  inherited Create;
  FImage := AImage;
  FOriginal := TPicture.Create;
end;

destructor TAtlasDiscoverPicture.Destroy;
begin
  FOriginal.Free;
  inherited;
end;

procedure TAtlasDiscoverPicture.Load(const AFileName: string);
begin
  if SameFileName(AFileName, FFileName) then
  begin
    Exit;
  end;
  FFileName := AFileName;
  FOriginal.Assign(nil);
  FImage.Picture.Assign(nil);
  FShownWidth := 0;
  FShownHeight := 0;
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    FOriginal.LoadFromFile(AFileName);
  except
    // Kaputtes Bild: Karte ohne Bild.
    on Exception do
      FOriginal.Assign(nil);
  end;
end;

function TAtlasDiscoverPicture.HasImage: Boolean;
begin
  Result := (FOriginal.Graphic <> nil) and not FOriginal.Graphic.Empty;
end;

procedure TAtlasDiscoverPicture.Render(AWidth, AHeight: Integer);
var
  mNative, mScaled: TBitmap;
begin
  if not HasImage or ((AWidth = FShownWidth) and (AHeight = FShownHeight)) then
  begin
    Exit;
  end;
  FShownWidth := AWidth;
  FShownHeight := AHeight;
  mNative := TBitmap.Create;
  mScaled := TBitmap.Create;
  try
    mNative.PixelFormat := pf24bit;
    mNative.SetSize(FOriginal.Width, FOriginal.Height);
    mNative.Canvas.Draw(0, 0, FOriginal.Graphic);
    mScaled.PixelFormat := pf24bit;
    mScaled.SetSize(AWidth, AHeight);
    if (AWidth = mNative.Width) and (AHeight = mNative.Height) then
    begin
      mScaled.Canvas.Draw(0, 0, mNative);
    end
    else
    begin
      // HALFTONE mittelt die Pixel; die Vorgabe der GDI ließe dünne helle Schrift ausfallen.
      SetStretchBltMode(mScaled.Canvas.Handle, HALFTONE);
      SetBrushOrgEx(mScaled.Canvas.Handle, 0, 0, nil);
      StretchBlt(mScaled.Canvas.Handle, 0, 0, AWidth, AHeight, mNative.Canvas.Handle, 0, 0, mNative.Width,
        mNative.Height, SRCCOPY);
    end;
    FImage.Picture.Assign(mScaled);
  finally
    mScaled.Free;
    mNative.Free;
  end;
end;

{ TAtlasWelcomeDiscoverFrame }

constructor TAtlasWelcomeDiscoverFrame.Create(AOwner: TComponent);
var
  mKind: TAtlasDiscoverButton;

  function NewLabel: TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Body;
    Result.ShowAccelChar := False;
  end;

begin
  inherited Create(AOwner);
  FImage := TImage.Create(Self);
  FImage.Parent := Body;
  // FPicture.Render liefert das Bild schon in der Größe von FImage.
  FImage.Stretch := False;
  FImage.Visible := False;
  FPicture := TAtlasDiscoverPicture.Create(FImage);
  FTitleLabel := NewLabel;
  FTitleLabel.Font.Style := [fsBold];
  FKey := NewLabel;
  FKey.Font.Color := clGrayText;
  FText := NewLabel;
  FText.WordWrap := True;
  FAge := NewLabel;
  FAge.Font.Color := clGrayText;
  FPosition := NewLabel;
  FPosition.Font.Color := clGrayText;
  FEmpty := NewLabel;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverEmpty);
  for mKind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
  begin
    FButtons[mKind] := TButton.Create(Self);
    FButtons[mKind].Parent := Body;
    FButtons[mKind].Caption := TAtlasDiscoverTexts.ButtonCaption(mKind);
    FButtons[mKind].Tag := Ord(mKind);
    FButtons[mKind].OnClick := ButtonClick;
  end;
  Body.OnResize := BodyResize;
  UpdateContent;
end;

destructor TAtlasWelcomeDiscoverFrame.Destroy;
begin
  FPicture.Free;
  inherited;
end;

{ TAtlasDiscoverTexts }

class function TAtlasDiscoverTexts.TitleText: string;
begin
  Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverTitle);
end;

class function TAtlasDiscoverTexts.AgeText(const AAge: TAtlasDiscoverAge): string;
begin
  case AAge.Kind of
    TAtlasDiscoverAgeKind.Never:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverNever);
    TAtlasDiscoverAgeKind.Today:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverToday);
    TAtlasDiscoverAgeKind.Yesterday:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverYesterday);
    TAtlasDiscoverAgeKind.Days:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverDays, [AAge.Count]);
    TAtlasDiscoverAgeKind.Weeks:
      if AAge.Count = 1 then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverWeek);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverWeeks, [AAge.Count]);
      end;
    TAtlasDiscoverAgeKind.Months:
      if AAge.Count = 1 then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverMonth);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverMonths, [AAge.Count]);
      end;
    TAtlasDiscoverAgeKind.Years:
      if AAge.Count = 1 then
      begin
        Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverYear);
      end
      else
      begin
        Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverYears, [AAge.Count]);
      end;
  else
    Result := '';
  end;
end;

class function TAtlasDiscoverTexts.PositionText(APosition, ACount: Integer): string;
begin
  Result := '';
  if (ACount > 1) and (APosition > 0) then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeDiscoverPosition, [APosition, ACount]);
  end;
end;

class function TAtlasDiscoverTexts.ButtonCaption(AButton: TAtlasDiscoverButton): string;
begin
  case AButton of
    TAtlasDiscoverButton.TryIt:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverTry);
    TAtlasDiscoverButton.Next:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverNext);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeDiscoverBlock);
  end;
end;

function TAtlasWelcomeDiscoverFrame.Button(AButton: TAtlasDiscoverButton): TButton;
begin
  Result := FButtons[AButton];
end;

procedure TAtlasWelcomeDiscoverFrame.SetSource(const AValue: IAtlasDiscoverSource);
begin
  FSource := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeDiscoverFrame.UpdateContent;
var
  mKind: TAtlasDiscoverButton;
  mOldHeight: Integer;
begin
  // Ohne Fenster später: Die Tafel ruft UpdateContent nach dem Einhängen.
  if not HasWindow then
  begin
    Exit;
  end;
  mOldHeight := FContentHeight;
  FCard := Default(TAtlasDiscoverCard);
  FHasCard := (FSource <> nil) and FSource.Card(FCard);
  if not FHasCard then
  begin
    FCard := Default(TAtlasDiscoverCard);
  end;
  FTitleLabel.Caption := FCard.Title;
  FKey.Caption := FCard.KeyText;
  FText.Caption := FCard.Text;
  FAge.Caption := TAtlasDiscoverTexts.AgeText(FCard.Age);
  FPosition.Caption := TAtlasDiscoverTexts.PositionText(FCard.Position, FCard.Count);
  FTitleLabel.Visible := FHasCard;
  FKey.Visible := FHasCard and (FCard.KeyText <> '');
  FText.Visible := FHasCard and (FCard.Text <> '');
  FAge.Visible := FHasCard and (FAge.Caption <> '');
  FPosition.Visible := FHasCard and (FPosition.Caption <> '');
  FEmpty.Visible := not FHasCard;
  for mKind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
  begin
    FButtons[mKind].Visible := FHasCard;
  end;
  FButtons[TAtlasDiscoverButton.TryIt].Enabled := FCard.CanTry;
  FButtons[TAtlasDiscoverButton.Next].Enabled := FCard.Count > 1;
  Arrange;
  inherited;
  if mOldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeDiscoverFrame.BodyResize(Sender: TObject);
var
  mOldHeight: Integer;
begin
  mOldHeight := FContentHeight;
  Arrange;
  // Anderer Umbruch bei neuer Breite: Der Frame „Atlas“ ordnet die Spalten neu.
  if mOldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasWelcomeDiscoverFrame.Arrange;
var
  mLeft, mRight, mTop, mTextLeft, mBottom: Integer;
begin
  if FArranging or (FTitleLabel = nil) then
  begin
    Exit;
  end;
  FArranging := True;
  try
    // Breite des Frames statt der Inhaltsfläche: Die richtet sich erst später nach dem Frame aus.
    mLeft := ScaleValue(cIndent);
    mRight := ClientWidth - ScaleValue(cIndent);
    mTop := ScaleValue(cGap) div 2;
    if not FHasCard then
    begin
      FImage.Visible := False;
      FEmpty.SetBounds(mLeft, mTop, FEmpty.Width, FEmpty.Height);
      FContentHeight := FEmpty.Top + FEmpty.Height + ScaleValue(cGap);
      Exit;
    end;
    mTextLeft := mLeft;
    mBottom := mTop;
    ArrangeImage(mLeft, mRight, mTop, mTextLeft, mBottom);
    mTop := ArrangeTexts(mTextLeft, mRight, mTop);
    FContentHeight := ArrangeButtons(mLeft, mRight, Max(mTop, mBottom) + ScaleValue(cGap));
  finally
    FArranging := False;
  end;
end;

procedure TAtlasWelcomeDiscoverFrame.ArrangeImage(ALeft, ARight: Integer; var ATop, ATextLeft, ABottom: Integer);
var
  mShownWidth, mShownHeight: Integer;
begin
  // Bild in voller Größe, solange die Spalte reicht, sonst kleiner mit gleichem Seitenverhältnis; die Datei
  // passend zur Breite (nach einem Monitorwechsel neu).
  mShownWidth := Max(Min(ARight - ALeft, ScaleValue(cImageWidth)), 1);
  mShownHeight := Max(mShownWidth * cImageHeight div cImageWidth, 1);
  FPicture.Load(TAtlasTipCatalog.ImageFor(FCard.ImageFile, mShownWidth));
  FImage.Visible := FHasCard and FPicture.HasImage;
  if not FImage.Visible then
  begin
    Exit;
  end;
  FImage.SetBounds(ALeft, ATop, mShownWidth, mShownHeight);
  FPicture.Render(mShownWidth, mShownHeight);
  if ARight - ALeft >= ScaleValue(cImageWidth) + ScaleValue(cGap) + ScaleValue(cMinTextWidth) then
  begin
    // Breit: Text neben dem Bild.
    ATextLeft := ALeft + mShownWidth + ScaleValue(cGap);
    ABottom := FImage.Top + FImage.Height;
  end
  else
  begin
    // Schmal: Text unter dem Bild.
    ATop := FImage.Top + FImage.Height + ScaleValue(cGap);
    ABottom := ATop;
  end;
end;

function TAtlasWelcomeDiscoverFrame.ArrangeTexts(ATextLeft, ARight, ATop: Integer): Integer;
begin
  FTitleLabel.SetBounds(ATextLeft, ATop, FTitleLabel.Width, FTitleLabel.Height);
  Result := FTitleLabel.Top + FTitleLabel.Height;
  // Kürzel neben dem Titel, sonst darunter.
  if FKey.Visible and (FTitleLabel.Left + FTitleLabel.Width + ScaleValue(cGap) + FKey.Width <= ARight) then
  begin
    FKey.SetBounds(FTitleLabel.Left + FTitleLabel.Width + ScaleValue(cGap), FTitleLabel.Top, FKey.Width, FKey.Height);
  end
  else if FKey.Visible then
  begin
    FKey.SetBounds(ATextLeft, Result, FKey.Width, FKey.Height);
    Result := FKey.Top + FKey.Height;
  end;
  if FText.Visible then
  begin
    // Breite zuerst: Das Label bricht danach um und passt seine Höhe an.
    FText.Width := Max(ARight - ATextLeft, ScaleValue(80));
    // AutoSize neu setzen: Erst das misst den umbrochenen Text für die neue Breite.
    FText.AutoSize := False;
    FText.AutoSize := True;
    FText.Left := ATextLeft;
    FText.Top := Result + 2;
    Result := FText.Top + FText.Height;
  end;
  if FAge.Visible or FPosition.Visible then
  begin
    Inc(Result, 2);
    FAge.SetBounds(ATextLeft, Result, FAge.Width, FAge.Height);
    FPosition.SetBounds(Max(ATextLeft, ARight - FPosition.Width), Result, FPosition.Width, FPosition.Height);
    Inc(Result, Max(FAge.Height, FPosition.Height));
  end;
end;

function TAtlasWelcomeDiscoverFrame.ArrangeButtons(ALeft, ARight, ATop: Integer): Integer;
var
  mKind: TAtlasDiscoverButton;
  mMeasure: TBitmap;
  mButtonLeft, mButtonTop, mButtonWidth: Integer;
begin
  mButtonLeft := ALeft;
  mButtonTop := ATop;
  mMeasure := TBitmap.Create;
  try
    mMeasure.Canvas.Font.Assign(Font);
    for mKind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
    begin
      mButtonWidth := mMeasure.Canvas.TextWidth(FButtons[mKind].Caption) + 2 * ScaleValue(cButtonPadding);
      if (mButtonLeft > ALeft) and (mButtonLeft + mButtonWidth > ARight) then
      begin
        mButtonLeft := ALeft;
        Inc(mButtonTop, ScaleValue(cButtonHeight) + ScaleValue(cGap) div 2);
      end;
      FButtons[mKind].SetBounds(mButtonLeft, mButtonTop, mButtonWidth, ScaleValue(cButtonHeight));
      Inc(mButtonLeft, mButtonWidth + ScaleValue(cGap) div 2);
    end;
  finally
    mMeasure.Free;
  end;
  Result := mButtonTop + ScaleValue(cButtonHeight) + ScaleValue(cGap) div 2;
end;

function TAtlasWelcomeDiscoverFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  Arrange;
  Result := Max(FContentHeight, ScaleValue(40));
end;

procedure TAtlasWelcomeDiscoverFrame.ClickButton(AButton: TAtlasDiscoverButton);
var
  mSource: IAtlasDiscoverSource;
  mId: string;
begin
  if (FSource = nil) or not FHasCard or not FButtons[AButton].Enabled then
  begin
    Exit;
  end;
  mSource := FSource;
  mId := FCard.Id;
  // Die Quelle baut die Karte neu: nicht im Klick des Knopfs.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      case AButton of
        TAtlasDiscoverButton.TryIt:
          mSource.TryTip(mId);
        TAtlasDiscoverButton.Next:
          mSource.NextTip(mId);
      else
        mSource.BlockTip(mId);
      end;
    end);
end;

procedure TAtlasWelcomeDiscoverFrame.ButtonClick(Sender: TObject);
begin
  ClickButton(TAtlasDiscoverButton((Sender as TButton).Tag));
end;

end.
