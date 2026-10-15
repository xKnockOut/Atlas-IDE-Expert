unit Atlas.UI.Welcome.Discover;

// Karte „Atlas entdecken“ der Willkommensseite (#757), ohne Open Tools API:
//   ┌────────┐ Code-Aktionen  Strg+.
//   │  Bild  │ Ein bis zwei Sätze, was die Funktion tut.
//   └────────┘ Noch nie benutzt                     Tipp 2 von 7
//   [Ausprobieren] [Nächster Tipp] [Nicht mehr zeigen]
// Ein Tipp je IDE-Start; Bild (PNG aus dem Installationsordner, sonst ohne),
// Titel, tatsächliche Belegung des Befehls, Text und Hinweis zur Nutzung
// („Noch nie benutzt“, „Zuletzt vor 3 Wochen“; ohne Zählung keiner).
// „Nächster Tipp“ nur, wenn es mehr als einen gibt; „Ausprobieren“ nur mit
// Beispieldatei oder vorhandenem Befehl.
// Daten und Aktionen kommen über IAtlasDiscoverSource aus der IDE-Schicht.
// Klicks rufen die Quelle über die Nachrichtenschleife auf: Die Quelle baut
// die Karte daraufhin neu, und ein Knopf darf nicht in seinem eigenen Klick
// verschwinden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
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

  TAtlasWelcomeDiscoverFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    Gap = 8;
    ImageWidth = 96;
    ImageHeight = 60;
    ButtonHeight = 24;
    ButtonPadding = 16;
  private
    FSource: IAtlasDiscoverSource;
    FCard: TAtlasDiscoverCard;
    FHasCard: Boolean;
    FImage: TImage;
    FImageFile: string;
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
    procedure LoadImage(const AFileName: string);
    procedure Arrange;
    procedure BodyResize(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Klick auf einen Knopf wie mit der Maus (auch für Tests).</summary>
    procedure ClickButton(AButton: TAtlasDiscoverButton);
    function Button(AButton: TAtlasDiscoverButton): TButton;
    /// <summary>„Atlas entdecken“ in der Sprache der IDE.</summary>
    class function TitleText: string; static;
    /// <summary>„Noch nie benutzt“, „Zuletzt vor 3 Wochen“ …; '' ohne Hinweis.</summary>
    class function AgeText(const AAge: TAtlasDiscoverAge): string; static;
    /// <summary>„Tipp 2 von 7“; '' bei höchstens einem Tipp.</summary>
    class function PositionText(APosition, ACount: Integer): string; static;
    class function ButtonCaption(AButton: TAtlasDiscoverButton): string; static;
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
  Atlas.UI.Strings;

{ TAtlasWelcomeDiscoverFrame }

constructor TAtlasWelcomeDiscoverFrame.Create(AOwner: TComponent);
var
  Kind: TAtlasDiscoverButton;

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
  FImage.Stretch := True;
  FImage.Proportional := True;
  FImage.Center := True;
  FImage.Visible := False;
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
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverEmpty);
  for Kind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
  begin
    FButtons[Kind] := TButton.Create(Self);
    FButtons[Kind].Parent := Body;
    FButtons[Kind].Caption := ButtonCaption(Kind);
    FButtons[Kind].Tag := Ord(Kind);
    FButtons[Kind].OnClick := ButtonClick;
  end;
  Body.OnResize := BodyResize;
  UpdateContent;
end;

class function TAtlasWelcomeDiscoverFrame.TitleText: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverTitle);
end;

class function TAtlasWelcomeDiscoverFrame.AgeText(const AAge: TAtlasDiscoverAge): string;
begin
  case AAge.Kind of
    TAtlasDiscoverAgeKind.Never:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverNever);
    TAtlasDiscoverAgeKind.Today:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverToday);
    TAtlasDiscoverAgeKind.Yesterday:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverYesterday);
    TAtlasDiscoverAgeKind.Days:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverDays, [AAge.Count]);
    TAtlasDiscoverAgeKind.Weeks:
      if AAge.Count = 1 then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverWeek)
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverWeeks, [AAge.Count]);
    TAtlasDiscoverAgeKind.Months:
      if AAge.Count = 1 then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverMonth)
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverMonths, [AAge.Count]);
    TAtlasDiscoverAgeKind.Years:
      if AAge.Count = 1 then
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverYear)
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverYears, [AAge.Count]);
  else
    Result := '';
  end;
