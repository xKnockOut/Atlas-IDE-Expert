unit Cm.W1045;

// W1045 Property declaration references ancestor private
// Erwartet: E2168
// Delphi 13 meldet hier E2168 statt W1045.

interface

uses
  Cm.Hilfe.W1045;

type
  TKind = class(TBasisPrivat)
  public
    property Wert: Integer read FWert; // <- E2168
  end;

implementation

end.
