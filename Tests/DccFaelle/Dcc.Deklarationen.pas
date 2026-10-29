unit Dcc.Deklarationen;

// #1380, Regeln declaration-invalid, abstract-declaration-invalid,
// default-property-invalid, property-accessor-invalid, unsatisfied-forward,
// invalid-var-argument und calling-convention-required: Diese Formen
// übersetzt dcc, Atlas darf hier nichts melden.

interface

type
  TBytes2 = packed array[0..1] of Byte; // DK1 packed vor array
  TPaar = packed record // DK2 packed vor record
    A, B: Byte;
  end;

  PKnoten = ^TKnoten;
  TKnoten = record
    Wert: Integer;
    Naechster: PKnoten; // DK3 Zeiger auf den eigenen Record
  end;

  TBasis = class;
  TBasis = class
  public
    procedure Tu; virtual; abstract;
  end;
  TAbleitung = class(TBasis) // DK4 Vorfahr erst vorwärts, dann vollständig
  end;

  TFertig = class sealed(TBasis) // DK5 sealed implementiert alles Abstrakte
  public
    procedure Tu; override;
  end;

  TListe = class
  private
    function GetPerName(const AName: string): Integer;
    function GetPerIndex(AIndex: Integer): Integer;
  public
    property Eintrag[const AName: string]: Integer read GetPerName; default; // DK6 default überladen
    property Eintrag[AIndex: Integer]: Integer read GetPerIndex; default; // DK6
  end;

  TZaehler = class
  private
    class var FAnzahl: Integer;
  public
    class property Anzahl: Integer read FAnzahl; // DK7 Klassen-Property ohne Selektor
  end;

  TDuo = class
  public
    constructor Create(AWert: Integer); overload;
    constructor Erzeuge(AWert: Integer); // DK8 gleiche Parameter, kein C++-Ausgang
  end;

  IDispBeispiel = dispinterface
    ['{6B5F4E1A-2C3D-4E5F-8A9B-0C1D2E3F4A5B}']
    property Wert: Integer dispid 1; // DK9 dispinterface ohne read/write
  end;

procedure Ausgabe(const AFormat: PAnsiChar); cdecl; varargs; external 'msvcrt.dll' name 'printf'; // DK10

function Adresse: Pointer;

implementation

procedure TFertig.Tu;
begin
end;

function TListe.GetPerName(const AName: string): Integer;
begin
  Result := Length(AName);
end;

function TListe.GetPerIndex(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

constructor TDuo.Create(AWert: Integer);
begin
  inherited Create;
end;

constructor TDuo.Erzeuge(AWert: Integer);
begin
  inherited Create;
end;

var
  GFeld: array[0..1] of Integer;

function Adresse: Pointer;
begin
  Result := @GFeld[1]; // DK11 @ vor einem Array-Element
end;

end.
