unit Atlas.Tests.Lists;

// Testhilfe: kleine Abfragen auf Listen von Texten, die viele Fakes und Tests brauchen (Aufrufe merken, Namen
// suchen).

interface

type
  TTestLists = record
  public
    /// <summary>True, wenn AList den Text AName enthält (Groß-/Kleinschreibung zählt).</summary>
    class function Contains(const AList: TArray<string>; const AName: string): Boolean; static;
    /// <summary>Hängt AEntry an AText an, mit ASeparator, wenn AText nicht leer ist.</summary>
    class procedure Append(var AText: string; const AEntry, ASeparator: string); static;
  end;

implementation

{ TTestLists }

class function TTestLists.Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AList do
  begin
    if mName = AName then
    begin
      Exit(True);
    end;
  end;
end;

class procedure TTestLists.Append(var AText: string; const AEntry, ASeparator: string);
begin
  if AText <> '' then
  begin
    AText := AText + ASeparator;
  end;
  AText := AText + AEntry;
end;

end.
