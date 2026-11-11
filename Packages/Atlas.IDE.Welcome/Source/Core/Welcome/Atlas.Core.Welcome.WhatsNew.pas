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
    cFileName = 'whatsnew.json';
    cModeOff = 'off';
    cModeAfterUpdate = 'afterUpdate';
    cModeAlways = 'always';
  public
    /// <summary>Versionen aus whatsnew.json, neueste zuerst, ohne Versionen ohne Einträge; leer bei ungültigem
    /// Inhalt. Einträge ohne Titel fallen weg.</summary>
    class function Parse(const AJson: string): TAtlasWhatsNewVersions; static;
    /// <summary>Vergleich nach SemVer: Zahlen numerisch, Vorabversion („1.1.0-beta.2“) vor der Version;
    /// '' gilt als kleiner als alles.</summary>
    class function CompareVersions(const A, B: string): Integer; static;
    /// <summary>Versionen mit ASeen &lt; Version &lt;= ACurrent, neueste zuerst.</summary>
    class function Between(const AVersions: TAtlasWhatsNewVersions; const ASeen,
      ACurrent: string): TAtlasWhatsNewVersions; static;
    /// <summary>Neueste Version &lt;= ACurrent mit Einträgen (für „Neuigkeiten dieser Version“); leer ohne.</summary>
    class function Latest(const AVersions: TAtlasWhatsNewVersions; const ACurrent: string): TAtlasWhatsNewVersions;
      static;
    /// <summary>Alle Versionen &lt;= ACurrent, neueste zuerst.</summary>
    class function UpTo(const AVersions: TAtlasWhatsNewVersions; const ACurrent: string): TAtlasWhatsNewVersions;
      static;
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
  System.Generics.Defaults,
  System.Math,
  Atlas.Text.Json;

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

