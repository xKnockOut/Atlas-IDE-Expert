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
// mit Zeile ab 1. Alles außer title ist freiwillig. titleEn und textEn
// (#1458) sind Titel und Text auf Englisch; mit englischer IDE zeigt die Karte
// sie, ohne sie den deutschen Text.
// Welche Versionen die Karte zeigt, regelt welcomePage.whatsNew: off nie,
// afterUpdate einmalig nach einem Versionswechsel (alle übersprungenen
// Versionen, nach Version gruppiert), always immer (dann ohne Ungelesenes die
// Neuerungen der aktuellen Version). "experimental": true kennzeichnet eine
// experimentelle Funktion (#834); die Karte zeigt solche Einträge nach den
// übrigen unter einer eigenen Überschrift. Die zuletzt gesehene Version steht in
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
    /// <summary>Titel und Text auf Englisch (#1458); '' = wie Title bzw. Text.</summary>
    TitleEn: string;
    TextEn: string;
    Setting: string;
    Key: string;
    Command: string;
    Sample: string;
    /// <summary>Zeile in Sample ab 1; 0 = Anfang.</summary>
    Line: Integer;
    /// <summary>Experimentelle Funktion (#834): eigener Abschnitt auf der Karte.</summary>
    Experimental: Boolean;
    /// <summary>Titel in der Sprache der Oberfläche (#1458): mit AEnglish TitleEn, falls vorhanden.</summary>
    function TitleFor(AEnglish: Boolean): string;
    /// <summary>Text in der Sprache der Oberfläche (#1458): mit AEnglish TextEn, falls vorhanden.</summary>
    function TextFor(AEnglish: Boolean): string;
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
    /// <summary>AItems an die Version AVersion anhängen (neu angelegt, wenn es sie noch nicht gibt; neueste
    /// zuerst). Einträge mit einem Titel, den die Version schon hat, fallen weg (#767: neue Bereiche).</summary>
    class function WithItems(const AVersions: TAtlasWhatsNewVersions; const AVersion: string;
      const AItems: TArray<TAtlasWhatsNewItem>): TAtlasWhatsNewVersions; static;
    /// <summary>AItems mit den übrigen Einträgen zuerst und den experimentellen danach, jeweils in der
    /// Reihenfolge der Datei (#834).</summary>
    class function Ordered(const AItems: TArray<TAtlasWhatsNewItem>): TArray<TAtlasWhatsNewItem>; static;
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
  begin
    Result := Trim(TJSONString(Value).Value);
  end;
end;

{ TAtlasWhatsNewItem }

function TAtlasWhatsNewItem.TitleFor(AEnglish: Boolean): string;
begin
  Result := Title;
  if AEnglish and (TitleEn <> '') then
  begin
    Result := TitleEn;
  end;
end;

function TAtlasWhatsNewItem.TextFor(AEnglish: Boolean): string;
begin
  Result := Text;
  if AEnglish and (TextEn <> '') then
  begin
    Result := TextEn;
  end;
end;

