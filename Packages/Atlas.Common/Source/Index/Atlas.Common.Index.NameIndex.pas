unit Atlas.Common.Index.NameIndex;

// Namensindex für die Import-Vorschläge der Vervollständigung (#617).
//
// Die Vervollständigung schlägt Symbole aus Units vor, die noch nicht in den
// uses stehen. Statt bei jeder Anfrage alle Units und alle Symbole (bei
// großen Projekten über 500.000) mit dem unscharfen Vergleich zu prüfen,
// hält der Namensindex nur die importierbaren Symbole (interface, oberste
// Ebene) in einer flachen Liste, Projekt-Units vor der Bibliothek.
//
// Zu jedem Namen gehört eine Zeichenmaske (Buchstaben, Ziffern, "_"). Ein
// Treffer, ob Präfix, Teilwort oder Teilfolge, enthält alle Zeichen der
// Anfrage; fehlt eines in der Maske, entfällt der teure Vergleich.
//
// Der Index ist ein unveränderlicher Schnappschuss (nur verwaltete Arrays):
// Wer ihn kopiert, kann ihn ohne Sperre lesen, auch während ein neuer
// aufgebaut wird. Generation sagt, zu welchem Stand des Index er gehört.
//
// TImportNames.Current hält einen Schnappschuss je Index und baut ihn neu,
// wenn sich der Index geändert hat. Während der Index wächst (Aufbau beim
// Start), ändert er sich ständig; große Schnappschüsse werden dann höchstens
// einmal pro RebuildMs erneuert, damit nicht jede Anfrage neu aufbaut.

interface

uses
  Atlas.Common.Index.Contract;

type
  TImportNameEntry = record
    /// <summary>Position in TImportNameIndex.Units.</summary>
    UnitPos: Integer;
    /// <summary>Position in Units[UnitPos].Symbols.</summary>
    SymbolPos: Integer;
    Mask: UInt64;
  end;

  TImportNameIndex = record
    Generation: Int64;
    Units: TArray<TUnitIndex>;
    /// <summary>Projekt-Units zuerst, dann die Bibliothek.</summary>
    Entries: TArray<TImportNameEntry>;
    /// <summary>Class- und Record-Helper mit Zieltyp (#456), Reihenfolge wie Entries; Mask = 0.</summary>
    Helpers: TArray<TImportNameEntry>;
    /// <summary>Baut den Index aus dem aktuellen Stand von AIndex.</summary>
    class function Build(const AIndex: ISymbolIndex): TImportNameIndex; static;
    /// <summary>Zeichenmaske ohne Groß-/Kleinschreibung; alle übrigen Zeichen teilen sich ein Bit.</summary>
    class function MaskOf(const AName: string): UInt64; static;
    /// <summary>Kann ein Name mit ANameMask zu einer Anfrage mit AQueryMask passen?</summary>
    class function MayMatch(ANameMask, AQueryMask: UInt64): Boolean; static; inline;
    function Count: Integer;
  end;

  TImportNames = class
  public const
    /// <summary>Ab so vielen Einträgen wird höchstens alle RebuildMs neu aufgebaut.</summary>
    LargeCount = 50000;
    RebuildMs = 1000;
  public
    /// <summary>Aktueller Namensindex zu AIndex; threadsicher.</summary>
    class function Current(const AIndex: ISymbolIndex): TImportNameIndex; static;
    /// <summary>AOwner (der Symbolindex als Objekt) wird freigegeben: seinen Schnappschuss verwerfen,
    /// sonst hielte der Cache dessen Units über das Ende hinaus fest.</summary>
    class procedure Forget(AOwner: TObject); static;
  end;

implementation

uses
  System.Diagnostics;

var
  CacheLock: TObject;
  CacheOwner: Pointer;
  CacheNames: TImportNameIndex;
  CacheWatch: TStopwatch;

{ TImportNameIndex }

class function TImportNameIndex.MaskOf(const AName: string): UInt64;
var
  Ch: Char;
begin
  Result := 0;
  for Ch in AName do
    case Ch of
      'a'..'z':
        Result := Result or (UInt64(1) shl (Ord(Ch) - Ord('a')));
      'A'..'Z':
        Result := Result or (UInt64(1) shl (Ord(Ch) - Ord('A')));
      '0'..'9':
        Result := Result or (UInt64(1) shl (26 + Ord(Ch) - Ord('0')));
      '_':
        Result := Result or (UInt64(1) shl 36);
    else
      Result := Result or (UInt64(1) shl 37);
    end;
end;

