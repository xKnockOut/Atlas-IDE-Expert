unit Atlas.Core.Editor.Elements;

// Von Atlas im Editor gezeichnete Elemente (#628), ohne VCL und Open Tools
// API. Jedes Element kennt den Schlüssel seiner Einstellung (Name der
// Plugin-Einstellung wie im Katalog TAtlasQuickToggles.PluginCatalog) und die
// Bereiche, in denen es sich ausblenden lässt:
// - Here: nur an dieser Stelle (Befund: Unterdrückungskommentar #147, sonst
//   Eintrag "hidden" in der Projektdatei .atlas #486 mit Anker),
// - InFile: in dieser Datei (Befund: lsp-ignore-file, sonst .atlas ohne Anker),
// - Everywhere: die Einstellung aus.
// Overlay-Elemente stehen als Pille hinter dem Text (Code Lens, Blockende-
// Beschriftung, Inlay-Hint): Ein Rechtsklick darauf öffnet das Menü
// „Ausblenden“ statt des Kontextmenüs der IDE. Die übrigen liegen im Text oder
// in der Rinne; dort bleibt das Kontextmenü der IDE, ausgeblendet wird über das
// Atlas-Untermenü oder die Taste (Strg+.).
// Für die Willkommensseite (#767) liefert SectionSetting den Schlüssel eines
// Bereichs; dort gibt es nur „Überall“ und „Einstellungen dazu …“.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Gezeichnetes Element. Neue Elemente hinten anhängen; der Wächtertest prüft, dass jedes einen
  /// Schlüssel im Einstellungskatalog hat.</summary>
  TAtlasDrawnElement = (
    /// <summary>Code Lens mit Kennzahlen der Methode (#66).</summary>
    CodeLensMetrics,
    /// <summary>Code Lens „Test ausführen“/„Debuggen“ (#69, #585).</summary>
    CodeLensTests,
    /// <summary>Code Lens „Testunit“/„Unit“ hinter unit … (#189).</summary>
    CodeLensTestUnit,
    /// <summary>Beschriftung hinter end (#620).</summary>
    BlockEndLabels,
    /// <summary>Parameternamen vor Literal-Argumenten (#401).</summary>
    InlayHints,
    /// <summary>Unterstreichung eines Befunds (#398).</summary>
    Problems,
    /// <summary>Symbol einer Notiz in der Rinne (#545).</summary>
    Notes,
    /// <summary>Band eines benannten Lesezeichens in der Rinne (#622).</summary>
    Bookmarks,
    /// <summary>Klammerfarben (#514).</summary>
    PairColors,
    /// <summary>Blocklinien (#514).</summary>
    PairGuides,
    /// <summary>Schlüsselwörter in der Farbe ihres Blocks (#653).</summary>
    PairOwners,
    /// <summary>Abgeblendete inaktive {$IFDEF}-Zweige (#615).</summary>
    InactiveDim,
    /// <summary>Vorschau des gewählten Vorschlags im Editor (#434).</summary>
    CompletionPreview,
    /// <summary>Abgeblendete ungenutzte uses-Einträge (#621).</summary>
    UnusedUses,
    /// <summary>Rekursionssymbol in der Rinne (#623).</summary>
    Recursion,
    /// <summary>Fehlertext am Zeilenende (#509).</summary>
    InlineDiagnostics,
    /// <summary>Abgeleiteter Typ von Inline-Variablen (#453).</summary>
    InlayTypeHints,
    /// <summary>Änderungsmarke gegenüber dem Repository in der Rinne (#507).</summary>
    GitGutter,
    /// <summary>Zeilenhistorie (blame) am Ende der Cursorzeile (#507).</summary>
    GitBlame,
    /// <summary>Vorgeschlagene nächste Zeile eines Musters (#671).</summary>
    PatternPreview,
    /// <summary>Symbol der Atlas-Spalte in der Zeilenleiste (#768).</summary>
    GutterColumn,
    /// <summary>Hervorhebung gleichen Texts wie die Markierung samt Anzahl (#709).</summary>
    SelectionMatches,
    /// <summary>Symbole aus Include-Dateien hinter {$I} (#860).</summary>
    InlayDefineHints,
    /// <summary>Codes von Steuerzeichen wie ^C (#862).</summary>
    InlayCharHints,
    /// <summary>Marker der schnellen Lesezeichen links der Zeilennummern (#1104).</summary>
    QuickBookmarks,
    /// <summary>Marke „braucht kein Self“ hinter Methoden, die Self nicht brauchen (#686).</summary>
    InlayMethodHints,
    /// <summary>Hervorgehobene Austrittspunkte samt Marke am Routinenkopf (#698).</summary>
    ExitPoints,
    /// <summary>Unterstreichung neu zugewiesener Variablen (#712).</summary>
    Reassigned,
    /// <summary>Gelernter Vorschlag als Schattentext (#1890).</summary>
    LearnedSuggestions);
  TAtlasHideScope = (Here, InFile, Everywhere);
{$SCOPEDENUMS OFF}
  TAtlasHideScopes = set of TAtlasHideScope;

  TAtlasDrawnElementInfo = record
    Element: TAtlasDrawnElement;
    /// <summary>Name der Plugin-Einstellung, z. B. "BlockEndLabels".</summary>
    SettingKey: string;
    /// <summary>Angebotene Bereiche.</summary>
    Scopes: TAtlasHideScopes;
    /// <summary>Pille hinter dem Text: Rechtsklick darauf öffnet das Menü „Ausblenden“.</summary>
    Overlay: Boolean;
    /// <summary>In der Rinne gezeichnet.</summary>
    Gutter: Boolean;
  end;

  TAtlasDrawnElements = class
  public const
    /// <summary>Höchstlänge eines Ankers in .atlas.</summary>
    cMaxAnchorLength = 120;
  public
    class function Info(AElement: TAtlasDrawnElement): TAtlasDrawnElementInfo; static;
    /// <summary>Alle Elemente in der Reihenfolge der Aufzählung.</summary>
    class function All: TArray<TAtlasDrawnElement>; static;
    /// <summary>Schlüssel der Einstellung von AElement.</summary>
    class function SettingKey(AElement: TAtlasDrawnElement): string; static;
    /// <summary>Element zum Schlüssel (ohne Groß-/Kleinschreibung); False, wenn kein Element ihn hat.</summary>
    class function ForSetting(const AKey: string; out AElement: TAtlasDrawnElement): Boolean; static;
    /// <summary>Schlüssel der Einstellung eines Bereichs der Willkommensseite ("atlas.state" →
    /// "WelcomePageStatusTile"); '' für unbekannte Bereiche.</summary>
    class function SectionSetting(const ASectionId: string): string; static;
    /// <summary>Kennungen der Bereiche, die SectionSetting kennt.</summary>
    class function KnownSections: TArray<string>; static;
    /// <summary>Anker aus einem Text (Name, Beschriftung oder Codezeile): ohne Leerraum am Rand, Folgen von
    /// Leerraum zu einem Leerzeichen, höchstens MaxAnchorLength Zeichen.</summary>
    class function Anchor(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Core.Editor.LineAnchor;

const
  cSectionIds: array[0..13] of string = ('atlas.header', 'atlas.state', 'atlas.continue', 'atlas.projects',
    'atlas.history', 'atlas.news', 'atlas.discover', 'atlas.setup', 'atlas.search', 'atlas.unsaved', 'atlas.tests',
    'atlas.help', 'atlas.issues', 'atlas.sprint');
  cSectionKeys: array[0..13] of string = ('WelcomePageHeader', 'WelcomePageStatusTile', 'WelcomePageContinue',
    'WelcomePageProjectStatus', 'WelcomePageTrends', 'WelcomePageWhatsNew', 'WelcomePageDiscover',
    'WelcomePageProjectSetup', 'WelcomePageSearch', 'WelcomePageUnsaved', 'WelcomePageTests', 'WelcomePageHelp',
    'WelcomePageIssues', 'WelcomePageSprint');

type
  TElementRow = record
    Key: string;
    Scopes: TAtlasHideScopes;
    Overlay: Boolean;
    Gutter: Boolean;
  end;

const
  cAllScopes = [TAtlasHideScope.Here, TAtlasHideScope.InFile, TAtlasHideScope.Everywhere];
  cFileScopes = [TAtlasHideScope.InFile, TAtlasHideScope.Everywhere];
  /// <summary>Je Element in der Reihenfolge von TAtlasDrawnElement: Einstellung, Bereiche, Pille, Rinne.</summary>
  cElementRows: array[TAtlasDrawnElement] of TElementRow = (
    (Key: 'CodeLensMetrics'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'CodeLensTests'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    // Nur einmal je Datei: „Nur hier“ wäre dasselbe wie „In dieser Datei“.
    (Key: 'CodeLensTestUnit'; Scopes: cFileScopes; Overlay: True; Gutter: False),
    (Key: 'BlockEndLabels'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'InlayHints'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'Problems'; Scopes: cAllScopes; Overlay: False; Gutter: False),
    (Key: 'Notes'; Scopes: cAllScopes; Overlay: False; Gutter: True),
    (Key: 'BookmarksNamed'; Scopes: cAllScopes; Overlay: False; Gutter: True),
    // Farben und Linien gehören zum ganzen Block: an einer einzelnen Stelle ergibt Ausblenden keinen Sinn.
    (Key: 'PairColors'; Scopes: cFileScopes; Overlay: False; Gutter: False),
    (Key: 'PairGuides'; Scopes: cFileScopes; Overlay: False; Gutter: False),
    (Key: 'PairOwners'; Scopes: cFileScopes; Overlay: False; Gutter: False),
    (Key: 'InactiveDim'; Scopes: cFileScopes; Overlay: False; Gutter: False),
    // Die Vorschau steht nur, solange die Liste offen ist: weder Stelle noch Datei sind dauerhaft.
    (Key: 'Preview'; Scopes: [TAtlasHideScope.Everywhere]; Overlay: False; Gutter: False),
    (Key: 'DimUnusedUses'; Scopes: cFileScopes; Overlay: False; Gutter: False),
    (Key: 'RecursionMarkers'; Scopes: cAllScopes; Overlay: False; Gutter: True),
    // Text hinter dem Zeilenende wie eine Beschriftung; „Überall“ setzt editor.inlineDiagnostics auf aus.
    (Key: 'InlineDiagnostics'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'InlayTypeHints'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    // Marken und Historie hängen an der ganzen Datei im Repository: „Nur hier“ hielte nur bis zum nächsten Commit.
    (Key: 'GitGutter'; Scopes: cFileScopes; Overlay: False; Gutter: True),
    (Key: 'GitBlame'; Scopes: cFileScopes; Overlay: True; Gutter: False),
    // Wie die Vorschau der Vervollständigung nur bis zum nächsten Tastendruck sichtbar.
    (Key: 'ContinuePattern'; Scopes: [TAtlasHideScope.Everywhere]; Overlay: False; Gutter: False),
    (Key: 'GutterColumn'; Scopes: cAllScopes; Overlay: False; Gutter: True),
    // Nur solange die Markierung steht; Ausblenden je Datei oder überall.
    (Key: 'SelectionMatches'; Scopes: cFileScopes; Overlay: True; Gutter: False),
    (Key: 'InlayDefineHints'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'InlayCharHints'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    (Key: 'QuickBookmarksGutter'; Scopes: cAllScopes; Overlay: False; Gutter: True),
    (Key: 'InlayMethodHints'; Scopes: cAllScopes; Overlay: True; Gutter: False),
    // Nur solange der Cursor steht; Ausblenden je Datei oder überall an der Marke.
    (Key: 'ExitPoints'; Scopes: cFileScopes; Overlay: True; Gutter: False),
    // Je Datei oder überall an einer Unterstreichung.
    (Key: 'Reassigned'; Scopes: cFileScopes; Overlay: True; Gutter: False),
    // Wie die Musterfortsetzung nur bis zum nächsten Tastendruck sichtbar.
    (Key: 'SuggestionsLearned'; Scopes: [TAtlasHideScope.Everywhere]; Overlay: False; Gutter: False)
  );

function Make(AElement: TAtlasDrawnElement; const AKey: string; AScopes: TAtlasHideScopes;
  AOverlay, AGutter: Boolean): TAtlasDrawnElementInfo;
begin
  Result := Default(TAtlasDrawnElementInfo);
  Result.Element := AElement;
  Result.SettingKey := AKey;
  Result.Scopes := AScopes;
  Result.Overlay := AOverlay;
  Result.Gutter := AGutter;
end;

{ TAtlasDrawnElements }

class function TAtlasDrawnElements.Info(AElement: TAtlasDrawnElement): TAtlasDrawnElementInfo;
begin
  Result := Make(AElement, cElementRows[AElement].Key, cElementRows[AElement].Scopes, cElementRows[AElement].Overlay,
    cElementRows[AElement].Gutter);
end;

class function TAtlasDrawnElements.All: TArray<TAtlasDrawnElement>;
var
  mElement: TAtlasDrawnElement;
begin
  Result := nil;
  for mElement := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
  begin
    Result := Result + [mElement];
  end;
end;

class function TAtlasDrawnElements.SettingKey(AElement: TAtlasDrawnElement): string;
begin
  Result := Info(AElement).SettingKey;
end;

class function TAtlasDrawnElements.ForSetting(const AKey: string; out AElement: TAtlasDrawnElement): Boolean;
var
  mElement: TAtlasDrawnElement;
begin
  AElement := Low(TAtlasDrawnElement);
  for mElement := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
  begin
    if SameText(SettingKey(mElement), AKey) then
    begin
      AElement := mElement;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDrawnElements.SectionSetting(const ASectionId: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Low(cSectionIds) to High(cSectionIds) do
  begin
    if SameText(cSectionIds[mIndex], ASectionId) then
    begin
      Exit(cSectionKeys[mIndex]);
    end;
  end;
  Result := '';
end;

class function TAtlasDrawnElements.KnownSections: TArray<string>;
var
  mId: string;
begin
  Result := nil;
  for mId in cSectionIds do
  begin
    Result := Result + [mId];
  end;
end;

class function TAtlasDrawnElements.Anchor(const AText: string): string;
begin
  Result := TAtlasLineAnchors.Normalize(AText);
  if Length(Result) > cMaxAnchorLength then
  begin
    Result := TrimRight(Copy(Result, 1, cMaxAnchorLength));
  end;
end;

end.
