unit Atlas.UI.Welcome.State;

// Zustandskachel „Atlas“ der Willkommensseite (#754), ohne Open Tools API:
//   ● Server läuft                                   seit 19:02
//   ● Update 1.0.1 bereit                       installiert 1.0.0
//   ● Index: 1284 Units                           indiziert 18:40
//   ● Einrichtung: 5 von 6 erledigt
//   ● Diagnosemodus aus
//   [Server neu starten] [Einstellungen] [Log-Ordner öffnen] [Jetzt aktualisieren]
// Je Zeile Ampelpunkt, Text und Zusatz rechts, selbst gezeichnet; der Tooltip
// zeigt den vollen Text der Zeile im Statusfeld (#591). Zeilen mit Aktion
// (Einrichtung öffnet die Prüfliste, Diagnosemodus das Diagnosefenster,
// Update die Änderungen) sind anklickbar. „Jetzt aktualisieren“ erscheint
// nur, wenn ein Update bereitsteht. Fehlt eine Zeile im Statusfeld, steht
// hier eine neutrale Ersatzzeile (z. B. „Diagnosemodus aus“).
// Daten und Aktionen kommen über IAtlasStateSource aus der IDE-Schicht;
// Klicks gehen über die Nachrichtenschleife. Neu gezeichnet wird bei einer
// Zustandsänderung (UpdateContent → Invalidate), nie per Zeitgeber.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Status.Contract,
  Atlas.Core.Welcome.State,
  Atlas.UI.Welcome.Frame;

type
  IAtlasStateSource = interface
    ['{5B8E1D37-2C4A-4F69-9E03-7A6D2B1C8F54}']
    /// <summary>Die fünf Zeilen aus dem Atlas-Statusfeld (#591).</summary>
    function Rows: TAtlasStateRows;
    /// <summary>Aktion der Statusfeld-Zeile AId ausführen.</summary>
    procedure RunRow(const AId: string);
    /// <summary>Knopf unter den Zeilen.</summary>
    procedure Run(AButton: TAtlasStateButton);
  end;

  TAtlasWelcomeStateFrame = class(TAtlasWelcomeSectionFrame)
  public const
    RowHeight = 22;
    Indent = 8;
    DotSize = 10;
    ButtonHeight = 24;
    ButtonGap = 6;
    ButtonPadding = 16;
  private
    FSource: IAtlasStateSource;
    FBox: TAtlasWelcomeCanvas;
    FBar: TPanel;
    FButtons: array[TAtlasStateButton] of TButton;
    FRows: TAtlasStateRows;
    FHintRow: Integer;
    FBarRows: Integer;
    procedure SetSource(const AValue: IAtlasStateSource);
    procedure BoxPaint(Sender: TObject);
    procedure PaintRow(ACanvas: TCanvas; AIndex, ARight: Integer; ATextColor, AMutedColor: TColor);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ButtonClick(Sender: TObject);
    procedure BarResize(Sender: TObject);
    /// <summary>Knöpfe von links nach rechts, bei zu wenig Breite in weiteren Reihen; Zahl der Reihen.</summary>
    function LayoutButtons: Integer;
    function RowTop(ARow: Integer): Integer;
    function BarHeight: Integer;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile an Y (Koordinaten der Zeichenfläche); -1 = keine.</summary>
    function HitTest(Y: Integer): Integer;
    /// <summary>Klick auf eine Zeile wie mit der Maus (auch für Tests); nur Zeilen mit Aktion.</summary>
    procedure ClickRow(ARow: Integer);
    /// <summary>Klick auf einen Knopf wie mit der Maus (auch für Tests).</summary>
    procedure ClickButton(AButton: TAtlasStateButton);
    /// <summary>Text einer Zeile; Ersatztext, wenn die Zeile im Statusfeld fehlt.</summary>
    class function RowText(const ARow: TAtlasStateRow): string; static;
    /// <summary>Zusatz rechts; bei der Ersatzzeile „Diagnosemodus“ leer.</summary>
    class function DetailText(const ARow: TAtlasStateRow): string; static;
    class function DotColor(AState: TAtlasStatusState): TColor; static;
    class function ButtonCaption(AButton: TAtlasStateButton): string; static;
    /// <summary>Knopf (für Tests).</summary>
    function Button(AButton: TAtlasStateButton): TButton;
    property Source: IAtlasStateSource read FSource write SetSource;
    property Rows: TAtlasStateRows read FRows;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
  end;

