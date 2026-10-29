unit Cm.E2232;

// E2232 Interface '%s' has no interface identification
// Erwartet: E2232

interface

implementation

type
  IOhneGuid = interface
    procedure Machen;
  end;

procedure Fall;
var
  mQuelle: IInterface;
  mZiel: IOhneGuid;
begin
  mQuelle := nil;
  mZiel := mQuelle as IOhneGuid; // <- E2232
end;

end.
