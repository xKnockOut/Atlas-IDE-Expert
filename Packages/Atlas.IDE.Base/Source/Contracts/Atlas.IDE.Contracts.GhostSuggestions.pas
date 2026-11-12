unit Atlas.IDE.Contracts.GhostSuggestions;

// Vertrag für Anbieter von Schattentext-Vorschlägen nach Enter (#1890): Base
// zeigt den Vorschlag (eine Zeile grauer Text an der Schreibmarke, Tab, Strg+→,
// Esc, Feld im Statusfeld) in Atlas.IDE.Editor.GhostSuggestions; woher er
// kommt, entscheidet der Anbieter. Erster Anbieter sind die gelernten
// Vorschläge aus dem Projekt; ein späterer (etwa ein KI-Anbieter) meldet sich
// mit TAtlasGhostProviders.Add an und beim Stoppen mit Remove ab.
// - Nach der Tipp-Pause fragt Base die Anbieter in der Reihenfolge der
//   Anmeldung: Prepare im Hauptthread (Puffer an den Server o. Ä.), dann die
//   gelieferte Arbeit im Hintergrund; der erste Vorschlag gewinnt.
// - Accepted und Rejected kommen im Hauptthread, wenn der Block ganz
//   geschrieben bzw. mit Esc verworfen ist.
// Nur Interfaces und Records; außer der Arbeit alles im Hauptthread.

interface

uses
  System.SysUtils;

type
  /// <summary>Stelle, an der nach Enter gefragt wird.</summary>
  TAtlasGhostContext = record
    FileName: string;
    /// <summary>Die neue, leere Zeile (0-basiert).</summary>
    Line: Integer;
    /// <summary>Ganzer Puffer, auch ungespeichert.</summary>
    Text: string;
    TabSize: Integer;
    InsertSpaces: Boolean;
  end;

  /// <summary>Beleg eines Vorschlags (Sprungziel aus dem Statusfeld).</summary>
  TAtlasGhostLocation = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
  end;

  /// <summary>Vorschlag für die leere Zeile des Kontexts.</summary>
  TAtlasGhostProposal = record
    /// <summary>Kennung beim Anbieter (für Accepted und Rejected).</summary>
    Id: string;
    /// <summary>Zeilen, die die leere Zeile ersetzen, samt Einrückung.</summary>
    Lines: TArray<string>;
    /// <summary>Schreibmarke nach dem ganzen Block (0-basiert, im Puffer danach).</summary>
    CursorLine: Integer;
    CursorCharacter: Integer;
    /// <summary>Feld im Statusfeld und sein Hinweis.</summary>
    StatusText: string;
    Hint: string;
    Locations: TArray<TAtlasGhostLocation>;
  end;

  /// <summary>Läuft im Hintergrund; False = kein Vorschlag.</summary>
  TAtlasGhostWork = reference to function(out AProposal: TAtlasGhostProposal): Boolean;

  IAtlasGhostProvider = interface
    ['{3333E76C-EC11-48A8-9EBE-E117F8F3B0A3}']
    /// <summary>Eingeschaltet (Einstellung des Anbieters)?</summary>
    function Enabled: Boolean;
    /// <summary>Bereitet die Anfrage für AContext vor; nil = kein Vorschlag.</summary>
    function Prepare(const AContext: TAtlasGhostContext): TAtlasGhostWork;
    procedure Accepted(const AProposal: TAtlasGhostProposal);
    procedure Rejected(const AProposal: TAtlasGhostProposal);
  end;

  /// <summary>Angemeldete Anbieter in der Reihenfolge der Anmeldung.</summary>
  TAtlasGhostProviders = class
  private class var
    FProviders: TArray<IAtlasGhostProvider>;
  public
    class destructor Destroy;
    class procedure Add(const AProvider: IAtlasGhostProvider); static;
    class procedure Remove(const AProvider: IAtlasGhostProvider); static;
    class function List: TArray<IAtlasGhostProvider>; static;
    /// <summary>Mindestens ein eingeschalteter Anbieter?</summary>
    class function AnyEnabled: Boolean; static;
  end;

implementation

{ TAtlasGhostProviders }

class destructor TAtlasGhostProviders.Destroy;
begin
  FProviders := nil;
end;

class procedure TAtlasGhostProviders.Add(const AProvider: IAtlasGhostProvider);
begin
  Remove(AProvider);
  if AProvider <> nil then
  begin
    FProviders := FProviders + [AProvider];
  end;
end;

class procedure TAtlasGhostProviders.Remove(const AProvider: IAtlasGhostProvider);
var
  mIndex: Integer;
begin
  for mIndex := High(FProviders) downto 0 do
  begin
    if FProviders[mIndex] = AProvider then
    begin
      Delete(FProviders, mIndex, 1);
    end;
  end;
end;

class function TAtlasGhostProviders.List: TArray<IAtlasGhostProvider>;
begin
  Result := Copy(FProviders);
end;

class function TAtlasGhostProviders.AnyEnabled: Boolean;
var
  mProvider: IAtlasGhostProvider;
begin
  for mProvider in FProviders do
  begin
    if mProvider.Enabled then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
