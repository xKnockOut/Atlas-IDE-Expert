unit Dcc.Inline;

// #1328, Regel type-restriction-violated (E2441, E2296, E2358): Fälle, die Atlas
// meldet, die Delphi aber nach den Korpus-Projekten übersetzt.

interface

type
  TSperre = record
    FZustand: Integer;
    procedure Sperren; inline; // TR1: echte Konstante aus dem implementation-Teil (mORMot2 TOSLightLock)
  end;

  TBild = class
  public
    constructor Create; overload;
    constructor Create(ABreite, AHoehe: Integer); overload;
  end;

  TBildHelfer = class helper for TBild
  strict private
    class var FZaehler: Integer;
    class constructor Create; // TR7: class constructor im Class-Helfer (Skia4Delphi MobileBars)
  public
    constructor CreateAus(AGroesse: Integer); // TR6: Konstruktor ruft in einem if einen überladenen Konstruktor (Skia4Delphi)
  end;

function KonstanteNutzen: Integer; inline; // TR2: echte Konstante aus dem implementation-Teil (mORMot2)
function TypKonstanteNutzen: Integer; inline; // TR3: typisierte Konstante aus dem implementation-Teil
function RoutineNutzen(AWert: Integer): Double; inline; // TR4: Routine aus dem implementation-Teil (Clipper2)
function NurHintenInline(AWert: Integer): Double; // TR5: inline nur an der Implementierung (HtmlViewer)

implementation

const
  cGesperrt = 1;
  cStart: Integer = 2;

function Quadrat(AWert: Integer): Double; inline;
begin
  Result := AWert * AWert;
end;

procedure TSperre.Sperren;
begin
  FZustand := cGesperrt;
end;

constructor TBild.Create;
begin
  inherited Create;
end;

constructor TBild.Create(ABreite, AHoehe: Integer);
begin
  inherited Create;
end;

class constructor TBildHelfer.Create;
begin
  FZaehler := 0;
end;

constructor TBildHelfer.CreateAus(AGroesse: Integer);
begin
  if AGroesse = 0 then
    Create
  else
    Create(AGroesse, AGroesse);
end;

function KonstanteNutzen: Integer;
begin
  Result := cGesperrt;
end;

function TypKonstanteNutzen: Integer;
begin
  Result := cStart;
end;

function RoutineNutzen(AWert: Integer): Double;
begin
  Result := Quadrat(AWert);
end;

function NurHintenInline(AWert: Integer): Double;
  inline;
begin
  Result := Quadrat(AWert);
end;

end.
