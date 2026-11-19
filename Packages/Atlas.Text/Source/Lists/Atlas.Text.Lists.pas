unit Atlas.Text.Lists;

// Kleine Suchen und Vergleiche auf Arrays (gemeinsam für Server und Plugin).
// Ob ein String in einer Liste steht, sagen MatchText (ohne Groß-/Kleinschreibung)
// und MatchStr (genau) aus System.StrUtils; dafür gibt es hier nichts Eigenes.

interface

uses
  System.Generics.Collections;

type
  TTextLists = class
  public
    /// <summary>Kommt AValue in AValues vor?</summary>
    class function ContainsInteger(const AValues: TArray<Integer>; AValue: Integer): Boolean; static;
    /// <summary>Gleich lang und an jeder Stelle gleich ohne Rücksicht auf Groß-/Kleinschreibung?</summary>
    class function SameTexts(const A, B: TArray<string>): Boolean; static;
    /// <summary>Hängt AName an AList an, wenn er nicht leer ist und dort noch nicht steht (ohne Rücksicht auf
    /// Groß-/Kleinschreibung). Für kurze Listen; lange über AddUniqueText.</summary>
    class procedure AddText(var AList: TArray<string>; const AName: string); static;
    /// <summary>Hängt AName an AList an, wenn er nicht leer ist und ASeen ihn noch nicht kennt (ohne Rücksicht auf
    /// Groß-/Kleinschreibung); merkt ihn dann in ASeen.</summary>
    class procedure AddUniqueText(var AList: TArray<string>; ASeen: TDictionary<string, Boolean>;
      const AName: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TTextLists }

class function TTextLists.ContainsInteger(const AValues: TArray<Integer>; AValue: Integer): Boolean;
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

class function TTextLists.SameTexts(const A, B: TArray<string>): Boolean;
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

class procedure TTextLists.AddText(var AList: TArray<string>; const AName: string);
begin
  if (AName <> '') and not MatchText(AName, AList) then
  begin
    AList := AList + [AName];
  end;
end;

class procedure TTextLists.AddUniqueText(var AList: TArray<string>; ASeen: TDictionary<string, Boolean>;
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
