unit Atlas.Core.Welcome.WhatsNew;

// Karte „Neu in Atlas“ der Willkommensseite (#756), Teil ohne VCL und Open
// Tools API. Quelle ist whatsnew.json aus dem Installationsordner (erzeugt im
// Release aus den markierten Einträgen von CHANGELOG.md, Tools/
// Update-WhatsNew.ps1); kein Netzabruf:
//   {"versions": [{"version": "1.1.0", "items": [{"title": "…", "text": "…",
//     "setting": "WelcomePageSearch", "key": "WelcomePageSearchKey",
//     "command": "Atlas.WelcomeStart", "sample": "Beispiele\\Suche.pas",
//     "line": 12}]}]}
// setting: Name der Plugin-Einstellung (wie in der Registry), die der Schalter
// der Zeile setzt; key: Einstellung mit dem Tastenkürzel (TShortCut), damit
// die Karte die tatsächliche Belegung zeigt; command: Atlas-Befehl der
// Palette für „Ausprobieren“, sonst sample (relativ zum Installationsordner)
// mit Zeile ab 1. Alles außer title ist freiwillig.
// Welche Versionen die Karte zeigt, regelt welcomePage.whatsNew: off nie,
// afterUpdate einmalig nach einem Versionswechsel (alle übersprungenen
// Versionen, nach Version gruppiert), always immer (dann ohne Ungelesenes die
// Neuerungen der aktuellen Version). Die zuletzt gesehene Version steht in
// der Registry des Plugins; bei der ersten Installation gibt es nichts
// Ungelesenes.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasWhatsNewItem = record
    Title: string;
    Text: string;
    Setting: string;
    Key: string;
    Command: string;
    Sample: string;
    /// <summary>Zeile in Sample ab 1; 0 = Anfang.</summary>
    Line: Integer;
  end;

  TAtlasWhatsNewVersion = record
    Version: string;
    Items: TArray<TAtlasWhatsNewItem>;
  end;

  TAtlasWhatsNewVersions = TArray<TAtlasWhatsNewVersion>;

