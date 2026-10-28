unit Dcc.Vorwaerts;

// #1328, Regel type-used-before-declaration: Klassenreferenz vor der Klasse im
// selben type-Block (Indy, DelphiAST).

interface

type
  TKnotenKlasse = class of TKnoten; // TU1
  TKnoten = class
  public
    class function Neu(AKlasse: TKnotenKlasse): TKnoten;
  end;

  TListeKlasse = class of TListe; // TU2: abgeleitete Klasse
  TListe = class(TKnoten)
  end;

implementation

class function TKnoten.Neu(AKlasse: TKnotenKlasse): TKnoten;
begin
  Result := AKlasse.Create;
end;

end.
