unit Atlas.Core.Settings.PageNames;

// Englische Namen der Seiten aus den Schemas (#1458): x-page in
// schemas/atlas.schema.json (Dialog der Server- und Projekt-Einstellungen) und
// schemas/atlas-plugin.schema.json (Überschriften der Schnellschalter). Das
// Schema nennt die Seite deutsch, weil sie zugleich Schlüssel ist (Zuordnung
// der Felder, Sprung „Einstellung öffnen“); angezeigt wird der Name hier.
// Der Test prüft, dass jede x-page beider Schemas einen Eintrag hat.

interface

type
  /// <summary>Anzeigename einer Seite (x-page) in der Sprache der Oberfläche.</summary>
  TAtlasSettingsPageNames = record
  public
    /// <summary>Englischer Name für AEnglish, sonst APage; unbekannte Seiten bleiben, wie sie sind.</summary>
    class function Caption(const APage: string; AEnglish: Boolean): string; static;
    /// <summary>True, wenn APage einen Eintrag hat (für den Test über die Schemas).</summary>
    class function Known(const APage: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

type
  TPageName = record
    De: string;
    En: string;
  end;

const
  // De ist der Schlüssel aus x-page und bleibt deutsch.
  cPages: array[0..27] of TPageName = (
    (De: 'Allgemein'; En: 'General'),
    (De: 'Architektur'; En: 'Architecture'),
    (De: 'Befehle'; En: 'Commands'),
    (De: 'Compiler'; En: 'Compiler'),
    (De: 'Debuggen'; En: 'Debugging'),
    (De: 'Editor'; En: 'Editor'),
    (De: 'Einfügen'; En: 'Paste'), // german-ok
    (De: 'Eingabehilfen'; En: 'Typing aids'),
    (De: 'Farben'; En: 'Colors'),
    (De: 'Formatierung'; En: 'Formatting'),
    (De: 'Hints'; En: 'Hints'),
    (De: 'Hotspots'; En: 'Hotspots'),
    (De: 'Index'; En: 'Index'),
    (De: 'Issue-Tracker'; En: 'Issue tracker'),
    (De: 'MCP'; En: 'MCP'),
    (De: 'Projekt'; En: 'Project'),
    (De: 'Protokoll'; En: 'Logging'),
    (De: 'Prüfregeln'; En: 'Check rules'), // german-ok
    (De: 'Release-Build'; En: 'Release build'),
    (De: 'Robustheit'; En: 'Robustness'),
    (De: 'Rückgängig'; En: 'Undo'), // german-ok
    (De: 'Speicher'; En: 'Memory'),
    (De: 'Start und Updates'; En: 'Startup and updates'), // german-ok
    (De: 'Tastenkonflikte'; En: 'Shortcut conflicts'),
    (De: 'Units suchen'; En: 'Unit search'), // german-ok
    (De: 'Versionsverwaltung'; En: 'Version control'),
    (De: 'Vervollständigung'; En: 'Completion'), // german-ok
    (De: 'Willkommensseite'; En: 'Welcome page'));

function IndexOf(const APage: string): Integer;
var
  Index: Integer;
begin
  for Index := Low(cPages) to High(cPages) do
    if SameText(cPages[Index].De, APage) then
      Exit(Index);
  Result := -1;
end;

class function TAtlasSettingsPageNames.Caption(const APage: string; AEnglish: Boolean): string;
var
  Index: Integer;
begin
  Result := APage;
  if not AEnglish then
    Exit;
  Index := IndexOf(APage);
  if Index >= 0 then
    Result := cPages[Index].En;
end;

class function TAtlasSettingsPageNames.Known(const APage: string): Boolean;
begin
  Result := IndexOf(APage) >= 0;
end;

end.
