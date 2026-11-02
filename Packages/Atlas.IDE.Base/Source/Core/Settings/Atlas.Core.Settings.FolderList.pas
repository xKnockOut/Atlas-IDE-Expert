unit Atlas.Core.Settings.FolderList;

// Ordnerliste als Wert einer Einstellung (#1455), etwa debug.ownCode.folders:
// Ordner durch „;“ oder Zeilenumbruch getrennt, ohne Leerraum, mit „\“, ohne
// Trenner am Ende, jeder einmal (Groß-/Kleinschreibung egal, der erste
// gewinnt). Der Optionsdialog (Base) bereinigt den Text beim Speichern, die
// Module lesen die Liste mit Parse; keiner muss den anderen kennen.

interface

type
  TAtlasFolderList = class
  public
    /// <summary>Ein Ordner bereinigt; '' für leeren Text.</summary>
    class function Normal(const AFolder: string): string; static;
    /// <summary>Ordner aus AText in der Reihenfolge des Texts, bereinigt, jeder einmal.</summary>
    class function Parse(const AText: string): TArray<string>; static;
    /// <summary>Bereinigter Text der Liste, mit „;“ getrennt.</summary>
    class function Text(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasFolderList.Normal(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  if Result = '' then
    Exit;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

class function TAtlasFolderList.Parse(const AText: string): TArray<string>;
var
  mPart, mFolder, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in StringReplace(StringReplace(AText, #13, ';', [rfReplaceAll]), #10, ';',
    [rfReplaceAll]).Split([';']) do
  begin
    mFolder := Normal(mPart);
    if mFolder = '' then
      Continue;
    mSeen := False;
    for mKnown in Result do
      if SameText(mKnown, mFolder) then
      begin
        mSeen := True;
        Break;
      end;
    if not mSeen then
      Result := Result + [mFolder];
  end;
end;

class function TAtlasFolderList.Text(const AText: string): string;
begin
  Result := string.Join(';', Parse(AText));
end;

end.
