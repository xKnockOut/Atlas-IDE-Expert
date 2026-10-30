unit Dcc.Generics;

// #1376, Regeln generic-declaration-invalid und generic-inference-failed:
// Muster, bei denen Atlas still bleibt. dcc soll sie ohne Meldung übersetzen.

interface

uses
  System.SysUtils,
  System.Variants,
  System.Classes;

type
  IZeigbar = interface
    ['{6F1E2B6A-3C51-4E37-9C0F-0B8F4E1A2D10}']
  end;

  TBehaelter<T> = class
  public
    procedure Machen;
  end;

  TFest = class
  public
    procedure Machen;
  end;

  TListe = TBehaelter<Integer>; // GN3: Alias auf einen instanziierten Typ
  TZahl = type Integer; // GN3: type vor einem normalen Typ

  TMitSchnittstelle<T: TComponent, IZeigbar, constructor> = class // GN6
  end;

  TFabrik = class
  public
    class function Aus<T>(A: T): T; static;
    class procedure Paar<T>(A, B: T); static;
  end;

procedure Fall;

implementation

procedure TBehaelter<T>.Machen;
var
  mProc: TProc;
begin
  mProc := procedure // GN1: anonyme Methode statt lokaler Routine
    begin
    end;
  mProc;
end;

procedure TFest.Machen;

  procedure Innen; // GN2: lokale Routine in einer normalen Methode
  begin
  end;

begin
  Innen;
end;

class function TFabrik.Aus<T>(A: T): T;
begin
  Result := A;
end;

class procedure TFabrik.Paar<T>(A, B: T);
begin
end;

procedure Fall;
var
  mZahl: Integer;
  mWert: Double;
  mText: string;
  mVariant: Variant;
begin
  mZahl := 1;
  mWert := 2;
  mText := 'a';
  mVariant := 3;
  mZahl := TFabrik.Aus(mZahl); // GN4: T aus dem Argument abgeleitet
  TFabrik.Paar(1, 2); // GN5
  TFabrik.Paar(mText, 'b'); // GN5
  TFabrik.Paar(mZahl, mWert); // GN7: Integer und Double
  TFabrik.Paar(mVariant, 1); // GN8: Variant und Zahl
  if mWert > mZahl then
    Writeln(mText);
end;

end.
