unit Dcc.Deklarationen.Gegen;

// #1380, Gegentests zu declaration-invalid, unsatisfied-forward,
// invalid-var-argument und calling-convention-required: Hier soll dcc melden.

interface

type
  TGepacktesByte = packed Byte; // DG1 packed vor einem einfachen Typ (E2006)
  TGepacktesObjekt = packed TObject; // DG2 packed vor einer Klasse (E2006)

  TSpaeter = class;
  TFrueh = class(TSpaeter) // DG3 Vorfahr nur vorwärts deklariert (E2086)
  end;
  TSpaeter = class
  end;

  IOhneZugriff = interface
    function GetWert: Integer;
    property Wert: Integer; // DG4 Interface-Property ohne read/write (E2128)
  end;

  TAutomat = class
  automated
    property Wert: Integer; // DG5 automated-Property ohne read/write (E2128)
  end;

procedure Variabel(AWert: Integer); stdcall; varargs; // DG6 varargs ohne external unter Win32 (E2277)

function Produkt(A, B: Integer): Pointer;

implementation

procedure Variabel(AWert: Integer); stdcall; varargs;
begin
end;

function Produkt(A, B: Integer): Pointer;
begin
  Result := @(A * B); // DG7 @ vor einem Ausdruck (E2036)
end;

end.
