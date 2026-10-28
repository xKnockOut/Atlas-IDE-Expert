unit Dcc.Inline.Gegen;

// #1328, Gegentests zu type-restriction-violated: Hier soll dcc vermutlich melden.

interface

type
  TBild = class
  public
    constructor Create(ABreite, AHoehe: Integer);
  end;

  TBildHelfer = class helper for TBild
  public
    constructor CreateLeer; // TG3: Konstruktor im Class-Helfer ruft keinen Konstruktor
  end;

function VariableNutzen: Integer; inline; // TG1: Variable aus dem implementation-Teil
function TypNutzen: Integer; inline; // TG2: Typ aus dem implementation-Teil

implementation

type
  TIntern = record
    Wert: Integer;
  end;

var
  gZaehler: Integer;

constructor TBild.Create(ABreite, AHoehe: Integer);
begin
  inherited Create;
end;

constructor TBildHelfer.CreateLeer;
begin
end;

function VariableNutzen: Integer;
begin
  Result := gZaehler;
end;

function TypNutzen: Integer;
var
  mWert: TIntern;
begin
  mWert.Wert := 1;
  Result := mWert.Wert;
end;

end.