function Flag(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  Result := ((mValue is TJSONBool) and TJSONBool(mValue).AsBoolean) or
    ((mValue is TJSONString) and SameText(Trim(TJSONString(mValue).Value), 'true'));
end;

/// <summary>Eintrag aus AObject; Title '' bei einem unbrauchbaren Eintrag.</summary>
function ItemFrom(AObject: TJSONObject): TAtlasWhatsNewItem;
begin
  Result := Default(TAtlasWhatsNewItem);
  Result.Title := TJsonRead.TrimmedText(AObject, 'title');
  Result.Text := TJsonRead.TrimmedText(AObject, 'text');
  Result.TitleEn := TJsonRead.TrimmedText(AObject, 'titleEn');
  Result.TextEn := TJsonRead.TrimmedText(AObject, 'textEn');
  Result.Setting := TJsonRead.TrimmedText(AObject, 'setting');
  Result.Key := TJsonRead.TrimmedText(AObject, 'key');
  Result.Command := TJsonRead.TrimmedText(AObject, 'command');
  Result.Sample := TJsonRead.TrimmedText(AObject, 'sample');
  Result.Line := Max(0, TJsonRead.Int(AObject, 'line'));
  Result.Experimental := Flag(AObject, 'experimental');
end;

/// <summary>Version aus AValue mit ihren Einträgen (nur solche mit Titel); False ohne Version oder Einträge.
/// </summary>
function TryVersionFrom(AValue: TJSONValue; out AVersion: TAtlasWhatsNewVersion): Boolean;
var
  mItems, mItemValue: TJSONValue;
  mItem: TAtlasWhatsNewItem;
begin
  AVersion := Default(TAtlasWhatsNewVersion);
  Result := False;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  AVersion.Version := TJsonRead.TrimmedText(TJSONObject(AValue), 'version');
  mItems := TJSONObject(AValue).GetValue('items');
  if (AVersion.Version = '') or not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItemValue in TJSONArray(mItems) do
  begin
    if mItemValue is TJSONObject then
    begin
      mItem := ItemFrom(TJSONObject(mItemValue));
      if mItem.Title <> '' then
      begin
        AVersion.Items := AVersion.Items + [mItem];
      end;
    end;
  end;
  Result := Length(AVersion.Items) > 0;
end;

class function TAtlasWhatsNew.Parse(const AJson: string): TAtlasWhatsNewVersions;
var
  mRoot, mVersions: TJSONValue;
  mVersionValue: TJSONValue;
  mVersion: TAtlasWhatsNewVersion;
  mList: TList<TAtlasWhatsNewVersion>;
begin
  Result := nil;
  try
    mRoot := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: keine Karte, kein Fehler in der IDE.
    on Exception do
      mRoot := nil;
  end;
  mList := TList<TAtlasWhatsNewVersion>.Create;
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mVersions := TJSONObject(mRoot).GetValue('versions');
    if not (mVersions is TJSONArray) then
    begin
      Exit;
    end;
    for mVersionValue in TJSONArray(mVersions) do
    begin
      if TryVersionFrom(mVersionValue, mVersion) then
      begin
        mList.Add(mVersion);
      end;
    end;
    mList.Sort(TComparer<TAtlasWhatsNewVersion>.Construct(
      function(const A, B: TAtlasWhatsNewVersion): Integer
      begin
        Result := CompareVersions(B.Version, A.Version);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
    mRoot.Free;
  end;
end;

/// <summary>Teile einer Version: Kern "1.2.3" und Vorabversion "beta.2" ('' ohne); "v" davor und "+Build"
/// dahinter fallen weg.</summary>
procedure SplitVersion(const AVersion: string; out ACore, APre: string);
var
  mValue: string;
  mAt: Integer;
begin
  mValue := Trim(AVersion);
  if (mValue <> '') and CharInSet(mValue[1], ['v', 'V']) then
  begin
    Delete(mValue, 1, 1);
  end;
  mAt := Pos('+', mValue);
  if mAt > 0 then
  begin
    mValue := Copy(mValue, 1, mAt - 1);
  end;
  mAt := Pos('-', mValue);
  if mAt > 0 then
  begin
    ACore := Copy(mValue, 1, mAt - 1);
    APre := Copy(mValue, mAt + 1, MaxInt);
  end
  else
  begin
    ACore := mValue;
    APre := '';
  end;
end;

function IsNumber(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

function CompareParts(const A, B: TArray<string>; ANumbersOnly: Boolean): Integer;
var
  mIndex: Integer;
  mLeft, mRight: string;
begin
  for mIndex := 0 to Length(A) - 1 do
  begin
    if mIndex > High(B) then
    begin
      Exit(1);
    end;
    mLeft := A[mIndex];
    mRight := B[mIndex];
    if ANumbersOnly or (IsNumber(mLeft) and IsNumber(mRight)) then
    begin
      Result := StrToIntDef(mLeft, 0) - StrToIntDef(mRight, 0);
    end
    else if IsNumber(mLeft) then
    begin
      // SemVer: Zahlen vor Text.
      Result := -1;
    end
    else if IsNumber(mRight) then
    begin
      Result := 1;
    end
    else
    begin
      Result := CompareStr(mLeft, mRight);
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

/// <summary>AParts auf drei Teile aufgefüllt: "1.1" und "1.1.0" sind gleich.</summary>
function Padded(const AParts: TArray<string>): TArray<string>;
begin
  Result := AParts;
  while Length(Result) < 3 do
  begin
    Result := Result + ['0'];
  end;
end;

/// <summary>Vorabversionen vergleichen; eine Vorabversion steht vor der fertigen Version ('').</summary>
function ComparePre(const APreA, APreB: string): Integer;
begin
  if (APreA = '') and (APreB = '') then
  begin
    Result := 0;
  end
  else if APreA = '' then
  begin
    Result := 1;
  end
  else if APreB = '' then
  begin
    Result := -1;
  end
  else
  begin
    Result := CompareParts(APreA.Split(['.']), APreB.Split(['.']), False);
  end;
end;

class function TAtlasWhatsNew.CompareVersions(const A, B: string): Integer;
var
  mCoreA, mPreA, mCoreB, mPreB: string;
begin
  if Trim(A) = Trim(B) then
  begin
    Exit(0);
  end;
  // Ohne Version steht vor jeder Version.
  if (Trim(A) = '') or (Trim(B) = '') then
  begin
    Exit(Ord(Trim(A) <> '') - Ord(Trim(B) <> ''));
  end;
  SplitVersion(A, mCoreA, mPreA);
  SplitVersion(B, mCoreB, mPreB);
  Result := CompareParts(Padded(mCoreA.Split(['.'])), Padded(mCoreB.Split(['.'])), True);
  if Result = 0 then
  begin
    Result := ComparePre(mPreA, mPreB);
  end;
end;

class function TAtlasWhatsNew.Between(const AVersions: TAtlasWhatsNewVersions;
  const ASeen, ACurrent: string): TAtlasWhatsNewVersions;
var
  mVersion: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for mVersion in AVersions do
  begin
    if (CompareVersions(mVersion.Version, ASeen) > 0) and (CompareVersions(mVersion.Version, ACurrent) <= 0) then
    begin
      Result := Result + [mVersion];
    end;
  end;
end;

class function TAtlasWhatsNew.UpTo(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  mVersion: TAtlasWhatsNewVersion;
begin
  Result := nil;
  for mVersion in AVersions do
  begin
    if CompareVersions(mVersion.Version, ACurrent) <= 0 then
    begin
      Result := Result + [mVersion];
    end;
  end;
end;

class function TAtlasWhatsNew.Latest(const AVersions: TAtlasWhatsNewVersions;
  const ACurrent: string): TAtlasWhatsNewVersions;
var
  mAll: TAtlasWhatsNewVersions;
begin
  mAll := UpTo(AVersions, ACurrent);
  Result := nil;
  if Length(mAll) > 0 then
  begin
    Result := [mAll[0]];
  end;
end;

/// <summary>Index der Version AVersion in AVersions; fehlt sie, kommt sie leer vor die erste ältere Version
/// (neueste zuerst).</summary>
function VersionSlot(var AVersions: TAtlasWhatsNewVersions; const AVersion: string): Integer;
var
  mIndex: Integer;
  mAdded: TAtlasWhatsNewVersion;
begin
  Result := -1;
  for mIndex := 0 to High(AVersions) do
  begin
    if TAtlasWhatsNew.CompareVersions(AVersions[mIndex].Version, AVersion) = 0 then
    begin
      Result := mIndex;
    end;
  end;
  if Result >= 0 then
  begin
    Exit;
  end;
  mAdded := Default(TAtlasWhatsNewVersion);
  mAdded.Version := AVersion;
  Result := Length(AVersions);
  for mIndex := High(AVersions) downto 0 do
  begin
    if TAtlasWhatsNew.CompareVersions(AVersions[mIndex].Version, AVersion) < 0 then
    begin
      Result := mIndex;
    end;
  end;
  Insert(mAdded, AVersions, Result);
end;

/// <summary>Steht ein Eintrag mit ATitle (ohne Groß-/Kleinschreibung) in AItems?</summary>
function HasTitle(const AItems: TArray<TAtlasWhatsNewItem>; const ATitle: string): Boolean;
var
  mKnown: TAtlasWhatsNewItem;
begin
  Result := False;
  for mKnown in AItems do
  begin
    Result := Result or SameText(mKnown.Title, ATitle);
  end;
end;

class function TAtlasWhatsNew.WithItems(const AVersions: TAtlasWhatsNewVersions; const AVersion: string;
  const AItems: TArray<TAtlasWhatsNewItem>): TAtlasWhatsNewVersions;
var
  mTarget: Integer;
  mItem: TAtlasWhatsNewItem;
begin
  Result := Copy(AVersions);
  if (AVersion = '') or (Length(AItems) = 0) then
  begin
    Exit;
  end;
  mTarget := VersionSlot(Result, AVersion);
  Result[mTarget].Items := Copy(Result[mTarget].Items);
  for mItem in AItems do
  begin
    if (mItem.Title <> '') and not HasTitle(Result[mTarget].Items, mItem.Title) then
    begin
      Result[mTarget].Items := Result[mTarget].Items + [mItem];
    end;
  end;
  // Eine neu angelegte Version ohne Einträge gäbe es in Parse nicht.
  if Length(Result[mTarget].Items) = 0 then
  begin
    Delete(Result, mTarget, 1);
  end;
end;

class function TAtlasWhatsNew.Ordered(const AItems: TArray<TAtlasWhatsNewItem>): TArray<TAtlasWhatsNewItem>;
var
  mItem: TAtlasWhatsNewItem;
  mLater: TArray<TAtlasWhatsNewItem>;
begin
  Result := nil;
  mLater := nil;
  for mItem in AItems do
  begin
    if mItem.Experimental then
    begin
      mLater := mLater + [mItem];
    end
    else
    begin
      Result := Result + [mItem];
    end;
  end;
  Result := Result + mLater;
end;

class function TAtlasWhatsNew.ModeOf(const AValue: string): TAtlasWhatsNewMode;
begin
  if SameText(Trim(AValue), cModeOff) then
  begin
    Result := TAtlasWhatsNewMode.Off;
  end
  else if SameText(Trim(AValue), cModeAlways) then
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
      Result := cModeOff;
    TAtlasWhatsNewMode.Always:
      Result := cModeAlways;
  else
    Result := cModeAfterUpdate;
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
