unit Atlas.IDE.Contracts.LineChanges;

// Vertrag zwischen Modulen (#1905, ADR 0017 Regeln 4 und 6): Änderungsmarken und Zeilenhistorie im Editor (#507).
// Das Modul Versionsverwaltung zeichnet sie und meldet für die Zeit, in der sein Teil läuft, ein IAtlasLineChanges bei
// TAtlasLineChangeMarks an (Bind, Bind(nil) beim Stoppen). Base fragt darüber die Übersichtsleiste (Snapshot), die
// Tasten und die Palette (Enabled, GoToChange); ohne Modul antwortet ein Null-Objekt: keine Marken, Tasten ohne
// Wirkung. Der Tracker ergänzt die Zeilenhistorie um Issues (#1275): Er legt seine Haken mit SetBlameHooks bei Base
// ab (Default beim Stoppen, Regel 3); das Modul holt sie über BlameHooks, sobald es läuft oder BlameHooksChanged
// kommt. So kennen sich Tracker und Versionsverwaltung nicht. Nur Interfaces, Records und Methodenreferenzen; alle
// Aufrufe im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Editor.LineChanges;

type
  /// <summary>Commit der Zeilenhistorie (#1275), wie ihn Randanzeige und Hover zeigen.</summary>
  TAtlasBlameCommit = record
    FileName: string;
    Kind: TAtlasVcsKind;
    Revision: string;
    Author: string;
    /// <summary>UTC.</summary>
    Date: TDateTime;
    /// <summary>Ganze Nachricht, sofern geladen (Haken Messages), sonst der Betreff aus blame (SVN: leer).</summary>
    Message: string;
    /// <summary>Zeile im Puffer, 0-basiert.</summary>
    Line: Integer;
  end;

  /// <summary>Ganze Nachrichten zu den Revisionen aus blame; läuft im Hintergrund.</summary>
  TAtlasBlameMessagesHook = reference to function(const AVcs: IAtlasVersionControl; const AFileName: string;
    const ALines: TArray<TAtlasVcsBlameLine>): TArray<TAtlasVcsRevisionMessage>;
  /// <summary>Hover ergänzen: AText erweitern, Links setzen; False = Hover wie bisher.</summary>
  TAtlasBlameDescribeHook = reference to function(const ACommit: TAtlasBlameCommit; var AText: string;
    out ALinks: TArray<string>): Boolean;
  /// <summary>Klick auf den Link AIndex des Hovers.</summary>
  TAtlasBlameLinkHook = reference to procedure(const ACommit: TAtlasBlameCommit; AIndex: Integer);

  /// <summary>Ergänzungen der Zeilenhistorie (Issues, #1275); der Tracker legt sie bei Base ab.</summary>
  TAtlasBlameHooks = record
    /// <summary>Ganze Nachrichten laden? Vor jedem blame und einmal je Sekunde gefragt (Hauptthread).</summary>
    Wanted: TFunc<Boolean>;
    Messages: TAtlasBlameMessagesHook;
    /// <summary>Anhang hinter der Zeit in der Randanzeige (" · ATL-97") zur Nachricht; '' ohne.</summary>
    Suffix: TFunc<string, string>;
    Describe: TAtlasBlameDescribeHook;
    Link: TAtlasBlameLinkHook;
  end;

  /// <summary>Änderungsmarken und Zeilenhistorie des Moduls Versionsverwaltung.</summary>
  IAtlasLineChanges = interface
    ['{7C2E4A91-5B3D-4F68-9E0A-1D6C8B4F2A37}']
    /// <summary>Sind die Änderungsmarken eingeschaltet (für Palette und Tastenkürzel)?</summary>
    function Enabled: Boolean;
    /// <summary>Cursor auf die erste Zeile der nächsten (AForward) bzw. vorigen Änderung, reihum.</summary>
    procedure GoToChange(AForward: Boolean);
    /// <summary>Letzter Vergleich für AFileName (Übersichtsleiste #519); False ohne.</summary>
    function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList; out ALineCount: Integer): Boolean;
    /// <summary>Commit der Randanzeige unter X, Y (Fensterkoordinaten von AWnd); False ohne.</summary>
    function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
    /// <summary>Hover der Zeilenhistorie neu aufbauen, falls er offen ist.</summary>
    procedure RefreshBlameTip;
    procedure HideBlameTip;
    /// <summary>Die Haken bei Base haben sich geändert (TAtlasLineChangeMarks.BlameHooks neu lesen).</summary>
    procedure BlameHooksChanged;
  end;

  /// <summary>Zugang von Base und den Modulen zu den Änderungsmarken.</summary>
  TAtlasLineChangeMarks = class
  private class var
    FMarks: IAtlasLineChanges;
    FHooks: TAtlasBlameHooks;
  public
    class destructor Destroy;
    /// <summary>Das Modul meldet seine Marken an (nil beim Stoppen).</summary>
    class procedure Bind(const AMarks: IAtlasLineChanges); static;
    /// <summary>Angemeldete Marken oder ein Null-Objekt (keine Marken, keine Wirkung).</summary>
    class function Current: IAtlasLineChanges; static;
    class function Available: Boolean; static;
    /// <summary>Haken des Trackers ablegen bzw. mit Default(TAtlasBlameHooks) entfernen; meldet es den Marken.
    /// </summary>
    class procedure SetBlameHooks(const AHooks: TAtlasBlameHooks); static;
    class function BlameHooks: TAtlasBlameHooks; static;
  end;

  /// <summary>Antwort ohne Modul: nichts eingeschaltet, nichts zu zeigen.</summary>
  TAtlasNullLineChanges = class(TInterfacedObject, IAtlasLineChanges)
  public
    function Enabled: Boolean;
    procedure GoToChange(AForward: Boolean);
    function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList; out ALineCount: Integer): Boolean;
    function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
    procedure RefreshBlameTip;
    procedure HideBlameTip;
    procedure BlameHooksChanged;
  end;

