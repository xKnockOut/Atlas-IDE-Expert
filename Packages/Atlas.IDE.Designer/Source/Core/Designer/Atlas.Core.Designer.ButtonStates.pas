unit Atlas.Core.Designer.ButtonStates;

// Gemerkter Zustand der Umschaltknöpfe der Designer-Leiste, ohne VCL und
// Windows: Die Werkzeug-Objekte (Datenbindung, Tab-Reihenfolge, Abstände
// messen, Griffe, Schnellleiste) entstehen mit der Leiste neu, beim Start
// der IDE ebenso wie beim Aus- und Einschalten der Leiste oder des Moduls.
// Ihr Zustand steht darum als Text in der Zustandseinstellung
// designer.barButtons, etwa „dataBindings=1, measure=0“:
// - je Knopf Kennung=1 (gedrückt) oder Kennung=0, Kennungen ohne
//   Groß-/Kleinschreibung, nach Kennung sortiert, durch „, “ getrennt;
// - ein Knopf ohne Eintrag hat seine Vorgabe; Einträge ohne „=“, mit leerer
//   Kennung oder anderem Wert als 0/1 zählen nicht.

interface

type
  TAtlasDesignerButtonStates = record
  public const
    cSeparator = ',';
    cJoin = ', ';
    cPressed = '1';
    cReleased = '0';
  public
    /// <summary>Gemerkter Zustand des Knopfs AId in AText; ADefault ohne gültigen Eintrag.</summary>
    class function Pressed(const AText, AId: string; ADefault: Boolean): Boolean; static;
    /// <summary>AText mit dem Zustand APressed für AId; ungültige Einträge fallen weg, die Reihenfolge folgt der
    /// Kennung. Leere Kennung: AText bereinigt.</summary>
    class function WithPressed(const AText, AId: string; APressed: Boolean): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TEntry = record
    Id: string;
    Pressed: Boolean;
  end;

/// <summary>Eintrag „Kennung=0|1“ lesen; False bei ungültigem Eintrag.</summary>
function TryEntry(const APart: string; out AEntry: TEntry): Boolean;
var
  mEqual: Integer;
  mValue: string;
begin
  AEntry := Default(TEntry);
  mEqual := Pos('=', APart);
  if mEqual = 0 then
  begin
    Exit(False);
  end;
  AEntry.Id := Trim(Copy(APart, 1, mEqual - 1));
  mValue := Trim(Copy(APart, mEqual + 1, MaxInt));
  AEntry.Pressed := mValue = TAtlasDesignerButtonStates.cPressed;
  Result := (AEntry.Id <> '') and (AEntry.Pressed or (mValue = TAtlasDesignerButtonStates.cReleased));
end;

/// <summary>Gültige Einträge von AText; bei doppelter Kennung gilt der letzte.</summary>
function Entries(const AText: string): TList<TEntry>;
var
  mPart: string;
  mEntry: TEntry;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := TList<TEntry>.Create;
  for mPart in AText.Split([TAtlasDesignerButtonStates.cSeparator]) do
  begin
    if not TryEntry(mPart, mEntry) then
    begin
      Continue;
    end;
    mFound := False;
    for mIndex := 0 to Result.Count - 1 do
    begin
      if SameText(Result[mIndex].Id, mEntry.Id) then
      begin
        Result[mIndex] := mEntry;
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Result.Add(mEntry);
    end;
  end;
end;

class function TAtlasDesignerButtonStates.Pressed(const AText, AId: string; ADefault: Boolean): Boolean;
var
  mEntries: TList<TEntry>;
  mEntry: TEntry;
begin
  Result := ADefault;
  mEntries := Entries(AText);
  try
    for mEntry in mEntries do
    begin
      if SameText(mEntry.Id, AId) then
      begin
        Result := mEntry.Pressed;
      end;
    end;
  finally
    mEntries.Free;
  end;
end;

class function TAtlasDesignerButtonStates.WithPressed(const AText, AId: string; APressed: Boolean): string;
var
  mEntries: TList<TEntry>;
  mEntry: TEntry;
  mParts: TArray<string>;
  mIndex: Integer;
begin
  mEntries := Entries(AText + cSeparator + Trim(AId) + '=' + cReleased);
  try
    // Die Kennung kam ganz hinten dazu und gilt damit; hier den gewünschten Zustand setzen.
    for mIndex := 0 to mEntries.Count - 1 do
    begin
      if SameText(mEntries[mIndex].Id, Trim(AId)) then
      begin
        mEntry := mEntries[mIndex];
        mEntry.Pressed := APressed;
        mEntries[mIndex] := mEntry;
      end;
    end;
    // Kennungen sind eindeutig (ohne Groß-/Kleinschreibung): Die Sortierung braucht keinen weiteren Schlüssel.
    mEntries.Sort(TComparer<TEntry>.Construct(
      function(const ALeft, ARight: TEntry): Integer
      begin
        Result := CompareText(ALeft.Id, ARight.Id);
      end));
    mParts := nil;
    SetLength(mParts, mEntries.Count);
    for mIndex := 0 to mEntries.Count - 1 do
    begin
      mParts[mIndex] := mEntries[mIndex].Id + '=' + cReleased;
      if mEntries[mIndex].Pressed then
      begin
        mParts[mIndex] := mEntries[mIndex].Id + '=' + cPressed;
      end;
    end;
    Result := string.Join(cJoin, mParts);
  finally
    mEntries.Free;
  end;
end;

end.
