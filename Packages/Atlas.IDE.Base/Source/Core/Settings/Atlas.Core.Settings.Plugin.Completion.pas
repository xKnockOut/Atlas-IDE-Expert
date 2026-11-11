unit Atlas.Core.Settings.Plugin.Completion;

// Einstellungen des IDE-Plugins, Bereich Vervollständigung (completion.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  cMinVisibleRows = 5;
  cMaxVisibleRows = 20;
  cMinListWidth = 240;
  cMaxListWidth = 720;
  cMinPanelWidth = 220;
  cMaxPanelWidth = 600;
  /// <summary>Verzögerung bis zum automatischen Öffnen der Liste (ARG-046, #227); 0 = sofort.</summary>
  cMaxOpenDelay = 2000;
  /// <summary>Grenzen der gelernten Vorschläge (#1890): Pause in ms, Anteil in %, Mindestzahl.</summary>
  cMinSuggestionDelay = 100;
  cMaxSuggestionDelay = 2000;
  cMinSuggestionShare = 50;
  cMaxSuggestionShare = 100;
  cMinSuggestionCount = 2;
  cMaxSuggestionCount = 100;
  cDefaultSuggestionDelay = 300;
  cDefaultSuggestionShare = 70;
  cDefaultSuggestionCount = 5;
  /// <summary>Wie TAtlasListModes.cModeNames bzw. ScopeNames (#497); Settings darf Completion nicht einbinden
  /// (A-09), der Test prüft Gleichheit.</summary>
  cCompletionListModeNames: array[0..2] of string = ('filter', 'all', 'rest');
  cCompletionListScopeNames: array[0..1] of string = ('members', 'everywhere');

type
  /// <summary>Plugin-Einstellungen: Liste, Einfügen und Vorschau der Vervollständigung.</summary>
  TAtlasPluginCompletionSettings = record
    /// <summary>Hauptschalter (#407): aus = eingebaute Code Insight der IDE.</summary>
    Enabled: Boolean;
    /// <summary>Sichtbare Zeilen der Liste (#413).</summary>
    VisibleRows: Integer;
    /// <summary>Von Hand gezogene Breite der Liste, 0 = automatisch (#416).</summary>
    ListWidth: Integer;
    /// <summary>Breite des Detailpanels (#416).</summary>
    PanelWidth: Integer;
    /// <summary>Detailpanel eingeklappt (#428).</summary>
    PanelCollapsed: Boolean;
    /// <summary>Gewählter Eintrag mit Rahmen und Marke statt nur farbig (#447).</summary>
    SelectionMarker: Boolean;
    /// <summary>Klammern beim Übernehmen von Methoden (#430).</summary>
    AutoParentheses: Boolean;
    /// <summary>Schreibweise des getippten Worts beim Übernehmen korrigieren (#433).</summary>
    FixCase: Boolean;
    /// <summary>Übernehmen über "(", ";" und "." (#429).</summary>
    CommitCharacters: Boolean;
    /// <summary>Unit beim Übernehmen automatisch in uses eintragen (#180).</summary>
    AutoUses: Boolean;
    /// <summary>Parameter-Hint bei "(" und "," (#436).</summary>
    ParameterHints: Boolean;
    /// <summary>Platzhalter von Format im Parameter-Hint zuordnen und im Editor einfärben (#451).</summary>
    FormatPlaceholders: Boolean;
    /// <summary>Millisekunden zwischen automatischem Auslösen (".") und dem Öffnen der Liste (ARG-046).</summary>
    OpenDelayMs: Integer;
    /// <summary>Filter-Chips über der Liste (#422).</summary>
    FilterChips: Boolean;
    /// <summary>Lernende Gewichtung (#418).</summary>
    Learning: Boolean;
    /// <summary>Favoriten anheften (#458): Strg+D bzw. Stern in der Liste, angeheftete Einträge stehen oben;
    /// gespeichert in %APPDATA%\Atlas\favorites.json.</summary>
    Favorites: Boolean;
    /// <summary>Geerbte Member nachrangig und gruppiert (#419).</summary>
    GroupInherited: Boolean;
    /// <summary>Marke „Zweig 0“ an Feldern varianter Records (#846, completion.variantBranch).</summary>
    CompletionVariantBranch: Boolean;
    /// <summary>Beim Tippen nur Treffer (filter), alle Einträge mit Treffern oben (all) oder Treffer und darunter
    /// gedämpft der Rest (rest) (completion.listMode, #497).</summary>
    CompletionListMode: string;
    /// <summary>Wo der Listenmodus gilt: Mitgliederlisten nach "." (members) oder überall (everywhere)
    /// (completion.listMode.scope, #497).</summary>
    CompletionListScope: string;
    /// <summary>Vorschau des gewählten Eintrags im Editor (#434).</summary>
    Preview: Boolean;
    /// <summary>Gelernte Vorschläge als Schattentext nach einem Auslöser (#1890, suggestions.learned).</summary>
    SuggestionsLearned: Boolean;
    /// <summary>Tipp-Pause bis zum Vorschlag in ms (suggestions.delayMs).</summary>
    SuggestionsDelayMs: Integer;
    /// <summary>Mindestanteil der Folge an allen Folgen des Auslösers in % (suggestions.minShare).</summary>
    SuggestionsMinShare: Integer;
    /// <summary>Mindestzahl der Stellen im Projekt (suggestions.minCount).</summary>
    SuggestionsMinCount: Integer;
    /// <summary>Annehmen und Verwerfen je Muster zählen und die Reihenfolge danach richten
    /// (suggestions.learnFromUsage).</summary>
    SuggestionsLearnFromUsage: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginCompletionSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math;

