unit Atlas.UI.Hover.Strings;

// Oberflächentexte des Features Hover auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasHoverTextId = (
    HoverInheritance, HoverTargetType, HoverPinned, HoverGoTo, HoverUsages, HoverUsagesCount, HoverCopy, HoverHelp,
    HoverKeyUsages, HoverKeyCopy, ProblemsSourceAtlas, ProblemsSourceCompiler, ProblemsStale, AccessHover,
    HoverCopySelection, ProblemsSourceInactive, ProblemsSourceUses, UsesRemove, UsesRemoveAll, UsesMove,
    HoverDebugPending, PublishedSummary, PublishedInherited, PublishedOnlyDefaults, PublishedProperties,
    PublishedEvents, PublishedName, PublishedType, PublishedDefault, PublishedDeclared, PublishedImplicit,
    PublishedMoreProperties, PublishedMoreEvents, PublishedEventsNote, PublishedArrayProperty,
    PublishedDefaultProperty, PublishedDefaultPropertyNote, PublishedCopyList, PublishedVclNote, HoverShowGraph,
    HoverDebugExplaining, HoverDebugChecked, ReassignedOne, ReassignedCount);

  TAtlasHoverStrings = class
  public
    class function Text(AId: TAtlasHoverTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasHoverTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasHoverTextId] of string = (
    ('Vererbung',
     'Zieltyp %s',
     'angeheftet',
     'Gehe zu %s',
     'Verwendungen',
     'Verwendungen (%d)',
     'Deklaration kopieren',
     'Hilfe',
     'Umschalt+F12',
     'Strg+C',
     'Atlas',
     'Compiler',
     'seit dem letzten Prüfen geändert',
     'Atlas Tooltip',
     'Markierung kopieren',
     'Bedingte Kompilierung',
     'Atlas · uses',
     'Entfernen',
     'Alle ungenutzten entfernen',
     'In implementation-uses verschieben',
     'wird ausgewertet …',
     'published: %d Properties · %d Ereignisse',
     'geerbte',
     'nur mit default',
     'Properties',
     'Ereignisse',
     'Name',
     'Typ',
     'Vorgabe',
     'deklariert in',
     'implizit',
     '+ %d weitere Properties',
     '+ %d weitere Ereignisse',
     'erkannt am Methodenzeiger-Typ, nicht am Namen',
     'Array-Property',
     'Standard-Property',
     '„default“ heißt hier nicht Vorgabewert',
     'Liste kopieren',
     'geerbte aus der VCL nur mit VCL-Quellen im Index',
     'Graph zeigen',
     'Ursache wird ermittelt …',
     'Geprüft, ohne Treffer:',
     'Einmal neu zugewiesen (Zeile %s)',
     'Neu zugewiesen: %d Zuweisungen (Zeilen %s)'),
    ('Inheritance',
     'Target type %s',
     'pinned',
     'Go to %s',
     'Usages',
     'Usages (%d)',
     'Copy declaration',
     'Help',
     'Shift+F12',
     'Ctrl+C',
     'Atlas',
     'Compiler',
     'changed since the last check',
     'Atlas tooltip',
     'Copy selection',
     'Conditional compilation',
     'Atlas · uses',
     'Remove',
     'Remove all unused',
     'Move to implementation uses',
     'evaluating …',
     'published: %d properties · %d events',
     'inherited',
     'only with default',
     'Properties',
     'Events',
     'Name',
     'Type',
     'Default',
     'declared in',
     'implicit',
     '+ %d more properties',
     '+ %d more events',
     'detected by method pointer type, not by name',
     'Array property',
     'Default property',
     '"default" does not mean a default value here',
     'Copy list',
     'inherited VCL members only with VCL sources in the index',
     'Show graph',
     'Finding the cause …',
     'Checked without a match:',
     'Reassigned once (line %s)',
     'Reassigned: %d assignments (lines %s)'));

{ TAtlasHoverStrings }

class function TAtlasHoverStrings.Text(AId: TAtlasHoverTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasHoverStrings.Fmt(AId: TAtlasHoverTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
