unit Atlas.Text.Updates;

// Versionen und Versionsdatei der Update-Prüfung (#495, #1519), gemeinsam für
// das Plugin (Prüfung, Anzeige) und AtlasUpdate.exe (Laden, Installieren):
// - Versionen nach SemVer 2.0: Vorabversionen vor der Version, Build-Angabe
//   ohne Bedeutung.
// - atlas-version.json des Release-Workflows:
//     {"version": "2.0.1", "changes": "https://…",
//      "packages": {"37.0": {"url": "https://…/atlas-ide-expert-2.0.1.zip", "sha256": "…"}},
//      "source": {"url": "https://…/atlas-ide-expert-2.0.1-src.zip", "sha256": "…"}}
//   "packages" nennt je CompilerVersion der IDE ein Release-Paket mit BPLs,
//   Server und Daten; "source" den Quelltext zum Bauen, wenn für die eigene
//   IDE kein Paket da ist (#1519). Ältere Plugins lesen nur version und
//   changes. Nur https-Adressen und SHA-256 aus 64 Hexziffern gelten.
// - Namen der Packages: Datei „Atlas.IDE.Debugger370.bpl“ heißt
//   „Atlas.IDE.Debugger“; Kern und Verträge sind Pflicht.

interface

uses
  System.SysUtils;

type
  /// <summary>Eine Datei zum Herunterladen mit ihrer Prüfsumme.</summary>
  TUpdateFile = record
    Url: string;
    /// <summary>SHA-256 als 64 Hexziffern, klein geschrieben.</summary>
    Sha256: string;
    function IsValid: Boolean;
  end;

  /// <summary>Release-Paket für eine IDE-Version (CompilerVersion wie „37.0“).</summary>
  TUpdateIdePackage = record
    Ide: string;
    Archive: TUpdateFile;
  end;

  TUpdateManifest = record
    Version: string;
    ChangesUrl: string;
    Packages: TArray<TUpdateIdePackage>;
    /// <summary>Quelltext zum Bauen; Url leer, wenn das Release keinen nennt.</summary>
    Source: TUpdateFile;
    /// <summary>Paket für AIde (z. B. „37.0“); False, wenn es keins gibt.</summary>
    function PackageFor(const AIde: string; out AFile: TUpdateFile): Boolean;
    /// <summary>Irgendein Paket (das erste): Server und Daten hängen nicht von der IDE ab.</summary>
    function AnyPackage(out AFile: TUpdateFile): Boolean;
  end;

  TUpdateVersions = class
  public const
    /// <summary>Kern und Verträge (ADR 0017): immer installiert, nie abwählbar.</summary>
    BasePackage = 'Atlas.IDE.Base';
    ContractsPackage = 'Atlas.IDE.Contracts';
    PackagePrefix = 'Atlas.IDE.';
  public
    class function IsValidVersion(const AVersion: string): Boolean; static;
    /// <summary>&lt; 0, 0 oder &gt; 0 wie CompareStr; ungültige Versionen sind kleiner als gültige.</summary>
    class function Compare(const A, B: string): Integer; static;
    /// <summary>Erste Zahl der Version; -1, wenn sie ungültig ist.</summary>
    class function Major(const AVersion: string): Integer; static;
    /// <summary>https-Adresse ohne Leer- und Steuerzeichen.</summary>
    class function IsSafeUrl(const AUrl: string): Boolean; static;
    class function IsSha256(const AText: string): Boolean; static;
    /// <summary>Name eines Packages aus Dateiname oder Pfad: ohne Ordner, Endung und Versionsendung
    /// (LIBSUFFIX AUTO, z. B. 370).</summary>
    class function PackageName(const AFileName: string): string; static;
    class function IsRequiredPackage(const AName: string): Boolean; static;
  end;

  /// <summary>Versionsdateien je Kanal (updates.channel). „latest“ von GitHub übergeht Vorabversionen; der Kanal
  /// für Vorabversionen ist deshalb ein fester Release „update-channel“, dessen Datei jeder Release ersetzt.
  /// </summary>
  TUpdateChannels = class
  public const
    ReleasesUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/releases';
    StableUrl = ReleasesUrl + '/latest/download/atlas-version.json';
    PrereleaseUrl = ReleasesUrl + '/download/update-channel/atlas-version-beta.json';
  public
    class function UrlOf(APrerelease: Boolean): string; static;
  end;

  TUpdateManifests = class
  public
    /// <summary>False, wenn AJson keine Versionsdatei mit gültiger Version ist. Ungültige Pakete und Quellen
    /// werden übergangen; ohne https-Adresse der Änderungen gilt die Release-Seite (AReleasesUrl/tag/v…).</summary>
    class function TryParse(const AJson, AReleasesUrl: string; out AManifest: TUpdateManifest): Boolean; static;
    class function ToJson(const AManifest: TUpdateManifest): string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Text.Json;

const
  cIdentifier = '(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)';
  cSemVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)' +
    '(-' + cIdentifier + '(?:\.' + cIdentifier + ')*)?' +
    '(\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$';

{ TUpdateFile }