class function TImportNameIndex.MayMatch(ANameMask, AQueryMask: UInt64): Boolean;
begin
  Result := (ANameMask and AQueryMask) = AQueryMask;
end;

/// <summary>Ist ASymbol ein Eintrag des Namensindex (im interface, nicht Mitglied eines Typs)?</summary>
function IsImportEntry(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := ASymbol.InInterface and (ASymbol.Container = '');
end;

function IsImportHelper(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.HelperType) and (Length(ASymbol.Ancestors) > 0);
end;

/// <summary>Zählt Einträge und Helfer, damit Build die Arrays einmal anlegt.</summary>
procedure CountImportEntries(const AUnits: TArray<TUnitIndex>; out AEntries, AHelpers: Integer);
var
  mUnitPos, mSymbolPos: Integer;
begin
  AEntries := 0;
  AHelpers := 0;
  for mUnitPos := 0 to High(AUnits) do
  begin
    for mSymbolPos := 0 to High(AUnits[mUnitPos].Symbols) do
    begin
      if IsImportEntry(AUnits[mUnitPos].Symbols[mSymbolPos]) then
      begin
        Inc(AEntries);
        Inc(AHelpers, Ord(IsImportHelper(AUnits[mUnitPos].Symbols[mSymbolPos])));
      end;
    end;
  end;
end;

class function TImportNameIndex.Build(const AIndex: ISymbolIndex): TImportNameIndex;
var
  mPass, mUnitPos, mSymbolPos, mUsed, mHelpers: Integer;
  mSymbol: TIndexSymbol;
begin
  // Generation vor Units lesen: Ändert sich der Index dazwischen, baut der nächste Aufruf neu.
  Result.Generation := AIndex.Generation;
  Result.Units := AIndex.Units;
  CountImportEntries(Result.Units, mUsed, mHelpers);
  SetLength(Result.Entries, mUsed);
  SetLength(Result.Helpers, mHelpers);
  mUsed := 0;
  mHelpers := 0;
  // Erst die Projekt-Units, dann die Bibliothek.
  for mPass := 0 to 1 do
  begin
    for mUnitPos := 0 to High(Result.Units) do
    begin
      for mSymbolPos := 0 to High(Result.Units[mUnitPos].Symbols) do
      begin
        mSymbol := Result.Units[mUnitPos].Symbols[mSymbolPos];
        if (Result.Units[mUnitPos].Library_ <> (mPass = 1)) or not IsImportEntry(mSymbol) then
        begin
          Continue;
        end;
        Result.Entries[mUsed].UnitPos := mUnitPos;
        Result.Entries[mUsed].SymbolPos := mSymbolPos;
        Result.Entries[mUsed].Mask := MaskOf(mSymbol.Name);
        Inc(mUsed);
        if IsImportHelper(mSymbol) then
        begin
          Result.Helpers[mHelpers].UnitPos := mUnitPos;
          Result.Helpers[mHelpers].SymbolPos := mSymbolPos;
          Result.Helpers[mHelpers].Mask := 0;
          Inc(mHelpers);
        end;
      end;
    end;
  end;
end;

function TImportNameIndex.Count: Integer;
begin
  Result := Length(Entries);
end;

{ TImportNames }

class function TImportNames.Current(const AIndex: ISymbolIndex): TImportNameIndex;
var
  Fresh: Boolean;
begin
  TMonitor.Enter(CacheLock);
  try
    Fresh := (CacheOwner = Pointer(AIndex as TObject)) and (CacheNames.Generation = AIndex.Generation);
    if not Fresh and (CacheOwner = Pointer(AIndex as TObject)) and (CacheNames.Count >= LargeCount) and
      (CacheWatch.ElapsedMilliseconds < RebuildMs) then
    begin
      Fresh := True;
    end;
    if not Fresh then
    begin
      CacheNames := TImportNameIndex.Build(AIndex);
      CacheOwner := Pointer(AIndex as TObject);
      CacheWatch := TStopwatch.StartNew;
    end;
    Result := CacheNames;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

class procedure TImportNames.Forget(AOwner: TObject);
begin
  TMonitor.Enter(CacheLock);
  try
    if CacheOwner = Pointer(AOwner) then
    begin
      CacheNames := Default(TImportNameIndex);
      CacheOwner := nil;
    end;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

initialization
  CacheLock := TObject.Create;
  // Monitor gleich anlegen: Sonst entsteht er beim ersten Zugriff (oft in einem Test) und gilt dort als Leck.
  TMonitor.Enter(CacheLock);
  TMonitor.Exit(CacheLock);

finalization
  CacheNames := Default(TImportNameIndex);
  CacheLock.Free;

end.
