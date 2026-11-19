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
// - Remove ist das Ende des Anbieters (Regel 3, #1922): Base verwirft seinen
//   sichtbaren Vorschlag und wartet, bis keine seiner Arbeiten mehr läuft;
//   danach hält Base keinen Verweis mehr auf ihn oder seine Arbeit. Ein Anbieter
//   aus einem Modul bricht vorher seine eigenen Anfragen ab.
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

  /// <summary>Base räumt beim Abmelden von AProvider auf (Anzeige, laufende Arbeit).</summary>
  TAtlasGhostRemoving = reference to procedure(const AProvider: IAtlasGhostProvider);

  /// <summary>Angemeldete Anbieter in der Reihenfolge der Anmeldung.</summary>
  TAtlasGhostProviders = class
  private class var
    FProviders: TArray<IAtlasGhostProvider>;
    FRemoving: TAtlasGhostRemoving;
  public
    class destructor Destroy;
    class procedure Add(const AProvider: IAtlasGhostProvider); static;
    /// <summary>Meldet AProvider ab; kehrt erst zurück, wenn Base ihn nicht mehr erreicht (siehe oben).</summary>
    class procedure Remove(const AProvider: IAtlasGhostProvider); static;
    /// <summary>Gehört AProvider (Zeiger des Interfaces) noch zu den angemeldeten? nil, wenn nicht.</summary>
    class function Find(AProvider: Pointer): IAtlasGhostProvider; static;
    /// <summary>Aufräumen der Anzeige beim Abmelden (nur Base); nil löst es.</summary>
    class procedure Watch(const ARemoving: TAtlasGhostRemoving); static;
    class function List: TArray<IAtlasGhostProvider>; static;
    /// <summary>Mindestens ein eingeschalteter Anbieter?</summary>
    class function AnyEnabled: Boolean; static;
  end;

implementation

{ TAtlasGhostProviders }

class destructor TAtlasGhostProviders.Destroy;
begin
  FProviders := nil;
  FRemoving := nil;
end;

class procedure TAtlasGhostProviders.Add(const AProvider: IAtlasGhostProvider);
begin
  // Schon angemeldet: bleibt an seiner Stelle.
  if (AProvider <> nil) and (Find(Pointer(AProvider)) = nil) then
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
      if Assigned(FRemoving) then
      begin
        FRemoving(AProvider);
      end;
    end;
  end;
end;

class function TAtlasGhostProviders.Find(AProvider: Pointer): IAtlasGhostProvider;
var
  mProvider: IAtlasGhostProvider;
begin
  Result := nil;
  for mProvider in FProviders do
  begin
    if Pointer(mProvider) = AProvider then
    begin
      Exit(mProvider);
    end;
  end;
end;

class procedure TAtlasGhostProviders.Watch(const ARemoving: TAtlasGhostRemoving);
begin
  FRemoving := ARemoving;
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