end;

class function TAtlasWelcomeDiscoverFrame.PositionText(APosition, ACount: Integer): string;
begin
  Result := '';
  if (ACount > 1) and (APosition > 0) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeDiscoverPosition, [APosition, ACount]);
end;

class function TAtlasWelcomeDiscoverFrame.ButtonCaption(AButton: TAtlasDiscoverButton): string;
begin
  case AButton of
    TAtlasDiscoverButton.TryIt:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverTry);
    TAtlasDiscoverButton.Next:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverNext);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeDiscoverBlock);
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

procedure TAtlasWelcomeDiscoverFrame.LoadImage(const AFileName: string);
begin
  if AFileName = FImageFile then
    Exit;
  FImageFile := AFileName;
  FImage.Picture.Assign(nil);
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  try
    FImage.Picture.LoadFromFile(AFileName);
  except
    // Kaputtes Bild: Karte ohne Bild.
    on Exception do
      FImage.Picture.Assign(nil);
  end;
end;

procedure TAtlasWelcomeDiscoverFrame.UpdateContent;
var
  Kind: TAtlasDiscoverButton;
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  FCard := Default(TAtlasDiscoverCard);
  FHasCard := (FSource <> nil) and FSource.Card(FCard);
  if not FHasCard then
    FCard := Default(TAtlasDiscoverCard);
  LoadImage(FCard.ImageFile);
  FImage.Visible := FHasCard and (FImage.Picture.Graphic <> nil) and not FImage.Picture.Graphic.Empty;
  FTitleLabel.Caption := FCard.Title;
  FKey.Caption := FCard.KeyText;
  FText.Caption := FCard.Text;
  FAge.Caption := AgeText(FCard.Age);
  FPosition.Caption := PositionText(FCard.Position, FCard.Count);
  FTitleLabel.Visible := FHasCard;
  FKey.Visible := FHasCard and (FCard.KeyText <> '');
  FText.Visible := FHasCard and (FCard.Text <> '');
  FAge.Visible := FHasCard and (FAge.Caption <> '');
  FPosition.Visible := FHasCard and (FPosition.Caption <> '');
  FEmpty.Visible := not FHasCard;
  for Kind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
    FButtons[Kind].Visible := FHasCard;
  FButtons[TAtlasDiscoverButton.TryIt].Enabled := FCard.CanTry;
  FButtons[TAtlasDiscoverButton.Next].Enabled := FCard.Count > 1;
  Arrange;
  inherited;
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeDiscoverFrame.BodyResize(Sender: TObject);
var
  OldHeight: Integer;
begin
  OldHeight := FContentHeight;
  Arrange;
  // Anderer Umbruch bei neuer Breite: Der Frame „Atlas“ ordnet die Spalten neu.
  if OldHeight <> FContentHeight then
    HeightChanged;
end;

procedure TAtlasWelcomeDiscoverFrame.Arrange;
var
  Width, Left, Top, TextLeft, Right, Bottom, ButtonWidth, ButtonLeft, ButtonTop: Integer;
  Kind: TAtlasDiscoverButton;
  Measure: TBitmap;
