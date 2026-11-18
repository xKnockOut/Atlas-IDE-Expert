unit Atlas.Core.Designer.Names;

// Namen und Komponentenlisten der Designer-Werkzeuge, ohne VCL und Windows:
// Suche in Namenslisten (ohne Groß-/Kleinschreibung, wie Delphi Bezeichner
// vergleicht), Suche nach Namen in Listen beliebiger Einträge, Namen einer
// Komponentenliste, Bezeichner und Ereignis-Zuweisungen im Formulartext
// prüfen. Die Werkzeuge brauchen das alle; jedes hatte seine eigene
// Kopie.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasDesignerNames = class
  public
    /// <summary>Index des ersten Eintrags von ANames gleich AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOf(const ANames: TArray<string>; const AName: string): Integer; static;
    /// <summary>Kommt AName in ANames vor (ohne Groß-/Kleinschreibung)?</summary>
    class function Contains(const ANames: TArray<string>; const AName: string): Boolean; static;
    /// <summary>Index des ersten Eintrags von AItems, dessen Name (über ANameOf) AName ist; -1 ohne.</summary>
    class function IndexOfName<T>(const AItems: TArray<T>; const AName: string;
      const ANameOf: TFunc<T, string>): Integer; static;
    /// <summary>Steht AComponent (dieselbe Instanz) in AComponents?</summary>
    class function ContainsComponent(const AComponents: TArray<TComponent>; AComponent: TComponent): Boolean;
      static;
    /// <summary>Namen der Komponenten in ihrer Reihenfolge.</summary>
    class function NamesOf(const AComponents: TArray<TComponent>): TArray<string>; static;
    /// <summary>Gültiger Delphi-Bezeichner aus ASCII-Buchstaben, Ziffern und _, nicht leer, ohne Ziffer
    /// vorn?</summary>
    class function IsIdentifier(const AText: string): Boolean; static;
    /// <summary>Weist die Zeile „APath = AValue“ des Formulartexts einem Ereignis einen Handler zu (OnClick =
    /// btnOkClick)?</summary>
    class function IsEventAssignment(const APath, AValue: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils;

const
  /// <summary>Beginn der Namen von Ereignis-Eigenschaften (OnClick).</summary>
  cEventPrefix = 'On';

{ TAtlasDesignerNames }

class function TAtlasDesignerNames.IndexOf(const ANames: TArray<string>; const AName: string): Integer;
begin
  Result := IndexText(AName, ANames);
end;

class function TAtlasDesignerNames.Contains(const ANames: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexOf(ANames, AName) >= 0;
end;

class function TAtlasDesignerNames.IndexOfName<T>(const AItems: TArray<T>; const AName: string;
  const ANameOf: TFunc<T, string>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(ANameOf(AItems[mIndex]), AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasDesignerNames.ContainsComponent(const AComponents: TArray<TComponent>;
  AComponent: TComponent): Boolean;
var
  mItem: TComponent;
begin
  for mItem in AComponents do
  begin
    if mItem = AComponent then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDesignerNames.NamesOf(const AComponents: TArray<TComponent>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AComponents));
  for mIndex := 0 to High(AComponents) do
  begin
    Result[mIndex] := AComponents[mIndex].Name;
  end;
end;

class function TAtlasDesignerNames.IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not (CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) or
      ((mIndex > 1) and CharInSet(AText[mIndex], ['0'..'9']))) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasDesignerNames.IsEventAssignment(const APath, AValue: string): Boolean;
begin
  Result := (Length(APath) > Length(cEventPrefix)) and APath.StartsWith(cEventPrefix) and
    CharInSet(APath[Length(cEventPrefix) + 1], ['A'..'Z']) and IsIdentifier(APath) and IsIdentifier(AValue);
end;

end.
