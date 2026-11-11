unit Atlas.Core.Diagnostics.FeatureTable;

// Teile des Plugins in Startreihenfolge: je Teil eine
// Bedingung (Stufe des abgesicherten Starts #722 und Einstellungen), eine
// Abfrage „läuft“ sowie Start und Stop.
//   - StartWanted startet in Reihenfolge jedes gewünschte, nicht laufende
//     Teil; mehrfach aufrufbar (Schnellschalter, „Normal weiterarbeiten“)
//   - StopAll stoppt rückwärts jedes laufende Teil
//   - Times: Beim Start misst StartWanted jedes Teil für die Startanteile
//    ; danach nil
//   - Module (#1454): Join ordnet Teile einem Modul zu (Debugger, Tests …).
//     Ist das Modul laut ModuleOn aus, startet StartWanted seine Teile nicht,
//     und StopOffModules stoppt rückwärts die laufenden (ohne Neustart).
// Ein Fehler in Start geht an den Aufrufer (wie zuvor in RegisterFeatures).
// Ein Fehler in Stop hält den Abbau nicht an (#886): Die übrigen Teile werden
// trotzdem gestoppt, StopAll liefert die fehlgeschlagenen mit Ausnahmeklasse.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.StartTimes,
  Atlas.Core.Diagnostics.Teardown;

type
  /// <summary>Bedingung je Stufe des abgesicherten Starts (#722) und Einstellung; der Typ steht im Modulvertrag.
  /// </summary>
  TAtlasFeatureWanted = Atlas.Core.Modules.Contract.TAtlasFeatureWanted;
  /// <summary>Ist das Modul AModule an (Modul-Schalter, #1454)?</summary>
  TAtlasModuleIsOn = reference to function(const AModule: string): Boolean;

  TAtlasFeatureTable = class
  private type
    TSlot = record
      Name: string;
      Wanted: TAtlasFeatureWanted;
      IsActive: TFunc<Boolean>;
      Start: TProc;
      Stop: TProc;
      /// <summary>Kennung des Moduls (#1454); '' = Kern.</summary>
      Module: string;
    end;
  private
    FSlots: TList<TSlot>;
    FTimes: TAtlasStartTimes;
    FModuleOn: TAtlasModuleIsOn;
    function SlotModuleOn(const ASlot: TSlot): Boolean;
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
    /// <summary>Rückwärts jedes aktive Feature stoppen, auch wenn ein Stop eine Ausnahme wirft (#886);
    /// Ergebnis: die fehlgeschlagenen Teile als „Name: Klasse“.</summary>
    function StopAll: TArray<string>;
    /// <summary>Ordnet die Teile ANames dem Modul AModule zu (#1454); unbekannte Namen sind ein Fehler.</summary>
    procedure Join(const AModule: string; const ANames: array of string);
    /// <summary>Rückwärts jedes aktive Teil eines ausgeschalteten Moduls stoppen (#1454), auch wenn ein Stop eine
    /// Ausnahme wirft; Ergebnis wie StopAll.</summary>
    function StopOffModules: TArray<string>;
    /// <summary>Gibt es ein Teil AName?</summary>
    function Contains(const AName: string): Boolean;
    /// <summary>Teil AName aus der Tabelle nehmen, ohne es zu stoppen (ein abgemeldetes Modul, #1455); False, wenn
    /// es fehlt. Nicht aus einem Start oder Stop der Tabelle heraus aufrufen.</summary>
    function Remove(const AName: string): Boolean;
    /// <summary>Modul des Teils AName; '' = Kern oder unbekannt.</summary>
    function ModuleOf(const AName: string): string;
    /// <summary>Namen in Startreihenfolge.</summary>
    function Names: TArray<string>;
    /// <summary>Gesetzt: StartWanted addiert die Dauer jedes Starts unter dem Namen des Teils
    /// (Startanteile). Gehört dem Aufrufer; vor dessen Freigabe auf nil setzen.</summary>
    property Times: TAtlasStartTimes read FTimes write FTimes;
    /// <summary>Zustand der Modul-Schalter; nil = alle Module an.</summary>
    property ModuleOn: TAtlasModuleIsOn read FModuleOn write FModuleOn;
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
  mSlot: TSlot;
