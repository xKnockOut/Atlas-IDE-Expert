unit Cm.E2021;

// E2021 Class type required
// Erwartet: E2021

interface

type
  TRec = record
    Wert: Integer;
  end;

  TKlasse = class(TRec) // <- E2021
  end;

implementation

end.
