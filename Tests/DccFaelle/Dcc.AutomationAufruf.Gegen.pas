unit Dcc.AutomationAufruf.Gegen;

// #1373, Gegentests zu automation-invalid bei Aufrufen über Variant: Hier soll
// dcc melden. Bestätigt sind OleVariant mit Record (E2160) und Variant mit
// Pointer (E2281); diese Fälle klären, ob der Code von der Art des Variants
// oder vom Typ des Arguments abhängt.

interface

procedure Aufrufe;

implementation

uses
  System.Variants;

type
  TPunkt = record
    X, Y: Integer;
  end;
  PPunkt = ^TPunkt;

procedure Aufrufe;
var
  mVar: Variant;
  mOle: OleVariant;
  mPunkt: TPunkt;
  mZeiger: Pointer;
  mTypisiert: PPunkt;
begin
  mVar := Unassigned;
  mOle := Unassigned;
  mPunkt := Default(TPunkt);
  mZeiger := nil;
  mTypisiert := nil;
  mVar.Machen(mPunkt); // AC1: Variant mit Record (E2281 oder E2160?)
  mOle.Machen(mZeiger); // AC2: OleVariant mit Pointer (E2160 oder E2281?)
  mVar.Machen(mTypisiert); // AC3: typisierter Zeiger (E2281?)
  mOle.Dokument.Oeffnen(mPunkt); // AC4: Kette über einen OleVariant (E2160)
  mVar.Machen(Wert := 1, 2); // AC5: Variant, unbenannt nach benannt (E2166)
end;

end.
