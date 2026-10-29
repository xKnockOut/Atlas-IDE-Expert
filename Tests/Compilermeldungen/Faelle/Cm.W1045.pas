unit Cm.W1045;

// W1045 Property declaration references ancestor private
// Erwartet: W1045

interface

uses
  Cm.Hilfe.W1045;

type
  TKind = class(TBasisPrivat)
  public
    property Wert: Integer read FWert; // <- W1045
  end;

implementation

end.
