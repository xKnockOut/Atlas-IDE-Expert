unit Atlas.Text.Arrays;

// Kleine Helfer für dynamische Arrays, gemeinsam für Server und Plugin: Vergleich zweier Arrays, Suchen und Listen
// von Texten ohne Dubletten. Ob ein String in einer Liste steht, sagen MatchText (ohne Groß-/Kleinschreibung) und
// MatchStr (genau) aus System.StrUtils, die Stelle IndexText bzw. IndexStr.

interface

uses
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

type
  TTextArrays = class
  public
    /// <summary>Gleich viele Elemente und paarweise gleich (TEqualityComparer&lt;T&gt;.Default: Texte mit
    /// Groß-/Kleinschreibung, Interfaces als Zeiger).</summary>
    class function Same<T>(const A, B: TArray<T>): Boolean; static;
    /// <summary>AValue an AList anhängen, wenn es nicht leer ist und ohne Groß-/Kleinschreibung noch fehlt.</summary>
    class procedure AddText(var AList: TArray<string>; const AValue: string); static;
    /// <summary>Kommt AValue in AValues vor?</summary>
    class function ContainsInteger(const AValues: TArray<Integer>; AValue: Integer): Boolean; static;
    /// <summary>0, 1, …, ACount - 1; leer für ACount &lt;= 0.</summary>
    class function Indices(ACount: Integer): TArray<Integer>; static;
    /// <summary>Enthält AText einen der Teile AParts (ohne Groß-/Kleinschreibung)?</summary>
    class function ContainsAnyText(const AText: string; const AParts: array of string): Boolean; static;
    /// <summary>Gleich lang und an jeder Stelle gleich ohne Rücksicht auf Groß-/Kleinschreibung?</summary>
    class function SameTexts(const A, B: TArray<string>): Boolean; static;
    /// <summary>Stelle des ersten Elements, dessen Text (ATextOf) ohne Rücksicht auf Groß-/Kleinschreibung AText
    /// ist; -1 ohne.</summary>
    class function IndexOfText<T>(const AItems: TArray<T>; const AText: string;
      const ATextOf: TFunc<T, string>): Integer; static;
    /// <summary>Zahl zum Schlüssel AKey aus den parallelen Arrays AKeys und ACounts (ohne Rücksicht auf
    /// Groß-/Kleinschreibung); 0 ohne.</summary>
    class function CountOfText(const AKeys: TArray<string>; const ACounts: TArray<Integer>;
      const AKey: string): Integer; static;
    /// <summary>Wie AddText für lange Listen: ASeen merkt die schon angehängten Namen (klein geschrieben).</summary>
    class procedure AddUniqueText(var AList: TArray<string>; ASeen: TDictionary<string, Boolean>;
      const AName: string); static;
  end;

implementation

uses
  System.StrUtils;

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

class function TTextArrays.ContainsInteger(const AValues: TArray<Integer>; AValue: Integer): Boolean;
var
  mValue: Integer;
begin
  for mValue in AValues do
  begin
    if mValue = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTextArrays.Indices(ACount: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  if ACount <= 0 then
  begin
    Exit;
  end;
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := mIndex;
  end;
end;

class function TTextArrays.ContainsAnyText(const AText: string; const AParts: array of string): Boolean;
var
  mPart: string;
begin
  for mPart in AParts do
  begin
    if ContainsText(AText, mPart) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTextArrays.SameTexts(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if not SameText(A[mIndex], B[mIndex]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TTextArrays.IndexOfText<T>(const AItems: TArray<T>; const AText: string;
  const ATextOf: TFunc<T, string>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(ATextOf(AItems[mIndex]), AText) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TTextArrays.CountOfText(const AKeys: TArray<string>; const ACounts: TArray<Integer>;
  const AKey: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(AKeys) do
  begin
    if SameText(AKeys[mIndex], AKey) and (mIndex <= High(ACounts)) then
    begin
      Exit(ACounts[mIndex]);
    end;
  end;
end;

class procedure TTextArrays.AddUniqueText(var AList: TArray<string>; ASeen: TDictionary<string, Boolean>;
  const AName: string);
var
  mKey: string;
begin
  mKey := LowerCase(AName);
  if (AName <> '') and not ASeen.ContainsKey(mKey) then
  begin
    ASeen.Add(mKey, True);
    AList := AList + [AName];
  end;
end;

end.
