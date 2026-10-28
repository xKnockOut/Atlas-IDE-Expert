unit Dcc.Interfaces.Gegen;

// #1328, Gegentests zu interface-declaration-invalid: Hier soll dcc melden.

interface

type
  IGegenBasis = interface
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A011}']
    function GetWert: Integer;
    property Wert: Integer read GetWert;
  end;

  IGegenOhneTyp = interface(IGegenBasis)
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A012}']
    property Wert; // IG1: Neudeklaration ohne Typ (E2206)
  end;

  IGegenGeerbt = interface(IGegenBasis)
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A013}']
    property Neu: Integer read GetWert; // IG2: neue Property mit geerbtem Getter (E2370?)
  end;

implementation

end.
