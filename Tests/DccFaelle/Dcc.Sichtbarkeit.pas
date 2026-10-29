unit Dcc.Sichtbarkeit;

// #1328, Regel inaccessible-member: Zugriffe aus einer anderen Unit, die Delphi
// nach den Korpus-Projekten übersetzt.

interface

uses
  Dcc.Sichtbarkeit.Basis;

type
  TListe<T> = class
  private
    FKopf: TKnoten<T>;
  public
    function Zweiter: TKnoten<T>;
    function ZweiterWert: T;
  end;

  TWoerterbuch<K> = class
  private
    FBaum: TBaum<K>;
  public
    function Hat(const AWert: K): Boolean;
    function Anzahl: Integer;
  end;

function KonkretZweiter(AKnoten: TKnoten<Integer>): TKnoten<Integer>;
function ErzeugeInspektor: TObject;

implementation

function TListe<T>.Zweiter: TKnoten<T>;
begin
  Result := FKopf.FNaechster; // IM1: protected-Feld einer generischen Klasse, aus generischem Code
end;

function TListe<T>.ZweiterWert: T;
begin
  Result := FKopf.FNaechster.FWert; // IM1
end;

function TWoerterbuch<K>.Hat(const AWert: K): Boolean;
begin
  Result := FBaum.Finde(AWert) <> nil; // IM2: protected-Methode einer generischen Klasse, aus generischem Code
end;

function TWoerterbuch<K>.Anzahl: Integer;
begin
  Result := FBaum.FAnzahl; // IM2: geerbtes protected-Feld einer nicht generischen Basis, aus generischem Code
end;

function KonkretZweiter(AKnoten: TKnoten<Integer>): TKnoten<Integer>;
begin
  Result := AKnoten.FNaechster; // IM3: protected-Feld einer generischen Klasse, aus nicht generischem Code
end;

function ErzeugeInspektor: TObject;
begin
  Result := TInspektor.Create; // IM4: private class constructor Create verdeckt nicht TObject.Create (Spring.Container)
end;

end.
