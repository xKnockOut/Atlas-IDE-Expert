unit Cm.E2295;

// E2295 A class helper cannot introduce a destructor
// Erwartet: E2295

interface

type
  THelfer = class helper for TObject
  public
    destructor Destroy; override; // <- E2295
  end;

implementation

destructor THelfer.Destroy;
begin
end;

end.
