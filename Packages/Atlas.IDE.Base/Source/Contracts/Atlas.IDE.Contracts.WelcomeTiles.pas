unit Atlas.IDE.Contracts.WelcomeTiles;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 4 und 6): Kacheln anderer
// Module auf der Willkommensseite. Ein Modul (Tracker: „Meine Issues“,
// Sprint) stellt je Kachel ein IAtlasWelcomeTile über seinen Scope bereit; die
// Willkommensseite hört auf die Registry, zeigt die Kachel mit Titelzeile,
// Griff und Spalte wie ihre eigenen Bereiche und legt das Steuerelement der
// Kachel in die Inhaltsfläche. Fehlt die Willkommensseite, bleibt die Kachel
// unsichtbar; fehlt das Modul, verschwindet sie samt Ansichten.
// Umgekehrt stellt die Willkommensseite IAtlasWelcomeBoard (Inhalt einer
// Kachel geändert) und IAtlasWelcomeProjects (Projektliste und gewähltes
// Projekt) bereit. Nur Interfaces und Records, kein Code; die Ansicht
// übergibt ein Steuerelement, daher Vcl.Controls. Liegt in Base (Source/Contracts, #1456,
// Entscheidung 04.11.2026). Alle Aufrufe im Hauptthread.

interface

uses
  System.Classes,
  Vcl.Controls;

type
{$SCOPEDENUMS ON}
  /// <summary>Spalte, solange das Layout der Willkommensseite die Kachel nicht kennt.</summary>
  TAtlasWelcomeTileColumn = (Left, Right);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeTileInfo = record
    /// <summary>Kennung, eindeutig über alle Module, z. B. "atlas.issues".</summary>
    Id: string;
    /// <summary>Überschrift in der Sprache der IDE.</summary>
    Title: string;
    /// <summary>Ein Satz für „Seite anpassen“ (#767); '' = keiner.</summary>
    Description: string;
    /// <summary>Reihenfolge ohne Layout, kleiner zuerst.</summary>
    Order: Integer;
    Column: TAtlasWelcomeTileColumn;
    /// <summary>Schalter der Kachel (x-key, Wahrheitswert, z. B. "welcomePage.issues"); '' = keiner. Die
    /// Willkommensseite zeigt ihn im Optionsdialog, ohne den Schlüssel selbst zu kennen (#1903, Regel X).</summary>
    SwitchKey: string;
    /// <summary>Einstellung, zu der „Einstellungen …“ neben dem Schalter springt (z. B. "issues.tracker"); '' =
    /// kein Knopf. Fehlt die Einstellung im Dialog, bleibt der Knopf unsichtbar.</summary>
    SettingsKey: string;
  end;

  /// <summary>Gibt die Willkommensseite jeder Ansicht mit.</summary>
  IAtlasWelcomeTileHost = interface
    ['{29CE5222-BC7D-4891-84E4-9E62D474E002}']
    /// <summary>Die Ansicht braucht eine andere Höhe (BodyHeight); die Seite ordnet die Spalten neu.</summary>
    procedure HeightChanged;
  end;

  /// <summary>Eine gezeigte Kachel; die Willkommensseite und das Fenster „Atlas-Start“ haben je eine.</summary>
  IAtlasWelcomeTileView = interface
    ['{15C5EE05-10F6-476E-BEAC-4F0182B68F46}']
    /// <summary>Inhalt; die Seite setzt Parent und Align. Besitzer ist der AOwner von CreateView.</summary>
    function Control: TWinControl;
    /// <summary>Höhe des Inhalts in Pixeln bei der aktuellen Skalierung, ohne Titelzeile.</summary>
    function BodyHeight: Integer;
    /// <summary>Inhalt neu lesen und zeichnen.</summary>
    procedure UpdateContent;
  end;

  /// <summary>Kachel eines Moduls.</summary>
  IAtlasWelcomeTile = interface
    ['{09456528-9EB2-4004-B7A8-7262803964DF}']
    function Info: TAtlasWelcomeTileInfo;
    /// <summary>Schalter der Kachel; False blendet sie aus, sie bleibt in „Seite anpassen“ wählbar.</summary>
    function Enabled: Boolean;
    /// <summary>Neue Ansicht mit Besitzer AOwner; nil, wenn gerade keine möglich ist.</summary>
    function CreateView(AOwner: TComponent; const AHost: IAtlasWelcomeTileHost): IAtlasWelcomeTileView;
  end;

  /// <summary>Stellt die Willkommensseite bereit: Änderungen einer Kachel melden.</summary>
  IAtlasWelcomeBoard = interface
    ['{5686075B-8CD4-41CF-8461-B34081821736}']
    /// <summary>Inhalt der Kachel AId geändert: alle ihre Ansichten lesen neu (UpdateContent).</summary>
    procedure TileChanged(const AId: string);
    /// <summary>Info oder Schalter der Kachel AId geändert (Sprache, Einstellungen).</summary>
    procedure TileInfoChanged(const AId: string);
  end;

  TAtlasWelcomeProject = record
    /// <summary>Absoluter Pfad der .dproj bzw. .groupproj.</summary>
    Project: string;
    /// <summary>Anzeigename.</summary>
    Name: string;
  end;

  /// <summary>Stellt die Willkommensseite bereit: die Projekte des Bereichs „Projekte“ (#592).</summary>
  IAtlasWelcomeProjects = interface
    ['{0233D3EB-37A9-4ED5-A196-A834954B8D47}']
    /// <summary>Gezeigte Projekte in Reihenfolge der Liste.</summary>
    function Projects: TArray<TAtlasWelcomeProject>;
    /// <summary>Für den Projektverlauf gewähltes Projekt; '' = keins.</summary>
    function Selected: string;
    procedure Open(const AProject: string);
    /// <summary>Stand der Versionsverwaltung von AProject neu abfragen (nach Pull, Branchwechsel).</summary>
    procedure Refresh(const AProject: string);
  end;

implementation

end.
