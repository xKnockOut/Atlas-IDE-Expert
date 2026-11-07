unit Atlas.Core.Tracker.Templates;

// Vorlagen für Abfragen des Issue-Trackers (#1263), ohne VCL und Open Tools
// API. YouTrack übersetzt die Schlüsselwörter seiner Suchsprache mit der
// Oberfläche: Bei deutscher Oberfläche findet "assignee: me #Unresolved"
// nichts, "assignee: meine #Ungelöst" dagegen die eigenen Issues. Deshalb
// gibt es die Vorlagen für YouTrack auf Deutsch und Englisch; die Vorgabe
// „Mir zugewiesen“ richtet sich nach der erkannten Sprache der Verbindung
// (TAtlasTrackerTarget.Language, erkannt in Atlas.Core.Tracker.QueryTest).
// GitHub kennt nur die englischen Suchbegriffe und keinen Sprint.
// Die Anzeigenamen der Vorlagen liefert die Oberfläche zu Kind.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Art einer Vorlage; der Name kommt aus Atlas.UI.Strings.</summary>
  TAtlasTrackerTemplateKind = (AssignedToMe, CurrentSprint, CreatedByMe, RecentlyChanged);
{$SCOPEDENUMS OFF}

  TAtlasTrackerTemplate = record
    Kind: TAtlasTrackerTemplateKind;
    /// <summary>"youtrack" oder "github".</summary>
    Provider: string;
    /// <summary>"de" oder "en".</summary>
    Language: string;
    Query: string;
  end;

  TAtlasTrackerTemplates = class
  public const
    cGerman = 'de';
    cEnglish = 'en';
  public
    /// <summary>"de", "de_DE", "de-AT" → "de"; "en…" → "en"; sonst ''.</summary>
    class function NormalLanguage(const AText: string): string; static;
    /// <summary>Vorlagen des Anbieters in der Sprache ALanguage; '' = alle Sprachen (YouTrack erst Deutsch,
    /// dann Englisch). GitHub immer Englisch.</summary>
    class function Templates(const AProvider, ALanguage: string): TArray<TAtlasTrackerTemplate>; static;
    /// <summary>Abfrage der Vorlage AKind; '' ohne (GitHub kennt keinen Sprint).</summary>
    class function QueryOf(const AProvider, ALanguage: string; AKind: TAtlasTrackerTemplateKind): string; static;
    /// <summary>„Mir zugewiesen“ in der Sprache der Verbindung; '' bei unbekannter Sprache (dann gilt die
    /// Vorgabe des Anbieters).</summary>
    class function DefaultQuery(const AProvider, ALanguage: string): string; static;
  end;

implementation

type
  TQueries = array[TAtlasTrackerTemplateKind] of string;

const
  cYouTrackGerman: TQueries = (
    'assignee: meine #Ungelöst',
    'assignee: meine #Ungelöst sprint: {Aktueller Sprint}',
    'reporter: meine #Ungelöst',
    'assignee: meine updated: {Letzte Woche}');
  cYouTrackEnglish: TQueries = (
    'assignee: me #Unresolved',
    'assignee: me #Unresolved sprint: {Current sprint}',
    'reporter: me #Unresolved',
    'assignee: me updated: {Last week}');
  // Ohne Sprint: GitHub hat keinen.
  cGitHubQueries: TQueries = (
    'assignee:@me state:open',
    '',
    'author:@me state:open',
    'involves:@me sort:updated-desc');

{ TAtlasTrackerTemplates }

class function TAtlasTrackerTemplates.NormalLanguage(const AText: string): string;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  if mText.StartsWith(cGerman) then
  begin
    Result := cGerman;
  end
  else if mText.StartsWith(cEnglish) then
  begin
    Result := cEnglish;
  end
  else
  begin
    Result := '';
  end;
end;

function Add(const AItems: TArray<TAtlasTrackerTemplate>; const AProvider, ALanguage: string;
  const AQueries: TQueries): TArray<TAtlasTrackerTemplate>;
var
  mKind: TAtlasTrackerTemplateKind;
  mItem: TAtlasTrackerTemplate;
begin
  Result := AItems;
  for mKind := Low(TAtlasTrackerTemplateKind) to High(TAtlasTrackerTemplateKind) do
  begin
    if AQueries[mKind] = '' then
    begin
      Continue;
    end;
    mItem.Kind := mKind;
    mItem.Provider := AProvider;
    mItem.Language := ALanguage;
    mItem.Query := AQueries[mKind];
    Result := Result + [mItem];
  end;
end;

class function TAtlasTrackerTemplates.Templates(const AProvider, ALanguage: string): TArray<TAtlasTrackerTemplate>;
var
  mProvider, mLanguage: string;
begin
  Result := nil;
  mProvider := LowerCase(Trim(AProvider));
  mLanguage := NormalLanguage(ALanguage);
  if mProvider = 'github' then
  begin
    Exit(Add(Result, mProvider, cEnglish, cGitHubQueries));
  end;
  if mProvider <> 'youtrack' then
  begin
    Exit;
  end;
  if mLanguage <> cEnglish then
  begin
    Result := Add(Result, mProvider, cGerman, cYouTrackGerman);
  end;
  if mLanguage <> cGerman then
  begin
    Result := Add(Result, mProvider, cEnglish, cYouTrackEnglish);
  end;
end;

class function TAtlasTrackerTemplates.QueryOf(const AProvider, ALanguage: string;
  AKind: TAtlasTrackerTemplateKind): string;
var
  mItem: TAtlasTrackerTemplate;
begin
  Result := '';
  for mItem in Templates(AProvider, ALanguage) do
  begin
    if mItem.Kind = AKind then
    begin
      Exit(mItem.Query);
    end;
  end;
end;

class function TAtlasTrackerTemplates.DefaultQuery(const AProvider, ALanguage: string): string;
begin
  // Ohne erkannte Sprache bleibt die Vorgabe des Anbieters (#765), damit sich für bestehende Verbindungen nichts
  // ändert.
  Result := '';
  if NormalLanguage(ALanguage) <> '' then
  begin
    Result := QueryOf(AProvider, ALanguage, TAtlasTrackerTemplateKind.AssignedToMe);
  end;
end;

end.
