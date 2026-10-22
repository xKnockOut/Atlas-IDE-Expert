unit Ref.Komponenten.Anzeige;

// Komponente mit published-Properties samt default, Ereignissen,
// Notification und Paint.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics;

type
  TAnzeigeStil = (asFlach, asRahmen, asSchatten);

  TRefAnzeige = class(TGraphicControl)
  private
    FStil: TAnzeigeStil;
    FWert: Integer;
    FBeschriftung: string;
    FVerknuepft: TControl;
    FOnWertGeaendert: TNotifyEvent;
    procedure SetStil(const AValue: TAnzeigeStil);
    procedure SetWert(const AValue: Integer);
    procedure SetVerknuepft(const AValue: TControl);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Stil: TAnzeigeStil read FStil write SetStil default asRahmen;
    property Wert: Integer read FWert write SetWert default 0;
    property Beschriftung: string read FBeschriftung write FBeschriftung;
    property Verknuepft: TControl read FVerknuepft write SetVerknuepft;
    property OnWertGeaendert: TNotifyEvent read FOnWertGeaendert write FOnWertGeaendert;
    property Align;
    property Color;
    property Font;
    property OnClick;
  end;

implementation

uses
  System.SysUtils;

const
  StandardBreite = 120;
  StandardHoehe = 32;
  TextAbstand = 4;

constructor TRefAnzeige.Create(AOwner: TComponent);
begin
  inherited;
  FStil := asRahmen;
  Width := StandardBreite;
  Height := StandardHoehe;
end;

procedure TRefAnzeige.SetStil(const AValue: TAnzeigeStil);
begin
  if FStil <> AValue then
  begin
    FStil := AValue;
    Invalidate;
  end;
end;

procedure TRefAnzeige.SetWert(const AValue: Integer);
begin
  if FWert <> AValue then
  begin
    FWert := AValue;
    Invalidate;
    if Assigned(FOnWertGeaendert) then
      FOnWertGeaendert(Self);
  end;
end;

procedure TRefAnzeige.SetVerknuepft(const AValue: TControl);
begin
  if FVerknuepft <> nil then
    FVerknuepft.RemoveFreeNotification(Self);
  FVerknuepft := AValue;
  if FVerknuepft <> nil then
    FVerknuepft.FreeNotification(Self);
end;

procedure TRefAnzeige.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FVerknuepft) then
    FVerknuepft := nil;
end;

procedure TRefAnzeige.Paint;
var
  Anzeigetext: string;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if FStil <> asFlach then
    Canvas.Rectangle(ClientRect);
  Anzeigetext := Format('%s: %d', [FBeschriftung, FWert]);
  Canvas.TextOut(TextAbstand, (Height - Canvas.TextHeight(Anzeigetext)) div 2, Anzeigetext);
end;

end.
