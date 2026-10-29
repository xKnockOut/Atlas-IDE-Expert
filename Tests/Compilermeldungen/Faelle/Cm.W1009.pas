unit Cm.W1009;

// W1009 Redeclaration hides a member in the base class
// Erwartet: -
// Delphi 13 meldet hier nichts (Win32 und Win64).

interface

type
  TBasis = class
  private
    FWert: Integer;
  public
    property Wert: Integer read FWert;
  end;

  TKind = class(TBasis)
  public
    Wert: string; // <- ohne Meldung
  end;

implementation

end.
