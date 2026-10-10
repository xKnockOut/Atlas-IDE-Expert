unit Argus.Core.Completion.Preview;

// Vorschau im Editor (#434): Welcher Rest des gewählten Eintrags gedämpft
// hinter dem Cursor steht. Nur wenn der Name mit dem Getippten beginnt und
// hinter dem Cursor nichts mehr steht, sonst würde die Vorschau Text verdecken.

interface

type
  TArgusPreview = class
  public
    /// <summary>Rest von AName hinter APrefix; '' wenn er nicht passt oder ARestOfLine nicht leer ist.</summary>
    class function RestOf(const AName, APrefix, ARestOfLine: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TArgusPreview }

class function TArgusPreview.RestOf(const AName, APrefix, ARestOfLine: string): string;
begin
  Result := '';
  if (Trim(ARestOfLine) <> '') or (Length(AName) <= Length(APrefix)) or not StartsText(APrefix, AName) then
    Exit;
  Result := Copy(AName, Length(APrefix) + 1, MaxInt);
end;

end.
