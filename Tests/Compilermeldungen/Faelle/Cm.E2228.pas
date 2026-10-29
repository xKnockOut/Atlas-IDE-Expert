unit Cm.E2228;

// E2228 A dispinterface type cannot have an ancestor interface
// Erwartet: E2228

interface

type
  IBasis = interface
  end;

  DAnzeige = dispinterface(IBasis) // <- E2228
    ['{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2228}']
  end;

implementation

end.