{ TAtlasPluginCompletionSettings }

class function TAtlasPluginCompletionSettings.Defaults: TAtlasPluginCompletionSettings;
begin
  Result.Enabled := True;
  Result.VisibleRows := 9;
  Result.ListWidth := 0;
  Result.PanelWidth := 320;
  Result.PanelCollapsed := False;
  Result.SelectionMarker := True;
  Result.AutoParentheses := True;
  Result.FixCase := True;
  Result.CommitCharacters := True;
  Result.AutoUses := True;
  Result.ParameterHints := True;
  Result.FormatPlaceholders := True;
  Result.OpenDelayMs := 150;
  Result.FilterChips := True;
  Result.Learning := True;
  Result.Favorites := True;
  Result.GroupInherited := True;
  Result.CompletionVariantBranch := True;
  Result.CompletionListMode := cCompletionListModeNames[0];
  Result.CompletionListScope := cCompletionListScopeNames[0];
  Result.Preview := False;
  Result.SuggestionsLearned := True;
  Result.SuggestionsDelayMs := cDefaultSuggestionDelay;
  Result.SuggestionsMinShare := cDefaultSuggestionShare;
  Result.SuggestionsMinCount := cDefaultSuggestionCount;
  Result.SuggestionsLearnFromUsage := True;
end;

procedure TAtlasPluginCompletionSettings.Normalize;
begin
  VisibleRows := EnsureRange(VisibleRows, cMinVisibleRows, cMaxVisibleRows);
  if ListWidth <> 0 then
  begin
    ListWidth := EnsureRange(ListWidth, cMinListWidth, cMaxListWidth);
  end;
  PanelWidth := EnsureRange(PanelWidth, cMinPanelWidth, cMaxPanelWidth);
  CompletionListMode := Choice(CompletionListMode, cCompletionListModeNames);
  CompletionListScope := Choice(CompletionListScope, cCompletionListScopeNames);
  OpenDelayMs := EnsureRange(OpenDelayMs, 0, cMaxOpenDelay);
  SuggestionsDelayMs := EnsureRange(SuggestionsDelayMs, cMinSuggestionDelay, cMaxSuggestionDelay);
  SuggestionsMinShare := EnsureRange(SuggestionsMinShare, cMinSuggestionShare, cMaxSuggestionShare);
  SuggestionsMinCount := EnsureRange(SuggestionsMinCount, cMinSuggestionCount, cMaxSuggestionCount);
end;

procedure TAtlasPluginCompletionSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('Enabled', Enabled);
  AIo.Number('VisibleRows', VisibleRows);
  AIo.Number('ListWidth', ListWidth);
  AIo.Number('PanelWidth', PanelWidth);
  AIo.Flag('PanelCollapsed', PanelCollapsed);
  AIo.Flag('SelectionMarker', SelectionMarker);
  AIo.Flag('AutoParentheses', AutoParentheses);
  AIo.Flag('FixCase', FixCase);
  AIo.Flag('CommitCharacters', CommitCharacters);
  AIo.Flag('AutoUses', AutoUses);
  AIo.Flag('ParameterHints', ParameterHints);
  AIo.Flag('FormatPlaceholders', FormatPlaceholders);
  AIo.Number('OpenDelayMs', OpenDelayMs);
  AIo.Flag('FilterChips', FilterChips);
  AIo.Flag('Learning', Learning);
  AIo.Flag('Favorites', Favorites);
  AIo.Flag('GroupInherited', GroupInherited);
  AIo.Flag('CompletionVariantBranch', CompletionVariantBranch);
  AIo.Text('CompletionListMode', CompletionListMode);
  AIo.Text('CompletionListScope', CompletionListScope);
  AIo.Flag('Preview', Preview);
  AIo.Flag('SuggestionsLearned', SuggestionsLearned);
  AIo.Number('SuggestionsDelayMs', SuggestionsDelayMs);
  AIo.Number('SuggestionsMinShare', SuggestionsMinShare);
  AIo.Number('SuggestionsMinCount', SuggestionsMinCount);
  AIo.Flag('SuggestionsLearnFromUsage', SuggestionsLearnFromUsage);
end;

end.
