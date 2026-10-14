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

class function TImportNameIndex.Build(const AIndex: ISymbolIndex): TImportNameIndex;
var
  Pass, UnitPos, SymbolPos, Used: Integer;
  Symbol: TIndexSymbol;
begin
  // Generation vor Units lesen: Ändert sich der Index dazwischen, baut der nächste Aufruf neu.
  Result.Generation := AIndex.Generation;
  Result.Units := AIndex.Units;
  Used := 0;
  for UnitPos := 0 to High(Result.Units) do
    for SymbolPos := 0 to High(Result.Units[UnitPos].Symbols) do
      if Result.Units[UnitPos].Symbols[SymbolPos].InInterface and
        (Result.Units[UnitPos].Symbols[SymbolPos].Container = '') then
        Inc(Used);
  SetLength(Result.Entries, Used);
  Used := 0;
  for Pass := 0 to 1 do
    for UnitPos := 0 to High(Result.Units) do
    begin
      if Result.Units[UnitPos].Library_ <> (Pass = 1) then
        Continue;
      for SymbolPos := 0 to High(Result.Units[UnitPos].Symbols) do
      begin
        Symbol := Result.Units[UnitPos].Symbols[SymbolPos];
        if not Symbol.InInterface or (Symbol.Container <> '') then
          Continue;
        Result.Entries[Used].UnitPos := UnitPos;
        Result.Entries[Used].SymbolPos := SymbolPos;
        Result.Entries[Used].Mask := MaskOf(Symbol.Name);
        Inc(Used);
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
      Fresh := True;
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
