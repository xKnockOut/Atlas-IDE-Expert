unit Atlas.Core.Diagnostics.FeatureTable;

// Teile des Plugins in Startreihenfolge (Code-Review S-03): je Teil eine
// Bedingung (Stufe des abgesicherten Starts #722 und Einstellungen), eine
// Abfrage „läuft“ sowie Start und Stop.
//   - StartWanted startet in Reihenfolge jedes gewünschte, nicht laufende
//     Teil; mehrfach aufrufbar (Schnellschalter, „Normal weiterarbeiten“)
//   - StopAll stoppt rückwärts jedes laufende Teil
// Keine Ausnahmebehandlung: Ein Fehler in Start oder Stop geht an den
// Aufrufer (wie zuvor in RegisterFeatures und Unregister).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.SafeMode;

type
  /// <summary>Bedingung je Stufe des abgesicherten Starts (#722) und Einstellung.</summary>
  TAtlasFeatureWanted = reference to function(ALevel: TAtlasSafeLevel): Boolean;

  TAtlasFeatureTable = class
  private type
    TSlot = record
      Name: string;
      Wanted: TAtlasFeatureWanted;
      IsActive: TFunc<Boolean>;
      Start: TProc;
      Stop: TProc;
    end;
  private
    FSlots: TList<TSlot>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nur ab Stufe AMinLevel: Normal = nur normal, Safe = nicht minimal, Minimal = immer.</summary>
    procedure Add(const AName: string; AMinLevel: TAtlasSafeLevel; const AIsActive: TFunc<Boolean>;
      const AStart, AStop: TProc);
    /// <summary>Wie Add, gewünscht nach AWanted statt ab einer Stufe. Eigener Name statt Überladung:
    /// Delphi wählt zwischen Überladungen mit anonymen Methoden als Argument nicht (E2250).</summary>
    procedure AddWanted(const AName: string; const AWanted: TAtlasFeatureWanted; const AIsActive: TFunc<Boolean>;
      const AStart, AStop: TProc);
    /// <summary>In Reihenfolge jedes nicht aktive, gewünschte Feature starten; mehrfach aufrufbar.</summary>
    procedure StartWanted(ALevel: TAtlasSafeLevel);
    /// <summary>Rückwärts jedes aktive Feature stoppen.</summary>
    procedure StopAll;
    /// <summary>Namen in Startreihenfolge.</summary>
    function Names: TArray<string>;
  end;

implementation

{ TAtlasFeatureTable }

constructor TAtlasFeatureTable.Create;
begin
  inherited Create;
  FSlots := TList<TSlot>.Create;
end;

destructor TAtlasFeatureTable.Destroy;
begin
  FSlots.Free;
  inherited;
end;

procedure TAtlasFeatureTable.Add(const AName: string; AMinLevel: TAtlasSafeLevel; const AIsActive: TFunc<Boolean>;
  const AStart, AStop: TProc);
begin
  AddWanted(AName,
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := Ord(ALevel) <= Ord(AMinLevel);
    end,
    AIsActive, AStart, AStop);
end;

procedure TAtlasFeatureTable.AddWanted(const AName: string; const AWanted: TAtlasFeatureWanted;
  const AIsActive: TFunc<Boolean>; const AStart, AStop: TProc);
var
  Slot: TSlot;
begin
  Slot.Name := AName;
  Slot.Wanted := AWanted;
  Slot.IsActive := AIsActive;
  Slot.Start := AStart;
  Slot.Stop := AStop;
  FSlots.Add(Slot);
end;

procedure TAtlasFeatureTable.StartWanted(ALevel: TAtlasSafeLevel);
var
  Index: Integer;
  Slot: TSlot;
begin
  // Über den Index: Ein Start darf die Tabelle nicht ändern, liest aber den Stand der früheren.
  for Index := 0 to FSlots.Count - 1 do
  begin
    Slot := FSlots[Index];
    if not Slot.IsActive() and Slot.Wanted(ALevel) then
      Slot.Start();
  end;
end;

procedure TAtlasFeatureTable.StopAll;
var
  Index: Integer;
  Slot: TSlot;
begin
  for Index := FSlots.Count - 1 downto 0 do
  begin
    Slot := FSlots[Index];
    if Slot.IsActive() then
      Slot.Stop();
  end;
end;

function TAtlasFeatureTable.Names: TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, FSlots.Count);
  for Index := 0 to FSlots.Count - 1 do
    Result[Index] := FSlots[Index].Name;
end;

end.
