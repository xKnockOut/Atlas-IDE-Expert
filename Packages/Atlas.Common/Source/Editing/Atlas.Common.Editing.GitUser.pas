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
  MaxLevels = 32;

function StripComment(const ALine: string): string;
var
  Index: Integer;
  Quoted: Boolean;
begin
  Quoted := False;
  for Index := 1 to Length(ALine) do
    if ALine[Index] = '"' then
      Quoted := not Quoted
    else if not Quoted and CharInSet(ALine[Index], [';', '#']) then
      Exit(Copy(ALine, 1, Index - 1));
  Result := ALine;
end;

function Unquote(const AValue: string): string;
begin
  Result := AValue;
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

class function TGitUser.NameIn(const AConfig: string): string;
var
  Line, Key: string;
  InUser: Boolean;
  Equal: Integer;
begin
  Result := '';
  InUser := False;
  for Line in AConfig.Replace(#13, '').Split([#10]) do
  begin
    Key := Trim(StripComment(Line));
    if Key = '' then
      Continue;
    if Key[1] = '[' then
    begin
      InUser := SameText(Key, '[user]');
      Continue;
    end;
    Equal := Pos('=', Key);
    if InUser and (Equal > 0) and SameText(Trim(Copy(Key, 1, Equal - 1)), 'name') then
      Result := Unquote(Trim(Copy(Key, Equal + 1, MaxInt)));
  end;
end;

/// <summary>Trenner, den APath schon benutzt; sonst der des Systems.</summary>
function SeparatorOf(const APath: string): string;
begin
  if Pos('\', APath) > 0 then
    Result := '\'
  else if Pos('/', APath) > 0 then
    Result := '/'
  else
    Result := PathDelim;
end;

function Join(const AFolder, AName: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not CharInSet(Result[Length(Result)], ['/', '\']) then
    Result := Result + SeparatorOf(AFolder);
  Result := Result + AName;
end;

/// <summary>Übergeordneter Ordner; '' am Wurzelordner.</summary>
function ParentOf(const AFolder: string): string;
var
  Folder: string;
  Index: Integer;
begin
  Folder := AFolder;
  while (Length(Folder) > 1) and CharInSet(Folder[Length(Folder)], ['/', '\']) do
    Delete(Folder, Length(Folder), 1);
  Result := '';
  for Index := Length(Folder) downto 1 do
    if CharInSet(Folder[Index], ['/', '\']) then
    begin
      Result := Copy(Folder, 1, Index - 1);
      // "C:" bzw. "/" bleiben als Wurzel stehen.
      if (Result = '') or ((Length(Result) = 2) and (Result[2] = ':')) then
        Result := Copy(Folder, 1, Index);
      Break;
    end;
  if Result = AFolder then
    Result := '';
end;

class function TGitUser.NameFor(const AFolder, AHome: string; const AReadFile: TGitReadFile): string;
var
  Folder, Text: string;
  Level: Integer;
begin
  Result := '';
  Folder := AFolder;
  Level := 0;
  while (Folder <> '') and (Level < MaxLevels) do
  begin
    if AReadFile(Join(Join(Folder, '.git'), 'config'), Text) then
    begin
      Result := NameIn(Text);
      if Result <> '' then
        Exit;
      // Das Repository gefunden, aber ohne Namen: dann gilt die globale Angabe.
      Break;
    end;
    Folder := ParentOf(Folder);
    Inc(Level);
  end;
  if (AHome <> '') and AReadFile(Join(AHome, '.gitconfig'), Text) then
    Result := NameIn(Text);
end;

class function TGitUser.HomeFolder: string;
begin
  Result := GetEnvironmentVariable('USERPROFILE');
  if Result = '' then
    Result := GetEnvironmentVariable('HOME');
end;

end.
