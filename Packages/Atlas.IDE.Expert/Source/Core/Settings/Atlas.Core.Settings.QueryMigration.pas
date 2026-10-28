unit Atlas.Core.Settings.QueryMigration;

// Übernahme der einzelnen Abfrage für „Meine Issues“ in die Liste (#1262),
// ohne VCL und Open Tools API. Ein früheres issues.query bzw.
// welcomePage.issues.query (Registry IssuesQuery bzw. WelcomePageIssuesQuery)
// wird einmal zur Abfrage „Standard“ vorn in issues.queries
// (TAtlasPluginSettings.IssuesQueries); danach entfällt der Name. Gilt beim
// Start, für Stände der Einstellungshistorie und beim Import.
// Liegt bei den Einstellungen, nicht beim Tracker: Die Einstellungen hängen von
// keinem Feature ab; gelesen wird die Liste mit TAtlasTrackerQueries.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
  /// <summary>Ergebnis der Übernahme von issues.query.</summary>
  TAtlasSettingsQueryMigration = record
    /// <summary>Ein früherer Name stand in der Ablage.</summary>
    Found: Boolean;
    /// <summary>Als „Standard“ in issues.queries übernommen (False: leer oder „Standard“ gab es schon).</summary>
    Moved: Boolean;
    /// <summary>Früherer Schlüssel für das Protokoll.</summary>
    OldKey: string;
    function LogLine: string;
  end;

  TAtlasSettingsQueryMigrations = class
  public const
    Path = 'issues.queries';
    /// <summary>Name der übernommenen Abfrage aus issues.query.</summary>
    StandardName = 'Standard';
    /// <summary>Frühere Namen in TAtlasPluginSettings.Load/Save, neuer zuerst.</summary>
    LegacyName = 'IssuesQuery';
    OlderLegacyName = 'WelcomePageIssuesQuery';
    /// <summary>Name in TAtlasPluginSettings.Load/Save (settings.json).</summary>
    SettingName = 'IssuesQueries';
  public
    /// <summary>AJson mit „Standard“ = ALegacyQuery vorn; unverändert, wenn ALegacyQuery leer ist oder es
    /// „Standard“ schon gibt.</summary>
    class function WithLegacy(const AJson, ALegacyQuery: string): string; static;
    /// <summary>Früheres issues.query aus ALegacy übernehmen: nach ATarget (issues.queries) als „Standard“. Die
    /// früheren Namen entfernt erst RemoveLegacy, nachdem der Aufrufer ATarget gespeichert hat.</summary>
    class function Migrate(const ALegacy: IAtlasSettingsStore; const ALegacyNames: IAtlasSettingsNames;
      const ATarget: IAtlasSettingsStore): TAtlasSettingsQueryMigration; static;
    class procedure RemoveLegacy(const ALegacyNames: IAtlasSettingsNames); static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Settings.JsonText;

{ TAtlasSettingsQueryMigration }

function TAtlasSettingsQueryMigration.LogLine: string;
begin
  if Moved then
    Result := Format('Einstellung %s ist jetzt die Abfrage „%s“ in %s', [OldKey,
      TAtlasSettingsQueryMigrations.StandardName, TAtlasSettingsQueryMigrations.Path])
  else
    Result := Format('Einstellung %s entfällt (%s gilt)', [OldKey, TAtlasSettingsQueryMigrations.Path]);
end;

{ TAtlasSettingsQueryMigrations }

function TextOf(AItem: TJSONValue; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if not (AItem is TJSONObject) then
    Exit;
  mValue := TJSONObject(AItem).GetValue(AName);
  if mValue is TJSONString then
    Result := Trim(TJSONString(mValue).Value);
end;

/// <summary>Eine gültige Zeile „Standard“ (wie TAtlasTrackerQueries.Read: Name und Abfrage nicht leer).</summary>
function IsStandard(AItem: TJSONValue): Boolean;
begin
  Result := SameText(TextOf(AItem, 'name'), TAtlasSettingsQueryMigrations.StandardName) and
    (TextOf(AItem, 'query') <> '');
end;

class function TAtlasSettingsQueryMigrations.WithLegacy(const AJson, ALegacyQuery: string): string;
var
  mQuery: string;
  mRoot: TJSONValue;
  mItem: TJSONValue;
  mParts: TArray<string>;
begin
  Result := AJson;
  // Einzeilig wie TAtlasTrackerQuery.Create: der Anbieter hängt die Abfrage an die Adresse.
  mQuery := Trim(ALegacyQuery.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' '));
  if mQuery = '' then
    Exit;
  mParts := TArray<string>.Create('{"name": ' + TAtlasJsonText.Quote(StandardName) + ', "query": ' +
    TAtlasJsonText.Quote(mQuery) + '}');
  mRoot := nil;
  if Trim(AJson) <> '' then
    mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if mRoot is TJSONArray then
      for mItem in TJSONArray(mRoot) do
      begin
        if IsStandard(mItem) then
          Exit;
        mParts := mParts + [mItem.ToJSON];
      end;
  finally
    mRoot.Free;
  end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasSettingsQueryMigrations.Migrate(const ALegacy: IAtlasSettingsStore;
  const ALegacyNames: IAtlasSettingsNames; const ATarget: IAtlasSettingsStore): TAtlasSettingsQueryMigration;
var
  mLegacy, mBefore, mAfter: string;
begin
  Result := Default(TAtlasSettingsQueryMigration);
  // issues.query (#1280) vor welcomePage.issues.query; beide entfallen danach.
  if ALegacyNames.Contains(LegacyName) then
  begin
    Result.OldKey := 'issues.query';
    mLegacy := ALegacy.ReadString(LegacyName, '');
  end
  else if ALegacyNames.Contains(OlderLegacyName) then
  begin
    Result.OldKey := 'welcomePage.issues.query';
    mLegacy := ALegacy.ReadString(OlderLegacyName, '');
  end
  else
    Exit;
  Result.Found := True;
  mBefore := ATarget.ReadString(SettingName, '[]');
  mAfter := WithLegacy(mBefore, mLegacy);
  Result.Moved := mAfter <> mBefore;
  if Result.Moved then
    ATarget.WriteString(SettingName, mAfter);
end;

class procedure TAtlasSettingsQueryMigrations.RemoveLegacy(const ALegacyNames: IAtlasSettingsNames);
begin
  ALegacyNames.Remove(LegacyName);
  ALegacyNames.Remove(OlderLegacyName);
end;

end.