implementation

uses
  System.UITypes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Product.Version,
  Atlas.UI.Welcome.Strings;

{ TAtlasWelcomeStateFrame }

constructor TAtlasWelcomeStateFrame.Create(AOwner: TComponent);
var
  Kind: TAtlasStateButton;
begin
  inherited Create(AOwner);
  FHintRow := -1;
  FBarRows := 1;
  FBar := TPanel.Create(Self);
  FBar.Parent := Body;
  FBar.Align := alBottom;
  FBar.BevelOuter := bvNone;
  FBar.ParentBackground := True;
  FBar.Height := BarHeight;
  for Kind := Low(TAtlasStateButton) to High(TAtlasStateButton) do
  begin
    FButtons[Kind] := TButton.Create(Self);
    FButtons[Kind].Parent := FBar;
    FButtons[Kind].Caption := ButtonCaption(Kind);
    FButtons[Kind].Tag := Ord(Kind);
    FButtons[Kind].OnClick := ButtonClick;
    // „Jetzt aktualisieren“ nur mit Update.
    FButtons[Kind].Visible := Kind <> TAtlasStateButton.Update;
  end;
  // Erst jetzt: Die Größenänderung ordnet die Knöpfe an.
  FBar.OnResize := BarResize;
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
end;

function TAtlasWelcomeStateFrame.Button(AButton: TAtlasStateButton): TButton;
begin
  Result := FButtons[AButton];
end;

class function TAtlasWelcomeStateFrame.ButtonCaption(AButton: TAtlasStateButton): string;
begin
  case AButton of
    TAtlasStateButton.Restart:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateRestart);
    TAtlasStateButton.Settings:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateSettings);
    TAtlasStateButton.LogFolder:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateLogFolder);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateUpdate);
  end;
end;

procedure TAtlasWelcomeStateFrame.SetSource(const AValue: IAtlasStateSource);
begin
  FSource := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeStateFrame.UpdateContent;
var
  Count: Integer;
  Kind: TAtlasStateButton;
  Wanted: array[TAtlasStateButton] of Boolean;
  Changed: Boolean;
begin
  Count := Length(FRows);
  FRows := nil;
  if FSource <> nil then
  begin
    FRows := FSource.Rows;
  end;
  // Knöpfe nach den Zeilen: „Jetzt aktualisieren“ nur mit Update.
  for Kind := Low(TAtlasStateButton) to High(TAtlasStateButton) do
  begin
    Wanted[Kind] := False;
  end;
  for Kind in TAtlasWelcomeState.Buttons(FRows) do
  begin
    Wanted[Kind] := True;
  end;
  Changed := False;
  for Kind := Low(TAtlasStateButton) to High(TAtlasStateButton) do
  begin
    if FButtons[Kind].Visible <> Wanted[Kind] then
    begin
      FButtons[Kind].Visible := Wanted[Kind];
      Changed := True;
    end;
  end;
  if Changed then
  begin
    BarResize(FBar);
  end;
  FHintRow := -1;
  FBox.Invalidate;
  inherited;
  if Count <> Length(FRows) then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeStateFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(Indent) div 2 + ARow * ScaleValue(RowHeight);
end;

function TAtlasWelcomeStateFrame.BarHeight: Integer;
begin
  Result := FBarRows * (ScaleValue(ButtonHeight) + ScaleValue(ButtonGap)) + ScaleValue(ButtonGap);
end;

