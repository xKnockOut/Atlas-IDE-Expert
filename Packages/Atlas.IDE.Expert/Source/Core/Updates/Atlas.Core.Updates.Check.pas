unit Atlas.Core.Updates.Check;

// Prüfung auf neue Versionen (#495), ohne Netzwerk und ohne IDE:
// - Nur mit updates.check (Vorgabe aus, Zustimmung beim ersten Start) und
//   höchstens einmal täglich; auch eine gescheiterte Abfrage zählt.
// - Abgefragt wird die Versionsdatei des Release-Prozesses
//   (atlas-version.json: {"version": "1.2.0", "changes": "https://…"});
//   übertragen werden nur Atlas-Version und IDE-Version als Parameter der
//   Adresse, keine Projektdaten.
// - Versionen nach SemVer 2.0 (Vorabversionen vor der Version, Build-Angabe
//   ohne Bedeutung). Neuer ist eine Version nur, wenn sie größer ist als die
//   installierte.
// - Der Zustand (gefragt, letzte Prüfung) liegt in einer eigenen Datei, nicht
//   in den Einstellungen, damit die tägliche Prüfung keine Einstellungsstände
//   (#722) erzeugt.
// Heruntergeladen oder installiert wird nie etwas.

interface

uses
  System.SysUtils,
  Atlas.Core.Updates.Contract;

type
  TAtlasRelease = record
    Version: string;
    /// <summary>https-Adresse der Änderungen dieser Version.</summary>
    ChangesUrl: string;
  end;

  TAtlasUpdateState = record
    /// <summary>Beim ersten Start gefragt (Ja oder Nein).</summary>
    Asked: Boolean;
    /// <summary>Letzte Abfrage (Ortszeit); 0 = nie.</summary>
    LastCheck: TDateTime;
    function ToJson: string;
    class function FromJson(const AJson: string): TAtlasUpdateState; static;
  end;

{$SCOPEDENUMS ON}
  TAtlasUpdateOutcome = (Disabled, NotDue, Failed, Current, NewVersion);
{$SCOPEDENUMS OFF}

  TAtlasUpdateResult = record
    Outcome: TAtlasUpdateOutcome;
    Release: TAtlasRelease;
    /// <summary>Bei Failed: warum, ohne Adresse.</summary>
    Error: string;
  end;

  TAtlasUpdates = class
  public const
    VersionUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/releases/latest/download/atlas-version.json';
    ReleasesUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/releases';
    TimeoutMs = 10000;
  public
    /// <summary>SemVer-Vergleich: negativ, 0 oder positiv; ungültige Versionen sind kleiner als gültige.</summary>
    class function Compare(const A, B: string): Integer; static;
    class function IsValidVersion(const AVersion: string): Boolean; static;
    /// <summary>Versionsdatei lesen; False ohne gültige Version. Fehlt "changes" oder ist es keine
    /// https-Adresse, gilt die Release-Seite der Version.</summary>
    class function TryParse(const AJson: string; out ARelease: TAtlasRelease): Boolean; static;
    /// <summary>Fällig, wenn noch nie, seit mindestens einem Tag nicht geprüft oder die Uhr
    /// zurückgestellt wurde.</summary>
    class function IsDue(ALastCheck, ANow: TDateTime): Boolean; static;
    /// <summary>Adresse mit genau zwei Parametern: atlas und ide.</summary>
    class function RequestUrl(const ABase, AAtlasVersion, AIdeVersion: string): string; static;
    /// <summary>Eine Prüfung; setzt AState.LastCheck, wenn abgefragt wurde.</summary>
    class function Run(const ASource: IAtlasVersionSource; var AState: TAtlasUpdateState; AEnabled: Boolean;
      const AInstalled, AIdeVersion: string; ANow: TDateTime): TAtlasUpdateResult; static;
    /// <summary>%LOCALAPPDATA%\Atlas\updates.json.</summary>
    class function StateFile: string; static;
    /// <summary>Compiler-Version der IDE, für die das Plugin gebaut ist, z. B. „37.0“ (Delphi 13).</summary>
    class function IdeVersion: string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.DateUtils,
  System.NetEncoding,
  System.RegularExpressions,
  System.IOUtils;

const
  Identifier = '(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)';
  SemVerPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)' +
    '(-' + Identifier + '(?:\.' + Identifier + ')*)?' +
    '(\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$';

{ TAtlasUpdateState }

function TAtlasUpdateState.ToJson: string;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('asked', TJSONBool.Create(Asked));
    if LastCheck > 0 then
      Root.AddPair('lastCheck', TJSONString.Create(DateToISO8601(LastCheck, False)));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAtlasUpdateState.FromJson(const AJson: string): TAtlasUpdateState;
var
  Value: TJSONValue;
  Text: string;
begin
  Result := Default(TAtlasUpdateState);
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    TJSONObject(Value).TryGetValue<Boolean>('asked', Result.Asked);
    if TJSONObject(Value).TryGetValue<string>('lastCheck', Text) and
      not TryISO8601ToDate(Text, Result.LastCheck, False) then
      Result.LastCheck := 0;
  finally
    Value.Free;
  end;
end;

{ TAtlasUpdates }

class function TAtlasUpdates.IsValidVersion(const AVersion: string): Boolean;
begin
  Result := TRegEx.IsMatch(AVersion, SemVerPattern);
end;

function IsNumber(const AText: string): Boolean;
var
  C: Char;
begin
  Result := AText <> '';
  for C in AText do
    if not CharInSet(C, ['0'..'9']) then
      Exit(False);
end;

