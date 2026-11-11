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
    cPath = 'issues.queries';
    /// <summary>Name der übernommenen Abfrage aus issues.query.</summary>
    cStandardName = 'Standard';
    /// <summary>Frühere Namen in TAtlasPluginSettings.Load/Save, neuer zuerst.</summary>
    cLegacyName = 'IssuesQuery';
    cOlderLegacyName = 'WelcomePageIssuesQuery';
    /// <summary>Name in TAtlasPluginSettings.Load/Save (settings.json).</summary>
    cSettingName = 'IssuesQueries';
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
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.JsonText,
  Atlas.Text.Json;

{ TAtlasSettingsQueryMigration }

function TAtlasSettingsQueryMigration.LogLine: string;
begin
  if Moved then
  begin
    Result := Format('Einstellung %s ist jetzt die Abfrage „%s“ in %s', [OldKey,
      TAtlasSettingsQueryMigrations.cStandardName, TAtlasSettingsQueryMigrations.cPath]);
  end
  else
  begin
    Result := Format('Einstellung %s entfällt (%s gilt)', [OldKey, TAtlasSettingsQueryMigrations.cPath]);
  end;
end;

{ TAtlasSettingsQueryMigrations }

/// <summary>Eine gültige Zeile „Standard“ (wie TAtlasTrackerQueries.Read: Name und Abfrage nicht leer).</summary>
function IsStandard(AItem: TJSONValue): Boolean;
begin
  Result := SameText(TJsonRead.TrimmedText(TJsonRead.AsObject(AItem), 'name'), TAtlasSettingsQueryMigrations.cStandardName) and
    (TJsonRead.TrimmedText(TJsonRead.AsObject(AItem), 'query') <> '');
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
  begin
    Exit;
  end;
  mParts := TArray<string>.Create('{"name": ' + TAtlasJsonText.Quote(cStandardName) + ', "query": ' +
    TAtlasJsonText.Quote(mQuery) + '}');
  mRoot := nil;
  if Trim(AJson) <> '' then
  begin
    mRoot := TJSONObject.ParseJSONValue(AJson);
  end;
  try
    if mRoot is TJSONArray then
    begin
      for mItem in TJSONArray(mRoot) do
      begin
        if IsStandard(mItem) then
        begin
          Exit;
        end;
        mParts := mParts + [mItem.ToJSON([])];
      end;
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
  if ALegacyNames.Contains(cLegacyName) then
  begin
    Result.OldKey := 'issues.query';
    mLegacy := ALegacy.ReadString(cLegacyName, '');
  end
  else if ALegacyNames.Contains(cOlderLegacyName) then
  begin
    Result.OldKey := 'welcomePage.issues.query';
    mLegacy := ALegacy.ReadString(cOlderLegacyName, '');
  end
  else
  begin
    Exit;
  end;
  Result.Found := True;
  mBefore := ATarget.ReadString(cSettingName, '[]');
  mAfter := WithLegacy(mBefore, mLegacy);
  Result.Moved := mAfter <> mBefore;
  if Result.Moved then
  begin
    ATarget.WriteString(cSettingName, mAfter);
  end;
end;

class procedure TAtlasSettingsQueryMigrations.RemoveLegacy(const ALegacyNames: IAtlasSettingsNames);
begin
  ALegacyNames.Remove(cLegacyName);
  ALegacyNames.Remove(cOlderLegacyName);
end;

end.
