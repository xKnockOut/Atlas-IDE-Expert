unit Cm.E2465;

// E2465 A record cannot introduce a destructor
// Erwartet: E2465

interface

type
  TRec = record
    destructor Destroy; // <- E2465
  end;

implementation

destructor TRec.Destroy;
begin
end;

end.
