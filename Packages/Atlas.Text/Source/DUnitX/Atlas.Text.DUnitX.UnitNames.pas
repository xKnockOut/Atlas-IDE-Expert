unit Atlas.Text.DUnitX.UnitNames;

// Namen von Unit und Testunit (#189) nach dem Muster testUnits.pattern
// ({unit}.Tests): Testgerüst, Wechsel zwischen Unit und Test und die
// Auswirkungsanalyse (welche Testunit gehört zu welcher Unit) nutzen dieselbe
// Zuordnung.

interface

type
  TTestUnitNames = class
  public const
    cDefaultPattern = '{unit}.Tests';
    cPlaceholder = '{unit}';
  public
    /// <summary>APattern, wenn es {unit} enthält, sonst die Vorgabe.</summary>
    class function PatternOrDefault(const APattern: string): string; static;
    /// <summary>Name der Testunit zu AUnitName nach APattern; leeres Muster gilt als Vorgabe.</summary>
    class function TestUnitName(const AUnitName, APattern: string): string; static;
    /// <summary>Getestete Unit zu einer Testunit; False, wenn der Name nicht zum Muster passt.</summary>
    class function TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TTestUnitNames }

class function TTestUnitNames.PatternOrDefault(const APattern: string): string;
begin
  Result := APattern;
  if Pos(cPlaceholder, Result) = 0 then
  begin
    Result := cDefaultPattern;
  end;
end;

class function TTestUnitNames.TestUnitName(const AUnitName, APattern: string): string;
begin
  Result := StringReplace(PatternOrDefault(APattern), cPlaceholder, AUnitName, [rfIgnoreCase]);
end;

class function TTestUnitNames.TestedUnitName(const ATestUnitName, APattern: string; out AUnitName: string): Boolean;
var
  mPattern, mPrefix, mSuffix: string;
  mAt: Integer;
begin
  AUnitName := '';
  mPattern := PatternOrDefault(APattern);
  mAt := Pos(cPlaceholder, mPattern);
  mPrefix := Copy(mPattern, 1, mAt - 1);
  mSuffix := Copy(mPattern, mAt + Length(cPlaceholder), MaxInt);
  Result := (Length(ATestUnitName) > Length(mPrefix) + Length(mSuffix)) and StartsText(mPrefix, ATestUnitName) and
    EndsText(mSuffix, ATestUnitName);
  if Result then
  begin
    AUnitName := Copy(ATestUnitName, Length(mPrefix) + 1, Length(ATestUnitName) - Length(mPrefix) - Length(mSuffix));
  end;
end;

end.