begin
  if FArranging or (FTitleLabel = nil) then
    Exit;
  FArranging := True;
  try
    // Breite des Frames statt der Inhaltsfläche: Die richtet sich erst später nach dem Frame aus.
    Width := ClientWidth;
    Left := ScaleValue(Indent);
    Right := Width - ScaleValue(Indent);
    Top := ScaleValue(Gap) div 2;
    if not FHasCard then
    begin
      FEmpty.SetBounds(Left, Top, FEmpty.Width, FEmpty.Height);
      FContentHeight := FEmpty.Top + FEmpty.Height + ScaleValue(Gap);
      Exit;
    end;
    TextLeft := Left;
    Bottom := Top;
    if FImage.Visible then
    begin
      FImage.SetBounds(Left, Top, ScaleValue(ImageWidth), ScaleValue(ImageHeight));
      TextLeft := Left + ScaleValue(ImageWidth) + ScaleValue(Gap);
      Bottom := FImage.Top + FImage.Height;
    end;
    FTitleLabel.SetBounds(TextLeft, Top, FTitleLabel.Width, FTitleLabel.Height);
    Top := FTitleLabel.Top + FTitleLabel.Height;
    if FKey.Visible then
    begin
      // Kürzel neben dem Titel, sonst darunter.
      if FTitleLabel.Left + FTitleLabel.Width + ScaleValue(Gap) + FKey.Width <= Right then
        FKey.SetBounds(FTitleLabel.Left + FTitleLabel.Width + ScaleValue(Gap), FTitleLabel.Top, FKey.Width,
          FKey.Height)
      else
      begin
        FKey.SetBounds(TextLeft, Top, FKey.Width, FKey.Height);
        Top := FKey.Top + FKey.Height;
      end;
    end;
    if FText.Visible then
    begin
      // Breite zuerst: Das Label bricht danach um und passt seine Höhe an.
      FText.Width := Max(Right - TextLeft, ScaleValue(80));
      // AutoSize neu setzen: Erst das misst den umbrochenen Text für die neue Breite.
      FText.AutoSize := False;
      FText.AutoSize := True;
      FText.Left := TextLeft;
      FText.Top := Top + 2;
      Top := FText.Top + FText.Height;
    end;
    if FAge.Visible or FPosition.Visible then
    begin
      Inc(Top, 2);
      if FAge.Visible then
        FAge.SetBounds(TextLeft, Top, FAge.Width, FAge.Height);
      if FPosition.Visible then
        FPosition.SetBounds(Max(TextLeft, Right - FPosition.Width), Top, FPosition.Width, FPosition.Height);
      Inc(Top, Max(FAge.Height, FPosition.Height));
    end;
    Top := Max(Top, Bottom) + ScaleValue(Gap);
    // Knöpfe von links nach rechts, bei zu wenig Breite in weiteren Reihen.
    ButtonLeft := Left;
    ButtonTop := Top;
    Measure := TBitmap.Create;
    try
      Measure.Canvas.Font.Assign(Font);
      for Kind := Low(TAtlasDiscoverButton) to High(TAtlasDiscoverButton) do
      begin
        ButtonWidth := Measure.Canvas.TextWidth(FButtons[Kind].Caption) + 2 * ScaleValue(ButtonPadding);
        if (ButtonLeft > Left) and (ButtonLeft + ButtonWidth > Right) then
        begin
          ButtonLeft := Left;
          Inc(ButtonTop, ScaleValue(ButtonHeight) + ScaleValue(Gap) div 2);
        end;
        FButtons[Kind].SetBounds(ButtonLeft, ButtonTop, ButtonWidth, ScaleValue(ButtonHeight));
        Inc(ButtonLeft, ButtonWidth + ScaleValue(Gap) div 2);
      end;
    finally
      Measure.Free;
    end;
    FContentHeight := ButtonTop + ScaleValue(ButtonHeight) + ScaleValue(Gap) div 2;
  finally
    FArranging := False;
  end;
end;

function TAtlasWelcomeDiscoverFrame.BodyHeight: Integer;
begin
  // Für die aktuelle Breite: Der Frame „Atlas“ setzt erst die Breite, dann die Höhe.
  Arrange;
  Result := Max(FContentHeight, ScaleValue(40));
end;

procedure TAtlasWelcomeDiscoverFrame.ClickButton(AButton: TAtlasDiscoverButton);
var
  Source: IAtlasDiscoverSource;
  Id: string;
begin
  if (FSource = nil) or not FHasCard or not FButtons[AButton].Enabled then
    Exit;
  Source := FSource;
  Id := FCard.Id;
  // Die Quelle baut die Karte neu: nicht im Klick des Knopfs.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      case AButton of
        TAtlasDiscoverButton.TryIt:
          Source.TryTip(Id);
        TAtlasDiscoverButton.Next:
          Source.NextTip(Id);
      else
        Source.BlockTip(Id);
      end;
    end);
end;

procedure TAtlasWelcomeDiscoverFrame.ButtonClick(Sender: TObject);
begin
  ClickButton(TAtlasDiscoverButton((Sender as TButton).Tag));
end;

end.