function TAtlasWelcomeStateFrame.BodyHeight: Integer;
var
  mRows: Integer;
begin
  mRows := Max(Length(FRows), 1);
  Result := mRows * ScaleValue(RowHeight) + ScaleValue(Indent) + BarHeight;
end;

function TAtlasWelcomeStateFrame.LayoutButtons: Integer;
var
  Kind: TAtlasStateButton;
  mLeft, mTop, mWidth, Right: Integer;
  Measure: TBitmap;
begin
  Result := 1;
  mLeft := ScaleValue(Indent);
  mTop := ScaleValue(ButtonGap);
  Right := FBar.ClientWidth - ScaleValue(Indent);
  // Messen auf einer Bitmap: Der Frame hat beim Anlegen noch kein Fenster.
  Measure := TBitmap.Create;
  try
    Measure.Canvas.Font.Assign(Font);
    for Kind := Low(TAtlasStateButton) to High(TAtlasStateButton) do
    begin
      if not FButtons[Kind].Visible then
      begin
        Continue;
      end;
      mWidth := Measure.Canvas.TextWidth(FButtons[Kind].Caption) + 2 * ScaleValue(ButtonPadding);
      // Zu schmal: nächste Reihe (nicht für den ersten Knopf einer Reihe).
      if (mLeft > ScaleValue(Indent)) and (Right > 0) and (mLeft + mWidth > Right) then
      begin
        mLeft := ScaleValue(Indent);
        Inc(mTop, ScaleValue(ButtonHeight) + ScaleValue(ButtonGap));
        Inc(Result);
      end;
      FButtons[Kind].SetBounds(mLeft, mTop, mWidth, ScaleValue(ButtonHeight));
      Inc(mLeft, mWidth + ScaleValue(ButtonGap));
    end;
  finally
    Measure.Free;
  end;
end;

procedure TAtlasWelcomeStateFrame.BarResize(Sender: TObject);
var
  BarRows: Integer;
begin
  BarRows := LayoutButtons;
  if BarRows = FBarRows then
  begin
    Exit;
  end;
  // Mehr oder weniger Reihen Knöpfe: Der Frame „Atlas“ ordnet die Spalten neu.
  FBarRows := BarRows;
  FBar.Height := BarHeight;
  HeightChanged;
end;

class function TAtlasWelcomeStateFrame.DotColor(AState: TAtlasStatusState): TColor;
begin
  // Dieselben Töne wie die Marken der Projekte (#592): lesbar im hellen und im dunklen Thema.
  case AState of
    TAtlasStatusState.Green:
      Result := TColor($0043A02E);
    TAtlasStatusState.Yellow:
      Result := TColor($001A8CC9);
    TAtlasStatusState.Red:
      Result := TColor($002E22CF);
  else
    Result := TColor($00817666);
  end;
end;

class function TAtlasWelcomeStateFrame.RowText(const ARow: TAtlasStateRow): string;
begin
  if ARow.Present and (ARow.Text <> '') then
  begin
    Exit(ARow.Text);
  end;
  case ARow.Kind of
    TAtlasStateRowKind.Server:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateServerMissing);
    TAtlasStateRowKind.Version:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeStateVersion, [TAtlasPluginVersion.Version]);
    TAtlasStateRowKind.Index:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateIndexMissing);
    TAtlasStateRowKind.Setup:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateSetupMissing);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateDiagnosticOff);
  end;
end;

class function TAtlasWelcomeStateFrame.DetailText(const ARow: TAtlasStateRow): string;
begin
  Result := '';
  if ARow.Present then
  begin
    Result := ARow.Detail;
  end;
end;

procedure TAtlasWelcomeStateFrame.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mIndex: Integer;
  mTextColor, mMutedColor: TColor;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Font.Assign(Font);
  // Farben des IDE-Themas (hell oder dunkel).
  mTextColor := StyleServices(Self).GetSystemColor(clWindowText);
  mMutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  for mIndex := 0 to High(FRows) do
  begin
    PaintRow(mCanvas, mIndex, FBox.Width - ScaleValue(Indent), mTextColor, mMutedColor);
  end;
