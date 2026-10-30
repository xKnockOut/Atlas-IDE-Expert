unit Cm.E1012Gegen;

// E1012 Constant expression violates subrange bounds
// Erwartet: -
// #1372: Gegenfall: Index im Bereich, dynamische und offene Arrays, Strings.

interface

implementation

function Lesen(const AOffen: array of Integer): Integer;
var
  mFeld: array[0..2] of Integer;
  mDynamisch: array of Integer;
  mText: string;
begin
  mFeld[2] := 0;
  SetLength(mDynamisch, 10);
  mDynamisch[5] := mFeld[2];
  mText := 'abc';
  Result := AOffen[5] + mDynamisch[5] + Ord(mText[3]);
end;

end.
