unit Cm.E2228b;

// E2228 A dispinterface type cannot have an ancestor interface
// Erwartet: -
// Gegenfall zu E2228 bis E2231 (#1374): zulässige dispinterface-Formen, die dcc
// ohne Meldung übersetzt und zu denen dispinterface-invalid still bleibt.

interface

const
  cListeGuid = '{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2281}';

type
  DAnzeige = dispinterface;

  DListe = dispinterface
    [cListeGuid]
    property Eintrag[AIndex: Integer]: DAnzeige readonly dispid 0; default;
  end;

  DAnzeige = dispinterface
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2280}']
    procedure Machen; dispid 1;
    function Wert(AIndex: Integer): Integer; dispid 2;
    property Name: WideString readonly dispid 3;
    property Ziel: WideString writeonly dispid 4;
    property Breite: Integer dispid 5;
  end;

implementation

end.
