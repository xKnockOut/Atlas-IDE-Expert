unit Cm.E2146;

// E2146 Default values must be of ordinal, pointer or small set type
// Erwartet: E2146

interface

type
  TGrosseMenge = set of 0..100;

implementation

procedure Fall(AMenge: TGrosseMenge = [1]); // <- E2146
begin
end;

end.
