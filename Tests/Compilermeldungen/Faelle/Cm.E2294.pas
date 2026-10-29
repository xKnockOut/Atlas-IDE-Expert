unit Cm.E2294;

// E2294 A class helper that descends from '%s' can only help classes that are descendents '%s'
// Erwartet: E2294

interface

uses
  System.Classes;

type
  THelferEins = class helper for TStream
  end;

  THelferZwei = class helper(THelferEins) for TObject // <- E2294
  end;

implementation

end.
