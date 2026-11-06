unit Atlas.Common.Updates.Archive;

// Platform-Feature "Updates" (#1519), Root: ZIP sicher entpacken.
// - Ein Eintrag darf den Zielordner nicht verlassen: keine absoluten Pfade,
//   kein Laufwerk, kein „..“ als Teil, keine Steuerzeichen. Ein Archiv mit
//   einem solchen Eintrag wird ganz abgelehnt (Fehler archive), bevor eine
//   Datei geschrieben ist.
// - Ordnereinträge (Name endet auf / oder \) werden übergangen.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateArchives = class
  public
    class function IsSafeEntry(const AEntry: string): Boolean; static;
    class function IsDirectoryEntry(const AEntry: string): Boolean; static;
    /// <summary>Eintrag als Windows-Pfad relativ zum Zielordner.</summary>
    class function RelativePath(const AEntry: string): string; static;
    /// <summary>Alle Dateien nach ATargetDir; EUpdateError (archive) bei unsicherem oder leerem Archiv.</summary>
    class procedure ExtractAll(const AArchive: IUpdateArchive; const AZipFile, ATargetDir: string); static;
  end;

implementation

uses
  Atlas.Text.UpdateRun,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TArchiveText = (Empty);

const
  cTexts: array[TArchiveText] of TAtlasText = (
    (De: 'leer'; En: 'empty'));

{$SCOPEDENUMS OFF}

{ TUpdateArchives }

class function TUpdateArchives.IsDirectoryEntry(const AEntry: string): Boolean;
begin
  Result := AEntry.EndsWith('/') or AEntry.EndsWith('\');
end;

class function TUpdateArchives.RelativePath(const AEntry: string): string;
begin
  Result := AEntry.Replace('/', '\');
end;

function HasControlChar(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := False;
  for mChar in AText do
  begin
    if (mChar < ' ') or (mChar = ':') then
    begin
      Result := True;
    end;
  end;
end;

class function TUpdateArchives.IsSafeEntry(const AEntry: string): Boolean;
var
  mPath, mPart: string;
begin
  mPath := RelativePath(AEntry);
  if (mPath = '') or mPath.StartsWith('\') or HasControlChar(mPath) then
  begin
    Exit(False);
  end;
  for mPart in mPath.Split(['\']) do
  begin
    if mPart = '..' then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class procedure TUpdateArchives.ExtractAll(const AArchive: IUpdateArchive; const AZipFile, ATargetDir: string);
var
  mEntries: TArray<string>;
  mEntry: string;
begin
  mEntries := AArchive.Entries(AZipFile);
  if Length(mEntries) = 0 then
  begin
    raise EUpdateError.CreateCode(TUpdateErrors.Archive, cTexts[TArchiveText.Empty].Text);
  end;
  for mEntry in mEntries do
  begin
    if not IsSafeEntry(mEntry) then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.Archive, mEntry);
    end;
  end;
  for mEntry in mEntries do
  begin
    if not IsDirectoryEntry(mEntry) then
    begin
      AArchive.Extract(AZipFile, mEntry, TUpdateLayout.Join(ATargetDir, RelativePath(mEntry)));
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Updates.Archive', cTexts);

end.
