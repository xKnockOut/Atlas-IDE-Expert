unit Dcc.Einbetten;

// #1328, Regel type-restriction-violated (E2441, E2296, E2358): Fälle, die Atlas
// meldete, die Delphi aber übersetzt (Korpus-Projekte, dcc-Lauf vom 29.10.2026).

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
    constructor CreateLeer; // TR9 (vorher TG3): Konstruktor im Class-Helfer ruft keinen Konstruktor
  end;

function KonstanteNutzen: Integer; inline; // TR2: echte Konstante aus dem implementation-Teil (mORMot2)
function TypNutzen: Integer; inline; // TR8 (vorher TG2): Typ aus dem implementation-Teil
function RoutineNutzen(AWert: Integer): Double; inline; // TR4: Routine aus dem implementation-Teil (Clipper2)
function NurHintenInline(AWert: Integer): Double; // TR5: inline nur an der Implementierung (HtmlViewer)

implementation

type
  TIntern = record
    Wert: Integer;
  end;

const
  cGesperrt = 1;

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

constructor TBildHelfer.CreateLeer;
begin
end;

function KonstanteNutzen: Integer;
begin
  Result := cGesperrt;
end;

function TypNutzen: Integer;
var
  mWert: TIntern;
begin
  mWert.Wert := 1;
  Result := mWert.Wert;
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
