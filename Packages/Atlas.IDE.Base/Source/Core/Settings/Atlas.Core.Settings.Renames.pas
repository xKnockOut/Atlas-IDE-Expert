unit Atlas.Core.Settings.Renames;

// Umbenannte Plugin-Einstellungen übernehmen (#1280), ohne VCL und ohne
// Registry. Grundlage ist x-renamedFrom im Plugin-Katalog: frühere Namen in
// TAtlasPluginSettings.Load/Save (Registry), unter denen derselbe Wert
// unverändert gespeichert war. Anders als x-formerKeys, das auch umgerechnete
// Werte meint (hints.xmlDocFull → hints.xmlDocExpand) und nur der Import
// auswertet, darf hier ohne Sondercode kopiert werden. Je früherem Namen mit
// Wert:
// - neuer Name ohne Wert: Wert übernehmen, alten entfernen (Übernommen);
// - neuer Name mit Wert: der neue gilt, der alte wird entfernt (Verworfen);
// - Wert der falschen Art (Text statt Zahl o. ä.): alten entfernen (Ungültig).
// Danach steht kein früherer Name mehr in der Ablage, ein zweiter Start findet
// nichts. Die Ergebnisse protokolliert der Aufrufer, eine Zeile je Übernahme.

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog;

type
  TAtlasSettingsRenameOutcome = (srMoved, srSuperseded, srInvalid);

  TAtlasSettingsRename = record
    /// <summary>Früherer Name in der Ablage (x-renamedFrom).</summary>
    OldName: string;
    /// <summary>Früherer Schlüssel für das Protokoll: erster Eintrag von x-formerKeys, sonst OldName.</summary>
    OldKey: string;
    /// <summary>Name in TAtlasPluginSettings.Load/Save.</summary>
    NewName: string;
    /// <summary>Schlüssel (x-key) der Einstellung.</summary>
    NewKey: string;
    Outcome: TAtlasSettingsRenameOutcome;
    /// <summary>Eine Zeile für das Protokoll, z. B. „Einstellung welcomePage.issues.query heißt jetzt
    /// issues.query“.</summary>
    function LogLine: string;
  end;

  TAtlasSettingsRenames = class
  public
    /// <summary>Frühere Namen aller Plugin-Einträge in ACatalog nach x-renamedFrom übernehmen: AStore liest und
    /// schreibt die Werte, ANames prüft und entfernt die Namen (meist dasselbe Objekt). Liefert je gefundenem
    /// früheren Namen ein Ergebnis; leer, wenn nichts zu tun war.</summary>
    class function Apply(const AStore: IAtlasSettingsStore; const ANames: IAtlasSettingsNames;
      ACatalog: TAtlasSettingsCatalog): TArray<TAtlasSettingsRename>; static;
  end;

implementation

uses
  System.SysUtils;

// Wert unter AName in der Art von AKind lesen; False, wenn dort ein Wert anderer Art steht. Zwei Lesungen mit
// verschiedener Vorgabe unterscheiden „Wert gleich Vorgabe“ von „Wert nicht lesbar“.
function ReadValue(const AStore: IAtlasSettingsStore; AKind: TAtlasSettingKind; const AName: string;
  out ANumber: Integer; out AText: string): Boolean;
begin
  ANumber := 0;
  AText := '';
  if AKind in [akBoolean, akInteger] then
  begin
    ANumber := AStore.ReadInteger(AName, 0);
    Result := (ANumber <> 0) or (AStore.ReadInteger(AName, 1) = 0);
  end
  else
  begin
    AText := AStore.ReadString(AName, '');
    Result := (AText <> '') or (AStore.ReadString(AName, #1) = '');
  end;
end;

{ TAtlasSettingsRename }

function TAtlasSettingsRename.LogLine: string;
begin
  case Outcome of
    srMoved:
      Result := Format('Einstellung %s heißt jetzt %s; Wert übernommen', [OldKey, NewKey]);
    srSuperseded:
      Result := Format('Warnung: Einstellung %s stand zusätzlich unter dem früheren Namen %s; ' +
        'es gilt der neue Wert, der alte wurde entfernt', [NewKey, OldKey]);
  else
    Result := Format('Warnung: Einstellung %s (früher %s) hatte einen Wert der falschen Art; er wurde entfernt',
      [NewKey, OldKey]);
  end;
end;

{ TAtlasSettingsRenames }

class function TAtlasSettingsRenames.Apply(const AStore: IAtlasSettingsStore; const ANames: IAtlasSettingsNames;
  ACatalog: TAtlasSettingsCatalog): TArray<TAtlasSettingsRename>;
var
  Index: Integer;
  Entry: TAtlasCatalogEntry;
  Former: string;
  Rename: TAtlasSettingsRename;
  Number: Integer;
  Text: string;
begin
  Result := nil;
  for Index := 0 to ACatalog.Count - 1 do
  begin
    Entry := ACatalog[Index];
    if Entry.Source <> asPlugin then
      Continue;
    for Former in Entry.RenamedFrom do
    begin
      if SameText(Former, Entry.Name) or not ANames.Contains(Former) then
        Continue;
      Rename := Default(TAtlasSettingsRename);
      Rename.OldName := Former;
      Rename.OldKey := Former;
      if Length(Entry.FormerKeys) > 0 then
        Rename.OldKey := Entry.FormerKeys[0];
      Rename.NewName := Entry.Name;
      Rename.NewKey := Entry.Key;
      if ANames.Contains(Entry.Name) then
        Rename.Outcome := srSuperseded
      else if not ReadValue(AStore, Entry.Kind, Former, Number, Text) then
        Rename.Outcome := srInvalid
      else
      begin
        if Entry.Kind in [akBoolean, akInteger] then
          AStore.WriteInteger(Entry.Name, Number)
        else
          AStore.WriteString(Entry.Name, Text);
        Rename.Outcome := srMoved;
      end;
      ANames.Remove(Former);
      Result := Result + [Rename];
    end;
  end;
end;

end.