function Number(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end
  else if Value is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(Value).Value, 0);
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function Flag(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  Result := ((Value is TJSONBool) and TJSONBool(Value).AsBoolean) or ((Value is TJSONString) and SameText(Trim(TJSONString(Value).Value), 'true'));
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
    begin
      Exit;
    end;
    Versions := TJSONObject(Root).GetValue('versions');
    if not (Versions is TJSONArray) then
    begin
      Exit;
    end;
    for VersionValue in TJSONArray(Versions) do
    begin
      if not (VersionValue is TJSONObject) then
      begin
        Continue;
      end;
      Version := Default(TAtlasWhatsNewVersion);
      Version.Version := Text(TJSONObject(VersionValue), 'version');
      Items := TJSONObject(VersionValue).GetValue('items');
      if (Version.Version = '') or not (Items is TJSONArray) then
      begin
        Continue;
      end;
      for ItemValue in TJSONArray(Items) do
      begin
        if not (ItemValue is TJSONObject) then
        begin
          Continue;
        end;
        Item := Default(TAtlasWhatsNewItem);
        Item.Title := Text(TJSONObject(ItemValue), 'title');
        Item.Text := Text(TJSONObject(ItemValue), 'text');
        Item.TitleEn := Text(TJSONObject(ItemValue), 'titleEn');
        Item.TextEn := Text(TJSONObject(ItemValue), 'textEn');
        Item.Setting := Text(TJSONObject(ItemValue), 'setting');
        Item.Key := Text(TJSONObject(ItemValue), 'key');
        Item.Command := Text(TJSONObject(ItemValue), 'command');
        Item.Sample := Text(TJSONObject(ItemValue), 'sample');
        Item.Line := Number(TJSONObject(ItemValue), 'line');
        Item.Experimental := Flag(TJSONObject(ItemValue), 'experimental');
        if Item.Title <> '' then
        begin
          Version.Items := Version.Items + [Item];
        end;
      end;
      if Length(Version.Items) > 0 then
      begin
        List.Add(Version);
      end;
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
  begin
    Delete(Value, 1, 1);
  end;
  At := Pos('+', Value);
  if At > 0 then
  begin
    Value := Copy(Value, 1, At - 1);
  end;
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
  begin
    if not CharInSet(AText[Index], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

function CompareParts(const A, B: TArray<string>; ANumbersOnly: Boolean): Integer;
var
  Index: Integer;
  Left, Right: string;
begin
  for Index := 0 to Length(A) - 1 do
  begin
    if Index > High(B) then
    begin
      Exit(1);
    end;
    Left := A[Index];
    Right := B[Index];
    if ANumbersOnly or (IsNumber(Left) and IsNumber(Right)) then
    begin
      Result := StrToIntDef(Left, 0) - StrToIntDef(Right, 0);
    end
    else if IsNumber(Left) then
    begin
      // SemVer: Zahlen vor Text.
      Result := -1;
    end
    else if IsNumber(Right) then
    begin
      Result := 1;
    end
    else
    begin
      Result := CompareStr(Left, Right);
    end;
    if Result <> 0 then
    begin
      Exit;
    end;
  end;
  if Length(B) > Length(A) then
  begin
    Exit(-1);
  end;
  Result := 0;
end;

class function TAtlasWhatsNew.CompareVersions(const A, B: string): Integer;
var
  CoreA, PreA, CoreB, PreB: string;
  PartsA, PartsB: TArray<string>;
begin
  if Trim(A) = Trim(B) then
  begin
    Exit(0);
  end;
  if Trim(A) = '' then
  begin
    Exit(-1);
  end;
  if Trim(B) = '' then
  begin
    Exit(1);
  end;
  SplitVersion(A, CoreA, PreA);
  SplitVersion(B, CoreB, PreB);
  PartsA := CoreA.Split(['.']);
  PartsB := CoreB.Split(['.']);
  // "1.1" und "1.1.0" sind gleich.
  while Length(PartsA) < 3 do
  begin
    PartsA := PartsA + ['0'];
  end;
  while Length(PartsB) < 3 do
  begin
    PartsB := PartsB + ['0'];
  end;
  Result := CompareParts(PartsA, PartsB, True);
  if Result <> 0 then
  begin
    Exit;
  end;
  if (PreA = '') and (PreB = '') then
  begin
    Exit(0);
  end;
  // Vorabversion vor der fertigen Version.
  if PreA = '' then
  begin
    Exit(1);
  end;
  if PreB = '' then
  begin
    Exit(-1);
  end;
  Result := CompareParts(PreA.Split(['.']), PreB.Split(['.']), False);
end;

class function TAtlasWhatsNew.Between(const AVersions: TAtlasWhatsNewVersions;
  const ASeen, ACurrent: string): TAtlasWhatsNewVersions;
var
  Version: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for Version in AVersions do
  begin
    if (CompareVersions(Version.Version, ASeen) > 0) and (CompareVersions(Version.Version, ACurrent) <= 0) then
    begin
      Result := Result + [Version];
    end;
  end;
end;

class function TAtlasWhatsNew.UpTo(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  Version: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for Version in AVersions do
  begin
    if CompareVersions(Version.Version, ACurrent) <= 0 then
    begin
      Result := Result + [Version];
    end;
  end;
end;

class function TAtlasWhatsNew.Latest(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  All: TAtlasWhatsNewVersions;
begin
  All := UpTo(AVersions, ACurrent);
  Result := nil;
  if Length(All) > 0 then
  begin
    Result := [All[0]];
  end;
end;

class function TAtlasWhatsNew.WithItems(const AVersions: TAtlasWhatsNewVersions; const AVersion: string;
  const AItems: TArray<TAtlasWhatsNewItem>): TAtlasWhatsNewVersions;
var
  Index, Target: Integer;
  Item, Known: TAtlasWhatsNewItem;
  Found: Boolean;
  Added: TAtlasWhatsNewVersion;
begin
  Result := Copy(AVersions);
  if (AVersion = '') or (Length(AItems) = 0) then
  begin
    Exit;
  end;
  Target := -1;
  for Index := 0 to High(Result) do
  begin
    if CompareVersions(Result[Index].Version, AVersion) = 0 then
    begin
      Target := Index;
    end;
  end;
  if Target < 0 then
  begin
    Added.Version := AVersion;
    Added.Items := nil;
    // Neueste zuerst: vor die erste ältere Version.
    Target := Length(Result);
    for Index := High(Result) downto 0 do
    begin
      if CompareVersions(Result[Index].Version, AVersion) < 0 then
      begin
        Target := Index;
      end;
    end;
    Insert(Added, Result, Target);
  end;
  Result[Target].Items := Copy(Result[Target].Items);
  for Item in AItems do
  begin
    if Item.Title = '' then
    begin
      Continue;
    end;
    Found := False;
    for Known in Result[Target].Items do
    begin
      Found := Found or SameText(Known.Title, Item.Title);
    end;
    if not Found then
    begin
      Result[Target].Items := Result[Target].Items + [Item];
    end;
  end;
  // Eine neu angelegte Version ohne Einträge gäbe es in Parse nicht.
  if Length(Result[Target].Items) = 0 then
  begin
    Delete(Result, Target, 1);
  end;
end;

class function TAtlasWhatsNew.Ordered(const AItems: TArray<TAtlasWhatsNewItem>): TArray<TAtlasWhatsNewItem>;
var
  Item: TAtlasWhatsNewItem;
  Later: TArray<TAtlasWhatsNewItem>;
begin
  Result := nil;
  Later := nil;
  for Item in AItems do
  begin
    if Item.Experimental then
    begin
      Later := Later + [Item];
    end
    else
    begin
      Result := Result + [Item];
    end;
  end;
  Result := Result + Later;
end;

class function TAtlasWhatsNew.ModeOf(const AValue: string): TAtlasWhatsNewMode;
begin
  if SameText(Trim(AValue), ModeOff) then
  begin
    Result := TAtlasWhatsNewMode.Off;
  end
  else if SameText(Trim(AValue), ModeAlways) then
  begin
    Result := TAtlasWhatsNewMode.Always;
  end
  else
  begin
    Result := TAtlasWhatsNewMode.AfterUpdate;
  end;
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
  begin
    Exit;
  end;
  if (ASeen <> '') and (Length(Between(AVersions, ASeen, ACurrent)) > 0) then
  begin
    Exit(TAtlasWhatsNewView.Unread);
  end;
  if (AMode = TAtlasWhatsNewMode.Always) and (Length(Latest(AVersions, ACurrent)) > 0) then
  begin
    Result := TAtlasWhatsNewView.Current;
  end;
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
  begin
    Result := ACurrent;
  end;
end;

end.
