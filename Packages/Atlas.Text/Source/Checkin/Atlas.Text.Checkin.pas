unit Atlas.Text.Checkin;

// Was in eine eingecheckte Einstellungsdatei darf, gemeinsam für Server und
// Plugin (#486): atlas.json und die Projektdatei .atlas liegen im
// Repository und gelten für alle im Team. Zugangsdaten (Passwort, Token,
// Benutzer …) und absolute Pfade gehören nicht hinein; Server und Plugin
// ignorieren solche Einträge beim Lesen und melden sie. Für .atlas gilt
// zusätzlich: kein relativer Pfad, der aus dem Projekt herausführt.
// Pfade wie unter Windows: „\“ und „/“ trennen, Groß-/Kleinschreibung egal.

interface

type
  TTextCheckin = class
  public
    /// <summary>Schlüssel, unter dem Zugangsdaten stehen (password, token, apiKey, secret, user, login …); ohne
    /// Rücksicht auf Groß-/Kleinschreibung, „-“, „_“, „.“ und Leerzeichen. Nur der ganze Name zählt:
    /// "tokenCount" oder die Regel "hardcoded-password" sind keine Zugangsdaten.</summary>
    class function IsCredentialKey(const AKey: string): Boolean; static;
    /// <summary>Name einer Umgebungsvariablen oder eines Parameters, der ein Geheimnis trägt: wie IsCredentialKey
    /// oder endet auf password, passwort, pwd, token, secret, apikey oder credentials (DB_PASSWORD, GITHUB_TOKEN).
    /// </summary>
    class function IsCredentialName(const AName: string): Boolean; static;
    /// <summary>Adresse mit Zugangsdaten: Benutzer oder Passwort vor „@“ (https://user:pw@host/…) oder ein
    /// Abfrageparameter wie ?token=… bzw. &amp;api_key=… (Namen wie bei IsCredentialKey).</summary>
    class function HasUrlCredentials(const AValue: string): Boolean; static;
    /// <summary>Laufwerk („C:\“, „C:/“, „C:“) oder UNC-Pfad („\\server“, „//server“): ein Ort auf genau einem
    /// Rechner. Glob-Muster wie "/Generated/**" zählen nicht.</summary>
    class function IsMachinePath(const APath: string): Boolean; static;
    /// <summary>Wie IsMachinePath, dazu ein Pfad ab der Wurzel des Laufwerks („\Daten“, „/Daten“) und „~“ für
    /// den Benutzerordner.</summary>
    class function IsAbsolutePath(const APath: string): Boolean; static;
    /// <summary>Enthält AText ein Wort, das ein Pfad auf einem bestimmten Rechner ist (IsMachinePath)? Wörter
    /// trennen Leerraum, Anführungszeichen, „=“, „;“ und „,“; für Startparameter und Umgebungsvariablen.</summary>
    class function ContainsMachinePath(const AText: string): Boolean; static;
    /// <summary>Bleibt ARelative, an den Ordner ABase gehängt, innerhalb von ARoot? Beachtet „.“ und „..“;
    /// False für absolute Pfade (IsAbsolutePath) und wenn ABase nicht in ARoot liegt. '' bleibt in ABase.</summary>
    class function StaysInside(const ARoot, ABase, ARelative: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  /// <summary>Normierte Namen (klein, ohne Trenner) von Schlüsseln mit Zugangsdaten.</summary>
  cCredentialKeys: array[0..30] of string = ('password', 'passwort', 'passwd', 'pwd', 'pass', 'kennwort',
    'token', 'apitoken', 'accesstoken', 'authtoken', 'bearertoken', 'privatetoken', 'personalaccesstoken',
    'refreshtoken', 'idtoken', 'apikey', 'secret', 'clientsecret', 'secretkey', 'privatekey', 'credential',
    'credentials', 'zugangsdaten', 'user', 'username', 'benutzer', 'benutzername', 'login', 'auth',
    'authorization', 'cookie');
  /// <summary>Endungen normierter Namen, die ein Geheimnis tragen.</summary>
  cCredentialEndings: array[0..7] of string = ('password', 'passwort', 'pwd', 'token', 'secret', 'apikey',
    'credentials', 'credential');

function Normalized(const AName: string): string;
var
  mCh: Char;
begin
  Result := '';
  for mCh in AName do
  begin
    if (mCh <> '-') and (mCh <> '_') and (mCh <> '.') and (mCh <> ' ') then
    begin
      Result := Result + mCh;
    end;
  end;
  Result := LowerCase(Result);
end;

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

function IsLetter(ACh: Char): Boolean;
begin
  Result := ((ACh >= 'A') and (ACh <= 'Z')) or ((ACh >= 'a') and (ACh <= 'z'));
end;

/// <summary>Teile eines Pfads ohne leere Teile und ohne „.“, klein geschrieben.</summary>
function Segments(const APath: string): TArray<string>;
var
  mStart, mIndex: Integer;
  mPart: string;
begin
  Result := nil;
  mStart := 1;
  for mIndex := 1 to Length(APath) + 1 do
  begin
    if (mIndex > Length(APath)) or IsSeparator(APath[mIndex]) then
    begin
      mPart := Trim(Copy(APath, mStart, mIndex - mStart));
      if (mPart <> '') and (mPart <> '.') then
      begin
        Result := Result + [LowerCase(mPart)];
      end;
      mStart := mIndex + 1;
    end;
  end;
end;

{ TTextCheckin }

class function TTextCheckin.IsCredentialKey(const AKey: string): Boolean;
var
  mName, mItem: string;
begin
  mName := Normalized(AKey);
  for mItem in cCredentialKeys do
  begin
    if mName = mItem then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TTextCheckin.IsCredentialName(const AName: string): Boolean;
var
  mName, mItem: string;
begin
  if IsCredentialKey(AName) then
  begin
    Exit(True);
  end;
  mName := Normalized(AName);
  for mItem in cCredentialEndings do
  begin
    if (Length(mName) > Length(mItem)) and (Copy(mName, Length(mName) - Length(mItem) + 1, Length(mItem)) = mItem) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

// Benutzer oder Kennwort im Authority-Teil (https://user:pass@host)?
function HasAuthorityCredentials(const AValue: string): Boolean;
var
  mScheme, mStop, mIndex: Integer;
begin
  mScheme := Pos('://', AValue);
  if mScheme = 0 then
  begin
    Exit(False);
  end;
  mStop := Length(AValue) + 1;
  for mIndex := mScheme + 3 to Length(AValue) do
  begin
    if CharInSet(AValue[mIndex], ['/', '?', '#']) then
    begin
      mStop := mIndex;
      Break;
    end;
  end;
  Result := Pos('@', Copy(AValue, mScheme + 3, mStop - mScheme - 3)) > 0;
end;

// Abfrageteil ohne ? und ohne Fragment; '' ohne Abfrage.
function QueryOf(const AValue: string): string;
var
  mIndex: Integer;
begin
  mIndex := Pos('?', AValue);
  if mIndex = 0 then
  begin
    Exit('');
  end;
  Result := Copy(AValue, mIndex + 1, MaxInt);
  mIndex := Pos('#', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, 1, mIndex - 1);
  end;
end;

// Name eines Abfrageparameters ("token" aus "token=abc").
function ParameterName(const APair: string): string;
var
  mEquals: Integer;
begin
  Result := APair;
  mEquals := Pos('=', Result);
  if mEquals > 0 then
  begin
    Result := Copy(Result, 1, mEquals - 1);
  end;
end;

class function TTextCheckin.HasUrlCredentials(const AValue: string): Boolean;
var
  mQuery: string;
  mIndex, mStart: Integer;
begin
  if HasAuthorityCredentials(AValue) then
  begin
    Exit(True);
  end;
  mQuery := QueryOf(AValue);
  mStart := 1;
  for mIndex := 1 to Length(mQuery) + 1 do
  begin
    if (mIndex > Length(mQuery)) or CharInSet(mQuery[mIndex], ['&', ';']) then
    begin
      if IsCredentialKey(ParameterName(Copy(mQuery, mStart, mIndex - mStart))) then
      begin
        Exit(True);
      end;
      mStart := mIndex + 1;
    end;
  end;
  Result := False;
end;

class function TTextCheckin.IsMachinePath(const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := Trim(APath);
  if (Length(mPath) >= 2) and IsLetter(mPath[1]) and (mPath[2] = ':') then
  begin
    Exit(True);
  end;
  Result := (Length(mPath) >= 3) and IsSeparator(mPath[1]) and IsSeparator(mPath[2]) and not IsSeparator(mPath[3]) and
    (mPath[3] <> '*');
end;

class function TTextCheckin.IsAbsolutePath(const APath: string): Boolean;
var
  mPath: string;
begin
  if IsMachinePath(APath) then
  begin
    Exit(True);
  end;
  mPath := Trim(APath);
  Result := (mPath <> '') and (IsSeparator(mPath[1]) or (mPath[1] = '~'));
end;

class function TTextCheckin.ContainsMachinePath(const AText: string): Boolean;
var
  mStart, mIndex: Integer;
  mWord: string;
begin
  mStart := 1;
  for mIndex := 1 to Length(AText) + 1 do
  begin
    if (mIndex > Length(AText)) or CharInSet(AText[mIndex], [' ', #9, #10, #13, '"', '''', '=', ';', ',']) then
    begin
      mWord := Copy(AText, mStart, mIndex - mStart);
      if (mWord <> '') and IsMachinePath(mWord) then
      begin
        Exit(True);
      end;
      mStart := mIndex + 1;
    end;
  end;
  Result := False;
end;

class function TTextCheckin.StaysInside(const ARoot, ABase, ARelative: string): Boolean;
var
  mRoot, mBase, mRelative: TArray<string>;
  mIndex, mDepth: Integer;
begin
  if IsAbsolutePath(ARelative) then
  begin
    Exit(False);
  end;
  mRoot := Segments(ARoot);
  mBase := Segments(ABase);
  if Length(mBase) < Length(mRoot) then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(mRoot) do
  begin
    if mRoot[mIndex] <> mBase[mIndex] then
    begin
      Exit(False);
    end;
  end;
  mDepth := Length(mBase) - Length(mRoot);
  mRelative := Segments(ARelative);
  for mIndex := 0 to High(mRelative) do
  begin
    if mRelative[mIndex] = '..' then
    begin
      Dec(mDepth);
      if mDepth < 0 then
      begin
        Exit(False);
      end;
    end
    else
    begin
      Inc(mDepth);
    end;
  end;
  Result := True;
end;

end.
