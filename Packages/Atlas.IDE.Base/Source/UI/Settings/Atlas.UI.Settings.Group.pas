unit Atlas.UI.Settings.Group;

// Rahmen einer Funktion auf der Optionsseite (#890): oben der Hauptschalter
// (Kontrollkästchen oder Zeile mit Auswahl), darunter eine Zeile mit dem Grund
// einer Sperre („gesperrt: …“, sonst ausgeblendet), dann die Unteroptionen
// eingerückt. Der Rahmen zeichnet nur seine Kante in der Farbe des IDE-Themas,
// der Hintergrund des Reiters scheint durch. Die Höhe folgt dem Inhalt: Zeilen
// stehen mit alTop untereinander, ausgeblendete (Filter) fallen heraus.
// Welche Zeilen hineingehören und wann sie gesperrt sind, bestimmt die Seite
// (Atlas.UI.Settings.Page) aus Atlas.Core.Settings.Groups.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls;

type
  TAtlasSettingsGroup = class(TCustomControl)
  public const
    /// <summary>Einrückung der Unteroptionen in Pixeln (bei 96 dpi).</summary>
    cIndent = 20;
  private
    FMaster: TControl;
    FMasterName: string;
    FReason: TLabel;
    FAdjusting: Boolean;
    FNextTop: Integer;
    function ContentHeight: Integer;
  protected
    procedure Paint; override;
    procedure AlignControls(AControl: TControl; var Rect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>AControl als Kopf (Hauptschalter) einsetzen; er steht immer oben und ist nicht eingerückt.</summary>
    procedure SetMaster(AControl: TControl; const AName: string);
    /// <summary>AControl als nächste Zeile darunter einhängen, eingerückt.</summary>
    procedure AddRow(AControl: TControl);
    /// <summary>Grund der Sperre zeigen; '' blendet die Zeile aus.</summary>
    procedure ShowReason(const AText: string);
    /// <summary>Höhe nach dem Inhalt setzen (ohne Fenster richtet die VCL nicht aus).</summary>
    procedure AdjustHeight;
    /// <summary>Kopf des Rahmens (Kontrollkästchen oder Zeile).</summary>
    property Master: TControl read FMaster;
    /// <summary>Registry-Name des Hauptschalters.</summary>
    property MasterName: string read FMasterName;
    property Reason: TLabel read FReason;
  end;

implementation

uses
  Vcl.Themes,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Foundation.Scaling;

const
  /// <summary>Innenabstand des Rahmens links, oben, rechts und unten.</summary>
  cPaddingSide = 6;
  cPaddingTop = 4;
  /// <summary>Höhe vor dem ersten AdjustHeight (Kopf allein).</summary>
  cInitialHeight = 40;
  /// <summary>Grund der Sperre: Einrückung zusätzlich zu cIndent (unter dem Text des Kopfs) und Oberkante.</summary>
  cReasonIndent = 3;
  cReasonTop = 2;
  /// <summary>Radius der abgerundeten Ecken.</summary>
  cCornerRadius = 6;

{ TAtlasSettingsGroup }

constructor TAtlasSettingsGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
  TAtlasControlScaling.SetPadding(Self, cPaddingSide, cPaddingTop, cPaddingSide, cPaddingSide);
  AlignWithMargins := True;
  Height := ScaleValue(cInitialHeight);
  FNextTop := 100;
  FReason := TAtlasWrapLabel.Create(Self);
  FReason.Parent := Self;
  FReason.Align := alTop;
  FReason.AlignWithMargins := True;
  FReason.Margins.Left := FReason.ScaleValue(cReasonIndent) + FReason.ScaleValue(cIndent);
  FReason.Top := FReason.ScaleValue(cReasonTop);
  FReason.ShowAccelChar := False;
  FReason.Font.Style := [fsItalic];
  FReason.Visible := False;
end;

procedure TAtlasSettingsGroup.Paint;
var
  mRadius: Integer;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
  mRadius := ScaleValue(cCornerRadius);
  Canvas.RoundRect(0, 0, Width, Height, mRadius, mRadius);
end;

procedure TAtlasSettingsGroup.AlignControls(AControl: TControl; var Rect: TRect);
var
  mNeeded: Integer;
begin
  inherited AlignControls(AControl, Rect);
  if FAdjusting then
  begin
    Exit;
  end;
  mNeeded := ContentHeight;
  if mNeeded = Height then
  begin
    Exit;
  end;
  FAdjusting := True;
  try
    Height := mNeeded;
  finally
    FAdjusting := False;
  end;
end;

function TAtlasSettingsGroup.ContentHeight: Integer;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := Padding.Top + Padding.Bottom;
  for mIndex := 0 to ControlCount - 1 do
  begin
    mControl := Controls[mIndex];
    if not mControl.Visible then
    begin
      Continue;
    end;
    Inc(Result, mControl.Height);
    if mControl.AlignWithMargins then
    begin
      Inc(Result, mControl.Margins.Top + mControl.Margins.Bottom);
    end;
  end;
end;

procedure TAtlasSettingsGroup.SetMaster(AControl: TControl; const AName: string);
begin
  FMaster := AControl;
  FMasterName := AName;
  AControl.Parent := Self;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := 0;
end;

procedure TAtlasSettingsGroup.AddRow(AControl: TControl);
begin
  AControl.Parent := Self;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Margins.Left := AControl.Margins.Left + AControl.ScaleValue(cIndent);
  // alTop ordnet nach Top: jede Zeile unter die vorige.
  AControl.Top := FNextTop;
  Inc(FNextTop, 100);
end;

procedure TAtlasSettingsGroup.ShowReason(const AText: string);
begin
  FReason.Caption := AText;
  FReason.Visible := AText <> '';
end;

procedure TAtlasSettingsGroup.AdjustHeight;
var
  mIndex: Integer;
begin
  // Verschachtelte Rahmen zuerst: Ihre Höhe geht in diese ein.
  for mIndex := 0 to ControlCount - 1 do
  begin
    if Controls[mIndex] is TAtlasSettingsGroup then
    begin
      TAtlasSettingsGroup(Controls[mIndex]).AdjustHeight;
    end;
  end;
  FAdjusting := True;
  try
    Height := ContentHeight;
  finally
    FAdjusting := False;
  end;
end;

end.
