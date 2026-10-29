unit Cm.E2431;

// E2431 for-in statement cannot operate on collection type because it does not contain a member
// Erwartet: E2431

interface

implementation

type
  TOhneMoveNext = class
  public
    function GetCurrent: Integer;
    property Current: Integer read GetCurrent;
  end;

  TSammlung = class
  public
    function GetEnumerator: TOhneMoveNext;
  end;

function TOhneMoveNext.GetCurrent: Integer;
begin
  Result := 0;
end;

function TSammlung.GetEnumerator: TOhneMoveNext;
begin
  Result := nil;
end;

procedure Fall;
var
  mSammlung: TSammlung;
  mWert: Integer;
begin
  mSammlung := nil;
  for mWert in mSammlung do // <- E2431
    ;
end;

end.
