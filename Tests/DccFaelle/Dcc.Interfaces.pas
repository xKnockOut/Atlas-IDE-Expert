unit Dcc.Interfaces;

// #1328, Regel interface-declaration-invalid (E2206, früher E2370): abgeleitetes
// Interface deklariert eine Property neu, um write zu ergänzen (DUnitX, F04),
// oder nutzt einen geerbten Getter für eine neue Property.

interface

type
  INurLesen = interface
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A001}']
    function GetAnzahl: Integer;
    property Anzahl: Integer read GetAnzahl;
  end;

  ILesenSchreiben = interface(INurLesen)
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A002}']
    procedure SetAnzahl(AWert: Integer);
    property Anzahl: Integer read GetAnzahl write SetAnzahl; // ID1
  end;

  INeuMitGeerbtem = interface(INurLesen)
    ['{4E1C1D35-2F6B-4C0F-9B7E-0C9A47E1A003}']
    property Zahl: Integer read GetAnzahl; // ID3 (vorher IG2): neue Property mit geerbtem Getter
  end;

  INurLesenListe<T> = interface
    function GetKapazitaet: Integer;
    property Kapazitaet: Integer read GetKapazitaet;
  end;

  IListe<T> = interface(INurLesenListe<T>)
    procedure SetKapazitaet(AWert: Integer);
    property Kapazitaet: Integer read GetKapazitaet write SetKapazitaet; // ID2: generisch (DUnitX.Generics)
  end;

implementation

end.
