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
  begin
    Exit;
  end;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
  begin
    Delete(Result, Length(Result), 1);
  end;
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
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mFolder) then
      begin
        mSeen := True;
        Break;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mFolder];
    end;
  end;
end;

class function TAtlasFolderList.Text(const AText: string): string;
begin
  Result := string.Join(';', Parse(AText));
end;

end.