implementation

{ TAtlasLineChangeMarks }

class destructor TAtlasLineChangeMarks.Destroy;
begin
  FMarks := nil;
  FHooks := Default(TAtlasBlameHooks);
end;

class procedure TAtlasLineChangeMarks.Bind(const AMarks: IAtlasLineChanges);
begin
  FMarks := AMarks;
end;

class function TAtlasLineChangeMarks.Current: IAtlasLineChanges;
begin
  Result := FMarks;
  if Result = nil then
  begin
    Result := TAtlasNullLineChanges.Create;
  end;
end;

class function TAtlasLineChangeMarks.Available: Boolean;
begin
  Result := FMarks <> nil;
end;

class procedure TAtlasLineChangeMarks.SetBlameHooks(const AHooks: TAtlasBlameHooks);
begin
  FHooks := AHooks;
  if FMarks <> nil then
  begin
    FMarks.BlameHooksChanged;
  end;
end;

class function TAtlasLineChangeMarks.BlameHooks: TAtlasBlameHooks;
begin
  Result := FHooks;
end;

{ TAtlasNullLineChanges }

function TAtlasNullLineChanges.Enabled: Boolean;
begin
  Result := False;
end;

procedure TAtlasNullLineChanges.GoToChange(AForward: Boolean);
begin
  // Ohne Modul keine Wirkung.
end;

function TAtlasNullLineChanges.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
begin
  AChanges := nil;
  ALineCount := 0;
  Result := False;
end;

function TAtlasNullLineChanges.BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
begin
  ACommit := Default(TAtlasBlameCommit);
  Result := False;
end;

procedure TAtlasNullLineChanges.RefreshBlameTip;
begin
  // Ohne Modul kein Hover.
end;

procedure TAtlasNullLineChanges.HideBlameTip;
begin
  // Ohne Modul kein Hover.
end;

procedure TAtlasNullLineChanges.BlameHooksChanged;
begin
  // Ohne Modul liest niemand die Haken.
end;

end.
