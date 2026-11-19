unit Atlas.Text.Arrays;

// Kleine Helfer für dynamische Arrays, gemeinsam für Server und Plugin: Vergleich zweier Arrays und Listen von
// Texten ohne Dubletten.

interface

uses
  System.SysUtils,
  System.Generics.Defaults;

type
  TTextArrays = class
  public
    /// <summary>Gleich viele Elemente und paarweise gleich (TEqualityComparer&lt;T&gt;.Default: Texte mit
    /// Groß-/Kleinschreibung, Interfaces als Zeiger).</summary>
    class function Same<T>(const A, B: TArray<T>): Boolean; static;
    /// <summary>AValue an AList anhängen, wenn es nicht leer ist und ohne Groß-/Kleinschreibung noch fehlt.</summary>
    class procedure AddText(var AList: TArray<string>; const AValue: string); static;
  end;

implementation

{ TTextArrays }

class function TTextArrays.Same<T>(const A, B: TArray<T>): Boolean;
var
  mComparer: IEqualityComparer<T>;
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  mComparer := TEqualityComparer<T>.Default;
  for mIndex := 0 to High(A) do
  begin
    if not mComparer.Equals(A[mIndex], B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

class procedure TTextArrays.AddText(var AList: TArray<string>; const AValue: string);
var
  mItem: string;
begin
  if AValue = '' then
  begin
    Exit;
  end;
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AValue];
end;

end.
