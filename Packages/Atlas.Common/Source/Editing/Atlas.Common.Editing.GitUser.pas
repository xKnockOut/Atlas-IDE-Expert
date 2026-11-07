unit Atlas.Common.Editing.GitUser;

// Name aus git config user.name für /todo -o (#297): sucht vom Ordner der
// Datei aufwärts nach .git/config, danach die .gitconfig im Benutzerordner.
// Gelesen wird über eine Funktion, damit der Editorpuffer bzw. Testdaten
// zählen; git selbst wird nicht gestartet.

interface

type
  /// <summary>Liest AFileName; False, wenn es die Datei nicht gibt.</summary>
  TGitReadFile = reference to function(const AFileName: string; out AText: string): Boolean;

  TGitUser = class
  public
    /// <summary>Wert von name im Abschnitt [user] einer git-Konfiguration; '' ohne.</summary>
    class function NameIn(const AConfig: string): string; static;
    /// <summary>user.name für AFolder: erst .git/config in AFolder und darüber (höchstens 32 Ebenen), dann
    /// .gitconfig in AHome ('' = überspringen); '' ohne.</summary>
    class function NameFor(const AFolder, AHome: string; const AReadFile: TGitReadFile): string; static;
    /// <summary>Benutzerordner aus USERPROFILE bzw. HOME; '' ohne.</summary>
    class function HomeFolder: string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cMaxLevels = 32;

function StripComment(const ALine: string): string;
var
  mIndex: Integer;
  mQuoted: Boolean;
begin
  mQuoted := False;
  for mIndex := 1 to Length(ALine) do
  begin
    if ALine[mIndex] = '"' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and CharInSet(ALine[mIndex], [';', '#']) then
    begin
      Exit(Copy(ALine, 1, mIndex - 1));
    end;
  end;
  Result := ALine;
end;

function Unquote(const AValue: string): string;
begin
  Result := AValue;
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

class function TGitUser.NameIn(const AConfig: string): string;
var
  mLine, mKey: string;
  mInUser: Boolean;
  mEqual: Integer;
begin
  Result := '';
  mInUser := False;
  for mLine in AConfig.Replace(#13, '').Split([#10]) do
  begin
    mKey := Trim(StripComment(mLine));
    if mKey = '' then
    begin
      Continue;
    end;
    if mKey[1] = '[' then
    begin
      mInUser := SameText(mKey, '[user]');
      Continue;
    end;
    mEqual := Pos('=', mKey);
    if mInUser and (mEqual > 0) and SameText(Trim(Copy(mKey, 1, mEqual - 1)), 'name') then
    begin
      Result := Unquote(Trim(Copy(mKey, mEqual + 1, MaxInt)));
    end;
  end;
end;

/// <summary>Trenner, den APath schon benutzt; sonst der des Systems.</summary>
function SeparatorOf(const APath: string): string;
begin
  if Pos('\', APath) > 0 then
  begin
    Result := '\';
  end
  else if Pos('/', APath) > 0 then
  begin
    Result := '/';
  end
  else
  begin
    Result := PathDelim;
  end;
end;

function Join(const AFolder, AName: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not CharInSet(Result[Length(Result)], ['/', '\']) then
  begin
    Result := Result + SeparatorOf(AFolder);
  end;
  Result := Result + AName;
end;

/// <summary>Übergeordneter Ordner; '' am Wurzelordner.</summary>
function ParentOf(const AFolder: string): string;
var
  mFolder: string;
  mIndex: Integer;
begin
  mFolder := AFolder;
  while (Length(mFolder) > 1) and CharInSet(mFolder[Length(mFolder)], ['/', '\']) do
  begin
    Delete(mFolder, Length(mFolder), 1);
  end;
  Result := '';
  for mIndex := Length(mFolder) downto 1 do
  begin
    if CharInSet(mFolder[mIndex], ['/', '\']) then
    begin
      Result := Copy(mFolder, 1, mIndex - 1);
      // "C:" bzw. "/" bleiben als Wurzel stehen.
      if (Result = '') or ((Length(Result) = 2) and (Result[2] = ':')) then
      begin
        Result := Copy(mFolder, 1, mIndex);
      end;
      Break;
    end;
  end;
  if Result = AFolder then
  begin
    Result := '';
  end;
end;

class function TGitUser.NameFor(const AFolder, AHome: string; const AReadFile: TGitReadFile): string;
var
  mFolder, mText: string;
  mLevel: Integer;
begin
  Result := '';
  mFolder := AFolder;
  mLevel := 0;
  while (mFolder <> '') and (mLevel < cMaxLevels) do
  begin
    if AReadFile(Join(Join(mFolder, '.git'), 'config'), mText) then
    begin
      Result := NameIn(mText);
      if Result <> '' then
      begin
        Exit;
      end;
      // Das Repository gefunden, aber ohne Namen: dann gilt die globale Angabe.
      Break;
    end;
    mFolder := ParentOf(mFolder);
    Inc(mLevel);
  end;
  if (AHome <> '') and AReadFile(Join(AHome, '.gitconfig'), mText) then
  begin
    Result := NameIn(mText);
  end;
end;

class function TGitUser.HomeFolder: string;
begin
  Result := GetEnvironmentVariable('USERPROFILE');
  if Result = '' then
  begin
    Result := GetEnvironmentVariable('HOME');
  end;
end;

end.