{$SCOPEDENUMS ON}
  TAtlasWhatsNewMode = (Off, AfterUpdate, Always);
  /// <summary>Was die Karte gerade zeigt: Ungelesenes nach Update, die aktuelle Version, alle Versionen.</summary>
  TAtlasWhatsNewView = (Hidden, Unread, Current, All);
{$SCOPEDENUMS OFF}

  TAtlasWhatsNew = class
  public const
    FileName = 'whatsnew.json';
    ModeOff = 'off';
    ModeAfterUpdate = 'afterUpdate';
    ModeAlways = 'always';
  public
    /// <summary>Versionen aus whatsnew.json, neueste zuerst, ohne Versionen ohne Einträge; leer bei ungültigem
    /// Inhalt. Einträge ohne Titel fallen weg.</summary>
    class function Parse(const AJson: string): TAtlasWhatsNewVersions; static;
    /// <summary>Vergleich nach SemVer: Zahlen numerisch, Vorabversion („1.1.0-beta.2“) vor der Version;
    /// '' gilt als kleiner als alles.</summary>
    class function CompareVersions(const A, B: string): Integer; static;
    /// <summary>Versionen mit ASeen &lt; Version &lt;= ACurrent, neueste zuerst.</summary>
    class function Between(const AVersions: TAtlasWhatsNewVersions; const ASeen, ACurrent: string): TAtlasWhatsNewVersions; static;
    /// <summary>Neueste Version &lt;= ACurrent mit Einträgen (für „Neuigkeiten dieser Version“); leer ohne.</summary>
    class function Latest(const AVersions: TAtlasWhatsNewVersions; const ACurrent: string): TAtlasWhatsNewVersions; static;
    /// <summary>Alle Versionen &lt;= ACurrent, neueste zuerst.</summary>
    class function UpTo(const AVersions: TAtlasWhatsNewVersions; const ACurrent: string): TAtlasWhatsNewVersions; static;
    /// <summary>Einstellung welcomePage.whatsNew; Unbekanntes gilt als afterUpdate.</summary>
    class function ModeOf(const AValue: string): TAtlasWhatsNewMode; static;
    class function ModeName(AMode: TAtlasWhatsNewMode): string; static;
    /// <summary>Was die Karte ohne Zutun des Benutzers zeigt. ASeen = '' (erste Installation) zählt nicht als
    /// Update.</summary>
    class function ViewFor(AMode: TAtlasWhatsNewMode; const AVersions: TAtlasWhatsNewVersions;
      const ASeen, ACurrent: string): TAtlasWhatsNewView; static;
    /// <summary>Die Versionen zu AView.</summary>
    class function VersionsFor(AView: TAtlasWhatsNewView; const AVersions: TAtlasWhatsNewVersions;
      const ASeen, ACurrent: string): TAtlasWhatsNewVersions; static;
    /// <summary>Gesehene Version, die nach dem Start gespeichert wird: bei der ersten Installation die aktuelle
    /// (es gibt nichts Ungelesenes), sonst unverändert bis „Gelesen“.</summary>
    class function SeenAfterStart(const ASeen, ACurrent: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults;

function Text(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := Trim(TJSONString(Value).Value);
end;

function Number(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else if Value is TJSONString then
    Result := StrToIntDef(TJSONString(Value).Value, 0);
  if Result < 0 then
    Result := 0;
end;

class function TAtlasWhatsNew.Parse(const AJson: string): TAtlasWhatsNewVersions;
var
  Root, Versions, Items: TJSONValue;
  VersionValue, ItemValue: TJSONValue;
  Version: TAtlasWhatsNewVersion;
  Item: TAtlasWhatsNewItem;
  List: TList<TAtlasWhatsNewVersion>;
begin
  Result := nil;
  Root := nil;
  try
    Root := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: keine Karte, kein Fehler in der IDE.
    on Exception do
      Root := nil;
  end;
  List := TList<TAtlasWhatsNewVersion>.Create;
  try
    if not (Root is TJSONObject) then
      Exit;
    Versions := TJSONObject(Root).GetValue('versions');
    if not (Versions is TJSONArray) then
      Exit;
    for VersionValue in TJSONArray(Versions) do
    begin
      if not (VersionValue is TJSONObject) then
        Continue;
      Version := Default(TAtlasWhatsNewVersion);
      Version.Version := Text(TJSONObject(VersionValue), 'version');
      Items := TJSONObject(VersionValue).GetValue('items');
      if (Version.Version = '') or not (Items is TJSONArray) then
        Continue;
      for ItemValue in TJSONArray(Items) do
      begin
        if not (ItemValue is TJSONObject) then
          Continue;
        Item := Default(TAtlasWhatsNewItem);
        Item.Title := Text(TJSONObject(ItemValue), 'title');
        Item.Text := Text(TJSONObject(ItemValue), 'text');
        Item.Setting := Text(TJSONObject(ItemValue), 'setting');
        Item.Key := Text(TJSONObject(ItemValue), 'key');
        Item.Command := Text(TJSONObject(ItemValue), 'command');
        Item.Sample := Text(TJSONObject(ItemValue), 'sample');
        Item.Line := Number(TJSONObject(ItemValue), 'line');
        if Item.Title <> '' then
          Version.Items := Version.Items + [Item];
      end;
      if Length(Version.Items) > 0 then
        List.Add(Version);
    end;
    List.Sort(TComparer<TAtlasWhatsNewVersion>.Construct(
      function(const A, B: TAtlasWhatsNewVersion): Integer
      begin
        Result := CompareVersions(B.Version, A.Version);
      end));
    Result := List.ToArray;
  finally
    List.Free;
    Root.Free;
  end;
end;

/// <summary>Teile einer Version: Kern "1.2.3" und Vorabversion "beta.2" ('' ohne); "v" davor und "+Build"
/// dahinter fallen weg.</summary>
procedure SplitVersion(const AVersion: string; out ACore, APre: string);
var
  Value: string;
  At: Integer;
begin
  Value := Trim(AVersion);
  if (Value <> '') and CharInSet(Value[1], ['v', 'V']) then
    Delete(Value, 1, 1);
  At := Pos('+', Value);
  if At > 0 then
    Value := Copy(Value, 1, At - 1);
  At := Pos('-', Value);
  if At > 0 then
  begin
    ACore := Copy(Value, 1, At - 1);
    APre := Copy(Value, At + 1, MaxInt);
  end
  else
  begin
    ACore := Value;
    APre := '';
  end;
end;

function IsNumber(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  for Index := 1 to Length(AText) do
    if not CharInSet(AText[Index], ['0'..'9']) then
      Exit(False);
end;

function CompareParts(const A, B: TArray<string>; ANumbersOnly: Boolean): Integer;
var
  Index: Integer;
  Left, Right: string;
begin
  for Index := 0 to Length(A) - 1 do
  begin
    if Index > High(B) then
      Exit(1);
    Left := A[Index];
    Right := B[Index];
    if ANumbersOnly or (IsNumber(Left) and IsNumber(Right)) then
      Result := StrToIntDef(Left, 0) - StrToIntDef(Right, 0)
    else if IsNumber(Left) then
      // SemVer: Zahlen vor Text.
      Result := -1
    else if IsNumber(Right) then
      Result := 1
    else
      Result := CompareStr(Left, Right);
    if Result <> 0 then
      Exit;
  end;
  if Length(B) > Length(A) then
    Exit(-1);
  Result := 0;
end;

class function TAtlasWhatsNew.CompareVersions(const A, B: string): Integer;
var
  CoreA, PreA, CoreB, PreB: string;
  PartsA, PartsB: TArray<string>;
begin
  if Trim(A) = Trim(B) then
    Exit(0);
  if Trim(A) = '' then
    Exit(-1);
  if Trim(B) = '' then
    Exit(1);
  SplitVersion(A, CoreA, PreA);
  SplitVersion(B, CoreB, PreB);
  PartsA := CoreA.Split(['.']);
  PartsB := CoreB.Split(['.']);
  // "1.1" und "1.1.0" sind gleich.
  while Length(PartsA) < 3 do
    PartsA := PartsA + ['0'];
  while Length(PartsB) < 3 do
    PartsB := PartsB + ['0'];
  Result := CompareParts(PartsA, PartsB, True);
  if Result <> 0 then
    Exit;
  if (PreA = '') and (PreB = '') then
    Exit(0);
  // Vorabversion vor der fertigen Version.
  if PreA = '' then
    Exit(1);
  if PreB = '' then
    Exit(-1);
  Result := CompareParts(PreA.Split(['.']), PreB.Split(['.']), False);
end;

class function TAtlasWhatsNew.Between(const AVersions: TAtlasWhatsNewVersions;
  const ASeen, ACurrent: string): TAtlasWhatsNewVersions;
var
  Version: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for Version in AVersions do
    if (CompareVersions(Version.Version, ASeen) > 0) and (CompareVersions(Version.Version, ACurrent) <= 0) then
      Result := Result + [Version];
end;

class function TAtlasWhatsNew.UpTo(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  Version: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for Version in AVersions do
    if CompareVersions(Version.Version, ACurrent) <= 0 then
      Result := Result + [Version];
end;

class function TAtlasWhatsNew.Latest(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  All: TAtlasWhatsNewVersions;
begin
  All := UpTo(AVersions, ACurrent);
  Result := nil;
  if Length(All) > 0 then
    Result := [All[0]];
end;

class function TAtlasWhatsNew.ModeOf(const AValue: string): TAtlasWhatsNewMode;
begin
  if SameText(Trim(AValue), ModeOff) then
    Result := TAtlasWhatsNewMode.Off
  else if SameText(Trim(AValue), ModeAlways) then
    Result := TAtlasWhatsNewMode.Always
  else
    Result := TAtlasWhatsNewMode.AfterUpdate;
end;

class function TAtlasWhatsNew.ModeName(AMode: TAtlasWhatsNewMode): string;
begin
  case AMode of
    TAtlasWhatsNewMode.Off:
      Result := ModeOff;
    TAtlasWhatsNewMode.Always:
      Result := ModeAlways;
  else
    Result := ModeAfterUpdate;
  end;
end;

class function TAtlasWhatsNew.ViewFor(AMode: TAtlasWhatsNewMode; const AVersions: TAtlasWhatsNewVersions;
  const ASeen, ACurrent: string): TAtlasWhatsNewView;
begin
  Result := TAtlasWhatsNewView.Hidden;
  if AMode = TAtlasWhatsNewMode.Off then
    Exit;
  if (ASeen <> '') and (Length(Between(AVersions, ASeen, ACurrent)) > 0) then
    Exit(TAtlasWhatsNewView.Unread);
  if (AMode = TAtlasWhatsNewMode.Always) and (Length(Latest(AVersions, ACurrent)) > 0) then
    Result := TAtlasWhatsNewView.Current;
end;

class function TAtlasWhatsNew.VersionsFor(AView: TAtlasWhatsNewView; const AVersions: TAtlasWhatsNewVersions;
  const ASeen, ACurrent: string): TAtlasWhatsNewVersions;
begin
  case AView of
    TAtlasWhatsNewView.Unread:
      Result := Between(AVersions, ASeen, ACurrent);
    TAtlasWhatsNewView.Current:
      Result := Latest(AVersions, ACurrent);
    TAtlasWhatsNewView.All:
      Result := UpTo(AVersions, ACurrent);
  else
    Result := nil;
  end;
end;

class function TAtlasWhatsNew.SeenAfterStart(const ASeen, ACurrent: string): string;
begin
  Result := ASeen;
  if Result = '' then
    Result := ACurrent;
end;

end.
