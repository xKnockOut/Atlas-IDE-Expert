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
    /// <summary>Hervorgehobene Austrittspunkte samt Marke am Routinenkopf (#698).</summary>
    ExitPoints);
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
    MaxAnchorLength = 120;
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
  SectionIds: array[0..12] of string = ('atlas.header', 'atlas.state', 'atlas.continue', 'atlas.projects',
    'atlas.history', 'atlas.news', 'atlas.discover', 'atlas.setup', 'atlas.search', 'atlas.unsaved', 'atlas.tests',
    'atlas.help', 'atlas.issues');
  SectionKeys: array[0..12] of string = ('WelcomePageHeader', 'WelcomePageStatusTile', 'WelcomePageContinue',
    'WelcomePageProjectStatus', 'WelcomePageTrends', 'WelcomePageWhatsNew', 'WelcomePageDiscover',
    'WelcomePageProjectSetup', 'WelcomePageSearch', 'WelcomePageUnsaved', 'WelcomePageTests', 'WelcomePageHelp',
    'WelcomePageIssues');

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
const
  AllScopes = [TAtlasHideScope.Here, TAtlasHideScope.InFile, TAtlasHideScope.Everywhere];
  FileScopes = [TAtlasHideScope.InFile, TAtlasHideScope.Everywhere];
begin
  case AElement of
    TAtlasDrawnElement.CodeLensMetrics:
      Result := Make(AElement, 'CodeLensMetrics', AllScopes, True, False);
    TAtlasDrawnElement.CodeLensTests:
      Result := Make(AElement, 'CodeLensTests', AllScopes, True, False);
    // Nur einmal je Datei: „Nur hier“ wäre dasselbe wie „In dieser Datei“.
    TAtlasDrawnElement.CodeLensTestUnit:
      Result := Make(AElement, 'CodeLensTestUnit', FileScopes, True, False);
    TAtlasDrawnElement.BlockEndLabels:
      Result := Make(AElement, 'BlockEndLabels', AllScopes, True, False);
    TAtlasDrawnElement.InlayHints:
      Result := Make(AElement, 'InlayHints', AllScopes, True, False);
    TAtlasDrawnElement.Problems:
      Result := Make(AElement, 'Problems', AllScopes, False, False);
    TAtlasDrawnElement.Notes:
      Result := Make(AElement, 'Notes', AllScopes, False, True);
    TAtlasDrawnElement.Bookmarks:
      Result := Make(AElement, 'BookmarksNamed', AllScopes, False, True);
    // Farben und Linien gehören zum ganzen Block: an einer einzelnen Stelle ergibt Ausblenden keinen Sinn.
    TAtlasDrawnElement.PairColors:
      Result := Make(AElement, 'PairColors', FileScopes, False, False);
    TAtlasDrawnElement.PairGuides:
      Result := Make(AElement, 'PairGuides', FileScopes, False, False);
    TAtlasDrawnElement.PairOwners:
      Result := Make(AElement, 'PairOwners', FileScopes, False, False);
    TAtlasDrawnElement.InactiveDim:
      Result := Make(AElement, 'InactiveDim', FileScopes, False, False);
    // Die Vorschau steht nur, solange die Liste offen ist: weder Stelle noch Datei sind dauerhaft.
    TAtlasDrawnElement.CompletionPreview:
      Result := Make(AElement, 'Preview', [TAtlasHideScope.Everywhere], False, False);
    TAtlasDrawnElement.UnusedUses:
      Result := Make(AElement, 'DimUnusedUses', FileScopes, False, False);
    TAtlasDrawnElement.Recursion:
      Result := Make(AElement, 'RecursionMarkers', AllScopes, False, True);
    // Text hinter dem Zeilenende wie eine Beschriftung; „Überall“ setzt editor.inlineDiagnostics auf aus.
    TAtlasDrawnElement.InlineDiagnostics:
      Result := Make(AElement, 'InlineDiagnostics', AllScopes, True, False);
    TAtlasDrawnElement.InlayTypeHints:
      Result := Make(AElement, 'InlayTypeHints', AllScopes, True, False);
    // Marken und Historie hängen an der ganzen Datei im Repository: „Nur hier“ hielte nur bis zum nächsten Commit.
    TAtlasDrawnElement.GitGutter:
      Result := Make(AElement, 'GitGutter', FileScopes, False, True);
    TAtlasDrawnElement.GitBlame:
      Result := Make(AElement, 'GitBlame', FileScopes, True, False);
    // Wie die Vorschau der Vervollständigung nur bis zum nächsten Tastendruck sichtbar.
    TAtlasDrawnElement.PatternPreview:
      Result := Make(AElement, 'ContinuePattern', [TAtlasHideScope.Everywhere], False, False);
    TAtlasDrawnElement.GutterColumn:
      Result := Make(AElement, 'GutterColumn', AllScopes, False, True);
    // Nur solange die Markierung steht; Ausblenden je Datei oder überall.
    TAtlasDrawnElement.SelectionMatches:
      Result := Make(AElement, 'SelectionMatches', FileScopes, True, False);
    TAtlasDrawnElement.InlayDefineHints:
      Result := Make(AElement, 'InlayDefineHints', AllScopes, True, False);
    TAtlasDrawnElement.InlayCharHints:
      Result := Make(AElement, 'InlayCharHints', AllScopes, True, False);
    TAtlasDrawnElement.QuickBookmarks:
      Result := Make(AElement, 'QuickBookmarksGutter', AllScopes, False, True);
    // Nur solange der Cursor steht; Ausblenden je Datei oder überall an der Marke.
    TAtlasDrawnElement.ExitPoints:
      Result := Make(AElement, 'ExitPoints', FileScopes, True, False);
  else
    Result := Make(AElement, '', [], False, False);
  end;
end;

class function TAtlasDrawnElements.All: TArray<TAtlasDrawnElement>;
var
  Element: TAtlasDrawnElement;
begin
  Result := nil;
  for Element := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
    Result := Result + [Element];
end;

class function TAtlasDrawnElements.SettingKey(AElement: TAtlasDrawnElement): string;
begin
  Result := Info(AElement).SettingKey;
end;

class function TAtlasDrawnElements.ForSetting(const AKey: string; out AElement: TAtlasDrawnElement): Boolean;
var
  Element: TAtlasDrawnElement;
begin
  AElement := Low(TAtlasDrawnElement);
  for Element := Low(TAtlasDrawnElement) to High(TAtlasDrawnElement) do
    if SameText(SettingKey(Element), AKey) then
    begin
      AElement := Element;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasDrawnElements.SectionSetting(const ASectionId: string): string;
var
  Index: Integer;
begin
  for Index := Low(SectionIds) to High(SectionIds) do
    if SameText(SectionIds[Index], ASectionId) then
      Exit(SectionKeys[Index]);
  Result := '';
end;

class function TAtlasDrawnElements.KnownSections: TArray<string>;
var
  Id: string;
begin
  Result := nil;
  for Id in SectionIds do
    Result := Result + [Id];
end;

class function TAtlasDrawnElements.Anchor(const AText: string): string;
begin
  Result := TAtlasLineAnchors.Normalize(AText);
  if Length(Result) > MaxAnchorLength then
    Result := TrimRight(Copy(Result, 1, MaxAnchorLength));
end;

end.