function CompareNumbers(const A, B: string): Integer;
begin
  // Ohne führende Nullen (SemVer): länger ist größer, sonst Zeichen für Zeichen.
  Result := Sign(Length(A) - Length(B));
  if Result = 0 then
    Result := Sign(CompareStr(A, B));
end;

function ComparePrerelease(const A, B: string): Integer;
var
  PartsA, PartsB: TArray<string>;
  Index: Integer;
begin
  // Ohne Vorabversion ist eine Version größer als mit.
  if (A = '') or (B = '') then
    Exit(Ord(A = '') - Ord(B = ''));
  PartsA := A.Split(['.']);
  PartsB := B.Split(['.']);
  for Index := 0 to Min(Length(PartsA), Length(PartsB)) - 1 do
  begin
    if IsNumber(PartsA[Index]) and IsNumber(PartsB[Index]) then
      Result := CompareNumbers(PartsA[Index], PartsB[Index])
    else if IsNumber(PartsA[Index]) then
      Result := -1
    else if IsNumber(PartsB[Index]) then
      Result := 1
    else
      Result := Sign(CompareStr(PartsA[Index], PartsB[Index]));
    if Result <> 0 then
      Exit;
  end;
  Result := Sign(Length(PartsA) - Length(PartsB));
end;

/// <summary>Kern (drei Zahlen) und Vorabversion ohne „-“; False, wenn AVersion keine SemVer-Version ist.</summary>
function SplitVersion(const AVersion: string; out ACore: TArray<string>; out APrerelease: string): Boolean;
var
  Rest: string;
  Position: Integer;
begin
  Result := TRegEx.IsMatch(AVersion, SemVerPattern);
  if not Result then
    Exit;
  Rest := AVersion;
  Position := Pos('+', Rest);
  if Position > 0 then
    Rest := Copy(Rest, 1, Position - 1);
  APrerelease := '';
  Position := Pos('-', Rest);
  if Position > 0 then
  begin
    APrerelease := Copy(Rest, Position + 1, MaxInt);
    Rest := Copy(Rest, 1, Position - 1);
  end;
  ACore := Rest.Split(['.']);
end;

class function TAtlasUpdates.Compare(const A, B: string): Integer;
var
  CoreA, CoreB: TArray<string>;
  PreA, PreB: string;
  ValidA, ValidB: Boolean;
  Index: Integer;
begin
  ValidA := SplitVersion(A, CoreA, PreA);
  ValidB := SplitVersion(B, CoreB, PreB);
  if not ValidA or not ValidB then
    Exit(Ord(ValidA) - Ord(ValidB));
  for Index := 0 to 2 do
  begin
    Result := CompareNumbers(CoreA[Index], CoreB[Index]);
    if Result <> 0 then
      Exit;
  end;
  Result := ComparePrerelease(PreA, PreB);
end;

class function TAtlasUpdates.TryParse(const AJson: string; out ARelease: TAtlasRelease): Boolean;
var
  Value: TJSONValue;
begin
  ARelease := Default(TAtlasRelease);
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    Result := (Value is TJSONObject) and TJSONObject(Value).TryGetValue<string>('version', ARelease.Version) and
      IsValidVersion(ARelease.Version);
    if not Result then
    begin
      ARelease := Default(TAtlasRelease);
      Exit;
    end;
    // Nur https-Adressen landen in der Meldungsansicht.
    if not TJSONObject(Value).TryGetValue<string>('changes', ARelease.ChangesUrl) or
      not ARelease.ChangesUrl.StartsWith('https://', True) or (ARelease.ChangesUrl.IndexOfAny([' ', #9, #10, #13]) >= 0)
    then
      ARelease.ChangesUrl := ReleasesUrl + '/tag/v' + ARelease.Version;
  finally
    Value.Free;
  end;
end;

class function TAtlasUpdates.IsDue(ALastCheck, ANow: TDateTime): Boolean;
begin
  Result := (ALastCheck <= 0) or (ANow - ALastCheck >= 1) or (ALastCheck > ANow);
end;

class function TAtlasUpdates.RequestUrl(const ABase, AAtlasVersion, AIdeVersion: string): string;
begin
  Result := ABase + '?atlas=' + TNetEncoding.URL.Encode(AAtlasVersion) + '&ide=' +
    TNetEncoding.URL.Encode(AIdeVersion);
end;

class function TAtlasUpdates.Run(const ASource: IAtlasVersionSource; var AState: TAtlasUpdateState;
  AEnabled: Boolean; const AInstalled, AIdeVersion: string; ANow: TDateTime): TAtlasUpdateResult;
var
  Text: string;
begin
  Result := Default(TAtlasUpdateResult);
  if not AEnabled then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Disabled;
    Exit;
  end;
  if not IsDue(AState.LastCheck, ANow) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.NotDue;
    Exit;
  end;
  // Auch ein Fehlschlag zählt: höchstens eine Abfrage am Tag.
  AState.LastCheck := ANow;
  if not ASource.Fetch(RequestUrl(VersionUrl, AInstalled, AIdeVersion), TimeoutMs, Text, Result.Error) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Failed;
    Exit;
  end;
  if not TryParse(Text, Result.Release) then
  begin
    Result.Outcome := TAtlasUpdateOutcome.Failed;
    Result.Error := 'Versionsdatei ungültig';
    Exit;
  end;
  if Compare(Result.Release.Version, AInstalled) > 0 then
    Result.Outcome := TAtlasUpdateOutcome.NewVersion
  else
    Result.Outcome := TAtlasUpdateOutcome.Current;
end;

class function TAtlasUpdates.IdeVersion: string;
begin
  Result := FormatFloat('0.0', CompilerVersion, TFormatSettings.Invariant);
end;

class function TAtlasUpdates.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'updates.json');
end;

end.
