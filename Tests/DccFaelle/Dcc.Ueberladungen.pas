unit Dcc.Ueberladungen;

// #1371, Regel overload-resolution: Aufrufe überladener Routinen, die dcc ohne
// Meldung übersetzt. Atlas darf hier weder E2250 noch E2251 melden.

interface

procedure Lauf;

implementation

type
  TZahl = Integer;
  TBetrag = record
    Wert: Double;
    class operator Implicit(AWert: Double): TBetrag;
  end;

  TBasis = class
  public
    procedure Nenne(AWert: Integer); overload;
  end;

  TKind = class(TBasis)
  public
    procedure Nenne(const AText: string); overload;
  end;

const
  cZeichen = 'a';

class operator TBetrag.Implicit(AWert: Double): TBetrag;
begin
  Result.Wert := AWert;
end;

procedure TBasis.Nenne(AWert: Integer);
begin
end;

procedure TKind.Nenne(const AText: string);
begin
end;

procedure Nimm(AWert: Integer); overload;
begin
end;

procedure Nimm(const AWert: string); overload;
begin
end;

procedure Zahl(AWert: Double); overload;
begin
end;

procedure Zahl(const AText: string); overload;
begin
end;

procedure Zeichen(AWert: Char); overload;
begin
end;

procedure Zeichen(AWert: Integer); overload;
begin
end;

procedure Buche(const ABetrag: TBetrag); overload;
begin
end;

procedure Buche(const AText: string); overload;
begin
end;

procedure Zaehle(AWert: TZahl); overload;
begin
end;

procedure Zaehle(const AText: string); overload;
begin
end;

procedure Zwei(AWert: Integer; AText: string = ''); overload;
begin
end;

procedure Zwei(AWert: Integer; AZahl: Integer = 0); overload;
begin
end;

procedure Wahl(AWert: Integer; AText: string = ''); overload;
begin
end;

procedure Wahl(AWert: Double; AZahl: Integer = 0); overload;
begin
end;

procedure Spaet(AWert: Integer; AText: string = ''); overload;
begin
end;

procedure Lauf;
var
  mKind: TKind;
begin
  Nimm(1); // UL1: Ganzzahl an Integer
  Nimm('Text'); // UL2: String-Literal an string
  Nimm('a'); // UL3: Char-Literal an string
  Zahl(1); // UL4: Ganzzahl an Double
  Zeichen(cZeichen); // UL5: untypisierte Konstante 'a' ist ein Char
  Buche(1.5); // UL6: Record mit Implicit-Operator
  Zaehle(1); // UL7: Alias auf Integer
  Zwei(1, 'x'); // UL8: das zweite Argument entscheidet
  Zwei(1, 2); // UL8
  Wahl(1); // UL9: Integer passt genauer als Double
  Spaet(1); // UL10: die zweite Überladung steht erst hinter Lauf
  mKind := TKind.Create;
  try
    mKind.Nenne(1); // UL11: Überladung aus dem Vorfahren
  finally
    mKind.Free;
  end;
end;

procedure Spaet(AWert: Integer; AZahl: Integer = 0); overload;
begin
end;

end.