end;

procedure TAtlasWelcomeStateFrame.PaintRow(ACanvas: TCanvas; AIndex, ARight: Integer; ATextColor, AMutedColor: TColor);
var
  mLeft, mTop, mDot, mTextTop, mDetailWidth: Integer;
  mRow: TAtlasStateRow;
  mDetail: string;
  mTextRect: TRect;
  mText: string;
begin
  mRow := FRows[AIndex];
  mDot := ScaleValue(DotSize);
  mTop := RowTop(AIndex);
  mLeft := ScaleValue(Indent);
  mTextTop := mTop + (ScaleValue(RowHeight) - ACanvas.TextHeight('Wg')) div 2;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := DotColor(mRow.State);
  ACanvas.Pen.Color := ACanvas.Brush.Color;
  ACanvas.Ellipse(mLeft, mTop + (ScaleValue(RowHeight) - mDot) div 2, mLeft + mDot,
    mTop + (ScaleValue(RowHeight) - mDot) div 2 + mDot);
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, mDot + ScaleValue(6));
  // Zusatz rechtsbündig in der gedämpften Farbe, Text davor gekürzt.
  mDetail := DetailText(mRow);
  mDetailWidth := 0;
  if mDetail <> '' then
  begin
    ACanvas.Font.Color := AMutedColor;
    mDetailWidth := ACanvas.TextWidth(mDetail);
    ACanvas.TextOut(ARight - mDetailWidth, mTextTop, mDetail);
    Inc(mDetailWidth, ScaleValue(8));
  end;
  ACanvas.Font.Color := ATextColor;
  if mRow.HasAction then
  begin
    ACanvas.Font.Style := [fsUnderline];
  end
  else
  begin
    ACanvas.Font.Style := [];
  end;
  mTextRect := Rect(mLeft, mTextTop, Max(mLeft, ARight - mDetailWidth), mTextTop + ACanvas.TextHeight('Wg'));
  mText := RowText(mRow);
  ACanvas.TextRect(mTextRect, mText, [tfLeft, tfSingleLine, tfEndEllipsis, tfNoPrefix]);
  ACanvas.Font.Style := [];
end;

function TAtlasWelcomeStateFrame.HitTest(Y: Integer): Integer;
begin
  Result := -1;
  if (Y < RowTop(0)) or (Length(FRows) = 0) then
  begin
    Exit;
  end;
  Result := (Y - RowTop(0)) div ScaleValue(RowHeight);
  if Result > High(FRows) then
  begin
    Result := -1;
  end;
end;

procedure TAtlasWelcomeStateFrame.ClickRow(ARow: Integer);
var
  mSource: IAtlasStateSource;
  Id: string;
begin
  if (FSource = nil) or (ARow < 0) or (ARow > High(FRows)) or not FRows[ARow].HasAction then
  begin
    Exit;
  end;
  mSource := FSource;
  Id := FRows[ARow].Id;
  // Die Aktion öffnet Fenster oder ändert den Zustand: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.RunRow(Id);
    end);
end;

procedure TAtlasWelcomeStateFrame.ClickButton(AButton: TAtlasStateButton);
var
  mSource: IAtlasStateSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Run(AButton);
    end);
end;

procedure TAtlasWelcomeStateFrame.ButtonClick(Sender: TObject);
begin
  ClickButton(TAtlasStateButton((Sender as TButton).Tag));
end;

procedure TAtlasWelcomeStateFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  Row := HitTest(Y);
  if (Row >= 0) and FRows[Row].HasAction then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  if Row = FHintRow then
  begin
    Exit;
  end;
  FHintRow := Row;
  if (Row >= 0) and FRows[Row].Present then
  begin
    FBox.Hint := FRows[Row].Hint;
  end
  else
  begin
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeStateFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
  begin
    ClickRow(HitTest(Y));
  end;
end;

end.