begin
  mSlot.Name := AName;
  mSlot.Wanted := AWanted;
  mSlot.IsActive := AIsActive;
  mSlot.Start := AStart;
  mSlot.Stop := AStop;
  mSlot.Module := '';
  FSlots.Add(mSlot);
end;

procedure TAtlasFeatureTable.StartWanted(ALevel: TAtlasSafeLevel);
var
  mIndex: Integer;
  mSlot: TSlot;
begin
  // Über den Index: Ein Start darf die Tabelle nicht ändern, liest aber den Stand der früheren.
  for mIndex := 0 to FSlots.Count - 1 do
  begin
    mSlot := FSlots[mIndex];
    if SlotModuleOn(mSlot) and not mSlot.IsActive() and mSlot.Wanted(ALevel) then
    begin
      if FTimes <> nil then
      begin
        FTimes.Measure(mSlot.Name, mSlot.Start);
      end
      else
      begin
        mSlot.Start();
      end;
    end;
  end;
end;

function TAtlasFeatureTable.StopAll: TArray<string>;
var
  mIndex: Integer;
  mSlot: TSlot;
  mTeardown: TAtlasTeardown;
begin
  mTeardown := TAtlasTeardown.Create;
  for mIndex := FSlots.Count - 1 downto 0 do
  begin
    mSlot := FSlots[mIndex];
    // Auch IsActive gehört zum Schritt: Es fragt oft das Teil selbst ab.
    mTeardown.Step(mSlot.Name,
      procedure
      begin
        if mSlot.IsActive() then
        begin
          mSlot.Stop();
        end;
      end);
  end;
  Result := mTeardown.Failures;
end;

function TAtlasFeatureTable.SlotModuleOn(const ASlot: TSlot): Boolean;
begin
  Result := (ASlot.Module = '') or not Assigned(FModuleOn) or FModuleOn(ASlot.Module);
end;

procedure TAtlasFeatureTable.Join(const AModule: string; const ANames: array of string);
var
  mName: string;
  mIndex: Integer;
  mFound: Boolean;
  mSlot: TSlot;
begin
  for mName in ANames do
  begin
    mFound := False;
    for mIndex := 0 to FSlots.Count - 1 do
    begin
      if FSlots[mIndex].Name = mName then
      begin
        mSlot := FSlots[mIndex];
        mSlot.Module := AModule;
        FSlots[mIndex] := mSlot;
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      raise EArgumentException.CreateFmt('Teil "%s" für Modul "%s" unbekannt', [mName, AModule]);
    end;
  end;
end;

function TAtlasFeatureTable.StopOffModules: TArray<string>;
var
  mIndex: Integer;
  mSlot: TSlot;
  mTeardown: TAtlasTeardown;
begin
  mTeardown := TAtlasTeardown.Create;
  for mIndex := FSlots.Count - 1 downto 0 do
  begin
    mSlot := FSlots[mIndex];
    if SlotModuleOn(mSlot) then
    begin
      Continue;
    end;
    mTeardown.Step(mSlot.Name,
      procedure
      begin
        if mSlot.IsActive() then
        begin
          mSlot.Stop();
        end;
      end);
  end;
  Result := mTeardown.Failures;
end;

function TAtlasFeatureTable.Contains(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to FSlots.Count - 1 do
  begin
    if FSlots[mIndex].Name = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasFeatureTable.Remove(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := FSlots.Count - 1 downto 0 do
  begin
    if FSlots[mIndex].Name = AName then
    begin
      FSlots.Delete(mIndex);
      Result := True;
    end;
  end;
end;

function TAtlasFeatureTable.ModuleOf(const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to FSlots.Count - 1 do
  begin
    if FSlots[mIndex].Name = AName then
    begin
      Exit(FSlots[mIndex].Module);
    end;
  end;
end;

function TAtlasFeatureTable.Names: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, FSlots.Count);
  for mIndex := 0 to FSlots.Count - 1 do
  begin
    Result[mIndex] := FSlots[mIndex].Name;
  end;
end;

end.