function TUpdateFile.IsValid: Boolean;
begin
  Result := TUpdateVersions.IsSafeUrl(Url) and TUpdateVersions.IsSha256(Sha256);
end;

{ TUpdateManifest }

function TUpdateManifest.PackageFor(const AIde: string; out AFile: TUpdateFile): Boolean;
var
  mPackage: TUpdateIdePackage;
begin
  AFile := Default(TUpdateFile);
  for mPackage in Packages do
  begin
    if mPackage.Ide = AIde then
    begin
      AFile := mPackage.Archive;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TUpdateManifest.AnyPackage(out AFile: TUpdateFile): Boolean;
begin
  AFile := Default(TUpdateFile);
  Result := Length(Packages) > 0;
  if Result then
  begin
    AFile := Packages[0].Archive;
  end;
end;

{ TUpdateVersions }

function IsNumber(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
end;

function CompareNumbers(const A, B: string): Integer;
begin
  // Ohne führende Nullen (SemVer): länger ist größer, sonst Zeichen für Zeichen.
  Result := Sign(Length(A) - Length(B));
  if Result = 0 then
  begin
    Result := Sign(CompareStr(A, B));
  end;
end;

function CompareIdentifier(const A, B: string): Integer;
begin
  if IsNumber(A) and IsNumber(B) then
  begin
    Result := CompareNumbers(A, B);
  end
  else if IsNumber(A) then
  begin
    Result := -1;
  end
  else if IsNumber(B) then
  begin
    Result := 1;
  end
  else
  begin
    Result := Sign(CompareStr(A, B));
  end;
end;

function ComparePrerelease(const A, B: string): Integer;
var
  mPartsA, mPartsB: TArray<string>;
  mIndex: Integer;
begin
  // Ohne Vorabversion ist eine Version größer als mit.
  if (A = '') or (B = '') then
  begin
    Exit(Ord(A = '') - Ord(B = ''));
  end;
  mPartsA := A.Split(['.']);
  mPartsB := B.Split(['.']);
  for mIndex := 0 to Min(Length(mPartsA), Length(mPartsB)) - 1 do
  begin
    Result := CompareIdentifier(mPartsA[mIndex], mPartsB[mIndex]);
    if Result <> 0 then
    begin
      Exit;
    end;
  end;
  Result := Sign(Length(mPartsA) - Length(mPartsB));
end;

/// <summary>Kern (drei Zahlen) und Vorabversion ohne „-“; False, wenn AVersion keine SemVer-Version ist.</summary>
function SplitVersion(const AVersion: string; out ACore: TArray<string>; out APrerelease: string): Boolean;
var
  mRest: string;
  mPosition: Integer;
begin
  ACore := nil;
  APrerelease := '';
  Result := TRegEx.IsMatch(AVersion, cSemVerPattern);
  if not Result then
  begin
    Exit;
  end;
  mRest := AVersion;
  mPosition := Pos('+', mRest);
  if mPosition > 0 then
  begin
    mRest := Copy(mRest, 1, mPosition - 1);
  end;
  mPosition := Pos('-', mRest);
  if mPosition > 0 then
  begin
    APrerelease := Copy(mRest, mPosition + 1, MaxInt);
    mRest := Copy(mRest, 1, mPosition - 1);
  end;
  ACore := mRest.Split(['.']);
end;

class function TUpdateVersions.IsValidVersion(const AVersion: string): Boolean;
begin
  Result := TRegEx.IsMatch(AVersion, cSemVerPattern);
end;

class function TUpdateVersions.Compare(const A, B: string): Integer;
var
  mCoreA, mCoreB: TArray<string>;
  mPreA, mPreB: string;
  mValidA, mValidB: Boolean;
  mIndex: Integer;
begin
  mValidA := SplitVersion(A, mCoreA, mPreA);
  mValidB := SplitVersion(B, mCoreB, mPreB);
  if not mValidA or not mValidB then
  begin
    Exit(Ord(mValidA) - Ord(mValidB));
  end;
  for mIndex := 0 to 2 do
  begin
    Result := CompareNumbers(mCoreA[mIndex], mCoreB[mIndex]);
    if Result <> 0 then
    begin
      Exit;
    end;
  end;
  Result := ComparePrerelease(mPreA, mPreB);
end;

class function TUpdateVersions.Major(const AVersion: string): Integer;
var
  mCore: TArray<string>;
  mPrerelease: string;
begin
  Result := -1;
  if SplitVersion(AVersion, mCore, mPrerelease) then
  begin
    Result := StrToIntDef(mCore[0], -1);
  end;
end;

class function TUpdateVersions.IsSafeUrl(const AUrl: string): Boolean;
var
  mChar: Char;
begin
  Result := AUrl.StartsWith('https://', True) and (Length(AUrl) > Length('https://'));
  for mChar in AUrl do
  begin
    if Ord(mChar) <= 32 then
    begin
      Exit(False);
    end;
  end;
end;

class function TUpdateVersions.IsSha256(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := Length(AText) = 64;
  for mChar in AText do
  begin
    if not CharInSet(mChar, ['0'..'9', 'a'..'f', 'A'..'F']) then
    begin
      Exit(False);
    end;
  end;
end;

class function TUpdateVersions.PackageName(const AFileName: string): string;
var
  mEnd: Integer;
begin
  Result := AFileName.Substring(AFileName.LastDelimiter('\/') + 1);
  if Result.EndsWith('.bpl', True) then
  begin
    Result := Result.Substring(0, Length(Result) - 4);
  end;
  mEnd := Length(Result);
  while (mEnd > 0) and CharInSet(Result[mEnd], ['0'..'9']) do
  begin
    Dec(mEnd);
  end;
  Result := Copy(Result, 1, mEnd);
end;

class function TUpdateVersions.IsRequiredPackage(const AName: string): Boolean;
begin
  Result := SameText(AName, BasePackage) or SameText(AName, ContractsPackage);
end;

{ TUpdateChannels }

class function TUpdateChannels.UrlOf(APrerelease: Boolean): string;
begin
  if APrerelease then
  begin
    Result := PrereleaseUrl;
  end
  else
  begin
    Result := StableUrl;
  end;
end;

{ TUpdateManifests }

function ReadFile(const AObject: TJSONObject; const AName: string; out AFile: TUpdateFile): Boolean;
var
  mNode: TJSONValue;
  mUrl, mSha: string;
begin
  AFile := Default(TUpdateFile);
  mNode := AObject.GetValue(AName);
  Result := mNode is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  if not TJSONObject(mNode).TryGetValue<string>('url', mUrl) then
  begin
    mUrl := '';
  end;
  if not TJSONObject(mNode).TryGetValue<string>('sha256', mSha) then
  begin
    mSha := '';
  end;
  AFile.Url := mUrl;
  AFile.Sha256 := LowerCase(mSha);
  Result := AFile.IsValid;
end;

function ReadPackages(const ARoot: TJSONObject): TArray<TUpdateIdePackage>;
var
  mNode: TJSONValue;
  mPair: TJSONPair;
  mList: TList<TUpdateIdePackage>;
  mPackage: TUpdateIdePackage;
begin
  Result := nil;
  mNode := ARoot.GetValue('packages');
  if not (mNode is TJSONObject) then
  begin
    Exit;
  end;
  mList := TList<TUpdateIdePackage>.Create;
  try
    for mPair in TJSONObject(mNode) do
    begin
      mPackage := Default(TUpdateIdePackage);
      mPackage.Ide := mPair.JsonString.Value;
      if (mPair.JsonValue is TJSONObject) and ReadFile(TJSONObject(mNode), mPackage.Ide, mPackage.Archive) then
      begin
        mList.Add(mPackage);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function ParseRoot(const ARoot: TJSONObject; const AReleasesUrl: string; out AManifest: TUpdateManifest): Boolean;
var
  mVersion, mChanges: string;
  mSource: TUpdateFile;
begin
  AManifest := Default(TUpdateManifest);
  Result := ARoot.TryGetValue<string>('version', mVersion) and TUpdateVersions.IsValidVersion(mVersion);
  if not Result then
  begin
    Exit;
  end;
  AManifest.Version := mVersion;
  if not ARoot.TryGetValue<string>('changes', mChanges) or not TUpdateVersions.IsSafeUrl(mChanges) then
  begin
    mChanges := AReleasesUrl + '/tag/v' + mVersion;
  end;
  AManifest.ChangesUrl := mChanges;
  AManifest.Packages := ReadPackages(ARoot);
  if ReadFile(ARoot, 'source', mSource) then
  begin
    AManifest.Source := mSource;
  end;
end;

class function TUpdateManifests.TryParse(const AJson, AReleasesUrl: string; out AManifest: TUpdateManifest): Boolean;
var
  mValue: TJSONValue;
begin
  AManifest := Default(TUpdateManifest);
  Result := False;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on EJSONException do
    begin
      Exit;
    end;
  end;
  try
    if mValue is TJSONObject then
    begin
      Result := ParseRoot(TJSONObject(mValue), AReleasesUrl, AManifest);
    end;
  finally
    mValue.Free;
  end;
end;

function FileJson(const AFile: TUpdateFile): string;
begin
  Result := '{"url": ' + TJsonText.Quote(AFile.Url) + ', "sha256": ' + TJsonText.Quote(AFile.Sha256) + '}';
end;

class function TUpdateManifests.ToJson(const AManifest: TUpdateManifest): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"version": ').Append(TJsonText.Quote(AManifest.Version));
    mBuilder.Append(', "changes": ').Append(TJsonText.Quote(AManifest.ChangesUrl));
    mBuilder.Append(', "packages": {');
    for mIndex := 0 to High(AManifest.Packages) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append(TJsonText.Quote(AManifest.Packages[mIndex].Ide)).Append(': ');
      mBuilder.Append(FileJson(AManifest.Packages[mIndex].Archive));
    end;
    mBuilder.Append('}');
    if AManifest.Source.Url <> '' then
    begin
      mBuilder.Append(', "source": ').Append(FileJson(AManifest.Source));
    end;
    mBuilder.Append('}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
