unit Dcc.Ueberladungen.Gegen;

// #1371, Regel overload-resolution: Aufrufe, die dcc mit E2250 (keine
// Überladung passt) bzw. E2251 (mehrdeutig) ablehnt.

interface

procedure Lauf;

implementation

type
  TText = string;
  TZahl = Integer;

  TRechner = class
  public
    procedure Merke(AWert: Integer); overload;
    procedure Merke(const AText: string); overload;
    procedure Teile(AWert: Integer; ARest: Integer = 0); overload;
    procedure Teile(AWert: Integer; const AText: string = ''); overload;
  end;

  TBasis = class
  public
    procedure Nenne(AWert: Integer); overload;
  end;

  TKind = class(TBasis)
  public
    procedure Nenne(const AText: string); overload;
  end;

procedure TRechner.Merke(AWert: Integer);
begin
end;

procedure TRechner.Merke(const AText: string);
begin
end;

procedure TRechner.Teile(AWert: Integer; ARest: Integer);
begin
end;

procedure TRechner.Teile(AWert: Integer; const AText: string);
begin
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

procedure Zaehle(AWert: TZahl); overload;
begin
end;

procedure Zaehle(const AText: TText); overload;
begin
end;

procedure Zwei(AWert: Integer; AText: string = ''); overload;
begin
end;

procedure Zwei(AWert: Integer; AZahl: Integer = 0); overload;
begin
end;

procedure Verwirrt(I: Integer); overload;
begin
end;

procedure Verwirrt(I: Integer; J: Integer = 0); overload;
begin
end;

procedure Lauf;
var
  mZahl: Double;
  mRechner: TRechner;
  mKind: TKind;
begin
  mZahl := 1.5;
  Nimm(1.5); // UG1: E2250, Gleitkomma an Integer oder string
  Nimm(True); // UG2: E2250, Boolean
  Nimm(mZahl); // UG3: E2250, Double-Variable
  Nimm(1, 2); // UG4: E2250, zu viele Argumente für jede Überladung
  Nimm; // UG5: E2250, ohne Argumente
  Zaehle(1.5); // UG6: E2250, Aliase auf Integer und string
  Zwei(1); // UG7: E2251, nur die Standardparameter unterscheiden sich
  Verwirrt(1); // UG8: E2251, Beispiel der Delphi-Hilfe
  mRechner := TRechner.Create;
  mKind := TKind.Create;
  try
    mRechner.Merke(1.5); // UG9: E2250 an einer Methode
    mRechner.Teile(1); // UG10: E2251 an einer Methode
    mKind.Nenne(1.5); // UG11: E2250 samt Überladung aus dem Vorfahren
  finally
    mKind.Free;
    mRechner.Free;
  end;
end;

end.
